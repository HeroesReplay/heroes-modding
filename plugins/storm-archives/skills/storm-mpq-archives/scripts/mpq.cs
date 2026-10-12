#!/usr/bin/env dotnet
#:package SharpZipLib@1.4.2
// MPQ reader and simple writer for Storm archives (.StormReplay, .stormmap, .stormmod,
// .StormInterface, .s2ma, .SC2Map, .SC2Replay ...). Needs the .NET 10 SDK. Usage:
//   dotnet run mpq.cs -- info    <archive>
//   dotnet run mpq.cs -- list    <archive> [--listfile <file>]
//   dotnet run mpq.cs -- extract <archive> <name> [<out-file>]
//   dotnet run mpq.cs -- unpack  <archive> <out-dir> [--listfile <file>]
//   dotnet run mpq.cs -- verify  <archive> [--listfile <file>]
//   dotnet run mpq.cs -- pack    <folder> <out-archive>
// Hash and block tables (header v1-v4), user data header (MPQ\x1B), encrypted files with or
// without FIX_KEY, single-unit and sectored files, sector CRC, zlib (0x02) and bzip2 (0x10).
// It reports LZMA, PKWARE, Huffman and ADPCM sectors as unsupported instead of guessing.
// verify checks every file against the archive's own (attributes) CRC32 and MD5. pack writes a
// format-1 archive (zlib sectors, (listfile), (attributes)); it round-trips with this reader, but
// the game loading it is not yet proven.
using System.IO.Compression;
using System.Text;
using ICSharpCode.SharpZipLib.BZip2;

if (args.Length < 2)
{
    Console.Error.WriteLine("usage: mpq.cs info|list|extract|unpack|verify <archive> [...] [--listfile <file>] | pack <folder> <out-archive>");
    return 2;
}

string command = args[0];
string archivePath = args[1];
string? extraListfile = null;
var positional = new List<string>();
for (int i = 2; i < args.Length; i++)
{
    if (args[i] == "--listfile" && i + 1 < args.Length)
    {
        extraListfile = args[++i];
    }
    else
    {
        positional.Add(args[i]);
    }
}

if (command == "pack")
{
    // pack <source-folder> <out-archive>: the folder is args[1] here, the archive the first positional.
    if (positional.Count < 1)
    {
        Console.Error.WriteLine("pack needs a source folder and an output archive");
        return 2;
    }
    int files = MpqWriter.Pack(archivePath, positional[0]);
    Console.WriteLine($"{files} files packed into {positional[0]}");
    return 0;
}

