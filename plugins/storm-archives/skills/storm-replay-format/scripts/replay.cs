#!/usr/bin/env dotnet
#:package SharpZipLib@1.4.2
// Decodes a Heroes of the Storm .StormReplay with the type tables of Blizzard's heroprotocol
// (MIT, github.com/Blizzard/heroprotocol). The protocolNNNNN.py files are read as data with
// regular expressions; no Python runs. Needs the .NET 10 SDK.
//
//   dotnet run replay.cs -- <protocols-dir> <replay> header|details|initdata|attributes
//   dotnet run replay.cs -- <protocols-dir> <replay> tracker|game|message [--event Name] [--stats]
//
// <protocols-dir> is heroprotocol/heroprotocol/versions. The table is protocol<m_baseBuild>.py; when
// the replay is newer than every file, the newest is used with a warning (the tables have not
// changed since build 85027), and the stream must still end cleanly or the tool fails.
// Output is one JSON object per line. Replays hold player names, BattleTags and chat: keep the
// output private.
using System.IO.Compression;
using System.Numerics;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using ICSharpCode.SharpZipLib.BZip2;

if (args.Length < 3)
{
    Console.Error.WriteLine("usage: replay.cs <protocols-dir> <replay> header|details|initdata|attributes|tracker|game|message [--event Name] [--stats]");
    return 2;
}

string protocolsDir = args[0];
string replayPath = args[1];
string stream = args[2];
string? eventFilter = null;
bool stats = false;
for (int i = 3; i < args.Length; i++)
{
    if (args[i] == "--event" && i + 1 < args.Length) eventFilter = args[++i];
    else if (args[i] == "--stats") stats = true;
}

var replay = Replay.Open(replayPath);

// The header is in the versioned format, so any table decodes it.
var protocolFiles = Directory.GetFiles(protocolsDir, "protocol*.py")
    .Select(p => (Path: p, Build: int.TryParse(Regex.Match(Path.GetFileName(p), @"^protocol(\d+)\.py$").Groups[1].Value, out int b) ? b : -1))
    .Where(p => p.Build > 0)
    .OrderBy(p => p.Build)
    .ToList();
if (protocolFiles.Count == 0)
{
    Console.Error.WriteLine($"no protocolNNNNN.py files in {protocolsDir}");
    return 2;
}
var latest = new Protocol(File.ReadAllText(protocolFiles[^1].Path));
var header = (Rec)new Versioned(replay.UserData, latest.Types).Instance(latest.Id("replay_header_typeid"))!;
long baseBuild = Convert.ToInt64(((Rec)header.Get("m_version")!).Get("m_baseBuild"));
var exact = protocolFiles.FirstOrDefault(p => p.Build == baseBuild);
Protocol protocol;
if (exact.Path != null)
{
    protocol = new Protocol(File.ReadAllText(exact.Path));
}
else
{
    Console.Error.WriteLine($"warning: no protocol{baseBuild}.py; decoding with protocol{protocolFiles[^1].Build}.py (newest)");
    protocol = latest;
}

using var stdout = Console.OpenStandardOutput();
var json = new Utf8JsonWriter(stdout, new JsonWriterOptions { Indented = false, Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping });
void Emit(object? value)
{
    Json.Write(json, value);
    json.Flush();
    stdout.Write("\n"u8);
    json.Reset(stdout);
}

