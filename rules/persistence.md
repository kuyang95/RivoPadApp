# 영속 데이터 (UserDefaults / App Group / 파일 / Keychain / Assets)

점검일: 2026-10-23 · 기준 코드: `c5865248`+작업 트리 (쉬운 유튜브 재생 의도·기존 저장소 범위) · 런처 유틸리티 대조: 2026-10-22 `514e00f5`+작업 트리 · 현재 위치 날씨 대조: 2026-10-22 `f56b06f0`+작업 트리 · 타이머 시각 설정 대조: 2026-10-22 `f56b06f0`+작업 트리 · 브라우저 즐겨찾기 대조: 2026-10-22 `f56b06f0`+작업 트리 · 데이지 본문 유지·자원 수명 대조: 2026-10-22 `f56b06f0`+작업 트리 · 즐겨찾기 아이콘 저장 대조: 2026-10-22 `f56b06f0`+작업 트리 · 유튜브 탭 목록 캐시 대조: 2026-10-22 `f56b06f0`+작업 트리 · 현재 페이지 빈자리 우선 추가 대조: 2026-10-23 `f56b06f0`+작업 트리 · 브라우저 광고 차단 설정 대조: 2026-10-23 `f56b06f0`+작업 트리 · 날씨 30분 갱신·큰 글자·원형 새로고침 대조: 2026-10-23 `f56b06f0`+작업 트리 · 전체 페이지 뉴스 위젯 대조: 2026-10-23 `2d5aae7e`+작업 트리 · 다중 언론사 뉴스 대조: 2026-10-23 `2d5aae7e`+작업 트리 · 뉴스 출처·표본 확대 대조: 2026-10-23 `2d5aae7e`+작업 트리 · 뉴스 74개 매체 목록 대조: 2026-10-23 `2d5aae7e`+작업 트리 · 뉴스 2시간 백그라운드 캐시 대조: 2026-10-23 `2d5aae7e`+작업 트리 · 뉴스 선택 분야 수신·HTML 정리 대조: 2026-10-23 `2d5aae7e`+작업 트리 · 런처 릴리즈·미디어 탐색 대조: 2026-10-23 `329441fb`+작업 트리

Room DB, EncryptedSharedPreferences 에 해당하는 것은 없다. 구조화 데이터는 전부 **JSON 파일** 또는 **UserDefaults(Codable 인코딩)**.

## UserDefaults.standard 키

