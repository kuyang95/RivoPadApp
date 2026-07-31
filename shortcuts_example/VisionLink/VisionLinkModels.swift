import Foundation

nonisolated enum VisionLinkContract {
    static let baseURL = URL(
        string: "https://rivo-oracle.duckdns.org/visionlink"
    )!
    static let receiverRole = "receiver"
    static let p2pPreferred = "p2p-preferred"
}

nonisolated struct VisionLinkStoredCredentials:
    Codable,
    Equatable,
    Sendable
{
    let pairID: String
    let deviceID: String
    let deviceToken: String
    var isConfirmed: Bool
}

nonisolated struct VisionLinkDeviceEndpoint:
    Decodable,
    Equatable,
    Sendable
{
    let deviceID: String?
    let deviceToken: String?
    let sessionToken: String?
    let websocketURL: String

    private enum CodingKeys: String, CodingKey {
        case deviceID = "deviceId"
        case deviceToken
        case sessionToken
        case websocketURL = "websocketUrl"
    }
}

nonisolated struct VisionLinkIceServer:
    Decodable,
    Equatable,
    Sendable
{
    let urls: [String]
    let username: String?
    let credential: String?

    private enum CodingKeys: String, CodingKey {
        case urls
        case username
        case credential
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        if let values = try? container.decode(
            [String].self,
            forKey: .urls
        ) {
            urls = values
        } else {
            urls = [
                try container.decode(
                    String.self,
                    forKey: .urls
                )
            ]
        }
        username = try container.decodeIfPresent(
            String.self,
            forKey: .username
        )
        credential = try container.decodeIfPresent(
            String.self,
            forKey: .credential
        )
    }
}

