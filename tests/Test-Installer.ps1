param([string]$PackageRoot)
$ErrorActionPreference = 'Stop'
$fixture = Join-Path $PSScriptRoot ('results\installer-' + [guid]::NewGuid().ToString('N'))
$bin = Join-Path $fixture 'DS\Binaries\Win64'
New-Item -ItemType Directory -Path $bin -Force | Out-Null
Set-Content -LiteralPath (Join-Path $bin 'DSClient-Win64-Shipping.exe') -Value 'test fixture'
Set-Content -LiteralPath (Join-Path $bin 'unrelated.txt') -Value 'preserve me'
$script = Join-Path $PackageRoot 'Manage-Mod.ps1'
& $script -Action Install -GameRoot $fixture
if (-not (Test-Path -LiteralPath (Join-Path $bin 'dwmapi.dll'))) { throw 'Install failed.' }
# A locally edited tracked file must block removal before any files are moved.
$lua = Join-Path $bin 'ue4ss\Mods\DragonSwordCameraNoDelay\Scripts\main.lua'
$original = [IO.File]::ReadAllBytes($lua)
Add-Content -LiteralPath $lua -Value '-- external edit'
$rejected=$false
try { & $script -Action Remove -GameRoot $fixture } catch { $rejected=$true }
if (-not $rejected -or -not (Test-Path -LiteralPath (Join-Path $bin 'dwmapi.dll'))) { throw 'Changed-file protection failed.' }
[IO.File]::WriteAllBytes($lua,$original)
& $script -Action Remove -GameRoot $fixture
if (Test-Path -LiteralPath (Join-Path $bin 'dwmapi.dll')) { throw 'Remove failed.' }
if ((Get-Content -LiteralPath (Join-Path $bin 'unrelated.txt')).Trim() -ne 'preserve me') { throw 'Unrelated file changed.' }
& $script -Action Install -GameRoot $fixture
& $script -Action Remove -GameRoot $fixture
Write-Output 'installer: install, backup removal, reinstall, changed-file protection, unrelated preservation PASS'
