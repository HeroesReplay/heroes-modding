# AGENTS.md

This is the contract for coding agents working in this repository. Code and this file win over
chat history.

## Product

Agent skills about modding Heroes of the Storm, shipped as a plugin marketplace (`heroes-modding`)
that Claude Code, GitHub Copilot CLI, VS Code agent mode and OpenAI Codex install from one
`.claude-plugin/marketplace.json`. Install steps are in [README.md](README.md).

| Path | What |
| --- | --- |
| `.claude-plugin/marketplace.json` | The only marketplace file; lists the plugins below |
| `plugins/<plugin>/plugin.json` | Agent Plugins 1.0 manifest (Copilot CLI, VS Code, Codex) |
| `plugins/<plugin>/.claude-plugin/plugin.json` | Claude Code manifest: the same fields without `$schema` |
| `plugins/<plugin>/skills/<skill>/SKILL.md` | A skill, with optional `references/` and `scripts/` |
| `eng/Test-Repo.ps1` | Repository rules (manifests, skill frontmatter, links, sizes, versions) |
| `tests/Test-Scripts.ps1` | Tests for every script the skills ship, on synthetic files |

## Plugins and skills

| Plugin | Skill | Use when |
| --- | --- | --- |
| `storm-modding` | `storm-mod-structure` | Anatomy of maps, mods and interfaces; dependencies; `includes.xml`; loose-file overrides; the linter |
| | `galaxy-script` | Galaxy code: language, libraries, triggers, banks, dialogs, natives of a build |
| | `storm-data-xml` | Catalog XML: add vs override, effects, behaviors, talents, CUser tables, GameStrings |
| | `storm-ui-layouts` | `.StormLayout` frames, DescIndex, styles, observer interfaces |
| | `hots-custom-game-mode` | Replacing a built-in single-player map (Veteran Challenges) with a map and mod; scaffold, install, uninstall |
| `storm-archives` | `storm-mpq-archives` | MPQ format; `mpq.cs` list/extract/unpack/verify/pack |
| | `hots-casc-game-files` | Reading the installed game data with TACTLib (`casc.cs`) |
| | `storm-replay-format` | `.StormReplay` and Blizzard heroprotocol; `replay.cs` decoder |
| `heroes-client` | `hots-client-observation` | Watching a running client read-only with HeroesClientSDK |

## Rules

1. **Nothing from Blizzard is committed.** No game files, extracted CASC data, `.s2ma`, replays,
   decoded replay dumps, generated natives lists or memory images. Tests build synthetic fixtures.
   A skill may quote a few lines (a signature, an XML element) with the build they came from.
2. **Facts are checked or marked.** A statement about the game says where it was seen (build,
   file, date) or says it is untested. Prefer checking against the installed game, Heroes Rogue,
   Try Mode 2.0 or Blizzard's own files over memory. StarCraft II documentation is labelled as such.
3. **Read-only toward the game.** Scripts never write into `<game>\HeroesData`. Only
   `Install-HotsMod.ps1` writes into the game folder, only to `maps\` and `mods\`, with a backup
   and a manifest. Nothing here writes to, injects into, hooks or patches a running client.
4. **Skills follow the Agent Skills rules.** Frontmatter keys `name`, `description`, `license`,
   optional `compatibility` and `metadata`. `name` equals the folder, is lowercase-hyphen, unique,
   and contains `storm-`, `galaxy-` or `hots-`. `description` is at most 1024 characters, has no
   angle brackets, and reads "what it covers. USE FOR: ... DO NOT USE FOR: ...". All descriptions
   together stay under 6000 characters. `SKILL.md` stays under 500 lines; detail goes in
   `references/`, linked one folder deep. No symlinks, no BOM in `.md`/`.json`, no `CLAUDE.md`,
   no top-level `bin/` in a plugin.
5. **Scripts state their runtime** in the skill's `compatibility`: PowerShell 7 or a .NET 10
   file-based app (`dotnet run file.cs`). Every script gets a test in `tests/Test-Scripts.ps1`,
   unless it needs the game or a replay (`casc.cs`, `replay.cs`); those are checked by hand and
   the skill says when and against what.
6. **Bump the version** in both manifests of a plugin whenever anything under it changes (patch for
   fixes, minor for new skills). CI compares with `origin/main`.
7. **In the HeroesReplay environment** a Heroes client is started only on ASA-SERVER while holding
   `C:\heroesreplay\asa-live.lock` (taken only while `C:\heroesreplay\asa-release-pending` does not
   exist), never on the stream PC (DESKTOP-8SJEK72), and mods are never installed on the stream PC.

## Validate

```powershell
pwsh -NoProfile -File eng/Test-Repo.ps1                    # add -BaseRef origin/main on a branch
pwsh -NoProfile -File tests/Test-Scripts.ps1               # needs the .NET 10 SDK for mpq.cs
claude plugin validate . --strict
claude plugin validate plugins/storm-modding --strict      # and each other plugin
pipx run --spec skills-ref==0.1.1 skills-ref validate plugins/storm-modding/skills/galaxy-script
```

CI (`.github/workflows/validate.yml`) runs all of these on every pull request. Changes reach
`main` through pull requests.

## Adding a skill

1. Pick the plugin, create `plugins/<plugin>/skills/<name>/SKILL.md` with the frontmatter above.
2. Add it to the table in this file and in README.md.
3. Bump the plugin version in both manifests.
4. Run the validation above.
