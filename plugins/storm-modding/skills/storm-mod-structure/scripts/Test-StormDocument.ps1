<#
.SYNOPSIS
    Checks folder-format Storm documents (.stormmap, .stormmod, .StormInterface) for the mistakes
    that make the game refuse a map with no useful message.

.DESCRIPTION
    Read-only. For each document it checks:
    - every XML file parses (.xml, .StormLayout, .StormStyle, .StormComponents, .StormCutscene,
      .aitree, and the extension-less DocumentInfo, Triggers, Objects, Regions, Attributes);
    - ComponentList.StormComponents exists and the files it names exist;
    - DocumentInfo dependencies have the bnet:<name>/<ver>/<id>,file:<path> form;
    - includes.xml injects into one of the ModifiableDependencies;
    - every GameData.xml <Catalog path> and DescIndex <Include path> exists;
    - GameStrings.txt files are UTF-8 with a BOM, Key=Value on every line, no duplicate keys;
    - Galaxy include "X" lines resolve inside the document or the -With documents. Unresolved
      includes are listed as notes, since they may come from the game's own mods.
    File lookups ignore case and treat / and \ alike, as the game does.

.PARAMETER Path
    A document folder, or with -Recurse a folder to search for documents.

.PARAMETER With
    Other document folders whose Base.StormData also counts when resolving Galaxy includes, for
    example the mod a map injects with includes.xml.

.PARAMETER Recurse
    Find every document folder under Path (a folder holding ComponentList.StormComponents, or named
    *.stormmap / *.stormmod / *.StormInterface).

.EXAMPLE
    pwsh -NoProfile -File Test-StormDocument.ps1 .\mods\MyMod.StormMod

.EXAMPLE
    pwsh -NoProfile -File Test-StormDocument.ps1 .\maps -Recurse -With .\mods\MyMod.StormMod
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $Path,
    [string[]] $With = @(),
    [switch] $Recurse
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:errors = 0
$script:warnings = 0

function Write-Finding([string] $Level, [string] $Doc, [string] $Message) {
    switch ($Level) {
        'ERROR' { $script:errors++ }
        'WARN' { $script:warnings++ }
    }
    Write-Output ('{0,-5} {1}: {2}' -f $Level, $Doc, $Message)
}

function Get-RelativeKey([string] $Root, [string] $Full) {
    $Full.Substring($Root.Length).TrimStart('\', '/').Replace('\', '/').ToLowerInvariant()
}

function Get-FileIndex([string] $Root) {
    $index = @{}
    foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -File -Force) {
        $index[(Get-RelativeKey $Root $file.FullName)] = $file.FullName
    }
    $index
}

