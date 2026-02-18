part of dllart_cli;

class _ResolvedProtoGeneration {
  const _ResolvedProtoGeneration({
    required this.protoPath,
    required this.outDir,
    required this.includeDirs,
    required this.grpc,
    required this.protocExecutable,
    required this.protocPluginExecutable,
    this.configPath,
  });

  final String protoPath;
  final String outDir;
  final List<String> includeDirs;
  final bool grpc;
  final String protocExecutable;
  final String protocPluginExecutable;
  final String? configPath;
}

Future<void> _commandProto(ParsedArgs args) async {
  _applyLoggingFromConfig(null);
  final jsonMode = _isJsonMode(args);
  final loaded = _loadConfigForProto(args);
  if (loaded != null) {
    _applyLoggingFromConfig(loaded.config);
  }
  final resolved = _resolveProtoGeneration(args, loaded);

  final protoFile = File(resolved.protoPath);
  if (!protoFile.existsSync()) {
    throw ToolError('Proto file not found: ${resolved.protoPath}');
  }
  if (!resolved.protoPath.toLowerCase().endsWith('.proto')) {
    throw ToolError(
      'Proto source must use .proto extension: ${resolved.protoPath}',
    );
  }

  final outDir = Directory(resolved.outDir);
  outDir.createSync(recursive: true);

  final protocArgs = _buildProtocArgs(resolved);
  _logLine('Generating Dart protobuf sources...', verboseOnly: false);
  _logLine('protoc executable: ${resolved.protocExecutable}');
  _logLine('protoc plugin:     ${resolved.protocPluginExecutable}');
  _logLine('proto source:      ${_displayPath(resolved.protoPath)}');
  _logLine('dart output:       ${_displayPath(resolved.outDir)}');
  await _runCommand(resolved.protocExecutable, protocArgs);

  final generated = _collectGeneratedProtoFiles(resolved.outDir);

  if (jsonMode) {
    _writeJsonCommandResult(
      'proto',
      ok: true,
      status: 'ok',
      data: <String, Object?>{
        'proto': _displayPath(resolved.protoPath),
        'out_dir': _displayPath(resolved.outDir),
        'grpc': resolved.grpc,
        'includes': resolved.includeDirs.map(_displayPath).toList(),
        'protoc': resolved.protocExecutable,
        'protoc_gen_dart': resolved.protocPluginExecutable,
        'generated_files': generated.map(_displayPath).toList(),
        if (resolved.configPath != null)
          'config': _displayPath(resolved.configPath!),
      },
    );
    return;
  }

  stdout.writeln('Generated protobuf Dart sources.');
  stdout.writeln('Proto:      ${_displayPath(resolved.protoPath)}');
  stdout.writeln('Output dir: ${_displayPath(resolved.outDir)}');
  stdout.writeln('Mode:       ${resolved.grpc ? 'grpc' : 'protobuf'}');
  stdout.writeln('Files:      ${generated.length}');
  if (generated.isNotEmpty) {
    for (final path in generated) {
      stdout.writeln('  - ${_displayPath(path)}');
    }
  } else {
    stdout.writeln('  (No generated *.pb*.dart files detected.)');
  }
}

LoadedConfig? _loadConfigForProto(ParsedArgs args) {
  final explicitConfig = args['config'];
  if (explicitConfig != null && explicitConfig.trim().isNotEmpty) {
    return _loadConfig(args, allowInferred: false);
  }

  final defaultConfig = p.normalize(p.absolute('dllart.json'));
  if (File(defaultConfig).existsSync()) {
    return _loadConfig(args, allowInferred: false);
  }

  return null;
}

_ResolvedProtoGeneration _resolveProtoGeneration(
  ParsedArgs args,
  LoadedConfig? loaded,
) {
  final baseDir = loaded?.configDir ?? Directory.current.path;
  final protobuf = loaded?.config.protobuf;
  final positionalProto = args.positional.isNotEmpty
      ? args.positional.first
      : null;

  String? protoRaw = _firstNonEmpty(<String?>[
    args['proto'],
    positionalProto,
    protobuf?.proto,
  ]);
  protoRaw ??= _inferProtoSource(baseDir, moduleName: loaded?.config.name);

  if (protoRaw == null) {
    throw ToolError(
      'Proto source is not configured. Use `dllart proto <path>` or '
      '`--proto=<path>`, or set "protobuf.proto" in dllart.json.',
    );
  }

  final outRaw =
      _firstNonEmpty(<String?>[args['out'], protobuf?.out]) ??
      p.join('lib', 'generated', 'proto');

  final includeRaw = args['include'];
  final includeTokens = includeRaw != null && includeRaw.trim().isNotEmpty
      ? _parsePathList(includeRaw)
      : List<String>.from(protobuf?.includes ?? const <String>[]);

  final protoPath = _resolvePathFromBase(baseDir, protoRaw);
  final outDir = _resolvePathFromBase(baseDir, outRaw);

  final includeDirs = <String>[];
  void addInclude(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      return;
    }
    final resolved = _resolvePathFromBase(baseDir, value);
    if (!includeDirs.contains(resolved)) {
      includeDirs.add(resolved);
    }
  }

  for (final include in includeTokens) {
    addInclude(include);
  }

  final defaultProtoRoot = p.join(baseDir, 'proto');
  if (Directory(defaultProtoRoot).existsSync()) {
    addInclude(defaultProtoRoot);
  }
  addInclude(p.dirname(protoPath));

  final grpc = args.options.containsKey('grpc')
      ? args.hasFlag('grpc')
      : (protobuf?.grpc ?? false);

  final protocRaw =
      _firstNonEmpty(<String?>[args['protoc'], protobuf?.protoc]) ??
      _defaultProtocExecutableName();
  final protocExecutable = _resolveProtocExecutable(baseDir, protocRaw);
  final protocPluginExecutable = _resolveProtocDartPluginExecutable();

  return _ResolvedProtoGeneration(
    protoPath: protoPath,
    outDir: outDir,
    includeDirs: includeDirs,
    grpc: grpc,
    protocExecutable: protocExecutable,
    protocPluginExecutable: protocPluginExecutable,
    configPath: loaded?.configPath,
  );
}

