part of dllart_cli;

String _frontendPathArg(String path) {
  final normalized = p.normalize(path);
  return normalized;
}

String _frontendUriArg(String path) {
  final normalized = p.normalize(path);
  if (!Platform.isWindows) {
    return normalized;
  }
  return Uri.file(normalized, windows: true).toString();
}

Future<void> _commandBuild(ParsedArgs args) async {
  _applyLoggingFromConfig(null);
  final jsonMode = _isJsonMode(args);
  final loaded = _loadConfig(args);
  _applyLoggingFromConfig(loaded.config);
  final buildTarget = _resolveBuildTarget(args);
  final androidAbis = _resolveAndroidAbis(args);
  final iosVariants = _resolveIosVariants(args);
  final runtimeProfile = _resolveRuntimeProfile(loaded, args);
  final generatedAt = _deterministicBuildTimestampUtc();
  final reproducibleBuild = _isReproducibleBuildEnabled();
  final sourcePath = loaded.resolvePath(loaded.config.source);
  final outputPath = loaded.resolvePath(loaded.config.output);
  final packagesConfig = await _ensurePackageConfig(
    sourcePath: sourcePath,
    configDir: loaded.configDir,
  );

  if (!File(sourcePath).existsSync()) {
    throw ToolError('Source file not found: $sourcePath');
  }

  final sourceCode = await File(sourcePath).readAsString();
  final exports = _discoverExports(sourceCode);
  if (exports.isEmpty) {
    throw ToolError(
      'No exports found in $sourcePath. Add @DllartExport() above top-level functions.',
    );
  }

  final outputRoot = Directory(outputPath);
  outputRoot.createSync(recursive: true);
  Map<String, Object?>? buildData;
  await _withBuildLock(outputPath, () async {
    _cleanupLegacyArtifacts(outputPath, loaded.config.name);

    final workRoot = Directory(p.join(outputPath, '.work'));
    workRoot.createSync(recursive: true);
    final workDir = await workRoot.createTemp('${loaded.config.name}_');

    final generatedDir = Directory(p.join(workDir.path, 'generated'));
    final includeDir = Directory(p.join(outputPath, 'include'));
    final libDir = Directory(p.join(outputPath, 'lib'));
    final integrationDir = Directory(p.join(outputPath, 'integration'));
    final cmakeDir = Directory(p.join(integrationDir.path, 'cmake'));
    final pkgConfigDir = Directory(p.join(integrationDir.path, 'pkgconfig'));

    generatedDir.createSync(recursive: true);
    includeDir.createSync(recursive: true);
    libDir.createSync(recursive: true);
    cmakeDir.createSync(recursive: true);
    pkgConfigDir.createSync(recursive: true);

    try {
      final generatedEntrypoint = p.join(
        generatedDir.path,
        '${loaded.config.name}_entry.dart',
      );
      await File(
        generatedEntrypoint,
      ).writeAsString(_generateEntrypoint(sourcePath, exports));
      final generatedSidecarEntrypoint = p.join(
        generatedDir.path,
        '${loaded.config.name}_sidecar.dart',
      );
      await File(
        generatedSidecarEntrypoint,
      ).writeAsString(_generateSidecarEntrypoint(generatedEntrypoint));

      final generatedApi = p.join(
        includeDir.path,
        '${loaded.config.name}_api.h',
      );
      await File(
        generatedApi,
      ).writeAsString(_generateApiHeader(loaded.config.name, exports));

      final toolchain = _resolveToolchain();
      final toolRoot = _toolRoot(packageConfigPath: packagesConfig);
      final bridgeSource = p.join(toolRoot, 'native', 'dllart_bridge.c');
      if (!File(bridgeSource).existsSync()) {
        throw ToolError('Bridge source is missing: $bridgeSource');
      }

      final aotDill = p.join(workDir.path, 'module.aot.dill');
      final frontendArgs = <String>[
        _frontendPathArg(toolchain.frontendServer),
        '--sdk-root=${_frontendUriArg(toolchain.sdkRoot)}',
        '--target=vm',
        '--aot',
        '--tfa',
        '--platform=${_frontendUriArg(toolchain.platformDill)}',
      ];
      if (packagesConfig != null) {
        frontendArgs.add('--packages=${_frontendUriArg(packagesConfig)}');
      }
      frontendArgs.addAll(<String>[
        '--output-dill=${_frontendPathArg(aotDill)}',
        _frontendPathArg(generatedEntrypoint),
      ]);

      _logLine('[1/4] Compiling AOT dill');
      await _runCommand(toolchain.dartaot, frontendArgs);

      final manifestPath = p.join(outputPath, 'artifact.json');
      final usagePath = p.join(outputPath, 'USAGE.md');
      final cmakeConfigPath = p.join(
        cmakeDir.path,
        '${loaded.config.name}Config.cmake',
      );
      final pkgConfigPath = p.join(
        pkgConfigDir.path,
        '${loaded.config.name}.pc',
      );
      final checksums = <String, String>{
        'module_api_header_sha256': _sha256File(generatedApi),
      };
      final mobileOutputs = <String, Object?>{};
      final toolchainChecks = <String, Object?>{
        'dart': toolchain.dart,
        'dartaotruntime': toolchain.dartaot,
        'gen_snapshot': toolchain.genSnapshot,
        'clang': toolchain.clang,
        'sdk_include': toolchain.sdkInclude,
      };

      String? outputLib;
      String? libFileName;
      String? runtimeFileName;
      String? bundledRuntimePath;
      String? sidecarFileName;
      String? sidecarBinaryPath;
      var symbolsExported = false;

      if (buildTarget == 'host') {
        final aotAsm = p.join(workDir.path, 'module.S');
        final aotObj = p.join(workDir.path, 'module.o');

        _logLine('[2/4] Generating AOT assembly');
        await _runCommand(toolchain.genSnapshot, <String>[
          '--snapshot_kind=app-aot-assembly',
          '--assembly=$aotAsm',
          aotDill,
        ]);

        _logLine('[3/4] Assembling object');
        await _runCommand(toolchain.clang, <String>[
          '-c',
          aotAsm,
          '-o',
          aotObj,
        ]);
        final snapshotSymbolDefines = await _snapshotSymbolDefinesForObject(
          aotObj,
        );

        final runtimePathForDefine = toolchain.dartaot.replaceAll('\\', '/');
        final runtimeDefine =
            '-DDLLART_DEFAULT_RUNTIME_PATH="$runtimePathForDefine"';
        sidecarFileName = _sidecarExecutableNameForHost(loaded.config.name);
        final resolvedSidecarBinaryPath = p.join(
          outputPath,
          'runtime',
          sidecarFileName,
        );
        sidecarBinaryPath = resolvedSidecarBinaryPath;
        final sidecarPathForDefine =
            resolvedSidecarBinaryPath.replaceAll('\\', '/');
        final sidecarDefine =
            '-DDLLART_DEFAULT_SIDECAR_PATH="$sidecarPathForDefine"';
        final runtimeVersionDefine =
            '-DDLLART_EXPECTED_DART_VERSION="${_escapeCString(toolchain.dartSdkVersion)}"';

        outputLib = _outputLibraryPath(libDir.path, loaded.config.name);

        _logLine('[4/4] Linking shared library');
        final linkArgs = <String>[
          '-O2',
          ..._bridgeSymbolDefines(loaded.config.name),
          runtimeDefine,
          sidecarDefine,
          runtimeVersionDefine,
          '-DDLLART_JSON_IN_MAX_BYTES=${loaded.config.limits.jsonInMaxBytes}',
          '-DDLLART_JSON_OUT_MAX_BYTES=${loaded.config.limits.jsonOutMaxBytes}',
          '-DDLLART_BYTES_IN_MAX_BYTES=${loaded.config.limits.bytesInMaxBytes}',
          '-DDLLART_BYTES_OUT_MAX_BYTES=${loaded.config.limits.bytesOutMaxBytes}',
          '-DDLLART_METHOD_CACHE_MAX_ENTRIES=${loaded.config.limits.methodCacheMaxEntries}',
          '-DDLLART_RUNTIME_PROFILE="${_escapeCString(runtimeProfile)}"',
          ...snapshotSymbolDefines,
          '-I${toolchain.sdkInclude}',
          bridgeSource,
          aotObj,
          '-o',
          outputLib,
        ];

        if (Platform.isMacOS) {
          linkArgs.insertAll(1, <String>['-fPIC', '-dynamiclib']);
          linkArgs.add('-lpthread');
        } else if (Platform.isLinux) {
          linkArgs.insertAll(1, <String>['-fPIC', '-shared']);
          linkArgs.addAll(<String>['-ldl', '-lpthread']);
        } else if (Platform.isWindows) {
          linkArgs.insertAll(1, <String>['-shared']);
        } else {
          throw ToolError(
            'Unsupported host platform: ${Platform.operatingSystem}',
          );
        }

        await _runCommand(toolchain.clang, linkArgs);

        final runtimeDir = Directory(p.join(outputPath, 'runtime'));
        runtimeDir.createSync(recursive: true);
        runtimeFileName = _runtimeExecutableNameForHost();
        final resolvedRuntimePath = p.join(runtimeDir.path, runtimeFileName);
        bundledRuntimePath = resolvedRuntimePath;
        await File(toolchain.dartaot).copy(resolvedRuntimePath);
        if (!Platform.isWindows) {
          Process.runSync('chmod', <String>['+x', resolvedRuntimePath]);
        }
        _logLine('[host] Compiling sidecar runtime helper');
        await _runCommand(toolchain.dart, <String>[
          'compile',
          'exe',
          _frontendPathArg(generatedSidecarEntrypoint),
          '-o',
          _frontendPathArg(resolvedSidecarBinaryPath),
        ]);
        if (!Platform.isWindows) {
          Process.runSync('chmod', <String>['+x', resolvedSidecarBinaryPath]);
        }

        libFileName = p.basename(outputLib);
        checksums['library_sha256'] = _sha256File(outputLib);
        checksums['runtime_sha256'] = _sha256File(resolvedRuntimePath);
        checksums['sidecar_sha256'] = _sha256File(resolvedSidecarBinaryPath);
        toolchainChecks['sidecar_runtime'] = resolvedSidecarBinaryPath;

        await File(cmakeConfigPath).writeAsString(
          _generateCMakeConfig(
            moduleName: loaded.config.name,
            libraryFileName: libFileName,
          ),
        );
        await File(
          pkgConfigPath,
        ).writeAsString(_generatePkgConfig(moduleName: loaded.config.name));
        await File(usagePath).writeAsString(
          _generateArtifactUsage(
            moduleName: loaded.config.name,
            outputPath: outputPath,
            libraryFileName: libFileName,
            runtimeFileName: runtimeFileName,
            sidecarFileName: sidecarFileName,
            runtimeExpectedSdkVersion: toolchain.dartSdkVersion,
          ),
        );
        symbolsExported = true;
      } else {
        if (buildTarget == 'android') {
          final androidBuilt = await _buildAndroidArtifacts(
            moduleName: loaded.config.name,
            outputPath: outputPath,
            workDirPath: workDir.path,
            aotDillPath: aotDill,
            bridgeSource: bridgeSource,
            toolchain: toolchain,
            runtimeProfile: runtimeProfile,
            limits: loaded.config.limits,
            androidAbis: androidAbis,
          );
          mobileOutputs['android'] = androidBuilt;
          toolchainChecks['android_ndk_home'] =
              (Platform.environment['ANDROID_NDK_HOME'] ?? '').trim();
          await File(usagePath).writeAsString(
            _generateMobileArtifactUsage(
              moduleName: loaded.config.name,
              target: 'android',
              mobileOutputs: mobileOutputs,
            ),
          );
          symbolsExported = true;
        } else if (buildTarget == 'ios') {
          final iosBuilt = await _buildIosArtifacts(
            moduleName: loaded.config.name,
            outputPath: outputPath,
            workDirPath: workDir.path,
            aotDillPath: aotDill,
            bridgeSource: bridgeSource,
            toolchain: toolchain,
            runtimeProfile: runtimeProfile,
            limits: loaded.config.limits,
            iosVariants: iosVariants,
            includeDir: includeDir.path,
          );
          mobileOutputs['ios'] = iosBuilt;
          await File(usagePath).writeAsString(
            _generateMobileArtifactUsage(
              moduleName: loaded.config.name,
              target: 'ios',
              mobileOutputs: mobileOutputs,
            ),
          );
          symbolsExported = true;
        } else {
          throw ToolError('Unsupported build target: $buildTarget');
        }
      }

      final effectiveTarget = buildTarget;
      final bridgeSourceSha256 = _sha256File(bridgeSource);
      toolchainChecks['bridge_source'] = bridgeSource;
      toolchainChecks['bridge_source_sha256'] = bridgeSourceSha256;

      await File(manifestPath).writeAsString(
        _generateArtifactManifest(
          moduleName: loaded.config.name,
          sourcePath: sourcePath,
          outputPath: outputPath,
          libraryFileName: libFileName,
          runtimeFileName: runtimeFileName,
          runtimePath: bundledRuntimePath,
          sidecarFileName: sidecarFileName,
          sidecarPath: sidecarBinaryPath,
          runtimeExpectedSdkVersion: toolchain.dartSdkVersion,
          runtimeProfile: runtimeProfile,
          generatedAtUtc: generatedAt,
          reproducibleBuild: reproducibleBuild,
          requestedTarget: buildTarget,
          effectiveTarget: effectiveTarget,
          mobileOutputs: mobileOutputs,
          bridgeSourcePath: bridgeSource,
          bridgeSourceSha256: bridgeSourceSha256,
          symbolsExported: symbolsExported,
          checksums: checksums,
          exports: exports,
        ),
      );

      final cmakeExists = File(cmakeConfigPath).existsSync();
      final pkgConfigExists = File(pkgConfigPath).existsSync();
      buildData = <String, Object?>{
        'module': loaded.config.name,
        'source': sourcePath,
        'output_root': outputPath,
        if (outputLib != null) 'library': outputLib,
        'headers_dir': includeDir.path,
        'api_header': generatedApi,
        'manifest': manifestPath,
        'usage': usagePath,
        if (cmakeExists) 'cmake_config': cmakeConfigPath,
        if (pkgConfigExists) 'pkg_config': pkgConfigPath,
        if (bundledRuntimePath != null) 'runtime': bundledRuntimePath,
        if (sidecarBinaryPath != null) 'sidecar_runtime': sidecarBinaryPath,
        'runtime_profile': runtimeProfile,
        'requested_target': buildTarget,
        'effective_target': effectiveTarget,
        'toolchain_checks': toolchainChecks,
        'mobile_outputs': mobileOutputs,
        'reproducible': reproducibleBuild,
        'exports': exports.map((item) => item.exportName).toList(),
      };

      if (!jsonMode && !_inJsonMode) {
        if (_inVerboseMode) {
          stdout.writeln('');
          stdout.writeln('Module:       ${loaded.config.name}');
          stdout.writeln('Source:       $sourcePath');
          if (outputLib != null) {
            stdout.writeln('Library:      $outputLib');
          }
          stdout.writeln('Headers:      ${includeDir.path}');
          stdout.writeln('Method API:   $generatedApi');
          stdout.writeln('Manifest:     $manifestPath');
          stdout.writeln('Usage guide:  $usagePath');
          if (cmakeExists) {
            stdout.writeln('CMake config: $cmakeConfigPath');
          }
          if (bundledRuntimePath != null) {
            stdout.writeln('Runtime:      $bundledRuntimePath');
          }
          if (sidecarBinaryPath != null) {
            stdout.writeln('Sidecar:      $sidecarBinaryPath');
          }
          stdout.writeln('Runtime prof: $runtimeProfile');
          stdout.writeln('Target req:   $buildTarget');
          stdout.writeln('Target eff:   $effectiveTarget');
          if (mobileOutputs.isNotEmpty) {
            stdout.writeln(
              'Mobile out:   ${const JsonEncoder().convert(mobileOutputs)}',
            );
          }
          stdout.writeln(
            'Exports:      ${exports.map((e) => e.exportName).join(', ')}',
          );
        } else {
          stdout.writeln('Build completed for ${loaded.config.name}.');
          stdout.writeln('Artifact root: ${_displayPath(outputPath)}');
          stdout.writeln('Target: $effectiveTarget');
        }
        stdout.writeln('Next: dllart integrate');
      }
    } finally {
      final keepWorkDir =
          (Platform.environment['DLLART_KEEP_WORKDIR'] ?? '').trim() == '1';
      if (keepWorkDir) {
        _logLine('Keeping work dir: ${_displayPath(workDir.path)}');
      } else {
        try {
          workDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
  });

  if (jsonMode) {
    _writeJsonCommandResult('build', ok: true, status: 'ok', data: buildData);
  }
}

String _generateMobileArtifactUsage({
  required String moduleName,
  required String target,
  required Map<String, Object?> mobileOutputs,
}) {
  final lines = <String>[
    '# DLLART Artifact Usage',
    '',
    'Module: `$moduleName`',
    'Target: `$target`',
    '',
    'This build contains mobile artifacts only.',
    '',
    'Outputs:',
    const JsonEncoder.withIndent('  ').convert(mobileOutputs),
    '',
    'Next steps:',
    '- `dllart integrate` to print platform snippets.',
    '- `dllart package $target --force` to scaffold packaging using real artifacts.',
    '',
  ];
  return '${lines.join('\n')}\n';
}

const List<String> _defaultAndroidAbis = <String>[
  'arm64-v8a',
  'armeabi-v7a',
  'x86_64',
];

List<String> _resolveAndroidAbis(ParsedArgs args) {
  final raw = args['android-abis'];
  if (raw == null || raw.trim().isEmpty) {
    return List<String>.from(_defaultAndroidAbis);
  }

  final out = <String>[];
  for (final chunk in raw.split(',')) {
    final abi = chunk.trim();
    if (abi.isEmpty) {
      continue;
    }
    if (abi != 'arm64-v8a' && abi != 'armeabi-v7a' && abi != 'x86_64') {
      throw ToolError(
        'Unsupported Android ABI: $abi. Supported values: '
        'arm64-v8a, armeabi-v7a, x86_64.',
      );
    }
    if (!out.contains(abi)) {
      out.add(abi);
    }
  }

  if (out.isEmpty) {
    throw ToolError(
      'No Android ABIs resolved from --android-abis. '
      'Example: --android-abis=arm64-v8a,armeabi-v7a,x86_64',
    );
  }
  return out;
}

String _resolveIosVariants(ParsedArgs args) {
  final raw = (args['ios-variants'] ?? 'all').trim().toLowerCase();
  if (raw == 'all' || raw == 'device' || raw == 'simulator') {
    return raw;
  }
  throw ToolError(
    'Unsupported iOS variants: $raw. Use all, device, or simulator.',
  );
}

Future<Map<String, Object?>> _buildAndroidArtifacts({
  required String moduleName,
  required String outputPath,
  required String workDirPath,
  required String aotDillPath,
  required String bridgeSource,
  required Toolchain toolchain,
  required String runtimeProfile,
  required DllartLimitsConfig limits,
  required List<String> androidAbis,
}) async {
  final ndkHome = (Platform.environment['ANDROID_NDK_HOME'] ?? '').trim();
  if (ndkHome.isEmpty) {
    throw ToolError(
      'ANDROID_NDK_HOME is required for --target=android. '
      'Export ANDROID_NDK_HOME to your NDK root.',
    );
  }

  final hostTag = _resolveAndroidNdkHostTag(ndkHome);
  final llvmBin = p.join(
    ndkHome,
    'toolchains',
    'llvm',
    'prebuilt',
    hostTag,
    'bin',
  );
  if (!Directory(llvmBin).existsSync()) {
    throw ToolError('Android NDK LLVM toolchain not found: $llvmBin');
  }

  final nmPath = _firstExistingFile(<String>[
    p.join(llvmBin, Platform.isWindows ? 'llvm-nm.exe' : 'llvm-nm'),
  ]);
  if (nmPath == null) {
    throw ToolError('llvm-nm not found in Android NDK toolchain: $llvmBin');
  }

  final runtimeDefine = '-DDLLART_DEFAULT_RUNTIME_PATH=""';
  final runtimeVersionDefine =
      '-DDLLART_EXPECTED_DART_VERSION="${_escapeCString(toolchain.dartSdkVersion)}"';
  final requiredSymbols = _requiredAbiSymbols(moduleName);
  final abiOutputs = <String, String>{};

  for (final abi in androidAbis) {
    final abiTag = abi.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    final genSnapshot = _resolveAndroidGenSnapshot(
      toolchain: toolchain,
      abi: abi,
    );
    final asmPath = p.join(workDirPath, 'module_android_$abiTag.S');
    final objPath = p.join(workDirPath, 'module_android_$abiTag.o');

    _logLine('[android:$abi] Generating AOT assembly');
    await _runCommand(genSnapshot, <String>[
      '--snapshot_kind=app-aot-assembly',
      '--assembly=$asmPath',
      aotDillPath,
    ]);

    final targetSpec = _androidAbiTarget(abi);
    final clangPath = _firstExistingFile(<String>[
      p.join(
        llvmBin,
        '${targetSpec.triple}${targetSpec.apiLevel}-clang${Platform.isWindows ? '.cmd' : ''}',
      ),
      p.join(
        llvmBin,
        '${targetSpec.triple}${targetSpec.apiLevel}-clang${Platform.isWindows ? '.exe' : ''}',
      ),
    ]);
    if (clangPath == null) {
      throw ToolError(
        'Android clang for $abi was not found under $llvmBin. '
        'Expected ${targetSpec.triple}${targetSpec.apiLevel}-clang.',
      );
    }

    _logLine('[android:$abi] Assembling object');
    await _runCommand(clangPath, <String>['-c', asmPath, '-o', objPath]);
    final snapshotSymbolDefines = await _snapshotSymbolDefinesForObject(
      objPath,
    );

    final abiDir = Directory(p.join(outputPath, 'lib', 'android', abi));
    abiDir.createSync(recursive: true);
    final outLib = p.join(abiDir.path, 'lib$moduleName.so');

    _logLine('[android:$abi] Linking shared library');
    await _runCommand(clangPath, <String>[
      '-O2',
      '-shared',
      '-fPIC',
      ..._bridgeSymbolDefines(moduleName),
      runtimeDefine,
      runtimeVersionDefine,
      '-DDLLART_JSON_IN_MAX_BYTES=${limits.jsonInMaxBytes}',
      '-DDLLART_JSON_OUT_MAX_BYTES=${limits.jsonOutMaxBytes}',
      '-DDLLART_BYTES_IN_MAX_BYTES=${limits.bytesInMaxBytes}',
      '-DDLLART_BYTES_OUT_MAX_BYTES=${limits.bytesOutMaxBytes}',
      '-DDLLART_METHOD_CACHE_MAX_ENTRIES=${limits.methodCacheMaxEntries}',
      '-DDLLART_RUNTIME_PROFILE="${_escapeCString(runtimeProfile)}"',
      ...snapshotSymbolDefines,
      '-I${toolchain.sdkInclude}',
      bridgeSource,
      objPath,
      '-ldl',
      '-o',
      outLib,
    ]);

    await _verifySymbolsWithNm(
      nmExecutable: nmPath,
      libraryPath: outLib,
      requiredSymbols: requiredSymbols,
    );
    abiOutputs[abi] = outLib;
  }

  return <String, Object?>{
    'abis': abiOutputs.map(
      (key, value) => MapEntry<String, Object?>(key, p.normalize(value)),
    ),
  };
}

Future<Map<String, Object?>> _buildIosArtifacts({
  required String moduleName,
  required String outputPath,
  required String workDirPath,
  required String aotDillPath,
  required String bridgeSource,
  required Toolchain toolchain,
  required String runtimeProfile,
  required DllartLimitsConfig limits,
  required String iosVariants,
  required String includeDir,
}) async {
  if (!Platform.isMacOS) {
    throw ToolError(
      '--target=ios is supported only on macOS (requires xcrun/xcodebuild).',
    );
  }

  final includeDevice = iosVariants == 'all' || iosVariants == 'device';
  final includeSimulator = iosVariants == 'all' || iosVariants == 'simulator';
  if (!includeDevice && !includeSimulator) {
    throw ToolError(
      'No iOS variants selected. Use --ios-variants=all|device|simulator.',
    );
  }

  final runtimeDefine = '-DDLLART_DEFAULT_RUNTIME_PATH=""';
  final runtimeVersionDefine =
      '-DDLLART_EXPECTED_DART_VERSION="${_escapeCString(toolchain.dartSdkVersion)}"';
  final requiredSymbols = _requiredAbiSymbols(moduleName);
  final iosRoot = Directory(p.join(outputPath, 'lib', 'ios'));
  iosRoot.createSync(recursive: true);
  final builtSlices = <String, String>{};

  Future<String> buildSlice({
    required String name,
    required String sdk,
    required String target,
    required String genSnapshot,
  }) async {
    final tag = name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    final asmPath = p.join(workDirPath, 'module_ios_$tag.S');
    final objPath = p.join(workDirPath, 'module_ios_$tag.o');
    final outDir = Directory(p.join(iosRoot.path, tag));
    outDir.createSync(recursive: true);
    final outLib = p.join(outDir.path, 'lib$moduleName.dylib');

    _logLine('[ios:$name] Generating AOT assembly');
    await _runCommand(genSnapshot, <String>[
      '--snapshot_kind=app-aot-assembly',
      '--assembly=$asmPath',
      aotDillPath,
    ]);

    _logLine('[ios:$name] Assembling object');
    await _runCommand('xcrun', <String>[
      '--sdk',
      sdk,
      'clang',
      '-target',
      target,
      '-fPIC',
      '-c',
      asmPath,
      '-o',
      objPath,
    ]);
    final snapshotSymbolDefines = await _snapshotSymbolDefinesForObject(
      objPath,
    );

    _logLine('[ios:$name] Linking dynamic library');
    await _runCommand('xcrun', <String>[
      '--sdk',
      sdk,
      'clang',
      '-target',
      target,
      '-dynamiclib',
      '-fPIC',
      ..._bridgeSymbolDefines(moduleName),
      runtimeDefine,
      runtimeVersionDefine,
      '-DDLLART_JSON_IN_MAX_BYTES=${limits.jsonInMaxBytes}',
      '-DDLLART_JSON_OUT_MAX_BYTES=${limits.jsonOutMaxBytes}',
      '-DDLLART_BYTES_IN_MAX_BYTES=${limits.bytesInMaxBytes}',
      '-DDLLART_BYTES_OUT_MAX_BYTES=${limits.bytesOutMaxBytes}',
      '-DDLLART_METHOD_CACHE_MAX_ENTRIES=${limits.methodCacheMaxEntries}',
      '-DDLLART_RUNTIME_PROFILE="${_escapeCString(runtimeProfile)}"',
      ...snapshotSymbolDefines,
      '-I${toolchain.sdkInclude}',
      bridgeSource,
      objPath,
      '-Wl,-install_name,@rpath/lib$moduleName.dylib',
      '-o',
      outLib,
    ]);

    await _verifySymbolsWithNm(
      nmExecutable: 'nm',
      libraryPath: outLib,
      requiredSymbols: requiredSymbols,
    );
    return outLib;
  }

  if (includeDevice) {
    final genSnapshot = _resolveIosGenSnapshot(
      toolchain: toolchain,
      arch: 'arm64',
    );
    builtSlices['device-arm64'] = await buildSlice(
      name: 'device-arm64',
      sdk: 'iphoneos',
      target: 'arm64-apple-ios12.0',
      genSnapshot: genSnapshot,
    );
  }

  String? simulatorLib;
  if (includeSimulator) {
    final simArm64 = await buildSlice(
      name: 'simulator-arm64',
      sdk: 'iphonesimulator',
      target: 'arm64-apple-ios12.0-simulator',
      genSnapshot: _resolveIosGenSnapshot(toolchain: toolchain, arch: 'arm64'),
    );
    final simX64 = await buildSlice(
      name: 'simulator-x86_64',
      sdk: 'iphonesimulator',
      target: 'x86_64-apple-ios12.0-simulator',
      genSnapshot: _resolveIosGenSnapshot(toolchain: toolchain, arch: 'x64'),
    );
    final simulatorLibPath = p.join(
      iosRoot.path,
      'simulator',
      'lib$moduleName.dylib',
    );
    simulatorLib = simulatorLibPath;
    Directory(p.dirname(simulatorLibPath)).createSync(recursive: true);
    await _runCommand('xcrun', <String>[
      'lipo',
      '-create',
      simArm64,
      simX64,
      '-output',
      simulatorLibPath,
    ]);
    builtSlices['simulator-arm64'] = simArm64;
    builtSlices['simulator-x86_64'] = simX64;
    builtSlices['simulator-universal'] = simulatorLibPath;
  }

  final xcframeworkPath = p.join(iosRoot.path, '$moduleName.xcframework');
  final existing = Directory(xcframeworkPath);
  if (existing.existsSync()) {
    existing.deleteSync(recursive: true);
  }

  final xcfArgs = <String>['-create-xcframework'];
  if (includeDevice) {
    xcfArgs.addAll(<String>[
      '-library',
      builtSlices['device-arm64']!,
      '-headers',
      includeDir,
    ]);
  }
  if (includeSimulator) {
    xcfArgs.addAll(<String>['-library', simulatorLib!, '-headers', includeDir]);
  }
  xcfArgs.addAll(<String>['-output', xcframeworkPath]);
  await _runCommand('xcodebuild', xcfArgs);

  return <String, Object?>{
    'xcframework': p.normalize(xcframeworkPath),
    'slices': builtSlices.map(
      (key, value) => MapEntry<String, Object?>(key, p.normalize(value)),
    ),
  };
}

String _resolveAndroidNdkHostTag(String ndkHome) {
  final prebuilt = Directory(p.join(ndkHome, 'toolchains', 'llvm', 'prebuilt'));
  if (!prebuilt.existsSync()) {
    throw ToolError('Invalid Android NDK layout: ${prebuilt.path}');
  }

  final candidates = Platform.isMacOS
      ? <String>['darwin-arm64', 'darwin-x86_64']
      : Platform.isLinux
      ? <String>['linux-x86_64']
      : Platform.isWindows
      ? <String>['windows-x86_64']
      : const <String>[];
  for (final candidate in candidates) {
    final dir = Directory(p.join(prebuilt.path, candidate));
    if (dir.existsSync()) {
      return candidate;
    }
  }

  final first =
      prebuilt
          .listSync(followLinks: false)
          .whereType<Directory>()
          .map((dir) => p.basename(dir.path))
          .toList()
        ..sort();
  if (first.isEmpty) {
    throw ToolError('No NDK prebuilt host toolchains found: ${prebuilt.path}');
  }
  return first.first;
}

String? _firstExistingFile(List<String> candidates) {
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }
  return null;
}

({String triple, int apiLevel}) _androidAbiTarget(String abi) {
  switch (abi) {
    case 'arm64-v8a':
      return (triple: 'aarch64-linux-android', apiLevel: 21);
    case 'armeabi-v7a':
      return (triple: 'armv7a-linux-androideabi', apiLevel: 19);
    case 'x86_64':
      return (triple: 'x86_64-linux-android', apiLevel: 21);
  }
  throw ToolError(
    'Unsupported Android ABI: $abi. Supported values: '
    'arm64-v8a, armeabi-v7a, x86_64.',
  );
}

String _resolveAndroidGenSnapshot({
  required Toolchain toolchain,
  required String abi,
}) {
  final envKey = switch (abi) {
    'arm64-v8a' => 'DLLART_ANDROID_GEN_SNAPSHOT_ARM64',
    'armeabi-v7a' => 'DLLART_ANDROID_GEN_SNAPSHOT_ARMV7',
    'x86_64' => 'DLLART_ANDROID_GEN_SNAPSHOT_X64',
    _ => '',
  };
  if (envKey.isNotEmpty) {
    final fromEnv = (Platform.environment[envKey] ?? '').trim();
    if (fromEnv.isNotEmpty) {
      if (!File(fromEnv).existsSync()) {
        throw ToolError('$envKey points to a missing file: $fromEnv');
      }
      return p.normalize(fromEnv);
    }
  }

  final hostArch = _hostArch();
  final hostMatches =
      (abi == 'arm64-v8a' && hostArch == 'arm64') ||
      (abi == 'x86_64' && hostArch == 'x64');
  if (hostMatches) {
    return toolchain.genSnapshot;
  }

  throw ToolError(
    'No gen_snapshot configured for Android ABI $abi. '
    'Set $envKey to a target-specific gen_snapshot binary.',
  );
}

String _resolveIosGenSnapshot({
  required Toolchain toolchain,
  required String arch,
}) {
  final envKey = arch == 'arm64'
      ? 'DLLART_IOS_GEN_SNAPSHOT_ARM64'
      : 'DLLART_IOS_GEN_SNAPSHOT_X64';
  final fromEnv = (Platform.environment[envKey] ?? '').trim();
  if (fromEnv.isNotEmpty) {
    if (!File(fromEnv).existsSync()) {
      throw ToolError('$envKey points to a missing file: $fromEnv');
    }
    return p.normalize(fromEnv);
  }

  if (arch == 'arm64' && _hostArch() == 'arm64') {
    return toolchain.genSnapshot;
  }

  throw ToolError(
    'No gen_snapshot configured for iOS arch $arch. '
    'Set $envKey to a target-specific gen_snapshot binary.',
  );
}

const List<String> _snapshotSymbolNames = <String>[
  'kDartVmSnapshotData',
  'kDartVmSnapshotInstructions',
  'kDartIsolateSnapshotData',
  'kDartIsolateSnapshotInstructions',
];

String _normalizeSnapshotSymbolName(String value) {
  var out = value;
  while (out.startsWith('_')) {
    out = out.substring(1);
  }
  return out;
}

int _snapshotLeadingUnderscoreCount(String value) {
  var i = 0;
  while (i < value.length && value.codeUnitAt(i) == 95) {
    i++;
  }
  return i;
}

String? _hostNmExecutable() {
  if (Platform.isWindows) {
    return _findExecutable(<String>[
          'llvm-nm.exe',
          'nm.exe',
          'llvm-nm',
          'nm',
        ]) ??
        _firstExistingFile(<String>[
          r'C:\Program Files\LLVM\bin\llvm-nm.exe',
          r'C:\Program Files\LLVM\bin\nm.exe',
        ]);
  }
  return _findExecutable(<String>['nm']) ??
      _firstExistingFile(<String>['/usr/bin/nm', '/usr/local/bin/nm']);
}

Future<List<String>> _snapshotSymbolDefinesForObject(String objectPath) async {
  if (!(Platform.isLinux || Platform.isWindows)) {
    return const <String>[];
  }

  final nmExecutable = _hostNmExecutable();
  if (nmExecutable == null) {
    return const <String>[];
  }

  final args = <String>['--defined-only', objectPath];
  final result = await _runCommandCapture(nmExecutable, args);
  if (result.exitCode != 0) {
    throw ToolError(
      _processFailureSummary('$nmExecutable ${args.join(' ')}', result),
    );
  }

  final symbols = <String>{};
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
    final symbol = parts.last.trim();
    if (symbol.isNotEmpty) {
      symbols.add(symbol);
    }
  }

  final resolved = <String, String>{};
  for (final symbol in symbols) {
    final normalized = _normalizeSnapshotSymbolName(symbol);
    if (!_snapshotSymbolNames.contains(normalized)) {
      continue;
    }
    final current = resolved[normalized];
    if (current == null ||
        _snapshotLeadingUnderscoreCount(symbol) <
            _snapshotLeadingUnderscoreCount(current)) {
      resolved[normalized] = symbol;
    }
  }

  final missing = _snapshotSymbolNames
      .where((symbol) => !resolved.containsKey(symbol))
      .toList(growable: false);
  if (missing.isNotEmpty) {
    throw ToolError(
      'Missing required AOT snapshot symbols in ${_displayPath(objectPath)}: '
      '${missing.join(', ')}',
    );
  }

  final defines = <String>[];
  for (final symbol in _snapshotSymbolNames) {
    final actual = resolved[symbol]!;
    if (actual != symbol) {
      defines.add('-D$symbol=$actual');
    }
  }
  return defines;
}

List<String> _requiredAbiSymbols(String moduleName) {
  final prefix = _moduleRuntimePrefix(moduleName);
  return <String>[
    '${prefix}_abi_version',
    '${prefix}_init',
    '${prefix}_call_json',
    '${prefix}_call_json_batch',
    '${prefix}_call_json_raw',
    '${prefix}_call_i64_2',
    '${prefix}_call_i64_2_index',
    '${prefix}_call_i64_4',
    '${prefix}_call_i64_4_index',
    '${prefix}_call_f64_2',
    '${prefix}_call_f64_2_index',
    '${prefix}_call_f64_4',
    '${prefix}_call_f64_4_index',
    '${prefix}_call_bytes',
    '${prefix}_call_bytes_index',
    '${prefix}_last_error_code',
    '${prefix}_last_error_json',
    '${prefix}_shutdown',
    '${prefix}_string_free',
    '${prefix}_bytes_free',
  ];
}

Future<void> _verifySymbolsWithNm({
  required String nmExecutable,
  required String libraryPath,
  required List<String> requiredSymbols,
}) async {
  final executableName = p.basename(nmExecutable).toLowerCase();
  final args =
      Platform.isMacOS && (executableName == 'nm' || executableName == 'nm.exe')
      ? <String>['-gU', libraryPath]
      : <String>['--defined-only', libraryPath];
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
    final symbol = parts.last.trim();
    if (symbol.isEmpty) {
      continue;
    }
    final normalized = symbol.startsWith('_') ? symbol.substring(1) : symbol;
    exported.add(normalized);
  }

  final missing = requiredSymbols
      .where((symbol) => !exported.contains(symbol))
      .toList(growable: false);
  if (missing.isNotEmpty) {
    throw ToolError(
      'Missing required symbols in ${_displayPath(libraryPath)}: '
      '${missing.join(', ')}',
    );
  }
}

