import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final String _repoRoot = p.normalize(Directory.current.path);

String _compiledMcpBinaryPath() {
  final fileName = Platform.isWindows ? 'dllart_mcp.exe' : 'dllart_mcp';
  return p.join(_repoRoot, 'bin', fileName);
}

Future<Process> _startMcpServer() {
  return Process.start(
    Platform.resolvedExecutable,
    <String>[p.join(_repoRoot, 'bin', 'dllart_mcp.dart')],
    workingDirectory: _repoRoot,
    runInShell: false,
  );
}

Future<void> _stopProcess(Process process) async {
  process.kill();
  try {
    await process.exitCode.timeout(const Duration(seconds: 5));
  } on TimeoutException {
    process.kill();
  }
}

Future<Map<String, Object?>> _sendInitializeAndRead(
  Process process, {
  required String lineEnding,
}) async {
  final request = _initializeRequest();

  final body = utf8.encode(jsonEncode(request));
  final header = ascii.encode(
    'Content-Length: ${body.length}$lineEnding$lineEnding',
  );
  process.stdin.add(header);
  process.stdin.add(body);
  await process.stdin.flush();

  return _readSingleFrame(process.stdout).timeout(
    const Duration(seconds: 10),
    onTimeout: () => throw TimeoutException('Timed out waiting for MCP reply'),
  );
}

Future<Map<String, Object?>> _sendInitializeAndReadNdjson(
  Process process,
) async {
  final request = _initializeRequest();
  process.stdin.add(utf8.encode('${jsonEncode(request)}\n'));
  await process.stdin.flush();

  return _readSingleLineMessage(process.stdout).timeout(
    const Duration(seconds: 10),
    onTimeout: () => throw TimeoutException('Timed out waiting for MCP reply'),
  );
}

Map<String, Object?> _initializeRequest() {
  return <String, Object?>{
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'initialize',
    'params': <String, Object?>{
      'protocolVersion': '2025-03-26',
      'capabilities': <String, Object?>{},
    },
  };
}

Future<Map<String, Object?>> _readSingleFrame(Stream<List<int>> source) async {
  final iterator = StreamIterator<List<int>>(source);
  final buffer = <int>[];
  try {
    while (await iterator.moveNext()) {
      buffer.addAll(iterator.current);
      final frame = _tryDecodeFrame(buffer);
      if (frame != null) {
        return frame;
      }
    }
  } finally {
    await iterator.cancel();
  }

  throw StateError('MCP stdout closed before response frame was received');
}

Future<Map<String, Object?>> _readSingleLineMessage(
  Stream<List<int>> source,
) async {
  final iterator = StreamIterator<List<int>>(source);
  final buffer = <int>[];
  try {
    return await _readSingleLineMessageFromIterator(iterator, buffer);
  } finally {
    await iterator.cancel();
  }
}

Future<Map<String, Object?>> _readSingleLineMessageFromIterator(
  StreamIterator<List<int>> iterator,
  List<int> buffer,
) async {
  while (await iterator.moveNext()) {
    buffer.addAll(iterator.current);
    final newline = buffer.indexOf(10);
    if (newline < 0) {
      continue;
    }

    var line = buffer.sublist(0, newline);
    if (line.isNotEmpty && line.last == 13) {
      line = line.sublist(0, line.length - 1);
    }
    buffer.removeRange(0, newline + 1);
    final decoded = jsonDecode(utf8.decode(line));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'MCP line-delimited message must be a JSON object',
      );
    }
    return decoded.cast<String, Object?>();
  }

  throw StateError('MCP stdout closed before response frame was received');
}

Map<String, Object?>? _tryDecodeFrame(List<int> buffer) {
  final split = _indexOfHeaderTerminator(buffer);
  if (split == null) {
    return null;
  }

  final headerText = ascii.decode(
    buffer.sublist(0, split.index),
    allowInvalid: true,
  );
  final contentLength = _parseContentLength(headerText);
  if (contentLength == null || contentLength < 0) {
    throw const FormatException('Missing or invalid Content-Length header');
  }

  final bodyOffset = split.index + split.length;
  final frameLength = bodyOffset + contentLength;
  if (buffer.length < frameLength) {
    return null;
  }

  final bodyBytes = buffer.sublist(bodyOffset, frameLength);
  buffer.removeRange(0, frameLength);

  final decoded = jsonDecode(utf8.decode(bodyBytes));
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('MCP frame body must be a JSON object');
  }

  return decoded.cast<String, Object?>();
}

