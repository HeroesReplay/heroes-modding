# Catalog reference

## Catalog files in heroesdata.stormmod (2.57)

`AbilData`, `AccumulatorData`, `AchievementData`, `ActorData`, `ActorSupportData`, `AlertData`,
`AnnouncerPackData`, `ArmorData`, `BeamData`, `BehaviorData`, `ButtonData`, `CameraData`,
`CharacterData`, `ConfigData`, `ConversationData`, `CursorData`, `EffectData`, `ErrorData`,
`FootprintData`, `GameUIData`, `HeroData`, `HeroMasteryData`, `HeroRoleData`, `ItemData`,
`LightData`, `MapData`, `ModelData`, `MountData`, `MoverData`, `PingData`, `PreloadData`,
`RaceData`, `RequirementData`, `RequirementNodeData`, ..., `TalentData`, `UnitData`,
`ValidatorData`, `WeaponData`. Each hero adds its own under `mods/heromods/HERO.stormmod/`.
A file named like these loads without being listed in `GameData.xml`.

## Entry types you will meet

| Family | Types |
| --- | --- |
| Units and weapons | `CUnit`, `CWeaponLegacy`, `CTurret`, `CMoverMissile` |
| Abilities | `CAbilEffectTarget`, `CAbilEffectInstant`, other `CAbil*` |
| Effects | `CEffectSet`, `CEffectSwitch`, `CEffectEnumArea`, `CEffectCreatePersistent`, `CEffectDamage`, `CEffectApplyBehavior`, `CEffectRemoveBehavior`, `CEffectLaunchMissile`, `CEffectModifyUnit`, `CEffectCreateUnit`, `CEffectIssueOrder`, `CEffectModifyPlayer`, `CEffectDestroyPersistent`, `CEffectModifyBehaviorBuffDuration`; Heroes adds `CEffectCreateHealer`, `CEffectModifyTokenCount`, `CEffectEnumTrackedUnits`, `CEffectAddTrackedUnit`, `CEffectModifyCatalogNumeric` |
| Behaviors | `CBehaviorBuff`, `CBehaviorAbility`; Heroes adds `CBehaviorTokenCounter` (quest stacks), `CBehaviorUnitTracker` |
| Validators | `CValidatorCombine`, `CValidatorUnitCompareBehaviorCount`, `CValidatorUnitFilters`, `CValidatorUnitHasBehavior`, `CValidatorUnitType`, `CValidatorLocationCompareRange`, `CValidatorUnitCompareVital`, `CValidatorUnitCompareCooldown`; Heroes adds `CValidatorUnitCompareTokenCount`, `CValidatorPlayerTalent`, `CValidatorIsUnitTracked`, `CValidatorCompareTrackedUnitsCount` |
| Accumulators (computed amounts) | `CAccumulatorToken`, `CAccumulatorVitals`, `CAccumulatorTrackedUnitCount` |
| Presentation | `CActorModel`, `CActorSound`, `CActorAction`, `CActorSite`, `CActorUnit`, `CActorBeamSimple`, `CActorSplat`, `CActorMissile`, `CModel`, `CSound`, `CButton` |
| Heroes progression | `CHero`, `CTalent`, `CRequirement`, `CUser` (your own tables), mounts and skins |

## Behaviors

`CBehaviorBuff` fields: `Duration`, `Period`, `PeriodicEffect`, `InitialEffect`, `ExpireEffect`,
`Modification` (most used children: `DamageDealtScaled`, `DamageDealtFraction`, `VitalMaxArray`,
`VitalMaxFractionArray`, `VitalRegenArray`, `UnifiedMoveSpeedFactor`, `AdditiveAttackSpeedFactor`,
`StateFlags`, `ModifyFlags`, `AbilLinkDisableArray`, `HealDealtAdditiveMultiplier`),
`DisableValidatorArray` (off while the test fails, can come back) and `RemoveValidatorArray`
(removed for good when the test fails).

Quest stacks: a `CBehaviorTokenCounter` (parent `StormQuestToken`), changed by a
`CEffectModifyTokenCount` (parent `BaseEffectModifyTokenCount`), read by
`CValidatorUnitCompareTokenCount`, a `CAccumulatorToken`, or `UnitGetTokenCount` in script.

## Validators

- On an effect, every validator must pass or the effect does nothing.
- On a behavior, they are disable or remove rules.
- They also gate abilities, buttons (`UseValidator`) and actor events
  (`ValidateEffect X`, `ValidateUnit X`).
- Name them as the predicate they test ("TargetIsHero", "CasterHasMyBuff"); the game's own
  behavior-count checks follow `CasterIsParent`/`TargetNotParent`.
- `CValidatorCombine` ANDs or ORs a list (with Negate) and nests.

## Effect tree examples

Missile ability: `CAbilEffectTarget` (`Effect` = launch) -> `CEffectLaunchMissile` (`AmmoUnit` =
a missile unit, `ImpactEffect` = damage) -> `CEffectDamage` (`Amount`).

