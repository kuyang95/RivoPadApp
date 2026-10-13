# VisionLink (폰 카메라 → iPad 수신)

점검일 2026-10-13 · 기준 코드 `cf9d0863` + 작업 트리

iPad 가 **수신기(receiver)** 로 시그널링 서버에 등록하고, 폰(companion) 이 페어링 코드로 붙어 WebRTC 로 영상·파일·텍스트를 보낸다. iPad 는 받은 이미지/문서를 로컬 AI 로 처리해 결과를 데이터 채널로 돌려준다. 코드는 `shortcuts_example/VisionLink/`. Android 대응 문서는 `/Users/me/Develop/AndroidProject/VisionCraft/rules/visionlink.md`이며, 대응 코드는 `visionlink/`에 있다.

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
- 미디어 워치독 `VisionLinkMediaWatchdog`: offer 대기 `8`초 초과는 전체 연결 복구, 첫 프레임·프레임 정지 `5`초 초과는 데이터 채널의 `media-recovery-request`로 ICE 재시작을 한 번 요청한다. 실제 프레임이 `12`초 더 오지 않거나 제어 채널을 사용할 수 없으면 전체 연결을 복구한다. `VisionLinkMediaRecoveryPolicy`가 중복 요청을 막고 실제 프레임 수신으로 시도를 초기화한다. 앱이 백그라운드면 `setApplicationActive(false)`로 워치독을 정지한다. 프레임마다 타이머를 새로 만들지 않고 최근 프레임 시각을 기준으로 검사한다.
- `VisionLinkManager.openWebSocket`: 네이티브 ping `25`초 간격, pong 대기 `12`초. 실패하면 소켓을 비우고 REST·WebSocket부터 복구한다. 기존 ICE 연결 성공 콜백이 시그널링 복구를 취소하지 않는다.
- 송신 `CameraSession`: 일시적인 ICE disconnected는 `3`초 유예 후 ICE 재시작, 재시작·answer 대기는 `12`초 제한. 전체 재연결 후 사용자가 공유하던 카메라는 앱이 전면에 있을 때 자동 재개한다. 사용자가 공유 중지·등록 해제·앱 종료를 선택하면 재개하지 않는다. 연결 종료 후 늦게 반환된 카메라 스트림은 트랙을 정지하고 폐기한다.
- 송신 `SignalingClient`: 네이티브 WebSocket ping `25`초와 pong 제한 `25`초, 연결·핸드셰이크 `12`초 제한. 데이터 채널 ping은 `15`초 간격이며 pong을 `30`초 안에 받지 못하면 전체 재연결한다. REST 재연결은 0·1·2·4·8·15초 대기 후 시도하고, 재시도 가능한 실패가 지속되면 `30`초 뒤 다시 시도한다. 페어 삭제·명시적 종료는 재시도를 취소한다.

## WebRTC

`VisionLinkWebRTCReceiver.swift` (패키지 `StreamWebRTC` 145.12.0)

- `RTCConfiguration.sdpSemantics = .unifiedPlan`, ICE 서버는 세션 응답의 `iceServers[] {urls, username, credential}` 를 그대로 `RTCIceServer` 로.
- 네이티브 PC·SDP·ICE·데이터 콜백은 현재 연결과 일치할 때만 반영하며 이전 연결의 이벤트를 버린다. 대기 ICE 후보는 최대 256개다.
- 수신 전용: 원격 비디오 트랙을 `VisionLinkVideoView` 에 붙이고 `VisionLinkVideoFrameSampler` 가 실시간 읽기용 프레임을 CGImage 로 샘플링.
- 데이터 채널은 폰이 열고(`didOpen dataChannel`) iPad 는 `VisionLinkDataReceiver` 에 위임. 제어 메시지는 JSON, 파일 본문은 바이너리 청크.

## 실시간 카메라 자동 화질 / 실제 수신 표시

