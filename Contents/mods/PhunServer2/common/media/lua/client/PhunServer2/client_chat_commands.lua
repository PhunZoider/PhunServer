if isServer() then
    return
end

local Core = require "PhunServer2/core"
local tools = Core.tools

-- ---------------------------------------------------------------------------
-- The /command hook.
--
-- Wraps the vanilla ISChat.onCommandEntered and dispatches into Core.cmds,
-- which any PhunServer2 module can register into. Handler return values:
--
--   true            handled, clear the chat box
--   "some string"   handled, show that string to the player as an error
--   false or nil    not handled, fall through to the vanilla handler
-- ---------------------------------------------------------------------------

local original_onCommandEntered = ISChat.onCommandEntered

local function splitString(s, sep)
    sep = sep or "%s"
    local t = {}
    for str in string.gmatch(s, "([^" .. sep .. "]+)") do
        table.insert(t, str)
    end
    return t
end

ISChat.onCommandEntered = function(self)

    local commandText = ISChat.instance.textEntry:getText()
    ISChat.instance:logChatCommand(commandText)

    if commandText and commandText ~= "" and commandText:sub(1, 1) == "/" then

        local parts = splitString(commandText)
        local entered = nil
        local args = {}

        for i, arg in ipairs(parts) do
            if i == 1 then
                entered = string.sub(arg, 2, #arg)
            else
                table.insert(args, arg)
            end
        end

        local command = entered and Core.cmds[string.lower(entered)]
        if command then
            if command.admin and not tools.isAdmin() then
                Core.FakeMessage(getText("IGUI_PhunServer2_NoAccess"), "<RGB:255,255,0>")
                ISChat.instance.textEntry:setText("")
                return
            end

            local result = command.handler(args)

            if type(result) == "string" and result ~= "" then
                Core.FakeMessage(result, "<RGB:255,255,0>")
            end

            if result ~= nil and result ~= false then
                ISChat.instance.textEntry:setText("")
                return
            end
        end
    end

    original_onCommandEntered(self)
end

-- ---------------------------------------------------------------------------
-- Commands core owns, because core owns the shutdown machinery.
-- ---------------------------------------------------------------------------

Core.registerCommand("restart", {
    admin = true,
    handler = function(args)
        sendClientCommand(Core.name, Core.commands.restart, args)
        return true
    end
})

Core.registerCommand("cancelrestart", {
    admin = true,
    handler = function(args)
        sendClientCommand(Core.name, Core.commands.cancelRestart, args)
        return true
    end
})
