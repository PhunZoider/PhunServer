if isServer() then
    return
end
local Core = PhunServer

function Core.map.wipeMap(player, args)

    if args.map == true or args.map ~= true and Core.getOption("WipeMap") == true then
        print("[" .. Core.name .. "] Wiping world map for player " .. player:getUsername())
        ISWorldMap.ShowWorldMap(player and player:getPlayerNum() or getPlayer())
        local wm = WorldMapVisited.getInstance()
        wm:forget()
        ISWorldMap.HideWorldMap(player and player:getPlayerNum() or getPlayer())
    end
    if args.symbols == true or args.symbols ~= true and Core.getOption("WipeSymbols") == true then
        print("[" .. Core.name .. "] Wiping world map symbols for player " .. player:getUsername())
        ISWorldMap.ShowWorldMap(player and player:getPlayerNum() or getPlayer())
        local count = ISWorldMap_instance.mapAPI:getSymbolsAPI():getSymbolCount() - 1
        local wm = ISWorldMap_instance
        for i = count, 1, -1 do
            wm.mapAPI:getSymbolsAPI():removeSymbolByIndex(i)
        end
        ISWorldMap.HideWorldMap(player and player:getPlayerNum() or getPlayer())

    end

end

