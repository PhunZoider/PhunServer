PhunServer = {
    name = "PhunServer",
    consts = {},
    data = {
        online = {},
        wipeKeys = {}
    },
    commands = {
        playerSetup = "playerSetup",
        notify = "notify",
        checkworkshop = "check",
        restart = "restart",
        welcome = "welcome",
        welcomeFirstTime = "welcomeFirstTime",
        goodbye = "goodbye",
        quit = "quit",
        players = "players",
        playersToday = "playersToday",
        message = "message",
        onDusk = "onDusk",
        onDawn = "onDawn",
        wipeMap = "wipeMap"
    },
    events = {
        OnReady = "PhunServerOnReady"
    },
    settings = {},
    ui = {},
    map = {
        pom = 1,
        pomm = 1
    },
    players = {},
    usernames = {}
}
local climateManager = nil
local gt = nil
local Core = PhunServer
local PL = PhunLib
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
    if Core.settings.debug then
        PL.debugLn("[" .. Core.name .. "] " .. str)
    end
end

function Core.debug(...)
    if Core.settings.debug then
        PL.debug(Core.name, ...)
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

        getSandboxOptions():getOptionByName("DayLength"):setValue(speed)
        getSandboxOptions():applySettings()
    end

    PL:setIsNight(value)

    -- if isServer() then
    --     sendServerCommand(self.name, value and self.commands.onDusk or self.commands.onDawn, {})
    -- end
    -- triggerEvent(value and self.events.OnDusk or self.events.OnDawn)
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
            PL.dawnTime = season:getDawn() + (enabled and self.getOption("DayOffset") or 0)
            PL.duskTime = season:getDusk() + (enabled and self.getOption("NightOffset") or 0)
        end
    end
    if PL.duskTime and PL.dawnTime then
        local currentTime = gt:getTimeOfDay()
        local night = currentTime > PL.duskTime or currentTime < PL.dawnTime
        if night ~= self.isNight then
            self:setIsNight(night)
        end
    end
end

