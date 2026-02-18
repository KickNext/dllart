part of dllart_cli;

String _generateEntrypoint(String sourcePath, List<ExportedFunction> exports) {
  final sourceUri = Uri.file(p.normalize(sourcePath)).toString();
  final i64_2MethodIds = _computeI64_2MethodIds(exports);
  final i64_4MethodIds = _computeI64_4MethodIds(exports);
  final f64_2MethodIds = _computeF64_2MethodIds(exports);
  final f64_4MethodIds = _computeF64_4MethodIds(exports);
  final bytesMethodIds = _computeBytesMethodIds(exports);

  final jsonEntries = exports
      .map((fn) {
        final escapedName = _escapeDartSingleQuoted(fn.exportName);
        if (fn.arity == 0) {
          return "  '$escapedName': (Object? _) => ${fn.dartName}(),";
        }
        if (fn.arity == 1) {
          return "  '$escapedName': (Object? args) => ${fn.dartName}(args),";
        }
        const keys = <String>['a', 'b', 'c', 'd'];
        final argsList = keys
            .take(fn.arity)
            .map((key) => "payload['$key'] as dynamic")
            .join(', ');
        return '''  '$escapedName': (Object? args) {
    final payload = _dllartRequireObjectMap(args, '$escapedName');
    return ${fn.dartName}($argsList);
  },''';
      })
      .join('\n');

  final typedI64_2MethodIdEntries = i64_2MethodIds.entries
      .map(
        (entry) => "  '${_escapeDartSingleQuoted(entry.key)}': ${entry.value},",
      )
      .join('\n');

  final typedI64_2Entries = exports
      .where((fn) => fn.supportsI64_2)
      .map((fn) {
        final escapedName = _escapeDartSingleQuoted(fn.exportName);
        if (fn.directI64_2) {
          return "  (int a, int b) => _dllartCoerceI64Result(${fn.dartName}(a, b), '$escapedName'),";
        }
        return "  (int a, int b) => _dllartCoerceI64Result(${fn.dartName}(<String, Object?>{'a': a, 'b': b}), '$escapedName'),";
      })
      .join('\n');

  final typedI64_4MethodIdEntries = i64_4MethodIds.entries
      .map(
        (entry) => "  '${_escapeDartSingleQuoted(entry.key)}': ${entry.value},",
      )
      .join('\n');

  final typedI64_4Entries = exports
      .where((fn) => fn.supportsI64_4)
      .map((fn) {
        final escapedName = _escapeDartSingleQuoted(fn.exportName);
        return "  (int a, int b, int c, int d) => _dllartCoerceI64Result(${fn.dartName}(a, b, c, d), '$escapedName'),";
      })
      .join('\n');

  final typedF64_2MethodIdEntries = f64_2MethodIds.entries
      .map(
        (entry) => "  '${_escapeDartSingleQuoted(entry.key)}': ${entry.value},",
      )
      .join('\n');

  final typedF64_2Entries = exports
      .where((fn) => fn.supportsF64_2)
      .map((fn) {
        final escapedName = _escapeDartSingleQuoted(fn.exportName);
        return "  (double a, double b) => _dllartCoerceF64Result(${fn.dartName}(a, b), '$escapedName'),";
      })
      .join('\n');

  final typedF64_4MethodIdEntries = f64_4MethodIds.entries
      .map(
        (entry) => "  '${_escapeDartSingleQuoted(entry.key)}': ${entry.value},",
      )
      .join('\n');

  final typedF64_4Entries = exports
      .where((fn) => fn.supportsF64_4)
      .map((fn) {
        final escapedName = _escapeDartSingleQuoted(fn.exportName);
        return "  (double a, double b, double c, double d) => _dllartCoerceF64Result(${fn.dartName}(a, b, c, d), '$escapedName'),";
      })
      .join('\n');

  final typedBytesMethodIdEntries = bytesMethodIds.entries
      .map(
        (entry) => "  '${_escapeDartSingleQuoted(entry.key)}': ${entry.value},",
      )
      .join('\n');

  final typedBytesEntries = exports
      .where((fn) => fn.supportsBytes)
      .map((fn) {
        final escapedName = _escapeDartSingleQuoted(fn.exportName);
        return "  (Uint8List args) => _dllartCoerceBytesResult(${fn.dartName}(args), '$escapedName'),";
      })
      .join('\n');

  return '''import 'dart:convert';
import 'dart:typed_data';
import '$sourceUri';

typedef _DllartJsonHandler = Object? Function(Object? args);
typedef _DllartTypedI64_2Handler = int Function(int a, int b);
typedef _DllartTypedI64_4Handler = int Function(int a, int b, int c, int d);
typedef _DllartTypedF64_2Handler = double Function(double a, double b);
typedef _DllartTypedF64_4Handler = double Function(
  double a,
  double b,
  double c,
  double d,
);
typedef _DllartTypedBytesHandler = Uint8List Function(Uint8List args);

final Map<String, _DllartJsonHandler> _dllartJsonHandlers =
    <String, _DllartJsonHandler>{
$jsonEntries
};

final Map<String, int> _dllartTypedI64_2MethodIds = <String, int>{
$typedI64_2MethodIdEntries
};

final List<_DllartTypedI64_2Handler> _dllartTypedI64_2Handlers =
    <_DllartTypedI64_2Handler>[
$typedI64_2Entries
];

final Map<String, int> _dllartTypedI64_4MethodIds = <String, int>{
$typedI64_4MethodIdEntries
};

final List<_DllartTypedI64_4Handler> _dllartTypedI64_4Handlers =
    <_DllartTypedI64_4Handler>[
$typedI64_4Entries
];

final Map<String, int> _dllartTypedF64_2MethodIds = <String, int>{
$typedF64_2MethodIdEntries
};

final List<_DllartTypedF64_2Handler> _dllartTypedF64_2Handlers =
    <_DllartTypedF64_2Handler>[
$typedF64_2Entries
];

final Map<String, int> _dllartTypedF64_4MethodIds = <String, int>{
$typedF64_4MethodIdEntries
};

final List<_DllartTypedF64_4Handler> _dllartTypedF64_4Handlers =
    <_DllartTypedF64_4Handler>[
$typedF64_4Entries
];

final Map<String, int> _dllartTypedBytesMethodIds = <String, int>{
$typedBytesMethodIdEntries
};

final List<_DllartTypedBytesHandler> _dllartTypedBytesHandlers =
    <_DllartTypedBytesHandler>[
$typedBytesEntries
];

String _dllartTypeName(Object? value) =>
    value == null ? 'null' : value.runtimeType.toString();

String _dllartStackToString(StackTrace stack) {
  final text = stack.toString();
  return text.isEmpty ? 'StackTrace.empty' : text;
}

String _dllartOk(Object? value) => jsonEncode(<String, Object?>{
      'ok': true,
      'result': value,
    });

String _dllartFail({
  required String method,
  required Object? input,
  required Object error,
  required StackTrace stack,
}) => jsonEncode(<String, Object?>{
      'ok': false,
      'error': error.toString(),
      'error_details': <String, Object?>{
        'method': method,
        'input_type': _dllartTypeName(input),
        'error_type': error.runtimeType.toString(),
        'stack': _dllartStackToString(stack),
      },
    });

Never _dllartThrowRawError({
  required String method,
  required Object? input,
  required Object error,
  required StackTrace stack,
}) {
  final details = <String>[
    'method=\$method',
    'input_type=\${_dllartTypeName(input)}',
    'error_type=\${error.runtimeType}',
    'error=\${error.toString()}',
    _dllartStackToString(stack),
  ].join('\\n');
  throw StateError(details);
}

Map<String, Object?> _dllartRequireObjectMap(Object? args, String method) {
  if (args is! Map) {
    throw ArgumentError('Method \$method expects JSON object payload');
  }
  return Map<String, Object?>.from(args);
}

int _dllartCoerceI64Result(Object? result, String method) {
  if (result is int) {
    return result;
  }
  if (result is num &&
      result.isFinite &&
      result == result.truncateToDouble()) {
    return result.toInt();
  }
  throw StateError(
    'Method \$method returned non-int result: \${result.runtimeType}',
  );
}

double _dllartCoerceF64Result(Object? result, String method) {
  if (result is double) {
    return result;
  }
  if (result is int) {
    return result.toDouble();
  }
  if (result is num && result.isFinite) {
    return result.toDouble();
  }
  throw StateError(
    'Method \$method returned non-double result: \${result.runtimeType}',
  );
}

Uint8List _dllartCoerceBytesResult(Object? result, String method) {
  if (result is Uint8List) {
    return result;
  }
  if (result is List<int>) {
    return Uint8List.fromList(result);
  }
  throw StateError(
    'Method \$method returned non-bytes result: \${result.runtimeType}',
  );
}

@pragma('vm:entry-point')
String dllart_dispatch(String method, String argsJson) {
  final handler = _dllartJsonHandlers[method];
  if (handler == null) {
    return jsonEncode(<String, Object?>{
      'ok': false,
      'error': 'Unknown method: \$method',
      'error_details': <String, Object?>{
        'method': method,
        'input_type': 'unparsed-json',
        'error_type': 'ArgumentError',
      },
    });
  }

  Object? decodedArgs;
  try {
    decodedArgs = jsonDecode(argsJson);
    final result = handler(decodedArgs);
    return _dllartOk(result);
  } catch (error, stack) {
    return _dllartFail(
      method: method,
      input: decodedArgs,
      error: error,
      stack: stack,
    );
  }
}

@pragma('vm:entry-point')
String dllart_dispatch_raw(String method, String argsJson) {
  final handler = _dllartJsonHandlers[method];
  if (handler == null) {
    throw ArgumentError('Unknown method: \$method');
  }

  Object? decodedArgs;
  try {
    decodedArgs = jsonDecode(argsJson);
    final result = handler(decodedArgs);
    return jsonEncode(result);
  } catch (error, stack) {
    _dllartThrowRawError(
      method: method,
      input: decodedArgs,
      error: error,
      stack: stack,
    );
  }
}

@pragma('vm:entry-point')
int dllart_dispatch_i64_2(String method, int a, int b) {
  try {
    final methodId = _dllartTypedI64_2MethodIds[method];
    if (methodId == null) {
      throw ArgumentError('Unknown method for i64_2 dispatch: \$method');
    }
    return dllart_dispatch_i64_2_index(methodId, a, b);
  } catch (error, stack) {
    _dllartThrowRawError(
      method: method,
      input: <String, Object?>{'abi': 'i64_2', 'a': a, 'b': b},
      error: error,
      stack: stack,
    );
  }
}

@pragma('vm:entry-point')
int dllart_dispatch_i64_2_index(int methodId, int a, int b) {
  try {
    if (_dllartTypedI64_2Handlers.isEmpty) {
      throw StateError('No i64_2 exports available');
    }
    if (methodId < 0 || methodId >= _dllartTypedI64_2Handlers.length) {
      throw RangeError.range(
        methodId,
        0,
        _dllartTypedI64_2Handlers.length - 1,
        'methodId',
        'Invalid i64_2 method index',
      );
    }
    final handler = _dllartTypedI64_2Handlers[methodId];
    return handler(a, b);
  } catch (error, stack) {
    _dllartThrowRawError(
      method: 'i64_2#index(\$methodId)',
      input: <String, Object?>{'abi': 'i64_2_index', 'a': a, 'b': b},
      error: error,
      stack: stack,
    );
  }
}

@pragma('vm:entry-point')
int dllart_dispatch_i64_4(String method, int a, int b, int c, int d) {
  try {
    final methodId = _dllartTypedI64_4MethodIds[method];
    if (methodId == null) {
      throw ArgumentError('Unknown method for i64_4 dispatch: \$method');
    }
    return dllart_dispatch_i64_4_index(methodId, a, b, c, d);
  } catch (error, stack) {
    _dllartThrowRawError(
      method: method,
      input: <String, Object?>{
        'abi': 'i64_4',
        'a': a,
        'b': b,
        'c': c,
        'd': d,
      },
      error: error,
      stack: stack,
    );
  }
}

@pragma('vm:entry-point')
int dllart_dispatch_i64_4_index(int methodId, int a, int b, int c, int d) {
  try {
    if (_dllartTypedI64_4Handlers.isEmpty) {
      throw StateError('No i64_4 exports available');
    }
    if (methodId < 0 || methodId >= _dllartTypedI64_4Handlers.length) {
      throw RangeError.range(
        methodId,
        0,
        _dllartTypedI64_4Handlers.length - 1,
        'methodId',
        'Invalid i64_4 method index',
      );
    }
    final handler = _dllartTypedI64_4Handlers[methodId];
    return handler(a, b, c, d);
  } catch (error, stack) {
    _dllartThrowRawError(
      method: 'i64_4#index(\$methodId)',
      input: <String, Object?>{
        'abi': 'i64_4_index',
        'a': a,
        'b': b,
        'c': c,
        'd': d,
      },
      error: error,
      stack: stack,
    );
  }
}

@pragma('vm:entry-point')
double dllart_dispatch_f64_2(String method, double a, double b) {
  try {
    final methodId = _dllartTypedF64_2MethodIds[method];
    if (methodId == null) {
      throw ArgumentError('Unknown method for f64_2 dispatch: \$method');
    }
    return dllart_dispatch_f64_2_index(methodId, a, b);
  } catch (error, stack) {
    _dllartThrowRawError(
      method: method,
      input: <String, Object?>{'abi': 'f64_2', 'a': a, 'b': b},
      error: error,
      stack: stack,
    );
  }
}

@pragma('vm:entry-point')
double dllart_dispatch_f64_2_index(int methodId, double a, double b) {
  try {
    if (_dllartTypedF64_2Handlers.isEmpty) {
      throw StateError('No f64_2 exports available');
    }
    if (methodId < 0 || methodId >= _dllartTypedF64_2Handlers.length) {
      throw RangeError.range(
        methodId,
        0,
        _dllartTypedF64_2Handlers.length - 1,
        'methodId',
        'Invalid f64_2 method index',
      );
    }
    final handler = _dllartTypedF64_2Handlers[methodId];
    return handler(a, b);
  } catch (error, stack) {
    _dllartThrowRawError(
      method: 'f64_2#index(\$methodId)',
      input: <String, Object?>{'abi': 'f64_2_index', 'a': a, 'b': b},
      error: error,
      stack: stack,
    );
  }
}

@pragma('vm:entry-point')
double dllart_dispatch_f64_4(
  String method,
  double a,
  double b,
  double c,
  double d,
) {
  try {
    final methodId = _dllartTypedF64_4MethodIds[method];
    if (methodId == null) {
      throw ArgumentError('Unknown method for f64_4 dispatch: \$method');
    }
    return dllart_dispatch_f64_4_index(methodId, a, b, c, d);
  } catch (error, stack) {
    _dllartThrowRawError(
      method: method,
      input: <String, Object?>{
        'abi': 'f64_4',
        'a': a,
        'b': b,
        'c': c,
        'd': d,
      },
      error: error,
      stack: stack,
    );
  }
}

@pragma('vm:entry-point')
double dllart_dispatch_f64_4_index(
  int methodId,
  double a,
  double b,
  double c,
  double d,
) {
  try {
    if (_dllartTypedF64_4Handlers.isEmpty) {
      throw StateError('No f64_4 exports available');
    }
    if (methodId < 0 || methodId >= _dllartTypedF64_4Handlers.length) {
      throw RangeError.range(
        methodId,
        0,
        _dllartTypedF64_4Handlers.length - 1,
        'methodId',
        'Invalid f64_4 method index',
      );
    }
    final handler = _dllartTypedF64_4Handlers[methodId];
    return handler(a, b, c, d);
  } catch (error, stack) {
    _dllartThrowRawError(
      method: 'f64_4#index(\$methodId)',
      input: <String, Object?>{
        'abi': 'f64_4_index',
        'a': a,
        'b': b,
        'c': c,
        'd': d,
      },
      error: error,
      stack: stack,
    );
  }
}

@pragma('vm:entry-point')
String dllart_dispatch_batch(String batchJson) {
  Object? decoded;
  try {
    decoded = jsonDecode(batchJson);
    if (decoded is! List) {
      throw ArgumentError('Batch payload must be a JSON array');
    }

    final out = <Object?>[];
    for (var i = 0; i < decoded.length; i++) {
      final item = decoded[i];
      if (item is! Map) {
        out.add(<String, Object?>{
          'ok': false,
          'error': 'Batch item at index \$i must be an object',
        });
        continue;
      }
      final map = Map<String, Object?>.from(item);
      final methodRaw = map['method'];
      if (methodRaw is! String || methodRaw.trim().isEmpty) {
        out.add(<String, Object?>{
          'ok': false,
          'error': 'Batch item at index \$i has invalid "method"',
        });
        continue;
      }
      final method = methodRaw.trim();
      final args = map['args'];
      final handler = _dllartJsonHandlers[method];
      if (handler == null) {
        out.add(<String, Object?>{
          'ok': false,
          'error': 'Unknown method: \$method',
        });
        continue;
      }
      try {
        final result = handler(args);
        out.add(<String, Object?>{'ok': true, 'result': result});
      } catch (error, stack) {
        out.add(<String, Object?>{
          'ok': false,
          'error': error.toString(),
          'error_details': <String, Object?>{
            'method': method,
            'error_type': error.runtimeType.toString(),
            'stack': _dllartStackToString(stack),
          },
        });
      }
    }
    return jsonEncode(out);
  } catch (error, stack) {
    return _dllartFail(
      method: '__batch__',
      input: decoded,
      error: error,
      stack: stack,
    );
  }
}

@pragma('vm:entry-point')
Uint8List dllart_dispatch_bytes(String method, Uint8List args) {
  try {
    final methodId = _dllartTypedBytesMethodIds[method];
    if (methodId == null) {
      throw ArgumentError('Unknown method for bytes dispatch: \$method');
    }
    return dllart_dispatch_bytes_index(methodId, args);
  } catch (error, stack) {
    _dllartThrowRawError(
      method: method,
      input: <String, Object?>{'abi': 'bytes', 'length': args.length},
      error: error,
      stack: stack,
    );
  }
}

@pragma('vm:entry-point')
Uint8List dllart_dispatch_bytes_index(int methodId, Uint8List args) {
  try {
    if (_dllartTypedBytesHandlers.isEmpty) {
      throw StateError('No bytes exports available');
    }
    if (methodId < 0 || methodId >= _dllartTypedBytesHandlers.length) {
      throw RangeError.range(
        methodId,
        0,
        _dllartTypedBytesHandlers.length - 1,
        'methodId',
        'Invalid bytes method index',
      );
    }
    final handler = _dllartTypedBytesHandlers[methodId];
    return handler(args);
  } catch (error, stack) {
    _dllartThrowRawError(
      method: 'bytes#index(\$methodId)',
      input: <String, Object?>{'abi': 'bytes_index', 'length': args.length},
      error: error,
      stack: stack,
    );
  }
}

@pragma('vm:entry-point')
void main() {}
''';
}

