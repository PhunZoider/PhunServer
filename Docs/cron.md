# Cron and ModWatch

`phunserver2cron` runs jobs on the real-world clock or the game clock:
shutdowns, announcements, mod-update checks, PhunZones profile changes, or any
Lua event. ModWatch is one of those jobs.

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
      "announcements": [
        { "before": 1800, "text": "Server restarts in half an hour" }
      ]
    },
    "modwatch": {
      "enabled": true,
      "action": "modcheck",
      "every": 5,
      "everyUnit": "minutes"
    },
    "happy-hour": {
      "enabled": true,
      "action": "announce",
      "args": { "text": "Loot respawn is boosted for the next hour" },
      "at": ["20:00"],
      "days": ["fri"]
    }
  }
}
```

Edit the file and run `/cron reload` to pick up changes without a restart.

### Timing

A job uses exactly one of four modes.

| Field | Mode | Meaning |
| --- | --- | --- |
| `at` | clock | List of `HH:MM` times, server local. |
| `every` + `everyUnit` | interval | `minutes`, `hours` or `days`. |
| `on` | phase | `dawn` and/or `dusk`, in game time. See below. |
| `gameAt` | game clock | List of `HH:MM` times on the in-game clock. See below. |
| `days` | all | Optional filter: `mon` to `sun` (real-world day). Omit for every day. |
| `startTime` / `endTime` | interval | Optional window. Windows may wrap past midnight. |
| `onStart` | phase | `false` stops the job running for the phase the server boots into. |
| `runIfEmpty` | all | `false` skips the job when nobody is online. |
| `announcements` | clock, interval | `{ "before": <seconds>, "text": "..." }`, sent ahead of the job. |

`at`, `on` and `gameAt` take either a list or a single string.

`at` is when the job's **effect** lands, not when it starts. A `shutdown` at
`03:00` with `notice: 15` begins its countdown at 02:45, so the server is
genuinely down at 03:00. Actions declare this via `leadSeconds`.

### Dawn and dusk

`on` jobs run at in-game dawn and dusk instead of on the real-world clock. A
typical use is switching a PhunZones profile when night falls:

```json
"night-zones": {
  "enabled": true,
  "action": "zoneprofile",
  "on": ["dusk"],
  "args": { "profile": "night" }
},
"day-zones": {
  "enabled": true,
  "action": "zoneprofile",
  "on": ["dawn"],
  "args": { "profile": "none" }
}
```

Dawn and dusk come from **PhunServer 2: Day/Night** (`phunserver2daynight`),
which has to be enabled. It follows the season, and its `DayOffset` /
`NightOffset` sandbox options shift the times when its day/night speed change
is on. Without it, `on` jobs never run and cron logs a warning at load.

When the server starts, the jobs for the phase it boots into run once, so a
restart at night still puts the night profile in place. Set `"onStart": false`
on jobs that should only run on an actual transition, such as an announcement.

`on` jobs can't have `announcements`. How many real seconds are left until
dawn depends on day length, speed changes and pauses, so there's no reliable
countdown to announce against.

### Game clock

`gameAt` jobs run when the in-game clock reaches a time, however fast your
days run:

```json
"curfew": {
  "enabled": true,
  "action": "zoneprofile",
  "gameAt": ["22:00"],
  "args": { "profile": "curfew" }
}
```

The clock is checked every in-game minute, and a job runs when its time has
passed since the last check. A short day length that skips a minute can't make
a job miss its time. A paused game doesn't advance the clock, so nothing runs
while paused.

Unlike `on` jobs, a `gameAt` job does **not** run when the server starts. A
game time is a single moment, and a restart shouldn't replay one that has
already passed. If something must be right after a restart, drive it from
`on` instead, or pair it with a second job.

Like `on`, `gameAt` can't have `announcements`. `days` still filters on the
real-world weekday, not the in-game one.

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

### Why JSON and not Lua

B42.20.4 removed `loadstring`, `load` and `loadfile`, so a config file that is
Lua source can no longer be read back. The failure is silent: `loadstring` is
just nil, so the file reads as empty and the mod carries on with its defaults.

If you already have a `PhunServer2Cron.txt` from an earlier build, convert it at
<https://phunzoider.github.io/PhunZones/converter/> (browser only, nothing is
uploaded) and save the result beside it as `PhunServer2Cron.json`. Until you do,
cron says so on every start and **runs no jobs at all**, rather than seeding
defaults over a config you still believe is live.

The converter takes data tables only. A config containing actual Lua
expressions has to be rewritten by hand.

## ModWatch

ModWatch asks Steam whether any of your workshop mods have been published since
this server booted, and schedules a restart when they have. It runs as the
`modcheck` cron action, so its cadence is a job like any other. A fresh install
gets one every five minutes.

ModWatch is heavily inspired by the excellent
[Udderly Up To Date](https://steamcommunity.com/sharedfiles/filedetails/?id=2844315442).

### It needs Steam, and it needs `WorkshopItems=`

Two server-side requirements, both of which are easy to miss on a dedicated
server and neither of which PhunServer can work around:

1. **The server has to be running with Steam enabled.** Started with `-nosteam`
   (or without `-Dzomboid.steam=1`), the engine returns no workshop data at all
   and ModWatch cannot function.
2. **Your mods' workshop ids have to be in `WorkshopItems=` in the server ini.**
   `Mods=` alone is not enough. On a dedicated server the engine only knows
   about workshop items *it* installed at boot, so mods placed on disk by hand,
   by SteamCMD, or by a hosting panel are invisible to any update check,
   including vanilla's own `checkModsNeedUpdate` console command.

If either is unmet, ModWatch says so explicitly in the server log on every poll
rather than looking like it is working. Run `/check` as an admin to poll on
demand and get the answer in chat.

### It stops the server, it does not restart it

ModWatch, like every PhunServer shutdown, only ever *stops* the server.
Bringing it back up, and thereby letting Steam apply the updates, is your
host's or service manager's job.
