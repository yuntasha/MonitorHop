# MonitorHop

키보드만으로 **N번째 모니터로 포커스를 옮기고**, **지금 보고 있는 창을 N번째 모니터로 보내는** macOS 메뉴 막대 앱입니다.
macOS 기본 기능에는 모니터 단위 포커스 이동이 없어서 만들었습니다.

| 기능 | 기본 단축키 | 동작 |
|---|---|---|
| N번 모니터로 포커스 이동 | `⌃⌥1` … `⌃⌥4` | 그 모니터에서 가장 앞에 있는 창을 활성화하고 마우스 커서를 그 창으로 옮깁니다. 창이 없으면 커서만 옮깁니다. |
| 현재 창을 N번 모니터로 보내기 | `⌃⌥⇧1` … `⌃⌥⇧4` | 포커스된 창을 그 모니터로 옮기고 포커스와 커서가 따라갑니다. |

- 모니터 번호 순서 변경: 설정 › 모니터 탭에서 드래그하거나 ↑↓ 버튼으로 바꿉니다. 모니터를 뺐다가 다시 꽂아도 순서를 기억합니다.
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
- 다른 앱이 이미 쓰는 조합이면 단축키 옆에 ⚠︎ 표시가 나오고 메뉴에도 경고가 뜹니다. 다른 조합으로 바꾸세요.
- 단축키에는 ⌘ · ⌃ · ⌥ 중 하나 이상이 들어가야 합니다 (F1–F20은 단독 사용 가능).
- 전체 화면(별도 Space) 창은 macOS 제약상 옮길 수 없습니다. 전체 화면을 끈 뒤 옮기세요.

## CLI

앱 번들 안의 실행 파일을 스크립트(Raycast, 단축어, skhd 등)에서 호출할 수 있습니다.

```bash
MH=/Applications/MonitorHop.app/Contents/MacOS/MonitorHop
$MH --list          # 모니터 목록(번호 순)과 각 모니터의 맨 앞 창
$MH --list-json     # 같은 정보를 JSON으로
$MH --focus 2       # 2번 모니터로 포커스
$MH --move 1        # 현재 창을 1번 모니터로
$MH --identify      # 모니터 번호 오버레이
$MH --check         # 권한 · API · 단축키 등록 진단
```

터미널에서 직접 실행하면 권한은 **터미널 앱** 기준으로 판단됩니다. MonitorHop의 권한으로 실행하려면
`open -g -n -W --stdout /dev/stdout /Applications/MonitorHop.app --args --move 1` 처럼 `open`을 거치세요.

## 개발

```bash
make build          # 디버그 빌드
make test           # 단위 테스트 (Swift Testing, 42개)
make app            # build/MonitorHop.app 조립 + 서명
make run            # build/ 의 앱 실행
make check          # 진단 출력
scripts/integration-test.py   # 실제 창을 띄워 포커스/이동을 끝까지 검증 (모니터 2대 + 권한 필요)
```

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
  StatusMenuController.swift, HUD.swift, PermissionWindow.swift, LoginItem.swift, CLI.swift
```

### 동작 원리

- **포커스 이동**: 창 서버의 앞→뒤 목록(`CGWindowListCopyWindowInfo`)에서 대상 모니터의 첫 번째 일반 창을 찾고,
  접근성 API 창과 CGWindowID로 정확히 매칭합니다. 그 창을 main으로 만들고(`AXMain`),
  앱을 앞으로 가져온 뒤(`SetFrontProcessWithOptions`, 앞 창만) `AXRaise` 합니다.
  macOS 14부터 `NSRunningApplication.activate`는 백그라운드 앱의 요청을 무시할 수 있어서 이 순서를 씁니다.
  200ms 뒤 실제로 전환됐는지 확인하고, 아니면 공개 API 경로로 한 번 더 시도합니다.
- **창 이동**: 포커스된 창의 위치·크기를 AX로 읽고, 원래 모니터와 대상 모니터의 사용 가능 영역(메뉴 막대·Dock 제외)을
  기준으로 새 프레임을 계산합니다. 크기 → 위치 → 크기 순서로 적용하고 결과를 다시 읽어 검증합니다.

## 제거

```bash
make uninstall      # 앱, 설정, 접근성 권한 항목 삭제
```
