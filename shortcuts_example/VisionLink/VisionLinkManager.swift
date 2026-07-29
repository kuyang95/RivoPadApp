import Combine
import Foundation
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
             .mediaOfferReceived:
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
    @Published private(set) var recentEvents:
        [VisionLinkEventRecord] = []

    private let server: any VisionLinkServerServing
    private let credentialStore:
        any VisionLinkCredentialStoring
    private let webSocketSession: URLSession
    private let deviceName: String

    private var connectionTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var webSocket: URLSessionWebSocketTask?
    private var socketGeneration = 0

    init(
        server: any VisionLinkServerServing =
            VisionLinkServerClient(),
        credentialStore:
            any VisionLinkCredentialStoring =
                VisionLinkCredentialStore(),
        webSocketSession: URLSession = .shared,
        deviceName: String? = nil
    ) {
        self.server = server
        self.credentialStore = credentialStore
        self.webSocketSession = webSocketSession
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
    }

    deinit {
        connectionTask?.cancel()
        receiveTask?.cancel()
        countdownTask?.cancel()
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

        case .offer:
            confirmPairing()
            state = .mediaOfferReceived

        case .peerLeft, .hangup:
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

        case .answer,
             .iceCandidate,
             .unknown:
            break
        }
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
        webSocket?.cancel(
            with: .goingAway,
            reason: reason.data(using: .utf8)
        )
        webSocket = nil
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
