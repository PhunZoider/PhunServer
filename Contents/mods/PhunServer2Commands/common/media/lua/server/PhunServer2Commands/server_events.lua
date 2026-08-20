if isClient() then
    return
end

local Cmds = require "PhunServer2Commands/core"
local Commands = require "PhunServer2Commands/server_commands"

Events.OnClientCommand.Add(function(module, command, playerObj, arguments)
    if module == Cmds.name and Commands[command] then
        Commands[command](playerObj, arguments)
    end
end)
