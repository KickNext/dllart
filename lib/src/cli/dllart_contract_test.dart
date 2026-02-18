part of dllart_cli;

class _AbiContractExport {
  const _AbiContractExport({
    required this.name,
    required this.arity,
    required this.supportsI64_2,
    required this.i64_2MethodId,
    required this.supportsI64_4,
    required this.i64_4MethodId,
    required this.supportsF64_2,
    required this.f64_2MethodId,
    required this.supportsF64_4,
    required this.f64_4MethodId,
    required this.supportsBytes,
    required this.bytesMethodId,
  });

  final String name;
  final int arity;
  final bool supportsI64_2;
  final int? i64_2MethodId;
  final bool supportsI64_4;
  final int? i64_4MethodId;
  final bool supportsF64_2;
  final int? f64_2MethodId;
  final bool supportsF64_4;
  final int? f64_4MethodId;
  final bool supportsBytes;
  final int? bytesMethodId;
}

class _AbiContractRunResult {
  const _AbiContractRunResult({required this.ok, required this.data});

  final bool ok;
  final Map<String, Object?> data;
}

Future<void> _commandTest(ParsedArgs args) async {
  final jsonMode = _isJsonMode(args);
  final loaded = _loadConfig(args, allowInferred: true);
  final skipBuild = args.hasFlag('skip-build');
  final perfGate = args.hasFlag('perf-gate');

  final details = <String, Object?>{
    'module': loaded.config.name,
    'config': loaded.configPath,
    'skip_build': skipBuild,
    'perf_gate': perfGate,
  };

  var ok = true;
  if (!skipBuild) {
    final buildOptions = Map<String, String>.from(args.options)
      ..remove('skip-build');
    buildOptions.remove('json');
    final buildArgs = ParsedArgs(args.positional, buildOptions);
    await _commandBuild(buildArgs);
    details['build'] = 'executed';
  } else {
    details['build'] = 'skipped';
  }

  try {
    final result = await _runAbiContractTest(loaded);
    ok = result.ok;
    details.addAll(result.data);
  } on ToolError catch (error) {
    ok = false;
    details['error'] = error.message;
  }

  if (ok && perfGate) {
    final perfResult = await _runPerfGate();
    details['perf'] = perfResult;
    if (perfResult['ok'] != true) {
      ok = false;
    }
  }

  if (jsonMode) {
    _writeJsonCommandResult(
      'test',
      ok: ok,
      status: ok ? 'ok' : 'fail',
      data: details,
    );
  } else {
    stdout.writeln('DLLART ABI Contract Test');
    stdout.writeln('Module: ${loaded.config.name}');
    stdout.writeln(
      'Build step: ${skipBuild ? 'skipped (--skip-build)' : 'executed'}',
    );
    final harness = details['harness'];
    if (harness is Map<String, Object?>) {
      final sourcePath = harness['source'];
      final executablePath = harness['executable'];
      if (sourcePath is String && sourcePath.isNotEmpty) {
        stdout.writeln('Harness source: ${_displayPath(sourcePath)}');
      }
      if (executablePath is String && executablePath.isNotEmpty) {
        stdout.writeln('Harness binary: ${_displayPath(executablePath)}');
      }
    }

    if (details['compile_stderr'] is String &&
        (details['compile_stderr'] as String).trim().isNotEmpty) {
      stdout.writeln('');
      stdout.writeln('Compile diagnostics:');
      stdout.writeln((details['compile_stderr'] as String).trimRight());
    }
    if (details['run_stdout'] is String &&
        (details['run_stdout'] as String).trim().isNotEmpty) {
      stdout.writeln('');
      stdout.writeln('Harness output:');
      stdout.writeln((details['run_stdout'] as String).trimRight());
    }
    if (details['run_stderr'] is String &&
        (details['run_stderr'] as String).trim().isNotEmpty) {
      stdout.writeln('');
      stdout.writeln('Harness stderr:');
      stdout.writeln((details['run_stderr'] as String).trimRight());
    }

    stdout.writeln('');
    stdout.writeln(
      ok ? 'ABI contract test passed.' : 'ABI contract test failed.',
    );
  }

  if (!ok) {
    exitCode = 1;
  }
}

