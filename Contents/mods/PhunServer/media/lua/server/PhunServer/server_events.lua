if isClient() then
    return
end
require "PhunServer/core"
local Commands = require "PhunServer/server_commands"
local Core = PhunServer
local PL = PhunLib
Events.OnInitGlobalModData.Add(function()

    Core.data = ModData.getOrCreate(Core.name)
    if not Core.data.online then
        Core.data.online = {}
    end
    -- if not Core.data.wipeKeys then
    --     Core.data.wipeKeys = {}
    -- end

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

        nextPoll = timestamp + (Core.getOption("WorkshopPollingIntervalMinutes", 15) * 60)

        print("Checking workshop for mod updates" ..
                  (lastPoll > 0 and ". Last check was " .. (PL.string.absDifference(timestamp, lastPoll) .. " ago") or
                      "") .. ".")

        lastPoll = timestamp

        if Core.getOption("EnableModWatch") == true then
            return Core.pollWorkshop()
        end

    end
end)

Events.OnServerStarted.Add(function()
    Core:ini()
    Core:testNight()
end)

Events.EveryOneMinute.Add(function()
    Core:testNight()
end)

Events.EveryTenMinutes.Add(function()
    -- refresh periodically so we aren't constantly reading from function
    Core.settings.Debug = Core.getOption("Debug", false)
end)

-- print('- -- -- EVENTS! --  - ')
-- local e = {}
-- for k, v in pairs(Events) do
--     table.insert(e, k)
-- end
-- table.sort(e, function(a, b)
--     return a < b
-- end)
-- PhunLib.printTable(e)
-- print(" /-------")
