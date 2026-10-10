if isServer() then
    return
end

local Core = require "PhunServer2/core"
local Diag = require "PhunServer2/diag"
local Probe = require "PhunServer2/diag_probe"

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
    o.resizable = false
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

    y = y + h + PAD
    local text = ISRichTextPanel:new(PAD, y, self.width - PAD * 2, self.height - y - PAD)
    text:initialise()
    text:instantiate()
    text.autosetheight = false
    text.clip = true
    text.background = false
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

function Window:onHere()
    if self:fillHere() then
        self:onProbe()
    end
end

function Window:onProbe()
    local x, y = tonumber(self.xBox:getText()), tonumber(self.yBox:getText())
    local z = tonumber(self.zBox:getText()) or 0
    if not x or not y then
        return
    end
    nextToken = nextToken + 1
    self.token = nextToken
    self.at = string.format("%d, %d, %d", x, y, z)
    self.client = Probe.read(x, y, z)
    self.server = nil
    self:render()
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
    self:render()
end

function Window:render()
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

function Window:close()
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    if Diag.probeWindow == self then
        Diag.probeWindow = nil
    end
end

-- Opens the window, or brings the open one forward. With coordinates it probes
-- there, otherwise where the player stands.
function Diag.openProbe(x, y, z)
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

Events.OnServerCommand.Add(function(module, command, arguments)
    if module == Diag.name and Diag.clientHandlers[command] then
        Diag.clientHandlers[command](arguments or {})
    end
end)

-- /diag            probe where you stand
-- /diag x y [z]    probe a square anywhere; the server answers zones,
--                  buildings and cell counts even where nobody has loaded it
Core.registerCommand("diag", {
    admin = true,
    handler = function(args)
        local x, y, z = tonumber(args and args[1]), tonumber(args and args[2]), tonumber(args and args[3])
        if args and args[1] and (not x or not y) then
            return getText("IGUI_PhunServer2Diag_Usage")
        end
        Diag.openProbe(x, y, z)
        return true
    end
})
