# Component Catalog

점검일: 2026-09-29 · 기준 코드: `babc3875`+작업 트리 · Android 기준: `c6a03f0`

앱에 실제로 그려지고 있는 UI 스타일을 전수 조사해서 이름을 붙인 목록이다. 이름은 Android `04_component_specs.md`의 `Vc*` 이름을 기준으로 하고, 각 항목의 `구현`이 iPadOS 코드 위치다. Android와 규격이 같으면 값을 되풀이하지 않고 "Android와 같음"으로 적는다.

## 읽는 법

- 한 항목 = 한 스타일. 여러 화면에서 같은 모양이면 한 항목으로 묶고 `같은 스타일`에 나머지 구현을 적는다.
- 새 화면을 만들 때는 `구현`에 적힌 공용 코드를 쓴다. 같은 모양을 새로 그리지 않는다. 시스템 `.bordered`/`.borderedProminent`와 시스템 색은 새 코드에 쓰지 않는다.
- 새 컴포넌트를 만들기 전에 이 목록을 먼저 본다. 여기 있는 스타일로 안 되는 경우에만 새로 만들고, 만들면 이 문서에 추가한다.

## 이름 규칙

- Android 이름 `Vc*` ↔ iPadOS 타입 `VisionCraft*`. 변형은 뒤에 붙인다: `VcButton` / `VcButtonAccent` / `VcButtonInk` = `VisionCraftAndroidButtonStyle()` / `(emphasized: true)` / `(filled: true)`.
- 화면에 종속된 스타일만 앞에 영역을 붙인다: `VcCam*`(카메라 미리보기 위, `VisionCraftCameraUI`), `VcLink*`(비전링크), `VcWidget*`(위젯).

---

# 1. 기초

## VcSoftColors — 앱 기본 색

- 구현: `DesignSystem/VisionCraftUI.swift` `VisionCraftUI`, `DesignSystem/VisionCraftHomeUI.swift` `VisionCraftHomeUI`. 값은 `03_design_tokens.md`. Android와 같음.
- 시스템 tint: `Assets.xcassets/AccentColor` = 잉크 남색(라이트 `#283546`, 다크 `#F0F4FA`).

## VcAccent — 강조색 두 가지

- **주황**(`VisionCraftUI.accent`): 뭔가를 실행하는 동작. 촬영, 작업, 보낸 말풍선, 마이크.
- **남색 잉크**(`VisionCraftUI.primary`를 면으로): 확인·이동 같은 차분한 주 동작. 카메라 모드 버튼, 새 대화, 다이얼로그 닫기.
- 파랑(`VisionCraftUI.linkBlue`)은 UI 면에 쓰지 않는다. 구분 표시(섹션 밑줄, 비전링크 연결 원)에만 남는다.

## VcShape — 모서리

- 구현: `RoundedRectangle(cornerRadius:, style: .continuous)`. Compose `HomeContinuousShape`와 같은 연속 곡선이라 값이 같으면 모양도 같다.
- 쓰는 값: 10(뱃지) / 12(값 고르기 줄·색 견본) / 14(버튼) / 16(패널·아이콘칸) / 20(모드 알약) / 22(카드·타일) / 24(값 고르기 다이얼로그) / 28(카드 다이얼로그)

## VcSoftSurface — 떠 있는 면

- 구현: `VisionCraftHomeUI.swift` `View.visionCraftHomeSurface(cornerRadius:fill:outlined:outlineColor:raised:)` (`VisionCraftHomeSurfaceModifier`)
- 기본: 면 `surface`, 1.5pt 테두리 `outline`(대비 높이기 설정에서는 2pt), 양방향 그림자(흐림 5, 오프셋 2: 왼쪽 위 `highlight`, 오른쪽 아래 `shadow`)
- 눌림(`VisionCraftHomePressStyle`이 환경값으로 전달): 흐림 2·오프셋 0.75, 면을 그림자 쪽으로 14% 어둡게. 물결 효과 없음.
- `raised: true`: 테두리 없음, 흐림 10·오프셋 5, `raisedTop`→`raisedBottom` 세로 기울기. 2x2 타일 전용.
- `outlined: false`: 테두리 없는 터치 영역. `outlineColor`: 현재 값 강조(강조색).
- `fill`: 안내 카드처럼 면 색만 바꿀 때.

---

# 2. 카드와 목록

## VcActionRow — 목록 한 줄 (가장 많이 쓰는 카드)

