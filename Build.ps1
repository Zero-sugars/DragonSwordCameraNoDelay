[CmdletBinding()]
param([switch]$PayloadOnly)
$ErrorActionPreference = 'Stop'
$backendPath = Join-Path $PSScriptRoot 'Manage-Mod.ps1'
$backendTokens = $null
$backendErrors = $null
[Management.Automation.Language.Parser]::ParseFile($backendPath, [ref]$backendTokens, [ref]$backendErrors) | Out-Null
if ($backendErrors.Count -gt 0) { throw ('Installer script syntax error: ' + ($backendErrors.Message -join '; ')) }
$version = '0.3.0'
$release = Join-Path $PSScriptRoot "release\DragonSwordCameraNoDelay-v$version"
if (-not $PayloadOnly -and (Test-Path -LiteralPath $release)) { throw 'Release folder already exists. Inspect it before rebuilding.' }
$project = Join-Path $PSScriptRoot 'src\Setup\DragonSword.CameraNoDelay.Setup.csproj'
dotnet restore $project -r win-x64
if ($LASTEXITCODE -ne 0) { throw 'Installer dependency restore failed.' }
$payload = Join-Path $PSScriptRoot "staging\manager-payload-v$version"
$bin = Join-Path $payload 'DS\Binaries\Win64'
$loader = Join-Path $bin 'ue4ss'
$scripts = Join-Path $loader 'Mods\DragonSwordCameraNoDelay\Scripts'
New-Item -ItemType Directory -Path $scripts -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'vendor\UE4SS\dwmapi.dll') -Destination $bin
foreach ($file in @('UE4SS.dll','UE4SS-settings.ini','LICENSE')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "vendor\UE4SS\ue4ss\$file") -Destination $loader
}
foreach ($file in @('main.lua','camera_patch.lua','menu_keyboard.lua','menu_navigation.lua')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "mod\Scripts\$file") -Destination $scripts
}
[IO.File]::WriteAllText((Join-Path $loader 'Mods\mods.txt'), "DragonSwordCameraNoDelay : 1`n", [Text.UTF8Encoding]::new($false))
$backendScript = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Manage-Mod.ps1') -Raw -Encoding UTF8
[IO.File]::WriteAllText((Join-Path $payload 'Manage-Mod.ps1'), $backendScript, [Text.UTF8Encoding]::new($true))
$entries = @(Get-ChildItem -LiteralPath $bin -Recurse -File | ForEach-Object {
    @{path=[IO.Path]::GetRelativePath($bin,$_.FullName);sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
})
@{version=$version;files=$entries} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $payload 'install-manifest.json') -Encoding utf8
$assets = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'src\Setup\obj\project.assets.json') -Raw | ConvertFrom-Json
$dependencies = @($assets.project.frameworks.PSObject.Properties | ForEach-Object { $_.Value.downloadDependencies })
foreach ($component in @('Microsoft.NETCore.App.Runtime.win-x64','Microsoft.WindowsDesktop.App.Runtime.win-x64')) {
    $dependency = $dependencies | Where-Object name -eq $component | Select-Object -First 1
    if (-not $dependency) { throw "Runtime package metadata missing: $component" }
    $runtimeVersion = [regex]::Match($dependency.version, '\d+\.\d+\.\d+').Value
    $componentRoot = $null
    foreach ($packageFolder in $assets.packageFolders.PSObject.Properties.Name) {
        $candidate = Join-Path $packageFolder ($component.ToLowerInvariant() + '\' + $runtimeVersion)
        if (Test-Path -LiteralPath $candidate) { $componentRoot=$candidate; break }
    }
    if (-not $componentRoot) { throw "Runtime license folder missing: $component $runtimeVersion" }
    $noticeFolder = Join-Path $payload "licenses\$component"
    New-Item -ItemType Directory -Path $noticeFolder -Force | Out-Null
    foreach ($notice in @('LICENSE','LICENSE.TXT','THIRD-PARTY-NOTICES.TXT')) {
        $source = Join-Path $componentRoot $notice
        if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination $noticeFolder -Force }
    }
}
$payloadZip = Join-Path $PSScriptRoot "staging\manager-payload-v$version.zip"
Compress-Archive -Path (Join-Path $payload '*') -DestinationPath $payloadZip -CompressionLevel Optimal -Force
if ($PayloadOnly) { Write-Output "Payload ready: $payload"; return }
$publish = Join-Path $PSScriptRoot "staging\publish-v$version"
dotnet publish $project -c Release -r win-x64 --self-contained true --no-restore -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true -p:DebugType=None -o $publish
if ($LASTEXITCODE -ne 0) { throw 'Installer publish failed.' }
New-Item -ItemType Directory -Path $release -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $publish 'DragonSword.CameraNoDelay.Setup.exe') -Destination $release
Copy-Item -LiteralPath (Join-Path $payload 'licenses') -Destination (Join-Path $release 'licenses') -Recurse
New-Item -ItemType Directory -Path (Join-Path $release 'licenses\UE4SS') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'third-party\UE4SS-LICENSE.txt') -Destination (Join-Path $release 'licenses\UE4SS\LICENSE.txt')
foreach ($file in @('README.txt','THIRD-PARTY-NOTICES.md')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $release }
New-Item -ItemType Directory -Path (Join-Path $PSScriptRoot 'dist') -Force | Out-Null
$zip = Join-Path $PSScriptRoot "dist\DragonSwordCameraNoDelay-v$version-win-x64.zip"
Compress-Archive -LiteralPath $release -DestinationPath $zip -CompressionLevel Optimal
$manual = Join-Path $PSScriptRoot "staging\manual-v$version"
$manualScripts = Join-Path $manual 'DragonSwordCameraNoDelay\Scripts'
New-Item -ItemType Directory -Path $manualScripts -Force | Out-Null
Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'mod\Scripts') -Filter '*.lua' -File | Copy-Item -Destination $manualScripts
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'docs\MANUAL-INSTALL.md') -Destination $manual
$manualZip = Join-Path $PSScriptRoot "dist\DragonSwordCameraNoDelay-v$version-mod-only.zip"
Compress-Archive -Path (Join-Path $manual '*') -DestinationPath $manualZip -CompressionLevel Optimal
Copy-Item -LiteralPath (Join-Path $release 'DragonSword.CameraNoDelay.Setup.exe') -Destination (Join-Path $PSScriptRoot 'dist\DragonSword.CameraNoDelay.Setup.exe') -Force
$checksumLines = @('DragonSword.CameraNoDelay.Setup.exe', "DragonSwordCameraNoDelay-v$version-win-x64.zip", "DragonSwordCameraNoDelay-v$version-mod-only.zip") | ForEach-Object {
    $hash = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot "dist\$_") -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $_"
}
[IO.File]::WriteAllLines((Join-Path $PSScriptRoot "dist\SHA256SUMS-v$version.txt"), $checksumLines, [Text.UTF8Encoding]::new($false))
Get-Item -LiteralPath $zip | Select-Object FullName,Length
Get-FileHash -LiteralPath $zip -Algorithm SHA256
