part of dllart_cli;

Future<void> _commandIntegrate(ParsedArgs args) async {
  _applyLoggingFromConfig(null);
  final jsonMode = _isJsonMode(args);
  final loaded = _loadConfig(args, allowInferred: true);
  _applyLoggingFromConfig(loaded.config);
  final outputPath = loaded.resolvePath(loaded.config.output);
  final outputRoot = Directory(outputPath);
  if (!outputRoot.existsSync()) {
    throw ToolError(
      'Artifact directory not found: $outputPath. Run `dllart build` first.',
    );
  }

  final includeDir = p.join(outputPath, 'include');
  final libDir = p.join(outputPath, 'lib');
  final integrationDir = p.join(outputPath, 'integration');
  final usagePath = p.join(outputPath, 'USAGE.md');
  final manifestPath = p.join(outputPath, 'artifact.json');
  final manifest = _readArtifactManifestMap(manifestPath);
  final androidAbiLibraries = _manifestAndroidAbiLibraries(manifest);
  final iosXcframeworkPath = _manifestIosXcframeworkPath(manifest);
  final iosXcframeworkExists =
      iosXcframeworkPath != null && Directory(iosXcframeworkPath).existsSync();
  final hasMobileArtifacts =
      androidAbiLibraries.isNotEmpty || iosXcframeworkExists;
  final cmakeConfigPath = p.join(
    integrationDir,
    'cmake',
    '${loaded.config.name}Config.cmake',
  );
  final hostLibraryPath =
      _libraryPathFromManifest(manifestPath) ??
      _outputLibraryPath(libDir, loaded.config.name);
  final hostLibraryExists = File(hostLibraryPath).existsSync();

  if (!Directory(includeDir).existsSync()) {
    throw ToolError(
      'Headers directory missing: $includeDir. Run `dllart build` first.',
    );
  }
  if (!hostLibraryExists && !hasMobileArtifacts) {
    throw ToolError(
      'No build artifacts found in $outputPath. Run `dllart build` first.',
    );
  }

  final includeDisplay = _displayPath(includeDir);
  final libDisplay = _displayPath(libDir);
  final libraryDisplay = hostLibraryExists
      ? _displayPath(hostLibraryPath)
      : null;
  final cmakeDisplay = _displayPath(cmakeConfigPath);
  final usageDisplay = _displayPath(usagePath);
  final manifestDisplay = _displayPath(manifestPath);
  final runtimePath = p.join(
    outputPath,
    'runtime',
    _runtimeExecutableNameForHost(),
  );
  final runtimeDisplay = _displayPath(runtimePath);
  final runtimePrefix = _moduleRuntimePrefix(loaded.config.name);
  final wrapperClass = '${_upperCamelCase(loaded.config.name)}Client';
  final runtimeExists = File(runtimePath).existsSync();
  final cmakeExists = File(cmakeConfigPath).existsSync();
  final manifestExists = File(manifestPath).existsSync();
  final usageExists = File(usagePath).existsSync();

  final compileSnippet = hostLibraryExists
      ? 'clang your_app.c -I"$includeDisplay" -L"$libDisplay" -l${loaded.config.name}'
      : null;
  final envSnippet = !hostLibraryExists
      ? null
      : Platform.isMacOS
      ? 'export DYLD_LIBRARY_PATH="$libDisplay:\$DYLD_LIBRARY_PATH"'
      : Platform.isLinux
      ? 'export LD_LIBRARY_PATH="$libDisplay:\$LD_LIBRARY_PATH"'
      : Platform.isWindows
      ? 'set PATH=$libDisplay;%PATH%'
      : null;
  final androidIntegrate = androidAbiLibraries.map(
    (abi, path) => MapEntry<String, Object?>(abi, _displayPath(path)),
  );
  final iosIntegratePath = iosXcframeworkPath == null
      ? null
      : _displayPath(iosXcframeworkPath);

  if (jsonMode) {
    _writeJsonCommandResult(
      'integrate',
      ok: true,
      status: 'ok',
      data: <String, Object?>{
        'module': loaded.config.name,
        'artifact_root': _displayPath(outputPath),
        'headers_dir': includeDisplay,
        'library_dir': libDisplay,
        if (libraryDisplay != null) 'library_file': libraryDisplay,
        if (runtimeExists) 'runtime_file': runtimeDisplay,
        if (cmakeExists) 'cmake_config': cmakeDisplay,
        if (manifestExists) 'manifest': manifestDisplay,
        if (usageExists) 'usage_doc': usageDisplay,
        if (androidIntegrate.isNotEmpty || iosIntegratePath != null)
          'mobile': <String, Object?>{
            if (androidIntegrate.isNotEmpty) 'android_abis': androidIntegrate,
            if (iosIntegratePath != null) 'ios_xcframework': iosIntegratePath,
          },
        'snippets': <String, Object?>{
          if (compileSnippet != null) 'c_compile': compileSnippet,
          if (envSnippet != null) 'env': envSnippet,
          if (cmakeExists) 'cmake_include': 'include("$cmakeDisplay")',
          if (cmakeExists)
            'cmake_link':
                'target_link_libraries(your_target PRIVATE ${loaded.config.name}::${loaded.config.name})',
          if (hostLibraryExists)
            'python_symbols': <String>[
              '${runtimePrefix}_init',
              '${runtimePrefix}_call_json',
              '${runtimePrefix}_call_json_batch',
              '${runtimePrefix}_call_json_raw',
              '${runtimePrefix}_call_i64_2',
              '${runtimePrefix}_call_i64_2_index',
              '${runtimePrefix}_call_i64_4',
              '${runtimePrefix}_call_i64_4_index',
              '${runtimePrefix}_call_f64_2',
              '${runtimePrefix}_call_f64_2_index',
              '${runtimePrefix}_call_f64_4',
              '${runtimePrefix}_call_f64_4_index',
              '${runtimePrefix}_call_bytes',
              '${runtimePrefix}_call_bytes_index',
              '${runtimePrefix}_last_error_code',
              '${runtimePrefix}_last_error_json',
              '${runtimePrefix}_bytes_free',
            ],
          if (hostLibraryExists)
            'python_minimal': <String>[
              'from bindings import $wrapperClass',
              'mod = $wrapperClass()',
              'mod.init()',
              "print(mod.call_json('add', '{\"a\": 20, \"b\": 22}'))",
              'mod.shutdown()',
            ],
          if (hostLibraryExists)
            'csharp_minimal': <String>[
              'using var mod = new $wrapperClass();',
              'mod.Init();',
              'Console.WriteLine(mod.CallJson("add", "{\\"a\\":20,\\"b\\":22}"));',
              'mod.Shutdown();',
            ],
          if (androidIntegrate.isNotEmpty || iosIntegratePath != null)
            'mobile_paths': <String, Object?>{
              if (androidIntegrate.isNotEmpty) 'android_abis': androidIntegrate,
              if (iosIntegratePath != null) 'ios_xcframework': iosIntegratePath,
            },
        },
      },
    );
    return;
  }

  stdout.writeln('DLLART Integration');
  stdout.writeln('Module:        ${loaded.config.name}');
  stdout.writeln('Artifact root: ${_displayPath(outputPath)}');
  stdout.writeln('Headers:       $includeDisplay');
  if (hostLibraryExists) {
    stdout.writeln('Library dir:   $libDisplay');
    stdout.writeln('Library file:  $libraryDisplay');
  }
  if (runtimeExists) {
    stdout.writeln('Runtime file:  $runtimeDisplay');
  }
  if (cmakeExists) {
    stdout.writeln('CMake config:  $cmakeDisplay');
  }
  if (manifestExists) {
    stdout.writeln('Manifest:      $manifestDisplay');
  }
  if (usageExists) {
    stdout.writeln('Usage doc:     $usageDisplay');
  }

  if (compileSnippet != null) {
    stdout.writeln('');
    stdout.writeln('C/C++ compile:');
    stdout.writeln('  $compileSnippet');
    if (envSnippet != null) {
      stdout.writeln('  $envSnippet');
    }
  }

  if (cmakeExists) {
    stdout.writeln('');
    stdout.writeln('CMake:');
    stdout.writeln('  include("$cmakeDisplay")');
    stdout.writeln(
      '  target_link_libraries(your_target PRIVATE ${loaded.config.name}::${loaded.config.name})',
    );
  }

  if (hostLibraryExists && libraryDisplay != null) {
    stdout.writeln('');
    stdout.writeln('Python quick start:');
    stdout.writeln('  from bindings import $wrapperClass');
    stdout.writeln('  mod = $wrapperClass()');
    stdout.writeln('  mod.init()');
    stdout.writeln("  print(mod.call_json('add', '{\"a\": 20, \"b\": 22}'))");
    stdout.writeln('  mod.shutdown()');
    stdout.writeln('');
    stdout.writeln('C# quick start:');
    stdout.writeln('  using var mod = new $wrapperClass();');
    stdout.writeln('  mod.Init();');
    stdout.writeln(
      '  Console.WriteLine(mod.CallJson("add", "{\\"a\\":20,\\"b\\":22}"));',
    );
    stdout.writeln('  mod.Shutdown();');
    if (_inVerboseMode) {
      stdout.writeln('');
      stdout.writeln('Native symbols (verbose):');
      stdout.writeln('  init = lib.${runtimePrefix}_init');
      stdout.writeln('  call_json = lib.${runtimePrefix}_call_json');
      stdout.writeln(
        '  call_json_batch = lib.${runtimePrefix}_call_json_batch',
      );
      stdout.writeln('  call_json_raw = lib.${runtimePrefix}_call_json_raw');
      stdout.writeln('  call_i64_2 = lib.${runtimePrefix}_call_i64_2');
      stdout.writeln(
        '  call_i64_2_index = lib.${runtimePrefix}_call_i64_2_index',
      );
      stdout.writeln('  call_i64_4 = lib.${runtimePrefix}_call_i64_4');
      stdout.writeln(
        '  call_i64_4_index = lib.${runtimePrefix}_call_i64_4_index',
      );
      stdout.writeln('  call_f64_2 = lib.${runtimePrefix}_call_f64_2');
      stdout.writeln(
        '  call_f64_2_index = lib.${runtimePrefix}_call_f64_2_index',
      );
      stdout.writeln('  call_f64_4 = lib.${runtimePrefix}_call_f64_4');
      stdout.writeln(
        '  call_f64_4_index = lib.${runtimePrefix}_call_f64_4_index',
      );
      stdout.writeln('  call_bytes = lib.${runtimePrefix}_call_bytes');
      stdout.writeln(
        '  call_bytes_index = lib.${runtimePrefix}_call_bytes_index',
      );
      stdout.writeln(
        '  last_error_code = lib.${runtimePrefix}_last_error_code',
      );
      stdout.writeln(
        '  last_error_json = lib.${runtimePrefix}_last_error_json',
      );
      stdout.writeln('  bytes_free = lib.${runtimePrefix}_bytes_free');
      stdout.writeln('  # init(runtime_path=NULL) enables auto runtime lookup');
    }
  }

  if (androidIntegrate.isNotEmpty || iosIntegratePath != null) {
    stdout.writeln('');
    stdout.writeln('Mobile artifacts:');
    if (androidIntegrate.isNotEmpty) {
      stdout.writeln('  Android .so:');
      for (final entry in androidIntegrate.entries) {
        stdout.writeln('    ${entry.key}: ${entry.value}');
      }
    }
    if (iosIntegratePath != null) {
      stdout.writeln('  iOS xcframework: $iosIntegratePath');
    }
  }
  stdout.writeln('');
  stdout.writeln('Mobile package scaffold:');
  stdout.writeln('  dllart package all');
}

