part of dllart_cli;

class ToolError implements Exception {
  ToolError(this.message);

  final String message;

  @override
  String toString() => message;
}

class ConfigValidationError implements Exception {
  ConfigValidationError(this.message, {this.field});

  final String message;
  final String? field;

  @override
  String toString() => message;
}

class ParsedArgs {
  ParsedArgs(this.positional, this.options);

  final List<String> positional;
  final Map<String, String> options;

  String? operator [](String key) => options[key];

  bool hasFlag(String key) {
    final value = options[key];
    if (value == null) {
      return false;
    }
    return value.toLowerCase() != 'false';
  }
}

class DllartProtobufConfig {
  DllartProtobufConfig({
    required this.proto,
    required this.out,
    required this.includes,
    required this.grpc,
    this.protoc,
  });

  final String proto;
  final String out;
  final List<String> includes;
  final bool grpc;
  final String? protoc;

  static const Set<String> allowedKeys = <String>{
    'proto',
    'out',
    'includes',
    'grpc',
    'protoc',
  };

  Map<String, Object> toJson() {
    return <String, Object>{
      'proto': proto,
      'out': out,
      'includes': includes,
      'grpc': grpc,
      if (protoc != null) 'protoc': protoc!,
    };
  }

  static DllartProtobufConfig fromJson(Object? raw) {
    if (raw is! Map) {
      throw ConfigValidationError(
        'Config field "protobuf" must be an object',
        field: 'protobuf',
      );
    }

    final map = <String, Object?>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String) {
        throw ConfigValidationError(
          'Config field "protobuf" must use string keys',
          field: 'protobuf',
        );
      }
      map[key] = entry.value;
    }

    final unknownKeys =
        map.keys.where((key) => !allowedKeys.contains(key)).toList()..sort();
    if (unknownKeys.isNotEmpty) {
      final unknownRendered = unknownKeys.map((key) => '"$key"').join(', ');
      final allowedRendered = allowedKeys.toList()..sort();
      throw ConfigValidationError(
        'Unknown field(s) in "protobuf": $unknownRendered. '
        'Allowed fields: ${allowedRendered.map((key) => '"$key"').join(', ')}',
        field: 'protobuf',
      );
    }

    final proto = map['proto'];
    if (proto is! String || proto.trim().isEmpty) {
      throw ConfigValidationError(
        'Config field "protobuf.proto" must be a non-empty string',
        field: 'proto',
      );
    }

    final out = map['out'];
    final resolvedOut = out == null
        ? p.join('lib', 'generated', 'proto')
        : out is String && out.trim().isNotEmpty
        ? out.trim()
        : throw ConfigValidationError(
            'Config field "protobuf.out" must be a non-empty string when provided',
            field: 'out',
          );

    final includesRaw = map['includes'];
    final includes = <String>[];
    if (includesRaw != null) {
      if (includesRaw is! List) {
        throw ConfigValidationError(
          'Config field "protobuf.includes" must be an array of strings',
          field: 'includes',
        );
      }
      for (final value in includesRaw) {
        if (value is! String || value.trim().isEmpty) {
          throw ConfigValidationError(
            'Config field "protobuf.includes" must contain only non-empty strings',
            field: 'includes',
          );
        }
        includes.add(value.trim());
      }
    }

    final grpcRaw = map['grpc'];
    final grpc = grpcRaw == null
        ? false
        : grpcRaw is bool
        ? grpcRaw
        : throw ConfigValidationError(
            'Config field "protobuf.grpc" must be a boolean',
            field: 'grpc',
          );

    final protocRaw = map['protoc'];
    final protoc = protocRaw == null
        ? null
        : protocRaw is String && protocRaw.trim().isNotEmpty
        ? protocRaw.trim()
        : throw ConfigValidationError(
            'Config field "protobuf.protoc" must be a non-empty string when provided',
            field: 'protoc',
          );

    return DllartProtobufConfig(
      proto: proto.trim(),
      out: resolvedOut,
      includes: includes,
      grpc: grpc,
      protoc: protoc,
    );
  }
}

class DllartLimitsConfig {
  DllartLimitsConfig({
    required this.jsonInMaxBytes,
    required this.jsonOutMaxBytes,
    required this.bytesInMaxBytes,
    required this.bytesOutMaxBytes,
    required this.methodCacheMaxEntries,
  });

