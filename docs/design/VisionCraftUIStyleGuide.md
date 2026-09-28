# VisionCraft iOS UI 스타일 가이드

안드로이드 VisionCraft(`AndroidProject/VisionCraft/docs/design/`)와 같은 토큰·컴포넌트 체계를
iPadOS 앱에서 어떻게 구현하는지 정리한 문서다. 새 화면이나 다이얼로그를 만들 때 이 문서의
컴포넌트를 먼저 쓰고, 없을 때만 새로 만든다. 새로 만든 컴포넌트는 `DesignSystem/`에 넣고
이 문서에 추가한다.

코드 위치

| 파일 | 내용 |
| --- | --- |
| `shortcuts_example/DesignSystem/VisionCraftUI.swift` | 색 토큰, 섹션 헤더, 홈 액션 패널/리스트, 아이콘 타일, 화면 모디파이어, 뒤로가기 버튼 |
| `shortcuts_example/DesignSystem/VisionCraftSettingsUI.swift` | 홈 설정 그룹/그리드/타일, 라디오 선택 다이얼로그 |
| `shortcuts_example/DesignSystem/VisionCraftDialogs.swift` | 선택 다이얼로그 카드, 스크림, 선택 항목 행 |
| `shortcuts_example/DesignSystem/VisionCraftChatUI.swift` | Android 채팅 말풍선, 입력창·입력 패널, 그라데이션, 응답 대기 표시 |

---

## 1. 색 토큰 (`VisionCraftUI`)

안드로이드 `VCColors`와 1:1로 맞춘다. 라이트/다크는 `UIColor` 트레이트로 자동 전환된다.

| 역할 | iOS 토큰 | Light | Dark | 안드로이드 |
| --- | --- | --- | --- | --- |
| Primary | `VisionCraftUI.primary` | `#5A7FE6` | `#7C9EFF` | `Primary` / `PrimaryVariant` |
| Background | `.background` | `#F5F5F5` | `#0F0F0F` | `Surface0` |
| Surface | `.surface` | `#FFFFFF` | `#1A1A1A` | `Surface1` |
| Surface Variant | `.surfaceVariant` | `#E8E8E8` | `#252525` | `Surface2` |
| Outline | `.outline` | `#DADADA` | `#303030` | `Surface3` |
| Text Primary | `.primaryText` | `#1A1A1A` | `#E8E8E8` | `TextPrimary` |
| Text Secondary | `.secondaryText` | `#616161` | `#9E9E9E` | `TextSecondary` |
| Success | `.success` | `#03DAC6`(근사) | 동일 | `Success` |
| Warning | `.warning` | `#FFB74D`(근사) | 동일 | `Warning` |

규칙

- Primary는 넓게 칠하지 않는다. 주요 버튼, 선택 상태, 아이콘 틴트, 포커스에만 쓴다.
- Primary를 배경으로 쓸 때는 `opacity(0.10~0.16)`, 테두리는 `opacity(0.28~0.45)`.
- 한 화면에 강한 액센트는 1개. 삭제/오류는 시스템 `.red`, 연결됨은 `.green`을 그대로 쓴다.
- 카메라 프리뷰 위의 컨트롤은 토큰 대신 흰색 + `UIColor(white: 0.145)` 계열 회색을 쓴다(아래 6절).

## 2. 타이포그래피

시스템 Dynamic Type을 쓰고, 안드로이드 스케일과 다음처럼 대응시킨다.

| 용도 | iOS | 안드로이드 |
| --- | --- | --- |
| 화면 제목 | `navigationTitle` (large) | `headlineMedium` 24sp |
| 섹션 헤더 (`VisionCraftSectionHeader`) | `.title2.semibold` | `titleLarge` 22sp |
| 다이얼로그 제목 | `.title2.bold` | `titleLarge` |
| 메뉴 섹션 제목 | `.title3.bold` | `titleMedium` 18sp |
| 리스트/항목 제목 | `.headline` | `titleMedium` / `bodyLarge` |
| 항목 설명 | `.subheadline` (+`.medium`) | `bodyMedium` 16sp |
| 버튼 라벨 | `.headline` | `labelLarge` 16sp |
| 메타/캡션 | `.caption` | `labelMedium` 14sp, 12sp 미만 금지 |

