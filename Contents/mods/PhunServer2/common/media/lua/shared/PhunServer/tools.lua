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
            print(indent .. key .. ":")
            tools.printTable(value, indent .. "  ")
        elseif type(value) ~= "function" then
            print(indent .. key .. ": " .. tostring(value))
        end
    end
end

function tools.getPlayerByUsername(name, caseSensitive)
    local online = tools.onlinePlayers()
    local text = caseSensitive and name or name:lower()
    for i = 0, online:size() - 1 do
        local player = online:get(i);
        if (caseSensitive and player:getUsername() == name) or
            (not caseSensitive and player:getUsername():lower() == text) then
            return player
        end
    end
    return nil
end

function tools.onlinePlayers(all)

    local onlinePlayers;

    if tools.isLocal then
        onlinePlayers = ArrayList.new();
        local p = getPlayer()
        onlinePlayers:add(p);
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

function tools.isAdmin(player)
    if not player then
        return (getAccessLevel and (getAccessLevel() == "moderator" or getAccessLevel() == "admin")) or false
    end
    if tools.isLocal then
        if isAdmin() then
            return true
        end
        if isDebugEnabled() then
            return true
        end
    end
    local level = player:getAccessLevel()
    return level == "admin" or level == "moderator"

end

-- serverside translations
local serverText = {}
if isServer() then
    -- there aren't server translation files, so if we are a server, use these
    serverText["UI_PhunServer_Hour"] = "Hour"
    serverText["UI_PhunServer_HoursAgo"] = "%1 Hours ago"
    serverText["UI_PhunServer_Hours"] = "Hours"
    serverText["UI_PhunServer_Day"] = "Day"
    serverText["UI_PhunServer_Days"] = "Days"
    serverText["UI_PhunServer_DaysAgo"] = "%1 Days"
    serverText["UI_PhunServer_Minutes"] = "Minutes"
    serverText["UI_PhunServer_Minute"] = "Minute"

    serverText["UI_PhunServer_JustNow"] = "Just now"
    serverText["UI_PhunServer_X_ago"] = "%1 ago"

    serverText["UI_PhunServer_X_Second"] = "%1 second"
    serverText["UI_PhunServer_X_Seconds"] = "%1 seconds"
    serverText["UI_PhunServer_X_Minute"] = "%1 minute"
    serverText["UI_PhunServer_X_Minutes"] = "%1 minutes"
    serverText["UI_PhunServer_X_Hour"] = "%1 hour"
    serverText["UI_PhunServer_X_Hours"] = "%1 hours"
    serverText["UI_PhunServer_X_Day"] = "day"
    serverText["UI_PhunServer_X_Days"] = "days"
    serverText["UI_PhunServer_X_Month"] = "%1 month"
    serverText["UI_PhunServer_X_Months"] = "%1 months"
    serverText["UI_PhunServer_X_Year"] = "%1 year"
    serverText["UI_PhunServer_X_Years"] = "%1 years"
    serverText["UI_PhunServer_DaysAndHours"] = "%1 %2, %3 %4"
    serverText["UI_PhunServer_LessThanHour"] = "Less than an hour"
    serverText["UI_PhunServer_LessThanMinute"] = "Less than a minute"
end

-- return the textual difference bewtween two timestamps
function tools.absDifference(time1, time2, opts)
    time2 = tonumber(time2) or os.time()
    time1 = tonumber(time1) or 0

    local diff = time1 - time2
    if diff <= 0 then
        diff = time2 - time1
    end

    return tools.secondsToText(diff, opts)
end

