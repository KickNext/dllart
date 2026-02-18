part of dllart_cli;

String? _libraryPathFromManifest(String manifestPath) {
  final file = File(manifestPath);
  if (!file.existsSync()) {
    return null;
  }

  try {
    final raw = jsonDecode(file.readAsStringSync());
    if (raw is! Map<String, dynamic>) {
      return null;
    }

    final paths = raw['paths'];
    if (paths is! Map<String, dynamic>) {
      return null;
    }

    final library = paths['library'];
    if (library is! String || library.trim().isEmpty) {
      return null;
    }

    return p.normalize(library);
  } catch (_) {
    return null;
  }
}

Future<T> _withBuildLock<T>(
  String outputPath,
  Future<T> Function() action,
) async {
  final lockPath = p.join(outputPath, '.build.lock');
  final lockFile = File(lockPath);
  lockFile.createSync(recursive: true);
  final raf = lockFile.openSync(mode: FileMode.append);
  _logLine('Acquiring build lock: ${_displayPath(lockPath)}');
  raf.lockSync(FileLock.blockingExclusive);
  try {
    return await action();
  } finally {
    try {
      raf.unlockSync();
    } catch (_) {}
    raf.closeSync();
  }
}

String _displayPath(String absolutePath) {
  final normalized = p.normalize(absolutePath);
  final relative = p.relative(normalized, from: Directory.current.path);
  final isInside = !relative.startsWith('..') && !p.isAbsolute(relative);
  if (isInside) {
    return relative.replaceAll('\\', '/');
  }
  return normalized.replaceAll('\\', '/');
}

String _hostTargetId() {
  final os = Platform.isMacOS
      ? 'macos'
      : Platform.isLinux
      ? 'linux'
      : Platform.isWindows
      ? 'windows'
      : Platform.operatingSystem;
  final arch = _hostArch();
  return '$os-$arch';
}

String _hostArch() {
  if (Platform.isWindows) {
    final arch = (Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '')
        .toLowerCase()
        .trim();
    if (arch == 'amd64' || arch == 'x86_64') {
      return 'x64';
    }
    if (arch == 'arm64' || arch == 'aarch64') {
      return 'arm64';
    }
    if (arch == 'x86') {
      return 'x86';
    }
    return arch.isEmpty ? 'unknown' : arch;
  }

  final result = Process.runSync('uname', <String>['-m']);
  if (result.exitCode == 0) {
    final raw = result.stdout.toString().trim().toLowerCase();
    if (raw == 'x86_64' || raw == 'amd64') {
      return 'x64';
    }
    if (raw == 'arm64' || raw == 'aarch64') {
      return 'arm64';
    }
    return raw.isEmpty ? 'unknown' : raw;
  }

  return 'unknown';
}

String _sanitizeForC(String value) {
  final out = StringBuffer();
  for (final rune in value.runes) {
    final ch = String.fromCharCode(rune);
    final isAlnum = RegExp(r'[A-Za-z0-9_]').hasMatch(ch);
    out.write(isAlnum ? ch : '_');
  }
  final text = out.toString();
  if (text.isEmpty) {
    return 'module';
  }
  if (RegExp(r'^[0-9]').hasMatch(text)) {
    return '_$text';
  }
  return text;
}

String _moduleRuntimePrefix(String moduleName) {
  final modulePrefix = _sanitizeForC(moduleName).toLowerCase();
  return '${modulePrefix}_dllart';
}

