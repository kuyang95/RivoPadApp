# Design Tokens

점검일: 2026-09-29 · 기준 코드: `babc3875`+작업 트리 · Android 기준: `c6a03f0`

앱 전체가 홈의 soft UI 한 벌을 쓴다. 색·모양·면을 새로 정하지 말고 아래 토큰을 쓴다. 값은 Android `docs/design/03_design_tokens.md`와 같다. 컴포넌트별 규격은 `04_component_specs.md`.

## 토큰 파일

| 무엇 | iPadOS |
| --- | --- |
| 기본 색 | `DesignSystem/VisionCraftUI.swift` `VisionCraftUI`, `DesignSystem/VisionCraftHomeUI.swift` `VisionCraftHomeUI` |
| 앱 강조색(시스템 tint) | `Assets.xcassets/AccentColor.colorset` = 잉크 남색 |
| 카메라 고정색 | `VisionCraftUI.swift` `VisionCraftCameraUI` |
| 모서리 | `RoundedRectangle(cornerRadius:, style: .continuous)` (연속 곡선) |
| 면 | `.visionCraftHomeSurface(...)`, `.visionCraftSurfaceCard(...)` |
| 글자 | `.visionCraftAndroidText(size, weight:, relativeTo:)` |

## 색

### 기본 팔레트 (VisionCraftUI / VisionCraftHomeUI)

| 역할 | 라이트 | 다크 | iPadOS |
| --- | --- | --- | --- |
| 배경 | `#FFFFFF` | `#000000` | `VisionCraftUI.background` |
| 면 | `#FAFAFA` | `#171717` | `.surface` |
| 보조면(입력칸·칩) | `#F0F2F5` | `#2B2B2B` | `.surfaceVariant` |
| 글자 | `#283546` | `#F0F4FA` | `.primaryText` (= `.primary`) |
| 보조글자 | `#536176` | `#BBC6D7` | `.secondaryText` |
| 테두리 | `#536176` | `#BBC6D7` | `.outline` |
| 아이콘 | `#526580` | `#C9D5E7` | `.icon` |
| 강조(주황) | `#C0521B` | `#FFA05C` | `.accent` |
| 강조 위 글자 | `#FFFFFF` | `#000000` | `.onAccent` |
| 잉크 위 글자 | `#FFFFFF` | `#000000` | `VisionCraftHomeUI.onPrimary` (= 배경색) |
| 안내 띠 | 글자색 88% | 글자색 88% | `.overlay` |
| 그림자 / 밝은 면 | `#CCD1D9` / `#FFFFFF` | `#000000` / `#2B2B2B` | `VisionCraftHomeUI.shadow` / `.highlight` |
| 오류 | `#CF6679` | `#CF6679` | `.error` |
| 입력칸 안내 글자 | `#616E7F` | `#8A97A8` | `.inputPlaceholder` |
| 연결됨 / 연결 중 | `#247548` / `#8B6517` | `#83D4A1` / `#E8C978` | `.success` / `.warning` |
| 비전링크 성공 / 경고 | `#28765A` / `#976026` | `#99D8BA` / `#E7BE80` | `.linkSuccess` / `.linkWarning` |
| 색 견본 테두리 | `#DADADA` | `#303030` | `VisionCraftHomeUI.swatchOutline` |
| raised 면 위 / 아래 | `#FDFDFD` / `#EDEFF1` | `#252525` / `#111111` | `VisionCraftHomeUI.raisedTop` / `.raisedBottom` |

### 강조색 쓰임