function tools.secondsToText(totalSeconds, opts)
    opts = opts or {}
    local maxParts = tonumber(opts.maxParts) or 1
    if maxParts < 1 then
        maxParts = 1
    end

    local includeSeconds = opts.includeSeconds == true
    local zeroText = opts.zeroText or getText(serverText["UI_PhunServer_JustNow"] or "UI_PhunLib_JustNow")

    local years, months, days, hours, minutes, seconds = tools.secondsToComponents(totalSeconds)

    if (years + months + days + hours + minutes + seconds) == 0 then
        return zeroText
    end

    local parts = {}

    local function addPart(value, singularKey, pluralKey)
        if value > 0 and #parts < maxParts then
            table.insert(parts, tSingPlural(singularKey, pluralKey, value))
        end
    end

    addPart(years, "UI_PhunServer_X_Year", "UI_PhunServer_X_Years")
    addPart(months, "UI_PhunServer_X_Month", "UI_PhunServer_X_Months")
    addPart(days, "UI_PhunServer_X_Day", "UI_PhunServer_X_Days")
    addPart(hours, "UI_PhunServer_X_Hour", "UI_PhunServer_X_Hours")
    addPart(minutes, "UI_PhunServer_X_Minute", "UI_PhunServer_X_Minutes")
    -- Only include seconds if:
    --  - caller wants it, OR
    --  - we have no larger units yet (so "12 seconds" is possible)
    if #parts < maxParts and seconds > 0 and (includeSeconds or #parts == 0) then
        addPart(seconds, "UI_PhunServer_X_Second", "UI_PhunServer_X_Seconds")
    end

    -- If we still have nothing (e.g. 0m 0s but diff >0 shouldn't happen), fallback
    if #parts == 0 then
        return zeroText
    end

    return table.concat(parts, " ")
end

local tid = nil
function tools.getCategory(item)
    if tid == nil then
        if TweakItemData then
            tid = TweakItemData
        else
            tid = false
        end
    end
    if tid then
        local check = TweakItemData[item:getFullName()] or {}
        local test = check["DisplayCategory"] or check["displaycategory"]
        if test then
            return test
        end
    end

    local category = item.getCategory and item:getCategory() or item.getTypeString and item:getTypeString() or nil
    local dcategory = item:getDisplayCategory();

    category = tostring(dcategory or category)

    -- print("Checking category for item: " .. item:getFullName() .. " - DisplayCategory: " .. category)

    if item.fluidContainer then
        local fluid = item.fluidContainer:getFluidContainer():getPrimaryFluid();
        if fluid and item:getFluidContainer():getAmount() > 0 then
            if fluid:isCategory(FluidCategory.Alcoholic) then
                category = "FoodA";
            elseif fluid:isCategory(FluidCategory.Beverage) then
                category = "FoodB";
            elseif fluid:isCategory(FluidCategory.Fuel) then
                category = "Fuel"
            end
        else
            category = "Container";
        end
    elseif item.getCanStoreWater and item:getCanStoreWater() then
        if item:getTypeString() ~= "Drainable" then
            category = "Container";
        else
            category = "FoodB";
        end

    elseif item:getDisplayCategory() == "Water" then
        category = "FoodB";

    elseif item.getTypeString and item:getTypeString() == "Food" then
        if item:getDaysTotallyRotten() > 0 and item:getDaysTotallyRotten() < 1000000000 then
            category = "FoodP";
        else
            category = "FoodN";
        end

    elseif item.getTypeString and item:getTypeString() == "Literature" then
        if string.len(item:getSkillTrained()) > 0 then
            category = "LitS";
        elseif item:getTeachedRecipes() and not item:getTeachedRecipes():isEmpty() then
            category = "LitR";
        elseif item:getStressChange() ~= 0 or item:getBoredomChange() ~= 0 or item:getUnhappyChange() ~= 0 then
            category = "LitE";
        else
            category = "LitW";
        end

    elseif item.getTypeString and item:getTypeString() == "Weapon" then
        if item:getDisplayCategory() == "Explosives" or item:getDisplayCategory() == "Devices" then
            category = "WepBomb";
        end

        -- Tsar's True Music Cassette and Vinyls
    elseif string.find(item:getFullName(), "Tsarcraft.Cassette") or string.find(item:getFullName(), "Tsarcraft.Vinyl") then
        category = "MediaA";

        -- Tsar's True Actions Dance Cards
    elseif item.getTypeString and item:getTypeString() == "Normal" and item:getModuleName() == "TAD" then
        category = "Misc";
    end

    return category or "Unknown"
end

function tools.getAllItemCategories()

    if tools.itemCategories == nil then
        tools.getAllItems()
    end

    return tools.itemCategories

end

function tools.getAllItems(refresh)

    if tools.itemsAll ~= nil and not refresh then
        return tools.itemsAll
    end
    tools.itemsAll = {}
    tools.itemCategories = {}
    local catMap = {}

    local itemList = getScriptManager():getAllItems()
    for i = 0, itemList:size() - 1 do
        local item = itemList:get(i)
        if not item:getObsolete() and not item:isHidden() then

            local cat = tools.getCategory(item) or "Unknown" -- tools.getCategory(item)
            if cat ~= "" and catMap[cat] == nil then
                catMap[cat] = true
                table.insert(tools.itemCategories, {
                    label = cat,
                    type = cat
                })
            end
            table.insert(tools.itemsAll, {
                type = item:getFullName(),
                label = item:getDisplayName(),
                texture = item:getNormalTexture(),
                category = cat
            })
        end
    end

    table.sort(tools.itemsAll, function(a, b)
        return a.label:lower() < b.label:lower()
    end)
    table.sort(tools.itemCategories, function(a, b)
        return a.label:lower() < b.label:lower()
    end)

    return tools.itemsAll
end

function tools.formatWholeNumber(n)
    n = tonumber(n) or 0
    -- Round half-up (works for positives; good enough for UI values)
    local rounded = math.floor(n + 0.5)

    local s = tostring(rounded)
    local sign = ""

    if s:sub(1, 1) == "-" then
        sign = "-"
        s = s:sub(2)
    end

    -- Insert commas
    local rev = s:reverse()
    rev = rev:gsub("(%d%d%d)", "%1,")
    s = rev:reverse():gsub("^,", "")

    return sign .. s
end

function tools.formatNumber(number, decimals)
    number = number or 0
    -- Round the number to remove the decimal part
    local roundedNumber = math.floor(number + (decimals and 0.005 or 0.5))
    -- Convert to string and format with commas
    local formattedNumber = tostring(roundedNumber):reverse():gsub("(%d%d%d)", "%1,")
    formattedNumber = formattedNumber:reverse():gsub("^,", "")
    return formattedNumber
end

-- ---------------------------------------------------------------------------
-- SHALLOW COPY
-- Returns a shallow copy of a table, optionally excluding specified keys.
-- Nested tables are not copied — they remain as shared references.
--
-- @param original    table
-- @param excludeKeys table|nil  array of keys to omit  e.g. {"points", "inherits"}
-- @return            table
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- DEEP COPY
-- Returns a fully independent deep copy of a table, optionally excluding
-- specified keys. Metatables are copied as-is (shallow reference).
-- Safe for nested zone property tables.
--
-- @param original    table
-- @param excludeKeys table|nil  array of keys to omit
-- @return            table
-- ---------------------------------------------------------------------------
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
-- TABLE SERIALISATION
-- Converts a Lua table to a formatted string representation suitable for
-- writing to a file and reloading with loadstring.
-- Handles nested tables, strings, booleans, and numbers.
-- Array parts are serialised before non-array (hash) parts.
-- ---------------------------------------------------------------------------
function tools.tableToString(tbl, indent)
    indent = indent or 0
    local prefix = string.rep("  ", indent + 1)
    local result = {}
    local doneKeys = {}

    -- Array part first (sequential numeric keys from 1)
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

    -- Non-array (hash) part
    for key, value in pairs(tbl) do
        if not doneKeys[key] then
            local keyStr
            if type(key) == "string" then
                -- Bare key if valid identifier, bracketed+quoted otherwise
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

-- ---------------------------------------------------------------------------
-- SAVE TABLE
-- Serialises a table and writes it to a file in the server Lua folder.
-- The file is written as a valid Lua module (return { ... }) so it can be
-- loaded directly with loadTable or require.
--
-- @param filename  string  path relative to the server Lua folder
-- @param data      table   the table to serialise and save
-- ---------------------------------------------------------------------------
function tools.saveTable(filename, data)
    if not data then
        return
    end
    local fileWriterObj = getFileWriter(filename, true, false)
    fileWriterObj:write("return " .. tools.tableToString(data))
    fileWriterObj:close()
end

-- ---------------------------------------------------------------------------
-- TABLE OF STRINGS TO TABLE
-- Internal helper. Takes an array of strings (lines read from a file),
-- concatenates them, and executes the result as a Lua chunk to produce
-- a table. Handles files that do or do not start with "return".
--
-- @param lines  table<string>  array of file lines
-- @return       table|nil, string|nil  (result, error message)
-- ---------------------------------------------------------------------------
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
    if not ok then
        return nil, "loadstring error: " .. tostring(chunk)
    end

    local ok2, result = pcall(chunk)
    if not ok2 then
        return nil, "execution error: " .. tostring(result)
    end

    return result, nil
end

-- ---------------------------------------------------------------------------
-- LOAD TABLE
-- Reads a Lua file from the server Lua folder and returns its contents as
-- a table. Returns nil if the file does not exist or cannot be parsed.
--
-- Unlike require, this bypasses Lua's module cache so it always reflects
-- the current state of the file on disk. Use this for mutable config files.
-- Use require for static data files that never change at runtime.
--
-- @param filename          string   path relative to the server Lua folder
-- @param createIfNotExists boolean  if true, creates the file if missing
-- @return                  table|nil
-- ---------------------------------------------------------------------------
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

    -- Guard against empty files
    if #lines == 0 then
        return nil
    end

    -- Strip trailing comma from last line (defensive: handles hand-edited files)
    if lines[#lines]:sub(-1) == "," then
        lines[#lines] = lines[#lines]:sub(1, -2)
    end

    local result, err = tableOfStringsToTable(lines)
    if err then
        print("PhunServer 2 file_utils: error loading '" .. filename .. "': " .. err)
        return nil
    end

    return result
end

return tools