- 구현: `VisionCraftHomeUI.swift` `VisionCraftHomeActionList(items:useLogoAccents:)` (홈 목록), `VisionCraftDialogs.swift` `VisionCraftDialogOptionRow(title:subtitle:systemImage:isPrimary:isEnabled:badge:showsIconTile:accent:action:)` (다이얼로그 안)
- 생김새: VcSoftSurface + 모서리 22, 최소 높이 88, 안쪽 20/18, 요소 간격 16. 왼쪽 VcIconTile Large(다이얼로그·카테고리) 또는 회색 28pt 아이콘(홈 목록형), 가운데 제목(18 SemiBold)과 설명(16 보조글자), 오른쪽 VcChevron.
- 상태: 눌림. `badge`(`VisionCraftActionItem.badge` / `VisionCraftDialogOptionRow.badge`)가 있으면 테두리가 강조색이 되고 화살표 자리에 VcBadge. `isPrimary`도 테두리 강조색. `isEnabled == false`면 아이콘 칸·글자를 흐리게.
- 스크린리더: "제목. 설명"(뱃지가 있으면 "제목, 뱃지. 설명") 한 덩어리, 역할 버튼.
- 쓰는 곳: 홈 목록형(`HomeView.swift`), 카테고리 다이얼로그, 이미지 분석·열기·카메라 모드·작업 다이얼로그, 데이지 여는 화면.

## VcNoticeCard — 안내 카드 (크림색)

- 구현: `VisionCraftHomeUI.swift` `VisionCraftHomeGuideEntry`. Android와 같음(면 `guideSurface`, 40pt 원형 화살표 칩 `guideArrow`, 화살표 `guideAccent`).
- 스크린리더: 자식 글자를 한 덩어리로, 힌트 "열기".

## VcTile — 2x2 큰 타일

- 구현: `VisionCraftHomeUI.swift` `VisionCraftHomeCategoryGrid(categories:columns:onOpen:)`, 제목 `VisionCraftHomeTileTitle`, 모델 `VisionCraftHomeCategory`
- 생김새: VcSoftSurface `raised` + 모서리 22. 세로 화면 2열, 가로 화면(폭 > 높이) 4열(`HomeView.categoryHomeContent`가 `columns`를 정함). 간격 16, 높이 = 너비 × 5/4(`aspectRatio(4/5)`). 한 화면에 맞도록 너비를 화면 높이로도 제한한다. 위쪽 그림, 아래 제목.
- 제목: 타일 안쪽 너비(타일 폭 − 36)의 17%를 글자 크기로 하고 `UIFontMetrics`로 글자 크기 설정을 반영. 가장 긴 낱말이 한 줄에 들어갈 때까지만 줄인다(×0.97).
- 그림: 남는 칸 안에서 가장 큰 정사각 squircle(모서리 = 한 변의 22.5%, 좌우 24 여백)을 `tileArtBackground`로 깔고 가운데 70% 크기로 `Assets.xcassets/HomeTile*` 아이콘(Android `home_tile_art_*.webp` 768px 한 벌, 라이트·다크 공용)을 올린다.
- 상태: 눌림. 항목이 하나뿐인 타일은 다이얼로그 없이 바로 실행.
- 스크린리더: 항목이 하나면 "제목. 기능 설명", 여럿이면 "제목. 항목 이름들", 역할 버튼.

## VcPanel — 묶음 패널

- 구현: `VisionCraftUI.swift` `View.visionCraftSurfaceCard(cornerRadius: 16, outlineOpacity: 0.7)`; 오류 변형 `View.visionCraftErrorPanel()`(1.5pt 강조색).
- 생김새: 면 `surface`, 모서리 16, 1pt 보조글자색 70% 테두리, 그림자 없음.
- 설정 그룹 `VisionCraftSettingsGroup(title:)`(`VisionCraftSettingsUI.swift`)은 이 면에 안쪽 20/12, 제목(14 Medium 보조글자색 + heading)을 더한 것.
- 쓰는 곳: 설정 그룹(`HomeSettingsPanel`), 텍스트뷰어 메뉴판, 데이지 요약·오류 카드, 사진 결과 패널.

---

# 3. 버튼

## VcButton — 기본 버튼

