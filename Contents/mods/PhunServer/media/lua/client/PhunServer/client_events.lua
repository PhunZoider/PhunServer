if isServer() then
    return
end
local Core = PhunServer
local PL = PhunLib
local Commands = require("PhunServer/client_commands")

local function setup()
    Events.OnTick.Remove(setup)
    Core:ini()
    sendClientCommand(Core.name, Core.commands.playerSetup, {})

end

Events.OnTick.Add(setup)

Events.OnServerCommand.Add(function(module, command, arguments)
    if module == Core.name and Commands[command] then
        Commands[command](arguments)
    end
end)

Events[Core.events.OnReady].Add(function()
    Core.debugLn("Client is ready")

    Core.map.pom = Core.getOption("PlayersOnMap", 1)
    Core.map.pomm = Core.getOption("PlayersOnMiniMap", 1)
    Core.debugLn("===========================")
    Core.debugLn("Players on Map/MiniMap features " .. tostring(Core.map.pom) .. " / " .. tostring(Core.map.pomm))
    Core.debugLn("===========================")
    if Core.map.pom > 1 or Core.map.pomm > 1 then
        Core.map.ini()
        -- we need to track factions
        Events.OnPreUIDraw.Add(function()
            Core.map.OnPreUIDraw()
        end);
        Events.OnPostUIDraw.Add(function()
            Core.map.OnPostUIDraw()
        end);

        Events.EveryTenMinutes.Add(function()
            -- Recache map options
            Core.map.pom = Core.getOption("PlayersOnMap", 1)
            Core.map.pomm = Core.getOption("PlayersOnMiniMap", 1)
        end);
    end
end)

local nextTick = 0
Events.OnTick.Add(function()
    if getTimestampMs() >= nextTick then
        Core.updatePlayers()
        nextTick = getTimestampMs() + (Core.getOption("PlayersUpdateMs") or 1500)
    end
end)

Events.EveryOneMinute.Add(function()
    Core:testNight()
end)