void _cleanupLegacyArtifacts(String outputPath, String moduleName) {
  final legacyPaths = <String>[
    p.join(outputPath, '${moduleName}_api.h'),
    p.join(outputPath, 'dllart_bridge.h'),
    p.join(outputPath, 'include', 'dllart_bridge.h'),
    p.join(outputPath, 'generated'),
    p.join(outputPath, 'module.aot.dill'),
    p.join(outputPath, 'module.S'),
    p.join(outputPath, 'module.o'),
    p.join(outputPath, 'lib$moduleName.dylib'),
    p.join(outputPath, 'lib$moduleName.so'),
    p.join(outputPath, '$moduleName.dll'),
  ];

  for (final legacyPath in legacyPaths) {
    final file = File(legacyPath);
    if (file.existsSync()) {
      file.deleteSync();
      continue;
    }

    final dir = Directory(legacyPath);
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  }
}

Future<void> _commandWorkflow(ParsedArgs args) async {
  _applyLoggingFromConfig(null);
  final loaded = _loadConfig(args);
  _applyLoggingFromConfig(loaded.config);
  final force = args.hasFlag('force');

  final outputPath = p.normalize(
    p.absolute(
      args['output'] ?? p.join('.github', 'workflows', 'dllart-build.yml'),
    ),
  );

  final outputFile = File(outputPath);
  if (outputFile.existsSync() && !force) {
    throw ToolError(
      'Workflow already exists: $outputPath (pass --force to overwrite).',
    );
  }

  await outputFile.create(recursive: true);
  final hasGlobal = args.options.containsKey('global-tool');
  final hasLocal = args.options.containsKey('local-tool');
  if (hasGlobal && hasLocal) {
    throw ToolError('Use either --global-tool or --local-tool, not both.');
  }

  final localToolExists = File(
    p.join(Directory.current.path, 'bin', 'dllart.dart'),
  ).existsSync();

  final useGlobalTool = hasGlobal
      ? true
      : hasLocal
      ? false
      : !localToolExists;
  await outputFile.writeAsString(
    _generateWorkflowYaml(loaded, useGlobalTool: useGlobalTool),
  );

  stdout.writeln('Generated workflow: $outputPath');
  stdout.writeln('Targets: ${loaded.config.targets.join(', ')}');
  stdout.writeln('Tool mode: ${useGlobalTool ? 'global' : 'local'}');
}

