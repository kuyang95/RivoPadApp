import Combine
import Foundation
@preconcurrency import StreamWebRTC
import UIKit

nonisolated enum VisionLinkConnectionState:
    Equatable,
    Sendable
{
    case inactive
    case creatingSession
    case reconnecting(attempt: Int)
    case waitingForCompanion
    case companionConnected(String)
    case mediaOfferReceived
    case mediaConnecting
    case mediaConnected
    case videoReceiving
    case disconnected
    case codeExpired
    case failed(String)

    var title: String {
        switch self {
        case .inactive:
            return "연결 전"
        case .creatingSession:
            return "연결 코드 생성 중"
        case .reconnecting(let attempt):
            return "저장된 기기에 재연결 중 · \(attempt)차"
        case .waitingForCompanion:
            return "VisionLink 기기 대기 중"
        case .companionConnected(let name):
            return "\(name) 신호 연결됨"
        case .mediaOfferReceived:
            return "영상 연결 제안 수신"
        case .mediaConnecting:
            return "영상 연결 중"
        case .mediaConnected:
            return "영상 연결됨 · 첫 화면 대기 중"
        case .videoReceiving:
            return "원격 영상 수신 중"
        case .disconnected:
            return "연결 끊김"
        case .codeExpired:
            return "연결 코드 만료"
        case .failed(let message):
            return message
        }
    }

    var isWorking: Bool {
        switch self {
        case .creatingSession, .reconnecting:
            return true
        default:
            return false
        }
    }

    var isSignalingConnected: Bool {
        switch self {
        case .waitingForCompanion,
             .companionConnected,
             .mediaOfferReceived,
             .mediaConnecting,
             .mediaConnected,
             .videoReceiving:
            return true
        default:
            return false
        }
    }
}

nonisolated struct VisionLinkEventRecord:
    Identifiable,
    Equatable,
    Sendable
{
    let id: UUID
    let date: Date
    let summary: String
}

nonisolated struct VisionLinkRemoteFeatureStatus:
    Equatable,
    Sendable
{
    let requestID: String
    let feature: VisionLinkRemoteFeature
    let stage: String
    let message: String
    let isWorking: Bool
}

nonisolated private enum VisionLinkRemoteWorkItem {
    case feature(VisionLinkRemoteFeatureRequest)
    case chat(VisionLinkRemoteChatWork)

    var temporaryFileURL: URL? {
        switch self {
        case .feature(let request):
            return request.temporaryFileURL
        case .chat(let work):
            return work.temporaryFileURL
        }
    }
}

@MainActor
final class VisionLinkManager: ObservableObject {
    @Published private(set) var state:
        VisionLinkConnectionState = .inactive
    @Published private(set) var pairingCode: String?
    @Published private(set) var pairingURI: String?
    @Published private(set) var remainingSeconds: Int?
    @Published private(set) var roomID: String?
    @Published private(set) var peerName: String?
    @Published private(set) var hasStoredPair = false
    @Published private(set) var remoteVideoTrack:
        RTCVideoTrack?
    @Published private(set) var isDataChannelReady =
        false
    @Published private(set) var isCameraShareActive =
        false
    @Published private(set) var incomingTransfer:
        VisionLinkTransferProgress?
    @Published private(set) var lastReceivedFile:
        VisionLinkReceivedFile?
    @Published private(set) var receivedClipboardText:
        String?
    @Published private(set) var dataTransferMessage:
        String?
    @Published private(set) var remoteFeatureStatus:
        VisionLinkRemoteFeatureStatus?
    @Published private(set) var recentEvents:
        [VisionLinkEventRecord] = []

    private let server: any VisionLinkServerServing
    private let credentialStore:
        any VisionLinkCredentialStoring
    private let webSocketSession: URLSession
    private let deviceName: String
    private let webRTCReceiver: VisionLinkWebRTCReceiver
    private let remoteFeatureProcessor:
        VisionLinkRemoteFeatureProcessor
    private let remoteChatProcessor:
        VisionLinkRemoteChatProcessor
    private let liveReadingService:
        any VisionLinkLiveReadingServing

    private var connectionTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var webSocket: URLSessionWebSocketTask?
    private var socketGeneration = 0
    private var currentIceServers: [VisionLinkIceServer] = []
    private var currentRelayPolicy =
        VisionLinkContract.p2pPreferred
    private var remoteWorkQueue:
        [VisionLinkRemoteWorkItem] = []
    private var remoteFeatureTask:
        Task<Void, Never>?
    private var remoteFeatureGeneration = 0
    private var liveReadingSessionID: String?
    private var liveReadingSequence = 0
    private var liveReadingTextFilter =
        VisionLinkLiveReadingTextFilter()
    private var liveReadingOCRTask:
        Task<Void, Never>?
    private var liveReadingScheduleTask:
        Task<Void, Never>?
    private var liveReadingOperationID: UUID?

