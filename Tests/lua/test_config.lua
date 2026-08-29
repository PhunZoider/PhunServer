-- The file layer and the versioned config envelope, on a runtime cut down to
-- what PZ B42.20.4 offers.
--
-- These files used to be Lua source read back through loadstring. This suite
-- exists mainly so that never happens again: the harness makes loadstring raise,
-- so any reintroduction fails here rather than silently reading every admin's
-- config as nil in the game.
--
-- Run: ..\PhunTestKit\run.cmd . config

local kit = require "phuntestkit"
local harness, check = kit.harness, kit.check

kit.installGlobals()
kit.addMod("PhunServer2")

local Core = require "PhunServer2/core"
local tools = Core.tools
require "PhunServer2/server_config"

-- Everything past here runs without loadstring, load, loadfile or next.
kit.strip()

local SAMPLE = {
    ["nightly-restart"] = {
        enabled = true,
        action = "shutdown",
        args = {
            notice = 15
        },
        at = {"03:00", "15:00"},
        days = {"mon", "fri"},
        announcements = {{
            before = 1800,
            text = "Server restarts in half an hour"
        }}
    },
    modwatch = {
        enabled = true,
        action = "modcheck",
        every = 5,
        everyUnit = "minutes"
    }
}

---------------------------------------------------------------------------
check.section("the file layer")

harness.reset()

check.ok("saveTable reports success", tools.saveTable("Test.json", SAMPLE) == true)
check.ok("something was written", (harness.files["Test.json"] or "") ~= "")
check.ok("it is indented, not one long line", (harness.files["Test.json"] or ""):find("\n", 1, true) ~= nil)
check.equal("loadTable returns the same table", tools.loadTable("Test.json"), SAMPLE)

-- Saving an unchanged table must not churn the file, or every restart looks
-- like an edit in version control.
local firstWrite = harness.files["Test.json"]
tools.saveTable("Test.json", SAMPLE)
check.ok("re-saving the same table is byte identical", harness.files["Test.json"] == firstWrite)

check.ok("loadTable on a missing file is nil", tools.loadTable("Absent.json") == nil)
check.ok("saveTable with no data reports failure", tools.saveTable("Test.json", nil) == false)

harness.files["Broken.json"] = '{"unterminated": '
check.ok("malformed JSON reads as nil", tools.loadTable("Broken.json") == nil)

harness.files["Scalar.json"] = '"just a string"'
check.ok("a non-object JSON file reads as nil", tools.loadTable("Scalar.json") == nil)

harness.files["Empty.json"] = ""
check.ok("an empty file reads as nil", tools.loadTable("Empty.json") == nil)

---------------------------------------------------------------------------
check.section("a refused save leaves the file alone")

-- getFileWriter truncates on open, so validating after opening it would replace
-- a good file with an empty one. saveTable validates first; this pins that.
local before = harness.files["Test.json"]
check.ok("saveTable refuses an unencodable table", tools.saveTable("Test.json", {
    [0] = "a number key"
}) == false)
check.ok("the file on disk is untouched", harness.files["Test.json"] == before)
check.equal("and it still reads back correctly", tools.loadTable("Test.json"), SAMPLE)

---------------------------------------------------------------------------
check.section("the old Lua format")

harness.reset()

-- Exactly what a pre-B42.20.4 config file looks like.
harness.files["Test.txt"] = "return {\n  version = 1,\n  data = {\n    modwatch = { enabled = true },\n  },\n}"

check.ok("needsConversion spots a stranded .txt", tools.needsConversion("Test.json") == true)
check.ok("loadTable does not try to run it", tools.loadTable("Test.json") == nil)
check.same("legacyNameFor maps the extension", tools.legacyNameFor("Test.json"), "Test.txt")
check.same("legacyNameFor leaves other names alone", tools.legacyNameFor("Test.cfg"), "Test.cfg")

harness.files["Test.json"] = '{"version":1,"data":{"modwatch":{"enabled":true}}}'
check.ok("needsConversion stops once the .json is there", tools.needsConversion("Test.json") == false)

harness.reset()
check.ok("needsConversion is false when nothing exists at all", tools.needsConversion("Test.json") == false)

-- The reason this suite exists. If someone reintroduces loadstring, the harness
-- makes it raise and this fails, rather than the game reading every config as
-- nil and quietly overwriting it with defaults.
harness.files["Test.txt"] = "return { data = { modwatch = { enabled = true } } }"
local ok = pcall(tools.loadTable, "Test.json")
check.ok("reading a stranded .txt never reaches an interpreter", ok)

---------------------------------------------------------------------------
check.section("the version envelope")

harness.reset()

Core.saveConfig("Cfg.json", SAMPLE, 1, "TestModule")
local data, version, needsConversion = Core.loadConfig("Cfg.json", "TestModule")
check.equal("loadConfig returns the data half", data, SAMPLE)
check.same("and the version it was read at", version, 1)
check.ok("and no conversion needed", needsConversion == false)

Core.saveConfig("V2.json", SAMPLE, 2, "TestModule")
local _, v2 = Core.loadConfig("V2.json", "TestModule")
check.same("a later version round trips", v2, 2)

-- Written by hand without a version, which an admin editing the file might do.
harness.files["NoVersion.json"] = '{"data":{"modwatch":{"enabled":true}}}'
local d3, v3 = Core.loadConfig("NoVersion.json", "TestModule")
check.same("a missing version defaults to 1", v3, 1)
check.equal("and the data still comes through", d3, {
    modwatch = {
        enabled = true
    }
})

local d4, v4, n4 = Core.loadConfig("Absent.json", "TestModule")
check.ok("an absent file gives nil, nil, false", d4 == nil and v4 == nil and n4 == false)

-- Valid JSON, wrong shape: no data key. Must not be mistaken for a config.
harness.files["Wrong.json"] = '{"jobs":{"modwatch":{"enabled":true}}}'
local d5, _, n5 = Core.loadConfig("Wrong.json", "TestModule")
check.ok("an envelope with no data half is refused", d5 == nil and n5 == false)

harness.reset()
harness.files["Cfg.txt"] = "return { version = 1, data = {} }"
local d6, v6, n6 = Core.loadConfig("Cfg.json", "TestModule")
check.ok("a stranded .txt reports needsConversion", d6 == nil and v6 == nil and n6 == true)

---------------------------------------------------------------------------
check.section("backups")

harness.reset()
Core.backupConfig("Cfg.json", SAMPLE, "TestModule")
check.ok("backupConfig writes beside the original", (harness.files["Cfg_backup.json"] or "") ~= "")
check.equal("and the backup reads back", tools.loadTable("Cfg_backup.json"), SAMPLE)
check.ok("it does not leave a .txt behind", harness.files["Cfg_backup.txt"] == nil)

---------------------------------------------------------------------------
check.finish()