Future<void> _commandDoctor(ParsedArgs args) async {
  _applyLoggingFromConfig(null);
  final jsonMode = _isJsonMode(args);
  final autoFix = args.hasFlag('fix');
  final packageTargetChecks = _resolveDoctorPackageTargets(
    args['package-target'],
  );
  final report = DoctorReport();
  report.ok('Working directory', Directory.current.path);
  report.ok(
    'Host platform',
    '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
  );

  final toolRoot = _toolRoot();
  if (Directory(toolRoot).existsSync()) {
    report.ok('Tool root', toolRoot);
  } else {
    report.fail('Tool root', 'Directory does not exist: $toolRoot');
  }

  final dartPath = p.normalize(Platform.resolvedExecutable);
  if (File(dartPath).existsSync()) {
    report.ok('Dart executable', dartPath);
  } else {
    report.fail('Dart executable', 'Missing file: $dartPath');
  }

  if (File(dartPath).existsSync()) {
    final result = await _runCommandCapture(dartPath, <String>['--version']);
    if (result.exitCode == 0) {
      final versionLine = _firstNonEmptyLine(
        '${_asText(result.stdout)}\n${_asText(result.stderr)}',
      );
      report.ok('Dart version', versionLine ?? 'Unknown');
    } else {
      report.fail(
        'Dart version',
        _processFailureSummary('dart --version', result),
      );
    }
  }

  final runtimeName = Platform.isWindows
      ? 'dartaotruntime.exe'
      : 'dartaotruntime';
  final genSnapshotName = Platform.isWindows
      ? 'gen_snapshot.exe'
      : 'gen_snapshot';

  final runtimeCandidates = <String>[
    p.join(p.dirname(dartPath), runtimeName),
    p.join(p.dirname(dartPath), 'cache', 'dart-sdk', 'bin', runtimeName),
  ];

  String? dartaotPath;
  for (final candidate in runtimeCandidates) {
    if (File(candidate).existsSync()) {
      dartaotPath = p.normalize(candidate);
      break;
    }
  }

  String? sdkInclude;
  String? clangPath;
  String? bridgeSourcePath;
  var bridgeSourceExists = false;
  var dartApiExists = false;

  if (dartaotPath == null) {
    report.fail(
      'dartaotruntime',
      'Not found. Checked: ${runtimeCandidates.join(', ')}',
    );
  } else {
    report.ok('dartaotruntime', dartaotPath);
    final sdkRoot = p.normalize(p.dirname(p.dirname(dartaotPath)));
    report.ok('Dart SDK root', sdkRoot);

    final frontendServer = p.join(
      sdkRoot,
      'bin',
      'snapshots',
      'frontend_server_aot.dart.snapshot',
    );
    final genSnapshot = p.join(sdkRoot, 'bin', 'utils', genSnapshotName);
    final platformDill = p.join(
      sdkRoot,
      'lib',
      '_internal',
      'vm_platform_strong.dill',
    );
    sdkInclude = p.join(sdkRoot, 'include');
    final dartApi = p.join(sdkInclude, 'dart_api.h');

    final requiredFiles = <String, String>{
      'frontend_server_aot.dart.snapshot': frontendServer,
      'gen_snapshot': genSnapshot,
      'vm_platform_strong.dill': platformDill,
      'dart_api.h': dartApi,
    };

    for (final entry in requiredFiles.entries) {
      if (File(entry.value).existsSync()) {
        report.ok(entry.key, entry.value);
      } else {
        report.fail(entry.key, 'Missing file: ${entry.value}');
      }
    }

    dartApiExists = File(dartApi).existsSync();
  }

  clangPath = _findExecutable(
    Platform.isWindows ? <String>['clang.exe', 'clang'] : <String>['clang'],
  );
  if (clangPath == null) {
    report.fail('clang', 'clang not found in PATH');
  } else {
    report.ok('clang', clangPath);
    final result = await _runCommandCapture(clangPath, <String>['--version']);
    if (result.exitCode == 0) {
      final versionLine = _firstNonEmptyLine(_asText(result.stdout));
      if (versionLine != null) {
        report.ok('clang version', versionLine);
      }
    } else {
      report.fail(
        'clang version',
        _processFailureSummary('clang --version', result),
      );
    }
  }

  bridgeSourcePath = p.join(toolRoot, 'native', 'dllart_bridge.c');
  final bridgeHeaderPath = p.join(toolRoot, 'native', 'dllart_bridge.h');

  if (File(bridgeSourcePath).existsSync()) {
    bridgeSourceExists = true;
    report.ok('Bridge source', bridgeSourcePath);
  } else {
    report.fail('Bridge source', 'Missing file: $bridgeSourcePath');
  }

  if (File(bridgeHeaderPath).existsSync()) {
    report.ok('Bridge header', bridgeHeaderPath);
  } else {
    report.fail('Bridge header', 'Missing file: $bridgeHeaderPath');
  }

  if (clangPath != null &&
      sdkInclude != null &&
      bridgeSourceExists &&
      dartApiExists) {
    final result = await _runCommandCapture(clangPath, <String>[
      '-Wall',
      '-Wextra',
      '-fsyntax-only',
      '-I$sdkInclude',
      bridgeSourcePath,
    ]);
    if (result.exitCode == 0) {
      report.ok('Bridge syntax', 'clang -fsyntax-only passed');
    } else {
      report.fail(
        'Bridge syntax',
        _processFailureSummary('clang -fsyntax-only', result),
      );
    }
  } else {
    report.warn(
      'Bridge syntax',
      'Skipped (requires clang, dart_api.h, and native bridge source)',
    );
  }

  final configArg = (args['config'] ?? '').trim();
  final sourceArg = (args['source'] ?? '').trim();
  final packageRootCandidates = <String>[
    if (configArg.isNotEmpty) p.dirname(p.normalize(p.absolute(configArg))),
    if (sourceArg.isNotEmpty) p.dirname(p.normalize(p.absolute(sourceArg))),
    if (configArg.isEmpty && sourceArg.isEmpty) Directory.current.path,
  ];
  String? packageRoot;
  for (final candidate in packageRootCandidates) {
    packageRoot = _findNearestPubspecDir(candidate);
    if (packageRoot != null) {
      break;
    }
  }

  if (packageRoot == null) {
    report.ok(
      'Package config',
      'Not required (no pubspec.yaml found near project context).',
    );
  } else {
    final packageConfigPath = p.join(
      packageRoot,
      '.dart_tool',
      'package_config.json',
    );
    if (File(packageConfigPath).existsSync()) {
      report.ok('Package config', packageConfigPath);
    } else {
      if (autoFix) {
        final result = await _runCommandCapture(
          Platform.resolvedExecutable,
          <String>['pub', 'get'],
          workingDirectory: packageRoot,
        );
        if (result.exitCode == 0 && File(packageConfigPath).existsSync()) {
          report.ok('Package config', '$packageConfigPath (auto-fixed)');
        } else {
          report.warn(
            'Package config',
            'Missing $packageConfigPath. Auto-fix failed: '
                '${_processFailureSummary('dart pub get', result)}',
          );
        }
      } else {
        report.warn(
          'Package config',
          'Missing $packageConfigPath. Run `dart pub get`.',
        );
      }
    }
  }

  LoadedConfig? loaded;
  final hasInline = args['name'] != null || args['source'] != null;
  if (hasInline) {
    try {
      loaded = _loadConfig(args);
      _applyLoggingFromConfig(loaded.config);
      report.ok(
        'Config (inline)',
        'name=${loaded.config.name}, source=${loaded.config.source}',
      );
    } on ToolError catch (error) {
      report.fail('Config (inline)', error.message);
    }
  } else {
    try {
      loaded = _loadConfig(args, allowInferred: true);
      _applyLoggingFromConfig(loaded.config);
      if (File(loaded.configPath).existsSync()) {
        report.ok('Config', loaded.configPath);
      } else {
        report.warn(
          'Config',
          'dllart.json not found, using inferred settings '
              '(source=${loaded.config.source}, output=${loaded.config.output})',
        );
      }
    } on ToolError catch (error) {
      _applyLoggingFromConfig(null);
      report.warn('Config', error.message);
    }
  }

  if (loaded != null) {
    const supportedTargets = <String>{
      'macos-arm64',
      'macos-x64',
      'linux-x64',
      'windows-x64',
    };

    final unknownTargets = loaded.config.targets
        .where((target) => !supportedTargets.contains(target))
        .toList();

    if (unknownTargets.isEmpty) {
      report.ok('Targets', loaded.config.targets.join(', '));
    } else {
      report.fail(
        'Targets',
        'Unsupported targets: ${unknownTargets.join(', ')}',
      );
    }

    const hardWarnJsonIn = 32 * 1024 * 1024;
    const hardWarnJsonOut = 64 * 1024 * 1024;
    const hardWarnBytesIn = 64 * 1024 * 1024;
    const hardWarnBytesOut = 128 * 1024 * 1024;
    const hardWarnMethodCache = 20000;
    if (loaded.config.limits.jsonInMaxBytes > hardWarnJsonIn ||
        loaded.config.limits.jsonOutMaxBytes > hardWarnJsonOut ||
        loaded.config.limits.bytesInMaxBytes > hardWarnBytesIn ||
        loaded.config.limits.bytesOutMaxBytes > hardWarnBytesOut ||
        loaded.config.limits.methodCacheMaxEntries > hardWarnMethodCache) {
      report.warn(
        'Limits',
        'Configured payload/cache limits are unusually high and may increase DoS/OOM risk.',
      );
    } else {
      report.ok(
        'Limits',
        'json_in=${loaded.config.limits.jsonInMaxBytes}, '
            'json_out=${loaded.config.limits.jsonOutMaxBytes}, '
            'bytes_in=${loaded.config.limits.bytesInMaxBytes}, '
            'bytes_out=${loaded.config.limits.bytesOutMaxBytes}, '
            'method_cache=${loaded.config.limits.methodCacheMaxEntries}',
      );
    }

    final sourcePath = loaded.resolvePath(loaded.config.source);
    if (!File(sourcePath).existsSync()) {
      report.fail('Source module', 'Missing file: $sourcePath');
    } else {
      report.ok('Source module', sourcePath);
      try {
        final sourceCode = await File(sourcePath).readAsString();
        final exports = _discoverExports(sourceCode);
        if (exports.isEmpty) {
          report.fail(
            'Exports',
            'No @DllartExport() functions found in $sourcePath',
          );
        } else {
          final i64_2MethodIds = _computeI64_2MethodIds(exports);
          final i64_4MethodIds = _computeI64_4MethodIds(exports);
          final f64_2MethodIds = _computeF64_2MethodIds(exports);
          final f64_4MethodIds = _computeF64_4MethodIds(exports);
          final bytesMethodIds = _computeBytesMethodIds(exports);
          final names = exports
              .map((fn) {
                final i64_2Mode = fn.directI64_2
                    ? 'i64_2=direct'
                    : fn.supportsI64_2
                    ? 'i64_2=fallback'
                    : 'i64_2=none';
                final i64_2MethodId = fn.supportsI64_2
                    ? ',id=${i64_2MethodIds[fn.exportName]}'
                    : '';
                final i64_4Mode = fn.directI64_4
                    ? 'i64_4=direct'
                    : fn.supportsI64_4
                    ? 'i64_4=fallback'
                    : 'i64_4=none';
                final i64_4MethodId = fn.supportsI64_4
                    ? ',id=${i64_4MethodIds[fn.exportName]}'
                    : '';
                final f64_2Mode = fn.directF64_2
                    ? 'f64_2=direct'
                    : fn.supportsF64_2
                    ? 'f64_2=fallback'
                    : 'f64_2=none';
                final f64_2MethodId = fn.supportsF64_2
                    ? ',id=${f64_2MethodIds[fn.exportName]}'
                    : '';
                final f64_4Mode = fn.directF64_4
                    ? 'f64_4=direct'
                    : fn.supportsF64_4
                    ? 'f64_4=fallback'
                    : 'f64_4=none';
                final f64_4MethodId = fn.supportsF64_4
                    ? ',id=${f64_4MethodIds[fn.exportName]}'
                    : '';
                final bytesMode = fn.directBytes
                    ? 'bytes=direct'
                    : fn.supportsBytes
                    ? 'bytes=fallback'
                    : 'bytes=none';
                final bytesMethodId = fn.supportsBytes
                    ? ',id=${bytesMethodIds[fn.exportName]}'
                    : '';
                return '${fn.exportName}/${fn.arity}'
                    '[$i64_2Mode$i64_2MethodId;$i64_4Mode$i64_4MethodId;$f64_2Mode$f64_2MethodId;$f64_4Mode$f64_4MethodId;$bytesMode$bytesMethodId]';
              })
              .join(', ');
          report.ok('Exports', '${exports.length} found: $names');
        }
      } on ToolError catch (error) {
        report.fail('Exports', error.message);
      }
    }

    final outputPath = loaded.resolvePath(loaded.config.output);
    if (Directory(outputPath).existsSync()) {
      report.ok('Output directory', outputPath);
      final bundledRuntime = p.join(
        outputPath,
        'runtime',
        _runtimeExecutableNameForHost(),
      );
      if (File(bundledRuntime).existsSync()) {
        report.ok('Bundled runtime', bundledRuntime);
      } else {
        report.warn(
          'Bundled runtime',
          'Missing $bundledRuntime (run `dllart build` to regenerate bundle)',
        );
      }
      _appendArtifactChecksumChecks(report, outputPath);
      await _appendArtifactAbiAndBridgeChecks(
        report: report,
        outputPath: outputPath,
        toolRoot: toolRoot,
      );
    } else {
      report.warn(
        'Output directory',
        'Not created yet: $outputPath (run build to generate artifacts)',
      );
    }

    await _appendProtobufDoctorChecks(report, loaded);
  }

  _appendDoctorPackageTargetChecks(report, packageTargetChecks);

  final workflowPath = p.join(
    Directory.current.path,
    '.github',
    'workflows',
    'dllart-build.yml',
  );
  if (File(workflowPath).existsSync()) {
    report.ok('Workflow', workflowPath);
  } else {
    if (autoFix && loaded != null) {
      try {
        final workflowLoaded = LoadedConfig(
          config: loaded.config,
          configPath: loaded.configPath,
        );
        final workflowFile = File(workflowPath);
        workflowFile.createSync(recursive: true);
        workflowFile.writeAsStringSync(_generateWorkflowYaml(workflowLoaded));
        report.ok('Workflow', '$workflowPath (auto-fixed)');
      } on ToolError catch (error) {
        report.warn(
          'Workflow',
          'Missing $workflowPath and auto-fix failed: ${error.message}',
        );
      }
    } else {
      report.warn(
        'Workflow',
        'Missing $workflowPath (run `dllart workflow --force`)',
      );
    }
  }

  if (jsonMode) {
    final status = report.hasFailures
        ? 'fail'
        : report.warnCount > 0
        ? 'warn'
        : 'ok';
    _writeJsonCommandResult(
      'doctor',
      ok: !report.hasFailures,
      status: status,
      data: report.toJson(),
    );
  } else {
    stdout.writeln('');
    report.print();
  }

  if (report.hasFailures) {
    if (!jsonMode) {
      stderr.writeln('Doctor found blocking issues. Fix FAIL items first.');
    }
    exitCode = 1;
    return;
  }

  if (!jsonMode) {
    if (report.warnCount > 0) {
      stdout.writeln('Doctor completed with warnings.');
    } else {
      stdout.writeln('Doctor check passed.');
    }
  }
}

