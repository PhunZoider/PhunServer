if isServer() then
    return
end

local Core = PhunServer
local tools = require("PhunServer/ui/tools")
-- ---------------------------------------------------------------------------
-- ISPhunSchedulePanel
-- Admin-only panel for viewing and editing server schedules.
-- Opened via /schedule chat command or the PhunServer admin button.
-- Left pane: schedule list.  Right pane: editor for the selected schedule.
-- ---------------------------------------------------------------------------
local profileName = "PhunServerUISchedules"
ISPhunSchedulePanel = ISCollapsableWindowJoypad:derive(profileName)
local UI = ISPhunSchedulePanel

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
local FONT_SCALE = FONT_HGT_SMALL / 14

local W, H = math.floor(620 * FONT_SCALE), math.floor(740 * FONT_SCALE)
local PAD = math.floor(10 * FONT_SCALE)
local LIST_W = math.floor(190 * FONT_SCALE)
local EDIT_X = LIST_W + PAD * 2
local EDIT_W = W - EDIT_X - PAD
local ROW_H = FONT_HGT_SMALL + 4
local BTN_H = FONT_HGT_SMALL + 6
local BTN_W = math.floor(90 * FONT_SCALE)

-- day labels; index matches os.date wday (1=Sun…7=Sat)
local DAY_LABELS = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"}

local TYPE_OPTIONS = {"restart", "event", "announcement"}
local TRIGGER_OPTIONS = {"cron", "workshop"}

-- ---------------------------------------------------------------------------
-- Colour palette (B42-ish dark theme)
-- ---------------------------------------------------------------------------
local C = {
    bg = {
        r = 0.08,
        g = 0.08,
        b = 0.10,
        a = 0.97
    },
    panel = {
        r = 0.11,
        g = 0.11,
        b = 0.14,
        a = 1.0
    },
    border = {
        r = 0.25,
        g = 0.25,
        b = 0.30,
        a = 1.0
    },
    accent = {
        r = 0.90,
        g = 0.55,
        b = 0.10,
        a = 1.0
    },
    accentDim = {
        r = 0.55,
        g = 0.33,
        b = 0.06,
        a = 1.0
    },
    danger = {
        r = 0.80,
        g = 0.15,
        b = 0.15,
        a = 1.0
    },
    text = {
        r = 0.90,
        g = 0.90,
        b = 0.90,
        a = 1.0
    },
    textDim = {
        r = 0.50,
        g = 0.50,
        b = 0.55,
        a = 1.0
    },
    textInherit = {
        r = 0.45,
        g = 0.55,
        b = 0.65,
        a = 1.0
    }
}

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

-- ---------------------------------------------------------------------------
-- Open (called from chat command or admin panel)
-- ---------------------------------------------------------------------------
function Core.openSchedulePanel()
    if Core.ui.schedulePanel and Core.ui.schedulePanel:isVisible() then
        return
    end
    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local panel = ISPhunSchedulePanel:new(math.floor((sw - W) / 2), math.floor((sh - H) / 2), getPlayer())
    panel:initialise()
    panel:addToUIManager()
    Core.ui.schedulePanel = panel
    sendClientCommand(Core.name, Core.commands.getSchedules, {})
end

-- ---------------------------------------------------------------------------
-- Constructor
-- ---------------------------------------------------------------------------
function UI:new(x, y, player)
    local o = ISCollapsableWindowJoypad.new(self, x, y, W, H, player)
    o.viewer = player
    o.player = player
    o.playerIndex = player:getPlayerNum()
    o.schedules = {}
    o.selected = nil
    o.warnEditIdx = nil
    o.statusMsg = nil
    o.statusTimer = 0
    o.backgroundColor = {
        r = C.bg.r,
        g = C.bg.g,
        b = C.bg.b,
        a = 1.0
    }
    o:setTitle("PhunServer - Schedules")
    return o
end

