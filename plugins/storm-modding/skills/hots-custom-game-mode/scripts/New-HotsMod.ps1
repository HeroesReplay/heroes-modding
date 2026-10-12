<#
.SYNOPSIS
    Scaffolds a Heroes of the Storm mod in folder format and, given a map folder, wires the mod into
    one of the four built-in single-player map slots (Veteran Challenges by default).

.DESCRIPTION
    Writes, under OutputPath, the same layout the game reads from its install folder:

      mods\<Name>.StormMod\                          the mod: library, data, strings, UI index
      maps\heroes\singleplayermaps\...\<slot>.stormmap\   a copy of -MapSource, patched

    The map patch is what Heroes Rogue does by hand:
      - Base.StormData\includes.xml adds Mods/<Name>.StormMod to Mods/HeroesData.StormMod;
      - MapScript.galaxy gets include "<Name>Lib" after its last include (under a "// hots-mod" line)
        and lib<ID>_InitLib(); // hots-mod at the end of InitLibs(). Neither is added twice.

    Get a map to start from with the hots-casc-game-files skill, for example the stock Veteran map:
    mods/heroes.stormmod/base.stormmaps/maps/heroes/singleplayermaps/startingexperience/tutorialveteran.stormmap/

    Install the result with Install-HotsMod.ps1. Nothing here touches the game folder.

.PARAMETER Name
    Mod name, letters and digits (MyMod). The library is <Name>Lib, the folder <Name>.StormMod.

.PARAMETER LibId
    Four-character library id used as the lib<ID>_ prefix. Default: the first four letters of Name.

.PARAMETER OutputPath
    Work folder that gets mods\ and maps\ (a git repository for your mod, typically).

.PARAMETER MapSource
    A folder-format map to copy into the slot and patch. Without it only the mod is written.

.PARAMETER Slot
    tutorialveteran (Challenges, default), trymemode (Try Mode), tutorial01, tutorialmapmechanics.

.PARAMETER Force
    Replace an existing map folder in the slot with -MapSource. An existing mod folder is never
    rewritten (delete it yourself for a fresh skeleton), so after a game patch you can run this
    again with the new stock map and -Force and keep your mod. -MapSource may be the slot folder
    itself, to re-apply the patch in place.

.EXAMPLE
    pwsh -File New-HotsMod.ps1 -Name RogueLite -OutputPath C:\src\roguelite -MapSource C:\casc\mods\heroes.stormmod\base.stormmaps\maps\heroes\singleplayermaps\startingexperience\tutorialveteran.stormmap
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z][A-Za-z0-9]{1,30}$')][string] $Name,
    [ValidatePattern('^[A-Za-z][A-Za-z0-9]{3}$')][string] $LibId,
    [Parameter(Mandatory)][string] $OutputPath,
    [string] $MapSource,
    [ValidateSet('tutorialveteran', 'trymemode', 'tutorial01', 'tutorialmapmechanics')][string] $Slot = 'tutorialveteran',
    [switch] $Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $LibId) {
    $letters = ($Name -replace '[^A-Za-z]', '')
    $LibId = ($letters + 'Modd').Substring(0, 4)
}
$prefix = "lib$LibId"
$slots = @{
    tutorialveteran      = 'maps\heroes\singleplayermaps\startingexperience\tutorialveteran.stormmap'
    trymemode            = 'maps\heroes\singleplayermaps\(10)trymemode.stormmap'
    tutorial01           = 'maps\heroes\singleplayermaps\startingexperience\tutorial01.stormmap'
    tutorialmapmechanics = 'maps\heroes\singleplayermaps\startingexperience\tutorialmapmechanics.stormmap'
}

$out = [System.IO.Path]::GetFullPath($OutputPath)
$utf8 = [System.Text.UTF8Encoding]::new($false)
$utf8Bom = [System.Text.UTF8Encoding]::new($true)