List<String> _bridgeSymbolDefines(String moduleName) {
  final runtimePrefix = _moduleRuntimePrefix(moduleName);
  return <String>[
    '-Ddllart_abi_version=${runtimePrefix}_abi_version',
    '-Ddllart_init=${runtimePrefix}_init',
    '-Ddllart_call_json=${runtimePrefix}_call_json',
    '-Ddllart_call_json_batch=${runtimePrefix}_call_json_batch',
    '-Ddllart_call_json_raw=${runtimePrefix}_call_json_raw',
    '-Ddllart_call_i64_2=${runtimePrefix}_call_i64_2',
    '-Ddllart_call_i64_2_index=${runtimePrefix}_call_i64_2_index',
    '-Ddllart_call_i64_4=${runtimePrefix}_call_i64_4',
    '-Ddllart_call_i64_4_index=${runtimePrefix}_call_i64_4_index',
    '-Ddllart_call_f64_2=${runtimePrefix}_call_f64_2',
    '-Ddllart_call_f64_2_index=${runtimePrefix}_call_f64_2_index',
    '-Ddllart_call_f64_4=${runtimePrefix}_call_f64_4',
    '-Ddllart_call_f64_4_index=${runtimePrefix}_call_f64_4_index',
    '-Ddllart_call_bytes=${runtimePrefix}_call_bytes',
    '-Ddllart_call_bytes_index=${runtimePrefix}_call_bytes_index',
    '-Ddllart_last_error_code=${runtimePrefix}_last_error_code',
    '-Ddllart_last_error_json=${runtimePrefix}_last_error_json',
    '-Ddllart_shutdown=${runtimePrefix}_shutdown',
    '-Ddllart_string_free=${runtimePrefix}_string_free',
    '-Ddllart_bytes_free=${runtimePrefix}_bytes_free',
    '-Ddllart_call=${runtimePrefix}_call',
  ];
}

String _escapeCString(String value) {
  return value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
}

String _escapeDartSingleQuoted(String value) {
  return value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$');
}

String _outputLibraryPath(String outputPath, String moduleName) {
  if (Platform.isMacOS) {
    return p.join(outputPath, 'lib$moduleName.dylib');
  }
  if (Platform.isLinux) {
    return p.join(outputPath, 'lib$moduleName.so');
  }
  if (Platform.isWindows) {
    return p.join(outputPath, '$moduleName.dll');
  }
  throw ToolError('Unsupported host platform: ${Platform.operatingSystem}');
}

String _runtimeExecutableNameForHost() {
  return Platform.isWindows ? 'dartaotruntime.exe' : 'dartaotruntime';
}

String _readSdkVersion(String sdkRoot) {
  final versionPath = p.join(sdkRoot, 'version');
  final file = File(versionPath);
  if (!file.existsSync()) {
    return 'unknown';
  }
  final version = file.readAsStringSync().trim();
  if (version.isEmpty) {
    return 'unknown';
  }
  return version;
}

Toolchain _resolveToolchain() {
  final dart = p.normalize(Platform.resolvedExecutable);

  final runtimeName = _runtimeExecutableNameForHost();
  final genSnapshotName = Platform.isWindows
      ? 'gen_snapshot.exe'
      : 'gen_snapshot';

  final candidates = <String>[
    p.join(p.dirname(dart), runtimeName),
    p.join(p.dirname(dart), 'cache', 'dart-sdk', 'bin', runtimeName),
  ];

  String? dartaot;
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) {
      dartaot = p.normalize(candidate);
      break;
    }
  }

  if (dartaot == null) {
    throw ToolError(
      'Cannot locate dartaotruntime. Checked: ${candidates.join(', ')}',
    );
  }

  final sdkRoot = p.normalize(p.dirname(p.dirname(dartaot)));
  final dartSdkVersion = _readSdkVersion(sdkRoot);
  final frontendServer = p.join(
    sdkRoot,
    'bin',
    'snapshots',
    'frontend_server_aot.dart.snapshot',
  );
  final genSnapshot = p.join(sdkRoot, 'bin', 'utils', genSnapshotName);
  final platformDill = p.join(
    sdkRoot,
    'lib',
    '_internal',
    'vm_platform_strong.dill',
  );
  final sdkInclude = p.join(sdkRoot, 'include');

  for (final required in <String>[
    frontendServer,
    genSnapshot,
    platformDill,
    p.join(sdkInclude, 'dart_api.h'),
  ]) {
    if (!File(required).existsSync()) {
      throw ToolError('Required SDK artifact not found: $required');
    }
  }

  final clang = _findExecutable(
    Platform.isWindows ? <String>['clang.exe', 'clang'] : <String>['clang'],
  );

  if (clang == null) {
    throw ToolError('clang not found in PATH');
  }

  return Toolchain(
    dart: dart,
    dartaot: dartaot,
    dartSdkVersion: dartSdkVersion,
    sdkRoot: sdkRoot,
    frontendServer: frontendServer,
    genSnapshot: genSnapshot,
    platformDill: platformDill,
    sdkInclude: sdkInclude,
    clang: clang,
  );
}

