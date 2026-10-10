# Commands

| Command | Access | Provided by |
| --- | --- | --- |
| `/restart <minutes?>` | admin | core |
| `/cancelrestart` | admin | core |
| `/diag`, `/diag <x> <y> <z?>`, `/diag health` | admin | core, see [diagnostics.md](diagnostics.md) |
| `/check` | admin | cron |
| `/cron reload` | admin | cron |
| `/players` | per setting | commands |
| `/hours <username?>` | per setting | commands |
| `/sethours <username?> <n>` | admin | commands |
| `/wipemap <username\|all>` | admin | wiper |

"Admin" means admin or moderator.

`/restart` with no argument uses the ModWatch notice period
(`PhunServer2Cron.RestartDelayMinutes`).

The `/command` hook lives in core, so each module's commands work whether or
not `phunserver2commands` is installed.

## They are in-game chat commands only

None of these work from the server console or over RCON, and they cannot be
made to. The engine dispatches console and RCON input in Java, matching it
against a fixed list of built-in command classes and answering anything else
with `Unknown command`. There is no Lua hook on that path, so no mod can add a
command to it. Typing `/restart 1` into the console will always fail.

Run them from the in-game chat box as an admin instead. The vanilla console
equivalents worth knowing are `quit` (save and stop, no warning to players),
`save`, `servermsg "..."` and `checkModsNeedUpdate`.
