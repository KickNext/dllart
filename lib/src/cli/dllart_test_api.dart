part of dllart_cli;

/// Test-oriented facade for internal CLI helpers.
///
/// Kept in `src` so production API surface stays minimal,
/// while unit tests can validate parser/config/codegen behavior directly.
class DllartCliTestApi {
  const DllartCliTestApi._();

  static String canonicalCommand(String command) => _canonicalCommand(command);

  static List<String> commandNames() {
    return _commandSpecs.map((spec) => spec.name).toList(growable: false);
  }

  static ParsedArgs parseArgs(List<String> args) => _parseArgs(args);

  static void validateCommandArgs(String command, ParsedArgs args) {
    _validateCommandArgs(command, args);
  }

  static Set<String> allowedOptionsForCommand(String command) {
    return _allowedOptionsForCommand(command);
  }

  static int maxPositionalArgsForCommand(String command) {
    return _maxPositionalArgsForCommand(command);
  }

  static String normalizePackageName(String raw) => _normalizePackageName(raw);

  static String resolvePackageTarget(ParsedArgs args) {
    return _resolvePackageTarget(args);
  }

  static String sanitizeForC(String value) => _sanitizeForC(value);

  static String moduleRuntimePrefix(String moduleName) {
    return _moduleRuntimePrefix(moduleName);
  }

  static String hostTargetId() => _hostTargetId();

  static String runtimeExecutableNameForHost() =>
      _runtimeExecutableNameForHost();

  static String outputLibraryPath(String outputPath, String moduleName) {
    return _outputLibraryPath(outputPath, moduleName);
  }

  static String? libraryPathFromManifest(String manifestPath) {
    return _libraryPathFromManifest(manifestPath);
  }

  static List<ExportedFunction> discoverExports(String sourceCode) {
    return _discoverExports(sourceCode);
  }

  static Map<String, int> computeI64_2MethodIds(
    List<ExportedFunction> exports,
  ) {
    return _computeI64_2MethodIds(exports);
  }

  static Map<String, int> computeI64_4MethodIds(
    List<ExportedFunction> exports,
  ) {
    return _computeI64_4MethodIds(exports);
  }

  static Map<String, int> computeF64_2MethodIds(
    List<ExportedFunction> exports,
  ) {
    return _computeF64_2MethodIds(exports);
  }

  static Map<String, int> computeF64_4MethodIds(
    List<ExportedFunction> exports,
  ) {
    return _computeF64_4MethodIds(exports);
  }

  static Map<String, int> computeBytesMethodIds(
    List<ExportedFunction> exports,
  ) {
    return _computeBytesMethodIds(exports);
  }

  static String generateEntrypoint(
    String sourcePath,
    List<ExportedFunction> exports,
  ) {
    return _generateEntrypoint(sourcePath, exports);
  }

  static String generateApiHeader(
    String moduleName,
    List<ExportedFunction> exports,
  ) {
    return _generateApiHeader(moduleName, exports);
  }

  static String generateCMakeConfig({
    required String moduleName,
    required String libraryFileName,
  }) {
    return _generateCMakeConfig(
      moduleName: moduleName,
      libraryFileName: libraryFileName,
    );
  }

  static String generatePkgConfig({required String moduleName}) {
    return _generatePkgConfig(moduleName: moduleName);
  }

  static String generateWorkflowYaml(
    LoadedConfig loaded, {
    String? baseDir,
    bool useGlobalTool = false,
  }) {
    return _generateWorkflowYaml(
      loaded,
      baseDir: baseDir,
      useGlobalTool: useGlobalTool,
    );
  }

  static LoadedConfig? inferConfigFromCurrentDirectory() {
    return _inferConfigFromCurrentDirectory();
  }

  static String? findNearestPubspecDir(String startPath) {
    return _findNearestPubspecDir(startPath);
  }

  static String displayPath(String absolutePath) => _displayPath(absolutePath);

  static String escapeCString(String value) => _escapeCString(value);

  static String escapeDartSingleQuoted(String value) {
    return _escapeDartSingleQuoted(value);
  }

  static String asText(Object? value) => _asText(value);

  static String? firstNonEmptyLine(String text) => _firstNonEmptyLine(text);

  static String processFailureSummary(
    String commandLabel,
    ProcessResult result,
  ) {
    return _processFailureSummary(commandLabel, result);
  }

  static Future<void> runCommand(
    String executable,
    List<String> args, {
    String? workingDirectory,
  }) {
    return _runCommand(executable, args, workingDirectory: workingDirectory);
  }

