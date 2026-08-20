-- PhunServer2DayNight
--
-- Runs day and night at different speeds by swapping the vanilla DayLength
-- sandbox option at dawn and dusk.
--
-- The server is authoritative. v1 let every client run its own dawn/dusk test
-- and mutate its own local DayLength, which meant clients could disagree with
-- the server and with each other. Here the server decides and broadcasts.
local Core = require "PhunServer2/core"

PhunServer2DayNight = {
    name = "PhunServer2DayNight",
    core = Core,
    isNight = nil,
    dawnTime = nil,
    duskTime = nil,
    events = {
        OnDawn = "OnPhunServer2Dawn",
        OnDusk = "OnPhunServer2Dusk"
    },
    commands = {
        onDawn = "onDawn",
        onDusk = "onDusk"
    }
}

local DN = PhunServer2DayNight

DN.getOption = Core.optionGetter(DN.name)
DN.verboseLn = Core.logger(DN.name)

function DN.logLn(str)
    Core.logLn(str, DN.name)
end

for _, event in pairs(DN.events) do
    if not Events[event] then
        LuaEventManager.AddEvent(event)
    end
end

-- ---------------------------------------------------------------------------
-- Legacy PhunLib channel.
--
-- Other Phun mods listen for OnPhunLibDusk/OnPhunLibDawn, so we keep feeding
-- that channel. This is a soft bridge: there is no require=phunlib and every
-- touch is guarded on the global actually existing.
-- ---------------------------------------------------------------------------

local LEGACY_EVENTS = {
    dawn = "OnPhunLibDawn",
    dusk = "OnPhunLibDusk"
}
local LEGACY_COMMANDS = {
    dawn = "PhunLibOnDawn",
    dusk = "PhunLibOnDusk"
}

local legacyPrepared = false

local function prepareLegacy()
    if legacyPrepared then
        return
    end
    legacyPrepared = true

    for _, name in pairs(LEGACY_EVENTS) do
        if not Events[name] then
            LuaEventManager.AddEvent(name)
        end
    end

    -- PhunLib yields its own day/night cycle only when it sees a mod called
    -- "PhunServer" activated. Our id is phunserver2, so that check misses and
    -- PhunLib would run a competing cycle, double-firing the legacy events.
    -- Neutering its testNight is the same yield PhunLib already intends.
    if PhunLib and type(PhunLib.testNight) == "function" then
        PhunLib.testNight = function()
        end
        DN.verboseLn("PhunLib detected: suppressed its day/night cycle and bridging the legacy events")
    end
end

local function publishLegacy(isNight)
    prepareLegacy()

    local key = isNight and "dusk" or "dawn"

    if PhunLib then
        PhunLib.isNight = isNight
        PhunLib.dawnTime = DN.dawnTime
        PhunLib.duskTime = DN.duskTime
    end

    if isServer() then
        sendServerCommand("PhunLib", LEGACY_COMMANDS[key], {})
    end
    triggerEvent(LEGACY_EVENTS[key])
end

-- ---------------------------------------------------------------------------

-- Applies the speed for the current phase and publishes the transition.
-- Called on the server by the cycle test, and on clients by the broadcast.
function DN.setIsNight(value)

    if DN.isNight == value then
        return
    end
    DN.isNight = value

    if DN.getOption("EnableDayNightChange", true) == true then
        local speed = value and DN.getOption("NightSpeed", 3) or DN.getOption("DaySpeed", 3)
        local option = getSandboxOptions():getOptionByName("DayLength")
        if option and option:getValue() ~= speed then
            DN.verboseLn("It is now " .. (value and "night" or "day") .. ", setting DayLength from " ..
                             tostring(option:getValue()) .. " to " .. tostring(speed))
            option:setValue(speed)
            getSandboxOptions():applySettings()
        end
    end

    triggerEvent(value and DN.events.OnDusk or DN.events.OnDawn)
    publishLegacy(value)
end

return PhunServer2DayNight
