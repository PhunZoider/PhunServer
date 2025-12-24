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

local canSeeAll = nil
local factionNames = nil

function Core.canSeeAllPlayers(refresh)

    if canSeeAll == nil or refresh then
        local p = getPlayer()
        canSeeAll = PL.isAdmin(p) or
                        (p and p.getRole and p:getRole().hasCapability and
                            p:getRole():hasCapability(Capability.CanSeeAll))
    end
    return canSeeAll
end

local online = {}
function Core.updatePlayers()

    local players = getOnlinePlayers()
    local me = getPlayer()
    local seen = getTimestamp()

    if Core.players == nil then
        Core.players = {}
        online[string.lower(me:getUsername())] = seen
        local me = getPlayer()
        Core.players[string.lower(me:getUsername())] = {
            id = -1,
            me = true,
            canSeeAll = Core.canSeeAllPlayers(),
            faction = getFactionName(me),
            myFaction = true,
            num = me:getPlayerNum(),
            seen = seen,
            username = me:getUsername(),
            x = me:getX(),
            y = me:getY(),
            z = me:getZ()
        }
    end

    local myFaction = getFactionName(me)

    for i = 0, players:size() - 1 do
        local p = players:get(i)
        local name = string.lower(p:getUsername())
        local faction = getFactionName(p)
        online[name] = seen
        Core.players[name] = {
            id = p:getOnlineID(),
            me = (p == me),
            seen = seen,
            myFaction = faction and faction == myFaction,
            faction = getFactionName(p),
            username = p:getUsername(),
            x = p:getX(),
            y = p:getY(),
            z = p:getZ()
        }

    end

    for k, v in pairs(online) do
        -- remove any stale players
        if v ~= seen then
            online[k] = nil
            Core.players[k] = nil
        end
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

