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

local W, H = math.floor(620 * FONT_SCALE), math.floor(640 * FONT_SCALE)
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
local TRIGGER_OPTIONS = {"cron", "workshop", "manual"}

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

local ICONS = {
    trigger = {
        cron = getTexture("media/ui/clock.png"),
        workshop = getTexture("media/ui/gear.png"),
        manual = getTexture("media/ui/bolt.png")
    },
    action = {
        restart = getTexture("media/ui/recycle.png"),
        announcement = getTexture("media/ui/speaker.png"),
        event = getTexture("media/ui/bolt.png")
    }
}

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

-- ---------------------------------------------------------------------------
-- Open (called from chat command or admin panel)
-- ---------------------------------------------------------------------------
function Core.openSchedulePanel()
    if not Core.tools.isAdmin(getPlayer()) then
        return
    end
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

    local controls = {}
    self.controls = controls

    local listTop = ROW_H + PAD * 2

    -- ---- LEFT PANE: schedule list ----------------------------------------

    local listH = H - listTop - PAD * 2
    local listBtnY = listTop + listH + PAD

    local leftPanel = ISPanel:new(PAD, listTop, LIST_W, listH)
    leftPanel:initialise()
    leftPanel:instantiate();
    leftPanel:setAnchorRight(true);
    leftPanel:setAnchorTop(true);
    leftPanel:setAnchorLeft(true);
    leftPanel.backgroundColor = {
        r = C.panel.r,
        g = C.panel.g,
        b = C.panel.b,
        a = C.panel.a
    }

    controls.leftPanel = leftPanel
    self:addChild(controls.leftPanel)

    local lblSchedules = ISLabel:new(PAD, PAD, ROW_H, "Schedules", C.textDim.r, C.textDim.g, C.textDim.b, C.textDim.a,
        UIFont.Small, true)
    lblSchedules:initialise()
    leftPanel:addChild(lblSchedules)

    local listBox = ISScrollingListBox:new(PAD, lblSchedules.y + lblSchedules.height + PAD, LIST_W - PAD * 2,
        listH - (PAD * 2) - BTN_H - PAD - lblSchedules.height - PAD)
    listBox.font = UIFont.Small
    listBox.itemheight = ROW_H
    listBox.onmousedown = self.onListSelect
    listBox.target = self
    listBox:setAnchorRight(true);
    listBox:setAnchorTop(true);
    listBox:setAnchorLeft(true);
    listBox:initialise()

    local schedulePanel = self
    listBox.doDrawItem = function(lb, y, item, alt)
        if not item.height then
            item.height = lb.itemheight
        end
        -- use PZ's themed selection / hover highlight methods
        if lb.selected == item.index then
            lb:drawSelection(0, y, lb:getWidth(), item.height - 1)
        elseif lb.mouseoverselected == item.index and lb:isMouseOver() and not lb:isMouseOverScrollBar() then
            lb:drawMouseOverHighlight(0, y, lb:getWidth(), item.height - 1)
        end
        local sch = schedulePanel.schedules and schedulePanel.schedules[item.item]
        local r, g, b, a
        if sch and sch.enabled then
            r, g, b, a = C.text.r, C.text.g, C.text.b, C.text.a
        else
            r, g, b, a = C.textDim.r, C.textDim.g, C.textDim.b, C.textDim.a
        end
        local iconSz = item.height - 2
        local x = 2
        local trigIcon = sch and ICONS.trigger[sch.trigger or "cron"]
        if trigIcon then
            lb:drawTextureScaled(trigIcon, x, y + 1, iconSz, iconSz, a, r, g, b)
        end
        x = x + iconSz + 2
        local actIcon = sch and ICONS.action[sch.type or "restart"]
        if actIcon then
            lb:drawTextureScaled(actIcon, x, y + 1, iconSz, iconSz, a, r, g, b)
        end
        x = x + iconSz + 4
        lb:drawText(item.text, x, y + 2, r, g, b, a, lb.font)
        -- right side: solid accent square when running, faint "..." affordance otherwise
        local isRunning = sch and sch.name == schedulePanel.runningScheduleName
        if isRunning then
            local sz = 6
            lb:drawRect(lb:getWidth() - PAD - sz, y + math.floor((item.height - sz) / 2), sz, sz, 1, C.accent.r,
                C.accent.g, C.accent.b)
        else
            lb:drawText("...", lb:getWidth() - PAD * 2, y + 2, C.textDim.r, C.textDim.g, C.textDim.b, C.textDim.a * 0.5,
                lb.font)
        end
        return y + item.height
    end

    listBox.onmousedown = self.onListSelect
    listBox.target = self

    listBox.onRightMouseDown = function(lb, x, y)
        local scrollPos = lb.vscroll and lb.vscroll.pos or 0
        local rowIdx = math.floor((y + scrollPos) / lb.itemheight) + 1
        local item = lb.items[rowIdx]
        if not item then
            return
        end
        lb.selected = rowIdx
        schedulePanel:onListSelect(item.item)
        schedulePanel:openContextMenu(item.item, x + lb:getAbsoluteX(), y + lb:getAbsoluteY())
    end

    controls.listBox = listBox
    leftPanel:addChild(controls.listBox)

    local addBtn = ISButton:new(listBox.x, listBox.y + listBox.height + PAD, listBox.width / 2 - PAD / 2, BTN_H,
        "+ Add", self, self.onAddSchedule)
    addBtn:initialise()
    addBtn:setTooltip("Add a new schedule")

    controls.addBtn = addBtn
    leftPanel:addChild(addBtn)

    local delBtn = ISButton:new(listBox.x + listBox.width / 2 + PAD / 2, addBtn.y, addBtn.width, BTN_H, "- Delete",
        self, self.onDeleteSchedule)
    delBtn:initialise()
    delBtn:setTooltip("Delete the selected schedule")

    controls.delBtn = delBtn
    leftPanel:addChild(delBtn)

    leftPanel.prerender = function(self)
        ISPanel.prerender(self)
        addBtn:setWidth(listBox.width / 2 - PAD / 2)
        addBtn:setX(listBox.x)
        addBtn:setY(listBox.y + listBox.height + PAD)

        delBtn:setWidth(addBtn.width)
        delBtn:setX(addBtn.x + addBtn.width + PAD)
        delBtn:setY(addBtn.y)
    end

    -- ---- RIGHT PANE: editor ----------------------------------------------

    local ex = EDIT_X
    local ey = listTop
    local eow = EDIT_W

    local rightTopPanel = ISPanel:new(ex, ey, eow + PAD * 2, 150)
    rightTopPanel:initialise()
    rightTopPanel:instantiate();
    rightTopPanel.backgroundColor = {
        r = C.panel.r,
        g = C.panel.g,
        b = C.panel.b,
        a = C.panel.a
    }
    controls.rightTopPanel = rightTopPanel
    self:addChild(controls.rightTopPanel)

    -- Name
    ex = PAD
    ey = PAD
    eow = eow - PAD * 2
    local ex2 = eow - 200 + PAD

    local nameLabel = ISLabel:new(ex, ey, ROW_H, "Name", C.textDim.r, C.textDim.g, C.textDim.b, C.textDim.a,
        UIFont.Small, true)
    nameLabel:initialise()
    rightTopPanel:addChild(nameLabel)
    self.controls.nameLabel = nameLabel

    local triggerLabel = ISLabel:new(ex2, nameLabel.y, ROW_H, "Trigger", C.textDim.r, C.textDim.g, C.textDim.b,
        C.textDim.a, UIFont.Small, true)
    triggerLabel:initialise()
    rightTopPanel:addChild(triggerLabel)
    self.controls.triggerLabel = triggerLabel

    ey = ey + ROW_H
    local nameEntry = ISTextEntryBox:new("", ex, ey, ex2 - PAD * 2, ROW_H)
    nameEntry:initialise()
    nameEntry:setTooltip("Unique name for this schedule")
    rightTopPanel:addChild(nameEntry)

    self.controls.nameEntry = nameEntry

    -- ey = ey + ROW_H
    local triggerCombo = ISComboBox:new(ex2, nameEntry.y, 200, ROW_H, self, self.onTriggerChanged)
    triggerCombo:initialise()
    triggerCombo:addOption("Scheduled")
    triggerCombo:addOption("Workshop update")
    triggerCombo:addOption("Manual")
    triggerCombo.tooltip =
        "Scheduled: fires at set times.\nWorkshop update: fires when a mod update is detected.\nManual: only fires when an admin clicks Trigger."
    controls.triggerCombo = triggerCombo
    rightTopPanel:addChild(triggerCombo)
    -- ey = ey + ROW_H + PAD

    ey = ey + ROW_H + PAD

    rightTopPanel:setHeight(ey)

    local rightSchedulePanel = ISPanel:new(rightTopPanel.x, rightTopPanel.y + rightTopPanel.height + PAD,
        rightTopPanel.width, H - rightTopPanel.y - PAD)
    rightSchedulePanel:initialise()
    rightSchedulePanel:instantiate();
    rightSchedulePanel.backgroundColor = {
        r = C.panel.r,
        g = C.panel.g,
        b = C.panel.b,
        a = C.panel.a
    }
    controls.rightSchedulePanel = rightSchedulePanel
    self:addChild(controls.rightSchedulePanel)

    ex = PAD
    ey = PAD

    -- Repeat (cron only)
    local repeatLabel = ISLabel:new(ex, ey, ROW_H, "Repeat", C.textDim.r, C.textDim.g, C.textDim.b, C.textDim.a,
        UIFont.Small, true)
    repeatLabel:initialise()
    rightSchedulePanel:addChild(repeatLabel)
    controls.repeatLabel = repeatLabel

    local lblWorkshopCheckFrequency = ISLabel:new(ex, ey, ROW_H, "Frequency", C.textDim.r, C.textDim.g, C.textDim.b,
        C.textDim.a, UIFont.Small, true)
    lblWorkshopCheckFrequency:initialise()
    rightSchedulePanel:addChild(lblWorkshopCheckFrequency)
    controls.lblWorkshopCheckFrequency = lblWorkshopCheckFrequency

    ey = ey + ROW_H

    local workshopFrequency = ISTextEntryBox:new("", ex, ey, ex2 - PAD * 2, ROW_H)
    workshopFrequency:initialise()
    workshopFrequency:setTooltip("Enter the frequency for workshop updates in minutes (e.g. 60 for hourly checks)")
    rightSchedulePanel:addChild(workshopFrequency)
    controls.workshopFrequency = workshopFrequency

    local recurCombo = ISComboBox:new(ex, ey, 100, ROW_H, self, self.onRecurChanged)
    recurCombo:initialise()
    recurCombo:addOption("daily")
    recurCombo:addOption("weekly")
    recurCombo.tooltip = "daily: fires every day.\nweekly: fires on selected days of the week"
    rightSchedulePanel:addChild(recurCombo)
    controls.recurCombo = recurCombo

    -- ey = ey + ROW_H + PAD

    local ex2 = recurCombo.x + recurCombo.width + PAD
    local eow2 = rightSchedulePanel.width - ex2 - PAD * 3
    -- Day selector (weekly + cron only)
    local daysLabel = ISLabel:new(ex2, repeatLabel.y, ROW_H, "Days", C.textDim.r, C.textDim.g, C.textDim.b, C.textDim.a,
        UIFont.Small, true)
    daysLabel:initialise()
    rightSchedulePanel:addChild(daysLabel)
    controls.daysLabel = daysLabel

    self.controls.dayTicks = {}
    local dayBtnW = math.floor((eow2 - 6) / 7)
    for i, lbl in ipairs(DAY_LABELS) do
        local btn = ISButton:new(ex2 + (i - 1) * (dayBtnW + 1), ey, dayBtnW, BTN_H, lbl, self, function(target)
            target:onDayToggle(i)
        end)
        btn:initialise()
        btn.selected = false
        rightSchedulePanel:addChild(btn)
        self.controls.dayTicks[i] = btn
    end
    ey = ey + BTN_H + PAD

    -- Times list (cron only)
    local timesLabel = ISLabel:new(ex, ey, ROW_H, "Times (HH:MM)", C.textDim.r, C.textDim.g, C.textDim.b, C.textDim.a,
        UIFont.Small, true)
    timesLabel:initialise()
    rightSchedulePanel:addChild(timesLabel)
    controls.timesLabel = timesLabel

    ey = ey + ROW_H
    local timesListH = 3 * ROW_H + 4
    local timesList = ISScrollingListBox:new(ex, ey, eow, timesListH)
    timesList.font = UIFont.Small
    timesList.itemheight = ROW_H
    timesList:initialise()
    rightSchedulePanel:addChild(timesList)
    controls.timesList = timesList
    ey = ey + timesListH + PAD

    -- Time input row (cron only)
    local timeEntry = ISTextEntryBox:new("", ex, ey, math.floor(80 * FONT_SCALE), ROW_H)
    timeEntry:initialise()
    timeEntry:setTooltip("Enter time in HH:MM 24-hour format")
    rightSchedulePanel:addChild(timeEntry)
    controls.timeEntry = timeEntry

    local addTimeBtn = ISButton:new(ex + math.floor(86 * FONT_SCALE), ey, math.floor(60 * FONT_SCALE), BTN_H, "Add",
        self, self.onAddTime)
    addTimeBtn:initialise()
    addTimeBtn:setTooltip("Add this time to the schedule")
    rightSchedulePanel:addChild(addTimeBtn)
    controls.addTimeBtn = addTimeBtn

    local removeTimeBtn = ISButton:new(ex + math.floor(152 * FONT_SCALE), ey, math.floor(70 * FONT_SCALE), BTN_H,
        "Remove", self, self.onRemoveTime)
    removeTimeBtn:initialise()
    removeTimeBtn:setTooltip("Remove the selected time entry")
    rightSchedulePanel:addChild(removeTimeBtn)
    controls.removeTimeBtn = removeTimeBtn

    rightSchedulePanel:setHeight(removeTimeBtn.y + removeTimeBtn.height + PAD)

    ey = PAD

    local rightOutcomePanel = ISPanel:new(rightSchedulePanel.x, rightSchedulePanel.y + rightSchedulePanel.height + PAD,
        rightSchedulePanel.width, H - rightSchedulePanel.y - rightSchedulePanel.height - PAD)
    rightOutcomePanel:initialise()
    rightOutcomePanel:instantiate();
    rightOutcomePanel.backgroundColor = {
        r = C.panel.r,
        g = C.panel.g,
        b = C.panel.b,
        a = C.panel.a
    }
    controls.rightOutcomePanel = rightOutcomePanel
    self:addChild(controls.rightOutcomePanel)

    -- Outcome / Type
    local typeLabel = ISLabel:new(ex, ey, ROW_H, "Action", C.textDim.r, C.textDim.g, C.textDim.b, C.textDim.a,
        UIFont.Small, true)
    typeLabel:initialise()
    rightOutcomePanel:addChild(typeLabel)
    controls.typeLabel = typeLabel

    ey = ey + ROW_H
    local typeCombo = ISComboBox:new(ex, ey, eow, ROW_H, self, self.onTypeChanged)
    typeCombo:initialise()
    typeCombo:addOption("restart")
    typeCombo:addOption("event")
    typeCombo:addOption("announcement")
    typeCombo.tooltip = "restart: schedules a server restart with countdown.\n" ..
                            "event: triggers a named Lua event.\n" .. "announcement: broadcasts messages to all players"
    rightOutcomePanel:addChild(typeCombo)
    controls.typeCombo = typeCombo
    ey = ey + ROW_H + PAD

    -- Extra field: adapts label/tooltip based on outcome type.
    -- type=event       → "Event name"    (stores sch.eventName)
    -- type=announcement → "Message"      (stores sch.announcementText)
    -- type=restart      → hidden
    local extraFieldLabel = ISLabel:new(ex, ey, ROW_H, "Data", C.textDim.r, C.textDim.g, C.textDim.b, C.textDim.a,
        UIFont.Small, true)
    extraFieldLabel:initialise()
    rightOutcomePanel:addChild(extraFieldLabel)
    controls.extraFieldLabel = extraFieldLabel

    ey = ey + ROW_H
    local extraFieldEntry = ISTextEntryBox:new("", ex, ey, eow, ROW_H)
    extraFieldEntry:initialise()
    rightOutcomePanel:addChild(extraFieldEntry)
    controls.extraFieldEntry = extraFieldEntry
    ey = ey + ROW_H + PAD

    rightOutcomePanel:setHeight(ey)

    local rightWarningPanel = ISPanel:new(rightOutcomePanel.x, rightOutcomePanel.y + rightOutcomePanel.height + PAD,
        rightOutcomePanel.width, H - rightOutcomePanel.y - rightOutcomePanel.height - PAD)

    rightWarningPanel:initialise()
    rightWarningPanel:instantiate();
    rightWarningPanel.backgroundColor = {
        r = C.panel.r,
        g = C.panel.g,
        b = C.panel.b,
        a = C.panel.a
    }
    controls.rightWarningPanel = rightWarningPanel
    self:addChild(controls.rightWarningPanel)

    ey = PAD

    -- Warnings / countdown messages
    -- restart/event: each entry fires N secs BEFORE the action.
    -- announcement:  each entry fires N secs AFTER the schedule fires (0 = immediate).
    local warnLabel = ISLabel:new(ex, ey, ROW_H, "Warnings", C.textDim.r, C.textDim.g, C.textDim.b, C.textDim.a,
        UIFont.Small, true)
    warnLabel:initialise()
    controls.warnLabel = warnLabel
    rightWarningPanel:addChild(warnLabel)
    ey = ey + ROW_H
    local warnListH = 6 * ROW_H + 4

    local warnList = ISScrollingListBox:new(ex, ey, eow, warnListH)
    warnList.font = UIFont.Small
    warnList.itemheight = ROW_H
    warnList.onmousedown = self.onWarnSelect
    warnList.target = self
    warnList:initialise()
    controls.warnList = warnList
    rightWarningPanel:addChild(warnList)
    ey = ey + warnListH + PAD

    -- Warning input hint labels
    local wSecsW = math.floor(50 * FONT_SCALE)
    local wBtnW = math.floor(50 * FONT_SCALE)
    local wTxtW = eow - wSecsW - wBtnW * 2 - PAD * 3

    local warnSecsHint = ISLabel:new(ex, ey, ROW_H, "Secs", C.textDim.r, C.textDim.g, C.textDim.b, C.textDim.a,
        UIFont.Small, true)
    warnSecsHint:initialise()
    rightWarningPanel:addChild(warnSecsHint)
    controls.warnSecsHint = warnSecsHint

    local warnMsgHint = ISLabel:new(ex + wSecsW + PAD, ey, ROW_H, "Message or translation key", C.textDim.r,
        C.textDim.g, C.textDim.b, C.textDim.a, UIFont.Small, true)
    warnMsgHint:initialise()
    rightWarningPanel:addChild(warnMsgHint)
    controls.warnMsgHint = warnMsgHint
    ey = ey + ROW_H

    -- Warning input row: [secs] [text] [Add/Update] [Del]
    local warnSecsEntry = ISTextEntryBox:new("", ex, ey, wSecsW, ROW_H)
    warnSecsEntry:initialise()
    warnSecsEntry:setTooltip(
        "Seconds before action (restart/event) or delay after firing (announcement).\n0 = immediate")
    rightWarningPanel:addChild(warnSecsEntry)
    controls.warnSecsEntry = warnSecsEntry

    local warnTextEntry = ISTextEntryBox:new("", ex + wSecsW + PAD, ey, wTxtW, ROW_H)
    warnTextEntry:initialise()
    warnTextEntry:setTooltip("Message text or translation key (e.g. IGUI_PhunServer_Left)")
    rightWarningPanel:addChild(warnTextEntry)
    controls.warnTextEntry = warnTextEntry

    local wAddX = ex + wSecsW + PAD + wTxtW + PAD
    local addWarnBtn = ISButton:new(wAddX, ey, wBtnW, BTN_H, "Add", self, self.onAddWarning)
    addWarnBtn:initialise()
    addWarnBtn:setTooltip("Add a new warning or save edits to the selected entry")
    rightWarningPanel:addChild(addWarnBtn)
    controls.addWarnBtn = addWarnBtn

    local removeWarnBtn = ISButton:new(wAddX + wBtnW + PAD, ey, wBtnW, BTN_H, "Del", self, self.onRemoveWarning)
    removeWarnBtn:initialise()
    removeWarnBtn:setTooltip("Remove the selected warning entry")
    rightWarningPanel:addChild(removeWarnBtn)
    controls.removeWarnBtn = removeWarnBtn

    rightWarningPanel:setHeight(ey + BTN_H + PAD)

    local bottomPanel = ISPanel:new(rightWarningPanel.x, rightWarningPanel.y + rightWarningPanel.height + PAD,
        rightWarningPanel.width, H - rightWarningPanel.y - rightWarningPanel.height - PAD)

    bottomPanel:initialise()
    bottomPanel:instantiate();
    bottomPanel:setAnchorRight(true);
    bottomPanel:setAnchorLeft(true);

    bottomPanel.backgroundColor = {
        r = C.panel.r,
        g = C.panel.g,
        b = C.panel.b,
        a = C.panel.a
    }
    controls.bottomPanel = bottomPanel
    self:addChild(controls.bottomPanel)

    ey = PAD
    ex = PAD

    -- Enabled tick
    local enabledTick = ISTickBox:new(ex, ey, 100, ROW_H, "", nil)
    enabledTick:initialise()
    enabledTick:addOption("Enabled")
    enabledTick.tooltip = "Enable or disable this schedule"
    controls.enabledTick = enabledTick
    bottomPanel:addChild(enabledTick)

    -- ---- FOOTER: status label + save button (aligned with list ± buttons) ----
    local statusLabel = ISLabel:new(enabledTick.x + enabledTick.width + PAD, PAD, ROW_H, "", C.textDim.r, C.textDim.g,
        C.textDim.b, C.textDim.a, UIFont.Small)
    statusLabel:initialise()
    bottomPanel:addChild(statusLabel)
    controls.statusLabel = statusLabel

    local saveBtn = ISButton:new(ex + EDIT_W - BTN_W, PAD, BTN_W, BTN_H, "Save", self, self.onSave)
    saveBtn:initialise()
    saveBtn:setTooltip("Save this schedule and send to server")
    bottomPanel:addChild(saveBtn)
    controls.saveBtn = saveBtn

    bottomPanel:setHeight(ey + BTN_H + PAD)

    self:setEditVisible(false)
    self:refreshDayButtons()
