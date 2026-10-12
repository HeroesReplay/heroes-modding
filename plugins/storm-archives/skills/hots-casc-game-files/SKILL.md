---
name: hots-casc-game-files
description: >-
  Read the installed Heroes of the Storm game data (CASC, product hero, MNDX root) without
  changing it: list and extract the built-in maps, mods, catalogs, Galaxy libraries, layouts and
  strings by path with a TACTLib-based .NET tool, and diff two builds. USE FOR: getting Blizzard's
  current files to start from, check against, or diff after a patch. DO NOT USE FOR: MPQ archives
  (storm-mpq-archives) or writing to the install.
license: MIT
compatibility: scripts/casc.cs needs the .NET 10 SDK and a clone of overtools/TACTLib next to it; Windows install of the game.
---

# Heroes game files (CASC)

The game keeps its data in a CASC store under `<game>\HeroesData` (`data\data.NNN` blobs, `.idx`
indexes, `config\`). Every file has a path; there are about 1.2 million on 2.57.0.98348. Mods are
folder trees inside it, not archives (`storm-mod-structure` lists the important ones).

## Rules

- **Read only. Never write into `HeroesData`.** Battle.net repairs it, and CascLib's author notes
  that editing it breaks Blizzard's terms. Mods go in loose folders (`hots-custom-game-mode`).
- **Extract into a work folder and never commit what you extract.** It is Blizzard's content;
  commit your diffs and notes, regenerate the files locally.
- **Paths:** package folders are lowercase (`mods/heroesdata.stormmod/base.stormdata/`), names
  under them keep their case (`TriggerLibs/GameLib.galaxy`). Match with case-insensitive regexes.

## The tool

`scripts/casc.cs` is a .NET 10 single-file program on [TACTLib](https://github.com/overtools/TACTLib)
(MIT). TACTLib is not on NuGet, so the script references a clone:

```powershell
mkdir C:\work\casc; cd C:\work\casc
copy <skill>\scripts\casc.cs .
git clone https://github.com/overtools/TACTLib.git
git -C TACTLib checkout 129f977b604b2576bfd048e0f2be8b44ee983f39   # the commit this was checked with
$game = 'C:\Program Files (x86)\Heroes of the Storm'

dotnet run casc.cs -- info    $game                       # build and entry count
dotnet run casc.cs -- list    $game 'TriggerLibs/.*\.galaxy$'
dotnet run casc.cs -- extract $game '^mods/heroes\.stormmod/base\.stormmaps/maps/heroes/singleplayermaps/startingexperience/tutorialveteran\.stormmap/' .\out
```

Checked on 2026-10-12 against 2.57.0.98348: 1,208,637 entries; the stock Veteran map extracts
(75 files on an enUS-only install, the other locales' text is not downloaded) and loads into
`New-HotsMod.ps1`.

TACTLib details that bite: its only constructor is `new ClientHandler(path, new ClientCreateArgs
{ Product = "hero" })`; the default product is `"pro"` (Overwatch). Names come from
`ProductHandler_MNDX.Entries` (`Path`, `Locale`, content key) and `OpenFile(entry)` returns null for
data not resident locally. TACTLib targets net9.0 and builds with only a `git describe` step.

## Paths worth knowing

| Regex | What you get |
| --- | --- |
| `^mods/core\.stormmod/base\.stormdata/TriggerLibs/` | `NativeLib.galaxy`, `natives.galaxy` (constants), `NativeLib.TriggerLib` (native signatures, for `galaxy-script`'s `Get-GalaxyNatives.ps1`) |
| `^mods/heroesdata\.stormmod/base\.stormdata/TriggerLibs/` | the Heroes libraries (`HeroesLib`, `GameLib`, `UILib`, `MapMechanicsLib`, `AILib`, `SoundLib`, `StartingExperienceLib`, `GameDataHelperLib`, `SupportLib`, with `_h` headers) |
| `^mods/heroesdata\.stormmod/base\.stormdata/GameData/` | core catalogs (`BehaviorData.xml`, `EffectData.xml`, `HeroData.xml`, `TalentData.xml`, ...) |
| `^mods/heromods/anduin\.stormmod/` | one hero's mod: `GameData.xml` and its catalogs, layouts, libraries |
| `^mods/heroes\.stormmod/base\.stormmaps/maps/heroes/singleplayermaps/` | the four replaceable single-player maps |
| `^mods/heroesmapmods/battlegroundmapmods/` | battleground map mods (data and libraries such as `LibMTOD`) |
| `\.StormLayout$` | every UI layout (the base UI for `storm-ui-layouts`) |
| `enus\.stormdata/LocalizedData/GameStrings\.txt$` | English strings per mod |
| `DepotCache/.*\.s2ma$` | depot archives (MPQ; open with `storm-mpq-archives`) |

The battleground maps themselves are not in this store as folders; they are `.s2ma` MPQ archives
in `C:\ProgramData\Blizzard Entertainment\Battle.net\Cache\` (identify one by its
`DocInfo/Name`, see `storm-mpq-archives`).

## Diff two builds

1. Extract the same regex from each build into `build-<old>\` and `build-<new>\`. The store
   serves the installed build, so extract before Battle.net patches the game.
2. `git diff --no-index build-<old> build-<new>` over the XML, Galaxy and layout trees.
3. Most useful folders: `heroesdata.stormmod/base.stormdata/GameData`, `.../TriggerLibs`,
   `core.stormmod/base.stormdata/UI/Layout`, and the hero mods you touch.

TACTLib can also open a build's data from the CDN (`ClientCreateArgs.OverrideBuildConfig`,
`Online`), but whether old Heroes builds are still served is not checked.

## How the store works (for when the tool breaks)

```
path --(root: MNDX, three name tries: packages, names in a package, full names)--> content key (MD5)
content key --(encoding file)--> encoded key
encoded key[0..9) --(bucket = xor fold)--> data\XX*.idx --> (data.NNN, offset, size)
data.NNN at offset: 30-byte header, then BLTE (chunks: N plain, Z zlib, E encrypted, 4 LZ4, F frame)
```

`.build.info` (pipe-separated, `Name!TYPE:size` header) names the active build and CDN config; on
this install its Product column is empty and TACTLib picks the single active row. Product codes:
`hero` retail, `herot` PTR, `heroc` tournament realm.

## Other readers

CascLib (C++, MIT) and its read-only GUI CascView (`CascView.exe "<game>\HeroesData"`) are the
battle-tested alternative; `storm-extract` (Node, on CascLib) is what Try Mode 2.0 uses;
Galaxy-Observer-UI ships a `CascExtractor.exe` for layouts.
