[CmdletBinding()]
param(
    [ValidateSet('Install','Remove','Status','Discover')][string]$Action = 'Install',
    [string]$GameRoot,
    [switch]$AsJson
)
$ErrorActionPreference = 'Stop'
Import-Module Microsoft.PowerShell.Utility -ErrorAction Stop
$legacyPaths = @('dwmapi.dll','ue4ss\LICENSE','ue4ss\UE4SS-settings.ini','ue4ss\UE4SS.dll','ue4ss\Mods\mods.txt',
    'ue4ss\Mods\DragonSwordCameraNoDelay\Scripts\camera_patch.lua','ue4ss\Mods\DragonSwordCameraNoDelay\Scripts\main.lua')
$allowedPaths = $legacyPaths + @('ue4ss\Mods\DragonSwordCameraNoDelay\Scripts\menu_keyboard.lua','ue4ss\Mods\DragonSwordCameraNoDelay\Scripts\menu_navigation.lua')

function Complete-Result($result, [string]$message) {
    if ($AsJson) { $result | ConvertTo-Json -Depth 6 -Compress } else { Write-Output $message }
}
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
            if ($match.Success) {
                $candidate = Join-Path $library ('steamapps\common\' + $match.Groups[1].Value)
                if (Test-Path -LiteralPath (Join-Path $candidate 'DS\Binaries\Win64\DSClient-Win64-Shipping.exe')) { return $candidate }
            }
        }
    }
    return ''
}
function Resolve-Child([string]$root, [string]$relative) {
    $rootFull = [IO.Path]::GetFullPath($root).TrimEnd('\')
    $full = [IO.Path]::GetFullPath((Join-Path $root $relative))
    if (-not $full.StartsWith(($rootFull + '\'), [StringComparison]::OrdinalIgnoreCase)) { throw '설치 기록의 파일 경로가 올바르지 않습니다.' }
    $probe = $full
    while ($probe -and $probe -ne $rootFull) {
        if ((Test-Path -LiteralPath $probe) -and ((Get-Item -LiteralPath $probe -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "연결된 폴더 또는 파일에는 자동 작업을 하지 않습니다: $probe"
        }
        $probe = [IO.Path]::GetDirectoryName($probe)
    }
    return $full
}
function Read-Record([string]$path) {
    $record = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    $requiredPaths = $allowedPaths
    if (@($record.files).Count -eq $legacyPaths.Count) { $requiredPaths = $legacyPaths }
    elseif (@($record.files).Count -ne $allowedPaths.Count) { throw '설치 기록의 파일 목록이 올바르지 않습니다.' }
    $seen = @{}
    foreach ($entry in $record.files) {
        $entry.path = ([string]$entry.path).Replace('/','\')
        if ($entry.path -notin $requiredPaths -or $seen.ContainsKey($entry.path) -or $entry.sha256 -notmatch '^[0-9a-fA-F]{64}$') {
            throw '설치 기록의 파일 목록 또는 해시가 올바르지 않습니다.'
        }
        $seen[$entry.path] = $true
    }
    return $record
}
function Assert-TrackedFiles($record) {
    foreach ($entry in $record.files) {
        $target = Resolve-Child $gameBin $entry.path
        if (Test-Path -LiteralPath $target) {
            if (-not (Test-Path -LiteralPath $target -PathType Leaf) -or
                (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $entry.sha256) {
                throw "설치 후 파일이 변경되어 중단했습니다. 원래 파일을 복원한 뒤 다시 시도하세요: $target"
            }
        }
    }
}
function Assert-NoOtherMods {
    $mods = Join-Path $gameBin 'ue4ss\Mods'
    if (Test-Path -LiteralPath $mods) {
        $other = @(Get-ChildItem -LiteralPath $mods -Directory | Where-Object { $_.Name -notin @('DragonSwordCameraNoDelay','shared') })
        if ($other.Count -gt 0) { throw '다른 UE4SS 모드가 있어 공용 로더를 자동 변경할 수 없습니다. 기존 모드 구성을 먼저 확인하세요.' }
    }
}

try {
    if ($Action -eq 'Discover') {
        $found = Find-GameRoot
        Complete-Result @{ok=$true;gameRoot=$found} $found
        return
    }
    if (-not $GameRoot) { $GameRoot = Find-GameRoot }
    if (-not $GameRoot -or -not (Test-Path -LiteralPath $GameRoot -PathType Container)) { throw '게임 폴더를 찾지 못했습니다. DSClient.exe가 있는 폴더를 선택하세요.' }
    $GameRoot = (Resolve-Path -LiteralPath $GameRoot).Path
    $gameBin = Resolve-Child $GameRoot 'DS\Binaries\Win64'
    if (-not (Test-Path -LiteralPath (Join-Path $gameBin 'DSClient-Win64-Shipping.exe') -PathType Leaf)) { throw '드래곤소드 설치 폴더가 아닙니다. DSClient.exe가 있는 폴더를 선택하세요.' }
    $recordPath = Resolve-Child $gameBin 'CameraNoDelay-install-manifest.json'
    $running = [bool](Get-Process -Name 'DSClient-Win64-Shipping','DSClient' -ErrorAction SilentlyContinue)
    $oldRecord = $null
    $conflict = ''
    try {
        if (Test-Path -LiteralPath $recordPath) {
            $oldRecord = Read-Record $recordPath
            Assert-TrackedFiles $oldRecord
            Assert-NoOtherMods
        } else {
            foreach ($loader in @('dwmapi.dll','UE4SS.dll','UE4SS-settings.ini','xinput1_3.dll','ue4ss\UE4SS.dll','ue4ss\UE4SS-settings.ini','ue4ss\Mods\mods.txt')) {
                if (Test-Path -LiteralPath (Resolve-Child $gameBin $loader)) { throw '기존 모드 로더가 감지됐습니다. 설치 기록이 없는 로더는 덮어쓰지 않습니다. 설치 안내의 수동 설치 방법을 확인하세요.' }
            }
        }
    } catch { $conflict = $_.Exception.Message }
    if ($Action -eq 'Status') {
        $version = ''; if ($oldRecord) { $version = [string]$oldRecord.version }
        $state = 'not-installed'; $message = '모드가 설치되어 있지 않습니다.'
        if ($oldRecord) { $state='installed'; $message="모드가 설치되어 있습니다. (v$version)" }
        if ($conflict) { $state='conflict'; $message=$conflict }
        if ($running -and -not $conflict) { $message += ' 게임을 종료한 뒤 상태 새로고침 버튼을 눌러주세요.' }
        Complete-Result @{ok=$true;gameRoot=$GameRoot;state=$state;version=$version;running=$running;
            canInstall=(-not $running -and -not $conflict);canRemove=([bool]$oldRecord -and -not $running -and -not $conflict);message=$message} $message
        return
    }
    if ($running) { throw '게임이 실행 중입니다. 드래곤소드를 완전히 종료한 뒤 다시 시도하세요.' }
    if ($conflict) { throw $conflict }
    if ($Action -eq 'Remove') {
        if (-not $oldRecord) { throw '설치 기록이 없어 자동 삭제할 수 없습니다. 변경된 파일은 없습니다.' }
        $backup = Resolve-Child $gameBin ('CameraNoDelay-backup-remove-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
        $moved = [Collections.Generic.List[object]]::new()
        try {
            foreach ($entry in $oldRecord.files) {
                $target = Resolve-Child $gameBin $entry.path
                if (-not (Test-Path -LiteralPath $target)) { continue }
                $destination = Resolve-Child $backup $entry.path
                New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
                Move-Item -LiteralPath $target -Destination $destination
                $moved.Add(@{target=$target;backup=$destination})
            }
            New-Item -ItemType Directory -Path $backup -Force | Out-Null
            Move-Item -LiteralPath $recordPath -Destination (Join-Path $backup 'install-manifest.json')
        } catch {
            $failure = $_.Exception.Message
            for ($i=$moved.Count-1; $i -ge 0; $i--) { Move-Item -LiteralPath $moved[$i].backup -Destination $moved[$i].target }
            throw "삭제를 완료하지 못해 이전 상태로 복원했습니다. $failure"
        }
        Complete-Result @{ok=$true;gameRoot=$GameRoot;state='not-installed';backupPath=$backup;message='모드를 삭제했습니다.'} "모드를 삭제했습니다. 파일 보관 위치: $backup"
        return
    }
    $payloadRoot = Join-Path $PSScriptRoot 'DS\Binaries\Win64'
    $packageManifest = Join-Path $PSScriptRoot 'install-manifest.json'
    if (-not (Test-Path -LiteralPath $packageManifest)) { throw '설치 파일이 누락됐습니다. 배포 파일을 다시 받으세요.' }
    $newRecord = Read-Record $packageManifest
    foreach ($entry in $newRecord.files) {
        $source = Resolve-Child $payloadRoot $entry.path
        $target = Resolve-Child $gameBin $entry.path
        if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $entry.sha256) { throw "배포 파일 검증에 실패했습니다: $($entry.path)" }
        if (-not $oldRecord -and (Test-Path -LiteralPath $target)) { throw "기존 파일을 덮어쓸 수 없습니다: $target" }
        if ($oldRecord -and $entry.path -notin @($oldRecord.files.path) -and (Test-Path -LiteralPath $target)) {
            throw "이전 설치 기록에 없는 파일을 덮어쓸 수 없습니다: $target"
        }
    }
    $backup = ''
    if ($oldRecord) {
        $backup = Resolve-Child $gameBin ('CameraNoDelay-backup-update-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
        foreach ($entry in $oldRecord.files) {
            $target = Resolve-Child $gameBin $entry.path
            if (-not (Test-Path -LiteralPath $target)) { continue }
            $destination = Resolve-Child $backup $entry.path
            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
            Copy-Item -LiteralPath $target -Destination $destination
        }
        New-Item -ItemType Directory -Path $backup -Force | Out-Null
        Copy-Item -LiteralPath $recordPath -Destination (Join-Path $backup 'install-manifest.json')
    }
    $written = [Collections.Generic.List[object]]::new()
    $manifestTemp = Resolve-Child $gameBin ('CameraNoDelay-manifest-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        foreach ($entry in $newRecord.files) {
            $source = Resolve-Child $payloadRoot $entry.path
            $target = Resolve-Child $gameBin $entry.path
            $original = ''; if ($backup) { $original = Resolve-Child $backup $entry.path }
            $written.Add(@{target=$target;original=$original})
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination $target -Force
            if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $entry.sha256) { throw "설치 파일 확인에 실패했습니다: $($entry.path)" }
        }
        Copy-Item -LiteralPath $packageManifest -Destination $manifestTemp
        Move-Item -LiteralPath $manifestTemp -Destination $recordPath -Force
    } catch {
        $failure = $_.Exception.Message
        for ($i=$written.Count-1; $i -ge 0; $i--) {
            $item = $written[$i]
            if ($item.original -and (Test-Path -LiteralPath $item.original -PathType Leaf)) {
                if (-not (Test-Path -LiteralPath $item.target) -or
                    (Get-FileHash -LiteralPath $item.target -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $item.original -Algorithm SHA256).Hash) {
                    Copy-Item -LiteralPath $item.original -Destination $item.target -Force
                }
            } elseif (Test-Path -LiteralPath $item.target -PathType Leaf) { Remove-Item -LiteralPath $item.target }
        }
        if (Test-Path -LiteralPath $manifestTemp) { Remove-Item -LiteralPath $manifestTemp }
        throw "설치를 완료하지 못해 이전 상태로 복원했습니다. $failure"
    }
    Complete-Result @{ok=$true;gameRoot=$GameRoot;state='installed';version=$newRecord.version;backupPath=$backup;message='모드를 설치했습니다. Steam에서 게임을 실행하세요. F7: 메뉴 조작, F8: 카메라.'} '모드를 설치했습니다. Steam에서 게임을 실행하세요. F7: 메뉴 조작, F8: 카메라.'
} catch {
    if ($AsJson) { @{ok=$false;message=$_.Exception.Message} | ConvertTo-Json -Compress; exit 1 }
    throw
}
