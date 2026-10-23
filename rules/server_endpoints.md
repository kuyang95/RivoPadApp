# 외부 서버 / 클라우드 서비스

점검일: 2026-10-23 · 기준 코드: `c25bf291` (이번 기능 변경 범위) · 런처 유틸리티 대조: 2026-10-22 `514e00f5`+작업 트리 · 현재 위치 날씨 대조: 2026-10-22 `f56b06f0`+작업 트리 · 날씨 30분 갱신·큰 글자·원형 새로고침 대조: 2026-10-23 `f56b06f0`+작업 트리 · 전체 페이지 뉴스 위젯 대조: 2026-10-23 `2d5aae7e`+작업 트리 · 다중 언론사 뉴스 대조: 2026-10-23 `2d5aae7e`+작업 트리 · 뉴스 출처·표본 확대 대조: 2026-10-23 `2d5aae7e`+작업 트리 · 뉴스 74개 매체 목록 대조: 2026-10-23 `2d5aae7e`+작업 트리 · 뉴스 2시간 백그라운드 캐시 대조: 2026-10-23 `2d5aae7e`+작업 트리 · 뉴스 선택 분야 수신·HTML 정리 대조: 2026-10-23 `2d5aae7e`+작업 트리

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
| `dailyLimit` | 기기 내 앱 설치당 `1_000_000` 토큰/일 (모든 Gemini 호출의 입력·출력 합산). 서버나 계정 전체의 사용량 제한은 아님 |
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

## 런처 날씨 (Open-Meteo)

현재 위치 예보에 `https://api.open-meteo.com/v1/forecast`를 GET 요청한다. current=temperature_2m,apparent_temperature,weather_code, daily=temperature_2m_max,temperature_2m_min, forecast_days=1, timezone=auto다. 기기에서 일회성으로 얻은 현재 위치를 소수 둘째 자리로 반올림해 좌표만 전송한다. 도시 검색 API는 호출하지 않고 지역 이름은 OS 지오코더로 얻는다. 요청 제한 시간은 12초, 보이는 위젯·앱 활성 상태에서만 30분 간격 또는 명시적 새로고침으로 호출한다. 화면 복귀 때 신선한 자료는 재사용하며 실패는 5분 뒤 재시도한다. 자료 시각과 Open-Meteo 출처를 표시한다. 무료 공개 엔드포인트는 비상업 개발용이며 상업 배포 전 서비스 이용 조건에 맞는 customer API 계약·인증 경로가 필요하다. API 키는 번들에 추가하지 않았다. 규격: https://open-meteo.com/en/docs.

### 날씨 갱신 수명

날씨 자동 갱신은 마지막 성공 시각 기준 30분 간격으로 보이는 페이지·앱 활성 상태에서만 실행한다. 화면 복귀 때 30분 미만의 자료는 위치 재조회 없이 재사용하고, 오래됐거나 자료가 없으면 즉시 위치 한 번과 예보를 요청한다. 수동 새로고침은 신선도·재시도 대기를 한 번만 무시하며 로딩 중 중복 입력은 막는다. 실패하면 지역명·날씨를 함께 보존하고 갱신 시각·오류를 표시하며 5분 뒤 재시도한다. 실패 대기는 메모리에만 유지하고 페이지 복귀가 대기를 초기화하지 않는다. 캐시는 최대 6시간까지만 표시하며 미래 시각·6시간 이상 자료는 제거한다. 위치 권한이 거부되면 이전 날씨를 숨기고 권한 설정을 안내한다. 위치와 예보는 성공 시 함께 교체하며 주기 위치 구독·백그라운드 예약 작업은 없다.

## 전체 페이지 뉴스 위젯

뉴스 목록은 `docs/news_publishers.json`의 74개 매체 등록부에서 확인된 **분야 전용 RSS만** 사용한다. 최신은 별도 전체 RSS를 요청하지 않고 사용자가 고른 분야의 캐시만 합친다. 기본 선택은 사회·경제·문화이고, 상단 ‘뉴스 분야 설정’에서 정치·국제·IT·과학·건강·스포츠·연예를 포함한 9개 분야를 복수 선택해 저장한다(‘IT·과학’은 한 분야). 설정은 재시작 후에도 유지하며 모든 분야를 끄면 안내만 표시하고 수신하지 않는다. 분야 탭도 선택한 것만 표시한다. 현재 사회·경제·문화에는 기존 8개 매체, 정치·국제·스포츠에는 뉴시스·SBS·동아일보, 연예에는 뉴시스·SBS, IT·과학에는 뉴시스·동아일보, 건강에는 동아일보를 연결한다. 뉴시스 IT·바이오와 동아일보 IT·의학은 IT·과학에 포함한다. 매체가 분류한 분야를 따르며 별도의 의미 분류는 하지 않는다. 분야 피드가 없는 매체는 전체/다른 분야로 대체하지 않는다. 전체 피드 주소는 등록부의 참고 자료로만 보존하며 자동 수신에는 사용하지 않는다. 사용자별 언론사 선택 화면은 포함하지 않는다. 전체 고정 URL·언론사 ID·원문 허용 호스트는 [목록](../docs/news_publishers.md)과 JSON에 유지하며 두 프로젝트의 생성 스크립트가 같은 원본을 사용한다. 제목과 소개는 길이를 자르기 전에 HTML 엔티티 해제와 태그 제거를 최대 6회 반복하고 마지막 잔여 태그·이미지 자리 문자·공백을 정리한다. script/style 본문과 닫히지 않은 태그도 제거하며 숫자 엔티티와 중첩 인코딩을 처리한다. 저장된 분야 캐시에도 같은 정리를 적용한다. HTML 렌더러나 외부 이미지 요청은 사용하지 않는다. 갱신 중단·다른 매체 링크·HTML·접근 제한 응답을 제공하는 후보는 연결하지 않고 사유를 목록에 남긴다.

