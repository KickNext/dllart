import 'dart:io';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'runtime_support.dart';

final String _repoRoot = p.normalize(Directory.current.path);

Future<ProcessResult> _runCli(List<String> args, {String? workingDirectory}) {
  return Process.run(Platform.resolvedExecutable, <String>[
    'run',
    p.join(_repoRoot, 'bin', 'dllart.dart'),
    ...args,
  ], workingDirectory: workingDirectory ?? _repoRoot);
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
    'create/check/build-all/integrate/package/workflow flow works',
    () async {
      final hasClang = await _hasClang();
      if (!hasClang) {
        stderr.writeln('Skipping e2e flow test: clang is not available.');
        return;
      }
      if (shouldSkipRuntimeDependentLinuxTests()) {
        stderr.writeln(
          'Skipping e2e flow test on Linux: dartaotruntime is not dlopen-compatible for this SDK build.',
        );
        return;
      }

      final tempRoot = await Directory.systemTemp.createTemp('dllart_e2e_');
      addTearDown(() {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      });

      final projectPath = p.join(tempRoot.path, 'mod_new');
      final configPath = p.join(projectPath, 'dllart.json');

      final created = await _runCli(<String>[
        'new',
        projectPath,
        '--local-path-dependency',
      ]);
      expect(
        created.exitCode,
        0,
        reason: '${created.stderr}\n${created.stdout}',
      );
      expect(File(configPath).existsSync(), isTrue);

      final checked = await _runCli(<String>['check', '--config', configPath]);
      expect(
        checked.exitCode,
        0,
        reason: '${checked.stderr}\n${checked.stdout}',
      );

      final workflowPath = p.join(
        projectPath,
        '.github',
        'workflows',
        'ci.yml',
      );
      final buildAll = await _runCli(<String>[
        'build-all',
        '--config',
        configPath,
        '--output',
        workflowPath,
        '--local-tool',
        '--force',
      ]);
      expect(
        buildAll.exitCode,
        0,
        reason: '${buildAll.stderr}\n${buildAll.stdout}',
      );

      final outputRoot = p.join(projectPath, 'build');
      final includeDir = Directory(p.join(outputRoot, 'include'));
      final libFile = File(
        p.join(outputRoot, 'lib', _libraryFileName('mod_new')),
      );
      expect(includeDir.existsSync(), isTrue);
      expect(libFile.existsSync(), isTrue);
      expect(File(workflowPath).existsSync(), isTrue);

      final contractTest = await _runCli(<String>[
        'test',
        '--config',
        configPath,
        '--skip-build',
        '--json',
      ]);
      expect(
        contractTest.exitCode,
        0,
        reason: '${contractTest.stderr}\n${contractTest.stdout}',
      );
      final contractPayload =
          jsonDecode(contractTest.stdout.toString()) as Map<String, Object?>;
      expect(contractPayload['command'], 'test');
      expect(contractPayload['ok'], isTrue);

      final integrate = await _runCli(<String>[
        'integrate',
        '--config',
        configPath,
      ]);
      expect(
        integrate.exitCode,
        0,
        reason: '${integrate.stderr}\n${integrate.stdout}',
      );
      expect(integrate.stdout.toString(), contains('DLLART Integration'));

      final packaged = await _runCli(<String>[
        'package',
        'fuchsia',
        '--config',
        configPath,
        '--force',
      ]);
      expect(
        packaged.exitCode,
        0,
        reason: '${packaged.stderr}\n${packaged.stdout}',
      );

      expect(
        Directory(p.join(outputRoot, 'package', 'fuchsia')).existsSync(),
        isTrue,
      );

      final pythonPackage = await _runCli(<String>[
        'package',
        'python',
        '--config',
        configPath,
        '--force',
      ]);
      expect(
        pythonPackage.exitCode,
        0,
        reason: '${pythonPackage.stderr}\n${pythonPackage.stdout}',
      );
      expect(
        File(
          p.join(outputRoot, 'package', 'python', 'bindings.py'),
        ).existsSync(),
        isTrue,
      );
    },
  );

  test('init + make flow works with custom config path', () async {
    final hasClang = await _hasClang();
    if (!hasClang) {
      stderr.writeln('Skipping init/make test: clang is not available.');
      return;
    }
    if (shouldSkipRuntimeDependentLinuxTests()) {
      stderr.writeln(
        'Skipping init/make test on Linux: dartaotruntime is not dlopen-compatible for this SDK build.',
      );
      return;
    }

    final tempRoot = await Directory.systemTemp.createTemp('dllart_init_make_');
    addTearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    final projectPath = p.join(tempRoot.path, 'mod_init');
    Directory(projectPath).createSync(recursive: true);

    final sourcePath = p.join(projectPath, 'lib', 'module.dart');
    final outputPath = p.join(projectPath, 'out');
    final configPath = p.join(projectPath, 'config', 'custom.json');

    final init = await _runCli(<String>[
      'init',
      '--name',
      'mod_init',
      '--source',
      sourcePath,
      '--output',
      outputPath,
      '--config',
      configPath,
      '--force',
    ]);
    expect(init.exitCode, 0, reason: '${init.stderr}\n${init.stdout}');

    final make = await _runCli(<String>['make', '--config', configPath]);
    expect(make.exitCode, 0, reason: '${make.stderr}\n${make.stdout}');

    expect(File(configPath).existsSync(), isTrue);
    expect(File(sourcePath).existsSync(), isTrue);
    expect(Directory(p.join(outputPath, 'include')).existsSync(), isTrue);
    expect(
      File(
        p.join(outputPath, 'lib', _libraryFileName('mod_init')),
      ).existsSync(),
      isTrue,
    );
    expect(File(p.join(outputPath, 'artifact.json')).existsSync(), isTrue);

    final contractTest = await _runCli(<String>[
      'test',
      '--config',
      configPath,
      '--skip-build',
    ]);
    expect(
      contractTest.exitCode,
      0,
      reason: '${contractTest.stderr}\n${contractTest.stdout}',
    );
  });
}
