if isServer() then
    return
end

local Core = require "PhunServer2/core"
local Diag = require "PhunServer2/diag"
local Probe = require "PhunServer2/diag_probe"
local Health = require "PhunServer2/diag_health"

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local PAD = 8

-- Column positions in the rich text, in pixels from the panel's left edge
local COL_CLIENT = 220
local COL_SERVER = 420
-- A table cell holds this many characters; the long fields get lines of
-- their own instead
local CELL_CHARS = 26

local Window = ISCollapsableWindow:derive("PhunServer2DiagProbeWindow")
Diag.ProbeWindow = Window

local nextToken = 0

-- Rich text treats < and > as tags, and a zone name is free text
local function clean(text)
    return (string.gsub(tostring(text), "[<>]", function(c)
        return c == "<" and "[" or "]"
    end))
end

local function cell(text)
    text = clean(text)
    if #text > CELL_CHARS then
        text = string.sub(text, 1, CELL_CHARS - 3) .. "..."
    end
    return text
end

local function label(key)
    return getText("IGUI_PhunServer2_Diag_F_" .. key)
end

function Window:new(x, y, width, height)
    local o = ISCollapsableWindow.new(self, x, y, width, height)
    o.title = getText("IGUI_PhunServer2_Diag_Title")
    o.resizable = true
    o.minimumWidth = 560
    o.minimumHeight = 260
    o.client = nil
    o.server = nil
    o.token = nil
    return o
end

function Window:createChildren()
    ISCollapsableWindow.createChildren(self)

    local y = self:titleBarHeight() + PAD
    local h = FONT_HGT_SMALL + 6
    local x = PAD

    local function box(name)
        local entry = ISTextEntryBox:new("", x, y, 70, h)
        entry:initialise()
        entry:instantiate()
        entry:setOnlyNumbers(true)
        self:addChild(entry)
        self[name] = entry
        x = x + 70 + 4
    end
    box("xBox")
    box("yBox")
    box("zBox")

    local function button(titleKey, onClick)
        local text = getText(titleKey)
        local width = getTextManager():MeasureStringX(UIFont.Small, text) + 20
        local btn = ISButton:new(x + 4, y, width, h, text, self, onClick)
        btn:initialise()
        btn:instantiate()
        self:addChild(btn)
        x = x + width + 8
        return btn
    end
    button("IGUI_PhunServer2_Diag_Here", Window.onHere)
    button("IGUI_PhunServer2_Diag_Probe", Window.onProbe)
    button("IGUI_PhunServer2_Diag_Go", Window.onGo)
    -- ISButton passes itself after the target, and onHealth takes an optional
    -- server result, so the button must not be handed to it
    button("IGUI_PhunServer2_Diag_Health", function(window)
        window:onHealth()
    end)

    y = y + h + PAD
    -- Stops short of the bottom edge, where the resize handles are: a panel
    -- over them hides them and takes their clicks
    local text = ISRichTextPanel:new(PAD, y, self.width - PAD * 2, self.height - y - self:resizeWidgetHeight() - 2)
    text:initialise()
    text:instantiate()
    text.autosetheight = false
    text.clip = true
    text.background = false
    -- grows with the window; prerender re-wraps it when the width changes
    text:setAnchorRight(true)
    text:setAnchorBottom(true)
    text:addScrollBars()
    text.onMouseWheel = function(panel, del)
        panel:setYScroll(panel:getYScroll() - del * (FONT_HGT_SMALL + 2) * 3)
        return true
    end
    self:addChild(text)
    self.text = text
end

-- Fills the boxes with the square the local player stands on
function Window:fillHere()
    local player = getPlayer()
    local square = player and player:getCurrentSquare()
    if not square then
        return false
    end
    self.xBox:setText(tostring(square:getX()))
    self.yBox:setText(tostring(square:getY()))
    self.zBox:setText(tostring(square:getZ()))
    return true
end

