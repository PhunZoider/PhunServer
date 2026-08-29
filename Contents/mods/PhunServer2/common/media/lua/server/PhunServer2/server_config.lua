if isClient() then
    return
end

local Core = require "PhunServer2/core"
local tools = Core.tools

-- ---------------------------------------------------------------------------
-- Versioned config files in <Zomboid>/Lua/.
--
-- Files are JSON wrapped in a version envelope so the shape can be migrated
-- later without guessing what an admin's file contains:
--
--   { "version": 1, "data": { ... } }
--
-- loadConfig returns just the data half, plus the version it was read at.
--
-- These were Lua source files until B42.20.4 removed loadstring. The FILE IO
-- notes in tools.lua cover what that broke and why JSON replaced it.
-- ---------------------------------------------------------------------------

-- Returns data, version, needsConversion.
--   data, version    nil when the file is absent or unreadable
--   needsConversion  true when an unconverted pre-JSON file is sitting there.
--                    Callers use it to decline to seed defaults on top of
--                    settings the admin still believes are live.
function Core.loadConfig(filename, moduleName)
    local label = moduleName or Core.name

    local d = tools.loadTable(filename)
    if d == nil then
        if tools.needsConversion(filename) then
            local legacy = tools.legacyNameFor(filename)
            Core.logLn("./Lua/" .. legacy .. " is in the old Lua format, which this build cannot read", label)
            Core.logLn("Convert it to ./Lua/" .. filename .. " here: " .. tools.converterUrl, label)
            Core.logLn("Until then the settings in that file are not being applied", label)
            return nil, nil, true
        end
        Core.logLn("No config file at ./Lua/" .. filename .. " (normal if nothing has been customised)", label)
        return nil, nil, false
    end

    if type(d) ~= "table" or d.data == nil then
        Core.logLn("Unexpected format in ./Lua/" .. filename .. ", ignoring it", label)
        return nil, nil, false
    end

    Core.logLn("Loaded config from ./Lua/" .. filename, label)
    return d.data, d.version or 1, false
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
    local backup = filename:gsub("%.json$", "") .. "_backup.json"
    tools.saveTable(backup, data)
    Core.logLn("Backed up previous config to ./Lua/" .. backup, moduleName)
end