Future<void> _commandMake(ParsedArgs args) async {
  _logLine('[make] Running doctor');
  await _commandDoctor(args);
  if (exitCode != 0) {
    _logLine('[make] Stopped: doctor found blocking issues.');
    return;
  }

  _logLine('[make] Building module');
  await _commandBuild(args);

  _logLine('[make] Printing integration guide');
  await _commandIntegrate(args);
}

Future<void> _commandPackage(ParsedArgs args) async {
  _applyLoggingFromConfig(null);
  final loaded = _loadConfig(args, allowInferred: true);
  _applyLoggingFromConfig(loaded.config);
  final force = args.hasFlag('force');
  final autoBuild = args.hasFlag('auto-build');
  final target = _resolvePackageTarget(args);
  final outputPath = loaded.resolvePath(loaded.config.output);
  final packageRoot = p.join(outputPath, 'package');

  Future<void> autoBuildTarget(String buildTarget) async {
    final options = <String, String>{'target': buildTarget};
    final explicitConfig = (args['config'] ?? '').trim();
    if (explicitConfig.isNotEmpty) {
      options['config'] = explicitConfig;
    } else if (File(loaded.configPath).existsSync()) {
      options['config'] = loaded.configPath;
    } else {
      options['name'] = loaded.config.name;
      options['source'] = loaded.config.source;
      options['output'] = loaded.config.output;
    }

    if (buildTarget == 'android') {
      options['android-abis'] =
          (args['android-abis'] ?? _defaultAndroidAbis.join(',')).trim();
    }
    if (buildTarget == 'ios') {
      options['ios-variants'] = (args['ios-variants'] ?? 'all').trim();
    }
    if (_inVerboseMode) {
      options['verbose'] = 'true';
    }
    await _commandBuild(ParsedArgs(const <String>[], options));
  }

  String buildCommandFor(String buildTarget) {
    final explicitConfig = (args['config'] ?? '').trim();
    final configPart = explicitConfig.isNotEmpty
        ? '--config=$explicitConfig '
        : File(loaded.configPath).existsSync()
        ? '--config=${loaded.configPath} '
        : '';
    final extras = <String>[];
    if (buildTarget == 'android') {
      extras.add(
        '--android-abis=${(args["android-abis"] ?? _defaultAndroidAbis.join(",")).trim()}',
      );
    }
    if (buildTarget == 'ios') {
      extras.add('--ios-variants=${(args["ios-variants"] ?? "all").trim()}');
    }
    return 'dllart build ${configPart}--target=$buildTarget ${extras.join(' ')}'
        .trim();
  }

  ({
    String includeHeader,
    String manifestPath,
    Map<String, Object?> manifest,
    String? runtimeBinaryPath,
    String? runtimeSidecarPath,
    bool hostRuntimeExists,
    bool hostSidecarExists,
    String hostLibraryPath,
    bool hostLibraryExists,
    Map<String, String> androidAbiLibraries,
    String? iosXcframeworkPath,
    bool iosXcframeworkExists,
  })
  readState() {
    final includeHeader = p.join(
      outputPath,
      'include',
      '${loaded.config.name}_api.h',
    );
    final manifestPath = p.join(outputPath, 'artifact.json');
    final manifest = _readArtifactManifestMap(manifestPath);
    final runtimeBinaryPath = _manifestRuntimeBinaryPath(manifest);
    final runtimeSidecarPath = _manifestRuntimeSidecarPath(manifest);
    final hostRuntimeExists =
        runtimeBinaryPath != null && File(runtimeBinaryPath).existsSync();
    final hostSidecarExists =
        runtimeSidecarPath != null && File(runtimeSidecarPath).existsSync();
    final hostLibraryPath =
        _libraryPathFromManifest(manifestPath) ??
        _outputLibraryPath(p.join(outputPath, 'lib'), loaded.config.name);
    final hostLibraryExists = File(hostLibraryPath).existsSync();
    final androidAbiLibraries = _manifestAndroidAbiLibraries(manifest);
    final iosXcframeworkPath = _manifestIosXcframeworkPath(manifest);
    final iosXcframeworkExists =
        iosXcframeworkPath != null &&
        Directory(iosXcframeworkPath).existsSync();
    return (
      includeHeader: includeHeader,
      manifestPath: manifestPath,
      manifest: manifest,
      runtimeBinaryPath: runtimeBinaryPath,
      runtimeSidecarPath: runtimeSidecarPath,
      hostRuntimeExists: hostRuntimeExists,
      hostSidecarExists: hostSidecarExists,
      hostLibraryPath: hostLibraryPath,
      hostLibraryExists: hostLibraryExists,
      androidAbiLibraries: androidAbiLibraries,
      iosXcframeworkPath: iosXcframeworkPath,
      iosXcframeworkExists: iosXcframeworkExists,
    );
  }

  List<({String buildTarget, String detail, String command})> preflightIssues(
    ({
      String includeHeader,
      String manifestPath,
      Map<String, Object?> manifest,
      String? runtimeBinaryPath,
      String? runtimeSidecarPath,
      bool hostRuntimeExists,
      bool hostSidecarExists,
      String hostLibraryPath,
      bool hostLibraryExists,
      Map<String, String> androidAbiLibraries,
      String? iosXcframeworkPath,
      bool iosXcframeworkExists,
    })
    state,
  ) {
    final issues = <({String buildTarget, String detail, String command})>[];
    final needsAndroid =
        target == 'android' || target == 'all' || target == 'flutter';
    final needsIos = target == 'ios' || target == 'all' || target == 'flutter';
    final needsHostLibrary =
        target == 'python' ||
        target == 'csharp' ||
        target == 'all' ||
        target == 'fuchsia';

    if (!Directory(outputPath).existsSync()) {
      final buildTarget = needsAndroid
          ? 'android'
          : needsIos
          ? 'ios'
          : 'host';
      issues.add((
        buildTarget: buildTarget,
        detail: 'Artifact directory is missing: $outputPath',
        command: buildCommandFor(buildTarget),
      ));
    }
    if (!File(state.includeHeader).existsSync()) {
      issues.add((
        buildTarget: 'host',
        detail: 'Module API header is missing: ${state.includeHeader}',
        command: buildCommandFor('host'),
      ));
    }
    if (state.manifest.isEmpty) {
      issues.add((
        buildTarget: 'host',
        detail:
            'Artifact manifest is missing or invalid: ${state.manifestPath}',
        command: buildCommandFor('host'),
      ));
    }
    if (needsAndroid && state.androidAbiLibraries.isEmpty) {
      issues.add((
        buildTarget: 'android',
        detail: 'Android artifacts are missing in artifact.json.',
        command: buildCommandFor('android'),
      ));
    }
    if (needsIos && !state.iosXcframeworkExists) {
      issues.add((
        buildTarget: 'ios',
        detail: 'iOS xcframework is missing in artifact.json.',
        command: buildCommandFor('ios'),
      ));
    }
    if (needsHostLibrary && !state.hostLibraryExists) {
      issues.add((
        buildTarget: 'host',
        detail: 'Host library artifact is missing: ${state.hostLibraryPath}',
        command: buildCommandFor('host'),
      ));
    }
    return issues;
  }

  String renderPreflightMessage(
    List<({String buildTarget, String detail, String command})> issues, {
    required bool afterAutoBuild,
  }) {
    final lines = <String>[
      'Package preflight failed for target `$target`.',
      '',
      'Missing prerequisites:',
    ];
    for (final issue in issues) {
      lines.add('- ${issue.detail}');
      lines.add('  Next: ${issue.command}');
    }
    if (!afterAutoBuild) {
      lines.add('');
      lines.add('Tip: re-run with `--auto-build` to build missing targets.');
    }
    return lines.join('\n');
  }

  List<({String buildTarget, String detail, String command})> autoBuildBlockers(
    Set<String> requiredTargets,
  ) {
    final blockers = <({String buildTarget, String detail, String command})>[];
    final seen = <String>{};

    void add(String buildTarget, String detail) {
      final key = '$buildTarget|$detail';
      if (!seen.add(key)) {
        return;
      }
      blockers.add((
        buildTarget: buildTarget,
        detail: detail,
        command: buildCommandFor(buildTarget),
      ));
    }

    Toolchain? toolchain;
    try {
      toolchain = _resolveToolchain();
    } on ToolError catch (error) {
      final fallbackTarget = requiredTargets.contains('host')
          ? 'host'
          : requiredTargets.contains('android')
          ? 'android'
          : requiredTargets.contains('ios')
          ? 'ios'
          : 'host';
      add(fallbackTarget, error.message);
    }

    if (requiredTargets.contains('android')) {
      final ndkHome = (Platform.environment['ANDROID_NDK_HOME'] ?? '').trim();
      final androidAbis = _resolveAndroidAbis(args);
      if (ndkHome.isEmpty) {
        add(
          'android',
          'ANDROID_NDK_HOME is required for --target=android. '
              'Export ANDROID_NDK_HOME to your NDK root.',
        );
      } else if (!Directory(ndkHome).existsSync()) {
        add(
          'android',
          'ANDROID_NDK_HOME points to missing directory: $ndkHome',
        );
      } else {
        try {
          final hostTag = _resolveAndroidNdkHostTag(ndkHome);
          final llvmBin = p.join(
            ndkHome,
            'toolchains',
            'llvm',
            'prebuilt',
            hostTag,
            'bin',
          );
          if (!Directory(llvmBin).existsSync()) {
            add('android', 'Android NDK LLVM toolchain not found: $llvmBin');
          } else {
            final nmPath = _firstExistingFile(<String>[
              p.join(llvmBin, Platform.isWindows ? 'llvm-nm.exe' : 'llvm-nm'),
            ]);
            if (nmPath == null) {
              add(
                'android',
                'llvm-nm not found in Android NDK toolchain: $llvmBin',
              );
            }
            for (final abi in androidAbis) {
              final targetSpec = _androidAbiTarget(abi);
              final clangPath = _firstExistingFile(<String>[
                p.join(
                  llvmBin,
                  '${targetSpec.triple}${targetSpec.apiLevel}-clang${Platform.isWindows ? '.cmd' : ''}',
                ),
                p.join(
                  llvmBin,
                  '${targetSpec.triple}${targetSpec.apiLevel}-clang${Platform.isWindows ? '.exe' : ''}',
                ),
              ]);
              if (clangPath == null) {
                add(
                  'android',
                  'Android clang for $abi was not found under $llvmBin. '
                      'Expected ${targetSpec.triple}${targetSpec.apiLevel}-clang.',
                );
              }
            }
          }
        } on ToolError catch (error) {
          add('android', error.message);
        }
      }

      if (toolchain != null) {
        for (final abi in androidAbis) {
          try {
            _resolveAndroidGenSnapshot(toolchain: toolchain, abi: abi);
          } on ToolError catch (error) {
            add('android', error.message);
          }
        }
      }
    }

    if (requiredTargets.contains('ios')) {
      final iosVariants = _resolveIosVariants(args);
      if (!Platform.isMacOS) {
        add(
          'ios',
          '--target=ios is supported only on macOS (requires xcrun/xcodebuild).',
        );
      } else {
        final xcrun = _findExecutable(<String>['xcrun']);
        final xcodebuild = _findExecutable(<String>['xcodebuild']);
        if (xcrun == null || xcodebuild == null) {
          add('ios', 'xcrun/xcodebuild not found in PATH');
        }
      }

      if (toolchain != null && Platform.isMacOS) {
        final includeDevice = iosVariants == 'all' || iosVariants == 'device';
        final includeSimulator =
            iosVariants == 'all' || iosVariants == 'simulator';
        if (includeDevice) {
          try {
            _resolveIosGenSnapshot(toolchain: toolchain, arch: 'arm64');
          } on ToolError catch (error) {
            add('ios', error.message);
          }
        }
        if (includeSimulator) {
          for (final simulatorArch in <String>['arm64', 'x64']) {
            try {
              _resolveIosGenSnapshot(toolchain: toolchain, arch: simulatorArch);
            } on ToolError catch (error) {
              add('ios', error.message);
            }
          }
        }
      }
    }

    return blockers;
  }

  String renderAutoBuildBlockersMessage(
    List<({String buildTarget, String detail, String command})> blockers,
  ) {
    final lines = <String>[
      'Package auto-build preflight failed for target `$target`.',
      '',
      'Blocking environment/toolchain issues:',
    ];
    for (final blocker in blockers) {
      lines.add('- [${blocker.buildTarget}] ${blocker.detail}');
      lines.add('  Next: ${blocker.command}');
    }
    return lines.join('\n');
  }

  var state = readState();
  var issues = preflightIssues(state);
  if (issues.isNotEmpty && autoBuild) {
    final order = <String>['host', 'android', 'ios'];
    final requiredTargets = <String>{
      for (final issue in issues) issue.buildTarget,
    };
    final blockers = autoBuildBlockers(requiredTargets);
    if (blockers.isNotEmpty) {
      throw ToolError(renderAutoBuildBlockersMessage(blockers));
    }
    for (final buildTarget in order) {
      if (!requiredTargets.contains(buildTarget)) {
        continue;
      }
      if (!_inJsonMode) {
        stdout.writeln('Auto-build: ${buildCommandFor(buildTarget)}');
      }
      await autoBuildTarget(buildTarget);
    }
    state = readState();
    issues = preflightIssues(state);
  }
  if (issues.isNotEmpty) {
    throw ToolError(renderPreflightMessage(issues, afterAutoBuild: autoBuild));
  }

  final runtimeBinaryPath = state.runtimeBinaryPath;
  final runtimeSidecarPath = state.runtimeSidecarPath;
  final runtimeFileName = runtimeBinaryPath == null
      ? null
      : p.basename(runtimeBinaryPath);
  final hostRuntimeExists = state.hostRuntimeExists;
  final hostSidecarExists = state.hostSidecarExists;
  final hostLibraryPath = state.hostLibraryPath;
  final androidAbiLibraries = state.androidAbiLibraries;
  final iosXcframeworkPath = state.iosXcframeworkPath;

  final includeHeader = state.includeHeader;
  final manifestPath = state.manifestPath;
  Directory(packageRoot).createSync(recursive: true);

  final generated = <String>[];
  if (hostRuntimeExists || hostSidecarExists) {
    final packageRuntimeDir = p.join(packageRoot, 'runtime');
    _prepareDirectory(packageRuntimeDir, force: force);
    if (hostRuntimeExists) {
      final runtimeSourcePath = runtimeBinaryPath!;
      final runtimeName = runtimeFileName!;
      await File(runtimeSourcePath).copy(p.join(packageRuntimeDir, runtimeName));
      if (!Platform.isWindows) {
        Process.runSync('chmod', <String>[
          '+x',
          p.join(packageRuntimeDir, runtimeName),
        ]);
      }
    }
    if (hostSidecarExists) {
      final sidecarSourcePath = runtimeSidecarPath!;
      final sidecarName = p.basename(sidecarSourcePath);
      await File(sidecarSourcePath).copy(p.join(packageRuntimeDir, sidecarName));
      if (!Platform.isWindows) {
        Process.runSync('chmod', <String>[
          '+x',
          p.join(packageRuntimeDir, sidecarName),
        ]);
      }
    }
    generated.add(packageRuntimeDir);
  }

  if (target == 'android' || target == 'all') {
    final androidDir = p.join(packageRoot, 'android');
    _prepareDirectory(androidDir, force: force);
    await _generateAndroidPackage(
      moduleName: loaded.config.name,
      includeHeader: includeHeader,
      androidDir: androidDir,
      abiLibraries: androidAbiLibraries,
    );
    generated.add(androidDir);
  }
  if (target == 'ios' || target == 'all') {
    final iosDir = p.join(packageRoot, 'ios');
    _prepareDirectory(iosDir, force: force);
    await _generateIosPackage(
      moduleName: loaded.config.name,
      includeHeader: includeHeader,
      iosDir: iosDir,
      xcframeworkPath: iosXcframeworkPath!,
    );
    generated.add(iosDir);
  }
  if (target == 'fuchsia' || target == 'all') {
    final fuchsiaDir = p.join(packageRoot, 'fuchsia');
    _prepareDirectory(fuchsiaDir, force: force);
    await _generateFuchsiaPackage(
      moduleName: loaded.config.name,
      includeHeader: includeHeader,
      fuchsiaDir: fuchsiaDir,
    );
    generated.add(fuchsiaDir);
  }
  if (target == 'flutter' || target == 'all') {
    final flutterDir = p.join(packageRoot, 'flutter_plugin');
    _prepareDirectory(flutterDir, force: force);
    await _generateFlutterPluginPackage(
      moduleName: loaded.config.name,
      includeHeader: includeHeader,
      artifactManifestPath: manifestPath,
      runtimeBinaryPath: hostRuntimeExists ? runtimeBinaryPath : null,
      runtimeSidecarPath: hostSidecarExists ? runtimeSidecarPath : null,
      androidAbiLibraries: androidAbiLibraries,
      iosXcframeworkPath: iosXcframeworkPath,
      flutterDir: flutterDir,
    );
    generated.add(flutterDir);
  }
  if (target == 'python' || target == 'all') {
    final pythonDir = p.join(packageRoot, 'python');
    _prepareDirectory(pythonDir, force: force);
    await _generatePythonPackage(
      moduleName: loaded.config.name,
      includeHeader: includeHeader,
      artifactManifestPath: manifestPath,
      hostLibraryPath: hostLibraryPath,
      runtimeBinaryPath: hostRuntimeExists ? runtimeBinaryPath : null,
      runtimeSidecarPath: hostSidecarExists ? runtimeSidecarPath : null,
      pythonDir: pythonDir,
    );
    generated.add(pythonDir);
  }
  if (target == 'csharp' || target == 'all') {
    final csharpDir = p.join(packageRoot, 'csharp');
    _prepareDirectory(csharpDir, force: force);
    await _generateCSharpPackage(
      moduleName: loaded.config.name,
      includeHeader: includeHeader,
      artifactManifestPath: manifestPath,
      hostLibraryPath: hostLibraryPath,
      runtimeBinaryPath: hostRuntimeExists ? runtimeBinaryPath : null,
      runtimeSidecarPath: hostSidecarExists ? runtimeSidecarPath : null,
      csharpDir: csharpDir,
    );
    generated.add(csharpDir);
  }

  stdout.writeln('Generated package scaffold:');
  for (final path in generated) {
    stdout.writeln('  - ${_displayPath(path)}');
  }
}

