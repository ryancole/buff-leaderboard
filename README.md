# Buff Leaderboard

WoW TBC Anniversary (2.5.6, Interface 20506) addon that tracks external buffs
cast on you by other players and keeps a persistent per-character leaderboard
of who has given you the most, across sessions.

## Files

- `BuffLeaderboard.toc` — addon manifest (must stay at the repo root — WoW
  looks for it at the top of the addon folder)
- `src/Spells.lua` — default tracked buffs, seeded into SavedVariables on
  first run; after that the user-managed list is authoritative
- `src/Core.lua` — SavedVariables, combat log handler, slash commands
- `src/Leaderboard.lua` — the in-game leaderboard window (`/blb`)
- `src/MinimapButton.lua` — minimap button that toggles the leaderboard window
- `src/Options.lua` — settings panel (Options -> AddOns -> Buff Leaderboard)

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

## Releasing

Releases are built by the [BigWigs packager](https://github.com/BigWigsMods/packager)
via GitHub Actions (`.github/workflows/release.yml`). Pushing a tag like
`v0.2.0` packages the addon (with `@project-version@` in the .toc replaced
by the tag) and uploads it to CurseForge using the `CF_API_KEY` repo secret
and the `## X-Curse-Project-ID` in the .toc.

```bash
git tag v0.2.0 && git push origin master --tags
```

## Commands

- `/blb` — toggle the leaderboard window (the minimap button does the same;
  drag it to move it around the minimap rim, or hide it in the settings panel)
- `/blb dump` — all casters and their per-buff counts
- `/blb dump session` — this session only
- `/blb dump <buff name>` — the all-time ladder for one buff
- `/blb track <name or spell id>` — add a buff to the tracked list
- `/blb untrack <name>` — remove a buff from the tracked list
- `/blb options` — open the settings panel
- `/blb prune confirm` — forget casters not seen in the last 90 days (the
  settings panel's "Prune Inactive" button does the same)
- `/blb reset confirm` — wipe this character's data

With the auto-reply option enabled, other players can whisper you `!rank`
for their rank on every buff ladder they appear on, or `!rank <buff name>`
(e.g. `!rank innervate`) for a single buff. Each reply is a ladder excerpt
showing the #1 caster plus the players one spot above and below the sender,
e.g. `Innervate: #1 Moonpriest (x50) ... #4 Baddruid (x12), #5 you (x10),
#6 Weakdruid (x9)`. All rankings are per-buff; there is no combined
leaderboard.
