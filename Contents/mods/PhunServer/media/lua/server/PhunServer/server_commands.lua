if isClient() then
    return
end
require "PhunServer/core"
local Core = PhunServer
local PL = PhunLib
local getTimestamp = getTimestamp
local Commands = {}

local function wipekeyCheck(username)

    if not Core.getOption("EnableWipeKey", false) then
        return
    end
    local wipeKey = Core.getOption("WipeKey", nil)
    if wipeKey and wipeKey ~= "" and wipeKey ~= Core.data.online[username].wipeKey then
        Core.data.online[username].wipeKey = wipeKey
        PL.debug("[" .. Core.name .. "] Player " .. username .. " has an outdated wipeKey, performing wipe.")
        sendServerCommand(Core.name, Core.commands.wipeMap, {
            username = username,
            args = {}
        })
    else
        Core.debugLn(username .. " has current wipeKey, no wipe needed.")
    end
end

Commands[Core.commands.playerSetup] = function(player, args)
    Core.debugLn("Setting up player " .. player:getUsername())
    wipekeyCheck(player:getUsername())
    Core.players[player:getOnlineID()] = {
        wipeKey = Core.getOption("WipeKey"),
        playerObj = player,
        username = player:getUsername(),
        online = true
    }
    Core.usernames[string.lower(player:getUsername())] = player:getUsername()
end

Commands[Core.commands.checkworkshop] = function(player, args)
    Core.pollWorkshop(player)
end

Commands[Core.commands.restart] = function(player, args)
    local restartSeconds = args and #args > 0 and (args[1] * 60) or (Core.getOption("RestartDelayMinutes", 5)) * 60;
    if restartSeconds <= 0 then
        restartSeconds = 1
    end
    print("[" .. Core.name .. "] Scheduling restart in " .. restartSeconds .. " seconds.")
    Core.scheduleServerRestart(getTimestamp() + restartSeconds)
end

Commands[Core.commands.players] = function(player, args)

    local today = Core.getOption("PlayersOffline24", false) == true

    local players = {
        online = {}
    }

    if today then
        players.offline = {}
    end

    local timeAgo = getTimestamp() - (24 * 60 * 60)
    for username, data in pairs(Core.data.online) do
        if data.lastSeen and data.lastSeen >= timeAgo and username ~= player:getUsername() then
            if data.online then
                table.insert(players.online, username)
            elseif today then
                table.insert(players.offline, username)
            end
        end
    end

    table.sort(players.online, function(a, b)
        return a:lower() < b:lower()
    end)
    table.sort(players.offline, function(a, b)
        return a:lower() < b:lower()
    end)

    Core.debugLn("Online players: " .. table.concat(players.online, ", "))
    if #players.offline > 0 then
        Core.debugLn("Offline players (last 24h): " .. table.concat(players.offline, ", "))
    end

    sendServerCommand(player, Core.name, Core.commands.players, {
        username = player:getUsername(),
        players = players
    })

end

return Commands
