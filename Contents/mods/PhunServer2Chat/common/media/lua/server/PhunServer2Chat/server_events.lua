if isClient() then
    return
end

local Core = require "PhunServer2/core"
local Chat = require "PhunServer2Chat/core"

-- Core detects the join/leave; this module decides whether to say anything.

Events[Core.events.OnPlayerJoined].Add(function(username)
    if Chat.getOption("WelcomeAnnounce", true) then
        sendServerCommand(Chat.name, Chat.commands.welcomeFirstTime, {username})
    end
end)

Events[Core.events.OnPlayerRejoined].Add(function(username)
    if Chat.getOption("WelcomeAnnounce", true) then
        sendServerCommand(Chat.name, Chat.commands.welcome, {username})
    end
end)

Events[Core.events.OnPlayerLeft].Add(function(username)
    if Chat.getOption("GoodbyeAnnouncements", true) then
        sendServerCommand(Chat.name, Chat.commands.goodbye, {username})
    end
end)
