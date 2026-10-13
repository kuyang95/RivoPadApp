@preconcurrency import StreamWebRTC
import CoreGraphics
import Foundation

nonisolated enum VisionLinkMediaConnectionState:
    Equatable,
    Sendable
{
    case connecting
    case connected
    case disconnected
    case failed
}

@MainActor
protocol VisionLinkWebRTCReceiverDelegate: AnyObject {
    func webRTCReceiver(
        _ receiver: VisionLinkWebRTCReceiver,
        didMeasureVideoQuality quality: VisionLinkVideoQuality?
    )

    func webRTCReceiver(
        _ receiver: VisionLinkWebRTCReceiver,
        didCreateAnswer sdp: String
    )

    func webRTCReceiver(
        _ receiver: VisionLinkWebRTCReceiver,
        didGenerate candidate: VisionLinkIceCandidate
    )

    func webRTCReceiverDidFinishGathering(
        _ receiver: VisionLinkWebRTCReceiver
    )

    func webRTCReceiver(
        _ receiver: VisionLinkWebRTCReceiver,
        didChange state: VisionLinkMediaConnectionState
    )

    func webRTCReceiver(
        _ receiver: VisionLinkWebRTCReceiver,
        didReceive videoTrack: RTCVideoTrack
    )

    func webRTCReceiverDidReceiveVideoFrame(
        _ receiver: VisionLinkWebRTCReceiver
    )

    func webRTCReceiver(
        _ receiver: VisionLinkWebRTCReceiver,
        didReceiveLiveReadingFrame image:
            CGImage
    )

    func webRTCReceiver(
        _ receiver: VisionLinkWebRTCReceiver,
        didFailLiveReadingFrame message: String
    )

    func webRTCReceiver(
        _ receiver: VisionLinkWebRTCReceiver,
        dataChannelReady: Bool
    )

    func webRTCReceiver(
        _ receiver: VisionLinkWebRTCReceiver,
        didReceive dataEvent: VisionLinkDataEvent
    )

    func webRTCReceiver(
        _ receiver: VisionLinkWebRTCReceiver,
        didFail message: String
    )
    func webRTCReceiver(_ receiver: VisionLinkWebRTCReceiver, compatibilityFailed message: String)
}

@MainActor
final class VisionLinkWebRTCReceiver: NSObject {
    weak var delegate:
        (any VisionLinkWebRTCReceiverDelegate)?

    private static let didInitializeSSL: Bool =
        RTCInitializeSSL()

    private let factory: RTCPeerConnectionFactory
    private var peerConnection: RTCPeerConnection?
    private var negotiationTask: Task<Void, Never>?
    private var videoStatisticsTask: Task<Void, Never>?
    private var videoStatisticsGeneration = 0
    private var videoQualityMeter = VisionLinkVideoQualityMeter()

    private var pendingRemoteCandidates: [RTCIceCandidate] = []
    private weak var remoteVideoTrack: RTCVideoTrack?
    private var compatibility: VisionLinkCompatibility?
    private(set) var compatibilityFailed = false
    private var compatibilityReady = false
    private var acceptedHelloID: String?
    private var compatibilityDeadline: Task<Void, Never>?
    private var pendingCompatibleVideoTrack: RTCVideoTrack?
    private var dataChannel: RTCDataChannel?
    private var dataChannelBridge:
        VisionLinkDataChannelBridge?
    private var dataReceiver:
        VisionLinkDataReceiver?
    private var dataReceiveTask: Task<Void, Never>?
    private lazy var liveReadingFrameSampler =
        VisionLinkVideoFrameSampler(
            frameHandler: { [weak self] in
                guard let self else {
                    return
                }
                self.delegate?
                    .webRTCReceiverDidReceiveVideoFrame(
                        self
                    )
            },
            handler: { [weak self] result in
                guard let self else {
                    return
                }
                switch result {
                case .success(let image):
                    self.delegate?.webRTCReceiver(
                        self,
                        didReceiveLiveReadingFrame:
                            image
                    )
                case .failure(let error):
                    self.delegate?.webRTCReceiver(
                        self,
                        didFailLiveReadingFrame:
                            error.localizedDescription
                    )
                }
            }
        )

