param([string]$SetupExe = (Join-Path $PSScriptRoot '..\dist\DragonSword.CameraNoDelay.Setup.exe'))
$ErrorActionPreference = 'Stop'
$fixtureRoot = Join-Path $PSScriptRoot 'results'
if ($env:DS_TEST_FIXTURE_ROOT) { $fixtureRoot=$env:DS_TEST_FIXTURE_ROOT }
$fixture = Join-Path $fixtureRoot ('ui-' + [guid]::NewGuid().ToString('N').Substring(0,8))
$bin = Join-Path $fixture 'DS\Binaries\Win64'
New-Item -ItemType Directory -Path $bin -Force | Out-Null
Set-Content -LiteralPath (Join-Path $bin 'DSClient-Win64-Shipping.exe') -Value 'UI test fixture'
$images = Join-Path $fixture 'images'
$start = [Diagnostics.ProcessStartInfo]::new((Resolve-Path -LiteralPath $SetupExe).Path)
$start.UseShellExecute = $false
$start.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
$start.RedirectStandardOutput = $true
$start.RedirectStandardError = $true
foreach ($argument in @('--ui-test','--game-root',$fixture,'--image-folder',$images)) { $start.ArgumentList.Add($argument) }
$process = [Diagnostics.Process]::Start($start)
$output = $process.StandardOutput.ReadToEndAsync()
$errorOutput = $process.StandardError.ReadToEndAsync()
$process.WaitForExit()
Write-Output $output.Result
if ($process.ExitCode -ne 0) { throw $errorOutput.Result }
if ($output.Result -notmatch 'UI: .* PASS') { throw 'UI test did not run. Close any other installer test instance and retry.' }
foreach ($image in @('menu-only.png','camera-only.png','installed.png','removed.png')) {
    if (-not (Test-Path -LiteralPath (Join-Path $images $image) -PathType Leaf)) { throw "UI test render is missing: $image" }
}
Write-Output "Rendered UI images: $images"
