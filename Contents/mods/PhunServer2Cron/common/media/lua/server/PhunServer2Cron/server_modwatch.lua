if isClient() then
    return
end

local Core = require "PhunServer2/core"
require "PhunServer2/server_shutdown"
local Cron = require "PhunServer2Cron/core"

-- ---------------------------------------------------------------------------
-- ModWatch.
--
-- Polls the Steam Workshop and, when any subscribed item has been updated
-- since this server started, schedules a controlled shutdown. It is exposed as
-- the "modcheck" action so admins choose the cadence in their cron file rather
-- than being tied to a fixed interval.
--
-- Note this only ever *stops* the server. Bringing it back up (and thereby
-- letting Steam apply the updates) is the host's or a service's job.
-- ---------------------------------------------------------------------------

local lastPoll = nil

-- Called once outdated items are confirmed. Idempotent: repeated detections
-- while a shutdown is already pending are ignored.
function Cron.outdatedWorkshop()
    if Core.isShutdownPending() then
        return true
    end

    local delayMinutes = Cron.getOption("RestartDelayMinutes", 5)

    if Core.isServerEmpty() then
        Cron.logLn("Outdated workshop items detected and the server is empty, restarting now")
        Core.rebootServer()
        return true
    end

    Cron.logLn("Outdated workshop items detected, restarting in " .. tostring(delayMinutes) .. " minute(s)")
    Core.scheduleShutdown(getTimestamp() + (delayMinutes * 60), {
        reason = "outdated workshop items",
        runIfEmpty = true
    })
    return true
end

-- player is optional; when present, feedback is sent to whoever ran /check.
function Cron.pollWorkshop(player)

    local function reply(textKey, args)
        if player then
            sendServerCommand(player, Core.name, Core.commands.message, {
                username = player:getUsername(),
                text = textKey,
                args = args or {}
            })
        end
    end

    if Core.isShutdownPending() then
        Cron.verboseLn("Skipping workshop poll, a shutdown is already in progress")
        reply("IGUI_PhunServer2Cron_Poll_PendingReboot")
        return
    end

    Cron.verboseLn("Polling the workshop for updates" ..
                       (lastPoll and (", last check was " .. Core.tools.absDifference(getTimestamp(), lastPoll) .. " ago") or
                           ""))
    lastPoll = getTimestamp()

    local ok, err = pcall(function()
        local ids = getSteamWorkshopItemIDs()

        if not ids or (ids.size and ids:size() == 0) then
            Cron.logLn("No workshop IDs to poll. Either no workshop mods are installed or Steam is unreachable.")
            reply("IGUI_PhunServer2Cron_Poll_NoIDs")
            return
        end

        return querySteamWorkshopItemDetails(ids, function(_, status, info)
            local ok2, err2 = pcall(function()
                if status ~= "Completed" or not info then
                    return
                end

                local names = {}
                for i = 0, (info:size() or 0) - 1 do
                    local details = info:get(i)
                    if details then
                        local updated = details:getTimeUpdated()
                        if Core.serverStarted and updated and updated >= Core.serverStarted then
                            table.insert(names, details:getTitle())
                        end
                    end
                end

                if #names > 0 then
                    Cron.logLn("Detected " .. #names .. " outdated workshop item(s): " .. table.concat(names, ", "))
                    reply(#names > 1 and "IGUI_PhunServer2Cron_Poll_UpdatedPlural" or
                              "IGUI_PhunServer2Cron_Poll_Updated", {tostring(#names), table.concat(names, ", ")})

                    local okOW, errOW = pcall(Cron.outdatedWorkshop)
                    if not okOW then
                        Cron.logLn("Error handling outdated workshop items: " .. tostring(errOW))
                    end
                else
                    Cron.verboseLn("No outdated workshop items")
                    reply("IGUI_PhunServer2Cron_Poll_UpToDate")
                end
            end)

            if not ok2 then
                Cron.logLn("Error in the workshop polling callback: " .. tostring(err2))
            end
        end, {})
    end)

    if not ok then
        Cron.logLn("Error polling the workshop: " .. tostring(err))
        Cron.logLn("You may not be connected to Steam, or their servers may be down.")
    end
end

Core.registerAction("modcheck", {
    label = "IGUI_PhunServer2Cron_Action_ModCheck",
    fields = {},
    handler = function(job, args)
        if Cron.getOption("EnableModWatch", true) ~= true then
            Cron.verboseLn("ModWatch is disabled, skipping the check")
            return
        end
        Cron.pollWorkshop()
    end
})

-- Fires a named Lua event so other mods can hang behaviour off a schedule
-- without needing an action of their own.
Core.registerAction("event", {
    label = "IGUI_PhunServer2Cron_Action_Event",
    fields = {
        event = {
            type = "string",
            default = "",
            label = "IGUI_PhunServer2Cron_Field_Event"
        }
    },
    handler = function(job, args)
        local name = args.event
        if not name or name == "" then
            return
        end
        if not Events[name] then
            LuaEventManager.AddEvent(name)
        end
        -- Server-side triggerEvent is limited to 3 arguments in total
        triggerEvent(name, job and job.name or nil)
    end
})