| 키 | 타입/기본 | 출처 |
|---|---|---|
| `settings.appTheme.v1` | `AppThemeMode` raw (`system`/`light`/`dark`), 기본 `system`. 잘못된 값은 시스템으로 복구하며 설정 초기화 시 `system`으로 저장 | `Settings/AppThemeMode.swift` · `AppThemeMode.preferenceKey`, `AppSettingsStore.appTheme` |
| `settings.soundEffects.v1` | Bool | `Settings/AppSettingsStore.swift` · `AppSettingsStore.Key` |
| `settings.voiceFeedback.v1` | Bool | 〃 |
| `settings.speechRate.v1` | `AppSpeechRate` raw (`slow/normal/fast/veryFast`) | 〃 |
| `settings.scanColorEnhancement.v1` | Bool | 〃 (Android RC `feature_doc_scan_color_enhance_enabled` 대응, 로컬 토글) |
| `settings.scanAutomaticCapture.v1` | Bool | 〃 |
| `settings.scanCurvedPageCorrection.v1` | Bool, **기본 false** | 〃. UVDoc 이 평평한 페이지를 휘게 할 수 있어 Android 처럼 기본 OFF |
| `settings.scanCurvedPageCorrection.defaultOff.v1` | Bool | 1회 마이그레이션 플래그 — 과거 iOS 기본 ON 값을 OFF 로 바꾼 뒤 이후 사용자 선택 유지 |
| `settings.ocrAutoCorrection.v1` | Bool | Gemini OCR 교정 사용 여부 |
| `settings.appLanguage.v1` | `AppLanguage` raw (`system`/`ko`/`en`/`ja`) | `AppLanguage.preferenceKey` |
| `settings.sharedTextEntryMode.v1` | `voice`/`chat` | 공유 텍스트 진입 방식 |
| `settings.rivoQuickMenuExpanded.v1` / `settings.rivoQuickMenuColorIndex.v1` | Bool / Int | Rivo 빠른 메뉴 UI |
| `settings.fontChoice.v1` | 글꼴 key, 기본 `system` | `Settings/AppFontCatalog.swift` · `AppFontCatalogStore.preferenceKey` |
| `visioncraft.home.layout` | `HomeLayoutMode` raw (`list`/`grid`). 홈이 나타날 때 저장값을 다시 적용한다 | `HomeView.swift` · `HomeLayoutMode.storageKey` (Android `HomeLayoutController` 대응) |
| `visioncraft.home.guideVisitCount.v1` | Int, 기본 0, 0~5 범위로 저장. 5번째 홈 방문부터 사용법 카드를 설정 오른쪽 아이콘으로 바꾼다 | `HomeGuideVisitStore.swift` · `HomeGuideVisitStore.recordVisit`, `HomeView.swift` · `HomeView.recordHomeVisitIfNeeded`. 홈 최초 표시·화면 복귀·백그라운드 복귀를 세며, 같은 표시 중 화면 갱신·회전·다이얼로그는 세지 않는다 |
| `display.app.interfaceInverted` / `display.app.orientation` | Bool / `AppDisplayOrientation` raw | `shortcuts_exampleApp.swift` `@AppStorage` |
| `camera.display.colorIndex.v1` / `camera.display.colorInverted.v1` / `camera.display.threshold.v1` | Int / Bool / 값 | `CameraTools/MagnifierDisplayPreferenceStore.swift` — 돋보기 Android 호환 색상 조합 복원 |
| `webSearch.enabled.v1` / `webSearch.automaticChat.v1` / `webSearch.removedBraveCredential.v1` | Bool (앞의 두 설정은 기본 true, 저장된 false는 유지) | `LLM/WebSearchConfigurationStore.swift` |
| `reader.epub.lastBookPath` | String | `Reader/EPUBLibraryStore.swift` |
| `reader.epub.progress.<base64(bookID)>` / `reader.epub.chapter.<base64(bookID)>` | 진행률 / 챕터 | 〃 `progressKey` / `chapterKey` |
| `RecentOriginalDocumentStore.records.v1` | JSON, 최대 100건 | `Documents/RecentOriginalDocumentStore.swift` |
| `AuthorizedDocumentLibrary.bookmark.v1` / `AuthorizedDocumentLibrary.folderName.v1` | security-scoped bookmark Data / String | `Documents/AuthorizedDocumentLibrary.swift` — 사용자가 고른 문서 폴더 |
| `rivo.remote.connectionDiagnostics` | JSON, 최근 80건 | `RivoRemote/RivoRemoteManager.swift` · `DefaultsKey`. 기기 UUID·타입·Bluetooth 활성화 이력은 저장하지 않고, 초기화 시 이전 버전의 `rivo.remote.peripheralIdentifier` / `rivo.remote.deviceType` / `rivo.remote.hasActivatedBluetooth` 값을 제거한다 |
| `LocalDocumentAppearance.v1` | `LocalDocumentAppearance` JSON (fontLevel 1~20·기본 5, lineHeightLevel 1~10·기본 5, colorIndex, showsLineSeparators, usesSingleLineInLandscape) — 문서 뷰어 글자/줄간격/색상·가로 한 줄 보기 | `Documents/LocalDocumentReading.swift` |

## App Group `group.net.rivo.visioncraft`

`UserDefaults(suiteName:)` 키 — 앱·위젯·익스텐션·App Intents 가 공유:

| 키 | 출처 |
|---|---|
| `cloudAI.tokenBudget.today.v1` | `LLM/CloudAITokenBudgetStore.swift` (Gemini 일일 토큰) |
| `localAI.usage.today.v1` | `LLM/LocalAIUsageStore.swift` (위젯 `LocalAIUsageWidget`) |
| `rivo.widget.snapshot.v1` | `RivoRemote/RivoWidgetStatusStore.swift` (위젯 `RivoStatusWidget`) |
| `shortcut_last_envelope_v1` | `ShortcutRouter.swift` · `ShortcutBridge` (Intent → 앱 전달) |

컨테이너 디렉터리 (`containerURL(forSecurityApplicationGroupIdentifier:)`):

