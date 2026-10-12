<#
.SYNOPSIS
    Checks the repository rules that the hosts' own validators miss (AGENTS.md, "Rules").

.DESCRIPTION
    Fails (exit 1) when:
    - the marketplace and plugins/* folders disagree, or an entry's source is not ./plugins/<name>;
    - a plugin.json is not Agent Plugins 1.0.0 with only the allowed keys, or its
      .claude-plugin/plugin.json differs from it (apart from $schema), or the marketplace entry's
      description differs from the manifest's;
    - a SKILL.md frontmatter breaks the Agent Skills rules (name = folder, lowercase-hyphen,
      at most 64 characters, unique, contains storm-, galaxy- or hots-; description at most 1024
      characters with no angle brackets; keys only name, description, license, compatibility,
      metadata);
    - a SKILL.md is 500 lines or longer, the descriptions together pass 6000 characters, or a file
      under plugins/ is over 5 MB;
    - a Markdown link in a SKILL.md is absolute, uses .., goes more than one folder deep, or points
      at a missing file;
    - plugins/ holds a symlink, a CLAUDE.md or a bin/ folder, a .md or .json file starts with a
      UTF-8 BOM, or a second marketplace file exists;
    - with -BaseRef, a plugin changed since that ref without a version bump.

.PARAMETER BaseRef
    Git ref to compare versions against (CI passes origin/main on pull requests).
#>
[CmdletBinding()]
param(
    [string] $BaseRef
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).ProviderPath
$failures = [System.Collections.Generic.List[string]]::new()
function Fail([string] $Message) { $failures.Add($Message) }

$agentSchema = 'https://agent-plugins.org/schemas/1.0.0/plugin.schema.json'
$manifestKeys = @('$schema', 'name', 'version', 'description', 'author', 'homepage', 'repository', 'license', 'keywords')
$skillKeys = @('name', 'description', 'license', 'compatibility', 'metadata')
$nameRegex = '^[a-z0-9]+(-[a-z0-9]+)*$'

function Read-Json([string] $Path) {
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
}

function ConvertTo-Canonical($Value) {
    # Order-independent JSON text for deep comparison.
    if ($Value -is [System.Collections.IDictionary]) {
        $sorted = [ordered]@{}
        foreach ($k in ($Value.Keys | Sort-Object)) { $sorted[$k] = ConvertTo-Canonical $Value[$k] }
        return $sorted
    }
    if ($Value -is [System.Collections.IList] -and $Value -isnot [string]) {
        return @($Value | ForEach-Object { ConvertTo-Canonical $_ })
    }
    $Value
}

function Read-Frontmatter([string] $Path) {
    # The subset of YAML the skills use: "key: value" and folded/literal blocks (>, >-, |, |-).
    $lines = Get-Content -LiteralPath $Path
    if ($lines.Count -lt 3 -or $lines[0] -ne '---') { return $null }
    $end = [Array]::IndexOf($lines, '---', 1)
    if ($end -lt 0) { return $null }
    $result = [ordered]@{}
    $i = 1
    while ($i -lt $end) {
        $line = $lines[$i]
        if ($line -match '^([A-Za-z0-9_-]+):\s*(.*)$') {
            $key = $Matches[1]
            $value = $Matches[2]
            if ($value -match '^[>|][-+]?$') {
                $block = @()
                $i++
                while ($i -lt $end -and ($lines[$i] -match '^\s+\S' -or $lines[$i] -eq '')) {
                    $block += $lines[$i].Trim()
                    $i++
                }
                $result[$key] = if ($value.StartsWith('>')) { ($block -join ' ').Trim() } else { ($block -join "`n").Trim() }
                continue
            }
            $result[$key] = $value.Trim().Trim('"').Trim("'")
        }
        elseif ($line -match '^\s+\S') {
            # nested map (metadata): ignore its children
        }
        else {
            Fail "$($Path): cannot parse frontmatter line '$line'"
        }
        $i++
    }
    $result
}

# 1. Marketplace and plugin folders
$marketplacePath = Join-Path $root '.claude-plugin/marketplace.json'
$marketplace = Read-Json $marketplacePath
$pluginDirs = @(Get-ChildItem -LiteralPath (Join-Path $root 'plugins') -Directory | ForEach-Object Name | Sort-Object)
$entryNames = @($marketplace.plugins | ForEach-Object { $_.name } | Sort-Object)
if (($pluginDirs -join ',') -ne ($entryNames -join ',')) {
    Fail "marketplace plugins ($($entryNames -join ', ')) differ from plugins/ folders ($($pluginDirs -join ', '))"
}
if ($marketplace.name -notmatch $nameRegex) { Fail "marketplace name '$($marketplace.name)' is not lowercase-hyphen" }
foreach ($extra in @('marketplace.json', '.github/plugin/marketplace.json', '.agents/plugins/marketplace.json', '.plugin/marketplace.json', 'CLAUDE.md')) {
    if (Test-Path -LiteralPath (Join-Path $root $extra)) { Fail "$extra must not exist (one marketplace file, AGENTS.md only)" }
}

# 2-3. Manifests
$allSkillNames = @{}
$descriptionTotal = 0
foreach ($entry in $marketplace.plugins) {
    $name = $entry.name
    $dir = Join-Path $root "plugins/$name"
    if ($entry.source -ne "./plugins/$name") { Fail "marketplace entry $name has source '$($entry.source)', expected ./plugins/$name" }
    if (-not (Test-Path -LiteralPath $dir)) { continue }

    $agentPath = Join-Path $dir 'plugin.json'
    $claudePath = Join-Path $dir '.claude-plugin/plugin.json'
    if (-not (Test-Path -LiteralPath $agentPath)) { Fail "plugins/$name/plugin.json is missing"; continue }
    if (-not (Test-Path -LiteralPath $claudePath)) { Fail "plugins/$name/.claude-plugin/plugin.json is missing"; continue }
    $agent = Read-Json $agentPath
    $claude = Read-Json $claudePath

    if ($agent['$schema'] -ne $agentSchema) { Fail "plugins/$name/plugin.json `$schema must be $agentSchema" }
    foreach ($k in $agent.Keys) { if ($manifestKeys -notcontains $k) { Fail "plugins/$name/plugin.json has key '$k' (allowed: $($manifestKeys -join ', '))" } }
    if ($agent.name -ne $name -or $name -notmatch $nameRegex -or $name.Length -gt 64) { Fail "plugins/$name/plugin.json name must be '$name' and lowercase-hyphen" }
    if ($agent.version -notmatch '^\d+\.\d+\.\d+$') { Fail "plugins/$name/plugin.json version '$($agent.version)' is not semver" }
    if ($agent.description.Length -gt 200) { Fail "plugins/$name description is $($agent.description.Length) characters (keep it at 200 or fewer)" }

    $withoutSchema = [ordered]@{}
    foreach ($k in $agent.Keys) { if ($k -ne '$schema') { $withoutSchema[$k] = $agent[$k] } }
    $a = ConvertTo-Canonical $withoutSchema | ConvertTo-Json -Depth 10 -Compress
    $c = ConvertTo-Canonical $claude | ConvertTo-Json -Depth 10 -Compress
    if ($a -ne $c) { Fail "plugins/$name/.claude-plugin/plugin.json differs from plugin.json (apart from `$schema)" }
    if ($entry.description -ne $agent.description) { Fail "marketplace description of $name differs from its plugin.json" }

    # 4-6. Skills
    $skillsDir = Join-Path $dir 'skills'
    if (-not (Test-Path -LiteralPath $skillsDir)) { Fail "plugins/$name has no skills/ folder"; continue }
    foreach ($skill in Get-ChildItem -LiteralPath $skillsDir -Directory) {
        $rel = "plugins/$name/skills/$($skill.Name)"
        $skillMd = Join-Path $skill.FullName 'SKILL.md'
        if (-not (Test-Path -LiteralPath $skillMd)) { Fail "$rel has no SKILL.md"; continue }
        $fm = Read-Frontmatter $skillMd
        if (-not $fm) { Fail "$rel/SKILL.md has no frontmatter"; continue }
        foreach ($k in $fm.Keys) { if ($skillKeys -notcontains $k) { Fail "$rel/SKILL.md frontmatter key '$k' (allowed: $($skillKeys -join ', '))" } }
        $skillName = [string]$fm['name']
        if ($skillName -ne $skill.Name) { Fail "$rel/SKILL.md name '$skillName' must equal the folder name" }
        if ($skillName -notmatch $nameRegex -or $skillName.Length -gt 64) { Fail "${rel}: name '$skillName' must be lowercase-hyphen, at most 64 characters" }
        if ($skillName -notmatch '(^|-)(storm|galaxy|hots)(-|$)') { Fail "${rel}: name '$skillName' must contain storm-, galaxy- or hots- (avoid clashing with other skills)" }
        if ($allSkillNames.ContainsKey($skillName)) { Fail "${rel}: skill name '$skillName' is also used by $($allSkillNames[$skillName])" }
        $allSkillNames[$skillName] = $rel
        $description = [string]$fm['description']
        if ($description.Length -lt 10 -or $description.Length -gt 1024) { Fail "${rel}: description is $($description.Length) characters (10 to 1024)" }
        if ($description -match '[<>]') { Fail "${rel}: description contains < or >" }
        $descriptionTotal += $description.Length
        if ($fm.Contains('compatibility') -and ([string]$fm['compatibility']).Length -gt 500) { Fail "${rel}: compatibility over 500 characters" }

        $lineCount = (Get-Content -LiteralPath $skillMd).Count
        if ($lineCount -ge 500) { Fail "$rel/SKILL.md has $lineCount lines (keep it under 500)" }

        $text = Get-Content -LiteralPath $skillMd -Raw
        foreach ($m in [regex]::Matches($text, '\]\(([^)\s]+)\)')) {
            $target = $m.Groups[1].Value
            if ($target -match '^(https?:|mailto:|#)') { continue }
            $path = $target.Split('#')[0]
            if ($path.StartsWith('/') -or $path -match '(^|/)\.\.(/|$)') { Fail "$rel/SKILL.md links '$target': use a relative path without .."; continue }
            if (($path.Split('/') | Where-Object { $_ }).Count -gt 2) { Fail "$rel/SKILL.md links '$target': at most one folder deep"; continue }
            if (-not (Test-Path -LiteralPath (Join-Path $skill.FullName $path))) { Fail "$rel/SKILL.md links '$target', which does not exist" }
        }
    }

    # 8. Version bump
    if ($BaseRef) {
        $changed = git -C $root diff --name-only "$BaseRef...HEAD" -- "plugins/$name/" 2>$null
        if ($LASTEXITCODE -eq 0 -and $changed) {
            $old = git -C $root show "${BaseRef}:plugins/$name/plugin.json" 2>$null
            if ($LASTEXITCODE -eq 0 -and $old) {
                $oldVersion = ($old -join "`n" | ConvertFrom-Json).version
                if ($oldVersion -eq $agent.version) { Fail "plugins/$name changed since $BaseRef but its version is still $oldVersion (bump plugin.json and .claude-plugin/plugin.json)" }
            }
        }
    }
}

if ($descriptionTotal -gt 6000) { Fail "skill descriptions total $descriptionTotal characters (keep all of them under 6000)" }

# 7. Bytes
foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File -Force | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' }) {
    $rel = $file.FullName.Substring($root.Length + 1).Replace('\', '/')
    if ($rel.StartsWith('plugins/')) {
        if ($file.Length -gt 5MB) { Fail "$rel is over 5 MB" }
        if ($file.LinkType) { Fail "$rel is a link" }
        if ($file.Name -eq 'CLAUDE.md') { Fail "${rel}: no CLAUDE.md in plugins" }
    }
    if ($file.Extension -in '.md', '.json') {
        $head = [byte[]]::new(3)
        $stream = [System.IO.File]::OpenRead($file.FullName)
        try { [void]$stream.Read($head, 0, 3) } finally { $stream.Dispose() }
        if ($head[0] -eq 0xEF -and $head[1] -eq 0xBB -and $head[2] -eq 0xBF) { Fail "$rel starts with a UTF-8 BOM" }
    }
}
foreach ($dir in Get-ChildItem -LiteralPath (Join-Path $root 'plugins') -Recurse -Directory -Force) {
    if ($dir.LinkType) { Fail "$($dir.FullName.Substring($root.Length + 1)) is a link" }
    if ($dir.Name -eq 'bin' -and $dir.Parent.Parent.Name -eq 'plugins') { Fail "plugins/$($dir.Parent.Name) has a bin/ folder (claude.ai refuses such plugins)" }
}

Write-Output ("{0} plugins, {1} skills, descriptions {2} characters" -f $marketplace.plugins.Count, $allSkillNames.Count, $descriptionTotal)
if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Output "FAIL $_" }
    exit 1
}
Write-Output 'OK'
