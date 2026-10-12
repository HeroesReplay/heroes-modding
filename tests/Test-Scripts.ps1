<#
.SYNOPSIS
    Tests the scripts the skills ship, on synthetic files only (nothing from Blizzard, no replays).

.DESCRIPTION
    - eng/Test-Repo.ps1 passes on the repo and fails on a broken copy;
    - New-HotsMod.ps1 scaffolds a mod and patches a synthetic map once, even when run twice;
    - Test-StormDocument.ps1 passes the result and fails a broken copy with the expected errors;
    - mpq.cs packs the mod, verifies it against (attributes) and unpacks it byte-identical
      (needs the .NET 10 SDK; skipped without it);
    - Install-HotsMod.ps1 installs, re-installs and uninstalls against a fake game folder and
      restores what was there (Windows only);
    - Get-GalaxyNatives.ps1 turns a small TriggerLib into script declarations.
    Exit 1 on any failure.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).ProviderPath
$skills = Join-Path $root 'plugins/storm-modding/skills'
$newMod = Join-Path $skills 'hots-custom-game-mode/scripts/New-HotsMod.ps1'
$install = Join-Path $skills 'hots-custom-game-mode/scripts/Install-HotsMod.ps1'
$lint = Join-Path $skills 'storm-mod-structure/scripts/Test-StormDocument.ps1'
$natives = Join-Path $skills 'galaxy-script/scripts/Get-GalaxyNatives.ps1'
$mpq = Join-Path $root 'plugins/storm-archives/skills/storm-mpq-archives/scripts/mpq.cs'

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("heroes-modding-tests-" + [guid]::NewGuid().ToString('n').Substring(0, 8))
New-Item -ItemType Directory -Path $work | Out-Null
$failed = 0

function Check([bool] $Condition, [string] $Message) {
    if ($Condition) { Write-Output "ok   $Message" }
    else { Write-Output "FAIL $Message"; $script:failed++ }
}

function Invoke-Pwsh([string] $Script, [string[]] $Arguments) {
    $output = & pwsh -NoProfile -File $Script @Arguments 2>&1 | ForEach-Object { "$_" }
    [pscustomobject]@{ Code = $LASTEXITCODE; Text = ($output -join "`n") }
}