## 3. 간격·모양

- 기본 그리드 8pt. 화면 좌우 패딩 24pt (`VisionCraftUI.horizontalPadding`).
- 섹션 사이 28pt (`VisionCraftUI.sectionSpacing`), 설정 그룹 사이 20pt.
- 본문 최대 폭 760pt (`VisionCraftUI.contentWidth`).
- 모서리 반경
  - 카드/리스트 컨테이너: 16~20pt (`visionCraftSurfaceCard`, `VisionCraftActionList` 20)
  - 다이얼로그 카드: 24pt
  - 다이얼로그 안 항목·버튼·입력창: 12~14pt
  - 아이콘 타일: `size * 0.28`
  - 항상 `style: .continuous`.
- 카드 안에 카드를 넣지 않는다. 그룹 안의 반복 항목은 배경 없는 행 + `Divider`로 나눈다.
- 테두리는 1pt, `outline.opacity(0.5~0.9)`. 그림자는 다이얼로그에만.

## 4. 화면 모디파이어

| 모디파이어 | 쓰는 곳 | 하는 일 |
| --- | --- | --- |
| `.visionCraftNavigationScreen()` | ScrollView 기반 화면 | 배경, 틴트, 툴바 배경 `background` 고정 |
| `.visionCraftListScreen()` | `List`/`Form` 화면 | 위와 같음 + `scrollContentBackground(.hidden)` |
| `.visionCraftRouteBackButton()` | 앱 라우트 destination(앱 파일에서 일괄 적용) | 시스템 뒤로가기 숨기고 `VisionCraftBackButton` 배치 |
| `.visionCraftHandlesBackNavigation()` | 자체 상단바가 있는 문서 뷰어 | 라우트 뒤로가기 버튼 생략 |
| `.visionCraftCameraScreen()` | 카메라 프리뷰가 전체를 채우는 화면 | 툴바 배경 투명, 뒤로가기 버튼 `overlay` 스타일 |

뒤로가기 버튼(`VisionCraftBackButton`)은 `chevron.left.circle` 30pt.
`.standard`는 Primary 색, `.overlay`는 흰색 + 그림자(배경판 없음).

## 5. 컴포넌트

### 5.1 섹션 헤더 `VisionCraftSectionHeader`
`.title2.semibold`, 아래 12pt. 접근성 헤더 트레이트.

### 5.2 주요 액션 패널 `VisionCraftPrimaryActionPanel`
홈 상단 1개만. Primary 12% 배경 + 28% 테두리, 반경 20.
아이콘 타일 52pt(흰 아이콘/Primary 배경), 제목 `.title2.bold`, 설명 `.body` secondary.
버튼 두 개(prominent + bordered) 높이 52, 반경 14. 폭이 좁으면 세로로 쌓인다.

### 5.3 액션 리스트 `VisionCraftActionList`
홈의 기능 진입 목록. `surface` 배경, 반경 20, `outline` 80% 테두리.
행: 아이콘 타일 48(액센트 14% 배경) + 제목 `.headline` + 설명 `.subheadline.medium` + chevron.
최소 높이 80, 행 사이 `Divider` (왼쪽 78pt 들여쓰기).
액센트는 상태 표현에만 바꾼다(예: 리모컨 연결 상태 색).

### 5.4 아이콘 타일 `VisionCraftIconTile`
SF Symbol을 둥근 사각형 안에. 기본 40pt/22pt. 항상 `accessibilityHidden`.
색 조합은 세 가지만 쓴다.

