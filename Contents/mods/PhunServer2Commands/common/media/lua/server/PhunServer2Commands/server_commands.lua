if isClient() then
    return
end

local Core = require "PhunServer2/core"
local Cmds = require "PhunServer2Commands/core"
local tools = Core.tools
local Commands = {}

local function reply(player, text, args)
    if not player then
        return
    end
    sendServerCommand(player, Core.name, Core.commands.message, {
        username = player:getUsername(),
        text = text,
        args = args or {}
    })
end

Commands[Cmds.commands.players] = function(player, args)

    local includeRecent = Cmds.getOption("PlayersOffline24", false) == true
    local recent = Core.getRecentPlayers(24 * 60 * 60, player:getUsername())

    local payload = {
        online = recent.online
    }
    if includeRecent then
        payload.offline = recent.offline
    end

    Cmds.verboseLn("Online players: " .. table.concat(recent.online, ", "))

    sendServerCommand(player, Cmds.name, Cmds.commands.players, {
        username = player:getUsername(),
        players = payload
    })
end

Commands[Cmds.commands.getHours] = function(player, args)

    local name = tostring((type(args) == "table" and args[1]) or player:getUsername())

    Cmds.verboseLn("hours requested by " .. player:getUsername() .. " for " .. name)

    local p = tools.getPlayerByUsername(name)
    if p then
        sendServerCommand(player, Cmds.name, Cmds.commands.getHours, {
            username = player:getUsername(),
            player = p:getUsername(),
            hours = p:getHoursSurvived()
        })
    else
        reply(player, "IGUI_PhunServer2Commands_NoSuchPlayer", {name})
    end
end

Commands[Cmds.commands.setHours] = function(player, args)
    args = args or {}

    -- Supports both:
    --   /sethours <playername> <hours>
    --   /sethours <hours>              (applies to the caller)
    local a1, a2 = args[1], args[2]
    local name, hours

    if a2 == nil then
        hours = tonumber(a1)
        if hours ~= nil then
            name = player and player:getUsername() or nil
        else
            name = a1 and tostring(a1) or nil
        end
    else
        name = a1 and tostring(a1) or nil
        hours = tonumber(a2)
    end

    if not name or name == "" or hours == nil then
        reply(player, "IGUI_PhunServer2Commands_SetHoursUsage")
        return
    end

    local p = tools.getPlayerByUsername(name)
    if not p then
        reply(player, "IGUI_PhunServer2Commands_NoSuchPlayer", {name})
        return
    end

    Cmds.logLn(player:getUsername() .. " set hours survived for " .. p:getUsername() .. " to " .. tostring(hours))
    p:setHoursSurvived(hours)

    sendServerCommand(player, Cmds.name, Cmds.commands.getHours, {
        username = player:getUsername(),
        player = p:getUsername(),
        hours = p:getHoursSurvived()
    })
end

return Commands
