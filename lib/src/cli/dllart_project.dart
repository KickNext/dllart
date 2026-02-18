part of dllart_cli;

enum _CreateDependencyMode { auto, version, path }

Future<void> _commandCreate(ParsedArgs args) async {
  final force = args.hasFlag('force');

  String? projectInput;
  if (args.positional.isNotEmpty) {
    projectInput = args.positional.first;
  } else if (args['path'] != null && args['path']!.trim().isNotEmpty) {
    projectInput = args['path']!.trim();
  } else if (args['name'] != null && args['name']!.trim().isNotEmpty) {
    projectInput = args['name']!.trim();
  }

  if (projectInput == null || projectInput.trim().isEmpty) {
    projectInput = '.';
  }

  final projectPath = p.normalize(
    p.absolute(args['path'] ?? projectInput.trim()),
  );
  final projectDir = Directory(projectPath);

  if (projectDir.existsSync()) {
    final hasFiles = projectDir
        .listSync(followLinks: false)
        .any((entity) => !p.basename(entity.path).startsWith('.DS_Store'));
    if (hasFiles && !force) {
      throw ToolError(
        'Directory is not empty: $projectPath (pass --force to overwrite files).',
      );
    }
  } else {
    projectDir.createSync(recursive: true);
  }

  final packageName = _normalizePackageName(p.basename(projectPath));
  final toolRoot = p.normalize(_toolRoot()).replaceAll('\\', '/');
  final dependencySelection = _resolveCreateDependencySelection(
    args,
    toolRoot: toolRoot,
  );
  final dllartVersion = _dllartPackageVersion(toolRoot);
  final sourceRel = 'lib/module.dart';
  final outputRel = 'build';
  final configPath = p.join(projectPath, 'dllart.json');

  final config = DllartConfig(
    name: packageName,
    source: sourceRel,
    output: outputRel,
    targets: List<String>.from(DllartConfig.defaultTargets),
  );

  _writeTextFile(
    p.join(projectPath, 'pubspec.yaml'),
    _projectPubspecTemplate(
      packageName,
      dllartVersion: dllartVersion,
      usePathDependency: dependencySelection.usePathDependency,
      dllartDependencyPath: dependencySelection.dllartDependencyPath,
    ),
    force: force,
  );
  _writeTextFile(
    p.join(projectPath, '.gitignore'),
    _projectGitignoreTemplate(),
    force: force,
  );
  _writeTextFile(
    configPath,
    const JsonEncoder.withIndent('  ').convert(config.toJson()) + '\n',
    force: force,
  );
  _writeTextFile(
    p.join(projectPath, sourceRel),
    _projectModuleTemplate(packageName),
    force: force,
  );
  _writeTextFile(
    p.join(projectPath, 'scripts', 'build.sh'),
    _projectBuildScriptTemplate(),
    force: force,
    makeExecutable: true,
  );
  _writeTextFile(
    p.join(projectPath, 'scripts', 'doctor.sh'),
    _projectDoctorScriptTemplate(),
    force: force,
    makeExecutable: true,
  );
  _writeTextFile(
    p.join(projectPath, 'README.md'),
    _projectReadmeTemplate(packageName),
    force: force,
  );
  _ensureNativeBridgeScaffold(projectRoot: projectPath, force: force);

  final loaded = LoadedConfig(config: config, configPath: configPath);
  _writeTextFile(
    p.join(projectPath, '.github', 'workflows', 'dllart-build.yml'),
    _generateWorkflowYaml(loaded, baseDir: projectPath, useGlobalTool: true),
    force: true,
  );

  stdout.writeln('Created dllart project: $projectPath');
  stdout.writeln('Package: $packageName');
  if (dependencySelection.usePathDependency &&
      dependencySelection.dllartDependencyPath != null) {
    stdout.writeln(
      'Dependency: path ${_displayPath(dependencySelection.dllartDependencyPath!)}',
    );
  } else {
    stdout.writeln('Dependency: version ^$dllartVersion');
  }
  stdout.writeln('Next steps:');
  stdout.writeln('  cd $projectPath');
  stdout.writeln('  dart pub get');
  stdout.writeln('  dllart doctor');
  stdout.writeln('  dllart build');
}