| 상황 | 아이콘 | 배경 |
| --- | --- | --- |
| 강조(주요 액션) | 흰색 | Primary |
| 일반 | Primary | Primary 14% |
| 비활성 | secondaryText 50% | surfaceVariant 60% |

### 5.5 홈 설정 그룹 `VisionCraftSettingsGroup` / `VisionCraftSettingsGrid`
그룹 제목 `.subheadline.semibold` secondary. 카드 반경 16, 테두리 50%, 안쪽 패딩 20/12.
그리드는 2열, 접근성 큰 글자에서는 1열.

타일 세 종류(모두 `surfaceVariant` 40% 배경, 반경 12, 최소 높이 112):

- `VisionCraftSettingSwitchTile` — 라벨 + 힌트 + 커스텀 스위치(켬 `#34C759`, 끔 `#B8BDC7`).
- `VisionCraftSettingValueTile` — 라벨 + 현재 값 박스(`surface`, 높이 44). 탭하면 선택 다이얼로그.
- `VisionCraftColorSettingTile` — 라벨 + 배경/글자색 반반 미리보기.

### 5.6 `Form` 기반 설정 화면 (`AppSettingsView`)
시스템 `Form` + `.visionCraftListScreen()`. 섹션 헤더/푸터 텍스트를 반드시 둔다.
행 종류: `Toggle`, `Picker`(인라인 메뉴), `Stepper`, `Slider`+`LabeledContent`, `NavigationLink`, `Button`.
파괴적 동작은 마지막 섹션에 `role: .destructive` 단독 버튼 + `confirmationDialog`.

### 5.7 라디오 선택 다이얼로그 `VisionCraftSelectionDialog`
값 하나를 고르는 용도(언어, 속도, 단계, 색 조합). 최대 폭 440, 목록 최대 높이 520.
행: `largecircle.fill.circle`/`circle` + 제목, 높이 52. 배경 없음(라디오라 구분이 필요 없음).
아래 `취소` 버튼(surfaceVariant 55%, 반경 12).

### 5.8 선택 항목 다이얼로그 `VisionCraftDialogCard` + `VisionCraftDialogOptionRow`
"열기", "저장", "질문 방식"처럼 **서로 다른 동작** 중 하나를 고를 때. 안드로이드
`AlertDialog(24dp) + DialogActionButton`에 대응한다.

```
VisionCraftDialogCard(title: "열기", onDismiss: close) {
    VisionCraftDialogOptionRow(
        title: "클립보드",
        subtitle: "복사해 둔 텍스트를 붙여 넣습니다.",
        systemImage: "doc.on.clipboard",
        isPrimary: true,
        action: openClipboard
    )
    VisionCraftDialogOptionRow(title: "문서", systemImage: "doc.text", action: openDocument)
}
```

카드
- 스크림 `black 52%`, 탭하면 닫힘. 카드 `surface`, 반경 24, `outline` 테두리, 그림자(22%, 24, y12).
- 제목 `.title2.bold`, 선택 메시지 `.subheadline` secondary.
- 항목 사이 10pt. 마지막에 `취소` 버튼(높이 52, surfaceVariant 55%, Primary 글자). 항목 안에 취소를 또 넣지 않는다.
- 최대 폭 480, 바깥 패딩 24. `.zIndex(100)`, `accessibilityAddTraits(.isModal)`.

항목 행 — **항목마다 배경과 테두리를 가져야 한다.** 배경 없는 `Label` 나열은 구분이 안 된다.
- 아이콘 타일 44 + 제목 `.headline` + 설명 `.subheadline` + chevron. 최소 높이 64, 반경 14.
- 일반: `surfaceVariant` 45% 배경, `outline` 90% 테두리.
- `isPrimary`(추천 항목, 최대 1개): Primary 10% 배경, Primary 45% 테두리, 아이콘 흰색/Primary.
- `isEnabled == false`: 글자·아이콘 50~55% 흐림, 버튼 비활성.
- 설명(subtitle)은 동작 결과를 한 문장으로. 없어도 되지만 항목이 3개 이상이면 넣는다.

