if isClient() then
    return
end

local Core = require "PhunServer2/core"
-- Explicit rather than relying on core's own server_events having loaded first:
-- this is where broadcastNotify and the shutdown action come from.
require "PhunServer2/server_shutdown"
require "PhunServer2/server_config"
local Cron = require "PhunServer2Cron/core"
local schedule = require "PhunServer2Cron/schedule"

-- ---------------------------------------------------------------------------
-- Job loading and the tick runner.
--
-- The config file holds admin intent and is never written back by the runner.
-- Runtime state (when a job last ran, which announcements have gone out) lives
-- in ModData, so an admin can hand-edit their file without losing schedule
-- position and without the mod fighting their editor.
-- ---------------------------------------------------------------------------

-- Shipped when no config file exists, so a fresh install behaves like v1 did.
local DEFAULT_JOBS = {
    modwatch = {
        enabled = true,
        action = "modcheck",
        every = 5,
        everyUnit = "minutes"
    }
}

local function state()
    Cron.data = Cron.data or ModData.getOrCreate(Cron.const.modDataName)
    if not Cron.data.jobs then
        Cron.data.jobs = {}
    end
    return Cron.data.jobs
end

local function stateFor(name)
    local s = state()
    if not s[name] then
        s[name] = {}
    end
    return s[name]
end

function Cron.loadJobs()

    local data, version = Core.loadConfig(Cron.const.configFile, Cron.name)

    if data == nil then
        if Cron.getOption("SeedDefaults", true) then
            Cron.logLn("Seeding default jobs and writing ./Lua/" .. Cron.const.configFile)
            data = DEFAULT_JOBS
            Core.saveConfig(Cron.const.configFile, data, Cron.const.configVersion, Cron.name)
        else
            data = {}
        end
    end

    local jobs = {}
    local loaded, skipped = 0, 0

    for name, raw in pairs(data or {}) do
        local job, err = schedule.normalise(name, raw)
        if job then
            jobs[name] = job
            loaded = loaded + 1
            if job.enabled then
                Cron.logLn("Job '" .. name .. "': " .. schedule.describe(job))
            else
                Cron.logLn("Job '" .. name .. "' is disabled")
            end
        else
            skipped = skipped + 1
            Cron.logLn("Ignoring job '" .. tostring(name) .. "': " .. tostring(err))
        end
    end

    Cron.jobs = jobs
    Cron.logLn("Loaded " .. loaded .. " job(s)" .. (skipped > 0 and (", skipped " .. skipped) or ""))
    triggerEvent(Cron.events.OnJobsLoaded, jobs)

    return jobs
end

function Cron.reloadJobs()
    Cron.loadJobs()
    return Cron.jobs
end

-- How far ahead of its nominal time an action needs to be started. A shutdown
-- with 15 minutes of notice has to begin 15 minutes early so the server is
-- actually down at the scheduled moment, rather than starting its countdown
-- then. Actions opt in by declaring leadSeconds; everything else fires on time.
local function leadSecondsFor(job)
    local action = Core.actions[job.action]
    if not action or type(action.leadSeconds) ~= "function" then
        return 0
    end
    local ok, value = pcall(action.leadSeconds, job.args)
    if not ok or type(value) ~= "number" then
        return 0
    end
    return value
end

local function fire(job, nowEpoch)
    local s = stateFor(job.name)

    if job.runIfEmpty == false and Core.isServerEmpty() then
        Cron.verboseLn("Skipping job '" .. job.name .. "': server is empty")
        s.lastRun = nowEpoch
        return
    end

    Cron.logLn("Running job '" .. job.name .. "' (" .. job.action .. ")")
    s.lastRun = nowEpoch

    -- Copy rather than mutate: job.args is the loaded config and actions are
    -- free to do what they like with what we hand them.
    local args = Core.tools.shallowCopy(job.args or {})
    if job.runIfEmpty ~= nil and args.runIfEmpty == nil then
        args.runIfEmpty = job.runIfEmpty
    end

    Core.runAction(job.action, job, args)
    triggerEvent(Cron.events.OnJobFired, job.name, job.action)
end

local function announce(job, secondsUntil)
    if #job.announcements == 0 then
        return
    end
    local s = stateFor(job.name)
    -- Seeded by the cycle reset in evaluate(); this is only a safety net.
    s.announced = s.announced or {}

    for _, a in ipairs(job.announcements) do
        local key = tostring(a.before)
        if not s.announced[key] and secondsUntil <= a.before then
            s.announced[key] = true
            Core.broadcastNotify(a.text, {}, {
                types = {
                    chat = true
                }
            })
        end
    end
end

-- Evaluated once a second from the tick loop.
function Cron.evaluate()

    if Cron.getOption("EnableCron", true) ~= true then
        return
    end

    local nowSecs, nowDow = schedule.localNow()
    if not nowSecs then
        return
    end
    local nowEpoch = getTimestamp()

    for name, job in pairs(Cron.jobs or {}) do
        if job.enabled and Core.hasAction(job.action) then
            local s = stateFor(name)
            local untilDue = schedule.secondsUntilDue(job, nowSecs, nowDow, s.lastRun, nowEpoch)

            if untilDue ~= nil then
                local lead = leadSecondsFor(job)

                -- Identify the occurrence we are currently counting down to,
                -- rounded to the minute so per-tick jitter doesn't invent new
                -- cycles. Rolling to a new occurrence rearms the job.
                local cycle = math.floor((nowEpoch + untilDue) / 60)
                if s.cycle ~= cycle then
                    s.cycle = cycle
                    s.fired = false
                    -- Any announcement whose lead time has already elapsed when
                    -- we first see this occurrence is marked done rather than
                    -- sent. Otherwise starting the server ten minutes before a
                    -- job would immediately announce "in half an hour".
                    s.announced = {}
                    for _, a in ipairs(job.announcements) do
                        if untilDue <= a.before then
                            s.announced[tostring(a.before)] = true
                        end
                    end
                end

                announce(job, untilDue)

                -- The +1 is tick slack: untilDue only passes through zero
                -- momentarily, and s.fired stops the extra second re-firing.
                if not s.fired and untilDue <= lead + 1 then
                    s.fired = true
                    fire(job, nowEpoch)
                end
            end
        end
    end
end
