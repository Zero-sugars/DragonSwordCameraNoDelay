[CmdletBinding()]
param(
    [ValidateSet('Install','Remove','Status')][string]$Action = 'Install',
    [string]$GameRoot
)
$ErrorActionPreference = 'Stop'

function Find-GameRoot {
    $steamRoots = @()
    foreach ($key in @('HKCU:\Software\Valve\Steam','HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')) {
        $item = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
        if ($item.SteamPath) { $steamRoots += $item.SteamPath }
        if ($item.InstallPath) { $steamRoots += $item.InstallPath }
    }
    $libraries = @($steamRoots)
    foreach ($steamRoot in $steamRoots) {
        $vdf = Join-Path $steamRoot 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            foreach ($match in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')) {
                $libraries += $match.Groups[1].Value.Replace('\\','\')
            }
        }
    }
    foreach ($drive in Get-PSDrive -PSProvider FileSystem) { $libraries += Join-Path $drive.Root 'SteamLibrary' }
    foreach ($library in $libraries | Select-Object -Unique) {
        $manifest = Join-Path $library 'steamapps\appmanifest_4570720.acf'
        if (Test-Path -LiteralPath $manifest) {
            $match = [regex]::Match((Get-Content -LiteralPath $manifest -Raw), '"installdir"\s+"([^"]+)"')
            if ($match.Success) { return Join-Path $library ('steamapps\common\' + $match.Groups[1].Value) }
        }
    }
    throw 'DragonSword was not found. Specify -GameRoot with the folder containing DSClient.exe.'
}

if (-not $GameRoot) { $GameRoot = Find-GameRoot }
$GameRoot = (Resolve-Path -LiteralPath $GameRoot).Path
$gameBin = Join-Path $GameRoot 'DS\Binaries\Win64'
if (-not (Test-Path -LiteralPath (Join-Path $gameBin 'DSClient-Win64-Shipping.exe'))) { throw 'Invalid DragonSword game folder.' }
$recordPath = Join-Path $gameBin 'CameraNoDelay-install-manifest.json'
$payloadRoot = Join-Path $PSScriptRoot 'DS\Binaries\Win64'
$packageManifest = Join-Path $PSScriptRoot 'install-manifest.json'

function Resolve-Child([string]$root, [string]$relative) {
    $prefix = [IO.Path]::GetFullPath($root).TrimEnd('\') + '\'
    $full = [IO.Path]::GetFullPath((Join-Path $root $relative))
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe path in manifest.' }
    return $full
}

if ($Action -eq 'Status') {
    if (Test-Path -LiteralPath $recordPath) { Write-Output "Installed: $GameRoot" } else { Write-Output "Not installed: $GameRoot" }
    return
}
if (Get-Process -Name 'DSClient-Win64-Shipping','DSClient' -ErrorAction SilentlyContinue) { throw 'Close DragonSword before installing or removing the mod.' }

$oldRecord = $null
if (Test-Path -LiteralPath $recordPath) {
    $oldRecord = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
    foreach ($entry in $oldRecord.files) {
        $target = Resolve-Child $gameBin $entry.path
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "Installed file is missing: $target" }
        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $entry.sha256) { throw "File changed outside this installer: $target" }
    }
}

if ($Action -eq 'Remove') {
    if (-not $oldRecord) { throw 'No install record was found. No files were changed.' }
    $backup = Join-Path $gameBin ('CameraNoDelay-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
    foreach ($entry in $oldRecord.files) {
        $target = Resolve-Child $gameBin $entry.path
        $destination = Resolve-Child $backup $entry.path
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Move-Item -LiteralPath $target -Destination $destination
    }
    Move-Item -LiteralPath $recordPath -Destination (Join-Path $backup 'install-manifest.json')
    Write-Output "Removed. Files preserved at: $backup"
    return
}

if (-not (Test-Path -LiteralPath $packageManifest)) { throw 'Extract the complete release ZIP before running Install.' }
$newRecord = Get-Content -LiteralPath $packageManifest -Raw | ConvertFrom-Json
$owned = @{}
if ($oldRecord) { foreach ($entry in $oldRecord.files) { $owned[$entry.path] = $true } }
foreach ($entry in $newRecord.files) {
    $source = Resolve-Child $payloadRoot $entry.path
    $target = Resolve-Child $gameBin $entry.path
    if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $entry.sha256) { throw "Package hash mismatch: $source" }
    if ((Test-Path -LiteralPath $target) -and -not $owned.ContainsKey($entry.path)) { throw "Existing file would be overwritten: $target" }
}
if (-not $oldRecord) {
    foreach ($loader in @('UE4SS.dll','UE4SS-settings.ini','xinput1_3.dll','ue4ss\UE4SS.dll','ue4ss\UE4SS-settings.ini','ue4ss\Mods\mods.txt')) {
        if (Test-Path -LiteralPath (Join-Path $gameBin $loader)) { throw "Existing mod loader found: $loader. Install the Lua mod manually as described in README.txt." }
    }
}
foreach ($entry in $newRecord.files) {
    $source = Resolve-Child $payloadRoot $entry.path
    $target = Resolve-Child $gameBin $entry.path
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $target -Force
}
Copy-Item -LiteralPath $packageManifest -Destination $recordPath -Force
Write-Output "Installed: $GameRoot"
Write-Output 'Launch from Steam. F8 toggles the mod; F9 writes camera status to ue4ss\UE4SS.log.'