Future<void> _commandVerify(ParsedArgs args) async {
  _applyLoggingFromConfig(null);
  final loaded = _loadConfig(args, allowInferred: true);
  _applyLoggingFromConfig(loaded.config);
  final jsonMode = _isJsonMode(args);
  final target = _resolveVerifyTarget(args);
  final outputPath = loaded.resolvePath(loaded.config.output);
  final outputDir = Directory(outputPath);
  final manifestPath = p.join(outputPath, 'artifact.json');
  final manifest = _readArtifactManifestMap(manifestPath);
  final hostLibraryPath =
      _libraryPathFromManifest(manifestPath) ??
      _outputLibraryPath(p.join(outputPath, 'lib'), loaded.config.name);

  final items = <Map<String, String>>[];
  void add(String status, String title, String detail) {
    items.add(<String, String>{
      'status': status,
      'title': title,
      'detail': detail,
    });
  }

  void verifyFiles({
    required String scope,
    required String rootPath,
    required List<String> requiredRelativePaths,
  }) {
    final root = Directory(rootPath);
    if (!root.existsSync()) {
      add('fail', '$scope root', 'Missing directory: $rootPath');
      return;
    }
    for (final relative in requiredRelativePaths) {
      final full = p.join(rootPath, relative);
      if (!File(full).existsSync()) {
        add('fail', '$scope file', 'Missing file: $full');
      } else {
        add('ok', '$scope file', _displayPath(full));
      }
    }
  }

  if (!outputDir.existsSync()) {
    add('fail', 'Output directory', 'Missing: $outputPath');
  } else {
    add('ok', 'Output directory', _displayPath(outputPath));
  }

  final runC = target == 'c' || target == 'all';
  final runPython = target == 'python' || target == 'all';
  final runCSharp = target == 'csharp' || target == 'all';

  if (runC) {
    final header = p.join(outputPath, 'include', '${loaded.config.name}_api.h');
    if (File(header).existsSync()) {
      add('ok', 'C header', _displayPath(header));
    } else {
      add(
        'fail',
        'C header',
        'Missing $header. Run `dllart build --target=host`.',
      );
    }
    if (File(hostLibraryPath).existsSync()) {
      add('ok', 'C library', _displayPath(hostLibraryPath));
    } else {
      add(
        'fail',
        'C library',
        'Missing $hostLibraryPath. Run `dllart build --target=host`.',
      );
    }
    if (manifest.isEmpty) {
      add('fail', 'C manifest', 'Missing or invalid $manifestPath');
    } else {
      add('ok', 'C manifest', _displayPath(manifestPath));
    }
  }

  if (runPython) {
    final pythonDir = p.join(outputPath, 'package', 'python');
    verifyFiles(
      scope: 'Python',
      rootPath: pythonDir,
      requiredRelativePaths: <String>[
        'bindings.py',
        'example.py',
        'artifact.json',
      ],
    );

    final bindingsPath = p.join(pythonDir, 'bindings.py');
    if (File(bindingsPath).existsSync()) {
      final bindings = File(bindingsPath).readAsStringSync();
      final requiredSymbols = <String>[
        'def call_json_batch',
        'def call_json_raw',
        'def call_i64_2_index',
        'def call_i64_4_index',
        'def call_f64_2_index',
        'def call_f64_4_index',
        'def call_bytes',
        'def call_bytes_index',
      ];
      final missing = requiredSymbols
          .where((token) => !bindings.contains(token))
          .toList(growable: false);
      if (missing.isEmpty) {
        add('ok', 'Python wrapper coverage', 'Full typed/json/bytes coverage');
      } else {
        add(
          'fail',
          'Python wrapper coverage',
          'Missing methods: ${missing.join(', ')}',
        );
      }
    }
  }

  if (runCSharp) {
    final csharpDir = p.join(outputPath, 'package', 'csharp');
    verifyFiles(
      scope: 'C#',
      rootPath: csharpDir,
      requiredRelativePaths: <String>[
        'DllartClient.cs',
        'Program.cs',
        'DllartScaffold.csproj',
        'artifact.json',
      ],
    );
    final clientPath = p.join(csharpDir, 'DllartClient.cs');
    if (File(clientPath).existsSync()) {
      final source = File(clientPath).readAsStringSync();
      final hasAnsi =
          source.contains('StringToHGlobalAnsi') ||
          source.contains('PtrToStringAnsi');
      if (hasAnsi) {
        add('fail', 'C# UTF-8 marshaling', 'ANSI marshaling API still present');
      } else if (source.contains('System.Text.Encoding.UTF8') ||
          source.contains('Encoding.UTF8')) {
        add('ok', 'C# UTF-8 marshaling', 'UTF-8 marshaling detected');
      } else {
        add(
          'warn',
          'C# UTF-8 marshaling',
          'Could not confirm UTF-8 marshaling helpers.',
        );
      }
      final requiredMethods = <String>[
        'CallJsonBatch',
        'CallJsonRaw',
        'CallI64_2Index',
        'CallI64_4Index',
        'CallF64_2Index',
        'CallF64_4Index',
        'CallBytes',
        'CallBytesIndex',
      ];
      final missingMethods = requiredMethods
          .where((method) => !source.contains(method))
          .toList(growable: false);
      if (missingMethods.isEmpty) {
        add('ok', 'C# wrapper coverage', 'Full typed/json/bytes coverage');
      } else {
        add(
          'fail',
          'C# wrapper coverage',
          'Missing methods: ${missingMethods.join(', ')}',
        );
      }
    }
  }

  final failCount = items.where((item) => item['status'] == 'fail').length;
  final warnCount = items.where((item) => item['status'] == 'warn').length;
  final okCount = items.where((item) => item['status'] == 'ok').length;
  final status = failCount > 0
      ? 'fail'
      : warnCount > 0
      ? 'warn'
      : 'ok';

  if (jsonMode) {
    _writeJsonCommandResult(
      'verify',
      ok: failCount == 0,
      status: status,
      data: <String, Object?>{
        'module': loaded.config.name,
        'target': target,
        'output_root': _displayPath(outputPath),
        'summary': <String, int>{
          'ok': okCount,
          'warnings': warnCount,
          'failures': failCount,
        },
        'items': items,
      },
      exitCode: failCount > 0 ? 1 : 0,
    );
  } else {
    stdout.writeln('DLLART Verify Report');
    stdout.writeln('Module: ${loaded.config.name}');
    stdout.writeln('Target: $target');
    for (final item in items) {
      final label = item['status']!.toUpperCase();
      stdout.writeln('[$label] ${item['title']}: ${item['detail']}');
    }
    stdout.writeln(
      'Summary: $okCount ok, $warnCount warnings, $failCount failures',
    );
  }

  if (failCount > 0) {
    exitCode = 1;
    if (!jsonMode) {
      stderr.writeln('Verify found blocking issues. Fix FAIL items first.');
    }
  }
}

