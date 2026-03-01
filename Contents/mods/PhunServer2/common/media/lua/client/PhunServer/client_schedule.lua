if isServer() then
    return
end

local Core = PhunServer

-- ---------------------------------------------------------------------------
-- ISPhunSchedulePanel
-- Admin-only panel for viewing and editing server schedules.
-- Opened via /schedule chat command or the PhunServer admin button.
-- Left pane: schedule list.  Right pane: editor for the selected schedule.
-- ---------------------------------------------------------------------------

ISPhunSchedulePanel = ISPanel:derive("ISPhunSchedulePanel")

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
local FONT_SCALE = FONT_HGT_SMALL / 14

local W, H = math.floor(620 * FONT_SCALE), math.floor(660 * FONT_SCALE)
local PAD = math.floor(10 * FONT_SCALE)
local LIST_W = math.floor(190 * FONT_SCALE)
local EDIT_X = LIST_W + PAD * 2
local EDIT_W = W - EDIT_X - PAD
local ROW_H = FONT_HGT_SMALL + 4
local BTN_H = FONT_HGT_SMALL + 6
local BTN_W = math.floor(90 * FONT_SCALE)

-- day labels for weekly display; index matches os.date wday (1=Sun…7=Sat)
local DAY_LABELS = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"}

local TYPE_OPTIONS = {"restart", "event", "announcement"}
local TRIGGER_OPTIONS = {"cron", "workshop"}

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

-- ---------------------------------------------------------------------------
-- Constructor
-- ---------------------------------------------------------------------------
function ISPhunSchedulePanel:new(x, y)
    local o = ISPanel.new(self, x, y, W, H)
    o.schedules = {}
    o.selected = nil
    o.statusMsg = nil
    o.statusTimer = 0
    return o
end

-- ---------------------------------------------------------------------------
-- Build UI
-- ---------------------------------------------------------------------------
function ISPhunSchedulePanel:initialise()
    ISPanel.initialise(self)
    self:createChildren()
end

