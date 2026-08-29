-- PhunServer2Cron
--
-- A real-world-clock scheduler for PhunServer2. Admins define jobs in
-- <Zomboid>/Lua/PhunServer2Cron.json; each job runs a named action from the
-- core action registry.
--
-- ModWatch lives here too: watching the Workshop for mod updates is just
-- another schedulable action ("modcheck"), so admins can decide when it runs
-- rather than being stuck with a fixed interval.
local Core = require "PhunServer2/core"

PhunServer2Cron = {
    name = "PhunServer2Cron",
    inied = false,
    core = Core,
    -- jobs[name] = normalised job table
    jobs = {},
    const = {
        configFile = "PhunServer2Cron.json",
        modDataName = "PhunServer2Cron",
        configVersion = 1
    },
    events = {
        OnJobsLoaded = "OnPhunServer2CronJobsLoaded",
        OnJobFired = "OnPhunServer2CronJobFired"
    },
    commands = {
        reload = "cronReload",
        check = "cronCheck"
    }
}

local Cron = PhunServer2Cron

Cron.getOption = Core.optionGetter(Cron.name)
Cron.verboseLn = Core.logger(Cron.name)

function Cron.logLn(str)
    Core.logLn(str, Cron.name)
end

for _, event in pairs(Cron.events) do
    if not Events[event] then
        LuaEventManager.AddEvent(event)
    end
end

return PhunServer2Cron
