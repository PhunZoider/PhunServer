-- Cron job loading: seeding, the seeding guard, and job normalisation.
--
-- Run: ..\PhunTestKit\run.cmd . cron

local kit = require "phuntestkit"
local harness, check = kit.harness, kit.check

kit.installGlobals()
kit.addMod("PhunServer2")
kit.addMod("PhunServer2Cron")

local Core = require "PhunServer2/core"
require "PhunServer2/server_config"
local Cron = require "PhunServer2Cron/core"
local schedule = require "PhunServer2Cron/schedule"
require "PhunServer2Cron/server_jobs"

-- Everything past here runs without loadstring, load, loadfile or next.
kit.strip()

local CONFIG = Cron.const.configFile
local LEGACY = "PhunServer2Cron.txt"

local function jobCount()
    local n = 0
    for _ in pairs(Cron.jobs or {}) do
        n = n + 1
    end
    return n
end

---------------------------------------------------------------------------
check.section("the config file name")

check.same("cron reads a .json file", CONFIG, "PhunServer2Cron.json")

---------------------------------------------------------------------------
check.section("seeding a fresh install")

harness.reset()
harness.sandbox["PhunServer2Cron.SeedDefaults"] = true

Cron.loadJobs()
check.ok("a config file is written", (harness.files[CONFIG] or "") ~= "")
check.same("the default job is loaded", jobCount(), 1)
check.ok("and it is modwatch", Cron.jobs.modwatch ~= nil)
check.same("on a five minute interval", Cron.jobs.modwatch and Cron.jobs.modwatch.intervalSeconds, 300)

-- What was written has to be what we can read back, or the second start of a
-- fresh server behaves differently from the first.
local reloaded = Core.loadConfig(CONFIG, Cron.name)
check.equal("the seeded file reads back", reloaded, {
    modwatch = {
        enabled = true,
        action = "modcheck",
        every = 5,
        everyUnit = "minutes"
    }
})

---------------------------------------------------------------------------
check.section("seeding turned off")

harness.reset()
harness.sandbox["PhunServer2Cron.SeedDefaults"] = false

Cron.loadJobs()
check.ok("no config file is written", harness.files[CONFIG] == nil)
check.same("and no jobs run", jobCount(), 0)

---------------------------------------------------------------------------
check.section("an unconverted config is never written over")

-- The case that matters on upgrade. Seeding here would write a defaults file,
-- which stops loadConfig ever reporting the problem again: the server would
-- then quietly run the default job set while the admin believes their own jobs
-- are live. Running nothing is the honest outcome.
harness.reset()
harness.sandbox["PhunServer2Cron.SeedDefaults"] = true
harness.files[LEGACY] = "return {\n  version = 1,\n  data = {\n    nightly = { action = \"shutdown\", at = {\"03:00\"} },\n  },\n}"

Cron.loadJobs()
check.ok("no .json is created over the top of it", harness.files[CONFIG] == nil)
check.same("no jobs run", jobCount(), 0)
check.ok("the old file is left exactly as it was", harness.files[LEGACY]:find("return {", 1, true) == 1)

-- And the warning has to keep coming, not fire once and go quiet.
Cron.loadJobs()
check.ok("the state repeats on the next start", harness.files[CONFIG] == nil and jobCount() == 0)

-- Once converted, normal service resumes.
harness.files[CONFIG] = '{"version":1,"data":{"nightly":{"action":"shutdown","at":["03:00"]}}}'
Cron.loadJobs()
check.same("after conversion the job loads", jobCount(), 1)
check.ok("and it is the admin's job, not the default", Cron.jobs.nightly ~= nil and Cron.jobs.modwatch == nil)

---------------------------------------------------------------------------
check.section("loading an admin's config")

harness.reset()
harness.sandbox["PhunServer2Cron.SeedDefaults"] = true
Core.saveConfig(CONFIG, {
    ["nightly-restart"] = {
        enabled = true,
        action = "shutdown",
        args = {
            notice = 15
        },
        at = {"15:00", "03:00"},
        days = {"mon", "fri"},
        announcements = {{
            before = 60,
            text = "one minute"
        }, {
            before = 1800,
            text = "half an hour"
        }}
    },
    disabled = {
        enabled = false,
        action = "modcheck",
        every = 5
    },
    broken = {
        enabled = true,
        action = "modcheck"
    }
}, 1, Cron.name)