function Find-Entry([hashtable] $Index, [string[]] $Candidates) {
    foreach ($candidate in $Candidates) {
        $key = $candidate.Replace('\', '/').TrimStart('/').ToLowerInvariant()
        if ($Index.ContainsKey($key)) { return $Index[$key] }
    }
    $null
}

function Read-Xml([string] $File) {
    $settings = [System.Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $reader = [System.Xml.XmlReader]::Create($File, $settings)
    try {
        $doc = [System.Xml.XmlDocument]::new()
        $doc.Load($reader)
        $doc
    }
    finally {
        $reader.Dispose()
    }
}

function Get-DataFolderName([hashtable] $Index, [string] $Root) {
    # Base.StormData, base.stormdata, Base.SC2Data: return the folder name as it is on disk.
    foreach ($dir in Get-ChildItem -LiteralPath $Root -Directory -Force) {
        if ($dir.Name -match '^base\.(stormdata|sc2data)$') { return $dir.Name }
    }
    'Base.StormData'
}

$xmlExtensions = @('.xml', '.stormlayout', '.stormstyle', '.stormcomponents', '.stormcutscene', '.aitree',
    '.sc2layout', '.sc2style', '.sc2components', '.sc2cutscene')
$xmlNoExtension = @('documentinfo', 'triggers', 'objects', 'regions', 'attributes')
$rootComponentFiles = @{ info = 'DocumentInfo'; trig = 'Triggers'; mapi = 'MapInfo'; terr = 't3Terrain.xml';
    plob = 'Objects'; regi = 'Regions'; attr = 'Attributes'
}

function Test-Document([string] $Root, [hashtable[]] $Extra) {
    $doc = Split-Path $Root -Leaf
    $index = Get-FileIndex $Root
    $data = Get-DataFolderName $index $Root
    $dataKey = $data.ToLowerInvariant()

    # 1. XML well-formedness. Later checks use these documents and skip files that did not parse.
    $xml = @{}
    foreach ($key in $index.Keys) {
        $name = [System.IO.Path]::GetFileName($key)
        $ext = [System.IO.Path]::GetExtension($key)
        if ($xmlExtensions -notcontains $ext -and $xmlNoExtension -notcontains $name) { continue }
        if ($key.StartsWith('(')) { continue }
        try {
            $xml[$index[$key]] = Read-Xml $index[$key]
        }
        catch {
            Write-Finding 'ERROR' $doc ("{0} is not well-formed XML: {1}" -f $key, $_.Exception.InnerException?.Message ?? $_.Exception.Message)
        }
    }

    # 2. ComponentList
    $componentList = Find-Entry $index @('ComponentList.StormComponents', 'ComponentList.SC2Components')
    $locales = @()
    if (-not $componentList) {
        Write-Finding 'ERROR' $doc 'no ComponentList.StormComponents at the document root'
    }
    else {
        $components = $xml[$componentList]
        if ($components) {
            foreach ($component in $components.SelectNodes('/Components/DataComponent')) {
                $type = $component.GetAttribute('Type')
                $target = $component.get_InnerText().Trim()
                if ($rootComponentFiles.ContainsKey($type)) {
                    if (-not (Find-Entry $index @($target))) {
                        Write-Finding 'ERROR' $doc "ComponentList names $type '$target' but the file is missing"
                    }
                }
                elseif ($type -in 'uiui', 'font') {
                    if (-not (Find-Entry $index @("$data/$target"))) {
                        Write-Finding 'ERROR' $doc "ComponentList names $type '$data/$target' but the file is missing"
                    }
                }
                elseif ($type -eq 'text') {
                    $locale = $component.GetAttribute('Locale')
                    $locales += $locale
                    if (-not (Find-Entry $index @("$locale.StormData/LocalizedData/GameStrings.txt", "$locale.SC2Data/LocalizedData/GameStrings.txt"))) {
                        Write-Finding 'WARN' $doc "ComponentList declares text for $locale but $locale.StormData/LocalizedData/GameStrings.txt is missing"
                    }
                }
            }
        }
    }

    # 3. DocumentInfo dependencies
    $modifiable = @()
    $documentInfo = Find-Entry $index @('DocumentInfo')
    if (-not $documentInfo) {
        Write-Finding 'ERROR' $doc 'no DocumentInfo at the document root'
    }
    else {
        $info = $xml[$documentInfo]
        if ($info) {
            foreach ($value in $info.SelectNodes('/DocInfo/Dependencies/Value')) {
                $dep = $value.get_InnerText().Trim()
                if ($dep -notmatch '^bnet:[^/]+/\d+\.\d+/\d+,file:.+$') {
                    Write-Finding 'WARN' $doc "dependency '$dep' is not in the bnet:<name>/<ver>/<id>,file:<path> form"
                }
            }
            $modifiable = @($info.SelectNodes('/DocInfo/ModifiableDependencies/Value') | ForEach-Object { $_.get_InnerText().Trim() })
        }
    }

    # 4. includes.xml mod injection
    $includes = Find-Entry $index @("$data/includes.xml")
    if ($includes) {
        $inc = $xml[$includes]
        if ($inc) {
            $includesRoot = $inc.get_DocumentElement()
            if ($includesRoot.get_LocalName() -ne 'Includes') {
                Write-Finding 'ERROR' $doc "$data/includes.xml root is <$($includesRoot.get_LocalName())>, expected <Includes id=...>"
            }
            else {
                $id = $includesRoot.GetAttribute('id')
                $paths = @($includesRoot.SelectNodes('Path') | ForEach-Object { $_.GetAttribute('value') })
                if ($paths.Count -gt 0) {
                    $match = $modifiable | Where-Object { $_.Replace('\', '/') -ieq $id.Replace('\', '/') }
                    if ($modifiable.Count -gt 0 -and -not $match) {
                        Write-Finding 'WARN' $doc "includes.xml injects into '$id', which is not one of the ModifiableDependencies ($($modifiable -join ', '))"
                    }
                    Write-Finding 'NOTE' $doc ("includes.xml adds {0} to {1}" -f ($paths -join ', '), $id)
                }
            }
        }
    }

    # 5. GameData.xml catalogs
    $gameData = Find-Entry $index @("$data/GameData.xml")
    if ($gameData) {
        $gd = $xml[$gameData]
        if ($gd) {
            foreach ($catalog in $gd.SelectNodes('/Includes/Catalog')) {
                $p = $catalog.GetAttribute('path')
                if (-not (Find-Entry $index @("$data/$p"))) {
                    Write-Finding 'ERROR' $doc "GameData.xml lists '$p' but $data/$p is missing"
                }
            }
        }
    }

    # 6. DescIndex includes
    $descIndex = Find-Entry $index @("$data/UI/Layout/DescIndex.StormLayout", "$data/UI/Layout/DescIndex.SC2Layout")
    if ($descIndex) {
        $di = $xml[$descIndex]
        if ($di) {
            foreach ($include in $di.SelectNodes('/Desc/*[translate(local-name(), "INCLUDE", "include")="include"]')) {
                $p = $include.GetAttribute('path')
                if (-not (Find-Entry $index @("$data/$p", $p))) {
                    $level = if ($include.GetAttribute('requiredtoload')) { 'NOTE' } else { 'ERROR' }
                    Write-Finding $level $doc "DescIndex includes '$p' but it is not in this document"
                }
            }
        }
    }

    # 7. GameStrings.txt
    foreach ($key in @($index.Keys | Where-Object { $_ -match '/localizeddata/gamestrings\.txt$' })) {
        $bytes = [System.IO.File]::ReadAllBytes($index[$key])
        if ($bytes.Length -ge 3 -and -not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) {
            Write-Finding 'WARN' $doc "$key has no UTF-8 BOM (Blizzard's files have one)"
        }
        $seen = @{}
        $lineNo = 0
        foreach ($line in [System.Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF) -split "`r?`n") {
            $lineNo++
            if ($line.Trim() -eq '') { continue }
            $eq = $line.IndexOf('=')
            if ($eq -le 0) {
                Write-Finding 'ERROR' $doc "${key}:$lineNo is not Key=Value: $($line.Substring(0, [Math]::Min(60, $line.Length)))"
                continue
            }
            $k = $line.Substring(0, $eq)
            if ($seen.ContainsKey($k)) {
                Write-Finding 'WARN' $doc "${key}:$lineNo duplicates key '$k' (first at line $($seen[$k]); the last one wins)"
            }
            else {
                $seen[$k] = $lineNo
            }
        }
    }

    # 8. Galaxy includes
    $galaxyIndex = @{}
    foreach ($source in @(@{ Index = $index; Data = $dataKey }) + $Extra) {
        foreach ($k in $source.Index.Keys) {
            if (-not $k.EndsWith('.galaxy')) { continue }
            $rel = $k
            if ($rel.StartsWith("$($source.Data)/")) { $rel = $rel.Substring($source.Data.Length + 1) }
            $galaxyIndex[$rel.Substring(0, $rel.Length - '.galaxy'.Length)] = $true
        }
    }
    $external = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($key in @($index.Keys | Where-Object { $_.EndsWith('.galaxy') })) {
        foreach ($match in [regex]::Matches([System.IO.File]::ReadAllText($index[$key]), '(?m)^\s*include\s+"([^"]+)"')) {
            $target = $match.Groups[1].Value.Replace('\', '/').ToLowerInvariant()
            if ($target.EndsWith('.galaxy')) { $target = $target.Substring(0, $target.Length - 7) }
            if (-not $galaxyIndex.ContainsKey($target)) { [void]$external.Add($match.Groups[1].Value) }
        }
    }
    if ($external.Count -gt 0) {
        Write-Finding 'NOTE' $doc ("Galaxy includes not in this document (must come from a dependency or -With): {0}" -f ($external -join ', '))
    }

    Write-Output ("      {0}: {1} files, {2} XML files parsed" -f $doc, $index.Count, $xml.Count)
}

$full = (Resolve-Path -LiteralPath $Path).ProviderPath
$extra = @(foreach ($w in $With) {
        $wFull = (Resolve-Path -LiteralPath $w).ProviderPath
        $wIndex = Get-FileIndex $wFull
        @{ Index = $wIndex; Data = (Get-DataFolderName $wIndex $wFull).ToLowerInvariant() }
    })

$documents = @(if ($Recurse) {
    @(Get-ChildItem -LiteralPath $full -Recurse -Directory -Force | Where-Object {
            $_.Name -match '\.(stormmap|stormmod|storminterface|sc2map|sc2mod|sc2interface)$' -and
            -not ($_.Parent.FullName -match '\.(stormmap|stormmod|storminterface)(\\|/|$)')
        } | ForEach-Object FullName)
}
else {
    $full
})

if ($documents.Count -eq 0) {
    Write-Output "no Storm documents under $full"
    exit 1
}

foreach ($document in $documents) {
    Test-Document $document $extra
}

Write-Output ("{0} document(s), {1} error(s), {2} warning(s)" -f $documents.Count, $script:errors, $script:warnings)
exit ($script:errors -gt 0 ? 1 : 0)