-- A focused text box keeps the keyboard and mouse, which is how the window
-- came to swallow world clicks until it was closed. Every button lets go.
function Window:releaseFocus()
    for _, name in ipairs({"xBox", "yBox", "zBox"}) do
        if self[name] and self[name].unfocus then
            self[name]:unfocus()
        end
    end
end

-- Moves the local player to the boxes. In multiplayer that is vanilla's own
-- /teleportto, so the server does it and its anti-cheat knows; in single player
-- the same set-both-positions move vanilla's debug teleport makes.
function Window:onGo()
    self:releaseFocus()
    local x, y = tonumber(self.xBox:getText()), tonumber(self.yBox:getText())
    local z = tonumber(self.zBox:getText()) or 0
    local player = getPlayer()
    if not x or not y or not player then
        return
    end
    if isClient() then
        SendCommandToServer(string.format("/teleportto %d,%d,%d", x, y, z))
    else
        player:setX(x + 0.5)
        player:setY(y + 0.5)
        player:setZ(z)
        player:setLastX(x + 0.5)
        player:setLastY(y + 0.5)
        player:setLastZ(z)
    end
end

function Window:onHere()
    if self:fillHere() then
        self:onProbe()
    end
end

function Window:onProbe()
    self:releaseFocus()
    local x, y = tonumber(self.xBox:getText()), tonumber(self.yBox:getText())
    local z = tonumber(self.zBox:getText()) or 0
    if not x or not y then
        return
    end
    nextToken = nextToken + 1
    self.token = nextToken
    self.mode = "square"
    self.at = string.format("%d, %d, %d", x, y, z)
    self.client = Probe.read(x, y, z)
    self.server = nil
    self:refresh()
    Diag.request(Diag.commands.probe, {
        x = x,
        y = y,
        z = z,
        token = self.token
    })
end

function Window:receive(result)
    -- Numbers cross the wire as doubles, so compare as numbers. A reply to an
    -- earlier probe is dropped rather than drawn against the wrong square.
    if tonumber(result.token) ~= self.token then
        return
    end
    self.server = result
    self:refresh()
end

-- NOT render(): that is the per-frame draw every ISUIElement has, and
-- overriding it re-laid the whole table out every frame while skipping the
-- window's own drawing, resize corner included.
function Window:refresh()
    if self.mode == "health" then
        return self:refreshHealth()
    end
    local lines = {}
    local function add(s)
        table.insert(lines, s)
    end

    if not self.client then
        self.text:setText("")
        self.text:paginate()
        return
    end

    local differ = 0
    if self.server then
        for _, field in ipairs(Probe.FIELDS) do
            if self.client[field.key] ~= self.server[field.key] then
                differ = differ + 1
            end
        end
    end

    add(" <RGB:1,1,1> " .. clean(getText("IGUI_PhunServer2_Diag_At", self.at)))
    if Core.isLocal then
        add(" <RGB:0.7,0.7,0.7> " .. getText("IGUI_PhunServer2_Diag_SinglePlayer"))
    elseif not self.server then
        add(" <RGB:1,0.85,0.4> " .. getText("IGUI_PhunServer2_Diag_Waiting"))
    elseif differ == 0 then
        add(" <RGB:0.5,1,0.5> " .. getText("IGUI_PhunServer2_Diag_Agree"))
    else
        add(" <RGB:1,0.4,0.4> " .. getText("IGUI_PhunServer2_Diag_Differ", tostring(differ)))
    end
    -- One healthy square says nothing about the rest of the map, so say when
    -- the server's boot check found something elsewhere
    local healthProblems = self.server and tonumber(self.server.healthProblems) or 0
    if healthProblems > 0 then
        add(" <RGB:1,0.85,0.4> " .. getText("IGUI_PhunServer2_Diag_HealthHint", tostring(healthProblems)))
    end
    -- Rooms with no map buildings is the Map= priority bug's own signature,
    -- and both sides agree about it, so no red cell would show it. Said here.
    local function dropped(side)
        local rooms = side and tonumber(side.cellRooms)
        local buildings = side and tonumber(side.cellBuildingsMap)
        return rooms and buildings and rooms > 0 and buildings == 0
    end
    if dropped(self.client) or dropped(self.server) then
        add(" <RGB:1,0.4,0.4> " .. getText("IGUI_PhunServer2_Diag_Dropped", tostring(self.client.cellRooms)))
    end
    add(" ")

    add(" <RGB:0.7,0.7,0.7> " .. getText("IGUI_PhunServer2_Diag_Field") .. " <SETX:" .. COL_CLIENT .. "> " ..
            getText("IGUI_PhunServer2_Diag_Client") .. " <SETX:" .. COL_SERVER .. "> " ..
            getText("IGUI_PhunServer2_Diag_Server"))

    local waiting = getText("IGUI_PhunServer2_Diag_Pending")
    for _, field in ipairs(Probe.FIELDS) do
        if not field.long then
            local c = self.client[field.key] or "-"
            local s = self.server and (self.server[field.key] or "-") or waiting
            local colour = (self.server and c ~= s) and " <RGB:1,0.4,0.4> " or " <RGB:1,1,1> "
            add(colour .. clean(label(field.key)) .. " <SETX:" .. COL_CLIENT .. "> " .. cell(c) .. " <SETX:" ..
                    COL_SERVER .. "> " .. cell(s))
        end
    end

    for _, field in ipairs(Probe.FIELDS) do
        if field.long then
            local c = self.client[field.key] or "-"
            local s = self.server and (self.server[field.key] or "-") or waiting
            local colour = (self.server and c ~= s) and " <RGB:1,0.4,0.4> " or " <RGB:1,1,1> "
            add(" ")
            add(colour .. clean(label(field.key)))
            add(" <RGB:0.7,0.7,0.7> " .. getText("IGUI_PhunServer2_Diag_Client") .. ": " .. colour .. clean(c))
            add(" <RGB:0.7,0.7,0.7> " .. getText("IGUI_PhunServer2_Diag_Server") .. ": " .. colour .. clean(s))
        end
    end

    self.text:setText(table.concat(lines, " <LINE> "))
    self.text:paginate()