Cron.loadJobs()
check.same("the good jobs load and the broken one is skipped", jobCount(), 2)

local job = Cron.jobs["nightly-restart"]
check.ok("the clock job is there", job ~= nil)
check.same("its mode is 'at'", job and job.mode, "at")
check.equal("its times are parsed and sorted", job and job.at, {10800, 54000})
check.ok("its day filter is by number", job and job.days and job.days[1] == true and job.days[5] == true)
check.ok("no other day slipped in", job and job.days and job.days[2] == nil)
check.same("its args survive", job and job.args and job.args.notice, 15)
check.same("announcements are longest lead first", job and job.announcements[1] and job.announcements[1].before, 1800)
check.ok("a disabled job still loads", Cron.jobs.disabled ~= nil and Cron.jobs.disabled.enabled == false)

---------------------------------------------------------------------------
check.section("normalise refusals")

local function refuses(name, raw, mustMention)
    local job, err = schedule.normalise("x", raw)
    if job then
        return check.ok(name, false, "accepted it")
    end
    if mustMention and not tostring(err):find(mustMention, 1, true) then
        return check.ok(name, false, "said: " .. tostring(err))
    end
    return check.ok(name, true)
end

refuses("no action", {
    every = 5
}, "action")
refuses("no timing at all", {
    action = "modcheck"
}, "one of")
refuses("both timing modes", {
    action = "modcheck",
    every = 5,
    at = {"03:00"}
}, "only one")
refuses("a clock time and a phase", {
    action = "modcheck",
    at = {"03:00"},
    on = {"dusk"}
}, "only one")
refuses("an unknown phase", {
    action = "modcheck",
    on = {"noon"}
}, "dawn or dusk")
refuses("announcements on a phase job", {
    action = "modcheck",
    on = "dusk",
    announcements = {{
        before = 60,
        text = "soon"
    }}
}, "announcements")
refuses("a bad clock time", {
    action = "modcheck",
    at = {"3pm"}
}, "HH:MM")
refuses("a bad unit", {
    action = "modcheck",
    every = 5,
    everyUnit = "fortnights"
}, "everyUnit")
refuses("a zero interval", {
    action = "modcheck",
    every = 0
}, "greater than zero")
refuses("an unknown day", {
    action = "modcheck",
    every = 5,
    days = {"funday"}
}, "unknown day")
refuses("something that is not a table", "nope", "not a table")

---------------------------------------------------------------------------
check.section("bare strings")

local single = schedule.normalise("x", {
    action = "modcheck",
    at = "22:00"
})
check.equal("a single 'at' time is taken as a list of one", single and single.at, {79200})

local phase = schedule.normalise("x", {
    action = "modcheck",
    on = "Dusk"
})
check.ok("a single phase is too, case-insensitively", phase and phase.on.dusk == true and phase.on.dawn == nil)
check.ok("and it runs on startup by default", phase and phase.onStart == true)
check.ok("unless told not to", schedule.normalise("x", {
    action = "modcheck",
    on = "dawn",
    onStart = false
}).onStart == false)
check.same("it is never due by the clock", phase and schedule.secondsUntilDue(phase, 0, 1, nil, 0), nil)

---------------------------------------------------------------------------
check.section("dawn and dusk jobs")

