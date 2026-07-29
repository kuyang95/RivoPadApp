@preconcurrency import StreamWebRTC
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
        remoteVideoTrack = nil
        pendingRemoteCandidates = []
        peerConnection?.close()
        peerConnection = nil
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
        remoteVideoTrack = track
        delegate?.webRTCReceiver(
            self,
            didReceive: track
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
    ) {}

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
