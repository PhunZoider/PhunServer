-- Schedule maths for PhunServer2Cron.
--
-- Everything here works in *local wall-clock* terms, expressed as relative
-- offsets from now. That deliberately avoids epoch/timezone conversion: we
-- never need to know what "03:00 tomorrow" is in epoch seconds, only how far
-- away it is. The server's timezone therefore never has to be configured, and
-- a DST change costs at most a one-off hour shift on the day it happens.
--
-- The local clock itself comes from whichever source the host Lua state
-- actually offers; see pickClockSource.
local Cron = require "PhunServer2Cron/core"

local schedule = {}

local DAYS = {
    mon = 1,
    tue = 2,
    wed = 3,
    thu = 4,
    fri = 5,
    sat = 6,
    sun = 7
}

local VALID_UNITS = {
    minutes = 60,
    hours = 3600,
    days = 86400
}

-- Reading the local wall clock is the one thing here that depends on what the
-- host Lua state actually exposes, so we probe once and remember. Java's
-- Calendar is preferred and is what the game itself uses; os.date is a fine
-- second choice; falling back to UTC is correct but will surprise an admin in
-- another timezone, so it says so loudly.
local clockSource = nil
local fmtClock = nil
local fmtDow = nil

local function pickClockSource()
    if clockSource then
        return clockSource
    end

    if Calendar and SimpleDateFormat then
        local ok = pcall(function()
            fmtClock = SimpleDateFormat.new("HH:mm:ss")
            -- "u" is ISO-8601 day of week: 1 = Monday .. 7 = Sunday
            fmtDow = SimpleDateFormat.new("u")
            local _ = fmtClock:format(Calendar.getInstance():getTime())
        end)
        if ok then
            clockSource = "calendar"
            return clockSource
        end
    end

    if os and os.date then
        local ok = pcall(function()
            local _ = os.date("*t")
        end)
        if ok then
            clockSource = "os"
            Cron.logLn("Using os.date for schedule times (Java Calendar was unavailable)")
            return clockSource
        end
    end

    clockSource = "utc"
    Cron.logLn("WARNING: no local clock available, schedule times will be interpreted as UTC")
    return clockSource
end

-- Returns secondsIntoDay, dayOfWeek(1=Mon..7=Sun) for the server's local clock.
function schedule.localNow()
    local source = pickClockSource()

    if source == "calendar" then
        local stamp = Calendar.getInstance():getTime()
        local text = tostring(fmtClock:format(stamp))
        local h, m, s = text:match("^(%d+):(%d+):(%d+)$")
        if h then
            local day = tonumber(tostring(fmtDow:format(stamp))) or 1
            return (tonumber(h) * 3600) + (tonumber(m) * 60) + tonumber(s), day
        end
        -- Fall through to a lesser source rather than stopping the scheduler
    end

    -- Guarded: reaching here from "calendar" means its formatter just failed,
    -- and os may not exist at all in this Lua state.
    if (source == "os" or source == "calendar") and os and os.date then
        local t = os.date("*t")
        if t then
            -- os.date wday is 1=Sunday..7=Saturday; convert to 1=Monday..7=Sunday
            local day = ((t.wday + 5) % 7) + 1
            return (t.hour * 3600) + (t.min * 60) + t.sec, day
        end
    end

    -- Last resort: UTC derived from the epoch. 1970-01-01 was a Thursday.
    local epoch = getTimestamp()
    local day = (math.floor(epoch / 86400) + 3) % 7 + 1
    return epoch % 86400, day
end

-- "03:00" -> 10800. Returns nil on anything malformed.
function schedule.parseClock(text)
    if type(text) ~= "string" then
        return nil
    end
    local h, m = text:match("^(%d%d?):(%d%d)$")
    if not h then
        return nil
    end
    h, m = tonumber(h), tonumber(m)
    if h > 23 or m > 59 then
        return nil
    end
    return (h * 3600) + (m * 60)
end

local function secondsToClock(seconds)
    seconds = seconds % 86400
    return string.format("%02d:%02d", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60))
end

-- ---------------------------------------------------------------------------
-- NORMALISATION
--
-- Turns whatever an admin hand-wrote into a predictable shape, or rejects it
-- with a reason. Rejections are logged rather than thrown so one bad job never
-- stops the rest from loading.
-- ---------------------------------------------------------------------------

