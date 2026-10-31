# 드래곤소드: 어웨이크닝 카메라 회전 딜레이 제거 모드

마우스를 움직일 때 카메라가 뒤늦게 따라오는 회전 보간을 끄는 모드입니다. 실행할 때 자동으로 켜지며, **F8**로 원래 동작과 비교할 수 있습니다.

**[배포 파일 다운로드](https://github.com/pwj891129-arch/DragonSwordCameraNoDelay/releases/latest)** · [v0.1.0 ZIP 바로 받기](https://github.com/pwj891129-arch/DragonSwordCameraNoDelay/releases/download/v0.1.0/DragonSwordCameraNoDelay-v0.1.0.zip)

## 설치 방법

1. 드래곤소드를 완전히 종료합니다.
2. [Releases](https://github.com/pwj891129-arch/DragonSwordCameraNoDelay/releases/latest)에서 **`DragonSwordCameraNoDelay-v0.1.0.zip`**을 받습니다.
3. ZIP을 새 폴더에 **모두 압축 해제**합니다.
4. 압축을 푼 폴더의 **`Install.cmd`**를 실행합니다. Steam에 설치된 게임을 자동으로 찾습니다.
5. 설치 완료 메시지를 확인하고 Steam에서 게임을 실행합니다.

GitHub의 `Source code (zip)`은 개발용 소스입니다. 위에 적힌 배포 ZIP을 받아 설치하세요. 별도의 Python이나 .NET 설치는 필요하지 않습니다.

## 단축키

| 키 | 기능 |
| --- | --- |
| **F8** | 지연 제거 켜기 / 끄기. 끄면 변경 전 카메라 값을 복원합니다. |
| **F9** | 카메라 상태를 로그에 기록합니다. |

게임을 다시 실행하면 기본으로 켜집니다. 화면에 별도의 켜짐·꺼짐 알림은 표시하지 않습니다.

## 제거 방법

1. 게임을 완전히 종료합니다.
2. 배포 ZIP에 포함된 **`Remove.cmd`**를 실행합니다.

설치 파일은 게임 폴더의 `DS\Binaries\Win64\CameraNoDelay-backup-*`로 옮겨 보관합니다. 설치 후 파일을 직접 수정했다면 자동 제거가 중단되므로, 표시된 파일을 먼저 확인하세요.

## 게임 경로를 찾지 못할 때

압축을 푼 폴더에서 PowerShell을 열고 `DSClient.exe`가 들어 있는 게임 폴더를 지정합니다. 아래 경로를 본인의 설치 경로로 바꾸세요.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Manage-Mod.ps1 -Action Install -GameRoot 'D:\SteamLibrary\steamapps\common\DragonSword  Awakening'
```

제거할 때는 `-Action Install`을 `-Action Remove`로 바꿉니다.

## 이미 UE4SS를 설치한 경우

자동 설치 프로그램은 기존 로더를 덮어쓰지 않고 중단합니다. 기존 UE4SS와 함께 사용하려면 다음과 같이 설치하세요.

1. 배포 ZIP 안의 `DS\Binaries\Win64\ue4ss\Mods\DragonSwordCameraNoDelay` 폴더를 기존 UE4SS의 `Mods` 폴더에 복사합니다.
2. 기존 `mods.txt`에 아래 한 줄을 추가합니다.

```text
DragonSwordCameraNoDelay : 1
```

이 방식으로 설치했다면 `Remove.cmd` 대신 해당 줄을 `DragonSwordCameraNoDelay : 0`으로 바꾸어 비활성화하세요. 기존 로더의 게임 호환성은 별도로 확인해야 합니다.

## 확인한 환경

| 항목 | 확인한 버전 |
| --- | --- |
| 게임 | Steam 드래곤소드: 어웨이크닝 1.1.2 |
| Steam 앱 / 빌드 | 4570720 / 26210326 |
| 엔진 | Unreal Engine 5.3 |
| 포함된 로더 | UE4SS 3.0.1-1188-gf885e8d2 |

실제 게임에서 적용과 F8 복원을 확인했고, 사용자 테스트에서 카메라 회전 딜레이가 없어졌음을 확인했습니다. 캐릭터 교체 시 다시 적용하는 로직은 자동 테스트를 통과했습니다. 탑승·컷신·협동 플레이를 포함한 모든 상황을 검증한 버전은 아니며, 게임 업데이트 후에는 호환성을 다시 확인해야 합니다.

문제가 있으면 게임 폴더의 `DS\Binaries\Win64\ue4ss\UE4SS.log`에서 `[DragonSwordCameraNoDelay]`가 포함된 줄을 확인하세요. [검증 범위](docs/VALIDATION.md)도 함께 참고할 수 있습니다.

## 작동 방식

로컬 플레이어의 `DsSpringArmComponent`에서 `bEnableCameraRotationLag`를 `false`, `CameraRotationLagSpeed`를 `0`으로 설정합니다. 고정 메모리 주소 대신 실제 프로퍼티를 조회하며, 게임 스레드에서 0.1초 간격으로 적용 상태를 확인합니다.

원본 실행 파일·PAK·게임 설정·세이브를 패치하지 않습니다. 위치 추적 보간, 벽 충돌, 마우스 감도는 기존 값을 유지합니다. 게임 제작사와 무관한 비공식 모드입니다.

## 소스에서 빌드하기

배포 ZIP에는 실행에 필요한 로더와 Lua 스크립트가 포함되어 있습니다. 소스를 수정해 새 패키지를 만들려면 Windows와 **PowerShell 7**을 사용하세요.

```powershell
pwsh -File .\Get-Dependencies.ps1
pwsh -File .\Build.ps1
```

결과는 `dist\DragonSwordCameraNoDelay-v0.1.0.zip`에 생성됩니다. `release`에 같은 버전 폴더가 이미 있으면 덮어쓰지 않고 중단합니다. UE4SS 의존성 다운로드 시 SHA256을 검증하며, 기존 배포 ZIP으로 준비할 수도 있습니다.

```powershell
pwsh -File .\Get-Dependencies.ps1 -ReleaseArchive 'C:\Downloads\DragonSwordCameraNoDelay-v0.1.0.zip'
```

자동 테스트는 개발용 Python 3.11 이상이 추가로 필요합니다.

```powershell
python -m pip install --target .\tools\python -r .\tests\requirements.txt
python .\tests\run.py
pwsh -File .\tests\Test-Installer.ps1 -PackageRoot .\release\DragonSwordCameraNoDelay-v0.1.0
```

## 포함된 오픈소스

UE4SS는 [UE4SS-RE/RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS)의 공식 배포본이며 MIT 라이선스를 따릅니다. [라이선스 전문](third-party/UE4SS-LICENSE.txt)과 [배포 정보](THIRD-PARTY-NOTICES.md)를 포함합니다.