try
{
    using var archive = MpqArchive.Open(archivePath);
    switch (command)
    {
        case "info":
            archive.PrintInfo(Console.Out);
            return 0;
        case "list":
            foreach (var (name, block) in archive.Names(extraListfile))
            {
                Console.WriteLine($"{block.FileSize,12} {block.CompressedSize,12} 0x{block.Flags:X8} {name}");
            }
            return 0;
        case "extract":
            {
                if (positional.Count < 1)
                {
                    Console.Error.WriteLine("extract needs a file name inside the archive");
                    return 2;
                }
                byte[] data = archive.Read(positional[0]);
                if (positional.Count > 1)
                {
                    File.WriteAllBytes(positional[1], data);
                }
                else
                {
                    using var stdout = Console.OpenStandardOutput();
                    stdout.Write(data);
                }
                return 0;
            }
        case "unpack":
            {
                if (positional.Count < 1)
                {
                    Console.Error.WriteLine("unpack needs an output folder");
                    return 2;
                }
                string root = Path.GetFullPath(positional[0]);
                int ok = 0, failed = 0;
                foreach (var (name, _) in archive.Names(extraListfile))
                {
                    string target = Path.GetFullPath(Path.Combine(root, name.Replace('\\', Path.DirectorySeparatorChar)));
                    if (!target.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
                    {
                        Console.Error.WriteLine($"skip (path escapes the output folder): {name}");
                        failed++;
                        continue;
                    }
                    try
                    {
                        byte[] data = archive.Read(name);
                        Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                        File.WriteAllBytes(target, data);
                        ok++;
                    }
                    catch (MpqException e)
                    {
                        Console.Error.WriteLine($"skip {name}: {e.Message}");
                        failed++;
                    }
                }
                Console.WriteLine($"{ok} files written to {root}, {failed} skipped");
                return failed == 0 ? 0 : 1;
            }
        case "verify":
            return archive.Verify(extraListfile, Console.Out) ? 0 : 1;
        default:
            Console.Error.WriteLine($"unknown command {command}");
            return 2;
    }
}
catch (MpqException e)
{
    Console.Error.WriteLine($"error: {e.Message}");
    return 1;
}

sealed class MpqException(string message) : Exception(message);

readonly record struct HashEntry(uint NameA, uint NameB, ushort Locale, ushort Platform, uint BlockIndex);

readonly record struct BlockEntry(long FilePos, uint CompressedSize, uint FileSize, uint Flags);

sealed class MpqArchive : IDisposable
{
    const uint FileImplode = 0x00000100;
    const uint FileCompress = 0x00000200;
    const uint FileEncrypted = 0x00010000;
    const uint FileFixKey = 0x00020000;
    const uint FilePatch = 0x00100000;
    const uint FileSingleUnit = 0x01000000;
    const uint FileDeleteMarker = 0x02000000;
    const uint FileSectorCrc = 0x04000000;
    const uint FileExists = 0x80000000;

    const uint HashEmpty = 0xFFFFFFFF;
    const uint HashDeleted = 0xFFFFFFFE;

    static readonly uint[] CryptTable = BuildCryptTable();

    readonly FileStream stream;
    readonly long headerOffset;
    readonly long userDataOffset = -1;
    readonly uint userDataSize;
    readonly ushort formatVersion;
    readonly uint headerSize;
    readonly int sectorSize;
    readonly HashEntry[] hashTable;
    readonly BlockEntry[] blockTable;
    readonly long hetOffset;
    readonly long betOffset;

    MpqArchive(string path)
    {
        stream = File.OpenRead(path);
        var reader = new BinaryReader(stream);
        headerOffset = -1;
        for (long offset = 0; offset + 32 <= stream.Length; offset += 0x200)
        {
            stream.Position = offset;
            uint magic = reader.ReadUInt32();
            if (magic == 0x1B51504D) // "MPQ\x1B": user data, then the real header further on
            {
                userDataOffset = offset;
                userDataSize = reader.ReadUInt32();
                uint shunt = reader.ReadUInt32();
                headerOffset = offset + shunt;
                break;
            }
            if (magic == 0x1A51504D) // "MPQ\x1A"
            {
                headerOffset = offset;
                break;
            }
        }
        if (headerOffset < 0)
        {
            throw new MpqException("no MPQ header found (is this a folder-format document or a CASC file?)");
        }

        stream.Position = headerOffset;
        if (reader.ReadUInt32() != 0x1A51504D)
        {
            throw new MpqException($"user data points at 0x{headerOffset:X} but no MPQ\\x1A header is there");
        }
        headerSize = reader.ReadUInt32();
        reader.ReadUInt32(); // archive size (32-bit, unreliable past v1)
        formatVersion = reader.ReadUInt16();
        sectorSize = 512 << reader.ReadUInt16();
        long hashPos = reader.ReadUInt32();
        long blockPos = reader.ReadUInt32();
        uint hashCount = reader.ReadUInt32();
        uint blockCount = reader.ReadUInt32();
        long hiBlockPos = 0;
        if (formatVersion >= 1 && headerSize >= 0x2C)
        {
            hiBlockPos = reader.ReadInt64();
            hashPos |= (long)reader.ReadUInt16() << 32;
            blockPos |= (long)reader.ReadUInt16() << 32;
        }
        if (formatVersion >= 2 && headerSize >= 0x44)
        {
            reader.ReadInt64(); // 64-bit archive size
            betOffset = reader.ReadInt64();
            hetOffset = reader.ReadInt64();
        }

        hashTable = new HashEntry[hashCount];
        uint[] rawHash = ReadEncryptedTable(reader, headerOffset + hashPos, hashCount * 4, HashString("(hash table)", 3));
        for (int i = 0; i < hashCount; i++)
        {
            hashTable[i] = new HashEntry(
                rawHash[i * 4],
                rawHash[i * 4 + 1],
                (ushort)(rawHash[i * 4 + 2] & 0xFFFF),
                (ushort)(rawHash[i * 4 + 2] >> 16),
                rawHash[i * 4 + 3]
            );
        }

        uint[] rawBlock = ReadEncryptedTable(reader, headerOffset + blockPos, blockCount * 4, HashString("(block table)", 3));
        ushort[]? hiBlock = null;
        if (hiBlockPos != 0)
        {
            stream.Position = headerOffset + hiBlockPos;
            hiBlock = new ushort[blockCount];
            for (int i = 0; i < blockCount; i++)
            {
                hiBlock[i] = reader.ReadUInt16();
            }
        }
        blockTable = new BlockEntry[blockCount];
        for (int i = 0; i < blockCount; i++)
        {
            long pos = rawBlock[i * 4] | ((long)(hiBlock?[i] ?? 0) << 32);
            blockTable[i] = new BlockEntry(pos, rawBlock[i * 4 + 1], rawBlock[i * 4 + 2], rawBlock[i * 4 + 3]);
        }
    }

    public static MpqArchive Open(string path)
    {
        if (Directory.Exists(path))
        {
            throw new MpqException($"{path} is a folder: a folder-format document needs no MPQ tool");
        }
        return new MpqArchive(path);
    }

    public void Dispose() => stream.Dispose();

    public void PrintInfo(TextWriter output)
    {
        if (userDataOffset >= 0)
        {
            output.WriteLine($"user data      MPQ\\x1B at 0x{userDataOffset:X}, {userDataSize} bytes reserved");
        }
        output.WriteLine($"header         MPQ\\x1A at 0x{headerOffset:X}, size 0x{headerSize:X}, format version {formatVersion + 1}");
        output.WriteLine($"sector size    {sectorSize}");
        output.WriteLine($"hash table     {hashTable.Length} entries, {hashTable.Count(h => h.BlockIndex < HashDeleted)} used");
        output.WriteLine($"block table    {blockTable.Length} entries, {blockTable.Count(b => (b.Flags & FileExists) != 0)} files");
        output.WriteLine($"HET/BET        {(hetOffset != 0 || betOffset != 0 ? $"present (HET 0x{hetOffset:X}, BET 0x{betOffset:X}); this tool uses the classic tables" : "none")}");
        foreach (string special in new[] { "(listfile)", "(attributes)", "(signature)", "(user data)" })
        {
            output.WriteLine($"{special,-14} {(TryFind(special, out _) ? "yes" : "no")}");
        }
        var flags = blockTable.Where(b => (b.Flags & FileExists) != 0)
            .GroupBy(b => b.Flags)
            .OrderByDescending(g => g.Count())
            .Select(g => $"0x{g.Key:X8} x{g.Count()}");
        output.WriteLine($"block flags    {string.Join(", ", flags)}");
    }

    /// <summary>Every name from (listfile) and the extra listfile that resolves to an existing file.</summary>
    public IEnumerable<(string Name, BlockEntry Block)> Names(string? extraListfile)
    {
        var names = new SortedSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "(listfile)",
            "(attributes)",
            "(signature)",
            "(user data)",
        };
        if (TryFind("(listfile)", out _))
        {
            AddNames(names, Encoding.UTF8.GetString(Read("(listfile)")));
        }
        if (extraListfile != null)
        {
            AddNames(names, File.ReadAllText(extraListfile));
        }
        var seen = new HashSet<uint>();
        foreach (string name in names)
        {
            if (TryFind(name, out uint index) && seen.Add(index))
            {
                yield return (name, blockTable[index]);
            }
        }
        int unnamed = blockTable.Count(b => (b.Flags & FileExists) != 0) - seen.Count;
        if (unnamed > 0)
        {
            Console.Error.WriteLine($"{unnamed} files have no name in the listfile (pass --listfile with more names)");
        }
    }

    /// <summary>
    /// Reads every named file and checks it against the CRC32 and MD5 that (attributes) keeps per
    /// block (version 100: flags, then a CRC32 array, a FILETIME array and an MD5 array, each
    /// present when its flag bit 1, 2 or 4 is set).
    /// </summary>
    public bool Verify(string? extraListfile, TextWriter output)
    {
        if (!TryFind("(attributes)", out _))
        {
            output.WriteLine("no (attributes) file: nothing to verify against");
            return false;
        }
        byte[] attributes = Read("(attributes)");
        uint flags = BitConverter.ToUInt32(attributes, 4);
        int count = blockTable.Length;
        int offset = 8;
        int crcOffset = (flags & 1) != 0 ? offset : -1;
        offset += (flags & 1) != 0 ? count * 4 : 0;
        offset += (flags & 2) != 0 ? count * 8 : 0;
        int md5Offset = (flags & 4) != 0 ? offset : -1;

        int good = 0, bad = 0;
        foreach (var (name, _) in Names(extraListfile))
        {
            if (name is "(attributes)" or "(signature)")
            {
                continue;
            }
            TryFind(name, out uint index);
            byte[] data = Read(name);
            var problems = new List<string>();
            if (crcOffset >= 0)
            {
                uint expected = BitConverter.ToUInt32(attributes, crcOffset + (int)index * 4);
                var crc = new ICSharpCode.SharpZipLib.Checksum.Crc32();
                crc.Update(data);
                if (expected != 0 && expected != (uint)crc.Value)
                {
                    problems.Add($"crc32 0x{crc.Value:X8} != 0x{expected:X8}");
                }
            }
            if (md5Offset >= 0)
            {
                byte[] expected = attributes[(md5Offset + (int)index * 16)..(md5Offset + (int)index * 16 + 16)];
                if (expected.Any(b => b != 0) && !System.Security.Cryptography.MD5.HashData(data).SequenceEqual(expected))
                {
                    problems.Add("md5 differs");
                }
            }
            if (problems.Count == 0)
            {
                good++;
            }
            else
            {
                bad++;
                output.WriteLine($"BAD  {name}: {string.Join(", ", problems)}");
            }
        }
        output.WriteLine($"{good} files match (attributes), {bad} do not");
        return bad == 0;
    }

    static void AddNames(SortedSet<string> names, string text)
    {
        foreach (string line in text.Split(['\r', '\n', ';'], StringSplitOptions.RemoveEmptyEntries))
        {
            string name = line.Trim();
            if (name.Length > 0)
            {
                names.Add(name.Replace('/', '\\'));
            }
        }
    }

    public bool TryFind(string name, out uint blockIndex)
    {
        blockIndex = 0;
        if (hashTable.Length == 0)
        {
            return false;
        }
        name = name.Replace('/', '\\');
        uint mask = (uint)hashTable.Length - 1;
        uint start = HashString(name, 0) & mask;
        uint nameA = HashString(name, 1);
        uint nameB = HashString(name, 2);
        for (uint i = start, n = 0; n < hashTable.Length; i = (i + 1) & mask, n++)
        {
            HashEntry entry = hashTable[i];
            if (entry.BlockIndex == HashEmpty)
            {
                return false;
            }
            if (entry.NameA == nameA && entry.NameB == nameB && entry.BlockIndex < blockTable.Length)
            {
                if ((blockTable[entry.BlockIndex].Flags & FileDeleteMarker) != 0)
                {
                    return false;
                }
                blockIndex = entry.BlockIndex;
                return true;
            }
        }
        return false;
    }

    public byte[] Read(string name)
    {
        name = name.Replace('/', '\\');
        if (!TryFind(name, out uint index))
        {
            throw new MpqException($"{name} is not in the archive");
        }
        BlockEntry block = blockTable[index];
        if ((block.Flags & FileExists) == 0)
        {
            throw new MpqException($"{name}: block has no EXISTS flag");
        }
        if ((block.Flags & FilePatch) != 0)
        {
            throw new MpqException($"{name}: patch files are not supported");
        }
        if ((block.Flags & FileImplode) != 0)
        {
            throw new MpqException($"{name}: PKWARE imploded files are not supported");
        }

        uint key = 0;
        if ((block.Flags & FileEncrypted) != 0)
        {
            string baseName = name[(name.LastIndexOf('\\') + 1)..];
            key = HashString(baseName, 3);
            if ((block.Flags & FileFixKey) != 0)
            {
                key = (key + (uint)block.FilePos) ^ block.FileSize;
            }
        }

        stream.Position = headerOffset + block.FilePos;
        byte[] raw = new byte[block.CompressedSize];
        stream.ReadExactly(raw);

        bool compressed = (block.Flags & FileCompress) != 0;
        if ((block.Flags & FileSingleUnit) != 0 || block.FileSize == 0)
        {
            if (key != 0)
            {
                Decrypt(raw, key);
            }
            return compressed && block.CompressedSize < block.FileSize
                ? Decompress(raw, (int)block.FileSize, name)
                : raw[..(int)Math.Min(block.FileSize, (uint)raw.Length)];
        }

        int sectors = (int)((block.FileSize + sectorSize - 1) / sectorSize);
        var output = new byte[block.FileSize];
        if (!compressed)
        {
            for (int s = 0; s < sectors; s++)
            {
                int start = s * sectorSize;
                int length = (int)Math.Min(sectorSize, block.FileSize - start);
                byte[] sector = raw[start..(start + length)];
                if (key != 0)
                {
                    Decrypt(sector, key + (uint)s);
                }
                sector.CopyTo(output, start);
            }
            return output;
        }

        int entries = sectors + 1 + ((block.Flags & FileSectorCrc) != 0 ? 1 : 0);
        byte[] table = raw[..(entries * 4)];
        if (key != 0)
        {
            Decrypt(table, key - 1);
        }
        for (int s = 0; s < sectors; s++)
        {
            int from = BitConverter.ToInt32(table, s * 4);
            int to = BitConverter.ToInt32(table, (s + 1) * 4);
            int expected = (int)Math.Min(sectorSize, block.FileSize - (long)s * sectorSize);
            byte[] sector = raw[from..to];
            if (key != 0)
            {
                Decrypt(sector, key + (uint)s);
            }
            byte[] plain = sector.Length < expected ? Decompress(sector, expected, name) : sector;
            plain.CopyTo(output, s * sectorSize);
        }
        return output;
    }

    static byte[] Decompress(byte[] data, int expected, string name)
    {
        byte mask = data[0];
        using var input = new MemoryStream(data, 1, data.Length - 1);
        using var result = new MemoryStream(expected);
        switch (mask)
        {
            case 0x02:
                using (var z = new ZLibStream(input, CompressionMode.Decompress))
                {
                    z.CopyTo(result);
                }
                break;
            case 0x10:
                BZip2.Decompress(input, result, false);
                break;
            default:
                throw new MpqException($"{name}: compression mask 0x{mask:X2} is not supported (0x02 zlib and 0x10 bzip2 are)");
        }
        if (result.Length != expected)
        {
            throw new MpqException($"{name}: decompressed {result.Length} bytes, expected {expected}");
        }
        return result.ToArray();
    }

    uint[] ReadEncryptedTable(BinaryReader reader, long position, long count, uint key)
    {
        stream.Position = position;
        byte[] bytes = reader.ReadBytes((int)(count * 4));
        if (bytes.Length != count * 4)
        {
            throw new MpqException($"table at 0x{position:X} runs past the end of the file");
        }
        Decrypt(bytes, key);
        var values = new uint[count];
        Buffer.BlockCopy(bytes, 0, values, 0, bytes.Length);
        return values;
    }

    static uint[] BuildCryptTable()
    {
        var table = new uint[0x500];
        uint seed = 0x00100001;
        for (int i = 0; i < 0x100; i++)
        {
            for (int j = 0, index = i; j < 5; j++, index += 0x100)
            {
                seed = (seed * 125 + 3) % 0x2AAAAB;
                uint high = (seed & 0xFFFF) << 16;
                seed = (seed * 125 + 3) % 0x2AAAAB;
                table[index] = high | (seed & 0xFFFF);
            }
        }
        return table;
    }

    /// <summary>Type 0 = hash table index, 1 = name A, 2 = name B, 3 = file key.</summary>
    public static uint HashString(string text, int type)
    {
        uint seed1 = 0x7FED7FED;
        uint seed2 = 0xEEEEEEEE;
        foreach (char c in text.ToUpperInvariant())
        {
            uint ch = (byte)c;
            seed1 = CryptTable[(type << 8) + ch] ^ (seed1 + seed2);
            seed2 = ch + seed1 + seed2 + (seed2 << 5) + 3;
        }
        return seed1;
    }

    public static void Encrypt(byte[] data, uint key)
    {
        uint seed = 0xEEEEEEEE;
        for (int i = 0; i + 4 <= data.Length; i += 4)
        {
            seed += CryptTable[0x400 + (key & 0xFF)];
            uint plain = BitConverter.ToUInt32(data, i);
            BitConverter.TryWriteBytes(data.AsSpan(i), plain ^ (key + seed));
            key = ((~key << 0x15) + 0x11111111) | (key >> 0x0B);
            seed = plain + seed + (seed << 5) + 3;
        }
    }

    static void Decrypt(byte[] data, uint key)
    {
        uint seed = 0xEEEEEEEE;
        for (int i = 0; i + 4 <= data.Length; i += 4)
        {
            seed += CryptTable[0x400 + (key & 0xFF)];
            uint value = BitConverter.ToUInt32(data, i) ^ (key + seed);
            key = ((~key << 0x15) + 0x11111111) | (key >> 0x0B);
            seed = value + seed + (seed << 5) + 3;
            BitConverter.TryWriteBytes(data.AsSpan(i), value);
        }
    }
}