switch (stream)
{
    case "header":
        Emit(header);
        break;
    case "details":
        {
            var dec = new Versioned(replay.Read("replay.details"), protocol.Types);
            Emit(dec.Instance(protocol.Id("game_details_typeid")));
            break;
        }
    case "initdata":
        {
            var dec = new BitPacked(replay.Read("replay.initData"), protocol.Types);
            Emit(dec.Instance(protocol.Id("replay_initdata_typeid")));
            break;
        }
    case "attributes":
        Emit(Attributes.Decode(replay.Read("replay.attributes.events")));
        break;
    case "tracker":
    case "game":
    case "message":
        {
            var (file, typeName, tableName, userId) = stream switch
            {
                "tracker" => ("replay.tracker.events", "tracker_eventid_typeid", "tracker_event_types", false),
                "game" => ("replay.game.events", "game_eventid_typeid", "game_event_types", true),
                _ => ("replay.message.events", "message_eventid_typeid", "message_event_types", true),
            };
            byte[] data = replay.Read(file);
            IDecoder dec = stream == "tracker" ? new Versioned(data, protocol.Types) : new BitPacked(data, protocol.Types);
            var table = protocol.EventTable(tableName);
            int deltaType = protocol.Id("svaruint32_typeid");
            int userType = protocol.Id("replay_userid_typeid");
            int eventIdType = protocol.Id(typeName);
            long gameloop = 0;
            var counts = new SortedDictionary<string, int>(StringComparer.Ordinal);
            while (!dec.Done())
            {
                var delta = (Rec)dec.Instance(deltaType)!;
                gameloop += Convert.ToInt64(delta.Fields[0].Value);
                object? user = userId ? dec.Instance(userType) : null;
                long eventId = Convert.ToInt64(dec.Instance(eventIdType));
                if (!table.TryGetValue(eventId, out var eventType))
                {
                    throw new InvalidDataException($"unknown event id {eventId} at loop {gameloop}: wrong protocol table?");
                }
                var ev = dec.Instance(eventType.TypeId) as Rec ?? new Rec();
                dec.ByteAlign();
                counts[eventType.Name] = counts.GetValueOrDefault(eventType.Name) + 1;
                if (stats || (eventFilter != null && !eventType.Name.EndsWith(eventFilter, StringComparison.Ordinal)))
                {
                    continue;
                }
                ev.Fields.Insert(0, ("_event", eventType.Name));
                ev.Fields.Insert(1, ("_eventid", eventId));
                ev.Fields.Insert(2, ("_gameloop", gameloop));
                if (user is Rec u) ev.Fields.Insert(3, ("_userid", u.Get("m_userId")));
                Emit(ev);
            }
            if (stats)
            {
                foreach (var (name, count) in counts.OrderByDescending(c => c.Value))
                {
                    Console.WriteLine($"{count,8} {name}");
                }
            }
            break;
        }
    default:
        Console.Error.WriteLine($"unknown stream {stream}");
        return 2;
}
return 0;

/// <summary>A decoded struct: ordered fields, as heroprotocol's dicts.</summary>
sealed class Rec
{
    public List<(string Key, object? Value)> Fields { get; } = new();
    public object? Get(string key) => Fields.FirstOrDefault(f => f.Key == key).Value;
}

sealed record BitArray(long Length, byte[] Bytes);

static class Json
{
    public static void Write(Utf8JsonWriter w, object? v)
    {
        switch (v)
        {
            case null: w.WriteNullValue(); break;
            case Rec r:
                w.WriteStartObject();
                foreach (var (k, x) in r.Fields) { w.WritePropertyName(k); Write(w, x); }
                w.WriteEndObject();
                break;
            case List<object?> l:
                w.WriteStartArray();
                foreach (var x in l) Write(w, x);
                w.WriteEndArray();
                break;
            case byte[] b:
                // Blobs: text when they are valid printable UTF-8, else hex.
                string? text = TryText(b);
                if (text != null) w.WriteStringValue(text);
                else { w.WriteStartObject(); w.WriteString("hex", Convert.ToHexString(b)); w.WriteEndObject(); }
                break;
            case BitArray a:
                w.WriteStartObject(); w.WriteNumber("bits", a.Length); w.WriteString("hex", Convert.ToHexString(a.Bytes)); w.WriteEndObject();
                break;
            case bool x: w.WriteBooleanValue(x); break;
            case long x: w.WriteNumberValue(x); break;
            case int x: w.WriteNumberValue(x); break;
            case float x: w.WriteNumberValue(x); break;
            case double x: w.WriteNumberValue(x); break;
            case string s: w.WriteStringValue(s); break;
            default: w.WriteStringValue(v.ToString()); break;
        }
    }

    static string? TryText(byte[] b)
    {
        try
        {
            string s = new UTF8Encoding(false, true).GetString(b);
            return s.All(c => !char.IsControl(c) || c is '\n' or '\r' or '\t') ? s : null;
        }
        catch (DecoderFallbackException)
        {
            return null;
        }
    }
}