- **주황**: 뭔가를 실행하는 동작. 촬영, `작업`, 분석, 보낸 말풍선, 마이크. `VisionCraftAndroidButtonStyle(emphasized: true)`.
- **남색 잉크**(글자색을 면으로): 확인·이동 같은 차분한 주 동작. 새 대화 버튼, 카메라 모드 버튼, 다이얼로그 닫기. `VisionCraftAndroidButtonStyle(filled: true)`. 앱 `AccentColor`도 이 색이라 시스템 컨트롤의 tint가 파랑이 아니다.
- **파랑**은 UI 면에 쓰지 않는다. 구분 표시에만 쓴다: 카메라 섹션 밑줄(`SectionTone.camera` `#356AA8`/`#9EC5FF`), 비전링크 연결 원·선(`VisionCraftUI.linkBlue`), 카드 다이얼로그 아이콘 색 중 하나.
- 한 화면에 강한 강조는 하나. 오류·삭제 같은 시스템 상태는 예외(`VisionCraftUI.error`).
- 라이트 주황 `#C0521B`는 흰 글자 4.7:1, 면(`#FAFAFA`) 위 글자로 4.5:1이 되도록 정한 값이다. 더 밝게 바꾸지 않는다.

### 영역 구분 색 (섹션 밑줄, `VisionCraftHomeUI.SectionTone`)

AI 보라 `#7655B4`/`#C6B1F5` · 카메라 파랑 `#356AA8`/`#9EC5FF` · 읽기 초록 `#28765A`/`#99D8BA` · 연동 청록 `#2A7A86`/`#8FD6E0` · 설정 갈색 `#976026`/`#E7BE80` · 업데이트·중립 회색 `#69778B`/`#B7C5D9`

### 로고 색 (`VisionCraftHomeUI.logoAccents`, `logoAccent(i)`)

카드 다이얼로그 아이콘 타일이 순서대로 쓴다: 빨강 `#B5403C`/`#F2A09B`, 주황 `#B2611F`/`#EFB07F`, 노랑 `#917511`/`#E6C45C`, 초록 `#4A7A2C`/`#A6D68A`, 파랑 `#356AA8`/`#9EC5FF`, 보라 `#7655B4`/`#C6B1F5`.

### 화면 전용 색

- 안내 카드: 면 `#FFF9EF`/`#211D18`, 보조글자 `#6F604F`/`#D4C4AF`, 화살표 칩 `#FFE1C9`/`#483326`, 화살표 `#885024`/`#F3C9A4` (`VisionCraftHomeUI.guide*`).
- 타일 그림 뒤 squircle: `#E6E8EA`/`#DBE2EC` (`VisionCraftHomeUI.tileArtBackground`).
- 카메라 미리보기 위 버튼: 테마를 따르지 않는 고정색(`VisionCraftCameraUI`). 면 `#171717`, 눌림 `#3A3A3A`, 테두리·글자 흰색, 보조글자 `#D6DCE6`, 켬 `#FFA05C` + 글자 `#2B1200`, 모드 버튼 `#283546` + 테두리 `#F0F4FA`, 촬영 눌림 `#D0D0D0`.
- 스위치: 켬 트랙 `#34C759`, 끔 트랙 `#B8BDC7` (`VisionCraftHomeUI.switchOn/Off`).
- 비전링크 HUD·연결 원·노드 색은 `VisionLink/VisionLinkView.swift` 위쪽에 한 번만 정의한다.

## 글자

`visionCraftAndroidText(size, weight:, relativeTo:)`가 Android `sp`처럼 Dynamic Type 배율을 따르고, 앱 글꼴 설정(`AppFontCatalogStore.fontName`, 환경값 `visionCraftAppFontName`)을 적용한다. 자간은 0.

| 크기 / 굵기 | 쓰는 곳 |
| --- | --- |
| 24 / Bold | 화면 제목(`VisionCraftScreenTitleRow`), 업데이트 버전 |
| 22 / SemiBold | 섹션 제목(`VisionCraftHomeSectionHeader`), 다이얼로그 제목 |
| 18 / SemiBold | 목록 카드 제목, 카메라 모드 버튼 |
| 18 / Regular | 다이얼로그 줄, 설정 항목 이름, 본문 |
| 16 / Regular | 목록 카드 설명, 안내 글, 업데이트 항목 |
| 16 / SemiBold | 버튼 글자, 값 버튼 |
| 16 / Bold | 뱃지 |
| 14 / Medium | 설정 그룹 이름, 카메라 버튼 상태 줄, 업데이트 날짜 |
| 13 / Bold | 채팅 보낸 사람 이름 |

