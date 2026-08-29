if isServer() then
    return
end

local Core = require "PhunServer2/core"
local tools = Core.tools
local Commands = {}

Commands[Core.commands.notify] = function(args)
    Core.notifyAll(args.soundName, args.types, args.text, args.args, args.volume)
end

Commands[Core.commands.message] = function(args)
    -- Targeted messages carry the intended recipient so split-screen clients
    -- only render it for the player it was meant for.
    if args.username and not tools.getPlayerByUsername(args.username) then
        return
    end
    Core.message(args.text, args.args)
end

Commands[Core.commands.quit] = function(args)
    getCore():quit()
end

return Commands
