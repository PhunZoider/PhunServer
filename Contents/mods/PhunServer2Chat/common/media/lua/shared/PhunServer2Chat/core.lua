-- PhunServer2Chat
--
-- Everything cosmetic about chat: join and leave announcements, username
-- highlighting, and tidier rendering of music and radio lines.
--
-- Announcements are driven by the player events core publishes, so this module
-- never polls and never needs to know how players are tracked.
local Core = require "PhunServer2/core"

PhunServer2Chat = {
    name = "PhunServer2Chat",
    core = Core,
    commands = {
        welcome = "welcome",
        welcomeFirstTime = "welcomeFirstTime",
        goodbye = "goodbye"
    }
}

local Chat = PhunServer2Chat

Chat.getOption = Core.optionGetter(Chat.name)
Chat.verboseLn = Core.logger(Chat.name)

function Chat.logLn(str)
    Core.logLn(str, Chat.name)
end

return PhunServer2Chat