/// <summary>Type tables of one protocolNNNNN.py, parsed as text.</summary>
sealed class Protocol
{
    public sealed class TypeInfo
    {
        public string Kind = "";
        public long Min;
        public int Bits;
        public int Type;
        public Dictionary<long, (string Name, int Type)> Choices = new();
        public List<(string Name, int Type, long Tag)> Fields = new();
    }

    readonly string text;
    public List<TypeInfo> Types { get; } = new();

    public Protocol(string text)
    {
        this.text = text;
        foreach (Match m in Regex.Matches(text, @"^\s*\('(_\w+)',\[(.*)\]\),\s*#(\d+)\s*$", RegexOptions.Multiline))
        {
            var ti = new TypeInfo { Kind = m.Groups[1].Value };
            string a = m.Groups[2].Value;
            var bounds = Regex.Match(a, @"^\((-?\d+),(\d+)\)");
            if (bounds.Success)
            {
                ti.Min = long.Parse(bounds.Groups[1].Value);
                ti.Bits = int.Parse(bounds.Groups[2].Value);
            }
            switch (ti.Kind)
            {
                case "_array": ti.Type = int.Parse(Regex.Match(a, @",(\d+)$").Groups[1].Value); break;
                case "_optional": ti.Type = int.Parse(a); break;
                case "_choice":
                    foreach (Match c in Regex.Matches(a, @"(\d+):\('(\w+)',(\d+)\)"))
                        ti.Choices[long.Parse(c.Groups[1].Value)] = (c.Groups[2].Value, int.Parse(c.Groups[3].Value));
                    break;
                case "_struct":
                    foreach (Match f in Regex.Matches(a, @"\('(\w+)',(\d+),(-?\d+)\)"))
                        ti.Fields.Add((f.Groups[1].Value, int.Parse(f.Groups[2].Value), long.Parse(f.Groups[3].Value)));
                    break;
            }
            if (int.Parse(m.Groups[3].Value) != Types.Count)
            {
                throw new InvalidDataException($"typeinfo #{m.Groups[3].Value} out of order; is this a heroprotocol protocol file?");
            }
            Types.Add(ti);
        }
    }

    public int Id(string name) =>
        int.Parse(Regex.Match(text, $@"^{name} = (\d+)", RegexOptions.Multiline).Groups[1].Value);

    public Dictionary<long, (int TypeId, string Name)> EventTable(string name)
    {
        string body = Regex.Match(text, name + @" = \{(.*?)\n\}", RegexOptions.Singleline).Groups[1].Value;
        return Regex.Matches(body, @"(\d+): \((\d+), '([\w.]+)'\)")
            .ToDictionary(x => long.Parse(x.Groups[1].Value), x => (int.Parse(x.Groups[2].Value), x.Groups[3].Value));
    }
}

interface IDecoder
{
    object? Instance(int id);
    bool Done();
    void ByteAlign();
}

/// <summary>heroprotocol's BitPackedBuffer: bytes are used from their low bits up.</summary>
sealed class BitBuffer(byte[] data, bool bigEndian = true)
{
    int used;
    int next;
    int nextBits;

    public bool Done() => nextBits == 0 && used >= data.Length;

    public void ByteAlign() => nextBits = 0;

    public byte[] Aligned(long n)
    {
        ByteAlign();
        if (n < 0 || used + n > data.Length) throw new InvalidDataException("stream truncated");
        var r = data.AsSpan(used, (int)n).ToArray();
        used += (int)n;
        return r;
    }

    public ulong Bits(int bits)
    {
        if (bits > 64) throw new ArgumentOutOfRangeException(nameof(bits));
        ulong result = 0;
        int done = 0;
        while (done != bits)
        {
            if (nextBits == 0)
            {
                if (Done()) throw new InvalidDataException("stream truncated");
                next = data[used++];
                nextBits = 8;
            }
            int take = Math.Min(bits - done, nextBits);
            ulong copy = (ulong)(next & ((1 << take) - 1));
            result |= bigEndian ? copy << (bits - done - take) : copy << done;
            next >>= take;
            nextBits -= take;
            done += take;
        }
        return result;
    }

