if isClient() then
    return
end
require "PhunServer/core"
local Commands = require "PhunServer/server_commands"
local Core = PhunServer

Events.OnInitGlobalModData.Add(function()

    Core.data = ModData.getOrCreate(Core.name)
    if not Core.data.wipeKeys then
        Core.data.wipeKeys = {}
    end
    PhunLib.debug("PhunServer: Loaded wipe keys:", Core.data)

end)

Events.OnClientCommand.Add(function(module, command, playerObj, arguments)
    if module == Core.name and Commands[command] then
        Core.debug(command, arguments)
        Commands[command](playerObj, arguments)
    end
end)

Events.OnDisconnect.Add(function()
    if Core.getOption("RestartDelayMinutes", 5) == 0 then
        Core.pollWorkshop()
    end
end)

local nextPoll
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
    if not nextPoll or timestamp >= nextPoll then
        nextPoll = timestamp + (Core.getOption("WorkshopPollingInterval", 15) * 60)
        return Core.pollWorkshop()
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
    Core.settings.debug = Core.getOption("debug", false)
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