function ISPhunSchedulePanel:createChildren()
    local self = self

    -- Title bar
    self.titleLabel = ISLabel:new(PAD, PAD, ROW_H, "PhunServer - Schedules", 1, 1, 1, 1, UIFont.Medium)
    self.titleLabel:initialise()
    self:addChild(self.titleLabel)

    -- Close button (top-right)
    local closeBtn = ISButton:new(W - BTN_W - PAD, PAD, BTN_W, BTN_H, "Close", self, self.close)
    closeBtn:initialise()
    self:addChild(closeBtn)

    local listTop = ROW_H + PAD * 2

    -- ---- LEFT PANE: schedule list ----------------------------------------

    local listH = H - listTop - BTN_H - PAD * 3
    self.listBox = ISScrollingListBox:new(PAD, listTop, LIST_W, listH)
    self.listBox.font = UIFont.Small
    self.listBox.itemheight = ROW_H
    self.listBox.onmousedown = self.onListSelect
    self.listBox.target = self
    self.listBox:initialise()
    self:addChild(self.listBox)

    local listBtnY = listTop + listH + PAD
    self.addBtn = ISButton:new(PAD, listBtnY, math.floor(60 * FONT_SCALE), BTN_H, "+ Add", self, self.onAddSchedule)
    self.addBtn:initialise()
    self:addChild(self.addBtn)

    self.delBtn = ISButton:new(PAD + math.floor(66 * FONT_SCALE), listBtnY, math.floor(70 * FONT_SCALE), BTN_H,
        "- Delete", self, self.onDeleteSchedule)
    self.delBtn:initialise()
    self:addChild(self.delBtn)

    -- ---- RIGHT PANE: editor ----------------------------------------------

    local ex = EDIT_X
    local ey = listTop
    local eow = EDIT_W

    -- Enabled tick
    self.enabledTick = ISTickBox:new(ex, ey, eow, ROW_H, "", nil)
    self.enabledTick:initialise()
    self.enabledTick:addOption("Enabled")
    self:addChild(self.enabledTick)
    ey = ey + ROW_H + PAD

    -- Name
    self.nameLabel = ISLabel:new(ex, ey, ROW_H, "Name:", 1, 1, 1, 1, UIFont.Small)
    self.nameLabel:initialise()
    self:addChild(self.nameLabel)
    ey = ey + ROW_H
    self.nameEntry = ISTextEntryBox:new("", ex, ey, eow, ROW_H)
    self.nameEntry:initialise()
    self:addChild(self.nameEntry)
    ey = ey + ROW_H + PAD

    -- Trigger  (Scheduled / Workshop)
    self.triggerLabel = ISLabel:new(ex, ey, ROW_H, "Trigger:", 1, 1, 1, 1, UIFont.Small)
    self.triggerLabel:initialise()
    self:addChild(self.triggerLabel)
    ey = ey + ROW_H
    self.triggerCombo = ISComboBox:new(ex, ey, eow, ROW_H, self, self.onTriggerChanged)
    self.triggerCombo:initialise()
    self.triggerCombo:addOption("Scheduled")
    self.triggerCombo:addOption("Workshop update")
    self:addChild(self.triggerCombo)
    ey = ey + ROW_H + PAD

    -- Repeat (cron only)
    self.repeatLabel = ISLabel:new(ex, ey, ROW_H, "Repeat:", 1, 1, 1, 1, UIFont.Small)
    self.repeatLabel:initialise()
    self:addChild(self.repeatLabel)
    ey = ey + ROW_H
    self.recurCombo = ISComboBox:new(ex, ey, eow, ROW_H, self, self.onRecurChanged)
    self.recurCombo:initialise()
    self.recurCombo:addOption("daily")
    self.recurCombo:addOption("weekly")
    self:addChild(self.recurCombo)
    ey = ey + ROW_H + PAD

    -- Day selector (weekly + cron only)
    self.daysLabel = ISLabel:new(ex, ey, ROW_H, "Days:", 1, 1, 1, 1, UIFont.Small)
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
    self.timesLabel = ISLabel:new(ex, ey, ROW_H, "Times (HH:MM):", 1, 1, 1, 1, UIFont.Small)
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

    -- Time add row (cron only)
    self.timeEntry = ISTextEntryBox:new("", ex, ey, math.floor(80 * FONT_SCALE), ROW_H)
    self.timeEntry:initialise()
    self:addChild(self.timeEntry)

    self.addTimeBtn = ISButton:new(ex + math.floor(86 * FONT_SCALE), ey, math.floor(60 * FONT_SCALE), BTN_H, "Add",
        self, self.onAddTime)
    self.addTimeBtn:initialise()
    self:addChild(self.addTimeBtn)

    self.removeTimeBtn = ISButton:new(ex + math.floor(152 * FONT_SCALE), ey, math.floor(70 * FONT_SCALE), BTN_H,
        "Remove", self, self.onRemoveTime)
    self.removeTimeBtn:initialise()
    self:addChild(self.removeTimeBtn)
    ey = ey + BTN_H + PAD

    -- Outcome / Type
    self.typeLabel = ISLabel:new(ex, ey, ROW_H, "Outcome:", 1, 1, 1, 1, UIFont.Small)
    self.typeLabel:initialise()
    self:addChild(self.typeLabel)
    ey = ey + ROW_H
    self.typeCombo = ISComboBox:new(ex, ey, eow, ROW_H, self, self.onTypeChanged)
    self.typeCombo:initialise()
    self.typeCombo:addOption("restart")
    self.typeCombo:addOption("event")
    self.typeCombo:addOption("announcement")
    self:addChild(self.typeCombo)
    ey = ey + ROW_H + PAD

    -- Event name (type=event only)
    self.eventNameLabel = ISLabel:new(ex, ey, ROW_H, "Event name:", 1, 1, 1, 1, UIFont.Small)
    self.eventNameLabel:initialise()
    self:addChild(self.eventNameLabel)
    ey = ey + ROW_H
    self.eventNameEntry = ISTextEntryBox:new("", ex, ey, eow, ROW_H)
    self.eventNameEntry:initialise()
    self:addChild(self.eventNameEntry)
    ey = ey + ROW_H + PAD

    -- Warnings / countdown messages
    -- restart/event: each entry fires N secs BEFORE the action.
    -- announcement:  each entry fires N secs AFTER the schedule fires (0 = immediate).
    self.warnLabel = ISLabel:new(ex, ey, ROW_H, "Warnings:", 1, 1, 1, 1, UIFont.Small)
    self.warnLabel:initialise()
    self:addChild(self.warnLabel)
    ey = ey + ROW_H
    local warnListH = 2 * ROW_H + 4
    self.warnList = ISScrollingListBox:new(ex, ey, eow, warnListH)
    self.warnList.font = UIFont.Small
    self.warnList.itemheight = ROW_H
    self.warnList:initialise()
    self:addChild(self.warnList)
    ey = ey + warnListH + PAD

    -- Warn input row: [secs][text][Add][Del]
    local wSecsW = math.floor(50 * FONT_SCALE)
    local wBtnW = math.floor(50 * FONT_SCALE)
    local wTxtW = eow - wSecsW - wBtnW * 2 - PAD * 3

    self.warnSecsEntry = ISTextEntryBox:new("", ex, ey, wSecsW, ROW_H)
    self.warnSecsEntry:initialise()
    self:addChild(self.warnSecsEntry)

    self.warnTextEntry = ISTextEntryBox:new("", ex + wSecsW + PAD, ey, wTxtW, ROW_H)
    self.warnTextEntry:initialise()
    self:addChild(self.warnTextEntry)

    local wAddX = ex + wSecsW + PAD + wTxtW + PAD
    self.addWarnBtn = ISButton:new(wAddX, ey, wBtnW, BTN_H, "Add", self, self.onAddWarning)
    self.addWarnBtn:initialise()
    self:addChild(self.addWarnBtn)

    self.removeWarnBtn = ISButton:new(wAddX + wBtnW + PAD, ey, wBtnW, BTN_H, "Del", self, self.onRemoveWarning)
    self.removeWarnBtn:initialise()
    self:addChild(self.removeWarnBtn)
    ey = ey + BTN_H + PAD

    -- Status message
    self.statusLabel = ISLabel:new(ex, ey, ROW_H, "", 1, 1, 1, 1, UIFont.Small)
    self.statusLabel:initialise()
    self:addChild(self.statusLabel)

    -- Save button (bottom-anchored)
    local saveY = H - BTN_H - PAD
    self.saveBtn = ISButton:new(ex, saveY, BTN_W, BTN_H, "Save", self, self.onSave)
    self.saveBtn:initialise()
    self:addChild(self.saveBtn)

    self:setEditVisible(false)
    self:refreshDayButtons()