    /// <summary>A bit array of any length, most significant chunk first as heroprotocol builds it.</summary>
    public byte[] BigBits(long bits)
    {
        BigInteger value = BigInteger.Zero;
        long left = bits;
        while (left > 0)
        {
            int take = (int)Math.Min(left, 64);
            value = (value << take) | new BigInteger(Bits(take));
            left -= take;
        }
        byte[] bytes = value.ToByteArray(isUnsigned: true, isBigEndian: true);
        int size = (int)((bits + 7) / 8);
        if (bytes.Length >= size) return bytes[^size..];
        var padded = new byte[size];
        bytes.CopyTo(padded, size - bytes.Length);
        return padded;
    }
}

sealed class BitPacked(byte[] data, List<Protocol.TypeInfo> types) : IDecoder
{
    readonly BitBuffer b = new(data);

    public bool Done() => b.Done();

    public void ByteAlign() => b.ByteAlign();

    long Int(Protocol.TypeInfo x) => unchecked(x.Min + (long)b.Bits(x.Bits));

    public object? Instance(int id)
    {
        var x = types[id];
        switch (x.Kind)
        {
            case "_int": return Int(x);
            case "_bool": return b.Bits(1) != 0;
            case "_blob": return b.Aligned(Int(x));
            case "_array":
                {
                    long n = Int(x);
                    var list = new List<object?>();
                    for (long i = 0; i < n; i++) list.Add(Instance(x.Type));
                    return list;
                }
            case "_bitarray":
                {
                    long n = Int(x);
                    return new BitArray(n, b.BigBits(n));
                }
            case "_optional": return b.Bits(1) != 0 ? Instance(x.Type) : null;
            case "_choice":
                {
                    long tag = Int(x);
                    if (!x.Choices.TryGetValue(tag, out var choice)) throw new InvalidDataException($"unknown choice tag {tag}");
                    var r = new Rec();
                    r.Fields.Add((choice.Name, Instance(choice.Type)));
                    return r;
                }
            case "_fourcc":
                {
                    uint v = (uint)b.Bits(32);
                    return new[] { (byte)(v >> 24), (byte)(v >> 16), (byte)(v >> 8), (byte)v };
                }
            case "_null": return null;
            case "_real32": return BitConverter.Int32BitsToSingle((int)b.Bits(32));
            case "_real64": return BitConverter.Int64BitsToDouble((long)b.Bits(64));
            case "_struct":
                {
                    var r = new Rec();
                    foreach (var f in x.Fields)
                    {
                        var v = Instance(f.Type);
                        if (f.Name == "__parent")
                        {
                            if (v is Rec parent) r.Fields.AddRange(parent.Fields);
                            else if (x.Fields.Count == 1) return v;
                            else r.Fields.Add((f.Name, v));
                        }
                        else
                        {
                            r.Fields.Add((f.Name, v));
                        }
                    }
                    return r;
                }
        }
        throw new InvalidDataException("unknown type kind " + x.Kind);
    }
}

sealed class Versioned(byte[] data, List<Protocol.TypeInfo> types) : IDecoder
{
    readonly BitBuffer b = new(data);

    public bool Done() => b.Done();

    public void ByteAlign() => b.ByteAlign();

    void Expect(int skip)
    {
        int v = (int)b.Bits(8);
        if (v != skip) throw new InvalidDataException($"corrupted: expected type tag {skip}, got {v} (wrong protocol table?)");
    }

    long VInt()
    {
        long x = (long)b.Bits(8);
        bool negative = (x & 1) != 0;
        long r = (x >> 1) & 0x3F;
        int bits = 6;
        while ((x & 0x80) != 0)
        {
            x = (long)b.Bits(8);
            r |= (x & 0x7F) << bits;
            bits += 7;
        }
        return negative ? -r : r;
    }

    void Skip()
    {
        switch ((int)b.Bits(8))
        {
            case 0: { long n = VInt(); for (long i = 0; i < n; i++) Skip(); break; }
            case 1: { long n = VInt(); b.Aligned((n + 7) / 8); break; }
            case 2: b.Aligned(VInt()); break;
            case 3: VInt(); Skip(); break;
            case 4: if (b.Bits(8) != 0) Skip(); break;
            case 5: { long n = VInt(); for (long i = 0; i < n; i++) { VInt(); Skip(); } break; }
            case 6: b.Aligned(1); break;
            case 7: b.Aligned(4); break;
            case 8: b.Aligned(8); break;
            case 9: VInt(); break;
        }
    }

