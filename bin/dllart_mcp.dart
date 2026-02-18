import 'dart:async';
import 'dart:convert';
import 'dart:io';

const List<String> _supportedCommands = <String>[
  'create',
  'new',
  'init',
  'build',
  'make',
  'package',
  'proto',
  'workflow',
  'integrate',
  'doctor',
  'check',
  'verify',
  'test',
  'build-all',
];

const Set<String> _jsonCapableCommands = <String>{
  'build',
  'doctor',
  'integrate',
  'proto',
  'verify',
  'test',
};

Future<void> main(List<String> args) async {
  final server = _DllartMcpServer();
  await server.run();
}

class _DllartMcpServer {
  _DllartMcpServer();

  final List<int> _buffer = <int>[];
  int? _expectedBodyBytes;
  _McpWireFormat _wireFormat = _McpWireFormat.unknown;
  bool _initialized = false;
  final String _startupCwd = Directory.current.path;
  _DllartInvocation? _cachedInvocation;

  Future<void> run() async {
    await for (final chunk in stdin) {
      _buffer.addAll(chunk);
      await _drainFrames();
    }
  }

  Future<void> _drainFrames() async {
    while (true) {
      if (_wireFormat == _McpWireFormat.unknown) {
        final detected = _detectWireFormat();
        if (detected == null) {
          return;
        }
        _wireFormat = detected;
      }

      if (_wireFormat == _McpWireFormat.contentLength) {
        final handled = await _drainContentLengthFrame();
        if (!handled) {
          return;
        }
        continue;
      }

      final handled = await _drainNdjsonFrame();
      if (!handled) {
        return;
      }
    }
  }

  Future<bool> _drainContentLengthFrame() async {
    if (_expectedBodyBytes == null) {
      final split = _indexOfHeaderTerminator(_buffer);
      if (split == null) {
        return false;
      }

      final headerBytes = _buffer.sublist(0, split.index);
      _buffer.removeRange(0, split.index + split.length);
      final headers = _parseHeaders(headerBytes);
      final lengthRaw = headers['content-length'];
      final length = int.tryParse(lengthRaw ?? '');
      if (length == null || length < 0) {
        await _sendRpcError(
          id: null,
          code: -32600,
          message: 'Missing or invalid Content-Length header',
        );
        return true;
      }
      _expectedBodyBytes = length;
    }

    final bodySize = _expectedBodyBytes!;
    if (_buffer.length < bodySize) {
      return false;
    }

    final bodyBytes = _buffer.sublist(0, bodySize);
    _buffer.removeRange(0, bodySize);
    _expectedBodyBytes = null;

    await _handleFrameBytes(bodyBytes);
    return true;
  }

  Future<bool> _drainNdjsonFrame() async {
    final newlineIndex = _indexOfByte(_buffer, 10);
    if (newlineIndex == null) {
      return false;
    }

    var lineBytes = _buffer.sublist(0, newlineIndex);
    _buffer.removeRange(0, newlineIndex + 1);
    if (lineBytes.isNotEmpty && lineBytes.last == 13) {
      lineBytes = lineBytes.sublist(0, lineBytes.length - 1);
    }
    if (lineBytes.every(_isAsciiWhitespace)) {
      return true;
    }

    await _handleFrameBytes(lineBytes);
    return true;
  }

  _McpWireFormat? _detectWireFormat() {
    var index = 0;
    while (index < _buffer.length && _isAsciiWhitespace(_buffer[index])) {
      index++;
    }
    if (index >= _buffer.length) {
      return null;
    }

    final first = _buffer[index];
    if (first == 123 || first == 91) {
      return _McpWireFormat.ndjson;
    }
    if (_isAsciiLetter(first)) {
      return _McpWireFormat.contentLength;
    }
    return null;
  }

