# Screen Specs

점검일: 2026-09-29 · 기준 코드: `babc3875`+작업 트리 · Android 기준: `c6a03f0`

화면별로 지금 무엇이 어디에 있는지 적는다. 모양은 `04_component_specs.md`의 컴포넌트 이름으로 말한다. 모든 화면은 라이트/다크를 따르고 soft UI 팔레트(`03_design_tokens.md`)를 쓴다. 예외는 카메라 미리보기 위 버튼과 위젯. 각 화면의 Android 원본 파일을 함께 적는다. Android와 다른 곳은 각 절 끝의 **Android와 다른 곳**에 적는다(구조적 불가 또는 사용자가 유지하기로 한 iPad 전용).

## 홈

파일: `HomeView.swift` — `HomeView` (Android `compose/MainScreen.kt`, `VcSoftHome.kt`, `HomeLayoutController.kt`)

홈 구성은 설정 "화면 및 글꼴" 그룹의 `홈 화면 구성`에서 고른다. `목록형`(기본)과 `카테고리형`. `@AppStorage("visioncraft.home.layout")`(`HomeLayoutMode`)에 저장하고 바로 바뀐다. 홈이 나타날 때 저장된 값과 화면 상태가 다르면 저장값을 다시 적용한다. 항목 목록(AI 대화·카메라·읽기·비전링크)은 `HomeView`에 한 번만 정의하고 두 구성이 같이 쓴다.

### 공통 머리

- 제목 줄(`homeTitleRow`): 왼쪽 `VisionCraft`(24 Bold heading), 오른쪽에 리모컨 연결 상태 아이콘(`VisionCraftHomeRemoteStatusIcon`, 누르면 앱 안의 리모컨 연결 화면)과 설정 아이콘(`VisionCraftIconButton` "전체 설정", 누르면 전체 설정 화면). 두 아이콘은 간격 없이 붙는다.
  - 리모컨 아이콘은 연결됨 초록 / 연결 중 노랑 / 끊김 보조글자색 + 오른쪽 위 점. 읽기: "리모컨 연결. 연결됨·연결 중·연결 안 됨. 조작 가능·상태 확인 중·리모컨을 켜주세요".
- 그 아래 사용법 안내 카드(`VisionCraftHomeGuideEntry`): "앱 사용법이 궁금하신가요? / 기능과 상황별 사용법을 알려드려요". 누르면 사용법 화면.
- 바깥 여백: 좌우 24, 위 44, 아래 32.

### 목록형

위에서부터 섹션 제목(`VisionCraftHomeSectionHeader`) + 목록 카드(`VisionCraftHomeActionList`), 섹션 사이 28:

1. **AI 대화**: 새 대화, 대화기록(저장된 대화가 있을 때만)
2. **카메라와 연결**: 카메라, 문서 스캔, 실시간 문자 읽기, 이미지 분석(→ 촬영하기/사진에서 다이얼로그), 사진 분석
3. **읽기와 문서**: 텍스트, 문서 작업(iPad 전용), 데이지/EPUB 플레이어
4. 비전링크 카드(섹션 제목 없이, 위 28)
5. **설정**: 설정 그룹 전체(`HomeSettingsPanel`) + "모든 설정" 카드(iPad 전용 설정 화면)
6. **업데이트 기록**(`HomeUpdateNotesSection`): 최신 버전 카드 + "이전 업데이트 기록보기"

- "텍스트"는 클립보드에 글이 있으면 바로 텍스트뷰어를 열고, 없을 때만 "어떤 텍스트를 열까요?" 화면을 연다(`openTextView`).
- "이미지 분석"은 다이얼로그(`HomeImageAnalysisDialog`: "촬영하거나 사진을 선택하면 내용을 설명하고 클립보드에 복사합니다.", 촬영하기 → 카메라 이미지 분석 모드, 사진에서 → 사진을 고르면 바로 설명).

### 카테고리형

