# heroprotocol internals

Paths are relative to `heroprotocol/` in Blizzard/heroprotocol at `9af3ea7` (protocol 96477,
2.55.15). `#N` is typeinfo index N in `versions/protocol96477.py`.

## Picking a table

- `hero_cli.py` decodes the header with `latest()` (any table reads it: the header is versioned),
  then imports `protocol{baseBuild:05d}`. A missing file exits with "Unsupported base build"; there
  is no fallback.
- `latest()` sorts file names as strings; fine until build 100000.
- 391 files exist (29406 to 96477) with only 36 distinct contents; 85027 to 96477 are identical.
- What changes between tables: fields appended to structs and types inserted into `typeinfos`,
  which shifts every later type id (85027 added `m_disabledHeroList`, moving `replay_initdata_typeid`
  from 70 to 71 and `SStatGameEvent` from #202 to #203). Event ids do not move.

## Header (`#18`)

| Tag | Field | Example (2.57) |
| --- | --- | --- |
| 0 | `m_signature` | `Heroes of the Storm replay` + `0x1B` + `11` |
| 1 | `m_version` | flags 1, 2.57.0, build 98304, baseBuild 98304 |
| 2 | `m_type` | 2 |
| 3 | `m_elapsedGameLoops` | 11976 |
| 4 | `m_useScaledTime` | false |
| 5 | `m_ngdpRootKey` | `{m_data: 16 bytes}` (the build's CASC root) |
| 6 | `m_dataBuildNum` | 98304 |
| 7 | `m_replayCompatibilityHash` | `{m_data: 16 zero bytes}` (was `m_fixedFileHash` before 49582) |

## Bit buffer

```text
read_bits(n):                         # big-endian mode (all streams except attributes)
    result = 0; got = 0
    while got < n:
        if no bits left in current byte: load next byte, 8 bits left
        take = min(n - got, bits left)
        chunk = current & ((1 << take) - 1)   # low bits of the current byte
        result |= chunk << (n - got - take)   # placed at the high end of what remains
        current >>= take; bits left -= take; got += take
byte_align(): drop the rest of the current byte
read_aligned_bytes(k): byte_align, then k raw bytes
done(): no bits left and all bytes used
```

Port it literally; it is not a plain MSB-first stream. Bit arrays can be wider than 64 bits
(`m_allowedAIBuilds` up to 127): read them in 64-bit chunks into a big integer.

## Type grammar

Bounds `(min, bits)` mean `value = min + read_bits(bits)`.

| Kind | Bit-packed | Versioned (tag byte, then...) |
| --- | --- | --- |
| `_int` | `min + bits` | `9`, vint (bounds ignored) |
| `_bool` | 1 bit | `6`, 1 byte |
| `_blob` | length (bounds), aligned bytes | `2`, vint length, aligned bytes |
| `_array` | length (bounds), elements | `0`, vint length, elements |
| `_bitarray` | length, then that many bits | `1`, vint length, `ceil(n/8)` bytes |
| `_choice` | tag (bounds); unknown tag is an error | `3`, vint tag; unknown tag is skipped |
| `_optional` | 1 bit present | `4`, 1 byte present |
| `_struct` | fields in list order (tags ignored) | `5`, vint count, then (vint tag, value) pairs; unknown tags skipped |
| `_fourcc` | 32 bits | `7`, 4 bytes |
| `_null` | nothing | nothing |

`vint`: first byte bit 0 = sign, bits 1-6 = low 6 value bits, bit 7 = more; each next byte gives
7 more bits, little-endian. Sign-magnitude, not zigzag.

Skipping in the versioned format by tag byte: 0 array (n values), 1 bit blob, 2 blob, 3 choice
(tag + value), 4 optional (flag + value), 5 struct (n tag/value pairs), 6 one byte, 7 four bytes,
8 eight bytes, 9 vint.

`__parent` fields: if the decoded value is a struct, merge its fields into the parent; if it is the
only field, it becomes the value. `SStatGameEvent` key/value entries use this.

Struct tags tell the encoding apart: versioned structs use tags 0..n, bit-packed ones negative tags.

## Event framing

```text
gameloop = 0
while not done:
    gameloop += value of svaruint32 (#7: 2-bit tag, then 6/14/22/32 bits; versioned: choice of int)
    userid = replay_userid (#8, {m_userId: int(0,5)})        # game and message streams only
    eventid = instance(eventid type)                          # 7 bits game, 4 bits message, vint tracker
    event = instance(event_types[eventid].typeid)             # unknown id: wrong table or corrupt
    byte_align()
```

## Tracker events (ids)

1 `SUnitBornEvent`, 2 `SUnitDiedEvent`, 3 `SUnitOwnerChangeEvent`, 4 `SUnitTypeChangeEvent`,
5 `SUpgradeEvent`, 6 `SUnitInitEvent`, 7 `SUnitDoneEvent`, 8 `SUnitPositionsEvent`,
9 `SPlayerSetupEvent`, 10 `SStatGameEvent`, 11 `SScoreResultEvent`, 12 `SUnitRevivedEvent`,
13 `SHeroBannedEvent`, 14 `SHeroPickedEvent`, 15 `SHeroSwappedEvent`.

`SStatGameEvent` has `m_eventName` and optional `m_stringData`, `m_intData`, `m_fixedData` lists
of `{m_key, m_value}` (fixed values /4096). Names seen in one 2.57 match: `GameStart`,
`GatesOpen`, `PlayerInit` (Controller, ToonHandle, PlayerID, Team), `PlayerSpawned` (Hero),
`LevelUp`, `TalentChosen` (PurchaseName), `PlayerDeath` (PlayerID, KillingPlayer..., PositionX/Y),
`RegenGlobePickedUp`, `JungleCampInit`, `JungleCampCapture`, `TownStructureInit`,
`TownStructureDeath`, `PeriodicXPBreakdown`, `EndOfGameXPBreakdown`, `EndOfGameTimeSpentDead`,
`EndOfGameTalentChoices` (Hero, Win/Loss, Map, Tier N Choice), `LootSprayUsed`. Map objectives add
their own (`SkyTempleShotsFired`, `GardenTerrorActivated`, ...).

## Game events that matter for mods (ids, 96477)

| Id | Event | Fields |
| --- | --- | --- |
| 7 | `SUserOptionsEvent` | build numbers, cheat flags (`m_developmentCheatsEnabled`, ...), `m_isMapToMapTransition` |
| 9-13 | `SBankFileEvent`, `SBankSectionEvent`, `SBankKeyEvent`, `SBankValueEvent`, `SBankSignatureEvent` | names, typed values, signature + toon handle |
| 26 | `SGameCheatEvent` | verb and arguments |
| 27 | `SCmdEvent` | `m_abil {m_abilLink, m_abilCmdIndex}` (catalog index, changes per build), target point or unit |
| 32 | `STriggerChatMessageEvent` | `m_chatMessage` (up to 1,023 bytes) |
| 55 | `STriggerDialogControlEvent` | `m_controlId`, `m_eventType`, `m_eventData` (Checked, ValueChanged, SelectionChanged, TextChanged up to 2,047 bytes, MouseEvent) |
| 58, 59 | `STriggerMouseClickedEvent`, `STriggerMouseMovedEvent` | UI and world positions |
| 61 | `STriggerHotkeyPressedEvent` | hotkey, down |
| 66 | `STriggerKeyPressedEvent` | `m_key`, `m_flags` (modifiers) |
| 95 | `STriggerButtonPressedEvent` | `m_button` |
| 109 | `SCatalogModifyEvent` | run-time catalog edit (catalog, entry, field, value) |
| 110 | `SHeroTalentTreeSelectedEvent` | `m_index` |

A 2.57 ranked replay already holds about 17,000 key presses and 2,300 dialog events from
Blizzard's own UI, so filter by the control ids your mod creates.

## Message events

0 `SChatMessage` (recipient 0 all, 1 allies, 4 observers), 1 `SPingMessage`, 2
`SLoadingProgressMessage`, 3 `SServerPingMessage`, 4 `SReconnectNotifyMessage`, 5
`SPlayerAnnounceMessage`.

## Attributes stream

Little-endian: u8 source, u32 map namespace, u32 count, then count records of u32 namespace, u32
attribute id, u8 scope, 4-byte value (reversed, NUL-stripped: bytes `74 72 61 50` are `Part`).
Scopes 1-10 are players, 16 is the game. Examples: 3009 game mode, 4002 hero, 4008 hero level,
4023/4025/4028/4030/4043/4045 draft bans.

## Porting checklist

1. Keep type tables as data, keyed by build; fall back to the newest only with a clean-end check.
2. 64-bit reads with unchecked `min + value` (`m_timeUTC` uses `min = -2^63`); big integers for
   wide bit arrays.
3. Merge `__parent` exactly as above.
4. Versioned unknown choice tags and struct tags skip; bit-packed ones throw.
5. Byte-align after every event.
6. Blobs are bytes; names and hero names are UTF-8.
7. Known bugs in Blizzard's Python on 3.x: `/ 8` float division in bit arrays, `imp` import on
   3.12+, `--json` passing bytes to `json.dumps`, and `setup.py`'s console script pointing at a
   module that does not exist (use `python -m heroprotocol`).
