# macOS 모니터 단위 포커스/창 이동 앱 — 기획 및 개발 계획

> **구현 결과 메모 (2026-09-28)**: 앱 이름은 **MonitorHop**으로 확정했습니다. 이 Mac에는 Xcode 없이 Command Line Tools만 있어서
> xcodegen/Xcode 프로젝트 대신 **SwiftPM + 번들 조립 스크립트**로 빌드합니다. 외부 의존성(KeyboardShortcuts 등)은 쓰지 않고
> 전역 단축키는 Carbon `RegisterEventHotKey`, 녹화 UI는 자체 구현했습니다. 실제 구조와 사용법은 README.md를 보세요.


앱 이름: 미정 (아래에서는 "앱"으로 표기)

## 1. 목표

macOS 기본 기능에 없는 두 가지를 전역 단축키로 제공하는 가벼운 메뉴바 앱.

| # | 기능 | 동작 | 기본 단축키(안) |
|---|------|------|----------------|
| F1 | N번째 모니터로 포커스 이동 | 해당 모니터의 최상단 창을 활성화하고 마우스 커서를 그 창(없으면 모니터 중앙)으로 옮김 | `Ctrl+Opt+1…6` |
| F2 | 현재 포커스 창을 N번째 모니터로 이동 | 활성 창을 대상 모니터로 옮기고(상대 위치 유지 또는 중앙) 포커스와 커서가 따라감 | `Ctrl+Opt+Shift+1…6` |

부가: 모니터 번호 확인(Identify 오버레이), 단축키 커스터마이즈, 로그인 시 실행.

비목표(1차 범위 밖): 타일링, 창 리사이즈 프리셋, Space(데스크탑) 간 이동, 전체화면 앱 이동.

## 2. 사용자 시나리오

1. 앱 첫 실행 → 손쉬운 사용(접근성) 권한 안내 → 권한 허용 → 메뉴바 아이콘 등장.
2. 메뉴 "모니터 번호 보기" 클릭 → 각 모니터 중앙에 큰 숫자 오버레이가 2초간 표시.
3. `Ctrl+Opt+2` → 2번 모니터의 맨 앞 창이 활성화되고 커서가 이동.
4. `Ctrl+Opt+Shift+1` → 지금 보고 있는 창이 1번 모니터로 옮겨지고 계속 활성 상태.
5. 설정 창에서 단축키 변경, 모니터 순서 변경(드래그), 창 배치 방식 선택.

## 3. 기술 설계

### 3.1 스택
- Swift 5.10+, AppKit + SwiftUI(설정 UI), macOS 13+ 타깃
- 메뉴바 전용 앱 (`LSUIElement = YES`), App Sandbox 비활성 (Accessibility API 사용 때문)
- 프로젝트 생성: `xcodegen` (project.yml → .xcodeproj) 또는 Xcode 직접 생성
- 의존성 (SwiftPM):
  - `sindresorhus/KeyboardShortcuts` — 전역 단축키 등록 + 설정용 레코더 UI
  - `sindresorhus/LaunchAtLogin` 또는 `SMAppService` 직접 사용

### 3.2 모듈 구성
```
App/
  AppDelegate.swift          메뉴바 StatusItem, 권한 체크, 단축키 바인딩
  Permissions.swift          AXIsProcessTrustedWithOptions, 폴링, 온보딩 창
Core/
  ScreenRegistry.swift       모니터 열거·정렬·번호 매핑·변경 감지
  Coordinates.swift          NSScreen(좌하단 원점) ↔ AX/CG(좌상단 원점) 변환
  WindowFinder.swift         CGWindowList로 모니터별 z-order 창 탐색
  AXWindow.swift             AXUIElement 래퍼: 포커스/raise/위치/크기
  FocusMonitorAction.swift   F1 구현
  MoveWindowAction.swift     F2 구현
  CursorWarp.swift           CGWarpMouseCursorPosition
UI/
  IdentifyOverlay.swift      모니터 번호 오버레이 (NSPanel, 투명, 최상위)
  SettingsView.swift         단축키·모니터 순서·배치 옵션·로그인 시작
Tests/
  CoordinatesTests, ScreenOrderingTests, PlacementTests
```

### 3.3 모니터 번호 규칙 (ScreenRegistry)
- 소스: `NSScreen.screens` (0번은 항상 주 디스플레이, 나머지 순서는 불안정)
- 기본 정렬: 화면 프레임 origin.x 오름차순 → 같으면 origin.y 내림차순 (왼쪽→오른쪽, 위→아래)
- 식별자: `NSScreen.deviceDescription["NSScreenNumber"]` (CGDirectDisplayID)로 저장. 사용자가 순서를 바꾸면 ID 배열을 UserDefaults에 저장하고 정렬보다 우선.
- `NSApplication.didChangeScreenParametersNotification` 수신 시 재계산. 저장된 ID가 사라지면 자동 정렬로 폴백.