- 머리 아래 2x2 타일(`VisionCraftHomeCategoryGrid`, 가로 화면은 4개 한 줄): **AI 대화 / 카메라 / 텍스트 · 문서 / 비전링크**. 타일 그림은 회색 squircle 위에 `HomeTile*` 아이콘(라이트·다크 공용 한 벌).
- 타일은 전폭을 둘로 나누고 16 간격, 높이는 너비 × 5/4.
- 가로·세로 화면 모두 스크롤 없이 한 화면에 놓는다. 타일은 4:5 비율을 유지하며 세로 공간이 부족하면 타일 묶음의 너비를 줄여 가운데에 둔다. 안내 카드 아래 20, 타일 아래 최소 12를 확보한다.
- 항목이 하나뿐인 타일은 다이얼로그 없이 바로 실행: 비전링크는 항상, AI 대화는 저장된 대화가 없을 때. 나머지는 카드 다이얼로그(`VisionCraftHomeCategoryDialog`)로 항목을 보여준다.
- 카메라 타일은 카메라를 바로 연다. 문서 스캔·실시간 문자 읽기·이미지 분석·사진 분석은 카메라의 모드 버튼에서 들어간다.
- 타일 읽기: 항목이 하나면 "<타일>. <기능 설명>", 여럿이면 "<타일>. <항목 이름들>", 역할 버튼.
- 설정과 업데이트 기록은 홈에 없다. 설정 아이콘 → 전체 설정 화면 맨 아래에 업데이트 기록이 있다.

### 전체 설정

- `AppRoute.allSettings` → `HomeAllSettingsView`(`HomeView.swift`). `VisionCraftScreenTitleRow("전체 설정", 뒤로 가기)` + 설정 그룹(목록형 홈과 같은 `HomeSettingsPanel`). 시스템 내비게이션 바는 숨긴다.
- 카테고리형일 때만 맨 아래에 업데이트 기록(`HomeUpdateNotesSection`).
- 설정 그룹은 `VisionCraftSettingsGroup`(VcPanel), 값은 `VisionCraftSettingValueTile` → `VisionCraftSelectionDialog`, 켜고 끄는 항목은 `VisionCraftSettingSwitchTile`. 홀수 개 그룹의 마지막 칸은 전폭.
- 설정 항목(Android와 같음): 효과음 피드백·음성 피드백·OCR 오타 자동 교정·문서 스캔 색상 자동 보정 / 음성 및 언어: 음성 속도(천천히·자연스럽게·빠르게·아주 빠르게)·언어 / 화면 및 글꼴: 앱 글꼴(글꼴 미리보기·다운로드 중·오류 안내, 기본 시스템)·홈 화면 구성 / 메뉴바: 메뉴바 펼쳐보기·리모컨 조작 메뉴 색 조합 / 텍스트 뷰어: 글씨 크기(1~10, "5"로 표시)·줄 간격·색 조합(16개, 각 줄을 그 색으로 칠하고 "가 나 다 라" 미리보기, 읽기는 색 이름).

### 업데이트 기록

- `HomeUpdateNotesSection`: 버전(24 Bold) + "(날짜)"(14 보조글자) 한 줄로 한 번에 읽힘, 구분선, 항목마다 "- " 16. 면 22, 테두리·그림자 없음. 아래 "이전 업데이트 기록보기" 글자 버튼(잉크색, 48) → `AppRoute.releaseNotes`(`HelpReleaseNotesView` "전체 업데이트 기록").
- 내용은 iPad 자체 릴리스 노트(`HelpContentLibrary.releaseNotes`).

### 사용법

- `Help/HelpGuideView.swift`, `Help/HelpGuideContent.swift`, 문구 `*/VisionCraftGuide.json`.
- 상황별/기능별 두 가지 목록 + 문제 해결. 각 항목은 단계, 도움말, 해당 기능·설정으로 가는 버튼(잉크 버튼).
- 리모컨·연결 항목에는 "리보탭 리모컨 자세히 알아보기" → 리모컨 매뉴얼 화면.

### Android와 다른 곳

- 리모컨 상태 아이콘은 블루투스 설정 대신 앱 안의 리모컨 연결 화면을 연다(iOS는 시스템 설정을 열 수 없음).
- 홈 "문서 작업" 항목과 설정 끝 "모든 설정" 카드는 iPad 전용(문서 편집·스캐너·공유·독서·연결 설정).
- 전체 설정은 시스템 내비게이션 바 없이 자체 제목 줄만 있어 가장자리 스와이프로 돌아갈 수 없다.
- 언어를 바꾸면 재시작 없이 바로 반영된다.
- 업데이트 기록 내용은 iPad 자체 릴리스 노트다. 사용법에는 iPad 전용 항목(문서 작업·편집·번역·웹·비전링크·공유·접근성)과 검색·행 아이콘이 더 있고, 화면 확대·화면 글자 인식·메뉴바 항목은 없다.
- 버전 확인·APK 업데이트, 접근성 서비스 안내, 시작 시 권한 요청, 옛 앱 삭제 안내는 없다(App Store·iOS 권한 흐름).

