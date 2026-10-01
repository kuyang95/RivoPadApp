# VisionLink (폰 카메라 → iPad 수신)

점검일 2026-09-29 · 기준 코드 `babc3875`

iPad 가 **수신기(receiver)** 로 시그널링 서버에 등록하고, 폰(companion) 이 페어링 코드로 붙어 WebRTC 로 영상·파일·텍스트를 보낸다. iPad 는 받은 이미지/문서를 로컬 AI 로 처리해 결과를 데이터 채널로 돌려준다. 코드는 `shortcuts_example/VisionLink/`. **안드로이드 rules 에는 대응 문서가 없다** (Android 쪽은 `visionlink/` 액티비티 3개만 존재).

## 서버 / 자격 증명

| 항목 | 값 | 출처 |
|---|---|---|
| Base URL | `https://rivo-oracle.duckdns.org/visionlink` | `VisionLinkModels.swift` · `VisionLinkContract.baseURL` |
| 역할 상수 | `receiverRole = "receiver"`, `p2pPreferred = "p2p-preferred"` (relayPolicy) | 〃 |
| REST | `POST /sessions`, `POST /pairs/{pairID}/connect`, `POST /pairs/{pairID}/delete` (JSON, 12초 타임아웃) | `VisionLinkServerClient.swift` |
| 기기 이름 | `UIDevice.current.name` (비면 `RivoPad`, 80자 제한) | `VisionLinkManager.init`, `VisionLinkServerClient.normalizedDeviceName` |
| 자격 증명 | `VisionLinkStoredCredentials {pairID, deviceID, deviceToken, isConfirmed}` → Keychain 서비스 `net.rivo.visioncraft.visionlink`, 계정 `receiver`, `AfterFirstUnlockThisDeviceOnly` | `VisionLinkCredentialStore.swift` |

## 연결 흐름

`VisionLinkManager.swift` · `VisionLinkManager` (`@StateObject`, 앱 전역)

```
activate()/retry() → launchConnection(forceNewSession:)
  Keychain 에 pair 있음 → reconnect: POST /pairs/{id}/connect (404 면 Keychain 삭제 후 새 세션)
  없음               → createSession: POST /sessions → pairingCode + websocketUrl + iceServers + ttl/expiresAt
  → openWebSocket(wss://…)  (URLSessionWebSocketTask, scheme wss/ws 만 허용)
  → 시그널링 이벤트 (VisionLinkJSON.parseSignalingMessage)
       connected / peer-joined / peer-left / peer-waiting / pair-created / pair-deleted /
       offer / answer / ice-candidate / hangup / error   (VisionLinkSignalingEvent)
  → offer 수신 → VisionLinkWebRTCReceiver.handleOffer → answer + ICE 후보를 sendSignaling
  → 영상 트랙 + 데이터 채널 → 상태 mediaConnected / videoReceiving
```

- 상태 `VisionLinkConnectionState`: `inactive, creatingSession, reconnecting(attempt), waitingForCompanion, companionConnected, mediaOfferReceived, mediaConnecting, mediaConnected, mediaIdle, videoReceiving, disconnected, codeExpired, failed`.
- 페어링 코드는 `pairingCode` 로 화면에 표시하고 `remainingSeconds` 카운트다운 (`expirationDate` = `ttlSeconds` 우선, 없으면 `expiresAt` ISO8601). 만료 시 `codeExpired` → `createNewCode()`. QR 은 `pairingURI` 필드만 파싱하고 렌더하지 않는다.
- `unregisterAndCreateNewCode()` = 서버 pair 삭제 + Keychain 삭제 + 새 코드. `VisionLinkPairDeletionPolicy` 가 언제 서버에 delete 를 보낼지 결정.
- 미디어 워치독 `VisionLinkMediaWatchdog`: offer 대기 `8`초, 첫 프레임 `5`초, 프레임 정지 `5`초 → 초과 시 재협상/복구 (`scheduleConnectionRecovery`). 앱이 백그라운드면 `setApplicationActive(false)` 로 워치독 정지.

## WebRTC

`VisionLinkWebRTCReceiver.swift` (패키지 `StreamWebRTC` 145.12.0)

- `RTCConfiguration.sdpSemantics = .unifiedPlan`, ICE 서버는 세션 응답의 `iceServers[] {urls, username, credential}` 를 그대로 `RTCIceServer` 로.
- 수신 전용: 원격 비디오 트랙을 `VisionLinkVideoView` 에 붙이고 `VisionLinkVideoFrameSampler` 가 실시간 읽기용 프레임을 CGImage 로 샘플링.
- 데이터 채널은 폰이 열고(`didOpen dataChannel`) iPad 는 `VisionLinkDataReceiver` 에 위임. 제어 메시지는 JSON, 파일 본문은 바이너리 청크.

