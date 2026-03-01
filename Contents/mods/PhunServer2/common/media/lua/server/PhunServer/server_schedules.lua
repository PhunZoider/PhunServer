if not isServer() then
    return
end

local Core = PhunServer

-- ---------------------------------------------------------------------------
-- SCHEDULE CACHE
-- ---------------------------------------------------------------------------
local scheduleCache = nil

-- Shipped with the mod; injected on first load (when no schedules file exists).
-- The admin must enable it via the panel before it will fire.
local DEFAULT_WORKSHOP_SCHEDULE = {
    name       = "Workshop Restart",
    enabled    = false,
    trigger    = "workshop",
    type       = "restart",
    countdowns = {
        {secs = 300, text = "IGUI_PhunServer_Left"},
        {secs = 60,  text = "IGUI_PhunServer_One"},
        {secs = 30,  text = "IGUI_PhunServer_Seconds"},
        {secs = 10,  text = "IGUI_PhunServer_Seconds"},
    },
}

function Core.getSchedule(refresh)
    if scheduleCache == nil or refresh == true then
        local data = Core.getSavedData() or {}
        scheduleCache = data.schedules
        if scheduleCache == nil then
            -- First install: seed the default workshop schedule
            scheduleCache  = {DEFAULT_WORKSHOP_SCHEDULE}
            data.schedules = scheduleCache
            Core.saveData(data)
        end
        scheduleCache = scheduleCache or {}
    end
    return scheduleCache
end

function Core.saveSchedules(schedules)
    scheduleCache = schedules
    local data = Core.getSavedData() or {}
    data.schedules = schedules
    Core.saveData(data)
end

-- ---------------------------------------------------------------------------
-- ANNOUNCEMENT FIRE
-- Broadcasts each countdown entry at fire_time + entry.secs delay.
-- secs=0  → immediate.  secs=30 → 30 seconds after the schedule fired.
-- ---------------------------------------------------------------------------
function Core.fireAnnouncements(countdowns)
    if not countdowns or #countdowns == 0 then return end

    local sorted = {}
    for _, c in ipairs(countdowns) do
        local s = tonumber(c.secs) or 0
        table.insert(sorted, {secs = s, text = c.text or ""})
    end
    table.sort(sorted, function(a, b) return a.secs < b.secs end)

    local startTime = getTimestamp()
    local nextIdx   = 1
    local tickFn
    tickFn = function()
        if nextIdx > #sorted then
            Events.OnTickEvenPaused.Remove(tickFn)
            return
        end
        local elapsed = getTimestamp() - startTime
        while nextIdx <= #sorted and elapsed >= sorted[nextIdx].secs do
            local entry = sorted[nextIdx]
            sendServerCommand(Core.name, Core.commands.notify, {
                text  = entry.text,
                args  = {},
                types = {chat = true},
            })
            nextIdx = nextIdx + 1
        end
    end
    Events.OnTickEvenPaused.Add(tickFn)
end

-- ---------------------------------------------------------------------------
-- FIRE ONE SCHEDULE
-- Shared by cron and workshop paths.  Handles restart / event / announcement.
-- Guards against double-restart.
-- ---------------------------------------------------------------------------
function Core.fireSchedule(schedule)
    if schedule.type == "restart" and (Core.restartingAt or Core.rebooting) then
        return
    end

    print("[" .. Core.name .. "] Schedule '" .. (schedule.name or "?") ..
          "' fired (" .. (schedule.type or "?") .. ")")
    triggerEvent(Core.events.OnSchedule, schedule)

    if schedule.type == "restart" then
        local delaySecs = Core.getOption("RestartDelayMinutes", 5) * 60
        if delaySecs < 1 then delaySecs = 1 end
        Core.scheduleServerRestart(getTimestamp() + delaySecs, schedule.countdowns)

    elseif schedule.type == "event" and schedule.eventName and schedule.eventName ~= "" then
        triggerEvent(schedule.eventName, schedule)

    elseif schedule.type == "announcement" then
        Core.fireAnnouncements(schedule.countdowns)
    end
end

-- ---------------------------------------------------------------------------
-- WORKSHOP TRIGGER DISPATCH
-- Finds the highest-priority enabled workshop-trigger schedule and fires it.
-- Priority: restart > event > announcement.
-- Returns true if one was fired, false if none found.
-- ---------------------------------------------------------------------------
local WORKSHOP_PRIORITY = {restart = 1, event = 2, announcement = 3}

function Core.fireWorkshopSchedules()
    local schedules  = Core.getSchedule()
    local candidates = {}
    for _, s in ipairs(schedules) do
        if s.enabled and s.trigger == "workshop" then
            table.insert(candidates, s)
        end
    end
    if #candidates == 0 then return false end

    table.sort(candidates, function(a, b)
        return (WORKSHOP_PRIORITY[a.type] or 99) < (WORKSHOP_PRIORITY[b.type] or 99)
    end)

    Core.fireSchedule(candidates[1])
    return true
end

-- ---------------------------------------------------------------------------
-- SCHEDULE ENGINE (cron)
-- Runs every minute.  Skips workshop-trigger schedules (those are fired by
-- Core.fireWorkshopSchedules instead).
-- ---------------------------------------------------------------------------
local lastFiredKey = {}

function Core.checkSchedules()
    if Core.restartingAt or Core.rebooting then return end

    local minUptime = Core.getOption("ScheduleMinUptimeMinutes", 30) * 60
    if Core.serverStarted and (getTimestamp() - Core.serverStarted < minUptime) then
        return
    end

    local schedules = Core.getSchedule()
    if not schedules or #schedules == 0 then return end

    local now = os.date("*t")

    for _, schedule in ipairs(schedules) do
        if schedule.enabled and schedule.trigger ~= "workshop" then

            local dayMatch = true
            if schedule.recur == "weekly" then
                dayMatch = false
                for _, d in ipairs(schedule.days or {}) do
                    if d == now.wday then dayMatch = true; break end
                end
            end

            if dayMatch then
                for _, timeStr in ipairs(schedule.times or {}) do
                    local h, m = timeStr:match("^(%d+):(%d+)$")
                    h, m = tonumber(h), tonumber(m)
                    if h and m and h == now.hour and m == now.min then
                        local key = string.format("%04d-%02d-%02d|%s|%s",
                            now.year, now.month, now.mday, schedule.name, timeStr)
                        if not lastFiredKey[key] then
                            lastFiredKey[key] = true
                            Core.fireSchedule(schedule)
                        end
                    end
                end
            end

        end
    end
end

Events.EveryOneMinute.Add(function()
    Core.checkSchedules()
end)