쓰는 곳: 홈 `텍스트 편집뷰` 열기 다이얼로그, 텍스트 편집뷰의 열기/저장 다이얼로그.
문서 스캔 검토의 `저장 방식 선택`/`질문 방식 선택`은 같은 규격(카드 24, 항목 배경)을 따르되
아직 자체 구현이다. 손댈 때 이 컴포넌트로 옮긴다.

### 5.8a 상태 배너 `VisionCraftStatusBanner`
홈 맨 위 한 개만. 목록 행이 아니라 "지금 상태"를 보여주는 카드다(`DesignSystem/VisionCraftStatusBanner.swift`).
- 왼쪽 64pt 원: 상태 색 16% 채움 + 55% 링, 아이콘 28pt, 오른쪽 아래 14pt 상태 점(surface 테두리).
- 가운데: 작은 라벨(`.subheadline.semibold`, 상태 색) → 상태 문구(`.title2.bold`) → 설명(`.subheadline` secondary).
- 배경: 상태 색 20%→6% 대각선 그라데이션 위에 `surface`, 반경 22, 상태 색 40% 테두리 1.5pt, 상태 색 14% 그림자.
- 상태 색: 연결됨 `success`, 진행 중 `warning`(아이콘 variableColor 애니메이션), 오류 `.red`, 대기 `primary`.
- 카드 전체가 버튼. `accessibilityElement(children: .combine)` + hint.

### 5.9 전체 화면 메뉴 (`TextEditorMenuOverlay`)
문서 뷰어의 햄버거 메뉴. 시스템 시트 대신 `background` 색 전체 화면 + 제목 `.title.bold` + 닫기(X, 44pt, surfaceVariant).
내용은 `surface` 카드(반경 16) 하나 안에 섹션(`.title3.bold` 제목) → 행(높이 56, 아이콘 타일 40) → `Divider(leading 68)`.
토글 행은 행 전체가 버튼이고 오른쪽 `Toggle`은 표시용(`allowsHitTesting(false)`).

### 5.10 시스템 다이얼로그
- 파괴적 확인, 동의 확인: SwiftUI `confirmationDialog`(제목 표시) + `role: .destructive` / `.cancel`.
- 오류: `alert` 제목 + 메시지 + `확인`.
- 위 두 경우 외에는 커스텀 카드(5.7, 5.8)를 쓴다. 시스템 `Menu`는 쓰지 않는다.

### 5.11 입력·카드
- 텍스트 입력: `.visionCraftInputSurface()` (surfaceVariant 58%, 반경 14, outline 85%).
- 정보 카드: `.visionCraftSurfaceCard(cornerRadius:outlineOpacity:)`.
- 빈 상태: `ContentUnavailableView` + 다음 행동 안내 문장.

### 5.12 로컬 AI 채팅

Android `a_chat.xml`, `item_sent_message.xml`, `item_received_message.xml`과 해당 배경 drawable을 기준으로 한다.
채팅은 일반 카드 규격 대신 다음 전용 규격을 사용한다.

- 새 대화는 “대화를 시작합니다. 무엇이든 말씀해주세요.” 안내 말풍선으로 시작한다. 안내는 모델 입력·저장 대화에 넣지 않는다.
- 목록 배경은 `background`, 행 배경은 투명. 위 20pt / 아래 12pt 여백.
- 말풍선은 글 길이에 맞는 폭, 글자는 기본 32pt에서 Dynamic Type에 따라 확대한다.
- 사용자: 왼쪽 72pt / 오른쪽 20pt, 안쪽 가로 20pt / 세로 14pt, 행 위아래 5pt.
  `#5A7FE6` → `#7C9EFF` 대각선 그라데이션, 흰 글자, 모서리 22pt 중 오른쪽 아래만 6pt.
