if isServer() then
    return
end

local Core = require "PhunServer2/core"
local Wiper = require "PhunServer2Wiper/core"
local tools = Core.tools
require "PhunServer2Wiper/client_wipe"

local Commands = {}

Commands[Wiper.commands.wipeMap] = function(args)
    -- Targeted, but split-screen means a client can hold several players
    local player = tools.getPlayerByUsername(args.username)
    if player then
        Wiper.wipeMap(player, args.args or {})
    end
end

Events.OnServerCommand.Add(function(module, command, arguments)
    if module == Wiper.name and Commands[command] then
        Commands[command](arguments)
    end
end)

Core.registerCommand("wipemap", {
    admin = true,
    handler = function(args)
        local target = args and args[1]
        if not target or target == "" then
            return getText("IGUI_PhunServer2Wiper_Usage")
        end
        sendClientCommand(Wiper.name, Wiper.commands.wipeRequest, {
            target = string.lower(target) == "all" and "all" or target
        })
        return true
    end
})
