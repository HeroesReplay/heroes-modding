---
name: storm-mod-structure
description: >-
  Anatomy of Heroes of the Storm .stormmap, .StormMod and .StormInterface documents as folders or
  MPQ archives: ComponentList, DocumentInfo dependencies, includes.xml mod injection, GameData.xml,
  the game's own mods, and loose-file overrides in the install folder. Has a linter. USE FOR:
  creating, inspecting, wiring or validating a map or mod. DO NOT USE FOR: Galaxy code
  (galaxy-script), catalog entries (storm-data-xml), MPQ internals (storm-mpq-archives).
license: MIT
compatibility: The linter needs PowerShell 7 (pwsh).
---

# Storm documents: maps, mods and interfaces

Every Storm container is the same tree in one of two forms: an MPQ archive, or that archive
unpacked as a folder whose name keeps the extension (`MyMod.StormMod/`). The extension says the
role. The game loads both forms. Ship folders while you develop; pack an archive only when you
need one file (see "Packing").

## Rules

- **Start from a real document of the current build.** Copy a Blizzard map (extract it from CASC,
  `hots-casc-game-files`) or a working community one (Try Mode 2.0, Heroes Rogue). Keep its binary
  files (`DocumentHeader`, `MapInfo`, `t3*`, `CellAttribute_*`, `*.version`) as they are; don't
  try to author them.
- **Don't commit Blizzard files you did not change.** A mod repo holds your files plus the few
  Blizzard files you override, each with the build it came from.
- **Run the linter before every test**: `pwsh -File scripts/Test-StormDocument.ps1 <folder>`.
  A malformed XML file or a missing include usually shows in game only as "map script error".

## File types

