if isServer() then
    return
end

local Core = PhunServer
local PL = PhunLib

local isAdmin = isAdmin
local getAccessLevel = getAccessLevel
local sendClientCommand = sendClientCommand
local getText = getText
local ISChat = ISChat
local getPlayer = getPlayer
local ZombRand = ZombRand
local tostring = tostring
local getTextOrNull = getTextOrNull
local unpack = unpack
local type = type
local table = table
local Calendar = Calendar
local SimpleDateFormat = SimpleDateFormat
local print = print
local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local string = string

local popit = "<SPACE><POPRGB>"
local white = "<PUSHRGB:255,255,255><SPACE>"
local yellow = "<RGB:255,255,0><SPACE>"

local function wrapText(text)
    return white .. " " .. text .. " " .. popit
end

function Core.playersList(list)
    local finalText = ""

    if #list.online == 0 then
        finalText = getText("IGUI_PhunServer_NoOtherPlayerOnline")
    elseif #list.online == 1 then
        finalText = getText("IGUI_PhunServer_OneOtherPlayerOnline", wrapText(list.online[1]))
    else
        local csv = {}
        for _, name in ipairs(list.online) do
            table.insert(csv, wrapText(name))
        end

        finalText = getText("IGUI_PhunServer_OtherPlayersOnline", wrapText(tostring(#list.online + 1)),
            table.concat(csv, ", "))
    end

    if list.offline then
        if #list.offline == 0 then
            finalText = finalText .. ". " .. getText("IGUI_PhunServer_NoOtherPlayerOffline24")
        elseif #list.offline == 1 then
            finalText = finalText .. ". " ..
                            getText("IGUI_PhunServer_OneOtherPlayerOffline24", wrapText(list.offline[1]))
        else
            local csv = {}
            for _, name in ipairs(list.offline) do
                table.insert(csv, wrapText(name))
            end

            finalText = finalText .. ". " ..
                            getText("IGUI_PhunServer_OtherPlayersOffline24", wrapText(tostring(#list.offline)),
                    table.concat(csv, ", "))
        end
    end
    print(finalText)
    Core.message(finalText)
end

function Core.welcomeFirstTime(username)
    if username == getPlayer():getUsername() then
        Core.usernameMessage("IGUI_PhunServer_WelcomeMyFirstTime", username, "<RGB:0,255,0>")
    else
        Core.usernameMessage("IGUI_PhunServer_WelcomeFirstTime", username)
    end
end

function Core.welcomeBack(username)
    if username == getPlayer():getUsername() then
        Core.usernameMessage("IGUI_PhunServer_WelcomeBack", username, "<RGB:0,255,0>")
    else
        local rnd = ZombRand(4)
        Core.usernameMessage("IGUI_PhunServer_Welcome" .. tostring(rnd), username)
    end
end

function Core.goodbye(username)
    if username == getPlayer():getUsername() then
        return
    end
    local rnd = ZombRand(4)
    Core.usernameMessage("IGUI_PhunServer_Goodbye" .. tostring(rnd), username, "<RGB:0,0,255>")
end

function Core.usernameMessage(translation, username, color)
    local text = getText(translation, wrapText(username))
    Core.message(text, {}, {
        color = color or "<RGB:255,255,0>"
    })
end

function Core.message(text, args, options)
    local txt = getTextOrNull(text, unpack(args or {})) or text
    options = options or {
        color = "<RGB:255,255,0>"
    }
    Core.FakeMessage(txt, options.color)
end

function Core.notifyAll(soundName, types, text, args)
    local players = PL.onlinePlayers()
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p:isLocalPlayer() then
            Core.notify(p, soundName, types, text, args);
        end
    end
end

function Core.notify(player, soundName, types, text, args)

    if soundName and soundName ~= "" and not player:getEmitter():isPlaying(soundName) then
        player:playSoundLocal(soundName)
    end

    if types == nil or types.chat then
        Core.message(text, args)
    end

    if types ~= nil then
        if types.halo then
            if table.unpack then
                player:setHaloNote(getText(text, table.unpack(args or {})))
            else
                player:setHaloNote(getText(text, unpack(args or {})))
            end
        end
    end

end

function Core.FakeMessage(message, color, options)

    if type(options) ~= "table" then
        options = {
            showTime = false,
            serverAlert = false,
            showAuthor = false
        };
    end

    if type(color) ~= "string" then
        color = "<RGB:1,1,1>";
    end

    if options.showTime then
        local dateStamp = Calendar.getInstance():getTime();
        local dateFormat = SimpleDateFormat.new("H:mm");
        if dateStamp and dateFormat then
            message = color .. "[" .. tostring(dateFormat:format(dateStamp) or "N/A") .. "]  " .. message;
        end
    else
        message = color .. message;
    end

    local msg = {
        getText = function(_)
            return message;
        end,
        getTextWithPrefix = function(_)
            return message;
        end,
        isServerAlert = function(_)
            return options.serverAlert;
        end,
        isShowAuthor = function(_)
            return options.showAuthor;
        end,
        getAuthor = function(_)
            return tostring(getPlayer():getDisplayName());
        end,
        setShouldAttractZombies = function(_)
            return false
        end,
        setOverHeadSpeech = function(_)
            return false
        end
    };

    if not ISChat.instance then
        return;
    end
    if not ISChat.instance.chatText then
        return;
    end
    ISChat.addLineInChat(msg, 0)

end

local original_command = ISChat["onCommandEntered"]

Core.hasAccess = function(command)
    return isAdmin() or getAccessLevel() == "moderator" or getAccessLevel() == "admin"
end

Core.cmds = {
    [Core.commands.checkworkshop] = function(args)
        if not Core.hasAccess() then
            return getText("IGUI_PhunServer_NoAccess")
        else
            sendClientCommand(Core.name, "check", args)
        end
    end,
    [Core.commands.restart] = function(args)
        if not Core.hasAccess() then
            return getText("IGUI_PhunServer_NoAccess")
        else
            sendClientCommand(Core.name, "restart", args)
        end
    end,
    [Core.commands.players] = function(args)
        if Core.getOption("Players") == false and not Core.hasAccess() then
            return getText("IGUI_PhunServer_NoAccess")
        else
            sendClientCommand(Core.name, Core.commands.players, args)
        end
    end
}

local function splitString(s, sep)
    if sep == nil then
        sep = "%s"
    end
    local t = {}
    for str in string.gmatch(s, "([^" .. sep .. "]+)") do
        table.insert(t, str)
    end
    return t
end

ISChat["onCommandEntered"] = function(self)

    local commandText = ISChat.instance.textEntry:getText()
    ISChat.instance:logChatCommand(commandText)
    if commandText and commandText ~= "" then

        local strings = splitString(commandText)
        local enteredCommand = nil
        local args = {}

        if #strings == 1 then
            enteredCommand = string.sub(strings[1], 2, #strings[1])
        else
            for i, arg in ipairs(strings) do
                if i == 1 then
                    enteredCommand = string.sub(arg, 2, #arg)
                    print(" Entered command \"" .. enteredCommand .. "\".")
                else
                    table.insert(args, arg)
                end
            end
        end
        local command = Core.cmds[enteredCommand]
        if command ~= nil and command ~= false then
            local result = command(args)
            if result and result ~= "" then
                Core.FakeMessage(result, "<RGB:255,255,0>")
            end
            ISChat.instance.textEntry:setText("")
            return
        elseif command == false then
            sendClientCommand(Core.name, enteredCommand, args)
            return
        end
    end

    original_command(self)
end
