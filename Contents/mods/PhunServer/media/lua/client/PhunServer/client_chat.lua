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

local function isEmptyTable(t)
    if type(t) ~= "table" then
        return true
    end
    for _ in pairs(t) do
        return false
    end
    return true
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
    -- print(finalText)
    Core.message(finalText)
end

function Core.welcomeFirstTime(username)
    if Core.getOption("WelcomeAnnounce", false) then
        local txt = Core.getOption("WelcomeAnnounceText", false)
        if txt == "" then
            txt = false
        end
        if username == getPlayer():getUsername() then
            Core.usernameMessage(txt or "IGUI_PhunServer_WelcomeMyFirstTime", username, "<RGB:0,255,0>")
        else
            Core.usernameMessage(txt or "IGUI_PhunServer_WelcomeFirstTime", username)
        end

    end

end

function Core.welcomeBack(username)

    if Core.getOption("WelcomeAnnounce", false) then
        local txt = Core.getOption("WelcomeAnnounceText", false)
        if txt == "" then
            txt = false
        end
        if username == getPlayer():getUsername() then
            Core.usernameMessage(txt or "IGUI_PhunServer_WelcomeBack", username, "<RGB:0,255,0>")
        else
            local rnd = ZombRand(4)
            Core.usernameMessage(txt or "IGUI_PhunServer_Welcome" .. tostring(rnd), username)
        end
    end
end

function Core.goodbye(username)

    if Core.getOption("GoodbyeAnnouncements", false) then
        if username == getPlayer():getUsername() then
            return
        end
        local txt = Core.getOption("GoodbyeAnnounceText", false)
        if txt == "" then
            txt = false
        end
        local rnd = ZombRand(4)
        Core.usernameMessage(txt or "IGUI_PhunServer_Goodbye" .. tostring(rnd), username, "<RGB:255,255,0>")
    end
end

function Core.usernameMessage(translation, username, color)
    if not Core.players then
        Core.updatePlayers()
    end
    if not Core.players[string.lower(username)] then
        Core.players[string.lower(username)] = {
            username = username
        }
    end
    local text = getText(translation, username)
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
    return PL.isAdmin()
end

Core.cmds = {
    [Core.commands.checkworkshop] = function(args)
        if not PL.isAdmin() then
            return getText("IGUI_PhunServer_NoAccess")
        else
            sendClientCommand(Core.name, "check", args)
        end
        -- indicate that the command was handled
        return true
    end,
    [Core.commands.restart] = function(args)
        if not PL.isAdmin() then
            return getText("IGUI_PhunServer_NoAccess")
        else
            sendClientCommand(Core.name, "restart", args)
        end
        -- indicate that the command was handled
        return true
    end,
    [Core.commands.players] = function(args)
        if Core.getOption("PlayersCommand") == 1 then
            -- return that this command wasn't handled
            return false
        elseif Core.getOption("PlayersCommand") == 2 and not PL.isAdmin() then
            return getText("IGUI_PhunServer_NoAccess")
        end
        sendClientCommand(Core.name, Core.commands.players, args)
        -- indicate that the command was handled
        return true
    end,
    [Core.commands.setHoursSurvived] = function(args)
        if Core.getOption("SetHours") == false or not PL.isAdmin() then
            return getText("IGUI_PhunServer_NoAccess")
        else
            sendClientCommand(Core.name, Core.commands.setHoursSurvived, args)
        end
        -- indicate that the command was handled
        return true
    end,
    [Core.commands.getHoursSurvived] = function(args)
        if Core.getOption("GetHours") == false and not PL.isAdmin() then
            return getText("IGUI_PhunServer_NoAccess")
        else
            if not PL.isAdmin() then
                args = {}
            end
            sendClientCommand(Core.name, Core.commands.getHoursSurvived, args)
        end
        -- indicate that the command was handled
        return true
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
        local command = Core.cmds[enteredCommand:lower()]
        if command ~= nil and command ~= false then
            local result = command(args)
            if result and type(result) == "string" and result ~= "" then
                Core.FakeMessage(result, "<RGB:255,255,0>")
            end
            if result ~= nil and result ~= false then
                -- command was handled, clear the chat input and exit
                ISChat.instance.textEntry:setText("")
                return
            end
        elseif command == false then
            sendClientCommand(Core.name, enteredCommand, args)
            return
        end
    end

    original_command(self)
end

local original_addLIneInChat = ISChat["addLineInChat"]
local lastLineChecked = 0

local function newGetTextWithPrefix(message)
    return message:getTextWithPrefix()
end

-- return the first <RGB:...> tag exactly as-is (Zomboid often uses 0..1 floats)
local function getRestoreRGBTag(text)
    local tag = text:match("(<RGB:[^>]+>)")
    return tag or "<RGB:1.0,1.0,1.0>"
end

local function highlightRawText(raw, lookup, restoreTag)
    if not raw or raw == "" then
        return raw
    end

    local highlightTag = "<RGB:1.0,1.0,1.0>" -- white in Zomboid's float RGB
    local highlightColor = "255,255,255"
    local color = Core.getOption("ColorUsernameText", false)
    if color and color ~= "" then
        highlightColor = color
    end
    -- IMPORTANT: only return the string (gsub returns 2 values)
    local s = raw:gsub("([%w_%.%-]+)", function(token)
        local key = string.lower(token)
        if lookup[key] then
            return "<PUSHRGB:" .. highlightColor .. "><SPACE> " .. token .. " <SPACE><POPRGB>"
        end
        return token
    end)

    return s
end

local function findLastPlain(haystack, needle)
    local lastS, lastE
    local s, e = haystack:find(needle, 1, true) -- plain find
    while s do
        lastS, lastE = s, e
        s, e = haystack:find(needle, e + 1, true)
    end
    return lastS, lastE
end

local function highlightUsernamesInChatLine(message, lookup)
    local baseLine = message:getTextWithPrefix()
    if not baseLine or baseLine == "" then
        return baseLine
    end
    if isEmptyTable(lookup) then
        return baseLine
    end

    local raw = message:getText() -- body only
    if not raw or raw == "" then
        -- system-ish line: no separate body, just highlight the whole thing
        local restore = getRestoreRGBTag(baseLine)
        return highlightRawText(baseLine, lookup, restore)
    end

    local s, e = findLastPlain(baseLine, raw)
    if not s then
        -- fallback if we can't locate the raw inside the formatted line
        local restore = getRestoreRGBTag(baseLine)
        return highlightRawText(baseLine, lookup, restore)
    end

    local restore = getRestoreRGBTag(baseLine)
    local highlightedRaw = highlightRawText(raw, lookup, restore)

    return baseLine:sub(1, s - 1) .. highlightedRaw .. baseLine:sub(e + 1)
end

local function replaceMusicImg(text)
    if not text then
        return text
    end
    if Core.getOption("ReplaceMusic") ~= true then
        return text
    end

    text = text:gsub("%[img=([%w_%-]+)%]", function(name)
        if name == "music" then
            return "<IMAGE:media/textures/music_note.png>"
        end
        return "[img=" .. name .. "]"
    end)
    return text
end

local function replaceRadioPrefix(text)
    if not text then
        return text
    end
    if Core.getOption("ReplaceRadio") ~= true then
        return text
    end

    -- Match ONLY at the start of the line
    -- ^Radio %([^%)]+%):
    text = text:gsub("(%s)Radio%s*%([^%)]+%):", "%1<IMAGE:media/textures/sound_icon.png> ", 1)

    return text
