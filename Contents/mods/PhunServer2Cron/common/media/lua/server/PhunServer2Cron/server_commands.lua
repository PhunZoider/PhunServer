if isClient() then
    return
end

local Core = require "PhunServer2/core"
local Cron = require "PhunServer2Cron/core"
local Commands = {}

Commands[Cron.commands.check] = function(player, args)
    Cron.pollWorkshop(player)
end

Commands[Cron.commands.reload] = function(player, args)
    local jobs = Cron.reloadJobs()
    local count = 0
    for _ in pairs(jobs or {}) do
        count = count + 1
    end
    if player then
        sendServerCommand(player, Core.name, Core.commands.message, {
            username = player:getUsername(),
            text = "IGUI_PhunServer2Cron_Reloaded",
            args = {tostring(count)}
        })
    end
end

return Commands
