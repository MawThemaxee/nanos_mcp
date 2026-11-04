---
name: nanos-mcp
description: Inspect and operate a running nanos world game server through the nanos-mcp MCP server (tools server_status, game_call, game_events, game_*). Use when the user asks about their nanos world server — players, entities, console logs, server files, chat, kicking, restarting or stopping — or wants to add MCP tools to a nanos world Lua package with NanosMCP.RegisterTool, or needs help installing or troubleshooting nanos-mcp.
---

# nanos-mcp

nanos-mcp links a running nanos world server to you. Every game action is a **Lua tool** registered
on the server; the MCP server only relays calls.

## Always start with `server_status`

It tells you whether the game server is connected and lists every available game tool
(`tools[].name`, `mcp_name`, `destructive`).

- `connected: false` → the game server is offline or cannot reach the hub. You can do nothing
  in-game; see [references/setup.md](references/setup.md) to help the user.
- The tool list changes when the server restarts or packages reload. Re-check it instead of
  assuming a tool exists.

## Calling game tools

Two equivalent ways:

- the dedicated MCP tool, e.g. `game_players_list`;
- `game_call` with `tool` = the Lua name (`players.list`) and `args` = an object.

**Prefer `game_call` when a `game_*` tool is missing from your tool list** but present in
`server_status`: some clients only load the tool list once, before the game server connected.

Results are JSON (or a plain message string). Errors come back as tool errors with a readable
message — report it, do not retry blindly.

## Built-in tools

| Lua tool | Use |
|---|---|
| `server.info` | name, map, version, player count, tick rate, loaded packages |
| `players.list` | connected players: `id` (network id used by other tools), name, account/steam ids, ping |
| `world.entities` | no args: entity count per class; `{class}`: list with id, asset, location |
| `console.logs` | console lines since nanos-mcp loaded; `filter` to search, `lines` to limit |
| `files.list` / `files.read` | browse and read text files in the server folder |
| `chat.broadcast` / `chat.send` | message everyone / one player |
| `players.kick` | kick a player |
| `packages.reload` | reload a package |
| `console.run` | run a console command **registered by a Lua package** |
| `files.write` | create/replace a data file |
| `server.restart` / `server.stop` | restart / stop the server |

Packages installed on the server may add their own tools: read their `description` and
`input_schema` in your tool list (or in `server_status`) before calling them.

## Safety rules

Tools flagged `destructive` change the live server, possibly with real players on it.

1. **Ask the user before** `server.stop`, `server.restart`, `players.kick`, `packages.reload`,
   `files.write`, `chat.*`, `console.run`, or any other destructive tool — unless they explicitly
   asked for that exact action.
2. **`server.stop` is one-way**: the server cannot be started again from MCP. Prefer
   `server.restart` and say so.
3. Check `players.list` before a restart/stop and mention connected players.
4. Read a file with `files.read` before overwriting it with `files.write`; write the complete new
   content (it replaces the file).
5. Never echo tokens or secrets you might read in files.

## Known limits (explain them instead of working around them)

- `Config.toml` is blocked by nanos world (read and write); `.lua` files cannot be read or written.
  `files.read` accepts `.txt .json .toml .xml .csv .dat .log`; `files.write` only
  `.txt .json .csv .xml .dat` (max 1 MB) and can be disabled by the server owner.
- `console.run` cannot run native server commands, only script-registered ones; an unknown command
  returns an error.
- `console.logs` only holds lines since nanos-mcp loaded; older history is in
  `.logs/NanosWorldCore.log` (use `files.read` with `tail: true`).
- Events in `game_events` are kept in the hub's memory; events during a restart (e.g. players
  disconnected by it) are not captured.
- Locations are Unreal units: **100 units = 1 meter**.

## Writing new tools

When the user wants their own package to expose tools (economy, admin commands, game state...),
read [references/writing-tools.md](references/writing-tools.md).