  final int jsonInMaxBytes;
  final int jsonOutMaxBytes;
  final int bytesInMaxBytes;
  final int bytesOutMaxBytes;
  final int methodCacheMaxEntries;

  static const int defaultJsonInMaxBytes = 1 * 1024 * 1024;
  static const int defaultJsonOutMaxBytes = 8 * 1024 * 1024;
  static const int defaultBytesInMaxBytes = 4 * 1024 * 1024;
  static const int defaultBytesOutMaxBytes = 16 * 1024 * 1024;
  static const int defaultMethodCacheMaxEntries = 2048;

  static const Set<String> allowedKeys = <String>{
    'json_in_max_bytes',
    'json_out_max_bytes',
    'bytes_in_max_bytes',
    'bytes_out_max_bytes',
    'method_cache_max_entries',
  };

  factory DllartLimitsConfig.defaults() {
    return DllartLimitsConfig(
      jsonInMaxBytes: defaultJsonInMaxBytes,
      jsonOutMaxBytes: defaultJsonOutMaxBytes,
      bytesInMaxBytes: defaultBytesInMaxBytes,
      bytesOutMaxBytes: defaultBytesOutMaxBytes,
      methodCacheMaxEntries: defaultMethodCacheMaxEntries,
    );
  }

  Map<String, Object> toJson() {
    return <String, Object>{
      'json_in_max_bytes': jsonInMaxBytes,
      'json_out_max_bytes': jsonOutMaxBytes,
      'bytes_in_max_bytes': bytesInMaxBytes,
      'bytes_out_max_bytes': bytesOutMaxBytes,
      'method_cache_max_entries': methodCacheMaxEntries,
    };
  }

  static DllartLimitsConfig fromJson(Object? raw) {
    if (raw is! Map) {
      throw ConfigValidationError(
        'Config field "limits" must be an object',
        field: 'limits',
      );
    }

    final map = <String, Object?>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String) {
        throw ConfigValidationError(
          'Config field "limits" must use string keys',
          field: 'limits',
        );
      }
      map[key] = entry.value;
    }

    final unknownKeys =
        map.keys.where((key) => !allowedKeys.contains(key)).toList()..sort();
    if (unknownKeys.isNotEmpty) {
      final unknownRendered = unknownKeys.map((key) => '"$key"').join(', ');
      final allowedRendered = allowedKeys.toList()..sort();
      throw ConfigValidationError(
        'Unknown field(s) in "limits": $unknownRendered. '
        'Allowed fields: ${allowedRendered.map((key) => '"$key"').join(', ')}',
        field: 'limits',
      );
    }

    int parseLimit(String key, int fallback) {
      final value = map[key];
      if (value == null) {
        return fallback;
      }
      if (value is! num || value.isNaN || value.isInfinite) {
        throw ConfigValidationError(
          'Config field "limits.$key" must be a positive integer',
          field: key,
        );
      }
      final asInt = value.toInt();
      if (asInt <= 0) {
        throw ConfigValidationError(
          'Config field "limits.$key" must be greater than 0',
          field: key,
        );
      }
      return asInt;
    }

    return DllartLimitsConfig(
      jsonInMaxBytes: parseLimit('json_in_max_bytes', defaultJsonInMaxBytes),
      jsonOutMaxBytes: parseLimit(
        'json_out_max_bytes',
        defaultJsonOutMaxBytes,
      ),
      bytesInMaxBytes: parseLimit(
        'bytes_in_max_bytes',
        defaultBytesInMaxBytes,
      ),
      bytesOutMaxBytes: parseLimit(
        'bytes_out_max_bytes',
        defaultBytesOutMaxBytes,
      ),
      methodCacheMaxEntries: parseLimit(
        'method_cache_max_entries',
        defaultMethodCacheMaxEntries,
      ),
    );
  }
}

class DllartRuntimeConfig {
  DllartRuntimeConfig({required this.profile});

  final String profile;

  static const String defaultProfile = 'full';
  static const Set<String> allowedProfiles = <String>{'full', 'slim'};
  static const Set<String> allowedKeys = <String>{'profile'};

  factory DllartRuntimeConfig.defaults() {
    return DllartRuntimeConfig(profile: defaultProfile);
  }

  Map<String, Object> toJson() {
    return <String, Object>{'profile': profile};
  }

