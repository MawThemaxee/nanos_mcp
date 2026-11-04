# Nanos MCP

Connect a [nanos world](https://nanos-world.com) server to any [MCP](https://modelcontextprotocol.io)
client (Claude Code, Claude Desktop, ...). The model can inspect and act on the running game
through tools written in Lua — and any package on your server can expose its own tools.

```
MCP client ──stdio / Streamable HTTP──► nanos-mcp (hub)
                                            ▲
                                            │ WebSocket (outbound from the game server)
                                            │
                     nanos world server ── nanos_mcp_bridge (C Module) ── nanos-mcp (Lua package)
```

The bridge connects **out** to the hub, so the game server needs no open port. It works the same
on a local server or on any host (VPS, game panel...).

## Features

- Server info, players, entities in the world
- Kick players, chat broadcast / private messages
- Stop / restart the server, reload packages
- Console logs and script-registered console commands
- Read / write server files (within the limits of the nanos `File` API)
- Real-time events (player connect / disconnect, custom events)
- **Extensible**: any package registers its own tools with `NanosMCP.RegisterTool`

## Installation

1. Download the latest release and copy into your server's `Packages/` folder:
   - `nanos-mcp-bridge/` (`Package.toml` + `nanos_mcp_bridge.dll` / `libnanos_mcp_bridge.so`)
   - `nanos-mcp/`
2. In the server `Config.toml`:
   ```toml
   [game]
       packages = [ ..., "nanos-mcp" ]

   [custom_settings]
       nanos_mcp_url   = "ws://127.0.0.1:8809"
       nanos_mcp_token = "<a long random secret>"
   ```
3. Start the server with `--enable_unsafe_libs` (required by nanos world for C Modules).
4. Copy `nanos-mcp.example.toml` to `nanos-mcp.toml` next to the hub and set `[bridge].token`
   to the same secret.
5. Register the hub in your MCP client, e.g. Claude Code (`.mcp.json`):
   ```json
   { "mcpServers": { "nanos": {
       "command": "/path/to/nanos-mcp",
       "args": ["--config", "/path/to/nanos-mcp.toml"]
   } } }
   ```

For a client on another machine, set `[mcp].transport = "http"` and a `http_token`; the hub then
serves Streamable HTTP on `http://<http_bind>/mcp` with Bearer authentication.

### Game server on another machine (dev box, dedicated server, VPS)

The game server connects to the hub, so the hub must be reachable from it:

```toml
# nanos-mcp.toml (hub machine)
[bridge]
bind  = "0.0.0.0:8809"
token = "<long random secret>"
```
```toml
# Config.toml (game server)
[custom_settings]
    nanos_mcp_url   = "ws://<hub-ip-or-host>:8809"
    nanos_mcp_token = "<same secret>"
```

Open port 8809 on the hub machine. The link is plain `ws://`: over the internet, prefer a private
network or tunnel (WireGuard, Tailscale, SSH) or restrict the port to the game server's IP.

`http_token` is unrelated: it protects the MCP endpoint when the **MCP client** runs on another
machine than the hub (`[mcp].transport = "http"`).

## Agent skill

[`skills/nanos-mcp`](skills/nanos-mcp/SKILL.md) teaches an agent when and how to use these tools
safely (check `server_status` first, ask before destructive actions, known limits) and how to write
new tools. For Claude Code, copy the folder to `~/.claude/skills/` (all projects) or to
`.claude/skills/` in your project.

## MCP tools

| Tool | Description |
|---|---|
| `server_status` | Bridge connection and list of game tools |
| `game_call` | Call any game tool by name (works even if the client cached an old tool list) |
| `game_events` | Recent game events |
| `game_*` | One MCP tool per Lua tool registered on the server |

Built-in Lua tools:

| Lua tool | Description |
|---|---|
| `server.info` | Name, map, players, tick rate, version, loaded packages |
| `server.stop` / `server.restart` | Stop or restart the server |
| `players.list` / `players.kick` | Connected players / kick one |
| `chat.broadcast` / `chat.send` | Chat to everyone / to one player |
| `world.entities` | Entity count per class, or list of one class with asset and location |
| `packages.reload` | Reload a package |
| `console.logs` / `console.run` | Console history / run a script-registered command |
| `files.list` / `files.read` / `files.write` | Server files (nanos blocks `Config.toml` and `.lua`) |

## Adding tools from your own package

```lua
-- Package.toml: packages_requirements = ["nanos-mcp"]
NanosMCP.RegisterTool("eco.balance", {
    description = "Balance of a player",
    input_schema = {
        type = "object",
        properties = { player_id = { type = "integer" } },
        required = { "player_id" },
    },
}, function(args)
    return { balance = 42 }
end)
```

A handler can return:
- a JSON-compatible value (table, string, number, boolean, nil);
- a promise (any object with `:Then(on_ok, on_err)`, e.g. nmrp-promise);
- `NanosMCP.ASYNC`, then call `respond(ok, data)` later (second handler argument).

Other helpers: `NanosMCP.Fail(message)` refuses a call (the model gets the message, the console
only a one-line warning instead of a stack trace), `NanosMCP.Emit(name, data)` pushes an event,
`NanosMCP.Array(t)` marks a table as a JSON array (an empty Lua table is sent as `{}` otherwise),
`NanosMCP.IsConnected()`.

## Security

- The hub only accepts the bridge with the shared token; keep it secret and long.
- Tools marked destructive (kick, stop, file write...) are flagged as such to the MCP client,
  which can ask for confirmation.
- File tools stay inside the server folder (no absolute paths, no `..`) and `Config.toml` is
  blocked by nanos world. `files.read` only reads text files; `files.write` only writes data
  files (`.txt .json .csv .xml .dat`, max 1 MB) — never `.toml` (`Package.toml`), `.lua` or
  logs — and every write is logged in the server console. Disable writing entirely with:
  ```toml
  [custom_settings]
      nanos_mcp_files_write = false
  ```
- The bridge link is plain `ws://` for now: keep the hub on the same host or a private network.

## License

- Lua packages and documentation: [MIT](LICENSE).
- `nanos-mcp` and `nanos_mcp_bridge` binaries: free to use, closed source — see
  [LICENSE-BINARIES.md](LICENSE-BINARIES.md) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Why Binaries are Closed Source is to protect the intellectual property and ensure the stability and security of the hub and bridge components, while still allowing the Lua packages and documentation to be freely used and modified.

## How IA helped create this project
- Source Recherche and Documentation: IA assisted in researching and providing documentation for the project.
- Code Assistance: IA helped in generating code base for the Lua packages and server-side logic.

All Code Review and major Code and design decisions were by me. I am not perfect so please help me in future improvements.