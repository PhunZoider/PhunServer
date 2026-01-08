if not isServer() then
    return
end

local Core = PhunServer
local PL = PhunLib


function Core.getSchedule(refresh)
    if Core.data == nil or refresh == true then
        
        local config = Core.getSavedData()
        local cache = {}
        if config and config.schedules then
            cache = config.schedules
        else
            cache = {}
        end

        for _, sch in pairs(Core.data.schedules or {}) do
            cache[sch.name] = sch
        end
        Core.data.schedules = cache
    end
    return Core.data.schedules or {}
end

local function examples()


    -- Scheduled restart
    local restartSchedule = {
        name = "restarts",
        enabled = true,
        type = "restart",
        times = {"03:00", "15:00"}, -- 24-hour format or cron expression
        message = "Server will restart in 5 minutes!",
        warningTimes = {300, 60, 30, 10, 5},
    }

    local a = {
        action = "restart",
        startTime = "02:00",
        reoccurEvery = 1,
        repeatUnit = "days", -- days, weeks, months, hours, minutes
        announcements = {
            {timeBefore = 300, message = "Server will restart in 5 minutes!"},
            {timeBefore = 60, message = "Server will restart in 1 minute!"},
        }
    }

    local b = {
        action = "poll_workshop",
        startTime = "02:00", -- optional. If nil, will run from server start time
        endTime = nil, -- optional. If nil, will run indefinitely
        reoccurEvery = 15,
        repeatUnit = "minutes", -- days, weeks, months, hours, minutes
        announcements = {}  
    }

end


