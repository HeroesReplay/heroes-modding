---
name: hots-custom-game-mode
description: >-
  Build a custom Heroes of the Storm game mode by replacing a built-in single-player map (Veteran
  Challenges by default, or Try Mode or a tutorial) with your own map plus mod, as Heroes Rogue
  does. Scripts scaffold the mod, patch the map and install or uninstall it. USE FOR: making,
  installing, testing or updating such a mode. DO NOT USE FOR: multiplayer or matchmaking changes,
  or editing the game's CASC data.
license: MIT
compatibility: Scripts need PowerShell 7 (pwsh) on Windows; the game must be installed to test.
---

# A custom game mode in a built-in slot

The game has four single-player maps inside `mods/heroes.stormmod/base.stormmaps/maps/` and lets
loose folders under `<game>\maps\` replace them. Put your own map at one of those paths, inject
your mod into it, and the in-game button that used to start the built-in map starts yours. No
launcher flag, no CASC edit, no injected code.

| Slot (folder under `<game>\maps\heroes\singleplayermaps\`) | Started from | Stock content |
| --- | --- | --- |
| `startingexperience\tutorialveteran.stormmap` | cog menu, Challenges, Play | "Heroes of the Storm Veteran Challenges" |
| `(10)trymemode.stormmap` | Try Mode from the hero collection | Try Mode |
| `startingexperience\tutorial01.stormmap` | the tutorial | Tutorial |
| `startingexperience\tutorialmapmechanics.stormmap` | the map-mechanics tutorial | Tutorial |

Heroes Rogue replaces all four with battlegrounds (Cursed Hollow in the Veteran slot), keeps its
logic in `<game>\mods\HeroesRogue.StormMod`, and moves between slots with `GameSetNextMap`.

## Rules

- **Single player, local files only.** Never write into `<game>\HeroesData` (CASC). Only these
  four slots and `<game>\mods\` are touched, and only by `Install-HotsMod.ps1`, which backs up
  whatever it replaces.
- **Blizzard's terms are not settled by any of these projects.** Heroes Rogue and Try Mode 2.0
  run locally and say nothing about anti-cheat. Tell the user that, and let them decide.
- **Uninstall to get the built-in mode back.** While installed, the replaced button starts your
  map.
- **In the HeroesReplay environment:** never install on the stream PC (DESKTOP-8SJEK72). On
  ASA-SERVER, test only while holding `C:\heroesreplay\asa-live.lock` (taken only while
  `C:\heroesreplay\asa-release-pending` does not exist), the same as any client launch.

## Workflow

1. **Get a map to start from.** The stock slot map is the safest start: extract
   `mods/heroes.stormmod/base.stormmaps/maps/heroes/singleplayermaps/startingexperience/tutorialveteran.stormmap/`
   with `hots-casc-game-files`. For a battleground (Heroes Rogue's approach) start from that
   battleground's map archive (`.s2ma` in the Battle.net cache, `storm-replay-format` shows how
   replays name it) unpacked with `storm-mpq-archives`; its `DocumentInfo` must list
   `Mods/HeroesData.StormMod` under `ModifiableDependencies`.
2. **Scaffold the mod and patch the map:**

   ```powershell
   pwsh -NoProfile -File scripts/New-HotsMod.ps1 -Name RogueLite -OutputPath C:\src\roguelite `
       -MapSource C:\casc\mods\heroes.stormmod\base.stormmaps\maps\heroes\singleplayermaps\startingexperience\tutorialveteran.stormmap
   ```

   It writes `mods\RogueLite.StormMod\` (ComponentList, DocumentInfo, Triggers stub, a
   `RogueLiteLib` library that says hello two seconds in, a data file, string file and UI index)
   and copies the map to `maps\...\tutorialveteran.stormmap\` with two changes:
   `Base.StormData\includes.xml` adds `Mods/RogueLite.StormMod` to `Mods/HeroesData.StormMod`, and
   `MapScript.galaxy` gets `include "RogueLiteLib"` and `libRogu_InitLib();`. On the 2.57 stock
   Veteran map that is a two-line script diff. `-Slot trymemode` targets Try Mode; `-LibId` sets
   the four-letter library id.
3. **Write the mode** in the mod: data (`storm-data-xml`), script (`galaxy-script`), UI
   (`storm-ui-layouts`). Keep the map's own files as they came; your changes live in the mod.
4. **Lint** with `storm-mod-structure`'s `Test-StormDocument.ps1`, giving it the mod so the map's
   `include "RogueLiteLib"` resolves:

   ```powershell
   pwsh -NoProfile -File Test-StormDocument.ps1 C:\src\roguelite\maps -Recurse -With C:\src\roguelite\mods\RogueLite.StormMod
   ```

   Warnings about missing non-enUS `GameStrings.txt` on a map extracted from an enUS-only install
   are expected.
5. **Install for a live edit loop:**

   ```powershell
   pwsh -NoProfile -File scripts/Install-HotsMod.ps1 -Source C:\src\roguelite -Link
   ```

   `-Link` makes directory junctions (no admin rights), so edits in your repo are what the game
   reads. Restart the client once after the first install; afterwards each start of the map reads
   the files again. Without `-Link` it copies. Writing into `C:\Program Files (x86)` may need an
   elevated shell; the script says so if access is denied.
6. **Play:** cog menu, Challenges, Play (or the slot you chose). "Map script error" means a Galaxy
   compile or run error: bisect by commenting out includes.
7. **Ship:** zip the `maps\` and `mods\` folders. Users extract them into the game folder (the
   Heroes Rogue way) or run `Install-HotsMod.ps1 -Source <unzipped>`.
8. **Uninstall:** `pwsh -NoProfile -File scripts/Install-HotsMod.ps1 -Uninstall` removes exactly
   what the manifest (`<game>\.hots-mods\manifest.json`) lists and restores backups.

## Mode patterns from Heroes Rogue

- **Runs across games:** save state in banks at the end of a game, load it at map init
  (`galaxy-script`, Banks). Heroes Rogue uses its own sections in Blizzard's `PlayerSettings`
  bank, which every stock map's `BankList.xml` already declares.
- **Map rotation:** `GameSetNextMap("heroes/singleplayermaps/startingexperience/tutorialveteran.stormmap");
  KickFromGame(PlayerGroupAll());`. Map paths are relative to the maps root, so other slots work too.
- **Content as data:** keep the list of upgrades (boons, curses, relics) in a `CUser` table and
  build their triggers from names in it (`storm-data-xml`).
- **Talent control:** `SetTalentsEnabled(false)` hides the normal talent UI; fill tree slots with
  empty talents and grant real ones with `PlayerAddTalent`.
- **Changing Blizzard behaviour:** add your trigger to Blizzard's generic events, or as a last
  resort ship a patched copy of a Blizzard library at the same path in your mod (it shadows the
  original, and must be redone every patch).

## Running a map without replacing a slot

`<game>\Support64\HeroesSwitcher_x64.exe "C:\full\path\MyMap.stormmap"` (or a path relative to
`<game>\maps\`) starts a map directly, but Try Mode 2.0 found that talents do not load this way.
Use a slot for anything players will use.

## Watching it run

`hots-client-observation` reads the running client without touching it: whether it shows the map
loading screen, a match, the score screen, and the last game-launch result. Launch results 4
(`GameLaunchMapOpenFailure`), 7 (`InvalidFiles`), 8 (`TooManyDependencies`), 16
(`ModDataMismatch`) and 17 (`MapDataMismatch`) point at a broken map or mod.

## After a game patch

1. Start the mode once; a "map script error" or missing UI means something moved.
2. Re-extract the stock slot map and re-run `New-HotsMod.ps1 -MapSource <new map> -Force`, so the
   map is the new build's plus your two lines. An existing mod folder is never rewritten, so your
   code is safe; `-MapSource` may also be the slot folder itself to re-apply the patch in place.
3. Diff every Blizzard file you shadow (libraries, layouts) against the new build and re-apply your
   edits.
4. Re-check the ids your data overrides against the new catalogs.

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| The built-in mode still starts | Wrong folder name or slot path; the client was not restarted after the first install |
| "Map script error" | Galaxy error; include order (`_h` headers first); a native that SC2 has and HotS lacks |
| Mod data ignored | `includes.xml` `id` is not in the map's `ModifiableDependencies`; the catalog file is not in `GameData.xml` |
| Text shows as a key | the key is missing from the client's locale `GameStrings.txt` |
| Texture missing | the `.dds` has mipmaps (UI textures need none) or a wrong path |
| Try Mode or tutorials changed | you installed into their slots; uninstall |
