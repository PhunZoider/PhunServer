if isServer() then
    return
end

local Chat = require "PhunServer2Chat/core"
require "PhunServer2Chat/client_announce"
require "PhunServer2Chat/client_render"

local Commands = {}

Commands[Chat.commands.welcomeFirstTime] = function(args)
    Chat.welcomeFirstTime(args[1])
end

Commands[Chat.commands.welcome] = function(args)
    Chat.welcomeBack(args[1])
end

Commands[Chat.commands.goodbye] = function(args)
    Chat.goodbye(args[1])
end

Events.OnServerCommand.Add(function(module, command, arguments)
    if module == Chat.name and Commands[command] then
        Commands[command](arguments)
    end
end)