end

function UI:prerender()
    ISCollapsableWindowJoypad.prerender(self)
    local controls = self.controls

    -- Right-side content defines the canonical height; left pane always matches it.
    local targetH = controls.bottomPanel.y + controls.bottomPanel.height + PAD
    local leftH = targetH - PAD - controls.leftPanel.y
    controls.leftPanel:setHeight(leftH)
    local lbH = leftH - controls.listBox.y - BTN_H - PAD * 2
    controls.listBox:setHeight(lbH)
    controls.addBtn.y = controls.listBox.y + controls.listBox.height + PAD
    controls.delBtn.y = controls.addBtn.y
    if self.height < targetH then
        self:setHeight(targetH)
    end

    local rpx = controls.leftPanel.x + controls.leftPanel.width + PAD
    controls.rightTopPanel:setX(rpx)
    controls.rightTopPanel:setWidth(self.width - rpx - PAD)
    controls.rightSchedulePanel:setX(rpx)
    controls.rightSchedulePanel:setWidth(controls.rightTopPanel.width)
    controls.rightOutcomePanel:setX(rpx)
    controls.rightOutcomePanel:setWidth(controls.rightTopPanel.width)
    controls.rightWarningPanel:setX(rpx)
    controls.rightWarningPanel:setWidth(controls.rightTopPanel.width)
    controls.bottomPanel:setX(rpx)
    controls.bottomPanel:setWidth(controls.rightTopPanel.width)
    controls.saveBtn:setX(controls.bottomPanel.width - controls.saveBtn.width - PAD)
    controls.statusLabel:setX(controls.enabledTick.x + controls.enabledTick.width + PAD)