String? _findExecutable(List<String> names) {
  final pathEnv = Platform.environment['PATH'] ?? '';
  final separator = Platform.isWindows ? ';' : ':';
  final dirs = pathEnv.split(separator).where((d) => d.trim().isNotEmpty);

  for (final dir in dirs) {
    for (final name in names) {
      final candidate = p.join(dir, name);
      if (File(candidate).existsSync()) {
        return p.normalize(candidate);
      }
    }
  }

  if (Platform.isWindows) {
    final llvm = p.join(r'C:\Program Files\LLVM\bin', 'clang.exe');
    if (File(llvm).existsSync()) {
      return llvm;
    }
  }

  return null;
}

Future<ProcessResult> _runCommandCapture(
  String executable,
  List<String> args, {
  String? workingDirectory,
}) async {
  return Process.run(
    executable,
    args,
    workingDirectory: workingDirectory,
    runInShell: false,
  );
}

Future<String?> _ensurePackageConfig({
  required String sourcePath,
  required String configDir,
}) async {
  final candidateRoots = <String>[
    p.dirname(sourcePath),
    configDir,
    Directory.current.path,
  ];

  String? packageRoot;
  for (final candidate in candidateRoots) {
    packageRoot = _findNearestPubspecDir(candidate);
    if (packageRoot != null) {
      break;
    }
  }

  if (packageRoot == null) {
    return null;
  }

  final packageConfigPath = p.join(
    packageRoot,
    '.dart_tool',
    'package_config.json',
  );
  if (File(packageConfigPath).existsSync()) {
    return packageConfigPath;
  }

  _logLine(
    'No package config found in $packageRoot, running `dart pub get`...',
  );
  final result = await _runCommandCapture(Platform.resolvedExecutable, <String>[
    'pub',
    'get',
  ], workingDirectory: packageRoot);
  if (result.exitCode != 0) {
    throw ToolError(
      '${_processFailureSummary('dart pub get', result)}. '
      'Next: run `dart pub get` in ${_displayPath(packageRoot)} and fix '
      'dependency resolution. If this project was created from a local '
      'dllart checkout, use `dllart create <project> --dependency=path`.',
    );
  }

  if (!File(packageConfigPath).existsSync()) {
    throw ToolError('Failed to generate package config: $packageConfigPath');
  }
  return packageConfigPath;
}

String? _findNearestPubspecDir(String startPath) {
  String current = p.normalize(p.absolute(startPath));
  while (true) {
    final pubspecPath = p.join(current, 'pubspec.yaml');
    if (File(pubspecPath).existsSync()) {
      return current;
    }
    final parent = p.dirname(current);
    if (parent == current) {
      return null;
    }
    current = parent;
  }
}

String _asText(Object? value) {
  if (value == null) {
    return '';
  }
  return value.toString();
}

String? _firstNonEmptyLine(String text) {
  final lines = text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty);
  if (lines.isEmpty) {
    return null;
  }
  return lines.first;
}

String _processFailureSummary(String commandLabel, ProcessResult result) {
  final combined = '${_asText(result.stderr)}\n${_asText(result.stdout)}';
  final line = _firstNonEmptyLine(combined);
  if (line == null) {
    return '$commandLabel failed with exit code ${result.exitCode}';
  }
  return '$commandLabel failed (${result.exitCode}): $line';
}

String _sha256Bytes(List<int> bytes) {
  return crypto.sha256.convert(bytes).toString();
}

String _sha256Text(String text) {
  return _sha256Bytes(utf8.encode(text));
}

