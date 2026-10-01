# 앱 메타데이터 / 빌드 정보

점검일 2026-09-29 · 기준 코드 `babc3875`

`shortcuts_example.xcodeproj/project.pbxproj`, `shortcuts-example-Info.plist`, `*.entitlements` 출처. 코드 안 봐도 한눈에 알 수 있는 정보만.

## 식별자 & 버전

| 항목 | 값 |
|---|---|
| 앱 번들 ID | `net.rivo.visioncraft` (`PRODUCT_BUNDLE_IDENTIFIER`) |
| App Group | `group.net.rivo.visioncraft` (앱 + 3개 익스텐션 전부) |
| `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` | `1.0` / `1` (전 타깃 동일) |
| `IPHONEOS_DEPLOYMENT_TARGET` | `26.2` (pbxproj + `Podfile` `platform :ios, '26.2'` + `post_install` 로 Pod 타깃에도 강제) |
| `TARGETED_DEVICE_FAMILY` | 앱 `"1,2,7"` (iPhone/iPad/Vision), 익스텐션·테스트 `"1,2"` |
| `SWIFT_VERSION` | `5.0` |
| Swift 동시성 설정 | `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES` (앱·익스텐션). 그래서 격리가 필요 없는 타입은 명시적으로 `nonisolated` 를 붙인다 |
| Debug 컴파일 조건 | `SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)"`. 라이브 AI 테스트 플래그(`EXCEL_AI_LIVE_*`, `WORD_AI_LIVE_*`)는 `OTHER_SWIFT_FLAGS` 로 넘긴다 |
| `developmentRegion` | `ko` (로컬라이즈: `ko.lproj` / `en.lproj` / `ja.lproj`) |
| 프로젝트 포맷 | `objectVersion = 77`, `LastUpgradeCheck = 2620` (Xcode 26) |
| 테스트 번들 | `net.rivo.visioncraftTests` (`shortcuts_exampleTests/`, 115개 항목) |

## 타깃 / 익스텐션

| 타깃 | productType | 번들 ID | 표시 이름 | 비고 |
|---|---|---|---|---|
| `shortcuts_example` | application | `net.rivo.visioncraft` | `VisionCraft` | 본 앱. `@main struct shortcuts_exampleApp` (`shortcuts_exampleApp.swift`) |
| `shareExtension` | app-extension | `net.rivo.visioncraft.shareExtension` | `VisionCraft로 공유` | `com.apple.share-services`. 활성 규칙: 텍스트, 이미지 ≤20, 파일 ≤20, 웹 URL 1. `ShareViewController` 가 App Group `ShareInbox/` 에 저장 후 `rivopad://share-inbox` 로 앱 열기 |
| `actionExtension` | app-extension | `net.rivo.visioncraft.actionExtension` | `VisionCraft에 질문` | `com.apple.ui-services`, 텍스트만. `ActionViewController.maximumTextCharacters = 200_000` |
| `rivoWidget` | app-extension | `net.rivo.visioncraft.rivoWidget` | `Rivo 상태` | `com.apple.widgetkit-extension`. `RivoWidgetBundle` = `RivoStatusWidget`(small/medium) + `VisionCraftShortcutWidget`(small, AppIntent 구성) + `LocalAIUsageWidget`(small) + `VisionCraftQuickLaunchControl`(ControlWidget) |

- `appIntentExtension/`, `intentExtension/`, `intentExtensionUI/` 폴더는 비어 있고 pbxproj 에 타깃도 없다. App Intents 는 본 앱 타깃 안에 있다.
- 공유 익스텐션 지원 문서 확장자: `epub`, `hwp`, `hwpx`, `pdf`, `txt`, `text`, `xls`, `xlsx` (`ShareViewController.supportedDocumentExtensions`). 항목당 100 MiB, 배치 250 MiB / 20개.

## 서명