| Extension | Role | Form |
| --- | --- | --- |
| `.stormmap` | Playable map: terrain, objects, regions, `MapScript.galaxy`, data, text | folder or MPQ |
| `.stormmod` / `.StormMod` | Dependency mod: data, Galaxy libraries, UI, assets, text; no terrain | folder or MPQ |
| `.StormInterface` | Observer/replay UI only (`ModType=Interface`), in `Documents\Heroes of the Storm\Interfaces\` | MPQ |
| `.StormReplay` | Replay (`storm-replay-format`) | MPQ with a user-data header |
| `.s2ma` | A map or mod stored by content hash (`DepotCache/` in CASC, `C:\ProgramData\Blizzard Entertainment\Battle.net\Cache\`) | MPQ |
| `.StormLayout`, `.StormStyle`, `.StormCutscene`, `.StormComponents` | UI layout, font styles, cutscene, component list | XML |

The StarCraft II names are the same with `SC2` (`.SC2Map`, `.SC2Mod`, `.SC2Layout`, `Base.SC2Data`).
Nested `*.SC2Mod` files inside Heroes documents are SC2 Editor projects kept as source, not loaded.

## Inside a document

```
MyThing.stormmap/ or .StormMod/
  ComponentList.StormComponents   XML: which components exist and where (below)
  DocumentInfo                    XML <DocInfo>: Dependencies, ModifiableDependencies, Icon, Preload
  DocumentHeader                  binary "Hero" header: dependencies + cached DocInfo strings (maps)
  MapInfo                         binary: tileset, loading-screen layout, players (maps only)
  MapScript.galaxy                the map's script; the engine calls InitMap() (maps only)
  Triggers                        XML: the editor's trigger source (editor-only; can be a stub)
  Objects, Regions, Attributes    XML: placed units/doodads/points, regions, lobby variants (maps)
  t3Terrain.xml, t3*, CellAttribute_*   terrain and pathing (maps)
  BankList.xml                    banks the map may load: <Bank Name="PlayerSettings" Player="1"/>
  Preload.xml, PreloadAssetDB.txt preload hints
  *.version                       editor bookkeeping (40-44 bytes per component); not required to load
  Base.StormData/
    GameData.xml                  <Includes><Catalog path="GameData/X.xml"/></Includes>
    GameData/*.xml                data catalogs (storm-data-xml)
    GameData/Assets.txt           Key=Assets\Textures\x.dds aliases for @ references
    includes.xml                  mod injection (below)
    *.galaxy, TriggerLibs/...     Galaxy libraries (galaxy-script)
    UI/Layout/DescIndex.StormLayout, UI/FontStyles.StormStyle   (storm-ui-layouts)
    AI/*.aitree, Cutscenes/*
  <locale>.StormData/LocalizedData/GameStrings.txt (+ ObjectStrings, TriggerStrings)
  Base.StormAssets/Assets/{Textures,Models,Anims,Sounds}/...
```

A loose mod loads with only `ComponentList.StormComponents`, `DocumentInfo` and `Base.StormData`
(Heroes Rogue's mod has no `DocumentHeader` and no `.version` files). Folders named `(listfile)` and
`(attributes)` in an extracted map are MPQ leftovers; the game ignores them as loose files.

### ComponentList.StormComponents

```xml
<?xml version="1.0" encoding="us-ascii"?>
<Components>
    <DataComponent Type="gada">GameData</DataComponent>
    <DataComponent Type="text" Locale="enUS">GameText</DataComponent>
    <DataComponent Type="info">DocumentInfo</DataComponent>
    <DataComponent Type="trig">Triggers</DataComponent>
    <DataComponent Type="uiui">UI/Layout/DescIndex.StormLayout</DataComponent>
    <DataComponent Type="font">UI/FontStyles.StormStyle</DataComponent>
</Components>
```

Maps add `mapi` MapInfo, `terr` t3Terrain.xml, `plob` Objects, `regi` Regions, `attr` Attributes
and `cuts` Cutscenes/Index. Add one `text` line per locale you ship. `uiui` and `font` paths are
relative to `Base.StormData`.

## Dependencies

`DocumentInfo` names what the document builds on, one `<Value>` each:

```xml
<DocInfo>
    <Dependencies>
        <Value>bnet:Heroes of the Storm (Data Mod)/0.0/999,file:Mods/HeroesData.StormMod</Value>
    </Dependencies>
    <ModifiableDependencies>
        <Value>Mods/HeroesData.StormMod</Value>
    </ModifiableDependencies>
</DocInfo>
```

- Form: `bnet:<published name>/<major.minor>/<id>,file:<path from the game root>`. Battleground maps
  depend on their map mod, for example
  `bnet:Cursed Hollow (Mod)/0.0/1497,file:Mods\heroesmapmods/battlegroundmapmods/cursedhollow.stormmod`,
  which pulls in `HeroesData.StormMod` and through it `Core`, `Heroes` and the hero mods.
- A map's `DocumentHeader` repeats its dependencies in binary. Changing `<Dependencies>` cleanly
  would mean regenerating that header, so don't; use `includes.xml` instead.
- Paths and separators are matched without case (`Mods\HeroesMapMods\...` and `mods/heroesmapmods/...`
  both load), but write canonical casing (`Mods/HeroesData.StormMod`).

### Injecting your mod: includes.xml

A map adds a mod to one of its `ModifiableDependencies` without touching `DocumentHeader`:

```xml
<!-- MyMap.stormmap/Base.StormData/includes.xml -->
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Includes id="Mods/HeroesData.StormMod">
    <Path value="Mods/MyMod.StormMod"/>
</Includes>
```

`id` must be one of the map's `ModifiableDependencies`; each `<Path value>` is resolved from the
game root, which covers both CASC mods and loose `<install>\mods\MyMod.StormMod` (Heroes Rogue
relies on that; Try Mode 2.0's comment: "Include Mods here without Modify DocumentHeader Binary").
Your mod is loaded as part of that dependency's layer, after it, so same-id data entries and
same-path files in your mod win (inferred from Heroes Rogue shadowing Blizzard's libraries).

### Two different "Includes" files

| File | Root | Children | Paths relative to | Purpose |
| --- | --- | --- | --- | --- |
| `Base.StormData/GameData.xml` | `<Includes>` | `<Catalog path="GameData/X.xml"/>` | this document's `Base.StormData` | register data files with non-standard names |
| `Base.StormData/includes.xml` | `<Includes id="Mods/...">` | `<Path value="Mods/X.StormMod"/>` | the game root | add mods to a dependency |

Standard catalog names (`GameData/UnitData.xml`, `ActorData.xml`, ...) load without being listed;
anything else (`GameData/HeroData/Illidan.xml`, `GameData/AffixData.xml`) must be in `GameData.xml`.

## The game's own documents

Inside CASC (`hots-casc-game-files`) every mod is a folder tree of single files, not an archive.
Folder names are lowercase (`base.stormdata`, `enus.stormdata`); names below them keep their case
(`TriggerLibs/GameLib.galaxy`). Checked on 2.57.0.98348:

| Path | What |
| --- | --- |
| `mods/core.stormmod/base.stormdata/` | Engine base: `TriggerLibs/NativeLib*.galaxy`, `natives.galaxy` (constants only), `NativeLib.TriggerLib` (the native signatures), core UI layouts, `DepotCache/xx/<sha256>.s2ma` |
| `mods/heroes.stormmod/` | Shared assets per locale (`*.stormassets`) and the four single-player maps under `base.stormmaps/maps/heroes/singleplayermaps/` |
| `mods/heroesdata.stormmod/base.stormdata/` | Heroes data (`GameData/`) and libraries (`TriggerLibs/HeroesLib`, `GameLib`, `UILib`, `MapMechanicsLib`, `AILib`, ...) |
| `mods/heromods/HERO.stormmod/` | One per hero |
| `mods/heroesmapmods/battlegroundmapmods/MAP.stormmod`, `MAPdata.stormmod` | One pair per battleground (the map mods, not the maps) |
| `mods/heroesbrawlmods/`, `mods/gameplaymods/` | Brawls, gameplay variants |

The battleground maps themselves are not folders in CASC: they are MPQ archives (`.s2ma`) in
`DepotCache` and the Battle.net cache, found by content hash (`storm-replay-format` shows how a
replay names them). The four built-in single-player maps are folders:
`(10)trymemode.stormmap` (Try Mode) and, under `startingexperience/`, `tutorial01.stormmap`,
`tutorialmapmechanics.stormmap` and `tutorialveteran.stormmap` ("Heroes of the Storm Veteran
Challenges", the in-game Challenges). Replacing them is `hots-custom-game-mode`.

## Loose files in the install folder

- `<install>\maps\...` overlays `mods/heroes.stormmod/base.stormmaps/maps/...` (Try Mode 2.0's
  INSTALL.md). A folder or an archive at the same relative path replaces the built-in map.
- `<install>\mods\<Name>.StormMod` is found as `Mods/<Name>.StormMod` by `includes.xml` and
  `file:` dependencies (Heroes Rogue ships its mod this way).
- No launch flag, `Variables.txt` setting or developer option is needed. Restart the client after
  the first install; later edits are read on the next map load.
- Battle.net updates leave these folders alone, so a stale override keeps loading after a patch.

## Packing

You rarely need to. If you do:

- Tools: Ladik's MPQ Editor (`MPQEditor.exe`, Windows; console: `n ARCHIVE MAXFILES`,
  `a ARCHIVE FOLDER "" /r`, `compact ARCHIVE`; Try Mode's CI does `new`, `add ... /r`, `close`), or
  StormLib directly (`storm-mpq-archives`). That skill's `mpq.cs pack` writes a format-1 archive
  with zlib sectors, `(listfile)` and `(attributes)`; it round-trips with its reader, but the game
  has not been shown to load it yet.
- Settings known to work: MPQ format 3, 16 KiB sectors, zlib or bzip2 per file, `(listfile)`
  present (Galaxy-Observer-UI). **Never LZMA**: the game crashes loading it.
- Pack the folder's contents at the archive root (not the folder itself), and delete extracted
  `(listfile)`/`(attributes)` files before re-packing.

## Validate

```powershell
pwsh -NoProfile -File scripts/Test-StormDocument.ps1 "<path>\MyMod.StormMod"
pwsh -NoProfile -File scripts/Test-StormDocument.ps1 "<path>\maps" -Recurse   # every document under a folder
```

It checks that every XML file parses, `ComponentList` targets exist, dependency values have the
`bnet:...,file:...` form, `GameData.xml` catalogs and `DescIndex` includes exist,
`GameStrings.txt` is `Key=Value` UTF-8 with a BOM and no duplicate keys, and that Galaxy `include`s
resolve inside the document (includes of `TriggerLibs/...` and other game libraries are listed as
external, not errors). Exit code 1 means errors.