    public object? Instance(int id)
    {
        var x = types[id];
        switch (x.Kind)
        {
            case "_int": Expect(9); return VInt();
            case "_bool": Expect(6); return b.Bits(8) != 0;
            case "_blob": Expect(2); return b.Aligned(VInt());
            case "_array":
                {
                    Expect(0);
                    long n = VInt();
                    var list = new List<object?>();
                    for (long i = 0; i < n; i++) list.Add(Instance(x.Type));
                    return list;
                }
            case "_bitarray":
                {
                    Expect(1);
                    long n = VInt();
                    return new BitArray(n, b.Aligned((n + 7) / 8));
                }
            case "_optional": Expect(4); return b.Bits(8) != 0 ? Instance(x.Type) : null;
            case "_choice":
                {
                    Expect(3);
                    long tag = VInt();
                    var r = new Rec();
                    if (!x.Choices.TryGetValue(tag, out var choice))
                    {
                        Skip();
                        return r;
                    }
                    r.Fields.Add((choice.Name, Instance(choice.Type)));
                    return r;
                }
            case "_fourcc": Expect(7); return b.Aligned(4);
            case "_null": return null;
            case "_real32": Expect(7); return BitConverter.ToSingle(b.Aligned(4).Reverse().ToArray());
            case "_real64": Expect(8); return BitConverter.ToDouble(b.Aligned(8).Reverse().ToArray());
            case "_struct":
                {
                    Expect(5);
                    var r = new Rec();
                    long n = VInt();
                    for (long i = 0; i < n; i++)
                    {
                        long tag = VInt();
                        var f = x.Fields.FirstOrDefault(ff => ff.Tag == tag);
                        if (f.Name == null)
                        {
                            Skip();
                            continue;
                        }
                        var v = Instance(f.Type);
                        if (f.Name == "__parent")
                        {
                            if (v is Rec parent) r.Fields.AddRange(parent.Fields);
                            else if (x.Fields.Count == 1) return v;
                            else r.Fields.Add((f.Name, v));
                        }
                        else
                        {
                            r.Fields.Add((f.Name, v));
                        }
                    }
                    return r;
                }
        }
        throw new InvalidDataException("unknown type kind " + x.Kind);
    }
}

/// <summary>replay.attributes.events: little-endian, byte-aligned records.</summary>
static class Attributes
{
    public static Rec Decode(byte[] d)
    {
        var r = new Rec();
        r.Fields.Add(("source", (long)d[0]));
        r.Fields.Add(("mapNamespace", (long)BitConverter.ToUInt32(d, 1)));
        uint count = BitConverter.ToUInt32(d, 5);
        var scopes = new SortedDictionary<long, List<object?>>();
        int p = 9;
        for (uint i = 0; i < count && p + 13 <= d.Length; i++, p += 13)
        {
            long ns = BitConverter.ToUInt32(d, p);
            long attrId = BitConverter.ToUInt32(d, p + 4);
            long scope = d[p + 8];
            string value = Encoding.UTF8.GetString(d.AsSpan(p + 9, 4).ToArray().Reverse().ToArray()).TrimStart('\0');
            var a = new Rec();
            a.Fields.Add(("namespace", ns));
            a.Fields.Add(("attrid", attrId));
            a.Fields.Add(("value", value));
            if (!scopes.TryGetValue(scope, out var list)) scopes[scope] = list = new List<object?>();
            list.Add(a);
        }
        var s = new Rec();
        foreach (var (scope, list) in scopes) s.Fields.Add((scope.ToString(), list));
        r.Fields.Add(("scopes", s));
        return r;
    }
}

/// <summary>Just enough MPQ for replays: user data, classic tables, single-unit bzip2/zlib files.</summary>
sealed class Replay
{
    static readonly uint[] Crypt = BuildCrypt();
    readonly byte[] file;
    readonly long headerOffset;
    readonly uint[] hash;
    readonly uint[] block;
    public byte[] UserData { get; }

