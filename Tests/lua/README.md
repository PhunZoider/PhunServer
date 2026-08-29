# Lua tests

Offline tests for the parts of PhunServer2 that can be exercised without the
game: JSON encoding and decoding, the file layer on top of it, the versioned
config envelope, and cron job loading.

The harness lives in a separate repo, [PhunTestKit][kit], so it stays out of the
mod repos and does not drift between them. Nothing here is deployed —
`deploy.cmd` copies only `Contents\mods\*` and removes `Tests` from the workshop
staging folders outright.

[kit]: ../../../PhunTestKit

## Running

```
..\PhunTestKit\run.cmd
```

One suite at a time:

```
..\PhunTestKit\run.cmd . cron
```

It needs LuaJIT, because Project Zomboid is Lua 5.1 and the difference is not
cosmetic:

```
winget install --id DEVCOM.LuaJIT --source winget
```

The kit's README covers the rest: what the harness stands in for, what it takes
away, and how to write a suite.

## The suites

| File              | Covers                                                                        |
| ----------------- | ----------------------------------------------------------------------------- |
| `test_json.lua`   | `json.lua` — round trips, pretty printing, stable key order, refusals, decoding |
| `test_config.lua` | `tools.lua` and `server_config.lua` — the file layer, legacy detection, the version envelope |
| `test_cron.lua`   | `server_jobs.lua` and `schedule.lua` — seeding, the seeding guard, normalisation |

## Why these exist

B42.20.4 removed `loadstring`, `load` and `loadfile`. The config files used to
be Lua source read back through `loadstring`, and the failure mode was silent:
`loadstring` is simply nil, so the file reads back as nil, the mod carries on
with its defaults, and the next save writes them over the admin's settings.

The harness makes those globals raise, so reintroducing one fails here rather
than in someone's server. Three behaviours are pinned deliberately, and a future
change might mistake any of them for a bug:

- **Encoding refuses a non-string key rather than coercing it.** JSON object
  keys are strings. A number key written out as a string comes back as a string,
  so the next lookup by number misses it and quietly creates a second record
  beside the first. Refusing loses nothing; coercing loses it slowly.
- **`saveTable` validates before opening the writer.** `getFileWriter`
  truncates on open, so checking afterwards would mean replacing a good file
  with an empty one. `test_config.lua` asserts the file is byte-identical after
  a refused save.
- **Cron will not seed defaults while an unconverted `.txt` is present.**
  Seeding would create a `.json`, which stops `loadConfig` ever reporting the
  problem again — the server would then run the default job set while the admin
  believes their own jobs are live. Running nothing is the honest outcome, and
  the warning repeats every start until the file is converted or removed.
