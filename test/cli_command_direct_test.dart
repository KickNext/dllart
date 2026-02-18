import 'dart:io';

import 'package:dllart/src/cli/app.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'runtime_support.dart';

ParsedArgs _args(
  Map<String, String> options, [
  List<String> positional = const <String>[],
]) {
  return ParsedArgs(positional, options);
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

Future<bool> _hasClang() async {
  try {
    final result = await Process.run('clang', <String>['--version']);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void main() {
  test(
    'direct command lifecycle: create -> build -> integrate -> package',
    () async {
      final hasClang = await _hasClang();
      if (!hasClang) {
        stderr.writeln(
          'Skipping direct lifecycle test: clang is not available.',
        );
        return;
      }
      if (shouldSkipRuntimeDependentLinuxTests()) {
        stderr.writeln(
          'Skipping direct lifecycle test on Linux: dartaotruntime is not dlopen-compatible for this SDK build.',
        );
        return;
      }

      final tempRoot = await Directory.systemTemp.createTemp('dllart_direct_');
      addTearDown(() {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      });

      final projectPath = p.join(tempRoot.path, 'direct_mod');
      final configPath = p.join(projectPath, 'dllart.json');

      await DllartCliTestApi.commandCreate(
        _args(<String, String>{
          'path': projectPath,
          'force': 'true',
          'local-path-dependency': 'true',
        }),
      );

      await DllartCliTestApi.commandDoctor(
        _args(<String, String>{'config': configPath}),
      );
      expect(exitCode, anyOf(0, 1));
      exitCode = 0;

      await DllartCliTestApi.commandBuild(
        _args(<String, String>{'config': configPath}),
      );

      final outputPath = p.join(projectPath, 'build');
      expect(Directory(p.join(outputPath, 'include')).existsSync(), isTrue);
      expect(
        File(
          p.join(outputPath, 'lib', _libraryFileName('direct_mod')),
        ).existsSync(),
        isTrue,
      );

      await DllartCliTestApi.commandIntegrate(
        _args(<String, String>{'config': configPath}),
      );

      await DllartCliTestApi.commandTest(
        _args(<String, String>{'config': configPath, 'skip-build': 'true'}),
      );

      await DllartCliTestApi.commandPackage(
        _args(<String, String>{
          'config': configPath,
          'target': 'fuchsia',
          'force': 'true',
        }),
      );

      expect(
        Directory(p.join(outputPath, 'package', 'fuchsia')).existsSync(),
        isTrue,
      );

      await DllartCliTestApi.commandPackage(
        _args(<String, String>{
          'config': configPath,
          'target': 'python',
          'force': 'true',
        }),
      );
      expect(
        Directory(p.join(outputPath, 'package', 'python')).existsSync(),
        isTrue,
      );
      expect(
        File(
          p.join(outputPath, 'package', 'python', 'bindings.py'),
        ).existsSync(),
        isTrue,
      );

      await DllartCliTestApi.commandPackage(
        _args(<String, String>{
          'config': configPath,
          'target': 'csharp',
          'force': 'true',
        }),
      );
      expect(
        Directory(p.join(outputPath, 'package', 'csharp')).existsSync(),
        isTrue,
      );
      expect(
        File(
          p.join(outputPath, 'package', 'csharp', 'DllartClient.cs'),
        ).existsSync(),
        isTrue,
      );

      final workflowPath = p.join(
        projectPath,
        '.github',
        'workflows',
        'direct.yml',
      );
      await DllartCliTestApi.commandWorkflow(
        _args(<String, String>{
          'config': configPath,
          'output': workflowPath,
          'force': 'true',
          'local-tool': 'true',
        }),
      );
      expect(File(workflowPath).existsSync(), isTrue);
    },
  );

  test('direct command lifecycle: init -> make', () async {
    final hasClang = await _hasClang();
    if (!hasClang) {
      stderr.writeln('Skipping direct init/make test: clang is not available.');
      return;
    }
    if (shouldSkipRuntimeDependentLinuxTests()) {
      stderr.writeln(
        'Skipping direct init/make test on Linux: dartaotruntime is not dlopen-compatible for this SDK build.',
      );
      return;
    }

    final tempRoot = await Directory.systemTemp.createTemp(
      'dllart_direct_init_',
    );
    addTearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    final projectPath = p.join(tempRoot.path, 'init_mod');
    Directory(projectPath).createSync(recursive: true);

    final sourcePath = p.join(projectPath, 'lib', 'module.dart');
    final outputPath = p.join(projectPath, 'out');
    final configPath = p.join(projectPath, 'cfg', 'dllart.json');

    await DllartCliTestApi.commandInit(
      _args(<String, String>{
        'name': 'init_mod',
        'source': sourcePath,
        'output': outputPath,
        'config': configPath,
        'force': 'true',
      }),
    );

    await DllartCliTestApi.commandMake(
      _args(<String, String>{'config': configPath}),
    );
    await DllartCliTestApi.commandTest(
      _args(<String, String>{'config': configPath, 'skip-build': 'true'}),
    );

    expect(File(configPath).existsSync(), isTrue);
    expect(File(sourcePath).existsSync(), isTrue);
    expect(Directory(p.join(outputPath, 'include')).existsSync(), isTrue);
    expect(
      File(
        p.join(outputPath, 'lib', _libraryFileName('init_mod')),
      ).existsSync(),
      isTrue,
    );
  });

  test(
    'integrate validates artifact structure and reports actionable errors',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'dllart_integrate_err_',
      );
      addTearDown(() {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      });

      final projectPath = p.join(tempRoot.path, 'broken_mod');
      Directory(projectPath).createSync(recursive: true);
      final configPath = p.join(projectPath, 'dllart.json');
      final outputPath = p.join(projectPath, 'out');

      File(configPath).writeAsStringSync('''
{
  "name": "broken_mod",
  "source": "lib/module.dart",
  "output": "out"
}
''');

      await expectLater(
        DllartCliTestApi.commandIntegrate(
          _args(<String, String>{'config': configPath}),
        ),
        throwsA(isA<ToolError>()),
      );

      Directory(outputPath).createSync(recursive: true);
      await expectLater(
        DllartCliTestApi.commandIntegrate(
          _args(<String, String>{'config': configPath}),
        ),
        throwsA(isA<ToolError>()),
      );

      Directory(p.join(outputPath, 'include')).createSync(recursive: true);
      await expectLater(
        DllartCliTestApi.commandIntegrate(
          _args(<String, String>{'config': configPath}),
        ),
        throwsA(isA<ToolError>()),
      );

      final libDir = Directory(p.join(outputPath, 'lib'))..createSync();
      await expectLater(
        DllartCliTestApi.commandIntegrate(
          _args(<String, String>{'config': configPath}),
        ),
        throwsA(isA<ToolError>()),
      );

      final libPath = p.join(libDir.path, _libraryFileName('broken_mod'));
      File(libPath).writeAsStringSync('');
      await DllartCliTestApi.commandIntegrate(
        _args(<String, String>{'config': configPath, 'json': 'true'}),
      );
    },
  );

  test('loadConfig requires full inline arguments', () {
    expect(
      () => DllartCliTestApi.loadConfig(
        _args(<String, String>{'name': 'missing_source'}),
      ),
      throwsA(isA<ToolError>()),
    );
  });
}
