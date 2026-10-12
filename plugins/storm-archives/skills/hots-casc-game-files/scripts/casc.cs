#!/usr/bin/env dotnet
#:project TACTLib/TACTLib/TACTLib.csproj
// Read-only Heroes of the Storm CASC lister and extractor on TACTLib (MIT, overtools/TACTLib).
// Put this file in a work folder next to a clone of TACTLib (the #:project line above points at
// ./TACTLib/TACTLib/TACTLib.csproj) and run it with the .NET 10 SDK. It only reads the install.
//   dotnet run casc.cs -- info    <install>
//   dotnet run casc.cs -- list    <install> [<regex>]
//   dotnet run casc.cs -- extract <install> <regex> <out-dir>
using System.Text.RegularExpressions;
using TACTLib;
using TACTLib.Client;
using TACTLib.Core.Product.MNDX;

if (args.Length < 2)
{
    Console.Error.WriteLine("usage: casc.cs info|list|extract <install> [<regex>] [<out-dir>]");
    return 2;
}

string command = args[0];
string install = args[1];
var pattern = args.Length > 2 ? new Regex(args[2], RegexOptions.IgnoreCase) : null;

var client = new ClientHandler(install, new ClientCreateArgs
{
    Product = "hero", // the default is "pro" (Overwatch)
    LoadSupportKeyring = false,
});
if (client.ProductHandler is not ProductHandler_MNDX root)
{
    Console.Error.WriteLine($"expected an MNDX root (Heroes or SC2), got {client.ProductHandler?.GetType().Name ?? "none"}");
    return 1;
}

var entries = root.Entries.Where(e => pattern == null || pattern.IsMatch(e.Path)).OrderBy(e => e.Path, StringComparer.Ordinal).ToList();
switch (command)
{
    case "info":
        Console.WriteLine($"build    {client.InstallationInfo.Values.GetValueOrDefault("Version")}");
        Console.WriteLine($"entries  {root.Entries.Count}");
        Console.WriteLine($"packages {root.Entries.Select(e => e.Path.Split('/')[0] + "/" + e.Path.Split('/').ElementAtOrDefault(1)).Distinct().Count()} top-level mod folders");
        return 0;
    case "list":
        foreach (var e in entries)
        {
            Console.WriteLine($"{e.Path}\t{e.Locale}");
        }
        Console.Error.WriteLine($"{entries.Count} entries");
        return 0;
    case "extract":
        {
            if (args.Length < 4 || pattern == null)
            {
                Console.Error.WriteLine("extract needs a regex and an output folder");
                return 2;
            }
            string outRoot = Path.GetFullPath(args[3]);
            int written = 0;
            foreach (var e in entries)
            {
                string target = Path.GetFullPath(Path.Combine(outRoot, e.Path.Replace('/', Path.DirectorySeparatorChar)));
                if (!target.StartsWith(outRoot + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }
                using var source = root.OpenFile(e);
                if (source == null)
                {
                    Console.Error.WriteLine($"not resident locally: {e.Path}");
                    continue;
                }
                Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                using var file = File.Create(target);
                source.CopyTo(file);
                written++;
            }
            Console.WriteLine($"{written} files written to {outRoot}");
            return 0;
        }
    default:
        Console.Error.WriteLine($"unknown command {command}");
        return 2;
}