String _sha256File(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw ToolError('Cannot compute SHA-256 for missing file: $path');
  }
  return _sha256Bytes(file.readAsBytesSync());
}

DateTime _deterministicBuildTimestampUtc() {
  final raw = (Platform.environment['SOURCE_DATE_EPOCH'] ?? '').trim();
  if (raw.isEmpty) {
    return DateTime.now().toUtc();
  }
  final seconds = int.tryParse(raw);
  if (seconds == null || seconds < 0) {
    return DateTime.now().toUtc();
  }
  return DateTime.fromMillisecondsSinceEpoch(
    seconds * 1000,
    isUtc: true,
  ).toUtc();
}

bool _isReproducibleBuildEnabled() {
  final raw = (Platform.environment['SOURCE_DATE_EPOCH'] ?? '').trim();
  return raw.isNotEmpty && int.tryParse(raw) != null;
}

String _resolveRuntimeProfile(LoadedConfig loaded, ParsedArgs args) {
  final value = (args['runtime-profile'] ?? loaded.config.runtime.profile)
      .trim();
  if (value == 'full' || value == 'slim') {
    return value;
  }
  throw ToolError('Unsupported runtime profile: $value. Use full or slim.');
}

String _resolveBuildTarget(ParsedArgs args) {
  final value = (args['target'] ?? 'host').trim().toLowerCase();
  if (value == 'host' || value == 'android' || value == 'ios') {
    return value;
  }
  throw ToolError(
    'Unsupported build target: $value. Use host, android, or ios.',
  );
}

Future<void> _runCommand(
  String executable,
  List<String> args, {
  String? workingDirectory,
}) async {
  final result = await _runCommandCapture(
    executable,
    args,
    workingDirectory: workingDirectory,
  );
  if (_inVerboseMode && !_inJsonMode) {
    final commandLabel = '$executable ${args.join(' ')}';
    _logLine('[exec] $commandLabel');
    final stdoutText = _asText(result.stdout).trimRight();
    final stderrText = _asText(result.stderr).trimRight();
    if (stdoutText.isNotEmpty) {
      stdout.writeln(stdoutText);
    }
    if (stderrText.isNotEmpty) {
      stderr.writeln(stderrText);
    }
  }
  if (result.exitCode != 0) {
    throw ToolError(
      _processFailureSummary('$executable ${args.join(' ')}', result),
    );
  }
}

String _toolRoot({String? packageConfigPath}) {
  final scriptPath = p.normalize(Platform.script.toFilePath());
  final scriptDir = p.dirname(scriptPath);

  final packageConfigCandidates = <String>{};
  if (packageConfigPath != null && packageConfigPath.trim().isNotEmpty) {
    packageConfigCandidates.add(p.normalize(packageConfigPath));
  }

  for (final start in <String>[
    Directory.current.path,
    scriptDir,
    p.join(scriptDir, '..'),
    p.join(scriptDir, '..', '..'),
    p.join(scriptDir, '..', '..', '..'),
  ]) {
    final config = _findNearestPackageConfig(start);
    if (config != null) {
      packageConfigCandidates.add(config);
    }
  }

  for (final configPath in packageConfigCandidates) {
    final resolved = _dllartRootFromPackageConfig(configPath);
    if (resolved != null) {
      return resolved;
    }
  }

  final starts = <String>{
    p.normalize(Directory.current.path),
    scriptDir,
    p.normalize(p.join(scriptDir, '..')),
    p.normalize(p.join(scriptDir, '..', '..')),
    p.normalize(p.join(scriptDir, '..', '..', '..')),
  };

  for (final start in starts) {
    final found = _findToolRootFrom(start);
    if (found != null) {
      return found;
    }
  }

  return p.normalize(Directory.current.path);
}

bool _isLikelyPubCachePath(String path) {
  final normalized = p.normalize(path).replaceAll('\\', '/').toLowerCase();
  return normalized.contains('/.pub-cache/') ||
      normalized.contains('/pub/cache/') ||
      normalized.contains('/pub-cache/');
}