최대 동시 수신은 세 개이며 대기 요청은 슬롯이 생길 때 시작한다. 매체당 연결/읽기 제한 12초·수신 처리 제한 15초·응답 최대 2MiB이다. XML 문서형·외부 엔티티는 허용하지 않는다. UTF-8 및 EUC-KR/KS C 5601 선언을 지원한다. 본문 전문·이미지·추적 픽셀은 로드하지 않으며 제목 240자·소개 160자·발행 시각·언론사만 유지한다. 매체당 후보 30개 중 표시 15개, 전체 상한 1200개다. 원문은 각 매체의 지정된 HTTPS 호스트만 허용하고 같은 매체의 유효한 RSS guid를 우선한다. 지정 매체의 http 원문은 https로 올리고 HTML amp 엔티티를 정리한다. 수신용 FeedBurner·CDN 호스트를 원문 호스트로 허용하지 않는다. 날짜는 RFC 1123(요일 유무·월 이름/숫자)·ISO 8601 pubDate/dc:date·한국 시각 `yyyy-MM-dd HH:mm:ss`를 읽고 쉼표 간격·앞뒤 공백·줄바꿈을 정리한다.

일부 출처 실패 시 그 출처의 24시간 이내 기존 캐시와 성공한 결과를 합치며 실패한 출처의 저장 시각을 갱신하지 않는다. 일부 실패는 5분 뒤 다시 시도하되 출처별 성공 후 2시간 이내인 결과는 재사용한다. 수동 새로고침은 신선한 출처도 다시 요청한다. 모두 성공한 목록은 2시간 간격이다. 인증 키·중계 서버·사용자 관심사 전송은 없다. RSS는 개인 기기의 리더에서 직접 표시하며 재배포 서버를 만들지 않는다.

## 뉴스 사전 수신과 실행 제한

뉴스 위젯이 배치되어 있으면 사용자가 선택한 분야만 약 2시간마다 화면 밖에서 미리 받아 저장한다. 최신용 전체 피드를 별도로 받지 않는다. 분야를 바꾸면 표시 중인 최신·대기 목록을 비우고 새 선택으로 합치며 진행 중인 수신도 비선택 분야의 추가 요청·결과 반영을 중단한다. 이미 시작한 요청은 종료/취소될 수 있으나 비선택 기사가 최신에 섞이지 않는다. 앱/런처 진입 시에도 예약과 별도로 조용히 보충하되 2시간 이내 캐시는 재사용한다. 정기 예약이 실제 실행될 때는 다시 수신해 예약 경계에서 갱신이 4시간으로 밀리지 않게 한다. 화면은 저장된 목록을 먼저 표시하며 캐시가 전혀 없으면 최초 성공한 출처부터 표시하고 이후 12개 출처 처리마다 중간 결과를 저장한다. 읽는 중 들어온 후속 목록은 ‘새 뉴스가 있어요 · 보기’로 적용해 읽기 위치를 유지한다. 동시 수신은 3개이고 캐시가 없거나 가장 오래된 출처부터 수신한다. 작업이 중단되어도 이미 저장된 결과는 남는다. 수동 새로고침은 캐시 신선도와 관계없이 수신한다. 뉴스 위젯 삭제 시 백그라운드 예약·진입 시 보충을 중지한다. 최초 설치·장시간 오프라인 등으로 캐시가 없으면 통신이 필요하다. 예약 시각은 운영체제의 절전·네트워크 상태에 따라 늦어질 수 있어 정확한 2시간 실행을 보장하지 않는다.

Android는 기존 WorkManager 2.9.1을 사용하고 연결된 네트워크·배터리 부족 아님 조건을 둔다. iPad는 네트워크가 필요한 BGProcessingTask를 쓰며 외부 전원을 필수로 요구하지 않는다. 추가 서버나 새 인증 키는 없다.
