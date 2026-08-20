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

            if not record then
                -- Never seen this player before
                record = {
                    firstSeen = now
                }
                Core.data.online[username] = record
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