String _generateApiHeader(String moduleName, List<ExportedFunction> exports) {
  final guard = 'DLLART_${_sanitizeForC(moduleName).toUpperCase()}_API_H';
  final prefix = _sanitizeForC(moduleName).toLowerCase();
  final runtimePrefix = _moduleRuntimePrefix(moduleName);
  final i64_2MethodIds = _computeI64_2MethodIds(exports);
  final i64_4MethodIds = _computeI64_4MethodIds(exports);
  final f64_2MethodIds = _computeF64_2MethodIds(exports);
  final f64_4MethodIds = _computeF64_4MethodIds(exports);
  final bytesMethodIds = _computeBytesMethodIds(exports);

  final wrappers = exports
      .map((fn) {
        final cname = _sanitizeForC(fn.exportName).toLowerCase();
        return '''static inline int ${prefix}_${cname}(const char* args_json,
                                    char** result_json_out,
                                    char** error_out) {
  return ${runtimePrefix}_call_json("${_escapeCString(fn.exportName)}", args_json, result_json_out, error_out);
}

static inline int ${prefix}_${cname}_raw(const char* args_json,
                                        char** result_json_out,
                                        char** error_out) {
  return ${runtimePrefix}_call_json_raw("${_escapeCString(fn.exportName)}", args_json, result_json_out, error_out);
}
''';
      })
      .join('\n');

  final typedI64_2Wrappers = exports
      .where((fn) => fn.supportsI64_2)
      .map((fn) {
        final cname = _sanitizeForC(fn.exportName).toLowerCase();
        final methodId = i64_2MethodIds[fn.exportName]!;
        return '''static inline int ${prefix}_${cname}_i64_2(int64_t a,
                                          int64_t b,
                                          int64_t* result_out,
                                          char** error_out) {
  return ${runtimePrefix}_call_i64_2("${_escapeCString(fn.exportName)}", a, b, result_out, error_out);
}

static inline int ${prefix}_${cname}_i64_2_fast(int64_t a,
                                                 int64_t b,
                                                 int64_t* result_out,
                                                 char** error_out) {
  return ${runtimePrefix}_call_i64_2_index($methodId, a, b, result_out, error_out);
}
''';
      })
      .join('\n');

  final typedI64_4Wrappers = exports
      .where((fn) => fn.supportsI64_4)
      .map((fn) {
        final cname = _sanitizeForC(fn.exportName).toLowerCase();
        final methodId = i64_4MethodIds[fn.exportName]!;
        return '''static inline int ${prefix}_${cname}_i64_4(int64_t a,
                                          int64_t b,
                                          int64_t c,
                                          int64_t d,
                                          int64_t* result_out,
                                          char** error_out) {
  return ${runtimePrefix}_call_i64_4("${_escapeCString(fn.exportName)}", a, b, c, d, result_out, error_out);
}

static inline int ${prefix}_${cname}_i64_4_fast(int64_t a,
                                                 int64_t b,
                                                 int64_t c,
                                                 int64_t d,
                                                 int64_t* result_out,
                                                 char** error_out) {
  return ${runtimePrefix}_call_i64_4_index($methodId, a, b, c, d, result_out, error_out);
}
''';
      })
      .join('\n');

  final typedF64_2Wrappers = exports
      .where((fn) => fn.supportsF64_2)
      .map((fn) {
        final cname = _sanitizeForC(fn.exportName).toLowerCase();
        final methodId = f64_2MethodIds[fn.exportName]!;
        return '''static inline int ${prefix}_${cname}_f64_2(double a,
                                          double b,
                                          double* result_out,
                                          char** error_out) {
  return ${runtimePrefix}_call_f64_2("${_escapeCString(fn.exportName)}", a, b, result_out, error_out);
}

static inline int ${prefix}_${cname}_f64_2_fast(double a,
                                                 double b,
                                                 double* result_out,
                                                 char** error_out) {
  return ${runtimePrefix}_call_f64_2_index($methodId, a, b, result_out, error_out);
}
''';
      })
      .join('\n');

  final typedF64_4Wrappers = exports
      .where((fn) => fn.supportsF64_4)
      .map((fn) {
        final cname = _sanitizeForC(fn.exportName).toLowerCase();
        final methodId = f64_4MethodIds[fn.exportName]!;
        return '''static inline int ${prefix}_${cname}_f64_4(double a,
                                          double b,
                                          double c,
                                          double d,
                                          double* result_out,
                                          char** error_out) {
  return ${runtimePrefix}_call_f64_4("${_escapeCString(fn.exportName)}", a, b, c, d, result_out, error_out);
}

static inline int ${prefix}_${cname}_f64_4_fast(double a,
                                                 double b,
                                                 double c,
                                                 double d,
                                                 double* result_out,
                                                 char** error_out) {
  return ${runtimePrefix}_call_f64_4_index($methodId, a, b, c, d, result_out, error_out);
}
''';
      })
      .join('\n');

  final typedBytesWrappers = exports
      .where((fn) => fn.supportsBytes)
      .map((fn) {
        final cname = _sanitizeForC(fn.exportName).toLowerCase();
        final methodId = bytesMethodIds[fn.exportName]!;
        return '''static inline int ${prefix}_${cname}_bytes(const uint8_t* args,
                                          int32_t args_len,
                                          uint8_t** result_out,
                                          int32_t* result_len_out,
                                          char** error_out) {
  return ${runtimePrefix}_call_bytes("${_escapeCString(fn.exportName)}", args, args_len, result_out, result_len_out, error_out);
}

static inline int ${prefix}_${cname}_bytes_fast(const uint8_t* args,
                                                 int32_t args_len,
                                                 uint8_t** result_out,
                                                 int32_t* result_len_out,
                                                 char** error_out) {
  return ${runtimePrefix}_call_bytes_index($methodId, args, args_len, result_out, result_len_out, error_out);
}
''';
      })
      .join('\n');

  final typedBlockParts = <String>[
    if (typedI64_2Wrappers.isNotEmpty) typedI64_2Wrappers,
    if (typedI64_4Wrappers.isNotEmpty) typedI64_4Wrappers,
    if (typedF64_2Wrappers.isNotEmpty) typedF64_2Wrappers,
    if (typedF64_4Wrappers.isNotEmpty) typedF64_4Wrappers,
    if (typedBytesWrappers.isNotEmpty) typedBytesWrappers,
  ];
  final typedBlock = typedBlockParts.isEmpty
      ? ''
      : '\n${typedBlockParts.join('\n')}';

  return '''#ifndef $guard
#define $guard

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int ${runtimePrefix}_abi_version(void);
int ${runtimePrefix}_init(const char* runtime_path, char** error_out);
int ${runtimePrefix}_call_json(const char* method,
                               const char* args_json,
                               char** result_json_out,
                               char** error_out);
int ${runtimePrefix}_call_json_batch(const char* batch_json,
                                     char** result_json_out,
                                     char** error_out);
int ${runtimePrefix}_call_json_raw(const char* method,
                                   const char* args_json,
                                   char** result_json_out,
                                   char** error_out);
int ${runtimePrefix}_call_i64_2(const char* method,
                                int64_t a,
                                int64_t b,
                                int64_t* result_out,
                                char** error_out);
int ${runtimePrefix}_call_i64_2_index(int32_t method_id,
                                      int64_t a,
                                      int64_t b,
                                      int64_t* result_out,
                                      char** error_out);
int ${runtimePrefix}_call_i64_4(const char* method,
                                int64_t a,
                                int64_t b,
                                int64_t c,
                                int64_t d,
                                int64_t* result_out,
                                char** error_out);
int ${runtimePrefix}_call_i64_4_index(int32_t method_id,
                                      int64_t a,
                                      int64_t b,
                                      int64_t c,
                                      int64_t d,
                                      int64_t* result_out,
                                      char** error_out);
int ${runtimePrefix}_call_f64_2(const char* method,
                                double a,
                                double b,
                                double* result_out,
                                char** error_out);
int ${runtimePrefix}_call_f64_2_index(int32_t method_id,
                                      double a,
                                      double b,
                                      double* result_out,
                                      char** error_out);
int ${runtimePrefix}_call_f64_4(const char* method,
                                double a,
                                double b,
                                double c,
                                double d,
                                double* result_out,
                                char** error_out);
int ${runtimePrefix}_call_f64_4_index(int32_t method_id,
                                      double a,
                                      double b,
                                      double c,
                                      double d,
                                      double* result_out,
                                      char** error_out);
int ${runtimePrefix}_call_bytes(const char* method,
                                const uint8_t* args,
                                int32_t args_len,
                                uint8_t** result_out,
                                int32_t* result_len_out,
                                char** error_out);
int ${runtimePrefix}_call_bytes_index(int32_t method_id,
                                      const uint8_t* args,
                                      int32_t args_len,
                                      uint8_t** result_out,
                                      int32_t* result_len_out,
                                      char** error_out);
void ${runtimePrefix}_shutdown(void);
void ${runtimePrefix}_string_free(char* value);
void ${runtimePrefix}_bytes_free(uint8_t* value);
int ${runtimePrefix}_call(const char* function_name,
                          const char* args_json,
                          char** result_json_out,
                          char** error_out);
int ${runtimePrefix}_last_error_code(void);
int ${runtimePrefix}_last_error_json(char** error_json_out);

static inline int ${prefix}_abi_version(void) {
  return ${runtimePrefix}_abi_version();
}

static inline int ${prefix}_init(const char* runtime_path, char** error_out) {
  return ${runtimePrefix}_init(runtime_path, error_out);
}

static inline int ${prefix}_call_json(const char* method,
                                      const char* args_json,
                                      char** result_json_out,
                                      char** error_out) {
  return ${runtimePrefix}_call_json(method, args_json, result_json_out, error_out);
}

static inline int ${prefix}_call_json_batch(const char* batch_json,
                                            char** result_json_out,
                                            char** error_out) {
  return ${runtimePrefix}_call_json_batch(batch_json, result_json_out, error_out);
}

static inline int ${prefix}_call_json_raw(const char* method,
                                          const char* args_json,
                                          char** result_json_out,
                                          char** error_out) {
  return ${runtimePrefix}_call_json_raw(method, args_json, result_json_out, error_out);
}

static inline int ${prefix}_call_i64_2(const char* method,
                                       int64_t a,
                                       int64_t b,
                                       int64_t* result_out,
                                       char** error_out) {
  return ${runtimePrefix}_call_i64_2(method, a, b, result_out, error_out);
}

static inline int ${prefix}_call_i64_2_index(int32_t method_id,
                                              int64_t a,
                                              int64_t b,
                                              int64_t* result_out,
                                              char** error_out) {
  return ${runtimePrefix}_call_i64_2_index(method_id, a, b, result_out, error_out);
}

static inline int ${prefix}_call_i64_4(const char* method,
                                       int64_t a,
                                       int64_t b,
                                       int64_t c,
                                       int64_t d,
                                       int64_t* result_out,
                                       char** error_out) {
  return ${runtimePrefix}_call_i64_4(method, a, b, c, d, result_out, error_out);
}

static inline int ${prefix}_call_i64_4_index(int32_t method_id,
                                             int64_t a,
                                             int64_t b,
                                             int64_t c,
                                             int64_t d,
                                             int64_t* result_out,
                                             char** error_out) {
  return ${runtimePrefix}_call_i64_4_index(method_id, a, b, c, d, result_out, error_out);
}

static inline int ${prefix}_call_f64_2(const char* method,
                                       double a,
                                       double b,
                                       double* result_out,
                                       char** error_out) {
  return ${runtimePrefix}_call_f64_2(method, a, b, result_out, error_out);
}

static inline int ${prefix}_call_f64_2_index(int32_t method_id,
                                             double a,
                                             double b,
                                             double* result_out,
                                             char** error_out) {
  return ${runtimePrefix}_call_f64_2_index(method_id, a, b, result_out, error_out);
}

static inline int ${prefix}_call_f64_4(const char* method,
                                       double a,
                                       double b,
                                       double c,
                                       double d,
                                       double* result_out,
                                       char** error_out) {
  return ${runtimePrefix}_call_f64_4(method, a, b, c, d, result_out, error_out);
}

static inline int ${prefix}_call_f64_4_index(int32_t method_id,
                                             double a,
                                             double b,
                                             double c,
                                             double d,
                                             double* result_out,
                                             char** error_out) {
  return ${runtimePrefix}_call_f64_4_index(
      method_id, a, b, c, d, result_out, error_out);
}

static inline int ${prefix}_call_bytes(const char* method,
                                       const uint8_t* args,
                                       int32_t args_len,
                                       uint8_t** result_out,
                                       int32_t* result_len_out,
                                       char** error_out) {
  return ${runtimePrefix}_call_bytes(
      method, args, args_len, result_out, result_len_out, error_out);
}

static inline int ${prefix}_call_bytes_index(int32_t method_id,
                                             const uint8_t* args,
                                             int32_t args_len,
                                             uint8_t** result_out,
                                             int32_t* result_len_out,
                                             char** error_out) {
  return ${runtimePrefix}_call_bytes_index(
      method_id, args, args_len, result_out, result_len_out, error_out);
}

static inline void ${prefix}_shutdown(void) {
  ${runtimePrefix}_shutdown();
}

static inline void ${prefix}_string_free(char* value) {
  ${runtimePrefix}_string_free(value);
}

static inline void ${prefix}_bytes_free(uint8_t* value) {
  ${runtimePrefix}_bytes_free(value);
}

static inline int ${prefix}_last_error_code(void) {
  return ${runtimePrefix}_last_error_code();
}

static inline int ${prefix}_last_error_json(char** error_json_out) {
  return ${runtimePrefix}_last_error_json(error_json_out);
}

$wrappers
$typedBlock
#ifdef __cplusplus
}
#endif

#endif
''';
}

