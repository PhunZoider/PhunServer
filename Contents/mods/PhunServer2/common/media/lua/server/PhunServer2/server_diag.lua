if isClient() then
    return
end

local Core = require "PhunServer2/core"
local Diag = require "PhunServer2/diag"
local Probe = require "PhunServer2/diag_probe"
local Health = require "PhunServer2/diag_health"

-- The boot health result, kept for the rest of the run. Zones and the map list
-- do not change while the server is up, so it stays true until the next
-- restart and nothing needs to re-read 37,000 zone entries per login. Set by
-- bootCheck below; declared here so the probe can report it too.
local bootResult = nil

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
    -- So a probe of a healthy square still says when the map list is not
    result.healthProblems = bootResult and #Health.problems(bootResult) or 0
    Diag.reply(player, Diag.commands.probeResult, result)
end

Diag.serverHandlers[Diag.commands.health] = function(player, args)
    if not mayProbe(player) then
        Diag.logLn("Rejected a map health check from " .. tostring(player and player:getUsername() or "?") ..
                       ": insufficient access")
        return
    end
    local result = Health.run()
    result.token = args.token
    Diag.reply(player, Diag.commands.healthResult, result)
end

-- Admins already told this boot, by username. A reconnect is not news.
local alerted = {}

local function runCheck()
    local ok, result = pcall(Health.run)
    if not ok then
        Diag.logLn("map health check failed to run: " .. tostring(result))
        return nil
    end
    return result
end

-- Once per boot, on the first tick, when the world and its zones have
-- certainly finished loading. Silent when healthy: a line every boot saying
-- nothing is wrong is how a log stops being read.
local function bootCheck()
    Events.OnTick.Remove(bootCheck)
    bootResult = runCheck()
    if not bootResult then
        return
    end
    for _, line in ipairs(Health.problems(bootResult)) do
        Diag.logLn("MAP HEALTH: " .. line)
    end
end
Events.OnTick.Add(bootCheck)

-- An admin joining a server with a problem is shown it, once per boot. Only
-- the server's answer is sent; the client runs its own check on receipt, so
-- the window opens with both columns and can say which kind of fault it is.
-- A healthy server sends nothing, so this costs nothing in the normal case.
local function alertOnJoin(username, player)
    if not username or alerted[username] or not player or not mayProbe(player) then
        return
    end
    -- In single player the join can beat the first tick
    if not bootResult then
        bootResult = runCheck()
    end
    if not bootResult or #Health.problems(bootResult) == 0 then
        return
    end
    alerted[username] = true
    Diag.reply(player, Diag.commands.healthAlert, bootResult)
end
Events[Core.events.OnPlayerJoined].Add(alertOnJoin)
Events[Core.events.OnPlayerRejoined].Add(alertOnJoin)

Events.OnClientCommand.Add(function(module, command, playerObj, arguments)
    if module == Diag.name and Diag.serverHandlers[command] then
        Diag.serverHandlers[command](playerObj, arguments or {})
    end
end)
