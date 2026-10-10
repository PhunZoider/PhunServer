# Diagnostics

Admin tools for the question "why is the world not what it should be". They are
part of core (`phunserver2`), so there is no extra mod id to add. Everything
here is read only and limited to admins and moderators, checked on both the
client and the server.

## Commands

| Command | What it does |
| --- | --- |
| `/diag` | Probe the square you are standing on. |
| `/diag <x> <y> <z?>` | Probe any square on the map. `z` defaults to 0. |
| `/diag health` | Check every map in `Map=`: is it installed, and did its zones load? |

All three open the same window. It has `x`, `y`, `z` boxes, a **Here** button
to fill them with your position, **Probe** to probe them, and **Map health**.
Like every PhunServer command these are in-game chat only (see
[commands.md](commands.md#they-are-in-game-chat-commands-only)).

## The square probe

The client and the server each read the same list of facts about one square,
and the window shows them side by side. Any field that differs is drawn in red.

Side by side is the point. A dedicated server keeps state a client never loads,
chiefly the save (zones live in `map_zone.bin`), so the two can disagree about
the same square while each looks healthy on its own. Both sides run the same
reader code, so a difference always comes from what each side holds, never from
two implementations drifting apart.

What it reports:

- **Square and cell:** whether the square is loaded, and which 256x256 cell it
  is in.
- **Building:** the room name, and whether the building is a map building, a
  player-built stand-in, or none. It reads this both from the square and from
  the map grid, and shows the map building's basement flag.
- **Power:** grid power, has electricity, and every reason a square can have no
  power (derelict room, player-built room, `NoPower` zone), listed separately
  because the engine's own "no power" flag does not say which.
- **World:** power grid exists, hydro on, `ElecShutModifier`, world day.
- **Cell:** room count, map buildings against player-built buildings, and where
  the player-built ones are, so you can walk into one and probe it.
- **Zones:** every zone on the square at level 0, not just the one the engine
  reports first.

The server only loads squares near players, so for a square nobody is standing
on the square-level fields say `(square not loaded)`. Zones, buildings and cell
counts come from the meta grid and still answer.

A cell with rooms but no map buildings gets a warning under the table: its
buildings were dropped when the map list loaded, and Map health names the cause.

In single player both columns read the same world, so they always agree.

## Map health

Map health exists for two silent failures, both met on a real server.

1. **A `Map=` entry whose mod is not active.** Missing, disabled, or missing one
   of its own requirements: the game still counts it when it hands out map
   priorities, so every map after it in the list, vanilla included, discards
   its own buildings. The region system replaces each house with a player-built
   stand-in, which never takes grid power. Symptoms: no roof cutaway, no power
   indoors.
2. **One bad entry in a map's `objects.lua`.** Vanilla loads zones from the
   last map in `Map=` to the first with no error handling, so a throw in one
   map's file leaves every map earlier in the list with no zones at all: no
   `NoPower` zones, no spawn points, no parking.

For each map the check looks for its `map.info`, re-reads its `objects.lua`,
and asks the meta grid whether the last plain zone in that file exists. It
samples the last zone rather than the first so that a file which throws partway
through reports itself rather than the next map.

| Status | Meaning |
| --- | --- |
| `present` | The sampled zone loaded. |
| `missing` | The sampled zone is not in the world. |
| `broken` | The file's first zone loaded and its last did not: it threw partway through itself. |
| `not installed` | Listed, but no `map.info` on disk. |
| `no objects.lua` / `no sample` | Nothing to check. Not a fault by itself. |
| `error: ...` | The check itself failed for this map. |

It runs on both sides, and comparing them tells two faults apart:

- **Missing on both:** a broken map file. Moving that map to the front of
  `Map=` limits the loss to itself.
- **Missing on the server only:** the server restored its zones from a save
  written before those maps were added, which happens when a map is added to an
  existing world. A restart does not rebuild `map_zone.bin`.

### At server start

The server runs Map health once per boot, after the world has loaded.

- **Healthy:** it logs nothing. A line every boot saying all is well is how a
  log stops being read.
- **Problems:** it logs each one as a `MAP HEALTH:` line, and the first time
  each admin or moderator joins that boot, the Diagnostics window opens for them
  with the server's result and their own client's check beside it.

Probes also carry the boot result, so a probe of a healthy square still says
when the map list is not.
