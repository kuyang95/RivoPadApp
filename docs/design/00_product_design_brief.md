# Product Design Brief

점검일: 2026-09-29 · 기준 코드: `babc3875`+작업 트리 · Android 기준: `c6a03f0`

## Product

VisionCraft는 저시력 사용자, 화면 내용을 빠르게 듣고 싶은 사용자, 문서와 책을 음성/AI로 다루는 사용자를 위한 접근성 보조 앱이다. Android 앱과 iPadOS 앱은 같은 제품이다. 핵심 기능은 AI 대화(문서·사진·클립보드 첨부, 대화기록), 카메라(확대·라이트·필터와 모드: 문서 스캔, 실시간 문자 읽기, 이미지 분석, AI 질문하기, 사진 분석), 텍스트뷰어, 데이지/EPUB 플레이어, 비전링크(스마트폰 연동), 음성 질의·명령, 리보 리모컨 빠른 메뉴, 홈 화면 위젯이다. 문서 작업(엑셀·한글 편집)도 두 앱에 있고, 워드 편집은 iPadOS에만 있다.

## Design North Star

VisionCraft는 "복잡한 기능을 조용하고 확실하게 실행하는 도구"처럼 느껴져야 한다. 앱은 과하게 장식적이기보다 선명하고, 반복 사용이 편하며, 음성/시각/터치 피드백이 서로 충돌하지 않아야 한다.

## Audience Assumptions

- 사용자는 작은 글자, 낮은 대비, 복잡한 리스트, 너무 많은 같은 모양 버튼에서 쉽게 피로해질 수 있다.
- 사용자는 기능을 탐색하기보다 "지금 필요한 작업"으로 바로 가고 싶어 한다.
- 일부 사용자는 VoiceOver, 큰 글씨(Dynamic Type), 시스템 다크 모드, 음성 명령, 홈 화면 위젯을 함께 쓸 수 있다.
- 앱의 성공은 기능 수가 아니라 실행 경로의 짧음, 실패 이유의 명확함, 다시 시도하기 쉬움에 있다.

## Product Principles

1. Primary action first
   - 화면마다 가장 중요한 작업 하나를 첫 시야에 둔다.
   - 보조 작업은 가까운 위치에 두되, 같은 무게로 경쟁시키지 않는다.

2. Accessible by default
   - 글자 크기는 Dynamic Type을 따르는 `visionCraftAndroidText`(Android `sp`)로, 레이아웃은 pt(`dp`)로 지정한다.
   - 터치 타깃은 최소 48pt를 기본값으로 둔다(`VisionCraftUI.minTouchTarget`).
   - 텍스트 대비는 4.5:1 이상, 아이콘/경계/상태 표시 대비는 3:1 이상을 목표로 한다.

3. Calm density
   - 홈과 설정은 기능을 많이 보여주되, 카드 장식으로 화면을 조각내지 않는다.
   - 리스트는 스캔하기 좋게 제목, 보조 정보, 액션 위치를 반복 패턴으로 고정한다.

4. State is visible
   - 켜짐/꺼짐, 듣는 중, 처리 중, 실패, 권한 필요 같은 상태는 색만으로 표현하지 않는다.
   - 실패 시 효과음만 내지 않고 화면 띠, 텍스트, 필요하면 TTS로 이유를 알려준다.

5. Respect the system
   - 시스템 큰 글씨, 다크 모드, 동작 줄이기, 접근성 설정을 존중한다.
   - 앱 자체 설정은 시스템 설정을 대체하지 않고, VisionCraft 고유의 세밀한 조절만 제공한다.

## Current App Shape

- 앱 전체 모양(soft UI): `shortcuts_example/DesignSystem/VisionCraftUI.swift`(토큰·기초 컴포넌트), `VisionCraftHomeUI.swift`(면·버튼·목록 카드·타일·글자 스타일), `VisionCraftDialogs.swift`(카드 다이얼로그), `VisionCraftSettingsUI.swift`(설정 패널·값 고르기 다이얼로그), `VisionCraftChatUI.swift`(채팅), `VisionCraftStatusBanner.swift`(리모컨 상태 아이콘)
- 앱 색: `Assets.xcassets/AccentColor`(남색 잉크). 시스템 파랑은 쓰지 않는다.
- 홈(목록형·카테고리형)과 전체 설정: `shortcuts_example/HomeView.swift` — `HomeView`, `HomeAllSettingsView`, `HomeSettingsPanel`, `HomeSettingsDialogs`, `HomeUpdateNotesSection`
- 화면 경로: `shortcuts_example/AppRouter.swift` `AppRoute`, 화면 연결은 `shortcuts_exampleApp.swift`
- 컴포넌트·토큰·화면 규격: 이 폴더의 `03`~`05`

## Redesign Tone

- Avoid: heavy bordered cards everywhere, decorative gradients, tiny secondary text, unexplained icons, many same-weight buttons, system-default blue.
- Prefer: strong hierarchy, generous but not wasteful spacing, high contrast, compact action groups, clear toggle states, quiet surfaces with one intentional accent.