List<String> _buildProtocArgs(_ResolvedProtoGeneration resolved) {
  final dartOut = resolved.grpc ? 'grpc:${resolved.outDir}' : resolved.outDir;
  return <String>[
    for (final include in resolved.includeDirs) '-I$include',
    '--dart_out=$dartOut',
    resolved.protoPath,
  ];
}

List<String> _collectGeneratedProtoFiles(String outDir) {
  final root = Directory(outDir);
  if (!root.existsSync()) {
    return <String>[];
  }

  final generated = <String>[];
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) {
      continue;
    }
    final name = p.basename(entity.path).toLowerCase();
    if (name.endsWith('.pb.dart') ||
        name.endsWith('.pbenum.dart') ||
        name.endsWith('.pbjson.dart') ||
        name.endsWith('.pbgrpc.dart') ||
        name.endsWith('.pbserver.dart')) {
      generated.add(p.normalize(entity.path));
    }
  }
  generated.sort();
  return generated;
}

String _defaultProtocExecutableName() {
  return Platform.isWindows ? 'protoc.exe' : 'protoc';
}

String _resolveProtocExecutable(String baseDir, String raw) {
  final value = raw.trim();
  if (value.isEmpty) {
    return _defaultProtocExecutableName();
  }

  final hasPath = value.contains('/') || value.contains(r'\');
  if (!hasPath && !p.isAbsolute(value)) {
    final names = <String>[value];
    if (Platform.isWindows) {
      final lower = value.toLowerCase();
      if (!lower.endsWith('.exe')) {
        names.insert(0, '$value.exe');
      }
      if (!lower.endsWith('.bat')) {
        names.add('$value.bat');
      }
      if (!lower.endsWith('.cmd')) {
        names.add('$value.cmd');
      }
    }
    final found = _findExecutable(names);
    if (found == null) {
      throw ToolError(
        'protoc executable not found in PATH: $value. '
        'Install protoc or pass --protoc=<path>.',
      );
    }
    return found;
  }

  final resolved = _resolvePathFromBase(baseDir, value);
  if (!File(resolved).existsSync()) {
    throw ToolError('protoc executable not found: $resolved');
  }
  return resolved;
}

String _resolveProtocDartPluginExecutable() {
  final names = Platform.isWindows
      ? <String>[
          'protoc-gen-dart.bat',
          'protoc-gen-dart.exe',
          'protoc-gen-dart',
        ]
      : <String>['protoc-gen-dart'];

  final found = _findExecutable(names);
  if (found == null) {
    throw ToolError(
      'protoc-gen-dart not found in PATH. Install with '
      '`dart pub global activate protoc_plugin` and add pub-cache bin to PATH.',
    );
  }
  return found;
}

String? _inferProtoSource(String baseDir, {String? moduleName}) {
  final protoRoot = Directory(p.join(baseDir, 'proto'));
  if (!protoRoot.existsSync()) {
    return null;
  }

  final protoFiles = _findProtoSourcesUnder(protoRoot.path);
  if (protoFiles.isEmpty) {
    return null;
  }
  if (protoFiles.length == 1) {
    return protoFiles.first;
  }

  if (moduleName != null && moduleName.trim().isNotEmpty) {
    final module = moduleName.trim().toLowerCase();
    final preferred = protoFiles
        .where(
          (path) => p.basenameWithoutExtension(path).toLowerCase() == module,
        )
        .toList();
    if (preferred.length == 1) {
      return preferred.first;
    }
  }

  final moduleProto = protoFiles
      .where((path) => p.basename(path).toLowerCase() == 'module.proto')
      .toList();
  if (moduleProto.length == 1) {
    return moduleProto.first;
  }

  final preview = protoFiles.take(5).map(_displayPath).join(', ');
  throw ToolError(
    'Multiple .proto files found under ${_displayPath(protoRoot.path)}. '
    'Specify one with `dllart proto <path>` or `--proto=<path>`. '
    'Candidates: $preview',
  );
}

List<String> _findProtoSourcesUnder(String rootPath) {
  final root = Directory(rootPath);
  if (!root.existsSync()) {
    return <String>[];
  }

  final out = <String>[];
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) {
      continue;
    }
    if (!entity.path.toLowerCase().endsWith('.proto')) {
      continue;
    }
    out.add(p.normalize(entity.path));
  }
  out.sort();
  return out;
}

String _resolvePathFromBase(String baseDir, String rawPath) {
  if (p.isAbsolute(rawPath)) {
    return p.normalize(rawPath);
  }
  return p.normalize(p.join(baseDir, rawPath));
}

List<String> _parsePathList(String raw) {
  final parts = raw.split(',').map((item) => item.trim());
  return parts.where((item) => item.isNotEmpty).toList();
}

String? _firstNonEmpty(List<String?> values) {
  for (final value in values) {
    if (value == null) {
      continue;
    }
    if (value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return null;
}
