if isServer() then
    return
end

local Core = require "PhunServer2/core"
local tools = Core.tools

-- ---------------------------------------------------------------------------
-- Chat output primitives.
--
-- These live in core, not in PhunServer2Chat, because a server running only
-- core plus cron still has to be able to tell players it is about to restart.
-- PhunServer2Chat builds its cosmetic features on top of these.
-- ---------------------------------------------------------------------------

-- Builds a duck-typed ChatMessage the vanilla chat renderer will accept, so a
-- message can be injected without going through the network chat layer.
function Core.FakeMessage(message, color, options)

    if type(options) ~= "table" then
        options = {
            showTime = false,
            serverAlert = false,
            showAuthor = false
        }
    end

    if type(color) ~= "string" then
        color = "<RGB:1,1,1>"
    end

    if options.showTime then
        local dateStamp = Calendar.getInstance():getTime()
        local dateFormat = SimpleDateFormat.new("H:mm")
        if dateStamp and dateFormat then
            message = color .. "[" .. tostring(dateFormat:format(dateStamp) or "N/A") .. "]  " .. message
        end
    else
        message = color .. message
    end

    local msg = {
        getText = function(_)
            return message
        end,
        getTextWithPrefix = function(_)
            return message
        end,
        isServerAlert = function(_)
            return options.serverAlert
        end,
        isShowAuthor = function(_)
            return options.showAuthor
        end,
        getAuthor = function(_)
            local p = getPlayer()
            return p and tostring(p:getDisplayName()) or ""
        end,
        setShouldAttractZombies = function(_)
            return false
        end,
        setOverHeadSpeech = function(_)
            return false
        end
    }

    if not ISChat.instance or not ISChat.instance.chatText then
        return
    end

    ISChat.addLineInChat(msg, 0)
end

-- text may be a translation key or a literal.
function Core.message(text, args, options)
    local txt = getTextOrNull(text, unpack(args or {})) or text
    options = options or {
        color = "<RGB:255,255,0>"
    }
    Core.FakeMessage(txt, options.color)
end

function Core.notify(player, soundName, types, text, args)

    if soundName and soundName ~= "" and not player:getEmitter():isPlaying(soundName) then
        player:playSoundLocal(soundName)
    end

    if types == nil or types.chat then
        Core.message(text, args)
    end

    if types and types.halo then
        local unp = table.unpack or unpack
        player:setHaloNote(getText(text, unp(args or {})))
    end
end

function Core.notifyAll(soundName, types, text, args)
    local players = tools.onlinePlayers()
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p:isLocalPlayer() then
            Core.notify(p, soundName, types, text, args)
        end
    end
end