String _resolveVerifyTarget(ParsedArgs args) {
  final value = (args['target'] ?? 'all').trim().toLowerCase();
  if (value == 'all' ||
      value == 'c' ||
      value == 'python' ||
      value == 'csharp') {
    return value;
  }
  throw ToolError(
    'Unsupported verify target: $value. Use c, python, csharp, or all.',
  );
}

String _resolvePackageTarget(ParsedArgs args) {
  String raw = 'all';
  if (args['target'] != null && args['target']!.trim().isNotEmpty) {
    raw = args['target']!.trim();
  } else if (args.positional.isNotEmpty) {
    raw = args.positional.first.trim();
  }

  final normalized = raw.toLowerCase();
  if (normalized == 'android' ||
      normalized == 'ios' ||
      normalized == 'fuchsia' ||
      normalized == 'flutter' ||
      normalized == 'python' ||
      normalized == 'csharp' ||
      normalized == 'all') {
    return normalized;
  }
  throw ToolError(
    'Unsupported package target: $raw. Use android, ios, fuchsia, flutter, python, csharp, or all.',
  );
}

void _prepareDirectory(String path, {required bool force}) {
  final dir = Directory(path);
  if (dir.existsSync()) {
    if (force) {
      dir.deleteSync(recursive: true);
      dir.createSync(recursive: true);
    }
    return;
  }
  dir.createSync(recursive: true);
}

Future<void> _generateAndroidPackage({
  required String moduleName,
  required String includeHeader,
  required String androidDir,
  required Map<String, String> abiLibraries,
}) async {
  final includeDir = p.join(androidDir, 'include');
  final jniDir = p.join(androidDir, 'jniLibs');

  Directory(includeDir).createSync(recursive: true);
  Directory(jniDir).createSync(recursive: true);
  for (final entry in abiLibraries.entries) {
    final abi = entry.key;
    final sourceLibrary = entry.value;
    if (!File(sourceLibrary).existsSync()) {
      throw ToolError('Android artifact for $abi is missing: $sourceLibrary');
    }
    final dir = Directory(p.join(jniDir, abi));
    dir.createSync(recursive: true);
    await File(sourceLibrary).copy(p.join(dir.path, 'lib$moduleName.so'));
  }

  await File(includeHeader).copy(p.join(includeDir, p.basename(includeHeader)));

  final cmakePath = p.join(androidDir, 'CMakeLists.txt');
  final gradlePath = p.join(androidDir, 'build.gradle.snippet');
  final readmePath = p.join(androidDir, 'README.md');

  await File(
    cmakePath,
  ).writeAsString(_generateAndroidCMakeTemplate(moduleName: moduleName));
  await File(
    gradlePath,
  ).writeAsString(_generateAndroidGradleSnippet(moduleName: moduleName));
  await File(
    readmePath,
  ).writeAsString(_generateAndroidPackageReadme(moduleName: moduleName));
}

Future<void> _generateIosPackage({
  required String moduleName,
  required String includeHeader,
  required String iosDir,
  required String xcframeworkPath,
}) async {
  final headersDir = p.join(iosDir, 'Headers');
  final frameworksDir = p.join(iosDir, 'Frameworks');
  Directory(headersDir).createSync(recursive: true);
  Directory(frameworksDir).createSync(recursive: true);
  final xcframeworkName = p.basename(xcframeworkPath);
  final destinationXcframework = p.join(frameworksDir, xcframeworkName);
  await _copyDirectoryRecursive(
    sourceDirPath: xcframeworkPath,
    destinationDirPath: destinationXcframework,
  );

  final headerName = p.basename(includeHeader);
  await File(includeHeader).copy(p.join(headersDir, headerName));

  final moduleMapPath = p.join(iosDir, 'module.modulemap');
  final podspecPath = p.join(iosDir, '${moduleName}_dllart.podspec');
  final readmePath = p.join(iosDir, 'README.md');

  await File(moduleMapPath).writeAsString(
    _generateIosModuleMap(moduleName: moduleName, headerName: headerName),
  );
  await File(
    podspecPath,
  ).writeAsString(_generateIosPodspec(moduleName: moduleName));
  await File(
    readmePath,
  ).writeAsString(_generateIosPackageReadme(moduleName: moduleName));
}

Future<void> _generateFuchsiaPackage({
  required String moduleName,
  required String includeHeader,
  required String fuchsiaDir,
}) async {
  final includeDir = p.join(fuchsiaDir, 'include');
  final libDir = p.join(fuchsiaDir, 'lib');
  Directory(includeDir).createSync(recursive: true);
  Directory(libDir).createSync(recursive: true);
  File(p.join(libDir, '.gitkeep')).writeAsStringSync('');

  await File(includeHeader).copy(p.join(includeDir, p.basename(includeHeader)));

  final gnPath = p.join(fuchsiaDir, 'BUILD.gn.snippet');
  final readmePath = p.join(fuchsiaDir, 'README.md');
  await File(
    gnPath,
  ).writeAsString(_generateFuchsiaBuildGnSnippet(moduleName: moduleName));
  await File(
    readmePath,
  ).writeAsString(_generateFuchsiaPackageReadme(moduleName: moduleName));
}

Future<void> _generateFlutterPluginPackage({
  required String moduleName,
  required String includeHeader,
  required String artifactManifestPath,
  required String? runtimeBinaryPath,
  required String? runtimeSidecarPath,
  required Map<String, String> androidAbiLibraries,
  required String? iosXcframeworkPath,
  required String flutterDir,
}) async {
  final packageName =
      '${_sanitizeForC(moduleName).toLowerCase()}_dllart_plugin';
  final className = '${_upperCamelCase(moduleName)}Dllart';
  final runtimePrefix = _moduleRuntimePrefix(moduleName);
  final methodIdConstants = _generateFlutterMethodIdConstants(
    _readArtifactManifestMap(artifactManifestPath),
  );

  final libDir = p.join(flutterDir, 'lib');
  final androidJniDir = p.join(flutterDir, 'android', 'src', 'main', 'jniLibs');
  final iosHeadersDir = p.join(flutterDir, 'ios', 'Headers');
  final iosFrameworksDir = p.join(flutterDir, 'ios', 'Frameworks');
  final nativeIncludeDir = p.join(flutterDir, 'native', 'include');
  final nativeRuntimeDir = p.join(flutterDir, 'native', 'runtime');

  Directory(libDir).createSync(recursive: true);
  Directory(androidJniDir).createSync(recursive: true);
  Directory(iosHeadersDir).createSync(recursive: true);
  Directory(iosFrameworksDir).createSync(recursive: true);
  Directory(nativeIncludeDir).createSync(recursive: true);
  Directory(nativeRuntimeDir).createSync(recursive: true);

  for (final entry in androidAbiLibraries.entries) {
    final abi = entry.key;
    final sourceLibrary = entry.value;
    if (!File(sourceLibrary).existsSync()) {
      throw ToolError('Android artifact for $abi is missing: $sourceLibrary');
    }
    final dir = Directory(p.join(androidJniDir, abi));
    dir.createSync(recursive: true);
    await File(sourceLibrary).copy(p.join(dir.path, 'lib$moduleName.so'));
  }
  if (iosXcframeworkPath != null && iosXcframeworkPath.trim().isNotEmpty) {
    if (!Directory(iosXcframeworkPath).existsSync()) {
      throw ToolError('iOS xcframework is missing: $iosXcframeworkPath');
    }
    await _copyDirectoryRecursive(
      sourceDirPath: iosXcframeworkPath,
      destinationDirPath: p.join(
        iosFrameworksDir,
        p.basename(iosXcframeworkPath),
      ),
    );
  }

  final headerName = p.basename(includeHeader);
  await File(includeHeader).copy(p.join(nativeIncludeDir, headerName));
  await File(includeHeader).copy(p.join(iosHeadersDir, headerName));
  await File(artifactManifestPath).copy(p.join(flutterDir, 'artifact.json'));
  final runtimeFileName = runtimeBinaryPath == null
      ? _runtimeExecutableNameForHost()
      : p.basename(runtimeBinaryPath);
  if (runtimeBinaryPath != null) {
    await File(
      runtimeBinaryPath,
    ).copy(p.join(nativeRuntimeDir, runtimeFileName));
    if (!Platform.isWindows) {
      Process.runSync('chmod', <String>[
        '+x',
        p.join(nativeRuntimeDir, runtimeFileName),
      ]);
    }
  }
  if (runtimeSidecarPath != null) {
    final sidecarFileName = p.basename(runtimeSidecarPath);
    await File(
      runtimeSidecarPath,
    ).copy(p.join(nativeRuntimeDir, sidecarFileName));
    if (!Platform.isWindows) {
      Process.runSync('chmod', <String>[
        '+x',
        p.join(nativeRuntimeDir, sidecarFileName),
      ]);
    }
  }

  await File(p.join(flutterDir, 'pubspec.yaml')).writeAsString(
    _generateFlutterPluginPubspec(
      packageName: packageName,
      moduleName: moduleName,
    ),
  );
  await File(p.join(flutterDir, 'README.md')).writeAsString(
    _generateFlutterPluginReadme(
      packageName: packageName,
      moduleName: moduleName,
      className: className,
      runtimeFileName: runtimeFileName,
    ),
  );
  await File(p.join(flutterDir, '.gitignore')).writeAsString('''
.dart_tool/
build/
''');
  await File(
    p.join(flutterDir, 'lib', '$packageName.dart'),
  ).writeAsString(_generateFlutterPluginLibrary(moduleName: moduleName));
  await File(p.join(flutterDir, 'lib', '${moduleName}_ffi.dart')).writeAsString(
    _generateFlutterPluginBindings(
      moduleName: moduleName,
      runtimePrefix: runtimePrefix,
      className: className,
      methodIdConstants: methodIdConstants,
    ),
  );
  await File(
    p.join(flutterDir, 'android', 'README.md'),
  ).writeAsString(_generateFlutterAndroidReadme(moduleName: moduleName));
  await File(
    p.join(flutterDir, 'ios', 'README.md'),
  ).writeAsString(_generateFlutterIosReadme(moduleName: moduleName));
}

