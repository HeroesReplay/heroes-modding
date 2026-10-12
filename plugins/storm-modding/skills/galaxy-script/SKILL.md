---
name: galaxy-script
description: >-
  Galaxy, the C-like script language of Heroes of the Storm and StarCraft II maps and mods: syntax
  limits, types, trigger libraries and the lib-prefix init chain, triggers and events, Wait and
  threads, banks, dialogs, catalog access, debugging, and the Heroes libraries. Can list the
  build's natives. USE FOR: writing or fixing .galaxy code. DO NOT USE FOR: XML data
  (storm-data-xml) or layout XML (storm-ui-layouts).
license: MIT
compatibility: Get-GalaxyNatives.ps1 needs PowerShell 7 (pwsh) and a NativeLib.TriggerLib extracted from the game.
---

# Galaxy script

Galaxy is the script language every Storm map runs. The game compiles all `.galaxy` files of a map
and its dependencies on every map load; there is nothing to build. A compile or runtime error
shows in game as a "map script error" dialog.

## Rules

- **Check every native against the build you target.** Heroes and StarCraft II share the language
  but not all natives (HotS has no `UnitAbilityAdd`, `TextToString` or item natives; its
  `UnitCreate` takes 7 arguments and returns a unitgroup). Run
  `scripts/Get-GalaxyNatives.ps1` on the build's `NativeLib.TriggerLib` and search Blizzard's own
  `TriggerLibs/*.galaxy` for a real call before using a native you have not seen in HotS code.
- **Prefer hooking Blizzard's events to copying Blizzard's libraries.** A copied `GameLib.galaxy`
  (1.2 MB) shadows the real one and breaks on the next patch. Listen to the generic events the
  Heroes libraries already send (`libGame_gv_eventID_HeroRespawn_C` and friends) instead.
- **Keep debug switches off in a release.** Gate cheats and test commands behind one
  `lib<ID>_DEBUG` constant.

## Where code lives

| File | Role |
| --- | --- |
| `MapScript.galaxy` (map root) | The map's script. The editor regenerates it from `Triggers` on save. The engine calls `InitMap()`, which calls `InitLibs()` then `InitTriggers()`. |
| `Base.StormData/<Lib>.galaxy` + `<Lib>_h.galaxy` | A trigger library: the header declares constants, structs, globals, prototypes and trigger variables; the body includes headers first and other library bodies at its end. |
| `TriggerLibs/NativeLib.galaxy` (core.stormmod) | `libNtve_`, the editor's built-in helpers (`libNtve_gf_SetDialogItemText`, ...) |
| `TriggerLibs/natives.galaxy` (core.stormmod) | Constants only in HotS; the native declarations are in `NativeLib.TriggerLib` |
| `TriggerLibs/*.galaxy` (heroesdata.stormmod) | The Heroes libraries below; the best reference for real HotS usage |

`include "Path/Without/Extension"` resolves against every loaded `Base.StormData`, ignores case,
and compiles each file once, so cycles are harmless. Order still matters: the compiler is single
pass, so a name must be declared above its first use (that is what `_h` headers are for).

### Heroes libraries

| File | Prefix | What |
| --- | --- | --- |
| NativeLib | `libNtve_` | Editor built-ins |
| HeroesLib | `libCore_` | Hero data, constants such as `libCore_gv_bALMaxPlayers` (10), debug flags `libCore_gv_dEBUG*` |
| GameLib | `libGame_` | Players (`libGame_gv_players[p]`), XP, talents, respawn, hero selection, generic event ids |
| MapMechanicsLib | `libMapM_` | Shared map objective framework |
| AILib | `libAIAI_` | Hero AI |
| UILib | `libUIUI_` | HUD and the debug panel |
| StartingExperienceLib | `libStEx_` | Tutorials |
| SoundLib | `libSond_` | Voice lines and sound |
| GameDataHelperLib | `libGDHL_` | Per-hero helpers |
| SupportLib | `libSprt_` | Support and test tools |

Battleground and hero mods add their own (`libMLCP_` Sky Temple, `libBBAY_` Blackheart's Bay,
`libHSTU_` Stukov, ...). The editor names generated symbols `lib<ID>_gv_` globals, `_gf_`
functions, `_gt_` triggers, `_ge_` presets, `_gs_` records, `lp_` parameters, `lv_` locals and
record members, `auto<hex>_` temporaries.

## A library, the way the game writes one

```c
// MyModLib_h.galaxy
include "TriggerLibs/NativeLib"

const string libMyMd_BankSection = "MyMod";
trigger libMyMd_gt_MapInit;

void libMyMd_InitVariables ();
```

