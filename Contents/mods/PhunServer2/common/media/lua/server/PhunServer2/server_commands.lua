if isClient() then
    return
end

local Core = require "PhunServer2/core"
local Commands = {}

-- Core's own client->server surface is deliberately tiny. Feature modules add
-- their own routers against their own module name.

Commands[Core.commands.playerSetup] = function(player, args)
    if not player then
        return
    end
    Core.verboseLn("Setting up player " .. tostring(player:getUsername()))
    -- Modules hook OnPlayerJoined/Rejoined rather than extending this.
end

-- /restart [minutes]. With no argument the ModWatch notice period is used when
-- cron is installed, otherwise five minutes.
Commands[Core.commands.restart] = function(player, args)
    local minutes = args and args[1] and tonumber(args[1])

    if minutes == nil then
        minutes = Core.getOptionFor("PhunServer2Cron", "RestartDelayMinutes", 5)
    end

    local seconds = math.floor(minutes * 60)
    if seconds < 1 then
        seconds = 1
    end

    Core.scheduleShutdown(getTimestamp() + seconds, {
        reason = "/restart by " .. tostring(player and player:getUsername() or "console"),
        runIfEmpty = true
    })
end

Commands[Core.commands.cancelRestart] = function(player, args)
    local cancelled = Core.cancelShutdown("/restart cancelled by " ..
                                              tostring(player and player:getUsername() or "console"))
    if player then
        sendServerCommand(player, Core.name, Core.commands.message, {
            username = player:getUsername(),
            text = cancelled and "IGUI_PhunServer2_RestartCancelled" or "IGUI_PhunServer2_NoRestartPending"
        })
    end
end

return Commands