  static DllartRuntimeConfig fromJson(Object? raw) {
    if (raw is! Map) {
      throw ConfigValidationError(
        'Config field "runtime" must be an object',
        field: 'runtime',
      );
    }

    final map = <String, Object?>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String) {
        throw ConfigValidationError(
          'Config field "runtime" must use string keys',
          field: 'runtime',
        );
      }
      map[key] = entry.value;
    }

    final unknownKeys =
        map.keys.where((key) => !allowedKeys.contains(key)).toList()..sort();
    if (unknownKeys.isNotEmpty) {
      final unknownRendered = unknownKeys.map((key) => '"$key"').join(', ');
      final allowedRendered = allowedKeys.toList()..sort();
      throw ConfigValidationError(
        'Unknown field(s) in "runtime": $unknownRendered. '
        'Allowed fields: ${allowedRendered.map((key) => '"$key"').join(', ')}',
        field: 'runtime',
      );
    }

    final profileRaw = map['profile'];
    if (profileRaw == null) {
      return DllartRuntimeConfig.defaults();
    }
    if (profileRaw is! String || profileRaw.trim().isEmpty) {
      throw ConfigValidationError(
        'Config field "runtime.profile" must be a non-empty string',
        field: 'profile',
      );
    }
    final profile = profileRaw.trim().toLowerCase();
    if (!allowedProfiles.contains(profile)) {
      throw ConfigValidationError(
        'Unsupported runtime profile "$profile". '
        'Supported values: ${allowedProfiles.toList()..sort()}',
        field: 'profile',
      );
    }
    return DllartRuntimeConfig(profile: profile);
  }
}

class DllartLoggingConfig {
  DllartLoggingConfig({required this.format, required this.level});

  final String format;
  final String level;

  static const String defaultFormat = 'text';
  static const String defaultLevel = 'info';
  static const Set<String> allowedFormats = <String>{'text', 'json'};
  static const Set<String> allowedLevels = <String>{'error', 'warn', 'info'};
  static const Set<String> allowedKeys = <String>{'format', 'level'};

  factory DllartLoggingConfig.defaults() {
    return DllartLoggingConfig(format: defaultFormat, level: defaultLevel);
  }

  Map<String, Object> toJson() {
    return <String, Object>{'format': format, 'level': level};
  }

  static DllartLoggingConfig fromJson(Object? raw) {
    if (raw is! Map) {
      throw ConfigValidationError(
        'Config field "logging" must be an object',
        field: 'logging',
      );
    }

    final map = <String, Object?>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String) {
        throw ConfigValidationError(
          'Config field "logging" must use string keys',
          field: 'logging',
        );
      }
      map[key] = entry.value;
    }

    final unknownKeys =
        map.keys.where((key) => !allowedKeys.contains(key)).toList()..sort();
    if (unknownKeys.isNotEmpty) {
      final unknownRendered = unknownKeys.map((key) => '"$key"').join(', ');
      final allowedRendered = allowedKeys.toList()..sort();
      throw ConfigValidationError(
        'Unknown field(s) in "logging": $unknownRendered. '
        'Allowed fields: ${allowedRendered.map((key) => '"$key"').join(', ')}',
        field: 'logging',
      );
    }

    String parseEnum(
      String key,
      String fallback,
      Set<String> allowedValues,
    ) {
      final value = map[key];
      if (value == null) {
        return fallback;
      }
      if (value is! String || value.trim().isEmpty) {
        throw ConfigValidationError(
          'Config field "logging.$key" must be a non-empty string',
          field: key,
        );
      }
      final normalized = value.trim().toLowerCase();
      if (!allowedValues.contains(normalized)) {
        throw ConfigValidationError(
          'Unsupported logging.$key value "$normalized". '
          'Supported values: ${allowedValues.toList()..sort()}',
          field: key,
        );
      }
      return normalized;
    }

    return DllartLoggingConfig(
      format: parseEnum('format', defaultFormat, allowedFormats),
      level: parseEnum('level', defaultLevel, allowedLevels),
    );
  }
}

class DllartConfig {
  DllartConfig({
    required this.name,
    required this.source,
    required this.output,
    required this.targets,
    DllartLimitsConfig? limits,
    DllartRuntimeConfig? runtime,
    DllartLoggingConfig? logging,
    this.protobuf,
  }) : limits = limits ?? DllartLimitsConfig.defaults(),
       runtime = runtime ?? DllartRuntimeConfig.defaults(),
       logging = logging ?? DllartLoggingConfig.defaults();

