if isServer() then
    return
end

require "DebugUIs/DebugMenu/ISDebugMenu"
local Core = PhunServer

local function showPhunServerConfigs()
    if Core.tools.isAdmin(getPlayer()) then
        Core.openSchedulePanel()
    end
end

local ISDebugMenu_setupButtons = ISDebugMenu.setupButtons;
function ISDebugMenu:setupButtons()
    self:addButtonInfo("PhunServer", function()
        Core.openSchedulePanel()
    end, "MAIN");
    ISDebugMenu_setupButtons(self);
end

local ISAdminPanelUI_create = ISAdminPanelUI.create;
-- b42
function ISAdminPanelUI:create()

    local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
    local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
    local UI_BORDER_SPACING = 10
    local BUTTON_HGT = FONT_HGT_SMALL + 6

    local btnWid = 200;
    local x = UI_BORDER_SPACING + 1;
    local y = FONT_HGT_MEDIUM + UI_BORDER_SPACING * 2 + 1;

    self.showPhunServerConfigs = ISButton:new(x, y, btnWid, BUTTON_HGT, "** PhunServer **", self, showPhunServerConfigs);
    self.showPhunServerConfigs.internal = "";
    self.showPhunServerConfigs:initialise();
    self.showPhunServerConfigs:instantiate();
    self.showPhunServerConfigs.borderColor = self.buttonBorderColor;
    self:addChild(self.showPhunServerConfigs);

    ISAdminPanelUI_create(self);

end