int? _parseContentLength(String headerText) {
  final normalized = headerText.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  for (final line in normalized.split('\n')) {
    final separator = line.indexOf(':');
    if (separator <= 0) {
      continue;
    }

    final key = line.substring(0, separator).trim().toLowerCase();
    if (key != 'content-length') {
      continue;
    }

    final value = line.substring(separator + 1).trim();
    return int.tryParse(value);
  }

  return null;
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

class _HeaderTerminator {
  const _HeaderTerminator(this.index, this.length);

  final int index;
  final int length;
}

void main() {
  test('initialize accepts CRLF header terminator', () async {
    final process = await _startMcpServer();
    try {
      final response = await _sendInitializeAndRead(
        process,
        lineEnding: '\r\n',
      );

      expect(response['jsonrpc'], '2.0');
      expect(response['id'], 1);
      final result = response['result'] as Map<Object?, Object?>;
      final serverInfo = result['serverInfo'] as Map<Object?, Object?>;
      expect(serverInfo['name'], 'dllart-mcp');
    } finally {
      await _stopProcess(process);
    }
  });

  test('initialize accepts LF-only header terminator', () async {
    final process = await _startMcpServer();
    try {
      final response = await _sendInitializeAndRead(process, lineEnding: '\n');

      expect(response['jsonrpc'], '2.0');
      expect(response['id'], 1);
      final result = response['result'] as Map<Object?, Object?>;
      final serverInfo = result['serverInfo'] as Map<Object?, Object?>;
      expect(serverInfo['name'], 'dllart-mcp');
    } finally {
      await _stopProcess(process);
    }
  });

  test('initialize accepts newline-delimited JSON framing', () async {
    final process = await _startMcpServer();
    try {
      final response = await _sendInitializeAndReadNdjson(process);

      expect(response['jsonrpc'], '2.0');
      expect(response['id'], 1);
      final result = response['result'] as Map<Object?, Object?>;
      final serverInfo = result['serverInfo'] as Map<Object?, Object?>;
      expect(serverInfo['name'], 'dllart-mcp');
    } finally {
      await _stopProcess(process);
    }
  });

  test('compiled mcp binary runs dllart.help tool', () async {
    final binaryPath = _compiledMcpBinaryPath();
    if (!File(binaryPath).existsSync()) {
      markTestSkipped('Compiled MCP binary not found at $binaryPath');
      return;
    }

    late final Process process;
    try {
      process = await Process.start(
        binaryPath,
        const <String>[],
        workingDirectory: _repoRoot,
        runInShell: false,
      );
    } on ProcessException catch (error) {
      final message = error.message.toLowerCase();
      final incompatibleBinary =
          message.contains('exec format') ||
          message.contains('bad cpu type') ||
          message.contains('not a valid win32 application') ||
          message.contains('cannot execute');
      if (incompatibleBinary) {
        markTestSkipped(
          'Compiled MCP binary is incompatible with ${Platform.operatingSystem}: $binaryPath',
        );
        return;
      }
      rethrow;
    }
    final iterator = StreamIterator<List<int>>(process.stdout);
    final buffer = <int>[];

    try {
      process.stdin.add(utf8.encode('${jsonEncode(_initializeRequest())}\n'));
      await process.stdin.flush();

      final initResponse =
          await _readSingleLineMessageFromIterator(iterator, buffer).timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException(
              'Timed out waiting for initialize response',
            ),
          );
      expect(initResponse['jsonrpc'], '2.0');
      expect(initResponse['id'], 1);

      final initializedNotification = <String, Object?>{
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
      };
      process.stdin.add(
        utf8.encode('${jsonEncode(initializedNotification)}\n'),
      );

      final toolsListRequest = <String, Object?>{
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'tools/list',
        'params': <String, Object?>{},
      };
      process.stdin.add(utf8.encode('${jsonEncode(toolsListRequest)}\n'));
      await process.stdin.flush();

      final toolsListResponse =
          await _readSingleLineMessageFromIterator(iterator, buffer).timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException(
              'Timed out waiting for tools/list response',
            ),
          );
      expect(toolsListResponse['jsonrpc'], '2.0');
      expect(toolsListResponse['id'], 2);

      final toolsListResult =
          toolsListResponse['result'] as Map<Object?, Object?>;
      final tools = toolsListResult['tools'] as List<Object?>;
      final runTool = tools.cast<Map<Object?, Object?>>().firstWhere(
        (tool) => tool['name'] == 'dllart.run',
      );
      final inputSchema = runTool['inputSchema'] as Map<Object?, Object?>;
      final properties = inputSchema['properties'] as Map<Object?, Object?>;
      final commandField = properties['command'] as Map<Object?, Object?>;
      final commandEnum = (commandField['enum'] as List<Object?>)
          .map((item) => item.toString())
          .toList(growable: false);
      expect(commandEnum, contains('verify'));
      expect(properties.containsKey('dependency'), isTrue);
      expect(properties.containsKey('auto_build'), isTrue);

      final helpRequest = <String, Object?>{
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'tools/call',
        'params': <String, Object?>{
          'name': 'dllart.help',
          'arguments': <String, Object?>{},
        },
      };
      process.stdin.add(utf8.encode('${jsonEncode(helpRequest)}\n'));
      await process.stdin.flush();

      final helpResponse =
          await _readSingleLineMessageFromIterator(iterator, buffer).timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException(
              'Timed out waiting for tools/call response',
            ),
          );

      expect(helpResponse['jsonrpc'], '2.0');
      expect(helpResponse['id'], 3);

      final result = helpResponse['result'] as Map<Object?, Object?>;
      final content = result['content'] as List<Object?>;
      final textPayload = content.first as Map<Object?, Object?>;
      final text = textPayload['text'] as String;
      expect(text, contains('"exit_code": 0'));
      expect(text, contains('DLLART - Dart to native FFI library toolchain'));
    } finally {
      await iterator.cancel();
      await _stopProcess(process);
    }
  });
}
