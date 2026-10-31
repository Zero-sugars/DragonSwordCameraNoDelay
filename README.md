# 드래곤소드: 어웨이크닝 카메라 회전 딜레이 제거 모드

마우스를 움직일 때 카메라가 뒤늦게 따라오는 회전 보간을 끄는 모드입니다. 실행할 때 자동으로 켜지며, **F8**로 원래 동작과 비교할 수 있습니다.

**[설치·삭제 프로그램 받기](https://github.com/pwj891129-arch/DragonSwordCameraNoDelay/releases/download/v0.2.1/DragonSword.CameraNoDelay.Setup.exe)** · [전체 ZIP 받기](https://github.com/pwj891129-arch/DragonSwordCameraNoDelay/releases/download/v0.2.1/DragonSwordCameraNoDelay-v0.2.1-win-x64.zip) · [최신 릴리스](https://github.com/pwj891129-arch/DragonSwordCameraNoDelay/releases/latest)

## 설치 방법

1. 드래곤소드를 완전히 종료합니다.
2. 위 링크에서 **`DragonSword.CameraNoDelay.Setup.exe`**를 받습니다. ZIP으로 받았다면 먼저 압축을 풉니다.
3. 실행 파일을 열고 자동으로 검색된 **게임 폴더**를 확인합니다. 자동 검색에 실패하면 **폴더 선택**으로 `DSClient.exe`가 있는 폴더를 고릅니다.
4. **모드 설치 / 업데이트** 버튼을 누릅니다.
5. ‘설치됨’ 상태를 확인하고 Steam에서 게임을 실행합니다.

Windows 10/11 64비트용입니다. 설치 자료와 .NET 런타임이 실행 파일에 포함되어 있어 별도의 Python·.NET 설치나 로더 다운로드가 필요하지 않습니다. GitHub의 `Source code (zip)`은 개발용 소스입니다.

프로그램은 대기 중에 자동 새로고침하지 않습니다. 게임을 종료한 뒤 버튼 상태를 갱신하려면 **상태 새로고침**을 누르세요. 0.2.0 설치 창의 주기적인 새로고침은 새 프로그램으로 교체하면 없어지며, 카메라 모드를 다시 설치할 필요는 없습니다.

## 단축키

| 키 | 기능 |
| --- | --- |
| **F8** | 지연 제거 켜기 / 끄기. 끄면 변경 전 카메라 값을 복원합니다. |
| **F9** | 카메라 상태를 로그에 기록합니다. |

게임을 다시 실행하면 기본으로 켜집니다. 화면에 별도의 켜짐·꺼짐 알림은 표시하지 않습니다.

## 제거 방법

1. 게임을 완전히 종료합니다.
2. 같은 **`DragonSword.CameraNoDelay.Setup.exe`**를 실행합니다.
3. 게임 폴더와 ‘설치됨’ 상태를 확인하고 **모드 삭제** 버튼을 누릅니다.

‘설치되지 않음’으로 바뀌면 삭제가 완료된 것입니다. 설치 파일은 게임 폴더의 `DS\Binaries\Win64\CameraNoDelay-backup-*`로 옮겨 보관합니다. 설치 후 파일을 직접 수정했거나 다른 UE4SS 모드가 추가됐다면 표시된 안내를 먼저 확인하세요.

## 기존 0.1.0·0.2.0 사용자는

0.1.0·0.2.0의 자동 설치로 설치한 모드도 인식합니다. 게임을 종료하고 새 프로그램에서 **모드 설치 / 업데이트** 또는 **모드 삭제**를 누르세요. 일부 설치 파일이 누락된 경우에는 설치 버튼으로 복구할 수 있습니다.

## 이미 UE4SS를 설치한 경우

자동 설치 프로그램은 기존 로더를 덮어쓰지 않고 중단합니다. 기존 UE4SS와 함께 사용하려면 다음과 같이 설치하세요.

1. [수동 설치용 ZIP](https://github.com/pwj891129-arch/DragonSwordCameraNoDelay/releases/download/v0.1.0/DragonSwordCameraNoDelay-v0.1.0.zip) 안의 `DS\Binaries\Win64\ue4ss\Mods\DragonSwordCameraNoDelay` 폴더를 기존 UE4SS의 `Mods` 폴더에 복사합니다. 카메라 Lua 모드는 0.2.1과 동일합니다.
2. 기존 `mods.txt`에 아래 한 줄을 추가합니다.

```text
DragonSwordCameraNoDelay : 1
```

이 방식으로 설치했다면 해당 줄을 `DragonSwordCameraNoDelay : 0`으로 바꾸어 비활성화하세요. 수동 설치한 모드는 설치 기록이 없어 새 프로그램에서 자동 삭제하지 않습니다. 기존 로더의 게임 호환성은 별도로 확인해야 합니다.

## 확인한 환경

| 항목 | 확인한 버전 |
| --- | --- |
| 게임 | Steam 드래곤소드: 어웨이크닝 1.1.2 |
| Steam 앱 / 빌드 | 4570720 / 26210326 |
| 엔진 | Unreal Engine 5.3 |
| 포함된 로더 | UE4SS 3.0.1-1188-gf885e8d2 |
| 설치·삭제 프로그램 | 0.2.1 / Windows x64 |

실제 게임에서 적용과 F8 복원을 확인했고, 사용자 테스트에서 카메라 회전 딜레이가 없어졌음을 확인했습니다. 캐릭터 교체 시 다시 적용하는 로직은 자동 테스트를 통과했습니다. 탑승·컷신·협동 플레이를 포함한 모든 상황을 검증한 버전은 아니며, 게임 업데이트 후에는 호환성을 다시 확인해야 합니다.

문제가 있으면 게임 폴더의 `DS\Binaries\Win64\ue4ss\UE4SS.log`에서 `[DragonSwordCameraNoDelay]`가 포함된 줄을 확인하세요. [검증 범위](docs/VALIDATION.md)도 함께 참고할 수 있습니다.

## 작동 방식

로컬 플레이어의 `DsSpringArmComponent`에서 `bEnableCameraRotationLag`를 `false`, `CameraRotationLagSpeed`를 `0`으로 설정합니다. 고정 메모리 주소 대신 실제 프로퍼티를 조회하며, 게임 스레드에서 0.1초 간격으로 적용 상태를 확인합니다.

원본 실행 파일·PAK·게임 설정·세이브를 패치하지 않습니다. 위치 추적 보간, 벽 충돌, 마우스 감도는 기존 값을 유지합니다. 게임 제작사와 무관한 비공식 모드입니다.

## 소스에서 빌드하기

설치 실행 파일에 로더·Lua 스크립트와 설치 도구가 포함되어 있습니다. 소스를 수정해 새 패키지를 만들려면 Windows, **.NET 10 SDK**, **PowerShell 7**을 사용하세요.

```powershell
pwsh -File .\Get-Dependencies.ps1
pwsh -File .\Build.ps1
```

결과는 `dist\DragonSword.CameraNoDelay.Setup.exe`와 `dist\DragonSwordCameraNoDelay-v0.2.1-win-x64.zip`에 생성됩니다. `release`에 같은 버전 폴더가 이미 있으면 덮어쓰지 않고 중단합니다. UE4SS 의존성 다운로드 시 SHA256을 검증하며, 기존 0.1.0 배포 ZIP으로 로더를 준비할 수도 있습니다.

```powershell
pwsh -File .\Get-Dependencies.ps1 -ReleaseArchive 'C:\Downloads\DragonSwordCameraNoDelay-v0.1.0.zip'
```

자동 테스트는 개발용 Python 3.11 이상이 추가로 필요합니다.

```powershell
python -m pip install --target .\tools\python -r .\tests\requirements.txt
python .\tests\run.py
pwsh -File .\tests\Test-Installer.ps1 -PackageRoot .\staging\manager-payload-v0.2.1
python .\tests\test_setup.py .\dist\DragonSword.CameraNoDelay.Setup.exe
pwsh -File .\tests\Test-Ui.ps1
```

## 포함된 오픈소스

UE4SS는 [UE4SS-RE/RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS)의 공식 배포본이며 MIT 라이선스를 따릅니다. [라이선스 전문](third-party/UE4SS-LICENSE.txt)과 [배포 정보](THIRD-PARTY-NOTICES.md)를 포함합니다.

자체 실행을 위한 Microsoft .NET 런타임과 관련 라이선스·고지도 포함합니다. ZIP 배포본의 `licenses` 폴더에서 확인할 수 있습니다.
