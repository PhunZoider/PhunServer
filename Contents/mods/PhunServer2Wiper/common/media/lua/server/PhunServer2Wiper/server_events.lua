if isClient() then
    return
end

local Core = require "PhunServer2/core"
local Wiper = require "PhunServer2Wiper/core"
require "PhunServer2Wiper/server_wipe"

local Commands = {}

-- The client gates /wipemap too, but a client can send whatever it likes, and
-- this one erases player data. Re-check server-side.
local function mayWipe(player)
    if not player then
        return false
    end
    local level = player.getAccessLevel and player:getAccessLevel()
    return level == "admin" or level == "moderator"
end

Commands[Wiper.commands.wipeRequest] = function(player, args)
    if not mayWipe(player) then
        Wiper.logLn("Rejected a wipe request from " ..
                        tostring(player and player:getUsername() or "?") .. ": insufficient access")
        return
    end

    local target = args and args.target

    if target == "all" then
        local count = Wiper.forceWipeAll({})
        sendServerCommand(player, Core.name, Core.commands.message, {
            username = player:getUsername(),
            text = "IGUI_PhunServer2Wiper_WipedAll",
            args = {tostring(count)}
        })
        return
    end

    local ok = Wiper.forceWipe(target, {})
    sendServerCommand(player, Core.name, Core.commands.message, {
        username = player:getUsername(),
        text = ok and "IGUI_PhunServer2Wiper_Wiped" or "IGUI_PhunServer2Wiper_NotOnline",
        args = {tostring(target)}
    })
end

Events.OnInitGlobalModData.Add(function()
    Wiper.data = ModData.getOrCreate(Wiper.const.modDataName)
    if not Wiper.data.wipeKeys then
        Wiper.data.wipeKeys = {}
    end
end)

Events.OnClientCommand.Add(function(module, command, playerObj, arguments)
    if module == Wiper.name and Commands[command] then
        Commands[command](playerObj, arguments)
    end
end)

Events[Core.events.OnReady].Add(function()
    Wiper.logState()
end)

-- Both a first join and a return are wipe-key checkpoints
Events[Core.events.OnPlayerJoined].Add(function(username)
    Wiper.check(username)
end)

Events[Core.events.OnPlayerRejoined].Add(function(username)
    Wiper.check(username)
end)

Events.OnCharacterDeath.Add(function(player)
    if not instanceof(player, "IsoPlayer") then
        return
    end
    local username = player:getUsername()
    if username and username ~= "" then
        Wiper.resetForNewCharacter(username)
    end
end)
