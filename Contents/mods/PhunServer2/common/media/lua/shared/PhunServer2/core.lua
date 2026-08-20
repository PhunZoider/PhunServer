-- PhunServer2 core.
--
-- This is the shared singleton every PhunServer2 module builds on. It owns the
-- settings accessors, verbose logging, the player registry and the action
-- registry that the cron module schedules against.
--
-- NOTE: the server-side triggerEvent implementation is a Java binding with a
-- fixed arity of 3 arguments (eventName, arg1, arg2). Do not call triggerEvent
-- with more than 3 arguments or it will throw at runtime on the server.
local tools = require("PhunServer2/tools")

PhunServer2 = {
    name = "PhunServer2",
    inied = false,
    tools = tools,
    settings = {},
    ui = {},
    -- data.online[username] = { online, lastSeen, firstSeen }
    data = {
        online = {}
    },
    -- Registered schedulable actions, keyed by name. See registerAction below.
    actions = {},
    -- Registered chat commands, keyed by lowercase name. See registerCommand.
    cmds = {},
    const = {
        modDataName = "PhunServer2"
    },
    events = {
        OnReady = "OnPhunServer2Ready",
        OnPlayerJoined = "OnPhunServer2PlayerJoined",
        OnPlayerRejoined = "OnPhunServer2PlayerRejoined",
        OnPlayerLeft = "OnPhunServer2PlayerLeft",
        OnEmptyServer = "OnPhunServer2EmptyServer",
        OnShutdownScheduled = "OnPhunServer2ShutdownScheduled",
        OnShutdownCancelled = "OnPhunServer2ShutdownCancelled"
    },
    commands = {
        playerSetup = "playerSetup",
        notify = "notify",
        message = "message",
        quit = "quit",
        restart = "restart",
        cancelRestart = "cancelRestart"
    }
}

local Core = PhunServer2

Core.isLocal = tools.isLocal

for _, event in pairs(Core.events) do
    if not Events[event] then
        LuaEventManager.AddEvent(event)
    end
end

-- ---------------------------------------------------------------------------
-- SETTINGS
-- ---------------------------------------------------------------------------

-- Reads a sandbox option under an explicit prefix. Every module owns its own
-- sandbox namespace (PhunServer2Cron.Foo, PhunServer2Chat.Bar and so on), so
-- module code uses optionGetter below rather than calling this directly.
function Core.getOptionFor(prefix, name, default)
    local options = getSandboxOptions()
    if not options then
        return default
    end
    local opt = options:getOptionByName(prefix .. "." .. name)
    local val = opt and opt:getValue()
    if val == nil then
        return default
    end
    return val
end

-- Core's own options live under the PhunServer2 prefix.
function Core.getOption(name, default)
    return Core.getOptionFor(Core.name, name, default)
end

-- Returns a getOption bound to a module's sandbox prefix:
--   local getOption = Core.optionGetter("PhunServer2Cron")
--   getOption("EnableCron", true)
function Core.optionGetter(prefix)
    return function(name, default)
        return Core.getOptionFor(prefix, name, default)
    end
end

function Core.refreshSettings()
    Core.settings = SandboxVars[Core.name] or {}
    Core.settings.Verbose = Core.getOption("Verbose", false)
end

Core.refreshSettings()

-- ---------------------------------------------------------------------------
-- LOGGING
-- One switch, PhunServer2.Verbose, shared by every module. Modules pass their
-- own name so the log line identifies the source.
-- ---------------------------------------------------------------------------

function Core.verboseLn(str, moduleName)
    if Core.settings.Verbose then
        print("[" .. (moduleName or Core.name) .. "] " .. tostring(str))
    end
end

function Core.verbose(...)
    if Core.settings.Verbose then
        tools.debug(...)
    end
end

-- Always printed, regardless of Verbose. For things an admin must see.
function Core.logLn(str, moduleName)
    print("[" .. (moduleName or Core.name) .. "] " .. tostring(str))
end

-- Returns a verboseLn bound to a module name.
function Core.logger(moduleName)
    return function(str)
        Core.verboseLn(str, moduleName)
    end
end

-- ---------------------------------------------------------------------------
-- ACTION REGISTRY
--
-- Modules register named actions; the cron module schedules them and its admin
-- UI builds its action picker from this table. A new module gains scheduling
-- support simply by registering here.
--
--   Core.registerAction("shutdown", {
--       label   = "IGUI_PhunServer2_Action_Shutdown",
--       fields  = { notice = { type = "int", default = 5 } },
--       handler = function(job, args) ... end,
--   })
-- ---------------------------------------------------------------------------

function Core.registerAction(name, definition)
    if not name or type(definition) ~= "table" or type(definition.handler) ~= "function" then
        Core.logLn("registerAction ignored: '" .. tostring(name) .. "' needs a handler function")
        return
    end
    definition.name = name
    Core.actions[name] = definition
    Core.verboseLn("Registered action '" .. name .. "'")
end

function Core.hasAction(name)
    return Core.actions[name] ~= nil
end

-- Runs a registered action. Errors are contained so one bad job cannot take
-- down the tick loop that dispatched it.
function Core.runAction(name, job, args)
    local action = Core.actions[name]
    if not action then
        Core.logLn("No such action '" .. tostring(name) .. "'")
        return false
    end
    local ok, err = pcall(action.handler, job, args or {})
    if not ok then
        Core.logLn("Action '" .. tostring(name) .. "' failed: " .. tostring(err))
        return false
    end
    return true
end

-- ---------------------------------------------------------------------------
-- CHAT COMMAND REGISTRY
--
-- The /command hook itself lives in core (client_chat_commands.lua) so that
-- any module's commands work without the PhunServer2Commands mod installed.
-- Modules register from a client-side file:
--
--   Core.registerCommand("restart", {
--       admin   = true,
--       handler = function(args) ... end,   -- see the hook for return values
--   })
-- ---------------------------------------------------------------------------

function Core.registerCommand(name, definition)
    if not name or type(definition) ~= "table" or type(definition.handler) ~= "function" then
        Core.logLn("registerCommand ignored: '" .. tostring(name) .. "' needs a handler function")
        return
    end
    definition.name = name
    Core.cmds[string.lower(name)] = definition
end

-- ---------------------------------------------------------------------------
-- INIT
-- ---------------------------------------------------------------------------

function Core:ini()
    if self.inied then
        return
    end
    self.inied = true

    Core.refreshSettings()
    Core.verboseLn("Initialising core...")

    if not isClient() then
        self.serverStarted = getTimestamp()
        self.started = self.serverStarted
        self.pendingShutdown = false
        self.shuttingDown = false
        -- Nobody is connected yet, whatever the persisted state claims
        for _, v in pairs(Core.data.online or {}) do
            v.online = false
        end
    end

    triggerEvent(self.events.OnReady, self)
end

return PhunServer2