bool _isValidDllartRoot(String rootPath) {
  final normalized = p.normalize(rootPath);
  return File(p.join(normalized, 'pubspec.yaml')).existsSync() &&
      File(p.join(normalized, 'native', 'dllart_bridge.c')).existsSync() &&
      File(p.join(normalized, 'native', 'dllart_bridge.h')).existsSync();
}

String? _findNearestPackageConfig(String startPath) {
  var current = p.normalize(p.absolute(startPath));
  while (true) {
    final candidate = p.join(current, '.dart_tool', 'package_config.json');
    if (File(candidate).existsSync()) {
      return candidate;
    }
    final parent = p.dirname(current);
    if (parent == current) {
      return null;
    }
    current = parent;
  }
}

String? _dllartRootFromPackageConfig(String packageConfigPath) {
  final configFile = File(packageConfigPath);
  if (!configFile.existsSync()) {
    return null;
  }

  try {
    final decoded = jsonDecode(configFile.readAsStringSync());
    if (decoded is! Map) {
      return null;
    }
    final packages = decoded['packages'];
    if (packages is! List) {
      return null;
    }

    for (final pkg in packages) {
      if (pkg is! Map) {
        continue;
      }
      final name = pkg['name'];
      if (name != 'dllart') {
        continue;
      }
      final rootUri = pkg['rootUri'];
      if (rootUri is! String || rootUri.trim().isEmpty) {
        continue;
      }
      final resolved = _resolvePackageRootUriPath(packageConfigPath, rootUri);
      if (resolved == null) {
        continue;
      }

      final bridgeSource = File(p.join(resolved, 'native', 'dllart_bridge.c'));
      final bridgeHeader = File(p.join(resolved, 'native', 'dllart_bridge.h'));
      if (bridgeSource.existsSync() && bridgeHeader.existsSync()) {
        return resolved;
      }
    }
  } catch (_) {
    return null;
  }

  return null;
}

String? _resolvePackageRootUriPath(
  String packageConfigPath,
  String rootUriText,
) {
  final configDir = p.dirname(packageConfigPath);

  try {
    final uri = Uri.parse(rootUriText);
    if (uri.scheme == 'file') {
      return p.normalize(uri.toFilePath());
    }
    if (uri.scheme.isNotEmpty) {
      return null;
    }

    final relativePath = Uri.decodeComponent(uri.path);
    if (relativePath.isEmpty) {
      return p.normalize(configDir);
    }
    return p.normalize(p.absolute(p.join(configDir, relativePath)));
  } catch (_) {
    return null;
  }
}

String? _findToolRootFrom(String start) {
  var current = p.normalize(start);
  while (true) {
    final pubspec = File(p.join(current, 'pubspec.yaml'));
    final bridgeSource = File(p.join(current, 'native', 'dllart_bridge.c'));
    final bridgeHeader = File(p.join(current, 'native', 'dllart_bridge.h'));
    if (pubspec.existsSync() &&
        bridgeSource.existsSync() &&
        bridgeHeader.existsSync()) {
      return current;
    }

    final parent = p.dirname(current);
    if (parent == current) {
      return null;
    }
    current = parent;
  }
}

class _BridgeTemplatePaths {
  const _BridgeTemplatePaths({required this.source, required this.header});

  final String source;
  final String header;
}

_BridgeTemplatePaths _resolveBridgeTemplatePaths({String? packageConfigPath}) {
  final scriptPath = p.normalize(Platform.script.toFilePath());
  final scriptDir = p.dirname(scriptPath);

  final candidateRoots = <String>{
    _toolRoot(packageConfigPath: packageConfigPath),
    p.normalize(Directory.current.path),
    scriptDir,
    p.normalize(p.join(scriptDir, '..')),
    p.normalize(p.join(scriptDir, '..', '..')),
    p.normalize(p.join(scriptDir, '..', '..', '..')),
  };

  for (final root in candidateRoots) {
    final source = p.join(root, 'native', 'dllart_bridge.c');
    final header = p.join(root, 'native', 'dllart_bridge.h');
    if (File(source).existsSync() && File(header).existsSync()) {
      return _BridgeTemplatePaths(source: source, header: header);
    }
  }

  throw ToolError(
    'Cannot locate bridge templates (native/dllart_bridge.c and '
    'native/dllart_bridge.h). Looked under: '
    '${candidateRoots.map(_displayPath).join(', ')}',
  );
}