    init(
        server: any VisionLinkServerServing =
            VisionLinkServerClient(),
        credentialStore:
            any VisionLinkCredentialStoring =
                VisionLinkCredentialStore(),
        webSocketSession: URLSession = .shared,
        deviceName: String? = nil,
        remoteFeatureService:
            (any VisionLinkRemoteFeatureServing)? =
                nil,
        remoteChatService:
            (any VisionLinkRemoteChatServing)? =
                nil,
        conversationStore:
            VisionLinkConversationStore =
                .shared,
        liveReadingService:
            (any VisionLinkLiveReadingServing)? =
                nil
    ) {
        self.server = server
        self.credentialStore = credentialStore
        self.webSocketSession = webSocketSession
        webRTCReceiver = VisionLinkWebRTCReceiver()
        remoteFeatureProcessor =
            VisionLinkRemoteFeatureProcessor(
                service:
                    remoteFeatureService
                    ?? VisionLinkLocalRemoteFeatureService
                    .shared
            )
        remoteChatProcessor =
            VisionLinkRemoteChatProcessor(
                service:
                    remoteChatService
                    ?? VisionLinkLocalRemoteChatService
                    .shared,
                conversationStore:
                    conversationStore
            )
        self.liveReadingService =
            liveReadingService
            ?? VisionLinkLocalLiveReadingService
                .shared
        let requestedName = deviceName
            ?? UIDevice.current.name
        let normalized = requestedName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        self.deviceName = String(
            (normalized.isEmpty ? "RivoPad" : normalized)
                .prefix(80)
        )

        hasStoredPair = (
            try? credentialStore.read()
        ) != nil
        webRTCReceiver.delegate = self
    }

    deinit {
        connectionTask?.cancel()
        receiveTask?.cancel()
        countdownTask?.cancel()
        remoteFeatureTask?.cancel()
        liveReadingOCRTask?.cancel()
        liveReadingScheduleTask?.cancel()
        webSocket?.cancel(
            with: .goingAway,
            reason: nil
        )
    }

    func activate() {
        guard connectionTask == nil,
              webSocket == nil else {
            return
        }
        launchConnection(forceNewSession: false)
    }

    func retry() {
        launchConnection(forceNewSession: false)
    }

    func createNewCode() {
        launchConnection(forceNewSession: true)
    }

    func disconnect() {
        connectionTask?.cancel()
        connectionTask = nil
        cancelSocket(reason: "user-disconnect")
        stopCountdown()
        pairingCode = nil
        pairingURI = nil
        state = .disconnected
    }

    func unregisterAndCreateNewCode() {
        connectionTask?.cancel()
        connectionTask = Task { [weak self] in
            guard let self else {
                return
            }
            defer {
                self.connectionTask = nil
            }
            self.cancelSocket(reason: "unregister")
            self.stopCountdown()
            do {
                if let credentials =
                    try self.credentialStore.read() {
                    do {
                        try await self.server
                            .deleteReceiverPair(
                                credentials: credentials
                            )
                    } catch let error as VisionLinkServerError
                        where error.statusCode == 404 {
                        // 이미 서버에서 삭제된 페어도 로컬에서는 정리한다.
                    }
                }
                try self.credentialStore.clear()
                self.hasStoredPair = false
                try await self.createSession()
            } catch is CancellationError {
                return
            } catch {
                self.state = .failed(
                    Self.userMessage(for: error)
                )
            }
        }
    }

    func clearEventHistory() {
        recentEvents = []
    }

    func clearReceivedClipboard() {
        receivedClipboardText = nil
    }

    func clearDataTransferMessage() {
        dataTransferMessage = nil
    }

    private func launchConnection(
        forceNewSession: Bool
    ) {
        connectionTask?.cancel()
        cancelSocket(reason: "new-connection")
        stopCountdown()
        connectionTask = Task { [weak self] in
            guard let self else {
                return
            }
            defer {
                self.connectionTask = nil
            }
            do {
                if forceNewSession {
                    try self.credentialStore.clear()
                    self.hasStoredPair = false
                    try await self.createSession()
                    return
                }

                if let credentials =
                    try self.credentialStore.read() {
                    self.hasStoredPair = true
                    do {
                        try await self.reconnect(
                            credentials: credentials
                        )
                        return
                    } catch let error as VisionLinkServerError
                        where error.statusCode == 404 {
                        try self.credentialStore.clear()
                        self.hasStoredPair = false
                    }
                }
                try await self.createSession()
            } catch is CancellationError {
                return
            } catch {
                self.state = .failed(
                    Self.userMessage(for: error)
                )
            }
        }
    }

    private func createSession() async throws {
        resetVisibleSession()
        state = .creatingSession
        let response = try await server
            .createReceiverSession(deviceName: deviceName)
        try Task.checkCancellation()

        guard let receiverID = response.receiver.deviceID,
              let receiverToken =
                response.receiver.deviceToken else {
            throw VisionLinkProtocolError
                .missingReceiverCredentials
        }

        let credentials = VisionLinkStoredCredentials(
            pairID: response.pairID,
            deviceID: receiverID,
            deviceToken: receiverToken,
            isConfirmed: false
        )
        try credentialStore.save(credentials)
        hasStoredPair = true
        roomID = response.roomID
        pairingCode = response.pairingCode
        pairingURI = response.pairingURI
        currentIceServers = response.iceServers
        currentRelayPolicy = response.relayPolicy
        startCountdown(
            pairID: response.pairID,
            expirationDate: expirationDate(
                for: response
            )
        )
        try openWebSocket(
            response.receiver.websocketURL
        )
    }

