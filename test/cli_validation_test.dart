import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final String _repoRoot = p.normalize(Directory.current.path);

Future<ProcessResult> _runCli(
  List<String> args, {
  String? workingDirectory,
  Map<String, String>? environment,
}) {
  return Process.run(
    Platform.resolvedExecutable,
    <String>['run', p.join(_repoRoot, 'bin', 'dllart.dart'), ...args],
    workingDirectory: workingDirectory ?? _repoRoot,
    environment: environment,
  );
}

Future<bool> _hasExecutable(String executable, List<String> args) async {
  try {
    final result = await Process.run(executable, args, runInShell: false);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

String _libraryFileName(String moduleName) {
  if (Platform.isMacOS) {
    return 'lib$moduleName.dylib';
  }
  if (Platform.isLinux) {
    return 'lib$moduleName.so';
  }
  if (Platform.isWindows) {
    return '$moduleName.dll';
  }
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}

String _writeFakeProtocExecutable(Directory tempRoot) {
  if (Platform.isWindows) {
    final path = p.join(tempRoot.path, 'fake_protoc.bat');
    File(path).writeAsStringSync(r'''
@echo off
setlocal enabledelayedexpansion
set "OUT="
set "PROTO="
:next
if "%~1"=="" goto done
set "ARG=%~1"
if /I "!ARG:~0,11!"=="--dart_out=" (
  set "OUT=!ARG:~11!"
  if /I "!OUT:~0,5!"=="grpc:" set "OUT=!OUT:~5!"
)
for %%F in ("!ARG!") do (
  if /I "%%~xF"==".proto" set "PROTO=!ARG!"
)
shift
goto next
:done
if "%OUT%"=="" exit /b 2
if not exist "%OUT%" mkdir "%OUT%"
for %%F in ("%PROTO%") do set "BASE=%%~nF"
> "%OUT%\%BASE%.pb.dart" echo // generated
exit /b 0
''');
    return path;
  }

  final path = p.join(tempRoot.path, 'fake_protoc.sh');
  File(path).writeAsStringSync(r'''
#!/usr/bin/env sh
set -eu
OUT=""
PROTO=""
for ARG in "$@"; do
  case "$ARG" in
    --dart_out=*)
      OUT="${ARG#--dart_out=}"
      case "$OUT" in
        grpc:*) OUT="${OUT#grpc:}" ;;
      esac
      ;;
    *.proto)
      PROTO="$ARG"
      ;;
  esac
done
if [ -z "$OUT" ]; then
  exit 2
fi
mkdir -p "$OUT"
BASE="$(basename "$PROTO" .proto)"
printf '%s\n' '// generated' > "$OUT/$BASE.pb.dart"
''');
  Process.runSync('chmod', <String>['+x', path]);
  return path;
}

String _writeFakeProtocGenDartExecutable(Directory tempRoot) {
  if (Platform.isWindows) {
    final path = p.join(tempRoot.path, 'protoc-gen-dart.bat');
    File(path).writeAsStringSync('''
@echo off
exit /b 0
''');
    return path;
  }

  final path = p.join(tempRoot.path, 'protoc-gen-dart');
  File(path).writeAsStringSync('''
#!/usr/bin/env sh
exit 0
''');
  Process.runSync('chmod', <String>['+x', path]);
  return path;
}

Map<String, String> _environmentWithPathPrefix(String pathPrefix) {
  final env = Map<String, String>.from(Platform.environment);
  final separator = Platform.isWindows ? ';' : ':';
  final existing = env['PATH'] ?? '';
  env['PATH'] = existing.isEmpty
      ? pathPrefix
      : '$pathPrefix$separator$existing';
  return env;
}

void main() {
  test('global help exits with code 0', () async {
    final result = await _runCli(<String>['--help']);
    expect(result.exitCode, 0);
    expect(result.stdout.toString(), contains('Usage:'));
    expect(result.stdout.toString(), contains('Commands:'));
  });

  test('command help exits with code 0', () async {
    final result = await _runCli(<String>['build', '--help']);
    expect(result.exitCode, 0);
    expect(
      result.stdout.toString(),
      contains('dart run dllart build [--config=<path>]'),
    );
  });

  test('unknown option is rejected', () async {
    final result = await _runCli(<String>['build', '--wat']);
    expect(result.exitCode, 2);
    expect(result.stderr.toString(), contains('Unknown option(s)'));
    expect(result.stderr.toString(), contains('--wat'));
  });

  test('extra positional arguments are rejected', () async {
    final result = await _runCli(<String>['init', 'unexpected']);
    expect(result.exitCode, 2);
    expect(
      result.stderr.toString(),
      contains('accepts at most 0 positional argument(s)'),
    );
  });

  test('create generates scaffold with config and source', () async {
    final tempRoot = await Directory.systemTemp.createTemp('dllart_cli_test_');
    addTearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    final projectPath = p.join(tempRoot.path, 'sample_module');
    final result = await _runCli(<String>['create', projectPath]);
    expect(result.exitCode, 0);

    final projectDir = Directory(projectPath);
    final configFile = File(p.join(projectDir.path, 'dllart.json'));
    final pubspecFile = File(p.join(projectDir.path, 'pubspec.yaml'));
    final sourceFile = File(p.join(projectDir.path, 'lib', 'module.dart'));
    final annotationsFile = File(
      p.join(projectDir.path, 'lib', 'dllart_annotations.dart'),
    );
    final bridgeSource = File(
      p.join(projectDir.path, 'native', 'dllart_bridge.c'),
    );
    final bridgeHeader = File(
      p.join(projectDir.path, 'native', 'dllart_bridge.h'),
    );

    expect(projectDir.existsSync(), isTrue);
    expect(configFile.existsSync(), isTrue);
    expect(pubspecFile.existsSync(), isTrue);
    expect(sourceFile.existsSync(), isTrue);
    expect(annotationsFile.existsSync(), isFalse);
    expect(bridgeSource.existsSync(), isTrue);
    expect(bridgeHeader.existsSync(), isTrue);

    final config =
        jsonDecode(configFile.readAsStringSync()) as Map<String, Object?>;
    expect(config['name'], 'sample_module');
    expect(config['source'], 'lib/module.dart');
    expect(config['output'], 'build');

    final pubspec = pubspecFile.readAsStringSync();
    expect(pubspec, contains('dependencies:'));
    expect(pubspec, contains('dllart:'));
    expect(pubspec, contains('path:'));
    expect(pubspec, contains(_repoRoot.replaceAll('\\', '/')));

    final source = sourceFile.readAsStringSync();
    expect(
      source,
      contains("import 'package:dllart/dllart_annotations.dart';"),
    );
  });

  test(
    'create --dependency=version keeps versioned pubspec dependency',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'dllart_cli_dep_version_',
      );
      addTearDown(() {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      });

      final projectPath = p.join(tempRoot.path, 'sample_module_versioned');
      final result = await _runCli(<String>[
        'create',
        projectPath,
        '--dependency=version',
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}\n${result.stdout}');

      final pubspec = File(
        p.join(projectPath, 'pubspec.yaml'),
      ).readAsStringSync();
      expect(pubspec, contains('dependencies:'));
      expect(pubspec, contains(RegExp(r'dllart:\s*\^[0-9]+\.[0-9]+\.[0-9]+')));
      expect(pubspec, isNot(contains('path:')));
    },
  );

  test('init bootstraps native bridge files in existing directory', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'dllart_init_native_',
    );
    addTearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    final projectDir = Directory(p.join(tempRoot.path, 'existing_project'))
      ..createSync(recursive: true);

    final result = await _runCli(<String>[
      'init',
      '--name',
      'native_init_mod',
      '--force',
    ], workingDirectory: projectDir.path);
    expect(result.exitCode, 0, reason: '${result.stderr}\n${result.stdout}');

    expect(
      File(p.join(projectDir.path, 'native', 'dllart_bridge.c')).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(projectDir.path, 'native', 'dllart_bridge.h')).existsSync(),
      isTrue,
    );
  });

  test(
    'doctor does not warn about package_config for init-only project context',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'dllart_doctor_init_only_',
      );
      addTearDown(() {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      });

      final projectDir = Directory(p.join(tempRoot.path, 'init_only_project'))
        ..createSync(recursive: true);
      final configPath = p.join(projectDir.path, 'dllart.json');

      final init = await _runCli(<String>[
        'init',
        '--name',
        'init_only_mod',
        '--config',
        configPath,
        '--force',
      ], workingDirectory: projectDir.path);
      expect(init.exitCode, 0, reason: '${init.stderr}\n${init.stdout}');

      final doctor = await _runCli(<String>[
        'doctor',
        '--config',
        configPath,
      ], workingDirectory: projectDir.path);
      final output = '${doctor.stdout}\n${doctor.stderr}';
      expect(
        output,
        contains('Not required (no pubspec.yaml found near project context).'),
      );
      expect(output, isNot(contains('.dart_tool/package_config.json. Run')));
    },
  );

  test(
    'build with --config uses package graph from config directory',
    () async {
      final hasClang = await _hasExecutable('clang', <String>['--version']);
      if (!hasClang) {
        stderr.writeln('Skipping build test: clang is not available.');
        return;
      }

      final tempRoot = await Directory.systemTemp.createTemp(
        'dllart_cli_build_cfg_',
      );
      addTearDown(() {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      });

      final depDir = Directory(p.join(tempRoot.path, 'extra_dep'));
      depDir.createSync(recursive: true);
      Directory(p.join(depDir.path, 'lib')).createSync(recursive: true);
      File(p.join(depDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: extra_dep
version: 0.0.1
publish_to: none

environment:
  sdk: ^3.10.0
''');
      File(p.join(depDir.path, 'lib', 'extra_dep.dart')).writeAsStringSync('''
String depMarker() => 'dep-ok';
''');

      final moduleDir = Directory(p.join(tempRoot.path, 'module_project'));
      moduleDir.createSync(recursive: true);
      Directory(p.join(moduleDir.path, 'lib')).createSync(recursive: true);

      final repoPathForYaml = _repoRoot.replaceAll('\\', '/');
      File(p.join(moduleDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: module_project
publish_to: none

environment:
  sdk: ^3.10.0

dependencies:
  dllart:
    path: "$repoPathForYaml"
  extra_dep:
    path: ../extra_dep
''');

      File(p.join(moduleDir.path, 'lib', 'module.dart')).writeAsStringSync('''
import 'package:dllart/dllart_annotations.dart';
import 'package:extra_dep/extra_dep.dart';

@DllartExport()
Object? depProbe() => depMarker();
''');

      final configPath = p.join(moduleDir.path, 'dllart.json');
      File(configPath).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(<String, Object>{
          'name': 'depmod',
          'source': 'lib/module.dart',
          'output': 'build/depmod',
        }),
      );

      final localPackageConfig = File(
        p.join(moduleDir.path, '.dart_tool', 'package_config.json'),
      );
      expect(localPackageConfig.existsSync(), isFalse);

      final result = await _runCli(<String>['build', '--config', configPath]);
      expect(
        result.exitCode,
        0,
        reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
      );

      expect(localPackageConfig.existsSync(), isTrue);

      final builtLibrary = File(
        p.join(
          moduleDir.path,
          'build',
          'depmod',
          'lib',
          _libraryFileName('depmod'),
        ),
      );
      expect(builtLibrary.existsSync(), isTrue);
    },
  );

  test('proto command requires source when not configured in config', () async {
    final tempRoot = await Directory.systemTemp.createTemp('dllart_proto_cfg_');
    addTearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    final configPath = p.join(tempRoot.path, 'dllart.json');
    File(configPath).writeAsStringSync('''
{
  "name": "proto_mod",
  "source": "lib/module.dart"
}
''');

    final result = await _runCli(<String>['proto', '--config', configPath]);
    expect(result.exitCode, 2);
    expect(
      result.stderr.toString(),
      contains('Proto source is not configured'),
    );
  });

  test('proto --json generates dart files through protoc', () async {
    final tempRoot = await Directory.systemTemp.createTemp('dllart_proto_ok_');
    addTearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    final protoDir = Directory(p.join(tempRoot.path, 'proto'))
      ..createSync(recursive: true);
    final outDir = p.join(tempRoot.path, 'lib', 'generated', 'proto');
    final protoPath = p.join(protoDir.path, 'calc.proto');
    File(protoPath).writeAsStringSync('''
syntax = "proto3";
package calc;

message AddRequest {
  int64 a = 1;
  int64 b = 2;
}
''');

    final fakeProtoc = _writeFakeProtocExecutable(tempRoot);
    _writeFakeProtocGenDartExecutable(tempRoot);
    final env = _environmentWithPathPrefix(tempRoot.path);
    final result = await _runCli(<String>[
      'proto',
      '--proto',
      protoPath,
      '--out',
      outDir,
      '--protoc',
      fakeProtoc,
      '--json',
    ], environment: env);
    expect(result.exitCode, 0, reason: '${result.stderr}\n${result.stdout}');

    final payload =
        jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    expect(payload['ok'], isTrue);
    expect(payload['command'], 'proto');
    expect(payload['status'], 'ok');

    final data = payload['data'] as Map<String, Object?>;
    expect(data['proto'], contains('calc.proto'));
    expect(data['out_dir'], contains('generated/proto'));
    expect(data['generated_files'], isA<List<Object?>>());

    final generated = File(p.join(outDir, 'calc.pb.dart'));
    expect(generated.existsSync(), isTrue);
  });

  test('proto command accepts positional proto path', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'dllart_proto_positional_',
    );
    addTearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    final protoDir = Directory(p.join(tempRoot.path, 'proto'))
      ..createSync(recursive: true);
    final protoPath = p.join(protoDir.path, 'echo.proto');
    File(protoPath).writeAsStringSync('''
syntax = "proto3";
package echo;
message Echo {}
''');

    final outDir = p.join(tempRoot.path, 'lib', 'generated', 'proto');
    final fakeProtoc = _writeFakeProtocExecutable(tempRoot);
    _writeFakeProtocGenDartExecutable(tempRoot);
    final env = _environmentWithPathPrefix(tempRoot.path);

    final result = await _runCli(<String>[
      'proto',
      protoPath,
      '--out',
      outDir,
      '--protoc',
      fakeProtoc,
    ], environment: env);
    expect(result.exitCode, 0, reason: '${result.stderr}\n${result.stdout}');
    expect(File(p.join(outDir, 'echo.pb.dart')).existsSync(), isTrue);
  });

  test(
    'proto auto-detects single file in ./proto when config is missing',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'dllart_proto_auto_',
      );
      addTearDown(() {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      });

      final projectDir = Directory(p.join(tempRoot.path, 'project'))
        ..createSync(recursive: true);
      final protoDir = Directory(p.join(projectDir.path, 'proto'))
        ..createSync(recursive: true);
      File(p.join(protoDir.path, 'single.proto')).writeAsStringSync('''
syntax = "proto3";
package single;
message Ping {}
''');

      final fakeProtoc = _writeFakeProtocExecutable(tempRoot);
      _writeFakeProtocGenDartExecutable(tempRoot);
      final env = _environmentWithPathPrefix(tempRoot.path);

      final result = await _runCli(
        <String>[
          'proto',
          '--out',
          p.join('lib', 'generated', 'proto'),
          '--protoc',
          fakeProtoc,
          '--json',
        ],
        workingDirectory: projectDir.path,
        environment: env,
      );
      expect(result.exitCode, 0, reason: '${result.stderr}\n${result.stdout}');

      final payload =
          jsonDecode(result.stdout.toString()) as Map<String, Object?>;
      expect(payload['command'], 'proto');
      final data = payload['data'] as Map<String, Object?>;
      expect(data['proto'], contains('single.proto'));
      expect(
        File(
          p.join(
            projectDir.path,
            'lib',
            'generated',
            'proto',
            'single.pb.dart',
          ),
        ).existsSync(),
        isTrue,
      );
    },
  );

  test('proto command reads protobuf section from config', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'dllart_proto_cfg_ok_',
    );
    addTearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    final projectDir = Directory(p.join(tempRoot.path, 'project'))
      ..createSync(recursive: true);
    Directory(p.join(projectDir.path, 'lib')).createSync(recursive: true);
    File(p.join(projectDir.path, 'lib', 'module.dart')).writeAsStringSync('''
@DllartExport()
Object? ping() => 'pong';
''');
    Directory(p.join(projectDir.path, 'proto')).createSync(recursive: true);
    File(p.join(projectDir.path, 'proto', 'calc.proto')).writeAsStringSync('''
syntax = "proto3";
package calc;
message Ping {}
''');

    final fakeProtoc = _writeFakeProtocExecutable(tempRoot);
    _writeFakeProtocGenDartExecutable(tempRoot);
    final env = _environmentWithPathPrefix(tempRoot.path);
    final configPath = p.join(projectDir.path, 'dllart.json');
    File(configPath).writeAsStringSync('''
{
  "name": "proto_mod",
  "source": "lib/module.dart",
  "output": "build",
  "protobuf": {
    "proto": "proto/calc.proto",
    "out": "lib/generated/proto",
    "includes": ["proto"],
    "grpc": true
  }
}
''');

    final result = await _runCli(<String>[
      'proto',
      '--config',
      configPath,
      '--protoc',
      fakeProtoc,
      '--json',
    ], environment: env);
    expect(result.exitCode, 0, reason: '${result.stderr}\n${result.stdout}');

    final payload =
        jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    expect(payload['command'], 'proto');
    final data = payload['data'] as Map<String, Object?>;
    expect(data['grpc'], isTrue);
    expect((data['includes'] as List<Object?>).isNotEmpty, isTrue);

    expect(
      File(
        p.join(projectDir.path, 'lib', 'generated', 'proto', 'calc.pb.dart'),
      ).existsSync(),
      isTrue,
    );
  });

  test('logging config controls text diagnostics format and level', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'dllart_proto_logging_',
    );
    addTearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    final projectDir = Directory(p.join(tempRoot.path, 'project'))
      ..createSync(recursive: true);
    Directory(p.join(projectDir.path, 'lib')).createSync(recursive: true);
    File(p.join(projectDir.path, 'lib', 'module.dart')).writeAsStringSync('''
@DllartExport()
Object? ping() => 'pong';
''');
    Directory(p.join(projectDir.path, 'proto')).createSync(recursive: true);
    File(p.join(projectDir.path, 'proto', 'calc.proto')).writeAsStringSync('''
syntax = "proto3";
package calc;
message Ping {}
''');

    final fakeProtoc = _writeFakeProtocExecutable(tempRoot);
    _writeFakeProtocGenDartExecutable(tempRoot);
    final env = _environmentWithPathPrefix(tempRoot.path);
    final configPath = p.join(projectDir.path, 'dllart.json');
    File(configPath).writeAsStringSync('''
{
  "name": "proto_mod",
  "source": "lib/module.dart",
  "output": "build",
  "logging": {
    "format": "json",
    "level": "info"
  },
  "protobuf": {
    "proto": "proto/calc.proto",
    "out": "lib/generated/proto"
  }
}
''');

    final jsonLogs = await _runCli(<String>[
      'proto',
      '--config',
      configPath,
      '--protoc',
      fakeProtoc,
    ], environment: env);
    expect(
      jsonLogs.exitCode,
      0,
      reason: '${jsonLogs.stderr}\n${jsonLogs.stdout}',
    );
    expect(
      jsonLogs.stdout.toString(),
      contains('"message":"Generating Dart protobuf sources..."'),
    );

    File(configPath).writeAsStringSync('''
{
  "name": "proto_mod",
  "source": "lib/module.dart",
  "output": "build",
  "logging": {
    "format": "json",
    "level": "warn"
  },
  "protobuf": {
    "proto": "proto/calc.proto",
    "out": "lib/generated/proto"
  }
}
''');

    final suppressedInfo = await _runCli(<String>[
      'proto',
      '--config',
      configPath,
      '--protoc',
      fakeProtoc,
    ], environment: env);
    expect(
      suppressedInfo.exitCode,
      0,
      reason: '${suppressedInfo.stderr}\n${suppressedInfo.stdout}',
    );
    expect(
      suppressedInfo.stdout.toString(),
      isNot(contains('Generating Dart protobuf sources...')),
    );
  });

  test(
    'build/integrate --json provide machine-readable success payloads',
    () async {
      final hasClang = await _hasExecutable('clang', <String>['--version']);
      if (!hasClang) {
        stderr.writeln(
          'Skipping build/integrate json payload test: clang is not available.',
        );
        return;
      }

      final tempRoot = await Directory.systemTemp.createTemp('dllart_json_ok_');
      addTearDown(() {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      });

      final projectPath = p.join(tempRoot.path, 'json_mod');
      final configPath = p.join(projectPath, 'dllart.json');

      final created = await _runCli(<String>[
        'create',
        projectPath,
        '--local-path-dependency',
      ]);
      expect(
        created.exitCode,
        0,
        reason: '${created.stderr}\n${created.stdout}',
      );

      final build = await _runCli(<String>[
        'build',
        '--config',
        configPath,
        '--json',
      ]);
      expect(build.exitCode, 0, reason: '${build.stderr}\n${build.stdout}');
      final buildPayload =
          jsonDecode(build.stdout.toString()) as Map<String, Object?>;
      expect(buildPayload['ok'], isTrue);
      expect(buildPayload['command'], 'build');
      expect(buildPayload['status'], 'ok');
      final buildData = buildPayload['data'] as Map<String, Object?>;
      expect(buildData['module'], 'json_mod');
      expect(buildData['library'], contains(_libraryFileName('json_mod')));
      expect(buildData['exports'], isA<List<Object?>>());

      final integrate = await _runCli(<String>[
        'integrate',
        '--config',
        configPath,
        '--json',
      ]);
      expect(
        integrate.exitCode,
        0,
        reason: '${integrate.stderr}\n${integrate.stdout}',
      );
      final integratePayload =
          jsonDecode(integrate.stdout.toString()) as Map<String, Object?>;
      expect(integratePayload['ok'], isTrue);
      expect(integratePayload['command'], 'integrate');
      expect(integratePayload['status'], 'ok');
      final integrateData = integratePayload['data'] as Map<String, Object?>;
      expect(integrateData['module'], 'json_mod');
      expect(
        integrateData['library_file'],
        contains(_libraryFileName('json_mod')),
      );

      final snippets = integrateData['snippets'] as Map<String, Object?>;
      expect(snippets['c_compile'], contains('clang your_app.c'));
      expect(snippets['python_symbols'], isA<List<Object?>>());
    },
  );

  test(
    'verify --json reports aggregated C/Python/C# scaffold checks',
    () async {
      final hasClang = await _hasExecutable('clang', <String>['--version']);
      if (!hasClang) {
        stderr.writeln('Skipping verify json test: clang is not available.');
        return;
      }

      final tempRoot = await Directory.systemTemp.createTemp(
        'dllart_verify_ok_',
      );
      addTearDown(() {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      });

      final projectPath = p.join(tempRoot.path, 'verify_mod');
      final configPath = p.join(projectPath, 'dllart.json');

      final created = await _runCli(<String>['create', projectPath]);
      expect(
        created.exitCode,
        0,
        reason: '${created.stderr}\n${created.stdout}',
      );

      final build = await _runCli(<String>['build', '--config', configPath]);
      expect(build.exitCode, 0, reason: '${build.stderr}\n${build.stdout}');

      final packagePython = await _runCli(<String>[
        'package',
        'python',
        '--config',
        configPath,
      ]);
      expect(
        packagePython.exitCode,
        0,
        reason: '${packagePython.stderr}\n${packagePython.stdout}',
      );

      final packageCSharp = await _runCli(<String>[
        'package',
        'csharp',
        '--config',
        configPath,
      ]);
      expect(
        packageCSharp.exitCode,
        0,
        reason: '${packageCSharp.stderr}\n${packageCSharp.stdout}',
      );

      final verify = await _runCli(<String>[
        'verify',
        '--config',
        configPath,
        '--target=all',
        '--json',
      ]);
      expect(verify.exitCode, 0, reason: '${verify.stderr}\n${verify.stdout}');
      final payload =
          jsonDecode(verify.stdout.toString()) as Map<String, Object?>;
      expect(payload['ok'], isTrue);
      expect(payload['command'], 'verify');
      expect(payload['status'], 'ok');
      final data = payload['data'] as Map<String, Object?>;
      expect(data['target'], 'all');
      final summary = data['summary'] as Map<String, Object?>;
      expect(summary['failures'], 0);
    },
  );

  test('package is idempotent across targets without --force', () async {
    final hasClang = await _hasExecutable('clang', <String>['--version']);
    if (!hasClang) {
      stderr.writeln(
        'Skipping package idempotency test: clang is not available.',
      );
      return;
    }

    final tempRoot = await Directory.systemTemp.createTemp(
      'dllart_package_idempotent_',
    );
    addTearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    final projectPath = p.join(tempRoot.path, 'idempotent_mod');
    final configPath = p.join(projectPath, 'dllart.json');

    final created = await _runCli(<String>['create', projectPath]);
    expect(created.exitCode, 0, reason: '${created.stderr}\n${created.stdout}');

    final built = await _runCli(<String>['build', '--config', configPath]);
    expect(built.exitCode, 0, reason: '${built.stderr}\n${built.stdout}');

    final pythonPackage = await _runCli(<String>[
      'package',
      'python',
      '--config',
      configPath,
    ]);
    expect(
      pythonPackage.exitCode,
      0,
      reason: '${pythonPackage.stderr}\n${pythonPackage.stdout}',
    );

    final csharpPackage = await _runCli(<String>[
      'package',
      'csharp',
      '--config',
      configPath,
    ]);
    expect(
      csharpPackage.exitCode,
      0,
      reason: '${csharpPackage.stderr}\n${csharpPackage.stdout}',
    );

    expect(
      File(
        p.join(projectPath, 'build', 'package', 'python', 'bindings.py'),
      ).existsSync(),
      isTrue,
    );
    expect(
      File(
        p.join(projectPath, 'build', 'package', 'csharp', 'DllartClient.cs'),
      ).existsSync(),
      isTrue,
    );
  });

  test(
    'package --target=all --auto-build reports aggregated env blockers',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'dllart_package_blockers_',
      );
      addTearDown(() {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      });

      final projectDir = Directory(p.join(tempRoot.path, 'package_blockers'))
        ..createSync(recursive: true);
      final configPath = p.join(projectDir.path, 'dllart.json');

      final init = await _runCli(<String>[
        'init',
        '--name',
        'package_blockers_mod',
        '--config',
        configPath,
        '--force',
      ], workingDirectory: projectDir.path);
      expect(init.exitCode, 0, reason: '${init.stderr}\n${init.stdout}');

      final packageResult = await _runCli(
        <String>[
          'package',
          '--target=all',
          '--config',
          configPath,
          '--auto-build',
        ],
        workingDirectory: projectDir.path,
        environment: <String, String>{
          'ANDROID_NDK_HOME': '',
          'DLLART_IOS_GEN_SNAPSHOT_ARM64': '/missing/ios/arm64/gen_snapshot',
          'DLLART_IOS_GEN_SNAPSHOT_X64': '/missing/ios/x64/gen_snapshot',
        },
      );
      expect(packageResult.exitCode, 2);
      final output = '${packageResult.stdout}\n${packageResult.stderr}';
      expect(
        output,
        contains('Package auto-build preflight failed for target `all`.'),
      );
      expect(output, contains('Blocking environment/toolchain issues:'));
      expect(output, contains('[android]'));
      expect(output, contains('ANDROID_NDK_HOME is required'));
      expect(output, contains('[ios]'));
    },
  );

  test('build --json emits structured error payload', () async {
    final missingConfig = p.join(
      Directory.systemTemp.path,
      'dllart_missing_${DateTime.now().microsecondsSinceEpoch}.json',
    );

    final result = await _runCli(<String>[
      'build',
      '--config',
      missingConfig,
      '--json',
    ]);

    expect(result.exitCode, 2);
    final payload =
        jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    expect(payload['ok'], isFalse);
    expect(payload['command'], 'build');
    expect(payload['exit_code'], 2);

    final error = payload['error'] as Map<String, Object?>;
    expect(error['type'], 'ToolError');
    expect(error['message'].toString(), contains('Config file not found'));
  });

  test('doctor --json prints machine-readable report', () async {
    final result = await _runCli(<String>['doctor', '--json']);
    expect(result.exitCode, anyOf(0, 1));

    final payload =
        jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    expect(payload['command'], 'doctor');
    expect(payload['status'], anyOf('ok', 'warn', 'fail'));

    final data = payload['data'] as Map<String, Object?>;
    expect(data['summary'], isA<Map<String, Object?>>());
    expect(data['items'], isA<List<Object?>>());
  });

  test('config with unknown fields is rejected with location', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'dllart_cfg_validate_',
    );
    addTearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    final configPath = p.join(tempRoot.path, 'dllart.json');
    File(configPath).writeAsStringSync('''
{
  "name": "bad",
  "source": "lib/module.dart",
  "wat": true
}
''');

    final result = await _runCli(<String>['build', '--config', configPath]);
    expect(result.exitCode, 2);
    expect(result.stderr.toString(), contains('Invalid config'));
    expect(result.stderr.toString(), contains('doc/schema/dllart.schema.json'));
    expect(
      RegExp(r'dllart\.json:\d+:\d+').hasMatch(result.stderr.toString()),
      isTrue,
    );
  });

  test('malformed config JSON is rejected with line/column', () async {
    final tempRoot = await Directory.systemTemp.createTemp('dllart_cfg_parse_');
    addTearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    final configPath = p.join(tempRoot.path, 'dllart.json');
    File(configPath).writeAsStringSync('''
{
  "name": "bad",
  "source": "lib/module.dart",
''');

    final result = await _runCli(<String>['build', '--config', configPath]);
    expect(result.exitCode, 2);
    expect(result.stderr.toString(), contains('Invalid JSON in'));
    expect(
      RegExp(r'dllart\.json:\d+:\d+').hasMatch(result.stderr.toString()),
      isTrue,
    );
  });
}