  final String name;
  final String source;
  final String output;
  final List<String> targets;
  final DllartLimitsConfig limits;
  final DllartRuntimeConfig runtime;
  final DllartLoggingConfig logging;
  final DllartProtobufConfig? protobuf;

  static const List<String> defaultTargets = <String>[
    'macos-arm64',
    'macos-x64',
    'linux-x64',
    'windows-x64',
  ];
  static const Set<String> supportedTargets = <String>{
    'macos-arm64',
    'macos-x64',
    'linux-x64',
    'windows-x64',
  };
  static const Set<String> allowedKeys = <String>{
    'name',
    'source',
    'output',
    'targets',
    'limits',
    'runtime',
    'logging',
    'protobuf',
  };

  Map<String, Object> toJson() {
    return <String, Object>{
      'name': name,
      'source': source,
      'output': output,
      'targets': targets,
      'limits': limits.toJson(),
      'runtime': runtime.toJson(),
      'logging': logging.toJson(),
      if (protobuf != null) 'protobuf': protobuf!.toJson(),
    };
  }

  static DllartConfig fromJson(Object? raw) {
    if (raw is! Map) {
      throw ConfigValidationError('dllart config must be a JSON object');
    }

    final map = <String, Object?>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String) {
        throw ConfigValidationError('Config keys must be strings');
      }
      map[key] = entry.value;
    }

    final unknownKeys =
        map.keys.where((key) => !allowedKeys.contains(key)).toList()..sort();
    if (unknownKeys.isNotEmpty) {
      final unknownRendered = unknownKeys.map((key) => '"$key"').join(', ');
      final allowedRendered = allowedKeys.toList()..sort();
      throw ConfigValidationError(
        'Unknown field(s): $unknownRendered. Allowed fields: ${allowedRendered.map((key) => '"$key"').join(', ')}',
        field: unknownKeys.length == 1 ? unknownKeys.first : null,
      );
    }

    final name = map['name'];
    final source = map['source'];

    if (name is! String || name.trim().isEmpty) {
      throw ConfigValidationError(
        'Config field "name" must be a non-empty string',
        field: 'name',
      );
    }
    if (source is! String || source.trim().isEmpty) {
      throw ConfigValidationError(
        'Config field "source" must be a non-empty string',
        field: 'source',
      );
    }

    final output = map['output'];
    final targets = map['targets'];
    final limitsRaw = map['limits'];
    final runtimeRaw = map['runtime'];
    final loggingRaw = map['logging'];
    final protobufRaw = map['protobuf'];

    final resolvedOutput = output == null
        ? 'build'
        : output is String && output.trim().isNotEmpty
        ? output.trim()
        : throw ConfigValidationError(
            'Config field "output" must be a non-empty string when provided',
            field: 'output',
          );

    final resolvedTargets = <String>[...defaultTargets];
    if (targets != null) {
      if (targets is! List) {
        throw ConfigValidationError(
          'Config field "targets" must be an array of strings',
          field: 'targets',
        );
      }
      if (targets.isEmpty) {
        throw ConfigValidationError(
          'Config field "targets" must not be empty when provided',
          field: 'targets',
        );
      }

      final seen = <String>{};
      final strictTargets = <String>[];
      for (final value in targets) {
        if (value is! String || value.trim().isEmpty) {
          throw ConfigValidationError(
            'Config field "targets" must contain only non-empty strings',
            field: 'targets',
          );
        }
        final normalized = value.trim();
        if (!supportedTargets.contains(normalized)) {
          throw ConfigValidationError(
            'Unsupported target "$normalized". Supported values: '
            '${supportedTargets.toList()..sort()}',
            field: 'targets',
          );
        }
        if (!seen.add(normalized)) {
          throw ConfigValidationError(
            'Duplicate target "$normalized" in "targets"',
            field: 'targets',
          );
        }
        strictTargets.add(normalized);
      }
      resolvedTargets
        ..clear()
        ..addAll(strictTargets);
    }

    final protobuf = protobufRaw == null
        ? null
        : DllartProtobufConfig.fromJson(protobufRaw);
    final limits = limitsRaw == null
        ? DllartLimitsConfig.defaults()
        : DllartLimitsConfig.fromJson(limitsRaw);
    final runtime = runtimeRaw == null
        ? DllartRuntimeConfig.defaults()
        : DllartRuntimeConfig.fromJson(runtimeRaw);
    final logging = loggingRaw == null
        ? DllartLoggingConfig.defaults()
        : DllartLoggingConfig.fromJson(loggingRaw);

    return DllartConfig(
      name: name.trim(),
      source: source.trim(),
      output: resolvedOutput,
      targets: resolvedTargets,
      limits: limits,
      runtime: runtime,
      logging: logging,
      protobuf: protobuf,
    );
  }
}