    override init() {
        _ = Self.didInitializeSSL
        factory = RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )
        super.init()
    }

    func prepare(
        iceServers: [VisionLinkIceServer],
        relayPolicy: String
    ) throws {
        close()

        let configuration = RTCConfiguration()
        configuration.sdpSemantics = .unifiedPlan
        configuration.iceTransportPolicy = .all
        configuration.iceServers = iceServers.flatMap {
            server in
            server.urls.compactMap { url in
                if relayPolicy == "relay-forbidden",
                   url.lowercased().hasPrefix("turn:") {
                    return nil
                }
                if relayPolicy == "relay-forbidden",
                   url.lowercased().hasPrefix("turns:") {
                    return nil
                }
                return RTCIceServer(
                    urlStrings: [url],
                    username: server.username,
                    credential: server.credential
                )
            }
        }

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: nil
        )
        guard let peerConnection = factory.peerConnection(
            with: configuration,
            constraints: constraints,
            delegate: self
        ) else {
            throw VisionLinkWebRTCError
                .peerConnectionCreationFailed
        }
        self.peerConnection = peerConnection
        pendingRemoteCandidates = []
    }

    func handleOffer(
        _ offer: VisionLinkSessionDescription,
        iceServers: [VisionLinkIceServer],
        relayPolicy: String
    ) {
        guard !compatibilityFailed else { return }
        do {
            if peerConnection == nil {
                try prepare(
                    iceServers: iceServers,
                    relayPolicy: relayPolicy
                )
            }
        } catch {
            fail(error.localizedDescription)
            return
        }

        guard let peerConnection else {
            fail(
                VisionLinkWebRTCError
                    .peerConnectionCreationFailed
                    .localizedDescription
            )
            return
        }

        delegate?.webRTCReceiver(
            self,
            didChange: .connecting
        )
        let description = RTCSessionDescription(
            type: .offer,
            sdp: offer.sdp
        )
        negotiationTask?.cancel()
        negotiationTask = Task {
            do {
                try await peerConnection
                    .setRemoteDescription(description)
                try Task.checkCancellation()
                self.drainPendingCandidates(
                    into: peerConnection
                )
                try await self.createAndSetAnswer(
                    for: peerConnection
                )
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, self.peerConnection === peerConnection else { return }
                self.fail(
                    AppLocalization.format(
                        "VisionLink 연결 협상 실패: %@",
                        error.localizedDescription
                    )
                )
            }
        }
    }

    func addRemoteIceCandidate(
        _ candidate: VisionLinkIceCandidate
    ) {
        guard let rawCandidate = candidate.candidate else {
            return
        }
        let webRTCCandidate = RTCIceCandidate(
            sdp: rawCandidate,
            sdpMLineIndex: Int32(
                candidate.sdpMLineIndex ?? 0
            ),
            sdpMid: candidate.sdpMid
        )
        guard let peerConnection,
              peerConnection.remoteDescription != nil else {
            if pendingRemoteCandidates.count >= 256 { pendingRemoteCandidates.removeFirst() }
            pendingRemoteCandidates.append(
                webRTCCandidate
            )
            return
        }
        add(
            webRTCCandidate,
            to: peerConnection
        )
    }

    func close() {
        setVideoStatisticsActive(false)
        negotiationTask?.cancel()
        negotiationTask = nil
        closeDataChannel()
        if let remoteVideoTrack {
            remoteVideoTrack.remove(
                liveReadingFrameSampler
            )
        }
        liveReadingFrameSampler.cancelRequest()
        remoteVideoTrack = nil
        pendingRemoteCandidates = []
        peerConnection?.delegate = nil
        peerConnection?.close()
        peerConnection = nil
    }

    func setVideoStatisticsActive(_ active: Bool) {
        if active && videoStatisticsTask != nil { return }
        videoStatisticsTask?.cancel()
        videoStatisticsTask = nil
        videoStatisticsGeneration &+= 1
        videoQualityMeter = VisionLinkVideoQualityMeter()
        delegate?.webRTCReceiver(self, didMeasureVideoQuality: nil)
        guard active, let peerConnection else { return }
        let generation = videoStatisticsGeneration
        videoStatisticsTask = Task { [weak self, weak peerConnection] in
            while !Task.isCancelled {
                guard let self, let peerConnection else { return }
                let report = await withCheckedContinuation { continuation in
                    peerConnection.statistics { report in
                        continuation.resume(returning: report)
                    }
                }
                guard !Task.isCancelled,
                      self.peerConnection === peerConnection,
                      self.videoStatisticsGeneration == generation else { return }
                self.reportVideoQuality(report)
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch { return }
            }
        }
    }

    private func reportVideoQuality(_ report: RTCStatisticsReport) {
        guard let stats = report.statistics.values.first(where: {
            $0.type == "inbound-rtp" &&
                (($0.values["kind"] as? String) == "video" ||
                 ($0.values["mediaType"] as? String) == "video")
        }) else {
            delegate?.webRTCReceiver(self, didMeasureVideoQuality: nil)
            return
        }
        func number(_ key: String) -> Double? {
            let value = (stats.values[key] as? NSNumber)?.doubleValue
                ?? (stats.values[key] as? String).flatMap(Double.init)
            return value.flatMap { $0.isFinite ? $0 : nil }
        }
        let quality = videoQualityMeter.sample(
            id: stats.id, timestampUs: stats.timestamp_us,
            width: Int(number("frameWidth") ?? 0),
            height: Int(number("frameHeight") ?? 0),
            bytesReceived: number("bytesReceived"),
            framesDecoded: number("framesDecoded"), fps: number("framesPerSecond")
        )
        delegate?.webRTCReceiver(self, didMeasureVideoQuality: quality)
    }

    @discardableResult
    func sendFeatureProgress(
        requestID: String,
        feature: VisionLinkRemoteFeature,
        stage: String
    ) -> Bool {
        sendControl(
            VisionLinkFeatureControl.progress(
                requestID: requestID,
                feature: feature,
                stage: stage
            )
        )
    }

    @discardableResult
    func sendFeatureResult(
        requestID: String,
        feature: VisionLinkRemoteFeature,
        text: String
    ) -> Bool {
        sendControl(
            VisionLinkFeatureControl.result(
                requestID: requestID,
                feature: feature,
                text: text
            )
        )
    }

    @discardableResult
    func sendFeatureError(
        requestID: String,
        feature: VisionLinkRemoteFeature,
        message: String
    ) -> Bool {
        sendControl(
            VisionLinkFeatureControl.error(
                requestID: requestID,
                feature: feature,
                message: message
            )
        )
    }

    @discardableResult
    func sendChatAttachmentReady(
        attachmentID: String,
        conversationID: String,
        name: String
    ) -> Bool {
        sendControl(
            VisionLinkChatControl.attachmentReady(
                attachmentID: attachmentID,
                conversationID: conversationID,
                name: name
            )
        )
    }

    @discardableResult
    func sendChatAttachmentError(
        attachmentID: String,
        conversationID: String,
        message: String
    ) -> Bool {
        sendControl(
            VisionLinkChatControl.attachmentError(
                attachmentID: attachmentID,
                conversationID: conversationID,
                message: message
            )
        )
    }

    @discardableResult
    func sendLiveReadingStatus(
        sessionID: String,
        state: String
    ) -> Bool {
        sendControl(
            VisionLinkLiveReadingControl.status(
                sessionID: sessionID,
                state: state
            )
        )
    }

    @discardableResult
    func sendLiveReadingResult(
        sessionID: String,
        sequence: Int,
        text: String
    ) -> Bool {
        sendControl(
            VisionLinkLiveReadingControl.result(
                sessionID: sessionID,
                sequence: sequence,
                text: text
            )
        )
    }

    @discardableResult
    func sendLiveReadingError(
        sessionID: String,
        message: String
    ) -> Bool {
        sendControl(
            VisionLinkLiveReadingControl.error(
                sessionID: sessionID,
                message: message
            )
        )
    }

    func requestLiveReadingFrame() {
        liveReadingFrameSampler.requestFrame()
    }

    func cancelLiveReadingFrameRequest() {
        liveReadingFrameSampler.cancelRequest()
    }

    private func createAndSetAnswer(
        for peerConnection: RTCPeerConnection
    ) async throws {
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: nil
        )
        let description = try await peerConnection.answer(
            for: constraints
        )
        try Task.checkCancellation()
        try await peerConnection.setLocalDescription(
            description
        )
        try Task.checkCancellation()
        delegate?.webRTCReceiver(
            self,
            didCreateAnswer: description.sdp
        )
    }

    private func drainPendingCandidates(
        into peerConnection: RTCPeerConnection
    ) {
        let candidates = pendingRemoteCandidates
        pendingRemoteCandidates = []
        candidates.forEach {
            add($0, to: peerConnection)
        }
    }

    private func add(
        _ candidate: RTCIceCandidate,
        to peerConnection: RTCPeerConnection
    ) {
        Task {
            do {
                try await peerConnection.add(candidate)
            } catch {
                guard self.peerConnection === peerConnection else { return }
                fail(
                    AppLocalization.format(
                        "VisionLink ICE 후보 적용 실패: %@",
                        error.localizedDescription
                    )
                )
            }
        }
    }

    private func attachVideoTrack(
        _ track: RTCMediaStreamTrack?
    ) {
        guard let track = track as? RTCVideoTrack else { return }
        guard compatibility?.cameraAvailable == true, !compatibilityFailed else {
            pendingCompatibleVideoTrack = track
            return
        }
        guard remoteVideoTrack !== track else {
            return
        }
        remoteVideoTrack?.remove(
            liveReadingFrameSampler
        )
        remoteVideoTrack = track
        track.add(liveReadingFrameSampler)
        setVideoStatisticsActive(true)
        delegate?.webRTCReceiver(
            self,
            didReceive: track
        )
    }

    private func attachDataChannel(
        _ channel: RTCDataChannel
    ) {
        let pendingTrack = pendingCompatibleVideoTrack
        closeDataChannel()
        pendingCompatibleVideoTrack = pendingTrack

        let destinationDirectory =
            FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            )
            .first!
            .appendingPathComponent(
                "VisionLink",
                isDirectory: true
            )
        let partialDirectory =
            FileManager.default.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            )
            .first!
            .appendingPathComponent(
                "VisionLink/Incoming",
                isDirectory: true
            )
        let receiver = VisionLinkDataReceiver(
            destinationDirectory:
                destinationDirectory,
            partialDirectory: partialDirectory
        )

        var continuation:
            AsyncStream<VisionLinkDataInput>
                .Continuation?
        let stream = AsyncStream<
            VisionLinkDataInput
        > { value in
            continuation = value
        }
        guard let continuation else {
            fail(
                AppLocalization.string(
                    "VisionLink 데이터 수신기를 만들 수 없습니다."
                )
            )
            return
        }
        let bridge = VisionLinkDataChannelBridge(
            continuation: continuation
        )

        dataChannel = channel
        dataReceiver = receiver
        dataChannelBridge = bridge
        channel.delegate = bridge
        dataReceiveTask = Task { [weak self] in
            for await input in stream {
                guard !Task.isCancelled,
                      let self else {
                    return
                }
                switch input {
                case .opened:
                    self.startCompatibilityDeadline(channel)
                case .closed:
                    self.compatibilityDeadline?.cancel()
                    self.compatibility = nil
                    await receiver.close()
                    self.delegate?.webRTCReceiver(
                        self,
                        dataChannelReady: false
                    )
                case .control, .binary:
                    guard self.acceptCompatibleInput(input) else { continue }
                    let actions = await receiver
                        .receive(input)
                    guard !Task.isCancelled else {
                        return
                    }
                    self.handleDataActions(actions)
                }
            }
        }
        bridge.publishCurrentState(of: channel)
    }

    private func closeDataChannel() {
        compatibilityDeadline?.cancel()
        compatibilityDeadline = nil
        compatibility = nil
        compatibilityFailed = false
        acceptedHelloID = nil
        compatibilityReady = false
        pendingCompatibleVideoTrack = nil
        let receiver = dataReceiver
        dataChannel?.delegate = nil
        dataChannel?.close()
        dataChannelBridge?.finish()
        dataReceiveTask?.cancel()
        dataReceiveTask = nil
        dataChannelBridge = nil
        dataReceiver = nil
        dataChannel = nil
        if let receiver {
            Task {
                await receiver.close()
            }
        }
        delegate?.webRTCReceiver(
            self,
            dataChannelReady: false
        )
    }

    private func handleDataActions(
        _ actions: [VisionLinkDataAction]
    ) {
        for action in actions {
            switch action {
            case .sendControl(let data):
                _ = sendControl(data)
            case .event(let event):
                delegate?.webRTCReceiver(
                    self,
                    didReceive: event
                )
            }
        }
    }

    @discardableResult
    func requestMediaRecovery() -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: ["type": "media-recovery-request"]) else { return false }
        return sendControl(data)
    }

    @discardableResult
    func requestCameraZoom(sessionID: String, value: Double) -> Bool {
        guard value.isFinite,
              let data = try? JSONSerialization.data(withJSONObject: [
                "type": "camera-zoom-request", "sessionId": sessionID, "value": value
              ]) else { return false }
        return sendControl(data)
    }

    private func startCompatibilityDeadline(_ channel: RTCDataChannel) {
        guard compatibilityDeadline == nil, compatibility == nil, !compatibilityFailed else { return }
        compatibilityDeadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(6)) } catch { return }
            guard let self, self.dataChannel === channel, channel.readyState == .open, !self.compatibilityReady else { return }
            self.rejectCompatibility()
        }
    }

    private func rejectCompatibility() {
        guard !compatibilityFailed else { return }
        compatibilityFailed = true
        setVideoStatisticsActive(false)
        remoteVideoTrack?.remove(liveReadingFrameSampler)
        remoteVideoTrack = nil
        compatibility = nil
        compatibilityDeadline?.cancel()
        pendingCompatibleVideoTrack = nil
        delegate?.webRTCReceiver(self, compatibilityFailed: AppLocalization.string(VisionLinkCompatibility.updateMessage))
    }

    private func acceptCompatibleInput(_ input: VisionLinkDataInput) -> Bool {
        guard !compatibilityFailed else { return false }
        switch input {
        case .binary:
            return compatibility?.common.contains("file.v1") == true
        case .control(let data):
            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let type = json["type"] as? String else { return false }
            if type == "visionlink-hello" {
                guard let requestID = json["requestId"] as? String, !requestID.isEmpty, requestID.count <= 80,
                      let agreed = VisionLinkCompatibility(message: json),
                      acceptedHelloID == nil || (acceptedHelloID == requestID && compatibility == agreed) else {
                    rejectCompatibility(); return false
                }
                let first = !compatibilityReady
                compatibility = agreed
                acceptedHelloID = requestID
                if sendControl(VisionLinkCompatibility.hello(requestID: requestID)), first {
                    compatibilityReady = true
                    compatibilityDeadline?.cancel()
                    delegate?.webRTCReceiver(self, dataChannelReady: true)
                    if let track = pendingCompatibleVideoTrack {
                        pendingCompatibleVideoTrack = nil
                        attachVideoTrack(track)
                    }
                }
                return false
            }
            guard compatibility?.permits(type) == true else { return false }
            if type == "file-start", json["feature"] != nil || json["purpose"] as? String == "visioncraft-chat-attachment" {
                return compatibility?.common.contains("remote-actions.v1") == true
            }
            return true
        default: return false
        }
    }

    private func sendControl(_ data: Data) -> Bool {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = json["type"] as? String,
              type == "visionlink-hello" || (!compatibilityFailed && compatibility?.permits(type) == true) else { return false }
        guard let dataChannel,
              dataChannel.readyState == .open else {
            return false
        }
        return dataChannel.sendData(
            RTCDataBuffer(
                data: data,
                isBinary: false
            )
        )
    }

    private func fail(_ message: String) {
        delegate?.webRTCReceiver(
            self,
            didFail: message
        )
    }
}