end

-- ---------------------------------------------------------------------------
-- Show / hide the edit pane
-- ---------------------------------------------------------------------------
function UI:setEditVisible(visible)
    local items = {self.controls.enabledTick, self.controls.nameLabel, self.controls.nameEntry,
                   self.controls.triggerLabel, self.controls.triggerCombo, self.controls.repeatLabel,
                   self.controls.recurCombo, self.controls.daysLabel, self.controls.timesLabel, self.controls.timesList,
                   self.controls.timeEntry, self.controls.addTimeBtn, self.controls.removeTimeBtn,
                   self.controls.typeLabel, self.controls.typeCombo, self.controls.extraFieldLabel,
                   self.controls.extraFieldEntry, self.controls.warnLabel, self.controls.warnList,
                   self.controls.warnSecsHint, self.controls.warnMsgHint, self.controls.warnSecsEntry,
                   self.controls.warnTextEntry, self.controls.addWarnBtn, self.controls.removeWarnBtn,
                   self.controls.saveBtn, self.controls.statusLabel}
    for _, w in ipairs(items) do
        if w then
            w:setVisible(visible)
        end
    end
    for _, btn in ipairs(self.controls.dayTicks or {}) do
        btn:setVisible(visible)
    end
end

-- ---------------------------------------------------------------------------
-- List population
-- ---------------------------------------------------------------------------
function UI:refreshList()
    self.controls.listBox:clear()
    for i, sch in ipairs(self.schedules) do

        self.controls.listBox:addItem(sch.name or "Unnamed", i)
    end
    if self.selected and self.selected > #self.schedules then
        self.selected = #self.schedules > 0 and #self.schedules or nil
    end
    if self.selected then
        self.controls.listBox.selected = self.selected
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
    self.controls.addWarnBtn:setTitle("Add")
    self.controls.warnSecsEntry:setText("")
    self.controls.warnTextEntry:setText("")

    self.controls.enabledTick:setSelected(1, sch.enabled == true)
    self.controls.nameEntry:setText(sch.name or "")

    -- trigger
    self.controls.triggerCombo.selected = sch.trigger == "workshop" and 2 or sch.trigger == "manual" and 3 or 1

    -- recur
    self.controls.recurCombo.selected = (sch.recur == "weekly") and 2 or 1

    self.controls.workshopFrequency:setText(tostring(sch.workshopFrequency or ""))

    -- days
    local daySet = {}
    for _, d in ipairs(sch.days or {}) do
        daySet[d] = true
    end
    for i, btn in ipairs(self.controls.dayTicks) do
        btn.selected = daySet[i] == true
    end

    -- times
    self.controls.timesList:clear()
    for _, t in ipairs(sch.times or {}) do
        self.controls.timesList:addItem(t, t)
    end

    -- type/outcome
    local typeMap = {
        restart = 1,
        event = 2,
        announcement = 3
    }
    self.controls.typeCombo.selected = typeMap[sch.type] or 1

    -- extra field (event name or announcement message)
    if sch.type == "event" then
        self.controls.extraFieldEntry:setText(sch.eventName or "")
    elseif sch.type == "announcement" then
        self.controls.extraFieldEntry:setText(sch.announcementText or "")
    else
        self.controls.extraFieldEntry:setText("")
    end

    -- warnings / countdowns
    self.controls.warnList:clear()
    for _, c in ipairs(sch.countdowns or {}) do
        local secs = tonumber(c.secs) or 0
        local text = c.text or ""
        self.controls.warnList:addItem(string.format("%ds — %s", secs, text), {
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
    local sel = self.controls.triggerCombo.selected
    local isCron = sel == 1
    local isWorkshop = sel == 2
    self.controls.repeatLabel:setVisible(isCron)
    self.controls.recurCombo:setVisible(isCron)
    self.controls.lblWorkshopCheckFrequency:setVisible(isWorkshop)
    self.controls.workshopFrequency:setVisible(isWorkshop)
    self.controls.timesLabel:setVisible(isCron)
    self.controls.timesList:setVisible(isCron)
    self.controls.timeEntry:setVisible(isCron)
    self.controls.addTimeBtn:setVisible(isCron)
    self.controls.removeTimeBtn:setVisible(isCron)
    if isCron then
        self:refreshDayButtons()
    else
        self.controls.daysLabel:setVisible(false)
        for _, btn in ipairs(self.controls.dayTicks or {}) do
            btn:setVisible(false)
        end
    end
end

function UI:refreshTypeVisibility()
    local t = self.controls.typeCombo.selected
    local isEvent = t == 2
    local isAnnounce = t == 3
    local showExtra = isEvent or isAnnounce
    self.controls.extraFieldLabel:setVisible(showExtra)
    self.controls.extraFieldEntry:setVisible(showExtra)
    if isEvent then
        self.controls.extraFieldLabel:setName("Event name")
        self.controls.extraFieldEntry:setTooltip("Name of the Lua event to trigger (e.g. OnPhunServerRestart)")
    elseif isAnnounce then
        self.controls.extraFieldLabel:setName("Message")
        self.controls.extraFieldEntry:setTooltip("Text or translation key to broadcast when this schedule fires")
    end
end

function UI:refreshDayButtons()
    local isCron = self.controls.triggerCombo.selected == 1
    local isWeekly = isCron and self.controls.recurCombo.selected == 2
    self.controls.daysLabel:setVisible(isWeekly == true)
    for _, btn in ipairs(self.controls.dayTicks or {}) do
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
    if item then
        self:loadScheduleIntoForm(item)
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
    local btn = self.controls.dayTicks[wdayIdx]
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
        times = {},
        countdowns = {}
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
    local t = self.controls.timeEntry:getText():match("^%s*(%d%d?:%d%d)%s*$")
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
    for _, item in ipairs(self.controls.timesList.items) do
        if item.text == normalised then
            self:setStatus("Time already in list", true)
            return
        end
    end
    self.controls.timesList:addItem(normalised, normalised)
    self.controls.timeEntry:setText("")
end

function UI:onRemoveTime()
    local sel = self.controls.timesList.selected
    if sel and sel > 0 then
        self.controls.timesList:removeItemByIndex(sel)
    end
end

-- ---------------------------------------------------------------------------
-- Callbacks — warnings
-- ---------------------------------------------------------------------------

-- Clicking a warning in the list populates the input fields for editing.
function UI:onWarnSelect(item, _)
    if item and item.item then
        local d = item.item
        self.warnEditIdx = self.controls.warnList.selected
        self.controls.warnSecsEntry:setText(tostring(d.secs))
        self.controls.warnTextEntry:setText(d.text)
        self.controls.addWarnBtn:setTitle("Update")
    end
end

function UI:onAddWarning()
    local secsStr = self.controls.warnSecsEntry:getText():match("^%s*(%d+)%s*$")
    if not secsStr then
        self:setStatus("Seconds must be a whole number (0 or greater)", true)
        return
    end
    local secs = tonumber(secsStr)
    local text = self.controls.warnTextEntry:getText():match("^%s*(.-)%s*$")
    if not text or text == "" then
        self:setStatus("Warning text cannot be empty", true)
        return
    end
    local display = string.format("%ds — %s", secs, getText(text))
    local data = {
        secs = secs,
        text = text
    }

    if self.warnEditIdx and self.warnEditIdx <= #self.controls.warnList.items then
        -- Update the entry in place
        self.controls.warnList.items[self.warnEditIdx] = {
            text = display,
            item = data,
            height = ROW_H
        }
        self.warnEditIdx = nil
        self.controls.addWarnBtn:setTitle("Add")
    else
        self.controls.warnList:addItem(display, data)
    end
    table.sort(self.controls.warnList.items, function(a, b)
        return a.item.secs > b.item.secs
    end)
    self.controls.warnSecsEntry:setText("")
    self.controls.warnTextEntry:setText("")
end

function UI:onRemoveWarning()
    local sel = self.controls.warnList.selected
    if sel and sel > 0 then
        self.controls.warnList:removeItemByIndex(sel)
        -- Clear edit state if we just removed the entry being edited
        if self.warnEditIdx then
            self.warnEditIdx = nil
            self.controls.warnSecsEntry:setText("")
            self.controls.warnTextEntry:setText("")
            self.controls.addWarnBtn:setTitle("Add")
        end
    end
end

-- ---------------------------------------------------------------------------
-- Context menu (right-click on list row)
-- ---------------------------------------------------------------------------
function UI:openContextMenu(schIdx, absX, absY)
    local sch = self.schedules and self.schedules[schIdx]
    if not sch then
        return
    end
    local isRunning = sch.name == self.runningScheduleName
    local anyRunning = self.runningScheduleName ~= nil

    local menu = ISContextMenu.get(0, absX, absY)

    local runOpt = menu:addOption("Run Now", self, UI.onMenuRunNow, schIdx)
    if anyRunning then
        runOpt.notAvailable = true
    end

    if sch.trigger == "workshop" then
        local checkOpt = menu:addOption("Check for Updates", self, UI.onMenuCheckNow, schIdx)
        if anyRunning then
            checkOpt.notAvailable = true
        end
    end

    local cancelOpt = menu:addOption("Cancel", self, UI.onMenuCancel, schIdx)
    if not isRunning then
        cancelOpt.notAvailable = true
    end
end

function UI:onMenuRunNow(schIdx)
    local sch = self.schedules and self.schedules[schIdx]
    if not sch or self.runningScheduleName then
        return
    end
    sendClientCommand(Core.name, Core.commands.triggerSchedule, {
        name = sch.name
    })
    self:setStatus("Triggering '" .. sch.name .. "'...")
end

function UI:onMenuCheckNow(schIdx)
    local sch = self.schedules and self.schedules[schIdx]
    if not sch or sch.trigger ~= "workshop" or self.runningScheduleName then
        return
    end
    sendClientCommand(Core.name, Core.commands.checkworkshop, {})
    self:setStatus("Checking for updates...")
end

function UI:onMenuCancel(schIdx)
    local sch = self.schedules and self.schedules[schIdx]
    if not sch or sch.name ~= self.runningScheduleName then
        return
    end
    sendClientCommand(Core.name, Core.commands.stopSchedule, {})
    self:setStatus("Stopping countdown...")
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

    local name = self.controls.nameEntry:getText():match("^%s*(.-)%s*$")
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
    sch.enabled = self.controls.enabledTick:isSelected(1)
    local trigSel = self.controls.triggerCombo.selected
    sch.trigger = trigSel == 2 and "workshop" or trigSel == 3 and "manual" or "cron"
    sch.type = TYPE_OPTIONS[self.controls.typeCombo.selected] or "restart"

    if sch.trigger == "cron" then
        sch.recur = self.controls.recurCombo.selected == 2 and "weekly" or "daily"

        if sch.recur == "weekly" then
            sch.days = {}
            for i, btn in ipairs(self.controls.dayTicks) do
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
        for _, item in ipairs(self.controls.timesList.items) do
            table.insert(sch.times, item.text)
        end
        table.sort(sch.times)
        if #sch.times == 0 then
            self:setStatus("Add at least one time", true)
            return
        end
        sch.workshopFrequency = nil
    elseif sch.trigger == "workshop" then
        sch.workshopFrequency = tonumber(self.controls.workshopFrequency:getText()) or nil
        sch.recur = nil
        sch.days = nil
        sch.times = nil
    else -- manual
        sch.workshopFrequency = nil
        sch.recur = nil
        sch.days = nil
        sch.times = nil
    end

    -- Extra field: event name or announcement message
    if sch.type == "event" then
        local en = self.controls.extraFieldEntry:getText():match("^%s*(.-)%s*$")
        sch.eventName = (en ~= "") and en or nil
        sch.announcementText = nil
    elseif sch.type == "announcement" then
        local at = self.controls.extraFieldEntry:getText():match("^%s*(.-)%s*$")
        sch.announcementText = (at ~= "") and at or nil
        sch.eventName = nil
    else
        sch.eventName = nil
        sch.announcementText = nil
    end

    -- Warnings / countdowns
    sch.countdowns = {}
    for _, listItem in ipairs(self.controls.warnList.items) do
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
function UI:onDataReceived(schedules, saved, runningScheduleName)
    self.schedules = schedules or {}
    self.runningScheduleName = runningScheduleName
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
        self.controls.statusLabel:setColor(1, 0.3, 0.3, 1)
    else
        self.controls.statusLabel:setColor(0.3, 1, 0.3, 1)
    end
    self.controls.statusLabel:setName(msg)
end

function UI:update()
    ISCollapsableWindowJoypad.update(self)
    if self.statusMsg and getTimestampMs() > self.statusTimer then
        self.statusMsg = nil
        self.controls.statusLabel:setName("")
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