/// <summary>
/// Writes a format-1 MPQ (32-byte header, classic hash and block tables) from a folder: every file
/// sectored, each sector zlib-compressed when that makes it smaller, plus (listfile) and
/// (attributes) with CRC32 and MD5. No file encryption, no HET/BET. Good for tests and for
/// shipping a folder as one archive; the game's own archives are format 3 or 4.
/// </summary>
static class MpqWriter
{
    const int SectorShift = 5; // 512 << 5 = 16 KiB sectors, as Blizzard's replays use
    const uint FileCompress = 0x00000200;
    const uint FileExists = 0x80000000;

    public static int Pack(string folder, string archivePath)
    {
        string root = Path.GetFullPath(folder);
        if (!Directory.Exists(root))
        {
            throw new MpqException($"{root} is not a folder");
        }
        var entries = Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories)
            .Select(path => (Name: Path.GetRelativePath(root, path).Replace('/', '\\'), Data: File.ReadAllBytes(path)))
            .Where(e => e.Name is not "(listfile)" and not "(attributes)")
            .OrderBy(e => e.Name, StringComparer.OrdinalIgnoreCase)
            .ToList();
        byte[] listfile = Encoding.UTF8.GetBytes(string.Join("\r\n", entries.Select(e => e.Name)) + "\r\n");
        entries.Add(("(listfile)", listfile));