- `CODE_SIGN_STYLE = Automatic`, `DEVELOPMENT_TEAM = Z3TXJ872H6` (전 타깃).
- 기기 빌드는 `-allowProvisioningUpdates` 로 실행 (시뮬레이터 불가 — [dependencies.md](dependencies.md)).
- `ENABLE_USER_SCRIPT_SANDBOXING = NO` (프로젝트 레벨).

## Entitlements

| 파일 | 키 | 값 |
|---|---|---|
| `shortcuts_example/shortcuts_example.entitlements` | `com.apple.developer.devicecheck.appattest-environment` | `$(APP_ATTEST_ENVIRONMENT)` → Debug `development`, Release `production` |
| 〃 | `com.apple.developer.kernel.increased-memory-limit` | `true` (MLX 로컬 모델 5~8 GiB 메모리 정책 — [gemini_ai.md](gemini_ai.md)) |
| 〃 + 익스텐션 3개 | `com.apple.security.application-groups` | `group.net.rivo.visioncraft` |

## Info.plist (`shortcuts-example-Info.plist`)

| 키 | 값 / 비고 |
|---|---|
| `CFBundleURLTypes` | scheme `rivopad`, name `net.rivo.visioncraft.share-inbox` |
| `CFBundleDocumentTypes` | XLSX (`org.openxmlformats.spreadsheetml.sheet`, Editor/Owner), XLS (`com.microsoft.excel.xls`, Viewer/Owner), HWP (`net.rivo.visioncraft.hwp`, Viewer/Alternate), HWPX (`net.rivo.visioncraft.hwpx`, Editor/Alternate) |
| `UTImportedTypeDeclarations` | `net.rivo.visioncraft.hwp` (`hwp`, `application/x-hwp`, conforms `public.data`), `net.rivo.visioncraft.hwpx` (`hwpx`, `application/hwp+zip`, conforms `public.archive`+`public.data`) |
| `LSSupportsOpeningDocumentsInPlace` / `UIFileSharingEnabled` | `true` — Files 앱과 iTunes 파일 공유에서 `Documents/` 노출 |
| `UIBackgroundModes` | `bluetooth-central` (Rivo 리모컨 백그라운드 유지) |
| `UIAppFonts` | 15개 파일 (NanumSquareRound EB, Batang/Gungsuh/Gulim/Dotum, Pretendard R/B, SUIT R/B, NanumSquareNeo Rg/Eb, MaruBuri R/B, PureBatang M/B). 출처·SHA 는 `shortcuts_example/HWP_FONT_SOURCES.md` |
| `UILaunchScreen` | 색 `LaunchBackground`, 이미지 `LaunchLogo` |
| `NSBluetoothAlwaysUsageDescription` | "Rivo Three 또는 Mini 리모컨을 검색하고 앱 내부 기능을 조작하기 위해 Bluetooth를 사용합니다." |

pbxproj 의 `INFOPLIST_KEY_*` (GENERATE_INFOPLIST_FILE=YES 로 병합):

| 키 | 값 |
|---|---|
| `NSCameraUsageDescription` | `for document scan` |
| `NSMicrophoneUsageDescription` | `음성 입력을 위해 필요합니다.` |
| `NSSpeechRecognitionUsageDescription` | `음성 인식을 위해 필요합니다.` |
| `NSMotionUsageDescription` | `문서 자동 촬영 중 기기 흔들림을 감지하기 위해 필요합니다.` (스캐너 `ScannerMotionMonitor`) |
| `NSPhotoLibraryAddUsageDescription` | `카메라에서 촬영한 사진을 사진 보관함에 저장하기 위해 필요합니다.` |
| `NSBluetoothAlwaysUsageDescription` | `Rivo 리모컨 연결을 위해 Bluetooth가 필요합니다.` (⚠️ plist 파일의 문구와 다름 — 어느 쪽이 최종 번들에 들어가는지 미확인) |
| `UISupportedInterfaceOrientations_iPad` | 4방향 전부 |

## 딥링크 / App Intents

