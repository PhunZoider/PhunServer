-- Player tracking and the join/leave announcements built on it.
--
-- The case worth pinning is the departure. Core's leave event carries only a
-- username: by the time it fires the IsoPlayer is gone, so nothing can be asked
-- about them. Suppressing an admin's goodbye therefore depends on the access
-- level having been recorded while they were still connected.
--
-- Run: ..\PhunTestKit\run.cmd . players

local kit = require "phuntestkit"
local harness, check = kit.harness, kit.check

kit.installGlobals()
kit.addMod("PhunServer2")
kit.addMod("PhunServer2Chat")

local Core = require "PhunServer2/core"
require "PhunServer2/server_players"
local Chat = require "PhunServer2Chat/core"
require "PhunServer2Chat/server_events"

-- Everything past here runs without loadstring, load, loadfile or next.
kit.strip()

-- Core.data is normally handed over by ModData in core's server_events, which
-- this suite does not load: it would also install the tick handlers, and the
-- sweep is being driven by hand here.
local function freshServer()
    harness.reset()
    Core.data = {
        online = {}
    }
end

local function connect(username, accessLevel)
    harness.addPlayer(username, accessLevel)
    Core.checkPlayers()
end

local function disconnect(username)
    harness.removePlayer(username)
    -- A player is only counted as gone once they have been missing for more
    -- than a second, so the clock has to move past that gap.
    harness.now = harness.now + 2
    Core.checkPlayers()
end

--- Announcements sent since the last reset, as "command:username".
local function announced()
    local out = {}
    for _, c in ipairs(harness.serverCommands) do
        if c.module == Chat.name then
            out[#out + 1] = c.command .. ":" .. tostring(c.args and c.args[1])
        end
    end
    return out
end

---------------------------------------------------------------------------
check.section("access levels")

freshServer()
check.ok("an unknown username is not staff", Core.isStaff("nobody") == false)

connect("bob", "none")
check.ok("an ordinary player is not staff", Core.isStaff("bob") == false)

-- B42 roles report ordinary players by role name rather than "none".
for _, level in ipairs({"user", "User", "priority", "newuser", ""}) do
    freshServer()
    connect("pleb", level)
    check.ok("'" .. level .. "' is not staff", Core.isStaff("pleb") == false)
end

freshServer()
harness.sandbox["PhunServer2Chat.AnnounceAdmins"] = false
connect("roleuser", "user")
check.equal("a B42 'user' is still welcomed with admins hidden", announced(), {"welcomeFirstTime:roleuser"})

for _, level in ipairs({"admin", "moderator", "overseer", "gm", "observer"}) do
    freshServer()
    connect("staffer", level)
    check.ok("'" .. level .. "' counts as staff", Core.isStaff("staffer") == true)
end

freshServer()
connect("MiXeD", "Admin")
check.ok("the level is matched case insensitively", Core.isStaff("MiXeD") == true)

-- The whole point of recording it on the player record.
freshServer()
connect("amy", "admin")
disconnect("amy")
check.ok("staff status survives the disconnect", Core.isStaff("amy") == true)

---------------------------------------------------------------------------
check.section("announcements on, the default")

freshServer()
harness.sandbox["PhunServer2Chat.AnnounceAdmins"] = true

connect("bob", "none")
connect("amy", "admin")
disconnect("bob")
disconnect("amy")
check.equal("everyone is announced, coming and going", announced(),
    {"welcomeFirstTime:bob", "welcomeFirstTime:amy", "goodbye:bob", "goodbye:amy"})

---------------------------------------------------------------------------
check.section("announcements off for staff")

freshServer()
harness.sandbox["PhunServer2Chat.AnnounceAdmins"] = false

connect("bob", "none")
connect("amy", "admin")
check.equal("only the ordinary player is welcomed", announced(), {"welcomeFirstTime:bob"})

disconnect("amy")
check.equal("and the admin leaves quietly", announced(), {"welcomeFirstTime:bob"})

disconnect("bob")
check.equal("while the ordinary player still gets a goodbye", announced(),
    {"welcomeFirstTime:bob", "goodbye:bob"})

-- Returning players go down the rejoin path rather than the first-time one.
harness.serverCommands = {}
connect("amy", "admin")
check.equal("a returning admin is silent too", announced(), {})
harness.serverCommands = {}
connect("bob", "none")
check.equal("a returning player is welcomed back", announced(), {"welcome:bob"})

---------------------------------------------------------------------------
check.section("promotion mid session")

freshServer()
harness.sandbox["PhunServer2Chat.AnnounceAdmins"] = false

connect("carl", "none")
check.equal("carl is welcomed as an ordinary player", announced(), {"welcomeFirstTime:carl"})

harness.setAccessLevel("carl", "moderator")
harness.now = harness.now + 1
Core.checkPlayers()
check.ok("the promotion is picked up without reconnecting", Core.isStaff("carl") == true)

harness.serverCommands = {}
disconnect("carl")
check.equal("so his goodbye is suppressed", announced(), {})

---------------------------------------------------------------------------
check.section("the announcement switches still win")

freshServer()
harness.sandbox["PhunServer2Chat.AnnounceAdmins"] = true
harness.sandbox["PhunServer2Chat.WelcomeAnnounce"] = false
harness.sandbox["PhunServer2Chat.GoodbyeAnnouncements"] = false

connect("bob", "none")
disconnect("bob")
check.equal("nothing is said when both are off", announced(), {})

harness.sandbox["PhunServer2Chat.WelcomeAnnounce"] = true
harness.sandbox["PhunServer2Chat.GoodbyeAnnouncements"] = true

---------------------------------------------------------------------------
check.section("the roster sent to clients")

-- A client cannot work out who else is connected: getOnlinePlayers there covers
-- only its loaded cells. The server sends it this list so chat can recognise
-- usernames, which is why the contents matter rather than just the call.

freshServer()

connect("bob", "none")
connect("amy", "admin")
check.equal("lists everyone connected, sorted", Core.getOnlineUsernames(), {"amy", "bob"})

disconnect("bob")
check.equal("and drops a player who has gone", Core.getOnlineUsernames(), {"amy"})

-- A player's record is not marked online until after their join event has
-- fired, and the handshake that asks for this list can land inside that gap.
-- Read from data.online the roster would then leave the asker out of their own
-- copy, making them the one name nobody could highlight. Reading the live
-- player list is what avoids that, so the gap is what gets tested.
--
-- Registered last on purpose: the harness cannot unregister handlers, so this
-- would otherwise fire for every connect in the sections above.
local rosterAtJoin
Events[Core.events.OnPlayerJoined].Add(function(username)
    rosterAtJoin = Core.getOnlineUsernames()
end)

connect("carl", "none")
check.equal("and includes a joining player while their own join is still firing", rosterAtJoin, {"amy", "carl"})

---------------------------------------------------------------------------
check.finish()
