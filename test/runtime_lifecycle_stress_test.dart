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

Future<bool> _hasClang() async {
  try {
    final result = await Process.run('clang', <String>['--version']);
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
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}

String _stressSource({required String moduleName}) {
  final prefix = '${moduleName}_dllart';
  return '''
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <dlfcn.h>

typedef int (*init_fn)(const char* runtime_path, char** error_out);
typedef int (*call_i64_2_fn)(const char* method,
                             int64_t a,
                             int64_t b,
                             int64_t* result_out,
                             char** error_out);
typedef void (*shutdown_fn)(void);
typedef void (*string_free_fn)(char* value);

typedef struct {
  call_i64_2_fn call_i64_2;
  string_free_fn string_free;
  int worker_index;
  int failed;
} worker_ctx;

static void report_error(const char* ctx, const char* message) {
  fprintf(stderr, "%s failed: %s\\n", ctx, message != NULL ? message : "<unknown>");
}

static void* worker_main(void* arg) {
  worker_ctx* ctx = (worker_ctx*)arg;
  for (int i = 0; i < 80; i++) {
    const int64_t a = (int64_t)(ctx->worker_index * 1000 + i);
    const int64_t b = (int64_t)(i + 1);
    const int64_t expected = a + b;
    int64_t actual = 0;
    char* error_out = NULL;
    const int rc =
        ctx->call_i64_2("add_fast", a, b, &actual, &error_out);
    if (rc != 0) {
      report_error("call_i64_2", error_out);
      if (error_out != NULL) {
        ctx->string_free(error_out);
      }
      ctx->failed = 1;
      return NULL;
    }
    if (actual != expected) {
      fprintf(stderr,
              "call_i64_2 mismatch: expected=%lld actual=%lld\\n",
              (long long)expected,
              (long long)actual);
      ctx->failed = 1;
      return NULL;
    }
  }
  return NULL;
}

int main(int argc, char** argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: runtime_stress <library_path>\\n");
    return 2;
  }

  const char* library_path = argv[1];
  void* handle = dlopen(library_path, RTLD_NOW | RTLD_LOCAL);
  if (handle == NULL) {
    report_error("dlopen", dlerror());
    return 1;
  }

  init_fn init =
      (init_fn)dlsym(handle, "${prefix}_init");
  call_i64_2_fn call_i64_2 =
      (call_i64_2_fn)dlsym(handle, "${prefix}_call_i64_2");
  shutdown_fn shutdown =
      (shutdown_fn)dlsym(handle, "${prefix}_shutdown");
  string_free_fn string_free =
      (string_free_fn)dlsym(handle, "${prefix}_string_free");
  if (init == NULL || call_i64_2 == NULL || shutdown == NULL || string_free == NULL) {
    report_error("dlsym", "required symbol is missing");
    dlclose(handle);
    return 1;
  }

  for (int round = 0; round < 8; round++) {
    char* error_out = NULL;
    if (init(NULL, &error_out) != 0) {
      report_error("init", error_out);
      if (error_out != NULL) {
        string_free(error_out);
      }
      dlclose(handle);
      return 1;
    }
    if (init(NULL, &error_out) != 0) {
      report_error("init(idempotent)", error_out);
      if (error_out != NULL) {
        string_free(error_out);
      }
      dlclose(handle);
      return 1;
    }

    pthread_t threads[6];
    worker_ctx ctx[6];
    for (int i = 0; i < 6; i++) {
      ctx[i].call_i64_2 = call_i64_2;
      ctx[i].string_free = string_free;
      ctx[i].worker_index = i;
      ctx[i].failed = 0;
      if (pthread_create(&threads[i], NULL, worker_main, &ctx[i]) != 0) {
        report_error("pthread_create", "failed");
        dlclose(handle);
        return 1;
      }
    }

    int failed = 0;
    for (int i = 0; i < 6; i++) {
      pthread_join(threads[i], NULL);
      if (ctx[i].failed) {
        failed = 1;
      }
    }
    if (failed) {
      shutdown();
      dlclose(handle);
      return 1;
    }

    shutdown();
    shutdown();
  }

  dlclose(handle);
  fprintf(stdout, "runtime_lifecycle_stress_ok\\n");
  return 0;
}
''';
}

void main() {
  test(
    'runtime lifecycle is stable under concurrent calls and repeated init/shutdown',
    () async {
      if (Platform.isWindows) {
        stderr.writeln('Skipping runtime lifecycle stress test on Windows.');
        return;
      }

      final hasClang = await _hasClang();
      if (!hasClang) {
        stderr.writeln(
          'Skipping runtime lifecycle stress test: clang is not available.',
        );
        return;
      }

      final tempRoot = await Directory.systemTemp.createTemp(
        'dllart_runtime_stress_',
      );
      addTearDown(() {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      });

      final projectPath = p.join(tempRoot.path, 'stress_mod');
      final configPath = p.join(projectPath, 'dllart.json');
      final created = await _runCli(<String>[
        'create',
        projectPath,
        '--local-path-dependency',
        '--force',
      ]);
      expect(
        created.exitCode,
        0,
        reason: '${created.stderr}\n${created.stdout}',
      );

      final built = await _runCli(<String>['build', '--config', configPath]);
      expect(built.exitCode, 0, reason: '${built.stderr}\n${built.stdout}');

      final moduleName = 'stress_mod';
      final libraryPath = p.join(
        projectPath,
        'build',
        'lib',
        _libraryFileName(moduleName),
      );
      expect(File(libraryPath).existsSync(), isTrue);

      final stressSourcePath = p.join(tempRoot.path, 'runtime_stress.c');
      File(
        stressSourcePath,
      ).writeAsStringSync(_stressSource(moduleName: moduleName));

      final stressBinPath = p.join(tempRoot.path, 'runtime_stress');
      final compileArgs = <String>[
        stressSourcePath,
        '-O2',
        '-o',
        stressBinPath,
        '-lpthread',
        if (Platform.isLinux) '-ldl',
      ];
      final compiled = await Process.run('clang', compileArgs);
      expect(
        compiled.exitCode,
        0,
        reason: '${compiled.stderr}\n${compiled.stdout}',
      );

      final env = Map<String, String>.from(Platform.environment)
        ..['DLLART_ISOLATE_POOL_SIZE'] = '4';
      final ran = await Process.run(stressBinPath, <String>[
        libraryPath,
      ], environment: env);
      expect(ran.exitCode, 0, reason: '${ran.stderr}\n${ran.stdout}');
      expect(ran.stdout.toString(), contains('runtime_lifecycle_stress_ok'));
    },
  );
}
