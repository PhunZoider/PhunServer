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

Events.OnPlayerDeath.Add(function(player)
    if Core.getOption("WipePerCharacter") then
        -- reset to random key to force wipe next time
        Core.data.wipeKeys[player:getUsername()] = tostring(getTimestampMs())
    end
end)

Events[Core.events.OnReady].Add(function()
    Core.debugLn("Client is ready")
end)

local nextTick = 0
Events.OnTick.Add(function()
    if getTimestampMs() >= nextTick then

        local players = getOnlinePlayers()
        local playerInfo = {}
        for i = 0, players:size() - 1 do
            local p = players:get(i)
            local faction = Faction.getPlayerFaction(p);
            if not Core.usernames[string.lower(p:getUsername())] then
                Core.usernames[string.lower(p:getUsername())] = p:getUsername()
            end
            playerInfo[p:getOnlineID()] = {
                id = p:getOnlineID(),
                num = p:getPlayerNum(),
                username = p:getUsername(),
                x = p:getX(),
                y = p:getY(),
                z = p:getZ()
            }

        end
        Core.players = playerInfo
        nextTick = getTimestampMs() + (Core.getOption("PlayersUpdateMs") or 1500)
    end
end)

Events.OnPreUIDraw.Add(function()
    Core.map.OnPreUIDraw()
end);
Events.OnPostUIDraw.Add(function()
    Core.map.OnPostUIDraw()
end);

Events.EveryTenMinutes.Add(function()
    Core.map.pom = Core.getOption("PlayersOnMap") or 1
    Core.map.pomm = Core.getOption("PlayersOnMiniMap") or 1
end);
Events.EveryOneMinute.Add(function()
    Core:testNight()
end)
