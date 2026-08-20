-- PhunServer2Wiper
--
-- Wipes a player's explored map and/or map symbols when the admin's wipe key
-- changes, or when they roll a new character if that option is on.
--
-- Wiping is destructive and irreversible, so it is never implicit. See
-- server_wipe.lua for the three rules that guarantee installing this mod
-- mid-game cannot erase anyone's map.
local Core = require "PhunServer2/core"

PhunServer2Wiper = {
    name = "PhunServer2Wiper",
    core = Core,
    const = {
        modDataName = "PhunServer2Wiper"
    },
    commands = {
        wipeMap = "wipeMap",
        wipeRequest = "wipeRequest"
    }
}

local Wiper = PhunServer2Wiper

Wiper.getOption = Core.optionGetter(Wiper.name)
Wiper.verboseLn = Core.logger(Wiper.name)

function Wiper.logLn(str)
    Core.logLn(str, Wiper.name)
end

return PhunServer2Wiper
