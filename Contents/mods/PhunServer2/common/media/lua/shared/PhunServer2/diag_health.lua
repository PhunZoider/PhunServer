-- Map health: is every map in the list loaded, and did every map's zones load?
--
-- Two silent failures this exists for, both met on a real server:
--
-- 1. A Map= entry with no folder behind it. IsoMetaGrid.CreateStep1 still
--    counts it when it hands out priorities, so every map after it (vanilla
--    included) discards its own buildings, and the world has no power because
--    the region system replaces each house with a player-built stand-in.
--
-- 2. One bad objects.lua entry. Vanilla's doMapZones (metazoneHandler.lua)
--    walks the map list from LAST to FIRST with no error handling, so a throw
--    in one map's file leaves every map earlier in Map= with no zones at all:
--    no NoPower zones, no spawn points, no parking. Hunter's Base's polygon
--    WaterZone did it, through a print in vanilla's own error message.
--
-- The zone check samples the LAST plain zone in each map's objects.lua and
-- asks the meta grid whether it exists. The last rather than the first, so a
-- file that throws partway through reports its own map rather than the next.
-- It runs on both sides: missing on both is a broken map file, missing only on
-- the server is a stale zone list in the save (map_zone.bin), which a restart
-- does not rebuild.
--
-- Read only. It re-reads each objects.lua the way vanilla does, through the
-- `objects` global, and puts back whatever was there.
local Health = {}

-- Types doMapZones never registers as a plain zone, or hands to a special
-- handler that does not produce one. A sample must be something registerZone
-- or registerVehiclesZone would have added.
local NOT_PLAIN = {
    Vegitation = true,
    DeepForest = true,
    Forest = true,
    TownZone = true,
    Farm = true,
    FarmLand = true,
    TrailerPark = true,
    Nav = true,
    Animal = true,
    Basement = true,
    Mannequin = true,
    RoomTone = true,
    SpawnOrigin = true,
    WaterFlow = true,
    WaterZone = true,
    WorldGen = true
}

-- registerZone refuses anything wider or taller than this, logging
-- "not adding suspicious zone", so such an entry is never evidence
local MAX_ZONE = 1202

local function isPlain(v)
    return type(v) == "table" and type(v.type) == "string" and not NOT_PLAIN[v.type] and v.geometry == nil and
               tonumber(v.x) and tonumber(v.y) and tonumber(v.width) and tonumber(v.height) and
               tonumber(v.width) <= MAX_ZONE and tonumber(v.height) <= MAX_ZONE
end

-- Loads one objects.lua into a fresh table, leaving the global as it was
local function readObjects(file)
    local saved = objects
    objects = {}
    local ok, err = pcall(reloadLuaFile, file)
    local loaded = objects
    objects = saved
    if not ok then
        return nil, tostring(err)
    end
    return type(loaded) == "table" and loaded or {}
end

local function zonePresent(sample)
    local mg = getWorld():getMetaGrid()
    local x, y, z = math.floor(sample.x), math.floor(sample.y), math.floor(tonumber(sample.z) or 0)
    local zones = mg:getZonesAt(x, y, z)
    if zones then
        for i = 0, zones:size() - 1 do
            if zones:get(i):getType() == sample.type then
                return true
            end
        end
    end
    local ok, vehicleZone = pcall(function()
        return mg:getVehicleZoneAt(x, y, z)
    end)
    return ok and vehicleZone ~= nil and vehicleZone:getType() == sample.type
end

-- The configured Map= list, server side only. Nil where there is none to read,
-- which is a client and single player.
local function configuredMaps()
    if isClient() or not getServerOptions then
        return nil
    end
    local ok, value = pcall(function()
        return getServerOptions():getOption("Map")
    end)
    if not ok or type(value) ~= "string" or value == "" then
        return nil
    end
    local list = {}
    for entry in string.gmatch(value, "([^;]+)") do
        local trimmed = string.gsub(entry, "^%s*(.-)%s*$", "%1")
        if trimmed ~= "" then
            table.insert(list, trimmed)
        end
    end
    return list
end

