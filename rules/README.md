# VisionCraft iPad (RivoPadApp) — Rules / Knowledge Base

이 폴더는 VisionCraft iPadOS 앱(Xcode 프로젝트 `shortcuts_example`)의 **메타 정보와 외부 의존성** 을 정리한 곳. 새 대화 세션에서 코드베이스를 읽지 않고도 빠르게 파악할 수 있는 정보 (서버 URL, 모델명, SDK 버전, UUID, UserDefaults 키 등) 위주. 안드로이드 쌍둥이 앱의 [VisionCraft/rules](../../../AndroidProject/VisionCraft/rules/README.md) 와 같은 구조·같은 작성 원칙을 따른다.

## ⚠️ 이 문서를 사용하는 LLM 에게

**문서 내용에 오류를 발견하거나 코드 변경으로 내용이 달라졌다면 반드시 해당 규칙 파일을 즉시 수정할 것.** 사용자가 따로 시키지 않아도 알아서 동기화. 이 문서는 다음 세션의 자신을 위한 인계자료이므로 stale 한 정보는 적극적으로 정정.

- 오류 발견 → 해당 파일 즉시 수정 + 변경 사유 commit 메시지에 명시
- 코드 변경 작업 후 → 영향받는 규칙 파일도 같은 커밋에서 업데이트
- 새로 알게 된 비자명한 도메인 지식 → 적절한 파일에 추가하거나 신규 파일 작성
- 더 이상 유효하지 않은 항목 → 삭제 (deprecated 표시만 하지 말고 깨끗하게 제거)

## 문서 색인

| 파일 | 내용 |
|---|---|
| [app_metadata.md](app_metadata.md) | 번들 ID, App Group, 타깃/익스텐션(share·action·widget), 버전, 배포 타깃, 서명, entitlements, Info.plist 키, App Shortcuts/Intents |
| [server_endpoints.md](server_endpoints.md) | 외부 호스트 (rivo.me 글꼴 매니페스트, Firebase AI Logic/Gemini, VisionLink 시그널링 서버, Hugging Face), 인증 방식, 일일 토큰 한도 |
| [firebase_services.md](firebase_services.md) | Firebase Pod(AI Logic/App Check/Core), GoogleService-Info 키 이름, App Check provider, 개발 빌드 경고, 손패치한 Pod 파일 |
| [gemini_ai.md](gemini_ai.md) | Gemini 모델명/온도/토큰 한도, 시스템 프롬프트, 웹 검색 라우팅, grounding, 로컬(MLX) vs 클라우드 분담, 음성 인텐트 분류, 토큰 회계 |
| [ble_protocol.md](ble_protocol.md) | Rivo 리모컨 BLE: Nordic UART UUID, 기기 식별, 패킷 조립/파싱, 키 → 액션 매핑, 빠른 메뉴/명령 모드/화면별 모드 |
| [dependencies.md](dependencies.md) | CocoaPods + SwiftPM 패키지 버전, 시스템 프레임워크, 번들 ONNX 모델/글꼴, 손패치 Pod, 시뮬레이터 제약 |
| [persistence.md](persistence.md) | UserDefaults 키(standard/App Group), 파일 저장 경로(Application Support/Caches/App Group), Keychain, 에셋 |
| [scanner_pipeline.md](scanner_pipeline.md) | 자체 문서 스캐너: LCNet 모서리 검출, 자동 셔터 게이트, PaperEdgeRefiner, 원근/색상 보정, UVDoc 평탄화, ML Kit OCR + Gemini 교정 |
| [visionlink.md](visionlink.md) | VisionLink 수신기: 페어링 REST/WebSocket, WebRTC 영상·데이터 채널, 원격 기능(이미지 분석·AI 채팅·실시간 읽기), Keychain 자격 증명. **안드로이드 rules 에는 대응 문서 없음** |

## 점검 기록

점검 = 문서 내용을 지금 코드와 대조해 확인한 것. 고친 게 없어도 확인했으면 점검이다.

