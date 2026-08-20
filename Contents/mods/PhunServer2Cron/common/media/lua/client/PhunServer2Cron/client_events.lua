if isServer() then
    return
end

local Core = require "PhunServer2/core"
local Cron = require "PhunServer2Cron/core"

-- Registered into core's shared chat-command registry, so these exist whether
-- or not the PhunServer2Commands mod is installed.

Core.registerCommand("check", {
    admin = true,
    handler = function(args)
        sendClientCommand(Cron.name, Cron.commands.check, args)
        return true
    end
})

Core.registerCommand("cron", {
    admin = true,
    handler = function(args)
        local sub = args and args[1] and string.lower(args[1]) or ""
        if sub == "reload" then
            sendClientCommand(Cron.name, Cron.commands.reload, {})
            return true
        end
        return getText("IGUI_PhunServer2Cron_Usage")
    end
})