end

-- ---------------------------------------------------------------------------
-- Show / hide the edit pane
-- ---------------------------------------------------------------------------
function ISPhunSchedulePanel:setEditVisible(visible)
    local items = {self.enabledTick, self.nameLabel, self.nameEntry, self.triggerLabel, self.triggerCombo,
                   self.repeatLabel, self.recurCombo, self.daysLabel, self.timesLabel, self.timesList, self.timeEntry,
                   self.addTimeBtn, self.removeTimeBtn, self.typeLabel, self.typeCombo, self.eventNameLabel,
                   self.eventNameEntry, self.warnLabel, self.warnList, self.warnSecsEntry, self.warnTextEntry,
                   self.addWarnBtn, self.removeWarnBtn, self.saveBtn, self.statusLabel}
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
function ISPhunSchedulePanel:refreshList()
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
function ISPhunSchedulePanel:loadScheduleIntoForm(idx)
    local sch = self.schedules[idx]
    if not sch then
        return
    end
    self.selected = idx

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

    -- event name
    self.eventNameEntry:setText(sch.eventName or "")

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
function ISPhunSchedulePanel:refreshTriggerVisibility()
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

function ISPhunSchedulePanel:refreshTypeVisibility()
    local isEvent = self.typeCombo.selected == 2
    self.eventNameLabel:setVisible(isEvent)
    self.eventNameEntry:setVisible(isEvent)
