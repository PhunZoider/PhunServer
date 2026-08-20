-- Local utility surface for the PhunServer2 family.
-- Everything in here was previously borrowed from the PhunLib mod. It is folded
-- in so that no PhunServer2 module carries an external dependency.
local luautils = luautils
local loadstring = loadstring
local tools = {}

tools.isLocal = not isClient() and not isServer() and not isCoopHost()

function tools.debug(...)

    local args = {...}
    for i, v in ipairs(args) do
        if type(v) == "table" then
            tools.printTable(v)
        else
            print(tostring(v))
        end
    end

end

function tools.printTable(t, indent)
    indent = indent or ""
    for key, value in pairs(t or {}) do
        if type(value) == "table" then
            print(indent .. tostring(key) .. ":")
            tools.printTable(value, indent .. "  ")
        elseif type(value) ~= "function" then
            print(indent .. tostring(key) .. ": " .. tostring(value))
        end
    end
end

-- ---------------------------------------------------------------------------
-- PLAYERS
-- ---------------------------------------------------------------------------

-- Wrapper for getOnlinePlayers that returns only local players when on a client.
function tools.onlinePlayers(all)

    local onlinePlayers;

    if tools.isLocal then
        onlinePlayers = ArrayList.new();
        local p = getPlayer()
        if p then
            onlinePlayers:add(p);
        end
    elseif all ~= false and isClient() then
        onlinePlayers = ArrayList.new();
        for i = 0, getOnlinePlayers():size() - 1 do
            local player = getOnlinePlayers():get(i);
            if player:isLocalPlayer() then
                onlinePlayers:add(player);
            end
        end
    else
        onlinePlayers = getOnlinePlayers();
    end

    return onlinePlayers;
end

-- Matches case-insensitively by default; callers pass already-lowered names.
function tools.getPlayerByUsername(name, caseSensitive)
    if not name then
        return nil
    end
    local online = tools.onlinePlayers()
    local text = caseSensitive and name or string.lower(name)
    for i = 0, online:size() - 1 do
        local player = online:get(i);
        if (caseSensitive and player:getUsername() == name) or
            (not caseSensitive and string.lower(player:getUsername()) == text) then
            return player
        end
    end
    return nil
end

function tools.isAdmin()
    local level = getAccessLevel and (getAccessLevel() == "moderator" or getAccessLevel() == "admin") or false
    return (isAdmin and isAdmin()) or (isDebugEnabled and isDebugEnabled()) or level
end

-- ---------------------------------------------------------------------------
-- TABLES
-- ---------------------------------------------------------------------------

-- Shallow copy, optionally omitting keys. Nested tables stay shared references.
function tools.shallowCopy(original, excludeKeys)
    local exclude = {}
    for _, k in ipairs(excludeKeys or {}) do
        exclude[k] = true
    end
    local copy = {}
    for key, value in pairs(original or {}) do
        if not exclude[key] then
            copy[key] = value
        end
    end
    return copy
end

-- Fully independent deep copy, optionally omitting keys.
function tools.deepCopy(original, excludeKeys)
    local exclude = {}
    for _, k in ipairs(excludeKeys or {}) do
        exclude[k] = true
    end

    local function _copy(obj)
        if type(obj) ~= "table" then
            return obj
        end
        local result = {}
        for k, v in pairs(obj) do
            if not exclude[k] then
                result[_copy(k)] = _copy(v)
            end
        end
        setmetatable(result, getmetatable(obj))
        return result
    end

    return _copy(original)
end

-- ---------------------------------------------------------------------------
-- STRINGS
-- ---------------------------------------------------------------------------

-- 1234567 -> "1,234,567". Rounds away any fractional part.
function tools.formatWholeNumber(number)
    number = number or 0
    local roundedNumber = math.floor(number + 0.5)
    local negative = roundedNumber < 0
    local formattedNumber = tostring(math.abs(roundedNumber)):reverse():gsub("(%d%d%d)", "%1,")
    formattedNumber = formattedNumber:reverse():gsub("^,", "")
    return (negative and "-" or "") .. formattedNumber
end

local secondsInMinute = 60
local secondsInHour = 3600
local secondsInDay = 86400
local secondsInMonth = 2592000 -- approximate, 30 days
local secondsInYear = 31536000 -- approximate, 365 days

-- Splits the gap between two timestamps into components. Order is largest first.
-- Returns years, months, days, hours, minutes, seconds. Never returns negatives.
function tools.timeDifference(time1, time2)
    time2 = time2 or getTimestamp()
    local diff = math.abs((time1 or 0) - (time2 or 0))

    local years = math.floor(diff / secondsInYear)
    diff = diff % secondsInYear
    local months = math.floor(diff / secondsInMonth)
    diff = diff % secondsInMonth
    local days = math.floor(diff / secondsInDay)
    diff = diff % secondsInDay
    local hours = math.floor(diff / secondsInHour)
    diff = diff % secondsInHour
    local minutes = math.floor(diff / secondsInMinute)
    local seconds = diff % secondsInMinute

    return years, months, days, hours, minutes, seconds
end

