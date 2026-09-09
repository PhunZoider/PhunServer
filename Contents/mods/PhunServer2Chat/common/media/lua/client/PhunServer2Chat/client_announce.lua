if isServer() then
    return
end

local Core = require "PhunServer2/core"
local Chat = require "PhunServer2Chat/core"

-- Known usernames, lowercased, used both for highlighting and to keep a
-- departed player's name coloured for the rest of the session.
--
-- The table belongs to core, which the server pushes its roster into. That is
-- the only way a client can learn a username belonging to somebody outside its
-- loaded cells. This used to be built from tools.onlinePlayers, which narrows
-- to local players on a client, so the lookup held little beyond your own name
-- plus whoever you happened to watch arrive - which is why highlighting worked
-- for some names and not others.
Chat.players = Core.knownPlayers
Chat.rememberPlayer = Core.rememberPlayer

function Chat.getPlayers()
    -- Top up from whoever is locally visible. The roster covers multiplayer;
    -- this is what keeps highlighting working in single player and on a coop
    -- host, where no roster is ever sent. Passing false asks the helper for
    -- every player it can see rather than only the local ones.
    local online = Core.tools.onlinePlayers(false)
    for i = 0, online:size() - 1 do
        Chat.rememberPlayer(online:get(i):getUsername())
    end
    return Chat.players
end

-- `text` is either one of our translation keys or an admin's literal string.
-- getText only substitutes %1 for a string it actually resolved, so a custom
-- literal has to be substituted by hand. v1 didn't, which meant the documented
-- %1 placeholder silently appeared verbatim in chat.
local function resolve(text, username)
    local translated = getTextOrNull(text, username)
    if translated then
        return translated
    end
    return (tostring(text):gsub("%%1", username))
end

local function announce(text, username, color)
    Chat.rememberPlayer(username)
    Core.message(resolve(text, username), {}, {
        color = color or "<RGB:255,255,0>"
    })
end

local function isSelf(username)
    local p = getPlayer()
    return p and p:getUsername() == username
end

-- An admin-supplied custom string wins over the random default variants.
local function customOr(optionName, fallback)
    local txt = Chat.getOption(optionName, "")
    if txt and txt ~= "" then
        return txt
    end
    return fallback
end

function Chat.welcomeFirstTime(username)
    if not Chat.getOption("WelcomeAnnounce", true) then
        return
    end
    if isSelf(username) then
        announce(customOr("WelcomeAnnounceText", "IGUI_PhunServer2Chat_WelcomeMyFirstTime"), username, "<RGB:0,255,0>")
    else
        announce(customOr("WelcomeAnnounceText", "IGUI_PhunServer2Chat_WelcomeFirstTime"), username)
    end
end

function Chat.welcomeBack(username)
    if not Chat.getOption("WelcomeAnnounce", true) then
        return
    end
    if isSelf(username) then
        announce(customOr("WelcomeAnnounceText", "IGUI_PhunServer2Chat_WelcomeBack"), username, "<RGB:0,255,0>")
    else
        announce(customOr("WelcomeAnnounceText", "IGUI_PhunServer2Chat_Welcome" .. tostring(ZombRand(4))), username)
    end
end

function Chat.goodbye(username)
    if not Chat.getOption("GoodbyeAnnouncements", true) then
        return
    end
    -- No point telling players they themselves have left
    if isSelf(username) then
        return
    end
    announce(customOr("GoodbyeAnnounceText", "IGUI_PhunServer2Chat_Goodbye" .. tostring(ZombRand(4))), username,
        "<RGB:255,255,0>")
end
