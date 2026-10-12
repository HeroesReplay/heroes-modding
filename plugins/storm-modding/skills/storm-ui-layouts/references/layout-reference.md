# Layout reference

Counts are from the Heroes of the Storm 2.57 base UI that Galaxy-Observer-UI dumps
(`baseUI/heroes`, about 24,800 frames). Use them to judge what is common and safe to copy.

## Element tree

```
Desc
 ├─ DescFlags val="Locked|Internal"
 ├─ RequiredDefines
 ├─ Include path="..." [requiredtoload="DEFINE"]
 ├─ Constant name="X" val="..."
 └─ Frame type="Type" name="Name" [template="File/Frame"] [file="LayoutFile"]
     ├─ property elements: <Width val/>, <Height val/>, <Texture val/>, <Text val/>, <Style val/>, ...
     ├─ Anchor side="Top|Bottom|Left|Right" relative="sel" pos="Min|Mid|Max" offset="n"
     ├─ Frame ... (children)
     ├─ Animation name="..."
     │   ├─ Event event="OnShown|OnHidden|custom" action="Play|Reset,Play|..." [frame="sel"]
     │   └─ Controller type="..." end="Pause|Stop|Loop" [frame="sel"]
     │       └─ Key type="Curve|Bool|Event|..." time="0" value="..."
     └─ StateGroup name="..."
         ├─ DefaultState val="..."
         └─ State name="..."
             ├─ When type="Property|AnimationState|StateGroup|Option" frame="sel" ...
             └─ Action type="SetProperty|SetAnchor|SendEvent|SetState|..." ...
```

## Frame types by use

| Group | Types |
| --- | --- |
| Primitives (most used) | `Image` (8,220), `Frame` (4,287), `Label` (3,401), `Button` (1,312), `ProgressBar`, `TextFormatFrame`, `CutsceneFrame`, `BlurFrame`, `CheckBox`, `Pulldown`, `EditBox`, `Slider`, `ScrollBar`, `ListBox`, `TileList`, `TabControl`, `Model`, `MovieFrame`, `ScrollableFrame`, `TreeView`, `AnchoredPopup`, `ContextMenu`, `PopupPanel`, `StandardTooltip`, `StandardDialog`, `AspectRatioFrame`, `ParentCenteredFrame`, `PropertyBind`, `Control`, `ToggleControl` |
| In-game HUD | `GameUI` (root), `UnitStatusFrame` and its `UnitStatus*` parts, `SelectionUnitStatusPanel`, `CommandButton`, `CommandPanel`, `CommandHotkeyFrame`, `BehaviorIcon`, `BehaviorBar`, `Minimap`, `MinimapPanel`, `PingPanel`, `ObjectivePanel`, `FloatingCombatElement`, `GameMessageDisplay`, `SubtitleDisplay`, `OffscreenUnitFrame`, `UnitTargetFrame` |
| Observer and score | `HeroLeaderPanel`, `HeroLeaderPanelPlayerFrame`, `HeroTalentsPanel`, `PlayerHeroSelectedTalentTreeFrame`, `PlayerHeroIconFrame`, `PlayerHeroNameFrame`, `PlayerScoreValueFrame`, `ScoreValueLabelFrame`, `TeamScoreValueFrame`, `TeamHeroLevelFrame`, `HeroExperienceBar`, `PlayerDeathIndicatorFrame`, `HeroSpecificContainerPanel` |
| Menus (glue) | `HeroSelectTileListItem`, `StoreTileListItem`, `BattleLobbyPlayerFrame`, `GlueButton`, `RankBadge`, `AvatarFrame`, `ObserverOptionsPanel`, `ReplayFilePanel` |

A native frame type may require named children ("hookups"). Copy them from the base UI when you
declare such a type from scratch; sc2-layouts reports missing ones.

## Common properties

`Anchor` (39,198 uses), `Width`, `Height`, `Texture`, `Visible`, `Text`, `Style`,
`RenderPriority`, `Alpha`, `TextureCoords`, `TextureType`, `BlendMode`, `AcceptsMouse`,
`Unclipped`, `ColorAdjustMode`, `RenderType`, `LayerCount`, `CollapseLayout`, `Color`, `Handle`,
`Tooltip`, `Tiled`, and the batching switches `Batch`, `BatchImages`, `BatchText` (AhliObs sets
them to `false` on panels it edits).

## Animation controllers, conditions and actions

| Element | Types, most used first |
| --- | --- |
| `Controller` | Fade, Visibility, Anchor, Event, Dimension, LayerUV, Texture, Sound, Cutscene, Rotation, Property, Text, Style, AdjustmentColor, Animation, State, Color, Blur |
| `Key` | Curve, Bool, Event, Cutscene, CurveReal, Image, Sound, Property, Text, Animation, Identifier |
| `When` | Property, AnimationState, StateGroup, Option |
| `Action` | SetProperty, SetAnchor, SendEvent, SetState, SetAnimationProperty, ApplyTemplate, SetAutoSizeClamps, PlaySound |
| top-level `Event` | OnShown, OnHidden, Reset, Hide, Show, OnMouseEnter, OnClick, custom names sent with `SendEvent` |

## Font styles (`.StormStyle`)

```xml
<StyleFile>
    <Constant name="ColorMyGold" val="255,214,120"/>
    <Style name="MyMod_Title" template="HeaderExtendedTemplate" height="18"
           vjustify="Middle" hjustify="Left" textcolor="#ColorMyGold"
           fontflags="Outline" styleflags="Shadow"/>
</StyleFile>
```

Other attributes: `font`, `outlinewidth`, `lineSpacing`, `characterSpacing`, `highlightcolor`,
`disabledcolor`, `hotkeycolor`, `hyperlinkcolor`, `glowcolor`, `shadowoffset`; `textcolor` may be
a gradient (`"255,192,192,192 - 255,181,193,255"`). Locale overrides go in
`<locale>.StormData/LocalizedData/FontStyles.StormStyle`. Use a style from a layout with
`<Style val="MyMod_Title"/>` or from Galaxy with `libNtve_gf_SetDialogItemStyle`.

## Cutscenes (`.StormCutscene`)

XML `<CutsceneState cutsceneVersion="...">` with `CCutsceneNodeActor modelPath="Assets/...m3"`
nodes and animation layers. A `CutsceneFrame` shows one, or a key sets it:
`<Key type="Cutscene" action="SetCutscene" file="Cutscenes/X.StormCutscene"/>`. In a `Key` or
`Action`, `file=` is a resource path, not a layout name.

## Textures

UI textures are `.dds`. Save UI textures with no mipmaps: Try Mode 2.0's author found textures with
mipmaps silently fail to load, and most of Heroes Rogue's 355 UI textures are uncompressed ARGB8888
with one mip level. Model textures keep their mips.

## sc2-layouts diagnostics

`Root element ("<Desc>") is missing`, `Could not find template`, `Cannot use FileDesc as template`,
`Couldn't find matching desc`, `Failed to locate specified File Desc`, `Child redeclared`,
`Unexpected attribute ... has no effect`, `Undeclared constant`, `Unknown property ... in property
bind expression`, missing hookups, and a warning when a path's case differs from its definition.
The schema it validates against is downloaded from `SC2Mapster/sc2layout-schema` at run time and
is SC2's, so HotS-only frame types can be reported as unknown.
