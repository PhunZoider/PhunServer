-- Map health, the boot check behind /diag health.
--
-- Every case here is a failure that happened on a real server and stayed
-- silent: a Map= entry with no folder (vanilla dropped its own buildings), and
-- one map's objects.lua throwing partway through (every map above it in Map=
-- lost its zones). What is pinned is the verdict, because the verdict is what
-- the server log says: which map, and that a healthy server says nothing.
--
-- Run: ..\PhunTestKit\run.cmd . diag_health

local kit = require "phuntestkit"
local check = kit.check

kit.installGlobals()
kit.addMod("PhunServer2")

local Health = require "PhunServer2/diag_health"

kit.strip()

---------------------------------------------------------------------------
-- A world: the map list, each map's objects.lua, and which zones the meta grid
-- actually holds. Zones are "Type x,y,z" strings.

local world

local function zone(t, x, y, extra)
    local v = {
        name = "",
        type = t,
        x = x,
        y = y,
        z = 0,
        width = 5,
        height = 5
    }
    for k, val in pairs(extra or {}) do
        v[k] = val
    end
    return v
end

local function setWorld(spec)
    world = spec
    world.present = world.present or {}
end

local function list(items)
    return {
        size = function()
            return #items
        end,
        get = function(_, i)
            return items[i + 1]
        end
    }
end

getLotDirectories = function()
    return list(world.dirs)
end

fileExists = function(path)
    -- Every listed map has a map.info unless its mod is not really active
    local dir = string.match(path, "^media/maps/(.+)/map%.info$")
    if dir then
        for _, d in ipairs(world.dirs) do
            if d == dir then
                return not (world.uninstalled and world.uninstalled[dir])
            end
        end
        return false
    end
    return world.files[path] ~= nil
end

reloadLuaFile = function(path)
    local data = world.files[path]
    if data == "throw" then
        error("attempt to concatenate a nil value", 0)
    end
    local copy = {}
    for i, v in ipairs(data) do
        copy[i] = v
    end
    objects = copy
end

getWorld = function()
    return {
        getMetaGrid = function()
            return {
                getZonesAt = function(_, x, y, z)
                    local found = {}
                    for key in pairs(world.present) do
                        local t, zx, zy, zz = string.match(key, "^(%S+) (%-?%d+),(%-?%d+),(%-?%d+)$")
                        if tonumber(zx) == x and tonumber(zy) == y and tonumber(zz) == z then
                            table.insert(found, {
                                getType = function()
                                    return t
                                end
                            })
                        end
                    end
                    return list(found)
                end,
                getVehicleZoneAt = function()
                    return nil
                end
            }
        end
    }
end

isClient = function()
    return false
end

getServerOptions = function()
    return {
        getOption = function(_, name)
            return name == "Map" and world.mapOption or nil
        end
    }
end

local function file(dir)
    return "media/maps/" .. dir .. "/objects.lua"
end

