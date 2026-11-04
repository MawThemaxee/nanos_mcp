# Writing MCP tools in a nanos world package

Any server-side Lua package can expose tools to the model through the global `NanosMCP`
(exported by the `nanos-mcp` package).

## Requirement

```toml
# Package.toml of your package
[script]
    packages_requirements = [ "nanos-mcp" ]
```

Register tools from **server-side** code (`Server/Index.lua` or a file it requires).

## RegisterTool

```lua
NanosMCP.RegisterTool(name, spec, handler)
```

| Param | Meaning |
|---|---|
| `name` | unique id, dotted by convention: `eco.balance`, `admin.teleport`. Exposed to MCP as `game_eco_balance`. |
| `spec.description` | what the tool does and when to use it — this is what the model reads |
| `spec.input_schema` | JSON Schema of the arguments (`type = "object"`, `properties`, `required`) |
| `spec.destructive` | `true` if it changes the game (spawn, delete, kick, money...) |
| `handler(args, respond)` | called on the game thread with the decoded arguments |

Registering an existing name replaces it (with a console warning). `NanosMCP.UnregisterTool(name)`
removes one.

## Returning results

A handler can:

```lua
-- 1. return a JSON-compatible value (table, string, number, boolean, nil)
return { balance = 42 }

-- 2. return a promise: any object with :Then(on_ok, on_err) (e.g. nmrp-promise)
return SomeAsyncCall():Then(...)

-- 3. answer later
Timer.SetTimeout(function() respond(true, { done = true }) end, 1000)
return NanosMCP.ASYNC
```

- A returned **string** is shown to the model as plain text; tables are sent as JSON.
- **Lists that may be empty**: wrap them with `NanosMCP.Array()`, otherwise an empty Lua table is
  sent as `{}` instead of `[]`.
- Results must be plain data: convert entities, vectors and other userdata to tables first
  (e.g. `{ x = loc.X, y = loc.Y, z = loc.Z }`).
- The hub waits 15 s by default (`[bridge].call_timeout_secs`); keep handlers fast.

## Refusing a call

```lua
if not player then NanosMCP.Fail("no player with id " .. tostring(args.player_id)) end
```

`NanosMCP.Fail(message)` sends the message to the model and logs a single console line.
Any other Lua error is treated as a bug: the model gets the message, the console the full stack
trace.

## Events

```lua
NanosMCP.Emit("round_end", { winner = team_name, duration = seconds })
```

Events are visible through the `game_events` MCP tool. Don't emit personal data (IP addresses...).

## Complete example

```lua
local function find_player(id)
    for _, p in pairs(Player.GetAll()) do
        if p:GetID() == id then return p end
    end
    NanosMCP.Fail("no player with id " .. tostring(id))
end

NanosMCP.RegisterTool("admin.teleport", {
    description = "Teleport a player's character to a location (Unreal units, 100 = 1 m).",
    destructive = true,
    input_schema = {
        type = "object",
        properties = {
            player_id = { type = "integer", description = "Network id from players.list" },
            x = { type = "number" }, y = { type = "number" }, z = { type = "number" },
        },
        required = { "player_id", "x", "y", "z" },
    },
}, function(args)
    local character = find_player(args.player_id):GetControlledCharacter()
    if not character then NanosMCP.Fail("this player has no character") end
    character:SetLocation(Vector(args.x, args.y, args.z))
    return "teleported"
end)
```

## Good tool design

- One clear action per tool; describe **when** to use it in `description`.
- Validate arguments and `Fail` with an actionable message.
- Mark anything that changes the world as `destructive` so clients can ask for confirmation.
- Never expose raw code execution (`load`, `Package.Require` of arbitrary paths) as a tool.
