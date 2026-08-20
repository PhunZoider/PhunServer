if isClient() then
    return
end

local Core = require "PhunServer2/core"
local tools = Core.tools

-- ---------------------------------------------------------------------------
-- Versioned config files in <Zomboid>/Lua/.
--
-- Files are plain Lua wrapped in a version envelope so the shape can be
-- migrated later without guessing what an admin's file contains:
--
--   return { version = 1, data = { ... } }
--
-- loadConfig returns just the data half, plus the version it was read at.
-- ---------------------------------------------------------------------------

-- Returns data, version. Both nil when the file is absent or unreadable.
function Core.loadConfig(filename, moduleName)
    local label = moduleName or Core.name

    local d = tools.loadTable(filename)
    if d == nil then
        Core.logLn("No config file at ./Lua/" .. filename .. " (normal if nothing has been customised)", label)
        return nil, nil
    end

    if type(d) ~= "table" or d.data == nil then
        Core.logLn("Unexpected format in ./Lua/" .. filename .. ", ignoring it", label)
        return nil, nil
    end

    Core.logLn("Loaded config from ./Lua/" .. filename, label)
    return d.data, d.version or 1
end

function Core.saveConfig(filename, data, version, moduleName)
    tools.saveTable(filename, {
        version = version or 1,
        data = data or {}
    })
    Core.verboseLn("Saved config to ./Lua/" .. filename, moduleName)
end

-- Writes a timestamped copy alongside the original before a destructive
-- migration, so an admin can always recover their hand-written file.
function Core.backupConfig(filename, data, moduleName)
    local backup = filename:gsub("%.txt$", "") .. "_backup.txt"
    tools.saveTable(backup, data)
    Core.logLn("Backed up previous config to ./Lua/" .. backup, moduleName)
end
