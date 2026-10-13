# PhunServer 2

Server tools for multiplayer Project Zomboid (Build 42), split into independent
mods so a server only loads what it actually uses.

This is a rewrite of PhunServer 1. It drops the PhunLib dependency, drops B41
support, drops the map features that B42 now provides natively, and adds a
scheduler and admin diagnostics.

## Modules

| Mod id | Folder | What it does |
| --- | --- | --- |
| `phunserver2` | `PhunServer2` | Required by all the others. Shared plumbing, verbose logging, player tracking, chat primitives, shutdown machinery, the action and command registries, and [diagnostics](Docs/diagnostics.md). |
| `phunserver2cron` | `PhunServer2Cron` | Scheduled jobs on the real-world clock or the game clock. Includes ModWatch as a `modcheck` action. |
| `phunserver2commands` | `PhunServer2Commands` | `/players`, `/hours`, `/sethours`. |
| `phunserver2chat` | `PhunServer2Chat` | Join and leave announcements, username highlighting, music and radio tidying. |
| `phunserver2daynight` | `PhunServer2DayNight` | Independent day and night speeds. |
| `phunserver2wiper` | `PhunServer2Wiper` | Map and symbol wipes. Off by default. |

Only `phunserver2` is mandatory. Mod-update restarts and nothing else:

```
Mods=phunserver2;phunserver2cron
```

## Documentation

| Page | Covers |
| --- | --- |
| [Docs/cron.md](Docs/cron.md) | The cron job file, timing, actions, and ModWatch's Steam and `WorkshopItems=` requirements. |
| [Docs/commands.md](Docs/commands.md) | Every chat command, who can use it, and why none of them work from the console or RCON. |
| [Docs/diagnostics.md](Docs/diagnostics.md) | `/diag`: the client and server square probe, Map health, and the check that runs at every server start. |
| [Docs/migrating.md](Docs/migrating.md) | Moving from PhunServer 1: the old-to-new settings table and behaviour changes. |
| [Tests/lua/README.md](Tests/lua/README.md) | The offline test suites. |

Every sandbox setting has an in-game tooltip, so these pages do not repeat
them.

## Shutdowns, not restarts

PhunServer never restarts your server. Whether it comes from `/restart`, a cron
job or ModWatch, a shutdown stops the server cleanly; bringing it back up (and
thereby letting Steam apply mod updates) is your host's or service manager's
job.

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

`workshop.txt` is the release Workshop page and `Tests/workshop.txt` the dev
one. Steam caps the description at 8000 characters, so long-form material
belongs in `Docs/` with a link from the Workshop page.

## Tests

```
..\PhunTestKit\run.cmd
```

Offline suites for the JSON layer, the config envelope, cron job loading,
player tracking and Map health, run against a Lua runtime cut down to what
B42.20.4 actually offers. The harness itself lives in the sibling
[PhunTestKit](../PhunTestKit) repo so it stays out of the mod repos. See
[Tests/lua/README.md](Tests/lua/README.md).
