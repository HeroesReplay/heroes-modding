---
name: storm-data-xml
description: >-
  Heroes of the Storm game data XML: catalog files and GameData.xml registration, adding entries
  with parent versus overriding Blizzard ids, array index and removed rules, effect trees,
  behaviors, validators, actors, CUser tables, and localized text in GameStrings.txt. USE FOR:
  changing heroes, abilities, talents or units, or adding data and strings to a mod. DO NOT USE
  FOR: script logic (galaxy-script) or UI frames (storm-ui-layouts).
license: MIT
---

# Storm data XML

Everything a hero, ability, talent, unit or effect does is data: XML catalog entries that the
game merges across every loaded document in dependency order. A mod changes the game by adding
entries and by redeclaring Blizzard's entries with only the fields it changes.

## Rules

- **Look up the real entry first.** Extract the Blizzard catalogs you touch
  (`mods/heroesdata.stormmod/base.stormdata/GameData/` and the hero's
  `mods/heromods/HERO.stormmod/`, with `hots-casc-game-files`) and copy ids and field names from
  them. A wrong id silently creates a new, unused entry.
- **Override, don't copy.** Redeclare an existing id with only the changed fields. Copying a whole
  entry freezes it at today's build.
- **Index every array element you patch.** An unindexed element appends.
- **Keep XML ASCII** and put display text in `GameStrings.txt`.

## Files

```
Base.StormData/
  GameData.xml               <Includes><Catalog path="GameData/MyModData.xml"/></Includes>
  GameData/AbilData.xml ...  standard names load without being listed
  GameData/MyModData.xml     any other name must be listed in GameData.xml
  GameData/HeroData/X.xml    sub-folders are fine when listed
enUS.StormData/LocalizedData/GameStrings.txt
```

Each catalog file is one `<Catalog>` with entries of any type, so one file per feature is fine:

```xml
<?xml version="1.0" encoding="us-ascii"?>
<Catalog>
    <CBehaviorBuff id="MyModHasteBuff" parent="CarryBehaviorParent">
        <Duration value="4"/>
        <Modification>
            <UnifiedMoveSpeedFactor value="0.25"/>
        </Modification>
    </CBehaviorBuff>
</Catalog>
```

Heroes Rogue adds `xsi:noNamespaceSchemaLocation="https://raw.githubusercontent.com/jamiephan/HeroesOfTheStorm_Gamedata/master/xsd/latest.xsd"`
(with the `xmlns:xsi` namespace) to `<Catalog>`; editors then complete element and field names.

## Add versus override

| Goal | Write |
| --- | --- |
| New entry | a new `id` and a `parent` template: `<CButton id="MyModButton" parent="StormButtonParent">` |
| Change a Blizzard entry | the same element type and `id`, no `parent`, only the fields to change |
| Change one array slot | `<ValidatorArray index="1" value="MyValidator"/>` |
| Add to an array | an element without `index` (appends) |
| Named slots | `<Flags index="Transient" value="1"/>`, `<VitalArray index="Life">`, `<DamageDealtFraction index="Ability" value="0.1"/>` |
| Remove an inherited element | `<AssetArray index="3" removed="1"/>` |
| Abstract template | `default="1"` on the entry (used as a parent only) |

Examples from Heroes Rogue's hero overrides:

```xml
<CHero id="Illidan">
    <TalentTreeArray index="21" Talent="MyModTalent" Tier="6" Column="4"/>
</CHero>
<CEffectDamage id="WitchDoctorCorpseSpidersWeaponDamage">
    <MultiplicativeModifierArray index="MyModPowerfulSpiders" Modifier="0"/>
</CEffectDamage>
```

Common Heroes parents (2.57 `heroesdata.stormmod` catalogs, all `default="1"`): buffs
`CarryBehaviorParent`, `StormArmor`, `StormShield`, `StormStun`, `StormRoot`, `StormSilence`,
`StormSlowParent`, `StormReveal`; token counters `StormGenericToken`, `StormQuestToken`; damage
effects `StormSpell` (ability damage) and `StormWeapon` (basic attacks); token effects
`BaseEffectModifyTokenCount`; buttons `StormButtonParent`; validators `CasterIsParent`,
`TargetNotParent` and friends (behavior-count checks); sounds `SoundOneShot`.

## How abilities work: effect trees

Abilities, weapons and behaviors only start effects; effects chain into trees.

