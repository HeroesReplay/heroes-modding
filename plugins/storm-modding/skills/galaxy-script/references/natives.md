# Natives by area (Heroes of the Storm 2.57)

Signatures are from the 2.57.0.98348 `NativeLib.TriggerLib` (via `scripts/Get-GalaxyNatives.ps1`)
in script form. Names marked "script-only" are not in that file but are called by Blizzard's own
Heroes libraries. Re-check after a patch.

## Units

```c
unitgroup UnitCreate(int count, string type, int flags, int player, point pos, fixed angle, unit creatorUnit);
unit UnitLastCreated();
void UnitRemove(unit u);
void UnitKill(unit u);
string UnitGetType(unit u);
int UnitGetOwner(unit u);
point UnitGetPosition(unit u);
void UnitSetPosition(unit u, point p, bool blend);
bool UnitIsAlive(unit u);
bool UnitIsValid(unit u);
fixed UnitGetPropertyFixed(unit u, int prop, bool current);    // c_unitPropLife, ...LifeMax, ...Energy
void UnitSetPropertyFixed(unit u, int prop, fixed val);
bool UnitIssueOrder(unit u, order ord, int queue);              // c_orderQueueReplace
order OrderTargetingUnit(abilcmd abilCmd, unit u);
order OrderTargetingPoint(abilcmd abilCmd, point p);
abilcmd AbilityCommand(string ability, int command);
void UnitSetCustomValue(unit u, int index, fixed val);         // per-unit scratch slots
fixed UnitGetCustomValue(unit u, int index);
```

Typical create: `UnitCreate(1, "MyUnit", c_unitCreateIgnorePlacement, player, pos, 270.0, null);`
then `UnitLastCreated()`.

## Unit groups

```c
unitgroup UnitGroup(string type, int player, region reg, unitfilter unitFilter, int count);
unitgroup UnitGroupAlliance(int player, int alliance, region reg, unitfilter unitFilter, int count);
unitgroup UnitGroupEmpty();
void UnitGroupAdd(unitgroup g, unit u);
int UnitGroupCount(unitgroup g, int type);                      // c_unitCountAll
unit UnitGroupUnit(unitgroup g, int i);                         // 1-based
// script-only: UnitFilter(required, required2, excluded, excluded2) built from (1 << c_targetFilterX)
```

## Behaviors, abilities, cooldowns, effects

```c
void UnitBehaviorAdd(unit inUnit, string inBehavior, unit inCaster, int inCount);
void UnitBehaviorRemove(unit inUnit, string inBehavior, int inCount);
int UnitBehaviorCount(unit unit, string behavior);
bool UnitHasBehavior(unit unit, string behavior);
fixed UnitBehaviorDuration(unit unit, string behavior);
void UnitBehaviorSetDuration(unit unit, string behavior, fixed duration);
fixed UnitGetTokenCount(unit unit, string tokenId);             // quest stacks (CBehaviorTokenCounter)
void UnitAbilityEnable(unit u, string abil, bool enable);
void UnitModifyCooldown(unit inUnit, string inCooldown, fixed inVal, int inCooldownOperation);
void PlayerCreateEffectPoint(int caster, string effect, point point);
// script-only: UnitCreateEffectUnit(caster, "Effect", target), UnitCreateEffectPoint(caster, "Effect", point)
```

Heroes get abilities from data and talents; HotS has no `UnitAbilityAdd`.

## Players, talents, XP, score

```c
playergroup PlayerGroupAll();
playergroup PlayerGroupSingle(int p);
playergroup PlayerGroupEmpty();
void PlayerGroupAdd(playergroup g, int p);
bool PlayerGroupHasPlayer(playergroup g, int p);
playergroup PlayerGroupAlliance(int alliance, int player);
int PlayerStatus(int p);                                        // c_playerStatusUnused, ...
int PlayerType(int p);                                          // c_playerTypeUser, ...Computer
text PlayerName(int p);
bool PlayerHasTalent(int p, string talent);
void PlayerAddTalent(int player, string talent);
void PlayerRemoveTalent(int player, string talent);
void SetTalentEnabled(string talent, bool enable);
void SetTalentsEnabled(bool enabled);                           // false hides the talent UI
void UnitXPAddXP(unit unit, string veterancyBehavior, fixed xP);
int UnitXPGetCurrentLevel(unit unit, string veterancyBehavior);
fixed PlayerScoreValueGetAsFixed(int player, string score);     // "HeroDamage", ...
// script-only: PlayerGroupNextPlayer(g, p) iterates: p = -1; while (true) { p = PlayerGroupNextPlayer(g, p); if (p < 0) break; }
```