end

-- ---------------------------------------------------------------------------
-- Map health. Same idea as the probe: both sides run Health.run and the view
-- lines them up. A map missing on both sides has a broken objects.lua; one
-- missing only on the server is a stale zone list in the save.
-- ---------------------------------------------------------------------------

local COL_H_CLIENT = 300
local COL_H_SERVER = 440
local MAP_CHARS = 34

-- serverResult is the server's answer when it arrived unasked, as the login
-- alert does; the client then runs only its own half.
function Window:onHealth(serverResult)
    self:releaseFocus()
    nextToken = nextToken + 1
    self.token = nextToken
    self.mode = "health"
    self.prefilled = false
    local ok, result = pcall(Health.run)
    self.healthClient = ok and result or {
        maps = {},
        missingFolders = {},
        failed = tostring(result)
    }
    self.healthServer = serverResult
    self:refresh()
    if not serverResult then
        Diag.request(Diag.commands.health, {
            token = self.token
        })
    end
end

function Window:receiveHealth(result)
    if tonumber(result.token) ~= self.token then
        return
    end
    self.healthServer = result
    self:refresh()
end

local function statusColour(status)
    if status == "present" then
        return " <RGB:0.5,1,0.5> "
    elseif status == "missing" or status == "broken" or status == "not installed" or
        string.sub(status, 1, 5) == "error" then
        return " <RGB:1,0.4,0.4> "
    end
    return " <RGB:0.7,0.7,0.7> "
end