function UI:createChildren()

    ISCollapsableWindowJoypad.createChildren(self)

    local listTop = ROW_H + PAD * 2

    -- ---- LEFT PANE: schedule list ----------------------------------------

    local listH = H - listTop - BTN_H - PAD * 3
    local listBtnY = listTop + listH + PAD

    self.listBox = ISScrollingListBox:new(PAD, listTop, LIST_W, listH)
    self.listBox.font = UIFont.Small
    self.listBox.itemheight = ROW_H
    self.listBox.onmousedown = self.onListSelect
    self.listBox.target = self
    self.listBox:initialise()
    self:addChild(self.listBox)

    self.addBtn = ISButton:new(PAD, listBtnY, math.floor(60 * FONT_SCALE), BTN_H, "+ Add", self, self.onAddSchedule)
    self.addBtn:initialise()
    self.addBtn:setTooltip("Add a new schedule")
    self:addChild(self.addBtn)

    self.delBtn = ISButton:new(PAD + math.floor(66 * FONT_SCALE), listBtnY, math.floor(70 * FONT_SCALE), BTN_H,
        "- Delete", self, self.onDeleteSchedule)
    self.delBtn:initialise()
    self.delBtn:setTooltip("Delete the selected schedule")
    self:addChild(self.delBtn)

    -- ---- RIGHT PANE: editor ----------------------------------------------

    local ex = EDIT_X
    local ey = listTop
    local eow = EDIT_W

    -- Enabled tick
    self.enabledTick = ISTickBox:new(ex, ey, eow, ROW_H, "", nil)
    self.enabledTick:initialise()
    self.enabledTick:addOption("Enabled")
    self.enabledTick.tooltip = "Enable or disable this schedule"
    self:addChild(self.enabledTick)
    ey = ey + ROW_H + PAD

    -- Name
    self.nameLabel = ISLabel:new(ex, ey, ROW_H, "Name", 1, 1, 1, 1, UIFont.Small, true)
    self.nameLabel:initialise()
    self:addChild(self.nameLabel)
    ey = ey + ROW_H
    self.nameEntry = ISTextEntryBox:new("", ex, ey, eow, ROW_H)
    self.nameEntry:initialise()
    self.nameEntry:setTooltip("Unique name for this schedule")
    self:addChild(self.nameEntry)
    ey = ey + ROW_H + PAD

    -- Trigger (Scheduled / Workshop update)
    self.triggerLabel = ISLabel:new(ex, ey, ROW_H, "Trigger", 1, 1, 1, 1, UIFont.Small, true)
    self.triggerLabel:initialise()
    self:addChild(self.triggerLabel)
    ey = ey + ROW_H
    self.triggerCombo = ISComboBox:new(ex, ey, eow, ROW_H, self, self.onTriggerChanged)
    self.triggerCombo:initialise()
    self.triggerCombo:addOption("Scheduled")
    self.triggerCombo:addOption("Workshop update")
    self.triggerCombo.tooltip = "Scheduled: fires at set times.\nWorkshop update: fires when a mod update is detected"
    self:addChild(self.triggerCombo)
    ey = ey + ROW_H + PAD

    -- Repeat (cron only)
    self.repeatLabel = ISLabel:new(ex, ey, ROW_H, "Repeat", 1, 1, 1, 1, UIFont.Small, true)
    self.repeatLabel:initialise()
    self:addChild(self.repeatLabel)
    ey = ey + ROW_H
    self.recurCombo = ISComboBox:new(ex, ey, eow, ROW_H, self, self.onRecurChanged)
    self.recurCombo:initialise()
    self.recurCombo:addOption("daily")
    self.recurCombo:addOption("weekly")
    self.recurCombo.tooltip = "daily: fires every day.\nweekly: fires on selected days of the week"
    self:addChild(self.recurCombo)
    ey = ey + ROW_H + PAD

    -- Day selector (weekly + cron only)
    self.daysLabel = ISLabel:new(ex, ey, ROW_H, "Days", 1, 1, 1, 1, UIFont.Small, true)
    self.daysLabel:initialise()
    self:addChild(self.daysLabel)
    ey = ey + ROW_H
    self.dayTicks = {}
    local dayBtnW = math.floor((eow - 6) / 7)
    for i, lbl in ipairs(DAY_LABELS) do
        local btn = ISButton:new(ex + (i - 1) * (dayBtnW + 1), ey, dayBtnW, BTN_H, lbl, self, function(target)
            target:onDayToggle(i)
        end)
        btn:initialise()
        btn.selected = false
        self:addChild(btn)
        self.dayTicks[i] = btn
    end
    ey = ey + BTN_H + PAD

    -- Times list (cron only)
    self.timesLabel = ISLabel:new(ex, ey, ROW_H, "Times (HH:MM)", 1, 1, 1, 1, UIFont.Small, true)
    self.timesLabel:initialise()
    self:addChild(self.timesLabel)
    ey = ey + ROW_H
    local timesListH = 3 * ROW_H + 4
    self.timesList = ISScrollingListBox:new(ex, ey, eow, timesListH)
    self.timesList.font = UIFont.Small
    self.timesList.itemheight = ROW_H
    self.timesList:initialise()
    self:addChild(self.timesList)
    ey = ey + timesListH + PAD

    -- Time input row (cron only)
    self.timeEntry = ISTextEntryBox:new("", ex, ey, math.floor(80 * FONT_SCALE), ROW_H)
    self.timeEntry:initialise()
    self.timeEntry:setTooltip("Enter time in HH:MM 24-hour format")
    self:addChild(self.timeEntry)

    self.addTimeBtn = ISButton:new(ex + math.floor(86 * FONT_SCALE), ey, math.floor(60 * FONT_SCALE), BTN_H, "Add",
        self, self.onAddTime)
    self.addTimeBtn:initialise()
    self.addTimeBtn:setTooltip("Add this time to the schedule")
    self:addChild(self.addTimeBtn)

    self.removeTimeBtn = ISButton:new(ex + math.floor(152 * FONT_SCALE), ey, math.floor(70 * FONT_SCALE), BTN_H,
        "Remove", self, self.onRemoveTime)
    self.removeTimeBtn:initialise()
    self.removeTimeBtn:setTooltip("Remove the selected time entry")
    self:addChild(self.removeTimeBtn)
    ey = ey + BTN_H + PAD

    -- Outcome / Type
    self.typeLabel = ISLabel:new(ex, ey, ROW_H, "Outcome", 1, 1, 1, 1, UIFont.Small, true)
    self.typeLabel:initialise()
    self:addChild(self.typeLabel)
    ey = ey + ROW_H
    self.typeCombo = ISComboBox:new(ex, ey, eow, ROW_H, self, self.onTypeChanged)
    self.typeCombo:initialise()
    self.typeCombo:addOption("restart")
    self.typeCombo:addOption("event")
    self.typeCombo:addOption("announcement")
    self.typeCombo.tooltip = "restart: schedules a server restart with countdown.\n" ..
                                 "event: triggers a named Lua event.\n" ..
                                 "announcement: broadcasts messages to all players"
    self:addChild(self.typeCombo)
    ey = ey + ROW_H + PAD

    -- Extra field: adapts label/tooltip based on outcome type.
    -- type=event       → "Event name"    (stores sch.eventName)
    -- type=announcement → "Message"      (stores sch.announcementText)
    -- type=restart      → hidden
    self.extraFieldLabel = ISLabel:new(ex, ey, ROW_H, "Event name", 1, 1, 1, 1, UIFont.Small, true)
    self.extraFieldLabel:initialise()
    self:addChild(self.extraFieldLabel)
    ey = ey + ROW_H
    self.extraFieldEntry = ISTextEntryBox:new("", ex, ey, eow, ROW_H)
    self.extraFieldEntry:initialise()
    self:addChild(self.extraFieldEntry)
    ey = ey + ROW_H + PAD

    -- Warnings / countdown messages
    -- restart/event: each entry fires N secs BEFORE the action.
    -- announcement:  each entry fires N secs AFTER the schedule fires (0 = immediate).
    self.warnLabel = ISLabel:new(ex, ey, ROW_H, "Warnings", 1, 1, 1, 1, UIFont.Small, true)
    self.warnLabel:initialise()
    self:addChild(self.warnLabel)
    ey = ey + ROW_H
    local warnListH = 6 * ROW_H + 4
    self.warnList = ISScrollingListBox:new(ex, ey, eow, warnListH)
    self.warnList.font = UIFont.Small
    self.warnList.itemheight = ROW_H
    self.warnList.onmousedown = self.onWarnSelect
    self.warnList.target = self
    self.warnList:initialise()
    self:addChild(self.warnList)
    ey = ey + warnListH + PAD

    -- Warning input hint labels
    local wSecsW = math.floor(50 * FONT_SCALE)
    local wBtnW = math.floor(50 * FONT_SCALE)
    local wTxtW = eow - wSecsW - wBtnW * 2 - PAD * 3

    self.warnSecsHint = ISLabel:new(ex, ey, ROW_H, "Secs", C.textDim.r, C.textDim.g, C.textDim.b, C.textDim.a,
        UIFont.Small, true)
    self.warnSecsHint:initialise()
    self:addChild(self.warnSecsHint)

    self.warnMsgHint = ISLabel:new(ex + wSecsW + PAD, ey, ROW_H, "Message or translation key", C.textDim.r, C.textDim.g,
        C.textDim.b, C.textDim.a, UIFont.Small, true)
    self.warnMsgHint:initialise()
    self:addChild(self.warnMsgHint)
    ey = ey + ROW_H

    -- Warning input row: [secs] [text] [Add/Update] [Del]
    self.warnSecsEntry = ISTextEntryBox:new("", ex, ey, wSecsW, ROW_H)
    self.warnSecsEntry:initialise()
    self.warnSecsEntry:setTooltip(
        "Seconds before action (restart/event) or delay after firing (announcement).\n0 = immediate")
    self:addChild(self.warnSecsEntry)

    self.warnTextEntry = ISTextEntryBox:new("", ex + wSecsW + PAD, ey, wTxtW, ROW_H)
    self.warnTextEntry:initialise()
    self.warnTextEntry:setTooltip("Message text or translation key (e.g. IGUI_PhunServer_Left)")
    self:addChild(self.warnTextEntry)

    local wAddX = ex + wSecsW + PAD + wTxtW + PAD
    self.addWarnBtn = ISButton:new(wAddX, ey, wBtnW, BTN_H, "Add", self, self.onAddWarning)
    self.addWarnBtn:initialise()
    self.addWarnBtn:setTooltip("Add a new warning or save edits to the selected entry")
    self:addChild(self.addWarnBtn)

    self.removeWarnBtn = ISButton:new(wAddX + wBtnW + PAD, ey, wBtnW, BTN_H, "Del", self, self.onRemoveWarning)
    self.removeWarnBtn:initialise()
    self.removeWarnBtn:setTooltip("Remove the selected warning entry")
    self:addChild(self.removeWarnBtn)

    -- ---- FOOTER: status label + save button (aligned with list ± buttons) ----
    self.statusLabel = ISLabel:new(ex, listBtnY, ROW_H, "", 1, 1, 1, 1, UIFont.Small)
    self.statusLabel:initialise()
    self:addChild(self.statusLabel)

    self.saveBtn = ISButton:new(ex + EDIT_W - BTN_W, listBtnY, BTN_W, BTN_H, "Save", self, self.onSave)
    self.saveBtn:initialise()
    self.saveBtn:setTooltip("Save this schedule and send to server")
    self:addChild(self.saveBtn)

    self:setEditVisible(false)
    self:refreshDayButtons()
