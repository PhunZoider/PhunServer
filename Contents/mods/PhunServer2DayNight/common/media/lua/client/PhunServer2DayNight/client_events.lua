if isServer() then
    return
end

local DN = require "PhunServer2DayNight/core"

-- Clients only ever react to the server's decision. They never test the cycle
-- themselves, which is what made v1's clients disagree with the server.

local Commands = {}

Commands[DN.commands.onDawn] = function(args)
    DN.setIsNight(false)
end

Commands[DN.commands.onDusk] = function(args)
    DN.setIsNight(true)
end

Events.OnServerCommand.Add(function(module, command, arguments)
    if module == DN.name and Commands[command] then
        Commands[command](arguments)
    end
end)