Future<void> _generatePythonPackage({
  required String moduleName,
  required String includeHeader,
  required String artifactManifestPath,
  required String hostLibraryPath,
  required String? runtimeBinaryPath,
  required String? runtimeSidecarPath,
  required String pythonDir,
}) async {
  final runtimePrefix = _moduleRuntimePrefix(moduleName);
  final manifest = _readArtifactManifestMap(artifactManifestPath);
  final nativeDir = p.join(pythonDir, 'native');
  final runtimeDir = p.join(pythonDir, 'runtime');
  Directory(nativeDir).createSync(recursive: true);
  Directory(runtimeDir).createSync(recursive: true);

  final libraryFileName = p.basename(hostLibraryPath);
  await File(hostLibraryPath).copy(p.join(nativeDir, libraryFileName));
  await File(includeHeader).copy(p.join(pythonDir, p.basename(includeHeader)));
  await File(artifactManifestPath).copy(p.join(pythonDir, 'artifact.json'));

  String? runtimeFileName;
  if (runtimeBinaryPath != null) {
    runtimeFileName = p.basename(runtimeBinaryPath);
    final destination = p.join(runtimeDir, runtimeFileName);
    await File(runtimeBinaryPath).copy(destination);
    if (!Platform.isWindows) {
      Process.runSync('chmod', <String>['+x', destination]);
    }
  }
  if (runtimeSidecarPath != null) {
    final sidecarDestination = p.join(runtimeDir, p.basename(runtimeSidecarPath));
    await File(runtimeSidecarPath).copy(sidecarDestination);
    if (!Platform.isWindows) {
      Process.runSync('chmod', <String>['+x', sidecarDestination]);
    }
  }

  await File(p.join(pythonDir, 'bindings.py')).writeAsString(
    _generatePythonBindings(
      moduleName: moduleName,
      runtimePrefix: runtimePrefix,
      libraryFileName: libraryFileName,
      runtimeFileName: runtimeFileName,
      methodIdConstants: _generatePythonMethodIdConstants(manifest),
    ),
  );
  await File(
    p.join(pythonDir, 'example.py'),
  ).writeAsString(_generatePythonExample(moduleName: moduleName));
  await File(p.join(pythonDir, 'README.md')).writeAsString(
    _generatePythonPackageReadme(
      moduleName: moduleName,
      libraryFileName: libraryFileName,
      runtimeFileName: runtimeFileName,
    ),
  );
}

Future<void> _generateCSharpPackage({
  required String moduleName,
  required String includeHeader,
  required String artifactManifestPath,
  required String hostLibraryPath,
  required String? runtimeBinaryPath,
  required String? runtimeSidecarPath,
  required String csharpDir,
}) async {
  final runtimePrefix = _moduleRuntimePrefix(moduleName);
  final manifest = _readArtifactManifestMap(artifactManifestPath);
  final nativeDir = p.join(csharpDir, 'native');
  final runtimeDir = p.join(csharpDir, 'runtime');
  Directory(nativeDir).createSync(recursive: true);
  Directory(runtimeDir).createSync(recursive: true);

  final libraryFileName = p.basename(hostLibraryPath);
  await File(hostLibraryPath).copy(p.join(nativeDir, libraryFileName));
  await File(includeHeader).copy(p.join(csharpDir, p.basename(includeHeader)));
  await File(artifactManifestPath).copy(p.join(csharpDir, 'artifact.json'));

  String? runtimeFileName;
  if (runtimeBinaryPath != null) {
    runtimeFileName = p.basename(runtimeBinaryPath);
    final destination = p.join(runtimeDir, runtimeFileName);
    await File(runtimeBinaryPath).copy(destination);
    if (!Platform.isWindows) {
      Process.runSync('chmod', <String>['+x', destination]);
    }
  }
  if (runtimeSidecarPath != null) {
    final sidecarDestination = p.join(runtimeDir, p.basename(runtimeSidecarPath));
    await File(runtimeSidecarPath).copy(sidecarDestination);
    if (!Platform.isWindows) {
      Process.runSync('chmod', <String>['+x', sidecarDestination]);
    }
  }

  await File(p.join(csharpDir, 'DllartClient.cs')).writeAsString(
    _generateCSharpBindings(
      moduleName: moduleName,
      runtimePrefix: runtimePrefix,
      libraryFileName: libraryFileName,
      runtimeFileName: runtimeFileName,
      methodIdConstants: _generateCSharpMethodIdConstants(manifest),
    ),
  );
  await File(
    p.join(csharpDir, 'Program.cs'),
  ).writeAsString(_generateCSharpExample(moduleName: moduleName));
  await File(
    p.join(csharpDir, 'DllartScaffold.csproj'),
  ).writeAsString(_generateCSharpProject(moduleName: moduleName));
  await File(
    p.join(csharpDir, 'README.md'),
  ).writeAsString(_generateCSharpPackageReadme(moduleName: moduleName));
}

Map<String, Object?> _readArtifactManifestMap(String artifactManifestPath) {
  final file = File(artifactManifestPath);
  if (!file.existsSync()) {
    return <String, Object?>{};
  }

  try {
    final raw = jsonDecode(file.readAsStringSync());
    if (raw is Map<String, dynamic>) {
      return raw.cast<String, Object?>();
    }
    if (raw is Map) {
      final out = <String, Object?>{};
      for (final entry in raw.entries) {
        final key = entry.key;
        if (key is String) {
          out[key] = entry.value;
        }
      }
      return out;
    }
  } catch (_) {}
  return <String, Object?>{};
}

Map<String, Object?> _asStringObjectMap(Object? raw) {
  if (raw is Map<String, Object?>) {
    return raw;
  }
  if (raw is Map<String, dynamic>) {
    return raw.cast<String, Object?>();
  }
  if (raw is! Map) {
    return <String, Object?>{};
  }

  final out = <String, Object?>{};
  for (final entry in raw.entries) {
    final key = entry.key;
    if (key is String) {
      out[key] = entry.value;
    }
  }
  return out;
}

Map<String, Object?> _manifestBuildSection(Map<String, Object?> manifest) {
  return _asStringObjectMap(manifest['build']);
}

Map<String, Object?> _manifestMobileOutputs(Map<String, Object?> manifest) {
  return _asStringObjectMap(_manifestBuildSection(manifest)['mobile_outputs']);
}

String? _manifestRuntimeBinaryPath(Map<String, Object?> manifest) {
  final paths = _asStringObjectMap(manifest['paths']);
  final value = paths['runtime_binary'];
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return p.normalize(value);
}

String? _manifestRuntimeSidecarPath(Map<String, Object?> manifest) {
  final paths = _asStringObjectMap(manifest['paths']);
  final value = paths['runtime_sidecar_binary'];
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return p.normalize(value);
}

Map<String, String> _manifestAndroidAbiLibraries(
  Map<String, Object?> manifest,
) {
  final mobile = _manifestMobileOutputs(manifest);
  final android = _asStringObjectMap(mobile['android']);
  final abis = _asStringObjectMap(android['abis']);
  final out = <String, String>{};
  for (final entry in abis.entries) {
    final value = entry.value;
    if (value is String && value.trim().isNotEmpty) {
      out[entry.key] = p.normalize(value);
    }
  }
  return out;
}

String? _manifestIosXcframeworkPath(Map<String, Object?> manifest) {
  final mobile = _manifestMobileOutputs(manifest);
  final ios = _asStringObjectMap(mobile['ios']);
  final value = ios['xcframework'];
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return p.normalize(value);
}

Future<void> _copyDirectoryRecursive({
  required String sourceDirPath,
  required String destinationDirPath,
}) async {
  final sourceDir = Directory(sourceDirPath);
  if (!sourceDir.existsSync()) {
    throw ToolError('Directory not found: $sourceDirPath');
  }

  final destinationDir = Directory(destinationDirPath);
  destinationDir.createSync(recursive: true);
  for (final entity in sourceDir.listSync(
    recursive: true,
    followLinks: false,
  )) {
    final rel = p.relative(entity.path, from: sourceDir.path);
    final targetPath = p.join(destinationDir.path, rel);
    if (entity is Directory) {
      Directory(targetPath).createSync(recursive: true);
      continue;
    }
    if (entity is File) {
      File(targetPath).createSync(recursive: true);
      await entity.copy(targetPath);
    }
  }
}

String _generateFlutterMethodIdConstants(Map<String, Object?> manifest) {
  final exports = manifest['exports'];
  if (exports is! List) {
    return '  // No typed method ids found in artifact.json.';
  }

  final used = <String>{};
  final lines = <String>[];
  for (final item in exports) {
    if (item is! Map) {
      continue;
    }
    final name = item['name'];
    if (name is! String || name.trim().isEmpty) {
      continue;
    }
    final suffix = _sanitizeForDartConst(name);

    void addConst(String field, String prefix) {
      final value = item[field];
      if (value is! int) {
        return;
      }
      final base = '${prefix}_$suffix';
      final constant = _uniqueDartConst(base, used);
      lines.add('  static const int $constant = $value;');
    }

    addConst('i64_2_method_id', 'i64_2');
    addConst('i64_4_method_id', 'i64_4');
    addConst('f64_2_method_id', 'f64_2');
    addConst('f64_4_method_id', 'f64_4');
    addConst('bytes_method_id', 'bytes');
  }

  if (lines.isEmpty) {
    return '  // No typed method ids found in artifact.json.';
  }
  return lines.join('\n');
}

String _sanitizeForDartConst(String value) {
  final out = StringBuffer();
  for (final rune in value.runes) {
    final ch = String.fromCharCode(rune);
    final isAlnum = RegExp(r'[A-Za-z0-9]').hasMatch(ch);
    out.write(isAlnum ? ch.toUpperCase() : '_');
  }
  var text = out.toString().replaceAll(RegExp(r'_+'), '_');
  text = text.replaceAll(RegExp(r'^_+|_+$'), '');
  if (text.isEmpty) {
    return 'METHOD';
  }
  if (RegExp(r'^[0-9]').hasMatch(text)) {
    return 'M_$text';
  }
  return text;
}

String _uniqueDartConst(String base, Set<String> used) {
  var candidate = base;
  var suffix = 2;
  while (!used.add(candidate)) {
    candidate = '${base}_$suffix';
    suffix++;
  }
  return candidate;
}

List<({String name, int value})> _collectTypedMethodIdConstants(
  Map<String, Object?> manifest,
) {
  final exports = manifest['exports'];
  if (exports is! List) {
    return const <({String name, int value})>[];
  }

  final out = <({String name, int value})>[];
  final used = <String>{};
  for (final item in exports) {
    if (item is! Map) {
      continue;
    }
    final name = item['name'];
    if (name is! String || name.trim().isEmpty) {
      continue;
    }
    final suffix = _sanitizeForDartConst(name);

    void addField(String field, String prefix) {
      final value = item[field];
      if (value is! int) {
        return;
      }
      final base = '${prefix}_$suffix';
      final unique = _uniqueDartConst(base, used).toUpperCase();
      out.add((name: unique, value: value));
    }

    addField('i64_2_method_id', 'I64_2');
    addField('i64_4_method_id', 'I64_4');
    addField('f64_2_method_id', 'F64_2');
    addField('f64_4_method_id', 'F64_4');
    addField('bytes_method_id', 'BYTES');
  }
  return out;
}

String _generatePythonMethodIdConstants(Map<String, Object?> manifest) {
  final entries = _collectTypedMethodIdConstants(manifest);
  if (entries.isEmpty) {
    return '  pass';
  }
  return entries.map((entry) => '  ${entry.name} = ${entry.value}').join('\n');
}

String _generateCSharpMethodIdConstants(Map<String, Object?> manifest) {
  final entries = _collectTypedMethodIdConstants(manifest);
  if (entries.isEmpty) {
    return '        // No typed method ids found in artifact.json.';
  }
  return entries
      .map(
        (entry) => '        public const int ${entry.name} = ${entry.value};',
      )
      .join('\n');
}

String _generateFlutterPluginPubspec({
  required String packageName,
  required String moduleName,
}) {
  return '''name: $packageName
description: Flutter FFI wrapper scaffold for dllart module $moduleName.
version: 0.1.0
publish_to: "none"

environment:
  sdk: ^3.10.0
  flutter: ">=3.19.0"

dependencies:
  ffi: ^2.1.4
  flutter:
    sdk: flutter

flutter:
  plugin:
    platforms:
      android:
        ffiPlugin: true
      ios:
        ffiPlugin: true
      linux:
        ffiPlugin: true
      macos:
        ffiPlugin: true
      windows:
        ffiPlugin: true
''';
}

String _generateFlutterPluginLibrary({required String moduleName}) {
  return '''library ${_sanitizeForC(moduleName).toLowerCase()}_dllart_plugin;

export '${moduleName}_ffi.dart';
''';
}