end

-- ---------------------------------------------------------------------------
-- Show / hide the edit pane
-- ---------------------------------------------------------------------------
function UI:setEditVisible(visible)
    local items = {self.enabledTick, self.nameLabel, self.nameEntry, self.triggerLabel, self.triggerCombo,
                   self.repeatLabel, self.recurCombo, self.daysLabel, self.timesLabel, self.timesList, self.timeEntry,
                   self.addTimeBtn, self.removeTimeBtn, self.typeLabel, self.typeCombo, self.extraFieldLabel,
                   self.extraFieldEntry, self.warnLabel, self.warnList, self.warnSecsHint, self.warnMsgHint,
                   self.warnSecsEntry, self.warnTextEntry, self.addWarnBtn, self.removeWarnBtn, self.saveBtn,
                   self.statusLabel}
    for _, w in ipairs(items) do
        if w then
            w:setVisible(visible)
        end
    end
    for _, btn in ipairs(self.dayTicks or {}) do
        btn:setVisible(visible)
    end
end

-- ---------------------------------------------------------------------------
-- List population
-- ---------------------------------------------------------------------------
function UI:refreshList()
    self.listBox:clear()
    for i, sch in ipairs(self.schedules) do
        local prefix = sch.enabled and "[ON] " or "[OFF] "
        local suffix = (sch.trigger == "workshop") and " [W]" or ""
        self.listBox:addItem(prefix .. (sch.name or "Unnamed") .. suffix, i)
    end
    if self.selected and self.selected > #self.schedules then
        self.selected = #self.schedules > 0 and #self.schedules or nil
    end
    if self.selected then
        self.listBox.selected = self.selected
    end
