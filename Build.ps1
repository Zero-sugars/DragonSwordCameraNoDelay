$ErrorActionPreference = 'Stop'
$release = Join-Path $PSScriptRoot 'release\DragonSwordCameraNoDelay-v0.1.0'
if (Test-Path -LiteralPath $release) { throw 'Release folder already exists. Inspect it before rebuilding.' }
$bin = Join-Path $release 'DS\Binaries\Win64'
$loader = Join-Path $bin 'ue4ss'
$scripts = Join-Path $loader 'Mods\DragonSwordCameraNoDelay\Scripts'
New-Item -ItemType Directory -Path $scripts -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'vendor\UE4SS\dwmapi.dll') -Destination $bin
foreach ($file in @('UE4SS.dll','UE4SS-settings.ini','LICENSE')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "vendor\UE4SS\ue4ss\$file") -Destination $loader
}
foreach ($file in @('main.lua','camera_patch.lua')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "mod\Scripts\$file") -Destination $scripts
}
[IO.File]::WriteAllText((Join-Path $loader 'Mods\mods.txt'), "DragonSwordCameraNoDelay : 1`n", [Text.UTF8Encoding]::new($false))
foreach ($file in @('README.txt','Manage-Mod.ps1','Install.cmd','Remove.cmd')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $release
}
$entries = @(Get-ChildItem -LiteralPath $bin -Recurse -File | ForEach-Object {
    @{path=[IO.Path]::GetRelativePath($bin,$_.FullName);sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
})
@{version='0.1.0';files=$entries} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $release 'install-manifest.json') -Encoding utf8
New-Item -ItemType Directory -Path (Join-Path $PSScriptRoot 'dist') -Force | Out-Null
$zip = Join-Path $PSScriptRoot 'dist\DragonSwordCameraNoDelay-v0.1.0.zip'
Compress-Archive -LiteralPath $release -DestinationPath $zip -CompressionLevel Optimal
Get-Item -LiteralPath $zip | Select-Object FullName,Length
Get-FileHash -LiteralPath $zip -Algorithm SHA256