        // (attributes) covers every block, itself included (its own CRC and MD5 stay zero).
        int blockCount = entries.Count + 1;
        byte[] attributes = new byte[8 + blockCount * (4 + 16)];
        BitConverter.TryWriteBytes(attributes.AsSpan(0), 100u);
        BitConverter.TryWriteBytes(attributes.AsSpan(4), 1u | 4u);
        for (int i = 0; i < entries.Count; i++)
        {
            var crc = new ICSharpCode.SharpZipLib.Checksum.Crc32();
            crc.Update(entries[i].Data);
            BitConverter.TryWriteBytes(attributes.AsSpan(8 + i * 4), (uint)crc.Value);
            System.Security.Cryptography.MD5.HashData(entries[i].Data).CopyTo(attributes, 8 + blockCount * 4 + i * 16);
        }
        entries.Add(("(attributes)", attributes));

        int hashCount = 16;
        while (hashCount < entries.Count * 2)
        {
            hashCount <<= 1;
        }

        using var output = new MemoryStream();
        output.Write(new byte[32]); // header, written last
        var blocks = new List<(uint Pos, uint Compressed, uint Size, uint Flags)>();
        foreach (var (_, data) in entries)
        {
            uint pos = (uint)output.Position;
            byte[] stored = Compress(data);
            output.Write(stored);
            blocks.Add((pos, (uint)stored.Length, (uint)data.Length, FileExists | FileCompress));
        }