## Rivo 리모컨 연결

파일: `RivoRemote/RivoRemoteView.swift` — `RivoRemoteView`, `RivoRemoteManager.swift` — `RivoRemoteManager`.

- 연결되지 않은 상태에서 화면 진입 시 검색을 시작하고 상태와 발견한 리모컨 중 신호가 가장 강한 한 대를 표시한다. 검색·연결 준비가 진행 중이면 그 작업을 유지한다. 사용자가 기기를 눌러야 연결한다.
- 검색 중에는 `검색 중지`, 연결되지 않았을 때는 `Rivo 리모컨 검색` 버튼을 제공한다. 연결 준비 중에는 검색·기기 선택 버튼을 비활성화한다.
- 연결된 상태에는 시간 전송 상태와 `시간 다시 맞추기`, `연결 끊기`, `다른 리모컨 연결` 버튼을 제공한다.
- 실패하거나 연결이 끊겨도 자동 재연결하지 않는다. 자동 재시도 안내·저장 기기로 돌아가기·기기 지우기 버튼은 없다. 사용자가 다시 검색하고 기기를 선택한다.

### Android와 다른 곳

- 사용자가 정한 iPad 동작: 이전 연결 기기를 저장하거나 자동 연결하지 않고, 앱 재시작·Bluetooth 재활성화 후에도 수동으로 기기를 선택한다.

## 시작 화면

- 정적 런치 화면(`LaunchLogo` 192pt 가운데, 배경 라이트 `#F3F5FF` / 다크 `#050816`) 뒤에 같은 구성의 SwiftUI 오버레이가 최소 700ms 보이며 빛 띠가 한 번 지나간다(−20°, 140ms 뒤 시작, 480ms, 폭 38%, 흰색 55%). 동작 줄이기면 애니메이션 없이 사라진다. `DesignSystem/VisionCraftSplashShine.swift`.

## AI 대화 (채팅)

파일: `LLM/LLMContentView.swift`, `LLM/ChatViewModel.swift`, `DesignSystem/VisionCraftChatUI.swift` (Android `ai/ChatActivity.kt`, `res/layout/a_chat.xml`).

- 위에는 뒤로 가기 + "AI 대화" 제목(`VisionCraftScreenTitleRow`, heading). 웹 출처·첨부가 있으면 제목 아래 배너를 둔다.
- 보낸 말풍선은 주황 면, 받은 말풍선은 soft 면 + 테두리(`VisionCraftChatUI`). 답변 생성 중에는 진행 막대를 보여 준다. 보낸 사람 이름은 13pt Bold.
- 아래는 첨부·요약 칩과 입력 영역. 첨부는 `VisionCraftDialogCard`에서 문서·클립보드·사진을 고른다. 마이크는 주황 면이며 듣는 중에는 정지 아이콘으로 바뀐다. "요약해주세요." 칩은 그 문구를 그대로 보낸다.
- 자유 채팅은 로컬 AI가 기본이고, 시점이 중요한 질문은 `ChatWebSearchRouter`로 기기에서 판별한 뒤 Gemini Google Search grounding으로 답한다. 웹 검색 설정 두 개는 기본 켬이다. 클라우드가 실패하면 로컬 AI 답변과 실패 안내를 표시한다. 출처는 제목 최대 3개를 읽기 좋게 적는다.
- 첨부 처리 진행·완료는 대화 흐름 안 안내 말풍선과 소리로 알린다.

**Android와 다른 곳:** 여러 줄 입력칸과 "전송" 버튼, 로컬 AI 실패 시 대체 답변은 iPadOS에서 유지한다. iOS 파일 선택기는 사용자가 고른 파일만 열 수 있어 Android 전체 저장소 문서 목록은 없다. 웹 검색의 필요 여부 판단은 클라우드 판별 호출 대신 로컬 키워드 규칙을 쓴다.

