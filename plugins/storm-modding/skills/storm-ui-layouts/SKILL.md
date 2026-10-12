---
name: storm-ui-layouts
description: >-
  Heroes of the Storm UI layout XML (.StormLayout frames, templates, anchors, constants, asset and
  property binds, animations, state groups), DescIndex order, font styles, overriding built-in
  frames such as GameUI, and observer or replay interfaces built with Galaxy-Observer-UI. USE FOR:
  adding or fixing UI in a map, mod or .StormInterface. DO NOT USE FOR: dialogs created from
  Galaxy (galaxy-script) or document wiring (storm-mod-structure).
license: MIT
---

# Storm UI layouts

Layouts are XML files that declare UI frames. The game reads them from a document's
`Base.StormData/UI/Layout/` folder through one index file, then applies every document in
dependency order, so a mod or interface can both add frames and edit the built-in HUD.

## Rules

- **Start from the game's own layouts.** Every frame path, template and constant you reference
  must exist in the build you target. Read them from the base UI dump (below) or extract them
  from CASC (`casc-game-files`). Never guess a frame path.
- **Never edit a locked file's frames or templates.** Files with `<DescFlags val="Locked"/>` (all
  `Common/Standard*.StormLayout`, `Glue/ObserverOptionsPanel.StormLayout`, 276 descs in 2.57)
  cannot be edited. `GameUI.StormLayout` and the hero and map-mechanic layouts are not locked.
- **Expect each patch to break built-in frame paths.** Re-dump the base UI after a patch and check
  every `file=`/`template=` you use against it.
- **Don't commit the game's layouts** into a mod repo except the few you override, and say which
  build they came from.

## Where things live

| Thing | Path inside a document (folder or archive) |
| --- | --- |
| Layout index (the `uiui` component) | `Base.StormData/UI/Layout/DescIndex.StormLayout` |
| Your layouts | `Base.StormData/UI/Layout/*.StormLayout` (any subfolder) |
| Font styles (the `font` component) | `Base.StormData/UI/FontStyles.StormStyle`, locale overrides in `<loc>.StormData/LocalizedData/FontStyles.StormStyle` |
| Asset aliases for `@` texture refs | `Base.StormData/GameData/Assets.txt` (`UI/MyIcon=Assets\Textures\my_icon.dds`) |
| Text for `@` text refs | `<loc>.StormData/LocalizedData/GameStrings.txt` |
| Textures, models, cutscenes | `Base.StormAssets/Assets/Textures/*.dds` (maps and mods) or `Base.StormData/Assets/...` (interfaces) |

`ComponentList.StormComponents` must list the index and the styles:

```xml
<DataComponent Type="uiui">UI/Layout/DescIndex.StormLayout</DataComponent>
<DataComponent Type="font">UI/FontStyles.StormStyle</DataComponent>
```

The `uiui` path is relative to `Base.StormData`.

## DescIndex and include order

```xml
<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<Desc>
    <Include path="UI/Layout/MyConstants.StormLayout"/>
    <Include path="UI/Layout/MyPanel.StormLayout"/>
</Desc>
```

- Include paths may be relative to `Base.StormData` or to the document root
  (`Base.StormData/UI/Layout/...`). Blizzard files mix `<Include>` and `<include>`.
- **Order matters.** A file that uses `#MyConstant` or `template="MyTemplates/X"` must come after
  the file that defines it. Galaxy-Observer-UI's builder reorders and rewrites the index for you
  (`repairLayoutOrder`); by hand, put constants and templates first.
- `requiredtoload="IS_PTR|DEBUG|..."` on an `<Include>` makes it conditional. Blizzard uses it;
  you rarely need it.

## Frames

```xml
<Desc>
    <Constant name="MyPanelWidth" val="420"/>

    <!-- A new top-level frame is also a template other files can use as "MyPanel/RunPanelTemplate". -->
    <Frame type="Frame" name="RunPanelTemplate">
        <Width val="#MyPanelWidth"/>
        <Height val="96"/>
        <Frame type="Image" name="Background">
            <Anchor relative="$parent"/>
            <Texture val="@UI/MyPanelBackground"/>
        </Frame>
        <Frame type="Label" name="Title">
            <Anchor side="Top" relative="$parent" pos="Min" offset="8"/>
            <Anchor side="Left" relative="$parent" pos="Min" offset="12"/>
            <Style val="@StandardTooltipHeader"/>
            <Text val="@UI/MyPanelTitle"/>
        </Frame>
    </Frame>

    <!-- Edit the built-in HUD: file= names the layout that declared the frame (no extension). -->
    <Frame type="GameUI" name="GameUI" file="GameUI">
        <Frame type="Frame" name="UIContainer/FullscreenUpperContainer/MyRunPanel" template="MyPanel/RunPanelTemplate">
            <Anchor side="Top" relative="$parent" pos="Min" offset="120"/>
            <Anchor side="Right" relative="$parent" pos="Max" offset="-20"/>
        </Frame>
    </Frame>
</Desc>
```

- `type` is the native frame class (`Frame`, `Image`, `Label`, `Button`, `ProgressBar`, ...; HotS
  adds HUD classes such as `UnitStatusFrame`, `HeroLeaderPanel`, `CommandButton`). `name` is
  unique among siblings and may be a `/` path when editing.
- `template="File/Frame"` copies a top-level frame of another layout file (file base name, no
  extension). Templates chain.
- `file="X"` edits a frame that layout X declared, instead of making a new one. Children you
  declare inside are added or, if the name exists, merged.