| Effect | Job |
| --- | --- |
| `CEffectSet` | run several effects (`EffectArray`) on the same target, optionally gated by `ValidatorArray` |
| `CEffectSwitch` | first case whose validator passes |
| `CEffectEnumArea` | search an area (`AreaArray` radius and effect, `SearchFilters "required;excluded"`) |
| `CEffectCreatePersistent` | periodic or delayed carrier (`PeriodCount`, `PeriodicPeriodArray`, `PeriodicEffectArray`) |
| `CEffectDamage` | `Amount` plus modifier arrays |
| `CEffectApplyBehavior` / `CEffectRemoveBehavior` | add or remove a behavior (`Behavior`, `WhichUnit`) |
| `CEffectLaunchMissile` | `AmmoUnit`, `ImpactEffect` |
| `CEffectModifyUnit`, `CEffectCreateUnit`, `CEffectIssueOrder`, `CEffectModifyTokenCount` | change vitals, spawn, order, quest stacks |

Every node knows its caster, source, target and origin; fields such as `WhichUnit` and
`WhichLocation` pick one. An aura is a behavior with `Period` and `PeriodicEffect` = search, the
search applies a short buff, and the buff fades when the unit leaves.

To react in script, listen with `TriggerAddEventPlayerEffectUsed(t, c_playerAny, "MyEffect")`
(`galaxy-script`). Entry types, behaviors, validators, accumulators and actor events are in
[references/catalogs.md](references/catalogs.md).

## Talents

A talent is a `CTalent` (`<Face value="Button"/>`, optionally `<Abil value="..."/>` and
`<Active value="1"/>` for an activated talent) plus a slot in the hero's `CHero`
`TalentTreeArray` (`Talent`, `Tier`, `Column`). Behaviors check a talent with a
`CValidatorPlayerTalent`. From script: `PlayerHasTalent`, `PlayerAddTalent`, `SetTalentEnabled`.
Heroes Rogue fills spare tree slots with empty `DoNothing` talents (`<Face value="DoNothing"/>`)
and grants real ones from script.

## Data tables for your own content: CUser

```xml
<CUser id="MyModRelic">
    <Fields Id="Rarity" Type="String"/>
    <Fields Id="Weight" Type="Int"/>
    <Fields Id="Trigger" Type="String" Count="4"/>
    <Instances Id="[Default]">
        <Int Int="100"><Field Id="Weight"/></Int>
    </Instances>
    <Instances Id="RelicOfHaste">
        <String String="Rare"><Field Id="Rarity"/></String>
        <String String="RelicAdded libMyMd_RelicOfHaste"><Field Id="Trigger" Index="0"/></String>
    </Instances>
</CUser>
```

Read it with `UserDataInstanceCount("MyModRelic")`, `UserDataInstance("MyModRelic", i)` and
`UserDataGetString("MyModRelic", instance, "Rarity", 1)`. Galaxy indexes from 1, the XML `Index`
from 0. Heroes Rogue keeps all 419 boons and curses this way and builds their triggers from the
`Trigger` strings.

## Text: GameStrings.txt

- One `Key=Value` per line, UTF-8 with a BOM, CRLF, in `<locale>.StormData/LocalizedData/`.
  A duplicate key is legal but only one wins; the linter warns.
- Data keys: `Button/Name/ID`, `Button/Tooltip/ID`, `Button/SimpleDisplayText/ID`, `Abil/Name/ID`,
  `Behavior/Name/ID`, `Unit/Name/ID`. Document keys: `DocInfo/Name`, `DocInfo/DescShort`,
  `DocInfo/DescLong`. Script keys are free-form (`MyMod/Relic/RelicOfHaste`) and read with
  `StringExternal`.
- Markup: `<n/>` new line, `<c val="#TooltipNumbers">..</c>` colour, `<s val="Style">..</s>`,
  `<img path="@UI/StormTalentInTextQuestIcon"/>`, live values
  `<d ref="Effect,MyDamage,Amount" precision="0"/>`, script globals
  `<d ref="($GalaxyVar:libMyMd_gv_bonus$)*100"/>`, script tokens `~A~`.
- Ship every locale you list in `ComponentList`; copy enUS when you have no translation, or the
  key shows instead of the text (untested; copying is safe).
- `ObjectStrings.txt` and `TriggerStrings.txt` are editor names; the game does not need them.

## Pitfalls

- An entry type mismatch (`CEffectDamage` vs `CEffectSet` for the same id) is a different entry,
  not an override.
- Moving data between documents loses its names and tooltips unless the matching
  `GameStrings.txt` lines move too.
- A malformed catalog breaks the map load with only the "map script error" dialog. Run
  `storm-mod-structure`'s `Test-StormDocument.ps1`; it parses every XML file and checks every
  `GameData.xml` path.
- After a patch, renamed or removed Blizzard ids make overrides dead. Diff the build's catalogs
  (`hots-casc-game-files`) against your overrides' ids.
