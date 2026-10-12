# heroes-modding

Agent skills for modding **Heroes of the Storm**: the Storm engine's documents (`.stormmap`,
`.StormMod`, `.StormInterface`), Galaxy script, data and UI XML, the MPQ and CASC formats, replays
(Blizzard's heroprotocol), and building a custom game mode by replacing a built-in single-player
map, the way [Heroes Rogue](https://github.com/HeroesReplay/heroesrogue) does. It ships as one
plugin marketplace that Claude Code, GitHub Copilot (CLI and VS Code) and OpenAI Codex can
install.

Each skill is a folder with a `SKILL.md` an agent loads when the task matches, plus references and
tested scripts:

| Plugin | Skill | What it gives the agent |
| --- | --- | --- |
| `storm-modding` | `storm-mod-structure` | Map, mod and interface anatomy, dependencies, `includes.xml` mod injection, the game's own mods, loose-file overrides; `Test-StormDocument.ps1` linter |
| | `galaxy-script` | The Galaxy language, Heroes libraries, triggers, threads, banks, dialogs, catalog access; `Get-GalaxyNatives.ps1` lists a build's natives from your install |
| | `storm-data-xml` | Catalog XML: adding vs overriding, effect trees, behaviors, talents, `CUser` tables, `GameStrings.txt` |
| | `storm-ui-layouts` | `.StormLayout` frames and templates, DescIndex order, font styles, observer and replay interfaces |
| | `hots-custom-game-mode` | Replace Veteran Challenges (or Try Mode, or a tutorial) with your map and mod: `New-HotsMod.ps1` scaffolds and patches, `Install-HotsMod.ps1` installs with backup and uninstalls |
| `storm-archives` | `storm-mpq-archives` | The MPQ format; `mpq.cs` lists, extracts, unpacks, verifies and packs archives |
| | `hots-casc-game-files` | Reading the installed game data (CASC) with TACTLib; `casc.cs` lists and extracts by path |
| | `storm-replay-format` | `.StormReplay` streams, decoders and events; `replay.cs` decodes replays with heroprotocol's tables |
| `heroes-client` | `hots-client-observation` | Watching a running client read-only with [HeroesClientSDK](https://github.com/HeroesReplay/HeroesClientSDK), and why hooking is out of scope |

## Install

Marketplace: `heroes-modding`. Plugins: `storm-modding`, `storm-archives`, `heroes-client`.

### Claude Code

```text
/plugin marketplace add HeroesReplay/heroes-modding
/plugin install storm-modding@heroes-modding
/plugin install storm-archives@heroes-modding
/plugin install heroes-client@heroes-modding
```

From a shell: `claude plugin marketplace add HeroesReplay/heroes-modding`, then
`claude plugin install storm-modding@heroes-modding` (add `--scope project` to share it through
the project's `.claude/settings.json`). Update with `claude plugin marketplace update
heroes-modding` and `claude plugin update storm-modding@heroes-modding`.

### GitHub Copilot CLI

```bash
copilot plugin marketplace add HeroesReplay/heroes-modding
copilot plugin install storm-modding@heroes-modding
```

Or without the marketplace: `copilot plugin install HeroesReplay/heroes-modding:plugins/storm-modding`.

### VS Code (Copilot agent mode)

```jsonc
// settings.json
{
  "chat.plugins.enabled": true,
  "chat.plugins.marketplaces": ["HeroesReplay/heroes-modding"]
}
```

Then install the plugins from the Extensions view (`@agentPlugins`) or **Chat: Open
Customizations**, Plugins.

### OpenAI Codex CLI

```bash
codex plugin marketplace add HeroesReplay/heroes-modding
codex plugin add storm-modding@heroes-modding
```

Or run `codex`, then `/plugins`, and open the `heroes-modding` tab.

### Other agents

Copy `plugins/<plugin>/skills/<skill>/` into your agent's skills folder (`.agents/skills/` for
Codex, Copilot and many others; `.claude/skills/` for Claude Code). For an agent that only reads
`AGENTS.md`, clone this repository and add to your project's `AGENTS.md`:

> Heroes of the Storm modding skills are in `<clone>/plugins/*/skills/*/SKILL.md`. Before working
> on `.stormmap`/`.StormMod` files, GameData XML, Galaxy script, `.StormLayout` UI, MPQ archives,
> CASC game files or replays, read the `description` of those files, open the matching one, and
> load only the files it links.

## Requirements for the scripts

- PowerShell 7 (`pwsh`) for the `.ps1` scripts; Windows for `Install-HotsMod.ps1`.
- The .NET 10 SDK for `mpq.cs`, `casc.cs` and `replay.cs` (`dotnet run file.cs`).
- A clone of [overtools/TACTLib](https://github.com/overtools/TACTLib) for `casc.cs`, and of
  [Blizzard/heroprotocol](https://github.com/Blizzard/heroprotocol) for `replay.cs`.
- An installed game for anything that reads game files or tests a mode.

## What was checked

On 2026-10-12, against Heroes of the Storm 2.57.0.98348 on Windows 11:

- `casc.cs` opened the install (1,208,637 entries) and extracted the stock Veteran Challenges map,
  `NativeLib.TriggerLib` and the Heroes libraries; every native, constant and catalog field the
  skills name was looked up in them.
- `mpq.cs verify` passed four 2.57 replays and three battleground maps from the Battle.net cache;
  `pack` and `unpack` round-tripped Heroes Rogue's 582-file mod byte for byte.
- `New-HotsMod.ps1` patched the stock Veteran map and an unpacked Towers of Doom (a two- or
  three-line script diff each); `Test-StormDocument.ps1` passed both and Heroes Rogue's own maps
  and mod.
- `replay.cs` decoded every stream of two 2.57 replays with heroprotocol's 96477 tables.

Not yet checked in game: loading a mode made by `New-HotsMod.ps1` (the same mechanism Heroes Rogue
ships), an archive written by `mpq.cs pack`, and what a replay of a custom map contains.

## Sources and credits

The skills are written from these projects, with thanks to their authors:

- [HeroesReplay/heroesrogue](https://github.com/HeroesReplay/heroesrogue): a shipping
  single-player mode in the built-in map slots.
- [jamiephan/HeroesOfTheStorm_TryMode2.0](https://github.com/jamiephan/HeroesOfTheStorm_TryMode2.0)
  and [HeroesOfTheStorm_StormMapGenerator](https://github.com/jamiephan/HeroesOfTheStorm_StormMapGenerator).
- [Ahli/Galaxy-Observer-UI](https://github.com/Ahli/Galaxy-Observer-UI) and
  [Talv/sc2-layouts](https://github.com/Talv/sc2-layouts).
- [overtools/TACTLib](https://github.com/overtools/TACTLib) and
  [HeroesReplay/MPQExtractor](https://github.com/HeroesReplay/MPQExtractor) (StormLib).
- [SC2Mapster/blizzard-tutorials](https://github.com/SC2Mapster/blizzard-tutorials).
- [Blizzard/heroprotocol](https://github.com/Blizzard/heroprotocol).
- [HeroesReplay/HeroesClientSDK](https://github.com/HeroesReplay/HeroesClientSDK).
- The layout follows [dotnet/skills](https://github.com/dotnet/skills).

Heroes of the Storm is a trademark of Blizzard Entertainment, Inc. This project is not affiliated
with or endorsed by Blizzard. It contains no game files; the scripts read your own install.
Modding the game is at your own risk; none of these projects settle what Blizzard's terms allow.

## License

[MIT](LICENSE)