- 구현: `VisionCraftHomeUI.swift` `VisionCraftAndroidButtonStyle()`
- 생김새: VcSoftSurface + 모서리 14, 최소 높이 52, 안쪽 12/14, 글자 16 SemiBold 가운데 정렬, 눌리면 14% 어두워짐.
- 쓰는 곳: 텍스트 열기 화면 세 버튼, 사진 다시 찍기·다른 사진, 문서 스캔 저장.

## VcButtonAccent — 실행 버튼 (주황)

- 구현: `VisionCraftAndroidButtonStyle(emphasized: true)` — 면·테두리 강조색, 글자 배경색(`onPrimary`), 최소 64.
- 쓰는 곳: 사진 분석·문서 스캔 `작업`, 채팅 다이얼로그 확인.

## VcButtonInk — 이동·확정 버튼 (남색)

- 구현: `VisionCraftAndroidButtonStyle(filled: true)` — 면·테두리 글자색, 글자 배경색, 최소 64.
- 쓰는 곳: 새 대화(대화 목록), 사용법 상세의 실행 버튼. 한 화면에 잉크 버튼은 하나만.

## VcDialogClose — 다이얼로그 닫기

- 구현: `VisionCraftDialogs.swift` `VisionCraftDialogCloseButton`. 기능·카테고리 다이얼로그와 값 선택 다이얼로그가 함께 쓴다.
- 생김새: 남색 잉크 면, 모서리 12, 최소 너비 104·높이 52, 좌우 안쪽 20. 다이얼로그 오른쪽 아래에 둔다.

## VcValueButton — 값 고르는 버튼

- 구현: `VisionCraftSettingsUI.swift` `VisionCraftSettingValueTile(label:value:action:)` 안의 값 부분. VcButton과 같고 전폭 + 오른쪽 끝 14 안쪽에 아래 VcChevron, 글자 좌우 36.
- 스크린리더: 부모 타일이 "항목, 값" + 힌트 "값 바꾸기"로 읽는다.

## VcIconButton — 제목 줄 아이콘 버튼

- 구현: `VisionCraftUI.swift` `VisionCraftIconButton(systemImage:label:tint:statusDot:action:)`
- 생김새: 52pt 정사각 터치 영역, 모서리 16, 면·테두리 없음, 아이콘 26.
- 변형 `VcStatusIconButton`: `VisionCraftStatusBanner.swift` `VisionCraftHomeRemoteStatusIcon(eyebrow:title:subtitle:systemImage:accent:action:)` — 같은 크기에 `accent` 색 아이콘과 오른쪽 위 8pt 점. 연결 `success`, 연결 중 `warning`, 끊김 보조글자색. 읽기 "리모컨 연결. <상태>. <설명>".

---

# 4. 작은 부품

## VcIconTile — 아이콘 칸

- 구현: `VisionCraftUI.swift` `VisionCraftIconTile(systemImage:tint:tileSize:isEnabled:)`, 크기 `VisionCraftIconTileSize`: `.large` 52/모서리 16/아이콘 30, `.medium` 44/14/22.
- 강조색 14% 바탕. 비활성: 바탕 글자색 6%, 아이콘 글자색 38%.

## VcBadge — 현재 값 뱃지

- 구현: `VisionCraftHomeUI.swift` `VisionCraftBadge(text:)` — 강조색 채움, 모서리 10, 12/6 여백, 16 Bold, 글자 배경색.

## VcChevron — 화살표

- 구현: `VisionCraftHomeUI.swift` `VisionCraftChevron(down:)` — SF `chevron.right` 18 / `chevron.down` 16, medium, 아이콘색.

## VcSectionHeader — 섹션 제목

- 구현: `VisionCraftHomeUI.swift` `VisionCraftHomeSectionHeader(title:tone:bottomSpacing:)` — 22 SemiBold + heading, 7 띄우고 3pt 밑줄(`SectionTone` 색), 아래 14(카드 다이얼로그 안 20 = 기본 14 + 추가 6). overlay 밑줄의 3pt 높이도 레이아웃에 확보한다.

## VcSwitch / VcSwitchRow — 스위치 줄

- 구현: `VisionCraftSettingsUI.swift` `VisionCraftSettingSwitchTile(label:hint:isOn:)` — 최소 112, 안쪽 12, 배경 없음(VcPanel 안). 직접 그린 52×32 캡슐(켬 `switchOn`, 끔 `switchOff`, 손잡이 흰색).
- 이름과 설명 사이 4pt, 설명 묶음과 스위치 사이 최소 12pt. 바깥 스택에는 추가 간격을 주지 않는다.
- 스크린리더: 역할 토글(`.isToggle`) + 값 "켬/끔" + 힌트.

