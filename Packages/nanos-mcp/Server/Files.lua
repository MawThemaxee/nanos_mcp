-- Fichiers du serveur via l'API File de nanos world.
--
-- Le moteur limite déjà l'accès au dossier du serveur et bloque Config.toml. On ajoute nos
-- propres règles, vérifiées AVANT d'appeler File (refus propre, sans S_ERR dans la console) :
--   * pas de chemin absolu ni de "..";
--   * lecture : fichiers texte uniquement ;
--   * écriture : fichiers de données uniquement (.txt .json .csv .xml .dat) — jamais .toml
--     (Package.toml / Assets.toml), .log ni média — taille limitée, désactivable ;
--   * chaque écriture est tracée dans la console.
--
-- Config.toml du serveur :
--   [custom_settings]
--       nanos_mcp_files_write = false   # désactive files.write

local MAX_READ_BYTES = 200000
local MAX_WRITE_BYTES = 1000000

local READ_EXTENSIONS = { txt = true, json = true, toml = true, xml = true, csv = true, dat = true, log = true }
local WRITE_EXTENSIONS = { txt = true, json = true, xml = true, csv = true, dat = true }

local settings = Server.GetCustomSettings() or {}
local WRITE_ENABLED = settings.nanos_mcp_files_write ~= false and settings.nanos_mcp_files_write ~= "false"

local function list_extensions(set)
    local out = {}
    for ext in pairs(set) do out[#out + 1] = "." .. ext end
    table.sort(out)
    return table.concat(out, " ")
end

local function safe_path(path)
    if type(path) ~= "string" or path == "" then NanosMCP.Fail("chemin manquant") end
    path = path:gsub("\\", "/"):gsub("^%./", "")
    if path:match("^/") or path:match("^%a:") then
        NanosMCP.Fail("chemin absolu interdit : " .. path)
    end
    for segment in path:gmatch("[^/]+") do
        if segment == ".." then NanosMCP.Fail("'..' interdit dans le chemin") end
    end
    return path
end

local function check_extension(path, allowed, action)
    local ext = (path:match("%.([%w]+)$") or ""):lower()
    if not allowed[ext] then
        NanosMCP.Fail(action .. " interdite pour '" .. path .. "' (extensions autorisées : "
            .. list_extensions(allowed) .. ")")
    end
end

NanosMCP.RegisterTool("files.list", {
    description = "Liste les sous-dossiers et fichiers d'un dossier du serveur (non récursif).",
    input_schema = {
        type = "object",
        properties = {
            path = { type = "string", description = "Dossier relatif au serveur, ex. Packages (défaut : racine)" },
            extension = { type = "string", description = "Filtre d'extension, ex. .json" },
        },
    },
}, function(args)
    local path = args.path and args.path ~= "" and safe_path(args.path) or ""
    if path ~= "" and not File.IsDirectory(path) then
        NanosMCP.Fail("dossier introuvable : " .. path)
    end
    local directories = NanosMCP.Array()
    for _, dir in ipairs(File.GetDirectories(path, 0)) do directories[#directories + 1] = dir end
    local files = NanosMCP.Array()
    for _, file in ipairs(File.GetFiles(path, args.extension, 0)) do files[#files + 1] = file end
    return { directories = directories, files = files }
end)

NanosMCP.RegisterTool("files.read", {
    description = "Lit un fichier texte du serveur (" .. list_extensions(READ_EXTENSIONS)
        .. ") ; Config.toml est bloqué par le moteur.",
    input_schema = {
        type = "object",
        properties = {
            path = { type = "string", description = "Fichier relatif au serveur, ex. .logs/NanosWorldCore.log" },
            tail = { type = "boolean", description = "Si le fichier est trop gros, lire la fin plutôt que le début" },
        },
        required = { "path" },
    },
}, function(args)
    local path = safe_path(args.path)
    check_extension(path, READ_EXTENSIONS, "lecture")
    if path:lower() == "config.toml" then NanosMCP.Fail("Config.toml est protégé par nanos world") end
    if not File.IsRegularFile(path) then NanosMCP.Fail("fichier introuvable : " .. path) end

    local file = File(path)
    if not file:IsGood() then
        file:Close()
        NanosMCP.Fail("impossible d'ouvrir " .. path)
    end
    local size = file:Size()
    local truncated = size > MAX_READ_BYTES
    if truncated and args.tail then file:Seek(size - MAX_READ_BYTES) end
    local content = file:Read(truncated and MAX_READ_BYTES or 0)
    file:Close()
    return { path = path, size = size, truncated = truncated, content = content }
end)

if WRITE_ENABLED then
    NanosMCP.RegisterTool("files.write", {
        description = "Crée ou remplace un fichier de données du serveur (" .. list_extensions(WRITE_EXTENSIONS)
            .. ", max " .. MAX_WRITE_BYTES .. " octets). Lire le fichier avant de le modifier.",
        destructive = true,
        input_schema = {
            type = "object",
            properties = {
                path = { type = "string", description = "Fichier relatif au serveur" },
                content = { type = "string", description = "Nouveau contenu complet" },
            },
            required = { "path", "content" },
        },
    }, function(args)
        local path = safe_path(args.path)
        check_extension(path, WRITE_EXTENSIONS, "écriture")
        if type(args.content) ~= "string" then NanosMCP.Fail("content doit être une chaîne") end
        if #args.content > MAX_WRITE_BYTES then
            NanosMCP.Fail("contenu trop gros (" .. #args.content .. " octets, max " .. MAX_WRITE_BYTES .. ")")
        end

        local file = File(path, true)
        if not file:IsGood() then
            file:Close()
            NanosMCP.Fail("impossible d'écrire " .. path)
        end
        file:Write(args.content)
        file:Close()
        Console.Log("files.write : " .. path .. " (" .. #args.content .. " octets)")
        return path .. " écrit (" .. #args.content .. " octets)"
    end)
else
    Console.Log("files.write désactivé (nanos_mcp_files_write = false)")
end