extension VisionLinkWebRTCReceiver:
    RTCPeerConnectionDelegate
{
    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didChange stateChanged: RTCSignalingState
    ) {}

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didAdd stream: RTCMediaStream
    ) {
        let track = stream.videoTracks.first
        Task { @MainActor [weak self] in
            guard let self, self.peerConnection === peerConnection else { return }
            self.attachVideoTrack(track)
        }
    }

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didRemove stream: RTCMediaStream
    ) {}

    nonisolated func peerConnectionShouldNegotiate(
        _ peerConnection: RTCPeerConnection
    ) {}

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didChange newState: RTCIceConnectionState
    ) {
        let state: VisionLinkMediaConnectionState?
        switch newState {
        case .checking:
            state = .connecting
        case .connected, .completed:
            state = .connected
        case .disconnected, .closed:
            state = .disconnected
        case .failed:
            state = .failed
        case .new, .count:
            state = nil
        @unknown default:
            state = nil
        }
        guard let state else {
            return
        }
        Task { @MainActor [weak self] in
            guard let self, self.peerConnection === peerConnection else {
                return
            }
            self.delegate?.webRTCReceiver(
                self,
                didChange: state
            )
        }
    }

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didChange newState: RTCIceGatheringState
    ) {
        guard newState == .complete else {
            return
        }
        Task { @MainActor [weak self] in
            guard let self, self.peerConnection === peerConnection else {
                return
            }
            self.delegate?
                .webRTCReceiverDidFinishGathering(self)
        }
    }

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didGenerate candidate: RTCIceCandidate
    ) {
        let value = VisionLinkIceCandidate(
            messageID: nil,
            candidate: candidate.sdp,
            sdpMid: candidate.sdpMid,
            sdpMLineIndex: Int(candidate.sdpMLineIndex)
        )
        Task { @MainActor [weak self] in
            guard let self, self.peerConnection === peerConnection else {
                return
            }
            self.delegate?.webRTCReceiver(
                self,
                didGenerate: value
            )
        }
    }

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didRemove candidates: [RTCIceCandidate]
    ) {}

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didOpen dataChannel: RTCDataChannel
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.peerConnection === peerConnection else { return }
            self.attachDataChannel(dataChannel)
        }
    }

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didAdd rtpReceiver: RTCRtpReceiver,
        streams mediaStreams: [RTCMediaStream]
    ) {
        let track = rtpReceiver.track
        Task { @MainActor [weak self] in
            guard let self, self.peerConnection === peerConnection else { return }
            self.attachVideoTrack(track)
        }
    }
}