List<String> _resolveDoctorPackageTargets(String? rawValue) {
  final raw = (rawValue ?? '').trim().toLowerCase();
  if (raw.isEmpty) {
    return const <String>[];
  }
  if (raw == 'all') {
    return const <String>['python', 'csharp', 'android', 'ios', 'flutter'];
  }
  if (raw == 'python' ||
      raw == 'csharp' ||
      raw == 'android' ||
      raw == 'ios' ||
      raw == 'flutter') {
    return <String>[raw];
  }
  throw ToolError(
    'Unsupported --package-target value: $raw. '
    'Use python, csharp, android, ios, flutter, or all.',
  );
}

void _appendDoctorPackageTargetChecks(
  DoctorReport report,
  List<String> targets,
) {
  if (targets.isEmpty) {
    return;
  }

  for (final target in targets) {
    switch (target) {
      case 'python':
        final python = _findExecutable(
          Platform.isWindows
              ? <String>['python3.exe', 'python.exe', 'python3', 'python']
              : <String>['python3', 'python'],
        );
        if (python == null) {
          report.warn(
            'Package toolchain (python)',
            'python3 not found in PATH',
          );
        } else {
          report.ok('Package toolchain (python)', _displayPath(python));
        }
        break;
      case 'csharp':
        final dotnet = _findExecutable(
          Platform.isWindows
              ? <String>['dotnet.exe', 'dotnet']
              : <String>['dotnet'],
        );
        if (dotnet == null) {
          report.warn('Package toolchain (csharp)', 'dotnet not found in PATH');
        } else {
          report.ok('Package toolchain (csharp)', _displayPath(dotnet));
        }
        break;
      case 'android':
        final ndkHome = (Platform.environment['ANDROID_NDK_HOME'] ?? '').trim();
        if (ndkHome.isEmpty) {
          report.warn(
            'Package toolchain (android)',
            'ANDROID_NDK_HOME is not set',
          );
        } else if (!Directory(ndkHome).existsSync()) {
          report.warn(
            'Package toolchain (android)',
            'ANDROID_NDK_HOME points to missing directory: $ndkHome',
          );
        } else {
          report.ok('Package toolchain (android)', ndkHome);
        }
        break;
      case 'ios':
        if (!Platform.isMacOS) {
          report.warn(
            'Package toolchain (ios)',
            'iOS packaging checks are available only on macOS',
          );
          break;
        }
        final xcrun = _findExecutable(<String>['xcrun']);
        final xcodebuild = _findExecutable(<String>['xcodebuild']);
        if (xcrun == null || xcodebuild == null) {
          report.warn(
            'Package toolchain (ios)',
            'xcrun/xcodebuild not found in PATH',
          );
        } else {
          report.ok(
            'Package toolchain (ios)',
            'xcrun=${_displayPath(xcrun)}, xcodebuild=${_displayPath(xcodebuild)}',
          );
        }
        break;
      case 'flutter':
        final flutter = _findExecutable(
          Platform.isWindows
              ? <String>['flutter.bat', 'flutter.cmd', 'flutter']
              : <String>['flutter'],
        );
        if (flutter == null) {
          report.warn(
            'Package toolchain (flutter)',
            'flutter not found in PATH',
          );
        } else {
          report.ok('Package toolchain (flutter)', _displayPath(flutter));
        }
        break;
    }
  }
}

