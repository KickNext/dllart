part of dllart_cli;

Future<void> runDllartCli(List<String> args) async {
  final code = await runDllartCliForTesting(args);
  if (code != 0) {
    exit(code);
  }
}

Future<int> runDllartCliForTesting(List<String> args) async {
  exitCode = 0;
  _activeOutputMode = _CliOutputMode.text;
  _resetCliLogConfig();
  _setCliVerboseMode(false);

  String? activeCommand;
  try {
    if (args.isEmpty || args.first == '--help') {
      _printUsage();
      return 0;
    }

    if (args.first == 'help') {
      if (args.length > 1) {
        _printCommandHelp(args[1]);
      } else {
        _printUsage();
      }
      return 0;
    }

    final spec = _commandSpec(args.first);
    final parsed = _parseArgs(args.sublist(1));

    activeCommand = spec.name;
    _activeOutputMode = _isJsonMode(parsed)
        ? _CliOutputMode.json
        : _CliOutputMode.text;
    _setCliVerboseMode(parsed.hasFlag('verbose'));

    if (parsed.hasFlag('help')) {
      _printCommandHelp(spec.name);
      return 0;
    }

    _validateCommandArgs(spec.name, parsed);
    await spec.runner(parsed);
    return exitCode;
  } on ToolError catch (error) {
    if (_inJsonMode) {
      _writeJsonCommandResult(
        activeCommand ?? 'unknown',
        ok: false,
        status: 'error',
        exitCode: 2,
        error: <String, Object?>{'type': 'ToolError', 'message': error.message},
      );
    } else {
      stderr.writeln('Error: ${error.message}');
    }
    return 2;
  } on ProcessException catch (error) {
    if (_inJsonMode) {
      _writeJsonCommandResult(
        activeCommand ?? 'unknown',
        ok: false,
        status: 'error',
        exitCode: 3,
        error: <String, Object?>{
          'type': 'ProcessException',
          'message': error.message,
        },
      );
    } else {
      stderr.writeln('Process failed: ${error.message}');
    }
    return 3;
  } finally {
    _activeOutputMode = _CliOutputMode.text;
    _setCliVerboseMode(false);
    _resetCliLogConfig();
  }
}

String _canonicalCommand(String command) {
  return _commandAliases[command] ?? command;
}

void _printUsage() {
  stdout.writeln('''
DLLART - Dart to native FFI library toolchain

Usage:
  dart run dllart <command> [command options]

Commands:
  help       Show command help (`dllart help <command>`).
  create     Create a new dllart project scaffold.
  new        Alias for `create`.
  init       Create dllart.json and scaffold Dart module.
  build      Generate dispatch + headers and build target artifacts.
  make       doctor + build + integrate (one command).
  package    Generate Android/iOS/Fuchsia/Flutter/Python/C# package scaffold.
  proto      Generate Dart protobuf files via protoc.
  workflow   Generate GitHub Actions workflow for macOS/Linux/Windows builds.
  integrate  Print ready-to-copy integration snippets for produced artifacts.
  doctor     Validate toolchain, config, exports, and build prerequisites.
  verify     Run integration smoke checks for C/Python/C# outputs.
  test       Run ABI contract checks (JSON wrapper/raw + typed dispatch paths).
  check      Alias for `doctor`.
  build-all  build + workflow.

Run `dllart help <command>` for command-specific flags and examples.

Simple flow:
  dart run dllart create my_module
  cd my_module
  dllart doctor
  dllart build
  dllart integrate
''');
}

void _printCommandHelp(String command) {
  final spec = _commandSpec(command);
  stdout.writeln(spec.help.trimRight());
}

void _validateCommandArgs(String command, ParsedArgs args) {
  final allowedOptions = _allowedOptionsForCommand(command);
  final unknownOptions =
      args.options.keys.where((key) => !allowedOptions.contains(key)).toList()
        ..sort();
  if (unknownOptions.isNotEmpty) {
    final rendered = unknownOptions.map((key) => '--$key').join(', ');
    throw ToolError(
      'Unknown option(s) for `$command`: $rendered. Use `dllart help $command`.',
    );
  }

  final maxPositional = _maxPositionalArgsForCommand(command);
  if (args.positional.length > maxPositional) {
    throw ToolError(
      '`$command` accepts at most $maxPositional positional argument(s), '
      'received ${args.positional.length}. Use `dllart help $command`.',
    );
  }
}

Set<String> _allowedOptionsForCommand(String command) {
  return _commandSpec(command).allowedOptions;
}

int _maxPositionalArgsForCommand(String command) {
  return _commandSpec(command).maxPositionalArgs;
}

ParsedArgs _parseArgs(List<String> args) {
  final positional = <String>[];
  final options = <String, String>{};

  for (var i = 0; i < args.length; i++) {
    final token = args[i];
    if (!token.startsWith('--')) {
      positional.add(token);
      continue;
    }

    final option = token.substring(2);
    final equals = option.indexOf('=');
    if (equals >= 0) {
      final key = option.substring(0, equals);
      final value = option.substring(equals + 1);
      options[key] = value;
      continue;
    }

    if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
      options[option] = args[i + 1];
      i++;
    } else {
      options[option] = 'true';
    }
  }

  return ParsedArgs(positional, options);
}
