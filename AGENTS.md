## Notion 작업 기록
- DB ID: 이 프로젝트에는 아직 정의되지 않음. "노션에 기록해줘" 요청이 오면 사용자에게 DB ID를 물어본다.
- 공통 절차는 `~/.Codex/AGENTS.md` 참조.

## 코드베이스 문서 (`rules/`, `docs/`)

- 해당 영역을 건드리기 전에 아래 문서를 먼저 읽는다.
- **코드를 고쳐서 `rules/`(또는 `docs/`) 내용과 달라지면, 시키지 않아도 같은 커밋에서 그 문서를 코드에 맞게 고친다.** 새로 생긴 동작·상수·흐름은 추가하고, 없어진 것은 지운다.
- 작업 중 문서가 이미 코드와 틀린 걸 발견해도 바로 고친다.
- **`rules/` 문서를 코드와 대조해 확인하면, 고친 게 없어도 무조건 그 문서 맨 위 `점검일 · 기준 코드` 줄과 `rules/README.md`의 "점검 기록" 표를 그날 날짜로 갱신한다(줄·행이 없으면 새로 넣는다).** 기준 코드는 `git log -1 --format=%h -- shortcuts_example/`.

| 건드리는 영역 | 먼저 읽을 문서 |
|---|---|
| 번들 ID·버전·타깃(공유/액션/인텐트/위젯 확장), 권한 문구, URL 스킴 | `rules/app_metadata.md` |
| rivo.me 글꼴 매니페스트, VisionLink 시그널링, 일일 토큰 한도 | `rules/server_endpoints.md` |
| Firebase(App Check·Remote Config·Crashlytics·Analytics·AI Logic) | `rules/firebase_services.md` |
| Gemini 호출·시스템 프롬프트·웹 검색 판별·로컬 AI/클라우드 분기·토큰 회계 | `rules/gemini_ai.md` |
| 리보 리모컨 BLE, 키 → 동작, 리모컨 모드·빠른 메뉴 | `rules/ble_protocol.md` |
| UserDefaults·앱 그룹·대화 기록·문서 라이브러리·에셋 | `rules/persistence.md` |
| 라이브러리 추가·버전 변경(CocoaPods·SwiftPM), 패치된 Pod | `rules/dependencies.md` |
| 문서 스캔 파이프라인(자동 셔터, 보정, OCR) | `rules/scanner_pipeline.md` |
| 비전링크(페어링·WebRTC·파일/텍스트 수신) | `rules/visionlink.md` |
| 색·모양·간격·컴포넌트·화면 구성·위젯, 접근성 기준 | `docs/design/README.md`부터 |

전체 색인과 작성 원칙: `rules/README.md`. 코드 위치는 파일·타입·함수 이름까지만 적고 줄 번호는 적지 않는다.

## 디자인 문서 점검
- UI 코드(색·모양·간격·배치·컴포넌트·화면 구성·위젯)를 바꾸면 같은 커밋에서 `docs/design/`의 해당 내용도 고친다. 바뀐 부분만 고친 건 점검이 아니므로 점검일은 그대로 둔다.
- `docs/design/` 문서를 코드와 대조해 점검하거나 고치면, 그 문서 맨 위 `점검일 · 기준 코드` 줄과 `docs/design/README.md`의 "점검 기록" 표를 함께 갱신한다.
- 기준 코드 = 대조한 코드 커밋(`git log -1 --format=%h -- shortcuts_example/`). 고친 게 없어도 점검했으면 갱신.
- 문서에는 현재 상태만 적는다(고친 결함·지운 리소스 같은 이력은 커밋 메시지로).
- 코드 위치는 파일·타입·함수 이름까지만 적는다. 줄 번호는 적지 않는다.

## Android VisionCraft와의 동기화
- 이 앱은 `/Users/me/Develop/AndroidProject/VisionCraft`와 같은 제품이다. UI·동작은 Android를 기준으로 맞추고, iPadOS에서 구조적으로 불가능한 것과 사용자가 유지하기로 한 iPad 전용 기능만 예외로 둔다. 예외 목록은 `docs/design/02_accessibility_contract.md`의 "기준을 벗어난 곳"과 `docs/design/05_screen_specs.md`의 "Android와 다른 곳"에 적는다.
- Android 쪽 최근 커밋(`git -C /Users/me/Develop/AndroidProject/VisionCraft log --since=<마지막 대조일> --stat -- app/src/main`)을 대조해 옮길 때는 `docs/design/README.md`의 "Android 기준" 줄을 그 커밋으로 갱신한다.

## 빌드·테스트
- 시뮬레이터는 쓸 수 없다(ML Kit Pod가 arm64 시뮬레이터를 제외). 컴파일 확인은 `xcodebuild -workspace shortcuts_example.xcworkspace -scheme shortcuts_example -destination 'generic/platform=iOS' -configuration Debug CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build`, 실행·테스트는 연결된 iPad에서 한다(`rules/dependencies.md` 참조).
- 새 Swift 파일은 `shortcuts_example/` 아래에 두면 프로젝트에 자동 포함된다(파일 시스템 동기화 그룹).
