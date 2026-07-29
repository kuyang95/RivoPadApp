import CryptoKit
import Foundation
@testable import shortcuts_example
import XCTest

final class VisionLinkDataReceiverTests:
    XCTestCase
{
    func testStreamsFileAndCompletesAfterHashCheck()
        async throws
    {
        let fixture = makeFixture()
        defer { fixture.remove() }
        let payload = Data("abcdef".utf8)

        let startActions = await fixture.receiver
            .receive(
                .control(
                    controlData(
                        [
                            "type": "file-start",
                            "transferId": "transfer-1",
                            "name": "sample.txt",
                            "kind": "file",
                            "size": payload.count,
                        ]
                    )
                )
            )
        XCTAssertEqual(
            controlType(in: startActions),
            "file-accepted"
        )
        XCTAssertTrue(
            startActions.contains(
                .event(
                    .transferStarted(
                        VisionLinkTransferProgress(
                            transferID: "transfer-1",
                            kind: "file",
                            fileName: "sample.txt",
                            receivedBytes: 0,
                            totalBytes: 6
                        )
                    )
                )
            )
        )

        let firstChunk = await fixture.receiver
            .receive(.binary(payload.prefix(3)))
        XCTAssertTrue(
            firstChunk.contains(
                .event(
                    .transferProgress(
                        VisionLinkTransferProgress(
                            transferID: "transfer-1",
                            kind: "file",
                            fileName: "sample.txt",
                            receivedBytes: 3,
                            totalBytes: 6
                        )
                    )
                )
            )
        )
        _ = await fixture.receiver.receive(
            .binary(payload.suffix(3))
        )

        let finishActions = await fixture.receiver
            .receive(
                .control(
                    controlData(
                        [
                            "type": "file-end",
                            "transferId": "transfer-1",
                            "size": payload.count,
                            "sha256": sha256(payload),
                        ]
                    )
                )
            )
        XCTAssertEqual(
            controlType(in: finishActions),
            "file-complete"
        )
        let file = try XCTUnwrap(
            receivedFile(in: finishActions)
        )
        XCTAssertEqual(file.fileName, "sample.txt")
        XCTAssertEqual(file.size, 6)
        XCTAssertEqual(
            try Data(contentsOf: file.url),
            payload
        )
        XCTAssertEqual(
            try directoryContents(fixture.partial),
            []
        )
    }

    func testHashMismatchDeletesPartialFile()
        async throws
    {
        let fixture = makeFixture()
        defer { fixture.remove() }
        let payload = Data("hash me".utf8)
        _ = await start(
            fixture,
            transferID: "bad-hash",
            name: "sample.txt",
            size: payload.count
        )
        _ = await fixture.receiver.receive(
            .binary(payload)
        )

        let actions = await fixture.receiver.receive(
            .control(
                controlData(
                    [
                        "type": "file-end",
                        "transferId": "bad-hash",
                        "size": payload.count,
                        "sha256": String(
                            repeating: "0",
                            count: 64
                        ),
                    ]
                )
            )
        )

        XCTAssertEqual(
            controlType(in: actions),
            "file-error"
        )
        XCTAssertNil(receivedFile(in: actions))
        XCTAssertEqual(
            try directoryContents(fixture.partial),
            []
        )
        XCTAssertEqual(
            try directoryContents(fixture.destination),
            []
        )
    }

    func testChunkBeyondDeclaredSizeIsRejected()
        async throws
    {
        let fixture = makeFixture()
        defer { fixture.remove() }
        _ = await start(
            fixture,
            transferID: "too-large",
            name: "sample.txt",
            size: 2
        )

        let actions = await fixture.receiver.receive(
            .binary(Data("abc".utf8))
        )

        XCTAssertEqual(
            controlType(in: actions),
            "file-error"
        )
        XCTAssertEqual(
            try directoryContents(fixture.partial),
            []
        )
    }

    func testCancelDeletesPartialWithoutPeerError()
        async throws
    {
        let fixture = makeFixture()
        defer { fixture.remove() }
        _ = await start(
            fixture,
            transferID: "cancel-me",
            name: "sample.txt",
            size: 4
        )
        _ = await fixture.receiver.receive(
            .binary(Data("ab".utf8))
        )

        let actions = await fixture.receiver.receive(
            .control(
                controlData(
                    [
                        "type": "file-cancel",
                        "transferId": "cancel-me",
                    ]
                )
            )
        )

        XCTAssertNil(controlType(in: actions))
        XCTAssertTrue(
            actions.contains(
                .event(
                    .failed(
                        "파일 전송이 취소되었습니다."
                    )
                )
            )
        )
        XCTAssertEqual(
            try directoryContents(fixture.partial),
            []
        )
    }

    func testClipboardPingAndCameraStateControls()
        async
    {
        let fixture = makeFixture()
        defer { fixture.remove() }

        let clipboard = await fixture.receiver.receive(
            .control(
                controlData(
                    [
                        "type": "clipboard-text",
                        "transferId": "clipboard-1",
                        "text": "복사할 글",
                    ]
                )
            )
        )
        XCTAssertEqual(
            controlType(in: clipboard),
            "clipboard-complete"
        )
        XCTAssertTrue(
            clipboard.contains(
                .event(
                    .clipboardReceived("복사할 글")
                )
            )
        )

        let ping = await fixture.receiver.receive(
            .control(
                controlData(
                    [
                        "type": "data-ping",
                        "sentAt": "12345",
                    ]
                )
            )
        )
        XCTAssertEqual(
            controlType(in: ping),
            "data-pong"
        )
        XCTAssertEqual(
            controlObject(in: ping)?["sentAt"]
                as? String,
            "12345"
        )

        let camera = await fixture.receiver.receive(
            .control(
                controlData(
                    [
                        "type": "camera-share-state",
                        "active": true,
                    ]
                )
            )
        )
        XCTAssertEqual(
            camera,
            [.event(.cameraShareChanged(true))]
        )
    }

    func testOversizedClipboardIsRejected()
        async
    {
        let fixture = makeFixture()
        defer { fixture.remove() }
        let text = String(
            repeating: "a",
            count:
                VisionLinkDataReceiver
                .maximumClipboardSize + 1
        )

        let actions = await fixture.receiver.receive(
            .control(
                controlData(
                    [
                        "type": "clipboard-text",
                        "transferId": "clipboard-2",
                        "text": text,
                    ]
                )
            )
        )

        XCTAssertEqual(
            controlType(in: actions),
            "clipboard-error"
        )
        XCTAssertFalse(
            actions.contains {
                if case .event(
                    .clipboardReceived
                ) = $0 {
                    return true
                }
                return false
            }
        )
    }

    func testBlockedExtensionAndUnsafeName()
        async throws
    {
        let fixture = makeFixture()
        defer { fixture.remove() }

        let blocked = await start(
            fixture,
            transferID: "blocked",
            name: "payload.apk",
            size: 0
        )
        XCTAssertEqual(
            controlType(in: blocked),
            "file-error"
        )

        let startActions = await start(
            fixture,
            transferID: "safe-name",
            name: "bad/name?.txt",
            size: 0
        )
        XCTAssertEqual(
            controlType(in: startActions),
            "file-accepted"
        )
        let empty = Data()
        let finish = await fixture.receiver.receive(
            .control(
                controlData(
                    [
                        "type": "file-end",
                        "transferId": "safe-name",
                        "size": 0,
                        "sha256": sha256(empty),
                    ]
                )
            )
        )
        let file = try XCTUnwrap(
            receivedFile(in: finish)
        )
        XCTAssertEqual(
            file.fileName,
            "bad_name_.txt"
        )
    }

    func testInvalidImagePayloadIsDeleted()
        async throws
    {
        let fixture = makeFixture()
        defer { fixture.remove() }
        let payload = Data("not an image".utf8)
        _ = await start(
            fixture,
            transferID: "image-1",
            name: "photo.jpg",
            size: payload.count,
            kind: "image"
        )
        _ = await fixture.receiver.receive(
            .binary(payload)
        )

        let actions = await fixture.receiver.receive(
            .control(
                controlData(
                    [
                        "type": "file-end",
                        "transferId": "image-1",
                        "size": payload.count,
                        "sha256": sha256(payload),
                    ]
                )
            )
        )

        XCTAssertEqual(
            controlType(in: actions),
            "file-error"
        )
        XCTAssertEqual(
            try directoryContents(fixture.destination),
            []
        )
    }

    private func start(
        _ fixture: Fixture,
        transferID: String,
        name: String,
        size: Int,
        kind: String = "file"
    ) async -> [VisionLinkDataAction] {
        await fixture.receiver.receive(
            .control(
                controlData(
                    [
                        "type": "file-start",
                        "transferId": transferID,
                        "name": name,
                        "kind": kind,
                        "size": size,
                    ]
                )
            )
        )
    }

    private func makeFixture() -> Fixture {
        let root = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "VisionLinkDataTests-"
                    + UUID().uuidString,
                isDirectory: true
            )
        let destination = root
            .appendingPathComponent(
                "Destination",
                isDirectory: true
            )
        let partial = root
            .appendingPathComponent(
                "Partial",
                isDirectory: true
            )
        return Fixture(
            root: root,
            destination: destination,
            partial: partial,
            receiver: VisionLinkDataReceiver(
                destinationDirectory: destination,
                partialDirectory: partial
            )
        )
    }

    private func controlData(
        _ object: [String: Any]
    ) -> Data {
        try! JSONSerialization.data(
            withJSONObject: object
        )
    }

    private func controlObject(
        in actions: [VisionLinkDataAction]
    ) -> [String: Any]? {
        for action in actions {
            guard case .sendControl(let data) =
                    action else {
                continue
            }
            return try? JSONSerialization
                .jsonObject(with: data)
                as? [String: Any]
        }
        return nil
    }

    private func controlType(
        in actions: [VisionLinkDataAction]
    ) -> String? {
        controlObject(in: actions)?["type"]
            as? String
    }

    private func receivedFile(
        in actions: [VisionLinkDataAction]
    ) -> VisionLinkReceivedFile? {
        for action in actions {
            if case .event(
                .fileReceived(let file)
            ) = action {
                return file
            }
        }
        return nil
    }

    private func sha256(
        _ data: Data
    ) -> String {
        SHA256.hash(data: data)
            .map {
                String(format: "%02x", $0)
            }
            .joined()
    }

    private func directoryContents(
        _ directory: URL
    ) throws -> [URL] {
        guard FileManager.default.fileExists(
            atPath: directory.path
        ) else {
            return []
        }
        return try FileManager.default
            .contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
    }
}

private struct Fixture {
    let root: URL
    let destination: URL
    let partial: URL
    let receiver: VisionLinkDataReceiver

    func remove() {
        try? FileManager.default.removeItem(
            at: root
        )
    }
}