Future<Map<String, Object?>> _runPerfGate() async {
  final scriptPath = p.join(_toolRoot(), 'scripts', 'benchmark.sh');
  if (!File(scriptPath).existsSync()) {
    return <String, Object?>{
      'ok': false,
      'error': 'Benchmark script not found: $scriptPath',
    };
  }

  final iterations = (Platform.environment['DLLART_PERF_GATE_ITERATIONS'] ?? '')
      .trim();
  final minThroughputRaw =
      (Platform.environment['DLLART_PERF_GATE_MIN_CPS'] ?? '').trim();
  final minThroughput =
      int.tryParse(minThroughputRaw) ?? 50000; // conservative default gate
  final args = <String>[if (iterations.isNotEmpty) iterations];
  final result = await Process.run(scriptPath, args, runInShell: false);
  if (result.exitCode != 0) {
    return <String, Object?>{
      'ok': false,
      'exit_code': result.exitCode,
      'stdout': _asText(result.stdout),
      'stderr': _asText(result.stderr),
    };
  }

  final output = '${_asText(result.stdout)}\n${_asText(result.stderr)}';
  final throughputMatches = RegExp(r'throughput=([0-9]+)\s*calls/s')
      .allMatches(output)
      .map((m) => int.tryParse(m.group(1) ?? ''))
      .whereType<int>()
      .toList(growable: false);

  if (throughputMatches.isEmpty) {
    return <String, Object?>{
      'ok': false,
      'error': 'Could not parse throughput values from benchmark output',
      'stdout': _asText(result.stdout),
    };
  }

  final minObserved = throughputMatches.reduce(
    (value, element) => value < element ? value : element,
  );

  return <String, Object?>{
    'ok': minObserved >= minThroughput,
    'minimum_required_cps': minThroughput,
    'minimum_observed_cps': minObserved,
    'samples': throughputMatches,
  };
}

Future<_AbiContractRunResult> _runAbiContractTest(LoadedConfig loaded) async {
  final outputPath = loaded.resolvePath(loaded.config.output);
  final includeDir = p.join(outputPath, 'include');
  final libDir = p.join(outputPath, 'lib');
  final manifestPath = p.join(outputPath, 'artifact.json');

  if (!File(manifestPath).existsSync()) {
    throw ToolError(
      'Artifact manifest not found: $manifestPath. Run `dllart build` first.',
    );
  }
  if (!Directory(includeDir).existsSync()) {
    throw ToolError(
      'Headers directory missing: $includeDir. Run `dllart build` first.',
    );
  }
  if (!Directory(libDir).existsSync()) {
    throw ToolError(
      'Library directory missing: $libDir. Run `dllart build` first.',
    );
  }

  final manifestRaw = jsonDecode(File(manifestPath).readAsStringSync());
  if (manifestRaw is! Map) {
    throw ToolError('Malformed artifact manifest: expected JSON object');
  }

  final manifest = Map<String, Object?>.from(
    manifestRaw.cast<String, Object?>(),
  );
  final symbolsRaw = manifest['symbols'];
  if (symbolsRaw is! Map) {
    throw ToolError('Malformed artifact manifest: missing `symbols` object');
  }
  final symbols = Map<String, Object?>.from(symbolsRaw.cast<String, Object?>());
  final requiredSymbols = <String>[
    'init',
    'call_json',
    'call_json_batch',
    'call_json_raw',
    'call_i64_2',
    'call_i64_2_index',
    'call_i64_4',
    'call_i64_4_index',
    'call_f64_2',
    'call_f64_2_index',
    'call_f64_4',
    'call_f64_4_index',
    'call_bytes',
    'call_bytes_index',
    'last_error_code',
    'last_error_json',
    'shutdown',
    'string_free',
    'bytes_free',
  ];
  final missingSymbols = requiredSymbols
      .where(
        (key) => symbols[key] is! String || (symbols[key] as String).isEmpty,
      )
      .toList(growable: false);
  if (missingSymbols.isNotEmpty) {
    throw ToolError(
      'Manifest symbols are incomplete. Missing: ${missingSymbols.join(', ')}',
    );
  }

  final exportsRaw = manifest['exports'];
  if (exportsRaw is! List || exportsRaw.isEmpty) {
    throw ToolError('Malformed artifact manifest: `exports` must be non-empty');
  }
  final exports = _parseAbiContractExports(exportsRaw);
  final abiRaw = manifest['abi'];
  var expectedAbiMajor = 1;
  if (abiRaw is Map) {
    expectedAbiMajor =
        _toInt(
          Map<String, Object?>.from(abiRaw.cast<String, Object?>())['major'],
        ) ??
        1;
  }

  final moduleName = loaded.config.name;
  final prefix = _sanitizeForC(moduleName).toLowerCase();
  final testRoot = Directory(p.join(outputPath, '.work', 'abi-contract'));
  testRoot.createSync(recursive: true);
  final workDir = await testRoot.createTemp('run_');
  final sourcePath = p.join(workDir.path, 'abi_contract_test.c');
  final executablePath = p.join(
    workDir.path,
    Platform.isWindows ? 'abi_contract_test.exe' : 'abi_contract_test',
  );

  await File(sourcePath).writeAsString(
    _generateAbiContractCTest(
      moduleName: moduleName,
      modulePrefix: prefix,
      exports: exports,
      expectedAbiMajor: expectedAbiMajor,
    ),
  );

  final toolchain = _resolveToolchain();
  final compileResult = await _runCommandCapture(toolchain.clang, <String>[
    sourcePath,
    '-I$includeDir',
    '-L$libDir',
    '-l$moduleName',
    '-o',
    executablePath,
  ]);

  if (compileResult.exitCode != 0) {
    return _AbiContractRunResult(
      ok: false,
      data: <String, Object?>{
        'artifact': manifestPath,
        'abi_major': expectedAbiMajor,
        'exports_count': exports.length,
        'harness': <String, Object?>{
          'source': sourcePath,
          'executable': executablePath,
        },
        'compile_exit_code': compileResult.exitCode,
        'compile_stdout': _asText(compileResult.stdout),
        'compile_stderr': _asText(compileResult.stderr),
        'compile_summary': _processFailureSummary(
          '${toolchain.clang} abi_contract_test.c',
          compileResult,
        ),
      },
    );
  }

  final env = Map<String, String>.from(Platform.environment);
  if (Platform.isMacOS) {
    env['DYLD_LIBRARY_PATH'] = _prependLibrarySearchPath(
      libDir,
      env['DYLD_LIBRARY_PATH'],
    );
  } else if (Platform.isLinux) {
    env['LD_LIBRARY_PATH'] = _prependLibrarySearchPath(
      libDir,
      env['LD_LIBRARY_PATH'],
    );
  } else if (Platform.isWindows) {
    env['PATH'] = _prependLibrarySearchPath(libDir, env['PATH']);
  }

  final runResult = await Process.run(
    executablePath,
    const <String>[],
    runInShell: false,
    environment: env,
  );

  return _AbiContractRunResult(
    ok: runResult.exitCode == 0,
    data: <String, Object?>{
      'artifact': manifestPath,
      'abi_major': expectedAbiMajor,
      'exports_count': exports.length,
      'harness': <String, Object?>{
        'source': sourcePath,
        'executable': executablePath,
      },
      'compile_exit_code': compileResult.exitCode,
      'run_exit_code': runResult.exitCode,
      'run_stdout': _asText(runResult.stdout),
      'run_stderr': _asText(runResult.stderr),
    },
  );
}

