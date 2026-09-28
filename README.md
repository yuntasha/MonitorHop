# MonitorHop

키보드만으로 **N번째 모니터로 포커스를 옮기고**, **지금 보고 있는 창을 N번째 모니터로 보내는** macOS 메뉴 막대 앱입니다.
macOS 기본 기능에는 모니터 단위 포커스 이동이 없어서 만들었습니다.

| 기능 | 기본 단축키 | 동작 |
|---|---|---|
| N번 모니터로 포커스 이동 | `⌃⌥1` … `⌃⌥4` | 그 모니터에서 가장 앞에 있는 창을 활성화하고 마우스 커서를 그 창으로 옮깁니다. 창이 없으면 커서만 옮깁니다. |
| 현재 창을 N번 모니터로 보내기 | `⌃⌥⇧1` … `⌃⌥⇧4` | 포커스된 창을 그 모니터로 옮기고 포커스와 커서가 따라갑니다. |

- 모니터 번호 순서 변경: 설정 › 모니터 탭에서 드래그하거나 ↑↓ 버튼으로 바꿉니다. 순서는 **연결된 모니터 조합마다** 따로 기억합니다
  (사무실 책상과 집 책상의 순서가 서로 섞이지 않음). 처음 보는 모니터는 실제 위치(왼쪽 → 오른쪽)에 맞춰 끼워 넣습니다.
- 단축키 변경: 설정 › 단축키 탭에서 버튼을 누르고 새 조합을 입력합니다. 1–9번 모니터까지 지정할 수 있습니다.
- 창 배치 방식: 크기 유지(기본) · 비율 맞춤 · 가운데 배치 · 화면 채우기. 최대화된 창은 새 모니터에서도 가득 찹니다.
- 그 밖에: 모니터 번호 오버레이, 전환 시 번호 표시, 로그인 시 자동 실행, 스크립트용 CLI.

## 요구 사항

- macOS 13 Ventura 이상 (Apple Silicon / Intel)
- 빌드: Xcode **Command Line Tools**만 있으면 됩니다 (`xcode-select --install`). Xcode 앱은 필요 없습니다.

## 설치

```bash
make install        # 빌드 → /Applications/MonitorHop.app 복사 → 실행
```

처음 실행하면 **접근성 권한** 안내 창이 뜹니다.

1. `시스템 설정 열기`를 누릅니다.
2. 개인정보 보호 및 보안 › 손쉬운 사용에서 **MonitorHop**을 켭니다.
3. 권한이 감지되면 안내 창이 자동으로 닫힙니다.

메뉴 막대의 모니터 아이콘에서 모든 기능과 설정을 열 수 있습니다. Dock에는 나타나지 않습니다.
앱을 다시 열면(Finder, Spotlight) 설정 창이 뜹니다.

> 접근성 권한이 없어도 포커스 이동은 앱 단위로 동작합니다. 창 단위 포커스와 창 이동에는 권한이 필요합니다.
> 단축키 자체는 권한 없이 등록됩니다 (Carbon `RegisterEventHotKey`).

## 사용 팁

- 모니터 번호가 헷갈리면 메뉴 › **모니터 번호 보기**를 누르면 각 모니터에 큰 번호가 표시됩니다.
- 번호는 기본적으로 **왼쪽 → 오른쪽**(같은 가로 위치면 위 → 아래) 순서입니다.
- 단축키에는 **⌃가 들어가거나 ⌥⌘를 함께** 써야 합니다 (F1–F20은 단독 사용 가능). ⌘만 쓰는 조합은 ⌘W · ⌘Q 같은
  다른 앱의 기본 단축키를, ⌥만 쓰는 조합은 특수문자 입력(⌥1 = ¡)을 가로채기 때문입니다.
- macOS 시스템 단축키(시스템 설정 › 키보드 › 키보드 단축키)와 겹치면 노란 ⚠︎가 표시됩니다.
  macOS가 등록을 거부한 단축키는 빨간 ⚠︎로 표시되고 메뉴에도 경고가 뜹니다.
  다른 앱이 따로 등록한 전역 단축키와의 충돌은 macOS가 알려 주지 않아 감지할 수 없습니다.
