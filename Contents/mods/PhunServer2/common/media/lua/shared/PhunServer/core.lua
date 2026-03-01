PhunServer = {
    name = "PhunServer",
    consts = {},
    data = {
        online = {}
    },
    commands = {
        playerSetup = "playerSetup",
        notify = "notify",
        checkworkshop = "check",
        restart = "restart",
        setHoursSurvived = "sethours",
        getHoursSurvived = "hours",
        welcome = "welcome",
        welcomeFirstTime = "welcomeFirstTime",
        goodbye = "goodbye",
        quit = "quit",
        players = "players",
        playersToday = "playersToday",
        message = "message",
        onDusk = "onDusk",
        onDawn = "onDawn",
        wipeMap = "wipeMap",
        updateLocations = "updateLocations",
        updateAllLocations = "updateAllLocations"
    },
    tools = require "PhunServer/tools",
    events = {
        OnReady = "PhunServerOnReady"
    },
    settings = {},
    ui = {},
    playerLocations = {},
    map = {
        pom = 1,
        pomm = 1
    }
}
local climateManager = nil
local gt = nil
local Core = PhunServer

Core.isLocal = not isClient() and not isServer() and not isCoopHost()
Core.settings = SandboxVars[Core.name] or {}
for _, event in pairs(Core.events) do
    if not Events[event] then
        LuaEventManager.AddEvent(event)
    end
end

function Core:ini()

    Core.debugLn("Initializing core...")
    self.inied = true
    if not isClient() then
        self.serverStarted = getTimestamp()

        for k, v in pairs(Core.data.online) do
            v.online = false
        end
        self.started = getTimestamp()
        self.pendingReboot = false
        self.rebooting = false
    end
    triggerEvent(self.events.OnReady, self)
end

function Core.debugLn(str)
    if Core.settings.Debug then
        print("[" .. Core.name .. "] " .. str)
    end
end

function Core.debug(...)
    if Core.settings.Debug then
        Core.tools.debug(Core.name, ...)
    end
end

function Core.getOption(name, default)
    local n = Core.name .. "." .. name
    local val = getSandboxOptions():getOptionByName(n) and getSandboxOptions():getOptionByName(n):getValue()
    if val == nil then
        return default
    end
    return val
end

local lengthText = {"15 minutes", "30 minutes", "1 hour", "1.5 hours", "2 hours", "3 hours", "4 hours", "5 hours",
                    "6 hours", "7 hours", "8 hours", "9 hours", "10 hours", "11 hours", "12 hours", "13 hours",
                    "14 hours", "15 hours", "16 hours", "17 hours", "18 hours", "19 hours", "20 hours", "21 hours",
                    "22 hours", "23 hours"}

function Core:setIsNight(value)

    if self.isNight == value then
        return
    end
    self.isNight = value

    if self.getOption("EnableDayNightChange") == true then

        local speed = self.getOption("DaySpeed")
        if value then
            speed = self.getOption("NightSpeed")
        end
        local currentLength = getSandboxOptions():getOptionByName("DayLength"):getValue()
        if currentLength ~= speed then
            Core.debugLn(getText("It is now %1, setting DayLength from %2 to %3", (value and "Night" or "Day"),
                lengthText[getSandboxOptions():getOptionByName("DayLength"):getValue()], lengthText[speed]))
            getSandboxOptions():getOptionByName("DayLength"):setValue(speed)
            print("==========================")
            print("SAVING SANDBOX OPTIONS")
            print("==========================")
            getSandboxOptions():applySettings()
        end
    end

end

function Core:testNight()

    local enabled = self.getOption("EnableDayNightChange", false) == true

    if not climateManager and getClimateManager then
        climateManager = getClimateManager()
    end
    if not gt and getGameTime then
        gt = getGameTime()
    end
    if gt and climateManager and climateManager.getSeason then

        local season = climateManager:getSeason()
        if season and season.getDawn then
            local time = gt:getTimeOfDay()
            Core.dawnTime = season:getDawn() + (enabled and self.getOption("DayOffset") or 0)
            Core.duskTime = season:getDusk() + (enabled and self.getOption("NightOffset") or 0)
        end
    end
    if Core.duskTime and Core.dawnTime then
        local currentTime = gt:getTimeOfDay()
        local night = currentTime > Core.duskTime or currentTime < Core.dawnTime
        if night ~= self.isNight then
            self:setIsNight(night)
        end
    end
end