local function statuses(result)
    local out = {}
    for _, row in ipairs(result.maps) do
        out[#out + 1] = row.dir .. "=" .. row.status
    end
    return out
end

---------------------------------------------------------------------------
check.section("a healthy server says nothing")

setWorld({
    dirs = {"AZSpawn", "phuninteriors", "Muldraugh, KY"},
    mapOption = "AZSpawn;phuninteriors;Muldraugh, KY",
    files = {
        [file("AZSpawn")] = {zone("ZombiesType", 12861, 6169)},
        [file("phuninteriors")] = {zone("NoPowerOrWater", 22272, 11776, {width = 512, height = 768})},
        [file("Muldraugh, KY")] = {zone("ParkingStall", 12593, 966)}
    },
    present = {
        ["ZombiesType 12861,6169,0"] = true,
        ["NoPowerOrWater 22272,11776,0"] = true,
        ["ParkingStall 12593,966,0"] = true
    }
})
local result = Health.run()
check.equal("every map's zone is found", statuses(result),
    {"AZSpawn=present", "phuninteriors=present", "Muldraugh, KY=present"})
check.equal("no folder is missing", result.missingFolders, {})
check.ok("nothing stopped", result.stoppedAt == nil)
check.equal("so the boot check logs nothing", Health.problems(result), {})

---------------------------------------------------------------------------
check.section("a Map= entry with no folder")

-- The host tool's line: a literal "Map" that nothing installs
world.mapOption = "AZSpawn;phuninteriors;Map;Muldraugh, KY"
result = Health.run()
check.equal("is named", result.missingFolders, {"Map"})
local problems = Health.problems(result)
check.ok("and reported", #problems == 1 and string.find(problems[1], "'Map'", 1, true) ~= nil)

world.mapOption = " AZSpawn ; phuninteriors;;Muldraugh, KY "
result = Health.run()
check.equal("spaces and empty entries in Map= are not folders", result.missingFolders, {})

---------------------------------------------------------------------------
check.section("one map's objects.lua stops zone loading")

-- Hunter's Base: a parking stall, then a polygon WaterZone that throws, then a
-- spawn point that never registers. Zones load from the bottom of Map= up, so
-- everything above it is missing too, and vanilla below it is fine.
setWorld({
    dirs = {"AZSpawn", "phuninteriors", "hunter's_base", "Muldraugh, KY"},
    mapOption = "AZSpawn;phuninteriors;hunter's_base;Muldraugh, KY",
    files = {
        [file("AZSpawn")] = {zone("ZombiesType", 12861, 6169)},
        [file("phuninteriors")] = {zone("NoPowerOrWater", 22272, 11776, {width = 512, height = 768})},
        [file("hunter's_base")] = {zone("ParkingStall", 6079, 5772), {
            type = "WaterZone",
            geometry = "polygon",
            points = {}
        }, zone("SpawnPoint", 6082, 5757, {width = 1, height = 1})},
        [file("Muldraugh, KY")] = {zone("ParkingStall", 12593, 966)}
    },
    present = {
        ["ParkingStall 6079,5772,0"] = true,
        ["ParkingStall 12593,966,0"] = true
    }
})
result = Health.run()
check.equal("the map itself is caught: its first zone is in, its LAST is not", statuses(result),
    {"AZSpawn=missing", "phuninteriors=missing", "hunter's_base=broken", "Muldraugh, KY=present"})
check.equal("and it samples the spawn point after the water zone", result.maps[3].sample, "SpawnPoint 6082,5757,0")
check.equal("loading stopped at it", result.stoppedAt, 3)
problems = Health.problems(result)
check.ok("the log names it", #problems == 1 and string.find(problems[1], "'hunter's_base'", 1, true) ~= nil)
check.ok("as having thrown inside its own file", string.find(problems[1], "threw partway through its own", 1, true) ~= nil)
check.ok("and counts the maps that lost zones", string.find(problems[1], "3 map(s) from it up", 1, true) ~= nil)
check.ok("without offering the stale save, which this pattern rules out",
    string.find(problems[1], "map_zone.bin", 1, true) == nil)

-- A map that throws AFTER its last plain zone looks whole, and the map above
-- it takes the blame it cannot pin down: both suspects and the save are named
world.files[file("hunter's_base")] = {zone("ParkingStall", 6079, 5772), {
    type = "WaterZone",
    geometry = "polygon",
    points = {}
}}
result = Health.run()
check.equal("a throw after the last zone", statuses(result),
    {"AZSpawn=missing", "phuninteriors=missing", "hunter's_base=present", "Muldraugh, KY=present"})
problems = Health.problems(result)
check.ok("names the first missing map and the one below it", #problems == 1 and
    string.find(problems[1], "Either 'phuninteriors' or 'hunter's_base'", 1, true) ~= nil)
check.ok("and offers the stale save too", string.find(problems[1], "map_zone.bin", 1, true) ~= nil)

---------------------------------------------------------------------------
check.section("a listed map whose mod is not active")

-- Hunter's Base without Erikas Tiles: still in the lot directories, so the
-- old check called it installed, while vanilla dropped every building after it
setWorld({
    dirs = {"hunter's_base", "Muldraugh, KY"},
    uninstalled = {
        ["hunter's_base"] = true
    },
    mapOption = "hunter's_base;Muldraugh, KY",
    files = {
        [file("Muldraugh, KY")] = {zone("ParkingStall", 12593, 966)}
    },
    present = {
        ["ParkingStall 12593,966,0"] = true
    }
})
result = Health.run()
check.equal("is not installed", statuses(result), {"hunter's_base=not installed", "Muldraugh, KY=present"})
check.equal("and reported once, not again from Map=", result.missingFolders, {"hunter's_base"})
problems = Health.problems(result)
check.ok("with the reasons a mod is not active", #problems == 1 and
    string.find(problems[1], "missing one of the mods it requires", 1, true) ~= nil)

isClient = function()
    return true
end
result = Health.run()
check.equal("a client sees it too, with no Map= to read", result.missingFolders, {"hunter's_base"})
isClient = function()
    return false
end

---------------------------------------------------------------------------
check.section("what is never taken as a sample")

setWorld({
    dirs = {"forest"},
    files = {
        [file("forest")] = {zone("DeepForest", 1, 1), zone("Nav", 2, 2), zone("TownZone", 3, 3), {
            type = "Forest",
            geometry = "polygon",
            points = {}
        }, zone("ParkingStall", 4, 4, {width = 2244, height = 18})}
    }
})
result = Health.run()
check.equal("vegetation, nav, geometry and oversize zones give no sample rather than a miss",
    statuses(result), {"forest=no sample"})
check.ok("which is not a stop", result.stoppedAt == nil)
check.equal("nor a problem", Health.problems(result), {})

---------------------------------------------------------------------------
check.section("files that cannot be read")

setWorld({
    dirs = {"nofile", "broken"},
    files = {
        [file("broken")] = "throw"
    }
})
objects = {"left alone"}
result = Health.run()
check.equal("a map with no objects.lua and one that throws", statuses(result),
    {"nofile=no objects.lua", "broken=error: attempt to concatenate a nil value"})
check.equal("the objects global is put back afterwards", objects, {"left alone"})

---------------------------------------------------------------------------
check.section("on a client")

isClient = function()
    return true
end
setWorld({
    dirs = {"AZSpawn"},
    mapOption = "Map;AZSpawn",
    files = {
        [file("AZSpawn")] = {zone("ZombiesType", 12861, 6169)}
    },
    present = {
        ["ZombiesType 12861,6169,0"] = true
    }
})
result = Health.run()
check.ok("there is no Map= list to read", result.configured == nil)
check.equal("so no folder is reported missing", result.missingFolders, {})

check.finish()