- AI: 왼쪽 20pt / 오른쪽 32pt, 안쪽 가로 18pt / 세로 14pt, 행 위아래 6pt.
  `surface` 채움 + `outline` 1pt, 모서리 22pt 중 왼쪽 위만 6pt.
- 첨부·요약 칩: 높이 42pt, 반경 22pt, `#7C9EFF` 10% 채움 / 27% 테두리, 최소 폭 78 / 96pt.
- 입력 패널: 위쪽 모서리 24pt, `surface` 채움 + `outline` 1pt, 안쪽 좌우 20pt / 위 14pt / 아래 22pt.
- 입력창: 최소 높이 52pt, 반경 28pt, `surfaceVariant` 채움 + `outline` 1pt, 안쪽 가로 22pt / 세로 8pt.
- 마이크는 52pt 원형 그라데이션 버튼. iPad의 명시적인 `전송` 버튼은 높이 52pt 캡슐로 유지한다.
- 응답 대기 중 AI 행에 120×4pt 진행 표시를 둔다. 준비됨·완료 같은 평상시 상태 줄은 생략하고 오류·음성·첨부 상태는 표시한다.

## 6. 카메라 화면 (문서 스캔·돋보기·실시간 읽기·이미지 설명)

- 라우트에 `.ignoresSafeArea()` + `.visionCraftCameraScreen()`. 툴바 배경이 사라지고 흰 뒤로가기 chevron만 카메라 위에 뜬다.
- 화면 안에 별도 X/닫기 버튼을 두지 않는다. 예외: 실시간 읽기의 하단 `닫기` 텍스트 버튼(리모컨 없이 멈출 수단).
- 컨트롤 버튼은 카메라 위에 바로 놓는다. 버튼들을 감싸는 패널/둥근 사각형을 만들지 않는다.
- 원형 버튼: 56pt, 배경 `UIColor(white: 0.145)`, 흰 아이콘 24pt semibold. 셔터: 70pt 흰색 + 그림자.
- 텍스트 버튼(스캔 촬영/닫기): 높이 52, `UIButton.Configuration.filled()` 흰색 14% 또는 투명 + 흰 22% 테두리, `cornerStyle = .large`.
- 상태 라벨(문서 스캔·실시간 읽기 공통): 반투명 캡슐(`#252525` 15%, 반경 22, Primary 20% 테두리), 흰 17pt bold, 상단 safe area + 18, 좌우 24. 실시간 읽기는 "글자를 찾는 중입니다." / "확인 중: …" / "읽는 중입니다."를 여기에 표시한다.

## 7. 접근성

- 모든 커스텀 버튼은 `accessibilityLabel`, 상태가 있으면 `accessibilityValue`, 결과가 불명확하면 `accessibilityHint`.
- 행 단위 컴포넌트는 `accessibilityElement(children: .combine)` + `.isButton`.
- 장식 아이콘(`VisionCraftIconTile`, chevron)은 `accessibilityHidden(true)`.
- 다이얼로그 루트에 `.isModal`, 스크림은 `accessibilityHidden`.
- 터치 영역 최소 44pt. 텍스트는 Dynamic Type 시스템 폰트만(고정 크기는 카메라 오버레이와 확대 라벨에만).
- 모든 사용자 문구는 한국어 키를 `AppLocalization.string`으로 감싸고 `en.lproj`/`ja.lproj`에 항목을 추가한다.

## 홈 UI — Android VisionCraft 원본 (2026-09-15)

사용자 요청에 따라 홈과 사용 안내의 Liquid Glass를 제거했다. Android `VcSoftHome.kt`,
`ComposeTheme.kt`, `MainScreen.kt`, `UserGuideScreen.kt`의 표면·간격·타이포그래피를 따른다.
이 절은 홈에 한해 기존 표면 규칙보다 우선한다. 기능 구성·설정 값·라우팅은 iOS 그대로 유지한다.

