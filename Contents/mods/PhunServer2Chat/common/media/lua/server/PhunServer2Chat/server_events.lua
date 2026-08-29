if isClient() then
    return
end

local Core = require "PhunServer2/core"
local Chat = require "PhunServer2Chat/core"

-- Core detects the join/leave; this module decides whether to say anything.

-- Staff hopping on and off to fix things is noise on a busy server, and on some
-- servers it is worse than noise: players who can see when no admin is watching
-- behave differently. One switch covers both directions, because announcing an
-- admin leaving but not arriving reads stranger than announcing neither.
local function announceable(username)
    if Chat.getOption("AnnounceAdmins", true) then
        return true
    end
    -- Core.isStaff comes from server_players, which core always loads.
    return not Core.isStaff(username)
end

Events[Core.events.OnPlayerJoined].Add(function(username)
    if Chat.getOption("WelcomeAnnounce", true) and announceable(username) then
        sendServerCommand(Chat.name, Chat.commands.welcomeFirstTime, {username})
    end
end)

Events[Core.events.OnPlayerRejoined].Add(function(username)
    if Chat.getOption("WelcomeAnnounce", true) and announceable(username) then
        sendServerCommand(Chat.name, Chat.commands.welcome, {username})
    end
end)

Events[Core.events.OnPlayerLeft].Add(function(username)
    if Chat.getOption("GoodbyeAnnouncements", true) and announceable(username) then
        sendServerCommand(Chat.name, Chat.commands.goodbye, {username})
    end
end)
