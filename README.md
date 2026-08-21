# Buff Leaderboard

WoW TBC Anniversary (2.5.6, Interface 20506) addon that tracks external buffs
cast on you by other players and keeps a persistent per-character leaderboard
of who has given you the most, across sessions.

## Files

- `BuffLeaderboard.toc` — addon manifest (must stay at the repo root — WoW
  looks for it at the top of the addon folder)
- `src/Spells.lua` — tracked-spell whitelist (all TBC ranks, per-spell refresh policy)
- `src/Core.lua` — SavedVariables, combat log handler, slash commands

## Developing

WoW loads an addon from a folder whose name matches the `.toc`, so link this
repo into your AddOns directory as `BuffLeaderboard` (PowerShell, adjust the
game path):

```powershell
New-Item -ItemType Junction `
  -Path "C:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns\BuffLeaderboard" `
  -Target "C:\Users\Ryan\source\repos\buff-leaderboard"
```

`/reload` in-game picks up Lua changes; a full restart is only needed for
`.toc` changes.

## Commands

- `/blb dump` — all-time leaderboard to chat
- `/blb dump session` — this session only
- `/blb reset confirm` — wipe this character's data