  Future<void> _handleFrameBytes(List<int> bodyBytes) async {
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bodyBytes));
    } on FormatException catch (error) {
      await _sendRpcError(
        id: null,
        code: -32700,
        message: 'Parse error: ${error.message}',
      );
      return;
    }

    if (decoded is! Map<String, dynamic>) {
      await _sendRpcError(
        id: null,
        code: -32600,
        message: 'Invalid Request: expected JSON object',
      );
      return;
    }

    final message = decoded;
    final method = message['method'];
    final id = message['id'];
    final params = message['params'];
    final isNotification = !message.containsKey('id');

    if (method is! String) {
      await _sendRpcError(
        id: id,
        code: -32600,
        message: 'Invalid Request: missing method',
      );
      return;
    }

    if (!_initialized &&
        method != 'initialize' &&
        method != 'notifications/initialized') {
      if (!isNotification) {
        await _sendRpcError(
          id: id,
          code: -32002,
          message: 'Server not initialized',
        );
      }
      return;
    }

    switch (method) {
      case 'initialize':
        await _handleInitialize(id: id, params: params);
        return;
      case 'notifications/initialized':
        _initialized = true;
        return;
      case 'ping':
        if (!isNotification) {
          await _sendRpcResult(id, <String, Object?>{});
        }
        return;
      case 'tools/list':
        if (!isNotification) {
          await _sendRpcResult(id, _toolsListResponse());
        }
        return;
      case 'tools/call':
        if (!isNotification) {
          await _handleToolsCall(id: id, params: params);
        }
        return;
      default:
        if (!isNotification) {
          await _sendRpcError(
            id: id,
            code: -32601,
            message: 'Method not found',
          );
        }
        return;
    }
  }

  Future<void> _handleInitialize({required Object? id, Object? params}) async {
    var negotiatedVersion = '2025-03-26';
    if (params is Map<String, dynamic>) {
      final clientVersion = params['protocolVersion'];
      if (clientVersion is String && clientVersion.trim().isNotEmpty) {
        negotiatedVersion = clientVersion.trim();
      }
    }

    await _sendRpcResult(id, <String, Object?>{
      'protocolVersion': negotiatedVersion,
      'capabilities': <String, Object?>{
        'tools': <String, Object?>{'listChanged': false},
      },
      'serverInfo': <String, Object?>{'name': 'dllart-mcp', 'version': '0.1.0'},
      'instructions':
          'Use tools to run dllart commands. Prefer `dllart.run` with '
          '`command=doctor|build|integrate|proto|verify|test` to get JSON output.',
    });
    _initialized = true;
  }

  Map<String, Object?> _toolsListResponse() {
    return <String, Object?>{
      'tools': <Map<String, Object?>>[
        <String, Object?>{
          'name': 'dllart.run',
          'description':
              'Run a dllart CLI command in a target working directory. '
              'For build/doctor/integrate/proto/verify/test, JSON mode can be enabled.',
          'inputSchema': <String, Object?>{
            'type': 'object',
            'additionalProperties': false,
            'properties': <String, Object?>{
              'command': <String, Object?>{
                'type': 'string',
                'enum': _supportedCommands,
                'description': 'dllart command name',
              },
              'cwd': <String, Object?>{
                'type': 'string',
                'description':
                    'Working directory where command will run (optional)',
              },
              'config': <String, Object?>{'type': 'string'},
              'path': <String, Object?>{'type': 'string'},
              'dependency': <String, Object?>{'type': 'string'},
              'dllart_path': <String, Object?>{'type': 'string'},
              'local_path_dependency': <String, Object?>{'type': 'boolean'},
              'name': <String, Object?>{'type': 'string'},
              'source': <String, Object?>{'type': 'string'},
              'output': <String, Object?>{'type': 'string'},
              'target': <String, Object?>{'type': 'string'},
              'package_target': <String, Object?>{'type': 'string'},
              'runtime_profile': <String, Object?>{'type': 'string'},
              'android_abis': <String, Object?>{'type': 'string'},
              'ios_variants': <String, Object?>{'type': 'string'},
              'force': <String, Object?>{'type': 'boolean'},
              'auto_build': <String, Object?>{'type': 'boolean'},
              'skip_build': <String, Object?>{'type': 'boolean'},
              'perf_gate': <String, Object?>{'type': 'boolean'},
              'fix': <String, Object?>{'type': 'boolean'},
              'proto': <String, Object?>{'type': 'string'},
              'out': <String, Object?>{'type': 'string'},
              'include': <String, Object?>{
                'type': 'array',
                'items': <String, Object?>{'type': 'string'},
              },
              'grpc': <String, Object?>{'type': 'boolean'},
              'protoc': <String, Object?>{'type': 'string'},
              'global_tool': <String, Object?>{'type': 'boolean'},
              'local_tool': <String, Object?>{'type': 'boolean'},
              'json': <String, Object?>{
                'type': 'boolean',
                'description':
                    'Enable --json output when command supports it '
                    '(build/doctor/integrate/proto/verify/test).',
              },
              'verbose': <String, Object?>{'type': 'boolean'},
            },
            'required': <String>['command'],
          },
        },
        <String, Object?>{
          'name': 'dllart.help',
          'description': 'Show general or command-specific help text.',
          'inputSchema': <String, Object?>{
            'type': 'object',
            'additionalProperties': false,
            'properties': <String, Object?>{
              'command': <String, Object?>{
                'type': 'string',
                'description': 'Optional command name',
              },
            },
          },
        },
      ],
    };
  }

  Future<void> _handleToolsCall({
    required Object? id,
    required Object? params,
  }) async {
    if (params is! Map<String, dynamic>) {
      await _sendRpcError(
        id: id,
        code: -32602,
        message: 'Invalid params: expected object',
      );
      return;
    }

    final name = params['name'];
    final arguments = params['arguments'];
    final argsMap = arguments is Map<String, dynamic>
        ? arguments
        : <String, dynamic>{};

    if (name is! String || name.trim().isEmpty) {
      await _sendRpcError(
        id: id,
        code: -32602,
        message: 'Invalid params: missing tool name',
      );
      return;
    }

    switch (name) {
      case 'dllart.run':
        await _runDllartTool(id: id, arguments: argsMap);
        return;
      case 'dllart.help':
        await _helpTool(id: id, arguments: argsMap);
        return;
      default:
        await _sendRpcError(
          id: id,
          code: -32601,
          message: 'Tool not found: $name',
        );
        return;
    }
  }

  Future<void> _runDllartTool({
    required Object? id,
    required Map<String, dynamic> arguments,
  }) async {
    final commandRaw = arguments['command'];
    if (commandRaw is! String || commandRaw.trim().isEmpty) {
      await _sendToolResult(
        id,
        isError: true,
        payload: <String, Object?>{'error': 'Argument "command" is required.'},
      );
      return;
    }

    final command = commandRaw.trim();
    if (!_supportedCommands.contains(command)) {
      await _sendToolResult(
        id,
        isError: true,
        payload: <String, Object?>{
          'error': 'Unsupported command: $command',
          'supported_commands': _supportedCommands,
        },
      );
      return;
    }

    final jsonFlag = arguments['json'];
    bool jsonMode;
    if (jsonFlag == null) {
      jsonMode = _jsonCapableCommands.contains(command);
    } else if (jsonFlag is bool) {
      jsonMode = jsonFlag;
    } else {
      await _sendToolResult(
        id,
        isError: true,
        payload: <String, Object?>{
          'error': 'Argument "json" must be boolean when provided.',
        },
      );
      return;
    }

    if (jsonMode && !_jsonCapableCommands.contains(command)) {
      await _sendToolResult(
        id,
        isError: true,
        payload: <String, Object?>{
          'error':
              'Command "$command" does not support --json. Supported: '
              '${_jsonCapableCommands.toList()..sort()}',
        },
      );
      return;
    }

    final cwdRaw = arguments['cwd'];
    final cwd = cwdRaw is String && cwdRaw.trim().isNotEmpty
        ? cwdRaw.trim()
        : Directory.current.path;

    final cliArgs = <String>[command];

    void addStringOption(String name, String key) {
      final value = arguments[key];
      if (value is String && value.trim().isNotEmpty) {
        cliArgs.add('--$name=${value.trim()}');
      }
    }

    void addBoolFlag(String name, String key) {
      final value = arguments[key];
      if (value == true) {
        cliArgs.add('--$name');
      }
    }

    addStringOption('config', 'config');
    addStringOption('path', 'path');
    addStringOption('dependency', 'dependency');
    addStringOption('dllart-path', 'dllart_path');
    addStringOption('name', 'name');
    addStringOption('source', 'source');
    addStringOption('output', 'output');
    addStringOption('target', 'target');
    addStringOption('package-target', 'package_target');
    addStringOption('runtime-profile', 'runtime_profile');
    addStringOption('android-abis', 'android_abis');
    addStringOption('ios-variants', 'ios_variants');
    addStringOption('proto', 'proto');
    addStringOption('out', 'out');
    addStringOption('protoc', 'protoc');
    addBoolFlag('local-path-dependency', 'local_path_dependency');
    addBoolFlag('force', 'force');
    addBoolFlag('auto-build', 'auto_build');
    addBoolFlag('skip-build', 'skip_build');
    addBoolFlag('perf-gate', 'perf_gate');
    addBoolFlag('fix', 'fix');
    addBoolFlag('grpc', 'grpc');
    addBoolFlag('global-tool', 'global_tool');
    addBoolFlag('local-tool', 'local_tool');
    addBoolFlag('verbose', 'verbose');

    final include = arguments['include'];
    if (include is List) {
      final values = include
          .whereType<String>()
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty);
      final rendered = values.join(',');
      if (rendered.isNotEmpty) {
        cliArgs.add('--include=$rendered');
      }
    }

    if (jsonMode) {
      cliArgs.add('--json');
    }

    final invocation = await _resolveDllartInvocation();
    final processResult = await Process.run(
      invocation.executable,
      <String>[...invocation.baseArgs, ...cliArgs],
      workingDirectory: cwd,
      runInShell: false,
    );

    final stdoutText = _asText(processResult.stdout);
    final stderrText = _asText(processResult.stderr);
    Object? parsedJson;

    if (jsonMode) {
      try {
        parsedJson = jsonDecode(stdoutText);
      } catch (_) {
        parsedJson = null;
      }
    }

    final payload = <String, Object?>{
      'command': command,
      'cwd': cwd,
      'json_mode': jsonMode,
      'launcher': <String, Object?>{
        'executable': invocation.executable,
        'base_args': invocation.baseArgs,
      },
      'argv': cliArgs,
      'exit_code': processResult.exitCode,
      'stdout': stdoutText,
      'stderr': stderrText,
      if (parsedJson != null) 'json': parsedJson,
    };

    await _sendToolResult(
      id,
      isError: processResult.exitCode != 0,
      payload: payload,
    );
  }

  Future<void> _helpTool({
    required Object? id,
    required Map<String, dynamic> arguments,
  }) async {
    final command = arguments['command'];
    final invocation = await _resolveDllartInvocation();
    final args = <String>[
      ...invocation.baseArgs,
      if (command is String && command.trim().isNotEmpty) ...<String>[
        'help',
        command.trim(),
      ] else
        '--help',
    ];

    final processResult = await Process.run(
      invocation.executable,
      args,
      runInShell: false,
    );

    final payload = <String, Object?>{
      'exit_code': processResult.exitCode,
      'stdout': _asText(processResult.stdout),
      'stderr': _asText(processResult.stderr),
    };

    await _sendToolResult(
      id,
      isError: processResult.exitCode != 0,
      payload: payload,
    );
  }

  Future<_DllartInvocation> _resolveDllartInvocation() async {
    if (_cachedInvocation != null) {
      return _cachedInvocation!;
    }

    final candidates = <_DllartInvocation>[];
    final dartExecutable = _findDartExecutable();
    final fromEnv = (Platform.environment['DLLART_MCP_DLLART_BIN'] ?? '')
        .trim();
    if (fromEnv.isNotEmpty) {
      candidates.add(_DllartInvocation(fromEnv, const <String>[]));
    }

    final localBinPath =
        '$_startupCwd${Platform.pathSeparator}bin'
        '${Platform.pathSeparator}dllart.dart';
    if (dartExecutable != null && File(localBinPath).existsSync()) {
      candidates.add(_DllartInvocation(dartExecutable, <String>[localBinPath]));
    }

    final cliName = Platform.isWindows ? 'dllart.bat' : 'dllart';
    final path = _findExecutableOnPath(cliName);
    if (path != null) {
      candidates.add(_DllartInvocation(path, const <String>[]));
    }

    if (dartExecutable != null) {
      candidates.add(
        _DllartInvocation(dartExecutable, const <String>[
          'pub',
          'global',
          'run',
          'dllart',
        ]),
      );
      candidates.add(
        _DllartInvocation(dartExecutable, const <String>['run', 'dllart']),
      );
    }

    if (candidates.isEmpty) {
      final fallback = _DllartInvocation(
        Platform.resolvedExecutable,
        const <String>[],
      );
      _cachedInvocation = fallback;
      return fallback;
    }

    for (final candidate in candidates) {
      if (await _isWorkingDllartInvocation(candidate)) {
        _cachedInvocation = candidate;
        return candidate;
      }
    }

    _cachedInvocation = candidates.first;
    return candidates.first;
  }

  String? _findDartExecutable() {
    final fromEnv = (Platform.environment['DART'] ?? '').trim();
    if (fromEnv.isNotEmpty && File(fromEnv).existsSync()) {
      return fromEnv;
    }

    final resolved = Platform.resolvedExecutable;
    final normalizedResolved = resolved.toLowerCase();
    if (_dartExecutableNames().any(
      (name) => normalizedResolved.endsWith('${Platform.pathSeparator}$name'),
    )) {
      return resolved;
    }

    for (final name in _dartExecutableNames()) {
      final onPath = _findExecutableOnPath(name);
      if (onPath != null) {
        return onPath;
      }
    }

    final dartSdk = (Platform.environment['DART_SDK'] ?? '').trim();
    if (dartSdk.isNotEmpty) {
      for (final name in _dartExecutableNames()) {
        final fromSdk =
            '$dartSdk${Platform.pathSeparator}bin${Platform.pathSeparator}$name';
        if (File(fromSdk).existsSync()) {
          return fromSdk;
        }
      }
    }

    final flutterRoot = (Platform.environment['FLUTTER_ROOT'] ?? '').trim();
    if (flutterRoot.isNotEmpty) {
      for (final name in _dartExecutableNames()) {
        final fromFlutter =
            '$flutterRoot${Platform.pathSeparator}bin'
            '${Platform.pathSeparator}$name';
        if (File(fromFlutter).existsSync()) {
          return fromFlutter;
        }
      }
    }

    return null;
  }

  List<String> _dartExecutableNames() {
    if (Platform.isWindows) {
      return const <String>['dart.exe', 'dart.bat', 'dart.cmd', 'dart'];
    }
    return const <String>['dart'];
  }

  Future<bool> _isWorkingDllartInvocation(_DllartInvocation candidate) async {
    try {
      final result = await Process.run(
        candidate.executable,
        <String>[...candidate.baseArgs, '--help'],
        workingDirectory: _startupCwd,
        runInShell: false,
      );
      if (result.exitCode != 0) {
        return false;
      }
      final out = _asText(result.stdout);
      return out.contains('DLLART') || out.contains('dart run dllart');
    } on ProcessException {
      return false;
    }
  }

  String? _findExecutableOnPath(String name) {
    final pathEnv = Platform.environment['PATH'] ?? '';
    final separator = Platform.isWindows ? ';' : ':';
    for (final dir in pathEnv.split(separator)) {
      final normalized = dir.trim();
      if (normalized.isEmpty) {
        continue;
      }
      final fullPath = '$normalized${Platform.pathSeparator}$name';
      if (File(fullPath).existsSync()) {
        return fullPath;
      }
    }
    return null;
  }

  Future<void> _sendToolResult(
    Object? id, {
    required bool isError,
    required Map<String, Object?> payload,
  }) async {
    final text = const JsonEncoder.withIndent('  ').convert(payload);
    await _sendRpcResult(id, <String, Object?>{
      'content': <Map<String, Object?>>[
        <String, Object?>{'type': 'text', 'text': text},
      ],
      'isError': isError,
    });
  }

  Future<void> _sendRpcResult(Object? id, Object? result) async {
    await _sendMessage(<String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'result': result,
    });
  }

  Future<void> _sendRpcError({
    required Object? id,
    required int code,
    required String message,
  }) async {
    await _sendMessage(<String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'error': <String, Object?>{'code': code, 'message': message},
    });
  }

  Future<void> _sendMessage(Map<String, Object?> payload) async {
    final encoded = utf8.encode(jsonEncode(payload));
    if (_wireFormat == _McpWireFormat.ndjson) {
      stdout.add(encoded);
      stdout.add(<int>[10]);
      await stdout.flush();
      return;
    }

    final header = ascii.encode('Content-Length: ${encoded.length}\r\n\r\n');
    stdout.add(header);
    stdout.add(encoded);
    await stdout.flush();
  }

  Map<String, String> _parseHeaders(List<int> headerBytes) {
    final headerText = ascii.decode(headerBytes, allowInvalid: true);
    final normalizedHeaderText = headerText
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final headers = <String, String>{};
    final lines = normalizedHeaderText.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final separator = trimmed.indexOf(':');
      if (separator <= 0) {
        continue;
      }
      final key = trimmed.substring(0, separator).trim().toLowerCase();
      final value = trimmed.substring(separator + 1).trim();
      headers[key] = value;
    }
    return headers;
  }

  _HeaderTerminator? _indexOfHeaderTerminator(List<int> bytes) {
    for (var i = 0; i <= bytes.length - 2; i++) {
      if (bytes[i] == 13 &&
          i <= bytes.length - 4 &&
          bytes[i + 1] == 10 &&
          bytes[i + 2] == 13 &&
          bytes[i + 3] == 10) {
        return _HeaderTerminator(i, 4);
      }
      if (bytes[i] == 10 && bytes[i + 1] == 10) {
        return _HeaderTerminator(i, 2);
      }
    }
    return null;
  }

  int? _indexOfByte(List<int> bytes, int value) {
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] == value) {
        return i;
      }
    }
    return null;
  }

  bool _isAsciiWhitespace(int value) {
    return value == 9 || value == 10 || value == 13 || value == 32;
  }

  bool _isAsciiLetter(int value) {
    return (value >= 65 && value <= 90) || (value >= 97 && value <= 122);
  }

  String _asText(Object? value) {
    if (value == null) {
      return '';
    }
    if (value is String) {
      return value;
    }
    return value.toString();
  }
}

class _DllartInvocation {
  const _DllartInvocation(this.executable, this.baseArgs);

  final String executable;
  final List<String> baseArgs;
}

class _HeaderTerminator {
  const _HeaderTerminator(this.index, this.length);

  final int index;
  final int length;
}

enum _McpWireFormat { unknown, contentLength, ndjson }
