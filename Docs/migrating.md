# Migrating from PhunServer 1

1. Remove `phunserver` from your `Mods` line.
2. Add `phunserver2` and whichever modules you want (see the
   [module list](../README.md#modules)).
3. `phunlib` is no longer required by any of them. Remove it unless another mod
   needs it.
4. Re-enter your settings. They do not carry over, because the sandbox options
   moved to per-module names.

## Settings

| PhunServer 1 | PhunServer 2 |
| --- | --- |
| `PhunServer.Debug` | `PhunServer2.Verbose` |
| `PhunServer.RefreshSettingsOnStartup` | `PhunServer2.RefreshSettingsOnStartup` |
| `PhunServer.NotificationCountdown` | `PhunServer2.NotificationCountdown` |
| `PhunServer.NotificationChime` | `PhunServer2.NotificationChime` (now a 0-100 volume) |
| `PhunServer.QuitDelaySeconds` | `PhunServer2.QuitDelaySeconds` |
| `PhunServer.EnableModWatch` | `PhunServer2Cron.EnableModWatch` |
| `PhunServer.RestartDelayMinutes` | `PhunServer2Cron.RestartDelayMinutes` |
| `PhunServer.WorkshopPollingIntervalMinutes` | The `every` value on the `modwatch` job, see [cron.md](cron.md) |
| `PhunServer.PlayersCommand` | `PhunServer2Commands.PlayersCommand` |
| `PhunServer.PlayersOffline24` | `PhunServer2Commands.PlayersOffline24` |
| `PhunServer.GetHours` / `SetHours` | `PhunServer2Commands.GetHours` / `SetHours` |
| `PhunServer.WelcomeAnnounce` and friends | `PhunServer2Chat.*` |
| `PhunServer.EnableDayNightChange` and friends | `PhunServer2DayNight.*` |
| `PhunServer.EnableWipeMap` | `PhunServer2Wiper.EnableWipe` (now defaults to off) |
| `PhunServer.WipeKey` / `WipeMap` / `WipeSymbols` / `WipePerCharacter` | `PhunServer2Wiper.*` |
| `PhunServer.PlayersOnMap` / `PlayersOnMiniMap` / `PlayersUpdateMs` | Removed. Use `MapRemotePlayerVisibility` in your server ini. |

## Behaviour changes

- `Debug` is now `Verbose`, and it is a single switch shared by every module.
- The shutdown chime is a 0-100 volume rather than a tickbox. 0 is silent.
- Map wiping is off by default and never wipes on first sight of a player.
- Day and night changes are server-authoritative; clients no longer compute
  their own transitions.
- `NightOffset` and `DayOffset` accept negative values, which the v1 tooltips
  advertised but the option ranges disallowed.
- Players-on-map is gone. Use `MapRemotePlayerVisibility` in your server ini.
- B41 is no longer supported, and the map features B42 now provides natively
  are gone.