String _generateFlutterPluginBindings({
  required String moduleName,
  required String runtimePrefix,
  required String className,
  required String methodIdConstants,
}) {
  return '''import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef _AbiVersionNative = Int32 Function();
typedef _AbiVersionDart = int Function();

typedef _InitNative = Int32 Function(
  Pointer<Utf8> runtimePath,
  Pointer<Pointer<Utf8>> errorOut,
);
typedef _InitDart = int Function(
  Pointer<Utf8> runtimePath,
  Pointer<Pointer<Utf8>> errorOut,
);

typedef _CallJsonNative = Int32 Function(
  Pointer<Utf8> method,
  Pointer<Utf8> argsJson,
  Pointer<Pointer<Utf8>> resultJsonOut,
  Pointer<Pointer<Utf8>> errorOut,
);
typedef _CallJsonDart = int Function(
  Pointer<Utf8> method,
  Pointer<Utf8> argsJson,
  Pointer<Pointer<Utf8>> resultJsonOut,
  Pointer<Pointer<Utf8>> errorOut,
);

typedef _CallI64_2Native = Int32 Function(
  Pointer<Utf8> method,
  Int64 a,
  Int64 b,
  Pointer<Int64> resultOut,
  Pointer<Pointer<Utf8>> errorOut,
);
typedef _CallI64_2Dart = int Function(
  Pointer<Utf8> method,
  int a,
  int b,
  Pointer<Int64> resultOut,
  Pointer<Pointer<Utf8>> errorOut,
);

typedef _CallI64_2IndexNative = Int32 Function(
  Int32 methodId,
  Int64 a,
  Int64 b,
  Pointer<Int64> resultOut,
  Pointer<Pointer<Utf8>> errorOut,
);
typedef _CallI64_2IndexDart = int Function(
  int methodId,
  int a,
  int b,
  Pointer<Int64> resultOut,
  Pointer<Pointer<Utf8>> errorOut,
);

typedef _CallI64_4Native = Int32 Function(
  Pointer<Utf8> method,
  Int64 a,
  Int64 b,
  Int64 c,
  Int64 d,
  Pointer<Int64> resultOut,
  Pointer<Pointer<Utf8>> errorOut,
);
typedef _CallI64_4Dart = int Function(
  Pointer<Utf8> method,
  int a,
  int b,
  int c,
  int d,
  Pointer<Int64> resultOut,
  Pointer<Pointer<Utf8>> errorOut,
);

typedef _CallI64_4IndexNative = Int32 Function(
  Int32 methodId,
  Int64 a,
  Int64 b,
  Int64 c,
  Int64 d,
  Pointer<Int64> resultOut,
  Pointer<Pointer<Utf8>> errorOut,
);
typedef _CallI64_4IndexDart = int Function(
  int methodId,
  int a,
  int b,
  int c,
  int d,
  Pointer<Int64> resultOut,
  Pointer<Pointer<Utf8>> errorOut,
);

typedef _CallF64_2Native = Int32 Function(
  Pointer<Utf8> method,
  Double a,
  Double b,
  Pointer<Double> resultOut,
  Pointer<Pointer<Utf8>> errorOut,
);
typedef _CallF64_2Dart = int Function(
  Pointer<Utf8> method,
  double a,
  double b,
  Pointer<Double> resultOut,
  Pointer<Pointer<Utf8>> errorOut,
);

typedef _CallF64_2IndexNative = Int32 Function(
  Int32 methodId,
  Double a,
  Double b,
  Pointer<Double> resultOut,
  Pointer<Pointer<Utf8>> errorOut,
);
typedef _CallF64_2IndexDart = int Function(
  int methodId,
  double a,
  double b,
  Pointer<Double> resultOut,
  Pointer<Pointer<Utf8>> errorOut,
);

typedef _CallF64_4Native = Int32 Function(
  Pointer<Utf8> method,
  Double a,
  Double b,
  Double c,
  Double d,
  Pointer<Double> resultOut,
  Pointer<Pointer<Utf8>> errorOut,
);
typedef _CallF64_4Dart = int Function(
  Pointer<Utf8> method,
  double a,
  double b,
  double c,
  double d,
  Pointer<Double> resultOut,
  Pointer<Pointer<Utf8>> errorOut,
);

typedef _CallF64_4IndexNative = Int32 Function(
  Int32 methodId,
  Double a,
  Double b,
  Double c,
  Double d,
  Pointer<Double> resultOut,
  Pointer<Pointer<Utf8>> errorOut,
);
typedef _CallF64_4IndexDart = int Function(
  int methodId,
  double a,
  double b,
  double c,
  double d,
  Pointer<Double> resultOut,
  Pointer<Pointer<Utf8>> errorOut,
);

typedef _CallBytesNative = Int32 Function(
  Pointer<Utf8> method,
  Pointer<Uint8> args,
  Int32 argsLen,
  Pointer<Pointer<Uint8>> resultOut,
  Pointer<Int32> resultLenOut,
  Pointer<Pointer<Utf8>> errorOut,
);
typedef _CallBytesDart = int Function(
  Pointer<Utf8> method,
  Pointer<Uint8> args,
  int argsLen,
  Pointer<Pointer<Uint8>> resultOut,
  Pointer<Int32> resultLenOut,
  Pointer<Pointer<Utf8>> errorOut,
);

typedef _CallBytesIndexNative = Int32 Function(
  Int32 methodId,
  Pointer<Uint8> args,
  Int32 argsLen,
  Pointer<Pointer<Uint8>> resultOut,
  Pointer<Int32> resultLenOut,
  Pointer<Pointer<Utf8>> errorOut,
);
typedef _CallBytesIndexDart = int Function(
  int methodId,
  Pointer<Uint8> args,
  int argsLen,
  Pointer<Pointer<Uint8>> resultOut,
  Pointer<Int32> resultLenOut,
  Pointer<Pointer<Utf8>> errorOut,
);

typedef _ShutdownNative = Void Function();
typedef _ShutdownDart = void Function();

typedef _StringFreeNative = Void Function(Pointer<Char> value);
typedef _StringFreeDart = void Function(Pointer<Char> value);
typedef _BytesFreeNative = Void Function(Pointer<Uint8> value);
typedef _BytesFreeDart = void Function(Pointer<Uint8> value);

class ${className}MethodIds {
  const ${className}MethodIds._();

$methodIdConstants
}

class $className {
  $className._(DynamicLibrary lib)
    : _abiVersion = lib.lookupFunction<_AbiVersionNative, _AbiVersionDart>(
        '${runtimePrefix}_abi_version',
      ),
      _init = lib.lookupFunction<_InitNative, _InitDart>(
        '${runtimePrefix}_init',
      ),
      _callJson = lib.lookupFunction<_CallJsonNative, _CallJsonDart>(
        '${runtimePrefix}_call_json',
      ),
      _callI64_2 = lib.lookupFunction<_CallI64_2Native, _CallI64_2Dart>(
        '${runtimePrefix}_call_i64_2',
      ),
      _callI64_2Index = lib.lookupFunction<
        _CallI64_2IndexNative,
        _CallI64_2IndexDart
      >('${runtimePrefix}_call_i64_2_index'),
      _callI64_4 = lib.lookupFunction<_CallI64_4Native, _CallI64_4Dart>(
        '${runtimePrefix}_call_i64_4',
      ),
      _callI64_4Index = lib.lookupFunction<
        _CallI64_4IndexNative,
        _CallI64_4IndexDart
      >('${runtimePrefix}_call_i64_4_index'),
      _callF64_2 = lib.lookupFunction<_CallF64_2Native, _CallF64_2Dart>(
        '${runtimePrefix}_call_f64_2',
      ),
      _callF64_2Index = lib.lookupFunction<
        _CallF64_2IndexNative,
        _CallF64_2IndexDart
      >('${runtimePrefix}_call_f64_2_index'),
      _callF64_4 = lib.lookupFunction<_CallF64_4Native, _CallF64_4Dart>(
        '${runtimePrefix}_call_f64_4',
      ),
      _callF64_4Index = lib.lookupFunction<
        _CallF64_4IndexNative,
        _CallF64_4IndexDart
      >('${runtimePrefix}_call_f64_4_index'),
      _callBytes = lib.lookupFunction<_CallBytesNative, _CallBytesDart>(
        '${runtimePrefix}_call_bytes',
      ),
      _callBytesIndex = lib.lookupFunction<
        _CallBytesIndexNative,
        _CallBytesIndexDart
      >('${runtimePrefix}_call_bytes_index'),
      _shutdown = lib.lookupFunction<_ShutdownNative, _ShutdownDart>(
        '${runtimePrefix}_shutdown',
      ),
      _stringFree = lib.lookupFunction<_StringFreeNative, _StringFreeDart>(
        '${runtimePrefix}_string_free',
      ),
      _bytesFree = lib.lookupFunction<_BytesFreeNative, _BytesFreeDart>(
        '${runtimePrefix}_bytes_free',
      );

  factory $className.open([DynamicLibrary? library]) {
    return $className._(library ?? _openLibrary());
  }

  final _AbiVersionDart _abiVersion;
  final _InitDart _init;
  final _CallJsonDart _callJson;
  final _CallI64_2Dart _callI64_2;
  final _CallI64_2IndexDart _callI64_2Index;
  final _CallI64_4Dart _callI64_4;
  final _CallI64_4IndexDart _callI64_4Index;
  final _CallF64_2Dart _callF64_2;
  final _CallF64_2IndexDart _callF64_2Index;
  final _CallF64_4Dart _callF64_4;
  final _CallF64_4IndexDart _callF64_4Index;
  final _CallBytesDart _callBytes;
  final _CallBytesIndexDart _callBytesIndex;
  final _ShutdownDart _shutdown;
  final _StringFreeDart _stringFree;
  final _BytesFreeDart _bytesFree;

  static DynamicLibrary _openLibrary() {
    if (Platform.isAndroid || Platform.isLinux || Platform.isFuchsia) {
      return DynamicLibrary.open('lib$moduleName.so');
    }
    if (Platform.isWindows) {
      return DynamicLibrary.open('$moduleName.dll');
    }
    if (Platform.isMacOS) {
      return DynamicLibrary.open('lib$moduleName.dylib');
    }
    if (Platform.isIOS) {
      return DynamicLibrary.process();
    }
    throw UnsupportedError('Unsupported platform for $moduleName');
  }

  int abiVersion() => _abiVersion();

  void init({String? runtimePath}) {
    final runtimePathPtr =
        runtimePath == null ? nullptr : runtimePath.toNativeUtf8();
    final errorOut = calloc<Pointer<Utf8>>();
    try {
      final rc = _init(runtimePathPtr, errorOut);
      if (rc != 0) {
        throw StateError(_consumeError(errorOut));
      }
    } finally {
      if (runtimePathPtr != nullptr) {
        calloc.free(runtimePathPtr);
      }
      calloc.free(errorOut);
    }
  }

  String callJson(String method, String argsJson) {
    final methodPtr = method.toNativeUtf8();
    final argsPtr = argsJson.toNativeUtf8();
    final resultOut = calloc<Pointer<Utf8>>();
    final errorOut = calloc<Pointer<Utf8>>();
    try {
      final rc = _callJson(methodPtr, argsPtr, resultOut, errorOut);
      if (rc != 0) {
        throw StateError(_consumeError(errorOut));
      }

      final resultPtr = resultOut.value;
      if (resultPtr == nullptr) {
        throw StateError('call_json returned null result');
      }

      final out = resultPtr.toDartString();
      _stringFree(resultPtr.cast<Char>());
      return out;
    } finally {
      calloc.free(methodPtr);
      calloc.free(argsPtr);
      calloc.free(resultOut);
      calloc.free(errorOut);
    }
  }

  int callI64_2(String method, int a, int b) {
    final methodPtr = method.toNativeUtf8();
    final resultOut = calloc<Int64>();
    final errorOut = calloc<Pointer<Utf8>>();
    try {
      final rc = _callI64_2(methodPtr, a, b, resultOut, errorOut);
      if (rc != 0) {
        throw StateError(_consumeError(errorOut));
      }
      return resultOut.value;
    } finally {
      calloc.free(methodPtr);
      calloc.free(resultOut);
      calloc.free(errorOut);
    }
  }

  int callI64_2Index(int methodId, int a, int b) {
    final resultOut = calloc<Int64>();
    final errorOut = calloc<Pointer<Utf8>>();
    try {
      final rc = _callI64_2Index(methodId, a, b, resultOut, errorOut);
      if (rc != 0) {
        throw StateError(_consumeError(errorOut));
      }
      return resultOut.value;
    } finally {
      calloc.free(resultOut);
      calloc.free(errorOut);
    }
  }

  int callI64_4(String method, int a, int b, int c, int d) {
    final methodPtr = method.toNativeUtf8();
    final resultOut = calloc<Int64>();
    final errorOut = calloc<Pointer<Utf8>>();
    try {
      final rc = _callI64_4(methodPtr, a, b, c, d, resultOut, errorOut);
      if (rc != 0) {
        throw StateError(_consumeError(errorOut));
      }
      return resultOut.value;
    } finally {
      calloc.free(methodPtr);
      calloc.free(resultOut);
      calloc.free(errorOut);
    }
  }

  int callI64_4Index(int methodId, int a, int b, int c, int d) {
    final resultOut = calloc<Int64>();
    final errorOut = calloc<Pointer<Utf8>>();
    try {
      final rc = _callI64_4Index(methodId, a, b, c, d, resultOut, errorOut);
      if (rc != 0) {
        throw StateError(_consumeError(errorOut));
      }
      return resultOut.value;
    } finally {
      calloc.free(resultOut);
      calloc.free(errorOut);
    }
  }

  double callF64_2(String method, double a, double b) {
    final methodPtr = method.toNativeUtf8();
    final resultOut = calloc<Double>();
    final errorOut = calloc<Pointer<Utf8>>();
    try {
      final rc = _callF64_2(methodPtr, a, b, resultOut, errorOut);
      if (rc != 0) {
        throw StateError(_consumeError(errorOut));
      }
      return resultOut.value;
    } finally {
      calloc.free(methodPtr);
      calloc.free(resultOut);
      calloc.free(errorOut);
    }
  }

  double callF64_2Index(int methodId, double a, double b) {
    final resultOut = calloc<Double>();
    final errorOut = calloc<Pointer<Utf8>>();
    try {
      final rc = _callF64_2Index(methodId, a, b, resultOut, errorOut);
      if (rc != 0) {
        throw StateError(_consumeError(errorOut));
      }
      return resultOut.value;
    } finally {
      calloc.free(resultOut);
      calloc.free(errorOut);
    }
  }

  double callF64_4(String method, double a, double b, double c, double d) {
    final methodPtr = method.toNativeUtf8();
    final resultOut = calloc<Double>();
    final errorOut = calloc<Pointer<Utf8>>();
    try {
      final rc = _callF64_4(methodPtr, a, b, c, d, resultOut, errorOut);
      if (rc != 0) {
        throw StateError(_consumeError(errorOut));
      }
      return resultOut.value;
    } finally {
      calloc.free(methodPtr);
      calloc.free(resultOut);
      calloc.free(errorOut);
    }
  }

  double callF64_4Index(int methodId, double a, double b, double c, double d) {
    final resultOut = calloc<Double>();
    final errorOut = calloc<Pointer<Utf8>>();
    try {
      final rc = _callF64_4Index(methodId, a, b, c, d, resultOut, errorOut);
      if (rc != 0) {
        throw StateError(_consumeError(errorOut));
      }
      return resultOut.value;
    } finally {
      calloc.free(resultOut);
      calloc.free(errorOut);
    }
  }

  Uint8List callBytes(String method, Uint8List args) {
    final methodPtr = method.toNativeUtf8();
    final argsPtr = calloc<Uint8>(args.length);
    if (args.isNotEmpty) {
      argsPtr.asTypedList(args.length).setAll(0, args);
    }
    final resultOut = calloc<Pointer<Uint8>>();
    final resultLenOut = calloc<Int32>();
    final errorOut = calloc<Pointer<Utf8>>();
    try {
      final rc = _callBytes(
        methodPtr,
        argsPtr,
        args.length,
        resultOut,
        resultLenOut,
        errorOut,
      );
      if (rc != 0) {
        throw StateError(_consumeError(errorOut));
      }

      final resultPtr = resultOut.value;
      final resultLen = resultLenOut.value;
      if (resultLen < 0) {
        throw StateError('call_bytes returned negative length');
      }
      if (resultLen == 0) {
        if (resultPtr != nullptr) {
          _bytesFree(resultPtr);
        }
        return Uint8List(0);
      }
      if (resultPtr == nullptr) {
        throw StateError('call_bytes returned null pointer with non-zero size');
      }
      final out = Uint8List.fromList(resultPtr.asTypedList(resultLen));
      _bytesFree(resultPtr);
      return out;
    } finally {
      calloc.free(methodPtr);
      calloc.free(argsPtr);
      calloc.free(resultOut);
      calloc.free(resultLenOut);
      calloc.free(errorOut);
    }
  }

  Uint8List callBytesIndex(int methodId, Uint8List args) {
    final argsPtr = calloc<Uint8>(args.length);
    if (args.isNotEmpty) {
      argsPtr.asTypedList(args.length).setAll(0, args);
    }
    final resultOut = calloc<Pointer<Uint8>>();
    final resultLenOut = calloc<Int32>();
    final errorOut = calloc<Pointer<Utf8>>();
    try {
      final rc = _callBytesIndex(
        methodId,
        argsPtr,
        args.length,
        resultOut,
        resultLenOut,
        errorOut,
      );
      if (rc != 0) {
        throw StateError(_consumeError(errorOut));
      }

      final resultPtr = resultOut.value;
      final resultLen = resultLenOut.value;
      if (resultLen < 0) {
        throw StateError('call_bytes_index returned negative length');
      }
      if (resultLen == 0) {
        if (resultPtr != nullptr) {
          _bytesFree(resultPtr);
        }
        return Uint8List(0);
      }
      if (resultPtr == nullptr) {
        throw StateError(
          'call_bytes_index returned null pointer with non-zero size',
        );
      }
      final out = Uint8List.fromList(resultPtr.asTypedList(resultLen));
      _bytesFree(resultPtr);
      return out;
    } finally {
      calloc.free(argsPtr);
      calloc.free(resultOut);
      calloc.free(resultLenOut);
      calloc.free(errorOut);
    }
  }

  void shutdown() {
    _shutdown();
  }

  String _consumeError(Pointer<Pointer<Utf8>> errorOut) {
    final errorPtr = errorOut.value;
    if (errorPtr == nullptr) {
      return 'Unknown dllart error';
    }
    final message = errorPtr.toDartString();
    _stringFree(errorPtr.cast<Char>());
    return message;
  }
}
''';
}

String _generateFlutterPluginReadme({
  required String packageName,
  required String moduleName,
  required String className,
  required String runtimeFileName,
}) {
  return '''# $packageName

Generated by `dllart package flutter`.

This is a Flutter FFI plugin scaffold for module `$moduleName`.

## Quick start

1. Add this package as path dependency in your Flutter app.
2. Copy native artifacts:
   - Android: `android/src/main/jniLibs/<abi>/lib$moduleName.so`
   - iOS: `ios/Frameworks/$moduleName.xcframework`
   - Runtime: `native/runtime/$runtimeFileName` (auto-generated)
3. Run `flutter pub get`.
4. Use `${className}.open()` to call exported methods.

## Files

- `lib/${moduleName}_ffi.dart` — generated FFI bindings.
- `artifact.json` — copied dllart manifest with method ids.
- `native/include/${moduleName}_api.h` — generated C API header.
- `native/runtime/$runtimeFileName` — bundled Dart runtime binary.
- `android/src/main/jniLibs/` — ABI folders for Android binaries.
- `ios/Headers/` + `ios/Frameworks/` — iOS integration placeholders.

## Example

```dart
import 'package:$packageName/$packageName.dart';

final mod = $className.open();
mod.init();
// Optional: mod.init(runtimePath: '/absolute/path/to/$runtimeFileName');

final json = mod.callJson('add', '{"a": 20, "b": 22}');
final fast = mod.callI64_2('add_fast', 20, 22);
// Protobuf/bytes fast-path (for Uint8List payloads):
// final bytes = mod.callBytes('ping_proto', yourRequestBytes);
// Indexed fast-path constants are generated from artifact.json:
// final fastIndexed = mod.callI64_2Index(${className}MethodIds.i64_2_<EXPORT>, 20, 22);

mod.shutdown();
```
''';
}

String _generateFlutterAndroidReadme({required String moduleName}) {
  return '''# Android integration

Copy built Android binaries into:

- `src/main/jniLibs/arm64-v8a/lib$moduleName.so`
- `src/main/jniLibs/armeabi-v7a/lib$moduleName.so`
- `src/main/jniLibs/x86_64/lib$moduleName.so`
''';
}

String _generateFlutterIosReadme({required String moduleName}) {
  return '''# iOS integration

1. Build `$moduleName.xcframework` for device + simulator.
2. Place it into `Frameworks/$moduleName.xcframework`.
3. Keep public headers in `Headers/`.
''';
}