String _generateArtifactManifest({
  required String moduleName,
  required String sourcePath,
  required String outputPath,
  required String? libraryFileName,
  required String? runtimeFileName,
  required String? runtimePath,
  required String runtimeExpectedSdkVersion,
  required String runtimeProfile,
  required DateTime generatedAtUtc,
  required bool reproducibleBuild,
  required String requestedTarget,
  required String effectiveTarget,
  required Map<String, Object?> mobileOutputs,
  required String bridgeSourcePath,
  required String bridgeSourceSha256,
  required bool symbolsExported,
  required Map<String, String> checksums,
  required List<ExportedFunction> exports,
}) {
  final includeDir = p.join(outputPath, 'include');
  final libDir = p.join(outputPath, 'lib');
  final runtimeDir = p.join(outputPath, 'runtime');
  final integrationDir = p.join(outputPath, 'integration');
  final target = _hostTargetId();
  final runtimePrefix = _moduleRuntimePrefix(moduleName);
  final i64_2MethodIds = _computeI64_2MethodIds(exports);
  final i64_4MethodIds = _computeI64_4MethodIds(exports);
  final f64_2MethodIds = _computeF64_2MethodIds(exports);
  final f64_4MethodIds = _computeF64_4MethodIds(exports);
  final bytesMethodIds = _computeBytesMethodIds(exports);

  final json = <String, Object?>{
    'schema': 'dllart-artifact-v1',
    'module': moduleName,
    'target': target,
    'generated_at': generatedAtUtc.toIso8601String(),
    'abi': <String, Object?>{
      'major': 1,
      'minor': 1,
      'patch': 0,
      'policy':
          'Backward-compatible additive changes are allowed within a major version.',
    },
    'build': <String, Object?>{
      'reproducible': reproducibleBuild,
      'requested_target': requestedTarget,
      'effective_target': effectiveTarget,
      'host_target': target,
      'source_date_epoch': Platform.environment['SOURCE_DATE_EPOCH'],
      if (mobileOutputs.isNotEmpty) 'mobile_outputs': mobileOutputs,
      'bridge': <String, Object?>{
        'source': bridgeSourcePath,
        'sha256': bridgeSourceSha256,
      },
    },
    'source': sourcePath,
    'paths': <String, Object?>{
      'root': outputPath,
      'include': includeDir,
      'lib': libDir,
      if (libraryFileName != null) 'library': p.join(libDir, libraryFileName),
      if (runtimePath != null) 'runtime': runtimeDir,
      if (runtimePath != null) 'runtime_binary': runtimePath,
      'integration': integrationDir,
      'module_api_header': p.join(includeDir, '${moduleName}_api.h'),
    },
    'runtime': <String, Object?>{
      if (runtimeFileName != null) 'binary': runtimeFileName,
      'bundled': runtimePath != null,
      'expected_sdk_version': runtimeExpectedSdkVersion,
      'profile': runtimeProfile,
      if (runtimeFileName != null)
        'lookup_order': <String>[
          'runtime_path argument of *_init',
          'DLLART_DART_RUNTIME env',
          '<library_dir>/$runtimeFileName',
          '<library_dir>/runtime/$runtimeFileName',
          '<library_dir>/../runtime/$runtimeFileName',
          'build-time DLLART_DEFAULT_RUNTIME_PATH',
        ],
    },
    'symbols': <String, Object?>{
      'abi_version': '${runtimePrefix}_abi_version',
      'init': '${runtimePrefix}_init',
      'call_json': '${runtimePrefix}_call_json',
      'call_json_batch': '${runtimePrefix}_call_json_batch',
      'call_json_raw': '${runtimePrefix}_call_json_raw',
      'call_i64_2': '${runtimePrefix}_call_i64_2',
      'call_i64_2_index': '${runtimePrefix}_call_i64_2_index',
      'call_i64_4': '${runtimePrefix}_call_i64_4',
      'call_i64_4_index': '${runtimePrefix}_call_i64_4_index',
      'call_f64_2': '${runtimePrefix}_call_f64_2',
      'call_f64_2_index': '${runtimePrefix}_call_f64_2_index',
      'call_f64_4': '${runtimePrefix}_call_f64_4',
      'call_f64_4_index': '${runtimePrefix}_call_f64_4_index',
      'call_bytes': '${runtimePrefix}_call_bytes',
      'call_bytes_index': '${runtimePrefix}_call_bytes_index',
      'last_error_code': '${runtimePrefix}_last_error_code',
      'last_error_json': '${runtimePrefix}_last_error_json',
      'shutdown': '${runtimePrefix}_shutdown',
      'string_free': '${runtimePrefix}_string_free',
      'bytes_free': '${runtimePrefix}_bytes_free',
    },
    'checksums': <String, Object?>{
      if (checksums['library_sha256'] != null)
        'library_sha256': checksums['library_sha256'],
      if (checksums['runtime_sha256'] != null)
        'runtime_sha256': checksums['runtime_sha256'],
      'module_api_header_sha256': checksums['module_api_header_sha256'],
      'manifest_sha256': '',
    },
    'verification': <String, Object?>{'symbols_exported': symbolsExported},
    'exports': exports
        .map(
          (item) => <String, Object?>{
            'name': item.exportName,
            'dart_name': item.dartName,
            'arity': item.arity,
            'supports_i64_2': item.supportsI64_2,
            'direct_i64_2': item.directI64_2,
            'i64_2_method_id': item.supportsI64_2
                ? i64_2MethodIds[item.exportName]
                : null,
            'supports_i64_4': item.supportsI64_4,
            'direct_i64_4': item.directI64_4,
            'i64_4_method_id': item.supportsI64_4
                ? i64_4MethodIds[item.exportName]
                : null,
            'supports_f64_2': item.supportsF64_2,
            'direct_f64_2': item.directF64_2,
            'f64_2_method_id': item.supportsF64_2
                ? f64_2MethodIds[item.exportName]
                : null,
            'supports_f64_4': item.supportsF64_4,
            'direct_f64_4': item.directF64_4,
            'f64_4_method_id': item.supportsF64_4
                ? f64_4MethodIds[item.exportName]
                : null,
            'supports_bytes': item.supportsBytes,
            'direct_bytes': item.directBytes,
            'bytes_method_id': item.supportsBytes
                ? bytesMethodIds[item.exportName]
                : null,
          },
        )
        .toList(),
  };

  final digestInput = const JsonEncoder.withIndent('  ').convert(json) + '\n';
  final manifestDigest = _sha256Text(digestInput);
  (json['checksums'] as Map<String, Object?>)['manifest_sha256'] =
      manifestDigest;

  return const JsonEncoder.withIndent('  ').convert(json) + '\n';
}