Channelled repeat: ability -> `CEffectCreatePersistent` (`PeriodCount` 15, `PeriodicPeriodArray`
0.125, `PeriodicEffectArray` = the launch) -> launch -> damage.

Aura:

```xml
<CBehaviorBuff id="MyAura" parent="CarryBehaviorParent">
    <Period value="0.25"/>
    <PeriodicEffect value="MyAuraSearch"/>
</CBehaviorBuff>
<CEffectEnumArea id="MyAuraSearch">
    <SearchFilters value="-;Self,Enemy,Structure,Missile,Dead,Hidden"/>
    <AreaArray Effect="MyAuraApply">
        <Radius value="5"/>
    </AreaArray>
</CEffectEnumArea>
<CEffectApplyBehavior id="MyAuraApply">
    <Behavior value="MyAuraBuff"/>
</CEffectApplyBehavior>
<CBehaviorBuff id="MyAuraBuff" parent="CarryBehaviorParent">
    <Duration value="0.5"/>
    <Modification>
        <DamageDealtFraction index="Ability" value="0.1"/>
    </Modification>
</CBehaviorBuff>
```

The buff's duration is a little longer than the aura period, so it stays while the unit is in range
and fades shortly after it leaves. Check every field name against the build's own catalogs before
shipping.

## Actors and events

Actors are client-side visuals: never make gameplay depend on them. Gameplay data names its
effect ("forward"); an actor declares which events create and drive it ("reverse"):

```xml
<On Terms="UnitBirth" Send="Create MyLoopModel"/>
<On Terms="UnitDeath" Target="MyLoopModel" Send="Destroy"/>
<On Terms="Effect.MyPersistent.Start; At Target" Send="Create"/>
<On Terms="Effect.MySearch.Start; ValidateEffect HasMyTalent" Send="Create"/>
```

Common messages: `Create`, `Destroy`, `AnimPlay`, `AnimBracketStart`/`Stop`, `SetTintColor`,
`SetOpacity`, `ModelSwap`, `TimerSet`, `AliasAdd`, `Signal`. Useful parents: `GenericAttack`
(fill `Attack`, or `Launch` and `Impact`), `ModelAddition`, `ModelAnimationStyleOneShot`,
`SoundOneShot`. From script: `ActorSend` or `libNtve_gf_SendActorMessageToUnit(unit, "SetTintColor 255,0,0")`.

## Buttons and tooltips

A `CButton` holds the icon (`<Icon value="Assets\Textures\x.dds"/>`), hotkey, name and tooltip
(text in `GameStrings.txt` as `Button/Name/ID` and `Button/Tooltip/ID`). Tooltips can show live
values: `<d ref="Effect,MyDamage,Amount" precision="0"/>`,
`<d ref="Effect,MyDamage,MultiplicativeModifierArray[Key].Modifier*100"/>`, or a script global
with `$GalaxyVar:name$`.

## Tokens and constants

- A parent can expose tokens: its fields reference `##Name##`, the child sets them as attributes
  of its own element (`<CActorAction id="MyAttack" parent="GenericAttack" Impact="MyDamage"/>`).
- Catalog constants: `<const id="$MyBonus" value="0.2"/>` inside `<Catalog>`, used as
  `value="$MyBonus"` (Blizzard's Anduin data: `<const id="$AnduinDivineStarHolyNovaSearchRadius"
  value="4"/>` then `<Radius value="$AnduinDivineStarHolyNovaSearchRadius"/>`).
- A hero mod's `GameData.xml` lists its catalogs, including nested skin folders
  (`GameData/AnduinSkinData/AnduinBaseData/AnduinVar1Data.xml`).

## Mod layering

Documents load in dependency order: `Core`, `Heroes`, `HeroesData`, hero and map mods, then mods
injected with `includes.xml`, then the map. A later layer wins per id and per field. Two
documents that both change the same field: the later one wins silently.

## Learn more

SC2Mapster tutorials (StarCraft II editor, same data system):
[data spaces and GameData.xml](https://github.com/SC2Mapster/blizzard-tutorials/blob/master/docs/New_Tutorials/04_Data_Editor/data-spaces.md),
[actors](https://github.com/SC2Mapster/blizzard-tutorials/blob/master/docs/New_Tutorials/04_Data_Editor/060_Actors.md),
[validators](https://github.com/SC2Mapster/blizzard-tutorials/blob/master/docs/New_Tutorials/04_Data_Editor/072_Validators_Rundown.md),
[a firebolt end to end](https://github.com/SC2Mapster/blizzard-tutorials/blob/master/docs/Data_Primer/01_Simple_Firebolt/01_Firebolt.md),
[an aura](https://github.com/SC2Mapster/blizzard-tutorials/blob/master/docs/New_Tutorials/07_Lessons/087_Create_an_Aura_Ability.md).
The community XSD at `jamiephan/HeroesOfTheStorm_Gamedata` gives editor completion for Heroes
catalogs.
