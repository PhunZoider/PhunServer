if isClient() then
    return
end

local Core = require "PhunServer2/core"
local tools = Core.tools

function Core.isServerEmpty()
    return getOnlinePlayers():size() == 0
end

function Core.getPlayerCount()
    return getOnlinePlayers():size()
end

-- Usernames seen in the most recent sweep, so departures can be detected.
local onliners = {}
local wasEmpty = nil

local function accessLevelOf(player)
    local level = player and player:getAccessLevel()
    if not level or tostring(level) == "" then
        return "none"
    end
    return string.lower(tostring(level))
end

-- True when the account has any access level above "none": admin, moderator,
-- overseer, gm or observer.
--
-- Reads the level recorded on the player record rather than asking the
-- IsoPlayer, because the caller that needs it most is the departure handler,
-- and by the time that fires there is no IsoPlayer left to ask. An unknown
-- username answers false, which treats a stranger as an ordinary player.
function Core.isStaff(username)
    local record = username and Core.data and Core.data.online and Core.data.online[username]
    local level = record and record.accessLevel
    return level ~= nil and level ~= "" and level ~= "none"
end

-- Polled from the server tick. Maintains data.online and fires the join/leave
-- events other modules listen to. Deliberately emits no chat of its own -
-- PhunServer2Chat subscribes to these events and decides what to say.
function Core.checkPlayers()

    local online = tools.onlinePlayers()
    local now = getTimestamp()

    for i = 0, online:size() - 1 do
        local p = online:get(i)
        local username = p:getUsername()

        if username and username ~= "" then
            onliners[username] = true
            local record = Core.data.online[username]
            local firstTime = record == nil

            if firstTime then
                -- Never seen this player before
                record = {
                    firstSeen = now
                }
                Core.data.online[username] = record
            end

            -- Written before the events fire, not after. Handlers ask whether
            -- the joining player is staff, and on a first connection the record
            -- is the only place that answer can come from.
            --
            -- Refreshed every sweep rather than only at join, so promoting
            -- someone mid-session takes effect without them reconnecting, and
            -- it stays on the record after they go, which is what makes their
            -- departure judgeable at all.
            record.accessLevel = accessLevelOf(p)

            if firstTime then
                Core.verboseLn("Player connected for the first time: " .. username)
                triggerEvent(Core.events.OnPlayerJoined, username, p)
            elseif not record.online then
                Core.verboseLn("Player re-connected: " .. username)
                triggerEvent(Core.events.OnPlayerRejoined, username, p)
            end

            record.lastSeen = now
            record.online = true
        end
    end

    for name in pairs(onliners) do
        local record = Core.data.online[name]
        if record and record.online then
            -- A player missing from two consecutive sweeps has gone
            if now - (record.lastSeen or 0) > 1 then
                Core.verboseLn("Player disconnected: " .. name)
                record.online = false
                onliners[name] = nil
                triggerEvent(Core.events.OnPlayerLeft, name)
            end
        end
    end

    -- Fire once on the transition, not every tick while empty
    local empty = Core.isServerEmpty()
    if empty and wasEmpty == false then
        Core.verboseLn("Server is now empty")
        triggerEvent(Core.events.OnEmptyServer)
    end
    wasEmpty = empty
end

-- Usernames seen within the last `seconds`, split by whether they are on now.
function Core.getRecentPlayers(seconds, excludeUsername)
    local cutoff = getTimestamp() - (seconds or 86400)
    local result = {
        online = {},
        offline = {}
    }

    for username, data in pairs(Core.data.online or {}) do
        if username ~= excludeUsername and data.lastSeen and data.lastSeen >= cutoff then
            table.insert(data.online and result.online or result.offline, username)
        end
    end

    local byName = function(a, b)
        return string.lower(a) < string.lower(b)
    end
    table.sort(result.online, byName)
    table.sort(result.offline, byName)

    return result
end