        var hash = new uint[hashCount * 4];
        Array.Fill(hash, 0xFFFFFFFF);
        for (int i = 0; i < entries.Count; i++)
        {
            string name = entries[i].Name;
            uint slot = MpqArchive.HashString(name, 0) & (uint)(hashCount - 1);
            while (hash[slot * 4 + 3] != 0xFFFFFFFF)
            {
                slot = (slot + 1) & (uint)(hashCount - 1);
            }
            hash[slot * 4] = MpqArchive.HashString(name, 1);
            hash[slot * 4 + 1] = MpqArchive.HashString(name, 2);
            hash[slot * 4 + 2] = 0; // locale neutral, platform 0
            hash[slot * 4 + 3] = (uint)i;
        }

        uint hashPos = (uint)output.Position;
        output.Write(EncryptTable(hash, MpqArchive.HashString("(hash table)", 3)));
        uint blockPos = (uint)output.Position;
        var block = blocks.SelectMany(b => new[] { b.Pos, b.Compressed, b.Size, b.Flags }).ToArray();
        output.Write(EncryptTable(block, MpqArchive.HashString("(block table)", 3)));

        byte[] archive = output.ToArray();
        var header = archive.AsSpan(0, 32);
        BitConverter.TryWriteBytes(header[0..], 0x1A51504Du);
        BitConverter.TryWriteBytes(header[4..], 32u);
        BitConverter.TryWriteBytes(header[8..], (uint)archive.Length);
        BitConverter.TryWriteBytes(header[12..], (ushort)0);
        BitConverter.TryWriteBytes(header[14..], (ushort)SectorShift);
        BitConverter.TryWriteBytes(header[16..], hashPos);
        BitConverter.TryWriteBytes(header[20..], blockPos);
        BitConverter.TryWriteBytes(header[24..], (uint)hashCount);
        BitConverter.TryWriteBytes(header[28..], (uint)blocks.Count);
        File.WriteAllBytes(archivePath, archive);
        return entries.Count - 2;
    }

    /// <summary>Sector offset table, then each sector: 0x02 + zlib when smaller, else raw.</summary>
    static byte[] Compress(byte[] data)
    {
        if (data.Length == 0)
        {
            return [];
        }
        int sectorSize = 512 << SectorShift;
        int sectors = (data.Length + sectorSize - 1) / sectorSize;
        var body = new MemoryStream();
        var offsets = new uint[sectors + 1];
        uint tableSize = (uint)(offsets.Length * 4);
        for (int s = 0; s < sectors; s++)
        {
            offsets[s] = tableSize + (uint)body.Length;
            var plain = data.AsSpan(s * sectorSize, Math.Min(sectorSize, data.Length - s * sectorSize));
            var packed = new MemoryStream();
            packed.WriteByte(0x02);
            using (var z = new ZLibStream(packed, CompressionLevel.Optimal, leaveOpen: true))
            {
                z.Write(plain);
            }
            if (packed.Length < plain.Length)
            {
                body.Write(packed.GetBuffer(), 0, (int)packed.Length);
            }
            else
            {
                body.Write(plain);
            }
        }
        offsets[sectors] = tableSize + (uint)body.Length;
        var result = new byte[tableSize + body.Length];
        Buffer.BlockCopy(offsets, 0, result, 0, (int)tableSize);
        body.ToArray().CopyTo(result, tableSize);
        return result;
    }

    static byte[] EncryptTable(uint[] values, uint key)
    {
        var bytes = new byte[values.Length * 4];
        Buffer.BlockCopy(values, 0, bytes, 0, bytes.Length);
        MpqArchive.Encrypt(bytes, key);
        return bytes;
    }
}
