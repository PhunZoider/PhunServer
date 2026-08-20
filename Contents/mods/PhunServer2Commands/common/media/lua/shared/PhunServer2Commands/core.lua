-- PhunServer2Commands
--
-- The player-facing chat commands: /players, /hours and /sethours.
-- The /command hook itself lives in PhunServer2 core, so this module only
-- supplies commands and their server handlers.
local Core = require "PhunServer2/core"

PhunServer2Commands = {
    name = "PhunServer2Commands",
    core = Core,
    commands = {
        players = "players",
        getHours = "hours",
        setHours = "sethours"
    }
}

local Cmds = PhunServer2Commands

Cmds.getOption = Core.optionGetter(Cmds.name)
Cmds.verboseLn = Core.logger(Cmds.name)

function Cmds.logLn(str)
    Core.logLn(str, Cmds.name)
end

return PhunServer2Commands
