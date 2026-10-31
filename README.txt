드래곤소드: 어웨이크닝 카메라 회전 딜레이 제거 모드 0.1.0

마우스를 움직일 때 플레이어 카메라가 뒤늦게 따라오는 회전 보간을 끕니다.
실행할 때마다 기본으로 켜집니다. F8로 원래 동작과 비교할 수 있습니다.

사용
  1. 게임을 완전히 종료합니다.
  2. ZIP을 새 폴더에 모두 압축 해제합니다.
  3. Install.cmd를 실행합니다. Steam 설치 폴더를 자동 검색합니다.
  4. Steam에서 게임을 실행합니다.

단축키
  F8: 지연 제거 켜기 / 끄기. 끄면 변경 전 카메라 값을 복원합니다.
  F9: 상태를 DS\Binaries\Win64\ue4ss\UE4SS.log에 기록합니다.
  화면에 별도 켜짐/꺼짐 알림은 표시하지 않습니다.

제거
  게임을 종료하고 Remove.cmd를 실행합니다.
  설치한 파일은 게임의 DS\Binaries\Win64\CameraNoDelay-backup-* 폴더로 보관합니다.
  원본 EXE, PAK, INI 설정, 세이브 파일은 이 모드가 패치하지 않습니다.

경로를 직접 지정하려면 PowerShell에서 실행합니다.
  .\Manage-Mod.ps1 -Action Install -GameRoot 'E:\SteamLibrary\steamapps\common\DragonSword  Awakening'
  .\Manage-Mod.ps1 -Action Remove -GameRoot 'E:\SteamLibrary\steamapps\common\DragonSword  Awakening'

이미 UE4SS를 사용하는 경우
  설치 스크립트는 기존 로더를 덮어쓰지 않고 중단합니다.
  DS\Binaries\Win64\ue4ss\Mods\DragonSwordCameraNoDelay 폴더만 기존 Mods 폴더에 복사하고,
  기존 mods.txt에 다음 줄을 추가하세요.
    DragonSwordCameraNoDelay : 1
  이 경우 자동 제거 스크립트는 사용하지 않고 해당 모드만 직접 비활성화하세요.

확인한 환경과 범위
  Steam 앱 4570720 / 빌드 26210326 / 게임 1.1.2 / Unreal Engine 5.3
  실제 플레이어의 DsSpringArmComponent에서 bEnableCameraRotationLag=True,
  CameraRotationLagSpeed=10인 것을 확인하고 False / 0으로 변경했습니다.
  제작 중 사용자가 게임 안에서 카메라 딜레이가 없어졌음을 확인했습니다.
  캐릭터 교체 시 현재 플레이어 카메라를 다시 찾아 적용합니다.
  위치 추적 보간, 벽 충돌, 감도, 전투 수치와 네트워크 로직은 변경하지 않습니다.
  캐릭터 교체·탑승·컷신·협동 플레이의 모든 조합을 검증한 버전은 아닙니다.
  게임 업데이트 후에는 호환성을 다시 확인해야 합니다.

구현
  UE4SS Lua 스크립트. 메모리 오프셋을 고정하지 않고 실제 프로퍼티를 조회합니다.
  로컬 플레이어 CameraControllerComponent가 가리키는 캐릭터 카메라만 변경합니다.
  게임 스레드에서 0.1초 간격으로 확인하며, 정상 실행 중 전체 씬을 반복 검색하지 않습니다.

포함된 로더
  UE4SS 3.0.1-1188-gf885e8d2, 공식 experimental 배포본, MIT License
  https://github.com/UE4SS-RE/RE-UE4SS
  원본 ZIP SHA256: 4a594fb5c6e1aa794b06a770730e072c53fb92b741f95a5f0601080d80f4a6c1
  라이선스: DS\Binaries\Win64\ue4ss\LICENSE

참고 문서
  https://docs.ue4ss.com/lua-api.html
  https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/Engine/USpringArmComponent