end

-- ---------------------------------------------------------------------------
-- Load a schedule into the form
-- ---------------------------------------------------------------------------
function UI:loadScheduleIntoForm(idx)
    local sch = self.schedules[idx]
    if not sch then
        return
    end
    self.selected = idx

    -- Reset warning edit state whenever a different schedule is loaded
    self.warnEditIdx = nil
    self.addWarnBtn:setTitle("Add")
    self.warnSecsEntry:setText("")
    self.warnTextEntry:setText("")

    self.enabledTick:setSelected(1, sch.enabled == true)
    self.nameEntry:setText(sch.name or "")

    -- trigger
    self.triggerCombo.selected = (sch.trigger == "workshop") and 2 or 1

    -- recur
    self.recurCombo.selected = (sch.recur == "weekly") and 2 or 1

    -- days
    local daySet = {}
    for _, d in ipairs(sch.days or {}) do
        daySet[d] = true
    end
    for i, btn in ipairs(self.dayTicks) do
        btn.selected = daySet[i] == true
    end

    -- times
    self.timesList:clear()
    for _, t in ipairs(sch.times or {}) do
        self.timesList:addItem(t, t)
    end

    -- type/outcome
    local typeMap = {
        restart = 1,
        event = 2,
        announcement = 3
    }
    self.typeCombo.selected = typeMap[sch.type] or 1

    -- extra field (event name or announcement message)
    if sch.type == "event" then
        self.extraFieldEntry:setText(sch.eventName or "")
    elseif sch.type == "announcement" then
        self.extraFieldEntry:setText(sch.announcementText or "")
    else
        self.extraFieldEntry:setText("")
    end

    -- warnings / countdowns
    self.warnList:clear()
    for _, c in ipairs(sch.countdowns or {}) do
        local secs = tonumber(c.secs) or 0
        local text = c.text or ""
        self.warnList:addItem(string.format("%ds — %s", secs, text), {
            secs = secs,
            text = text
        })
    end

    self:setEditVisible(true)
    self:refreshTriggerVisibility()
    self:refreshTypeVisibility()
    self:refreshDayButtons()
