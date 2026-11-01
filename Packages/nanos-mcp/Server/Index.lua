-- nanos-mcp : expose des outils Lua au modèle via le hub nanos-mcp.
--
-- Config.toml du serveur :
--   [custom_settings]
--       nanos_mcp_url   = "ws://127.0.0.1:8809"
--       nanos_mcp_token = "même valeur que [bridge].token de nanos-mcp.toml"
--
-- Depuis un autre package (packages_requirements = ["nanos-mcp"]) :
--   NanosMCP.RegisterTool("eco.balance", {
--       description = "Solde d'un joueur",
--       input_schema = { type = "object", properties = { player_id = { type = "integer" } }, required = { "player_id" } },
--   }, function(args) return { balance = 42 } end)
--
-- Un handler peut retourner :
--   * une valeur JSON (table, string, number, boolean, nil) ;
--   * une promesse (tout objet avec :Then(on_ok, on_err), ex. nmrp-promise) ;
--   * NanosMCP.ASYNC, puis appeler respond(ok, data) plus tard (2e argument du handler).

local bridge = nanos_mcp_bridge
local MAX_CALLS_PER_TICK = 16

local settings = Server.GetCustomSettings() or {}
local URL = settings.nanos_mcp_url or "ws://127.0.0.1:8809"
local TOKEN = settings.nanos_mcp_token

local traceback = (debug and debug.traceback) or tostring

local tools = {}        -- nom -> { spec, handler }
local tools_dirty = false

NanosMCP = {}
NanosMCP.ASYNC = setmetatable({}, { __tostring = function() return "NanosMCP.ASYNC" end })

local function log(level, msg)
    Console[level](msg)
end

function NanosMCP.RegisterTool(name, spec, handler)
    assert(type(name) == "string" and name ~= "", "RegisterTool : nom invalide")
    assert(type(handler) == "function", "RegisterTool : handler doit être une fonction")
    spec = spec or {}
    if tools[name] then
        log("Warn", "outil '" .. name .. "' ré-enregistré (l'ancien est remplacé)")
    end
    tools[name] = {
        handler = handler,
        spec = {
            name = name,
            description = spec.description or "",
            input_schema = spec.input_schema or { type = "object", properties = {} },
            destructive = spec.destructive == true,
        },
    }
    tools_dirty = true
end

function NanosMCP.UnregisterTool(name)
    if tools[name] then
        tools[name] = nil
        tools_dirty = true
    end
end

--- Pousse un événement visible par le modèle (outil game_events).
function NanosMCP.Emit(name, data)
    local ok, err = pcall(bridge.emit, name, data)
    if not ok then log("Warn", "Emit '" .. tostring(name) .. "' : " .. tostring(err)) end
end

--- Marque une table comme tableau JSON : sans ça, une liste vide est envoyée en `{}`.
--- Refuse un appel (argument invalide, action interdite) : le message va au modèle,
--- la console n'affiche qu'un avertissement d'une ligne, sans stack trace.
local REFUSAL = {}
function NanosMCP.Fail(message)
    error(setmetatable({ message = tostring(message) }, REFUSAL), 0)
end

function NanosMCP.Array(t)
    return bridge.array(t)
end

function NanosMCP.IsConnected()
    return bridge.status().connected
end

Package.Export("NanosMCP", NanosMCP)

-- Dispatch ---------------------------------------------------------------

local function sync_tools()
    local specs = {}
    for _, entry in pairs(tools) do
        specs[#specs + 1] = entry.spec
    end
    local ok, err = pcall(bridge.set_tools, specs)
    if not ok then log("Error", "liste d'outils invalide : " .. tostring(err)) end
end

local function capture_error(err)
    if getmetatable(err) == REFUSAL then return { message = err.message } end
    return { message = tostring(err), trace = traceback(err, 2) }
end

local function dispatch(call)
    local id = call.id
    local settled = false
    local function respond(ok, data)
        if settled then return end
        settled = true
        if not bridge.reply(id, ok == true, data) then
            log("Warn", "réponse " .. id .. " perdue (hub déconnecté)")
        end
    end

    local entry = tools[call.tool]
    if not entry then
        return respond(false, "outil inconnu : " .. tostring(call.tool))
    end

    local ok, result = xpcall(entry.handler, capture_error, call.args or {}, respond)
    if not ok then
        if result.trace then
            -- Vrai bug : la trace complète reste dans la console, le modèle n'a que le message.
            log("Error", "outil '" .. call.tool .. "' : " .. result.trace)
        else
            -- Console.Warn ajoute sa propre pile d'appels : Log garde le refus sur une ligne.
            log("Log", "outil '" .. call.tool .. "' refusé : " .. result.message)
        end
        return respond(false, result.message)
    end

    if result == NanosMCP.ASYNC then return end
    if type(result) == "table" and type(result.Then) == "function" then
        result:Then(
            function(value) respond(true, value) end,
            function(err) respond(false, tostring(err)) end
        )
        return
    end
    respond(true, result)
end

Server.Subscribe("Tick", function()
    if tools_dirty then
        tools_dirty = false
        sync_tools()
    end
    for _, call in ipairs(bridge.poll(MAX_CALLS_PER_TICK)) do
        dispatch(call)
    end
end)

Package.Subscribe("Unload", function()
    bridge.stop()
end)

-- Démarrage ----------------------------------------------------------------

Package.Require("Console.lua")
Package.Require("Tools.lua")
Package.Require("Files.lua")

if not TOKEN or TOKEN == "" then
    log("Warn", "nanos_mcp_token manquant dans [custom_settings] du Config.toml : bridge désactivé")
else
    bridge.start({ url = URL, token = TOKEN, server_name = Server.GetName() })
    log("Log", "bridge v" .. bridge.version() .. " -> " .. URL)
end
