if isServer() then
    return
end

local Core = require "PhunServer2/core"
local Chat = require "PhunServer2Chat/core"

-- ---------------------------------------------------------------------------
-- Chat line decoration.
--
-- This replaces ISChat.addLineInChat wholesale rather than wrapping it,
-- because the decorated text has to be built before the line is appended and
-- the vanilla function offers no hook at that point. The tab blinking,
-- pagination and scroll behaviour below mirrors vanilla.
-- ---------------------------------------------------------------------------

local original_addLineInChat = ISChat.addLineInChat

local function isEmptyTable(t)
    if type(t) ~= "table" then
        return true
    end
    for _ in pairs(t) do
        return false
    end
    return true
end

-- Zomboid mixes 0..1 float RGB and 0..255 integer RGB tags, so reuse whatever
-- tag the line already carries rather than assuming a format.
local function getRestoreRGBTag(text)
    return text:match("(<RGB:[^>]+>)") or "<RGB:1.0,1.0,1.0>"
end

local function highlightRawText(raw, lookup)
    if not raw or raw == "" then
        return raw
    end

    local highlightColor = "255,255,255"
    local color = Chat.getOption("ColorUsernameText", "")
    if color and color ~= "" then
        highlightColor = color
    end

    -- gsub returns two values; parenthesise so only the string escapes
    local s = raw:gsub("([%w_%.%-]+)", function(token)
        if lookup[string.lower(token)] then
            return "<PUSHRGB:" .. highlightColor .. "><SPACE> " .. token .. " <SPACE><POPRGB>"
        end
        return token
    end)

    return s
end

local function findLastPlain(haystack, needle)
    local lastS, lastE
    local s, e = haystack:find(needle, 1, true)
    while s do
        lastS, lastE = s, e
        s, e = haystack:find(needle, e + 1, true)
    end
    return lastS, lastE
end

-- Highlights usernames in the message body only, leaving the prefix intact.
local function highlightUsernames(message, lookup)
    local baseLine = message:getTextWithPrefix()
    if not baseLine or baseLine == "" or isEmptyTable(lookup) then
        return baseLine
    end

    local raw = message:getText()
    if not raw or raw == "" then
        -- System line with no separate body
        return highlightRawText(baseLine, lookup)
    end

    local s, e = findLastPlain(baseLine, raw)
    if not s then
        return highlightRawText(baseLine, lookup)
    end

    return baseLine:sub(1, s - 1) .. highlightRawText(raw, lookup) .. baseLine:sub(e + 1)
end

local function replaceMusicImg(text)
    if not text or Chat.getOption("ReplaceMusic", true) ~= true then
        return text
    end
    return (text:gsub("%[img=([%w_%-]+)%]", function(name)
        if name == "music" then
            return "<IMAGE:media/textures/music_note.png>"
        end
        return "[img=" .. name .. "]"
    end))
end

local function replaceRadioPrefix(text)
    if not text or Chat.getOption("ReplaceRadio", true) ~= true then
        return text
    end
    return (text:gsub("(%s)Radio%s*%([^%)]+%):", "%1<IMAGE:media/textures/sound_icon.png> ", 1))
end

ISChat.addLineInChat = function(message, tabID)

    local line
    if Chat.getOption("ColorUsernames", true) then
        line = highlightUsernames(message, Chat.getPlayers())
    else
        line = message:getTextWithPrefix()
    end

    line = replaceMusicImg(line)
    line = replaceRadioPrefix(line)

    if message:getAuthor() and ISChat.instance.mutedUsers[message:getAuthor()] then
        message:setText("* * *")
        return
    end

    if not ISChat.instance.chatText then
        ISChat.instance.chatText = ISChat.instance.defaultTab
        ISChat.instance:onActivateView()
    end

    local chatText
    for _, tab in ipairs(ISChat.instance.tabs) do
        if tab and tab.tabID == tabID then
            chatText = tab
            break
        end
    end
    if not chatText then
        return
    end

    -- Blink the tab if the line landed somewhere the player isn't looking
    if chatText.tabTitle ~= ISChat.instance.chatText.tabTitle then
        local alreadyExist = false
        for _, blinkedTab in ipairs(ISChat.instance.panel.blinkTabs) do
            if blinkedTab == chatText.tabTitle then
                alreadyExist = true
                break
            end
        end
        if not alreadyExist then
            table.insert(ISChat.instance.panel.blinkTabs, chatText.tabTitle)
        end
    end

    local vscroll = chatText.vscroll
    local scrolledToBottom = (chatText:getScrollHeight() <= chatText:getHeight()) or (vscroll and vscroll.pos == 1)

    if #chatText.chatTextLines > ISChat.maxLine then
        local newLines = {}
        for i, v in ipairs(chatText.chatTextLines) do
            if i ~= 1 then
                table.insert(newLines, v)
            end
        end
        table.insert(newLines, line .. " <LINE> ")
        chatText.chatTextLines = newLines
    else
        table.insert(chatText.chatTextLines, line .. " <LINE> ")
    end

    local newText = ""
    for i, v in ipairs(chatText.chatTextLines) do
        if i == #chatText.chatTextLines then
            v = string.gsub(v, " <LINE> $", "")
        end
        newText = newText .. v
    end
    chatText.text = newText

    table.insert(chatText.chatMessages, message)
    chatText:paginate()

    if scrolledToBottom then
        chatText:setYScroll(-10000)
    end
end