### 3.4 F1: N번째 모니터로 포커스
1. 대상 `NSScreen` 조회. 없으면 무시(짧은 비프 또는 무반응).
2. `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)` → 앞에서 뒤 순서.
3. 필터: `kCGWindowLayer == 0`, 소유 PID ≠ 자기 자신, 창 bounds 중심이 대상 모니터 프레임(CG 좌표) 안.
4. 첫 번째 창의 PID로 `AXUIElementCreateApplication(pid)` → `kAXWindowsAttribute` 목록에서 위치·크기가 일치하는 AX 창을 찾음.
5. `NSRunningApplication(processIdentifier:).activate(options: [.activateIgnoringOtherApps])` → AX 창에 `kAXMainAttribute = true`, `kAXRaiseAction`.
6. 커서를 창 중앙으로 warp. 창이 없으면 모니터 중앙으로만 warp.
- 옵션: "커서 따라가기" on/off.

### 3.5 F2: 포커스 창을 N번째 모니터로 이동
1. `NSWorkspace.shared.frontmostApplication` → AX app → `kAXFocusedWindowAttribute`.
2. 현재 창의 position/size(AX, 좌상단 원점) 읽기. 현재 모니터 = 창 중심이 속한 화면.
3. 배치 계산 (설정):
   - `relative`(기본): 현재 모니터 visibleFrame 내 상대 비율(x%, y%, w%, h%)을 대상 모니터 visibleFrame에 적용
   - `center`: 크기 유지, 대상 중앙
   - `fill`: 대상 visibleFrame 전체
   - 항상 대상 visibleFrame 안으로 클램프(메뉴바·Dock 회피)
4. AX 쓰기 순서: size → position → size (일부 앱이 최소 크기 제약으로 위치를 튕기는 문제 회피). 쓰기 후 실제 값 재조회로 검증.
5. 실패 처리: `kAXPositionAttribute` settable 아님(전체화면·시스템 창) → 사용자 알림(NSUserNotification 대체: `UNUserNotificationCenter` 또는 메뉴바 아이콘 잠깐 흔들기).
6. 커서를 이동된 창 중앙으로 warp. 포커스는 이미 그 창이므로 유지.

### 3.6 좌표계 주의
- NSScreen: 원점 좌하단, 주 디스플레이 기준. AX/CGWindowList: 원점 좌상단.
- 변환: `y_ax = primary.frame.height - (y_ns + height)`. 단위 테스트로 고정.

### 3.7 권한·배포
- 접근성 권한: 첫 실행 시 `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`, 1초 폴링으로 허용 감지 후 온보딩 창 자동 닫기.
- 서명: 개발 단계는 ad-hoc, 배포 시 Developer ID + notarize. 서명이 바뀌면 접근성 권한을 다시 줘야 하므로 팀 ID 고정.
- 배포: GitHub Releases(.zip) → 이후 Homebrew cask.

## 4. 개발 일정 (마일스톤)

| 단계 | 내용 | 산출물 | 예상 |
|-----|------|-------|-----|
| M0 | 프로젝트 골격: xcodegen, 메뉴바 앱, 권한 온보딩, KeyboardShortcuts 연결 | 아이콘 뜨고 단축키 로그 찍힘 | 1일 |
| M1 | ScreenRegistry + 좌표 변환 + Identify 오버레이 + 단위 테스트 | 모니터 번호 표시 | 1일 |
| M2 | F1 포커스 이동 (WindowFinder, AXWindow, CursorWarp) | 단축키로 모니터 포커스 이동 | 2일 |
| M3 | F2 창 이동 (배치 3모드, 클램프, 검증) | 단축키로 창 이동 | 2일 |
| M4 | 설정 UI: 단축키 레코더, 모니터 순서 드래그, 옵션, 로그인 시 실행 | 설정 창 | 2일 |
| M5 | 엣지 케이스·수동 테스트 매트릭스·서명·릴리스 | v0.1.0 | 2일 |

총 약 10 작업일.

## 5. 테스트 계획

- 단위: 좌표 변환, 모니터 정렬(2·3대, 세로 배치, 스케일 다른 조합), 배치 계산·클램프.
- 수동 매트릭스:
  - 모니터 2대 가로 / 3대 / 노트북 닫힘(clamshell) / 모니터 핫플러그
  - "디스플레이마다 별도의 공간 사용" ON/OFF
  - 대상 모니터에 창 없음 / 최소화된 창만 있음 / 전체화면 앱
  - 이동 대상 앱: Finder, Safari, VS Code, Terminal, Electron 앱, 시스템 설정
  - 단축키 충돌: Rectangle, Hocus 등과 동시 실행

## 6. 리스크와 대응

- CGWindowID ↔ AXUIElement 매칭에 공개 API가 없음 → 위치·크기·타이틀로 매칭, 실패 시 앱 활성화만 수행.
- 일부 앱(Electron, Java)이 AX 위치 설정을 지연 반영 → 쓰기 후 50ms 재시도 1회.
- 전체화면 창은 이동 불가 → 명시적으로 알림하고 스킵.
- 접근성 권한 재부여 문제 → 서명 ID 고정, 온보딩에 "권한 목록에서 삭제 후 재추가" 안내.

## 7. 다음 액션

1. 앱 이름·번들 ID 결정
2. xcodegen 설치 및 M0 골격 생성
3. M1부터 순차 진행