- 스테이지 매니저를 켜 두었다면 "맨 앞 창"은 그 모니터의 무대에 올라 있는 창입니다. 옆 줄의 썸네일은 대상이 아닙니다.
- 전체 화면(별도 Space) 창은 macOS 제약상 옮길 수 없습니다. 전체 화면을 끈 뒤 옮기세요.

## CLI

앱 번들 안의 실행 파일을 스크립트(Raycast, 단축어, skhd 등)에서 호출할 수 있습니다.

```bash
MH=/Applications/MonitorHop.app/Contents/MacOS/MonitorHop
$MH --focus 2       # 2번 모니터로 포커스
$MH --move 1        # 현재 창을 1번 모니터로
$MH --move 1 --pid 1234   # PID 1234 앱이 맨 앞일 때만 옮김 (다른 앱 창을 실수로 옮기지 않게)
$MH --list          # 모니터 목록(번호 순)과 각 모니터의 맨 앞 창
$MH --list-json     # 같은 정보를 JSON으로
$MH --identify      # 모니터 번호 오버레이
$MH --check         # 권한 · API · 단축키 진단
$MH --reload        # defaults로 설정을 직접 바꾼 뒤 앱이 다시 읽게 함
$MH --login-item on # 로그인 시 자동 실행 켜기 (off / status)
```

MonitorHop 앱이 실행 중이면 명령은 **앱으로 전달되어 앱의 접근성 권한으로** 실행됩니다.
그래서 터미널이나 skhd에 따로 권한을 줄 필요가 없습니다. 앱이 꺼져 있으면 CLI가 직접 실행하며,
이때는 호출한 앱(터미널 등)의 권한 기준입니다. 성공하면 종료 코드 0, 실패하면 1, 잘못된 인자는 2입니다.
MonitorHop 메뉴가 열려 있는 동안에는 macOS가 전달을 미루므로 명령이 실패로 끝나며, 나중에 뒤늦게 실행되지 않습니다.

## 개발

```bash
make build          # 디버그 빌드
make test           # 단위 테스트 (Swift Testing, 46개)
make app            # build/MonitorHop.app 조립 + 서명
make run            # build/ 의 앱 실행
make check          # 진단 출력
scripts/integration-test.py   # 실제 창으로 포커스·이동·실제 단축키를 끝까지 검증 (모니터 2대 + 앱 권한 필요, 26개 항목)
```

`make app`은 build/ 의 앱이 실행 중이면 새 빌드로 자동 재시작합니다.
통합 테스트는 build/ 의 최신 앱을 개발 모드(`MONITORHOP_DEVTOOLS=1`)로 띄워 검사하고, 끝나면 원래 실행 중이던 앱을 다시 켭니다.
테스트가 옮기는 창은 항상 테스트용 창뿐입니다 (`--move … --pid`).

개발용 명령:

```bash
# 앱을 `open --env MONITORHOP_DEVTOOLS=1 build/MonitorHop.app`으로 실행했을 때만 동작
$MH --simulate-hotkey focus.2      # 앱이 자기 단축키를 실제로 눌러 봄 (창 서버 → Carbon → 동작)
$MH --set-frame ID X Y W H         # 창 위치·크기 지정 (테스트 복구용)
# 앱 없이 CLI 프로세스 안에서 동작
$MH --render-settings /tmp/shots   # 설정 창 각 탭과 HUD를 PNG로 저장 (화면 점검용)
```

CI(GitHub Actions, macOS 15)는 푸시마다 빌드 · 단위 테스트 · 앱 조립 · CLI 확인을 실행합니다.

### 서명과 접근성 권한

`make app`은 기본적으로 프로젝트 전용 자체 서명 인증서(`.signing/`, git 제외)로 서명합니다.
서명 요구조건이 `identifier "com.alencup.MonitorHop" and certificate leaf = H"…"`로 고정되므로
**다시 빌드해도 접근성 권한이 유지됩니다.** 로그인 키체인에는 아무것도 추가하지 않습니다.

