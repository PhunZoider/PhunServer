if isClient() then
    return
end
local Core = PhunServer
local PL = PhunLib
local luautils = luautils

function Core.isServerEmpty()
    return getOnlinePlayers():size() == 0
end

function Core.getPlayerCount()
    return getOnlinePlayers():size()
end

local onliners = {}

function Core.checkPlayers()

    -- players online 
    local online = PL.onlinePlayers()

    local now = getTimestamp()
    for i = 0, online:size() - 1 do
        local p = online:get(i)
        local username = p:getUsername()

        onliners[username] = true
        if not Core.data.online[username] then
            -- just joined
            Core.data.online[username] = {}
            Core.debugLn("Player connected for the first time: " .. username)
            if Core.getOption("WelcomeAnnounce", false) then
                sendServerCommand(Core.name, Core.commands.welcomeFirstTime, {username})
            end
        elseif not Core.data.online[username].online then
            -- re-joined
            Core.debugLn("Player re-connected: " .. username)
            if Core.getOption("WelcomeAnnounce", false) then
                sendServerCommand(Core.name, Core.commands.welcome, {username})
            end

        end
        Core.data.online[username].lastSeen = now
        Core.data.online[username].online = true
    end
    for name, data in pairs(onliners) do
        if Core.data.online[name].online then
            if now - Core.data.online[name].lastSeen > 1 then
                -- player left
                Core.debugLn("Player disconnected: " .. name)
                local suffix = ZombRand(4)
                local t = {
                    soundName = "",
                    text = "IGUI_PhunServer_Goodbye" .. tostring(suffix),
                    args = {},
                    types = {
                        chat = true
                    }
                }
                table.insert(t.args, name)
                if Core.getOption("GoodbyeAnnouncements", false) then
                    sendServerCommand(Core.name, Core.commands.goodbye, {name})
                end

                Core.data.online[name].online = false
                onliners[name] = nil
            end
        end
    end

end

function Core.wipeKeyCheck(username)

    if not Core.getOption("EnableWipeMap", false) then
        Core.debugLn("WipeKey check disabled.")
        return
    end

    local wipeKey = Core.getOption("WipeKey", nil)
    local data = Core.data.online[username]

    if wipeKey and wipeKey ~= "" and data and wipeKey ~= data.wipeKey then

        Core.debugLn(
            username .. " has an outdated wipeKey (" .. tostring(data.wipeKey) .. " vs " .. tostring(wipeKey) ..
                " , performing wipe.")
        data.wipeKey = wipeKey
        sendServerCommand(Core.name, Core.commands.wipeMap, {
            username = username,
            args = {}
        })
    else
        Core.debugLn(username .. " has current wipeKey, no wipe needed.")
    end
end

function Core.scheduleServerRestart(timestamp)

    Core.restartingAt = timestamp
    Core.restartingIn = timestamp - getTimestamp()

    Core.debugLn("Scheduling server restart at timestamp " .. tostring(Core.restartingAt) .. " (in " ..
                     tostring(Core.restartingIn) .. " seconds).")

    local nextNotified = 0
    local lastNotified = 9999999
    local lastNotifiedIndex = -1
    local values = luautils.split(Core.getOption("NotificationCountdown", "300;120;60;30;10;9;8;7;6;5;3;2;1"), ";")

    Events.OnTickEvenPaused.Add(function()
        if Core.restartingAt == nil then
            return
        end

        local secondsLeft = Core.restartingAt - getTimestamp()
        -- print("secondsLeft:", secondsLeft)
        local doNotify = false
        for i, v in ipairs(values) do
            if i > lastNotifiedIndex then
                if tonumber(v) < lastNotified then
                    if secondsLeft <= tonumber(v) then
                        lastNotifiedIndex = i
                        doNotify = true
                        lastNotified = tonumber(v)
                    end
                end
            end
        end

        if doNotify then

            local val = lastNotified
            -- is this a second, seconds, minute or minutes?
            local suffix = "Second"
            if lastNotified <= 1 then
                suffix = "Second"
            elseif lastNotified < 60 then
                suffix = "Seconds"
            elseif lastNotified == 60 then
                suffix = "One"
                val = 1
            else
                suffix = "Left"
                val = PL.string.formatWholeNumber(lastNotified / 60)
            end

            local t = {
                soundName = Core.getOption("NotificationChime") == true and "restartNotice" or "",
                text = "IGUI_PhunServer_" .. suffix,
                args = {},
                types = {
                    halo = true,
                    chat = true
                }
            }
            table.insert(t.args, tostring(val))
            sendServerCommand(Core.name, Core.commands.notify, t)
            print(getText(t.text, tostring(val)))
        end

        Core.restartingIn = secondsLeft

        if secondsLeft <= 0 then
            Events.OnTickEvenPaused.Remove(self)
            return
        end

    end)