    private func reconnect(
        credentials: VisionLinkStoredCredentials
    ) async throws {
        let delays: [UInt64] = [
            0,
            1_000_000_000,
            2_000_000_000,
            4_000_000_000
        ]
        var lastError: Error?

        for (index, delay) in delays.enumerated() {
            try Task.checkCancellation()
            state = .reconnecting(attempt: index + 1)
            if delay > 0 {
                try await Task.sleep(nanoseconds: delay)
            }
            do {
                let response = try await server
                    .reconnectReceiver(
                        credentials: credentials,
                        deviceName: deviceName
                    )
                try Task.checkCancellation()
                roomID = response.roomID
                pairingCode = nil
                pairingURI = nil
                remainingSeconds = nil
                peerName = response.peerName
                currentIceServers = response.iceServers
                currentRelayPolicy = response.relayPolicy
                try openWebSocket(
                    response.receiver.websocketURL
                )
                return
            } catch let error as VisionLinkServerError
                where error.statusCode == 404 {
                throw error
            } catch {
                lastError = error
            }
        }
        throw lastError
            ?? VisionLinkServerError.invalidResponse
    }

    private func openWebSocket(
        _ rawURL: String
    ) throws {
        guard let url = URL(string: rawURL),
              url.scheme == "wss"
                || url.scheme == "ws" else {
            throw VisionLinkProtocolError.invalidWebSocketURL
        }
        cancelSocket(reason: "replace-socket")
        socketGeneration &+= 1
        let generation = socketGeneration
        let socket = webSocketSession.webSocketTask(
            with: url
        )
        webSocket = socket
        state = .waitingForCompanion
        appendEvent("신호 서버 연결 시작")
        socket.resume()

        receiveTask = Task { [weak self, socket] in
            guard let self else {
                return
            }
            await self.receiveMessages(
                from: socket,
                generation: generation
            )
        }
    }

    private func receiveMessages(
        from socket: URLSessionWebSocketTask,
        generation: Int
    ) async {
        do {
            while !Task.isCancelled {
                let message = try await socket.receive()
                guard generation == socketGeneration else {
                    return
                }
                let text: String
                switch message {
                case .string(let value):
                    text = value
                case .data(let data):
                    guard let value = String(
                        data: data,
                        encoding: .utf8
                    ) else {
                        continue
                    }
                    text = value
                @unknown default:
                    continue
                }
                do {
                    let event = try VisionLinkJSON
                        .parseSignalingMessage(text)
                    handle(event)
                } catch {
                    appendEvent(
                        "해석하지 못한 신호 메시지"
                    )
                }
            }
        } catch is CancellationError {
            return
        } catch {
            guard generation == socketGeneration else {
                return
            }
            webSocket = nil
            state = .failed(
                "VisionLink 신호 연결 끊김: "
                    + Self.userMessage(for: error)
            )
        }
    }

    private func handle(
        _ event: VisionLinkSignalingEvent
    ) {
        appendEvent(event.summary)
        switch event {
        case .connected(let roomID, _, _):
            if let roomID {
                self.roomID = roomID
            }
            state = .waitingForCompanion

        case .peerJoined(_, _, _, let peerName):
            confirmPairing()
            let name = normalizedPeerName(peerName)
            self.peerName = name
            state = .companionConnected(name)

        case .pairCreated(_, let cameraName):
            confirmPairing()
            let name = normalizedPeerName(cameraName)
            peerName = name
            state = .companionConnected(name)

        case .peerWaiting:
            state = .waitingForCompanion

        case .offer(let offer):
            confirmPairing()
            state = .mediaOfferReceived
            webRTCReceiver.handleOffer(
                offer,
                iceServers: currentIceServers,
                relayPolicy: currentRelayPolicy
            )

        case .peerLeft, .hangup:
            resetMedia()
            state = .disconnected

        case .pairDeleted(let pairID, _):
            if let credentials = try? credentialStore.read(),
               pairID == nil
                || credentials.pairID == pairID {
                try? credentialStore.clear()
                hasStoredPair = false
            }
            cancelSocket(reason: "pair-deleted")
            state = .disconnected

        case .serverError(let code, let message):
            state = .failed(
                "VisionLink 오류 \(code ?? "unknown"): "
                    + (message ?? "")
            )

        case .iceCandidate(let candidate):
            webRTCReceiver.addRemoteIceCandidate(
                candidate
            )

        case .answer, .unknown:
            break
        }
    }

    func markFirstVideoFrameRendered() {
        guard remoteVideoTrack != nil,
              state != .videoReceiving else {
            return
        }
        state = .videoReceiving
        appendEvent("원격 영상 첫 화면 표시")
    }