| 경로 | 내용 |
|---|---|
| `ShareInbox/` + `manifest.json` | 공유/액션 익스텐션이 넣은 항목 (`Sharing/SharedInboxStore.swift`, `schemaVersion 1`). 항목당 100 MiB, 커밋 항목 7일·미완료 24시간 후 정리 |
| `ShortcutEnvelopes/` | Intent 봉투 (`ShortcutBridge`) |
| `ShortcutLastAttachments/` | Intent 첨부 (`AppBootstrap.prepareAppGroup`, 없으면 `fatalError`) |

⚠️ `OCRSharedStore.swift` 는 suite `group.com.yourcompany.yourapp`, 키 `latest_ocr_text` / `latest_ocr_ts` 를 쓴다 — entitlements 에 없는 템플릿 이름. `OCRIntent` 결과 저장에만 쓰이며 실제로 공유되지 않는다. 고치려면 `group.net.rivo.visioncraft` 로 바꿔야 한다.

## Application Support (`FileManager.url(for: .applicationSupportDirectory)`)

| 경로 | 내용 | 출처 |
|---|---|---|
| `LocalChat/conversations-v1.json` | AI 채팅 기록 (`StoredChatDatabase`, `schemaVersion 2`, 제목 30자+`...`) | `LLM/ChatHistoryStore.swift` |
| `LocalChat/Attachments/` | 채팅 첨부 원본 | `LLM/ChatAttachmentStore.swift` |
| `VisionLink/conversations-v1.json`, `VisionLink/ChatAttachments/` | VisionLink 원격 채팅 기록 (`schemaVersion 1`, 최근 30개) | `VisionLink/VisionLinkConversationStore.swift` |
| `EPUBBooks/<book>/` + `.rivo-library-book.json` | 가져온 EPUB/DAISY (zip) 사본, 250 MiB/권, 2,000권 | `Reader/EPUBLibraryStore.swift` |
| `HFModels/` | Hugging Face 스냅샷 (MLX 모델 수 GB) | `LLM/LLMService.swift` · `modelStoreURL` |
| `VisionCraft/AppFonts/` + `manifest.json` | rivo.me 에서 받은 글꼴 | `Settings/AppFontCatalog.swift` |

## Caches (`.cachesDirectory`)

| 경로 | 내용 | 출처 |
|---|---|---|
| `DocumentScanSessions/<sessionUUID>/manifest.json` + 페이지 이미지 | 스캔 세션 (`schemaVersion 1`), 재시작 시 `restoringLatest` 로 복구 | `DocumentScan/ScanSession/DocumentScanSessionStore.swift` |
| `VisionLink/ReceivedText/` | 폰에서 받은 텍스트 | `VisionLink/VisionLinkReceivedTextStore.swift` |

## Documents (`UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`)

사용자 문서(HWP/HWPX/XLSX/XLS/DOCX/PDF/TXT/EPUB)는 Files 앱에서 직접 열거나(`LocalFileOpening`, `LocalDocumentImportService`) `AuthorizedDocumentLibrary` 가 북마크한 폴더에서 나열 (지원 확장자 `supportedExtensions`, 최대 5,000개 / 깊이 64). 테스트 산출물도 `Documents/` 에 쓴다.

## 쉬운 브라우저 세션

`Settings/AccessibleWeb/AccessibleWebBrowserModel.swift`는 일반 브라우저 전용 `WKWebsiteDataStore(forIdentifier:)`(UUID `382B897A-44FB-49CB-9A93-FCDA0D815DB1`)를 사용한다. 웹 쿠키·로그인·localStorage는 위젯·단독 화면·팝업이 공유하고 화면 종료 후에도 유지한다. YouTube는 기존 별도 UUID를 유지한다. 주소·방문 내역·색상 통일 여부·팔레트는 화면 메모리에만 둔다. 사용자가 추가한 즐겨찾기와 광고 차단 설정은 별도 UserDefaults 키에 저장한다. 기존 문서용 WebView나 앱의 네이티브 데이터 브리지를 사용하지 않는다.

## Keychain

