# PhunServer 2

Server tools for multiplayer Project Zomboid (Build 42), split into independent
mods so a server only loads what it actually uses.

This is a rewrite of PhunServer 1. It drops the PhunLib dependency, drops B41
support, drops the map features that B42 now provides natively, and adds a
scheduler.

## Modules

| Mod id | Folder | What it does |
| --- | --- | --- |
| `phunserver2` | `PhunServer2` | Required by all the others. Shared plumbing, verbose logging, player tracking, chat primitives, shutdown machinery, and the action and command registries. |
| `phunserver2cron` | `PhunServer2Cron` | Scheduled jobs on a real-world clock. Includes ModWatch as a `modcheck` action. |
| `phunserver2commands` | `PhunServer2Commands` | `/players`, `/hours`, `/sethours`. |
| `phunserver2chat` | `PhunServer2Chat` | Join and leave announcements, username highlighting, music and radio tidying. |
| `phunserver2daynight` | `PhunServer2DayNight` | Independent day and night speeds. |
| `phunserver2wiper` | `PhunServer2Wiper` | Map and symbol wipes. Off by default. |

Only `phunserver2` is mandatory. Mod-update restarts and nothing else:

```
Mods=phunserver2;phunserver2cron
```

## Cron job format

Jobs live in `<Zomboid>/Lua/PhunServer2Cron.json`. If the file is missing it is
created with a five minute mod-update check, matching PhunServer 1's default.

```json
{
  "version": 1,
  "data": {
    "nightly-restart": {
      "enabled": true,
      "action": "shutdown",
      "args": { "notice": 15 },
      "at": ["03:00", "15:00"],
      "days": ["mon", "tue", "wed", "thu", "fri", "sat", "sun"],
      "announcements": [
        { "before": 1800, "text": "Server restarts in half an hour" }
      ]
    },
    "modwatch": {
      "enabled": true,
      "action": "modcheck",
      "every": 5,
      "everyUnit": "minutes"
    }
  }
}
```

### Timing

A job uses exactly one of two modes.

| Field | Mode | Meaning |
| --- | --- | --- |
| `at` | clock | List of `HH:MM` times, server local. |
| `every` + `everyUnit` | interval | `minutes`, `hours` or `days`. |
| `days` | both | Optional filter: `mon` … `sun`. Omit for every day. |
| `startTime` / `endTime` | interval | Optional window. Windows may wrap past midnight. |
| `runIfEmpty` | both | `false` skips the job when nobody is online. |
| `announcements` | both | `{ before = <seconds>, text = "…" }`, sent ahead of the job. |

`at` is when the job's **effect** lands, not when it starts. A `shutdown` at
`03:00` with `notice = 15` begins its countdown at 02:45, so the server is
genuinely down at 03:00. Actions declare this via `leadSeconds`.

### Actions

| Action | Provided by | Args |
| --- | --- | --- |
| `shutdown` | core | `notice` (minutes), `runIfEmpty` |
| `announce` | core | `text` |
| `modcheck` | cron | none |
| `event` | cron | `event` (Lua event name to fire) |

Other mods add their own with `PhunServer2.registerAction(name, definition)`.
Registered actions automatically become schedulable and will appear in the
admin UI when that ships.

Edit the file and run `/cron reload` to pick up changes without a restart.

### Why JSON and not Lua

B42.20.4 removed `loadstring`, `load` and `loadfile`, so a config file that is
Lua source can no longer be read back. The failure is silent — `loadstring` is
just nil, so the file reads as empty and the mod carries on with its defaults.

If you already have a `PhunServer2Cron.txt` from an earlier build, convert it at
<https://phunzoider.github.io/PhunZones/converter/> (browser only, nothing is
uploaded) and save the result beside it as `PhunServer2Cron.json`. Until you do,
cron says so on every start and **runs no jobs at all**, rather than seeding
defaults over a config you still believe is live.

The converter takes data tables only. A config containing actual Lua
expressions has to be rewritten by hand.

## Commands

| Command | Access | Provided by |
| --- | --- | --- |
| `/restart <minutes?>` | admin | core |
| `/cancelrestart` | admin | core |
| `/check` | admin | cron |
| `/cron reload` | admin | cron |
| `/players` | per setting | commands |
| `/hours <username?>` | per setting | commands |
| `/sethours <username?> <n>` | admin | commands |
| `/wipemap <username\|all>` | admin | wiper |

The `/command` hook lives in core, so each module's commands work whether or
not `phunserver2commands` is installed.

## Map wiping is never implicit

Erasing a map cannot be undone, so three rules make it impossible to wipe
someone by accident:

1. `EnableWipe` defaults to **false**.
2. The first time the module sees a player it records the current wipe key as
   their baseline and does **not** wipe. Only a key that changes afterwards
   wipes. Installing mid-season is therefore safe.
3. `/wipemap` gives admins a deliberate, immediate wipe when they do want one.

## Building

`deploy.cmd` copies every module into `%USERPROFILE%\Zomboid\mods`, builds the
`*Test` variants by overlaying `Tests\root`, and stages both Workshop uploads.
`.vscode/settings.json` runs it on save via the `emeraldwalk.runonsave`
extension.

`Tests/root/<Mod>/common/mod.info` carries the `*test` mod ids so a dev build
can sit alongside a release build in one install.

## Tests

```
..\PhunTestKit\run.cmd
```

Offline suites for the JSON layer, the config envelope and cron job loading,
run against a Lua runtime cut down to what B42.20.4 actually offers. The
harness itself lives in the sibling [PhunTestKit](../PhunTestKit) repo so it
stays out of the mod repos. See [Tests/lua/README.md](Tests/lua/README.md).

## Migrating from PhunServer 1

Remove `phunserver` from your `Mods` line and add the modules you want.
`phunlib` is no longer required by any of them.

Settings do not carry over — sandbox options moved to per-module names.
The mapping table is in `workshop.txt`.

Notable behaviour changes:

- `Debug` is now `Verbose`, and it is a single switch shared by every module.
- Map wiping is off by default and never wipes on first sight of a player.
- Day and night changes are server-authoritative; clients no longer compute
  their own transitions.
- `NightOffset` and `DayOffset` accept negative values, which the v1 tooltips
  advertised but the option ranges disallowed.
- Players-on-map is gone. Use `MapRemotePlayerVisibility` in your server ini.