String _generatePythonBindings({
  required String moduleName,
  required String runtimePrefix,
  required String libraryFileName,
  required String? runtimeFileName,
  required String methodIdConstants,
}) {
  final className = '${_upperCamelCase(moduleName)}Client';
  final runtimeLiteral = runtimeFileName == null
      ? 'None'
      : "'${_escapeDartSingleQuoted(runtimeFileName)}'";
  return '''from __future__ import annotations

import ctypes
from pathlib import Path


class DllartError(RuntimeError):
  pass


class ${className}MethodIds:
$methodIdConstants


class $className:
  def __init__(self, library_path: str | None = None, runtime_path: str | None = None) -> None:
    root = Path(__file__).resolve().parent
    bundled_runtime = $runtimeLiteral
    self._library_path = Path(library_path) if library_path else root / "native" / "$libraryFileName"
    self._runtime_path = Path(runtime_path) if runtime_path else (
      (root / "runtime" / bundled_runtime) if bundled_runtime else None
    )
    self._lib = ctypes.CDLL(str(self._library_path))

    self._init = self._lib.${runtimePrefix}_init
    self._init.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_char_p)]
    self._init.restype = ctypes.c_int

    self._call_json = self._lib.${runtimePrefix}_call_json
    self._call_json.argtypes = [
      ctypes.c_char_p,
      ctypes.c_char_p,
      ctypes.POINTER(ctypes.c_char_p),
      ctypes.POINTER(ctypes.c_char_p),
    ]
    self._call_json.restype = ctypes.c_int

    self._call_json_batch = self._lib.${runtimePrefix}_call_json_batch
    self._call_json_batch.argtypes = [
      ctypes.c_char_p,
      ctypes.POINTER(ctypes.c_char_p),
      ctypes.POINTER(ctypes.c_char_p),
    ]
    self._call_json_batch.restype = ctypes.c_int

    self._call_json_raw = self._lib.${runtimePrefix}_call_json_raw
    self._call_json_raw.argtypes = [
      ctypes.c_char_p,
      ctypes.c_char_p,
      ctypes.POINTER(ctypes.c_char_p),
      ctypes.POINTER(ctypes.c_char_p),
    ]
    self._call_json_raw.restype = ctypes.c_int

    self._call_i64_2 = self._lib.${runtimePrefix}_call_i64_2
    self._call_i64_2.argtypes = [
      ctypes.c_char_p,
      ctypes.c_longlong,
      ctypes.c_longlong,
      ctypes.POINTER(ctypes.c_longlong),
      ctypes.POINTER(ctypes.c_char_p),
    ]
    self._call_i64_2.restype = ctypes.c_int

    self._call_i64_2_index = self._lib.${runtimePrefix}_call_i64_2_index
    self._call_i64_2_index.argtypes = [
      ctypes.c_int32,
      ctypes.c_longlong,
      ctypes.c_longlong,
      ctypes.POINTER(ctypes.c_longlong),
      ctypes.POINTER(ctypes.c_char_p),
    ]
    self._call_i64_2_index.restype = ctypes.c_int

    self._call_i64_4 = self._lib.${runtimePrefix}_call_i64_4
    self._call_i64_4.argtypes = [
      ctypes.c_char_p,
      ctypes.c_longlong,
      ctypes.c_longlong,
      ctypes.c_longlong,
      ctypes.c_longlong,
      ctypes.POINTER(ctypes.c_longlong),
      ctypes.POINTER(ctypes.c_char_p),
    ]
    self._call_i64_4.restype = ctypes.c_int

    self._call_i64_4_index = self._lib.${runtimePrefix}_call_i64_4_index
    self._call_i64_4_index.argtypes = [
      ctypes.c_int32,
      ctypes.c_longlong,
      ctypes.c_longlong,
      ctypes.c_longlong,
      ctypes.c_longlong,
      ctypes.POINTER(ctypes.c_longlong),
      ctypes.POINTER(ctypes.c_char_p),
    ]
    self._call_i64_4_index.restype = ctypes.c_int

    self._call_f64_2 = self._lib.${runtimePrefix}_call_f64_2
    self._call_f64_2.argtypes = [
      ctypes.c_char_p,
      ctypes.c_double,
      ctypes.c_double,
      ctypes.POINTER(ctypes.c_double),
      ctypes.POINTER(ctypes.c_char_p),
    ]
    self._call_f64_2.restype = ctypes.c_int

    self._call_f64_2_index = self._lib.${runtimePrefix}_call_f64_2_index
    self._call_f64_2_index.argtypes = [
      ctypes.c_int32,
      ctypes.c_double,
      ctypes.c_double,
      ctypes.POINTER(ctypes.c_double),
      ctypes.POINTER(ctypes.c_char_p),
    ]
    self._call_f64_2_index.restype = ctypes.c_int

    self._call_f64_4 = self._lib.${runtimePrefix}_call_f64_4
    self._call_f64_4.argtypes = [
      ctypes.c_char_p,
      ctypes.c_double,
      ctypes.c_double,
      ctypes.c_double,
      ctypes.c_double,
      ctypes.POINTER(ctypes.c_double),
      ctypes.POINTER(ctypes.c_char_p),
    ]
    self._call_f64_4.restype = ctypes.c_int

    self._call_f64_4_index = self._lib.${runtimePrefix}_call_f64_4_index
    self._call_f64_4_index.argtypes = [
      ctypes.c_int32,
      ctypes.c_double,
      ctypes.c_double,
      ctypes.c_double,
      ctypes.c_double,
      ctypes.POINTER(ctypes.c_double),
      ctypes.POINTER(ctypes.c_char_p),
    ]
    self._call_f64_4_index.restype = ctypes.c_int

    self._call_bytes = self._lib.${runtimePrefix}_call_bytes
    self._call_bytes.argtypes = [
      ctypes.c_char_p,
      ctypes.POINTER(ctypes.c_uint8),
      ctypes.c_int32,
      ctypes.POINTER(ctypes.POINTER(ctypes.c_uint8)),
      ctypes.POINTER(ctypes.c_int32),
      ctypes.POINTER(ctypes.c_char_p),
    ]
    self._call_bytes.restype = ctypes.c_int

    self._call_bytes_index = self._lib.${runtimePrefix}_call_bytes_index
    self._call_bytes_index.argtypes = [
      ctypes.c_int32,
      ctypes.POINTER(ctypes.c_uint8),
      ctypes.c_int32,
      ctypes.POINTER(ctypes.POINTER(ctypes.c_uint8)),
      ctypes.POINTER(ctypes.c_int32),
      ctypes.POINTER(ctypes.c_char_p),
    ]
    self._call_bytes_index.restype = ctypes.c_int

    self._last_error_code = self._lib.${runtimePrefix}_last_error_code
    self._last_error_code.argtypes = []
    self._last_error_code.restype = ctypes.c_int

    self._last_error_json = self._lib.${runtimePrefix}_last_error_json
    self._last_error_json.argtypes = [ctypes.POINTER(ctypes.c_char_p)]
    self._last_error_json.restype = ctypes.c_int

    self._shutdown = self._lib.${runtimePrefix}_shutdown
    self._shutdown.argtypes = []
    self._shutdown.restype = None

    self._string_free = self._lib.${runtimePrefix}_string_free
    self._string_free.argtypes = [ctypes.c_void_p]
    self._string_free.restype = None

    self._bytes_free = self._lib.${runtimePrefix}_bytes_free
    self._bytes_free.argtypes = [ctypes.c_void_p]
    self._bytes_free.restype = None

  def _consume_error(self, error_ptr: ctypes.c_char_p) -> str:
    if not error_ptr or not error_ptr.value:
      return "Unknown dllart error"
    message = error_ptr.value.decode("utf-8")
    self._string_free(error_ptr)
    return message

  def _consume_json_result(self, result_ptr: ctypes.c_char_p) -> str:
    if not result_ptr or not result_ptr.value:
      raise DllartError("call_json returned null result")
    out = result_ptr.value.decode("utf-8")
    self._string_free(result_ptr)
    return out

  def init(self, runtime_path: str | None = None) -> None:
    resolved_runtime = runtime_path or (
      str(self._runtime_path) if self._runtime_path and self._runtime_path.exists() else None
    )
    error = ctypes.c_char_p()
    runtime_arg = resolved_runtime.encode("utf-8") if resolved_runtime else None
    rc = self._init(runtime_arg, ctypes.byref(error))
    if rc != 0:
      raise DllartError(self._consume_error(error))

  def call_json(self, method: str, args_json: str) -> str:
    result = ctypes.c_char_p()
    error = ctypes.c_char_p()
    rc = self._call_json(
      method.encode("utf-8"),
      args_json.encode("utf-8"),
      ctypes.byref(result),
      ctypes.byref(error),
    )
    if rc != 0:
      raise DllartError(self._consume_error(error))
    return self._consume_json_result(result)

  def call_json_batch(self, batch_json: str) -> str:
    result = ctypes.c_char_p()
    error = ctypes.c_char_p()
    rc = self._call_json_batch(
      batch_json.encode("utf-8"),
      ctypes.byref(result),
      ctypes.byref(error),
    )
    if rc != 0:
      raise DllartError(self._consume_error(error))
    return self._consume_json_result(result)

  def call_json_raw(self, method: str, args_json: str) -> str:
    result = ctypes.c_char_p()
    error = ctypes.c_char_p()
    rc = self._call_json_raw(
      method.encode("utf-8"),
      args_json.encode("utf-8"),
      ctypes.byref(result),
      ctypes.byref(error),
    )
    if rc != 0:
      raise DllartError(self._consume_error(error))
    return self._consume_json_result(result)

  def call_i64_2(self, method: str, a: int, b: int) -> int:
    result = ctypes.c_longlong()
    error = ctypes.c_char_p()
    rc = self._call_i64_2(
      method.encode("utf-8"),
      a,
      b,
      ctypes.byref(result),
      ctypes.byref(error),
    )
    if rc != 0:
      raise DllartError(self._consume_error(error))
    return int(result.value)

  def call_i64_2_index(self, method_id: int, a: int, b: int) -> int:
    result = ctypes.c_longlong()
    error = ctypes.c_char_p()
    rc = self._call_i64_2_index(method_id, a, b, ctypes.byref(result), ctypes.byref(error))
    if rc != 0:
      raise DllartError(self._consume_error(error))
    return int(result.value)

  def call_i64_4(self, method: str, a: int, b: int, c: int, d: int) -> int:
    result = ctypes.c_longlong()
    error = ctypes.c_char_p()
    rc = self._call_i64_4(
      method.encode("utf-8"),
      a,
      b,
      c,
      d,
      ctypes.byref(result),
      ctypes.byref(error),
    )
    if rc != 0:
      raise DllartError(self._consume_error(error))
    return int(result.value)

  def call_i64_4_index(self, method_id: int, a: int, b: int, c: int, d: int) -> int:
    result = ctypes.c_longlong()
    error = ctypes.c_char_p()
    rc = self._call_i64_4_index(
      method_id,
      a,
      b,
      c,
      d,
      ctypes.byref(result),
      ctypes.byref(error),
    )
    if rc != 0:
      raise DllartError(self._consume_error(error))
    return int(result.value)

  def call_f64_2(self, method: str, a: float, b: float) -> float:
    result = ctypes.c_double()
    error = ctypes.c_char_p()
    rc = self._call_f64_2(
      method.encode("utf-8"),
      a,
      b,
      ctypes.byref(result),
      ctypes.byref(error),
    )
    if rc != 0:
      raise DllartError(self._consume_error(error))
    return float(result.value)

  def call_f64_2_index(self, method_id: int, a: float, b: float) -> float:
    result = ctypes.c_double()
    error = ctypes.c_char_p()
    rc = self._call_f64_2_index(
      method_id,
      a,
      b,
      ctypes.byref(result),
      ctypes.byref(error),
    )
    if rc != 0:
      raise DllartError(self._consume_error(error))
    return float(result.value)

  def call_f64_4(self, method: str, a: float, b: float, c: float, d: float) -> float:
    result = ctypes.c_double()
    error = ctypes.c_char_p()
    rc = self._call_f64_4(
      method.encode("utf-8"),
      a,
      b,
      c,
      d,
      ctypes.byref(result),
      ctypes.byref(error),
    )
    if rc != 0:
      raise DllartError(self._consume_error(error))
    return float(result.value)

  def call_f64_4_index(self, method_id: int, a: float, b: float, c: float, d: float) -> float:
    result = ctypes.c_double()
    error = ctypes.c_char_p()
    rc = self._call_f64_4_index(
      method_id,
      a,
      b,
      c,
      d,
      ctypes.byref(result),
      ctypes.byref(error),
    )
    if rc != 0:
      raise DllartError(self._consume_error(error))
    return float(result.value)

  def call_bytes(self, method: str, args: bytes) -> bytes:
    payload = bytes(args)
    payload_len = len(payload)
    payload_buf = (ctypes.c_uint8 * payload_len).from_buffer_copy(payload) if payload_len > 0 else None
    payload_ptr = ctypes.cast(payload_buf, ctypes.POINTER(ctypes.c_uint8)) if payload_buf is not None else None
    result_ptr = ctypes.POINTER(ctypes.c_uint8)()
    result_len = ctypes.c_int32()
    error = ctypes.c_char_p()
    rc = self._call_bytes(
      method.encode("utf-8"),
      payload_ptr,
      payload_len,
      ctypes.byref(result_ptr),
      ctypes.byref(result_len),
      ctypes.byref(error),
    )
    if rc != 0:
      raise DllartError(self._consume_error(error))
    if result_len.value < 0:
      raise DllartError("call_bytes returned negative length")
    size = int(result_len.value)
    if size == 0:
      if bool(result_ptr):
        self._bytes_free(result_ptr)
      return b""
    if not bool(result_ptr):
      raise DllartError("call_bytes returned null pointer with non-zero size")
    out = ctypes.string_at(result_ptr, size)
    self._bytes_free(result_ptr)
    return out

  def call_bytes_index(self, method_id: int, args: bytes) -> bytes:
    payload = bytes(args)
    payload_len = len(payload)
    payload_buf = (ctypes.c_uint8 * payload_len).from_buffer_copy(payload) if payload_len > 0 else None
    payload_ptr = ctypes.cast(payload_buf, ctypes.POINTER(ctypes.c_uint8)) if payload_buf is not None else None
    result_ptr = ctypes.POINTER(ctypes.c_uint8)()
    result_len = ctypes.c_int32()
    error = ctypes.c_char_p()
    rc = self._call_bytes_index(
      method_id,
      payload_ptr,
      payload_len,
      ctypes.byref(result_ptr),
      ctypes.byref(result_len),
      ctypes.byref(error),
    )
    if rc != 0:
      raise DllartError(self._consume_error(error))
    if result_len.value < 0:
      raise DllartError("call_bytes_index returned negative length")
    size = int(result_len.value)
    if size == 0:
      if bool(result_ptr):
        self._bytes_free(result_ptr)
      return b""
    if not bool(result_ptr):
      raise DllartError("call_bytes_index returned null pointer with non-zero size")
    out = ctypes.string_at(result_ptr, size)
    self._bytes_free(result_ptr)
    return out

  def last_error_code(self) -> int:
    return int(self._last_error_code())

  def last_error_json(self) -> str:
    out = ctypes.c_char_p()
    rc = self._last_error_json(ctypes.byref(out))
    if rc != 0:
      raise DllartError("last_error_json failed")
    return self._consume_json_result(out)

  def shutdown(self) -> None:
    self._shutdown()
''';
}

String _generatePythonExample({required String moduleName}) {
  final className = '${_upperCamelCase(moduleName)}Client';
  return '''from bindings import $className


def main() -> None:
  mod = $className()
  mod.init()
  print(mod.call_json("add", '{"a": 20, "b": 22}'))
  print(mod.call_i64_2("add_fast", 20, 22))
  mod.shutdown()


if __name__ == "__main__":
  main()
''';
}

String _generatePythonPackageReadme({
  required String moduleName,
  required String libraryFileName,
  required String? runtimeFileName,
}) {
  final runtimeLine = runtimeFileName == null
      ? '- Optional runtime: set `DLLART_DART_RUNTIME` or pass `runtime_path` to `init()`.'
      : '- Bundled runtime: `runtime/$runtimeFileName`.';
  return '''# Python scaffold for $moduleName

Generated by `dllart package python`.

Files:

- `bindings.py` — ctypes wrapper for core dllart calls.
- `example.py` — runnable usage example.
- `native/$libraryFileName` — host library artifact.
$runtimeLine
- `${moduleName}_api.h` — generated C API header.
- `artifact.json` — copied dllart manifest.

Run:

```bash
python3 example.py
```
''';
}