    Replay(byte[] file)
    {
        this.file = file;
        if (BitConverter.ToUInt32(file, 0) != 0x1B51504D) throw new InvalidDataException("not a replay: no MPQ user data at offset 0");
        headerOffset = BitConverter.ToUInt32(file, 8);
        uint userSize = BitConverter.ToUInt32(file, 12);
        UserData = file.AsSpan(16, (int)userSize).ToArray();
        long h = headerOffset;
        if (BitConverter.ToUInt32(file, (int)h) != 0x1A51504D) throw new InvalidDataException("no MPQ header");
        hash = Table(h + BitConverter.ToUInt32(file, (int)h + 16), BitConverter.ToUInt32(file, (int)h + 24), "(hash table)");
        block = Table(h + BitConverter.ToUInt32(file, (int)h + 20), BitConverter.ToUInt32(file, (int)h + 28), "(block table)");
    }

    public static Replay Open(string path) => new(File.ReadAllBytes(path));

    uint[] Table(long pos, uint entries, string keyName)
    {
        var bytes = file.AsSpan((int)pos, (int)entries * 16).ToArray();
        Decrypt(bytes, HashString(keyName, 3));
        var values = new uint[entries * 4];
        Buffer.BlockCopy(bytes, 0, values, 0, bytes.Length);
        return values;
    }

    public byte[] Read(string name)
    {
        uint count = (uint)hash.Length / 4;
        uint start = HashString(name, 0) & (count - 1), a = HashString(name, 1), b = HashString(name, 2);
        for (uint i = start, n = 0; n < count; i = (i + 1) & (count - 1), n++)
        {
            uint index = hash[i * 4 + 3];
            if (index == 0xFFFFFFFF) break;
            if (hash[i * 4] != a || hash[i * 4 + 1] != b) continue;
            long pos = headerOffset + block[index * 4];
            int stored = (int)block[index * 4 + 1], size = (int)block[index * 4 + 2];
            uint flags = block[index * 4 + 3];
            if ((flags & 0x01000000) == 0 && size > 0) throw new InvalidDataException($"{name}: sectored file; use the storm-mpq-archives tool");
            var raw = file.AsSpan((int)pos, stored).ToArray();
            if ((flags & 0x200) == 0 || stored >= size) return raw[..size];
            using var input = new MemoryStream(raw, 1, raw.Length - 1);
            using var output = new MemoryStream(size);
            if (raw[0] == 0x10) BZip2.Decompress(input, output, false);
            else if (raw[0] == 0x02) { using var z = new ZLibStream(input, CompressionMode.Decompress); z.CopyTo(output); }
            else throw new InvalidDataException($"{name}: compression 0x{raw[0]:X2} not supported");
            return output.ToArray();
        }
        throw new FileNotFoundException($"{name} is not in the replay");
    }

    static uint[] BuildCrypt()
    {
        var t = new uint[0x500];
        uint seed = 0x00100001;
        for (int i = 0; i < 0x100; i++)
        {
            for (int j = 0, k = i; j < 5; j++, k += 0x100)
            {
                seed = (seed * 125 + 3) % 0x2AAAAB;
                uint hi = (seed & 0xFFFF) << 16;
                seed = (seed * 125 + 3) % 0x2AAAAB;
                t[k] = hi | (seed & 0xFFFF);
            }
        }
        return t;
    }

    static uint HashString(string s, int type)
    {
        uint s1 = 0x7FED7FED, s2 = 0xEEEEEEEE;
        foreach (char c in s.ToUpperInvariant())
        {
            uint ch = (byte)c;
            s1 = Crypt[(type << 8) + ch] ^ (s1 + s2);
            s2 = ch + s1 + s2 + (s2 << 5) + 3;
        }
        return s1;
    }

    static void Decrypt(byte[] d, uint key)
    {
        uint seed = 0xEEEEEEEE;
        for (int i = 0; i + 4 <= d.Length; i += 4)
        {
            seed += Crypt[0x400 + (key & 0xFF)];
            uint v = BitConverter.ToUInt32(d, i) ^ (key + seed);
            key = ((~key << 0x15) + 0x11111111) | (key >> 0x0B);
            seed = v + seed + (seed << 5) + 3;
            BitConverter.TryWriteBytes(d.AsSpan(i), v);
        }
    }
}
