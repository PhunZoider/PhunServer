if isClient() then
    return
end

local Core = require "PhunServer2/core"
require "PhunServer2/server_config"
require "PhunServer2/server_players"
require "PhunServer2/server_shutdown"
local Commands = require "PhunServer2/server_commands"

Events.OnInitGlobalModData.Add(function()
    -- This replaces the placeholder table declared in core.lua, so nothing
    -- should write to Core.data before this fires.
    Core.data = ModData.getOrCreate(Core.const.modDataName)
    if not Core.data.online then
        Core.data.online = {}
    end
end)

Events.OnClientCommand.Add(function(module, command, playerObj, arguments)
    if module == Core.name and Commands[command] then
        Commands[command](playerObj, arguments)
    end
end)

-- Tells everyone already here about a new arrival, so they can highlight the
-- name. The full list goes out once per client on the playerSetup handshake;
-- this only has to carry what changed since.
--
-- One name rather than the whole roster: sendServerCommand serialises its
-- payload in full on every call, with no delta of its own, so resending the
-- list would repeat to every client what all of them already hold. There is no
-- matching leave broadcast, because clients never drop a name - a departing
-- player stays highlightable for the rest of the session, which is the point.
--
-- Deliberately independent of the chat module's announcement settings: an admin
-- who has turned off join announcements still wants names highlighted.
local function announceArrival(username)
    if not username or username == "" then
        return
    end
    sendServerCommand(Core.name, Core.commands.roster, {
        names = {username}
    })
end

Events[Core.events.OnPlayerJoined].Add(announceArrival)
Events[Core.events.OnPlayerRejoined].Add(announceArrival)

local nextPlayerCheck = 0

Events.OnTickEvenPaused.Add(function()
    local now = getTimestamp()
    if now >= nextPlayerCheck then
        nextPlayerCheck = now + 2
        Core.checkPlayers()
    end
end)

Events.OnServerStarted.Add(function()

    -- Workaround for a B42 bug where sandbox settings are cached and later
    -- edits to the server's Sandbox_Vars file are ignored until this reload.
    if Core.getOption("RefreshSettingsOnStartup", true) then
        Core.logLn("Refreshing sandbox options from the server lua file...")
        getSandboxOptions():loadServerLuaFile(getServerName())
        getSandboxOptions():applySettings()
        Core.refreshSettings()
    end

    Core:ini()
end)

Events.EveryTenMinutes.Add(function()
    -- Pick up sandbox edits made while the server is running
    Core.refreshSettings()
end)
