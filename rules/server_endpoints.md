# 외부 서버 / 클라우드 서비스

점검일 2026-09-29 · 기준 코드 `babc3875`

VisionCraft iPad 앱이 사용하는 모든 외부 URL과 클라우드 서비스 목록.

## 호스트 한눈에

| 호스트 | 용도 |
|---|---|
| `rivo.me` | 앱 글꼴 매니페스트 + 글꼴 파일 배포 (GET) |
| `rivo-oracle.duckdns.org` | VisionLink 시그널링 서버 (REST + WebSocket) |
| Firebase / Google AI | Gemini `gemini-2.5-flash-lite` (Firebase AI Logic, App Check) — [firebase_services.md](firebase_services.md) |
| `huggingface.co` | MLX 로컬 모델 다운로드 (`swift-transformers` `HubApi` 기본 엔드포인트) |
| `www.google.com`, `policies.google.com` | 검색 진입점 링크 / 개인정보 링크 (UI 링크만) |

안드로이드에 있던 SKT Vision API, `rivo.me/app/VisionCraft/update/*` APK 업데이트, `daisy.local` 가상 호스트는 **iOS 에 없다**. 이미지 설명은 Gemini, 업데이트는 App Store/TestFlight, EPUB/DAISY 는 네이티브 파서.

## rivo.me 글꼴 매니페스트

`Settings/AppFontCatalog.swift` · `AppFontCatalogStore.manifestURL`

| 항목 | 값 |
|---|---|
| URL | `https://rivo.me/app/VisionCraft/fonts/manifest.json` |
| 인증 | 없음 (공개 GET) |
| 스키마 | `AppFontManifest` — `schemaVersion`(=1), `generatedAt`, `baseUrl`, `fonts[]` (`key`, `labels`, `scripts`, `license`, `licenseUrl`, `files`) |
| 한도 | 매니페스트 256 KiB, 글꼴 32개, 글꼴 파일당 32 MiB (`AppFontManifestParser`) |
| 신뢰 조건 | 응답 URL 이 `https` + host `rivo.me` + port/user/password/query/fragment 없음 (`AppFontCatalogStore.TrustedResponseKind`) — 리다이렉트로 다른 호스트에 가면 거부 |
| 저장 | Application Support `VisionCraft/AppFonts/` + 로컬 `manifest.json` 사본, 무결성은 `AppFontIntegrity` (SHA) |
| 선택 키 | UserDefaults `settings.fontChoice.v1`, 기본 `system` (Android 처럼 시스템 글꼴), 번들 글꼴 `NanumSquareRoundOTFEB` |

## VisionLink 시그널링 서버

`VisionLink/VisionLinkModels.swift` · `VisionLinkContract`, `VisionLink/VisionLinkServerClient.swift`

| 항목 | 값 |
|---|---|
| Base URL | `https://rivo-oracle.duckdns.org/visionlink` |
| `POST {base}/sessions` | body `{"receiverName"}` → 페어링 코드·`websocketUrl`·ICE 서버·`ttlSeconds`/`expiresAt` (`VisionLinkSessionResponse`) |
| `POST {base}/pairs/{pairID}/connect` | body `{"role":"receiver","deviceId","deviceToken","deviceName"}` → 재접속 (`VisionLinkReconnectResponse`) |
| `POST {base}/pairs/{pairID}/delete` | body `{"role","deviceId","deviceToken"}` — 페어 해제 |
| 타임아웃 | `URLRequest.timeoutInterval = 12`, `Content-Type: application/json; charset=utf-8` |
| 이후 채널 | 응답의 `websocketUrl` (`wss`/`ws`) 로 `URLSessionWebSocketTask` 시그널링, WebRTC 미디어는 서버가 준 ICE 서버(`urls`/`username`/`credential`) 사용 |
| 인증 | `deviceToken` (본문). 자격 증명은 Keychain 서비스 `net.rivo.visioncraft.visionlink`, 계정 `receiver` (`VisionLinkCredentialStore`) |
| 404 처리 | 재접속이 404 면 Keychain 을 지우고 새 세션 생성 (`VisionLinkManager.launchConnection`) |

상세는 [visionlink.md](visionlink.md).

## Firebase AI Logic (Gemini)

