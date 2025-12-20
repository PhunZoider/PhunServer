if isServer() then
    return
end

local Core = PhunServer
local PL = PhunLib

local getFactionName = function(player)
    local faction = Faction.getPlayerFaction(player)
    return faction and faction.getName and faction:getName() or nil
end

function Core.getPlayers()
    if Core.players == nil then
        Core.updatePlayers()
    end
    return Core.players
end

function Core.updatePlayers()

    local players = getOnlinePlayers()
    local me = getPlayer()

    if Core.players == nil then
        Core.players = {}
        -- make sure we're in here
        local me = getPlayer()
        Core.players[string.lower(me:getUsername())] = {
            id = -1,
            me = true,
            faction = getFactionName(me),
            num = me:getPlayerNum(),
            username = me:getUsername(),
            x = me:getX(),
            y = me:getY(),
            z = me:getZ()
        }
    end

    local playerInfo = {}
    local myFaction = getFactionName(me)
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        local faction = getFactionName(p)

        Core.players[string.lower(p:getUsername())] = {
            id = p:getOnlineID(),
            me = (p == me),
            myFaction = faction and faction == myFaction,
            faction = getFactionName(p),
            username = p:getUsername(),
            x = p:getX(),
            y = p:getY(),
            z = p:getZ()
        }

    end

end

function Core.getPlayerInfo(playerOrUsername)
    if Core.players == nil then
        Core.updatePlayers()
    end
    if type(playerOrUsername) == "string" then
        return Core.players[string.lower(playerOrUsername)]
    elseif instanceof(playerOrUsername, "IsoPlayer") then
        return Core.players[string.lower(playerOrUsername:getUsername())]
    end

end