nonisolated struct VisionLinkSessionResponse:
    Decodable,
    Equatable,
    Sendable
{
    let roomID: String?
    let pairingCode: String?
    let pairingURI: String?
    let ttlSeconds: Int?
    let expiresAt: String?
    let pairID: String
    let receiver: VisionLinkDeviceEndpoint
    let iceServers: [VisionLinkIceServer]
    let relayPolicy: String

    private struct Pair: Decodable {
        let pairID: String

        private enum CodingKeys: String, CodingKey {
            case pairID = "pairId"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case roomID = "roomId"
        case pairingCode
        case pairingURI = "pairingUri"
        case ttlSeconds
        case expiresAt
        case pair
        case receiver
        case iceServers
        case relayPolicy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        roomID = try container.decodeIfPresent(
            String.self,
            forKey: .roomID
        )
        pairingCode = try Self.decodePairingCode(
            from: container
        )
        pairingURI = try container.decodeIfPresent(
            String.self,
            forKey: .pairingURI
        )
        ttlSeconds = try Self.decodeInteger(
            from: container,
            key: .ttlSeconds
        )
        expiresAt = try container.decodeIfPresent(
            String.self,
            forKey: .expiresAt
        )
        pairID = try container.decode(
            Pair.self,
            forKey: .pair
        ).pairID
        receiver = try container.decode(
            VisionLinkDeviceEndpoint.self,
            forKey: .receiver
        )
        iceServers = try container.decodeIfPresent(
            [VisionLinkIceServer].self,
            forKey: .iceServers
        ) ?? []
        relayPolicy = try container.decodeIfPresent(
            String.self,
            forKey: .relayPolicy
        ) ?? VisionLinkContract.p2pPreferred
    }

    private static func decodePairingCode(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> String? {
        if let value = try? container.decodeIfPresent(
            String.self,
            forKey: .pairingCode
        ) {
            return value
        }
        if let value = try? container.decodeIfPresent(
            Int.self,
            forKey: .pairingCode
        ) {
            return String(format: "%04d", value)
        }
        return nil
    }

    private static func decodeInteger(
        from container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) throws -> Int? {
        if let value = try? container.decodeIfPresent(
            Int.self,
            forKey: key
        ) {
            return value
        }
        if let value = try? container.decodeIfPresent(
            String.self,
            forKey: key
        ) {
            return Int(value)
        }
        return nil
    }
}

nonisolated struct VisionLinkReconnectResponse:
    Decodable,
    Equatable,
    Sendable
{
    let roomID: String?
    let pairID: String
    let receiver: VisionLinkDeviceEndpoint
    let peerName: String?
    let iceServers: [VisionLinkIceServer]
    let relayPolicy: String

    private struct Pair: Decodable {
        let pairID: String

        private enum CodingKeys: String, CodingKey {
            case pairID = "pairId"
        }
    }

    private struct Peer: Decodable {
        let name: String?
    }

    private enum CodingKeys: String, CodingKey {
        case roomID = "roomId"
        case pair
        case receiver
        case peer
        case iceServers
        case relayPolicy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        roomID = try container.decodeIfPresent(
            String.self,
            forKey: .roomID
        )
        pairID = try container.decode(
            Pair.self,
            forKey: .pair
        ).pairID
        receiver = try container.decode(
            VisionLinkDeviceEndpoint.self,
            forKey: .receiver
        )
        peerName = try container.decodeIfPresent(
            Peer.self,
            forKey: .peer
        )?.name
        iceServers = try container.decodeIfPresent(
            [VisionLinkIceServer].self,
            forKey: .iceServers
        ) ?? []
        relayPolicy = try container.decodeIfPresent(
            String.self,
            forKey: .relayPolicy
        ) ?? VisionLinkContract.p2pPreferred
    }
}

nonisolated struct VisionLinkSessionDescription:
    Equatable,
    Sendable
{
    let messageID: String?
    let type: String
    let sdp: String
}

nonisolated struct VisionLinkIceCandidate:
    Equatable,
    Sendable
{
    let messageID: String?
    let candidate: String?
    let sdpMid: String?
    let sdpMLineIndex: Int?
}

nonisolated enum VisionLinkSignalingEvent:
    Equatable,
    Sendable
{
    case connected(
        roomID: String?,
        role: String?,
        peerID: String?
    )
    case peerJoined(
        roomID: String?,
        peerRole: String?,
        peerID: String?,
        peerName: String?
    )
    case peerLeft(peerName: String?)
    case peerWaiting(waitingFor: String?)
    case pairCreated(pairID: String?, cameraName: String?)
    case pairDeleted(pairID: String?, deletedBy: String?)
    case offer(VisionLinkSessionDescription)
    case answer(VisionLinkSessionDescription)
    case iceCandidate(VisionLinkIceCandidate)
    case hangup(reason: String?)
    case serverError(code: String?, message: String?)
    case unknown(type: String?)

    var summary: String {
        switch self {
        case .connected:
            return AppLocalization.string(
                "신호 서버 연결됨"
            )
        case .peerJoined(_, _, _, let peerName):
            return AppLocalization.format(
                "%@ 연결됨",
                peerName ?? "VisionLink"
            )
        case .peerLeft:
            return AppLocalization.string(
                "상대 기기 연결 끊김"
            )
        case .peerWaiting:
            return AppLocalization.string(
                "상대 기기 대기 중"
            )
        case .pairCreated(_, let cameraName):
            return AppLocalization.format(
                "%@ 페어링 완료",
                cameraName ?? "VisionLink"
            )
        case .pairDeleted:
            return AppLocalization.string(
                "페어링 삭제됨"
            )
        case .offer:
            return AppLocalization.string(
                "영상 연결 제안 수신"
            )
        case .answer:
            return AppLocalization.string(
                "영상 연결 응답 수신"
            )
        case .iceCandidate:
            return AppLocalization.string(
                "네트워크 후보 수신"
            )
        case .hangup:
            return AppLocalization.string(
                "상대 기기 연결 종료"
            )
        case .serverError(let code, let message):
            return AppLocalization.format(
                "서버 오류 %@ %@",
                code ?? "",
                message ?? ""
            )
                .trimmingCharacters(in: .whitespaces)
        case .unknown(let type):
            return AppLocalization.format(
                "알 수 없는 메시지 %@",
                type ?? ""
            )
                .trimmingCharacters(in: .whitespaces)
        }
    }
}

nonisolated enum VisionLinkPairDeletionPolicy {
    static func shouldReset(
        currentPairID: String?,
        deletedPairID: String?
    ) -> Bool {
        guard let currentPairID,
              let deletedPairID else {
            return false
        }
        return currentPairID == deletedPairID
    }
}

nonisolated enum VisionLinkJSON {
    static func decodeSession(
        _ data: Data
    ) throws -> VisionLinkSessionResponse {
        try JSONDecoder().decode(
            VisionLinkSessionResponse.self,
            from: data
        )
    }

    static func decodeReconnect(
        _ data: Data
    ) throws -> VisionLinkReconnectResponse {
        try JSONDecoder().decode(
            VisionLinkReconnectResponse.self,
            from: data
        )
    }

    static func parseSignalingMessage(
        _ text: String
    ) throws -> VisionLinkSignalingEvent {
        guard let data = text.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(
                  with: data
              ) as? [String: Any] else {
            throw VisionLinkProtocolError.invalidMessage
        }

        let type = string("type", in: json)
        switch type {
        case "connected":
            return .connected(
                roomID: string("roomId", in: json),
                role: string("role", in: json),
                peerID: string("peerId", in: json)
            )
        case "peer-joined":
            return .peerJoined(
                roomID: string("roomId", in: json),
                peerRole: string("peerRole", in: json),
                peerID: string("peerId", in: json),
                peerName: string("peerName", in: json)
            )
        case "peer-left":
            return .peerLeft(
                peerName: string("peerName", in: json)
            )
        case "peer-waiting":
            return .peerWaiting(
                waitingFor: string("waitingFor", in: json)
            )
        case "pair-created":
            return .pairCreated(
                pairID: nestedString(
                    "pairId",
                    object: "pair",
                    in: json
                ),
                cameraName: nestedString(
                    "name",
                    object: "cameraDevice",
                    in: json
                )
            )
        case "pair-deleted":
            return .pairDeleted(
                pairID: string("pairId", in: json),
                deletedBy: string("deletedBy", in: json)
            )
        case "offer":
            return .offer(
                try description(from: json)
            )
        case "answer":
            return .answer(
                try description(from: json)
            )
        case "ice-candidate":
            return .iceCandidate(
                candidate(from: json)
            )
        case "hangup":
            return .hangup(
                reason: string("reason", in: json)
            )
        case "error":
            return .serverError(
                code: string("code", in: json),
                message: string("message", in: json)
            )
        default:
            return .unknown(type: type)
        }
    }

    static func answerMessage(
        sdp: String
    ) throws -> String {
        try encode([
            "type": "answer",
            "description": [
                "type": "answer",
                "sdp": sdp
            ]
        ])
    }

    static func iceCandidateMessage(
        _ candidate: VisionLinkIceCandidate?
    ) throws -> String {
        var json: [String: Any] = [
            "type": "ice-candidate"
        ]
        if let candidate,
           let rawCandidate = candidate.candidate {
            let sdpMid: Any = candidate.sdpMid ?? NSNull()
            json["candidate"] = [
                "candidate": rawCandidate,
                "sdpMid": sdpMid,
                "sdpMLineIndex":
                    candidate.sdpMLineIndex ?? 0
            ]
        } else {
            json["candidate"] = NSNull()
        }
        return try encode(json)
    }

    static func hangupMessage(
        reason: String = "user-requested"
    ) throws -> String {
        try encode([
            "type": "hangup",
            "reason": reason
        ])
    }

    private static func description(
        from json: [String: Any]
    ) throws -> VisionLinkSessionDescription {
        guard let description =
                json["description"] as? [String: Any],
              let type = string(
                  "type",
                  in: description
              ),
              let sdp = string(
                  "sdp",
                  in: description
              ) else {
            throw VisionLinkProtocolError.invalidDescription
        }
        return VisionLinkSessionDescription(
            messageID: string("messageId", in: json),
            type: type,
            sdp: sdp
        )
    }

    private static func candidate(
        from json: [String: Any]
    ) -> VisionLinkIceCandidate {
        guard let value = json["candidate"],
              !(value is NSNull),
              let candidate = value as? [String: Any] else {
            return VisionLinkIceCandidate(
                messageID: string("messageId", in: json),
                candidate: nil,
                sdpMid: nil,
                sdpMLineIndex: nil
            )
        }
        return VisionLinkIceCandidate(
            messageID: string("messageId", in: json),
            candidate: string("candidate", in: candidate),
            sdpMid: string("sdpMid", in: candidate),
            sdpMLineIndex: candidate[
                "sdpMLineIndex"
            ] as? Int
        )
    }

    private static func nestedString(
        _ key: String,
        object: String,
        in json: [String: Any]
    ) -> String? {
        guard let nested = json[object] as? [String: Any] else {
            return nil
        }
        return string(key, in: nested)
    }

    private static func string(
        _ key: String,
        in json: [String: Any]
    ) -> String? {
        guard let value = json[key],
              !(value is NSNull) else {
            return nil
        }
        if let value = value as? String {
            return value.isEmpty ? nil : value
        }
        if let value = value as? NSNumber {
            return value.stringValue
        }
        return nil
    }

    private static func encode(
        _ json: [String: Any]
    ) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: json,
            options: [.sortedKeys]
        )
        guard let value = String(
            data: data,
            encoding: .utf8
        ) else {
            throw VisionLinkProtocolError.invalidMessage
        }
        return value
    }
}

nonisolated enum VisionLinkProtocolError:
    Error,
    LocalizedError,
    Equatable
{
    case invalidMessage
    case invalidDescription
    case missingReceiverCredentials
    case invalidWebSocketURL

    var errorDescription: String? {
        switch self {
        case .invalidMessage:
            return AppLocalization.string(
                "VisionLink 메시지 형식이 올바르지 않습니다."
            )
        case .invalidDescription:
            return AppLocalization.string(
                "VisionLink 연결 협상 정보가 올바르지 않습니다."
            )
        case .missingReceiverCredentials:
            return AppLocalization.string(
                "수신기 자격정보가 응답에 없습니다."
            )
        case .invalidWebSocketURL:
            return AppLocalization.string(
                "VisionLink 신호 서버 주소가 올바르지 않습니다."
            )
        }
    }
}
