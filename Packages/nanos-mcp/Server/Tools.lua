-- Outils fournis par défaut. Les autres packages ajoutent les leurs via NanosMCP.RegisterTool.

local function player_info(player)
    return {
        id = player:GetID(),
        name = player:GetName(),
        account_id = player:GetAccountID(),
        steam_id = player:GetSteamID(),
        ping = player:GetPing(),
    }
end

local function find_player(id)
    for _, player in pairs(Player.GetAll()) do
        if player:GetID() == id then return player end
    end
    NanosMCP.Fail("aucun joueur avec l'id " .. tostring(id))
end

local PLAYER_ID = { type = "integer", description = "ID réseau du joueur (voir players.list)" }

-- Laisse le temps à la réponse de partir avant d'arrêter ou redémarrer.
local POWER_DELAY_MS = 500

NanosMCP.RegisterTool("server.stop", {
    description = "Arrête le serveur. Il ne pourra pas être relancé depuis le MCP.",
    destructive = true,
}, function()
    Timer.SetTimeout(function() Server.Stop() end, POWER_DELAY_MS)
    return "arrêt en cours"
end)

NanosMCP.RegisterTool("server.restart", {
    description = "Redémarre le serveur (recharge la carte et tous les packages).",
    destructive = true,
}, function()
    Timer.SetTimeout(function() Server.Restart() end, POWER_DELAY_MS)
    return "redémarrage en cours"
end)

NanosMCP.RegisterTool("server.info", {
    description = "Nom, carte, joueurs, tick rate, version et packages chargés du serveur.",
}, function()
    local packages = NanosMCP.Array()
    for _, p in pairs(Server.GetPackages(true)) do
        packages[#packages + 1] = p
    end
    return {
        name = Server.GetName(),
        description = Server.GetDescription(),
        version = Server.GetVersion(),
        map = Server.GetMap(),
        players = Player.GetCount(),
        max_players = Server.GetMaxPlayers(),
        tick_rate = Server.GetTickRate(),
        packages = packages,
    }
end)

NanosMCP.RegisterTool("players.list", {
    description = "Liste les joueurs connectés (id, nom, account_id, steam_id, ping).",
}, function()
    local out = NanosMCP.Array()
    for _, player in pairs(Player.GetAll()) do
        out[#out + 1] = player_info(player)
    end
    return out
end)

-- Classes d'entités interrogées ; celles absentes de la version du serveur sont ignorées.
local ENTITY_CLASSES = {
    "Character", "CharacterSimple", "Prop", "StaticMesh", "VehicleWheeled", "VehicleWater",
    "Weapon", "Melee", "Grenade", "Light", "Trigger", "TextRender", "Blueprint", "Cable",
    "Particle", "Decal", "Billboard", "Widget3D", "SceneCapture",
}

local function entity_class(name)
    local class = _G[name]
    if type(class) == "table" and type(class.GetAll) == "function" then return class end
end

local function entity_info(entity, class_name)
    local info = { id = entity:GetID(), class = class_name }
    -- GetMesh() remplace GetAssetName(), dépréciée sur Vehicle depuis 1.16x.
    local get_asset = entity.GetMesh or entity.GetAssetName
    if get_asset then
        local ok, asset = pcall(get_asset, entity)
        if ok and type(asset) == "string" and asset ~= "" then info.asset = asset end
    end
    local ok_loc, loc = pcall(entity.GetLocation, entity)
    if ok_loc and loc then
        info.location = { x = math.floor(loc.X), y = math.floor(loc.Y), z = math.floor(loc.Z) }
    end
    return info
end

NanosMCP.RegisterTool("world.entities", {
    description = "Sans argument : nombre d'entités par classe (props, véhicules, personnages...). "
        .. "Avec `class` : liste ces entités (id, asset, position).",
    input_schema = {
        type = "object",
        properties = {
            class = { type = "string", description = "Classe à détailler, ex. Prop, VehicleWheeled, Character" },
            limit = { type = "integer", description = "Nombre max d'entités listées (défaut 50)" },
        },
    },
}, function(args)
    if args.class then
        local class = entity_class(args.class)
        if not class then NanosMCP.Fail("classe inconnue : " .. tostring(args.class)) end
        local limit = math.min(args.limit or 50, 500)
        local out = NanosMCP.Array()
        for _, entity in pairs(class.GetAll()) do
            if #out >= limit then break end
            out[#out + 1] = entity_info(entity, args.class)
        end
        return out
    end

    local counts = {}
    for _, name in ipairs(ENTITY_CLASSES) do
        local class = entity_class(name)
        if class then
            local n = #class.GetAll()
            if n > 0 then counts[name] = n end
        end
    end
    return counts
end)

NanosMCP.RegisterTool("players.kick", {
    description = "Expulse un joueur du serveur.",
    destructive = true,
    input_schema = {
        type = "object",
        properties = { player_id = PLAYER_ID, reason = { type = "string" } },
        required = { "player_id" },
    },
}, function(args)
    local player = find_player(args.player_id)
    local name = player:GetName()
    player:Kick(args.reason or "Expulsé par un administrateur")
    return name .. " expulsé"
end)

NanosMCP.RegisterTool("chat.broadcast", {
    description = "Envoie un message dans le chat à tous les joueurs.",
    destructive = true,
    input_schema = {
        type = "object",
        properties = { message = { type = "string" } },
        required = { "message" },
    },
}, function(args)
    Chat.BroadcastMessage(args.message)
    return "message envoyé"
end)

NanosMCP.RegisterTool("chat.send", {
    description = "Envoie un message privé dans le chat d'un joueur.",
    destructive = true,
    input_schema = {
        type = "object",
        properties = { player_id = PLAYER_ID, message = { type = "string" } },
        required = { "player_id", "message" },
    },
}, function(args)
    Chat.SendMessage(find_player(args.player_id), args.message)
    return "message envoyé"
end)

NanosMCP.RegisterTool("packages.reload", {
    description = "Recharge un package du serveur (nom du dossier dans Packages/).",
    destructive = true,
    input_schema = {
        type = "object",
        properties = { name = { type = "string" } },
        required = { "name" },
    },
}, function(args, respond)
    -- Recharger depuis le tick courant pourrait recharger ce package pendant le dispatch.
    Timer.SetTimeout(function()
        respond(Server.ReloadPackage(args.name), "rechargement de " .. args.name)
    end, 0)
    return NanosMCP.ASYNC
end)

-- Événements (l'IP des joueurs n'est volontairement pas remontée).
Server.Subscribe("PlayerConnect", function(_, account_id, name)
    NanosMCP.Emit("player_connect", { account_id = account_id, name = name })
end)

Server.Subscribe("PlayerDisconnect", function(_, account_id, name, _, reason)
    NanosMCP.Emit("player_disconnect", { account_id = account_id, name = name, reason = reason })
end)
