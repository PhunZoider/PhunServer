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
    name = "Workshop Restart",
    enabled = false,
    trigger = "workshop",
    type = "restart",
    countdowns = {{
        secs = 300,
        text = "IGUI_PhunServer_Left"
    }, {
        secs = 60,
        text = "IGUI_PhunServer_One"
    }, {
        secs = 30,
        text = "IGUI_PhunServer_Seconds"
    }, {
        secs = 10,
        text = "IGUI_PhunServer_Seconds"
    }}
}

function Core.getSchedule(refresh)
    if scheduleCache == nil or refresh == true then
        local data = Core.getSavedData() or {}
        scheduleCache = data.schedules
        if scheduleCache == nil then
            -- First install: seed the default workshop schedule
            scheduleCache = {DEFAULT_WORKSHOP_SCHEDULE}
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
-- COUNTDOWN RUNNER
-- Unified pre-action countdown for all schedule types.
-- Warning messages fire when secondsLeft drops to <= entry.secs (i.e. secs
-- means "N seconds before the action", same semantics for every type).
-- Cancel by setting Core.runningScheduleName to nil or a different value.
-- ---------------------------------------------------------------------------
function Core.runCountdown(schedule)
    local isRestart = schedule.type == "restart"

    -- Duration = largest countdown secs; restart falls back to the global option.
    local delaySecs = 0
    for _, c in ipairs(schedule.countdowns or {}) do
        local s = tonumber(c.secs) or 0
        if s > delaySecs then
            delaySecs = s
        end
    end
    if delaySecs < 1 and isRestart then
        delaySecs = Core.getOption("RestartDelayMinutes", 5) * 60
    end

    -- For restart: keep restartingAt set so server_events.lua can monitor it.
    if isRestart then
        Core.restartingAt = getTimestamp() + delaySecs
        Core.restartingIn = delaySecs
    end

    -- No countdown needed — execute immediately.
    if delaySecs < 1 then
        Core.runningScheduleName = nil
        Core.executeScheduleAction(schedule)
        return
    end

    local sorted = {}
    for _, c in ipairs(schedule.countdowns or {}) do
        local s = tonumber(c.secs) or 0
        if s > 0 then
            table.insert(sorted, {
                secs = s,
                text = c.text or "",
                sound = c.sound
            })
        end
    end
    table.sort(sorted, function(a, b)
        return a.secs > b.secs
    end)

    local fireAt = getTimestamp() + delaySecs
    local firedSet = {}
    local snapName = schedule.name -- cancellation token
    local useChime = isRestart and Core.getOption("NotificationChime") == true
    local msgTypes = isRestart and {
        halo = true,
        chat = true
    } or {
        chat = true
    }

    local tickFn
    tickFn = function()
        if Core.runningScheduleName ~= snapName then
            Events.OnTickEvenPaused.Remove(tickFn)
            return
        end

        local secondsLeft = fireAt - getTimestamp()
        if isRestart then
            Core.restartingIn = secondsLeft
        end

        for _, entry in ipairs(sorted) do
            if not firedSet[entry.secs] and secondsLeft <= entry.secs then
                firedSet[entry.secs] = true
                local entrySnd
                if entry.sound and entry.sound ~= "" then
                    entrySnd = "restartNotice"
                else
                    entrySnd = useChime and "restartNotice" or ""
                end
                sendServerCommand(Core.name, Core.commands.notify, {
                    soundName = entrySnd,
                    text = entry.text,
                    secs = secondsLeft,
                    args = {secondsLeft},
                    types = msgTypes
                })
            end
        end

        if secondsLeft <= 0 then
            Events.OnTickEvenPaused.Remove(tickFn)
            Core.runningScheduleName = nil
            Core.executeScheduleAction(schedule)
        end
    end
    Events.OnTickEvenPaused.Add(tickFn)
end

-- ---------------------------------------------------------------------------
-- SCHEDULE ACTION EXECUTOR
-- Called when the countdown reaches zero (or immediately if there is none).
-- ---------------------------------------------------------------------------
function Core.executeScheduleAction(schedule)
    if schedule.type == "restart" then
        Core.rebootServer()

    elseif schedule.type == "event" and schedule.eventName and schedule.eventName ~= "" then
        triggerEvent(schedule.eventName, schedule)

    elseif schedule.type == "announcement" then
        if schedule.announcementText and schedule.announcementText ~= "" then
            sendServerCommand(Core.name, Core.commands.notify, {
                soundName = schedule.announcementSound == "ding" and "restartNotice" or "",
                text = schedule.announcementText,
                args = {},
                types = {
                    chat = true
                }
            })
        end
    end
    Core.runningScheduleName = nil
end

-- ---------------------------------------------------------------------------
-- FIRE ONE SCHEDULE
-- Entry point shared by cron, workshop, and manual trigger paths.
-- Guards against double-restart.
-- ---------------------------------------------------------------------------
function Core.fireSchedule(schedule)
    if schedule.type == "restart" and (Core.restartingAt or Core.rebooting) then
        return
    end

    print("[" .. Core.name .. "] Schedule '" .. (schedule.name or "?") .. "' fired (" .. (schedule.type or "?") .. ")")
    triggerEvent(Core.events.OnSchedule, schedule)

    Core.runningScheduleName = schedule.name
    Core.runCountdown(schedule)
end

-- ---------------------------------------------------------------------------
-- WORKSHOP TRIGGER DISPATCH
-- Finds the highest-priority enabled workshop-trigger schedule and fires it.
-- Priority: restart > event > announcement.
-- Returns true if one was fired, false if none found.
-- ---------------------------------------------------------------------------
local WORKSHOP_PRIORITY = {
    restart = 1,
    event = 2,
    announcement = 3
}

function Core.fireWorkshopSchedules()
    local schedules = Core.getSchedule()
    local candidates = {}
    for _, s in ipairs(schedules) do
        if s.enabled and s.trigger == "workshop" then
            table.insert(candidates, s)
        end
    end
    if #candidates == 0 then
        return false
    end

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
    if Core.restartingAt or Core.rebooting then
        return
    end

    local minUptime = Core.getOption("ScheduleMinUptimeMinutes", 30) * 60
    if Core.serverStarted and (getTimestamp() - Core.serverStarted < minUptime) then
        return
    end

    local schedules = Core.getSchedule()
    if not schedules or #schedules == 0 then
        return
    end

    local now = os.date("*t")

    for _, schedule in ipairs(schedules) do
        if schedule.enabled and schedule.trigger == "cron" then

            local dayMatch = true
            if schedule.recur == "weekly" then
                dayMatch = false
                for _, d in ipairs(schedule.days or {}) do
                    if d == now.wday then
                        dayMatch = true;
                        break
                    end
                end
            end

            if dayMatch then
                for _, timeStr in ipairs(schedule.times or {}) do
                    local h, m = timeStr:match("^(%d+):(%d+)$")
                    h, m = tonumber(h), tonumber(m)
                    if h and m and h == now.hour and m == now.min then
                        local key = string.format("%04d-%02d-%02d|%s|%s", now.year, now.month, now.mday, schedule.name,
                            timeStr)
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
