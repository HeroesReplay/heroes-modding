<#
.SYNOPSIS
    Prints the Galaxy native functions of the installed game build as declarations, from the
    trigger editor's library file. Read-only.

.DESCRIPTION
    Heroes of the Storm's TriggerLibs/natives.galaxy holds only constants: the native declarations
    are not shipped as script. The editor's library definition, NativeLib.TriggerLib (XML, about
    6.5 MB, in mods/core.stormmod/base.stormdata/TriggerLibs/), lists every function. Elements with
    <FlagNative/> are engine natives; this script prints each as

        native unitgroup UnitCreate(int count, string type, int flags, int player, point pos, fixed angle, unit creator);

    The library describes functions as the trigger editor sees them, so this script converts them
    to script form: event functions (TriggerAddEvent*) get their leading trigger argument back;
    editor-only types become their script type (game links, catalog entries and field paths,
    layout frames, user data instances and actor messages are string; dialogs, dialog controls,
    objectives, pings and portraits are int ids); presets print as their base type (int when the
    preset does not say). Other editor types print unchanged. Extract the file first with the
    hots-casc-game-files skill. Keep the output local: it is generated from Blizzard's files.

    The library lists the natives the trigger editor exposes (about 1,860 on 2.57). A few
    script-only natives that Blizzard's own libraries call are not in it (TriggerCreate,
    UnitFilter, UnitCreateEffectUnit, UnitCreateEffectPoint, PlayerGroupNextPlayer, UnitRefFromUnit,
    DoodadFromId, TriggerQueueEnter). Search heroesdata.stormmod/base.stormdata/TriggerLibs/*.galaxy
    for a real call when a name is missing here.

.PARAMETER TriggerLib
    Path to NativeLib.TriggerLib (or any *.TriggerLib).

.PARAMETER Name
    Only natives whose name matches this regex.

.PARAMETER All
    Also print non-native library functions (the libNtve_gf_ GUI helpers), marked "// library".

.EXAMPLE
    pwsh -NoProfile -File Get-GalaxyNatives.ps1 .\casc\mods\core.stormmod\base.stormdata\TriggerLibs\NativeLib.TriggerLib -Name '^Bank'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $TriggerLib,
    [string] $Name,
    [switch] $All
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$settings = [System.Xml.XmlReaderSettings]::new()
$settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
$settings.XmlResolver = $null
$reader = [System.Xml.XmlReader]::Create((Resolve-Path -LiteralPath $TriggerLib).ProviderPath, $settings)
$xml = [System.Xml.XmlDocument]::new()
try { $xml.Load($reader) } finally { $reader.Dispose() }

# Elements are referenced by (Type, Id).
$elements = @{}
foreach ($element in $xml.SelectNodes('/TriggerData/Element')) {
    $elements["$($element.GetAttribute('Type'))/$($element.GetAttribute('Id'))"] = $element
}

# Editor-only parameter types and what the script sees.
$scriptTypes = @{
    gamelink = 'string'; catalogentry = 'string'; catalogfieldpath = 'string'; catalogfieldname = 'string'
    reference = 'string'; userinstance = 'string'; userfield = 'string'; layoutframe = 'string'
    layoutframerel = 'string'; actormsg = 'string'; filepath = 'string'; modelanim = 'string'
    fontstyle = 'string'; cooldown = 'string'; charge = 'string'
    dialog = 'int'; control = 'int'; objective = 'int'; ping = 'int'; portrait = 'int'
}

function Get-TypeName([System.Xml.XmlNode] $TypeHolder) {
    if (-not $TypeHolder) { return 'void' }
    $type = $TypeHolder.SelectSingleNode('Type')
    if (-not $type) { return 'void' }
    $value = $type.GetAttribute('Value')
    if ($scriptTypes.ContainsKey($value)) { return $scriptTypes[$value] }
    switch ($value) {
        'preset' {
            $ref = $TypeHolder.SelectSingleNode('TypeElement')
            if ($ref) {
                $preset = $elements["Preset/$($ref.GetAttribute('Id'))"]
                $base = if ($preset) { $preset.SelectSingleNode('BaseType') } else { $null }
                if ($base) { return $base.GetAttribute('Value') }
            }
            return 'int'
        }
        default { return $value }
    }
}

$count = 0
foreach ($function in $xml.SelectNodes('/TriggerData/Element[@Type="FunctionDef"]')) {
    $identifier = $function.SelectSingleNode('Identifier')
    if (-not $identifier) { continue }
    $native = [bool]$function.SelectSingleNode('FlagNative')
    if (-not $native -and -not $All) { continue }
    $fname = $identifier.InnerText
    if ($Name -and $fname -notmatch $Name) { continue }

    $parameters = foreach ($p in $function.SelectNodes('Parameter')) {
        $def = $elements["ParamDef/$($p.GetAttribute('Id'))"]
        if (-not $def) { continue }
        $pname = $def.SelectSingleNode('Identifier')
        '{0} {1}' -f (Get-TypeName $def.SelectSingleNode('ParameterType')), ($pname ? $pname.InnerText : 'arg')
    }
    if ($function.SelectSingleNode('FlagEvent')) {
        $parameters = @('trigger trig') + @($parameters)
    }
    $ret = Get-TypeName $function.SelectSingleNode('ReturnType')
    $prefix = $native ? 'native ' : ''
    $suffix = $native ? '' : '    // library'
    '{0}{1} {2}({3});{4}' -f $prefix, $ret, $fname, ($parameters -join ', '), $suffix
    $count++
}
Write-Verbose "$count functions"