Future<void> _appendProtobufDoctorChecks(
  DoctorReport report,
  LoadedConfig loaded,
) async {
  final protobuf = loaded.config.protobuf;
  if (protobuf == null) {
    return;
  }

  final protoPath = loaded.resolvePath(protobuf.proto);
  if (File(protoPath).existsSync()) {
    report.ok('Protobuf source', protoPath);
  } else {
    report.fail('Protobuf source', 'Missing file: $protoPath');
  }

  final outDir = loaded.resolvePath(protobuf.out);
  report.ok('Protobuf output', outDir);
  report.ok('Protobuf mode', protobuf.grpc ? 'grpc' : 'protobuf');

  final includeDirs = <String>{
    for (final include in protobuf.includes) loaded.resolvePath(include),
    p.dirname(protoPath),
  };

  for (final includeDir in includeDirs) {
    if (Directory(includeDir).existsSync()) {
      report.ok('Protobuf include', includeDir);
    } else {
      report.warn('Protobuf include', 'Directory does not exist: $includeDir');
    }
  }

  final protocRaw = protobuf.protoc ?? _defaultProtocExecutableName();
  String? protocPath;
  try {
    protocPath = _resolveProtocExecutable(loaded.configDir, protocRaw);
    report.ok('protoc', protocPath);
  } on ToolError catch (error) {
    report.fail('protoc', error.message);
  }

  if (protocPath != null) {
    final result = await _runCommandCapture(protocPath, <String>['--version']);
    if (result.exitCode == 0) {
      final versionLine = _firstNonEmptyLine(
        '${_asText(result.stdout)}\n${_asText(result.stderr)}',
      );
      if (versionLine != null) {
        report.ok('protoc version', versionLine);
      } else {
        report.ok('protoc version', 'Unknown');
      }
    } else {
      report.warn(
        'protoc version',
        _processFailureSummary('$protocPath --version', result),
      );
    }
  }

  try {
    final pluginPath = _resolveProtocDartPluginExecutable();
    report.ok('protoc-gen-dart', pluginPath);
  } on ToolError catch (error) {
    report.fail('protoc-gen-dart', error.message);
  }
}

void _appendArtifactChecksumChecks(DoctorReport report, String outputPath) {
  final manifestPath = p.join(outputPath, 'artifact.json');
  final manifestFile = File(manifestPath);
  if (!manifestFile.existsSync()) {
    report.warn('Artifact checksums', 'Missing $manifestPath');
    return;
  }

  Object? decoded;
  try {
    decoded = jsonDecode(manifestFile.readAsStringSync());
  } catch (error) {
    report.warn('Artifact checksums', 'Cannot parse artifact.json: $error');
    return;
  }
  if (decoded is! Map) {
    report.warn('Artifact checksums', 'artifact.json must be a JSON object');
    return;
  }

  final manifest = <String, Object?>{};
  for (final entry in decoded.entries) {
    final key = entry.key;
    if (key is String) {
      manifest[key] = entry.value;
    }
  }

  final checksumsRaw = manifest['checksums'];
  if (checksumsRaw is! Map) {
    report.warn(
      'Artifact checksums',
      'Missing `checksums` block in artifact.json',
    );
    return;
  }

  final checksums = <String, Object?>{};
  for (final entry in checksumsRaw.entries) {
    final key = entry.key;
    if (key is String) {
      checksums[key] = entry.value;
    }
  }

  final pathsRaw = manifest['paths'];
  final paths = <String, Object?>{};
  if (pathsRaw is Map) {
    for (final entry in pathsRaw.entries) {
      final key = entry.key;
      if (key is String) {
        paths[key] = entry.value;
      }
    }
  }

  void verifyFileChecksum(String title, String key, String? path) {
    final expected = checksums[key];
    if (path == null || path.trim().isEmpty) {
      report.warn(title, 'Path is missing in artifact.json');
      return;
    }
    if (expected is! String || expected.trim().isEmpty) {
      report.warn(title, 'Missing checksum `$key` in artifact.json');
      return;
    }
    final file = File(path);
    if (!file.existsSync()) {
      report.warn(title, 'File not found: $path');
      return;
    }
    final actual = _sha256File(path);
    if (actual == expected) {
      report.ok(title, 'ok');
    } else {
      report.fail(
        title,
        'Checksum mismatch for $path (expected $expected, actual $actual)',
      );
    }
  }

  verifyFileChecksum(
    'Checksum library',
    'library_sha256',
    paths['library'] as String?,
  );
  verifyFileChecksum(
    'Checksum runtime',
    'runtime_sha256',
    paths['runtime_binary'] as String?,
  );
  verifyFileChecksum(
    'Checksum module header',
    'module_api_header_sha256',
    paths['module_api_header'] as String?,
  );

  final expectedManifest = checksums['manifest_sha256'];
  if (expectedManifest is! String || expectedManifest.trim().isEmpty) {
    report.warn(
      'Checksum manifest',
      'Missing checksum `manifest_sha256` in artifact.json',
    );
    return;
  }

  final manifestForDigest = Map<String, Object?>.from(manifest);
  final checksumForDigest = Map<String, Object?>.from(checksums);
  checksumForDigest['manifest_sha256'] = '';
  manifestForDigest['checksums'] = checksumForDigest;
  final digest = _sha256Text(
    const JsonEncoder.withIndent('  ').convert(manifestForDigest) + '\n',
  );
  if (digest == expectedManifest) {
    report.ok('Checksum manifest', 'ok');
  } else {
    report.fail(
      'Checksum manifest',
      'Checksum mismatch for artifact.json (expected $expectedManifest, actual $digest)',
    );
  }
}

