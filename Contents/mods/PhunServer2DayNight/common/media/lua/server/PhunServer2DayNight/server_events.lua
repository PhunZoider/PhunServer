if isClient() then
    return
end

local Core = require "PhunServer2/core"
local DN = require "PhunServer2DayNight/core"

local climateManager = nil
local gt = nil

-- Recomputes dawn and dusk for the current season and, if the phase changed,
-- applies it and tells every client.
function DN.testNight()

    local enabled = DN.getOption("EnableDayNightChange", true) == true

    if not climateManager and getClimateManager then
        climateManager = getClimateManager()
    end
    if not gt and getGameTime then
        gt = getGameTime()
    end

    if gt and climateManager and climateManager.getSeason then
        local season = climateManager:getSeason()
        if season and season.getDawn then
            DN.dawnTime = season:getDawn() + (enabled and DN.getOption("DayOffset", 0) or 0)
            DN.duskTime = season:getDusk() + (enabled and DN.getOption("NightOffset", 0) or 0)
        end
    end

    if not (gt and DN.duskTime and DN.dawnTime) then
        return
    end

    local currentTime = gt:getTimeOfDay()
    local night = currentTime > DN.duskTime or currentTime < DN.dawnTime

    if night ~= DN.isNight then
        DN.setIsNight(night)
        -- Clients apply the same change rather than working it out themselves
        sendServerCommand(DN.name, night and DN.commands.onDusk or DN.commands.onDawn, {})
    end
end

Events[Core.events.OnReady].Add(function()
    DN.testNight()
end)

Events.EveryOneMinute.Add(function()
    DN.testNight()
end)
