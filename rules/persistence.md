# 영속 데이터 (UserDefaults / App Group / 파일 / Keychain / Assets)

점검일 2026-10-06 · 기준 코드 `c0b9f54a`

Room DB, EncryptedSharedPreferences 에 해당하는 것은 없다. 구조화 데이터는 전부 **JSON 파일** 또는 **UserDefaults(Codable 인코딩)**.

## UserDefaults.standard 키

| 키 | 타입/기본 | 출처 |
|---|---|---|
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
| `display.app.interfaceInverted` / `display.app.orientation` | Bool / `AppDisplayOrientation` raw | `shortcuts_exampleApp.swift` `@AppStorage` |
| `camera.display.colorIndex.v1` / `camera.display.colorInverted.v1` / `camera.display.threshold.v1` | Int / Bool / 값 | `CameraTools/MagnifierDisplayPreferenceStore.swift` — 돋보기 Android 호환 색상 조합 복원 |
| `webSearch.enabled.v1` / `webSearch.automaticChat.v1` / `webSearch.removedBraveCredential.v1` | Bool (앞의 두 설정은 기본 true, 저장된 false는 유지) | `LLM/WebSearchConfigurationStore.swift` |
| `reader.epub.lastBookPath` | String | `Reader/EPUBLibraryStore.swift` |
| `reader.epub.progress.<base64(bookID)>` / `reader.epub.chapter.<base64(bookID)>` | 진행률 / 챕터 | 〃 `progressKey` / `chapterKey` |
| `RecentOriginalDocumentStore.records.v1` | JSON, 최대 100건 | `Documents/RecentOriginalDocumentStore.swift` |
| `AuthorizedDocumentLibrary.bookmark.v1` / `AuthorizedDocumentLibrary.folderName.v1` | security-scoped bookmark Data / String | `Documents/AuthorizedDocumentLibrary.swift` — 사용자가 고른 문서 폴더 |
| `rivo.remote.connectionDiagnostics` | JSON, 최근 80건 | `RivoRemote/RivoRemoteManager.swift` · `DefaultsKey`. 기기 UUID·타입·Bluetooth 활성화 이력은 저장하지 않고, 초기화 시 이전 버전의 `rivo.remote.peripheralIdentifier` / `rivo.remote.deviceType` / `rivo.remote.hasActivatedBluetooth` 값을 제거한다 |
| `LocalDocumentAppearance.v1` | `LocalDocumentAppearance` JSON (fontLevel, lineHeightLevel, colorIndex, showsLineSeparators) — 문서 뷰어 글자/줄간격/색상 | `Documents/LocalDocumentReading.swift` |

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
| `Assets.xcassets` | `AppIcon`, `AccentColor`, `LaunchBackground`, `LaunchLogo`, 홈 타일 4종 (`HomeTileAIChat/Camera/PhoneLink/Reading`), `TextOpenSourceIllustration` |
| `AppShortcuts.xcstrings` | App Shortcut 문구 |
