<#
.SYNOPSIS
    Installs or removes loose Heroes of the Storm map and mod folders in the game folder, keeping a
    backup of anything it replaces and a manifest so uninstall restores the game exactly.

.DESCRIPTION
    Source is a folder laid out like the game folder (what New-HotsMod.ps1 writes, or a Heroes Rogue
    style release): maps\...\<name>.stormmap\ and mods\<name>.StormMod\. Each document folder found
    there is copied (or, with -Link, junctioned for a live edit loop) to the same relative path under
    the game folder. A folder already at that path is moved to <game>\.hots-mods\backup\<time>\
    first. The manifest <game>\.hots-mods\manifest.json lists what was installed and what was backed
    up. -Uninstall removes only what the manifest lists and puts the backups back.

    The game reads these folders on the next map load; restart the client after the first install.
    Battle.net never removes them, so uninstall before you play normally again.

.PARAMETER Source
    Folder holding maps\ and/or mods\.

.PARAMETER GamePath
    The Heroes of the Storm folder (holding .build.info and HeroesData). Default: the uninstall
    registry entry, then C:\Program Files (x86)\Heroes of the Storm.

.PARAMETER Link
    Create directory junctions to Source instead of copying (no admin rights needed).

.PARAMETER Uninstall
    Remove what the manifest lists and restore backups.

.EXAMPLE
    pwsh -File Install-HotsMod.ps1 -Source C:\src\roguelite -Link -WhatIf

.EXAMPLE
    pwsh -File Install-HotsMod.ps1 -Uninstall
#>
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Install')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Install')][string] $Source,
    [string] $GamePath,
    [Parameter(ParameterSetName = 'Install')][switch] $Link,
    [Parameter(Mandatory, ParameterSetName = 'Uninstall')][switch] $Uninstall
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Find-GamePath {
    $keys = @(
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Heroes of the Storm',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Heroes of the Storm'
    )
    foreach ($key in $keys) {
        $value = Get-ItemProperty -Path $key -Name InstallLocation -ErrorAction SilentlyContinue
        if ($value -and $value.InstallLocation -and (Test-Path -LiteralPath $value.InstallLocation)) {
            return $value.InstallLocation
        }
    }
    'C:\Program Files (x86)\Heroes of the Storm'
}

if (-not $GamePath) { $GamePath = Find-GamePath }
$game = [System.IO.Path]::GetFullPath($GamePath)
if (-not (Test-Path -LiteralPath (Join-Path $game '.build.info')) -or -not (Test-Path -LiteralPath (Join-Path $game 'HeroesData'))) {
    throw "$game does not look like a Heroes of the Storm folder (no .build.info or HeroesData)"
}
if (Get-Process -Name 'HeroesOfTheStorm_x64' -ErrorAction SilentlyContinue) {
    Write-Warning 'Heroes of the Storm is running: changes apply on the next map load, and a file in use may fail to copy.'
}

$state = Join-Path $game '.hots-mods'
$manifestPath = Join-Path $state 'manifest.json'

function Read-Manifest {
    if (Test-Path -LiteralPath $manifestPath) {
        $m = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        return @{ installed = @($m.installed) }
    }
    @{ installed = @() }
}

function Save-Manifest([hashtable] $Manifest) {
    New-Item -ItemType Directory -Force -Path $state | Out-Null
    [pscustomobject]@{ installed = @($Manifest.installed) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding utf8
}

function Remove-Installed([string] $Path) {
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.LinkType -eq 'Junction' -or $item.LinkType -eq 'SymbolicLink') {
        # Remove the link only, never the target's contents.
        $item.Delete()
    }
    else {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

function Remove-EmptyParents([string] $Path) {
    $dir = Split-Path $Path -Parent
    while ($dir -and $dir.Length -gt $game.Length -and (Test-Path -LiteralPath $dir) -and -not (Get-ChildItem -LiteralPath $dir -Force)) {
        Remove-Item -LiteralPath $dir -Force
        $dir = Split-Path $dir -Parent
    }
}

$manifest = Read-Manifest

if ($Uninstall) {
    if ($manifest.installed.Count -eq 0) {
        Write-Output "nothing installed (no $manifestPath)"
        return
    }
    $kept = @()
    foreach ($entry in $manifest.installed) {
        $target = Join-Path $game $entry.path
        if (-not $PSCmdlet.ShouldProcess($target, 'remove and restore backup')) {
            $kept += $entry
            continue
        }
        if (Test-Path -LiteralPath $target) { Remove-Installed $target }
        if ($entry.backup) {
            Move-Item -LiteralPath (Join-Path $state $entry.backup) -Destination $target
            Write-Output "restored $($entry.path)"
        }
        else {
            Remove-EmptyParents $target
            Write-Output "removed  $($entry.path)"
        }
    }
    $manifest.installed = $kept
    if ($kept.Count -eq 0 -and -not $WhatIfPreference) {
        Remove-Item -LiteralPath $state -Recurse -Force
    }
    elseif (-not $WhatIfPreference) {
        Save-Manifest $manifest
    }
    return
}

$src = (Resolve-Path -LiteralPath $Source).ProviderPath
$documents = @(Get-ChildItem -LiteralPath $src -Directory -Recurse | Where-Object {
        $_.Name -match '\.(stormmap|stormmod)$' -and
        ($_.FullName.Substring($src.Length).TrimStart('\') -match '^(maps|mods)\\') -and
        -not ($_.Parent.FullName -match '\.(stormmap|stormmod)$')
    })
if ($documents.Count -eq 0) {
    throw "no maps\...\*.stormmap or mods\*.StormMod folders under $src"
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
foreach ($doc in $documents) {
    $relative = $doc.FullName.Substring($src.Length).TrimStart('\')
    $target = Join-Path $game $relative
    $existing = $manifest.installed | Where-Object { $_.path -eq $relative } | Select-Object -First 1
    $action = if ($Link) { "junction to $($doc.FullName)" } else { "copy from $($doc.FullName)" }
    if (-not $PSCmdlet.ShouldProcess($target, $action)) { continue }

    $backup = $null
    if ($existing) {
        # Ours from an earlier install: replace it, keep the original backup.
        Remove-Installed $target
        $backup = $existing.backup
        $manifest.installed = @($manifest.installed | Where-Object { $_.path -ne $relative })
    }
    elseif (Test-Path -LiteralPath $target) {
        $backup = "backup\$stamp\$relative"
        $backupFull = Join-Path $state $backup
        New-Item -ItemType Directory -Force -Path (Split-Path $backupFull -Parent) | Out-Null
        Move-Item -LiteralPath $target -Destination $backupFull
        Write-Output "backed up $relative"
    }

    try {
        New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
        if ($Link) {
            New-Item -ItemType Junction -Path $target -Target $doc.FullName | Out-Null
        }
        else {
            Copy-Item -LiteralPath $doc.FullName -Destination $target -Recurse
        }
    }
    catch [System.UnauthorizedAccessException] {
        throw "Access denied writing $target. The game folder is under Program Files: run this from an elevated pwsh. ($($_.Exception.Message))"
    }
    $manifest.installed = @($manifest.installed) + [pscustomobject]@{ path = $relative; backup = $backup; link = [bool]$Link; source = $doc.FullName; at = $stamp }
    Write-Output ("installed {0}{1}" -f $relative, $(if ($Link) { ' (junction)' } else { '' }))
}

if (-not $WhatIfPreference) { Save-Manifest $manifest }
Write-Output "manifest: $manifestPath"
