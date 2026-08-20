if isClient() then
    return
end

local Core = require "PhunServer2/core"
local Wiper = require "PhunServer2Wiper/core"

-- ---------------------------------------------------------------------------
-- Wiping is always an explicit act.
--
-- Three rules keep it that way:
--
--   1. EnableWipe defaults to false. The admin has to opt in.
--   2. The first time this module sees a player it *adopts* the current wipe
--      key as their baseline instead of wiping. Only a key that changes after
--      a baseline exists causes a wipe. Without this, installing the mod on a
--      running server with a key already set would wipe everyone at once,
--      because their stored key would be nil and so would never match.
--   3. /wipemap gives admins an immediate, deliberate wipe, so rule 2 costs
--      them nothing when they genuinely do want one now.
-- ---------------------------------------------------------------------------

local function keys()
    Wiper.data = Wiper.data or ModData.getOrCreate(Wiper.const.modDataName)
    if not Wiper.data.wipeKeys then
        Wiper.data.wipeKeys = {}
    end
    return Wiper.data.wipeKeys
end

-- Sends the actual wipe instruction to one player.
local function sendWipe(username, args)
    local player = Core.tools.getPlayerByUsername(username)
    if not player then
        Wiper.verboseLn("Cannot wipe " .. tostring(username) .. ": they are not online")
        return false
    end
    sendServerCommand(player, Wiper.name, Wiper.commands.wipeMap, {
        username = username,
        args = args or {}
    })
    return true
end

-- Forces a wipe regardless of keys. Used by /wipemap.
function Wiper.forceWipe(username, args)
    Wiper.logLn("Forcing a map wipe for " .. tostring(username))
    -- Keep the baseline current so the forced wipe doesn't cause a second one
    keys()[username] = Wiper.getOption("WipeKey", "")
    return sendWipe(username, args)
end

function Wiper.forceWipeAll(args)
    local count = 0
    local online = Core.tools.onlinePlayers()
    for i = 0, online:size() - 1 do
        local username = online:get(i):getUsername()
        if username and username ~= "" and Wiper.forceWipe(username, args) then
            count = count + 1
        end
    end
    return count
end

-- Evaluated at login and after a new character is created.
function Wiper.check(username)

    if not username or username == "" then
        return
    end

    if Wiper.getOption("EnableWipe", false) ~= true then
        Wiper.verboseLn("Wiping is disabled, skipping the check for " .. username)
        return
    end

    local wipeKey = Wiper.getOption("WipeKey", "")
    if not wipeKey or wipeKey == "" then
        Wiper.verboseLn("No wipe key is set, nothing to do for " .. username)
        return
    end

    local store = keys()
    local known = store[username]

    if known == nil then
        -- Rule 2: adopt, never wipe on first sight
        store[username] = wipeKey
        Wiper.logLn("Recorded the current wipe key '" .. tostring(wipeKey) .. "' as the baseline for " .. username ..
                        ". No wipe performed.")
        return
    end

    if known == wipeKey then
        Wiper.verboseLn(username .. " is already on wipe key '" .. tostring(wipeKey) .. "'")
        return
    end

    Wiper.logLn(username .. " has an outdated wipe key (" .. tostring(known) .. " -> " .. tostring(wipeKey) ..
                    "), wiping their map")
    store[username] = wipeKey
    sendWipe(username, {})
end

-- A new character means a new wipe key for that player, so the next check
-- sees a genuine change and wipes.
function Wiper.resetForNewCharacter(username)
    if Wiper.getOption("EnableWipe", false) ~= true then
        return
    end
    if Wiper.getOption("WipePerCharacter", false) ~= true then
        return
    end
    if not username or username == "" then
        return
    end

    Wiper.logLn(username .. " created a new character, wiping their map")
    Wiper.forceWipe(username, {})
end

-- One clear line at startup, so the wipe state is never a surprise.
function Wiper.logState()
    local enabled = Wiper.getOption("EnableWipe", false) == true
    if not enabled then
        Wiper.logLn("Map wiping is DISABLED")
        return
    end
    local key = Wiper.getOption("WipeKey", "")
    Wiper.logLn("Map wiping is ENABLED. Current wipe key: '" .. tostring(key) .. "'" ..
                    ((key == "") and " (empty, so nothing will ever wipe)" or ""))
    Wiper.logLn("Players seen for the first time adopt this key without being wiped. Use /wipemap to wipe deliberately.")
end