function Write-Utf8([string] $Path, [string] $Text) {
    New-Item -ItemType Directory -Force -Path (Split-Path $Path -Parent) | Out-Null
    [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
}

try {
    # ------------------------------------------------------------------ repo rules
    $r = Invoke-Pwsh (Join-Path $root 'eng/Test-Repo.ps1') @()
    Check ($r.Code -eq 0) 'Test-Repo passes on the repository'

    $copy = Join-Path $work 'repo'
    New-Item -ItemType Directory -Path $copy | Out-Null
    foreach ($item in '.claude-plugin', 'eng', 'plugins') { Copy-Item -Recurse (Join-Path $root $item) (Join-Path $copy $item) }
    $skillMd = Join-Path $copy 'plugins/storm-modding/skills/galaxy-script/SKILL.md'
    (Get-Content $skillMd -Raw).Replace('name: galaxy-script', 'name: Galaxy_Script').Replace('Galaxy, the C-like', 'Galaxy <script>, the C-like') | Set-Content $skillMd -NoNewline
    $claudeManifest = Join-Path $copy 'plugins/heroes-client/.claude-plugin/plugin.json'
    (Get-Content $claudeManifest -Raw).Replace('"version": "0.1.0"', '"version": "9.9.9"') | Set-Content $claudeManifest -NoNewline
    $r = Invoke-Pwsh (Join-Path $copy 'eng/Test-Repo.ps1') @()
    Check ($r.Code -eq 1) 'Test-Repo fails on a broken copy'
    Check ($r.Text -match "name 'Galaxy_Script' must equal the folder name") 'Test-Repo reports a skill name that is not the folder name'
    Check ($r.Text -match 'description contains < or >') 'Test-Repo reports angle brackets in a description'
    Check ($r.Text -match 'heroes-client/.claude-plugin/plugin.json differs') 'Test-Repo reports manifests out of sync'

    # ------------------------------------------------------------------ scaffold and patch
    $map = Join-Path $work 'source/TestMap.stormmap'
    Write-Utf8 "$map/ComponentList.StormComponents" @'
<?xml version="1.0" encoding="us-ascii"?>
<Components>
    <DataComponent Type="gada">GameData</DataComponent>
    <DataComponent Type="text" Locale="enUS">GameText</DataComponent>
    <DataComponent Type="info">DocumentInfo</DataComponent>
</Components>
'@
    Write-Utf8 "$map/DocumentInfo" @'
<?xml version="1.0" encoding="utf-8"?>
<DocInfo>
    <Dependencies>
        <Value>bnet:Heroes of the Storm (Data Mod)/0.0/999,file:Mods/HeroesData.StormMod</Value>
    </Dependencies>
    <ModifiableDependencies>
        <Value>Mods/HeroesData.StormMod</Value>
    </ModifiableDependencies>
</DocInfo>
'@
    Write-Utf8 "$map/MapScript.galaxy" ((@(
                'include "TriggerLibs/NativeLib"',
                'include "TriggerLibs/HeroesLib"',
                '',
                'void InitLibs () {',
                '    libNtve_InitLib();',
                '    libCore_InitLib();',
                '}',
                '',
                'void InitMap () {',
                '    InitLibs();',
                '}'
            ) -join "`r`n") + "`r`n")
    Write-Utf8 "$map/enUS.StormData/LocalizedData/GameStrings.txt" ([char]0xFEFF + "DocInfo/Name=Test Map`r`n")

    $out = Join-Path $work 'mymod'
    $r = Invoke-Pwsh $newMod @('-Name', 'TestMode', '-OutputPath', $out, '-MapSource', $map)
    Check ($r.Code -eq 0) 'New-HotsMod scaffolds and patches'
    $slot = Join-Path $out 'maps/heroes/singleplayermaps/startingexperience/tutorialveteran.stormmap'
    $script = Get-Content (Join-Path $slot 'MapScript.galaxy')
    Check (@($script | Where-Object { $_ -eq 'include "TestModeLib"' }).Count -eq 1) 'MapScript includes the library once'
    Check (@($script | Where-Object { $_ -match '^\s+libTest_InitLib\(\);' }).Count -eq 1) 'InitLibs calls libTest_InitLib once'
    Check ([Array]::IndexOf($script, 'include "TestModeLib"') -eq 3) 'the include goes after the last include, under the marker line'
    $initIndex = [Array]::IndexOf(@($script | ForEach-Object { $_ -match 'libTest_InitLib' }), $true)
    Check ($script[$initIndex + 1] -eq '}') 'the InitLib call is the last line of InitLibs'
    Check ((Get-Content (Join-Path $slot 'Base.StormData/includes.xml') -Raw) -match '<Path value="Mods/TestMode.StormMod"/>') 'includes.xml injects the mod'

    # Patching the slot in place must not duplicate anything.
    $r = Invoke-Pwsh $newMod @('-Name', 'TestMode', '-OutputPath', $out, '-MapSource', $slot)
    $again = Get-Content (Join-Path $slot 'MapScript.galaxy')
    Check ($r.Code -eq 0 -and @($again | Where-Object { $_ -match 'TestModeLib|libTest_InitLib' }).Count -eq 2) 'patching in place adds nothing'

    # After a game patch: a new stock map with -Force replaces the map and keeps the mod's code.
    $libFile = Join-Path $out 'mods/TestMode.StormMod/Base.StormData/TestModeLib.galaxy'
    Add-Content -LiteralPath $libFile '// my code'
    $r = Invoke-Pwsh $newMod @('-Name', 'TestMode', '-OutputPath', $out, '-MapSource', $map, '-Force')
    $fresh = Get-Content (Join-Path $slot 'MapScript.galaxy')
    Check ($r.Code -eq 0 -and $r.Text -match 'left unchanged') 'a rerun with -Force leaves an existing mod alone'
    Check ((Get-Content $libFile -Raw) -match '// my code') 'the mod''s own code survives'
    Check (@($fresh | Where-Object { $_ -match 'TestModeLib|libTest_InitLib' }).Count -eq 2) 'the new map is patched once'
    $r = Invoke-Pwsh $newMod @('-Name', 'TestMode', '-OutputPath', $out, '-MapSource', $map)
    Check ($r.Code -ne 0 -and $r.Text -match 'pass -Force') 'replacing a map without -Force is refused'

    # ------------------------------------------------------------------ lint
    $mod = Join-Path $out 'mods/TestMode.StormMod'
    $r = Invoke-Pwsh $lint @("$out/maps", '-Recurse', '-With', $mod)
    Check ($r.Code -eq 0 -and $r.Text -match '0 error\(s\)') 'Test-StormDocument passes the patched map'
    Check ($r.Text -notmatch 'TestModeLib') 'the map''s include of the library resolves through -With'
    $r = Invoke-Pwsh $lint @($mod)
    Check ($r.Code -eq 0 -and $r.Text -match '0 error\(s\), 0 warning\(s\)') 'Test-StormDocument passes the scaffolded mod'

    $broken = Join-Path $work 'Broken.StormMod'
    Copy-Item -Recurse $mod $broken
    Add-Content -LiteralPath (Join-Path $broken 'Base.StormData/GameData/TestModeData.xml') '<oops>'
    (Get-Content (Join-Path $broken 'Base.StormData/GameData.xml') -Raw).Replace('TestModeData.xml', 'Missing.xml') | Set-Content (Join-Path $broken 'Base.StormData/GameData.xml') -NoNewline
    Add-Content -LiteralPath (Join-Path $broken 'enUS.StormData/LocalizedData/GameStrings.txt') "no equals sign here`r`nTestMode/Loaded=twice`r`n"
    $r = Invoke-Pwsh $lint @($broken)
    Check ($r.Code -eq 1) 'Test-StormDocument fails a broken mod'
    Check ($r.Text -match 'TestModeData.xml is not well-formed XML') 'it reports malformed XML'
    Check ($r.Text -match "GameData.xml lists 'GameData/Missing.xml'") 'it reports a missing catalog'
    Check ($r.Text -match 'is not Key=Value') 'it reports a bad GameStrings line'
    Check ($r.Text -match "duplicates key 'TestMode/Loaded'") 'it reports a duplicate string key'

    # ------------------------------------------------------------------ natives
    $lib = Join-Path $work 'Test.TriggerLib'
    Write-Utf8 $lib @'
<?xml version="1.0" encoding="utf-8"?>
<TriggerData>
    <Element Type="FunctionDef" Id="1">
        <Identifier>UnitCreate</Identifier>
        <FlagNative/>
        <ReturnType><Type Value="unitgroup"/></ReturnType>
        <Parameter Type="ParamDef" Library="Ntve" Id="11"/>
        <Parameter Type="ParamDef" Library="Ntve" Id="12"/>
        <Parameter Type="ParamDef" Library="Ntve" Id="13"/>
    </Element>
    <Element Type="ParamDef" Id="11"><Identifier>count</Identifier><ParameterType><Type Value="int"/></ParameterType></Element>
    <Element Type="ParamDef" Id="12"><Identifier>type</Identifier><ParameterType><Type Value="gamelink"/><GameType Value="Unit"/></ParameterType></Element>
    <Element Type="ParamDef" Id="13"><Identifier>flags</Identifier><ParameterType><Type Value="preset"/><TypeElement Type="Preset" Library="Ntve" Id="20"/></ParameterType></Element>
    <Element Type="Preset" Id="20"><BaseType Value="int"/></Element>
    <Element Type="FunctionDef" Id="2">
        <Identifier>TriggerAddEventMapInit</Identifier>
        <FlagEvent/>
        <FlagNative/>
    </Element>
    <Element Type="FunctionDef" Id="3">
        <Identifier>DialogCreate</Identifier>
        <FlagNative/>
        <ReturnType><Type Value="dialog"/></ReturnType>
    </Element>
    <Element Type="FunctionDef" Id="4">
        <Identifier>libNtve_gf_Helper</Identifier>
    </Element>
</TriggerData>
'@
    $r = Invoke-Pwsh $natives @($lib)
    Check ($r.Text -match [regex]::Escape('native unitgroup UnitCreate(int count, string type, int flags);')) 'Get-GalaxyNatives prints a native with game links as string and presets as int'
    Check ($r.Text -match [regex]::Escape('native void TriggerAddEventMapInit(trigger trig);')) 'it restores the trigger argument of events'
    Check ($r.Text -match [regex]::Escape('native int DialogCreate();')) 'it maps editor-only types to script types'
    Check ($r.Text -notmatch 'libNtve_gf_Helper') 'it skips library functions without -All'

    # ------------------------------------------------------------------ mpq
    if (Get-Command dotnet -ErrorAction SilentlyContinue) {
        $archive = Join-Path $work 'TestMode.StormMod.mpq'
        $unpacked = Join-Path $work 'unpacked'
        Push-Location (Split-Path $mpq -Parent)
        try {
            $packOut = & dotnet run mpq.cs -- pack $mod $archive 2>&1
            Check ($LASTEXITCODE -eq 0) "mpq.cs pack ($($packOut | Select-Object -Last 1))"
            $verifyOut = & dotnet run mpq.cs -- verify $archive 2>&1
            Check ($LASTEXITCODE -eq 0 -and ($verifyOut -join ' ') -match ', 0 do not') 'mpq.cs verify matches (attributes)'
            $null = & dotnet run mpq.cs -- unpack $archive $unpacked 2>&1
            Check ($LASTEXITCODE -eq 0) 'mpq.cs unpack'
        }
        finally {
            Pop-Location
        }
        $a = Get-ChildItem $mod -Recurse -File | ForEach-Object { '{0} {1}' -f $_.FullName.Substring($mod.Length), (Get-FileHash $_.FullName).Hash } | Sort-Object
        $b = Get-ChildItem $unpacked -Recurse -File | Where-Object Name -notin '(listfile)', '(attributes)' | ForEach-Object { '{0} {1}' -f $_.FullName.Substring($unpacked.Length), (Get-FileHash $_.FullName).Hash } | Sort-Object
        Check (@(Compare-Object $a $b).Count -eq 0 -and @($a).Count -gt 0) "pack then unpack returns all $(@($a).Count) files byte-identical"
    }
    else {
        Write-Output 'skip mpq.cs (no dotnet)'
    }

    # ------------------------------------------------------------------ install
    if ($IsWindows) {
        $game = Join-Path $work 'game'
        New-Item -ItemType Directory -Force -Path (Join-Path $game 'HeroesData') | Out-Null
        Set-Content (Join-Path $game '.build.info') 'test'
        $existing = Join-Path $game 'maps/heroes/singleplayermaps/startingexperience/tutorialveteran.stormmap'
        New-Item -ItemType Directory -Force -Path $existing | Out-Null
        Set-Content (Join-Path $existing 'marker.txt') 'original'

        $r = Invoke-Pwsh $install @('-Source', $out, '-GamePath', $game)
        Check ($r.Code -eq 0 -and $r.Text -match 'backed up') 'Install-HotsMod copies and backs up the existing slot'
        Check (Test-Path (Join-Path $game 'mods/TestMode.StormMod/DocumentInfo')) 'the mod is in the game folder'
        $r = Invoke-Pwsh $install @('-Source', $out, '-GamePath', $game, '-Link')
        Check ($r.Code -eq 0 -and (Get-Item (Join-Path $game 'mods/TestMode.StormMod') -Force).LinkType -eq 'Junction') 'reinstall with -Link makes junctions'
        $r = Invoke-Pwsh $install @('-Uninstall', '-GamePath', $game)
        Check ($r.Code -eq 0 -and (Get-Content (Join-Path $existing 'marker.txt')) -eq 'original') 'uninstall restores the original slot'
        Check (-not (Test-Path (Join-Path $game 'mods')) -and -not (Test-Path (Join-Path $game '.hots-mods'))) 'uninstall leaves nothing behind'
        Check (Test-Path (Join-Path $mod 'DocumentInfo')) 'removing junctions leaves the source alone'
    }
    else {
        Write-Output 'skip Install-HotsMod (Windows only)'
    }
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failed -gt 0) {
    Write-Output "$failed check(s) failed"
    exit 1
}
Write-Output 'all checks passed'