## 대화 목록

파일: `LLM/ChatHistoryView.swift`, `LLM/ChatHistoryStore.swift` (Android `compose/ConversationListScreen.kt`).

- 제목 줄(뒤로 가기 + "대화기록") + 대화 수. 각 대화는 22pt 카드에 기록 아이콘, 두 줄까지 제목, `yyyy-MM-dd HH:mm` 날짜, 이름 바꾸기·삭제 48pt 아이콘 버튼. 카드 사이 16pt.
- 아래에는 전폭 남색 잉크 "새 대화" 버튼을 고정한다. 빈 상태는 "대화 기록이 없습니다 / 새 대화를 시작하면 여기에 저장됩니다."로 설명한다.

## 엑셀 요약 영역

파일: 엔진 저장소 `VisionCraftDocumentEngine`의 `Sources/RivoDocumentEngine/ExcelAccessibilityModel.swift` · `ExcelAccessibilityAnalyzer`.

- 제목·부제 아래에 항목과 숫자가 나란히 있는 2열 요약은 간편 표에서 "항목 / 값"으로 읽는다. 첫 항목과 숫자도 데이터 행에 포함하며, 숫자를 열 제목으로 사용하지 않는다.
- AI 단순 값 질문은 원본 셀을 읽고 직접 답하며, 반환된 근거 주소의 셀을 표시한다. 셀 주소·실제 값·수식·병합 범위를 보존해 전달하고, 간편 표용 추정 열 제목은 AI 입력에 넣지 않는다.

## AI 문서 선택

파일: `LLM/AIDocumentSelectionView.swift` (Android `compose/FileSelectScreen.kt`).

- 음성 명령 "AI 문서"에서 들어간다. 머리에는 "파일 선택" 제목, "AI 문서 질의" 안내 패널(`VisionCraftPrimaryActionPanel`), 새 대화·대화기록 버튼을 둔다.
- 파일 선택기로 PDF·엑셀·한글·TXT를 고르면 문서 내용을 준비해 AI 대화로 연다. 사용자가 폴더 접근을 허용했다면 그 폴더의 최근 문서를 검색하고 바로 고를 수 있다.

**Android와 다른 곳:** iPadOS는 전체 저장소를 스캔하거나 모든 파일 접근 권한을 요청할 수 없다. 사용자가 고른 파일과 허용한 폴더만 나열한다.

## 텍스트뷰어

파일: `Documents/TextEditorViewerView.swift` (Android `compose/TextEditorViewerScreen.kt`).

- 클립보드가 비었거나 문서를 직접 열지 않았을 때 뷰어 안에 "어떤 텍스트를 열까요?" 첫 화면을 보인다. 뒤에는 옅은 `TextOpenSourceIllustration`을 깔고, 클립보드·이미지에서 텍스트 읽어오기·문서 버튼을 전폭 최대 320pt로 둔다.
- 본문은 사용자가 고른 고대비 색 조합과 글자 크기를 따른다. 테마 색은 메뉴·다이얼로그 바깥에만 쓴다. 상단 메뉴와 일시정지는 48pt 이상.
- 전체 메뉴는 제목 줄 + 닫기, 패널 안에 도구·모양·읽기·열기/저장 줄을 둔다. 글자 크기 1~10 단계와 16색 미리보기가 있다.

**Android와 다른 곳:** iPadOS 내비게이션에는 시스템 뒤로 가기가 따로 남는다. 텍스트 선택은 시스템 선택·복사 동작을 쓴다. 이미지에서 글자 가져올 때 iPadOS는 OCR 교정 단계가 있다.

## 데이지 / EPUB

파일: `Reader/ReaderLibraryView.swift`, `Reader/EPUBReaderView.swift`, `Reader/EPUBMediaOverlayPlayer.swift` (Android `daisy/ui/DaisyFileOpenScreen.kt`, `DaisyReaderView.kt`, `PlayerBottomBar.kt`).