end

ISChat.addLineInChat = function(message, tabID)

    local line = Core.getOption("ColorUsernames", false) and highlightUsernamesInChatLine(message, Core.getPlayers()) or
                     message:getTextWithPrefix()
    line = replaceMusicImg(line)
    line = replaceRadioPrefix(line)

    if message:getAuthor() and ISChat.instance.mutedUsers[message:getAuthor()] then
        message:setText("* * *")
        return
    end
    if not ISChat.instance.chatText then
        ISChat.instance.chatText = ISChat.instance.defaultTab;
        ISChat.instance:onActivateView();
    end
    local chatText;
    for i, tab in ipairs(ISChat.instance.tabs) do
        if tab and tab.tabID == tabID then
            chatText = tab;
            break
        end
    end
    if chatText.tabTitle ~= ISChat.instance.chatText.tabTitle then
        local alreadyExist = false;
        for i, blinkedTab in ipairs(ISChat.instance.panel.blinkTabs) do
            if blinkedTab == chatText.tabTitle then
                alreadyExist = true;
                break
            end
        end
        if alreadyExist == false then
            table.insert(ISChat.instance.panel.blinkTabs, chatText.tabTitle);
        end
    end
    local vscroll = chatText.vscroll
    local scrolledToBottom = (chatText:getScrollHeight() <= chatText:getHeight()) or (vscroll and vscroll.pos == 1)
    if #chatText.chatTextLines > ISChat.maxLine then
        local newLines = {};
        for i, v in ipairs(chatText.chatTextLines) do
            if i ~= 1 then
                table.insert(newLines, v);
            end
        end
        table.insert(newLines, line .. " <LINE> ");
        chatText.chatTextLines = newLines;
    else
        table.insert(chatText.chatTextLines, line .. " <LINE> ");
    end
    chatText.text = "";
    local newText = "";
    for i, v in ipairs(chatText.chatTextLines) do
        if i == #chatText.chatTextLines then
            v = string.gsub(v, " <LINE> $", "")
        end
        newText = newText .. v;
    end
    chatText.text = newText;
    table.insert(chatText.chatMessages, message);
    chatText:paginate();
    if scrolledToBottom then
        chatText:setYScroll(-10000);
    end
end
