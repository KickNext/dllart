# DLLART MCP Server

`dllart` ships with an MCP stdio server for AI agents.

## Run

From source checkout:

```bash
dart bin/dllart_mcp.dart
```

From global activation:

```bash
dllart_mcp
```

## Exposed Tools

- `dllart.run`
- `dllart.help`

## Tool: `dllart.run`

Runs a `dllart` command with structured args.

Common input fields:

- `command` (required): `create|new|init|build|make|package|proto|workflow|integrate|doctor|check|verify|test|build-all`
- `cwd`: working directory
- `config`, `name`, `source`, `output`, `target`, `force`
- `dependency`, `dllart_path`, `local_path_dependency` for `create`
- `auto_build`, `android_abis`, `ios_variants` for `package` / mobile build flow
- `package_target` for `doctor`
- `runtime_profile`: `full|slim` for `build`
- `skip_build`: skip auto-build step in `dllart test`
- `perf_gate`: run perf gate in `dllart test`
- `fix`: auto-fix common issues in `dllart doctor`
- `proto`, `out`, `include`, `grpc`, `protoc`
- `verbose`: pass through `--verbose` for supported commands
- `json`: enable/disable `--json` for JSON-capable commands

JSON mode is auto-enabled by default for:

- `build`
- `doctor`
- `integrate`
- `proto`
- `verify`
- `test`

## Tool: `dllart.help`

- Optional field: `command`
- Returns global help (or command help) text

## Executable Resolution

Server resolves `dllart` invocation in this order:

1. `DLLART_MCP_DLLART_BIN` environment variable
2. `dllart` on `PATH`
3. local source mode: `<server_start_cwd>/bin/dllart.dart`
4. `dart pub global run dllart`
5. `dart run dllart`

Use `DLLART_MCP_DLLART_BIN` when you need explicit binary control.

## Example MCP Client Config

```json
{
  "mcpServers": {
    "dllart": {
      "command": "dart",
      "args": ["bin/dllart_mcp.dart"],
      "cwd": "/absolute/path/to/dllart"
    }
  }
}
```

Use direct executable invocation (`command: "dart"`) with `cwd` instead of a
shell wrapper like `zsh -lc`.
