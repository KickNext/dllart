part of dllart_cli;

typedef _CommandRunner = Future<void> Function(ParsedArgs args);

enum _CliOutputMode { text, json }

enum _CliLogFormat { text, json }

enum _CliLogLevel { error, warn, info }

_CliOutputMode _activeOutputMode = _CliOutputMode.text;
_CliLogFormat _activeLogFormat = _CliLogFormat.text;
_CliLogLevel _activeLogLevel = _CliLogLevel.info;
bool _cliVerboseEnabled = false;

bool _isJsonMode(ParsedArgs args) => args.hasFlag('json');

bool get _inJsonMode => _activeOutputMode == _CliOutputMode.json;
bool get _inVerboseMode => _cliVerboseEnabled;

void _setCliVerboseMode(bool enabled) {
  _cliVerboseEnabled = enabled;
}

void _resetCliLogConfig() {
  _activeLogFormat = _CliLogFormat.text;
  _activeLogLevel = _CliLogLevel.info;
}

void _configureCliLogConfig(DllartLoggingConfig? logging) {
  if (logging == null) {
    _resetCliLogConfig();
    return;
  }

  _activeLogFormat = logging.format == 'json'
      ? _CliLogFormat.json
      : _CliLogFormat.text;
  _activeLogLevel = switch (logging.level) {
    'error' => _CliLogLevel.error,
    'warn' => _CliLogLevel.warn,
    _ => _CliLogLevel.info,
  };
}

void _applyLoggingFromConfig(DllartConfig? config) {
  _configureCliLogConfig(config?.logging);
}

int _cliLogPriority(_CliLogLevel level) {
  return switch (level) {
    _CliLogLevel.error => 0,
    _CliLogLevel.warn => 1,
    _CliLogLevel.info => 2,
  };
}

String _cliLogLevelName(_CliLogLevel level) {
  return switch (level) {
    _CliLogLevel.error => 'error',
    _CliLogLevel.warn => 'warn',
    _CliLogLevel.info => 'info',
  };
}

void _logMessage(_CliLogLevel level, String message) {
  if (_inJsonMode) {
    return;
  }
  if (_cliLogPriority(level) > _cliLogPriority(_activeLogLevel)) {
    return;
  }

  if (_activeLogFormat == _CliLogFormat.json) {
    stdout.writeln(
      jsonEncode(<String, Object?>{
        'level': _cliLogLevelName(level),
        'message': message,
      }),
    );
    return;
  }

  stdout.writeln(message);
}

void _logLine(String line, {bool verboseOnly = true}) {
  if (verboseOnly && !_inVerboseMode) {
    return;
  }
  _logMessage(_CliLogLevel.info, line);
}

void _writeJsonPayload(Map<String, Object?> payload) {
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(payload));
}

void _writeJsonCommandResult(
  String command, {
  required bool ok,
  String? status,
  int? exitCode,
  Map<String, Object?>? data,
  Map<String, Object?>? error,
}) {
  final payload = <String, Object?>{
    'ok': ok,
    'command': command,
    if (status != null) 'status': status,
    if (exitCode != null) 'exit_code': exitCode,
    if (data != null) 'data': data,
    if (error != null) 'error': error,
  };
  _writeJsonPayload(payload);
}

class _CliCommandSpec {
  const _CliCommandSpec({
    required this.name,
    required this.help,
    required this.allowedOptions,
    required this.maxPositionalArgs,
    required this.runner,
    this.aliases = const <String>[],
  });

  final String name;
  final List<String> aliases;
  final String help;
  final Set<String> allowedOptions;
  final int maxPositionalArgs;
  final _CommandRunner runner;
}

