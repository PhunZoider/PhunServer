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
}, "either")
refuses("both timing modes", {
    action = "modcheck",
    every = 5,
    at = {"03:00"}
}, "both")
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
check.finish()