## 데이터 채널 프로토콜

`VisionLinkDataReceiver.swift` · `VisionLinkDataReceiver` (actor). JSON 의 `"type"` 으로 분기.

| 수신 (폰 → iPad) | 처리 |
|---|---|
| `file-start` / (바이너리 청크) / `file-end` / `file-cancel` | 파일 수신 → `file-accepted` 응답, 완료 시 `file-complete`, 오류 `file-error`. 저장 후 `VisionLinkReceivedFile` 이벤트 |
| `clipboard-text` | 텍스트 수신 → `VisionLinkReceivedTextStore` (Caches/VisionLink/ReceivedText), 응답 `clipboard-complete` / `clipboard-error` |
| `camera-share-state` | 폰 카메라 공유 on/off |
| `data-ping` ↔ `data-pong` | 생존 확인 |
| `feature-request` (`kind`: `image`…) | 원격 기능 요청 `VisionLinkRemoteFeature`: `image-analysis`, `ai-chat`, `live-reading` (+ 텍스트 번역 `VisionLinkTextTranslationRequest`) |
| `chat-context-attachment` (`purpose: "visioncraft-chat-attachment"`) | 채팅 첨부(이미지/PDF/문서) 수신 → `chat-attachment-ready` / `chat-attachment-error` (`VisionLinkChatControl`) |
| `live-reading-start` / `live-reading-stop` | 실시간 읽기 세션 시작/정지 |

| 송신 (iPad → 폰) | 출처 |
|---|---|
| `feature-progress` / `feature-result` / `feature-error` | `VisionLinkFeatureControl` (결과 ≤ `maximumResultSize`, 오류 ≤ 500자) |
| `live-reading-status` / `live-reading-result` / `live-reading-error` | `VisionLinkLiveReadingControl` (`sequence`, `text`) |

한도 (`VisionLinkDataReceiver` 상수): 파일 `1_073_741_824` B, 기능 이미지 25 MiB, 클립보드 128 KiB, 기능 요청 40 KiB, 번역 텍스트 32 KiB, 채팅 요청 128 KiB / 메시지 16 KiB / 문맥 64 KiB / 첨부 25 MiB / PDF 14 MiB / 메시지 40개, requestID 80자, 여유 공간 예약 64 MiB, 임시 파일 24시간. 차단 확장자 목록 `blockedGeneralExtensions`.

## 원격 기능의 로컬 처리

| 기능 | 서비스 | 백엔드 |
|---|---|---|
| 이미지 OCR | `VisionLinkLocalRemoteFeatureService.recognizeImage` | `OCRService` (ML Kit) |
| 이미지 설명 | `…describeImage` | `GeminiVisionService.stream` (클라우드, 토큰 예산 적용) |
| 번역 | `…translate` | `LLMService.streamText` (로컬 MLX) |
| AI 채팅 | `VisionLinkLocalRemoteChatService.answer` | 로컬 MLX (`systemPrompt` 는 [gemini_ai.md](gemini_ai.md)); 이미지 첨부 시 `GeminiVisionService`. PDF/HWP/HWPX/DOCX/XLSX 텍스트는 `extractDocumentText` |
| 실시간 읽기 | `VisionLinkLocalLiveReadingService.recognize` + `VisionLinkLiveReadingTextFilter` (bigram 유사도로 최근 결과와 겹치는 문장 억제) | `OCRService`, 프레임은 `VisionLinkVideoFrameSampler.requestFrame` |

요청은 `VisionLinkManager` 의 직렬 큐(`enqueueRemoteFeature` / `enqueueRemoteChat` → `drainRemoteFeatureQueue`)로 한 번에 하나씩 처리하고 진행 단계를 `feature-progress` 로 알린다.

## 저장 / UI

- 대화 기록: Application Support `VisionLink/conversations-v1.json` + `ChatAttachments/` (`VisionLinkConversationStore`, 최근 30개).
- 받은 텍스트: Caches `VisionLink/ReceivedText/`. `VisionLinkManager.handle(.clipboardReceived)`가 시스템 클립보드(`UIPasteboard.general.string`)에도 즉시 저장한다. 받은 파일 삭제는 `deleteLastReceivedFile()`.
- 이벤트 로그 `VisionLinkEventRecord` (`appendEvent`, `clearEventHistory`).
- 진입: 홈 → `AppRoute.visionLink` (`VisionLinkView`), 딥링크 `rivopad://open/vision-link`, App Shortcut "VisionLink", Rivo 빠른 메뉴 없음.
- 테스트: `VisionLinkTests`, `VisionLinkDataReceiverTests`, `VisionLinkRemoteChatTests`, `VisionLinkRemoteFeatureTests`, `VisionLinkLiveReadingTests`.
