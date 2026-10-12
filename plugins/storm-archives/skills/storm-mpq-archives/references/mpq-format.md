# MPQ byte layouts

All integers little-endian. "Archive offset" is relative to the `MPQ\x1A` header, not the file.
Sources: StormLib (`StormLib.h`, `SBaseCommon.cpp`, `SBaseFileTable.cpp`, `SFileReadFile.cpp`),
zezula.net's format page, and this skill's `mpq.cs`, checked against 2.57 replays and cache maps.

## User data (`MPQ\x1B`)

| Off | Type | Field |
| --- | --- | --- |
| 0x00 | u32 | `0x1B51504D` |
| 0x04 | u32 | space reserved for user data |
| 0x08 | u32 | offset of the MPQ header from this struct |
| 0x0C | u32 | bytes of user data used; the content starts at +0x10 |

Replays: reserved 0x200, header at 0x400, content 0x77 bytes starting with
`Heroes of the Storm replay\x1B11` (the replay header, `storm-replay-format`).

## Header (`MPQ\x1A`)

| Off | Type | Field | From |
| --- | --- | --- | --- |
| 0x00 | u32 | `0x1A51504D` | v1 |
| 0x04 | u32 | header size: 0x20 v1, 0x2C v2, 0x44 v3, 0xD0 v4 | v1 |
| 0x08 | u32 | archive size (unreliable after v1) | v1 |
| 0x0C | u16 | format version 0..3 | v1 |
| 0x0E | u16 | sector size shift (`512 << n`; 3 = 4 KiB, 5 = 16 KiB) | v1 |
| 0x10 | u32 | hash table position (low 32 bits) | v1 |
| 0x14 | u32 | block table position (low 32 bits) | v1 |
| 0x18 | u32 | hash table entries (a power of two) | v1 |
| 0x1C | u32 | block table entries | v1 |
| 0x20 | u64 | hi-block table position (0 when unused) | v2 |
| 0x28 | u16 | hash table position bits 32-47 | v2 |
| 0x2A | u16 | block table position bits 32-47 | v2 |
| 0x2C | u64 | archive size | v3 |
| 0x34 | u64 | BET table position | v3 |
| 0x3C | u64 | HET table position | v3 |
| 0x44 | 5 x u64 | stored sizes of hash, block, hi-block, HET, BET tables | v4 |
| 0x6C | u32 | raw chunk size for MD5s (0x4000) | v4 |
| 0x70 | 6 x 16 | MD5 of block, hash, hi-block, BET, HET tables and of the header | v4 |

Heroes replays and cache maps are v4 and carry both HET/BET and the classic tables; reading the
classic tables is enough.

## Hash table entry (16 bytes, encrypted as one block)

| Off | Type | Field |
| --- | --- | --- |
| 0 | u32 | name hash A (`HashString(name, 1)`) |
| 4 | u32 | name hash B (`HashString(name, 2)`) |
| 8 | u16 | locale (0 = neutral) |
| 10 | u16 | platform |
| 12 | u32 | block index; 0xFFFFFFFF empty (ends a probe), 0xFFFFFFFE deleted (keep probing) |

## Block table entry (16 bytes, encrypted as one block)

| Off | Type | Field |
| --- | --- | --- |
| 0 | u32 | file position (archive offset; v2+: plus hi-block u16 << 32) |
| 4 | u32 | stored size |
| 8 | u32 | file size |
| 12 | u32 | flags |

## Crypt table and hashing

```text
seed = 0x00100001
for i in 0..255:
    for j in 0..4:                       # index = i + j*256
        seed = (seed*125 + 3) % 0x2AAAAB;  hi = (seed & 0xFFFF) << 16
        seed = (seed*125 + 3) % 0x2AAAAB;  table[i + j*256] = hi | (seed & 0xFFFF)

HashString(s, type):                     # type 0 index, 1 name A, 2 name B, 3 file key
    s1 = 0x7FED7FED; s2 = 0xEEEEEEEE
    for c in upper(s):                   # '/' should already be '\'
        s1 = table[type*256 + c] ^ (s1 + s2)
        s2 = c + s1 + s2 + (s2 << 5) + 3
    return s1

Decrypt(u32[] data, key):
    s = 0xEEEEEEEE
    for each v:
        s += table[0x400 + (key & 0xFF)]
        p = v ^ (key + s)
        key = ((~key << 0x15) + 0x11111111) | (key >> 0x0B)
        s = p + s + (s << 5) + 3
        v = p
```

Encrypt is the same loop, feeding the plain value (not the cipher) into `s`. Table keys:
`HashString("(hash table)", 3)` and `HashString("(block table)", 3)`.

## File data

- **Single unit** (`0x01000000`): the whole file is one blob; compressed when stored size is less
  than file size, with one leading mask byte.
- **Sectored**: `ceil(size / sectorSize)` sectors. A compressed file starts with `sectors + 1` u32
  offsets (plus one more with sector CRC `0x04000000`; the CRC block sits after the last sector).
  Each sector whose stored length is less than its plain length starts with a mask byte.
- **Masks**: `0x02` zlib (a zlib stream with header), `0x10` bzip2, `0x12` LZMA, `0x08` PKWARE DCL,
  `0x01` Huffman, `0x40`/`0x80` ADPCM mono/stereo, `0x20` sparse. Several bits mean a chain
  (decompress in StormLib's fixed order).
- **Encryption**: key `HashString(name after the last '\', 3)`; with fix key `0x20000`:
  `(key + filePosition) ^ fileSize`. The sector offset table is decrypted with `key - 1`, sector n
  with `key + n`.
- **Imploded** (`0x100`) is the old PKWARE-only flag; Storm archives use `0x200`.

## Special files

| Name | Content |
| --- | --- |
| `(listfile)` | names separated by CR, LF or `;` |
| `(attributes)` | u32 version (100), u32 flags (1 CRC32, 2 file time, 4 MD5, 8 patch bit), then per block-table entry: CRC32 array, FILETIME array, MD5 array, patch bit array, each present only when its flag is set. The entry for `(attributes)` itself is zero |
| `(signature)` | weak signature (not seen in Heroes files) |
| `(user data)` | not a file; the `MPQ\x1B` block |

Replays use flags 5 (CRC32 + MD5); StormLib's default is 7. Without a listfile, names can only be
found by hashing candidate names (a community listfile or names you expect, such as
`DocumentInfo`, `MapScript.galaxy`, `ComponentList.StormComponents`).

## HET and BET (v3+)

The HET table hashes names with Jenkins `hashlittle2` into 8-bit fragments with a BET index; the
BET table packs block entries into bit fields. Both are themselves encrypted and, in v4,
compressed. Heroes archives still carry the classic tables, so a reader can ignore HET/BET.
