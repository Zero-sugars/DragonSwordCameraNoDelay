# 다른 UE4SS 모드와 함께 사용하기

이미 다른 UE4SS 모드를 사용 중이면 설치 프로그램의 자동 설치가 중단될 수 있습니다. 이 경우 아래 방법으로 모드 파일을 추가하세요. 메뉴 기능은 UE4SS 실험판 `v3.0.1-1188-gf885e8d2`에서 확인했습니다. 오래된 로더에서는 메뉴 기능이 작동하지 않을 수 있습니다.

## 설치

1. 게임을 완전히 종료합니다.
2. [배포 페이지](https://github.com/Zero-sugars/DragonSwordCameraNoDelay/releases)에서 해당 버전의 `mod-only.zip`을 받아 압축을 풉니다.
3. ZIP 안의 `DragonSwordCameraNoDelay` 폴더를 기존 UE4SS의 `Mods` 폴더에 복사합니다. 이전 버전을 수동으로 설치했다면 같은 폴더의 파일을 교체하세요.
4. 기존 `mods.txt`에 다음 줄이 없으면 추가합니다.

```text
DragonSwordCameraNoDelay : 1
```

게임에서 **F7**은 메뉴 조작, **F8**은 카메라 기능을 켜거나 끕니다. **WASD**로 항목 이동, **스페이스바**로 확인, **Q/E**로 첫 번째 탭, 키보드 윗줄의 **1/3**으로 두 번째 탭을 전환합니다. 세 번째 이하 탭은 마우스를 사용하세요. 던전 퇴장 동작과 확인창은 **F**로 승인하며, Esc 취소는 기존 게임 기능을 사용합니다.

수동 설치 파일은 두 기능을 모두 켭니다. 한 기능만 사용하려면 게임을 종료하고 `Scripts\components.lua`에서 카메라는 `camera`, 키보드 메뉴는 `menu` 값을 `true` 또는 `false`로 설정하세요. 설치 프로그램에서 자동으로 설치한 파일은 이 방법으로 수정하지 말고, 해당 기능의 설치·삭제 버튼으로 관리하세요.

## 끄기·삭제

끄려면 `mods.txt`의 해당 줄을 `DragonSwordCameraNoDelay : 0`으로 바꾸세요.

삭제하려면 게임을 종료하고, `mods.txt`의 해당 줄과 `Mods\DragonSwordCameraNoDelay` 폴더를 제거하세요. 수동 설치한 모드는 설치 프로그램에서 자동 삭제하지 않습니다.

[기본 설치 안내로 돌아가기](../README.md)