-- Runs every check. Returns
--   {
--     configured = {"AZSpawn", ...} or nil,
--     missingFolders = {"Map", ...},
--     maps = {{dir, status, entries, sample}, ...}   in Map= order
--     stoppedAt = index into maps or nil,
--   }
-- status is "present", "missing", "broken", "no objects.lua", "no sample" or
-- "error: ...". sample is "Type x,y,z" or "". stale is set on a missing map
-- that sits under a present one, so a stale save rather than a throw.
function Health.run()
    local result = {
        maps = {},
        missingFolders = {}
    }

    local dirs = getLotDirectories()
    local loaded = {}
    for i = 0, dirs:size() - 1 do
        local dir = dirs:get(i)
        loaded[dir] = true
        local file = "media/maps/" .. dir .. "/objects.lua"
        local row = {
            dir = dir,
            entries = 0,
            sample = ""
        }
        -- The game lists a map whose mod is not active (missing, disabled, or
        -- missing one of its own requirements) as though it were installed,
        -- and that is the Map= priority bug: every map after it drops its
        -- buildings. Every real map folder has a map.info, so ask the disk.
        if not fileExists("media/maps/" .. dir .. "/map.info") then
            row.status = "not installed"
            table.insert(result.missingFolders, dir)
        elseif not fileExists(file) then
            row.status = "no objects.lua"
        else
            local list, err = readObjects(file)
            if not list then
                row.status = "error: " .. err
            else
                local first, sample
                for _, v in ipairs(list) do
                    row.entries = row.entries + 1
                    if isPlain(v) then
                        first = first or v
                        sample = v
                    end
                end
                if not sample then
                    row.status = "no sample"
                else
                    row.sample = string.format("%s %d,%d,%d", sample.type, math.floor(sample.x),
                        math.floor(sample.y), math.floor(tonumber(sample.z) or 0))
                    local ok, present = pcall(zonePresent, sample)
                    if not ok then
                        row.status = "error: " .. tostring(present)
                    else
                        row.status = present and "present" or "missing"
                        -- First in and last out means this file threw partway
                        -- through itself: the one case that names the culprit
                        if not present and first ~= sample then
                            local okFirst, firstPresent = pcall(zonePresent, first)
                            if okFirst and firstPresent then
                                row.status = "broken"
                            end
                        end
                    end
                end
            end
        end
        table.insert(result.maps, row)
    end

    result.configured = configuredMaps()
    if result.configured then
        local seen = {}
        for _, dir in ipairs(result.missingFolders) do
            seen[dir] = true
        end
        for _, entry in ipairs(result.configured) do
            if not loaded[entry] and not seen[entry] then
                table.insert(result.missingFolders, entry)
            end
        end
    end

    -- A throw stops zone loading for every map above it in Map=, so a map
    -- missing zones under one that has them did not stop anything. Its zones
    -- came from a save written before its objects.lua gained them, which is
    -- also how a map can be first in and last out without having thrown.
    local presentAbove = false
    for _, row in ipairs(result.maps) do
        if row.status == "present" then
            presentAbove = true
        elseif presentAbove and (row.status == "missing" or row.status == "broken") then
            row.status = "missing"
            row.stale = true
        end
    end

    -- Zones load from the bottom of the list up, so the first missing map met
    -- that way is where loading stopped. It is that map, or the one just below
    -- it if that one threw after its own last zone.
    for i = #result.maps, 1, -1 do
        local row = result.maps[i]
        if (row.status == "missing" or row.status == "broken") and not row.stale then
            result.stoppedAt = i
            break
        end
    end

    return result
end

-- One line per finding, for the server log. Empty when everything is fine.
function Health.problems(result)
    local lines = {}
    for _, entry in ipairs(result.missingFolders) do
        table.insert(lines, "Map= lists '" .. entry .. "' but that map is not installed: its mod is missing, " ..
            "disabled, or missing one of the mods it requires. Every map after it in the list, vanilla " ..
            "included, drops its own buildings: no roof cutaway, no power indoors.")
    end
    if result.stoppedAt then
        local row = result.maps[result.stoppedAt]
        local below = result.maps[result.stoppedAt + 1]
        local missing = 0
        for i = 1, result.stoppedAt do
            local status = result.maps[i].status
            if (status == "missing" or status == "broken") and not result.maps[i].stale then
                missing = missing + 1
            end
        end
        if row.status == "broken" then
            table.insert(lines, string.format(
                "'%s' threw partway through its own objects.lua: its first zone loaded and its last did not. " ..
                    "Zone loading stopped there, so %d map(s) from it up the Map= list have no zones (spawn " ..
                    "points, parking, no-power areas). Moving it to the front of Map= limits the loss to itself.",
                row.dir, missing))
        else
            table.insert(lines, string.format(
                "zones missing for %d map(s), from '%s' up the Map= list. Either '%s'%s threw in its " ..
                    "objects.lua and stopped zone loading, or this save's map_zone.bin predates them, as it " ..
                    "does when a map is added to an existing world. /diag health on a client tells the two apart.",
                missing, row.dir, row.dir, below and (" or '" .. below.dir .. "'") or ""))
        end
    end
    local stale = {}
    for _, row in ipairs(result.maps) do
        if row.stale then
            table.insert(stale, row.dir)
        end
    end
    if #stale > 0 then
        table.insert(lines, string.format(
            "zones missing for %d map(s) (%s) while maps above them in Map= have theirs, so nothing " ..
                "stopped zone loading. This save's map_zone.bin predates their current objects.lua, as it " ..
                "does when a map is added to or extended in an existing world.",
            #stale, table.concat(stale, ", ")))
    end
    return lines
end

return Health
