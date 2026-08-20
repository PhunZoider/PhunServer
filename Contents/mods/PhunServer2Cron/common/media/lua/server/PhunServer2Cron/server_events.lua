if isClient() then
    return
end

local Core = require "PhunServer2/core"
local Cron = require "PhunServer2Cron/core"
require "PhunServer2Cron/server_modwatch"
require "PhunServer2Cron/server_jobs"
local Commands = require "PhunServer2Cron/server_commands"

Events.OnInitGlobalModData.Add(function()
    Cron.data = ModData.getOrCreate(Cron.const.modDataName)
    if not Cron.data.jobs then
        Cron.data.jobs = {}
    end
end)

Events.OnClientCommand.Add(function(module, command, playerObj, arguments)
    if module == Cron.name and Commands[command] then
        Commands[command](playerObj, arguments)
    end
end)

-- Jobs are loaded once core is up, so the action registry is fully populated
-- by the time we validate job actions against it.
Events[Core.events.OnReady].Add(function()
    if Cron.inied then
        return
    end
    Cron.inied = true
    Cron.loadJobs()
end)

local nextTick = 0

Events.OnTickEvenPaused.Add(function()
    local now = getTimestamp()
    if now < nextTick then
        return
    end
    nextTick = now + 1
    Cron.evaluate()
end)

-- A departing player is a good moment to check: the server may now be empty,
-- which is the cheapest possible time to take it down for a mod update.
Events.OnDisconnect.Add(function()
    if Cron.getOption("EnableModWatch", true) == true and Cron.getOption("PollOnDisconnect", true) == true then
        Cron.pollWorkshop()
    end
end)