- 여는 화면은 계속 읽기 / 도서 파일 선택 `VcActionRow` 두 줄, 로딩·오류·책 요약 패널(형식·제목·읽기 순서·목차·페이지·아카이브 파일 수). EPUB·ZIP과 octet-stream에 해당하는 파일을 고를 수 있다.
- 리더 제목 줄에는 목차·검색·보기 설정 아이콘. 본문은 사용자가 고른 밝게/세피아/어둡게 테마를 따르고, 현재 읽는 위치는 옅은 노란색으로 강조한다.
- 아래 플레이어 바는 항상 위치 슬라이더 + 재생 56pt 원, 이전·다음 48pt, 이동 단위 알약(단어/문장/문단/페이지/목차). 재생할 수 없으면 슬라이더가 흐려진다. 단위를 바꾸면 음성으로 알린다.
- 검색 시트는 입력 안내·일치 개수·결과 문맥, 설정 시트는 글자 크기·줄 간격·테마·음성 속도와 현재 값을 보인다.

**Android와 다른 곳:** iPadOS "내 서재" 목록(최근 읽음·삭제), 출판물 원본 표현 토글, 목차 시트, 장 단위 본문 구성은 유지한다. 목차를 본문 자리로 바꾸거나 책 전체를 한 문서로 이어 붙이지 않는다. 파일 열기는 시스템 파일 선택기를 쓴다.

## 카메라

파일: `CameraTools/MagnifierView.swift`, `MagnifierViewController.swift`, `VisionCraftCameraControls.swift`, `VisionCraftCameraViews.swift` (Android `camera/RVCameraXActivity.kt`, `CameraControls.kt`, `CameraModes.kt`).

- 미리보기 위 버튼은 테마를 따르지 않는 `VisionCraftCameraUI` 고정색. 미리보기를 가리는 띠는 깔지 않는다. 격자·라이트·전환은 상태 글자가 있는 둥근 사각 타일, 켜면 주황 면. "설정"으로 접고 펴며 접힌 채로 켠 항목이 있으면 주황 테두리로 알린다.
- 촬영과 접이식 설정 버튼은 카메라 화면 안전 영역의 오른쪽 아래에 붙은 한 열이다. 열 너비는 촬영 버튼 크기로 고정하고 모든 타일의 오른쪽 끝을 맞춘다. 타일 높이는 최소치만 두고 아이콘·제목·상태 글자가 커지면 함께 늘어난다. 모드 알약은 왼쪽 위이고 "모드: 이름"에서 이름만 굵게 쓰고 아래 화살표를 둔다. 모드/촬영/설정/전환/라이트/격자 순서로 읽는다.
- 기본 촬영은 사진 앱에 저장 후 "촬영한 사진" 검토 화면(다시 촬영·작업)으로 이어진다. 저장 실패는 화면과 음성으로 알린다. 이미지 분석 모드는 카메라 위에서 결과를 읽고 클립보드에 복사한다. AI 질문 촬영은 사진을 첨부한 음성 질의로 이어진다.
- 격자·라이트·전환·모드 상태를 바꿀 때 큰 글자와 음성 안내가 나온다. 색 조합 변경 시 격자선은 선택한 전경색을 따른다.
- 홈, 위젯, App Shortcut의 "카메라"는 모두 기본 카메라 화면을 바로 연다. 기능을 고르는 경로는 화면 위 모드 버튼이다.
- 기본 카메라·실시간 문자 읽기·문서 스캔의 제목 줄은 `VisionCraftCameraHeader`를 사용한다. 미리보기만 안전 영역 바깥까지 펼치고, 뒤로 가기와 모드는 안전 영역 위에서 8pt 아래에 놓는다.
- 문서 스캔·실시간 문자 읽기는 카메라 위의 새 화면으로 연다. 뒤로 가면 카메라로 돌아오며 카메라 세션은 전환 중 잠시 멈췄다가 다시 시작한다.

- 실시간 문자 읽기에서 기본·이미지 분석·AI 질문 모드를 고르면 읽기 카메라 세션을 멈추고 촬영 컨트롤이 있는 새 화면을 연다. 기본·이미지 분석·AI 질문 사이에서는 같은 화면의 모드만 바꾼다.

## 사진 분석

파일: `CameraTools/MagnifierView.swift` `PhotoReviewView` (Android `camera/PhotoReviewActivity.kt`, `ImageAnalysisActivity.kt`).