| 문서 | 점검일 | 기준 코드 |
|---|---|---|
| app_metadata.md | 2026-09-29 | `babc3875` |
| server_endpoints.md | 2026-09-29 | `babc3875` |
| firebase_services.md | 2026-09-29 | `babc3875` |
| gemini_ai.md | 2026-09-29 | `babc3875` |
| ble_protocol.md | 2026-09-29 | `babc3875` |
| dependencies.md | 2026-09-29 | `babc3875` |
| persistence.md | 2026-09-29 | `babc3875` |
| scanner_pipeline.md | 2026-09-29 | `babc3875` |
| visionlink.md | 2026-09-29 | `babc3875` |

문서를 코드와 대조해 확인할 때마다 **무조건**:

1. 그 문서 맨 위 `점검일 · 기준 코드` 줄과 이 표의 같은 줄을 그날 날짜로 고친다. 처음 점검하는 문서면 제목 바로 아래에 그 줄을 넣고 표에 행을 추가한다.
2. 기준 코드는 대조한 코드의 커밋(`git log -1 --format=%h -- shortcuts_example/`).
3. 고친 내용 없이 맞는 것만 확인했어도 갱신한다.
4. 코드를 바꾸면서 문서 일부만 맞춘 것은 점검이 아니므로 점검일은 그대로 둔다.

## 코어 개념 한 줄 요약

- **VisionCraft iPad** = 시각장애인용 iPadOS 보조앱. 번들 ID `net.rivo.visioncraft`, App Group `group.net.rivo.visioncraft`, 표시 이름 `VisionCraft`. Xcode 타깃/폴더 이름은 역사적 이유로 `shortcuts_example`
- **로컬 우선** — 텍스트 AI 채팅·번역·음성 명령은 MLX(`mlx-swift-lm`) 로컬 모델(Qwen3.5 4B/9B 4bit, 홈에서 "M4 로컬 AI" 로 부름)로 기기 안에서 처리. Apple FoundationModels 는 사용하지 않는다
- **클라우드 AI 1개** — Firebase AI Logic → Gemini `gemini-2.5-flash-lite` (이미지 설명, Google Search grounding, OCR 교정, Excel/Word AI). App Check(App Attest)로 보호, 일일 1,000,000 토큰 예산 (`CloudAITokenBudgetStore`)
- **주요 기능** — 자체 문서 스캐너(LCNet + UVDoc + ML Kit Korean OCR), 카메라 돋보기/실시간 글자 읽기, HWP/HWPX/XLSX/DOCX/PDF 문서 뷰어·편집, EPUB/DAISY 리더, AI 채팅, 웹 검색, VisionLink(폰 카메라 수신)
- **BLE Rivo 리모컨** — Rivo Three / Rivo Mini. Nordic UART 계열 UUID, 키 문자 → `RivoButton` → 빠른 메뉴/명령 모드/화면별 액션 매핑 (`RivoRemote/`)
- **외부 호스트** — `rivo.me` (글꼴 매니페스트), `rivo-oracle.duckdns.org` (VisionLink 시그널링), Firebase/Google AI, `huggingface.co` (로컬 모델 다운로드)
- **익스텐션 3개** — 공유(share), 액션(action), 위젯(widget). App Intents / App Shortcuts 는 본 앱 타깃 안에 있고 별도 intent 익스텐션 타깃은 없다
- **시뮬레이터 불가** — ML Kit Pod 이 arm64 시뮬레이터를 제외하므로 실기 iPad 에서만 빌드/테스트 ([dependencies.md](dependencies.md))

## 작성 원칙

- **코드 출처는 파일·클래스·함수 이름까지** — 모든 주장은 코드 출처와 함께 (`ChatWebSearchRouter.swift` · `ChatWebSearchRouter.requiresCurrentInformation` 형식). 줄 번호는 코드를 조금만 고쳐도 틀어지므로 적지 않는다
- **상수/UUID/URL 그대로 인용** — 줄임 금지
- **"왜" 가 비자명할 때만 설명** — 코드만 봐서는 알 수 없는 도메인 지식, 과거 사고, 펌웨어 제약, Android 와의 차이 등
- **변경 시 동기화** — 코드 변경하면 해당 규칙도 업데이트 (위 ⚠️ 섹션 참조)
- **오류 발견 시 즉시 정정** — 자신이 작성한 문서더라도 잘못된 내용 보면 바로 고침
- **비밀값 금지** — `GoogleService-Info.plist` 등의 키 값은 적지 않고 키 이름만 적는다
