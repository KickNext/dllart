import 'dart:convert';
import 'dart:io';

import 'package:dllart/src/cli/app.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

ParsedArgs _args(
  Map<String, String> options, [
  List<String> positional = const <String>[],
]) {
  return ParsedArgs(positional, options);
}

String _pathSeparator() => Platform.isWindows ? ';' : ':';

String _scriptFileName(String baseName) {
  if (Platform.isWindows) {
    return '$baseName.bat';
  }
  return baseName;
}

String _scriptBody(String body) {
  if (Platform.isWindows) {
    return '@echo off\r\n$body\r\n';
  }
  return '#!/usr/bin/env sh\nset -eu\n$body\n';
}

Directory _pickWritablePathDir() {
  final paths = (Platform.environment['PATH'] ?? '').split(_pathSeparator());
  for (final raw in paths) {
    final dirPath = raw.trim();
    if (dirPath.isEmpty) {
      continue;
    }
    final dir = Directory(dirPath);
    if (!dir.existsSync()) {
      continue;
    }
    final probe = File(
      p.join(
        dirPath,
        '.dllart_path_probe_${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    try {
      probe.writeAsStringSync('probe');
      probe.deleteSync();
      return dir;
    } catch (_) {
      if (probe.existsSync()) {
        probe.deleteSync();
      }
    }
  }
  throw StateError('No writable directory found in PATH');
}

File _installPathExecutable({
  required String commandName,
  required String scriptBody,
  bool executable = true,
}) {
  final dir = _pickWritablePathDir();
  final fileName = _scriptFileName(commandName);
  final file = File(p.join(dir.path, fileName));
  file.writeAsStringSync(_scriptBody(scriptBody));
  if (!Platform.isWindows && executable) {
    Process.runSync('chmod', <String>['+x', file.path]);
  }
  return file;
}

void main() {
  tearDown(() {
    exitCode = 0;
  });

  group('cli dispatch edge cases', () {
    test('runCli executes help branch without exiting', () async {
      await DllartCliTestApi.runCli(<String>['--help']);
    });

    test('runCliForTesting returns JSON ToolError exit code', () async {
      final missing = p.join(
        Directory.systemTemp.path,
        'dllart_missing_${DateTime.now().microsecondsSinceEpoch}.json',
      );
      final code = await DllartCliTestApi.runCliForTesting(<String>[
        'build',
        '--json',
        '--config',
        missing,
      ]);
      expect(code, 2);
    });

    test('runCliForTesting returns JSON ProcessException exit code', () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'dllart_proc_exception_',
      );
      addTearDown(() {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      });

      final protoPath = p.join(tempRoot.path, 'sample.proto');
      File(protoPath).writeAsStringSync('''
syntax = "proto3";
message Ping {
  string msg = 1;
}
''');

      final nonExecutable = File(p.join(tempRoot.path, 'fake_protoc'));
      nonExecutable.writeAsStringSync('echo fake');

      final plugin = _installPathExecutable(
        commandName: 'protoc-gen-dart',
        scriptBody: 'exit 0',
      );
      addTearDown(() {
        if (plugin.existsSync()) {
          plugin.deleteSync();
        }
      });

      final code = await DllartCliTestApi.runCliForTesting(<String>[
        'proto',
        '--json',
        '--proto',
        protoPath,
        '--protoc',
        nonExecutable.path,
      ]);
      expect(code, 3);
    });
  });

  group('project/workflow edge cases', () {
    test('create falls back to --name as project path', () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'dllart_create_name_',
      );
      addTearDown(() {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      });

      final moduleDir = p.join(tempRoot.path, 'named_module');
      await DllartCliTestApi.commandCreate(
        _args(<String, String>{'name': moduleDir, 'force': 'true'}),
      );

      expect(Directory(moduleDir).existsSync(), isTrue);
      expect(File(p.join(moduleDir, 'dllart.json')).existsSync(), isTrue);
    });

    test('create fails for non-empty directory without --force', () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'dllart_create_nonempty_',
      );
      addTearDown(() {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      });

      final project = Directory(p.join(tempRoot.path, 'project'))
        ..createSync(recursive: true);
      File(p.join(project.path, 'keep.txt')).writeAsStringSync('x');

      await expectLater(
        DllartCliTestApi.commandCreate(
          _args(<String, String>{'path': project.path}),
        ),
        throwsA(isA<ToolError>()),
      );
    });

    test(
      'init rejects empty --name and existing config without force',
      () async {
        final tempRoot = await Directory.systemTemp.createTemp(
          'dllart_init_edge_',
        );
        addTearDown(() {
          if (tempRoot.existsSync()) {
            tempRoot.deleteSync(recursive: true);
          }
        });

        await expectLater(
          DllartCliTestApi.commandInit(
            _args(<String, String>{'name': '   ', 'force': 'true'}),
          ),
          throwsA(isA<ToolError>()),
        );

        final configPath = p.join(tempRoot.path, 'dllart.json');
        File(configPath).writeAsStringSync('{}');
        final sourcePath = p.join(tempRoot.path, 'lib', 'module.dart');
        await expectLater(
          DllartCliTestApi.commandInit(
            _args(<String, String>{
              'name': 'edge_mod',
              'source': sourcePath,
              'config': configPath,
            }),
          ),
          throwsA(isA<ToolError>()),
        );
      },
    );

    test(
      'workflow validates conflicting tool flags and existing output',
      () async {
        final tempRoot = await Directory.systemTemp.createTemp(
          'dllart_workflow_edge_',
        );
        addTearDown(() {
          if (tempRoot.existsSync()) {
            tempRoot.deleteSync(recursive: true);
          }
        });

        final sourcePath = p.join(tempRoot.path, 'lib', 'module.dart');
        Directory(p.dirname(sourcePath)).createSync(recursive: true);
        File(sourcePath).writeAsStringSync('''
@DllartExport()
Object? ping() => 'pong';
''');

        final configPath = p.join(tempRoot.path, 'dllart.json');
        File(configPath).writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(<String, Object>{
            'name': 'workflow_mod',
            'source': 'lib/module.dart',
            'output': 'build',
          }),
        );

        final workflowPath = p.join(
          tempRoot.path,
          '.github',
          'workflows',
          'ci.yml',
        );
        await expectLater(
          DllartCliTestApi.commandWorkflow(
            _args(<String, String>{
              'config': configPath,
              'output': workflowPath,
              'global-tool': 'true',
              'local-tool': 'true',
              'force': 'true',
            }),
          ),
          throwsA(isA<ToolError>()),
        );

        File(workflowPath).createSync(recursive: true);
        await expectLater(
          DllartCliTestApi.commandWorkflow(
            _args(<String, String>{
              'config': configPath,
              'output': workflowPath,
            }),
          ),
          throwsA(isA<ToolError>()),
        );
      },
    );
  });

  group('runtime and config helpers', () {
    test('manifest and text helpers handle invalid/valid inputs', () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'dllart_runtime_helpers_',
      );
      addTearDown(() {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      });

      final missingManifest = p.join(tempRoot.path, 'missing.json');
      expect(DllartCliTestApi.libraryPathFromManifest(missingManifest), isNull);

      final malformedManifest = File(p.join(tempRoot.path, 'malformed.json'))
        ..writeAsStringSync('{bad json');
      expect(
        DllartCliTestApi.libraryPathFromManifest(malformedManifest.path),
        isNull,
      );

      final manifest = File(p.join(tempRoot.path, 'artifact.json'))
        ..writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(<String, Object>{
            'paths': <String, Object>{'library': './lib/libcalc.dylib'},
          }),
        );
      expect(
        DllartCliTestApi.libraryPathFromManifest(manifest.path),
        p.normalize('./lib/libcalc.dylib'),
      );

      expect(DllartCliTestApi.asText(null), '');
      expect(DllartCliTestApi.asText(42), '42');
      expect(
        DllartCliTestApi.firstNonEmptyLine('\n  \n hello \nworld'),
        'hello',
      );
      expect(DllartCliTestApi.firstNonEmptyLine(' \n\t\n '), isNull);
      expect(DllartCliTestApi.lineNumberAt('a\nb\nc', 4), 3);

      final emptySummary = DllartCliTestApi.processFailureSummary(
        'cmd',
        ProcessResult(1, 2, '', ''),
      );
      expect(emptySummary, contains('cmd failed with exit code 2'));

      final detailedSummary = DllartCliTestApi.processFailureSummary(
        'cmd',
        ProcessResult(1, 7, '', 'boom'),
      );
      expect(detailedSummary, contains('cmd failed (7):'));
      expect(detailedSummary, contains('boom'));
    });

    test('package config helpers resolve package roots and paths', () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'dllart_pkg_cfg_helpers_',
      );
      addTearDown(() {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      });

      final packageDir = Directory(p.join(tempRoot.path, 'dllart_pkg'))
        ..createSync(recursive: true);
      Directory(p.join(packageDir.path, 'native')).createSync(recursive: true);
      File(
        p.join(packageDir.path, 'native', 'dllart_bridge.c'),
      ).writeAsStringSync('/* c */');
      File(
        p.join(packageDir.path, 'native', 'dllart_bridge.h'),
      ).writeAsStringSync('/* h */');

      final configDir = Directory(p.join(tempRoot.path, '.dart_tool'))
        ..createSync(recursive: true);
      final packageConfigPath = p.join(configDir.path, 'package_config.json');
      File(packageConfigPath).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(<String, Object>{
          'configVersion': 2,
          'packages': <Object>[
            <String, Object>{
              'name': 'dllart',
              'rootUri': '../dllart_pkg',
              'packageUri': 'lib/',
              'languageVersion': '3.10',
            },
          ],
        }),
      );

      expect(
        DllartCliTestApi.dllartRootFromPackageConfig(packageConfigPath),
        p.normalize(packageDir.path),
      );

      final absoluteUri = Uri.file(packageDir.path).toString();
      expect(
        DllartCliTestApi.resolvePackageRootUriPath(
          packageConfigPath,
          absoluteUri,
        ),
        p.normalize(packageDir.path),
      );
      expect(
        DllartCliTestApi.resolvePackageRootUriPath(
          packageConfigPath,
          '../dllart_pkg',
        ),
        p.normalize(packageDir.path),
      );
      expect(
        DllartCliTestApi.resolvePackageRootUriPath(
          packageConfigPath,
          'https://example.com/pkg',
        ),
        isNull,
      );

      final nested = Directory(p.join(tempRoot.path, 'a', 'b', 'c'))
        ..createSync(recursive: true);
      final nestedConfig = p.join(
        tempRoot.path,
        'a',
        '.dart_tool',
        'package_config.json',
      );
      File(nestedConfig).createSync(recursive: true);
      expect(
        DllartCliTestApi.findNearestPackageConfig(nested.path),
        p.normalize(nestedConfig),
      );
    });

    test(
      'ensurePackageConfig generates local package config when missing',
      () async {
        final tempRoot = await Directory.systemTemp.createTemp(
          'dllart_pkg_get_',
        );
        addTearDown(() {
          if (tempRoot.existsSync()) {
            tempRoot.deleteSync(recursive: true);
          }
        });

        final sourcePath = p.join(tempRoot.path, 'lib', 'module.dart');
        File(sourcePath).createSync(recursive: true);
        File(sourcePath).writeAsStringSync('Object? ping() => null;');
        File(p.join(tempRoot.path, 'pubspec.yaml')).writeAsStringSync('''
name: pkg_get_case
version: 0.0.1
publish_to: none

environment:
  sdk: ^3.10.0
''');

        final packageConfig = await DllartCliTestApi.ensurePackageConfig(
          sourcePath: sourcePath,
          configDir: tempRoot.path,
        );
        expect(packageConfig, isNotNull);
        expect(File(packageConfig!).existsSync(), isTrue);
      },
    );

    test('runCommand wrappers work in text and json modes', () async {
      await DllartCliTestApi.runCommand(Platform.resolvedExecutable, <String>[
        '--version',
      ]);
      await DllartCliTestApi.runCommandInJsonMode(
        Platform.resolvedExecutable,
        <String>['--version'],
      );
    });
  });

  group('doctor and protobuf helpers', () {
    test('doctor handles inline config errors and missing source', () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'dllart_doctor_inline_',
      );
      addTearDown(() {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      });

      exitCode = 0;
      await DllartCliTestApi.commandDoctor(
        _args(<String, String>{'name': 'x'}),
      );
      expect(exitCode, 1);

      exitCode = 0;
      final missingSource = p.join(tempRoot.path, 'lib', 'missing.dart');
      await DllartCliTestApi.commandDoctor(
        _args(<String, String>{'name': 'x', 'source': missingSource}),
      );
      expect(exitCode, 1);
    });

    test('doctor json branch works for inline source', () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'dllart_doctor_json_',
      );
      addTearDown(() {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      });

      final sourcePath = p.join(tempRoot.path, 'lib', 'module.dart');
      File(sourcePath).createSync(recursive: true);
      File(sourcePath).writeAsStringSync('''
@DllartExport()
Object? ping() => 'pong';
''');

      exitCode = 0;
      await DllartCliTestApi.commandDoctor(
        _args(<String, String>{
          'name': 'doctor_mod',
          'source': sourcePath,
          'output': p.join(tempRoot.path, 'build'),
          'json': 'true',
        }),
      );
      expect(exitCode, anyOf(0, 1));
    });

    test(
      'protobuf doctor checks cover success/failure and version warnings',
      () async {
        final tempRoot = await Directory.systemTemp.createTemp(
          'dllart_pb_doctor_',
        );
        addTearDown(() {
          if (tempRoot.existsSync()) {
            tempRoot.deleteSync(recursive: true);
          }
        });

        final protoDir = Directory(p.join(tempRoot.path, 'proto'))
          ..createSync(recursive: true);
        final protoPath = p.join(protoDir.path, 'calc.proto');
        File(protoPath).writeAsStringSync('''
syntax = "proto3";
message Calc { int32 v = 1; }
''');

        final reportNoProto = DoctorReport();
        final noProtoLoaded = LoadedConfig(
          config: DllartConfig(
            name: 'no_pb',
            source: 'lib/module.dart',
            output: 'build',
            targets: List<String>.from(DllartConfig.defaultTargets),
          ),
          configPath: p.join(tempRoot.path, 'dllart.json'),
        );
        await DllartCliTestApi.appendProtobufDoctorChecks(
          reportNoProto,
          noProtoLoaded,
        );
        expect(reportNoProto.items, isEmpty);

        final plugin = _installPathExecutable(
          commandName: 'protoc-gen-dart',
          scriptBody: 'exit 0',
        );
        addTearDown(() {
          if (plugin.existsSync()) {
            plugin.deleteSync();
          }
        });

        final protocOk =
            File(p.join(tempRoot.path, _scriptFileName('protoc_ok')))
              ..writeAsStringSync(_scriptBody('echo libprotoc 99.1'))
              ..setLastModifiedSync(DateTime.now());
        if (!Platform.isWindows) {
          Process.runSync('chmod', <String>['+x', protocOk.path]);
        }

        final protocFail =
            File(p.join(tempRoot.path, _scriptFileName('protoc_fail')))
              ..writeAsStringSync(
                _scriptBody(Platform.isWindows ? 'exit /b 9' : 'exit 9'),
              )
              ..setLastModifiedSync(DateTime.now());
        if (!Platform.isWindows) {
          Process.runSync('chmod', <String>['+x', protocFail.path]);
        }

        final successLoaded = LoadedConfig(
          config: DllartConfig(
            name: 'pb_ok',
            source: 'lib/module.dart',
            output: 'build',
            targets: List<String>.from(DllartConfig.defaultTargets),
            protobuf: DllartProtobufConfig(
              proto: p.relative(protoPath, from: tempRoot.path),
              out: 'lib/generated/proto',
              includes: <String>['proto'],
              grpc: true,
              protoc: protocOk.path,
            ),
          ),
          configPath: p.join(tempRoot.path, 'dllart.json'),
        );

        final successReport = DoctorReport();
        await DllartCliTestApi.appendProtobufDoctorChecks(
          successReport,
          successLoaded,
        );
        expect(successReport.failCount, 0);
        expect(successReport.okCount, greaterThan(0));

        final warnLoaded = LoadedConfig(
          config: DllartConfig(
            name: 'pb_warn',
            source: 'lib/module.dart',
            output: 'build',
            targets: List<String>.from(DllartConfig.defaultTargets),
            protobuf: DllartProtobufConfig(
              proto: p.relative(protoPath, from: tempRoot.path),
              out: 'lib/generated/proto',
              includes: <String>['proto', 'missing_include'],
              grpc: false,
              protoc: protocFail.path,
            ),
          ),
          configPath: p.join(tempRoot.path, 'dllart.json'),
        );
        final warnReport = DoctorReport();
        await DllartCliTestApi.appendProtobufDoctorChecks(
          warnReport,
          warnLoaded,
        );
        expect(warnReport.warnCount, greaterThan(0));

        plugin.deleteSync();
        final failLoaded = LoadedConfig(
          config: DllartConfig(
            name: 'pb_fail',
            source: 'lib/module.dart',
            output: 'build',
            targets: List<String>.from(DllartConfig.defaultTargets),
            protobuf: DllartProtobufConfig(
              proto: 'proto/missing.proto',
              out: 'lib/generated/proto',
              includes: <String>['proto'],
              grpc: false,
              protoc: p.join(tempRoot.path, 'missing-protoc'),
            ),
          ),
          configPath: p.join(tempRoot.path, 'dllart.json'),
        );
        final failReport = DoctorReport();
        await DllartCliTestApi.appendProtobufDoctorChecks(
          failReport,
          failLoaded,
        );
        expect(failReport.failCount, greaterThan(0));
      },
    );
  });

  group('proto command and helpers', () {
    test('proto helper functions parse and infer sources', () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'dllart_proto_helpers_',
      );
      addTearDown(() {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      });

      expect(DllartCliTestApi.parsePathList(' a, b ,, c '), <String>[
        'a',
        'b',
        'c',
      ]);
      expect(DllartCliTestApi.firstNonEmpty(<String?>[' ', null, ' x ']), 'x');
      expect(
        DllartCliTestApi.resolvePathFromBase(tempRoot.path, 'proto/a.proto'),
        p.join(tempRoot.path, 'proto', 'a.proto'),
      );

      final protoDir = Directory(p.join(tempRoot.path, 'proto'))
        ..createSync(recursive: true);
      final one = File(p.join(protoDir.path, 'single.proto'))
        ..writeAsStringSync('syntax = "proto3";');
      expect(DllartCliTestApi.findProtoSourcesUnder(protoDir.path), <String>[
        p.normalize(one.path),
      ]);
      expect(
        DllartCliTestApi.inferProtoSource(tempRoot.path),
        p.normalize(one.path),
      );

      final second = File(p.join(protoDir.path, 'module.proto'))
        ..writeAsStringSync('syntax = "proto3";');
      final third = File(p.join(protoDir.path, 'calc.proto'))
        ..writeAsStringSync('syntax = "proto3";');
      expect(
        DllartCliTestApi.inferProtoSource(tempRoot.path, moduleName: 'calc'),
        p.normalize(third.path),
      );

      second.deleteSync();
      await expectLater(
        () => DllartCliTestApi.inferProtoSource(tempRoot.path),
        throwsA(isA<ToolError>()),
      );
    });

    test('commandProto runs in json/text mode and validates input', () async {
      final tempRoot = await Directory.systemTemp.createTemp('dllart_proto_');
      addTearDown(() {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      });

      final plugin = _installPathExecutable(
        commandName: 'protoc-gen-dart',
        scriptBody: 'exit 0',
      );
      addTearDown(() {
        if (plugin.existsSync()) {
          plugin.deleteSync();
        }
      });

      final protoc = File(p.join(tempRoot.path, _scriptFileName('fake_protoc')))
        ..writeAsStringSync(
          _scriptBody(
            Platform.isWindows
                ? r'''
setlocal enabledelayedexpansion
set "OUT="
set "PROTO="
for %%A in (%*) do (
  set "ARG=%%~A"
  if /I "!ARG:~0,11!"=="--dart_out=" (
    set "OUT=!ARG:~11!"
    if /I "!OUT:~0,5!"=="grpc:" set "OUT=!OUT:~5!"
  )
  for %%F in ("!ARG!") do (
    if /I "%%~xF"==".proto" set "PROTO=!ARG!"
  )
)
if "%OUT%"=="" exit /b 2
if not exist "%OUT%" mkdir "%OUT%"
for %%F in ("%PROTO%") do set "BASE=%%~nF"
> "%OUT%\%BASE%.pb.dart" echo // generated
exit /b 0
'''
                : r'''
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
mkdir -p "$OUT"
BASE="$(basename "$PROTO" .proto)"
printf '%s\n' '// generated' > "$OUT/$BASE.pb.dart"
''',
          ),
        );
      if (!Platform.isWindows) {
        Process.runSync('chmod', <String>['+x', protoc.path]);
      }

      final protoDir = Directory(p.join(tempRoot.path, 'proto'))
        ..createSync(recursive: true);
      final protoPath = p.join(protoDir.path, 'echo.proto');
      File(protoPath).writeAsStringSync('''
syntax = "proto3";
message Echo { string msg = 1; }
''');

      final outDir = p.join(tempRoot.path, 'lib', 'generated', 'proto');
      await DllartCliTestApi.commandProto(
        _args(<String, String>{
          'proto': protoPath,
          'out': outDir,
          'protoc': protoc.path,
          'json': 'true',
        }),
      );
      expect(File(p.join(outDir, 'echo.pb.dart')).existsSync(), isTrue);

      await DllartCliTestApi.commandProto(
        _args(<String, String>{
          'proto': protoPath,
          'out': outDir,
          'protoc': protoc.path,
          'grpc': 'true',
        }),
      );
      expect(
        DllartCliTestApi.collectGeneratedProtoFiles(outDir),
        contains(p.join(outDir, 'echo.pb.dart')),
      );

      final badExt = p.join(tempRoot.path, 'bad.txt');
      File(badExt).writeAsStringSync('x');
      await expectLater(
        DllartCliTestApi.commandProto(
          _args(<String, String>{'proto': badExt, 'protoc': protoc.path}),
        ),
        throwsA(isA<ToolError>()),
      );

      final missingProto = p.join(tempRoot.path, 'missing.proto');
      await expectLater(
        DllartCliTestApi.commandProto(
          _args(<String, String>{'proto': missingProto, 'protoc': protoc.path}),
        ),
        throwsA(isA<ToolError>()),
      );
    });

    test(
      'loadConfigForProto resolves explicit and default config paths',
      () async {
        final tempRoot = await Directory.systemTemp.createTemp(
          'dllart_proto_cfg_load_',
        );
        addTearDown(() {
          if (tempRoot.existsSync()) {
            tempRoot.deleteSync(recursive: true);
          }
        });

        final configPath = p.join(tempRoot.path, 'dllart.json');
        File(configPath).writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(<String, Object>{
            'name': 'proto_mod',
            'source': 'lib/module.dart',
            'output': 'build',
          }),
        );

        final explicit = DllartCliTestApi.loadConfigForProto(
          _args(<String, String>{'config': configPath}),
        );
        expect(explicit, isNotNull);

        final oldCurrent = Directory.current;
        try {
          Directory.current = tempRoot.path;
          final detected = DllartCliTestApi.loadConfigForProto(
            _args(<String, String>{}),
          );
          expect(detected, isNotNull);
        } finally {
          Directory.current = oldCurrent;
        }
      },
    );
  });

  group('ABI contract helpers', () {
    test('parse helpers validate rows and scalar conversions', () {
      final parsed = DllartCliTestApi.parseAbiContractExportsForTesting(
        <dynamic>[
          <String, Object?>{
            'name': 'add',
            'arity': 1,
            'supports_i64_2': true,
            'i64_2_method_id': 0,
          },
        ],
      );
      expect(parsed.single['name'], 'add');
      expect(parsed.single['supports_i64_2'], isTrue);

      expect(
        () => DllartCliTestApi.parseAbiContractExportsForTesting(<dynamic>[
          'bad',
        ]),
        throwsA(isA<ToolError>()),
      );
      expect(
        () => DllartCliTestApi.parseAbiContractExportsForTesting(<dynamic>[
          <String, Object?>{'name': '', 'arity': 1},
        ]),
        throwsA(isA<ToolError>()),
      );

      expect(DllartCliTestApi.toIntForTesting(7), 7);
      expect(DllartCliTestApi.toIntForTesting(7.8), 7);
      expect(DllartCliTestApi.toIntForTesting('x'), isNull);

      expect(
        DllartCliTestApi.prependLibrarySearchPath('/tmp/lib', null),
        p.normalize('/tmp/lib'),
      );
      expect(
        DllartCliTestApi.prependLibrarySearchPath('/tmp/lib', 'A'),
        contains('A'),
      );

      final cSource = DllartCliTestApi.generateAbiContractCTestForTesting(
        moduleName: 'calc',
        modulePrefix: 'calc_dllart',
        exports: <Map<String, Object?>>[
          <String, Object?>{
            'name': 'add',
            'arity': 1,
            'supports_i64_2': true,
            'i64_2_method_id': 0,
            'supports_i64_4': false,
            'supports_f64_2': false,
            'supports_bytes': false,
          },
        ],
      );
      expect(cSource, contains('#include "calc_api.h"'));
      expect(cSource, contains('calc_dllart_call_json'));
    });

    test(
      'runAbiContractTest validates manifest and returns compile failure payload',
      () async {
        final tempRoot = await Directory.systemTemp.createTemp(
          'dllart_abi_validate_',
        );
        addTearDown(() {
          if (tempRoot.existsSync()) {
            tempRoot.deleteSync(recursive: true);
          }
        });

        final output = p.join(tempRoot.path, 'out');
        final config = LoadedConfig(
          config: DllartConfig(
            name: 'abi_mod',
            source: 'lib/module.dart',
            output: 'out',
            targets: List<String>.from(DllartConfig.defaultTargets),
          ),
          configPath: p.join(tempRoot.path, 'dllart.json'),
        );

        await expectLater(
          DllartCliTestApi.runAbiContractTestForTesting(config),
          throwsA(isA<ToolError>()),
        );

        Directory(output).createSync(recursive: true);
        File(p.join(output, 'artifact.json')).writeAsStringSync('{}');
        await expectLater(
          DllartCliTestApi.runAbiContractTestForTesting(config),
          throwsA(isA<ToolError>()),
        );

        Directory(p.join(output, 'include')).createSync(recursive: true);
        await expectLater(
          DllartCliTestApi.runAbiContractTestForTesting(config),
          throwsA(isA<ToolError>()),
        );

        Directory(p.join(output, 'lib')).createSync(recursive: true);
        File(p.join(output, 'artifact.json')).writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(<String, Object?>{
            'symbols': <String, Object?>{'init': 'abi_mod_dllart_init'},
            'exports': <Object?>[
              <String, Object?>{'name': 'ping', 'arity': 0},
            ],
          }),
        );
        await expectLater(
          DllartCliTestApi.runAbiContractTestForTesting(config),
          throwsA(isA<ToolError>()),
        );

        File(p.join(output, 'artifact.json')).writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(<String, Object?>{
            'symbols': <String, Object?>{
              'init': 'x',
              'call_json': 'x',
              'call_json_batch': 'x',
              'call_json_raw': 'x',
              'call_i64_2': 'x',
              'call_i64_2_index': 'x',
              'call_i64_4': 'x',
              'call_i64_4_index': 'x',
              'call_f64_2': 'x',
              'call_f64_2_index': 'x',
              'call_f64_4': 'x',
              'call_f64_4_index': 'x',
              'call_bytes': 'x',
              'call_bytes_index': 'x',
              'last_error_code': 'x',
              'last_error_json': 'x',
              'shutdown': 'x',
              'string_free': 'x',
              'bytes_free': 'x',
            },
            'exports': <Object?>[
              <String, Object?>{
                'name': 'add',
                'arity': 1,
                'supports_i64_2': true,
                'i64_2_method_id': 0,
              },
            ],
          }),
        );

        final result = await DllartCliTestApi.runAbiContractTestForTesting(
          config,
        );
        expect(result['ok'], isFalse);
        expect(result['compile_exit_code'], isNotNull);
        expect(result['compile_summary'], isNotNull);
      },
    );

    test(
      'commandTest sets failure exit code in json mode for invalid artifact',
      () async {
        final tempRoot = await Directory.systemTemp.createTemp(
          'dllart_cmd_test_',
        );
        addTearDown(() {
          if (tempRoot.existsSync()) {
            tempRoot.deleteSync(recursive: true);
          }
        });

        Directory(p.join(tempRoot.path, 'lib')).createSync(recursive: true);
        File(p.join(tempRoot.path, 'lib', 'module.dart')).writeAsStringSync('''
@DllartExport()
Object? ping() => 'pong';
''');

        final configPath = p.join(tempRoot.path, 'dllart.json');
        File(configPath).writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(<String, Object>{
            'name': 'cmd_test_mod',
            'source': 'lib/module.dart',
            'output': 'out',
          }),
        );

        exitCode = 0;
        await DllartCliTestApi.commandTest(
          _args(<String, String>{
            'config': configPath,
            'skip-build': 'true',
            'json': 'true',
          }),
        );
        expect(exitCode, 1);
      },
    );
  });

  group('config locator and inferred source helpers', () {
    test('locator and config error prefix produce stable positions', () {
      const raw = '{\n  "name": "calc",\n  "source": "lib/module.dart"\n}\n';
      final offsetLoc = DllartCliTestApi.configLocationFromOffset(raw, 2);
      expect(offsetLoc, <int>[2, 1]);

      final nameLoc = DllartCliTestApi.configLocationForField(raw, 'name');
      expect(nameLoc, <int>[2, 3]);
      expect(DllartCliTestApi.configLocationForField(raw, 'missing'), isNull);

      expect(DllartCliTestApi.configErrorPrefix('/tmp/a.json'), '/tmp/a.json');
      expect(
        DllartCliTestApi.configErrorPrefix('/tmp/a.json', line: 2, column: 9),
        '/tmp/a.json:2:9',
      );
    });

    test(
      'selectInferredSource resolves unique and module-like candidates',
      () async {
        final tempRoot = await Directory.systemTemp.createTemp(
          'dllart_select_source_',
        );
        addTearDown(() {
          if (tempRoot.existsSync()) {
            tempRoot.deleteSync(recursive: true);
          }
        });

        final libDir = Directory(p.join(tempRoot.path, 'lib'))
          ..createSync(recursive: true);
        expect(DllartCliTestApi.selectInferredSource(libDir.path), isNull);

        final first = File(p.join(libDir.path, 'a.dart'))
          ..writeAsStringSync('@DllartExport()\nObject? a() => null;');
        expect(
          DllartCliTestApi.selectInferredSource(libDir.path),
          p.normalize(first.path),
        );

        File(
          p.join(libDir.path, 'x.dart'),
        ).writeAsStringSync('@DllartExport()\nObject? x() => null;');
        File(
          p.join(libDir.path, 'my_module.dart'),
        ).writeAsStringSync('@DllartExport()\nObject? m() => null;');
        expect(
          DllartCliTestApi.selectInferredSource(libDir.path),
          p.normalize(p.join(libDir.path, 'my_module.dart')),
        );
      },
    );
  });

  group('package/helpers and model edges', () {
    test('cleanupLegacyArtifacts removes files and directories', () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'dllart_cleanup_legacy_',
      );
      addTearDown(() {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      });

      final output = tempRoot.path;
      File(p.join(output, 'mod_api.h')).createSync(recursive: true);
      File(p.join(output, 'module.aot.dill')).createSync(recursive: true);
      Directory(p.join(output, 'generated')).createSync(recursive: true);
      Directory(p.join(output, 'include')).createSync(recursive: true);
      File(p.join(output, 'include', 'dllart_bridge.h')).createSync();
      File(p.join(output, 'libmod.dylib')).createSync();

      DllartCliTestApi.cleanupLegacyArtifacts(output, 'mod');
      expect(File(p.join(output, 'mod_api.h')).existsSync(), isFalse);
      expect(Directory(p.join(output, 'generated')).existsSync(), isFalse);
      expect(File(p.join(output, 'libmod.dylib')).existsSync(), isFalse);
    });

    test(
      'artifact manifest map and Flutter method constants handle edge inputs',
      () async {
        final tempRoot = await Directory.systemTemp.createTemp(
          'dllart_manifest_helpers_',
        );
        addTearDown(() {
          if (tempRoot.existsSync()) {
            tempRoot.deleteSync(recursive: true);
          }
        });

        final missing = p.join(tempRoot.path, 'missing.json');
        expect(DllartCliTestApi.readArtifactManifestMap(missing), isEmpty);

        final malformed = File(p.join(tempRoot.path, 'bad.json'))
          ..writeAsStringSync('{oops');
        expect(
          DllartCliTestApi.readArtifactManifestMap(malformed.path),
          isEmpty,
        );

        final manifest = <String, Object?>{
          'exports': <Object?>[
            <String, Object?>{
              'name': 'add-fast',
              'i64_2_method_id': 1,
              'bytes_method_id': 5,
            },
            <String, Object?>{'name': 'add fast', 'i64_2_method_id': 2},
            <String, Object?>{'name': '123', 'i64_4_method_id': 7},
            <String, Object?>{'name': '', 'i64_2_method_id': 9},
            'bad',
          ],
        };

        final constants = DllartCliTestApi.generateFlutterMethodIdConstants(
          manifest,
        );
        expect(constants, contains('static const int i64_2_ADD_FAST = 1;'));
        expect(constants, contains('static const int i64_2_ADD_FAST_2 = 2;'));
        expect(constants, contains('static const int i64_4_M_123 = 7;'));

        expect(DllartCliTestApi.sanitizeForDartConst('***'), 'METHOD');
        expect(DllartCliTestApi.sanitizeForDartConst('9abc'), 'M_9ABC');
      },
    );

    test(
      'model parsing covers protobuf protoc and target assignment branches',
      () {
        final cfg = DllartConfig.fromJson(<String, Object?>{
          'name': 'calc',
          'source': 'lib/module.dart',
          'targets': <String>['linux-x64'],
          'protobuf': <String, Object?>{
            'proto': 'proto/calc.proto',
            'protoc': 'custom-protoc',
          },
        });
        expect(cfg.targets, <String>['linux-x64']);
        expect(cfg.protobuf!.protoc, 'custom-protoc');

        expect(
          () => DllartConfig.fromJson(<String, Object?>{
            'name': 'calc',
            'source': 'lib/module.dart',
            'protobuf': <String, Object?>{
              'proto': 'proto/calc.proto',
              'includes': <String>['proto', ' '],
            },
          }),
          throwsA(isA<ConfigValidationError>()),
        );
      },
    );

    test('json payload helper emits optional fields branch', () {
      DllartCliTestApi.writeJsonCommandResultForTesting(
        'x',
        ok: false,
        status: 'error',
        exitCode: 9,
        data: <String, Object?>{'k': 'v'},
        error: <String, Object?>{'type': 'X'},
      );
    });
  });
}