- 호출 코드: `FirebaseAI.firebaseAI(backend: .googleAI()).generativeModel(modelName: "gemini-2.5-flash-lite", …)` — `LLM/GeminiVisionService.swift`, `LLM/WebSearchService.swift` · `GeminiGoogleSearchService`, `OCRCorrectionService.swift` · `GeminiOCRCorrectionService`, `Documents/ExcelAICommandService.swift`, `Documents/WordAICommandService.swift`.
- 인증: 클라이언트에 API 키 저장 없음. Firebase App Check (실기 App Attest / 시뮬레이터 Debug provider). `GoogleService-Info.plist` 의 `API_KEY` 는 Firebase 기본 키.
- Google Search grounding: `Tool.googleSearch()` (`GeminiGoogleSearchService.generate`).

## Hugging Face (로컬 모델)

`LLM/LLMService.swift` · `LLMService.makeHub`, `LLM/LocalModelDownloader.swift`

- `HubApi(downloadBase: <Application Support>/HFModels, useOfflineMode:)` — 엔드포인트는 `swift-transformers` 기본값 (`https://huggingface.co`), 코드에 URL 하드코딩 없음.
- 저장소: `mlx-community/Qwen3.5-4B-MLX-4bit`, `mlx-community/Qwen3.5-9B-MLX-4bit`, `mlx-community/Qwen3-VL-8B-Instruct-4bit`, `mlx-community/Qwen3-8B-4bit`, `mlx-community/Ministral-3-8B-Instruct-2512-4bit` (모델 선택은 [gemini_ai.md](gemini_ai.md)).
- 인증 없음(공개 리포). 오프라인이면 `useOfflineMode: true` 허브로 스냅샷만 검증 (`LocalModelSnapshotValidator`).

## 일일 한도 / 토큰 회계

`LLM/CloudAITokenBudgetStore.swift` · `CloudAITokenBudgetStore`

| 항목 | 값 |
|---|---|
| `dailyLimit` | `1_000_000` 토큰/일 (모든 Gemini 호출 합산) |
| 저장 | App Group `group.net.rivo.visioncraft` UserDefaults 키 `cloudAI.tokenBudget.today.v1` (`dayIdentifier` `yyyy-MM-dd`, 날짜 바뀌면 리셋) |
| 흐름 | `reserve(inputTokens: countTokens 결과, maximumOutputTokens:)` → 성공 시 `commit(_, actualTokens: usageMetadata.totalTokenCount)` (없으면 예약량 차감) / 실패·취소 시 `cancel` |
| 초과 오류 | `CloudAITokenBudgetError.dailyLimitExceeded` — "오늘의 클라우드 AI 100만 토큰을 모두 사용했습니다. 내일 다시 이용해 주세요." |
| 테스트 리셋 | `refillForTesting()` — `DEBUG`/`WORD_AI_LIVE_EVAL`/`WORD_AI_LIVE_SMOKE` 빌드에서만 |

로컬 AI 는 한도 없이 통계만 기록: `LLM/LocalAIUsageStore.swift` (App Group 키 `localAI.usage.today.v1`, 위젯 `LocalAIUsageWidget`).

## 인증 / API 키 요약

| 채널 | 인증 | 저장 위치 |
|---|---|---|
| rivo.me 글꼴 | 없음 | — |
| VisionLink | `deviceToken` (서버 발급) | Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) |
| Firebase AI | App Check 토큰 | — (SDK 관리) |
| Hugging Face | 없음 | — |
| ~~Brave Search API 키~~ | 제거됨 — `WebSearchConfigurationStore.removeLegacyBraveCredentialIfNeeded` 가 Keychain 서비스 `com.rivo.shortcuts-example.web-search` / 계정 `brave-search-api-key` 를 첫 실행 때 삭제 (`webSearch.removedBraveCredential.v1`) | — |

## 네트워크 호출이 아닌 URL

- `https://rivo.net/spreadsheet/2026` — XLSX 확장 속성 XML 네임스페이스 (`ExcelAdvancedWorkbookEditing.swift`), 요청 아님.
- `schemas.openxmlformats.org`, `www.hancom.co.kr/hwpml/2011/*`, `www.idpf.org/2007/opf` — OOXML/HWPML/EPUB 네임스페이스.
- `backend/excel-ai-groq-worker/` — 저장소에 있는 Cloudflare Worker. **Swift 코드에서 참조하지 않는다** (grep `groq` 0건).
