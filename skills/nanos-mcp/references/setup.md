# Installing and troubleshooting nanos-mcp

## Pieces

| Piece | Where it runs |
|---|---|
| `nanos-mcp` hub (`nanos-mcp.exe` / `nanos-mcp`) | next to the MCP client, or on any machine both can reach |
| `Packages/nanos-mcp-bridge` (C Module: `.dll` Windows, `.so` Linux) | on the game server |
| `Packages/nanos-mcp` (Lua) | on the game server |

The game server connects **out** to the hub over WebSocket. The hub listens on `[bridge].bind`.

## Setup checklist

1. Copy both packages from the release into the server `Packages/` folder.
2. Server `Config.toml`:
   ```toml
   [game]
       packages = [ ..., "nanos-mcp" ]

   [custom_settings]
       nanos_mcp_url   = "ws://<hub-host>:8809"
       nanos_mcp_token = "<long random secret>"
   ```
3. Start the server with `--enable_unsafe_libs` (nanos world requires it for C Modules).
4. Hub config (`nanos-mcp.toml`, from `nanos-mcp.example.toml`):
   ```toml
   [bridge]
   bind  = "127.0.0.1:8809"      # same machine as the game server
   # bind = "0.0.0.0:8809"       # game server on another machine (dev box, dedicated, VPS)
   token = "<same secret>"
   ```
5. Register the hub in the MCP client, e.g. `.mcp.json`:
   ```json
   { "mcpServers": { "nanos": { "command": "/path/to/nanos-mcp", "args": ["--config", "/path/to/nanos-mcp.toml"] } } }
   ```
   For a client on another machine: `[mcp] transport = "http"`, `http_bind`, `http_token`, and add
   the public host name to `allowed_hosts`.

A good secret: at least 32 random characters (`openssl rand -hex 24`). Never keep the example value.

## Troubleshooting `connected: false`

Check in this order:

1. **Is the game server running?** In its console, look for
   `[nanos-mcp] bridge v… -> ws://…`. If missing:
   - `To be able to load c-module Packages … --enable_unsafe_libs` → start flag missing;
   - `nanos_mcp_token manquant` → token not set in `[custom_settings]`;
   - `nanos-mcp` not in `[game].packages`.
2. **Can it reach the hub?** `nanos_mcp_url` must point to the hub machine, not `127.0.0.1`,
   when they are different machines; the hub must bind `0.0.0.0` (or that interface) and the port
   (default 8809) must be open in the firewall.
3. **Same token on both sides?** The hub log shows `connexion refusée : token invalide`.
4. **Hub actually listening?** If another hub instance held the port, the new one logs a bind
   error and retries every 5 s; close the old instance.
5. The bridge reconnects automatically with backoff up to 30 s — wait before concluding.

## Game tools missing from the client but present in `server_status`

The client loaded its tool list before the game server connected. Use `game_call`, or reconnect
the MCP server in the client.

## Security notes for remote setups

The bridge link is plain `ws://`: on the internet, the token travels unencrypted. For a VPS or a
remote dev box, prefer a private network or tunnel (WireGuard, Tailscale, SSH tunnel) between the
game server and the hub, or restrict the port to the game server's IP in the firewall.
