-- json.lua on a runtime cut down to what PZ B42.20.4 offers.
--
-- Run: ..\PhunTestKit\run.cmd . json

local kit = require "phuntestkit"
local check = kit.check

kit.installGlobals()
kit.addMod("PhunServer2")

local json = require "PhunServer2/json"

-- Everything past here runs without loadstring, load, loadfile or next.
kit.strip()

---------------------------------------------------------------------------
check.section("round trips")

local function roundTrip(name, value, pretty)
    local encoded, encErr = json.encode(value, pretty)
    if not encoded then
        return check.ok(name, false, "encode: " .. tostring(encErr))
    end
    local decoded, decErr = json.decode(encoded)
    if decErr then
        return check.ok(name, false, "decode: " .. tostring(decErr) .. "  <<" .. encoded .. ">>")
    end
    return check.equal(name, decoded, value)
end

roundTrip("empty table", {})
roundTrip("flat object", {
    a = 1,
    b = "two",
    c = true,
    d = false
})
roundTrip("array", {1, 2, 3})
roundTrip("array of objects", {{
    before = 1800,
    text = "half an hour"
}, {
    before = 60,
    text = "one minute"
}})
roundTrip("nested", {
    version = 1,
    data = {
        job = {
            enabled = true,
            at = {"03:00", "15:00"},
            args = {
                notice = 15
            }
        }
    }
})
roundTrip("negatives and fractions", {
    offset = -3,
    ratio = 0.25,
    big = 1234567
})

-- The escape pattern is [%z\1-\31\\"], which is Lua 5.1 only. If this suite is
-- ever run on 5.2+ the pattern raises rather than failing an assert, which is
-- the loudest possible way to be told the runtime is wrong.
roundTrip("control characters and quotes", {
    text = 'line\nbreak\ttab "quoted" back\\slash' .. string.char(0)
})
roundTrip("keys needing escapes", {
    ["a.b"] = 1,
    ["with space"] = 2,
    ["with\"quote"] = 3
})

---------------------------------------------------------------------------
check.section("pretty printing")

local sample = {
    version = 1,
    data = {
        modwatch = {
            enabled = true,
            every = 5
        }
    }
}

local compact = json.encode(sample)
local pretty = json.encode(sample, true)

check.ok("compact output is one line", not compact:find("\n", 1, true))
check.ok("pretty output is not", pretty:find("\n", 1, true) ~= nil)
check.ok("pretty output indents", pretty:find("\n  \"", 1, true) ~= nil)
roundTrip("pretty output decodes to the same table", sample, true)
check.equal("both forms decode alike", json.decode(pretty), json.decode(compact))

check.same("empty object stays compact when pretty", json.encode({
    -- an empty Lua table is indistinguishable from an empty array, and the
    -- encoder resolves it as an array. Pinned because the file layer writes
    -- these and a change of mind here would alter every seeded config.
}, true), "[]")

---------------------------------------------------------------------------
check.section("stable output")

-- pairs() order is not stable between runs. Saving an unchanged config must
-- not produce a different file, or every save shows up as a diff.
local manyKeys = {}
for i = 1, 20 do
    manyKeys["key" .. i] = i
end
local first = json.encode(manyKeys)
local stable = true
for _ = 1, 20 do
    if json.encode(manyKeys) ~= first then
        stable = false
    end
end
check.ok("repeated encodes of one table match", stable)
check.ok("keys come out sorted", json.encode({
    b = 1,
    a = 2,
    c = 3
}) == '{"a":2,"b":1,"c":3}')

---------------------------------------------------------------------------
check.section("encoding refusals")

-- These are deliberate. A future change turning one back into a coercion would
-- lose data slowly rather than refusing loudly, so each is pinned.
local function refuses(name, value, mustMention)
    local encoded, err = json.encode(value)
    if encoded then
        return check.ok(name, false, "encoded anyway: " .. encoded)
    end
    if mustMention and not tostring(err):find(mustMention, 1, true) then
        return check.ok(name, false, "message did not mention '" .. mustMention .. "': " .. tostring(err))
    end
    return check.ok(name, true)
end

refuses("a number key", {
    [0] = "bad"
}, "number")
refuses("a number key, naming it", {
    [7] = "bad"
}, "7")
refuses("a boolean key", {
    [true] = "bad"
}, "boolean")
refuses("a function value", {
    f = print
}, "function")

local circular = {}
circular.self = circular
refuses("a circular table", circular, "circular")

refuses("infinity", {
    n = math.huge
}, "infinity")

---------------------------------------------------------------------------
check.section("decoding")

local function decodes(name, source, expected)
    local value, err = json.decode(source)
    if err then
        return check.ok(name, false, tostring(err))
    end
    return check.equal(name, value, expected)
end

decodes("whitespace everywhere", '  {  "a" : [ 1 , 2 ]  }  ', {
    a = {1, 2}
})
decodes("exponent notation", '{"n":1e3}', {
    n = 1000
})
decodes("negative fraction", '{"n":-0.5}', {
    n = -0.5
})
decodes("escaped unicode", '{"s":"\\u0041\\u00e9"}', {
    s = "A\195\169"
})
decodes("escaped solidus", '{"s":"a\\/b"}', {
    s = "a/b"
})
decodes("empty array and object", '{"a":[],"o":{}}', {
    a = {},
    o = {}
})

local function rejects(name, source)
    local value, err = json.decode(source)
    return check.ok(name, value == nil and err ~= nil, "got " .. tostring(value))
end

rejects("unterminated object", '{"a": ')
rejects("unterminated string", '{"a": "no end}')
rejects("trailing content", '{"a":1} and then some')
rejects("a bare comma", '{"a":1,,"b":2}')
rejects("an unquoted key", '{a:1}')
rejects("a bad unicode escape", '{"s":"\\uZZZZ"}')
rejects("a non-string input", nil)

---------------------------------------------------------------------------
check.finish()