function Write-TextFile([string] $Path, [string] $Text, [switch] $Bom) {
    $dir = Split-Path $Path -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $crlf = (($Text -replace "`r`n", "`n").TrimEnd("`n") + "`n") -replace "`n", "`r`n"
    [System.IO.File]::WriteAllText($Path, $crlf, $(if ($Bom) { $utf8Bom } else { $utf8 }))
}

# ---------------------------------------------------------------------------------------------
# The mod
# ---------------------------------------------------------------------------------------------
$mod = Join-Path $out "mods\$Name.StormMod"
$modExists = Test-Path -LiteralPath $mod
if ($modExists) {
    Write-Output "mod:  $mod exists; left unchanged"
}

if (-not $modExists -and $PSCmdlet.ShouldProcess($mod, 'write mod skeleton')) {
    Write-TextFile "$mod\ComponentList.StormComponents" @'
<?xml version="1.0" encoding="us-ascii"?>
<Components>
    <DataComponent Type="gada">GameData</DataComponent>
    <DataComponent Type="text" Locale="enUS">GameText</DataComponent>
    <DataComponent Type="info">DocumentInfo</DataComponent>
    <DataComponent Type="trig">Triggers</DataComponent>
    <DataComponent Type="uiui">UI/Layout/DescIndex.StormLayout</DataComponent>
    <DataComponent Type="font">UI/FontStyles.StormStyle</DataComponent>
</Components>
'@

    Write-TextFile "$mod\DocumentInfo" @'
<?xml version="1.0" encoding="utf-8"?>
<DocInfo>
    <Dependencies>
        <Value>bnet:Heroes of the Storm (Data Mod)/0.0/999,file:Mods/HeroesData.StormMod</Value>
    </Dependencies>
</DocInfo>
'@

    # The editor's trigger source; a stub that reserves the library id.
    Write-TextFile "$mod\Triggers" @"
<?xml version="1.0" encoding="utf-8"?>
<TriggerData>
    <Library Id="$LibId"></Library>
</TriggerData>
"@

    Write-TextFile "$mod\Base.StormData\GameData.xml" @"
<?xml version="1.0" encoding="us-ascii"?>
<Includes>
    <Catalog path="GameData/${Name}Data.xml"/>
</Includes>
"@

    Write-TextFile "$mod\Base.StormData\GameData\${Name}Data.xml" @"
<?xml version="1.0" encoding="us-ascii"?>
<Catalog>
    <!--
    Add entries with a new id and a parent, or override a Blizzard entry by repeating its id with
    only the fields you change (storm-data-xml skill). Example, commented out:

    <CBehaviorBuff id="${Name}HasteBuff" parent="CarryBehaviorParent">
        <Duration value="4"/>
        <Modification>
            <UnifiedMoveSpeedFactor value="0.25"/>
        </Modification>
    </CBehaviorBuff>
    -->
</Catalog>
"@

    Write-TextFile "$mod\Base.StormData\${Name}Lib_h.galaxy" @"
include "TriggerLibs/NativeLib"

//--------------------------------------------------------------------------------------------------
// Library: $Name ($LibId)
//--------------------------------------------------------------------------------------------------
// Constants
const string ${prefix}_ModName = "$Name";
const bool ${prefix}_DEBUG = false;

// Trigger Variables
trigger ${prefix}_gt_Hello;

// Library Initialization
void ${prefix}_InitVariables ();
"@

    Write-TextFile "$mod\Base.StormData\${Name}Lib.galaxy" @"
include "TriggerLibs/NativeLib"

include "${Name}Lib_h"

//--------------------------------------------------------------------------------------------------
// Library: $Name
//--------------------------------------------------------------------------------------------------
// External Library Initialization
void ${prefix}_InitLibraries () {
    libNtve_InitVariables();
}

// Variable Initialization
bool ${prefix}_InitVariables_completed = false;

void ${prefix}_InitVariables () {
    if (${prefix}_InitVariables_completed) {
        return;
    }

    ${prefix}_InitVariables_completed = true;
}

//--------------------------------------------------------------------------------------------------
// Trigger: Hello (two game seconds after the map starts)
//--------------------------------------------------------------------------------------------------
bool ${prefix}_gt_Hello_Func (bool testConds, bool runActions) {
    if (!runActions) {
        return true;
    }

    UIDisplayMessage(PlayerGroupAll(), c_messageAreaDebug, StringExternal("$Name/Loaded"));
    return true;
}

//--------------------------------------------------------------------------------------------------
void ${prefix}_gt_Hello_Init () {
    ${prefix}_gt_Hello = TriggerCreate("${prefix}_gt_Hello_Func");
    TriggerAddEventTimeElapsed(${prefix}_gt_Hello, 2.0, c_timeGame);
}

void ${prefix}_InitTriggers () {
    ${prefix}_gt_Hello_Init();
}

//--------------------------------------------------------------------------------------------------
// Library Initialization
//--------------------------------------------------------------------------------------------------
bool ${prefix}_InitLib_completed = false;

void ${prefix}_InitLib () {
    if (${prefix}_InitLib_completed) {
        return;
    }

    ${prefix}_InitLib_completed = true;

    ${prefix}_InitLibraries();
    ${prefix}_InitVariables();
    ${prefix}_InitTriggers();
}
"@

    Write-TextFile "$mod\Base.StormData\UI\Layout\DescIndex.StormLayout" @'
<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<Desc>
</Desc>
'@

    Write-TextFile "$mod\Base.StormData\UI\FontStyles.StormStyle" @'
<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<StyleFile>
</StyleFile>
'@

    Write-TextFile "$mod\enUS.StormData\LocalizedData\GameStrings.txt" -Bom @"
DocInfo/Name=$Name
$Name/Loaded=$Name is loaded.
"@
}

