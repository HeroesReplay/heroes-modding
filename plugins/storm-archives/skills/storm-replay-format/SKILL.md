---
name: storm-replay-format
description: >-
  The Heroes of the Storm .StormReplay format and Blizzard's heroprotocol: MPQ container and
  header, the replay.* streams, bit-packed and versioned decoders, protocol tables per build,
  tracker stats, game and trigger events, bank events, map and mod references, game loops. Has a
  .NET decoder that reads heroprotocol tables. USE FOR: reading or porting replay data, finding
  what a mod records. DO NOT USE FOR: live client memory (hots-client-observation).
license: MIT
compatibility: scripts/replay.cs needs the .NET 10 SDK and a clone of Blizzard/heroprotocol for its protocol tables.
---

# The .StormReplay format

A replay is an MPQ archive (`storm-mpq-archives`) with a user-data block in front. The user data
is the replay header; the archive holds `replay.*` streams that the client re-simulates on
playback. [Blizzard/heroprotocol](https://github.com/Blizzard/heroprotocol) (MIT) is the official
decoder: one generated `versions/protocol<build>.py` per published build, plus `decoders.py`.

## Rules

- **Replays are personal data.** They carry player names, BattleTags, toon handles and chat
  (`STriggerChatMessageEvent` can hold both teams' chat). Never commit replays or decoded dumps;
  test against local files only.
- **Decode with the table of the replay's `m_baseBuild`.** When the build is newer than every
  table, the newest table may work (the tables have been byte-identical from 85027 to 96477), but
  only trust it if every stream ends exactly at the end of its data with no corruption error.
- **Event ids are stable across builds; type ids are not.** Never hard-code a type id.

## Decode a replay

```powershell
git clone https://github.com/Blizzard/heroprotocol.git C:\work\heroprotocol
$p = 'C:\work\heroprotocol\heroprotocol\versions'
dotnet run scripts/replay.cs -- $p game.StormReplay header             # version, length, build
dotnet run scripts/replay.cs -- $p game.StormReplay details            # players, map title, cache handles
dotnet run scripts/replay.cs -- $p game.StormReplay tracker --stats    # event counts
dotnet run scripts/replay.cs -- $p game.StormReplay tracker --event SStatGameEvent
dotnet run scripts/replay.cs -- $p game.StormReplay game --event STriggerDialogControlEvent
```

Output is one JSON object per line (`_event`, `_eventid`, `_gameloop`, `_userid`, then fields).
Blobs print as text when they are printable UTF-8, else `{"hex": ...}`. Checked on 2026-10-12 with
the 96477 table against two 2.57.0.98304 replays: header, details, initdata, attributes, 5,402
tracker, 94,527 game and 124 message events, all ending cleanly. Blizzard's own CLI
(`python -m heroprotocol`, Python 3.11 or older because it imports `imp`) refuses such replays with
"Unsupported base build".

## Layout

| Part | Decoder | Holds |
| --- | --- | --- |
| user data (`MPQ\x1B` at 0, 0x77 bytes) | versioned, `replay_header_typeid` | `m_version` (`m_baseBuild` picks the table), `m_elapsedGameLoops`, `m_dataBuildNum`, `m_ngdpRootKey` |
| `replay.details` | versioned, `game_details_typeid` | players (name, toon, team, result, localized hero), localized map title, `m_cacheHandles`, `m_isBlizzardMap`, `m_mapFileName`, time |
| `replay.initData` | bit-packed, `replay_initdata_typeid` | lobby state: game options, slots (hero, skin, mount, banner, spray), `m_gameDescription` (map checksums, cache handles, `m_isBlizzardMap`) |
| `replay.attributes.events` | little-endian records | 4-character lobby attributes by scope (mode, bans, hero) |
| `replay.tracker.events` | versioned, no user id | server-side stats: unit born/died/owner, `SStatGameEvent`, `SScoreResultEvent`, draft |
| `replay.game.events` | bit-packed, with user id | every synchronized input: commands, camera, selection, talents, trigger (UI) events, bank events |
| `replay.message.events` | bit-packed, with user id | chat, pings, loading progress, as the recording client saw them |
| `replay.server.battlelobby`, `.load.info`, `.sync.events`, `.smartcam.events`, `.resumable.events` | not in heroprotocol | lobby (starts with the local cache paths of every handle), others undocumented |

Every replay file is single-unit bzip2. Decoder grammar, event framing and the porting checklist
are in [references/replay-protocol.md](references/replay-protocol.md).

## Time

- 16 game loops per second.
- `SStatGameEvent` `GatesOpen` is the in-game 0:00; it fired at loop 610 in every replay checked.
  Read it rather than hard-coding 610: match time = `(loop - gatesOpenLoop) / 16`. Tracker
  `GameTime` values (fixed point, /4096) agree exactly.
- `m_elapsedGameLoops` is the recorded length, not the match length.
- The live client's match clock (HeroesClientSDK, ticks/4096) is a different source; don't mix
  the two without calibrating.

## Things that differ from heroprotocol's README

- **Unit tags:** in 2.55-2.57 replays a game-event unit tag is `(trackerIndex << 22) | recycle`,
  not the `unit_tag()` helper's `<< 18` (1,177 of 1,177 tags matched).
- **Score arrays:** in `SScoreResultEvent`, index `i` is tracker player id `i + 1`.
- **Positions:** `SUnitPositionsEvent` items are already map cells; the README's `x4` puts units
  off the map.
- **Player ids:** tracker `PlayerID` is 1-based (11 and 12 are the team AI owners); the event
  `_userid` is the 0-based lobby user; `SPlayerSetupEvent` maps the two.

## What a mod leaves in a replay

- **UI and input:** dialog clicks (`STriggerDialogControlEvent`: control id, event type, data),
  key presses (`STriggerKeyPressedEvent`), chat commands (`STriggerChatMessageEvent`), mouse and
  button events. Control ids are run-time handles, so map them with the mod's own knowledge.
- **Stats:** `StatEventCreate`/`StatEventSend` in Galaxy produce `SStatGameEvent` entries with
  your name and keys (Blizzard's: `PlayerDeath`, `TalentChosen`, `EndOfGameTalentChoices`, ...).
- **Banks:** `SBankFile/Section/Key/Value/SignatureEvent` game events (names up to 127 bytes,
  values up to 4,095). A ranked replay has none; by analogy with StarCraft II a map that loads a
  bank streams it here, so bank contents are readable from the replay (not yet seen in a Heroes
  replay).
- **Map and mods:** Blizzard maps appear as 40-byte cache handles (`s2ma`, region, SHA-256)
  pointing at `C:\ProgramData\Blizzard Entertainment\Battle.net\Cache\xx\yy\<sha256>.s2ma`; core
  mods are small "Standard Data: X.StormMod" stubs, the map and its map mod are real MPQs. For a
  local or replaced map, whether a replay is written and what `m_mapFileName`, `m_isBlizzardMap`
  and the handles contain is not yet known; a replay re-simulates inputs, so playback needs the
  identical map and mod files.

## .NET libraries

`HeroesReplay/Heroes.StormReplayParser` and `HeroesReplay/Heroes.ReplayParser` (forks; the latter
is the NuGet package HeroesReplay uses) are hand-written parsers with build checks, so a new build
can mis-parse silently instead of failing. A table-driven decoder (this skill's tool, or the Rust
`storm-codex`) fails loudly instead.
