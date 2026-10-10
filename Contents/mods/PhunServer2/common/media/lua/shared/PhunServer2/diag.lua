-- Diagnostics: admin tools for the question "why is the world not what it
-- should be". The first one is the square probe (diag_probe.lua): the client
-- and the server each read the same facts about one square, and the window
-- shows them side by side.
--
-- Side by side is the point. A dedicated server keeps state a client never
-- loads, chiefly the save (zones live in map_zone.bin), so the two can
-- disagree about the same square while each looks healthy on its own. That
-- is exactly how a broken zone list hid on a server whose clients were fine.
--
-- Part of core rather than a module of its own: modules exist so an admin can
-- leave out gameplay, and this is read-only and admin-only, so there is
-- nothing to opt out of. It is reached as PhunServer2.diag and adds no global.
-- It routes on its own module name, as core's comment in server_commands.lua
-- asks of anything beyond core's own tiny surface.
local Core = require "PhunServer2/core"

local Diag = {
    name = "PhunServer2Diag",
    commands = {
        probe = "probe",
        probeResult = "probeResult"
    },
    -- Handlers by command name, filled in by server_diag.lua and
    -- client_diag.lua. Kept here so single player can call across without
    -- the wire.
    serverHandlers = {},
    clientHandlers = {}
}

Core.diag = Diag

function Diag.logLn(str)
    Core.logLn(str, Diag.name)
end

-- Client to server. In single player both halves share one Lua state, so the
-- handler is called directly rather than trusting sendClientCommand to loop
-- back.
function Diag.request(command, args)
    if Core.isLocal then
        local handler = Diag.serverHandlers[command]
        if handler then
            handler(getPlayer(), args or {})
        end
        return
    end
    sendClientCommand(Diag.name, command, args or {})
end

-- Server to one client.
function Diag.reply(player, command, args)
    if Core.isLocal then
        local handler = Diag.clientHandlers[command]
        if handler then
            handler(args or {})
        end
        return
    end
    sendServerCommand(player, Diag.name, command, args or {})
end

return Diag