- `SIGN_IDENTITY=- make app` — ad-hoc 서명 (빌드할 때마다 권한을 다시 줘야 함)
- `SIGN_IDENTITY="Developer ID Application: …" make app` — 배포용 서명 (hardened runtime)
- 권한 목록이 꼬였을 때: `make reset-permission` 후 앱을 다시 실행해 권한을 켭니다.

### 구조

```
Sources/MonitorHopCore/   순수 로직 (테스트 대상)
  Geometry.swift          Cocoa(좌하단 원점) ↔ Quartz/AX(좌상단 원점) 좌표 변환, 모니터 판정
  DisplayOrdering.swift   모니터 번호 결정: 사용자 순서(UUID) + 자동(왼→오) 정렬
  Placement.swift         창 배치 계산 4가지 모드, 화면 안으로 클램프
  Shortcut.swift          단축키 모델, 수정키 변환(Carbon/Cocoa), 키 이름
  AppConfig.swift         설정 모델 (JSON, 알 수 없는 값은 기본값으로)
Sources/MonitorHop/       앱
  ActionPerformer.swift   두 기능의 구현 (포커스 대상 선택, 활성화, 검증 · 창 이동)
  Accessibility.swift     AXUIElement 래퍼, AX 창 ↔ CGWindowID 매핑
  AppActivator.swift      백그라운드 앱에서 다른 앱을 앞으로 가져오기, 커서 이동
  WindowFinder.swift      CGWindowList로 모니터별 앞→뒤 창 목록
  ScreenRegistry.swift    연결된 모니터와 번호, 핫플러그 감지
  HotkeyCenter.swift      전역 단축키 (Carbon)
  ShortcutRecorder.swift  단축키 녹화 버튼
  SettingsView.swift      설정 창 (단축키 · 모니터 · 일반)
  RemoteControl.swift     CLI ↔ 실행 중인 앱 (분산 알림), 두 번째 실행 → 설정 창 열기
  InstanceLock.swift      GUI 단일 실행 (flock)
  SystemShortcuts.swift   macOS 시스템 단축키와의 충돌 확인
  StatusMenuController.swift, HUD.swift, PermissionWindow.swift, LoginItem.swift, CLI.swift
```

### 동작 원리

- **포커스 이동**: 창 서버의 앞→뒤 목록(`CGWindowListCopyWindowInfo`)에서 대상 모니터의 첫 번째 일반 창을 찾고,
  접근성 API 창과 CGWindowID로 정확히 매칭합니다. 그 창을 main으로 만들고(`AXMain`),
  앱을 앞으로 가져온 뒤(`SetFrontProcessWithOptions`, 앞 창만) `AXRaise` 합니다.
  macOS 14부터 `NSRunningApplication.activate`는 백그라운드 앱의 요청을 무시할 수 있어서 이 순서를 씁니다.
  150 · 300 · 500ms에 실제로 전환됐는지 확인해 필요하면 다시 시도합니다. 그 사이 사용자가 다른 앱이나 창으로
  옮겼다면 되돌리지 않습니다. 화면 밖에 놓인 창과 스테이지 매니저 썸네일은 대상에서 뺍니다.
- **창 이동**: 포커스된 창의 위치·크기를 AX로 읽고, 원래 모니터와 대상 모니터의 사용 가능 영역(메뉴 막대·Dock 제외)을
  기준으로 새 프레임을 계산합니다. 크기 → 위치 → 크기 순서로 적용하고 결과를 다시 읽어 검증합니다.
  앱이 이동을 거부하면 원래 크기와 위치로 되돌립니다. 이미 그 모니터에 있지만 화면 밖으로 삐져나온 창은 안으로 끌어옵니다.

## 제거

```bash
make uninstall      # 로그인 항목 해제, 접근성 권한 항목 · 설정 · 앱 삭제
```
