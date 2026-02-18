import 'dart:io';

import 'package:dllart/src/cli/app.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('command parser', () {
    test('canonical aliases are resolved', () {
      expect(DllartCliTestApi.canonicalCommand('new'), 'create');
      expect(DllartCliTestApi.canonicalCommand('check'), 'doctor');
      expect(DllartCliTestApi.canonicalCommand('build'), 'build');
    });

    test('parseArgs handles positional and key-value options', () {
      final parsed = DllartCliTestApi.parseArgs(<String>[
        'create',
        '--name=calc',
        '--output',
        'build/calc',
        '--force',
      ]);

      expect(parsed.positional, <String>['create']);
      expect(parsed['name'], 'calc');
      expect(parsed['output'], 'build/calc');
      expect(parsed.hasFlag('force'), isTrue);
      expect(parsed.hasFlag('missing'), isFalse);
    });

    test('validateCommandArgs rejects unknown options', () {
      final parsed = DllartCliTestApi.parseArgs(<String>['--wat']);

      expect(
        () => DllartCliTestApi.validateCommandArgs('build', parsed),
        throwsA(isA<ToolError>()),
      );
    });

    test('validateCommandArgs rejects extra positional args', () {
      final parsed = ParsedArgs(<String>['a', 'b'], <String, String>{});

      expect(
        () => DllartCliTestApi.validateCommandArgs('init', parsed),
        throwsA(isA<ToolError>()),
      );
    });

    test('command metadata exposes known options', () {
      final options = DllartCliTestApi.allowedOptionsForCommand('workflow');
      expect(options, contains('global-tool'));
      expect(options, contains('local-tool'));
      expect(
        DllartCliTestApi.allowedOptionsForCommand('create'),
        containsAll(<String>[
          'dependency',
          'dllart-path',
          'local-path-dependency',
        ]),
      );
      expect(
        DllartCliTestApi.allowedOptionsForCommand('proto'),
        containsAll(<String>['proto', 'out', 'include', 'grpc', 'protoc']),
      );
      expect(DllartCliTestApi.maxPositionalArgsForCommand('proto'), 1);
      expect(
        DllartCliTestApi.allowedOptionsForCommand('build'),
        containsAll(<String>['json', 'verbose']),
      );
      expect(
        DllartCliTestApi.allowedOptionsForCommand('package'),
        containsAll(<String>[
          'auto-build',
          'android-abis',
          'ios-variants',
          'verbose',
        ]),
      );
      expect(
        DllartCliTestApi.allowedOptionsForCommand('integrate'),
        containsAll(<String>['json', 'verbose']),
      );
      expect(
        DllartCliTestApi.allowedOptionsForCommand('doctor'),
        containsAll(<String>['json', 'package-target', 'verbose']),
      );
      expect(
        DllartCliTestApi.allowedOptionsForCommand('verify'),
        containsAll(<String>['target', 'json', 'verbose']),
      );
      expect(
        DllartCliTestApi.allowedOptionsForCommand('test'),
        containsAll(<String>['json', 'skip-build']),
      );
      expect(DllartCliTestApi.maxPositionalArgsForCommand('create'), 1);
      expect(DllartCliTestApi.maxPositionalArgsForCommand('build'), 0);
      expect(DllartCliTestApi.maxPositionalArgsForCommand('verify'), 0);
    });

    test('command registry exposes unique command names', () {
      final names = DllartCliTestApi.commandNames();
      expect(
        names,
        containsAll(<String>[
          'create',
          'init',
          'build',
          'make',
          'package',
          'proto',
          'workflow',
          'integrate',
          'doctor',
          'verify',
          'test',
          'build-all',
        ]),
      );
      expect(names.toSet().length, names.length);
    });

    test('runCliForTesting handles help and argument errors', () async {
      expect(await DllartCliTestApi.runCliForTesting(<String>['--help']), 0);
      expect(
        await DllartCliTestApi.runCliForTesting(<String>['help', 'build']),
        0,
      );
      expect(
        await DllartCliTestApi.runCliForTesting(<String>['build', '--wat']),
        2,
      );
      expect(await DllartCliTestApi.runCliForTesting(<String>['unknown']), 2);
    });

    test('runCliForTesting dispatches command branches', () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'dllart_cli_dispatch_',
      );
      addTearDown(() {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      });

      final projectPath = p.join(tempRoot.path, 'dispatch_mod');
      final createCode = await DllartCliTestApi.runCliForTesting(<String>[
        'create',
        projectPath,
        '--force',
      ]);
      expect(createCode, 0);

      final initConfig = p.join(tempRoot.path, 'init', 'dllart.json');
      final initSource = p.join(tempRoot.path, 'init', 'lib', 'module.dart');
      final initCode = await DllartCliTestApi.runCliForTesting(<String>[
        'init',
        '--name',
        'init_dispatch',
        '--source',
        initSource,
        '--output',
        p.join(tempRoot.path, 'init', 'out'),
        '--config',
        initConfig,
        '--force',
      ]);
      expect(initCode, 0);

      final missingConfig = p.join(tempRoot.path, 'missing.json');
      expect(
        await DllartCliTestApi.runCliForTesting(<String>[
          'build',
          '--config',
          missingConfig,
        ]),
        2,
      );
      expect(
        await DllartCliTestApi.runCliForTesting(<String>[
          'make',
          '--config',
          missingConfig,
        ]),
        2,
      );
      expect(
        await DllartCliTestApi.runCliForTesting(<String>[
          'package',
          '--config',
          missingConfig,
        ]),
        2,
      );
      expect(
        await DllartCliTestApi.runCliForTesting(<String>[
          'workflow',
          '--config',
          missingConfig,
        ]),
        2,
      );
      expect(
        await DllartCliTestApi.runCliForTesting(<String>[
          'proto',
          '--config',
          missingConfig,
        ]),
        2,
      );
      expect(
        await DllartCliTestApi.runCliForTesting(<String>[
          'integrate',
          '--config',
          missingConfig,
        ]),
        2,
      );
      final doctorCode = await DllartCliTestApi.runCliForTesting(<String>[
        'doctor',
        '--config',
        missingConfig,
      ]);
      expect(doctorCode, anyOf(0, 1));

      expect(
        await DllartCliTestApi.runCliForTesting(<String>[
          'build-all',
          '--config',
          missingConfig,
        ]),
        2,
      );
    });
  });

  group('naming and targets', () {
    test('normalizePackageName sanitizes and stabilizes names', () {
      expect(
        DllartCliTestApi.normalizePackageName('My Module!!!'),
        'my_module',
      );
      expect(DllartCliTestApi.normalizePackageName('123'), 'p_123');
      expect(DllartCliTestApi.normalizePackageName('___'), 'dllart_project');
    });

    test('resolvePackageTarget supports explicit and default values', () {
      expect(
        DllartCliTestApi.resolvePackageTarget(
          ParsedArgs(<String>[], <String, String>{'target': 'ios'}),
        ),
        'ios',
      );
      expect(
        DllartCliTestApi.resolvePackageTarget(
          ParsedArgs(<String>['flutter'], <String, String>{}),
        ),
        'flutter',
      );
      expect(
        DllartCliTestApi.resolvePackageTarget(
          ParsedArgs(<String>['python'], <String, String>{}),
        ),
        'python',
      );
      expect(
        DllartCliTestApi.resolvePackageTarget(
          ParsedArgs(<String>['csharp'], <String, String>{}),
        ),
        'csharp',
      );
      expect(
        DllartCliTestApi.resolvePackageTarget(
          ParsedArgs(<String>[], <String, String>{}),
        ),
        'all',
      );
    });

    test('resolvePackageTarget rejects unsupported values', () {
      expect(
        () => DllartCliTestApi.resolvePackageTarget(
          ParsedArgs(<String>[], <String, String>{'target': 'web'}),
        ),
        throwsA(isA<ToolError>()),
      );
    });
  });

  group('config model validation', () {
    test('ToolError and ConfigValidationError stringify message', () {
      expect(ToolError('boom').toString(), 'boom');
      expect(
        ConfigValidationError('bad config', field: 'name').toString(),
        'bad config',
      );
    });

    test('DllartConfig fromJson accepts valid payload and defaults', () {
      final config = DllartConfig.fromJson(<String, Object?>{
        'name': '  calc  ',
        'source': '  lib/module.dart ',
        'protobuf': <String, Object?>{
          'proto': 'proto/calc.proto',
          'includes': <String>['proto'],
          'grpc': true,
        },
      });

      expect(config.name, 'calc');
      expect(config.source, 'lib/module.dart');
      expect(config.output, 'build');
      expect(config.targets, DllartConfig.defaultTargets);
      expect(config.protobuf, isNotNull);
      expect(config.protobuf!.proto, 'proto/calc.proto');
      expect(config.protobuf!.out, p.join('lib', 'generated', 'proto'));
      expect(config.protobuf!.includes, <String>['proto']);
      expect(config.protobuf!.grpc, isTrue);
      expect(config.toJson()['name'], 'calc');
    });

    test('DllartConfig validates unknown fields and target constraints', () {
      expect(
        () => DllartConfig.fromJson(<String, Object?>{
          'name': 'calc',
          'source': 'lib/module.dart',
          'wat': true,
        }),
        throwsA(isA<ConfigValidationError>()),
      );
      expect(
        () => DllartConfig.fromJson(<String, Object?>{
          'name': 'calc',
          'source': 'lib/module.dart',
          'targets': <Object?>[],
        }),
        throwsA(isA<ConfigValidationError>()),
      );
      expect(
        () => DllartConfig.fromJson(<String, Object?>{
          'name': 'calc',
          'source': 'lib/module.dart',
          'targets': <Object?>['linux-x64', 'linux-x64'],
        }),
        throwsA(isA<ConfigValidationError>()),
      );
      expect(
        () => DllartConfig.fromJson(<String, Object?>{
          'name': 'calc',
          'source': 'lib/module.dart',
          'targets': <Object?>['web-x64'],
        }),
        throwsA(isA<ConfigValidationError>()),
      );
      expect(
        () => DllartConfig.fromJson(<String, Object?>{
          'name': 'calc',
          'source': 'lib/module.dart',
          'protobuf': <String, Object?>{'proto': ''},
        }),
        throwsA(isA<ConfigValidationError>()),
      );
      expect(
        () => DllartConfig.fromJson(<String, Object?>{
          'name': 'calc',
          'source': 'lib/module.dart',
          'protobuf': <String, Object?>{
            'proto': 'proto/calc.proto',
            'grpc': 'yes',
          },
        }),
        throwsA(isA<ConfigValidationError>()),
      );
      expect(
        () => DllartConfig.fromJson(<String, Object?>{
          'name': 'calc',
          'source': 'lib/module.dart',
          'protobuf': <String, Object?>{
            'proto': 'proto/calc.proto',
            'includes': <Object?>['proto', 1],
          },
        }),
        throwsA(isA<ConfigValidationError>()),
      );
    });

    test('DllartConfig validates required and typed fields', () {
      expect(
        () => DllartConfig.fromJson(<String, Object?>{
          'source': 'lib/module.dart',
        }),
        throwsA(isA<ConfigValidationError>()),
      );
      expect(
        () => DllartConfig.fromJson(<String, Object?>{'name': 'calc'}),
        throwsA(isA<ConfigValidationError>()),
      );
      expect(
        () => DllartConfig.fromJson(<String, Object?>{
          'name': 'calc',
          'source': 'lib/module.dart',
          'output': '',
        }),
        throwsA(isA<ConfigValidationError>()),
      );
      expect(
        () => DllartConfig.fromJson(<Object, Object?>{
          1: 'bad-key',
          'name': 'calc',
          'source': 'lib/module.dart',
        }),
        throwsA(isA<ConfigValidationError>()),
      );
      expect(
        () => DllartConfig.fromJson('not-a-map'),
        throwsA(isA<ConfigValidationError>()),
      );
    });

    test('LoadedConfig resolves relative and absolute paths', () {
      final loaded = LoadedConfig(
        config: DllartConfig(
          name: 'calc',
          source: 'lib/module.dart',
          output: 'build',
          targets: List<String>.from(DllartConfig.defaultTargets),
        ),
        configPath: '/tmp/project/dllart.json',
      );

      expect(
        loaded.resolvePath('lib/module.dart'),
        p.normalize('/tmp/project/lib/module.dart'),
      );
      expect(
        loaded.resolvePath('/tmp/other.dart'),
        p.normalize('/tmp/other.dart'),
      );
    });

    test('Doctor report json status reflects summary', () {
      final warnOnly = DoctorReport()..warn('Config', 'missing file');
      final warnJson = warnOnly.toJson();
      expect(warnJson['status'], 'warn');

      final fail = DoctorReport()
        ..ok('Dart', 'found')
        ..warn('Config', 'missing')
        ..fail('clang', 'not found');

      final itemOk = DoctorItem(DoctorStatus.ok, 'ok', 'detail').toJson();
      final itemWarn = DoctorItem(DoctorStatus.warn, 'warn', 'detail').toJson();
      final itemFail = DoctorItem(DoctorStatus.fail, 'fail', 'detail').toJson();

      expect(itemOk['status'], 'ok');
      expect(itemWarn['status'], 'warn');
      expect(itemFail['status'], 'fail');

      final json = fail.toJson();
      expect(json['status'], 'fail');

      final summary = json['summary'] as Map<String, int>;
      expect(summary['ok'], 1);
      expect(summary['warnings'], 1);
      expect(summary['failures'], 1);

      final items = json['items'] as List<Map<String, String>>;
      expect(items.length, 3);
    });
  });

  group('export discovery and method IDs', () {
    test('discoverExports detects JSON and typed signatures', () {
      const source = '''
import 'dart:typed_data';

@DllartExport()
Object? add(Object? args) => args;

@DllartExport('add_fast')
int addFast(int a, int b) => a + b;

@DllartExport('sum4_fast')
int sum4Fast(int a, int b, int c, int d) => a + b + c + d;

@DllartExport('avg2_fast')
double avg2Fast(double a, double b) => (a + b) / 2.0;

@DllartExport('proto_fast')
Uint8List protoFast(Uint8List args) => args;

@DllartExport()
Object? ping() => 'pong';
''';

      final exports = DllartCliTestApi.discoverExports(source);
      expect(exports.length, 6);

      final byName = <String, ExportedFunction>{
        for (final fn in exports) fn.exportName: fn,
      };

      expect(byName['add']!.supportsI64_2, isTrue);
      expect(byName['add']!.directI64_2, isFalse);

      expect(byName['add_fast']!.supportsI64_2, isTrue);
      expect(byName['add_fast']!.directI64_2, isTrue);

      expect(byName['sum4_fast']!.supportsI64_4, isTrue);
      expect(byName['sum4_fast']!.directI64_4, isTrue);

      expect(byName['avg2_fast']!.supportsF64_2, isTrue);
      expect(byName['avg2_fast']!.directF64_2, isTrue);
      expect(byName['proto_fast']!.supportsBytes, isTrue);
      expect(byName['proto_fast']!.directBytes, isTrue);
      expect(byName['add']!.supportsBytes, isFalse);

      final i64_2 = DllartCliTestApi.computeI64_2MethodIds(exports);
      final i64_4 = DllartCliTestApi.computeI64_4MethodIds(exports);
      final f64_2 = DllartCliTestApi.computeF64_2MethodIds(exports);
      final bytes = DllartCliTestApi.computeBytesMethodIds(exports);

      expect(i64_2['add'], 0);
      expect(i64_2['add_fast'], 1);
      expect(i64_4['sum4_fast'], 0);
      expect(f64_2['avg2_fast'], 0);
      expect(bytes['proto_fast'], 0);
    });

    test('discoverExports rejects duplicate export aliases', () {
      const source = '''
@DllartExport('same')
Object? a() => null;

@DllartExport('same')
Object? b() => null;
''';

      expect(
        () => DllartCliTestApi.discoverExports(source),
        throwsA(isA<ToolError>()),
      );
    });

    test('discoverExports rejects named or unsupported params', () {
      const named = '''
@DllartExport()
Object? a({int v = 1}) => v;
''';

      const many = '''
@DllartExport()
Object? b(int a, int b, int c, int d, int e) => 0;
''';

      expect(
        () => DllartCliTestApi.discoverExports(named),
        throwsA(isA<ToolError>()),
      );
      expect(
        () => DllartCliTestApi.discoverExports(many),
        throwsA(isA<ToolError>()),
      );
    });
  });

  group('code generation helpers', () {
    test(
      'generateEntrypoint and generateApiHeader include expected symbols',
      () {
        const source = '''
import 'dart:typed_data';

@DllartExport('add_fast')
int addFast(int a, int b) => a + b;

@DllartExport('proto_fast')
Uint8List protoFast(Uint8List args) => args;
''';

        final exports = DllartCliTestApi.discoverExports(source);
        final entry = DllartCliTestApi.generateEntrypoint(
          '/tmp/module.dart',
          exports,
        );
        final header = DllartCliTestApi.generateApiHeader('calc', exports);

        expect(entry, contains('dllart_dispatch_i64_2'));
        expect(entry, contains('dllart_dispatch_bytes'));
        expect(entry, contains('add_fast'));
        expect(header, contains('calc_dllart_call_i64_2'));
        expect(header, contains('calc_dllart_call_bytes'));
        expect(header, contains('calc_add_fast_i64_2_fast'));
        expect(header, contains('calc_proto_fast_bytes_fast'));
      },
    );

    test('generate build integration files include module-specific names', () {
      final cmake = DllartCliTestApi.generateCMakeConfig(
        moduleName: 'calc',
        libraryFileName: 'libcalc.so',
      );
      final pc = DllartCliTestApi.generatePkgConfig(moduleName: 'calc');

      expect(cmake, contains('calc::calc'));
      expect(cmake, contains('libcalc.so'));
      expect(pc, contains('Name: calc'));
      expect(pc, contains('-lcalc'));
    });

    test('generateWorkflowYaml switches between local/global tool mode', () {
      final loaded = LoadedConfig(
        config: DllartConfig(
          name: 'calc',
          source: 'lib/module.dart',
          output: 'build/calc',
          targets: List<String>.from(DllartConfig.defaultTargets),
        ),
        configPath: '/tmp/project/dllart.json',
      );

      final localYaml = DllartCliTestApi.generateWorkflowYaml(
        loaded,
        baseDir: '/tmp/project',
        useGlobalTool: false,
      );
      final globalYaml = DllartCliTestApi.generateWorkflowYaml(
        loaded,
        baseDir: '/tmp/project',
        useGlobalTool: true,
      );

      expect(localYaml, contains('dart run dllart build --config dllart.json'));
      expect(globalYaml, contains('dart pub global activate dllart'));
      expect(globalYaml, contains('dllart build --config dllart.json'));
    });
  });

  group('path and platform helpers', () {
    test('sanitizers and prefixes generate stable identifiers', () {
      expect(DllartCliTestApi.sanitizeForC('calc-module'), 'calc_module');
      expect(DllartCliTestApi.sanitizeForC('9bad'), '_9bad');
      expect(
        DllartCliTestApi.moduleRuntimePrefix('calc-module'),
        'calc_module_dllart',
      );
      expect(DllartCliTestApi.escapeCString('a"b\\c'), 'a\\"b\\\\c');
      expect(
        DllartCliTestApi.escapeDartSingleQuoted("a'b\\c\$"),
        "a\\'b\\\\c\\\$",
      );
    });

    test('runtime and output paths align with host platform', () {
      final runtime = DllartCliTestApi.runtimeExecutableNameForHost();
      if (Platform.isWindows) {
        expect(runtime, 'dartaotruntime.exe');
      } else {
        expect(runtime, 'dartaotruntime');
      }

      final lib = DllartCliTestApi.outputLibraryPath('/tmp/out', 'calc');
      if (Platform.isMacOS) {
        expect(lib, '/tmp/out/libcalc.dylib');
      } else if (Platform.isLinux) {
        expect(lib, '/tmp/out/libcalc.so');
      } else if (Platform.isWindows) {
        expect(lib.replaceAll('\\', '/'), contains('/tmp/out/calc.dll'));
      }

      expect(DllartCliTestApi.hostTargetId(), contains('-'));
    });

    test('displayPath prefers relative workspace paths', () {
      final nested = p.join(Directory.current.path, 'lib', 'dllart.dart');
      expect(DllartCliTestApi.displayPath(nested), 'lib/dllart.dart');
    });
  });

  group('filesystem inference helpers', () {
    test('findNearestPubspecDir finds nearest ancestor', () async {
      final root = await Directory.systemTemp.createTemp('dllart_pubspec_');
      addTearDown(() {
        if (root.existsSync()) {
          root.deleteSync(recursive: true);
        }
      });

      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: tmp\n');
      final nested = Directory(p.join(root.path, 'a', 'b', 'c'))
        ..createSync(recursive: true);

      final found = DllartCliTestApi.findNearestPubspecDir(nested.path);
      expect(found, p.normalize(root.path));
    });

    test(
      'inferConfigFromCurrentDirectory uses lib/module.dart convention',
      () async {
        final root = await Directory.systemTemp.createTemp('dllart_infer_');
        addTearDown(() {
          if (root.existsSync()) {
            root.deleteSync(recursive: true);
          }
        });

        Directory(p.join(root.path, 'lib')).createSync(recursive: true);
        File(p.join(root.path, 'lib', 'module.dart')).writeAsStringSync('''
@DllartExport()
Object? ping() => 'pong';
''');

        final oldCurrent = Directory.current;
        try {
          Directory.current = root.path;
          final loaded = DllartCliTestApi.inferConfigFromCurrentDirectory();
          expect(loaded, isNotNull);
          expect(loaded!.config.source, 'lib/module.dart');
          expect(loaded.config.output, 'build');
        } finally {
          Directory.current = oldCurrent;
        }
      },
    );
  });
}
