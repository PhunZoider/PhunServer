if isServer() then
    return
end

local Core = require "PhunServer2/core"
local Cmds = require "PhunServer2Commands/core"
local tools = Core.tools
local Commands = require "PhunServer2Commands/client_commands"

Events.OnServerCommand.Add(function(module, command, arguments)
    if module == Cmds.name and Commands[command] then
        Commands[command](arguments)
    end
end)

-- ---------------------------------------------------------------------------
-- Chat command registrations
--
-- Access is checked here rather than with the registry's `admin` flag because
-- each of these is gated by its own sandbox option as well as by role.
-- ---------------------------------------------------------------------------

Core.registerCommand("players", {
    handler = function(args)
        local mode = Cmds.getOption("PlayersCommand", 3)
        if mode == 1 then
            -- Disabled: fall through so vanilla or another mod can have it
            return false
        end
        if mode == 2 and not tools.isAdmin() then
            return getText("IGUI_PhunServer2_NoAccess")
        end
        sendClientCommand(Cmds.name, Cmds.commands.players, args)
        return true
    end
})

Core.registerCommand("hours", {
    handler = function(args)
        if Cmds.getOption("GetHours", true) == false and not tools.isAdmin() then
            return getText("IGUI_PhunServer2_NoAccess")
        end
        -- Only admins may query someone else
        if not tools.isAdmin() then
            args = {}
        end
        sendClientCommand(Cmds.name, Cmds.commands.getHours, args)
        return true
    end
})

Core.registerCommand("sethours", {
    handler = function(args)
        if Cmds.getOption("SetHours", true) == false or not tools.isAdmin() then
            return getText("IGUI_PhunServer2_NoAccess")
        end
        sendClientCommand(Cmds.name, Cmds.commands.setHours, args)
        return true
    end
})
