-- The square probe: one ordered list of facts about a square, read the same
-- way on whichever side runs it.
--
-- The client and the server both call Probe.read with the same coordinates,
-- so any difference in the window comes from what each side holds, never
-- from two implementations of the reading drifting apart. Add a fact here and
-- both columns grow it.
--
-- Every reader is pcall'd. A probe is for a world that is already broken in
-- some way, so it must report "error" for one fact and carry on rather than
-- lose the rest of the table.
--
-- Values are always strings. They cross the wire as a flat table, and a
-- string compares the same on both sides however the engine serialised it.
local Probe = {}

-- Readers that only need the square return this when it is not loaded. On the
-- server that is normal for anywhere no player is standing; zones, buildings
-- and cell counts come from the meta grid and still answer.
local NOT_LOADED = "(square not loaded)"

local function bool(v)
    if v == nil then
        return "-"
    end
    return v and "true" or "false"
end

local function squareBool(method)
    return function(ctx)
        if not ctx.square then
            return NOT_LOADED
        end
        return bool(ctx.square[method](ctx.square))
    end
end

-- "map", "player-built" or "none", for a BuildingDef. Player-built is the
-- region system's stand-in for an enclosed area no map defines, and it never
-- takes grid power: the tell for a map whose own buildings were dropped.
local function buildingKind(def)
    if not def then
        return "none"
    end
    return def:isUserDefined() and "player-built" or "map"
end

local function cellData(ctx)
    return getWorld():getMetaGrid():getCellData(ctx.cellX, ctx.cellY)
end

-- Ordered. `long` fields are drawn on lines of their own under the table.
Probe.FIELDS = {{
    key = "square",
    read = function(ctx)
        return ctx.square and "loaded" or "not loaded"
    end
}, {
    key = "cell",
    read = function(ctx)
        return ctx.cellX .. "," .. ctx.cellY
    end
}, {
    key = "room",
    read = function(ctx)
        if not ctx.square then
            return NOT_LOADED
        end
        local room = ctx.square:getRoom()
        if not room then
            return "none"
        end
        local name = room:getName()
        return (name and name ~= "") and name or "(no name)"
    end
}, {
    key = "squareBuilding",
    read = function(ctx)
        if not ctx.square then
            return NOT_LOADED
        end
        local building = ctx.square:getBuilding()
        return buildingKind(building and building:getDef())
    end
}, {
    key = "mapBuilding",
    read = function(ctx)
        return buildingKind(getWorld():getMetaGrid():getBuildingAt(ctx.x, ctx.y))
    end
}, {
    key = "hasGridPower",
    read = squareBool("hasGridPower")
}, {
    key = "haveElectricity",
    read = squareBool("haveElectricity")
}, {
    -- isNoPower is true for any ONE of the three below, which is why all
    -- three are listed: a bare "true" here says nothing about which.
    key = "isNoPower",
    read = squareBool("isNoPower")
}, {
    key = "isDerelict",
    read = squareBool("isDerelict")
}, {
    key = "isUserDefinedRoom",
    read = squareBool("isUserDefinedRoom")
}, {
    key = "noPowerZone",
    read = function(ctx)
        -- isNoPower asks for zones at level 0 whatever level the square is on
        local zones = getWorld():getMetaGrid():getZonesAt(ctx.x, ctx.y, 0)
        if zones then
            for i = 0, zones:size() - 1 do
                local t = zones:get(i):getType()
                if t == "NoPower" or t == "NoPowerOrWater" then
                    return t
                end
            end
        end
        return "none"
    end
}, {
    key = "isOutside",
    read = squareBool("isOutside")
}, {
    key = "powerGrid",
    read = function()
        return bool(getSandboxOptions():doesPowerGridExist())
    end
}, {
    key = "hydro",
    read = function()
        return bool(getWorld():isHydroPowerOn())
    end
}, {
    key = "elecShut",
    read = function()
        return tostring(getSandboxOptions():getElecShutModifier())
    end
}, {
    key = "day",
    read = function()
        return tostring(math.floor(getGameTime():getWorldAgeHours() / 24))
    end
}, {
    key = "cellRooms",
    read = function(ctx)
        local cell = cellData(ctx)
        return cell and tostring(cell:getRoomCount()) or "no cell data"
    end
}, {
    -- Map-defined against player-built is the ratio that matters. A cell
    -- whose map buildings have gone and whose player-built count has risen
    -- lost its buildings at load, see the Map= list.
    key = "cellBuildingsMap",
    read = function(ctx)
        local cell = cellData(ctx)
        return cell and tostring(cell:getBuildingCount(true)) or "no cell data"
    end
}, {
    key = "cellBuildingsUser",
    read = function(ctx)
        local cell = cellData(ctx)
        return cell and tostring(cell:getBuildingCount() - cell:getBuildingCount(true)) or "no cell data"
    end
}, {
    -- Every zone, not getZoneType(), which reports one per square and so hid
    -- a NoPowerOrWater zone behind a DeepForest one.
    key = "zones",
    long = true,
    read = function(ctx)
        local zones = getWorld():getMetaGrid():getZonesAt(ctx.x, ctx.y, 0)
        local names = {}
        if zones then
            for i = 0, zones:size() - 1 do
                local zone = zones:get(i)
                local name = zone:getName()
                local label = tostring(zone:getType())
                if name and name ~= "" then
                    label = label .. " (" .. name .. ")"
                end
                table.insert(names, label)
            end
        end
        if #names == 0 then
            return "none"
        end
        -- Sorted so the same set reads the same on both sides
        table.sort(names)
        return table.concat(names, ", ")
    end
}}

-- Reads every field at x, y, z. Returns a flat {key = string} table.
function Probe.read(x, y, z)
    x, y, z = math.floor(tonumber(x) or 0), math.floor(tonumber(y) or 0), math.floor(tonumber(z) or 0)
    local ctx = {
        x = x,
        y = y,
        z = z,
        cellX = math.floor(x / 256),
        cellY = math.floor(y / 256),
        square = getCell() and getCell():getGridSquare(x, y, z)
    }
    local result = {}
    for _, field in ipairs(Probe.FIELDS) do
        local ok, value = pcall(field.read, ctx)
        if not ok then
            value = "error: " .. tostring(value)
        elseif value == nil then
            value = "-"
        end
        result[field.key] = tostring(value)
    end
    return result
end

return Probe