local ran = {}
local function registerProbe()
    Core.registerAction("probe", {
        handler = function(job, args)
            ran[#ran + 1] = job.name .. ":" .. tostring(args.profile)
        end
    })
end

local function phaseJobs()
    harness.reset()
    harness.sandbox["PhunServer2Cron.SeedDefaults"] = true
    Core.saveConfig(CONFIG, {
        night = {
            action = "probe",
            on = {"dusk"},
            args = {
                profile = "night"
            }
        },
        day = {
            action = "probe",
            on = {"dawn"},
            onStart = false,
            args = {
                profile = "none"
            }
        }
    }, 1, Cron.name)
end

-- Day/Night publishes dusk before cron has loaded: nothing to run yet, and it
-- must not be swallowed either.
Cron.jobs = nil
PhunServer2DayNight = {
    isNight = true
}
triggerEvent("OnPhunServer2Dusk")
check.same("a phase before jobs load runs nothing", #ran, 0)

-- The real startup order: core loads jobs and Day/Night publishes dusk from
-- OnServerStarted, possibly before PhunZones has registered zoneprofile in its
-- own OnServerStarted. Nothing may run, or be marked done, until the first tick.
phaseJobs()
Cron.loadJobs()
triggerEvent("OnPhunServer2Dusk")
check.same("phase jobs are held until the first tick", #ran, 0)

registerProbe()
Cron.startPhases()
check.equal("the first tick catches up on dusk, with a late-registered action", ran, {"night:night"})

Cron.loadJobs()
check.same("a reload in the same phase does not run it again", #ran, 1)

triggerEvent("OnPhunServer2Dusk")
check.same("nor does a repeat of the same phase", #ran, 1)

triggerEvent("OnPhunServer2Dawn")
check.equal("dawn runs the dawn job", ran, {"night:night", "day:none"})

triggerEvent("OnPhunServer2Dusk")
check.equal("and dusk the dusk job again", ran, {"night:night", "day:none", "night:night"})

check.same("the clock runner leaves phase jobs alone", (function()
    local before = #ran
    Cron.evaluate()
    return #ran - before
end)(), 0)

PhunServer2DayNight = nil

---------------------------------------------------------------------------
check.section("game clock jobs")

refuses("a bad game time", {
    action = "probe",
    gameAt = {"25:00"}
}, "gameAt")
refuses("a game time and a real one", {
    action = "probe",
    gameAt = {"22:00"},
    at = {"22:00"}
}, "only one")
refuses("announcements on a game time", {
    action = "probe",
    gameAt = "22:00",
    announcements = {{
        before = 60,
        text = "soon"
    }}
}, "announcements")

local gameJob = schedule.normalise("x", {
    action = "probe",
    gameAt = {"22:30", "06:00"}
})
check.equal("game times are fractional hours, sorted", gameJob and gameJob.gameAt, {6, 22.5})
check.same("it is never due by the real clock", gameJob and schedule.secondsUntilDue(gameJob, 0, 1, nil, 0), nil)
check.same("and it describes itself", gameJob and schedule.describe(gameJob), "probe at game time 06:00, 22:30")

check.ok("a crossing within the day", schedule.gameTimeCrossed(22, 21.9, 22.1))
check.ok("landing exactly on it counts", schedule.gameTimeCrossed(22, 21.9, 22))
check.ok("starting exactly on it does not", not schedule.gameTimeCrossed(22, 22, 22.1))
check.ok("a crossing over midnight", schedule.gameTimeCrossed(0, 23.95, 0.05))
check.ok("a late time just before midnight", schedule.gameTimeCrossed(23.98, 23.95, 0.05))
check.ok("no crossing far from it", not schedule.gameTimeCrossed(6, 23.95, 0.05))

harness.reset()
harness.sandbox["PhunServer2Cron.SeedDefaults"] = true
Core.saveConfig(CONFIG, {
    curfew = {
        action = "probe",
        gameAt = {"22:00", "22:30"},
        args = {
            profile = "night"
        }
    }
}, 1, Cron.name)
Cron.loadJobs()
ran = {}

Cron.evaluateGameClock(22.2)
check.same("the first reading after boot runs nothing", #ran, 0)
Cron.evaluateGameClock(22.4)
check.same("nor does a step that crosses nothing", #ran, 0)
Cron.evaluateGameClock(22.5)
check.equal("crossing a time runs the job", ran, {"curfew:night"})
Cron.evaluateGameClock(22.5)
check.same("a repeated reading does not run it again", #ran, 1)
Cron.evaluateGameClock(21.5)
Cron.evaluateGameClock(22.75)
check.same("a big step over both times runs it once", #ran, 2)

---------------------------------------------------------------------------
check.finish()
