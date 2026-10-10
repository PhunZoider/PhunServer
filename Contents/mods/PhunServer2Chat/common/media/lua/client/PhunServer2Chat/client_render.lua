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

-- Wrapping a name in colour tags is not just a matter of concatenation, because
-- of how ISRichTextPanel:paginate reads the line. It splits on spaces, treats
-- any token containing <...> as a command, and starts a fresh chunk positioned
-- at the running x. Three consequences decide what gets emitted here:
--
--   * A character touching a tag is swallowed with it. "(<PUSHRGB:...>" parses
--     as the command and the bracket is simply gone, so every tag needs a
--     literal space either side to stay a token of its own.
--   * Chunk boundaries carry no width, so a visible gap only appears where a
--     <SPACE> command asks for one. That is why the tags cannot just be
--     dropped in: without it the name runs into the following word.
--   * <SPACE> is unconditional, so emitting it on both sides regardless of
--     context pushed punctuation off the name - "Bob ," rather than "Bob," -
--     and doubled the gap between two names that sat next to each other. It is
--     emitted only where the source text actually had whitespace, and only once
--     per gap.
--
-- Written with find and sub rather than gsub with a position capture, because
-- the game runs Kahlua rather than a reference Lua and the pattern extensions
-- are not worth relying on.
local function highlightRawText(raw, lookup)
    if not raw or raw == "" then
        return raw
    end

    local highlightColor = "255,255,255"
    local color = Chat.getOption("ColorUsernameText", "")
    if color and color ~= "" then
        highlightColor = color
    end

    local out = {}
    local pos = 1
    local prevTrailed = false

    while true do
        local s, e, token = raw:find("([%w_%.%-]+)", pos)
        if not s then
            break
        end

        local gap = raw:sub(pos, s - 1)

        if lookup[string.lower(token)] then
            local before = s > 1 and raw:sub(s - 1, s - 1) or ""
            local after = raw:sub(e + 1, e + 1)
            local lead = before:match("%s") and "<SPACE>" or ""
            local trail = after:match("%s") and "<SPACE>" or ""

            -- The name before this one already paid for the gap between them.
            if prevTrailed and gap:match("^%s*$") then
                lead = ""
            end

            out[#out + 1] = gap
            out[#out + 1] = " <PUSHRGB:" .. highlightColor .. ">" .. lead .. " " .. token .. " " ..
                                trail .. "<POPRGB> "
            prevTrailed = trail ~= ""
        else
            out[#out + 1] = raw:sub(pos, e)
            prevTrailed = false
        end

        pos = e + 1
    end

    out[#out + 1] = raw:sub(pos)
    return table.concat(out)
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
