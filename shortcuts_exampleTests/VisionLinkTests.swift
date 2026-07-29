import Foundation
import XCTest

@testable import shortcuts_example

final class VisionLinkModelTests: XCTestCase {
    func testSessionResponseMatchesAndroidContract() throws {
        let data = Data(
            """
            {
              "roomId": "room-1",
              "pairingCode": "0042",
              "pairingUri": "visionlink://pair/0042",
              "ttlSeconds": "120",
              "expiresAt": "2026-07-29T06:00:00Z",
              "pair": {"pairId": "pair-1"},
              "receiver": {
                "deviceId": "receiver-1",
                "deviceToken": "device-secret",
                "sessionToken": "session-secret",
                "websocketUrl": "wss://example.test/socket"
              },
              "iceServers": [
                {"urls": "stun:stun.example.test"},
                {
                  "urls": [
                    "turn:one.example.test",
                    "turn:two.example.test"
                  ],
                  "username": "rivo",
                  "credential": "secret"
                }
              ],
              "relayPolicy": "p2p-preferred"
            }
            """.utf8
        )

        let response = try VisionLinkJSON.decodeSession(data)

        XCTAssertEqual(response.roomID, "room-1")
        XCTAssertEqual(response.pairingCode, "0042")
        XCTAssertEqual(response.ttlSeconds, 120)
        XCTAssertEqual(response.pairID, "pair-1")
        XCTAssertEqual(
            response.receiver.deviceID,
            "receiver-1"
        )
        XCTAssertEqual(
            response.receiver.websocketURL,
            "wss://example.test/socket"
        )
        XCTAssertEqual(response.iceServers.count, 2)
        XCTAssertEqual(
            response.iceServers[0].urls,
            ["stun:stun.example.test"]
        )
        XCTAssertEqual(
            response.iceServers[1].urls,
            [
                "turn:one.example.test",
                "turn:two.example.test"
            ]
        )
    }

    func testNumericPairingCodeIsPadded() throws {
        let data = Data(
            """
            {
              "pairingCode": 7,
              "pair": {"pairId": "pair-7"},
              "receiver": {
                "deviceId": "receiver-7",
                "deviceToken": "token-7",
                "websocketUrl": "wss://example.test/socket"
              }
            }
            """.utf8
        )

        let response = try VisionLinkJSON.decodeSession(data)

        XCTAssertEqual(response.pairingCode, "0007")
        XCTAssertEqual(
            response.relayPolicy,
            VisionLinkContract.p2pPreferred
        )
    }

    func testReconnectResponseMatchesAndroidContract() throws {
        let data = Data(
            """
            {
              "roomId": "room-saved",
              "pair": {"pairId": "pair-saved"},
              "receiver": {
                "deviceId": "receiver-saved",
                "sessionToken": "new-session",
                "websocketUrl": "wss://example.test/reconnect"
              },
              "peer": {"name": "Rivo Camera"},
              "iceServers": [],
              "relayPolicy": "relay-forbidden"
            }
            """.utf8
        )

        let response = try VisionLinkJSON.decodeReconnect(data)

        XCTAssertEqual(response.pairID, "pair-saved")
        XCTAssertEqual(response.peerName, "Rivo Camera")
        XCTAssertEqual(
            response.relayPolicy,
            "relay-forbidden"
        )
    }

    func testStoredCredentialsRoundTrip() throws {
        let source = VisionLinkStoredCredentials(
            pairID: "pair",
            deviceID: "device",
            deviceToken: "token",
            isConfirmed: true
        )

        let data = try JSONEncoder().encode(source)
        let restored = try JSONDecoder().decode(
            VisionLinkStoredCredentials.self,
            from: data
        )

        XCTAssertEqual(restored, source)
    }
}

final class VisionLinkSignalingTests: XCTestCase {
    func testParsesConnectionAndPairingEvents() throws {
        XCTAssertEqual(
            try parse(
                """
                {
                  "type": "connected",
                  "roomId": "room",
                  "role": "receiver",
                  "peerId": "receiver-1"
                }
                """
            ),
            .connected(
                roomID: "room",
                role: "receiver",
                peerID: "receiver-1"
            )
        )
        XCTAssertEqual(
            try parse(
                """
                {
                  "type": "peer-joined",
                  "roomId": "room",
                  "peerRole": "camera",
                  "peerId": "camera-1",
                  "peerName": "Rivo Camera"
                }
                """
            ),
            .peerJoined(
                roomID: "room",
                peerRole: "camera",
                peerID: "camera-1",
                peerName: "Rivo Camera"
            )
        )
        XCTAssertEqual(
            try parse(
                """
                {
                  "type": "pair-created",
                  "pair": {"pairId": "pair-1"},
                  "cameraDevice": {"name": "Camera"}
                }
                """
            ),
            .pairCreated(
                pairID: "pair-1",
                cameraName: "Camera"
            )
        )
    }

