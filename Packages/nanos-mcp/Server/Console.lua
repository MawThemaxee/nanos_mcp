-- Console du serveur : historique des logs depuis le chargement du package + commandes de script.

local MAX_LINES = 2000
local lines = {}
local first = 1 -- index du plus ancien (tampon circulaire)
-- Sorties en cours de capture (une par console.run en attente).
local captures = {}
-- Les logs nanos sont asynchrones : la sortie d'une commande arrive après RunCommand.
local CAPTURE_MS = 300

Console.Subscribe("LogEntry", function(text, log_type)
    for capture in pairs(captures) do capture[#capture + 1] = text end
    local entry = { text = text, type = log_type }
    if #lines < MAX_LINES then
        lines[#lines + 1] = entry
    else
        lines[first] = entry
        first = first % MAX_LINES + 1
    end
end)

local function last_lines(count)
    local out = NanosMCP.Array()
    local total = #lines
    count = math.min(count, total)
    for i = total - count + 1, total do
        -- i-ème plus ancien -> position dans le tampon circulaire
        local entry = lines[(first + i - 2) % total + 1]
        out[#out + 1] = entry.text
    end
    return out
end

NanosMCP.RegisterTool("console.logs", {
    description = "Dernières lignes de la console du serveur (depuis le chargement de nanos-mcp). "
        .. "L'historique complet est dans .logs/NanosWorldCore.log (voir files.read).",
    input_schema = {
        type = "object",
        properties = {
            lines = { type = "integer", description = "Nombre de lignes (défaut 100, max 2000)" },
            filter = { type = "string", description = "Ne garder que les lignes contenant ce texte" },
        },
    },
}, function(args)
    local count = math.max(1, math.min(args.lines or 100, MAX_LINES))
    if not args.filter then return last_lines(count) end

    local matched = NanosMCP.Array()
    local all = last_lines(MAX_LINES)
    for i = #all, 1, -1 do
        if #matched >= count then break end
        if string.find(all[i], args.filter, 1, true) then
            table.insert(matched, 1, all[i])
        end
    end
    return matched
end)

NanosMCP.RegisterTool("console.run", {
    description = "Exécute une commande console enregistrée par un package (Console.RegisterCommand). "
        .. "Les commandes natives du serveur ne sont pas accessibles depuis Lua.",
    destructive = true,
    input_schema = {
        type = "object",
        properties = { command = { type = "string", description = "Commande et arguments" } },
        required = { "command" },
    },
}, function(args, respond)
    local output = NanosMCP.Array()
    captures[output] = true
    local ok, err = pcall(Console.RunCommand, args.command)
    if not ok then
        captures[output] = nil
        error(err, 0)
    end

    Timer.SetTimeout(function()
        captures[output] = nil
        for _, text in ipairs(output) do
            if string.find(text, "Console Command '.-' not found") then
                return respond(false, "commande introuvable : " .. args.command
                    .. " (seules les commandes enregistrées par un package sont disponibles)")
            end
        end
        respond(true, { command = args.command, output = output })
    end, CAPTURE_MS)
    return NanosMCP.ASYNC
end)