## VcValueRow — 값 줄

- 구현: `VisionCraftSettingValueTile`, 색 조합은 `VisionCraftColorSettingTile(label:theme:action:)`(높이 48 색 견본 `VisionCraftColorSwatch`, 1pt `swatchOutline`, 모서리 12).
- 항목 이름과 값 버튼/색 견본 사이 최소 10pt. 바깥 스택에는 추가 간격을 주지 않는다.
- 격자: `VisionCraftSettingsGrid`(`VisionCraftSettingsGridLayout`) — 넓은 화면·보통 글자 크기에서 두 열, 홀수 개면 마지막 칸은 전폭.

---

# 5. 다이얼로그

## VcOptionDialog — 값 고르기

- 구현: `VisionCraftSettingsUI.swift` `VisionCraftSelectionDialog(title:options:selectedID:onSelect:onDismiss:notices:markSelected:rowSpacing:dismissTitle:)`, 줄 모델 `VisionCraftSelectionOption(id:title:supportingText:fontName:swatch:accessibilityLabel:)`, 안내 `VisionCraftSelectionNotice`.
- 생김새: 모서리 24, 최대 너비 440. 제목 22 SemiBold(화면이 열릴 때 `screenChanged`로 읽고 요소로는 숨김). 줄은 꽉 찬 너비, 모서리 12, 안쪽 16, 18pt. 현재 값인 줄만 강조색 15% 바탕 + 강조색 글자 + SemiBold. `markSelected`면 오른쪽 ●. 닫기 = 공용 VcDialogClose. 제목 아래 16, 목록과 닫기 버튼 사이 24, 다이얼로그 바깥면까지 좌우·아래 24 여백(Android Material3 1.2.1 `AlertDialog`의 `TitlePadding`·`TextPadding` 기준).
- 줄을 누르면 호출한 쪽이 적용하고 닫는다(글꼴은 받는 동안 열어 둠). 내용 높이로 화면 중앙에 놓고, 화면보다 긴 목록만 스크롤한다.
- 줄 변형: `supportingText`(아래 작은 글), `fontName`(글꼴 미리보기), `swatch`(바탕·글자 색 견본, 읽기는 `accessibilityLabel`).
- 쓰는 곳: 홈·전체 설정(`HomeSettingsDialogs`): 음성 속도·언어·단계·홈 구성·앱 글꼴·색 조합.

## VcCardDialog — 기능 고르기

- 제목 밑줄 아래에서 본문까지 20pt(`VisionCraftUI.cardDialogHeaderBottomSpacing`). Android `VcHomeCategoryDialog`의 14dp + 6dp와 같다. 카메라 모드·사진 작업·문서 스캔 저장/작업·Excel/HWP 더보기·셀 도구처럼 내부 목록을 따로 감싼 경우도 `VisionCraftUI.actionRowSpacing`(16pt)을 사용한다.

- 구현: `VisionCraftDialogs.swift` `VisionCraftDialogCard(title:message:cancelTitle:maxWidth:tone:onDismiss:content:)`, 카테고리용 `VisionCraftHomeCategoryDialog(category:onDismiss:)`
- 생김새: 모서리 28, 배경색 면 + 1.5pt 테두리, 최대 너비 560, 안쪽 24. 머리는 VcSectionHeader(밑줄 `tone`, 아래 20), 몸통은 VcActionRow 목록(간격 16, 아이콘은 `logoAccent(index)`), 오른쪽 아래 공용 VcDialogClose(위 24). 내용 높이로 화면 중앙에 놓고, 화면보다 길 때만 스크롤한다. 열릴 때 제목을 `screenChanged`로 읽는다. 스크림 탭·escape로 닫힘.
- 언제: 고르는 대상이 아이콘과 설명이 있는 기능일 때. 값 하나를 고르는 거라면 VcOptionDialog.
- 쓰는 곳: 카테고리 타일, 이미지 분석(촬영하기/사진에서), 열기(클립보드/이미지/문서), 카메라 모드, 사진·문서 스캔 작업, 채팅 첨부, 엑셀·한글 문서 작업.

---

# 6. 화면 뼈대

## VcScreenTitleRow — 화면 제목 줄