Future<void> _appendArtifactAbiAndBridgeChecks({
  required DoctorReport report,
  required String outputPath,
  required String toolRoot,
}) async {
  final manifestPath = p.join(outputPath, 'artifact.json');
  final manifest = _readArtifactManifestMap(manifestPath);
  if (manifest.isEmpty) {
    report.warn('Artifact ABI', 'Missing or invalid $manifestPath');
    return;
  }

  final symbols = _asStringObjectMap(manifest['symbols']);
  final expectedSymbols = symbols.values
      .whereType<String>()
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet();
  if (expectedSymbols.isEmpty) {
    report.fail(
      'Artifact ABI',
      'artifact.json.symbols is missing or empty; cannot validate exports.',
    );
    return;
  }

  final binariesToCheck = <String, String>{};
  final hostLibraryPath = _libraryPathFromManifest(manifestPath);
  if (hostLibraryPath != null && hostLibraryPath.trim().isNotEmpty) {
    binariesToCheck['host'] = p.normalize(hostLibraryPath);
  }
  for (final entry in _manifestAndroidAbiLibraries(manifest).entries) {
    binariesToCheck['android:${entry.key}'] = p.normalize(entry.value);
  }
  for (final entry in _manifestIosSliceLibraries(manifest).entries) {
    binariesToCheck['ios:${entry.key}'] = p.normalize(entry.value);
  }

  if (binariesToCheck.isEmpty) {
    report.warn(
      'ABI symbols',
      'No binary paths found in artifact.json for symbol verification.',
    );
  }

  var hasSymbolFailures = false;
  var checkedBinaries = 0;
  for (final entry in binariesToCheck.entries) {
    final label = entry.key;
    final binaryPath = entry.value;
    if (!File(binaryPath).existsSync()) {
      report.fail('ABI symbols ($label)', 'Binary not found: $binaryPath');
      hasSymbolFailures = true;
      continue;
    }

    Set<String>? exported;
    try {
      exported = await _collectExportedSymbolsForDoctor(binaryPath);
    } on ToolError catch (error) {
      report.fail('ABI symbols ($label)', error.message);
      hasSymbolFailures = true;
      continue;
    }

    if (exported == null) {
      report.warn(
        'ABI symbols ($label)',
        'Skipped: neither nm nor dumpbin is available in PATH.',
      );
      continue;
    }

    checkedBinaries++;
    final missing = expectedSymbols
        .where((symbol) => !exported!.contains(symbol))
        .toList(growable: false);
    if (missing.isEmpty) {
      report.ok(
        'ABI symbols ($label)',
        'All ${expectedSymbols.length} required symbols are exported.',
      );
    } else {
      report.fail(
        'ABI symbols ($label)',
        'Missing symbols: ${missing.join(', ')}',
      );
      hasSymbolFailures = true;
    }
  }

  final verification = _asStringObjectMap(manifest['verification']);
  final declaredSymbolsExported = verification['symbols_exported'];
  if (declaredSymbolsExported is bool) {
    if (declaredSymbolsExported && hasSymbolFailures) {
      report.fail(
        'Artifact verification',
        'artifact.json verification.symbols_exported=true, but ABI checks failed.',
      );
    } else if (!declaredSymbolsExported &&
        !hasSymbolFailures &&
        checkedBinaries > 0) {
      report.warn(
        'Artifact verification',
        'artifact.json verification.symbols_exported=false, but symbols are exported.',
      );
    } else {
      report.ok(
        'Artifact verification',
        'verification.symbols_exported=$declaredSymbolsExported',
      );
    }
  } else {
    report.warn(
      'Artifact verification',
      'artifact.json.verification.symbols_exported is missing.',
    );
  }

  final expectedBridgeSource = p.normalize(
    p.join(toolRoot, 'native', 'dllart_bridge.c'),
  );
  final build = _manifestBuildSection(manifest);
  final bridge = _asStringObjectMap(build['bridge']);
  final recordedBridgeSource = bridge['source'];
  final recordedBridgeSha = bridge['sha256'];

  if (recordedBridgeSource is! String || recordedBridgeSource.trim().isEmpty) {
    report.fail(
      'Bridge source consistency',
      'artifact.json.build.bridge.source is missing.',
    );
  } else {
    final normalizedRecorded = p.normalize(recordedBridgeSource);
    if (normalizedRecorded != expectedBridgeSource) {
      report.fail(
        'Bridge source consistency',
        'artifact.json points to $normalizedRecorded, expected $expectedBridgeSource',
      );
    } else {
      report.ok('Bridge source consistency', _displayPath(normalizedRecorded));
    }
  }

  if (!File(expectedBridgeSource).existsSync()) {
    report.fail(
      'Bridge template/version',
      'Tool bridge source is missing: $expectedBridgeSource',
    );
    return;
  }

  final actualBridgeSha = _sha256File(expectedBridgeSource);
  if (recordedBridgeSha is! String || recordedBridgeSha.trim().isEmpty) {
    report.fail(
      'Bridge template/version',
      'artifact.json.build.bridge.sha256 is missing.',
    );
  } else if (recordedBridgeSha != actualBridgeSha) {
    report.fail(
      'Bridge template/version',
      'Bridge sha256 mismatch (artifact=$recordedBridgeSha, tool=$actualBridgeSha).',
    );
  } else {
    report.ok('Bridge template/version', 'sha256 matches tool bridge template');
  }
}

Map<String, String> _manifestIosSliceLibraries(Map<String, Object?> manifest) {
  final mobile = _manifestMobileOutputs(manifest);
  final ios = _asStringObjectMap(mobile['ios']);
  final slices = _asStringObjectMap(ios['slices']);
  final out = <String, String>{};
  for (final entry in slices.entries) {
    final value = entry.value;
    if (value is String && value.trim().isNotEmpty) {
      out[entry.key] = p.normalize(value);
    }
  }
  return out;
}

Future<Set<String>?> _collectExportedSymbolsForDoctor(String binaryPath) async {
  Future<Set<String>> runNm(String nmPath) {
    return _collectSymbolsWithNmForDoctor(
      nmExecutable: nmPath,
      binaryPath: binaryPath,
    );
  }

  if (Platform.isWindows) {
    final dumpbin = _findExecutable(<String>['dumpbin.exe', 'dumpbin']);
    if (dumpbin != null) {
      return _collectSymbolsWithDumpbinForDoctor(
        dumpbinExecutable: dumpbin,
        binaryPath: binaryPath,
      );
    }

    final nmPath =
        _findExecutable(<String>['llvm-nm.exe', 'nm.exe', 'llvm-nm', 'nm']) ??
        _firstExistingFile(<String>[
          r'C:\Program Files\LLVM\bin\llvm-nm.exe',
          r'C:\Program Files\LLVM\bin\nm.exe',
        ]);
    if (nmPath == null) {
      return null;
    }
    return runNm(nmPath);
  }

  final nmPath =
      _findExecutable(<String>['nm']) ??
      _firstExistingFile(<String>['/usr/bin/nm', '/usr/local/bin/nm']);
  if (nmPath == null) {
    return null;
  }
  return runNm(nmPath);
}