    func testParsesOfferAndIceCandidates() throws {
        XCTAssertEqual(
            try parse(
                """
                {
                  "type": "offer",
                  "messageId": "message-1",
                  "description": {
                    "type": "offer",
                    "sdp": "v=0"
                  }
                }
                """
            ),
            .offer(
                VisionLinkSessionDescription(
                    messageID: "message-1",
                    type: "offer",
                    sdp: "v=0"
                )
            )
        )
        XCTAssertEqual(
            try parse(
                """
                {
                  "type": "ice-candidate",
                  "messageId": "message-2",
                  "candidate": {
                    "candidate": "candidate:1",
                    "sdpMid": "0",
                    "sdpMLineIndex": 0
                  }
                }
                """
            ),
            .iceCandidate(
                VisionLinkIceCandidate(
                    messageID: "message-2",
                    candidate: "candidate:1",
                    sdpMid: "0",
                    sdpMLineIndex: 0
                )
            )
        )
        XCTAssertEqual(
            try parse(
                """
                {
                  "type": "ice-candidate",
                  "candidate": null
                }
                """
            ),
            .iceCandidate(
                VisionLinkIceCandidate(
                    messageID: nil,
                    candidate: nil,
                    sdpMid: nil,
                    sdpMLineIndex: nil
                )
            )
        )
    }

    func testParsesDisconnectAndServerEvents() throws {
        XCTAssertEqual(
            try parse(
                """
                {"type":"peer-waiting","waitingFor":"camera"}
                """
            ),
            .peerWaiting(waitingFor: "camera")
        )
        XCTAssertEqual(
            try parse(
                """
                {"type":"hangup","reason":"user-requested"}
                """
            ),
            .hangup(reason: "user-requested")
        )
        XCTAssertEqual(
            try parse(
                """
                {
                  "type":"error",
                  "code":"expired",
                  "message":"Pair expired"
                }
                """
            ),
            .serverError(
                code: "expired",
                message: "Pair expired"
            )
        )
        XCTAssertEqual(
            try parse(
                """
                {"type":"future-event","value":1}
                """
            ),
            .unknown(type: "future-event")
        )
    }

    func testRejectsMalformedOffer() {
        XCTAssertThrowsError(
            try parse(
                """
                {"type":"offer","description":{"type":"offer"}}
                """
            )
        )
    }

    func testEncodesAnswerMessage() throws {
        let text = try VisionLinkJSON.answerMessage(
            sdp: "v=0\r\na=recvonly"
        )
        let json = try jsonObject(text)
        let description = try XCTUnwrap(
            json["description"] as? [String: Any]
        )

        XCTAssertEqual(json["type"] as? String, "answer")
        XCTAssertEqual(
            description["type"] as? String,
            "answer"
        )
        XCTAssertEqual(
            description["sdp"] as? String,
            "v=0\r\na=recvonly"
        )
    }

    func testEncodesLocalIceCandidate() throws {
        let text = try VisionLinkJSON.iceCandidateMessage(
            VisionLinkIceCandidate(
                messageID: nil,
                candidate: "candidate:1",
                sdpMid: "video",
                sdpMLineIndex: 2
            )
        )
        let json = try jsonObject(text)
        let candidate = try XCTUnwrap(
            json["candidate"] as? [String: Any]
        )

        XCTAssertEqual(
            json["type"] as? String,
            "ice-candidate"
        )
        XCTAssertEqual(
            candidate["candidate"] as? String,
            "candidate:1"
        )
        XCTAssertEqual(
            candidate["sdpMid"] as? String,
            "video"
        )
        XCTAssertEqual(
            candidate["sdpMLineIndex"] as? Int,
            2
        )
    }

    func testEncodesEndOfIceCandidates() throws {
        let text = try VisionLinkJSON
            .iceCandidateMessage(nil)
        let json = try jsonObject(text)

        XCTAssertEqual(
            json["type"] as? String,
            "ice-candidate"
        )
        XCTAssertTrue(json["candidate"] is NSNull)
    }

    private func parse(
        _ text: String
    ) throws -> VisionLinkSignalingEvent {
        try VisionLinkJSON.parseSignalingMessage(text)
    }

    private func jsonObject(
        _ text: String
    ) throws -> [String: Any] {
        let data = try XCTUnwrap(
            text.data(using: .utf8)
        )
        return try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: data
            ) as? [String: Any]
        )
    }
}