- 구현: `VisionCraftUI.swift` `VisionCraftScreenTitleRow(title:onBack:actions:)` — 24 Bold + heading. `onBack`이 있으면 왼쪽에 48pt `VisionCraftBackButton`, `actions`에 오른쪽 `VisionCraftIconButton`.
- 쓰는 곳: 홈 제목 줄(`HomeView.homeTitleRow`, 앱 이름 + 상태 아이콘 + 설정), 전체 설정(`HomeAllSettingsView`), 대화 목록, 채팅, 텍스트뷰어 메뉴. 이 화면들은 시스템 내비게이션 바를 숨긴다.

## VcScreen — 화면 여백

- 구현: `VisionCraftUI.swift` `View.visionCraftScreenPadding(bottom:)` — 좌우 24, 위 12, 아래 24. 홈은 위 44/아래 32를 직접 쓴다.

## 뒤로 가기

- 구현: `VisionCraftUI.swift` `VisionCraftBackButton(style:tint:action:)` 48×48, `chevron.left.circle`을 30×30으로 직접 그린다. 툴바에서도 이 크기를 유지한다. 라우트·사용법·문서 도구·리모컨 메뉴에서 함께 쓰고, 카메라에서는 흰색 + 그림자다.

---

# 7. 채팅

| 이름 | 구현 | 생김새 |
| --- | --- | --- |
| `VcChip` | `LLM/LLMContentView.swift` 빠른 칩 | 모서리 14, 보조면 채움, 테두리 없음. 48 높이, 15 Bold. 비활성 = 투명도 0.45 |
| `VcBubbleSent` | `DesignSystem/VisionCraftChatUI.swift` `bubbleShape(isUser: true)` | 모서리 22/22/22/6, 강조색 채움, 글자 32 |
| `VcBubbleReceived` | `bubbleShape(isUser: false)` | 모서리 6/22/22/22, 면 채움 + 1.5 테두리 |
| `VcInputField` | `VisionCraftChatUI.swift` 입력칸 | 모서리 28 알약, 보조면, 테두리 없음, 52. 안내 글자색 `VisionCraftUI.inputPlaceholder` |
| `VcInputBar` | `VisionCraftChatUI.swift` 입력 영역 | 위쪽 모서리만 24, 면 채움, 테두리 없음 |
| `VcMicButton` | `LLMContentView.swift` 마이크 | 52 원, 강조색, 아이콘 배경색. 말하는 중 = 아이콘·설명만 바뀜 |
| 진행 막대 | `VisionCraftChatUI.swift` `VisionCraftChatTypingIndicator` | 120×4 무한 막대 |

- 보낸 사람 이름: 13 Bold, 보조글자색, 자간 0.03(보낸 쪽·받은 쪽 같음).
- iPadOS 전용: 여러 줄 입력칸과 주황 "전송" 버튼(사용자가 유지하기로 함).

---

# 8. 카메라 (미리보기 위, 테마 안 따름)

색은 `VisionCraftCameraUI`로 고정: 면 `#171717`, 눌림 `#3A3A3A`, 테두리·글자 흰색, 보조글자 `#D6DCE6`, 켬 `#FFA05C` + 글자 `#2B1200`, 모드 면 `#283546` + 테두리 `#F0F4FA`.

## VcCamControl — 조작 버튼

- 구현: `CameraTools/MagnifierViewController.swift` (격자·라이트·전환·설정 타일)
- 생김새: 모서리 16, 너비 76(iPad 96), 최소 높이 68/80(화면이 낮으면 52·아이콘 생략), 1.5 흰 테두리. 아이콘 28 + 16 SemiBold 라벨, 토글은 아래 줄에 상태 글자(켬/끔, 후면/전면).
- 높이는 아이콘·라벨·상태의 실제 크기와 위아래 8 여백으로 계산한다. 최소 높이 이상으로 내용만큼만 커지고 남는 화면을 채우지 않는다. 접힌 조작 목록은 배치에서 뺀다.
- 상태: 눌림 / 켬(강조색 채움 + 어두운 글자 + 상태 굵게) / 강조 테두리 3(설정을 접었는데 뭔가 켜져 있을 때)
- 스크린리더: 토글은 스위치 + 값, 나머지는 버튼. 읽는 순서 모드 → 촬영 → 설정 → 전환 → 라이트 → 격자.

## VcCamModePill — 모드 버튼

