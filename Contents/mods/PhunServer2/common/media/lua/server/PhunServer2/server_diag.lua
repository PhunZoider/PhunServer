if isClient() then
    return
end

local Core = require "PhunServer2/core"
local Diag = require "PhunServer2/diag"
local Probe = require "PhunServer2/diag_probe"

-- The client gates /diag too, but a client can send whatever it likes. A probe
-- only reads, but it reads anywhere on the map, so it stays an admin tool.
local function mayProbe(player)
    if Core.isLocal then
        return true
    end
    if not player then
        return false
    end
    local level = player.getAccessLevel and player:getAccessLevel()
    return level == "admin" or level == "moderator"
end

Diag.serverHandlers[Diag.commands.probe] = function(player, args)
    if not mayProbe(player) then
        Diag.logLn("Rejected a probe from " .. tostring(player and player:getUsername() or "?") ..
                       ": insufficient access")
        return
    end
    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
    if not x or not y then
        return
    end
    local result = Probe.read(x, y, z or 0)
    result.token = args.token
    Diag.reply(player, Diag.commands.probeResult, result)
end

Events.OnClientCommand.Add(function(module, command, playerObj, arguments)
    if module == Diag.name and Diag.serverHandlers[command] then
        Diag.serverHandlers[command](playerObj, arguments or {})
    end
end)