- An anchor names `side` (`Top|Bottom|Left|Right`), `relative` (a frame reference), `pos`
  (`Min|Mid|Max`) and `offset`. One `<Anchor relative="$parent"/>` with no side fills the parent.
  Enum values are matched without case in Blizzard files (`side="left"`, `pos="MId"` exist).

## Values and references

| Form | Meaning |
| --- | --- |
| `#Name` | a `<Constant name="Name">` from any loaded layout (`##`, `###`: race and console-skin variants) |
| `@Key` | an asset: texture fields resolve through `Assets.txt`, text fields through `GameStrings.txt`, style fields name a font style, hotkeys go through `GameHotkeys.txt` |
| `@@Key`, `@@@Key` | race and console-skin suffixed assets |
| `{$sel/@Prop}` | live binding to another frame's property: `<Text val="{$parent/@AccountLevel}"/>` |
| plain | a literal, or a raw path relative to the document root (`_Assets\Textures\x.dds`) |

Frame references: `$this`, `$parent`, `$root`, `$layer`, `$sibling+1`, `$ancestor[@type=X]`, and
custom handles declared with `<Handle val="Name"/>` used as `$Name`. Segments join with `/`
(`\` works too). GameData XML has its own `$` constants (`<const id="$X">`); don't mix them up.

## Animations and states

- `<Animation name>` holds `<Event event="OnShown" action="Reset,Play"/>` triggers and
  `<Controller type="Fade|Visibility|Anchor|Dimension|Texture|...">` with `<Key time value>`
  curves.
- `<StateGroup name>` holds `<DefaultState val>` and `<State name>` with `<When type="Property|
  AnimationState|StateGroup|Option">` conditions and `<Action type="SetProperty|SetAnchor|
  SendEvent|SetState|ApplyTemplate|PlaySound">` effects.

These are how the HUD reacts without Galaxy code. The full element and attribute census of the
2.57 base UI is in [references/layout-reference.md](references/layout-reference.md).

## From Galaxy

A layout frame is only a declaration until the game shows it. Map code drives custom UI with the
dialog natives (`DialogCreate`, `DialogControlCreateFromTemplate(dialog, c_triggerControlTypePanel,
"MyPanel/RunPanelTemplate")`, `DialogControlHookup`/`DialogControlHookupStandard` for built-in
frames, `DialogControlSetVisible`, `libNtve_gf_SetDialogItemText`). See `galaxy-script`.

## Observer and replay interfaces

An interface is a document whose `DocumentInfo` says `<ModType><Value>Interface</Value></ModType>`.
It carries only UI (layouts, styles, assets, strings), no triggers or game data.

- Install: `%USERPROFILE%\Documents\Heroes of the Storm\Interfaces\<Name>.StormInterface`.
- Select: Options > Observer has two pulldowns, "Observer Interface" and "Replay Interface". It
  applies to observing and replays, not to a player's own game (inferred from the options layout).
- Build: [Galaxy-Observer-UI](https://github.com/Ahli/Galaxy-Observer-UI) (Java 21, Spring Boot +
  JavaFX). Name the source folder `X.StormInterface`; `--compile="<folder>"` builds it,
  `--compileRun` also starts the most recent replay through `Support64\HeroesSwitcher_x64.exe`,
  `--noGUI` runs headless. It validates every layout against the base UI (missing constants,
  unknown templates, edits to locked files), minifies the XML (its "protection") and packs an MPQ
  v3 archive with MPQ Editor (16 KiB sectors, no `(attributes)`, bzip2/zlib per file).
- AhliObs (`dev/heroes/AhliObs.StormInterface`) is the reference interface. Its `_Config.StormLayout`
  shows the `@Hotkey`/`@Setting` comment convention the end-user Settings Editor reads; keep those
  comments when minifying.

## Base UI dump

Galaxy-Observer-UI commits the game's layouts per patch under `baseUI/heroes/mods/` (2.57.0.98304
at the time of writing): `core.stormmod/base.stormdata/UI/Layout/{Common,UI,Glue,HomeScreens,
LoadingScreens}`, `heroesdata.stormmod`, `heromods/<hero>.stormmod`, map mods, and Try Mode's own
`TryMeMode.StormLayout`. Use it to look up frame paths and templates. Key files to override:
`UI/GameUI.StormLayout` (root `GameUI`), `UI/ObserverPanel.StormLayout`,
`UI/StormObserverPanel.StormLayout`. For a newer build, dump again with its `CascExtractor` or
`hots-casc-game-files` (regex `\.StormLayout$`).

A map can also replace a layout by path, without listing it in DescIndex: Heroes Rogue ships
`UI/Layout/LoadingScreens/CursedHollow_Loading.StormLayout` at the path the map's `MapInfo` names,
and `UI/Layout/UI/GameMenuDialog.StormLayout` to change the game menu.

## Editor support

[sc2-layouts](https://github.com/Talv/sc2-layouts) (VS Code, `talv.sc2layouts`) gives completion,
template and constant checks, but it registers only `.SC2Layout` and finds only SC2-named folders.
For `.StormLayout` map the extension in `files.associations` and expect HotS-only frame types to
be flagged. Its diagnostics ("Could not find template", "Undeclared constant", "Child
redeclared", case mismatch warnings) match what breaks in game.

## When a layout does not show

1. Is the file in `DescIndex.StormLayout`, after everything it uses?
2. Is `uiui` in `ComponentList.StormComponents`?
3. Does every `file=`/`template=` path exist in this build's base UI, and is the target unlocked?
4. Is the XML well formed (one bad file can drop the whole index)? Run `storm-mod-structure`'s
   `Test-StormDocument.ps1` on the document folder; it also checks every DescIndex include.
5. For runtime dialogs: was the control created from the template and made visible for the right
   player group?