- 2x2 타일 제목은 타일 안쪽 너비에 비례해 정한다(`VisionCraftHomeTileTitle`).
- 채팅 말풍선 32pt, 텍스트뷰어 본문은 사용자가 고른 크기.
- 12pt 아래로는 쓰지 않는다(`.caption2` 금지). 사용자 글꼴 크기 설정을 따른다.

## 간격

- 화면 좌우 24pt, 위 12pt, 아래 24pt(`.visionCraftScreenPadding()`). 홈은 위 44pt, 아래 32pt.
- 목록 카드 사이 16pt(`VisionCraftUI.actionRowSpacing`), 섹션 사이 28pt. 제목 글자와 밑줄 사이 7pt, 밑줄 높이 3pt. 밑줄 아래는 일반 섹션 14pt, 카드 다이얼로그 20pt(기본 14 + 추가 6).
- 카드 안쪽 20/18pt, 패널 안쪽 20/12pt, 다이얼로그 안쪽 24pt. 값 선택 다이얼로그는 제목 아래 16pt, 목록과 닫기 버튼 사이 24pt. 설정 항목 이름과 값/색 견본 사이 최소 10pt, 설명 묶음과 스위치 사이 최소 12pt(행 높이에 여유가 있으면 늘어남).
- 누를 수 있는 것은 최소 48pt. 카드 88pt, 버튼 52pt(주 버튼 64pt), 제목 줄 아이콘 52pt.

## 모서리

모두 `RoundedRectangle(cornerRadius:, style: .continuous)`(연속 곡선).

| 값 | 쓰는 곳 |
| --- | --- |
| 10 | 뱃지 |
| 12 | 값 고르기 다이얼로그 안 줄, 색 견본 |
| 14 | 버튼(`VisionCraftAndroidButtonStyle`), 안내 띠, 채팅 칩, 값 버튼 |
| 16 | 패널(`visionCraftSurfaceCard`), 목록 아이콘 칸(Large), 제목 줄 아이콘 버튼, 카메라 조작 버튼 |
| 20 | 카메라 모드 버튼 |
| 22 | 목록 카드, 2x2 타일, 말풍선, 업데이트 카드 |
| 24 | 값 고르기 다이얼로그(`VisionCraftSelectionDialog`), 채팅 입력 영역 위쪽 |
| 28 | 카드 다이얼로그(`VisionCraftDialogCard`), 채팅 입력칸 |

## 면과 테두리

- 떠 있는 면(`visionCraftHomeSurface`): 1.5pt 테두리 + 양방향 그림자(흐림 5, 오프셋 2). 누르면 흐림 2·오프셋 0.75, 면이 그림자 쪽으로 14% 어두워진다. 물결 효과는 쓰지 않는다(`VisionCraftHomePressStyle`).
- 2x2 타일만 테두리 없이 큰 그림자(흐림 10·오프셋 5)와 위아래 밝기 기울기로 띄운다(`raised: true`).
- 묶음 패널은 그림자 없이 1pt 보조글자색 70% 테두리(`visionCraftSurfaceCard`, 면 위 3:1 이상). 오류 패널은 1.5pt 강조색(`visionCraftErrorPanel`).
- 채팅 칩·입력칸·입력 영역은 테두리 없이 면 색으로만 구분한다.
- 카드 안에 카드를 넣지 않는다.

## 위젯

- WidgetKit small/medium. 런처 배경 위에 그리므로 라이트/다크와 무관하게 어두운 유리·그림자를 쓴다. 규격은 `rivoWidget/`.
- Android 2x2 15개 고정과 달리 하나의 바로가기 위젯에서 기능을 고른다.