- 구현: `CameraTools/VisionCraftCameraViews.swift` `VisionCraftCameraModePill`, 공용 제목 줄 `VisionCraftCameraHeader`(뒤로 가기와 간격 8). 기본 카메라·문서 스캔·실시간 문자 읽기 모두 안전 영역 위쪽에서 8, 왼쪽에서 16 띄운다.
- 생김새: 모서리 20 알약, 남색 채움, 2.5 `#F0F4FA` 테두리, 흰 글자. 조절 아이콘 24 + `모드: 이름`(이름만 Bold) + 아래 화살표. 최소 높이 56(iPad 64). 왼쪽 위(뒤로 가기 옆), 읽는 순서 첫 번째.

## VcCamShutter — 촬영 버튼

- 구현: `CameraTools/MagnifierViewController.swift` 촬영 버튼
- 생김새: 흰 원 → 3 여백 → `#171717` 링 → 4 여백 → 채움. 100(iPad 124, 낮은 화면 80). 안에 "촬영"/"분석\n촬영"/"질문\n촬영".
- 상태: 눌림 `#D0D0D0`, 이미지 분석·AI 질문 모드에서는 강조색 채움.

## VcCamStatusOverlay — 안내 띠

- 구현: 사진 분석(`CameraTools/MagnifierView.swift` `PhotoReviewView`), 문서 스캔 결과(`DocumentScan/DocumentScanRootView.swift`), 카메라 이미지 분석 결과
- 생김새: `VisionCraftUI.overlay`(글자색 88%) 면, 모서리 14, 글자는 배경색 17~18 굵게. 바뀔 때마다 읽는다(`UIAccessibility.post(.announcement)`).
- 카메라 미리보기 위 문서 스캔 상태 알약은 별개: 거의 투명한 어두운 면 + 옅은 파란 테두리, 모서리 22, 화면 아래.

---

# 9. 비전링크

| 이름 | 구현 | 생김새 |
| --- | --- | --- |
| `VcLinkOrb` | `VisionLink/VisionLinkView.swift` 연결 대기 원 | 64 원, 파랑(`linkBlue`) 채움 + 1.5 테두리. 바깥 원이 64에서 88까지 커졌다 작아짐(동작 줄이기면 정지) |
| `VcLinkNode` | 연결됨 노드 | 58 원, 강조색 20% 또는 `linkSuccess` 16% 채움 + 1 테두리, 선 위를 오가는 점 |
| `VcLinkChip` | 상태 칩 | 모서리 22, 반투명 면 `#E6FAFAFA`, 1 반투명 테두리, 44 |
| `VcLinkHudCard` | 수신 진행·완료·최근 수신 카드 | 모서리 16, 반투명 면 `#F2FAFAFA`, 1 테두리, 그림자 16 |

---

# 10. 데이지 / 플레이어

| 이름 | 구현 | 생김새 |
| --- | --- | --- |
| `VcSheet` | `Reader/EPUBReaderView.swift` 목차·검색·설정 시트 | `.sheet` + `presentationBackground(surface)`, 글자 `text` |
| `VcPlayerBar` | `Reader/EPUBReaderView.swift` `playbackBar` | 면 `surface`, 1 보조글자 70% 위 테두리, 그림자 16 |
| `VcTransportButton` | 재생 | 56 원, 강조색 채움. 비활성 40% |
| `VcTransportIcon` | 이전·다음 | 48, 아이콘 28. 비활성 보조글자색 |
| `VcPill` | 이동 단위, 테마 칩 | 완전 둥근 알약, 강조색 14% 채움. 선택 시 2 강조 테두리 |
| `VcSlider` | 위치 슬라이더 | 손잡이·지나온 트랙 강조색, 남은 트랙 보조글자 30%. 재생 불가 38% |

---

# 11. AI 문서 진입 패널과 안 쓰는 레거시

`VisionCraftPrimaryActionPanel`은 Android `FileSelectScreen`이 쓰는 `VcPrimaryActionPanel`에 대응한다. iPadOS의 `AIDocumentSelectionView`에서도 문서 안내와 새 대화·대화기록 버튼을 묶는 머리 패널로 쓴다. 제목과 설명 사이에는 추가 간격을 두지 않는다.

`VisionCraftUI.swift`의 `VisionCraftSectionHeader`, `VisionCraftActionList`와 `VisionCraftStatusBanner.swift`의 `VisionCraftStatusBanner`는 옛 스타일이다. 새 화면에서 쓰지 않는다.
