---
name: hots-client-observation
description: >-
  Observe a running Heroes of the Storm client from outside, read-only, with HeroesReplay's
  HeroesClientSDK: screen state, map loading, match clock, score and awards screens, dialogs and
  game-launch result codes, plus the probe tool. Explains why hooking or patching client functions
  is out of scope and what to use instead. USE FOR: testing a mod against the live client,
  building tools that react to the game. DO NOT USE FOR: changing game behaviour (galaxy-script).
license: MIT
compatibility: HeroesClientSDK is a net10.0, Windows-only NuGet package from the HeroesClientSDK GitHub releases.
---

# Observing the client

[HeroesClientSDK](https://github.com/HeroesReplay/HeroesClientSDK) reads a running
`HeroesOfTheStorm_x64.exe` with `PROCESS_QUERY_INFORMATION | PROCESS_VM_READ` only. It finds what
it needs from instruction patterns in the client's own code, so a new build usually works without
new addresses, and an unknown build reads "not ok" with a reason instead of throwing.

## Rules

- **Read only.** No `WriteProcessMemory`, no injected DLL or thread, no debugger, no suspended
  threads, no window input. That is the SDK's contract (its AGENTS.md rule 1).
- **No function hooking.** Detours, trampolines, patched code or injected scripts in the client
  are outside the SDK and this repository: they write to the process, the client talks to
  Battle.net, and they put the player's account and Blizzard's terms at risk. Don't write that
  code or instructions for it. If someone needs behaviour the game does not offer, the answer is
  a Galaxy and data mod (`galaxy-script`, `hots-custom-game-mode`); if they still want hooking,
  stop and ask the owner for an explicit decision.
- **One reader per client process**, kept for the life of your watcher; the version is always
  optional.
- **In the HeroesReplay environment**, start a client only on ASA-SERVER while holding
  `C:\heroesreplay\asa-live.lock` (the SDK's AGENTS.md rule 5); otherwise read a client someone
  already started. Never the stream PC.

## What you can read

| Reader | Tells you |
| --- | --- |
| `ClientScreen` | `Screen`: `Home`, `Login`, `Authenticating`, `Splash`, `MapLoading`, `Match`, `NoScreen`, `Score`, `Awards`, `Menu`, `Dialog`, `Download`, `Unknown`; the screens and dialogs shown with their text; `LaunchResultCode`/`LaunchResult`; signed-in |
| `LoadingScreen` | menu, loading screen or match |
| `MatchClock` | in-match time from the tick counter (ticks/4096 seconds), `near-zero` on menus and loading |

```csharp
using System.Diagnostics;
using HeroesClientSDK;

Process client = Process.GetProcessesByName("HeroesOfTheStorm_x64")[0];
using HeroesClientProcess attached = HeroesClientProcess.Attach(client);
using var menus = new ClientScreen();
using var clock = new MatchClock();

ClientScreenSample screen = menus.Read(attached);
Console.WriteLine($"{screen.Screen} launch={screen.LaunchResult} dialogs=[{string.Join(", ", screen.Dialogs ?? [])}]");
MatchClockSample time = clock.Read(attached);
Console.WriteLine(time.Time is TimeSpan t ? $"match {t:mm\\:ss}" : $"no clock: {time.Reason}");
```

Install from the release asset (no credentials): download `HeroesClientSDK.<version>.nupkg` from
the GitHub release, check its SHA-256 against the release notes, and map the package to that
folder in `nuget.config` (the SDK README shows the file). GitHub Packages also has it but needs a
token with `read:packages`.

## The probe: watch a client while you test a mod

```powershell
git clone https://github.com/HeroesReplay/HeroesClientSDK.git
cd HeroesClientSDK
dotnet run --project tools/HeroesClientSDK.Probe -c Release -- --watch 250
```

It prints a line on every change: build, screen and screens shown, dialogs, last launch result,
map loading, signed-in, loading screen and match clock. Start your replaced mode
(`hots-custom-game-mode`) and you should see `Home`, then `MapLoading`, then `Match` with a running
clock. A launch that fails shows a `Dialog` and a launch result:

| Code | Key (`@UI/` + key) | Likely meaning for a mod (read from the key, not tested) |
| --- | --- | --- |
| 4 | `GameLaunchMapOpenFailure` | the map file or folder could not be opened |
| 6 | `GameLaunchMapPrefetchFailure` | a dependency could not be fetched |
| 7 | `GameLaunchInvalidFiles` | a damaged or unreadable document |
| 8 | `GameLaunchTooManyDependencies` | the dependency chain is too long |
| 16 | `GameLaunchModDataMismatch` | mod data differs from what the game expected |
| 17 | `GameLaunchMapDataMismatch` | map data differs from what the game expected |
| 10, 23 | `GameLaunchBaseBuildMissing`, `GameLaunchUnsupportedNoData` | a replay or map needs a client build that is not installed |

The full table (1 to 24 on 2.57) is in the SDK's `heroes-client-re` skill. A Galaxy script error
inside a map that did load is not a launch result; it shows as the in-game "map script error".

## Getting information out of a mod without hooking

| Need | Use |
| --- | --- |
| Is my map loaded, is the match running, did it end | `ClientScreen` and `MatchClock` (above) |
| Events and numbers from my mode after the game | `StatEventCreate`/`StatEventSend` in Galaxy, read from `replay.tracker.events` (`storm-replay-format`) |
| State that survives games | banks (`galaxy-script`); also recorded in replays as bank events |
| What the player clicked in my UI | `STriggerDialogControlEvent` in `replay.game.events` |
| Text on screen in a standard dialog | `ClientScreenSample.DialogMessages` (title and message of shown standard dialogs) |

## Extending the SDK

New reads (for example a frame from your mod's layout by name, or a label's text in game) follow
the SDK's `heroes-client-re` skill: a read-only memory image of a running client, a pattern that
survives builds, checked on the current and a previous patch, and tests from recorded bytes.
Nothing from the client is ever committed. Contributions go to the SDK repository, not here.
