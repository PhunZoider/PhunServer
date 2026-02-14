if isServer() then
    return
end
local ISWorldMap_render = ISWorldMap.render;
local ISMiniMapOuter_render = ISMiniMapOuter.render;
local Core = PhunServer
local PL = PhunLib
local getPlayerByOnlineID = getPlayerByOnlineID
local getPlayer = getPlayer
local ISWorldMap_instance = nil;
local ISMiniMap_instance = nil;
local ISWorldMap_players = nil;
local ISMiniMap_players = nil;
local ISMiniMapOuter = ISMiniMapOuter;
local ISWorldMap = ISWorldMap;
local getTextManager = getTextManager;
local UIFont = UIFont;
local Faction = Faction;

local pom_dot_color = {
    r = 0,
    g = 1,
    b = 0,
    a = 1
};

local pom_dot_size = 3;

function Core.map.drawPlayerOnMap(map, player, isMinimap)

    if (map.inner) then
        map = map.inner;
    end
    if not player.x or not player.y then
        return
    end

    -- Get position where to draw
    local x = math.floor(map.mapAPI:worldToUIX(player.x, player.y));
    local y = math.floor(map.mapAPI:worldToUIY(player.x, player.y));

    -- Draw player dot on a map
    map:drawRect(x - pom_dot_size, y - pom_dot_size, pom_dot_size * 2 - 1, pom_dot_size * 2 - 1, pom_dot_color.a,
        pom_dot_color.r, pom_dot_color.g, pom_dot_color.b);
    map:drawRectBorder(x - pom_dot_size, y - pom_dot_size, pom_dot_size * 2, pom_dot_size * 2, 1, 0, 0, 0);

    -- Draw player name on a map

    local width = getTextManager():MeasureStringX(UIFont.Small, player.username) + 8;
    local height = getTextManager():MeasureStringY(UIFont.Small, player.username);
    map:drawRect(x - width / 2, y + pom_dot_size * 2 - 2, width, height + 1, 0.5, 0.5, 0.5, 0.5);
    map:drawText(player.username, x + 4 - width / 2, y - 3 + pom_dot_size * 2, 0, 0, 0, 1, UIFont.Small);

end

local canSeeAll = nil
local factionNames = nil

local function canSeeAllPlayers()

    if canSeeAll == nil then
        local p = getPlayer()
        canSeeAll = PL.isAdmin(p) or
                        (p and p.getRole and p:getRole().hasCapability and
                            p:getRole():hasCapability(Capability.CanSeeAll))
    end
    return canSeeAll

end

local function getFactionNameForPlayer(player)
    if factionNames == nil then
        local f = {}
        for _, player in pairs(PL.onlinePlayers()) do
            local faction = Faction.getPlayerFaction(player)
            f[player:getPlayerNum()] = faction and faction.getName and faction:getName() or nil
        end
        factionNames = f
    end
    return factionNames[player:getPlayerNum()]
end

local getFactionName = function(player)
    local faction = Faction.getPlayerFaction(player)
    return faction and faction.getName and faction:getName() or nil
end

local myFaction = nil
Events.EveryOneMinute.Add(function()
    Core.canSeeAllPlayers(true)
    myFaction = getFactionName(getPlayer())
end)

local function doDrawPlayers(self, mini)
    local players = Core.playerLocations or {}
    local mf = myFaction
    local seenMe = false
    if Core.map.pom == 2 or Core.canSeeAllPlayers() then
        -- show all
        for username, vals in pairs(players) do
            -- if Core.playerLocations[player.username] then
            if username == getPlayer():getUsername() then
                seenMe = true
            end
            Core.map.drawPlayerOnMap(self, {
                username = username,
                x = vals[2],
                y = vals[3]
            }, mini);
            -- end

        end

    elseif Core.map.pom == 3 then
        -- show only if faction match
        for username, vals in pairs(players) do
            if myFaction and vals[1] and myFaction == vals[1] then
                if username == getPlayer():getUsername() then
                    seenMe = true
                end
                Core.map.drawPlayerOnMap(self, {
                    username = username,
                    x = vals[2],
                    y = vals[3]
                }, mini);

            end
        end
    end

    if not seenMe then
        Core.map.drawPlayerOnMap(self, {
            username = getPlayer():getUsername(),
            x = getPlayer():getX(),
            y = getPlayer():getY()
        }, mini);
    end
end

function Core.map.ini()

    function ISWorldMap:render(...)

        ISWorldMap_instance = self;
        ISWorldMap_render(self, ...);
        doDrawPlayers(self, false);
        -- if Core.map.pom == 2 or canSeeAllPlayers() then
        --     -- show all
        --     local seen = getTimestamp() - 5;
        --     for _, player in pairs(Core.players or {}) do
        --         if (player.seen or 0) > seen then
        --             -- stale info, skip
        --             Core.map.drawPlayerOnMap(self, player, false);
        --         end
        --     end

        -- elseif Core.map.pom == 3 then
        --     -- show only if faction match
        --     local f = Faction.getPlayerFaction(getPlayer())
        --     local seen = getTimestamp() - 5;
        --     for _, player in pairs(Core.players or {}) do
        --         if player.me or f and player.faction == f then
        --             if (player.seen or 0) > seen then
        --                 Core.map.drawPlayerOnMap(self, player, false);
        --             end
        --         end
        --     end
        -- end
    end

    function ISMiniMapOuter:render(...)
        ISMiniMap_instance = self;
        ISMiniMapOuter_render(self, ...);

        self.inner:setStencilRect(0, 0, self:getWidth(), self:getHeight());
        doDrawPlayers(self, true);
        -- if Core.map.pom == 2 or canSeeAllPlayers() then
        --     -- show all
        --     local seen = getTimestamp() - 5;
        --     for _, player in pairs(Core.players or {}) do
        --         if (player.seen or 0) > seen then
        --             -- stale info, skip
        --             Core.map.drawPlayerOnMap(self, player, true);
        --         end
        --     end

        -- elseif Core.map.pom == 3 then
        --     -- show only if faction match
        --     local f = Faction.getPlayerFaction(getPlayer())
        --     local seen = getTimestamp() - 5;
        --     for _, player in pairs(Core.players or {}) do
        --         if player.me or f and player.faction == f then
        --             if (player.seen or 0) > seen then
        --                 Core.map.drawPlayerOnMap(self, player, true);
        --             end
        --         end
        --     end
        -- end

        self.inner:clearStencilRect();
    end

end

function Core.map.OnPreUIDraw()

    if (ISWorldMap_instance) then
        ISWorldMap_players = ISWorldMap_instance.mapAPI:getBoolean("Players");
        ISWorldMap_instance.mapAPI:setBoolean("Players", false);
    end

    if (ISMiniMap_instance) then
        ISMiniMap_players = ISMiniMap_instance.inner.mapAPI:getBoolean("Players");
        ISMiniMap_instance.inner.mapAPI:setBoolean("Players", false);
    end
end

function Core.map.OnPostUIDraw()

    if (ISWorldMap_instance and (ISWorldMap_players ~= nil)) then
        ISWorldMap_instance.mapAPI:setBoolean("Players", ISWorldMap_players);
    end

    if (ISMiniMap_instance and (ISMiniMap_players ~= nil)) then
        ISMiniMap_instance.inner.mapAPI:setBoolean("Players", ISMiniMap_players);
    end
end