final List<_CliCommandSpec> _commandSpecs = <_CliCommandSpec>[
  _CliCommandSpec(
    name: 'create',
    aliases: <String>['new'],
    help: '''
Usage:
  dart run dllart create [project_path] [--name=<module>] [--path=<dir>] [--dependency=<auto|version|path>] [--dllart-path=<dir>] [--local-path-dependency] [--force]

Notes:
  - If both positional path and --path are provided, --path wins.
  - `--dependency=auto` uses path dependency for local checkout installs
    and version dependency for pub-cache/global installs.
  - `--local-path-dependency` is a compatibility alias for `--dependency=path`.
  - `new` is an alias for `create`.
''',
    allowedOptions: <String>{
      'path',
      'name',
      'dependency',
      'dllart-path',
      'local-path-dependency',
      'force',
      'help',
    },
    maxPositionalArgs: 1,
    runner: _commandCreate,
  ),
  _CliCommandSpec(
    name: 'init',
    help: '''
Usage:
  dart run dllart init [--name=<module>] [--source=<path>] [--output=<dir>] [--config=<path>] [--force]
''',
    allowedOptions: <String>{
      'name',
      'source',
      'output',
      'config',
      'force',
      'help',
    },
    maxPositionalArgs: 0,
    runner: _commandInit,
  ),
  _CliCommandSpec(
    name: 'build',
    help: '''
Usage:
  dart run dllart build [--config=<path>] [--target=<host|android|ios>] [--runtime-profile=<full|slim>] [--android-abis=<a,b,c>] [--ios-variants=<all|device|simulator>] [--json] [--verbose]
  dart run dllart build --name=<module> --source=<path> [--output=<dir>] [--target=<host|android|ios>] [--runtime-profile=<full|slim>] [--android-abis=<a,b,c>] [--ios-variants=<all|device|simulator>] [--json] [--verbose]
''',
    allowedOptions: <String>{
      'name',
      'source',
      'output',
      'config',
      'target',
      'runtime-profile',
      'android-abis',
      'ios-variants',
      'json',
      'verbose',
      'help',
    },
    maxPositionalArgs: 0,
    runner: _commandBuild,
  ),
  _CliCommandSpec(
    name: 'make',
    help: '''
Usage:
  dart run dllart make [--config=<path>] [--target=<host|android|ios>] [--runtime-profile=<full|slim>] [--android-abis=<a,b,c>] [--ios-variants=<all|device|simulator>] [--verbose]
  dart run dllart make --name=<module> --source=<path> [--output=<dir>] [--target=<host|android|ios>] [--runtime-profile=<full|slim>] [--android-abis=<a,b,c>] [--ios-variants=<all|device|simulator>] [--verbose]
''',
    allowedOptions: <String>{
      'name',
      'source',
      'output',
      'config',
      'target',
      'runtime-profile',
      'android-abis',
      'ios-variants',
      'verbose',
      'help',
    },
    maxPositionalArgs: 0,
    runner: _commandMake,
  ),
  _CliCommandSpec(
    name: 'package',
    help: '''
Usage:
  dart run dllart package [target] [--target=<name>] [--config=<path>] [--auto-build] [--android-abis=<a,b,c>] [--ios-variants=<all|device|simulator>] [--force] [--verbose]

Targets:
  android | ios | fuchsia | flutter | python | csharp | all

Notes:
  - `package all` preflights host/mobile artifacts first.
  - Use `--auto-build` to build missing host/android/ios prerequisites.
''',
    allowedOptions: <String>{
      'name',
      'source',
      'output',
      'config',
      'target',
      'auto-build',
      'android-abis',
      'ios-variants',
      'force',
      'verbose',
      'help',
    },
    maxPositionalArgs: 1,
    runner: _commandPackage,
  ),
  _CliCommandSpec(
    name: 'proto',
    help: '''
Usage:
  dart run dllart proto [proto_path] [--config=<path>] [--proto=<path>] [--out=<dir>] [--include=<a,b,c>] [--grpc] [--protoc=<path>] [--json]

Notes:
  - `proto_path` is a shorthand for `--proto`.
  - If proto source is omitted, uses `protobuf.proto` from config.
  - If config is absent, tries to auto-detect a single file under `./proto`.
  - If --out is omitted, uses `protobuf.out` from config (default: lib/generated/proto).
  - --include accepts comma-separated include roots for protoc imports.
''',
    allowedOptions: <String>{
      'config',
      'proto',
      'out',
      'include',
      'grpc',
      'protoc',
      'json',
      'help',
    },
    maxPositionalArgs: 1,
    runner: _commandProto,
  ),
  _CliCommandSpec(
    name: 'workflow',
    help: '''
Usage:
  dart run dllart workflow [--config=<path>] [--output=<path>] [--global-tool|--local-tool] [--force]
''',
    allowedOptions: <String>{
      'config',
      'output',
      'global-tool',
      'local-tool',
      'force',
      'help',
    },
    maxPositionalArgs: 0,
    runner: _commandWorkflow,
  ),
  _CliCommandSpec(
    name: 'integrate',
    help: '''
Usage:
  dart run dllart integrate [--config=<path>] [--json] [--verbose]
''',
    allowedOptions: <String>{
      'name',
      'source',
      'output',
      'config',
      'json',
      'verbose',
      'help',
    },
    maxPositionalArgs: 0,
    runner: _commandIntegrate,
  ),
  _CliCommandSpec(
    name: 'doctor',
    aliases: <String>['check'],
    help: '''
Usage:
  dart run dllart doctor [--config=<path>] [--fix] [--package-target=<python|csharp|android|ios|flutter|all>] [--json] [--verbose]
  dart run dllart doctor --name=<module> --source=<path> [--output=<dir>] [--fix] [--package-target=<python|csharp|android|ios|flutter|all>] [--json] [--verbose]

Note:
  `check` is an alias for `doctor`.
''',
    allowedOptions: <String>{
      'name',
      'source',
      'output',
      'config',
      'fix',
      'package-target',
      'json',
      'verbose',
      'help',
    },
    maxPositionalArgs: 0,
    runner: _commandDoctor,
  ),
  _CliCommandSpec(
    name: 'verify',
    help: '''
Usage:
  dart run dllart verify [--config=<path>] [--target=<c|python|csharp|all>] [--json] [--verbose]
''',
    allowedOptions: <String>{'config', 'target', 'json', 'verbose', 'help'},
    maxPositionalArgs: 0,
    runner: _commandVerify,
  ),
  _CliCommandSpec(
    name: 'test',
    help: '''
Usage:
  dart run dllart test [--config=<path>] [--skip-build] [--perf-gate] [--json]
  dart run dllart test --name=<module> --source=<path> [--output=<dir>] [--skip-build] [--perf-gate] [--json]
''',
    allowedOptions: <String>{
      'name',
      'source',
      'output',
      'config',
      'skip-build',
      'perf-gate',
      'json',
      'help',
    },
    maxPositionalArgs: 0,
    runner: _commandTest,
  ),
  _CliCommandSpec(
    name: 'build-all',
    help: '''
Usage:
  dart run dllart build-all [--config=<path>] [--target=<host|android|ios>] [--runtime-profile=<full|slim>] [--android-abis=<a,b,c>] [--ios-variants=<all|device|simulator>] [--force] [--global-tool|--local-tool] [--verbose]
''',
    allowedOptions: <String>{
      'name',
      'source',
      'output',
      'config',
      'target',
      'runtime-profile',
      'android-abis',
      'ios-variants',
      'global-tool',
      'local-tool',
      'force',
      'verbose',
      'help',
    },
    maxPositionalArgs: 0,
    runner: _commandBuildAll,
  ),
];

final Map<String, _CliCommandSpec> _commandSpecsByName =
    <String, _CliCommandSpec>{
      for (final spec in _commandSpecs) spec.name: spec,
    };

final Map<String, String> _commandAliases = <String, String>{
  for (final spec in _commandSpecs)
    for (final alias in spec.aliases) alias: spec.name,
};

_CliCommandSpec _commandSpec(String command) {
  final canonical = _canonicalCommand(command);
  final spec = _commandSpecsByName[canonical];
  if (spec == null) {
    throw ToolError('Unknown command: $command');
  }
  return spec;
}

Future<void> _commandBuildAll(ParsedArgs args) async {
  await _commandBuild(args);
  await _commandWorkflow(args);
  _logLine('Build completed and workflow updated for all platforms.');
}