```c
// MyModLib.galaxy
include "TriggerLibs/NativeLib"
include "MyModLib_h"

void libMyMd_InitLibraries () {
    libNtve_InitVariables();
}

bool libMyMd_InitVariables_completed = false;

void libMyMd_InitVariables () {
    if (libMyMd_InitVariables_completed) {
        return;
    }
    libMyMd_InitVariables_completed = true;
}

bool libMyMd_gt_MapInit_Func (bool testConds, bool runActions) {
    if (!runActions) {
        return true;
    }
    UIDisplayMessage(PlayerGroupAll(), c_messageAreaDebug, StringExternal("MyMod/Loaded"));
    return true;
}

void libMyMd_gt_MapInit_Init () {
    libMyMd_gt_MapInit = TriggerCreate("libMyMd_gt_MapInit_Func");
    TriggerAddEventMapInit(libMyMd_gt_MapInit);
}

void libMyMd_InitTriggers () {
    libMyMd_gt_MapInit_Init();
}

bool libMyMd_InitLib_completed = false;

void libMyMd_InitLib () {
    if (libMyMd_InitLib_completed) {
        return;
    }
    libMyMd_InitLib_completed = true;
    libMyMd_InitLibraries();
    libMyMd_InitVariables();
    libMyMd_InitTriggers();
}
```

The map then needs `include "MyModLib"` after its `TriggerLibs` includes and `libMyMd_InitLib();`
at the end of `InitLibs()`. `hots-custom-game-mode`'s `New-HotsMod.ps1` writes both files and that
patch. The editor never learns about a hand-added library, so re-saving the map in an editor drops
those two lines; keep the patch scripted.

## Triggers and events

- A trigger function is `bool Name (bool testConds, bool runActions)`: return false from the
  `testConds` block to fail the conditions, `true` when `runActions` is false.
- `TriggerCreate("Name")` binds by **string** at run time, so names can come from data (Heroes
  Rogue reads trigger names from a `CUser` table and creates them in a loop). A typo fails only at
  run time.
- Add events after creating: `TriggerAddEventMapInit`, `TriggerAddEventTimeElapsed(t, 1.0,
  c_timeGame)`, `TriggerAddEventTimePeriodic`, `TriggerAddEventUnitDied(t, null)`,
  `TriggerAddEventPlayerEffectUsed(t, c_playerAny, "EffectId")` (the main bridge from data to
  script), `TriggerAddEventChatMessage(t, c_playerAny, "-cmd", false)`,
  `TriggerAddEventKeyPressed`, `TriggerAddEventDialogControl`, `TriggerAddEventGeneric(t, "Name")`.
- Inside, read the context with `EventUnit()`, `EventPlayer()`, `EventChatMessage(false)`,
  `EventDialogControl()`, `EventPlayerEffectUsedUnit(c_effectUnitCaster)`.
- Custom events: `TriggerSendEvent("Name")` to `TriggerAddEventGeneric`; pass data through the
  data table with `TriggerEventParamName("Name", "Param")` keys.
- Run one directly: `TriggerExecute(t, testConds, waitUntilDone)`; `false` starts a new thread.

### Time, threads and limits

- 16 game loops per second; `Wait(0.0625, c_timeGame)` waits one loop.
- Every trigger firing is a thread; threads are cooperative. `Wait` yields. A thread that runs too
  long without yielding is killed with an error, so split big loops with `Wait(0, c_timeGame)`.
- `fixed` is fixed-point (12 fractional bits, about 1/4096), maximum 524287.999. Heroes Rogue grants
  XP in 524287 chunks for this reason.
- No dynamic memory, no pointers: fixed-size arrays (`int[10] a;`, sizes are constants), structs
  passed as `structref<T>`, engine objects (units, groups, timers, dialogs) created by natives.
  Dialogs, dialog controls and text tags are plain `int` ids.
- No `++`/`--` (`i += 1`), no ternary, locals declared at the top of the function.

More language detail: [references/language.md](references/language.md). Natives by area, with
HotS signatures: [references/natives.md](references/natives.md).

## Banks: data that survives the match

```c
const string kBank = "PlayerSettings";   // already listed in the stock maps' BankList.xml
const string kSection = "MyMod Run";

int MyMod_LoadInt (int player, string key, int fallback) {
    BankLoad(kBank, player);
    if (!BankKeyExists(BankLastCreated(), kSection, key)) {
        return fallback;
    }
    return BankValueGetAsInt(BankLastCreated(), kSection, key);
}

void MyMod_SaveInt (int player, string key, int value) {
    BankLoad(kBank, player);
    BankValueSetFromInt(BankLastCreated(), kSection, key, value);
    BankSave(BankLastCreated());
}
```

- A map may load only the banks its `BankList.xml` declares
  (`<Bank Name="PlayerSettings" Player="1"/>`). Heroes Rogue keeps its run in its own sections of
  Blizzard's `PlayerSettings` bank, next to Blizzard's `MapPlayCounts` and `Debug Menu Options`,
  so it needs no new declaration.