- 송신 앱은 `/Users/me/Develop/AndroidProject/VisionLink/client`의 Flutter 구현이다. `lib/src/camera_session.dart` · `CameraSession._pollSenderStats`와 `adaptive_video_quality.dart` · `AdaptiveVideoQuality`에서 2초마다 선택된 ICE 경로의 `availableOutgoingBitrate`·왕복 지연, 원격 수신 패킷 손실과 인코더 제한을 확인한다. 일반 인터넷 속도 측정값이 아니라 실제 영상 연결의 추정 전송 여유를 사용한다.
- 첫 연결·재연결의 초기 상한은 1080p / 30fps / 5Mbps. 1920×1080 카메라 캡처를 요청하고, 인코더에서 실제 캡처 크기의 짧은 변을 기준으로 1080p / 720p 두 상한을 선택한다. 1080p 캡처의 축소 배율은 1배·1.5배이다. 각 최대 비트레이트는 5Mbps / 3Mbps, 최대 프레임은 모두 30fps이다. 720p보다 낮은 프로필은 선택하지 않는다. 더 낮은 캡처 크기나 세로 방향에서도 같은 해상도 상한을 적용하며 낮은 해상도를 확대하지 않는다. 실제 출력은 카메라와 인코더 상태에 따라 더 낮을 수 있다.
- 첫 정상 출력 후 초기 안정화는 2초다. 첫 상한 변경이 실제로 적용된 뒤에는 10초 안정화·4회 상향 확인·20초 정상 연결 시험으로 돌아가 느린 회선에서 빠른 시험을 반복하지 않는다(심각한 지연·손실·CPU 부하·24fps 미만 출력은 안정화 예외). 추정 전송 여유의 75%를 상향 예산으로 쓰며 현재 상한의 80% 미만으로 떨어질 때 하향을 고려한다. 다만 인코더가 `none`(제한 없음)을 보고하면 낮은 추정값만으로는 해상도를 낮추지 않는다. 화면 변화가 적은 정적인 영상에서도 현재 고화질 상한을 유지한다. RTT 450ms 이상·손실 3% 이상·cpu 제한이 지속되면 낮춘다. 누적 `totalEncodeTime`과 `framesEncoded`의 차이에 목표 fps를 곱한 인코더 부하도 사용한다. 부하 95% 이상은 하향 압력으로 처리하고 초기 안정화 중에도 허용하며, 80% 이상은 상향 시험을 막는다. bandwidth 제한 표시만으로는 하향하지 않는다. RTT 800ms 이상·손실 10% 이상이면 720p 하향을 고려한다. 하향은 연속 2회(4초), 시작 단계 이후의 상향은 연속 4회(8초) 확인 후 한 단계씩 적용한다. 추정 여유가 없으면 수신 비트레이트를 회선 용량으로 간주하지 않는다. 지연·손실·CPU·실제 fps의 하향 조건이 없으면 현재 상한을 유지한다. 현재 상한에 비해 추정 여유가 80% 이상이며 RTT 200ms 미만·손실 2% 미만이 20초 지속되면 한 단계 상향 시험을 한다. 출력이 멈췄을 때는 추정값으로 상한을 바꾸지 않는다. 해상도·fps는 앱이 조절하고 WebRTC 자체 적응은 `MAINTAIN_FRAMERATE_AND_RESOLUTION`으로 중복 축소를 막는다. 네트워크 비트레이트 제어는 계속 사용하며 최소 비트레이트는 50kbps, 시작 힌트는 3Mbps다.
- 송신 미리보기와 양쪽 수신 화면은 실제 영상의 짧은 변을 `720p`·`1080p`처럼 표시하고 확인된 배율과 `1080p · 1.5x` 한 항목으로 합친다. 자동 화질 문구·가로×세로·fps·전송률·측정 중 문구는 공유 HUD에 표시하지 않는다. 측정 전에는 확인된 배율만 표시한다. 공유 중에는 설정 진입 버튼을 숨기고 중지하면 다시 표시한다. 수신 상태 칩에는 연결됨 접두어 없이 카메라 화면 공유 중 또는 바로 읽기 처리 중만 표시한다. `inbound-rtp` 크기·누적 framesDecoded/bytesReceived 차이의 측정과 최소 화질 차단·복구는 그대로 유지한다. 주기적인 값은 자동 낭독하지 않는다.
- iPad 구현: `VisionLinkWebRTCReceiver.setVideoStatisticsActive` / `reportVideoQuality`, `VisionLinkVideoQualityMeter.sample`, `VisionLinkManager.videoQuality`, `VisionLinkView.cameraQualityAndZoomText`. 연결·통계 세대가 바뀌면 이전 콜백과 누적 기준을 버린다.
- Android 구현: `VisionLinkWebRtcReceiver.logNetworkStats`, `VisionLinkVideoQualityMeter.sample`, `VisionLinkReceiverActivity.onVideoQualityChanged`, `a_vision_link_receiver.xml` · `tvCameraZoomValue` · `updateCameraSummary`.

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
| `media-recovery-request` | 실제 프레임 정지 시 폰에 ICE 재시작 요청 |
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
- 테스트: `VisionLinkTests`, `VisionLinkDataReceiverTests`, `VisionLinkRemoteChatTests`, `VisionLinkRemoteFeatureTests`, `VisionLinkLiveReadingTests`, `VisionLinkVideoQualityTests`.