Library helpers worth knowing: `libGame_gf_GrantXPToPlayer`, `libGame_gv_players[p].lv_heroUnit`,
`libCore_gf_GetHeroFromIndex`, `libCore_gv_mAPMapStringID` (the running battleground's id).

## Catalog data at run time (per player)

```c
string CatalogFieldValueGet(int catalog, string entry, string fieldPath, int player);
int CatalogFieldValueGetAsInt(int catalog, string entry, string fieldPath, int player);
fixed CatalogFieldValueGetAsFixed(int catalog, string entry, string fieldPath, int player);
bool CatalogFieldValueSet(int catalog, string entry, string fieldPath, int player, string value);
bool CatalogFieldValueSetFixed(int catalog, string entry, string fieldPath, int player, fixed value);
bool CatalogFieldValueModify(int catalog, string entry, string fieldPath, int player, string value, int operation); // c_upgradeOperationAdd
int CatalogFieldValueCount(int catalog, string entry, string fieldPath, int player);
string CatalogReferenceGet(string reference, int player);       // "Effect,MyDamage,Amount"
bool CatalogReferenceModify(string reference, int player, string value, int operation);
bool CatalogEntryIsValid(int catalog, string entry);
int CatalogEntryCount(int catalog);
string CatalogEntryGet(int catalog, int index);
```

Catalog ids: `c_gameCatalogEffect`, `...Behavior`, `...Abil`, `...Unit`, `...Hero`, `...Talent`,
`...Actor`, `...Weapon`, `...Button`. Field paths use the XML names: `Cost[0].Cooldown.TimeUse`,
`Modification.DamageDealtFraction[Ability]`.

## User data tables (CUser)

```c
int UserDataInstanceCount(string userType);
string UserDataInstance(string userType, int index);            // 1-based
string UserDataGetString(string userType, string instance, string field, int index);
int UserDataGetInt(string userType, string instance, string field, int index);
fixed UserDataGetFixed(string userType, string instance, string field, int index);
```

## Timers and time

```c
timer TimerCreate();
void TimerStart(timer t, fixed dur, bool r, int timeType);      // r = periodic
fixed TimerGetRemaining(timer t);
fixed TimerGetElapsed(timer t);
void TimerPause(timer t, bool pause);
fixed GameGetMissionTime();
void Wait(fixed t, int timeType);                               // c_timeGame, c_timeReal
```

## Triggers and events

```c
// script-only: trigger TriggerCreate(string function)
void TriggerEnable(trigger t, bool state);
void TriggerExecute(trigger t, bool check, bool wait);
trigger TriggerGetCurrent();
void TriggerSendEvent(string eventName);
string TriggerEventParamName(string eventName, string parameterName);
void TriggerAddEventGeneric(trigger t, string eventName);
void TriggerAddEventMapInit(trigger t);
void TriggerAddEventTimeElapsed(trigger t, fixed dur, int timeType);
void TriggerAddEventTimePeriodic(trigger t, fixed dur, int timeType);
void TriggerAddEventTimer(trigger t, timer tmr);
void TriggerAddEventUnitDied(trigger t, unit u);                // null = any unit
void TriggerAddEventUnitCreated(trigger t, unit creator, string ability, string behavior);
void TriggerAddEventUnitDamaged(trigger t, unit u, int damageType, int damageFatalOption, string damageEffect);
void TriggerAddEventUnitBehaviorChange(trigger t, unit unit, string behavior, int type);
void TriggerAddEventPlayerEffectUsed(trigger t, int p, string effect);
void TriggerAddEventChatMessage(trigger t, int p, string s, bool exact);
void TriggerAddEventKeyPressed(trigger t, int player, int key, bool down, int s2, int c2, int a2);
void TriggerAddEventDialogControl(trigger t, int player, int item, int eventType);
unit EventUnit();
int EventPlayer();
string EventChatMessage(bool m);
int EventDialogControl();
fixed EventUnitDamageAmount();
unit EventPlayerEffectUsedUnit(int location);                   // c_effectUnitCaster, ...Target
```

## Messages, dialogs, text tags

```c
void UIDisplayMessage(playergroup players, int messageArea, text message);  // c_messageAreaDebug, ...Chat
void UIClearMessages(playergroup players, int options);
int DialogCreate(int width, int height, int anchor, int offsetX, int offsetY, bool modal);
void DialogSetVisible(int dialog, playergroup players, bool visible);
void DialogSetFullscreen(int dialog, bool fullscreen);
int DialogControlCreate(int dialog, int type);                  // c_triggerControlTypeButton, ...Label
int DialogControlCreateFromTemplate(int dialog, int type, string template);
int DialogControlLastCreated();
void DialogControlSetVisible(int dialogItem, playergroup players, bool visible);
void DialogControlSetEnabled(int dialogItem, playergroup players, bool enableOption);
int DialogControlHookup(int dialogItem, int type, string name);
int DialogControlHookupStandard(int type, string name);
int TextTagCreate(text text, int fontSize, point point, fixed heightOffset, bool visible, bool useFogofWar, playergroup players);
void TextTagAttachToUnit(int tag, unit unit, fixed heightOffset);
void TextTagDestroy(int textTag);
```

## Strings and text

```c
text StringExternal(string path);
text StringToText(string val);
text IntToText(int val);
text FixedToText(fixed val, int prec);                          // c_fixedPrecisionAny
string IntToString(int val);
string FixedToString(fixed val, int prec);
int StringToInt(string val);
fixed StringToFixed(string val);
string StringWord(string string, int index);                    // 1-based, space separated
string StringSub(string s, int start, int end);
int StringLength(string s);
int StringFind(string string, string substring, bool sensitivity);
bool StringEqual(string s1, string s2, bool sens);
void TextExpressionSetToken(string expressionId, string token, text text);
text TextExpressionAssemble(string expressionId);
text TextWithColor(text text, color color);
text FormatNumber(int number);
```

## Math, points, regions

```c
int RandomInt(int min, int max);
fixed RandomFixed(fixed min, fixed max);
int MaxI(int value1, int value2);
int MinI(int value1, int value2);
int AbsI(int value);
int ModI(int x, int y);
fixed Pow(fixed x, fixed p);
fixed SquareRoot(fixed x);
point Point(fixed x, fixed y);
fixed PointGetX(point p);
point PointWithOffsetPolar(point p, fixed dist, fixed angle);
fixed DistanceBetweenPoints(point p1, point p2);
fixed AngleBetweenPoints(point p1, point p2);
region RegionCircle(point c, fixed r);
```

## Data table

```c
void DataTableSetInt(bool scope, string name, int value);       // true = global, false = this trigger
int DataTableGetInt(bool scope, string name);
void DataTableValueRemove(bool scope, string name);
```

## Banks

```c
bank BankLoad(string name, int player);
bank BankLastCreated();
void BankSave(bank bank);
bool BankExists(string name, int player);
bool BankSectionExists(bank bank, string section);
bool BankKeyExists(bank bank, string section, string key);
int BankValueGetAsInt(bank bank, string section, string key);
fixed BankValueGetAsFixed(bank bank, string section, string key);
string BankValueGetAsString(bank bank, string section, string key);
bool BankValueGetAsFlag(bank bank, string section, string key);
void BankValueSetFromInt(bank bank, string section, string key, int value);
void BankValueSetFromFixed(bank bank, string section, string key, fixed value);
void BankValueSetFromString(bank bank, string section, string key, string value);
void BankValueSetFromFlag(bank bank, string section, string key, bool value);
void BankKeyRemove(bank bank, string section, string key);
void BankSectionRemove(bank bank, string section);
void BankOptionSet(bank bank, int option, bool state);          // c_bankOptionSignature
bool BankVerify(bank bank);
void BankWait(bank bank);
void BankReload(bank bank);
```

## Map flow, game state, stats

```c
void GameSetNextMap(string map);
void KickFromGame(playergroup playerGroup);
void RestartGame(playergroup playerGroup);
string GameMapPath();
bool GameIsTestMap(bool type);
bool GameCheatsEnabled(int category);                           // c_gameCheatCategoryDevelopment
void GameSetSpeedValue(int speed);
int StatEventCreate(string eventName);                          // appears in replay.tracker.events
void StatEventAddDataString(int statEvent, string key, string value);
void StatEventAddDataInt(int statEvent, string key, int value);
void StatEventAddDataFixed(int statEvent, string key, fixed value);
void StatEventSend(int statEvent);
```

## Debug and actors

```c
void TriggerDebugOutput(int type, text msg, bool ui);
void TriggerDebugSetTypeFile(int type, string file);
void ActorSend(actor actor, string message);
actor ActorCreate(actorscope actorScope, string name, string content1, string content2, string content3);
// library: libNtve_gf_SendActorMessageToUnit(unit, "SetTintColor 255,0,0")
```