Future<void> _commandInit(ParsedArgs args) async {
  final cwd = Directory.current.path;
  final name = (args['name'] ?? p.basename(cwd)).trim();
  if (name.isEmpty) {
    throw ToolError('Module name is empty. Pass --name=<module>.');
  }

  final source = args['source'] ?? 'lib/module.dart';
  final output = args['output'] ?? 'build';
  final configPath = p.normalize(p.absolute(args['config'] ?? 'dllart.json'));
  final sourcePath = p.normalize(p.absolute(source));
  final force = args.hasFlag('force');

  if (File(configPath).existsSync() && !force) {
    throw ToolError(
      'Config already exists: $configPath (pass --force to overwrite).',
    );
  }

  final config = DllartConfig(
    name: name,
    source: p
        .relative(sourcePath, from: p.dirname(configPath))
        .replaceAll('\\', '/'),
    output: output,
    targets: List<String>.from(DllartConfig.defaultTargets),
  );

  await File(configPath).create(recursive: true);
  await File(configPath).writeAsString(
    const JsonEncoder.withIndent('  ').convert(config.toJson()) + '\n',
  );

  final annotationsPath = p.join(
    p.dirname(sourcePath),
    'dllart_annotations.dart',
  );
  if (!File(annotationsPath).existsSync() || force) {
    await File(annotationsPath).create(recursive: true);
    await File(annotationsPath).writeAsString(_projectAnnotationsTemplate());
  }

  if (!File(sourcePath).existsSync() || force) {
    await File(sourcePath).create(recursive: true);
    await File(sourcePath).writeAsString(_sourceTemplate(name));
  }

  final projectRoot =
      _findNearestPubspecDir(p.dirname(configPath)) ??
      _findNearestPubspecDir(p.dirname(sourcePath)) ??
      p.dirname(configPath);
  _ensureNativeBridgeScaffold(projectRoot: projectRoot, force: force);

  stdout.writeln('Created config: $configPath');
  stdout.writeln('Source module:  $sourcePath');
  stdout.writeln(
    'Next: dart run dllart build --config ${p.relative(configPath)}',
  );
}

String _normalizePackageName(String raw) {
  final lowered = raw.toLowerCase();
  final sanitized = lowered.replaceAll(RegExp(r'[^a-z0-9_]'), '_');
  final collapsed = sanitized.replaceAll(RegExp(r'_+'), '_');
  final trimmed = collapsed.replaceAll(RegExp(r'^_+|_+$'), '');
  if (trimmed.isEmpty) {
    return 'dllart_project';
  }
  if (RegExp(r'^[0-9]').hasMatch(trimmed)) {
    return 'p_$trimmed';
  }
  return trimmed;
}

void _writeTextFile(
  String path,
  String content, {
  required bool force,
  bool makeExecutable = false,
}) {
  final file = File(path);
  if (file.existsSync() && !force) {
    throw ToolError('File already exists: $path (pass --force to overwrite)');
  }
  file.createSync(recursive: true);
  file.writeAsStringSync(content);
  if (makeExecutable && !Platform.isWindows) {
    Process.runSync('chmod', <String>['+x', path]);
  }
}

String _projectPubspecTemplate(
  String packageName, {
  required String dllartVersion,
  required bool usePathDependency,
  required String? dllartDependencyPath,
}) {
  final quotedDependencyPath = dllartDependencyPath == null
      ? null
      : _yamlSingleQuoted(dllartDependencyPath);
  final dependencyBlock = usePathDependency
      ? '''
  dllart:
    path: $quotedDependencyPath'''
      : '  dllart: ^$dllartVersion';
  return '''name: $packageName
description: DLLART module project.
version: 0.1.0
publish_to: "none"

environment:
  sdk: ^3.10.0

dependencies:
$dependencyBlock
''';
}

String _dllartPackageVersion(String toolRoot) {
  final pubspecPath = p.join(toolRoot, 'pubspec.yaml');
  final file = File(pubspecPath);
  if (!file.existsSync()) {
    return '0.1.0';
  }
  final match = RegExp(
    r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9\.-]+)?)\s*$',
    multiLine: true,
  ).firstMatch(file.readAsStringSync());
  if (match == null) {
    return '0.1.0';
  }
  return match.group(1)!;
}

String _projectGitignoreTemplate() {
  return '''.dart_tool/
build/
''';
}

String _projectAnnotationsTemplate() {
  return '''class DllartExport {
  const DllartExport([this.name]);

  final String? name;
}
''';
}

String _projectModuleTemplate(String packageName) {
  return '''import 'package:dllart/dllart_annotations.dart';

@DllartExport()
Object? ping() => '$packageName::pong';

@DllartExport()
Object? add(Object? args) {
  if (args is! Map<String, dynamic>) {
    throw ArgumentError('Expected JSON object payload');
  }
  final a = args['a'];
  final b = args['b'];
  if (a is! num || b is! num) {
    throw ArgumentError('Fields \"a\" and \"b\" must be numbers');
  }
  return a + b;
}

@DllartExport('add_fast')
int addFast(int a, int b) => a + b;

@DllartExport('sum4_fast')
int sum4Fast(int a, int b, int c, int d) => a + b + c + d;

@DllartExport('avg2_fast')
double avg2Fast(double a, double b) => (a + b) / 2.0;
''';
}

String _yamlSingleQuoted(String value) {
  return "'${value.replaceAll("'", "''")}'";
}

String _projectBuildScriptTemplate() {
  return '''#!/usr/bin/env bash
set -euo pipefail

dart pub get
dllart build
''';
}

String _projectDoctorScriptTemplate() {
  return '''#!/usr/bin/env bash
set -euo pipefail

dart pub get
dllart doctor
''';
}