void _ensureNativeBridgeScaffold({
  required String projectRoot,
  required bool force,
  String? packageConfigPath,
}) {
  final templates = _resolveBridgeTemplatePaths(
    packageConfigPath: packageConfigPath,
  );

  final nativeDir = p.join(projectRoot, 'native');
  Directory(nativeDir).createSync(recursive: true);

  _copyTemplateFile(
    sourcePath: templates.source,
    destinationPath: p.join(nativeDir, 'dllart_bridge.c'),
    force: force,
  );
  _copyTemplateFile(
    sourcePath: templates.header,
    destinationPath: p.join(nativeDir, 'dllart_bridge.h'),
    force: force,
  );
}

void _copyTemplateFile({
  required String sourcePath,
  required String destinationPath,
  required bool force,
}) {
  final source = File(sourcePath);
  if (!source.existsSync()) {
    throw ToolError('Bridge template not found: $sourcePath');
  }

  final destination = File(destinationPath);
  if (destination.existsSync() && !force) {
    return;
  }

  destination.createSync(recursive: true);
  source.copySync(destinationPath);
}

String _generateWorkflowYaml(
  LoadedConfig loaded, {
  String? baseDir,
  bool useGlobalTool = false,
}) {
  final relBase = p.normalize(baseDir ?? Directory.current.path);
  final configRel = p
      .relative(loaded.configPath, from: relBase)
      .replaceAll('\\', '/');
  final outputRel = loaded.config.output.replaceAll('\\', '/');
  final sourceRel = loaded.config.source.replaceAll('\\', '/');
  final toolSteps = useGlobalTool
      ? '''
      - name: Activate dllart
        run: dart pub global activate dllart

      - name: Add pub cache to PATH (Unix)
        if: runner.os != 'Windows'
        run: echo "\$HOME/.pub-cache/bin" >> "\$GITHUB_PATH"

      - name: Add pub cache to PATH (Windows)
        if: runner.os == 'Windows'
        shell: pwsh
        run: '"\$env:LOCALAPPDATA\\Pub\\Cache\\bin" | Out-File -FilePath \$env:GITHUB_PATH -Encoding utf8 -Append'
'''
      : '';
  final toolStepsBlock = toolSteps.isEmpty ? '' : '$toolSteps\n';
  final buildCommand = useGlobalTool
      ? 'dllart build --config $configRel'
      : 'dart run dllart build --config $configRel';

  return '''name: DLLART Build

on:
  workflow_dispatch:
  push:
    paths:
      - '$configRel'
      - '$sourceRel'
      - 'lib/**'

jobs:
  build:
    strategy:
      fail-fast: false
      matrix:
        os: [macos-latest, ubuntu-latest, windows-latest]
    runs-on: \${{ matrix.os }}

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Dart
        uses: dart-lang/setup-dart@v1
${toolStepsBlock}
      - name: Install Clang (Linux)
        if: runner.os == 'Linux'
        run: sudo apt-get update && sudo apt-get install -y clang

      - name: Install LLVM (Windows)
        if: runner.os == 'Windows'
        run: choco install llvm --yes --no-progress

      - name: Add LLVM to PATH (Windows)
        if: runner.os == 'Windows'
        shell: pwsh
        run: '"C:\\Program Files\\LLVM\\bin" | Out-File -FilePath \$env:GITHUB_PATH -Encoding utf8 -Append'

      - name: Resolve deps
        run: dart pub get

      - name: Build dllart module
        run: $buildCommand

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: dllart-\${{ runner.os }}
          path: $outputRel/**
''';
}