String _generateArtifactUsage({
  required String moduleName,
  required String outputPath,
  required String libraryFileName,
  required String runtimeFileName,
  required String runtimeExpectedSdkVersion,
}) {
  final rootRel = p.relative(outputPath, from: Directory.current.path);
  final includeRel = p.join(rootRel, 'include');
  final libRel = p.join(rootRel, 'lib');
  final cmakeRel = p.join(
    rootRel,
    'integration',
    'cmake',
    '${moduleName}Config.cmake',
  );
  final target = _hostTargetId();
  final runtimePrefix = _moduleRuntimePrefix(moduleName);
  final wrapperClass = '${_upperCamelCase(moduleName)}Client';

  return '''# DLLART Artifact Usage

Module: `$moduleName`
Target: `$target`

## Files

- Headers: `$includeRel`
- Library: `$libRel/$libraryFileName`
- Runtime: `$rootRel/runtime/$runtimeFileName`
- CMake config: `$cmakeRel`

Runtime expected SDK version: `$runtimeExpectedSdkVersion`

## C/C++ (manual)

```bash
clang your_app.c -I$includeRel -L$libRel -l$moduleName
```

## CMake

```cmake
include("$cmakeRel")
target_link_libraries(your_target PRIVATE ${moduleName}::${moduleName})
```

## Python (scaffold)

```bash
dllart package python
python3 "$rootRel/package/python/example.py"
```

```python
from bindings import $wrapperClass

mod = $wrapperClass()
mod.init()
print(mod.call_json("add", '{"a": 20, "b": 22}'))
mod.shutdown()
```

## C# (scaffold)

```bash
dllart package csharp
dotnet run --project "$rootRel/package/csharp/DllartScaffold.csproj"
```

```csharp
using var mod = new $wrapperClass();
mod.Init();
Console.WriteLine(mod.CallJson("add", "{\\"a\\":20,\\"b\\":22}"));
mod.Shutdown();
```

## Python ctypes (low-level symbols)

```python
import ctypes
lib = ctypes.CDLL("$libRel/$libraryFileName")
init = lib.${runtimePrefix}_init
call_json = lib.${runtimePrefix}_call_json
call_json_batch = lib.${runtimePrefix}_call_json_batch
call_json_raw = lib.${runtimePrefix}_call_json_raw
call_i64_2 = lib.${runtimePrefix}_call_i64_2
call_i64_2_index = lib.${runtimePrefix}_call_i64_2_index
call_i64_4 = lib.${runtimePrefix}_call_i64_4
call_i64_4_index = lib.${runtimePrefix}_call_i64_4_index
call_f64_2 = lib.${runtimePrefix}_call_f64_2
call_f64_2_index = lib.${runtimePrefix}_call_f64_2_index
call_f64_4 = lib.${runtimePrefix}_call_f64_4
call_f64_4_index = lib.${runtimePrefix}_call_f64_4_index
call_bytes = lib.${runtimePrefix}_call_bytes
call_bytes_index = lib.${runtimePrefix}_call_bytes_index
last_error_code = lib.${runtimePrefix}_last_error_code
last_error_json = lib.${runtimePrefix}_last_error_json
bytes_free = lib.${runtimePrefix}_bytes_free
```

Initialization tip:

- pass `NULL` / `nullptr` as `runtime_path` to `${runtimePrefix}_init`.
- runtime auto-lookup checks:
  - `DLLART_DART_RUNTIME`
  - runtime next to library
  - `../runtime/$runtimeFileName` relative to library

## Mobile scaffold

```bash
dllart package all
```
''';
}