| 서비스 / 계정 | 내용 | 출처 |
|---|---|---|
| `net.rivo.visioncraft.visionlink` / `receiver` | `VisionLinkStoredCredentials` JSON (`pairID`, `deviceID`, `deviceToken`, `isConfirmed`), `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | `VisionLink/VisionLinkCredentialStore.swift` |
| ~~`com.rivo.shortcuts-example.web-search` / `brave-search-api-key`~~ | 레거시, 첫 실행 때 삭제 | `WebSearchConfigurationStore.removeLegacyBraveCredentialIfNeeded` |

## Assets (앱 번들)

| 파일 | 용도 |
|---|---|
| `DocumentScan/CustomScanner/Models/lcnet100_doc_aligner.onnx`, `uvdoc.onnx` | 스캐너 모델 ([scanner_pipeline.md](scanner_pipeline.md)) |
| `Help/VisionCraftGuide.json` (+ `en.lproj`/`ja.lproj` 사본) | 사용 설명서 항목 (`id`, `group` feature/situation, `feature`, `situation`, `icon`, `action`, `steps[]`, `tip`) — `Help/HelpGuideContent.swift`, `HelpGuideView` |
| `Help/RivoPadManual.txt`, `Help/RivoPadChangelog.txt` (+ 언어별) | `@title/@version/@date/@chapter/@section/@text` 마크업 — `Help/HelpDocument.swift` · `HelpContentLibrary` 가 언어 lproj 우선, 없으면 루트 파일 |
| `*.mp3`, `*.wav` 16개 | `SoundEffectManager` ([gemini_ai.md](gemini_ai.md) 효과음 표) |
| `*.ttf`/`*.otf` 15개 | `UIAppFonts` |
| `Assets.xcassets` | `AppIcon`, `AccentColor`, `LaunchBackground`, `LaunchLogo`, 홈 타일 4종 (`HomeTileAIChat/Camera/PhoneLink/Reading`), 카테고리 기능 타일 11종 (`HomeAction*`, 사용자 제공 투명 PNG), `TextOpenSourceIllustration` |
| `AppShortcuts.xcstrings` | App Shortcut 문구 |

## Ratio 홈 설정

`Launcher/RatioLauncherView.swift`의 UserDefaults: `ratio.home.favorites.v1`는 ID 쉼표 목록(기본 magnifier,live,chat,books), `ratio.home.apps.v1`는 앱 이름·URL·UUID 배열의 JSON Data(기본 빈 배열), `ratio.home.textSize.v1`는 Double 28(24~40), `ratio.home.clock.v1`는 Bool false, `ratio.home.icons.v1`는 Bool true. `Assets.xcassets/RatioBlueMist.imageset`는 Android와 같은 Unsplash 사진이며 라이선스는 `Launcher/wallpaper-license.txt`다.

`ratio.home.widgets.v2`는 `{id,name,textOnly,columns,rows,textSize,iconOnly?,colorKey?}` 배열 JSON Data다. `widget:search` ID는 검색 위젯이다. v2가 없으면 v1을 디코딩해 기존 검색 크기의 검색 항목을 맨 앞에 추가하고 이전 첫 사각형은 lemon으로 보존한다. 기존 즐겨찾기 마이그레이션도 검색 항목을 포함한다. v2 빈 배열·검색 삭제를 보존한다. `ratio.home.searchColumns.v1`·`ratio.home.searchRows.v1`는 이전 검색 크기 이관용이다. `ratio.home.apps.v1` 항목에는 선택적 `iconData`(128×128 PNG Data)를 저장하며 기존 아이콘 없는 항목도 디코딩된다. PhotosPicker로 선택한 이미지에만 접근한다.

Ratio v2 위젯은 선택적인 `iconText`를 추가 저장한다(기본 false, 이전 데이터 누락 시 false). Android는 Boolean, iPad는 하위 호환 Codable Bool?이다. 앱 TEXT에서만 앱 아이콘 색을 표시하고 `colorKey`는 단색 및 이미지 실패 시 대체색이다. 색상 선택은 iconText를 false로 바꾸며 크기·순서·유형 변경은 보존한다. 아이콘 이미지 자체를 위젯 데이터에 복사하지 않는다.

텍스트 바로가기 공통 글자 크기는 `ratio.home.shortcutTextSize.v1`에 저장한다. 기본 36, UI 범위 24~56, 증감 4. 기존 위젯별 textSize는 호환용으로 보존하지만 표시에는 사용하지 않는다. 저장된 공통 값이 없으면 개별 값과 무관하게 36으로 표시한다.

Ratio 브라우저 위젯 ID `widget:browser`(Android kind BROWSER, iPad ID)는 전체 페이지로 표시한다. 과거 columns·rows는 호환 데이터로 보존하며 실제 렌더링 높이에는 사용하지 않는다. URL·입력·스크롤은 열린 화면의 세션에 속하며 쿠키·로그인은 전용 영속 웹 저장소를 공유한다.

Ratio 데이지 위젯 ID `widget:daisy`(Android kind DAISY)는 전체 페이지다. 배치 외 책·진행·보기 데이터는 기존 독서 저장소를 공유한다. 페이지 이동 중의 본문·스크롤은 세션 메모리에만 유지하고 영속 저장 키는 추가하지 않는다.

## 쉬운 유튜브 저장소

`AccessibleWebBrowserModel(easyYouTube: true)`는 `WKWebsiteDataStore(forIdentifier:)`와 고정 UUID `6492E698-D7FC-4721-9F45-A2EC60B94889`를 사용한다. YouTube 로그인·사이트 저장소를 다음 진입에도 유지하며 `.default()`·문서 웹뷰·일반 접근성 웹의 `.nonPersistent()` 저장소와 공유하지 않는다.

비밀번호·쿠키를 네이티브 코드에서 읽거나 기존 임시 브라우저 로그인 정보를 복사하지 않는다. 로그아웃은 YouTube의 로그인 서비스에서 처리한다. 주소·추천 목록·별도 화면 모드 설정을 앱 저장소에 추가하지 않는다.

쉬운 유튜브 로그인 배경은 기본 이미지 생성 도구로 만든 투명 재생 타일이다. Android 번들 원본 `easy-youtube-login.webp`와 같은 바이트를 `easy-youtube.js`·iPad의 `EasyYouTubePage.source`에 data URL로 포함한다. 다운로드나 사용자 저장소 키를 추가하지 않으며 별도 이미지 파일을 Release 에셋에 추가하지 않는다. 배경을 바꾸면 두 스크립트의 내장 이미지도 함께 갱신한다. 생성 프롬프트는 `docs/design/easy-youtube-login-art.json`에 둔다.

### 전체 페이지 위젯의 최초 배치

UserDefaults `ratio.home.fullPageWidgets.v1`는 Int(기본 0)다. 첫 Ratio 홈 진입 때 `installFullPageWidgets`로 일반 바로가기를 그대로 보존하고 쉬운 유튜브·쉬운 브라우저·데이지를 뒤에 한 번 추가한 뒤 1로 기록한다. 이후 사용자 제거·순서·빈 목록은 보존한다. 새 ID는 `widget:youtube`이며 기존 `ratio.home.widgets.v2` JSON Data 배열에 함께 저장한다. 과거 브라우저·데이지 rows는 데이터 호환용으로 유지하며 현재 표시 높이는 페이지 가용 높이다. 쉬운 유튜브 쿠키는 기존 영속 WKWebsiteDataStore를 공유하고 브라우저도 모드 전용 영속 저장소를 공유한다.

### 쉬운 유튜브의 탭 내 재생 의도

YouTube 페이지의 `sessionStorage` 키 `rivo.youtube.playback.v1`은 사용자가 누른 일반 영상/쇼츠의 화면 이동을 연결한다. 종류(`watch`/`shorts`), 공개 영상 ID·제목(일반 영상), 생성 시각만 담는다. 2분이 지난 값은 재생 의도로 사용하지 않는다. 일반 영상 값은 재생창을 열 때 소비하고 쇼츠 값은 같은 탭의 연속 이동에 사용하며 뒤로/채널 이동 때 지운다. 쿠키·비밀번호·계정 식별자는 읽거나 복사하지 않는다. 네이티브 앱 저장소 키를 추가하지 않으며 댓글·채널 목록도 앱에 저장하지 않는다.

## 런처 날씨·타이머 위젯

UserDefaults `ratio.utility.weather.locationCache.v1`는 현재 위치의 지역명·반올림 좌표·기온·체감·최고/최저·코드·fetched를 저장한다. 과거 수동 지역 city/cache v1 키는 읽지 않고 최초 현재 위치 예보 성공 시 지운다. `ratio.utility.compactDefaults.v1`은 기존 기본 크기 위젯의 2×2 전환 1회 표시다. `ratio.utility.timer.v1`의 deadline·remaining·minutes·alarm은 유지한다. 날씨 캐시는 30분 미만이면 위치 재조회 없이 재사용하며, 갱신 실패 시 최대 6시간 미만 자료만 시각·오류와 함께 표시한다. 5분 재시도 대기는 세션 메모리에만 보관하고 기존 저장 키·좌표 반올림 규격을 유지한다. 위젯 ID와 기존 저장 배치 필드는 유지하며 삭제한 타이머의 OS 알림은 취소한다.

시간 설정 창은 `ratio.utility.timer.v1`에 선택 알람 시각 `hour`·`minute` 선택 필드를 저장한다. 기존 자료에 없으면 현재 예약의 시각 또는 현재 시각을 사용한다. 설정 적용 시 현재 일시정지 잔여 시간과 만료 예약을 초기화하고 새 선택 값을 저장한다. 재생 때 선택 시각의 다음 한 번을 예약하며 실행 중에는 설정을 열지 않는다.

## 사용자 브라우저 즐겨찾기와 일반 위젯 삽입

UserDefaults `browser.favorites.v1`은 `{name,url,icon?}` 배열 JSON Data다. `ratio.utility.inlineUtilities.v1`은 전체 페이지 뒤의 기존 날씨·타이머를 일반 홈 영역으로 옮긴 1회 표시다. 즐겨찾기는 최대 24개, 이름 60자·주소 2048자 이내이며 HTTP 입력은 HTTPS로 바꾼다. 같은 URL은 기존 항목을 갱신한다. 웹 쿠키·방문 내역과 분리하며 웹 localStorage·외부 서버에는 저장하지 않는다. 즐겨찾기 목록은 HTTPS 구글 홈에만 전달하고 다른 웹 원본에는 전달하지 않는다. 일반 위젯의 새 배치도 기존 v2 배열에 저장하며 ID·크기·색 형식을 바꾸지 않는다. 현재 페이지 빈자리 선택에 사용하는 줄 ID·측정 높이·가용 높이는 편집 화면을 여는 동안 메모리에만 보관하고 저장 키는 추가하지 않는다.

## 데이지 위젯의 읽기 세션

`RatioDaisyWidgetView`는 같은 런처의 페이지 이동 동안 책 URL과 독서 화면·스크롤을 유지한다. 메모리 경고 때 다른 홈 페이지·앱 배경의 비재생 본문은 해제하고 다음 방문에 기존 진행 저장소로 복원하며 자동 재생하지 않는다. `EPUBArchive`는 기존 메모리 매핑 가능한 ZIP 데이터와 항목 인덱스를 사용하고 필요한 자료만 압축 해제한다. 유휴 `AVPlayerItem`·음성 버퍼·오디오용 archive 참조는 해제하고 추출한 오디오 파일은 책 세션 종료 때 삭제한다. 디스크 파일을 다시 쓰는 동안 빠른 재생 재개가 파일 삭제와 경합하지 않도록 유휴 정리는 추출 파일을 삭제하지 않는다. 새 영속 저장 키는 없다.

즐겨찾기 `icon`은 사이트에서 읽은 이미지를 긴 변 96px 이하 PNG로 변환한 `data:image/png;base64,...` 문자열이다. 필드가 없는 기존 자료는 이전 첫 글자 아이콘으로 표시한다. 주소만 입력하면 사이트 이름을 자동 추출하고 실패 시 도메인을 저장한다. 원본 HTML·외부 이미지 URL·쿠키는 저장하지 않으며 기본 네 사이트 아이콘은 기존 로컬 기호를 사용한다.

쉬운 유튜브 목록 복원은 YouTube 탭의 sessionStorage `rivo.youtube.feed.v1`에 저장한다. `{routes,lastSeen,needsRefresh?}`이며 routes는 최대 4개 경로의 `{route,section,scroll,items}`이고 items는 최대 120개 공개 영상 카드 정보다(영상 ID·제목·썸네일 URL·길이·보조 문구). 이미지 바이트·DOM·댓글·채널 본문·쿠키·계정 식별자를 저장하지 않는다. 현재 표시 목록만 DOM 카드로 만들고 나머지는 텍스트 메타데이터로 보관한다. 네이티브 페이지 활성·앱 생명주기와 웹 문서 가시성으로 30분 비활성을 판단하고, 영상을 보는 동안에는 사용 시각을 최대 15초 간격으로 갱신한다. 홈 목록 수동 새로고침·30분 비활성·로그아웃 확인 때 목록을 비우며, 영상에서 뒤로 돌아오는 동작은 기존 자료를 유지한다. 네이티브 앱 저장 키는 추가하지 않는다.

일반 쉬운 브라우저 광고 차단 선택은 Android SharedPreferences `debug_browser_privacy/ad_block_enabled`, iPad UserDefaults `browser.adBlock.enabled` Bool이며 없으면 true다. 광고 URL·차단 이력·방문 페이지는 저장하거나 전송하지 않는다. 필터 목록과 CSS는 앱에 번들하며 WebView 기본 프로필·책 저장소·YouTube 로그인 프로필에는 적용하지 않는다. iPad는 WebKit 콘텐츠 규칙 저장소 식별자 `rivo-browser-ads-v1`의 컴파일된 규칙을 재사용한다. 기존 임시 웹 세션과 구분되는 앱 설정이다.

### 날씨 갱신 수명

날씨 자동 갱신은 마지막 성공 시각 기준 30분 간격으로 보이는 페이지·앱 활성 상태에서만 실행한다. 화면 복귀 때 30분 미만의 자료는 위치 재조회 없이 재사용하고, 오래됐거나 자료가 없으면 즉시 위치 한 번과 예보를 요청한다. 수동 새로고침은 신선도·재시도 대기를 한 번만 무시하며 로딩 중 중복 입력은 막는다. 실패하면 지역명·날씨를 함께 보존하고 갱신 시각·오류를 표시하며 5분 뒤 재시도한다. 실패 대기는 메모리에만 유지하고 페이지 복귀가 대기를 초기화하지 않는다. 캐시는 최대 6시간까지만 표시하며 미래 시각·6시간 이상 자료는 제거한다. 위치 권한이 거부되면 이전 날씨를 숨기고 권한 설정을 안내한다. 위치와 예보는 성공 시 함께 교체하며 주기 위치 구독·백그라운드 예약 작업은 없다.

## 전체 페이지 뉴스 위젯

뉴스 배치는 기존 위젯 배열에 `widget:news`(Android kind NEWS)·4열·호환 10행으로 저장한다. Android `accessible_launcher/news_widget_version`(Int, 기본 0)은 배치와 같은 저장 연산으로 1을 기록한다. iPad `ratio.news.installed.v1`(Bool, 기본 false)은 한 번 추가한 뒤 true이며, 기존 ID가 있으면 중복 추가하지 않는다. 삭제·재정렬 후 자동 복원하지 않는다. 기사 캐시는 Android SharedPreferences `launcher_news`의 `multi_v5_<분야>` JSON, iPad UserDefaults `ratio.news.cache.<분야>.v5` JSON Data에 분야별 최대 1200개(매체당 최대 15개)를 저장한다. 항목은 title/url/summary/published/source, 묶음은 items/fetched/sourceFetched/partial이다. source는 `docs/news_publishers.json`의 안정적인 74개 언론사 ID이며 출처별 마지막 성공 시각(sourceFetched)을 따로 보존한다. 일부 출처가 실패해도 성공한 출처는 갱신하며 실패 출처의 기존 기사는 그 출처의 원래 수신 시각부터 24시간 이내에만 유지한다. 목록 전체 수신 시각을 새로 써도 오래된 출처의 수명을 연장하지 않는다. 본문·이미지는 저장하지 않는다. 기존 v1·v2·v3 기사 캐시는 읽지 않고 제거한다. v4 분야 캐시는 현재 분야에 연결된 출처만 남기고 제목·소개를 HTML 정리해 복원하며 다음 저장 때 v5로 바꾼다. v4 최신 전체 캐시는 사용하지 않고 제거한다. 최신은 선택 분야의 유효 캐시로 매번 구성하고 별도로 저장하지 않는다. 관심 분야는 Android `launcher_news/selected_topics_v1` 문자열 집합, iPad `ratio.news.selected.topics.v1` 문자열 배열에 저장한다. 키가 없으면 사회·경제·문화, 빈 집합은 수신 없음이다. 현재 보고 있는 탭·읽기 위치·새 목록 대기·전체 실패 후 5분 재시도 대기는 세션 메모리에만 유지한다. partial 캐시는 재시작해도 5분 기준으로 다시 요청하되 출처별 마지막 성공부터 2시간 이내 결과는 재사용한다. 재사용한 출처의 마지막 성공 시각은 보존한다. 분야별 RSS가 없는 매체는 그 분야의 실패로 계산하지 않는다. 기존 날씨·타이머·웹·데이지 저장소와 분리한다.

## 뉴스 백그라운드 저장

캐시 형식은 v5이며 분야 설정과 수신에 공유한다. Android `launcher_news/background_enabled`(Bool, 기본 false), iPad `ratio.news.background.enabled`(Bool, 기본 false)는 뉴스 위젯 배치 여부를 저장한다. 삭제 시 false로 바꾸고 예약을 취소한다. 최신 캐시를 재시작 시 복원하고 최초 성공 출처·이후 12개 출처마다 같은 캐시에 중간 저장한다. Android는 IO 디스패처의 SharedPreferences commit 이후 메모리/StateFlow revision을 갱신하며 메모리 캐시 접근은 동기화한다. iPad는 MainActor 공유 LauncherNewsStore와 UserDefaults v5를 사용하고 읽은 적 없는 분야·앱 백그라운드 세션의 새 목록은 즉시 공유 캐시에 반영한다. 화면에서 읽는 중에는 새 목록을 대기시킨다. 소스별 기존 수신 시각을 연장하지 않는다. 오래된/누락된 출처부터 시도해 시스템이 작업을 중단해도 같은 첫 출처만 반복하지 않는다.

### 뉴스 분야와 표시 텍스트

뉴스 목록은 `docs/news_publishers.json`의 74개 매체 등록부에서 확인된 **분야 전용 RSS만** 사용한다. 최신은 별도 전체 RSS를 요청하지 않고 사용자가 고른 분야의 캐시만 합친다. 기본 선택은 사회·경제·문화이고, 상단 ‘뉴스 분야 설정’에서 정치·국제·IT·과학·건강·스포츠·연예를 포함한 9개 분야를 복수 선택해 저장한다(‘IT·과학’은 한 분야). 설정은 재시작 후에도 유지하며 모든 분야를 끄면 안내만 표시하고 수신하지 않는다. 분야 탭도 선택한 것만 표시한다. 현재 사회·경제·문화에는 기존 8개 매체, 정치·국제·스포츠에는 뉴시스·SBS·동아일보, 연예에는 뉴시스·SBS, IT·과학에는 뉴시스·동아일보, 건강에는 동아일보를 연결한다. 뉴시스 IT·바이오와 동아일보 IT·의학은 IT·과학에 포함한다. 매체가 분류한 분야를 따르며 별도의 의미 분류는 하지 않는다. 분야 피드가 없는 매체는 전체/다른 분야로 대체하지 않는다. 전체 피드 주소는 등록부의 참고 자료로만 보존하며 자동 수신에는 사용하지 않는다. 사용자별 언론사 선택 화면은 포함하지 않는다. 제목과 소개는 길이를 자르기 전에 HTML 엔티티 해제와 태그 제거를 최대 6회 반복하고 마지막 잔여 태그·이미지 자리 문자·공백을 정리한다. script/style 본문과 닫히지 않은 태그도 제거하며 숫자 엔티티와 중첩 인코딩을 처리한다. 저장된 분야 캐시에도 같은 정리를 적용한다. HTML 렌더러나 외부 이미지 요청은 사용하지 않는다.

## 앱 시작 홈과 미디어 탐색 표시

iPad UserDefaults `home.launcher.v1` 문자열은 `standard`(기본) / `widgets`, `home.media.visible.v1` Boolean은 기본 true다. `AppHomeRoot`와 기존 홈·설정은 같은 AppStorage 키를 사용한다. `standardHome` 경로는 저장된 위젯 런처 선택과 관계없이 기존 홈을 연다. 기존 목록형/카테고리형·위젯 배치·로그인·즐겨찾기 값은 유지한다.