- 딥링크 형식 `rivopad://open/<destination>` — `AppDeepLinkRouter.swift` · `AppDeepLinkRouter.destination(for:)`. host 는 `open`, path 1개. `AppDeepLinkDestination` raw 값: `settings`, `ai`, `ai-new`, `ai-history`, `reader`, `camera`, `magnifier`, `live-text`, `voice-action`, `scanner`, `files`, `text-viewer`, `rivo`, `vision-link`. `text-viewer`는 클립보드 글이 있으면 해당 글로, 없으면 빈 텍스트로 `AppRoute.textEditorText`를 연다. `camera`와 `magnifier`는 모두 홈의 카메라와 같은 `AppRoute.magnifier`를 연다. 위젯과 App Shortcut도 이 딥링크를 쓴다.
- 익스텐션 → 앱: `rivopad://share-inbox` (`ShareViewController.openContainingApp`, `ActionViewController.openContainingApp`). 위젯 상태 카드: `rivopad://open/rivo`.
- Shortcuts ↔ 앱 브리지: `ShortcutRouter.swift` · `ShortcutBridge` — App Group `UserDefaults` 키 `shortcut_last_envelope_v1` + 디렉터리 `ShortcutEnvelopes/`, 첨부는 `ShortcutLastAttachments/` (`AppBootstrap.prepareAppGroup`).

| Intent | title | 비고 |
|---|---|---|
| `OpenVisionCraftScreenIntent` | `VisionCraft 화면 열기` | `@Parameter screen: AppDeepLinkDestination`. `VisionCraftAppShortcuts` (AppShortcutsProvider) 가 설정/AI 채팅/독서/카메라/문서 스캔/돋보기/실시간 글자 읽기/파일 열기/Rivo 리모컨/VisionLink 10개 App Shortcut 등록 (`AppShortcuts.xcstrings`) |
| `LLMIntent` | `AI에게 요청하기` | 텍스트 + 요청문구 |
| `VoiceQueryIntent` | `음성 질의` | 이미지/문서 첨부 |
| `VMLIntent` (`VLMIntent.swift`) | `이미지 질의` | 이미지 + 질의문구 |
| `DocumentScanIntent` | `문서 스캔` | 스캐너 바로 열기 |
| `OCRIntent` (`OCRFromImageIntent.swift`) | `스크린샷 OCR` | 앱 열지 않고 `OCRService` 실행, 결과를 `OCRSharedStore` 에 저장 후 문자열 반환 |

모두 `openAppWhenRun = true` (OCRIntent 포함).

## 폴더 구조 (한눈에)

```
shortcuts_example/           # 앱 타깃 (Swift 300개)
├── (루트)                   # App 진입, AppRouter/DeepLink, OCRService, TTS/STT, SoundEffect, Firebase
├── CameraTools/             # 돋보기 · 실시간 글자 읽기 (MagnifierViewController)
├── DesignSystem/            # VisionCraft UI 컴포넌트
├── DocumentScan/            # 스캔 UI + CustomScanner/ (LCNet·UVDoc·Metal) + ScanSession/
├── Documents/               # 문서 라이브러리, Excel/Word AI·편집, HWP/ (HWP5·HWPX 파서/편집기)
├── Help/                    # 사용 설명서 JSON·매뉴얼·변경내역 txt
├── LLM/                     # MLX 로컬 LLM, Gemini 서비스, 웹 검색, 채팅 저장, 텍스트 추출기
├── Reader/                  # EPUB/DAISY 리더·라이브러리
├── RivoRemote/              # BLE 리모컨
├── Settings/                # AppSettingsStore, AppFontCatalog, LocalDiagnostics
├── Sharing/                 # SharedInboxStore/View
├── ShortcutIntent/          # App Intents
└── VisionLink/              # WebRTC 수신기
rivoWidget/ shareExtension/ actionExtension/   # 익스텐션 타깃
Tools/  docs/  backend/      # 도구 스크립트·설계 문서·Cloudflare worker (앱 코드에서 참조 안 함)
```