## 최소 영상 표시 품질

- 실제 인코딩 fps가 24 미만으로 2회(약 4초) 연속 측정되면 `none` 제한 보고나 넉넉한 추정 전송 여유와 관계없이 1080p에서 720p로 낮춘다. 27fps 미만에서는 1080p 복귀를 막는다. 0프레임 정지는 기존 미디어 복구가 처리한다. 카메라 입력 자체가 느린 상황은 720p에서도 지속될 수 있고 수신 최소 품질 표시는 그대로 적용한다.

`VisionLinkVideoDisplayGate`는 실제 수신 영상의 짧은 변 720픽셀 이상·디코딩 24fps 이상을 표시 기준으로 사용한다. 기준 미달(측정 불가·프레임 정지 포함)이 8초 지속되면 영상을 불투명 안내로 가리고, 두 기준을 4초 연속 만족하면 자동 표시한다. 순간 저하는 허용하며 5초 넘는 측정 공백은 안정 시간에서 제외한다. 비트레이트만으로 가리지 않는다. 가리는 동안 렌더러·디코딩·통계·연결 복구는 유지한다. 카메라 세션 시작·중지·연결 종료 시 초기화한다. 안내는 네트워크 속도만 원인으로 단정하지 않으며 화면 읽기 도구에 상태 전환만 알린다.

## 공유 카메라 확대