String _generateCMakeConfig({
  required String moduleName,
  required String libraryFileName,
}) {
  final upper = _sanitizeForC(moduleName).toUpperCase();

  return '''# Auto-generated by dllart.
set(DLLART_${upper}_ROOT "\${CMAKE_CURRENT_LIST_DIR}/../..")
set(DLLART_${upper}_INCLUDE_DIR "\${DLLART_${upper}_ROOT}/include")
set(DLLART_${upper}_LIBRARY "\${DLLART_${upper}_ROOT}/lib/$libraryFileName")

if(NOT TARGET ${moduleName}::${moduleName})
  add_library(${moduleName}::${moduleName} SHARED IMPORTED)
  set_target_properties(${moduleName}::${moduleName} PROPERTIES
    IMPORTED_LOCATION "\${DLLART_${upper}_LIBRARY}"
    INTERFACE_INCLUDE_DIRECTORIES "\${DLLART_${upper}_INCLUDE_DIR}"
  )
endif()
''';
}

String _generatePkgConfig({required String moduleName}) {
  return '''prefix=\${pcfiledir}/../..
includedir=\${prefix}/include
libdir=\${prefix}/lib

Name: $moduleName
Description: DLLART module $moduleName
Version: 0.1.0
Cflags: -I\${includedir}
Libs: -L\${libdir} -l$moduleName
''';
}