Future<Set<String>> _collectSymbolsWithNmForDoctor({
  required String nmExecutable,
  required String binaryPath,
}) async {
  final executableName = p.basename(nmExecutable).toLowerCase();
  final args =
      Platform.isMacOS && (executableName == 'nm' || executableName == 'nm.exe')
      ? <String>['-gU', binaryPath]
      : <String>['--defined-only', binaryPath];
  final result = await _runCommandCapture(nmExecutable, args);
  if (result.exitCode != 0) {
    throw ToolError(
      _processFailureSummary('$nmExecutable ${args.join(' ')}', result),
    );
  }

  final exported = <String>{};
  final text = '${_asText(result.stdout)}\n${_asText(result.stderr)}';
  for (final rawLine in text.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }
    final parts = line.split(RegExp(r'\s+'));
    if (parts.isEmpty) {
      continue;
    }
    var symbol = parts.last.trim();
    if (symbol.isEmpty) {
      continue;
    }
    if (symbol.startsWith('_')) {
      symbol = symbol.substring(1);
    }
    exported.add(symbol);
  }
  return exported;
}

Future<Set<String>> _collectSymbolsWithDumpbinForDoctor({
  required String dumpbinExecutable,
  required String binaryPath,
}) async {
  final result = await _runCommandCapture(dumpbinExecutable, <String>[
    '/EXPORTS',
    binaryPath,
  ]);
  if (result.exitCode != 0) {
    throw ToolError(
      _processFailureSummary('$dumpbinExecutable /EXPORTS', result),
    );
  }

  final exported = <String>{};
  final text = '${_asText(result.stdout)}\n${_asText(result.stderr)}';
  final linePattern = RegExp(
    r'^\s*\d+\s+[0-9A-Fa-f]+\s+[0-9A-Fa-f]+\s+(.+?)\s*$',
  );
  for (final rawLine in text.split('\n')) {
    final match = linePattern.firstMatch(rawLine);
    if (match == null) {
      continue;
    }
    var symbol = (match.group(1) ?? '').trim();
    if (symbol.isEmpty) {
      continue;
    }
    symbol = symbol.split(RegExp(r'\s+')).first;
    if (symbol.startsWith('_')) {
      symbol = symbol.substring(1);
    }
    exported.add(symbol);
  }
  return exported;
}

class _TextLocation {
  const _TextLocation(this.line, this.column);

  final int line;
  final int column;
}

class _ConfigTextLocator {
  _ConfigTextLocator(this._text);

  final String _text;

  _TextLocation fromOffset(int offset) {
    final safeOffset = offset.clamp(0, _text.length).toInt();
    var line = 1;
    var column = 1;
    for (var i = 0; i < safeOffset; i++) {
      if (_text.codeUnitAt(i) == 10) {
        line++;
        column = 1;
      } else {
        column++;
      }
    }
    return _TextLocation(line, column);
  }

  _TextLocation? keyLocation(String field) {
    final pattern = RegExp('"${RegExp.escape(field)}"\\s*:');
    final match = pattern.firstMatch(_text);
    if (match == null) {
      return null;
    }
    return fromOffset(match.start);
  }
}

String _configErrorPrefix(String configPath, {_TextLocation? location}) {
  final rendered = _displayPath(configPath);
  if (location == null) {
    return rendered;
  }
  return '$rendered:${location.line}:${location.column}';
}

LoadedConfig _loadConfig(ParsedArgs args, {bool allowInferred = true}) {
  final hasInline = args['name'] != null || args['source'] != null;

  if (hasInline) {
    final name = args['name'];
    final source = args['source'];
    if (name == null || source == null) {
      throw ToolError('Inline build requires both --name and --source');
    }

    final output = args['output'] ?? 'build';
    return LoadedConfig(
      config: DllartConfig(
        name: name,
        source: source,
        output: output,
        targets: List<String>.from(DllartConfig.defaultTargets),
      ),
      configPath: p.normalize(p.absolute('dllart.inline.json')),
    );
  }

  final configPath = p.normalize(p.absolute(args['config'] ?? 'dllart.json'));
  if (File(configPath).existsSync()) {
    final rawText = File(configPath).readAsStringSync();
    final locator = _ConfigTextLocator(rawText);

    Object? raw;
    try {
      raw = jsonDecode(rawText);
    } on FormatException catch (error) {
      final location = locator.fromOffset(error.offset ?? 0);
      throw ToolError(
        'Invalid JSON in ${_configErrorPrefix(configPath, location: location)}: '
        '${error.message}.',
      );
    }

    DllartConfig config;
    try {
      config = DllartConfig.fromJson(raw);
    } on ConfigValidationError catch (error) {
      final location = error.field == null
          ? null
          : locator.keyLocation(error.field!);
      throw ToolError(
        'Invalid config ${_configErrorPrefix(configPath, location: location)}: '
        '${error.message}. See doc/schema/dllart.schema.json',
      );
    }

    return LoadedConfig(config: config, configPath: configPath);
  }

  if (allowInferred) {
    final inferred = _inferConfigFromCurrentDirectory();
    if (inferred != null) {
      _logLine(
        'Config not found, using inferred config: '
        'name=${inferred.config.name}, source=${inferred.config.source}, '
        'output=${inferred.config.output}',
      );
      return inferred;
    }
  }

  throw ToolError(
    'Config file not found: $configPath. '
    'Run `dllart create <project>` or `dllart init`.',
  );
}

LoadedConfig? _inferConfigFromCurrentDirectory() {
  final cwd = p.normalize(Directory.current.path);
  final libDir = Directory(p.join(cwd, 'lib'));
  if (!libDir.existsSync()) {
    return null;
  }

  final explicitModule = File(p.join(cwd, 'lib', 'module.dart'));
  String? sourcePath;
  if (explicitModule.existsSync()) {
    sourcePath = explicitModule.path;
  } else {
    sourcePath = _selectInferredSource(libDir);
  }

  if (sourcePath == null) {
    return null;
  }

  return LoadedConfig(
    config: DllartConfig(
      name: _normalizePackageName(p.basename(cwd)),
      source: p.relative(sourcePath, from: cwd).replaceAll('\\', '/'),
      output: 'build',
      targets: List<String>.from(DllartConfig.defaultTargets),
    ),
    configPath: p.join(cwd, 'dllart.json'),
  );
}

String? _selectInferredSource(Directory libDir) {
  final exportedCandidates = <String>[];
  for (final entity in libDir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) {
      continue;
    }
    if (!entity.path.endsWith('.dart')) {
      continue;
    }
    final base = p.basename(entity.path);
    if (base == 'dllart_annotations.dart') {
      continue;
    }
    final source = entity.readAsStringSync();
    if (source.contains('@DllartExport')) {
      exportedCandidates.add(p.normalize(entity.path));
    }
  }

  if (exportedCandidates.isEmpty) {
    return null;
  }

  if (exportedCandidates.length == 1) {
    return exportedCandidates.first;
  }

  final moduleLike = exportedCandidates
      .where(
        (path) =>
            p.basename(path) == 'module.dart' ||
            p.basename(path).endsWith('_module.dart'),
      )
      .toList();

  if (moduleLike.length == 1) {
    return moduleLike.first;
  }

  return null;
}