- Nothing reaches disk until `BankSave`. `BankSectionRemove` + `BankSave` resets.
- Signing exists (`BankOptionSet(bank, c_bankOptionSignature, true)`, `BankVerify`), but a
  replay records loaded bank values (`storm-replay-format`), so don't treat bank data as secret.
- The bank file location for HotS is not confirmed (by analogy with SC2:
  `Documents\Heroes of the Storm\Accounts\...\Banks\`). Find it after a run before telling a user.

## UI from script

```c
int dialog = DialogCreate(500, 300, c_anchorCenter, 0, 0, true);
int button = DialogControlCreateFromTemplate(dialog, c_triggerControlTypeButton,
                                             "StandardTemplates/StandardButtonTemplate");
libNtve_gf_SetDialogItemText(button, StringExternal("MyMod/Button"), PlayerGroupAll());
DialogSetVisible(dialog, PlayerGroupAll(), true);
TriggerAddEventDialogControl(libMyMd_gt_Clicked, c_playerAny, button, c_triggerControlEventTypeClick);
```

`DialogControlHookupStandard(c_triggerControlTypeLabel, "UIContainer/FullscreenUpperContainer/...")`
takes over a built-in frame; `DialogControlHookup(parent, type, "Child")` reaches a child of a
control made from your own layout template (`storm-ui-layouts`). Style text with
`libNtve_gf_SetDialogItemStyle(control, "MyStyle", PlayerGroupAll())`.

## Data from script

- `CatalogFieldValueGet(c_gameCatalogEffect, "MyDamage", "Amount", player)` (string),
  `...GetAsInt`/`...GetAsFixed`, `CatalogFieldValueSet`/`...SetFixed`/`...Modify`: per player, at
  run time only; the XML files never change.
- `CatalogReferenceGet("Effect,MyDamage,Amount", player)` and `CatalogReferenceModify` take one
  `Catalog,Entry,Field` string.
- `CUser` tables (`storm-data-xml`): `UserDataInstanceCount("Type")`,
  `UserDataInstance("Type", i)`, `UserDataGetString/Int/Fixed("Type", instance, "Field", index)`.

## Map flow

`GameSetNextMap("heroes/singleplayermaps/startingexperience/tutorialveteran.stormmap")` then
`KickFromGame(PlayerGroupAll())` loads another map (paths are relative to the maps root, with the
same overrides as the client). `RestartGame(PlayerGroupAll())` reloads the current one.
`GameMapPath()` returns the running map.

## Debugging in HotS

- There is no trigger debugger window in the retail client. Print instead:
  `UIDisplayMessage(PlayerGroupAll(), c_messageAreaDebug, StringToText("x=" + IntToString(x)))`,
  or `TriggerDebugOutput(type, text, true)`; HeroesLib routes type 1 to a `Debug_Output.txt` with
  `TriggerDebugSetTypeFile`.
- `libCore_gv_dEBUGDebuggingEnabled = true` (set before map init, as Try Mode 2.0 does) unlocks
  Blizzard's debug panel; `GameCheatsEnabled(c_gameCheatCategoryDevelopment)` stays false in retail.
- Bisect: keep a known-good copy, and remove includes until the script error goes away.
- Editing in the StarCraft II editor and exporting works for shared natives; Try Mode 2.0 prefixes
  HotS-only calls with `//_heroes_replace_//` so the SC2 editor accepts them, then strips it.

## List the natives of a build

```powershell
# 1. extract mods/core.stormmod/base.stormdata/TriggerLibs/NativeLib.TriggerLib (hots-casc-game-files)
# 2. print declarations; filter with -Name
pwsh -NoProfile -File scripts/Get-GalaxyNatives.ps1 .\NativeLib.TriggerLib -Name '^Bank'
```

Keep the output local (it is generated from Blizzard's files). 2.57.0.98348 lists 1,864 natives.

## Learn more

The SC2Mapster editor tutorials (StarCraft II, same language):
[Galaxy script](https://github.com/SC2Mapster/blizzard-tutorials/blob/master/docs/New_Tutorials/03_Trigger_Editor/058_GalaxyScript.md),
[banks](https://github.com/SC2Mapster/blizzard-tutorials/blob/master/docs/New_Tutorials/03_Trigger_Editor/051_Banks.md),
[threads](https://github.com/SC2Mapster/blizzard-tutorials/blob/master/docs/New_Tutorials/03_Trigger_Editor/057_Multithreading_with_Action_Definitions.md),
[optimizing](https://github.com/SC2Mapster/blizzard-tutorials/blob/master/docs/New_Tutorials/03_Trigger_Editor/056_Optimizing_Code.md),
[dialogs](https://github.com/SC2Mapster/blizzard-tutorials/blob/master/docs/New_Tutorials/03_Trigger_Editor/043_Dialogs.md).
For real HotS code, read Heroes Rogue's `LibAffx.galaxy` (bank I/O, data-driven triggers) and the
game's own `TriggerLibs`.