String _generateCSharpBindings({
  required String moduleName,
  required String runtimePrefix,
  required String libraryFileName,
  required String? runtimeFileName,
  required String methodIdConstants,
}) {
  final className = '${_upperCamelCase(moduleName)}Client';
  final runtimeLiteral = runtimeFileName == null
      ? 'null'
      : '"${_escapeCString(runtimeFileName)}"';
  return '''using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

public sealed class $className : IDisposable
{
    private readonly IntPtr _libraryHandle;
    private readonly string? _runtimePath;
    private bool _disposed;

    public static class MethodIds
    {
$methodIdConstants
    }

    private delegate int AbiVersionDelegate();
    private delegate int InitDelegate(IntPtr runtimePath, out IntPtr errorOut);
    private delegate int CallJsonDelegate(
        IntPtr method,
        IntPtr argsJson,
        out IntPtr resultJsonOut,
        out IntPtr errorOut);
    private delegate int CallJsonBatchDelegate(
        IntPtr batchJson,
        out IntPtr resultJsonOut,
        out IntPtr errorOut);
    private delegate int CallJsonRawDelegate(
        IntPtr method,
        IntPtr argsJson,
        out IntPtr resultJsonOut,
        out IntPtr errorOut);
    private delegate int CallI64_2Delegate(
        IntPtr method,
        long a,
        long b,
        out long resultOut,
        out IntPtr errorOut);
    private delegate int CallI64_2IndexDelegate(
        int methodId,
        long a,
        long b,
        out long resultOut,
        out IntPtr errorOut);
    private delegate int CallI64_4Delegate(
        IntPtr method,
        long a,
        long b,
        long c,
        long d,
        out long resultOut,
        out IntPtr errorOut);
    private delegate int CallI64_4IndexDelegate(
        int methodId,
        long a,
        long b,
        long c,
        long d,
        out long resultOut,
        out IntPtr errorOut);
    private delegate int CallF64_2Delegate(
        IntPtr method,
        double a,
        double b,
        out double resultOut,
        out IntPtr errorOut);
    private delegate int CallF64_2IndexDelegate(
        int methodId,
        double a,
        double b,
        out double resultOut,
        out IntPtr errorOut);
    private delegate int CallF64_4Delegate(
        IntPtr method,
        double a,
        double b,
        double c,
        double d,
        out double resultOut,
        out IntPtr errorOut);
    private delegate int CallF64_4IndexDelegate(
        int methodId,
        double a,
        double b,
        double c,
        double d,
        out double resultOut,
        out IntPtr errorOut);
    private delegate int CallBytesDelegate(
        IntPtr method,
        byte[] args,
        int argsLen,
        out IntPtr resultOut,
        out int resultLenOut,
        out IntPtr errorOut);
    private delegate int CallBytesIndexDelegate(
        int methodId,
        byte[] args,
        int argsLen,
        out IntPtr resultOut,
        out int resultLenOut,
        out IntPtr errorOut);
    private delegate int LastErrorCodeDelegate();
    private delegate int LastErrorJsonDelegate(out IntPtr errorJsonOut);
    private delegate void ShutdownDelegate();
    private delegate void StringFreeDelegate(IntPtr value);
    private delegate void BytesFreeDelegate(IntPtr value);

    private static readonly string? BundledRuntimeFileName = $runtimeLiteral;

    private readonly AbiVersionDelegate _abiVersion;
    private readonly InitDelegate _init;
    private readonly CallJsonDelegate _callJson;
    private readonly CallJsonBatchDelegate _callJsonBatch;
    private readonly CallJsonRawDelegate _callJsonRaw;
    private readonly CallI64_2Delegate _callI64_2;
    private readonly CallI64_2IndexDelegate _callI64_2Index;
    private readonly CallI64_4Delegate _callI64_4;
    private readonly CallI64_4IndexDelegate _callI64_4Index;
    private readonly CallF64_2Delegate _callF64_2;
    private readonly CallF64_2IndexDelegate _callF64_2Index;
    private readonly CallF64_4Delegate _callF64_4;
    private readonly CallF64_4IndexDelegate _callF64_4Index;
    private readonly CallBytesDelegate _callBytes;
    private readonly CallBytesIndexDelegate _callBytesIndex;
    private readonly LastErrorCodeDelegate _lastErrorCode;
    private readonly LastErrorJsonDelegate _lastErrorJson;
    private readonly ShutdownDelegate _shutdown;
    private readonly StringFreeDelegate _stringFree;
    private readonly BytesFreeDelegate _bytesFree;

    public $className(string? libraryPath = null, string? runtimePath = null)
    {
        var root = AppContext.BaseDirectory;
        var resolvedLibrary = libraryPath ?? Path.Combine(root, "native", "$libraryFileName");
        _runtimePath = runtimePath ?? (BundledRuntimeFileName == null
            ? null
            : Path.Combine(root, "runtime", BundledRuntimeFileName));

        _libraryHandle = NativeLibrary.Load(resolvedLibrary);
        _abiVersion = Load<AbiVersionDelegate>("${runtimePrefix}_abi_version");
        _init = Load<InitDelegate>("${runtimePrefix}_init");
        _callJson = Load<CallJsonDelegate>("${runtimePrefix}_call_json");
        _callJsonBatch = Load<CallJsonBatchDelegate>("${runtimePrefix}_call_json_batch");
        _callJsonRaw = Load<CallJsonRawDelegate>("${runtimePrefix}_call_json_raw");
        _callI64_2 = Load<CallI64_2Delegate>("${runtimePrefix}_call_i64_2");
        _callI64_2Index = Load<CallI64_2IndexDelegate>("${runtimePrefix}_call_i64_2_index");
        _callI64_4 = Load<CallI64_4Delegate>("${runtimePrefix}_call_i64_4");
        _callI64_4Index = Load<CallI64_4IndexDelegate>("${runtimePrefix}_call_i64_4_index");
        _callF64_2 = Load<CallF64_2Delegate>("${runtimePrefix}_call_f64_2");
        _callF64_2Index = Load<CallF64_2IndexDelegate>("${runtimePrefix}_call_f64_2_index");
        _callF64_4 = Load<CallF64_4Delegate>("${runtimePrefix}_call_f64_4");
        _callF64_4Index = Load<CallF64_4IndexDelegate>("${runtimePrefix}_call_f64_4_index");
        _callBytes = Load<CallBytesDelegate>("${runtimePrefix}_call_bytes");
        _callBytesIndex = Load<CallBytesIndexDelegate>("${runtimePrefix}_call_bytes_index");
        _lastErrorCode = Load<LastErrorCodeDelegate>("${runtimePrefix}_last_error_code");
        _lastErrorJson = Load<LastErrorJsonDelegate>("${runtimePrefix}_last_error_json");
        _shutdown = Load<ShutdownDelegate>("${runtimePrefix}_shutdown");
        _stringFree = Load<StringFreeDelegate>("${runtimePrefix}_string_free");
        _bytesFree = Load<BytesFreeDelegate>("${runtimePrefix}_bytes_free");
    }

    public int AbiVersion()
    {
        EnsureNotDisposed();
        return _abiVersion();
    }

    public void Init(string? runtimePath = null)
    {
        EnsureNotDisposed();
        var resolvedRuntime = runtimePath ?? (_runtimePath != null && File.Exists(_runtimePath) ? _runtimePath : null);
        using var runtimeUtf8 = Utf8String.Allocate(resolvedRuntime);
        IntPtr errorPtr;
        var rc = _init(runtimeUtf8.Pointer, out errorPtr);
        if (rc != 0)
        {
            throw new InvalidOperationException(ConsumeError(errorPtr));
        }
    }

    public string CallJson(string method, string argsJson)
    {
        EnsureNotDisposed();
        using var methodUtf8 = Utf8String.Allocate(method);
        using var argsUtf8 = Utf8String.Allocate(argsJson);
        IntPtr resultPtr;
        IntPtr errorPtr;
        var rc = _callJson(methodUtf8.Pointer, argsUtf8.Pointer, out resultPtr, out errorPtr);
        if (rc != 0)
        {
            throw new InvalidOperationException(ConsumeError(errorPtr));
        }
        return ConsumeJsonResult(resultPtr, "call_json");
    }

    public string CallJsonBatch(string batchJson)
    {
        EnsureNotDisposed();
        using var batchUtf8 = Utf8String.Allocate(batchJson);
        IntPtr resultPtr;
        IntPtr errorPtr;
        var rc = _callJsonBatch(batchUtf8.Pointer, out resultPtr, out errorPtr);
        if (rc != 0)
        {
            throw new InvalidOperationException(ConsumeError(errorPtr));
        }
        return ConsumeJsonResult(resultPtr, "call_json_batch");
    }

    public string CallJsonRaw(string method, string argsJson)
    {
        EnsureNotDisposed();
        using var methodUtf8 = Utf8String.Allocate(method);
        using var argsUtf8 = Utf8String.Allocate(argsJson);
        IntPtr resultPtr;
        IntPtr errorPtr;
        var rc = _callJsonRaw(methodUtf8.Pointer, argsUtf8.Pointer, out resultPtr, out errorPtr);
        if (rc != 0)
        {
            throw new InvalidOperationException(ConsumeError(errorPtr));
        }
        return ConsumeJsonResult(resultPtr, "call_json_raw");
    }

    public long CallI64_2(string method, long a, long b)
    {
        EnsureNotDisposed();
        using var methodUtf8 = Utf8String.Allocate(method);
        long result;
        IntPtr errorPtr;
        var rc = _callI64_2(methodUtf8.Pointer, a, b, out result, out errorPtr);
        if (rc != 0)
        {
            throw new InvalidOperationException(ConsumeError(errorPtr));
        }
        return result;
    }

    public long CallI64_2Index(int methodId, long a, long b)
    {
        EnsureNotDisposed();
        long result;
        IntPtr errorPtr;
        var rc = _callI64_2Index(methodId, a, b, out result, out errorPtr);
        if (rc != 0)
        {
            throw new InvalidOperationException(ConsumeError(errorPtr));
        }
        return result;
    }

    public long CallI64_4(string method, long a, long b, long c, long d)
    {
        EnsureNotDisposed();
        using var methodUtf8 = Utf8String.Allocate(method);
        long result;
        IntPtr errorPtr;
        var rc = _callI64_4(methodUtf8.Pointer, a, b, c, d, out result, out errorPtr);
        if (rc != 0)
        {
            throw new InvalidOperationException(ConsumeError(errorPtr));
        }
        return result;
    }

    public long CallI64_4Index(int methodId, long a, long b, long c, long d)
    {
        EnsureNotDisposed();
        long result;
        IntPtr errorPtr;
        var rc = _callI64_4Index(methodId, a, b, c, d, out result, out errorPtr);
        if (rc != 0)
        {
            throw new InvalidOperationException(ConsumeError(errorPtr));
        }
        return result;
    }

    public double CallF64_2(string method, double a, double b)
    {
        EnsureNotDisposed();
        using var methodUtf8 = Utf8String.Allocate(method);
        double result;
        IntPtr errorPtr;
        var rc = _callF64_2(methodUtf8.Pointer, a, b, out result, out errorPtr);
        if (rc != 0)
        {
            throw new InvalidOperationException(ConsumeError(errorPtr));
        }
        return result;
    }

    public double CallF64_2Index(int methodId, double a, double b)
    {
        EnsureNotDisposed();
        double result;
        IntPtr errorPtr;
        var rc = _callF64_2Index(methodId, a, b, out result, out errorPtr);
        if (rc != 0)
        {
            throw new InvalidOperationException(ConsumeError(errorPtr));
        }
        return result;
    }

    public double CallF64_4(string method, double a, double b, double c, double d)
    {
        EnsureNotDisposed();
        using var methodUtf8 = Utf8String.Allocate(method);
        double result;
        IntPtr errorPtr;
        var rc = _callF64_4(methodUtf8.Pointer, a, b, c, d, out result, out errorPtr);
        if (rc != 0)
        {
            throw new InvalidOperationException(ConsumeError(errorPtr));
        }
        return result;
    }

    public double CallF64_4Index(int methodId, double a, double b, double c, double d)
    {
        EnsureNotDisposed();
        double result;
        IntPtr errorPtr;
        var rc = _callF64_4Index(methodId, a, b, c, d, out result, out errorPtr);
        if (rc != 0)
        {
            throw new InvalidOperationException(ConsumeError(errorPtr));
        }
        return result;
    }

    public byte[] CallBytes(string method, byte[]? args)
    {
        EnsureNotDisposed();
        using var methodUtf8 = Utf8String.Allocate(method);
        var payload = args ?? Array.Empty<byte>();
        IntPtr resultPtr;
        int resultLen;
        IntPtr errorPtr;
        var rc = _callBytes(
            methodUtf8.Pointer,
            payload,
            payload.Length,
            out resultPtr,
            out resultLen,
            out errorPtr);
        if (rc != 0)
        {
            throw new InvalidOperationException(ConsumeError(errorPtr));
        }
        return ConsumeBytesResult(resultPtr, resultLen, "call_bytes");
    }

    public byte[] CallBytesIndex(int methodId, byte[]? args)
    {
        EnsureNotDisposed();
        var payload = args ?? Array.Empty<byte>();
        IntPtr resultPtr;
        int resultLen;
        IntPtr errorPtr;
        var rc = _callBytesIndex(
            methodId,
            payload,
            payload.Length,
            out resultPtr,
            out resultLen,
            out errorPtr);
        if (rc != 0)
        {
            throw new InvalidOperationException(ConsumeError(errorPtr));
        }
        return ConsumeBytesResult(resultPtr, resultLen, "call_bytes_index");
    }

    public int LastErrorCode()
    {
        EnsureNotDisposed();
        return _lastErrorCode();
    }

    public string LastErrorJson()
    {
        EnsureNotDisposed();
        IntPtr errorJsonPtr;
        var rc = _lastErrorJson(out errorJsonPtr);
        if (rc != 0)
        {
            throw new InvalidOperationException("last_error_json failed");
        }
        return ConsumeJsonResult(errorJsonPtr, "last_error_json");
    }

    public void Shutdown()
    {
        if (_disposed)
        {
            return;
        }
        _shutdown();
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        try
        {
            _shutdown();
        }
        catch
        {
            // no-op during dispose
        }
        NativeLibrary.Free(_libraryHandle);
        _disposed = true;
    }

    private T Load<T>(string symbol) where T : Delegate
    {
        var fn = NativeLibrary.GetExport(_libraryHandle, symbol);
        return Marshal.GetDelegateForFunctionPointer<T>(fn);
    }

    private string ConsumeJsonResult(IntPtr resultPtr, string callName)
    {
        if (resultPtr == IntPtr.Zero)
        {
            throw new InvalidOperationException(callName + " returned null result");
        }
        var value = DecodeUtf8(resultPtr);
        _stringFree(resultPtr);
        return value;
    }

    private byte[] ConsumeBytesResult(IntPtr resultPtr, int resultLen, string callName)
    {
        if (resultLen < 0)
        {
            throw new InvalidOperationException(callName + " returned negative length");
        }
        if (resultLen == 0)
        {
            if (resultPtr != IntPtr.Zero)
            {
                _bytesFree(resultPtr);
            }
            return Array.Empty<byte>();
        }
        if (resultPtr == IntPtr.Zero)
        {
            throw new InvalidOperationException(callName + " returned null pointer with non-zero length");
        }

        var managed = new byte[resultLen];
        try
        {
            Marshal.Copy(resultPtr, managed, 0, resultLen);
        }
        finally
        {
            _bytesFree(resultPtr);
        }
        return managed;
    }

    private string ConsumeError(IntPtr errorPtr)
    {
        if (errorPtr == IntPtr.Zero)
        {
            return "Unknown dllart error";
        }
        var message = DecodeUtf8(errorPtr);
        if (message.Length == 0)
        {
            message = "Unknown dllart error";
        }
        _stringFree(errorPtr);
        return message;
    }

    private static string DecodeUtf8(IntPtr ptr)
    {
        if (ptr == IntPtr.Zero)
        {
            return string.Empty;
        }

        var length = 0;
        while (Marshal.ReadByte(ptr, length) != 0)
        {
            length++;
        }
        if (length == 0)
        {
            return string.Empty;
        }

        var bytes = new byte[length];
        Marshal.Copy(ptr, bytes, 0, length);
        return Encoding.UTF8.GetString(bytes);
    }

    private void EnsureNotDisposed()
    {
        if (_disposed)
        {
            throw new ObjectDisposedException(nameof($className));
        }
    }

    private sealed class Utf8String : IDisposable
    {
        public IntPtr Pointer { get; private set; }

        private Utf8String(IntPtr pointer)
        {
            Pointer = pointer;
        }

        public static Utf8String Allocate(string? value)
        {
            if (value == null)
            {
                return new Utf8String(IntPtr.Zero);
            }
            var bytes = Encoding.UTF8.GetBytes(value);
            var memory = Marshal.AllocHGlobal(bytes.Length + 1);
            Marshal.Copy(bytes, 0, memory, bytes.Length);
            Marshal.WriteByte(memory, bytes.Length, 0);
            return new Utf8String(memory);
        }

        public void Dispose()
        {
            if (Pointer != IntPtr.Zero)
            {
                Marshal.FreeHGlobal(Pointer);
                Pointer = IntPtr.Zero;
            }
        }
    }
}
''';
}

String _generateCSharpExample({required String moduleName}) {
  final className = '${_upperCamelCase(moduleName)}Client';
  return '''using System;

internal static class Program
{
    private static void Main()
    {
        using var mod = new $className();
        mod.Init();
        Console.WriteLine(mod.CallJson("add", "{\\"a\\":20,\\"b\\":22}"));
        Console.WriteLine(mod.CallI64_2("add_fast", 20, 22));
        mod.Shutdown();
    }
}
''';
}

String _generateCSharpProject({required String moduleName}) {
  return '''<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>
</Project>
''';
}

String _generateCSharpPackageReadme({required String moduleName}) {
  return '''# C# scaffold for $moduleName

Generated by `dllart package csharp`.

Files:

- `DllartClient.cs` — P/Invoke wrapper for core dllart calls.
- `Program.cs` — runnable console example.
- `DllartScaffold.csproj` — .NET project file.
- `native/` — host library artifact.
- `runtime/` — optional bundled runtime copy.
- `${moduleName}_api.h` — generated C API header.
- `artifact.json` — copied dllart manifest.

Run:

```bash
dotnet run --project DllartScaffold.csproj
```
''';
}

String _generateAndroidPackageReadme({required String moduleName}) {
  return '''# Android package scaffold for $moduleName

Generated by `dllart package android`.

This folder is ready for Android integration, but it still needs Android-specific binaries:

1. Build `lib$moduleName.so` for each ABI (`arm64-v8a`, `armeabi-v7a`, `x86_64`).
2. Copy each binary to `jniLibs/<abi>/lib$moduleName.so`.
3. Include `CMakeLists.txt` in your Android native build and link `${moduleName}`.

Files:

- `include/${moduleName}_api.h` — generated C API header.
- `CMakeLists.txt` — imported prebuilt library target.
- `build.gradle.snippet` — Gradle sourceSets/externalNativeBuild snippet.
- `jniLibs/` — ABI folders for Android `.so` files.
''';
}

String _generateAndroidCMakeTemplate({required String moduleName}) {
  return '''cmake_minimum_required(VERSION 3.10)
project(dllart_${moduleName} C)

add_library($moduleName SHARED IMPORTED GLOBAL)
set_target_properties($moduleName PROPERTIES
  IMPORTED_LOCATION "\${CMAKE_CURRENT_LIST_DIR}/jniLibs/\${ANDROID_ABI}/lib$moduleName.so"
  INTERFACE_INCLUDE_DIRECTORIES "\${CMAKE_CURRENT_LIST_DIR}/include"
)

# Example:
# target_link_libraries(your_target PRIVATE $moduleName)
''';
}

String _generateAndroidGradleSnippet({required String moduleName}) {
  return '''android {
  sourceSets {
    main {
      jniLibs.srcDirs += ['src/main/jniLibs']
    }
  }
}

// CMake example:
// target_link_libraries(your_target PRIVATE $moduleName)
''';
}

String _generateIosPackageReadme({required String moduleName}) {
  return '''# iOS package scaffold for $moduleName

Generated by `dllart package ios`.

This folder is ready for iOS integration, but it still needs iOS-specific binaries:

1. Build iOS device and simulator binaries for `$moduleName`.
2. Produce `Frameworks/$moduleName.xcframework`.
3. Add the xcframework to Xcode, and expose headers from `Headers/`.

Files:

- `Headers/${moduleName}_api.h` — generated C API header.
- `module.modulemap` — module map for C import.
- `${moduleName}_dllart.podspec` — CocoaPods template.
- `Frameworks/` — place `${moduleName}.xcframework` here.
''';
}

String _generateIosModuleMap({
  required String moduleName,
  required String headerName,
}) {
  final safeModule = _sanitizeForC(moduleName);
  return '''module $safeModule {
  header "Headers/$headerName"
  export *
}
''';
}

String _generateIosPodspec({required String moduleName}) {
  final podName = 'Dllart${_upperCamelCase(moduleName)}';
  return '''Pod::Spec.new do |s|
  s.name             = '$podName'
  s.version          = '0.1.0'
  s.summary          = 'Generated DLLART iOS package for $moduleName'
  s.description      = 'Prebuilt iOS framework wrapper for dllart module $moduleName.'
  s.homepage         = 'https://example.invalid/dllart'
  s.license          = { :type => 'MIT' }
  s.author           = { 'dllart' => 'noreply@example.invalid' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '12.0'
  s.vendored_frameworks = 'Frameworks/$moduleName.xcframework'
  s.public_header_files = 'Headers/*.h'
  s.source_files        = 'Headers/*.h'
  s.module_map          = 'module.modulemap'
end
''';
}

String _generateFuchsiaPackageReadme({required String moduleName}) {
  return '''# Fuchsia package scaffold for $moduleName

Generated by `dllart package fuchsia`.

This folder is a Fuchsia integration scaffold:

1. Build Fuchsia-compatible library binary for `$moduleName`.
2. Place binary artifact(s) in `lib/`.
3. Use `BUILD.gn.snippet` as a starting point in your GN build graph.

Files:

- `include/${moduleName}_api.h` — generated C API header.
- `BUILD.gn.snippet` — GN target template.
- `lib/` — place Fuchsia binary artifacts.
''';
}

String _generateFuchsiaBuildGnSnippet({required String moduleName}) {
  return '''# Example GN snippet for dllart module $moduleName
import("//build/config.gni")

source_set("${moduleName}_headers") {
  public = [ "include/${moduleName}_api.h" ]
  include_dirs = [ "include" ]
}

# Add your prebuilt/native target here and depend on :${moduleName}_headers.
''';
}

String _upperCamelCase(String value) {
  final chunks = value
      .split(RegExp(r'[^A-Za-z0-9]+'))
      .where((chunk) => chunk.isNotEmpty)
      .toList();
  if (chunks.isEmpty) {
    return 'Module';
  }
  return chunks
      .map(
        (chunk) =>
            '${chunk[0].toUpperCase()}${chunk.substring(1).toLowerCase()}',
      )
      .join();
}
