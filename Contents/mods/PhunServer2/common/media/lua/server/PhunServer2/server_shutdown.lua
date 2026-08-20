if isClient() then
    return
end

local Core = require "PhunServer2/core"
local tools = Core.tools
local luautils = luautils

-- ---------------------------------------------------------------------------
-- Controlled shutdown.
--
-- Lives in core rather than in cron because more than one thing triggers it:
-- the /restart command, a scheduled cron job, and a detected mod update all
-- funnel through scheduleShutdown so there is exactly one countdown
-- implementation and exactly one in-flight shutdown at a time.
--
-- v1 added an anonymous OnTickEvenPaused closure per call and tried to remove
-- it with a nil `self`, so countdowns accumulated and double-announced. Here
-- the handler is named, removes itself, and any pending countdown is cancelled
-- before a new one starts.
-- ---------------------------------------------------------------------------

local DEFAULT_COUNTDOWN = "300;120;60;30;10;9;8;7;6;5;3;2;1"

-- The single live countdown, or nil.
local countdownHandler = nil

local function parseCountdown(raw)
    local values = {}
    for _, v in ipairs(luautils.split(raw or DEFAULT_COUNTDOWN, ";")) do
        local n = tonumber(v)
        if n and n > 0 then
            table.insert(values, n)
        end
    end
    -- Largest first, so the walk down is monotonic
    table.sort(values, function(a, b)
        return a > b
    end)
    return values
end

-- Picks the translation key and display value for a given seconds-remaining.
local function countdownText(seconds)
    if seconds <= 1 then
        return "IGUI_PhunServer2_Second", tostring(seconds)
    elseif seconds < 60 then
        return "IGUI_PhunServer2_Seconds", tostring(seconds)
    elseif seconds == 60 then
        return "IGUI_PhunServer2_One", "1"
    end
    return "IGUI_PhunServer2_Left", tools.formatWholeNumber(seconds / 60)
end

function Core.broadcastNotify(textKey, args, opts)
    opts = opts or {}
    sendServerCommand(Core.name, Core.commands.notify, {
        soundName = opts.sound or "",
        text = textKey,
        args = args or {},
        types = opts.types or {
            halo = true,
            chat = true
        }
    })
end

function Core.isShutdownPending()
    return Core.shutdownAt ~= nil
end

function Core.cancelShutdown(reason)
    if not Core.shutdownAt then
        return false
    end

    Core.logLn("Shutdown cancelled" .. (reason and (" (" .. reason .. ")") or ""))
    Core.shutdownAt = nil
    Core.shutdownIn = nil
    Core.pendingShutdown = false

    if countdownHandler then
        Events.OnTickEvenPaused.Remove(countdownHandler)
        countdownHandler = nil
    end

    triggerEvent(Core.events.OnShutdownCancelled, reason)
    return true
end