    private func confirmPairing() {
        stopCountdown()
        pairingCode = nil
        pairingURI = nil
        guard var credentials =
                try? credentialStore.read(),
              credentials.isConfirmed == false else {
            return
        }
        credentials.isConfirmed = true
        try? credentialStore.save(credentials)
        hasStoredPair = true
    }

    private func startCountdown(
        pairID: String,
        expirationDate: Date?
    ) {
        stopCountdown()
        guard let expirationDate else {
            return
        }
        updateRemainingSeconds(
            expirationDate: expirationDate
        )
        countdownTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(
                    nanoseconds: 1_000_000_000
                )
                guard !Task.isCancelled,
                      let self else {
                    return
                }
                let remaining = self.updateRemainingSeconds(
                    expirationDate: expirationDate
                )
                if remaining <= 0 {
                    self.expireCode(pairID: pairID)
                    return
                }
            }
        }
    }

    @discardableResult
    private func updateRemainingSeconds(
        expirationDate: Date
    ) -> Int {
        let value = max(
            Int(
                ceil(
                    expirationDate.timeIntervalSinceNow
                )
            ),
            0
        )
        remainingSeconds = value
        return value
    }

    private func expireCode(pairID: String) {
        guard let credentials =
                try? credentialStore.read(),
              credentials.pairID == pairID,
              credentials.isConfirmed == false else {
            return
        }
        try? credentialStore.clear()
        hasStoredPair = false
        pairingCode = nil
        pairingURI = nil
        remainingSeconds = nil
        cancelSocket(reason: "code-expired")
        state = .codeExpired
    }

    private func expirationDate(
        for response: VisionLinkSessionResponse
    ) -> Date? {
        if let ttlSeconds = response.ttlSeconds {
            return Date().addingTimeInterval(
                TimeInterval(max(ttlSeconds, 0))
            )
        }
        guard let rawValue = response.expiresAt else {
            return nil
        }
        return ISO8601DateFormatter().date(
            from: rawValue
        )
    }

    private func cancelSocket(reason: String) {
        socketGeneration &+= 1
        receiveTask?.cancel()
        receiveTask = nil
        resetMedia()
        webSocket?.cancel(
            with: .goingAway,
            reason: reason.data(using: .utf8)
        )
        webSocket = nil
    }

    private func resetMedia() {
        invalidateRemoteFeatureWork(
            reason: "media-reset"
        )
        webRTCReceiver.close()
        remoteVideoTrack = nil
        isDataChannelReady = false
        isCameraShareActive = false
        incomingTransfer = nil
    }

    private func startRemoteLiveReading(
        sessionID: String
    ) {
        stopRemoteLiveReading(
            reason: "new-live-reading-session"
        )
        liveReadingSessionID = sessionID
        liveReadingSequence = 0
        liveReadingTextFilter.reset()
        _ = webRTCReceiver
            .sendLiveReadingStatus(
                sessionID: sessionID,
                state: "started"
            )
        remoteFeatureStatus =
            VisionLinkRemoteFeatureStatus(
                requestID: sessionID,
                feature: .liveReading,
                stage: "started",
                message: "원격 화면 글자 읽는 중",
                isWorking: true
            )
        dataTransferMessage = nil
        appendEvent("원격 실시간 읽기 시작")
        webRTCReceiver
            .requestLiveReadingFrame()
    }

    private func stopRemoteLiveReading(
        reason: String,
        requestedSessionID: String? = nil,
        sendStoppedStatus: Bool = false
    ) {
        if let requestedSessionID,
           requestedSessionID
            != liveReadingSessionID {
            return
        }
        let previousSessionID =
            liveReadingSessionID
        liveReadingSessionID = nil
        liveReadingSequence = 0
        liveReadingTextFilter.reset()
        liveReadingOperationID = nil
        liveReadingOCRTask?.cancel()
        liveReadingOCRTask = nil
        liveReadingScheduleTask?.cancel()
        liveReadingScheduleTask = nil
        webRTCReceiver
            .cancelLiveReadingFrameRequest()

        guard let previousSessionID else {
            return
        }
        if sendStoppedStatus {
            _ = webRTCReceiver
                .sendLiveReadingStatus(
                    sessionID:
                        previousSessionID,
                    state: "stopped"
                )
            remoteFeatureStatus =
                VisionLinkRemoteFeatureStatus(
                    requestID:
                        previousSessionID,
                    feature: .liveReading,
                    stage: "stopped",
                    message:
                        "원격 실시간 읽기 중지",
                    isWorking: false
                )
        } else if remoteFeatureStatus?
                    .feature == .liveReading {
            remoteFeatureStatus = nil
        }
        appendEvent(
            "원격 실시간 읽기 중지 · "
                + reason
        )
    }

    private func processLiveReadingFrame(
        _ image: CGImage
    ) {
        guard let sessionID =
                liveReadingSessionID,
              liveReadingOCRTask == nil else {
            return
        }
        let generation =
            remoteFeatureGeneration
        let operationID = UUID()
        liveReadingOperationID = operationID
        remoteFeatureStatus =
            VisionLinkRemoteFeatureStatus(
                requestID: sessionID,
                feature: .liveReading,
                stage: "recognizing",
                message: "원격 화면 글자 인식 중",
                isWorking: true
            )
        liveReadingOCRTask = Task {
            do {
                let rawText =
                    try await liveReadingService
                    .recognize(image)
                try Task.checkCancellation()
                guard generation
                        == remoteFeatureGeneration,
                      liveReadingSessionID
                        == sessionID else {
                    return
                }
                if let text =
                        liveReadingTextFilter
                        .accept(rawText) {
                    liveReadingSequence += 1
                    _ = webRTCReceiver
                        .sendLiveReadingResult(
                            sessionID: sessionID,
                            sequence:
                                liveReadingSequence,
                            text: text
                        )
                    appendEvent(
                        "실시간 읽기 결과 전송 · "
                            + "\(text.count)자"
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                guard generation
                        == remoteFeatureGeneration,
                      liveReadingSessionID
                        == sessionID else {
                    return
                }
                sendLiveReadingError(
                    sessionID: sessionID,
                    message:
                        Self.userMessage(
                            for: error
                        )
                )
            }
            finishLiveReadingFrame(
                sessionID: sessionID,
                generation: generation,
                operationID: operationID
            )
        }
    }

    private func finishLiveReadingFrame(
        sessionID: String,
        generation: Int,
        operationID: UUID
    ) {
        guard liveReadingOperationID
                == operationID else {
            return
        }
        liveReadingOperationID = nil
        liveReadingOCRTask = nil
        guard generation
                == remoteFeatureGeneration,
              liveReadingSessionID == sessionID
        else {
            return
        }
        scheduleNextLiveReadingFrame(
            sessionID: sessionID,
            generation: generation
        )
    }

    private func scheduleNextLiveReadingFrame(
        sessionID: String,
        generation: Int
    ) {
        liveReadingScheduleTask?.cancel()
        liveReadingScheduleTask = Task {
            try? await Task.sleep(
                nanoseconds: 1_200_000_000
            )
            guard !Task.isCancelled,
                  generation
                    == remoteFeatureGeneration,
                  liveReadingSessionID
                    == sessionID,
                  isDataChannelReady,
                  isCameraShareActive,
                  remoteVideoTrack != nil else {
                return
            }
            liveReadingScheduleTask = nil
            webRTCReceiver
                .requestLiveReadingFrame()
        }
    }

    private func sendLiveReadingError(
        sessionID: String,
        message: String
    ) {
        _ = webRTCReceiver
            .sendLiveReadingError(
                sessionID: sessionID,
                message: message
            )
        dataTransferMessage = message
        appendEvent(
            "원격 실시간 읽기 오류 · "
                + message
        )
    }

    private func enqueueRemoteFeature(
        _ request: VisionLinkRemoteFeatureRequest
    ) {
        remoteWorkQueue.append(.feature(request))
        appendEvent(
            "원격 \(request.feature.title) 요청 수신"
        )
        startRemoteFeatureQueueIfNeeded()
    }

    private func enqueueRemoteChat(
        _ work: VisionLinkRemoteChatWork
    ) {
        remoteWorkQueue.append(.chat(work))
        switch work {
        case .request:
            appendEvent("원격 AI 대화 요청 수신")
        case .context(let attachment):
            appendEvent(
                "AI 대화 문맥 첨부 수신 · "
                    + attachment.name
            )
        case .file(let attachment):
            appendEvent(
                "AI 대화 파일 첨부 수신 · "
                    + attachment.name
            )
        }
        startRemoteFeatureQueueIfNeeded()
    }

    private func startRemoteFeatureQueueIfNeeded() {
        guard remoteFeatureTask == nil,
              isDataChannelReady,
              !remoteWorkQueue.isEmpty else {
            return
        }
        let generation = remoteFeatureGeneration
        remoteFeatureTask = Task { [weak self] in
            guard let self else {
                return
            }
            await self.drainRemoteFeatureQueue(
                generation: generation
            )
        }
    }

    private func drainRemoteFeatureQueue(
        generation: Int
    ) async {
        defer {
            if generation
                == remoteFeatureGeneration {
                remoteFeatureTask = nil
                startRemoteFeatureQueueIfNeeded()
            }
        }

        while !Task.isCancelled,
              generation == remoteFeatureGeneration,
              isDataChannelReady,
              !remoteWorkQueue.isEmpty {
            let work = remoteWorkQueue.removeFirst()
            do {
                switch work {
                case .feature(let request):
                    try await remoteFeatureProcessor
                        .process(
                            request
                        ) { [weak self] update in
                            guard let self,
                                  generation
                                    == self
                                        .remoteFeatureGeneration,
                                  self
                                    .isDataChannelReady,
                                  !Task
                                    .isCancelled
                            else {
                                return
                            }
                            self
                                .handleRemoteFeatureUpdate(
                                    update,
                                    request:
                                        request
                                )
                        }
                case .chat(let chatWork):
                    try await remoteChatProcessor
                        .process(
                            chatWork
                        ) { [weak self] update in
                            guard let self,
                                  generation
                                    == self
                                        .remoteFeatureGeneration,
                                  self
                                    .isDataChannelReady,
                                  !Task
                                    .isCancelled
                            else {
                                return
                            }
                            self
                                .handleRemoteChatUpdate(
                                    update
                                )
                        }
                    }
            } catch is CancellationError {
                return
            } catch {
                guard generation
                        == remoteFeatureGeneration,
                      isDataChannelReady else {
                    return
                }
                switch work {
                case .feature(let request):
                    handleRemoteFeatureUpdate(
                        .failed(
                            Self.userMessage(for: error)
                        ),
                        request: request
                    )
                case .chat(let chatWork):
                    handleUnexpectedRemoteChatError(
                        error,
                        work: chatWork
                    )
                }
            }
        }
    }

    private func handleRemoteChatUpdate(
        _ update: VisionLinkRemoteChatUpdate
    ) {
        switch update {
        case .progress(let request, let stage):
            _ = webRTCReceiver.sendFeatureProgress(
                requestID: request.requestID,
                feature: .aiChat,
                stage: stage
            )
            remoteFeatureStatus =
                VisionLinkRemoteFeatureStatus(
                    requestID: request.requestID,
                    feature: .aiChat,
                    stage: stage,
                    message: "답변 생각 중",
                    isWorking: true
                )
            appendEvent("원격 AI 대화 · 답변 생각 중")

        case .result(let request, let text):
            _ = webRTCReceiver.sendFeatureResult(
                requestID: request.requestID,
                feature: .aiChat,
                text: text
            )
            remoteFeatureStatus =
                VisionLinkRemoteFeatureStatus(
                    requestID: request.requestID,
                    feature: .aiChat,
                    stage: "complete",
                    message: "AI 대화 완료",
                    isWorking: false
                )
            dataTransferMessage = nil
            appendEvent("원격 AI 대화 결과 전송 완료")

        case .failed(let request, let message):
            _ = webRTCReceiver.sendFeatureError(
                requestID: request.requestID,
                feature: .aiChat,
                message: message
            )
            showRemoteChatFailure(
                id: request.requestID,
                message: message
            )

        case .attachmentReady(
            let attachmentID,
            let conversationID,
            let name
        ):
            _ = webRTCReceiver
                .sendChatAttachmentReady(
                    attachmentID: attachmentID,
                    conversationID:
                        conversationID,
                    name: name
                )
            remoteFeatureStatus =
                VisionLinkRemoteFeatureStatus(
                    requestID: attachmentID,
                    feature: .aiChat,
                    stage: "attachment-ready",
                    message: "\(name) 첨부 완료",
                    isWorking: false
                )
            dataTransferMessage = nil
            appendEvent(
                "AI 대화 첨부 준비 완료 · \(name)"
            )

        case .attachmentFailed(
            let attachmentID,
            let conversationID,
            let message
        ):
            _ = webRTCReceiver
                .sendChatAttachmentError(
                    attachmentID: attachmentID,
                    conversationID:
                        conversationID,
                    message: message
                )
            showRemoteChatFailure(
                id: attachmentID,
                message: message
            )
        }
    }

    private func handleUnexpectedRemoteChatError(
        _ error: Error,
        work: VisionLinkRemoteChatWork
    ) {
        let message = Self.userMessage(for: error)
        switch work {
        case .request(let request):
            _ = webRTCReceiver.sendFeatureError(
                requestID: request.requestID,
                feature: .aiChat,
                message: message
            )
            showRemoteChatFailure(
                id: request.requestID,
                message: message
            )
        case .context(let attachment):
            _ = webRTCReceiver
                .sendChatAttachmentError(
                    attachmentID:
                        attachment.attachmentID,
                    conversationID:
                        attachment.conversationID,
                    message: message
                )
            showRemoteChatFailure(
                id: attachment.attachmentID,
                message: message
            )
        case .file(let attachment):
            _ = webRTCReceiver
                .sendChatAttachmentError(
                    attachmentID:
                        attachment.attachmentID,
                    conversationID:
                        attachment.conversationID,
                    message: message
                )
            showRemoteChatFailure(
                id: attachment.attachmentID,
                message: message
            )
        }
    }

    private func showRemoteChatFailure(
        id: String,
        message: String
    ) {
        remoteFeatureStatus =
            VisionLinkRemoteFeatureStatus(
                requestID: id,
                feature: .aiChat,
                stage: "error",
                message: message,
                isWorking: false
            )
        dataTransferMessage = message
        appendEvent(
            "원격 AI 대화 실패 · " + message
        )
    }

    private func handleRemoteFeatureUpdate(
        _ update: VisionLinkRemoteFeatureUpdate,
        request: VisionLinkRemoteFeatureRequest
    ) {
        let requestID = request.requestID
        let feature = request.feature
        switch update {
        case .progress(let stage):
            _ = webRTCReceiver.sendFeatureProgress(
                requestID: requestID,
                feature: feature,
                stage: stage
            )
            remoteFeatureStatus =
                VisionLinkRemoteFeatureStatus(
                    requestID: requestID,
                    feature: feature,
                    stage: stage,
                    message:
                        Self.featureStageMessage(
                            feature: feature,
                            stage: stage
                        ),
                    isWorking: true
                )
            appendEvent(
                "원격 \(feature.title) · "
                    + Self.featureStageMessage(
                        feature: feature,
                        stage: stage
                    )
            )

        case .result(let text):
            _ = webRTCReceiver.sendFeatureResult(
                requestID: requestID,
                feature: feature,
                text: text
            )
            remoteFeatureStatus =
                VisionLinkRemoteFeatureStatus(
                    requestID: requestID,
                    feature: feature,
                    stage: "complete",
                    message: "\(feature.title) 완료",
                    isWorking: false
                )
            dataTransferMessage = nil
            appendEvent(
                "원격 \(feature.title) 결과 전송 완료"
            )

        case .failed(let message):
            _ = webRTCReceiver.sendFeatureError(
                requestID: requestID,
                feature: feature,
                message: message
            )
            remoteFeatureStatus =
                VisionLinkRemoteFeatureStatus(
                    requestID: requestID,
                    feature: feature,
                    stage: "error",
                    message: message,
                    isWorking: false
                )
            dataTransferMessage = message
            appendEvent(
                "원격 \(feature.title) 실패 · "
                    + message
            )
        }
    }

    private func invalidateRemoteFeatureWork(
        reason: String
    ) {
        stopRemoteLiveReading(reason: reason)
        remoteFeatureGeneration &+= 1
        remoteFeatureTask?.cancel()
        remoteFeatureTask = nil
        let queuedFiles = remoteWorkQueue
            .compactMap(\.temporaryFileURL)
        remoteWorkQueue = []
        queuedFiles.forEach {
            try? FileManager.default.removeItem(
                at: $0
            )
        }
        remoteFeatureStatus = nil
        if !queuedFiles.isEmpty {
            appendEvent(
                "원격 기능 작업 취소 · \(reason)"
            )
        }
    }

    private static func featureStageMessage(
        feature: VisionLinkRemoteFeature,
        stage: String
    ) -> String {
        switch stage {
        case "recognizing":
            return "글자 인식 중"
        case "translating":
            return "번역 중"
        case "analyzing":
            return "이미지 분석 중"
        default:
            return "\(feature.title) 처리 중"
        }
    }

    private func sendSignaling(
        _ message: String,
        successEvent: String
    ) {
        guard let socket = webSocket else {
            state = .failed(
                "VisionLink 신호 연결이 없어 응답을 보낼 수 없습니다."
            )
            return
        }
        let generation = socketGeneration
        Task { [weak self, socket] in
            do {
                try await socket.send(.string(message))
                guard let self,
                      generation == self.socketGeneration else {
                    return
                }
                self.appendEvent(successEvent)
            } catch {
                guard let self,
                      generation == self.socketGeneration else {
                    return
                }
                self.state = .failed(
                    "VisionLink 신호 전송 실패: "
                        + Self.userMessage(for: error)
                )
            }
        }
    }

    private func stopCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        remainingSeconds = nil
    }

    private func resetVisibleSession() {
        pairingCode = nil
        pairingURI = nil
        remainingSeconds = nil
        roomID = nil
        peerName = nil
    }

    private func normalizedPeerName(
        _ value: String?
    ) -> String {
        let normalized = value?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return String(
            ((normalized?.isEmpty == false)
                ? normalized!
                : "VisionLink")
                .prefix(80)
        )
    }

    private func appendEvent(_ summary: String) {
        recentEvents.insert(
            VisionLinkEventRecord(
                id: UUID(),
                date: Date(),
                summary: summary
            ),
            at: 0
        )
        if recentEvents.count > 30 {
            recentEvents.removeLast(
                recentEvents.count - 30
            )
        }
    }

    private static func userMessage(
        for error: Error
    ) -> String {
        if let error = error as? LocalizedError,
           let description = error.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}

extension VisionLinkManager:
    VisionLinkWebRTCReceiverDelegate
{
    func webRTCReceiver(
        _ receiver: VisionLinkWebRTCReceiver,
        didCreateAnswer sdp: String
    ) {
        do {
            sendSignaling(
                try VisionLinkJSON.answerMessage(sdp: sdp),
                successEvent: "영상 연결 응답 전송"
            )
        } catch {
            state = .failed(
                Self.userMessage(for: error)
            )
        }
    }

    func webRTCReceiver(
        _ receiver: VisionLinkWebRTCReceiver,
        didGenerate candidate: VisionLinkIceCandidate
    ) {
        do {
            sendSignaling(
                try VisionLinkJSON.iceCandidateMessage(
                    candidate
                ),
                successEvent: "로컬 네트워크 후보 전송"
            )
        } catch {
            state = .failed(
                Self.userMessage(for: error)
            )
        }
    }

    func webRTCReceiverDidFinishGathering(
        _ receiver: VisionLinkWebRTCReceiver
    ) {
        do {
            sendSignaling(
                try VisionLinkJSON.iceCandidateMessage(nil),
                successEvent: "로컬 네트워크 후보 수집 완료"
            )
        } catch {
            state = .failed(
                Self.userMessage(for: error)
            )
        }
    }

    func webRTCReceiver(
        _ receiver: VisionLinkWebRTCReceiver,
        didChange mediaState: VisionLinkMediaConnectionState
    ) {
        switch mediaState {
        case .connecting:
            state = .mediaConnecting
        case .connected:
            if state != .videoReceiving {
                state = .mediaConnected
            }
            appendEvent("WebRTC 미디어 연결됨")
        case .disconnected:
            state = .disconnected
            appendEvent("WebRTC 미디어 연결 끊김")
        case .failed:
            remoteVideoTrack = nil
            state = .failed(
                "VisionLink 영상 연결에 실패했습니다."
            )
            appendEvent("WebRTC 미디어 연결 실패")
        }
    }

    func webRTCReceiver(
        _ receiver: VisionLinkWebRTCReceiver,
        didReceive videoTrack: RTCVideoTrack
    ) {
        remoteVideoTrack = videoTrack
        appendEvent("원격 비디오 트랙 수신")
    }

    func webRTCReceiver(
        _ receiver: VisionLinkWebRTCReceiver,
        dataChannelReady: Bool
    ) {
        guard isDataChannelReady
                != dataChannelReady else {
            return
        }
        isDataChannelReady = dataChannelReady
        if dataChannelReady {
            dataTransferMessage = nil
            appendEvent("VisionLink 데이터 채널 연결됨")
            startRemoteFeatureQueueIfNeeded()
        } else {
            invalidateRemoteFeatureWork(
                reason: "data-channel-closed"
            )
            isCameraShareActive = false
            incomingTransfer = nil
            appendEvent("VisionLink 데이터 채널 연결 끊김")
        }
    }

    func webRTCReceiver(
        _ receiver: VisionLinkWebRTCReceiver,
        didReceive dataEvent: VisionLinkDataEvent
    ) {
        switch dataEvent {
        case .cameraShareChanged(let active):
            isCameraShareActive = active
            if !active {
                stopRemoteLiveReading(
                    reason:
                        "camera-share-stopped"
                )
            }
            appendEvent(
                active
                    ? "상대 카메라 공유 시작"
                    : "상대 카메라 공유 종료"
            )
        case .clipboardReceived(let text):
            receivedClipboardText = text
            dataTransferMessage = nil
            appendEvent(
                "클립보드 텍스트 수신 · "
                    + "\(text.count)자"
            )
        case .transferStarted(let progress):
            incomingTransfer = progress
            dataTransferMessage = nil
            appendEvent(
                "파일 수신 시작 · "
                    + progress.fileName
            )
        case .transferProgress(let progress):
            incomingTransfer = progress
        case .fileReceived(let file):
            incomingTransfer = nil
            lastReceivedFile = file
            dataTransferMessage = nil
            appendEvent(
                "파일 수신 완료 · "
                    + file.fileName
            )
        case .remoteFeatureRequested(let request):
            incomingTransfer = nil
            dataTransferMessage = nil
            enqueueRemoteFeature(request)
        case .remoteChatRequested(let request):
            dataTransferMessage = nil
            enqueueRemoteChat(.request(request))
        case .remoteChatContextReceived(
            let attachment
        ):
            dataTransferMessage = nil
            enqueueRemoteChat(.context(attachment))
        case .remoteChatAttachmentReceived(
            let attachment
        ):
            incomingTransfer = nil
            dataTransferMessage = nil
            enqueueRemoteChat(.file(attachment))
        case .liveReadingStarted(
            let sessionID
        ):
            startRemoteLiveReading(
                sessionID: sessionID
            )
        case .liveReadingStopped(
            let sessionID
        ):
            stopRemoteLiveReading(
                reason: "peer-requested",
                requestedSessionID:
                    sessionID,
                sendStoppedStatus: true
            )
        case .failed(let message):
            incomingTransfer = nil
            dataTransferMessage = message
            appendEvent(message)
        }
    }

    func webRTCReceiver(
        _ receiver: VisionLinkWebRTCReceiver,
        didFail message: String
    ) {
        remoteVideoTrack = nil
        state = .failed(message)
        appendEvent(message)
    }

    func webRTCReceiver(
        _ receiver: VisionLinkWebRTCReceiver,
        didReceiveLiveReadingFrame image:
            CGImage
    ) {
        processLiveReadingFrame(image)
    }

    func webRTCReceiver(
        _ receiver: VisionLinkWebRTCReceiver,
        didFailLiveReadingFrame message: String
    ) {
        guard let sessionID =
                liveReadingSessionID else {
            return
        }
        sendLiveReadingError(
            sessionID: sessionID,
            message: message.isEmpty
                ? "카메라 화면을 읽지 못했습니다."
                : message
        )
        scheduleNextLiveReadingFrame(
            sessionID: sessionID,
            generation:
                remoteFeatureGeneration
        )
    }
}
