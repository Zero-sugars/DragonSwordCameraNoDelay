# 다른 UE4SS 모드와 함께 사용하기

이미 다른 UE4SS 모드를 사용 중이면 설치 프로그램의 자동 설치가 중단될 수 있습니다. 이 경우 카메라 모드만 수동으로 추가하세요.

## 설치

1. 게임을 완전히 종료합니다.
2. [수동 설치용 ZIP](https://github.com/pwj891129-arch/DragonSwordCameraNoDelay/releases/download/v0.1.0/DragonSwordCameraNoDelay-v0.1.0.zip)을 받아 압축을 풉니다.
3. ZIP 안의 `DS\Binaries\Win64\ue4ss\Mods\DragonSwordCameraNoDelay` 폴더를 기존 UE4SS의 `Mods` 폴더에 복사합니다.
4. 기존 `mods.txt`에 다음 줄이 없으면 추가합니다.

```text
DragonSwordCameraNoDelay : 1
```

게임에서 **F8**로 켜거나 끌 수 있습니다. 수동 설치용 ZIP에도 같은 카메라 모드가 들어 있습니다.

## 끄기·삭제

끄려면 `mods.txt`의 해당 줄을 `DragonSwordCameraNoDelay : 0`으로 바꾸세요.

삭제하려면 게임을 종료하고, `mods.txt`의 해당 줄과 `Mods\DragonSwordCameraNoDelay` 폴더를 제거하세요. 수동 설치한 모드는 설치 프로그램에서 자동 삭제하지 않습니다.

[기본 설치 안내로 돌아가기](../README.md)
