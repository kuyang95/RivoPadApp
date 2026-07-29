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
    private var pendingRemoteCandidates: [RTCIceCandidate] = []
    private weak var remoteVideoTrack: RTCVideoTrack?
    private var dataChannel: RTCDataChannel?
    private var dataChannelBridge:
        VisionLinkDataChannelBridge?
    private var dataReceiver:
        VisionLinkDataReceiver?
    private var dataReceiveTask: Task<Void, Never>?
    private lazy var liveReadingFrameSampler =
        VisionLinkVideoFrameSampler {
            [weak self] result in
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
                self.fail(
                    "VisionLink 연결 협상 실패: "
                        + error.localizedDescription
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
        peerConnection?.close()
        peerConnection = nil
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
                fail(
                    "VisionLink ICE 후보 적용 실패: "
                        + error.localizedDescription
                )
            }
        }
    }

    private func attachVideoTrack(
        _ track: RTCMediaStreamTrack?
    ) {
        guard let track = track as? RTCVideoTrack,
              remoteVideoTrack !== track else {
            return
        }
        remoteVideoTrack?.remove(
            liveReadingFrameSampler
        )
        remoteVideoTrack = track
        track.add(liveReadingFrameSampler)
        delegate?.webRTCReceiver(
            self,
            didReceive: track
        )
    }

    private func attachDataChannel(
        _ channel: RTCDataChannel
    ) {
        closeDataChannel()

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
                "VisionLink 데이터 수신기를 만들 수 없습니다."
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
                    self.delegate?.webRTCReceiver(
                        self,
                        dataChannelReady: true
                    )
                case .closed:
                    await receiver.close()
                    self.delegate?.webRTCReceiver(
                        self,
                        dataChannelReady: false
                    )
                case .control, .binary:
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
    private func sendControl(_ data: Data) -> Bool {
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
            self?.attachVideoTrack(track)
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
            guard let self else {
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
            guard let self else {
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
            guard let self else {
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
            self?.attachDataChannel(dataChannel)
        }
    }

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didAdd rtpReceiver: RTCRtpReceiver,
        streams mediaStreams: [RTCMediaStream]
    ) {
        let track = rtpReceiver.track
        Task { @MainActor [weak self] in
            self?.attachVideoTrack(track)
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
        "VisionLink 미디어 연결을 만들 수 없습니다."
    }
}