function schedule.normalise(name, raw)
    if type(raw) ~= "table" then
        return nil, "job is not a table"
    end

    local job = {
        name = name,
        enabled = raw.enabled ~= false,
        action = raw.action,
        args = type(raw.args) == "table" and raw.args or {},
        runIfEmpty = raw.runIfEmpty,
        announcements = {}
    }

    if type(job.action) ~= "string" or job.action == "" then
        return nil, "missing 'action'"
    end

    -- Timing mode: 'at' (clock times) or 'every' (interval). Not both.
    local hasAt = type(raw.at) == "table" and #raw.at > 0
    local hasEvery = tonumber(raw.every) ~= nil

    if hasAt and hasEvery then
        return nil, "has both 'at' and 'every'; use one or the other"
    end
    if not hasAt and not hasEvery then
        return nil, "needs either 'at' or 'every'"
    end

    if hasAt then
        job.mode = "at"
        job.at = {}
        for _, t in ipairs(raw.at) do
            local secs = schedule.parseClock(t)
            if not secs then
                return nil, "bad time '" .. tostring(t) .. "' in 'at' (expected HH:MM)"
            end
            table.insert(job.at, secs)
        end
        table.sort(job.at)
    else
        job.mode = "every"
        job.every = tonumber(raw.every)
        job.everyUnit = raw.everyUnit or "minutes"
        if not VALID_UNITS[job.everyUnit] then
            return nil, "bad 'everyUnit' value '" .. tostring(job.everyUnit) .. "'"
        end
        if job.every <= 0 then
            return nil, "'every' must be greater than zero"
        end
        job.intervalSeconds = job.every * VALID_UNITS[job.everyUnit]

        -- Optional active window
        if raw.startTime then
            job.startTime = schedule.parseClock(raw.startTime)
            if not job.startTime then
                return nil, "bad 'startTime' (expected HH:MM)"
            end
        end
        if raw.endTime then
            job.endTime = schedule.parseClock(raw.endTime)
            if not job.endTime then
                return nil, "bad 'endTime' (expected HH:MM)"
            end
        end
    end

    -- Optional day-of-week filter, applies to both modes
    if type(raw.days) == "table" and #raw.days > 0 then
        job.days = {}
        for _, d in ipairs(raw.days) do
            local key = tostring(d):lower():sub(1, 3)
            local num = DAYS[key]
            if not num then
                return nil, "unknown day '" .. tostring(d) .. "'"
            end
            job.days[num] = true
        end
    end

    for _, a in ipairs(raw.announcements or {}) do
        local before = tonumber(a.before)
        if before and before > 0 and a.text and a.text ~= "" then
            table.insert(job.announcements, {
                before = before,
                text = a.text
            })
        end
    end
    -- Longest lead time first, so the walk down is monotonic
    table.sort(job.announcements, function(x, y)
        return x.before > y.before
    end)

    return job, nil
end

function schedule.dayAllowed(job, dayOfWeek)
    if not job.days then
        return true
    end
    return job.days[dayOfWeek] == true
end

-- ---------------------------------------------------------------------------
-- WHEN DOES THIS JOB NEXT COME DUE?
-- ---------------------------------------------------------------------------

-- Seconds until the next 'at' occurrence: zero when it is due this very
-- second, otherwise positive. Looks a full week ahead so a day filter of a
-- single weekday still resolves. nil should be unreachable, since normalise
-- rejects both an empty 'at' list and an empty 'days' list.
local function secondsUntilAt(job, nowSecs, nowDow)
    local best = nil
    for dayOffset = 0, 7 do
        local dow = ((nowDow - 1 + dayOffset) % 7) + 1
        if schedule.dayAllowed(job, dow) then
            for _, t in ipairs(job.at) do
                local delta = (dayOffset * 86400) + t - nowSecs
                -- Never negative: a time already past today is picked up by a
                -- later dayOffset instead.
                if delta >= 0 and (best == nil or delta < best) then
                    best = delta
                end
            end
        end
    end
    return best
end

-- True when the local clock sits inside a job's optional active window.
-- Windows that wrap past midnight (22:00 -> 04:00) are handled.
function schedule.inWindow(job, nowSecs)
    if not job.startTime and not job.endTime then
        return true
    end
    local s = job.startTime or 0
    local e = job.endTime or 86399
    if s <= e then
        return nowSecs >= s and nowSecs <= e
    end
    return nowSecs >= s or nowSecs <= e
end

-- Seconds until this job should next fire, or nil if it cannot be determined.
-- For 'every' jobs, lastRun is an epoch timestamp (nil if it has never run).
function schedule.secondsUntilDue(job, nowSecs, nowDow, lastRun, nowEpoch)
    if job.mode == "at" then
        return secondsUntilAt(job, nowSecs, nowDow)
    end

    -- interval mode
    if not schedule.dayAllowed(job, nowDow) then
        return nil
    end
    if not lastRun then
        -- Never run: due as soon as we are inside the window
        return schedule.inWindow(job, nowSecs) and 0 or nil
    end
    local due = lastRun + job.intervalSeconds
    local delta = due - nowEpoch
    if delta < 0 then
        delta = 0
    end
    -- Wrap into the day: an interval that carries us past midnight would
    -- otherwise be compared against a seconds-of-day range it can't fall in.
    if not schedule.inWindow(job, (nowSecs + delta) % 86400) then
        return nil
    end
    return delta
end

-- Human-readable summary used in the startup log, so admins can see at a
-- glance that the file was understood the way they meant it.
function schedule.describe(job)
    local bits = {}
    if job.mode == "at" then
        local times = {}
        for _, t in ipairs(job.at) do
            table.insert(times, secondsToClock(t))
        end
        table.insert(bits, "at " .. table.concat(times, ", "))
    else
        table.insert(bits, "every " .. tostring(job.every) .. " " .. job.everyUnit)
        if job.startTime or job.endTime then
            table.insert(bits, "between " .. secondsToClock(job.startTime or 0) .. " and " ..
                secondsToClock(job.endTime or 86399))
        end
    end

    if job.days then
        local names = {}
        for key, num in pairs(DAYS) do
            if job.days[num] then
                names[num] = key
            end
        end
        local ordered = {}
        for i = 1, 7 do
            if names[i] then
                table.insert(ordered, names[i])
            end
        end
        table.insert(bits, "on " .. table.concat(ordered, ", "))
    end

    return job.action .. " " .. table.concat(bits, " ")
end

Cron.schedule = schedule

return schedule
