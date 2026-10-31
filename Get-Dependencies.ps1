[CmdletBinding()]
param([string]$ReleaseArchive)
$ErrorActionPreference = 'Stop'
$downloadRoot = Join-Path $PSScriptRoot 'tools\downloads'
$vendor = Join-Path $PSScriptRoot 'vendor\UE4SS'
New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null

function Assert-Hash([string]$path, [string]$expected) {
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $expected) { throw "SHA256 mismatch: $path" }
}

if (-not $ReleaseArchive) {
    $upstream = Join-Path $downloadRoot 'UE4SS_v3.0.1-1188-gf885e8d2.zip'
    try {
        Invoke-WebRequest -Uri 'https://github.com/UE4SS-RE/RE-UE4SS/releases/download/experimental-latest/UE4SS_v3.0.1-1188-gf885e8d2.zip' -OutFile $upstream
    } catch {
        Write-Output 'Pinned upstream asset unavailable; using the verified v0.1.0 release archive.'
        $ReleaseArchive = Join-Path $downloadRoot 'DragonSwordCameraNoDelay-v0.1.0.zip'
        Invoke-WebRequest -Uri 'https://github.com/pwj891129-arch/DragonSwordCameraNoDelay/releases/download/v0.1.0/DragonSwordCameraNoDelay-v0.1.0.zip' -OutFile $ReleaseArchive
    }
    if (-not $ReleaseArchive) {
        Assert-Hash $upstream '4a594fb5c6e1aa794b06a770730e072c53fb92b741f95a5f0601080d80f4a6c1'
        Expand-Archive -LiteralPath $upstream -DestinationPath $vendor -Force
        Write-Output 'Verified official UE4SS dependency is ready.'
        return
    }
}

Assert-Hash $ReleaseArchive '29a503dccf4e2f6d35e5beaaf8539ce061dcde6f5f1b231037d57be075b45dc5'
$extract = Join-Path $downloadRoot 'verified-release'
Expand-Archive -LiteralPath $ReleaseArchive -DestinationPath $extract -Force
$payload = Join-Path $extract 'DragonSwordCameraNoDelay-v0.1.0\DS\Binaries\Win64'
New-Item -ItemType Directory -Path (Join-Path $vendor 'ue4ss') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $payload 'dwmapi.dll') -Destination $vendor -Force
foreach ($file in @('UE4SS.dll','UE4SS-settings.ini','LICENSE')) {
    Copy-Item -LiteralPath (Join-Path $payload "ue4ss\$file") -Destination (Join-Path $vendor 'ue4ss') -Force
}
Write-Output 'Verified UE4SS dependency extracted from the v0.1.0 release.'
