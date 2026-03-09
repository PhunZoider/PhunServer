if isClient() then
    return
end
require "PhunServer/core"
local Commands = require "PhunServer/server_commands"
local Core = PhunServer

Events.OnInitGlobalModData.Add(function()

    Core.data = ModData.getOrCreate(Core.name)
    if not Core.data.online then
        Core.data.online = {}
    end
end)

Events.OnCharacterDeath.Add(function(player)
    if instanceof(player, "IsoPlayer") then
        -- a player died
        local username = player:getUsername()
        if not username or username == "" then
            return
        end
        if not Core.data.online[username] then
            return
        end
        Core.debugLn("Player " .. tostring(username) .. " died.")
        if Core.getOption("EnableWipeMap") and Core.getOption("WipePerCharacter", false) then
            Core.debugLn("Player " .. tostring(username) .. " died, wiping their wipe key.")
            Core.data.online[username].wipeKey = tostring(getTimestamp())
            Core.wipeKeyCheck(username)
        end
    end
end)

Events.OnClientCommand.Add(function(module, command, playerObj, arguments)
    if module == Core.name and Commands[command] then
        Commands[command](playerObj, arguments)
    end
end)

Events.OnDisconnect.Add(function()
    if Core.getOption("EnableModWatch") == true then
        Core.pollWorkshop()
    end
end)

local function getWorkshopPollInterval()
    local minInterval = nil
    if Core.getSchedule then
        for _, s in ipairs(Core.getSchedule()) do
            if s.enabled and s.trigger == "workshop" and s.workshopFrequency and s.workshopFrequency > 0 then
                if not minInterval or s.workshopFrequency < minInterval then
                    minInterval = s.workshopFrequency
                end
            end
        end
    end
    return minInterval or 15
end

local nextPoll = 0
local lastPoll = 0
local nextPlayerCheck = getTimestamp()

Events.OnTickEvenPaused.Add(function()

    if nextPlayerCheck <= getTimestamp() then
        nextPlayerCheck = getTimestamp() + 2
        Core.checkPlayers()
    end

    if Core.restartingAt then
        if Core.isServerEmpty() then
            print("[" .. Core.name ..
                      "] Restarting the server now! (Outdated workshop items were detected and server is empty)")
            Core.rebootServer()
        elseif Core.restartingAt - getTimestamp() <= 0 then
            print("[" .. Core.name .. "] Restarting the server now! (Outdated workshop items were detected)")
            Core.rebootServer()
        end
        return
    end

    if Core.pendingReboot then
        return
    end

    if Core.getOption("RestartDelayMinutes", 5) == 0 and not Core.isServerEmpty() then
        return
    end

    local timestamp = getTimestamp()

    if timestamp >= nextPoll then

        local pollIntervalMins = getWorkshopPollInterval()
        nextPoll = timestamp + (pollIntervalMins * 60)

        if Core.getOption("EnableModWatch") == true then
            print("[" .. Core.name .. "] ModWatch checking workshop for updates" ..
                      (lastPoll > 0 and ". Last check was " .. (Core.tools.absDifference(timestamp, lastPoll) .. " ago") or
                          "") .. ".")
            Core.pollWorkshop()
            lastPoll = timestamp
        else
            nextPoll = timestamp + (60 * 15) -- check again in 15 minutes in case option changed
        end

    end
end)

Events.OnServerStarted.Add(function()

    if Core.getOption("RefreshSettingsOnStartup", false) then
        local was = Core.getOption("DayOffset", false)
        print("[" .. Core.name .. "] Refreshing sandbox options from server lua file... " ..
                  (was and " (previous DayOffset: " .. tostring(was) .. ")" or ""))
        getSandboxOptions():loadServerLuaFile(getServerName())
        getSandboxOptions():applySettings()
        local now = Core.getOption("DayOffset", false)
        print("[" .. Core.name .. "] Sandbox options refreshed from server lua file." ..
                  (now and " (current DayOffset: " .. tostring(now) .. ")" or ""))
    end

    Core:ini()
    Core:testNight()
end)

Events.EveryOneMinute.Add(function()
    Core:testNight()
end)