- 처음에는 사진을 고른다. 선택을 취소하면 닫는다. 카메라 기본 촬영에서 오면 화면이 나타날 때 전달된 사진을 한 번 받고 제목 "촬영한 사진"과 "다시 촬영" 버튼을 쓴다. 사진 앨범에서 오면 "사진 분석"과 "다른 사진" 버튼을 쓴다.
- 사진은 손가락으로 확대·원상복귀할 수 있고 제스처를 접근성 이름으로 안내한다. 남는 화면의 약 60%를 사진, 나머지를 결과에 나눠 쓴다.
- 아래 "다시 촬영/다른 사진"과 "작업"은 한 줄에서 같은 높이로 맞추고 너비를 1:1.45로 나눈다.
- "작업" 다이얼로그에는 글자 인식(OCR)·번역·AI와 이 사진으로 대화·텍스트뷰어로 보기·이미지 설명·텍스트 읽기 카드가 아이콘·설명과 함께 나온다. 글자 인식은 한 번만 수행하고 결과를 재사용하며 설정에 따라 OCR 오타 교정을 거친다.
- 처리 중에는 상태 띠와 소리·TTS로 알린다. OCR·이미지 설명 결과는 화면에 보이고 클립보드에 복사되며, 읽기를 다시 누르면 멈춘다. 화면을 나갈 때 TTS를 멈춘다. 홈 "이미지 분석 > 사진에서"는 사진을 고르면 곧바로 설명한다.

## 문서 스캔

파일: `DocumentScan/CustomScanner/LocalDocumentScannerViewController.swift`, `DocumentScan/DocumentScanRootView.swift` (Android `scanner/DocumentScanActivity.kt`, `DocumentScanResultActivity.kt`). 상세 파이프라인은 `rules/scanner_pipeline.md`.

- 촬영 화면은 미리보기 아래 상태 알약으로 문서 탐색·프레이밍·고정·촬영을 알린다. 문서가 잘렸으면 방향을 말해 준다. 강제 촬영·어두워서 라이트 켬·다음 장 준비도 음성 피드백 설정에 따라 TTS로 말한다.
- 한 장 검토는 사진/텍스트 전환과 사진 핀치 확대(최대 4배), 인식 중 안내 띠를 둔다. 글자가 없으면 이유를 알리고 글자가 필요한 작업은 열지 않는다.
- "저장"은 사진/PDF/텍스트 복사, "작업"은 AI 대화·번역·텍스트뷰어·이미지 설명·텍스트 읽기. 다이얼로그는 `VisionCraftDialogCard`로 아이콘·설명이 있는 88pt 카드 행이다. 이미지 설명은 화면에 남아 결과를 표시하고 읽는다. 텍스트 읽기는 다시 누르면 멈춘다.

**Android와 다른 곳:** iPadOS에는 자동 촬영 끄기와 곡면 보정 설정, 세분화된 상태·거리 안내, 여러 장 검토, PDF 저장 위치 선택 기능이 더 있다. 시스템 권한·파일 선택 방식은 iPadOS를 따른다.

## 비전링크

파일: `VisionLink/VisionLinkView.swift`, `VisionLink/VisionLinkManager.swift` (Android `visionlink/VisionLinkReceiverActivity.kt`, `VisionLinkSettingsActivity.kt`).

- 제목 없는 전체 화면. 연결 대기에는 파란 원 맥박, 연결 뒤에는 두 노드와 움직이는 점·선. 동작 줄이기 설정을 따르면 멈춘다. 연결 상태·현재 활동(카메라, 바로 읽기, 기능 처리)을 제목과 칩에 텍스트로 적는다.
- 원격 OCR·이미지 분석·AI 답변·첨부·번역의 처리 중/완료/실패를 HUD 카드와 접근성 알림으로 보여 준다. 사진/파일 받는 중에는 진행률, 완료 시 이름·크기·저장 위치를 잠시 보여 준다. 최근 수신은 사진·파일·텍스트를 열 수 있다.
- 클립보드 텍스트를 받으면 시스템 클립보드에도 저장하고 완료 카드를 자동으로 닫는다. 설정 시트는 연결된 기기 이름과 등록 해제 확인·진행·오류 안내를 보인다.

**Android와 다른 곳:** 받은 파일은 앱 문서 폴더의 `VisionLink/`에 저장하고 파일 앱·QuickLook에서 연다. iPadOS에는 미리보기·내보내기·삭제와 진단 섹션이 더 있다.

