if isServer() then
    return
end

local Core = require "PhunServer2/core"
local Wiper = require "PhunServer2Wiper/core"

-- ---------------------------------------------------------------------------
-- The actual erasure, which has to happen client-side because explored map
-- data and map symbols live on the client.
--
-- v1 reached for the global ISWorldMap_instance, which only ever existed
-- because the (now removed) players-on-map feature assigned it inside its own
-- render override. With that feature gone the global is always nil. We resolve
-- the map instance from the vanilla API instead.
-- ---------------------------------------------------------------------------

local function playerNum(player)
    return player and player:getPlayerNum() or 0
end

-- ISWorldMap.ShowWorldMap must run first: the instance is created lazily.
local function worldMapInstance(num)
    if ISWorldMap.getInstance then
        return ISWorldMap.getInstance(num)
    end
    -- Older signature kept as a fallback
    return ISWorldMap_instance
end

function Wiper.wipeMap(player, args)

    args = args or {}
    local num = playerNum(player)
    local username = player and player:getUsername() or "?"

    local doMap = args.map == true or (args.map ~= true and Wiper.getOption("WipeMap", true) == true)
    local doSymbols = args.symbols == true or (args.symbols ~= true and Wiper.getOption("WipeSymbols", true) == true)

    if not doMap and not doSymbols then
        Wiper.verboseLn("Nothing to wipe for " .. username .. ": both WipeMap and WipeSymbols are off")
        return
    end

    Wiper.logLn("Wiping map for " .. username .. (doMap and " [explored]" or "") ..
                    (doSymbols and " [symbols]" or ""))

    ISWorldMap.ShowWorldMap(num)

    local ok, err = pcall(function()
        if doMap then
            WorldMapVisited.getInstance():forget()
        end

        if doSymbols then
            local wm = worldMapInstance(num)
            if not wm or not wm.mapAPI then
                Wiper.logLn("Could not reach the world map API, skipping symbols for " .. username)
                return
            end
            local symbols = wm.mapAPI:getSymbolsAPI()
            -- Symbols are zero-indexed, so the loop has to reach 0.
            -- v1 stopped at 1 and always left the first symbol behind.
            for i = symbols:getSymbolCount() - 1, 0, -1 do
                symbols:removeSymbolByIndex(i)
            end
        end
    end)

    ISWorldMap.HideWorldMap(num)

    if not ok then
        Wiper.logLn("Error while wiping the map for " .. username .. ": " .. tostring(err))
    end
end
