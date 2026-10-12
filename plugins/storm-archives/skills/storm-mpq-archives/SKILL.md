---
name: storm-mpq-archives
description: >-
  MPQ, the archive format behind .StormReplay, .s2ma and packed .stormmap and .StormMod files:
  header versions, user data, encrypted hash and block tables, sectors and compression, listfile
  and attributes. Has a .NET tool to list, extract, unpack, verify and pack. USE FOR: opening or
  building any Storm archive, checking an archive is intact. DO NOT USE FOR: the game's installed
  data (hots-casc-game-files) or replay events (storm-replay-format).
license: MIT
compatibility: scripts/mpq.cs needs the .NET 10 SDK (dotnet run file.cs); it pulls SharpZipLib from NuGet for bzip2.
---

# MPQ archives

Blizzard's MPQ ("Mo'PaQ") format is a single-file archive with an encrypted hash table for name
lookup and a block table for file data. In Heroes of the Storm it holds:

| What | Where | Shape seen |
| --- | --- | --- |
| Replays (`.StormReplay`) | `Documents\Heroes of the Storm\Accounts\...\Replays\` | `MPQ\x1B` user data at 0 (the replay header), MPQ v4 header at 0x400, 16 KiB sectors, every file single-unit bzip2 |
| Battleground maps and depot mods (`.s2ma`) | `C:\ProgramData\Blizzard Entertainment\Battle.net\Cache\xx\yy\<sha256>.s2ma`, `DepotCache` in CASC | MPQ v4 at 0, 16 KiB sectors, single-unit or sectored with sector CRC, zlib/bzip2 |
| Packed maps, mods, interfaces | anywhere | whatever the packer wrote: MPQ Editor via StormMapGenerator wrote v1 with 4 KiB sectors; Galaxy-Observer-UI writes v3 with 16 KiB sectors |

The game's own installed data is not MPQ (it is CASC, `hots-casc-game-files`), and a folder-format
document needs no MPQ at all (`storm-mod-structure`).

## The tool

`scripts/mpq.cs` is a single-file .NET 10 program (reader plus a simple writer):

```powershell
dotnet run scripts/mpq.cs -- info    archive.s2ma          # header, tables, special files, block flags
dotnet run scripts/mpq.cs -- list    archive.s2ma          # size, packed size, flags, name
dotnet run scripts/mpq.cs -- extract archive.s2ma "enUS.StormData\LocalizedData\GameStrings.txt" out.txt
dotnet run scripts/mpq.cs -- unpack  archive.s2ma .\Map.stormmap     # whole archive to a folder
dotnet run scripts/mpq.cs -- verify  replay.StormReplay    # every file against (attributes) CRC32 + MD5
dotnet run scripts/mpq.cs -- pack    .\MyMod.StormMod MyMod.StormMod.mpq
```

Checked on 2026-10-12: `verify` passed on four 2.57 replays (13 of 13 files each) and three
battleground maps from the Battle.net cache; `unpack` then `New-HotsMod.ps1` turned Towers of Doom
into a working folder map; `pack` then `unpack` returned Heroes Rogue's 582 mod files
byte-identical (130 MB folder, 37 MB archive). Whether the game loads a `pack`ed archive is not yet
proven; prefer folders for the game and MPQ Editor for archives you ship.

Find a battleground in the cache by its name: list a `.s2ma`, extract
`enUS.StormData\LocalizedData\GameStrings.txt`, read `DocInfo/Name=` (for example
`Towers of Doom`). A replay names the exact hashes it used (`storm-replay-format`).

## Rules

- **Treat archives as data.** Unpack into a new empty folder; `unpack` refuses names that would
  escape it.
- **Never LZMA.** Galaxy-Observer-UI's author found LZMA-compressed files crash the game on load;
  use zlib (0x02) or bzip2 (0x10).
- **Keep a `(listfile)`.** Without it nothing can list the archive; names can only be probed.
- **Don't commit Blizzard archives or replays.** Replays also carry player names, BattleTags and
  chat.

## How a reader works

1. Scan offsets 0, 0x200, 0x400, ... for `MPQ\x1A` (header) or `MPQ\x1B` (user data, whose u32 at
   +8 is the header offset).
2. Read the header: format version 0..3 (v1..v4), sector size `512 << shift`, hash and block table
   positions (relative to the header) and entry counts. v2 adds high 16 bits for positions and a
   hi-block table, v3 adds 64-bit size and HET/BET positions, v4 adds table sizes and MD5s.
3. Decrypt the hash table with key `HashString("(hash table)", 3)` and the block table with
   `HashString("(block table)", 3)`.
4. Look a name up: start at `HashString(name, 0) & (count - 1)`, probe until `nameA`
   (`HashString(name, 1)`) and `nameB` (type 2) match or an empty slot (block index 0xFFFFFFFF)
   ends the chain. Names use `\`, compare without case.
5. Read the block: flags `0x80000000` exists, `0x200` compressed, `0x100` PKWARE implode,
   `0x10000` encrypted, `0x20000` fix key, `0x1000000` single unit, `0x2000000` delete marker,
   `0x4000000` sector CRC. A sectored file starts with a table of sector offsets; a sector shorter
   than its plain size starts with a compression mask byte (`0x02` zlib, `0x10` bzip2, `0x12`
   LZMA, `0x08` PKWARE, `0x01` Huffman, `0x40`/`0x80` ADPCM, `0x20` sparse).
6. Encrypted files: key `HashString(basename, 3)`, adjusted `(key + offset) ^ size` with fix key;
   the sector table uses `key - 1`, sector n uses `key + n`.

Byte layouts, the crypt table, `(attributes)` and HET/BET are in
[references/mpq-format.md](references/mpq-format.md).

## Other tools

| Tool | Use |
| --- | --- |
| StormLib (C, MIT, Ladislav Zezula) | the reference library; create with `SFileCreateArchive2`, add with `SFileAddFileEx(h, local, "Base.StormData\\X", MPQ_FILE_COMPRESS, MPQ_COMPRESSION_ZLIB, MPQ_COMPRESSION_NEXT_SAME)`, finish with `SFileCloseArchive` (writes the tables, `(listfile)`, `(attributes)`); it cannot write user data |
| Ladik's MPQ Editor (Windows, freeware) | GUI and console: `MPQEditor.exe a out.stormmap folder /c /auto /r`, `e in.stormmap "*" outdir /fp`. Its compression rules come from `%APPDATA%\MPQEditor_Ruleset.ini`; `GameId=11` is its SC2/Heroes preset |
| [MPQExtractor](https://github.com/HeroesReplay/MPQExtractor) (C++, MIT) | CLI over StormLib: `-l` listfile, `-s`/`-e` search or extract by wildcard, `-f` keep paths, `-o` output. Its submodules use dead `git://` URLs: set `submodule.StormLib.url https://github.com/ladislav-zezula/StormLib.git` and `submodule.dirent.url https://github.com/tronkko/dirent.git` before `git submodule update --init`; keep `STORM_UNICODE` off |
| mpyq (Python, read-only) | what Blizzard's heroprotocol uses |

StormLib's `SFileCreateArchive` always adds a `(listfile)`, uses 16 KiB sectors for v3+, and with
`MPQ_CREATE_ATTRIBUTES` writes CRC32, file time and MD5.
