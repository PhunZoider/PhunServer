if isServer() then
    return
end

local Core = PhunServer
local PL = PhunLib
local Commands = {}

Commands[Core.commands.wipeMap] = function(args)
    local player = PL.getPlayerByUsername(args.username)
    if player then
        Core.map.wipeMap(player, (args or {}).args or {})
    end
end

Commands[Core.commands.notify] = function(args)
    Core.notifyAll(args.soundName, args.types, args.text, args.args)
end

Commands[Core.commands.message] = function(args)
    local player = PL.getPlayerByUsername(args.username)
    if player then
        Core.message(args.text, args.args)
    end
end

Commands[Core.commands.getHoursSurvived] = function(args)
    local player = PL.getPlayerByUsername(args.username)
    if player then
        local hours = args.hours
        local seconds = hours * 3600
        local text = PL.string.secondsToText(seconds, {
            maxParts = 4,
            zeroText = "UI_PhunLib_LessThanMinute"
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
    Core.goodbye(args[1])
end

Commands[Core.commands.players] = function(args)
    local player = PL.getPlayerByUsername(args.username)
    local finalText = ""
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

return Commands