end

-- ---------------------------------------------------------------------------
-- Visibility helpers
-- ---------------------------------------------------------------------------
function UI:refreshTriggerVisibility()
    local isCron = self.triggerCombo.selected ~= 2
    self.repeatLabel:setVisible(isCron)
    self.recurCombo:setVisible(isCron)
    self.timesLabel:setVisible(isCron)
    self.timesList:setVisible(isCron)
    self.timeEntry:setVisible(isCron)
    self.addTimeBtn:setVisible(isCron)
    self.removeTimeBtn:setVisible(isCron)
    if isCron then
        self:refreshDayButtons()
    else
        self.daysLabel:setVisible(false)
        for _, btn in ipairs(self.dayTicks or {}) do
            btn:setVisible(false)
        end
    end
end

function UI:refreshTypeVisibility()
    local t = self.typeCombo.selected
    local isEvent = t == 2
    local isAnnounce = t == 3
    local showExtra = isEvent or isAnnounce
    self.extraFieldLabel:setVisible(showExtra)
    self.extraFieldEntry:setVisible(showExtra)
    if isEvent then
        self.extraFieldLabel:setName("Event name")
        self.extraFieldEntry:setTooltip("Name of the Lua event to trigger (e.g. OnPhunServerRestart)")
    elseif isAnnounce then
        self.extraFieldLabel:setName("Message")
        self.extraFieldEntry:setTooltip("Text or translation key to broadcast when this schedule fires")
    end
end

function UI:refreshDayButtons()
    local isCron = self.recurCombo and self.triggerCombo.selected ~= 2
    local isWeekly = isCron and self.recurCombo and self.recurCombo.selected == 2
    self.daysLabel:setVisible(isWeekly == true)
    for _, btn in ipairs(self.dayTicks or {}) do
        btn:setVisible(isWeekly == true)
        btn.backgroundColor = btn.selected and {
            r = 0.3,
            g = 0.7,
            b = 0.3,
            a = 0.9
        } or {
            r = 0.2,
            g = 0.2,
            b = 0.2,
            a = 0.9
        }
    end
end