# ---------------------------------------------------------------------------------------------
# The map
# ---------------------------------------------------------------------------------------------
$mapTarget = $null
if ($MapSource) {
    $source = (Resolve-Path -LiteralPath $MapSource).ProviderPath
    if (-not (Test-Path -LiteralPath (Join-Path $source 'MapScript.galaxy'))) {
        throw "$source has no MapScript.galaxy; pass a folder-format .stormmap"
    }
    $mapTarget = [System.IO.Path]::GetFullPath((Join-Path $out $slots[$Slot]))
    $separator = [System.IO.Path]::DirectorySeparatorChar
    $sourceKey = $source.TrimEnd('\', '/') + $separator
    $targetKey = $mapTarget.TrimEnd('\', '/') + $separator
    $ignoreCase = [System.StringComparison]::OrdinalIgnoreCase
    $inPlace = [string]::Equals($sourceKey, $targetKey, $ignoreCase)
    if (-not $inPlace -and ($targetKey.StartsWith($sourceKey, $ignoreCase) -or $sourceKey.StartsWith($targetKey, $ignoreCase))) {
        throw "-MapSource and the slot folder overlap ($source, $mapTarget)"
    }
    if (-not $inPlace -and (Test-Path -LiteralPath $mapTarget) -and -not $Force) {
        throw "$mapTarget exists; pass -Force to replace it with $source"
    }

    $action = if ($inPlace) { "inject $Name in place" } else { "copy $source and inject $Name" }
    if ($PSCmdlet.ShouldProcess($mapTarget, $action)) {
        if (-not $inPlace) {
            if (Test-Path -LiteralPath $mapTarget) { Remove-Item -LiteralPath $mapTarget -Recurse -Force }
            New-Item -ItemType Directory -Force -Path (Split-Path $mapTarget -Parent) | Out-Null
            Copy-Item -LiteralPath $source -Destination $mapTarget -Recurse
        }

        $dataDir = Get-ChildItem -LiteralPath $mapTarget -Directory | Where-Object Name -match '^base\.stormdata$' | Select-Object -First 1
        $dataPath = if ($dataDir) { $dataDir.FullName } else { New-Item -ItemType Directory -Path (Join-Path $mapTarget 'Base.StormData') | ForEach-Object FullName }

        # DocumentInfo must let us modify HeroesData.
        $info = [xml](Get-Content -LiteralPath (Join-Path $mapTarget 'DocumentInfo') -Raw)
        $modifiable = @($info.SelectNodes('/DocInfo/ModifiableDependencies/Value') | ForEach-Object { $_.get_InnerText().Trim().Replace('\', '/') })
        if ($modifiable -notcontains 'Mods/HeroesData.StormMod') {
            Write-Warning "DocumentInfo does not list Mods/HeroesData.StormMod under ModifiableDependencies ($($modifiable -join ', ')); includes.xml may be ignored"
        }

        # includes.xml: add our Path to the HeroesData include set.
        $includesFile = Get-ChildItem -LiteralPath $dataPath -File | Where-Object Name -ieq 'includes.xml' | Select-Object -First 1
        $pathValue = "Mods/$Name.StormMod"
        if ($includesFile) {
            $inc = [xml](Get-Content -LiteralPath $includesFile.FullName -Raw)
            $exists = @($inc.SelectNodes('/Includes/Path') | Where-Object { $_.GetAttribute('value') -ieq $pathValue }).Count -gt 0
            if (-not $exists) {
                $node = $inc.CreateElement('Path')
                $node.SetAttribute('value', $pathValue)
                [void]$inc.get_DocumentElement().AppendChild($node)
                $inc.Save($includesFile.FullName)
            }
        }
        else {
            Write-TextFile (Join-Path $dataPath 'includes.xml') @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Includes id="Mods/HeroesData.StormMod">
    <Path value="$pathValue"/>
</Includes>
"@
        }

        # MapScript.galaxy: include the library and call its InitLib from InitLibs().
        $scriptPath = Join-Path $mapTarget 'MapScript.galaxy'
        $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
        $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
        $text = [System.Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF)
        $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
        $lines = [System.Collections.Generic.List[string]]::new($text -split "`r?`n")

        $includeLine = "include `"${Name}Lib`""
        if (-not ($lines | Where-Object { $_ -match "^\s*include\s+`"${Name}Lib`"" })) {
            $last = -1
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match '^\s*include\s+"') { $last = $i }
                elseif ($last -ge 0 -and $lines[$i] -match '^\s*(void|bool|int|const|trigger|static)\b') { break }
            }
            if ($last -lt 0) { throw "MapScript.galaxy has no include lines; patch it by hand" }
            $lines.Insert($last + 1, $includeLine)
            $lines.Insert($last + 1, '// hots-mod: the next line was added by New-HotsMod.ps1')
        }

        $initCall = "    ${prefix}_InitLib(); // hots-mod"
        if (-not ($lines | Where-Object { $_ -match "^\s*${prefix}_InitLib\(\);" })) {
            $start = -1
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match '^\s*void\s+InitLibs\s*\(\s*\)') { $start = $i; break }
            }
            if ($start -lt 0) { throw "MapScript.galaxy has no InitLibs(); patch it by hand" }
            $end = -1
            for ($i = $start + 1; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match '^\}') { $end = $i; break }
            }
            if ($end -lt 0) { throw "could not find the end of InitLibs()" }
            $lines.Insert($end, $initCall)
        }

        $encoding = if ($hasBom) { $utf8Bom } else { $utf8 }
        [System.IO.File]::WriteAllText($scriptPath, ($lines -join $newline), $encoding)
    }
}

if (-not $modExists) { Write-Output "mod:  $mod (library $prefix)" }
if ($mapTarget) {
    Write-Output "map:  $mapTarget (slot $Slot)"
}
else {
    Write-Output "map:  none. Copy a map into $($slots[$Slot]) under $out, then run again with -MapSource, or add"
    Write-Output "      include `"${Name}Lib`" and ${prefix}_InitLib(); to its MapScript.galaxy and Base.StormData/includes.xml by hand."
}
Write-Output "next: pwsh -File Test-StormDocument.ps1 `"$out\maps`" -Recurse -With `"$mod`"   (storm-mod-structure)"
Write-Output "      pwsh -File Install-HotsMod.ps1 -Source `"$out`""
