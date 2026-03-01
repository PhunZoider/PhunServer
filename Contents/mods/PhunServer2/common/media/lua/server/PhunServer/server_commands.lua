if isClient() then
    return
end
require "PhunServer/core"
local Core = PhunServer
local getTimestamp = getTimestamp
local Commands = {}

Commands[Core.commands.playerSetup] = function(player, args)
    Core.debugLn("Setting up player " .. player:getUsername())
    Core.wipeKeyCheck(player:getUsername())
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

    table.sort(players.online or {}, function(a, b)
        return a:lower() < b:lower()
    end)
    table.sort(players.offline or {}, function(a, b)
        return a:lower() < b:lower()
    end)

    Core.debugLn("Online players: " .. table.concat(players.online, ", "))
    if players.offline and #players.offline > 0 then
        Core.debugLn("Offline players (last 24h): " .. table.concat(players.offline, ", "))
    end

    sendServerCommand(player, Core.name, Core.commands.players, {
        username = player:getUsername(),
        players = players
    })

end

Commands[Core.commands.setHoursSurvived] = function(player, args)
    args = args or {}

    -- Support:
    --   /setsurvivedhours <playername> <hours>
    --   /setsurvivedhours <hours>            (applies to the caller)
    local a1 = args[1]
    local a2 = args[2]

    local hours
    local name

    -- If only one argument and it's numeric => hours for the caller
    if a2 == nil then
        hours = tonumber(a1)
        if hours ~= nil then
            name = player and player:getUsername() or nil
        else
            name = a1 and tostring(a1):lower() or nil
            hours = nil
        end
    else
        name = a1 and tostring(a1):lower() or nil
        hours = tonumber(a2)
    end

    Core.debugLn(
        "setHours command called by " .. tostring(player and player:getUsername() or "nil") .. " for player " ..
            tostring(name) .. " to " .. tostring(hours))

    if not name or name == "" or hours == nil then
        sendServerCommand(player, Core.name, Core.commands.message, {
            username = player:getUsername(),
            text = "Invalid arguments. Usage: /setsurvivedhours playername hours  OR  /setsurvivedhours hours",
            args = {}
        })
        return
    end

    local p = Core.tools.getPlayerByUsername(name)
    if p then
        Core.debugLn("Setting hours survived for player " .. p:getUsername() .. " to " .. tostring(hours))
        p:setHoursSurvived(hours)

        sendServerCommand(player, Core.name, Core.commands.getHoursSurvived, {
            username = player:getUsername(),
            player = p:getUsername(),
            hours = p:getHoursSurvived()
        })
        return
    end

    sendServerCommand(player, Core.name, Core.commands.message, {
        username = player:getUsername(),
        text = "Could not find an online player with name " .. tostring(name) .. ".",
        args = {}
    })
end

Commands[Core.commands.getHoursSurvived] = function(player, args)

    local name = tostring((args and type(args) == "table" and args[1]) or player:getUsername()):lower()

    Core.debugLn("getHoursSurvived command called by " .. player:getUsername() .. " for player " .. name)

    local p = Core.tools.getPlayerByUsername(name)
    if p then
        sendServerCommand(player, Core.name, Core.commands.getHoursSurvived, {
            username = player:getUsername(),
            player = p:getUsername(),
            hours = p:getHoursSurvived()
        })
    else
        sendServerCommand(player, Core.name, Core.commands.message, {
            username = player:getUsername(),
            text = "Could not find an online player with name " .. name .. ".",
            args = {}
        })
    end

end

Commands[Core.commands.getSchedules] = function(player, args)
    if not Core.tools.isAdmin(player) then return end
    sendServerCommand(player, Core.name, Core.commands.scheduleData, {
        schedules = Core.getSchedule()
    })
end

Commands[Core.commands.saveSchedules] = function(player, args)
    if not Core.tools.isAdmin(player) then return end
    Core.saveSchedules(args.schedules or {})
    sendServerCommand(player, Core.name, Core.commands.scheduleData, {
        schedules = Core.getSchedule(),
        saved = true
    })
end

return Commands
