-- Local utility surface for the PhunServer2 family.
-- Everything in here was previously borrowed from the PhunLib mod. It is folded
-- in so that no PhunServer2 module carries an external dependency.
local json = require "PhunServer2/json"
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
--
-- These files used to be Lua source: saveTable wrote "return { ... }" and
-- loadTable handed the text back to loadstring. B42.20.4 removed loadstring,
-- load and loadfile, so that round trip no longer completes. Nothing errors:
-- loadstring is simply nil, the pcall around it fails, and every config file on
-- disk reads back as nil. An admin's customisations do not survive a restart,
-- and the next save writes the defaults over the top of them.
--
-- The format is therefore JSON, which needs a parser rather than an
-- interpreter. The trade is that a config file can no longer hold Lua
-- expressions. None of ours ever did, but a hand-written one might, and there
-- is no way to read those on the new runtime: hence the converter below.
-- ---------------------------------------------------------------------------

-- Where an admin converts a pre-B42.20.4 config file. The page is format
-- generic and lives in the PhunZones repository because that is where it was
-- first needed; it handles every Phun mod's files, this one included.
tools.converterUrl = "https://phunzoider.github.io/PhunZones/converter/"

-- The pre-JSON name for a config file: PhunServer2Cron.json -> ...Cron.txt.
-- Only used to notice that an old file is sitting there unconverted.
function tools.legacyNameFor(filename)
    return (filename:gsub("%.json$", ".txt"))
end

-- Whole file as one string, or nil when it is not there.
local function readAll(filename, createIfNotExists)
    local reader = getFileReader(filename, createIfNotExists == true)
    if not reader then
        return nil
    end
    local lines = {}
    local line = reader:readLine()
    while line do
        lines[#lines + 1] = line
        line = reader:readLine()
    end
    reader:close()
    return table.concat(lines, "\n")
end

-- True when an old-format file is present and its JSON replacement is not.
-- Callers use this to tell "the admin has not converted yet" apart from "the
-- admin has never configured this", which loadTable reports the same way.
function tools.needsConversion(filename)
    local legacy = tools.legacyNameFor(filename)
    if legacy == filename then
        return false
    end
    local current = readAll(filename, false)
    if current and current ~= "" then
        return false
    end
    local old = readAll(legacy, false)
    return old ~= nil and old ~= ""
end

-- NOTE the argument order: (filename, data). PhunServer v1 called the PhunLib
-- equivalent the other way round, which silently serialised the filename.
--
-- Written indented rather than minified: these are files admins edit by hand.
-- @return true on success, false if nothing was written
function tools.saveTable(filename, data)
    if not data then
        return false
    end

    local encoded, err = json.encode(data, true)
    if not encoded then
        -- Deliberately before getFileWriter. That call truncates on open, so
        -- opening it and only then finding we have nothing to write would
        -- replace a good file with an empty one. The likeliest cause is a
        -- non-string table key, which the Lua format allowed and JSON does not.
        print("[PhunServer2] refusing to save '" .. filename .. "': " .. tostring(err))
        print("[PhunServer2] the file on disk has been left as it was")
        return false
    end

    local fileWriterObj = getFileWriter(filename, true, false)
    if not fileWriterObj then
        return false
    end
    fileWriterObj:write(encoded)
    fileWriterObj:close()
    return true
end

-- Reads a JSON file from the Lua folder and returns its table, or nil when the
-- file is missing, empty or malformed.
--
-- Unlike require, this reads from disk every time, so it always reflects the
-- current state of the file. Use this for mutable config files; use require for
-- static data that never changes at runtime.
--
-- nil for malformed is the same answer as for missing, which is not ideal, but
-- every caller already treats nil as "nothing configured" and the alternative
-- is refusing to start. The message on the way out is what makes the
-- difference visible.
function tools.loadTable(filename, createIfNotExists)
    local src = readAll(filename, createIfNotExists)
    if not src or src == "" then
        return nil
    end

    local result, err = json.decode(src)
    if err then
        print("[PhunServer2] could not read '" .. filename .. "': " .. tostring(err))
        print("[PhunServer2] its settings are not being applied; the file has not been changed")
        return nil
    end

    -- A JSON file whose top level is a string or a number parses fine and is
    -- still not a config. Callers index the result, so hand back nil rather
    -- than something that errors on first use.
    if type(result) ~= "table" then
        print("[PhunServer2] '" .. filename .. "' does not contain a JSON object")
        return nil
    end

    return result
end

return tools