end

function Core.rebootServer()
    if Core.rebooting then
        return
    end
    Core.rebooting = true

    sendServerCommand(Core.name, Core.commands.quit, {})

    Events.OnSave.Add(function()
        local delaySeconds = Core.getOption("QuitDelaySeconds", 15)
        local delayTimestamp = getTimestamp() + delaySeconds
        local lastSecondLogged = delaySeconds + 1
        Events.OnTickEvenPaused.Add(function()
            local secondsLeft = delayTimestamp - getTimestamp()
            if secondsLeft <= 0 then
                print("[" .. Core.name .. "] Quitting...")
                getCore():quit()
            else
                if lastSecondLogged > secondsLeft then
                    print("[" .. Core.name .. "] Quitting in " .. secondsLeft .. " seconds!")
                    lastSecondLogged = secondsLeft
                end
            end
        end)
    end)

    Core.debugLn("[" .. Core.name .. "] Saving...")
    saveGame()
end

local function rebootWhenEmpty()
    if Core.pendingReboot and Core.isServerEmpty() then
        Core.rebootServer()
        Events.OnTickEvenPaused.Remove(rebootWhenEmpty)
    end
end

function Core.outdatedWorkshop()
    if Core.pendingReboot then
        return true
    end
    Core.pendingReboot = true

    if Core.isServerEmpty() then
        print("[" .. Core.name .. "] Restarting the server (server empty and outdated workshop items were detected)..")
        Core.rebootServer()
        return true
    end

    local restartDelay = Core.getOption("RestartDelayMinutes", 5)
    local delaySeconds = Core.getOption("QuitDelaySeconds", 15)

    if restartDelay > 0 then
        local restartSeconds = restartDelay * 60;
        print("[" .. Core.name .. "] Detected outdated workshop item - restarting server in " ..
                  PL.string.formatWholeNumber(restartSeconds) .. "!")
        Core.scheduleServerRestart(getTimestamp() + restartSeconds)
    else
        print("[" .. Core.name ..
                  "] Restarting the server when it becomes empty... (outdated workshop items were detected)")
        Events.OnTickEvenPaused.Add(rebootWhenEmpty)
    end
    return true
end

function Core.pollWorkshop(player)
    Core.debugLn("Polling Workshop for updates...")
    if Core.pendingReboot then
        if player then
            sendServerCommand(player, Core.name, Core.commands.message, {
                username = player:getUsername(),
                text = "IGUI_PhunServer_Poll_PendingReboot"
            })
        end
        return
    end

    local ok, err = pcall(function()
        local ids = getSteamWorkshopItemIDs()

        if not ids or (ids.size and ids:size() == 0) then
            print("[" .. Core.name ..
                      "] No workshop IDs to poll, skipping. This means either no mods are installed or Steam is not connected.")
            if player then
                sendServerCommand(player, Core.name, Core.commands.message, {
                    username = player:getUsername(),
                    text = "IGUI_PhunServer_Poll_NoIDs"
                })
            end
            return
        end

        return querySteamWorkshopItemDetails(ids, function(_, status, info)
            local ok2, err2 = pcall(function()
                if status ~= "Completed" or not info then
                    return
                end

                local count = info:size() or 0
                local list = {}
                local names = {}
                for i = 0, count - 1 do
                    local details = info:get(i)
                    if details then
                        local updated = details:getTimeUpdated()
                        local haveUpdate = false

                        if Core.serverStarted and updated and updated >= Core.serverStarted then
                            haveUpdate = true
                            table.insert(list, {
                                id = details:getID(),
                                title = details:getTitle(),
                                updated = updated
                            })
                            table.insert(names, details:getTitle())
                        end
                    end
                end

                if #names > 0 then
                    print("[" .. Core.name .. "] Detected " .. tostring(#names) .. " outdated workshop item(s):" ..
                              table.concat(names, ", "))
                    if player then
                        sendServerCommand(player, Core.name, Core.commands.message, {
                            username = player:getUsername(),
                            text = #names > 1 and "IGUI_PhunServer_Poll_UpdatedPlural" or "IGUI_PhunServer_Poll_Updated",
                            args = names
                        })
                    end

                    local okOW, errOW = pcall(Core.outdatedWorkshop)
                    if not okOW then
                        print("[" .. Core.name .. "] Error in Core.outdatedWorkshop: " .. tostring(errOW))
                    end
                end

                return

            end)

            if not ok2 then
                print("[" .. Core.name .. "] Error in workshop polling callback: " .. tostring(err2))
            end
        end, {})
    end)

    if not ok then
        print("[" .. Core.name .. "] error polling workshop: " .. tostring(err))
        print("[" .. Core.name .. "] You may not be connected to Steam or their servers may be down.")
    end

end