-- Renders a duration in seconds as readable text, largest unit first.
--   opts.maxParts  how many magnitude components to emit (default 2)
--   opts.zeroText  translation key or literal used when nothing rounds up
-- Example: 93784 -> "1 day 2 hours"
function tools.secondsToText(seconds, opts)
    opts = opts or {}
    local maxParts = opts.maxParts or 2
    local years, months, days, hours, minutes, secs = tools.timeDifference(math.abs(seconds or 0), 0)

    local parts = {}
    local candidates = {{years, "Year", "Years"}, {months, "Month", "Months"}, {days, "Day", "Days"},
                        {hours, "Hour", "Hours"}, {minutes, "Minute", "Minutes"}}

    for _, c in ipairs(candidates) do
        if #parts >= maxParts then
            break
        end
        local value = c[1]
        if value > 0 then
            local key = "IGUI_PhunServer2_X_" .. (value == 1 and c[2] or c[3])
            table.insert(parts, getTextOrNull(key, tostring(value)) or (tostring(value) .. " " .. c[2]))
        end
    end

    if #parts == 0 then
        local zero = opts.zeroText or "IGUI_PhunServer2_LessThanMinute"
        return getTextOrNull(zero) or zero
    end

    return table.concat(parts, " ")
end

-- Readable gap between two timestamps, e.g. "5 minutes". Order-independent.
function tools.absDifference(a, b, opts)
    return tools.secondsToText(math.abs((a or 0) - (b or 0)), opts)
end

-- ---------------------------------------------------------------------------
-- FILE IO
-- Paths are relative to the game's Lua folder (<Zomboid>/Lua/).
-- ---------------------------------------------------------------------------

-- Converts a table to a source string that loadstring can turn back into a table.
-- The array part is emitted before the hash part so output stays stable.
function tools.tableToString(tbl, indent)
    indent = indent or 0
    local prefix = string.rep("  ", indent + 1)
    local result = {}
    local doneKeys = {}

    for i = 1, #tbl do
        local value = tbl[i]
        doneKeys[i] = true
        local line
        if type(value) == "table" then
            line = prefix .. tools.tableToString(value, indent + 1)
        elseif type(value) == "string" then
            line = string.format("%s%q", prefix, value)
        else
            line = string.format("%s%s", prefix, tostring(value))
        end
        table.insert(result, line)
    end

    for key, value in pairs(tbl) do
        if not doneKeys[key] then
            local keyStr
            if type(key) == "string" then
                -- Bare key if it is a valid identifier, bracketed and quoted otherwise
                if string.match(key, "^[%a_][%w_]*$") then
                    keyStr = key .. " = "
                else
                    keyStr = string.format("[%q] = ", key)
                end
            else
                keyStr = "[" .. tostring(key) .. "] = "
            end

            local line
            if type(value) == "table" then
                line = prefix .. keyStr .. tools.tableToString(value, indent + 1)
            elseif type(value) == "string" then
                line = string.format("%s%s%q", prefix, keyStr, value)
            else
                line = string.format("%s%s%s", prefix, keyStr, tostring(value))
            end
            table.insert(result, line)
        end
    end

    return "{\n" .. table.concat(result, ",\n") .. "\n" .. string.rep("  ", indent) .. "}"
end

-- NOTE the argument order: (filename, data). PhunServer v1 called the PhunLib
-- equivalent the other way round, which silently serialised the filename.
function tools.saveTable(filename, data)
    if not data then
        return
    end
    local fileWriterObj = getFileWriter(filename, true, false)
    if not fileWriterObj then
        return
    end
    fileWriterObj:write("return " .. tools.tableToString(data))
    fileWriterObj:close()
end

local function tableOfStringsToTable(lines)
    if not lines or type(lines) ~= "table" or #lines == 0 then
        return nil, "invalid input: empty or non-table"
    end

    local startsWithReturn = luautils.stringStarts(lines[1], "return")
    local src
    if startsWithReturn then
        src = table.concat(lines, "\n")
    else
        src = "return {\n" .. table.concat(lines, "\n") .. "\n}"
    end

    local ok, chunk = pcall(loadstring, src)
    if not ok or not chunk then
        return nil, "loadstring error: " .. tostring(chunk)
    end

    local ok2, result = pcall(chunk)
    if not ok2 then
        return nil, "execution error: " .. tostring(result)
    end

    return result, nil
end

-- Reads a Lua file from the Lua folder and returns its table.
--
-- Unlike require, this bypasses Lua's module cache so it always reflects the
-- current state of the file on disk. Use this for mutable config files; use
-- require for static data that never changes at runtime.
function tools.loadTable(filename, createIfNotExists)
    local fileReaderObj = getFileReader(filename, createIfNotExists == true)
    if not fileReaderObj then
        return nil
    end

    local lines = {}
    local line = fileReaderObj:readLine()
    while line do
        lines[#lines + 1] = line
        line = fileReaderObj:readLine()
    end
    fileReaderObj:close()

    if #lines == 0 then
        return nil
    end

    -- Defensive: hand-edited files often leave a trailing comma
    if lines[#lines]:sub(-1) == "," then
        lines[#lines] = lines[#lines]:sub(1, -2)
    end

    local result, err = tableOfStringsToTable(lines)
    if err then
        print("[PhunServer2] error loading '" .. tostring(filename) .. "': " .. err)
        return nil
    end

    return result
end

return tools