class LoadedConfig {
  LoadedConfig({required this.config, required this.configPath});

  final DllartConfig config;
  final String configPath;

  String get configDir => p.dirname(configPath);

  String resolvePath(String filePath) {
    if (p.isAbsolute(filePath)) {
      return p.normalize(filePath);
    }
    return p.normalize(p.join(configDir, filePath));
  }
}

class ExportedFunction {
  ExportedFunction({
    required this.dartName,
    required this.exportName,
    required this.arity,
    required this.supportsI64_2,
    required this.directI64_2,
    required this.supportsI64_4,
    required this.directI64_4,
    required this.supportsF64_2,
    required this.directF64_2,
    required this.supportsF64_4,
    required this.directF64_4,
    required this.supportsBytes,
    required this.directBytes,
    required this.line,
  });

  final String dartName;
  final String exportName;
  final int arity;
  final bool supportsI64_2;
  final bool directI64_2;
  final bool supportsI64_4;
  final bool directI64_4;
  final bool supportsF64_2;
  final bool directF64_2;
  final bool supportsF64_4;
  final bool directF64_4;
  final bool supportsBytes;
  final bool directBytes;
  final int line;
}

class Toolchain {
  Toolchain({
    required this.dart,
    required this.dartaot,
    required this.dartSdkVersion,
    required this.sdkRoot,
    required this.frontendServer,
    required this.genSnapshot,
    required this.platformDill,
    required this.sdkInclude,
    required this.clang,
  });

  final String dart;
  final String dartaot;
  final String dartSdkVersion;
  final String sdkRoot;
  final String frontendServer;
  final String genSnapshot;
  final String platformDill;
  final String sdkInclude;
  final String clang;
}

enum DoctorStatus { ok, warn, fail }

class DoctorItem {
  DoctorItem(this.status, this.title, this.detail);

  final DoctorStatus status;
  final String title;
  final String detail;

  Map<String, String> toJson() {
    final statusName = switch (status) {
      DoctorStatus.ok => 'ok',
      DoctorStatus.warn => 'warn',
      DoctorStatus.fail => 'fail',
    };
    return <String, String>{
      'status': statusName,
      'title': title,
      'detail': detail,
    };
  }
}

class DoctorReport {
  final List<DoctorItem> _items = <DoctorItem>[];

  void ok(String title, String detail) {
    _items.add(DoctorItem(DoctorStatus.ok, title, detail));
  }

  void warn(String title, String detail) {
    _items.add(DoctorItem(DoctorStatus.warn, title, detail));
  }

  void fail(String title, String detail) {
    _items.add(DoctorItem(DoctorStatus.fail, title, detail));
  }

  int get okCount =>
      _items.where((item) => item.status == DoctorStatus.ok).length;
  int get warnCount =>
      _items.where((item) => item.status == DoctorStatus.warn).length;
  int get failCount =>
      _items.where((item) => item.status == DoctorStatus.fail).length;

  bool get hasFailures => failCount > 0;
  List<DoctorItem> get items => List<DoctorItem>.unmodifiable(_items);

  Map<String, Object> toJson() {
    final status = hasFailures
        ? 'fail'
        : warnCount > 0
        ? 'warn'
        : 'ok';
    return <String, Object>{
      'status': status,
      'summary': <String, int>{
        'ok': okCount,
        'warnings': warnCount,
        'failures': failCount,
      },
      'items': items.map((item) => item.toJson()).toList(),
    };
  }

  void print() {
    stdout.writeln('DLLART Doctor Report');
    for (final item in _items) {
      final label = switch (item.status) {
        DoctorStatus.ok => 'OK',
        DoctorStatus.warn => 'WARN',
        DoctorStatus.fail => 'FAIL',
      };
      stdout.writeln('[$label] ${item.title}: ${item.detail}');
    }
    stdout.writeln(
      'Summary: $okCount ok, $warnCount warnings, $failCount failures',
    );
  }
}
