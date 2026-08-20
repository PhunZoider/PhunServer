if isServer() then
    return
end

local Core = require "PhunServer2/core"
require "PhunServer2/client_notify"
require "PhunServer2/client_chat_commands"
local Commands = require "PhunServer2/client_commands"

-- One-shot bootstrap. OnGameStart is unreliable for this in MP, so we take the
-- first tick and remove ourselves.
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

Events.EveryTenMinutes.Add(function()
    -- v1 only refreshed this server-side, so client verbose logging was frozen
    -- at whatever SandboxVars held at load time.
    Core.refreshSettings()
end)