List<_AbiContractExport> _parseAbiContractExports(List<dynamic> rawList) {
  final out = <_AbiContractExport>[];
  for (var i = 0; i < rawList.length; i++) {
    final row = rawList[i];
    if (row is! Map) {
      throw ToolError('Malformed export descriptor at index $i');
    }
    final map = Map<String, Object?>.from(row.cast<String, Object?>());
    final name = map['name'];
    final arity = _toInt(map['arity']);
    if (name is! String || name.trim().isEmpty || arity == null) {
      throw ToolError('Malformed export descriptor at index $i');
    }
    out.add(
      _AbiContractExport(
        name: name,
        arity: arity,
        supportsI64_2: map['supports_i64_2'] == true,
        i64_2MethodId: _toInt(map['i64_2_method_id']),
        supportsI64_4: map['supports_i64_4'] == true,
        i64_4MethodId: _toInt(map['i64_4_method_id']),
        supportsF64_2: map['supports_f64_2'] == true,
        f64_2MethodId: _toInt(map['f64_2_method_id']),
        supportsF64_4: map['supports_f64_4'] == true,
        f64_4MethodId: _toInt(map['f64_4_method_id']),
        supportsBytes: map['supports_bytes'] == true,
        bytesMethodId: _toInt(map['bytes_method_id']),
      ),
    );
  }
  return out;
}

int? _toInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return null;
}

String _prependLibrarySearchPath(String dir, String? existing) {
  final separator = Platform.isWindows ? ';' : ':';
  final normalized = p.normalize(dir);
  if (existing == null || existing.trim().isEmpty) {
    return normalized;
  }
  return '$normalized$separator$existing';
}

