param([string]$SetupExe = (Join-Path $PSScriptRoot '..\dist\DragonSword.CameraNoDelay.Setup.exe'))
$ErrorActionPreference = 'Stop'
$fixture = Join-Path $PSScriptRoot ('results\ui-' + [guid]::NewGuid().ToString('N'))
$bin = Join-Path $fixture 'DS\Binaries\Win64'
New-Item -ItemType Directory -Path $bin -Force | Out-Null
Set-Content -LiteralPath (Join-Path $bin 'DSClient-Win64-Shipping.exe') -Value 'UI test fixture'
$images = Join-Path $fixture 'images'
$start = [Diagnostics.ProcessStartInfo]::new((Resolve-Path -LiteralPath $SetupExe).Path)
$start.UseShellExecute = $false
$start.RedirectStandardOutput = $true
$start.RedirectStandardError = $true
foreach ($argument in @('--ui-test','--game-root',$fixture,'--image-folder',$images)) { $start.ArgumentList.Add($argument) }
$process = [Diagnostics.Process]::Start($start)
$output = $process.StandardOutput.ReadToEndAsync()
$errorOutput = $process.StandardError.ReadToEndAsync()
$process.WaitForExit()
Write-Output $output.Result
if ($process.ExitCode -ne 0) { throw $errorOutput.Result }
Write-Output "Rendered UI images: $images"