String _projectReadmeTemplate(String packageName) {
  return '''# $packageName

DLLART module project scaffold.

## Commands

```bash
dart pub get
dllart make
```

Manual flow:

```bash
dllart doctor
dllart build
dllart integrate
```

## Source

Main module source is in:

- `lib/module.dart`

Mark exported functions with `@DllartExport()`.
Supported signatures:

- `Object? fn()`
- `Object? fn(Object? args)`
- `int fn(int a, int b)` (direct typed i64_2 fast-path)
- `int fn(int a, int b, int c, int d)` (direct typed i64_4 fast-path)
- `double fn(double a, double b)` (direct typed f64_2 fast-path)
- `Uint8List fn(Uint8List args)` / `Uint8List fn(List<int> args)` (direct typed bytes fast-path, protobuf-ready)

After `dllart build`, artifacts are in:

- `build/include/`
- `build/lib/`
- `build/runtime/`
- `build/artifact.json`
- `build/USAGE.md`

Generated C API header:

- `build/include/${packageName}_api.h`

Low-level exported symbols are namespaced:

- `${packageName}_dllart_*`

Runtime is bundled automatically:

- `build/runtime/${_runtimeExecutableNameForHost()}`
- `${packageName}_dllart_init(NULL, ...)` uses runtime auto-lookup.

Optional runtime tuning:

- `DLLART_ISOLATE_POOL_SIZE=4 dllart build`
- `DLLART_KEEP_WORKDIR=1 dllart build` (debug temp files)

Mobile package scaffold:

- `dllart package android`
- `dllart package ios`
- `dllart package fuchsia`
- `dllart package flutter`
- `dllart package python`
- `dllart package csharp`
- `dllart package all`
''';
}

String _sourceTemplate(String name) {
  return '''import 'dllart_annotations.dart';

@DllartExport()
Object? ping(Object? _) => '$name::pong';

@DllartExport()
Object? add(Object? args) {
  if (args is! Map<String, dynamic>) {
    throw ArgumentError('Expected JSON object payload');
  }
  final a = args['a'];
  final b = args['b'];
  if (a is! num || b is! num) {
    throw ArgumentError('Fields "a" and "b" must be numbers');
  }
  return a + b;
}

@DllartExport('add_fast')
int addFast(int a, int b) => a + b;

@DllartExport('sum4_fast')
int sum4Fast(int a, int b, int c, int d) => a + b + c + d;

@DllartExport('avg2_fast')
double avg2Fast(double a, double b) => (a + b) / 2.0;
''';
}

class _CreateDependencySelection {
  const _CreateDependencySelection({
    required this.usePathDependency,
    this.dllartDependencyPath,
  });

  final bool usePathDependency;
  final String? dllartDependencyPath;
}

_CreateDependencySelection _resolveCreateDependencySelection(
  ParsedArgs args, {
  required String toolRoot,
}) {
  final hasLegacyPathFlag = args.hasFlag('local-path-dependency');
  final rawMode = (args['dependency'] ?? 'auto').trim().toLowerCase();
  final rawDllartPath = (args['dllart-path'] ?? '').trim();

  final mode = switch (rawMode) {
    '' || 'auto' => _CreateDependencyMode.auto,
    'version' => _CreateDependencyMode.version,
    'path' => _CreateDependencyMode.path,
    _ => throw ToolError(
      'Unsupported create dependency mode: $rawMode. '
      'Use auto, version, or path.',
    ),
  };

  if (hasLegacyPathFlag && mode == _CreateDependencyMode.version) {
    throw ToolError(
      'Conflicting dependency options: --local-path-dependency cannot be used '
      'with --dependency=version.',
    );
  }

  if (rawDllartPath.isNotEmpty && mode == _CreateDependencyMode.version) {
    throw ToolError('--dllart-path cannot be used with --dependency=version.');
  }

  final resolvedDllartPath = rawDllartPath.isEmpty
      ? toolRoot
      : p.normalize(p.absolute(rawDllartPath)).replaceAll('\\', '/');
  if (!_isValidDllartRoot(resolvedDllartPath)) {
    throw ToolError(
      'Invalid --dllart-path: $resolvedDllartPath. Expected a dllart root with '
      'pubspec.yaml and native bridge templates.',
    );
  }

  var effectiveMode = mode;
  if (hasLegacyPathFlag) {
    effectiveMode = _CreateDependencyMode.path;
  } else if (mode == _CreateDependencyMode.auto && rawDllartPath.isNotEmpty) {
    effectiveMode = _CreateDependencyMode.path;
  }

  if (effectiveMode == _CreateDependencyMode.auto) {
    effectiveMode = _isLikelyPubCachePath(resolvedDllartPath)
        ? _CreateDependencyMode.version
        : _CreateDependencyMode.path;
  }

  if (effectiveMode == _CreateDependencyMode.path) {
    return _CreateDependencySelection(
      usePathDependency: true,
      dllartDependencyPath: resolvedDllartPath,
    );
  }
  return const _CreateDependencySelection(usePathDependency: false);
}