List<ExportedFunction> _discoverExports(String sourceCode) {
  final annotation = RegExp(r'@DllartExport(?:\(([^)]*)\))?');
  final signature = RegExp(
    r'([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)\s*(?:async\s*)?(?:\{|=>)',
    multiLine: true,
  );

  final exports = <ExportedFunction>[];
  final seenNames = <String>{};

  for (final match in annotation.allMatches(sourceCode)) {
    final suffix = sourceCode.substring(match.end);
    final fnMatch = signature.firstMatch(suffix);
    if (fnMatch == null) {
      final line = _lineNumberAt(sourceCode, match.start);
      throw ToolError(
        'Cannot find function declaration after @DllartExport at line $line',
      );
    }

    final dartName = fnMatch.group(1)!;
    final params = fnMatch.group(2) ?? '';
    final parsedParams = _parseRequiredPositionalParams(
      params,
      dartName,
      sourceCode,
      match.start,
    );
    final arity = parsedParams.length;

    bool supportsI64_2 = false;
    bool directI64_2 = false;
    bool supportsI64_4 = false;
    bool directI64_4 = false;
    bool supportsF64_2 = false;
    bool directF64_2 = false;
    bool supportsF64_4 = false;
    bool directF64_4 = false;
    bool supportsBytes = false;
    bool directBytes = false;
    if (arity == 1) {
      supportsI64_2 = true;
      final bytesCompatible = _isBytesCompatibleParamToken(parsedParams.first);
      supportsBytes = bytesCompatible;
      directBytes = bytesCompatible;
    } else if (arity == 2) {
      final i64Compatible = parsedParams.every(_isI64CompatibleParamToken);
      final f64Compatible = parsedParams.every(_isF64CompatibleParamToken);
      supportsI64_2 = i64Compatible;
      directI64_2 = i64Compatible;
      supportsF64_2 = f64Compatible;
      directF64_2 = f64Compatible;
    } else if (arity == 4) {
      final i64Compatible = parsedParams.every(_isI64CompatibleParamToken);
      final f64Compatible = parsedParams.every(_isF64CompatibleParamToken);
      supportsI64_4 = i64Compatible;
      directI64_4 = i64Compatible;
      supportsF64_4 = f64Compatible;
      directF64_4 = f64Compatible;
    }

    final aliasRaw = match.group(1);
    String exportName = dartName;
    if (aliasRaw != null && aliasRaw.trim().isNotEmpty) {
      final aliasMatch = RegExp(r'''["']([^"']+)["']''').firstMatch(aliasRaw);
      if (aliasMatch != null) {
        exportName = aliasMatch.group(1)!;
      }
    }

    if (!seenNames.add(exportName)) {
      throw ToolError(
        'Duplicate export name "$exportName" detected for @DllartExport',
      );
    }

    exports.add(
      ExportedFunction(
        dartName: dartName,
        exportName: exportName,
        arity: arity,
        supportsI64_2: supportsI64_2,
        directI64_2: directI64_2,
        supportsI64_4: supportsI64_4,
        directI64_4: directI64_4,
        supportsF64_2: supportsF64_2,
        directF64_2: directF64_2,
        supportsF64_4: supportsF64_4,
        directF64_4: directF64_4,
        supportsBytes: supportsBytes,
        directBytes: directBytes,
        line: _lineNumberAt(sourceCode, match.start),
      ),
    );
  }

  return exports;
}

List<String> _parseRequiredPositionalParams(
  String params,
  String functionName,
  String source,
  int offset,
) {
  final text = params.trim();
  if (text.isEmpty) {
    return <String>[];
  }

  var angle = 0;
  var paren = 0;
  var square = 0;
  var curly = 0;
  var current = StringBuffer();
  final tokens = <String>[];

  void flush() {
    final token = current.toString().trim();
    if (token.isNotEmpty) {
      tokens.add(token);
    }
    current = StringBuffer();
  }

  for (final rune in text.runes) {
    final ch = String.fromCharCode(rune);
    switch (ch) {
      case '<':
        angle++;
        break;
      case '>':
        if (angle > 0) {
          angle--;
        }
        break;
      case '(':
        paren++;
        break;
      case ')':
        if (paren > 0) {
          paren--;
        }
        break;
      case '[':
        if (angle == 0 && paren == 0 && square == 0 && curly == 0) {
          final line = _lineNumberAt(source, offset);
          throw ToolError(
            'Function $functionName at line $line uses optional positional params, '
            'only required positional params are supported',
          );
        }
        square++;
        break;
      case ']':
        if (square > 0) {
          square--;
        }
        break;
      case '{':
        if (angle == 0 && paren == 0 && square == 0 && curly == 0) {
          final line = _lineNumberAt(source, offset);
          throw ToolError(
            'Function $functionName at line $line uses named params, '
            'only required positional params are supported',
          );
        }
        curly++;
        break;
      case '}':
        if (curly > 0) {
          curly--;
        }
        break;
      case ',':
        if (angle == 0 && paren == 0 && square == 0 && curly == 0) {
          flush();
          continue;
        }
        break;
      default:
        break;
    }
    current.write(ch);
  }
  flush();

  if (tokens.length > 4) {
    final line = _lineNumberAt(source, offset);
    throw ToolError(
      'Function $functionName at line $line has ${tokens.length} parameters, '
      'only 0, 1, 2 or 4 are currently supported',
    );
  }

  return tokens;
}

const Set<String> _i64CompatibleParamTypes = <String>{
  'dynamic',
  'Object',
  'Object?',
  'num',
  'num?',
  'int',
  'int?',
};

const Set<String> _f64CompatibleParamTypes = <String>{
  'dynamic',
  'Object',
  'Object?',
  'num',
  'num?',
  'double',
  'double?',
};

const Set<String> _bytesCompatibleParamTypes = <String>{
  'Uint8List',
  'Uint8List?',
  'List<int>',
  'List<int>?',
};

bool _isI64CompatibleParamToken(String token) {
  return _isCompatibleParamToken(token, _i64CompatibleParamTypes);
}

bool _isF64CompatibleParamToken(String token) {
  return _isCompatibleParamToken(token, _f64CompatibleParamTypes);
}

bool _isBytesCompatibleParamToken(String token) {
  final type = _paramTypeFromToken(token);
  return _bytesCompatibleParamTypes.contains(type);
}

bool _isCompatibleParamToken(String token, Set<String> allowedTypes) {
  final type = _paramTypeFromToken(token);
  if (type.isEmpty) {
    return true;
  }
  return allowedTypes.contains(type);
}

String _paramTypeFromToken(String token) {
  final normalized = token.replaceAll(RegExp(r'\s+'), ' ').trim();
  final parts = normalized.split(' ');
  if (parts.length <= 1) {
    return '';
  }
  return parts.sublist(0, parts.length - 1).join('').trim();
}

int _lineNumberAt(String source, int offset) {
  return '\n'.allMatches(source.substring(0, offset)).length + 1;
}

Map<String, int> _computeI64_2MethodIds(List<ExportedFunction> exports) {
  return _computeMethodIds(exports, (fn) => fn.supportsI64_2);
}

Map<String, int> _computeI64_4MethodIds(List<ExportedFunction> exports) {
  return _computeMethodIds(exports, (fn) => fn.supportsI64_4);
}

Map<String, int> _computeF64_2MethodIds(List<ExportedFunction> exports) {
  return _computeMethodIds(exports, (fn) => fn.supportsF64_2);
}

Map<String, int> _computeF64_4MethodIds(List<ExportedFunction> exports) {
  return _computeMethodIds(exports, (fn) => fn.supportsF64_4);
}

Map<String, int> _computeBytesMethodIds(List<ExportedFunction> exports) {
  return _computeMethodIds(exports, (fn) => fn.supportsBytes);
}

Map<String, int> _computeMethodIds(
  List<ExportedFunction> exports,
  bool Function(ExportedFunction fn) supportsTypedDispatch,
) {
  final out = <String, int>{};
  var nextId = 0;
  for (final fn in exports) {
    if (!supportsTypedDispatch(fn)) {
      continue;
    }
    out[fn.exportName] = nextId;
    nextId++;
  }
  return out;
}