  static Future<void> runCommandInJsonMode(
    String executable,
    List<String> args, {
    String? workingDirectory,
  }) async {
    final previous = _activeOutputMode;
    _activeOutputMode = _CliOutputMode.json;
    try {
      await _runCommand(executable, args, workingDirectory: workingDirectory);
    } finally {
      _activeOutputMode = previous;
    }
  }

  static Future<String?> ensurePackageConfig({
    required String sourcePath,
    required String configDir,
  }) {
    return _ensurePackageConfig(sourcePath: sourcePath, configDir: configDir);
  }

  static String? findNearestPackageConfig(String startPath) {
    return _findNearestPackageConfig(startPath);
  }

  static String? dllartRootFromPackageConfig(String packageConfigPath) {
    return _dllartRootFromPackageConfig(packageConfigPath);
  }

  static String? resolvePackageRootUriPath(
    String packageConfigPath,
    String rootUriText,
  ) {
    return _resolvePackageRootUriPath(packageConfigPath, rootUriText);
  }

  static String toolRoot({String? packageConfigPath}) {
    return _toolRoot(packageConfigPath: packageConfigPath);
  }

  static void cleanupLegacyArtifacts(String outputPath, String moduleName) {
    _cleanupLegacyArtifacts(outputPath, moduleName);
  }

  static Map<String, Object?> readArtifactManifestMap(String manifestPath) {
    return _readArtifactManifestMap(manifestPath);
  }

  static String generateFlutterMethodIdConstants(
    Map<String, Object?> manifest,
  ) {
    return _generateFlutterMethodIdConstants(manifest);
  }

  static String sanitizeForDartConst(String value) {
    return _sanitizeForDartConst(value);
  }

  static String defaultProtocExecutableName() {
    return _defaultProtocExecutableName();
  }

  static LoadedConfig? loadConfigForProto(ParsedArgs args) {
    return _loadConfigForProto(args);
  }

  static Map<String, Object?> resolveProtoGenerationForTesting(
    ParsedArgs args,
    LoadedConfig? loaded,
  ) {
    final resolved = _resolveProtoGeneration(args, loaded);
    return <String, Object?>{
      'proto_path': resolved.protoPath,
      'out_dir': resolved.outDir,
      'include_dirs': List<String>.from(resolved.includeDirs),
      'grpc': resolved.grpc,
      'protoc': resolved.protocExecutable,
      'protoc_gen_dart': resolved.protocPluginExecutable,
      'config_path': resolved.configPath,
    };
  }

  static List<String> buildProtocArgsForTesting(Map<String, Object?> resolved) {
    return _buildProtocArgs(
      _ResolvedProtoGeneration(
        protoPath: resolved['proto_path'] as String,
        outDir: resolved['out_dir'] as String,
        includeDirs: List<String>.from(resolved['include_dirs'] as List),
        grpc: resolved['grpc'] as bool,
        protocExecutable: resolved['protoc'] as String,
        protocPluginExecutable: resolved['protoc_gen_dart'] as String,
        configPath: resolved['config_path'] as String?,
      ),
    );
  }

  static List<String> collectGeneratedProtoFiles(String outDir) {
    return _collectGeneratedProtoFiles(outDir);
  }

  static String resolveProtocExecutable(String baseDir, String raw) {
    return _resolveProtocExecutable(baseDir, raw);
  }

  static String resolveProtocDartPluginExecutable() {
    return _resolveProtocDartPluginExecutable();
  }

  static String? inferProtoSource(String baseDir, {String? moduleName}) {
    return _inferProtoSource(baseDir, moduleName: moduleName);
  }

  static List<String> findProtoSourcesUnder(String rootPath) {
    return _findProtoSourcesUnder(rootPath);
  }

  static String resolvePathFromBase(String baseDir, String rawPath) {
    return _resolvePathFromBase(baseDir, rawPath);
  }

  static List<String> parsePathList(String raw) {
    return _parsePathList(raw);
  }

  static String? firstNonEmpty(List<String?> values) {
    return _firstNonEmpty(values);
  }

  static Future<void> appendProtobufDoctorChecks(
    DoctorReport report,
    LoadedConfig loaded,
  ) {
    return _appendProtobufDoctorChecks(report, loaded);
  }

  static String? selectInferredSource(String libDirPath) {
    return _selectInferredSource(Directory(libDirPath));
  }

  static List<int> configLocationFromOffset(String text, int offset) {
    final location = _ConfigTextLocator(text).fromOffset(offset);
    return <int>[location.line, location.column];
  }

