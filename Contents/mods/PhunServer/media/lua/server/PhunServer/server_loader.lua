local Core = PhunServer
local PL = PhunLib

local fileTools = PL.file
local tableTools = PL.table

function Core.getSavedData()

    local data = {}

    -- this is a server or local game
    -- load the modified data from ./lua/PhunServer.lua
    -- local filename = Core.name .. ".lua"
    -- local d = fileTools.loadTable(filename)
    -- if d == nil then
    --     print("PhunServer: missing ./lua/" .. Core.name .. ", this is normal if you haven't defined any schedules")
    --     return {}
    -- else
    --     print("PhunServer: loaded customisations from ./lua/" .. Core.name .. ".lua")
    --     return d or {}
    -- end

end

function Core.saveData(data)

    local filename = Core.name .. ".lua"
    fileTools.saveTable(data, filename)
    print("PhunServer: saved data to ./lua/" .. Core.name .. ".lua")

end
