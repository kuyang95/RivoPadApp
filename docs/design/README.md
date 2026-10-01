# VisionCraft iPadOS Design Reference Pack

Android 기준: `c6a03f0` (Android `docs/design/` 점검 기준 코드 `0878501`)

이 폴더는 VisionCraft iPadOS UI를 AI가 이어서 고치기 쉽게 만든 디자인 기준 문서 모음이다. Android VisionCraft의 `docs/design/`과 같은 구성이고, 두 앱은 같은 제품이므로 규격도 같다. iPadOS에서 구조적으로 못 만드는 것과 사용자가 유지하기로 한 iPad 전용 기능만 예외로 적는다. 새 화면을 만들거나 기존 화면을 손볼 때는 이 순서로 읽는다.

1. `00_product_design_brief.md`: 제품 성격, 사용자, 디자인 원칙.
2. `01_reference_matrix.md`: Mobbin/Page Flows/Apple HIG/접근성 레퍼런스를 어떤 용도로 참고할지.
3. `02_accessibility_contract.md`: 절대 깨면 안 되는 접근성 기준.
4. `03_design_tokens.md`: 색, 타이포그래피, 간격, 형태 토큰.
5. `04_component_specs.md`: 앱에 실제로 쓰이는 공용 컴포넌트 목록과 이름(`VisionCraft*`). 새 화면을 만들기 전에 여기서 쓸 스타일을 고른다.
6. `05_screen_specs.md`: 홈(목록형/카테고리형), 전체 설정, 채팅, 데이지, 카메라와 모드, 사진 분석, 문서 스캔, 비전링크, 위젯별 화면 구성과 Android와 다른 곳.
7. `06_ai_redesign_prompt.md`: 다음 AI 작업자에게 그대로 줄 수 있는 작업 프롬프트.
8. `07_mobbin_reference_picks.md`: Mobbin 레퍼런스 선정.

## 코드를 바꿀 때

UI 코드(색·모양·간격·배치·컴포넌트·화면 구성·위젯)를 바꾸면 같은 커밋에서 이 폴더의 해당 내용도 고친다. 바뀐 부분만 맞춘 것은 점검이 아니므로 점검일은 그대로 둔다.

## 점검 기록

점검 = 문서 내용을 지금 코드와 대조해 맞는지 확인하고, 틀린 곳을 고친 것. 읽기만 한 것은 점검이 아니다.

| 문서 | 점검일 | 기준 코드 |
| --- | --- | --- |
| `00_product_design_brief.md` | 2026-09-29 | `babc3875`+작업 트리 |
| `01_reference_matrix.md` | 2026-09-29 | `babc3875`+작업 트리 |
| `02_accessibility_contract.md` | 2026-09-29 | `babc3875`+작업 트리 |
| `03_design_tokens.md` | 2026-09-29 | `babc3875`+작업 트리 |
| `04_component_specs.md` | 2026-09-29 | `babc3875`+작업 트리 |
| `05_screen_specs.md` | 2026-09-29 | `babc3875`+작업 트리 |
| `06_ai_redesign_prompt.md` | 2026-09-29 | `babc3875`+작업 트리 |
| `07_mobbin_reference_picks.md` | 2026-09-29 | — |

점검할 때마다:

1. 문서 맨 위 `점검일 · 기준 코드` 줄과 이 표의 같은 줄을 함께 고친다.
2. 점검일은 점검한 날, 기준 코드는 대조한 코드의 커밋(`git log -1 --format=%h -- shortcuts_example/`). 커밋하지 않은 작업 트리를 대조했으면 `<커밋>+작업 트리`로 적고 커밋 뒤에 바꾼다.
3. 고친 내용 없이 맞는 것만 확인했어도 날짜와 기준 코드를 갱신한다.
4. 문서는 지금 상태만 적는다. 무엇을 고쳤는지는 커밋 메시지에 남긴다.
5. 코드 위치는 파일 이름과 타입·함수 이름까지만 적는다. 줄 번호는 코드를 조금만 고쳐도 틀어지므로 적지 않는다.
6. Android와 대조했으면 맨 위 "Android 기준" 줄을 그 커밋으로 갱신한다. Android 쪽 변경 보기: `git -C /Users/me/Develop/AndroidProject/VisionCraft log <Android 기준>..HEAD --oneline -- app/src/main docs/design`

기준 코드 이후 바뀐 코드 보기: `git log <기준 코드>..HEAD --oneline -- shortcuts_example`

## Working Rule

- 레퍼런스 앱 화면을 복사하지 않는다. 구조, 밀도, 액션 배치, 상태 표현만 추출한다.
- VisionCraft는 접근성 보조 앱이다. 예쁜 것보다 먼저 읽기 쉽고, 누르기 쉽고, 설명이 명확해야 한다.
- 화면마다 핵심 작업을 하나씩 선명하게 둔다. 기능을 숨기기보다 덜 복잡하게 묶는다.
- 모든 화면은 `shortcuts_example/DesignSystem/`의 토큰(`VisionCraftUI`, `VisionCraftHomeUI`)과 공용 컴포넌트를 먼저 쓴다. 시스템 `.bordered`/`.borderedProminent` 버튼과 시스템 색(`.red`, `.blue` …)은 새 코드에 쓰지 않는다.
- 카메라 미리보기 위 버튼만 테마를 따르지 않는 고정색(`VisionCraftCameraUI`)을 쓴다.

## Source Links

- Mobbin: https://mobbin.com/
- Page Flows: https://pageflows.com/
- Apple HIG Accessibility: https://developer.apple.com/design/human-interface-guidelines/accessibility
- Apple HIG Layout: https://developer.apple.com/design/human-interface-guidelines/layout
- Apple HIG Widgets: https://developer.apple.com/design/human-interface-guidelines/widgets
- Android Accessibility(원본 기준): https://developer.android.com/design/ui/mobile/guides/foundations/accessibility
- WCAG 2.2: https://www.w3.org/TR/WCAG22/