function Window:refreshHealth()
    local lines = {}
    local function add(s)
        table.insert(lines, s)
    end
    local client, server = self.healthClient, self.healthServer
    local waiting = getText("IGUI_PhunServer2_Diag_Pending")

    add(" <RGB:1,1,1> " .. getText("IGUI_PhunServer2_Diag_HealthTitle"))
    if client.failed then
        add(" <RGB:1,0.4,0.4> " .. clean(client.failed))
    end
    if Core.isLocal then
        add(" <RGB:0.7,0.7,0.7> " .. getText("IGUI_PhunServer2_Diag_SinglePlayer"))
    elseif not server then
        add(" <RGB:1,0.85,0.4> " .. getText("IGUI_PhunServer2_Diag_Waiting"))
    end

    -- The two columns settle what neither side can alone. A zone the client
    -- loaded and the server did not cannot be a broken objects.lua, which
    -- would break both; it is the server restoring its zones from the save,
    -- typically after a map was added to an existing world.
    local stale, serverMissing = {}, 0
    local clientByDir = {}
    for _, row in ipairs(client.maps) do
        clientByDir[row.dir] = row
    end
    if server and not Core.isLocal then
        for _, row in ipairs(server.maps or {}) do
            if row.status == "missing" or row.status == "broken" then
                serverMissing = serverMissing + 1
                local mine = clientByDir[row.dir]
                if mine and mine.status == "present" then
                    table.insert(stale, row)
                end
            end
        end
    end
    local allStale = #stale > 0 and #stale == serverMissing

    -- Problems first, in the same words the server log uses
    local problems = {}
    local serverLines, clientLines = {}, {}
    if server then
        if allStale then
            table.insert(serverLines,
                getText("IGUI_PhunServer2_Diag_StaleSave", tostring(#stale), clean(stale[1].dir)))
        end
        for _, line in ipairs(Health.problems(server)) do
            -- the zone verdict is replaced by the stale one above; the folder
            -- lines still stand
            if not (allStale and string.find(line, "^zones missing")) then
                table.insert(serverLines, line)
            end
        end
    end

    -- Point the probe at a square that shows the difference
    local first = stale[1]
    if first and first.sample ~= "" and not self.prefilled then
        local x, y, z = string.match(first.sample, "(%-?%d+),(%-?%d+),(%-?%d+)$")
        if x then
            self.xBox:setText(x)
            self.yBox:setText(y)
            self.zBox:setText(z)
            self.prefilled = true
        end
    end
    for _, line in ipairs(Health.problems(client)) do
        clientLines[line] = true
    end
    -- A finding both sides make is said once
    for _, line in ipairs(serverLines) do
        local who = clientLines[line] and "IGUI_PhunServer2_Diag_Both" or "IGUI_PhunServer2_Diag_Server"
        clientLines[line] = nil
        table.insert(problems, getText(who) .. ": " .. line)
    end
    for _, line in ipairs(Health.problems(client)) do
        if clientLines[line] and (server or not Core.isLocal) then
            table.insert(problems, getText("IGUI_PhunServer2_Diag_Client") .. ": " .. line)
        end
    end
    add(" ")
    if server and #problems == 0 then
        add(" <RGB:0.5,1,0.5> " .. getText("IGUI_PhunServer2_Diag_Healthy"))
    end
    for _, line in ipairs(problems) do
        add(" <RGB:1,0.4,0.4> " .. clean(line))
    end

    -- Map= folders, which only the server can read
    add(" ")
    if server and server.configured then
        if #server.missingFolders == 0 then
            add(" <RGB:0.5,1,0.5> " .. getText("IGUI_PhunServer2_Diag_FoldersOk", tostring(#server.configured)))
        end
    elseif server then
        add(" <RGB:0.7,0.7,0.7> " .. getText("IGUI_PhunServer2_Diag_NoMapOption"))
    end

    -- One row per map, in Map= order
    add(" ")
    add(" <RGB:0.7,0.7,0.7> " .. getText("IGUI_PhunServer2_Diag_Map") .. " <SETX:" .. COL_H_CLIENT .. "> " ..
            getText("IGUI_PhunServer2_Diag_Client") .. " <SETX:" .. COL_H_SERVER .. "> " ..
            getText("IGUI_PhunServer2_Diag_Server"))
    local serverByDir = {}
    if server then
        for _, row in ipairs(server.maps or {}) do
            serverByDir[row.dir] = row
        end
    end
    for i, row in ipairs(client.maps) do
        local s = server and (serverByDir[row.dir] and serverByDir[row.dir].status or "-") or waiting
        local name = clean(row.dir)
        if #name > MAP_CHARS then
            name = string.sub(name, 1, MAP_CHARS - 3) .. "..."
        end
        add(" <RGB:1,1,1> " .. i .. ". " .. name .. " <SETX:" .. COL_H_CLIENT .. "> " .. statusColour(row.status) ..
                clean(row.status) .. " <SETX:" .. COL_H_SERVER .. "> " .. statusColour(s) .. clean(s))
        if row.status == "missing" or s == "missing" or row.status == "broken" or s == "broken" then
            add(" <RGB:0.6,0.6,0.6> " .. getText("IGUI_PhunServer2_Diag_Sample", clean(row.sample)))
        end
    end

    self.text:setText(table.concat(lines, " <LINE> "))
    self.text:paginate()
end

function Window:prerender()
    ISCollapsableWindow.prerender(self)
    -- Rich text wraps at the width it was paginated for, so re-lay it out
    -- after a resize
    if self.text and self.renderedWidth ~= self.text:getWidth() then
        self.renderedWidth = self.text:getWidth()
        self:refresh()
    end
end

function Window:close()
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    if Diag.probeWindow == self then
        Diag.probeWindow = nil
    end
end

-- Opens the window, or brings the open one forward, without probing anything.
function Diag.openWindow()
    local window = Diag.probeWindow
    if not window then
        local width, height = 640, 560
        window = Window:new((getCore():getScreenWidth() - width) / 2,
            (getCore():getScreenHeight() - height) / 2, width, height)
        window:initialise()
        window:addToUIManager()
        Diag.probeWindow = window
    else
        window:setVisible(true)
        window:bringToTop()
    end
    return window
end

-- Opens the window and probes: at the coordinates given, otherwise where the
-- player stands.
function Diag.openProbe(x, y, z)
    local window = Diag.openWindow()
    if x and y then
        window.xBox:setText(tostring(x))
        window.yBox:setText(tostring(y))
        window.zBox:setText(tostring(z or 0))
        window:onProbe()
    elseif window:fillHere() then
        window:onProbe()
    end
    return window
end

Diag.clientHandlers[Diag.commands.probeResult] = function(args)
    if Diag.probeWindow then
        Diag.probeWindow:receive(args)
    end
end

Diag.clientHandlers[Diag.commands.healthResult] = function(args)
    if Diag.probeWindow then
        Diag.probeWindow:receiveHealth(args)
    end
end

-- Sent once per boot to an admin joining a server whose boot check found a
-- problem. It can arrive while the client is still loading in, so the window
-- waits for a player before opening.
local pendingAlert = nil

local function showPendingAlert()
    if not pendingAlert or not getPlayer() then
        return
    end
    Events.OnTick.Remove(showPendingAlert)
    local result = pendingAlert
    pendingAlert = nil
    local window = Diag.openWindow()
    window:fillHere()
    window:onHealth(result)
end

Diag.clientHandlers[Diag.commands.healthAlert] = function(args)
    if not pendingAlert then
        Events.OnTick.Add(showPendingAlert)
    end
    pendingAlert = args
end

Events.OnServerCommand.Add(function(module, command, arguments)
    if module == Diag.name and Diag.clientHandlers[command] then
        Diag.clientHandlers[command](arguments or {})
    end
end)

-- /diag            probe where you stand
-- /diag x y [z]    probe a square anywhere; the server answers zones,
--                  buildings and cell counts even where nobody has loaded it
-- /diag health     the map list and every map's zones, client and server
Core.registerCommand("diag", {
    admin = true,
    handler = function(args)
        local first = args and args[1]
        if first and string.lower(first) == "health" then
            local window = Diag.openWindow()
            window:fillHere()
            window:onHealth()
            return true
        end
        local x, y, z = tonumber(first), tonumber(args and args[2]), tonumber(args and args[3])
        if first and (not x or not y) then
            return getText("IGUI_PhunServer2_Diag_Usage")
        end
        Diag.openProbe(x, y, z)
        return true
    end
})