nonisolated private final class
    VisionLinkDataChannelBridge:
    NSObject,
    RTCDataChannelDelegate,
    @unchecked Sendable
{
    private let continuation:
        AsyncStream<VisionLinkDataInput>
            .Continuation

    init(
        continuation:
            AsyncStream<VisionLinkDataInput>
                .Continuation
    ) {
        self.continuation = continuation
    }

    func publishCurrentState(
        of dataChannel: RTCDataChannel
    ) {
        dataChannelDidChangeState(dataChannel)
    }

    func finish() {
        continuation.finish()
    }

    func dataChannelDidChangeState(
        _ dataChannel: RTCDataChannel
    ) {
        switch dataChannel.readyState {
        case .open:
            continuation.yield(.opened)
        case .closed:
            continuation.yield(.closed)
        case .connecting, .closing:
            break
        @unknown default:
            break
        }
    }

    func dataChannel(
        _ dataChannel: RTCDataChannel,
        didReceiveMessageWith buffer: RTCDataBuffer
    ) {
        if buffer.isBinary {
            continuation.yield(
                .binary(buffer.data)
            )
        } else {
            continuation.yield(
                .control(buffer.data)
            )
        }
    }
}

nonisolated enum VisionLinkWebRTCError:
    Error,
    LocalizedError,
    Equatable
{
    case peerConnectionCreationFailed

    var errorDescription: String? {
        AppLocalization.string(
            "VisionLink 미디어 연결을 만들 수 없습니다."
        )
    }
}