- `VisionCraftHomeUI` 배경: 흰색 / 검정. 표면 `#FAFAFA` / `#171717`.
  본문 `#283546` / `#F0F4FA`, 보조 문구 `#536176` / `#BBC6D7`.
- 홈 카드: 반경 22pt, 최소 높이 88pt, 가로 20pt / 세로 18pt 패딩, 카드 간격 16pt.
  불투명 표면에 위·왼쪽 밝은 그림자와 아래·오른쪽 어두운 그림자를 각각 적용한다.
  평상시 blur 5pt / offset ±2pt, 누를 때 2pt / ±0.75pt 및 어두운 색 14% 혼합.
  글라스, 배경 블러, 투명 재질, 누름 확대·축소를 사용하지 않는다.
- 밝은 그림자: `#FFFFFF` / `#2B2B2B`, 어두운 그림자: `#CCD1D9` / 검정.
  대비 증가 설정에서는 추가 테두리를 제공한다.
- 섹션 제목 22pt semibold, 아래 간격 7pt와 3pt 컬러 밑줄. 카드 제목 18pt,
  설명 16pt. `visionCraftAndroidText`는 Android 기준 크기에 Dynamic Type을 적용한다.
- 홈 도움말: 리모컨 아래 크림색 표면 `#FFF9EF` / `#211D18`, 보조 문구
  `#6F604F` / `#D4C4AF`, 40pt 원형 화살표. 기존 홈 기능 순서를 유지한다.
- 설정 그룹: 반경 16pt, 1pt 테두리. 값 선택은 반경 14pt soft surface.
  스위치는 Android Material 크기 52×32pt, 초록/회색 트랙, 흰색 손잡이를 그린다.
  기존 전체 타일 버튼의 동작과 VoiceOver 읽기 순서를 유지한다.
- 홈 선택창: 반경 24pt 불투명 표면, 선택 행 12pt 반경·primary 15% 배경,
  오른쪽 아래의 불투명 primary 버튼. 텍스트 가져오기 창은 `usesHomeStyle: true`로 적용한다.

## 사용 안내 — Android 화면 구성 (2026-09-15)

- Android 기본 페이지 팔레트 `VisionCraftUI`를 사용한다. 앱 내용은 기존 iPad 안내를 유지한다.
- 상단은 평평한 뒤로가기 화살표와 제목. 소개 문구 없이 상황별/기능별 토글부터 시작한다.
  토글은 반경 16pt 배경 + 11pt 선택 칸, 선택 칸은 primary 색으로 채운다.
- 검색창은 사용자 요청대로 토글 바로 아래에 유지한다.
- 목록은 기능 아이콘, 텍스트와 chevron, 64pt 이상 높이, 세로 18pt 패딩, 구분선으로 구성한다.
- 기능별 목록은 기능명만 표시하고, 기능명 아래 상황 설명 문구는 표시하지 않는다.
- 상세 안내는 기능명, 제목, 번호가 있는 단계, 반경 12pt 팁 카드와 기능 실행 버튼 순서다.
  버튼은 반경 12pt 불투명 primary 표면이며 글라스를 사용하지 않는다.
- 사용자 요청으로 목록·상세 기능 아이콘, 팁의 전구, 실행 버튼의 화살표를 복원했다.
- 안내 데이터는 `Help/VisionCraftGuide.json`, `en.lproj/VisionCraftGuide.json`,
  `ja.lproj/VisionCraftGuide.json`에 같은 ID/액션을 갖는 20개 기능과 6개 문제 해결로 유지한다.
- 전체 설명서·업데이트·개인정보·라이선스는 목록 하단에서 계속 열 수 있다.
- 본문 줄 수를 제한하지 않고 Dynamic Type을 유지한다. 장식 아이콘은 VoiceOver에서 제외한다.