- 송신앱 `CameraZoomController`가 폰 핀치와 수신기 요청을 한 큐에서 처리한다. 진행 중 요청은 직렬 실행하며 빠른 연속 입력은 마지막 대기 값으로 합친다. 송신기는 매 단계 배율 변화를 최대 3%로 제한해 목표 배율까지 연결한다. 명령은 최대 60회/초로 제한한다. Android Camera2는 명령 제출과 CaptureResult 수신을 분리해 이전 적용 대기가 새 입력을 막지 않게 한다. 화면에는 최신 CaptureResult의 실제 값만 표시하고, 최종 목표의 확인을 계속 조회한다. 3초간 확인이 없거나 최신 요청이 실패하면 오류로 끝내고 다음 제스처에서 재시도한다. 새 목표가 오면 다음 단계부터 바로 반영하고 중지 시 남은 단계를 폐기한다. 실제 카메라 적용 확인 뒤 배율을 양쪽에 표시한다. 화면만 잘라 확대하지 않는다.
- 데이터 채널 `camera-zoom-state`: `sessionId`, 실제 `value`, 카메라 `min`·`max`, `supported`, 증가하는 `revision`, `error`. 수신기는 잘못된 수치·범위·세션 ID·revision을 버린다. 같은 세션의 과거 revision은 UI에 반영하지 않는다. `camera-zoom-request`는 현재 `sessionId`와 유한한 `value`를 보내며 송신기가 실제 범위로 제한한다.
- 새 공유는 1배에서 시작한다. 중지·연결 종료는 확대 상태와 대기 요청을 지우며 이전 카메라의 지연 응답이 새 공유를 덮어쓰지 않는다. 채널이 열릴 때 현재 상태를 다시 알린다. 확대 실패는 확인된 배율을 유지하고 재시도 안내를 표시한다. 확대 미지원 카메라는 확인된 배율을 표시하며 확대 요청을 적용하지 않는다.
- 송신 Android `CameraZoomBridge`: 현재 WebRTC 카메라 스레드에서 Camera2 crop 또는 Camera1 zoom ratio를 적용한다. Camera2 센서 원점·초점·프레임레이트·안정화 설정을 유지하고 capture result의 crop에서 적용 배율을 확인한다. 내부 필드 접근은 앱 ProGuard 규칙으로 보존한다. 송신 iOS `AppDelegate`: 현재 AVCaptureDevice의 지원 범위·videoZoomFactor를 사용한다. 기기·현재 렌즈에 따라 최대 배율이 달라지고 디지털 확대의 세부 화질은 감소할 수 있다.
- 송신 미리보기와 양쪽 수신 화면은 실제 영상의 짧은 변을 `720p`·`1080p`처럼 표시하고 확인된 배율과 `1080p · 1.5x` 한 항목으로 합친다. 자동 화질 문구·가로×세로·fps·전송률·측정 중 문구는 공유 HUD에 표시하지 않는다. 측정 전에는 확인된 배율만 표시한다. 공유 중에는 설정 진입 버튼을 숨기고 중지하면 다시 표시한다. 수신 상태 칩에는 연결됨 접두어 없이 카메라 화면 공유 중 또는 바로 읽기 처리 중만 표시한다. 영상 핀치 전달 간격은 33ms이며 VoiceOver/TalkBack 배율 조절 동작을 유지한다.

## 규격·기능 호환

연결 직후 `visionlink-hello`로 protocol 1·앱 버전·기능 목록·영상 상한을 확인한다. 협상 전 카메라·데이터 사용은 차단하며, 지원 기능의 교집합과 작은 영상 상한을 사용한다. 선택 기능 미지원은 해당 요청을 차단하고, 필수 규격 불일치는 양쪽 업데이트를 안내한다. 자세한 wire 형식, 최초 지원 기준, 기능별 fallback과 작업 절차는 [VisionLink 호환 규격](visionlink_compatibility.md)을 따른다.

## 공유 카메라 방향

공통 `camera-orientation.v1` 지원 시 송신 폰의 물리 방향을 WebRTC 프레임 회전 정보로 전달한다. 카메라 방향은 UI 방향과 독립적으로 감지한다. 송신 홈·설정은 세로이며, `CameraScreenOrientation`이 공유 화면에서만 가로 회전을 허용하고 공유 중지·연결 종료·화면 종료 때 세로를 복구한다. 방향 설정 호출은 직렬 처리하여 늦은 진입 요청이 종료 설정을 덮지 않게 한다. 송신 공유 미리보기는 `RTCVideoViewObjectFitCover`로 화면을 채우고 제목·HUD·버튼도 함께 회전한다. 가로 중지 버튼은 오른쪽 아래 내용 폭(최대 320dp), 세로는 가운데 아래의 기존 폭이다. 수신 렌더러는 회전 정보를 한 번 적용하고 전체 프레임을 비율 유지로 맞춘다(iPad `.scaleAspectFit`, Android `SCALE_ASPECT_FIT`). 송신 방향 때문에 수신 앱 화면을 강제 회전시키지 않는다. 별도 JSON 각도 메시지나 중복 영상 회전은 사용하지 않는다. 미지원 상대는 기존 WebRTC 방향 처리를 유지한다. 세부 규격·미출시 버전·검사는 [호환 규격](visionlink_compatibility.md)을 따른다.