String _generateAbiContractCTest({
  required String moduleName,
  required String modulePrefix,
  required List<_AbiContractExport> exports,
  int expectedAbiMajor = 1,
}) {
  final exportRows = exports
      .map(
        (item) =>
            '  {"${_escapeCString(item.name)}", ${item.arity}, '
            '${item.supportsI64_2 ? 1 : 0}, ${item.i64_2MethodId ?? -1}, '
            '${item.supportsI64_4 ? 1 : 0}, ${item.i64_4MethodId ?? -1}, '
            '${item.supportsF64_2 ? 1 : 0}, ${item.f64_2MethodId ?? -1}, '
            '${item.supportsF64_4 ? 1 : 0}, ${item.f64_4MethodId ?? -1}, '
            '${item.supportsBytes ? 1 : 0}, ${item.bytesMethodId ?? -1}},',
      )
      .join('\n');

  return '''#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "${moduleName}_api.h"

typedef struct {
  const char* name;
  int arity;
  int supports_i64_2;
  int i64_2_method_id;
  int supports_i64_4;
  int i64_4_method_id;
  int supports_f64_2;
  int f64_2_method_id;
  int supports_f64_4;
  int f64_4_method_id;
  int supports_bytes;
  int bytes_method_id;
} dllart_export_case_t;

static const dllart_export_case_t kExportCases[] = {
$exportRows
};

static const char* args_for_arity(int arity) {
  switch (arity) {
    case 0:
      return "null";
    case 1:
      return "{}";
    case 2:
      return "{\\"a\\":1,\\"b\\":2}";
    case 3:
      return "{\\"a\\":1,\\"b\\":2,\\"c\\":3}";
    case 4:
      return "{\\"a\\":1,\\"b\\":2,\\"c\\":3,\\"d\\":4}";
    default:
      return "{}";
  }
}

static int fail(const char* step, const char* detail) {
  fprintf(stderr, "[FAIL] %s: %s\\n", step, detail ? detail : "<null>");
  return 1;
}

static int expect_contains(const char* step, const char* text, const char* needle) {
  if (text == NULL || strstr(text, needle) == NULL) {
    return fail(step, text);
  }
  return 0;
}

static int expect_error_mentions(const char* step, const char* text, const char* needle) {
  if (text == NULL || needle == NULL || strstr(text, needle) == NULL) {
    return fail(step, text);
  }
  return 0;
}

int main(void) {
  char* err = NULL;
  char* json = NULL;

  if (${modulePrefix}_abi_version() != $expectedAbiMajor) {
    return fail("abi_version", "mismatch with artifact abi.major");
  }

  if (${modulePrefix}_init(NULL, &err) != 0) {
    return fail("init", err);
  }

  if (${modulePrefix}_call_json("__dllart_unknown__", "{}", &json, &err) != 0) {
    return fail("call_json_unknown", err);
  }
  if (expect_contains("call_json_unknown_contract", json, "\\"ok\\":false") != 0) {
    ${modulePrefix}_string_free(json);
    return 1;
  }
  ${modulePrefix}_string_free(json);
  json = NULL;

  if (${modulePrefix}_call_json_batch("[{\\"method\\":\\"__dllart_unknown__\\",\\"args\\":{}}]", &json, &err) != 0) {
    return fail("call_json_batch", err);
  }
  if (expect_contains("call_json_batch_contract", json, "\\"ok\\":false") != 0) {
    ${modulePrefix}_string_free(json);
    return 1;
  }
  ${modulePrefix}_string_free(json);
  json = NULL;

  {
    int64_t out = 0;
    if (${modulePrefix}_call_i64_2("__dllart_unknown__", 1, 2, &out, &err) == 0) {
      return fail("call_i64_2_unknown_expected_error", "call unexpectedly succeeded");
    }
    if (err != NULL) {
      ${modulePrefix}_string_free(err);
      err = NULL;
    }
    if (${modulePrefix}_last_error_code() == 0) {
      return fail("last_error_code", "expected non-zero after failed call");
    }
    if (${modulePrefix}_last_error_json(&json) != 0) {
      return fail("last_error_json", "failed to fetch last error json");
    }
    if (expect_contains("last_error_json_contract", json, "\\"code\\":") != 0) {
      ${modulePrefix}_string_free(json);
      return 1;
    }
    ${modulePrefix}_string_free(json);
    json = NULL;
  }

  const size_t export_count = sizeof(kExportCases) / sizeof(kExportCases[0]);
  for (size_t i = 0; i < export_count; i++) {
    const dllart_export_case_t* item = &kExportCases[i];
    const char* args_json = args_for_arity(item->arity);

    if (${modulePrefix}_call_json(item->name, args_json, &json, &err) != 0) {
      return fail("call_json", err);
    }
    if (expect_contains("call_json_contract", json, "\\"ok\\":") != 0) {
      ${modulePrefix}_string_free(json);
      return 1;
    }
    ${modulePrefix}_string_free(json);
    json = NULL;

    if (${modulePrefix}_call_json_raw(item->name, args_json, &json, &err) != 0) {
      if (expect_error_mentions("call_json_raw_error_context", err, item->name) != 0) {
        return 1;
      }
      ${modulePrefix}_string_free(err);
      err = NULL;
    } else {
      if (json == NULL) {
        return fail("call_json_raw_result", "null result");
      }
      ${modulePrefix}_string_free(json);
      json = NULL;
    }

    if (item->supports_i64_2) {
      int64_t out = 0;
      if (${modulePrefix}_call_i64_2(item->name, 11, 22, &out, &err) != 0) {
        if (expect_error_mentions("call_i64_2_error_context", err, item->name) != 0) {
          return 1;
        }
        ${modulePrefix}_string_free(err);
        err = NULL;
      }
      if (${modulePrefix}_call_i64_2_index(item->i64_2_method_id, 11, 22, &out, &err) != 0) {
        if (expect_error_mentions("call_i64_2_index_error_context", err, "id=") != 0) {
          return 1;
        }
        ${modulePrefix}_string_free(err);
        err = NULL;
      }
    }

    if (item->supports_i64_4) {
      int64_t out = 0;
      if (${modulePrefix}_call_i64_4(item->name, 1, 2, 3, 4, &out, &err) != 0) {
        if (expect_error_mentions("call_i64_4_error_context", err, item->name) != 0) {
          return 1;
        }
        ${modulePrefix}_string_free(err);
        err = NULL;
      }
      if (${modulePrefix}_call_i64_4_index(item->i64_4_method_id, 1, 2, 3, 4, &out, &err) != 0) {
        if (expect_error_mentions("call_i64_4_index_error_context", err, "id=") != 0) {
          return 1;
        }
        ${modulePrefix}_string_free(err);
        err = NULL;
      }
    }

    if (item->supports_f64_2) {
      double out = 0.0;
      if (${modulePrefix}_call_f64_2(item->name, 1.25, 2.5, &out, &err) != 0) {
        if (expect_error_mentions("call_f64_2_error_context", err, item->name) != 0) {
          return 1;
        }
        ${modulePrefix}_string_free(err);
        err = NULL;
      }
      if (${modulePrefix}_call_f64_2_index(item->f64_2_method_id, 1.25, 2.5, &out, &err) != 0) {
        if (expect_error_mentions("call_f64_2_index_error_context", err, "id=") != 0) {
          return 1;
        }
        ${modulePrefix}_string_free(err);
        err = NULL;
      }
    }

    if (item->supports_f64_4) {
      double out = 0.0;
      if (${modulePrefix}_call_f64_4(item->name, 1.0, 2.0, 3.0, 4.0, &out, &err) != 0) {
        if (expect_error_mentions("call_f64_4_error_context", err, item->name) != 0) {
          return 1;
        }
        ${modulePrefix}_string_free(err);
        err = NULL;
      }
      if (${modulePrefix}_call_f64_4_index(item->f64_4_method_id, 1.0, 2.0, 3.0, 4.0, &out, &err) != 0) {
        if (expect_error_mentions("call_f64_4_index_error_context", err, "id=") != 0) {
          return 1;
        }
        ${modulePrefix}_string_free(err);
        err = NULL;
      }
    }

    if (item->supports_bytes) {
      const uint8_t payload[4] = {1, 2, 3, 4};
      uint8_t* out_ptr = NULL;
      int32_t out_len = 0;
      if (${modulePrefix}_call_bytes(item->name, payload, 4, &out_ptr, &out_len, &err) != 0) {
        if (expect_error_mentions("call_bytes_error_context", err, item->name) != 0) {
          return 1;
        }
        ${modulePrefix}_string_free(err);
        err = NULL;
      } else if (out_ptr != NULL) {
        ${modulePrefix}_bytes_free(out_ptr);
      }

      out_ptr = NULL;
      out_len = 0;
      if (${modulePrefix}_call_bytes_index(item->bytes_method_id, payload, 4, &out_ptr, &out_len, &err) != 0) {
        if (expect_error_mentions("call_bytes_index_error_context", err, "id=") != 0) {
          return 1;
        }
        ${modulePrefix}_string_free(err);
        err = NULL;
      } else if (out_ptr != NULL) {
        ${modulePrefix}_bytes_free(out_ptr);
      }
    }
  }

  ${modulePrefix}_shutdown();
  printf("abi_contract_ok module=%s exports=%zu\\n", "$moduleName", export_count);
  return 0;
}
''';
}