## 음성 질의

- 문서 질문의 로컬 모델 준비가 실패하면 다음 "다시 말하기"에서 준비를 다시 시도한다. 화면을 나가면 음성 인식·응답·모델 준비 대기 작업을 취소한다.

파일: `VoiceQueryResponseView.swift`, `STTManager.swift`, `AuroraListeningOverlay.swift` (Android `ai/voice/VoiceQueryScreen.kt`, `STTHelper.kt`).

- 공유 화면 설정에서 음성 질문을 고르면 전용 음성 질의 화면으로 간다. 위 오른쪽 "닫기", 아래 72pt "다시 말하기" 마이크. 듣는 중에는 오로라 오버레이를 유지한다.
- 라이트/다크를 따르고, PDF·웹·엑셀·한글·텍스트·이미지처럼 받은 형식을 안내한다. 답은 스트리밍으로 표시하고 문장 단위로 읽으며 마크다운 기호는 읽지 않는다.
- 음성 인식은 앱 언어를 따르고, 인식된 문장이 2.5초 동안 바뀌지 않거나 소리가 3.5초 동안 조용하면 자동으로 끝낸다. 인식 실패는 이유별 텍스트와 실패음으로 알린다.

**Android와 다른 곳:** 보라 Orb 대신 기존 오로라를 유지한다. 자유 채팅 답변은 로컬 AI를 우선하고 클라우드 웹 검색이 실패하면 로컬 AI로 대신 답한다.

## 리모컨 빠른 메뉴

파일: `RivoRemote/RivoRemoteControlCenter.swift`, `RivoRemote/RivoRemoteModeOverlay.swift` (Android `menu/RemoteRibbonOverlay.kt`, `RemoteModeOverlay.kt`).

- 리모컨 L1으로 앱 안 빠른 메뉴를 연다. 접힌 화면은 아래 카드 3개와 키 안내, 펼친 화면은 목록과 조절 항목의 −/+ 버튼. 사용자가 고른 메뉴 색 조합을 강조색으로 쓴다.
- 도구·위젯 명령을 실행하면 닫고, 카메라·텍스트·데이지처럼 이어 누르는 페이지에서는 열린 채로 둔다. 60초 동안 조작이 없으면 닫고 최근 메뉴 상태를 복원할 수 있다.
- 모드를 바꾸면 큰 이름을 잠시 띄우고, 명령·텍스트·데이지·메뉴 모드의 키 안내를 보여 준다. 카메라 전환·라이트 켜기/끄기 항목의 이름은 카메라가 보고한 실제 상태를 따른다(`MagnifierViewController.onCameraStateChanged` → `RivoRemoteControlCenter.noteMagnifierState`). 화면 직접 조작·리모컨 키·카메라 재진입을 반영하고, 실패한 토글 명령만으로 이름을 바꾸지 않는다.

**Android와 다른 곳:** iPadOS에서 다른 앱 위에 뜨는 가장자리 메뉴바, 시스템 화면 확대·반전·회전 잠금, TalkBack 토글은 만들 수 없다. 하단 카드형 빠른 메뉴는 기존 iPadOS 방식을 유지한다.

## 위젯

- 텍스트뷰어 바로가기는 `rivopad://open/text-viewer`로 진입한다. 클립보드에 글이 있으면 그 글을 열고, 없으면 텍스트 원본 선택 화면을 연다.

파일: `rivoWidget/RivoStatusWidget.swift` (Android `widget/*`).

- WidgetKit small/medium 리모컨 상태 위젯, 고르는 바로가기 위젯, 로컬 AI 사용량/클라우드 AI 토큰 잔량 위젯과 제어 센터 컨트롤. 이름은 "데이지 플레이어", "카메라", "새 대화", "실시간 문자 읽기"처럼 앱 화면과 맞춘다.
- AI 사용량은 하루 100만 클라우드 토큰의 남은 비율과 막대도 보여 준다. 글자는 12pt 이상, 상태는 글자와 접근성 이름으로도 알린다.

**Android와 다른 곳:** WidgetKit 크기·구성 방식에 맞춰 바로가기 기능을 선택한다. 화면 확대·TalkBack·회전 잠금·음소거 시스템 토글 위젯은 iPadOS에서 만들 수 없다.