-- ---------------------------------------------------------------------------
-- Callbacks — list
-- ---------------------------------------------------------------------------
function UI:onListSelect(item, _)
    if item and item.item then
        self:loadScheduleIntoForm(item.item)
    end
end

-- ---------------------------------------------------------------------------
-- Callbacks — trigger / type / recur
-- ---------------------------------------------------------------------------
function UI:onTriggerChanged()
    self:refreshTriggerVisibility()
end

function UI:onTypeChanged()
    self:refreshTypeVisibility()
end

function UI:onRecurChanged()
    self:refreshDayButtons()
end

function UI:onDayToggle(wdayIdx)
    local btn = self.dayTicks[wdayIdx]
    if btn then
        btn.selected = not btn.selected
        self:refreshDayButtons()
    end
end

-- ---------------------------------------------------------------------------
-- Callbacks — schedule list management
-- ---------------------------------------------------------------------------
function UI:onAddSchedule()
    table.insert(self.schedules, {
        name = "New Schedule",
        enabled = false,
        trigger = "cron",
        type = "restart",
        recur = "daily",
        times = {}
    })
    self:refreshList()
    self:loadScheduleIntoForm(#self.schedules)
end

function UI:onDeleteSchedule()
    if not self.selected then
        return
    end
    table.remove(self.schedules, self.selected)
    self.selected = clamp(self.selected, 1, #self.schedules)
    if #self.schedules == 0 then
        self.selected = nil
        self:setEditVisible(false)
    end
    self:refreshList()
    if self.selected then
        self:loadScheduleIntoForm(self.selected)
    end
end

-- ---------------------------------------------------------------------------
-- Callbacks — times
-- ---------------------------------------------------------------------------
function UI:onAddTime()
    local t = self.timeEntry:getText():match("^%s*(%d%d?:%d%d)%s*$")
    if not t then
        self:setStatus("Invalid time — use HH:MM", true)
        return
    end
    local h, m = t:match("^(%d+):(%d+)$")
    h, m = tonumber(h), tonumber(m)
    if h > 23 or m > 59 then
        self:setStatus("Invalid time — hours 0-23, minutes 0-59", true)
        return
    end
    local normalised = string.format("%02d:%02d", h, m)
    for _, item in ipairs(self.timesList.items) do
        if item.text == normalised then
            self:setStatus("Time already in list", true)
            return
        end
    end
    self.timesList:addItem(normalised, normalised)
    self.timeEntry:setText("")
end

function UI:onRemoveTime()
    local sel = self.timesList.selected
    if sel and sel > 0 then
        self.timesList:removeItemByIndex(sel)
    end
end

-- ---------------------------------------------------------------------------
-- Callbacks — warnings
-- ---------------------------------------------------------------------------

-- Clicking a warning in the list populates the input fields for editing.
function UI:onWarnSelect(item, _)
    if item and item.item then
        local d = item.item
        self.warnEditIdx = self.warnList.selected
        self.warnSecsEntry:setText(tostring(d.secs))
        self.warnTextEntry:setText(d.text)
        self.addWarnBtn:setTitle("Update")
    end
end

function UI:onAddWarning()
    local secsStr = self.warnSecsEntry:getText():match("^%s*(%d+)%s*$")
    if not secsStr then
        self:setStatus("Seconds must be a whole number (0 or greater)", true)
        return
    end
    local secs = tonumber(secsStr)
    local text = self.warnTextEntry:getText():match("^%s*(.-)%s*$")
    if not text or text == "" then
        self:setStatus("Warning text cannot be empty", true)
        return
    end
    local display = string.format("%ds — %s", secs, text)
    local data = {
        secs = secs,
        text = text
    }

    if self.warnEditIdx and self.warnEditIdx <= #self.warnList.items then
        -- Update the entry in place
        self.warnList.items[self.warnEditIdx] = {
            text = display,
            item = data,
            height = ROW_H
        }
        self.warnEditIdx = nil
        self.addWarnBtn:setTitle("Add")
    else
        self.warnList:addItem(display, data)
    end
    self.warnSecsEntry:setText("")
    self.warnTextEntry:setText("")
end

function UI:onRemoveWarning()
    local sel = self.warnList.selected
    if sel and sel > 0 then
        self.warnList:removeItemByIndex(sel)
        -- Clear edit state if we just removed the entry being edited
        if self.warnEditIdx then
            self.warnEditIdx = nil
            self.warnSecsEntry:setText("")
            self.warnTextEntry:setText("")
            self.addWarnBtn:setTitle("Add")
        end
    end
end

-- ---------------------------------------------------------------------------
-- Save
-- ---------------------------------------------------------------------------
function UI:onSave()
    if not self.selected then
        return
    end

    local sch = self.schedules[self.selected]
    if not sch then
        return
    end

    local name = self.nameEntry:getText():match("^%s*(.-)%s*$")
    if not name or name == "" then
        self:setStatus("Name cannot be empty", true)
        return
    end
    for i, s in ipairs(self.schedules) do
        if i ~= self.selected and s.name == name then
            self:setStatus("Name already in use", true)
            return
        end
    end

    sch.name = name
    sch.enabled = self.enabledTick:isSelected(1)
    sch.trigger = self.triggerCombo.selected == 2 and "workshop" or "cron"
    sch.type = TYPE_OPTIONS[self.typeCombo.selected] or "restart"

    if sch.trigger == "cron" then
        sch.recur = self.recurCombo.selected == 2 and "weekly" or "daily"

        if sch.recur == "weekly" then
            sch.days = {}
            for i, btn in ipairs(self.dayTicks) do
                if btn.selected then
                    table.insert(sch.days, i)
                end
            end
            if #sch.days == 0 then
                self:setStatus("Select at least one day for weekly schedule", true)
                return
            end
        else
            sch.days = nil
        end

        sch.times = {}
        for _, item in ipairs(self.timesList.items) do
            table.insert(sch.times, item.text)
        end
        table.sort(sch.times)
        if #sch.times == 0 then
            self:setStatus("Add at least one time", true)
            return
        end
    else
        sch.recur = nil
        sch.days = nil
        sch.times = nil
    end

    -- Extra field: event name or announcement message
    if sch.type == "event" then
        local en = self.extraFieldEntry:getText():match("^%s*(.-)%s*$")
        sch.eventName = (en ~= "") and en or nil
        sch.announcementText = nil
    elseif sch.type == "announcement" then
        local at = self.extraFieldEntry:getText():match("^%s*(.-)%s*$")
        sch.announcementText = (at ~= "") and at or nil
        sch.eventName = nil
    else
        sch.eventName = nil
        sch.announcementText = nil
    end

    -- Warnings / countdowns
    sch.countdowns = {}
    for _, listItem in ipairs(self.warnList.items) do
        local d = listItem.item
        if d then
            table.insert(sch.countdowns, {
                secs = d.secs,
                text = d.text
            })
        end
    end
    if #sch.countdowns == 0 then
        sch.countdowns = nil
    end

    self:refreshList()

    sendClientCommand(Core.name, Core.commands.saveSchedules, {
        schedules = self.schedules
    })
    self:setStatus("Saving...", false)
end

-- ---------------------------------------------------------------------------
-- Server response
-- ---------------------------------------------------------------------------
function UI:onDataReceived(schedules, saved)
    self.schedules = schedules or {}
    self:refreshList()
    if saved then
        self:setStatus("Saved.", false)
    end
    if self.selected and self.schedules[self.selected] then
        self:loadScheduleIntoForm(self.selected)
    elseif #self.schedules > 0 then
        self:loadScheduleIntoForm(1)
    else
        self.selected = nil
        self:setEditVisible(false)
    end
end

-- ---------------------------------------------------------------------------
-- Status message (auto-clears after 4 seconds)
-- ---------------------------------------------------------------------------
function UI:setStatus(msg, isError)
    self.statusMsg = msg
    self.statusTimer = getTimestampMs() + 4000
    if isError then
        self.statusLabel:setColor(1, 0.3, 0.3, 1)
    else
        self.statusLabel:setColor(0.3, 1, 0.3, 1)
    end
    self.statusLabel:setName(msg)
end

function UI:update()
    ISCollapsableWindowJoypad.update(self)
    if self.statusMsg and getTimestampMs() > self.statusTimer then
        self.statusMsg = nil
        self.statusLabel:setName("")
    end
end

-- ---------------------------------------------------------------------------
-- Close
-- ---------------------------------------------------------------------------
function UI:close()
    self:setVisible(false)
    self:removeFromUIManager()
    Core.ui.schedulePanel = nil
end
