## 리보패드·리보탭 공동 작업

- 두 앱은 같은 제품의 iPadOS·Android 구현이다.
  - 리보패드(iPadOS): `/Users/me/Develop/IOSProject/RivoPadApp`
  - 리보탭(Android): `/Users/me/Develop/AndroidProject/VisionCraft`
- **기능·UI·사용자 동작을 바꾸는 요청은 기본적으로 양쪽 프로젝트를 확인하고 함께 반영한다.** 사용자가 한쪽만 지정한 요청이나 플랫폼 전용 구현·설정 변경은 해당 범위에서 처리한다. 공통 기능의 버그라도 상대 앱이 이미 올바르게 동작하면 불필요한 수정은 하지 않고 확인 결과를 보고한다.
- 작업 시작 시 **양쪽 루트의 `AGENTS.md`를 직접 읽는다.** 현재 프로젝트에 자동 로드된 지침만으로 상대 프로젝트의 규칙을 대신하지 않는다. 각 저장소에서 수정할 영역의 지침과 관련 문서(`rules/README.md`, `docs/design/README.md` 등)를 먼저 읽는다.
- 기존 UI·동작의 동기화 기준은 Android다. 새 기능이나 변경 동작은 사용자의 요청을 공통 기준으로 삼아 양쪽에 반영한다. iPadOS에서 구조적으로 불가능한 것과 사용자가 유지하기로 한 iPad 전용 기능은 예외다. 예외는 리보패드의 `docs/design/02_accessibility_contract.md`의 "기준을 벗어난 곳"과 `docs/design/05_screen_specs.md`의 "Android와 다른 곳"에 기록한다.
- 공통 변경은 양쪽의 대응 코드와 문서를 확인하고, 각 프로젝트의 규칙에 따라 필요한 문서도 함께 갱신한다. 요청과 무관한 기존 차이를 일괄 수정하지 않는다.
- 빌드·테스트는 각 플랫폼에서 변경에 맞는 검증을 수행한다. 실행하지 못한 검증은 이유와 남은 확인 사항을 명시하고, 컴파일 성공을 기기 실행 확인으로 대신하지 않는다.
- 완료 보고에는 **리보패드 반영 상태 / 리보탭 반영 상태 / 각 검증 결과 / 남은 차이·확인 사항**을 함께 적는다. 한쪽 반영이 남았으면 공동 작업을 전체 완료로 표시하지 않는다. 한쪽만 변경할 필요가 있었다면 그 이유를 적는다.
- Git 저장소·커밋은 각각 유지한다. 작업 전 양쪽의 기존 변경 사항을 확인하고 보존하며, 이번 작업과 무관한 변경을 커밋에 포함하지 않는다. Git 명령은 대상 저장소를 명시하고, 푸쉬 요청 시 공통 리뷰·사용자 확인 절차를 저장소별로 적용한다.

## 푸쉬 전 교차 리뷰

- **Codex에서 작업한 변경은 항상 푸쉬 전에 Claude Code로 독립 리뷰한다.** Claude에서 작업한 변경은 기존 `~/.claude/CLAUDE.md`의 Codex 리뷰 절차를 따른다.
- 실행·실패 처리·트리아지·푸쉬 확인은 `~/.Codex/AGENTS.md`의 "Claude Advisory Review"를 따른다. 실행: `~/.Codex/scripts/claude-review.sh --base <업스트림 또는 원격 기본 브랜치>`.
- 양쪽 저장소를 각각 리뷰하며, 실제 푸쉬되는 미푸쉬 커밋 전체를 포함한다. 다른 채팅의 미커밋 변경은 포함하지 않는다. 기존 미푸쉬 커밋이 같이 올라가면 사용자에게 알린다.
- Claude 리뷰가 성공한 뒤 실제 버그는 수정하고 다시 리뷰한다. 실패·시간 초과·인증 문제를 리뷰 통과로 취급하지 않는다. 사용자가 해당 푸쉬의 리뷰 생략을 명시한 경우만 생략한다.
- 리뷰 결과를 보고하고 `푸쉬 진행할까요?` 확인 후 푸쉬한다. 리뷰어는 파일 수정·커밋·푸쉬 및 다른 리뷰어 재호출을 하지 않는다.

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

## VisionLink 기능 호환 관리

- VisionLink 기능·메시지·영상 상한을 변경하기 전에 `rules/visionlink_compatibility.md`와 `rules/visionlink.md`를 읽는다.
- 모든 기능에 버전이 있는 기능 ID, 요구 protocol, 세 앱별 최초 지원 버전·빌드, 미지원 시 동작과 호환 테스트를 명시한다. 미출시 버전은 출시됐다고 기록하지 않는다.
- 송신앱·리보탭·리보패드가 협상한 공통 기능만 사용한다. 앱 버전 숫자가 같다는 이유로 기능 지원을 가정하지 않는다. 기능 목록·호환 문서·테스트를 세 앱에 함께 반영한다.
- 공통 호환 규격 문서는 양쪽 `rules/visionlink_compatibility.md`와 송신앱 `docs/visionlink_compatibility.md`에 유지하고 함께 갱신한다.
