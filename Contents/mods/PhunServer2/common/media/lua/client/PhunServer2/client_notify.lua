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

-- ---------------------------------------------------------------------------
-- Delivery, and why it is not just a call to addLineInChat.
--
-- Chat is not ready the instant a player connects. ISChat.instance exists well
-- before its tabs arrive from the server, and every renderer - vanilla's and
-- PhunServer2Chat's replacement alike - quietly drops a line whose tab it
-- cannot find. The join announcement fires within the server's two second
-- sweep, which lands squarely inside that window, so the welcome a player is
-- meant to see on arrival was being built and then thrown away.
--
-- Lines are held until there is somewhere to put them instead.
-- ---------------------------------------------------------------------------

-- Tab 0 is the General tab, which is where everything here is addressed.
local function chatReady()
    local instance = ISChat.instance
    if not instance or not instance.tabs then
        return false
    end
    for _, tab in ipairs(instance.tabs) do
        if tab and tab.tabID == 0 then
            return true
        end
    end
    return false
end

-- A cap in case chat never becomes ready at all: better to lose the oldest
-- notice than to grow a queue for the length of a session.
local maxPending = 32
local pending = {}
local waiting = false
local flushPending

flushPending = function()
    if not chatReady() then
        return
    end

    Events.OnTick.Remove(flushPending)
    waiting = false

    -- Swapped out before delivering: addLineInChat is replaced by other mods,
    -- and one that emits a line of its own must not append to the list being
    -- walked.
    local queued = pending
    pending = {}
    for _, msg in ipairs(queued) do
        ISChat.addLineInChat(msg, 0)
    end
end

local function deliver(msg)
    if chatReady() then
        ISChat.addLineInChat(msg, 0)
        return
    end

    if #pending >= maxPending then
        table.remove(pending, 1)
    end
    table.insert(pending, msg)

    if not waiting then
        waiting = true
        Events.OnTick.Add(flushPending)
    end
end

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

    deliver(msg)
end

-- text may be a translation key or a literal.
function Core.message(text, args, options)
    local txt = getTextOrNull(text, unpack(args or {})) or text
    options = options or {
        color = "<RGB:255,255,0>"
    }
    Core.FakeMessage(txt, options.color)
end

-- volume is the sandbox scale, 0..100. Nil means the caller has no opinion and
-- gets full volume; 0 means play nothing.
--
-- Through SoundManager rather than the character emitter. The emitter route
-- produces no audible sound for this clip: restartNotice is declared
-- is3D = false, and a non-positional clip played through a positional emitter
-- goes nowhere. playSoundLocal does work, but hands back no handle to set a
-- volume on. SoundManager:PlaySound returns an Audio, which does.
local function playChime(soundName, volume)
    if not soundName or soundName == "" then
        return
    end

    local level = tonumber(volume)
    if level == nil then
        level = 100
    end
    level = math.max(0, math.min(100, level))
    if level == 0 then
        return
    end

    local audio = getSoundManager():PlaySound(soundName, false, 0)
    if audio then
        audio:setVolume(level / 100)
    end
end

function Core.notify(player, soundName, types, text, args, volume)

    playChime(soundName, volume)

    if types == nil or types.chat then
        Core.message(text, args)
    end

    if types and types.halo then
        local unp = table.unpack or unpack
        player:setHaloNote(getText(text, unp(args or {})))
    end
end

function Core.notifyAll(soundName, types, text, args, volume)
    local players = tools.onlinePlayers()
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p:isLocalPlayer() then
            Core.notify(p, soundName, types, text, args, volume)
        end
    end
end
