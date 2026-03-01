if isServer() then
    return
end

local Core = PhunServer
local Commands = {}

Commands[Core.commands.wipeMap] = function(args)
    local player = Core.tools.getPlayerByUsername(args.username)
    if player then
        Core.map.wipeMap(player, (args or {}).args or {})
    end
end

Commands[Core.commands.notify] = function(args)
    Core.notifyAll(args.soundName, args.types, args.text, args.args)
end

Commands[Core.commands.message] = function(args)
    local player = Core.tools.getPlayerByUsername(args.username)
    if player then
        Core.message(args.text, args.args)
    end
end

Commands[Core.commands.updateLocations] = function(args)
    local playerLocations = Core.playerLocations
    for k, v in pairs(args or {}) do
        playerLocations[k] = {v[1] or false, v[2], v[3]}
    end

end

Commands[Core.commands.updateAllLocations] = function(args)
    Core.playerLocations = args or {}
end

Commands[Core.commands.getHoursSurvived] = function(args)
    local player = Core.tools.getPlayerByUsername(args.username)
    if player then
        local hours = args.hours
        local seconds = hours * 3600
        local text = Core.tools.secondsToText(seconds, {
            maxParts = 4,
            zeroText = "UI_PhunServer_LessThanMinute"
        })
        Core.message(getText("IGUI_PhunServer_PlayerHasSurvivedFor", args.player, text))
    end
end

Commands[Core.commands.welcomeFirstTime] = function(args)
    Core.welcomeFirstTime(args[1])
end

Commands[Core.commands.welcome] = function(args)
    Core.welcomeBack(args[1])
end

Commands[Core.commands.goodbye] = function(args)
    Core.playerLocations[args[1]] = nil
    if Core.getOption("GoodbyeAnnouncements", false) then
        Core.goodbye(args[1])
    end
end

Commands[Core.commands.players] = function(args)
    local player = Core.tools.getPlayerByUsername(args.username)
    if player then
        Core.playersList(args.players)
    end
end

Commands[Core.commands.quit] = function(args)
    getCore():quit()
end

Commands[Core.commands.onDawn] = function(args)
    Core:setIsNight(false)
end

Commands[Core.commands.onDusk] = function(args)
    Core:setIsNight(true)
end

Commands[Core.commands.scheduleData] = function(args)
    if Core.ui.schedulePanel then
        Core.ui.schedulePanel:onDataReceived(args.schedules or {}, args.saved)
    end
end

return Commands