-- Schedules a shutdown at an absolute epoch timestamp.
--   opts.reason      free text for the log
--   opts.countdown   overrides the sandbox countdown thresholds
--   opts.runIfEmpty  when true, shut down early the moment the server empties
function Core.scheduleShutdown(timestamp, opts)
    opts = opts or {}

    -- Replace, never stack
    if Core.shutdownAt then
        Core.cancelShutdown("superseded by a new shutdown request")
    end
    -- Defensive: a handler with no shutdown behind it should not survive
    if countdownHandler then
        Events.OnTickEvenPaused.Remove(countdownHandler)
        countdownHandler = nil
    end

    Core.shutdownAt = timestamp
    Core.shutdownIn = timestamp - getTimestamp()
    Core.pendingShutdown = true

    Core.logLn("Shutdown scheduled in " .. tostring(Core.shutdownIn) .. " seconds" ..
                   (opts.reason and (" (" .. opts.reason .. ")") or ""))

    local values = parseCountdown(opts.countdown or Core.getOption("NotificationCountdown", DEFAULT_COUNTDOWN))
    local chime = Core.getOption("NotificationChime", true) == true
    local runIfEmpty = opts.runIfEmpty == true

    -- Skip any threshold that is already behind us. Scheduling a shutdown four
    -- minutes out must not immediately announce "restart in 5 minutes".
    local nextIndex = 1
    while nextIndex <= #values and values[nextIndex] > Core.shutdownIn do
        nextIndex = nextIndex + 1
    end

    -- `handler` is a fresh local per call, so the closure unregisters *itself*
    -- and never the file-level variable, which a later schedule may have
    -- reassigned. v1's equivalent used a nil `self` and so never unregistered
    -- at all, which is how its countdowns stacked.
    local handler
    handler = function()
        if Core.shutdownAt == nil then
            -- Cancelled from under us
            Events.OnTickEvenPaused.Remove(handler)
            if countdownHandler == handler then
                countdownHandler = nil
            end
            return
        end

        local secondsLeft = Core.shutdownAt - getTimestamp()
        Core.shutdownIn = secondsLeft

        -- Consume every threshold we have passed, but announce only the last
        -- of them. A hitch that skips several must not spam the whole set.
        local crossed = nil
        while nextIndex <= #values and secondsLeft <= values[nextIndex] do
            crossed = values[nextIndex]
            nextIndex = nextIndex + 1
        end

        if crossed then
            local key, val = countdownText(crossed)
            Core.broadcastNotify(key, {val}, {
                sound = chime and "restartNotice" or ""
            })
        end

        if secondsLeft <= 0 or (runIfEmpty and Core.isServerEmpty()) then
            Events.OnTickEvenPaused.Remove(handler)
            if countdownHandler == handler then
                countdownHandler = nil
            end
            Core.rebootServer()
        end
    end

    countdownHandler = handler
    Events.OnTickEvenPaused.Add(handler)
    triggerEvent(Core.events.OnShutdownScheduled, timestamp, opts.reason)
end

function Core.rebootServer()
    if Core.shuttingDown then
        return
    end
    Core.shuttingDown = true

    -- Tell clients to quit so they don't sit staring at a dead connection
    sendServerCommand(Core.name, Core.commands.quit, {})

    local delaySeconds = Core.getOption("QuitDelaySeconds", 15)
    local tickHandler
    local saveHandler

    saveHandler = function()
        Events.OnSave.Remove(saveHandler)

        local quitAt = getTimestamp() + delaySeconds
        local lastLogged = delaySeconds + 1

        tickHandler = function()
            local secondsLeft = quitAt - getTimestamp()

            if secondsLeft <= 0 then
                Events.OnTickEvenPaused.Remove(tickHandler)
                Core.logLn("Quitting...")
                getCore():quit()
                return
            end

            if lastLogged > secondsLeft then
                Core.logLn("Quitting in " .. secondsLeft .. " seconds!")
                lastLogged = secondsLeft
            end
        end

        Events.OnTickEvenPaused.Add(tickHandler)
    end

    Events.OnSave.Add(saveHandler)
    Core.logLn("Saving before shutdown...")
    save(false)
end

-- ---------------------------------------------------------------------------
-- Actions core contributes to the scheduler
-- ---------------------------------------------------------------------------

Core.registerAction("shutdown", {
    label = "IGUI_PhunServer2_Action_Shutdown",
    fields = {
        notice = {
            type = "int",
            default = 5,
            label = "IGUI_PhunServer2_Field_Notice"
        },
        runIfEmpty = {
            type = "boolean",
            default = true,
            label = "IGUI_PhunServer2_Field_RunIfEmpty"
        }
    },
    -- A job scheduled for 03:00 with 15 minutes of notice must start its
    -- countdown at 02:45, so that the server is actually down at 03:00.
    leadSeconds = function(args)
        return (tonumber(args and args.notice) or 5) * 60
    end,
    handler = function(job, args)
        local noticeMinutes = tonumber(args.notice) or 5
        Core.scheduleShutdown(getTimestamp() + (noticeMinutes * 60), {
            reason = "scheduled job '" .. tostring(job and job.name or "?") .. "'",
            runIfEmpty = args.runIfEmpty ~= false
        })
    end
})

Core.registerAction("announce", {
    label = "IGUI_PhunServer2_Action_Announce",
    fields = {
        text = {
            type = "string",
            default = "",
            label = "IGUI_PhunServer2_Field_Text"
        }
    },
    handler = function(job, args)
        local text = args.text
        if not text or text == "" then
            return
        end
        Core.broadcastNotify(text, {}, {
            types = {
                chat = true
            }
        })
    end
})
