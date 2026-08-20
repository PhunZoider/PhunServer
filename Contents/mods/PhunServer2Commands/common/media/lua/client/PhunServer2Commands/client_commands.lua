if isServer() then
    return
end

local Core = require "PhunServer2/core"
local Cmds = require "PhunServer2Commands/core"
local tools = Core.tools
local Commands = {}

local popit = "<SPACE><POPRGB>"
local white = "<PUSHRGB:255,255,255><SPACE>"

local function wrapText(text)
    return white .. " " .. text .. " " .. popit
end

local function joinNames(names)
    local out = {}
    for _, name in ipairs(names) do
        table.insert(out, wrapText(name))
    end
    return table.concat(out, ", ")
end

Commands[Cmds.commands.players] = function(args)
    if args.username and not tools.getPlayerByUsername(args.username) then
        return
    end

    local list = args.players or {}
    local online = list.online or {}
    local text

    if #online == 0 then
        text = getText("IGUI_PhunServer2Commands_NoOtherPlayerOnline")
    elseif #online == 1 then
        text = getText("IGUI_PhunServer2Commands_OneOtherPlayerOnline", wrapText(online[1]))
    else
        text = getText("IGUI_PhunServer2Commands_OtherPlayersOnline", wrapText(tostring(#online + 1)),
            joinNames(online))
    end

    if list.offline then
        local offline = list.offline
        if #offline == 0 then
            text = text .. ". " .. getText("IGUI_PhunServer2Commands_NoOtherPlayerRecently")
        elseif #offline == 1 then
            text = text .. ". " .. getText("IGUI_PhunServer2Commands_OneOtherPlayerRecently", wrapText(offline[1]))
        else
            text = text .. ". " ..
                       getText("IGUI_PhunServer2Commands_OtherPlayersRecently", wrapText(tostring(#offline)),
                    joinNames(offline))
        end
    end

    Core.message(text)
end

Commands[Cmds.commands.getHours] = function(args)
    if args.username and not tools.getPlayerByUsername(args.username) then
        return
    end

    local seconds = (tonumber(args.hours) or 0) * 3600
    local text = tools.secondsToText(seconds, {
        maxParts = 4,
        zeroText = "IGUI_PhunServer2_LessThanMinute"
    })

    Core.message(getText("IGUI_PhunServer2Commands_PlayerHasSurvivedFor", args.player, text))
end

return Commands