  static List<int>? configLocationForField(String text, String field) {
    final location = _ConfigTextLocator(text).keyLocation(field);
    if (location == null) {
      return null;
    }
    return <int>[location.line, location.column];
  }

  static String configErrorPrefix(String configPath, {int? line, int? column}) {
    final location = line == null ? null : _TextLocation(line, column ?? 1);
    return _configErrorPrefix(configPath, location: location);
  }

  static int lineNumberAt(String source, int offset) {
    return _lineNumberAt(source, offset);
  }

  static List<Map<String, Object?>> parseAbiContractExportsForTesting(
    List<dynamic> rawList,
  ) {
    return _parseAbiContractExports(rawList)
        .map(
          (item) => <String, Object?>{
            'name': item.name,
            'arity': item.arity,
            'supports_i64_2': item.supportsI64_2,
            'i64_2_method_id': item.i64_2MethodId,
            'supports_i64_4': item.supportsI64_4,
            'i64_4_method_id': item.i64_4MethodId,
            'supports_f64_2': item.supportsF64_2,
            'f64_2_method_id': item.f64_2MethodId,
            'supports_f64_4': item.supportsF64_4,
            'f64_4_method_id': item.f64_4MethodId,
            'supports_bytes': item.supportsBytes,
            'bytes_method_id': item.bytesMethodId,
          },
        )
        .toList(growable: false);
  }

  static int? toIntForTesting(Object? value) => _toInt(value);

  static String prependLibrarySearchPath(String dir, String? existing) {
    return _prependLibrarySearchPath(dir, existing);
  }

  static String generateAbiContractCTestForTesting({
    required String moduleName,
    required String modulePrefix,
    required List<Map<String, Object?>> exports,
    int expectedAbiMajor = 1,
  }) {
    final parsed = exports
        .map(
          (item) => _AbiContractExport(
            name: item['name'] as String,
            arity: item['arity'] as int,
            supportsI64_2: item['supports_i64_2'] == true,
            i64_2MethodId: item['i64_2_method_id'] as int?,
            supportsI64_4: item['supports_i64_4'] == true,
            i64_4MethodId: item['i64_4_method_id'] as int?,
            supportsF64_2: item['supports_f64_2'] == true,
            f64_2MethodId: item['f64_2_method_id'] as int?,
            supportsF64_4: item['supports_f64_4'] == true,
            f64_4MethodId: item['f64_4_method_id'] as int?,
            supportsBytes: item['supports_bytes'] == true,
            bytesMethodId: item['bytes_method_id'] as int?,
          ),
        )
        .toList(growable: false);
    return _generateAbiContractCTest(
      moduleName: moduleName,
      modulePrefix: modulePrefix,
      exports: parsed,
      expectedAbiMajor: expectedAbiMajor,
    );
  }

  static Future<Map<String, Object?>> runAbiContractTestForTesting(
    LoadedConfig loaded,
  ) async {
    final result = await _runAbiContractTest(loaded);
    return <String, Object?>{'ok': result.ok, ...result.data};
  }

  static void writeJsonCommandResultForTesting(
    String command, {
    required bool ok,
    String? status,
    int? exitCode,
    Map<String, Object?>? data,
    Map<String, Object?>? error,
  }) {
    _writeJsonCommandResult(
      command,
      ok: ok,
      status: status,
      exitCode: exitCode,
      data: data,
      error: error,
    );
  }

  static Future<void> runCli(List<String> args) => runDllartCli(args);

  static Future<int> runCliForTesting(List<String> args) {
    return runDllartCliForTesting(args);
  }

  static Future<void> commandCreate(ParsedArgs args) => _commandCreate(args);

  static Future<void> commandInit(ParsedArgs args) => _commandInit(args);

  static Future<void> commandBuild(ParsedArgs args) => _commandBuild(args);

  static Future<void> commandMake(ParsedArgs args) => _commandMake(args);

  static Future<void> commandPackage(ParsedArgs args) => _commandPackage(args);

  static Future<void> commandProto(ParsedArgs args) => _commandProto(args);

  static Future<void> commandIntegrate(ParsedArgs args) {
    return _commandIntegrate(args);
  }

  static Future<void> commandWorkflow(ParsedArgs args) =>
      _commandWorkflow(args);

  static Future<void> commandDoctor(ParsedArgs args) => _commandDoctor(args);

  static Future<void> commandVerify(ParsedArgs args) => _commandVerify(args);

  static Future<void> commandTest(ParsedArgs args) => _commandTest(args);

  static LoadedConfig loadConfig(ParsedArgs args, {bool allowInferred = true}) {
    return _loadConfig(args, allowInferred: allowInferred);
  }
}