end

function ISPhunSchedulePanel:refreshDayButtons()
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
function ISPhunSchedulePanel:onListSelect(item, _)
    if item and item.item then
        self:loadScheduleIntoForm(item.item)
    end
end

-- ---------------------------------------------------------------------------
-- Callbacks — trigger / type / recur
-- ---------------------------------------------------------------------------
function ISPhunSchedulePanel:onTriggerChanged()
    self:refreshTriggerVisibility()
end

function ISPhunSchedulePanel:onTypeChanged()
    self:refreshTypeVisibility()
end

function ISPhunSchedulePanel:onRecurChanged()
    self:refreshDayButtons()
end

function ISPhunSchedulePanel:onDayToggle(wdayIdx)
    local btn = self.dayTicks[wdayIdx]
    if btn then
        btn.selected = not btn.selected
        self:refreshDayButtons()
    end
end

-- ---------------------------------------------------------------------------
-- Callbacks — schedule list management
-- ---------------------------------------------------------------------------
function ISPhunSchedulePanel:onAddSchedule()
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

function ISPhunSchedulePanel:onDeleteSchedule()
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
function ISPhunSchedulePanel:onAddTime()
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

function ISPhunSchedulePanel:onRemoveTime()
    local sel = self.timesList.selected
    if sel and sel > 0 then
        self.timesList:removeItemByIndex(sel)
    end
end

-- ---------------------------------------------------------------------------
-- Callbacks — warnings
-- ---------------------------------------------------------------------------
function ISPhunSchedulePanel:onAddWarning()
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
    self.warnList:addItem(string.format("%ds — %s", secs, text), {
        secs = secs,
        text = text
    })
    self.warnSecsEntry:setText("")
    self.warnTextEntry:setText("")
end

function ISPhunSchedulePanel:onRemoveWarning()
    local sel = self.warnList.selected
    if sel and sel > 0 then
        self.warnList:removeItemByIndex(sel)
    end
end

-- ---------------------------------------------------------------------------
-- Save
-- ---------------------------------------------------------------------------
function ISPhunSchedulePanel:onSave()
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

    if sch.type == "event" then
        local en = self.eventNameEntry:getText():match("^%s*(.-)%s*$")
        sch.eventName = (en ~= "") and en or nil
    else
        sch.eventName = nil
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
function ISPhunSchedulePanel:onDataReceived(schedules, saved)
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
function ISPhunSchedulePanel:setStatus(msg, isError)
    self.statusMsg = msg
    self.statusTimer = getTimestampMs() + 4000
    if isError then
        self.statusLabel:setColor(1, 0.3, 0.3, 1)
    else
        self.statusLabel:setColor(0.3, 1, 0.3, 1)
    end
    self.statusLabel:setName(msg)
end

function ISPhunSchedulePanel:update()
    ISPanel.update(self)
    if self.statusMsg and getTimestampMs() > self.statusTimer then
        self.statusMsg = nil
        self.statusLabel:setName("")
    end
end

-- ---------------------------------------------------------------------------
-- Close
-- ---------------------------------------------------------------------------
function ISPhunSchedulePanel:close()
    self:setVisible(false)
    self:removeFromUIManager()
    Core.ui.schedulePanel = nil
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
    local panel = ISPhunSchedulePanel:new(math.floor((sw - W) / 2), math.floor((sh - H) / 2))
    panel:initialise()
    panel:addToUIManager()
    Core.ui.schedulePanel = panel
    sendClientCommand(Core.name, Core.commands.getSchedules, {})
end
