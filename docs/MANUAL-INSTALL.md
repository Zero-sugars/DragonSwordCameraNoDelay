# 다른 UE4SS 모드와 함께 사용하기

이미 다른 UE4SS 모드를 사용 중이면 설치 프로그램의 자동 설치가 중단될 수 있습니다. 이 경우 아래 방법으로 모드 파일을 추가하세요. 메뉴 기능은 UE4SS 실험판 `v3.0.1-1188-gf885e8d2`에서 확인했습니다. 오래된 로더에서는 메뉴 기능이 작동하지 않을 수 있습니다.

## 설치

1. 게임을 완전히 종료합니다.
2. [수동 설치용 ZIP](https://github.com/Zero-sugars/DragonSwordCameraNoDelay/releases/download/v0.3.0/DragonSwordCameraNoDelay-v0.3.0-mod-only.zip)을 받아 압축을 풉니다.
3. ZIP 안의 `DragonSwordCameraNoDelay` 폴더를 기존 UE4SS의 `Mods` 폴더에 복사합니다. 이전 버전을 수동으로 설치했다면 같은 폴더의 파일을 교체하세요.
4. 기존 `mods.txt`에 다음 줄이 없으면 추가합니다.

```text
DragonSwordCameraNoDelay : 1
```

게임에서 **F7**은 메뉴 조작, **F8**은 카메라 기능을 켜거나 끕니다. **WASD**로 항목 이동, **스페이스바**로 확인, **Q/E**로 탭을 전환합니다.

## 끄기·삭제

끄려면 `mods.txt`의 해당 줄을 `DragonSwordCameraNoDelay : 0`으로 바꾸세요.

삭제하려면 게임을 종료하고, `mods.txt`의 해당 줄과 `Mods\DragonSwordCameraNoDelay` 폴더를 제거하세요. 수동 설치한 모드는 설치 프로그램에서 자동 삭제하지 않습니다.

[기본 설치 안내로 돌아가기](../README.md)
