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

    func testOpenedChannelCleansOnlyOrphanedTemporaryFiles()
        async throws
    {
        let fixture = makeFixture()
        defer { fixture.remove() }
        let featureDirectory =
            fixture.partial
            .appendingPathComponent(
                "Features",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: featureDirectory,
            withIntermediateDirectories: true
        )
        let orphan = fixture.partial
            .appendingPathComponent(
                "orphan.visionlink-part"
            )
        let unrelated = fixture.partial
            .appendingPathComponent("keep.tmp")
        let expiredFeature = featureDirectory
            .appendingPathComponent("expired.png")
        let currentFeature = featureDirectory
            .appendingPathComponent("current.png")
        try Data("partial".utf8).write(to: orphan)
        try Data("keep".utf8).write(to: unrelated)
        try Data("old".utf8).write(
            to: expiredFeature
        )
        try Data("new".utf8).write(
            to: currentFeature
        )
        try FileManager.default.setAttributes(
            [
                .modificationDate:
                    Date().addingTimeInterval(
                        -2 * 24 * 60 * 60
                    )
            ],
            ofItemAtPath: expiredFeature.path
        )

        let actions = await fixture.receiver
            .receive(.opened)

        XCTAssertEqual(actions, [])
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: orphan.path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: unrelated.path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: expiredFeature.path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: currentFeature.path
            )
        )
    }

    func testInsufficientStorageRejectsBeforePartialFileCreation()
        async throws
    {
        let fixture = makeFixture(
            availableCapacity: 1_000,
            minimumFreeSpaceReserve: 400
        )
        defer { fixture.remove() }

        let actions = await start(
            fixture,
            transferID: "no-space",
            name: "large.txt",
            size: 601
        )

        XCTAssertEqual(
            controlType(in: actions),
            "file-error"
        )
        XCTAssertTrue(
            actions.contains(
                .event(
                    .failed(
                        "파일 저장 준비에 실패했습니다: 파일을 받을 저장 공간이 부족합니다."
                    )
                )
            )
        )
        XCTAssertEqual(
            try directoryContents(fixture.partial),
            []
        )
        XCTAssertEqual(
            try directoryContents(
                fixture.destination
            ),
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

    func testFeatureImageCompletesIntoTemporaryRequest()
        async throws
    {
        let fixture = makeFixture()
        defer { fixture.remove() }
        let payload = pngPayload()

        let startActions = await fixture.receiver
            .receive(
                .control(
                    controlData(
                        [
                            "type": "file-start",
                            "transferId": "feature-file-1",
                            "requestId": "request-1",
                            "purpose":
                                "visioncraft-feature",
                            "feature": "ocr",
                            "name": "page.png",
                            "kind": "image",
                            "mimeType": "image/png",
                            "size": payload.count,
                        ]
                    )
                )
            )
        XCTAssertEqual(
            controlType(in: startActions),
            "file-accepted"
        )
        _ = await fixture.receiver.receive(
            .binary(payload)
        )

        let finishActions = await fixture.receiver
            .receive(
                .control(
                    controlData(
                        [
                            "type": "file-end",
                            "transferId": "feature-file-1",
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
        let request = try XCTUnwrap(
            remoteFeatureRequest(
                in: finishActions
            )
        )
        guard case .image(let imageRequest) =
                request else {
            return XCTFail("이미지 기능 요청이어야 합니다.")
        }
        XCTAssertEqual(
            imageRequest.requestID,
            "request-1"
        )
        XCTAssertEqual(
            imageRequest.feature,
            .ocr
        )
        XCTAssertEqual(
            try Data(
                contentsOf: imageRequest.fileURL
            ),
            payload
        )
        XCTAssertTrue(
            imageRequest.fileURL.path
                .contains("/Partial/Features/")
        )
        XCTAssertEqual(
            try directoryContents(fixture.destination),
            []
        )
        XCTAssertNil(receivedFile(in: finishActions))
    }

    func testInvalidFeatureImageMetadataIsRejected()
        async
    {
        let fixture = makeFixture()
        defer { fixture.remove() }

        let invalidKind = await fixture.receiver
            .receive(
                .control(
                    controlData(
                        [
                            "type": "file-start",
                            "transferId": "bad-kind",
                            "requestId": "request-1",
                            "purpose":
                                "visioncraft-feature",
                            "feature": "ocr",
                            "name": "page.png",
                            "kind": "file",
                            "size": 12,
                        ]
                    )
                )
            )
        XCTAssertEqual(
            controlType(in: invalidKind),
            "file-error"
        )

        let empty = await fixture.receiver.receive(
            .control(
                controlData(
                    [
                        "type": "file-start",
                        "transferId": "empty-feature",
                        "requestId": "request-1",
                        "purpose":
                            "visioncraft-feature",
                        "feature": "ocr",
                        "name": "page.png",
                        "kind": "image",
                        "size": 0,
                    ]
                )
            )
        )
        XCTAssertEqual(
            controlType(in: empty),
            "file-error"
        )

        let unsupported = await fixture.receiver
            .receive(
                .control(
                    controlData(
                        [
                            "type": "file-start",
                            "transferId": "bad-feature",
                            "requestId": "request-1",
                            "purpose":
                                "visioncraft-feature",
                            "feature": "unknown",
                            "name": "page.png",
                            "kind": "image",
                            "size": 12,
                        ]
                    )
                )
            )
        XCTAssertEqual(
            controlType(in: unsupported),
            "file-error"
        )

        let longID = await fixture.receiver.receive(
            .control(
                controlData(
                    [
                        "type": "file-start",
                        "transferId": "long-id",
                        "requestId": String(
                            repeating: "a",
                            count: 81
                        ),
                        "purpose":
                            "visioncraft-feature",
                        "feature": "ocr",
                        "name": "page.png",
                        "kind": "image",
                        "size": 12,
                    ]
                )
            )
        )
        XCTAssertEqual(
            controlType(in: longID),
            "file-error"
        )
    }

    func testTranslationTextRequestValidation()
        async
    {
        let fixture = makeFixture()
        defer { fixture.remove() }

        let valid = await fixture.receiver.receive(
            .control(
                controlData(
                    [
                        "type": "feature-request",
                        "requestId": "translate-1",
                        "feature": "translation",
                        "payload": [
                            "text": "Hello",
                        ],
                    ]
                )
            )
        )
        XCTAssertEqual(
            remoteFeatureRequest(in: valid),
            .translationText(
                VisionLinkTextTranslationRequest(
                    requestID: "translate-1",
                    text: "Hello"
                )
            )
        )

        let empty = await fixture.receiver.receive(
            .control(
                controlData(
                    [
                        "type": "feature-request",
                        "requestId": "translate-2",
                        "feature": "translation",
                        "payload": [
                            "text": "   ",
                        ],
                    ]
                )
            )
        )
        XCTAssertEqual(
            controlType(in: empty),
            "feature-error"
        )

        let oversized = await fixture.receiver
            .receive(
                .control(
                    controlData(
                        [
                            "type": "feature-request",
                            "requestId": "translate-3",
                            "feature": "translation",
                            "payload": [
                                "text": String(
                                    repeating: "a",
                                    count:
                                        VisionLinkDataReceiver
                                        .maximumTranslationTextSize
                                        + 1
                                ),
                            ],
                        ]
                    )
                )
            )
        XCTAssertEqual(
            controlType(in: oversized),
            "feature-error"
        )
        XCTAssertNil(
            remoteFeatureRequest(in: oversized)
        )
    }

    func testAIChatRequestValidation()
        async
    {
        let fixture = makeFixture()
        defer { fixture.remove() }

        let valid = await fixture.receiver.receive(
            .control(
                controlData(
                    [
                        "type": "feature-request",
                        "requestId": "chat-1",
                        "conversationId":
                            "conversation-1",
                        "feature": "ai-chat",
                        "payload": [
                            "messages": [
                                [
                                    "role": "user",
                                    "content": "첫 질문",
                                ],
                                [
                                    "role": "assistant",
                                    "content": "첫 답변",
                                ],
                                [
                                    "role": "user",
                                    "content": "다음 질문",
                                ],
                            ],
                        ],
                    ]
                )
            )
        )
        XCTAssertEqual(
            remoteChatRequest(in: valid),
            VisionLinkChatRequest(
                requestID: "chat-1",
                conversationID: "conversation-1",
                messages: [
                    VisionLinkChatMessage(
                        role: .user,
                        content: "첫 질문"
                    ),
                    VisionLinkChatMessage(
                        role: .assistant,
                        content: "첫 답변"
                    ),
                    VisionLinkChatMessage(
                        role: .user,
                        content: "다음 질문"
                    ),
                ]
            )
        )

        let assistantLast = await fixture.receiver
            .receive(
                .control(
                    controlData(
                        [
                            "type": "feature-request",
                            "requestId": "chat-2",
                            "conversationId":
                                "conversation-1",
                            "feature": "ai-chat",
                            "payload": [
                                "messages": [
                                    [
                                        "role":
                                            "assistant",
                                        "content": "잘못된 끝",
                                    ],
                                ],
                            ],
                        ]
                    )
                )
            )
        XCTAssertEqual(
            controlType(in: assistantLast),
            "feature-error"
        )
        XCTAssertEqual(
            controlObject(
                in: assistantLast
            )?["feature"] as? String,
            "ai-chat"
        )

        let tooMany = Array(
            repeating: [
                "role": "user",
                "content": "질문",
            ],
            count:
                VisionLinkDataReceiver
                .maximumChatMessages + 1
        )
        let oversizedTurns = await fixture.receiver
            .receive(
                .control(
                    controlData(
                        [
                            "type": "feature-request",
                            "requestId": "chat-3",
                            "conversationId":
                                "conversation-1",
                            "feature": "ai-chat",
                            "payload": [
                                "messages": tooMany,
                            ],
                        ]
                    )
                )
            )
        XCTAssertEqual(
            controlType(in: oversizedTurns),
            "feature-error"
        )
        XCTAssertNil(
            remoteChatRequest(in: oversizedTurns)
        )
    }

    func testChatContextAttachmentValidation()
        async
    {
        let fixture = makeFixture()
        defer { fixture.remove() }

        let valid = await fixture.receiver.receive(
            .control(
                controlData(
                    [
                        "type":
                            "chat-context-attachment",
                        "attachmentId":
                            "attachment-1",
                        "conversationId":
                            "conversation-1",
                        "name": "  메모  ",
                        "text": "참고 문맥",
                    ]
                )
            )
        )
        XCTAssertEqual(
            remoteChatContext(in: valid),
            VisionLinkChatContextAttachment(
                attachmentID: "attachment-1",
                conversationID: "conversation-1",
                name: "메모",
                text: "참고 문맥"
            )
        )

        let oversized = await fixture.receiver
            .receive(
                .control(
                    controlData(
                        [
                            "type":
                                "chat-context-attachment",
                            "attachmentId":
                                "attachment-2",
                            "conversationId":
                                "conversation-1",
                            "text": String(
                                repeating: "a",
                                count:
                                    VisionLinkDataReceiver
                                    .maximumChatContextSize
                                    + 1
                            ),
                        ]
                    )
                )
            )
        XCTAssertEqual(
            controlType(in: oversized),
            "chat-attachment-error"
        )
        XCTAssertNil(
            remoteChatContext(in: oversized)
        )
    }

    func testChatImageAttachmentCompletesToTemporaryEvent()
        async throws
    {
        let fixture = makeFixture()
        defer { fixture.remove() }
        let payload = pngPayload()
        let startActions = await fixture.receiver
            .receive(
                .control(
                    controlData(
                        [
                            "type": "file-start",
                            "transferId":
                                "attachment-3",
                            "attachmentId":
                                "attachment-3",
                            "conversationId":
                                "conversation-1",
                            "purpose":
                                "visioncraft-chat-attachment",
                            "attachmentKind":
                                "image",
                            "name": "photo.png",
                            "kind": "image",
                            "mimeType":
                                "image/png",
                            "size": payload.count,
                        ]
                    )
                )
            )
        XCTAssertEqual(
            controlType(in: startActions),
            "file-accepted"
        )
        _ = await fixture.receiver.receive(
            .binary(payload)
        )
        let finishActions = await fixture.receiver
            .receive(
                .control(
                    controlData(
                        [
                            "type": "file-end",
                            "transferId":
                                "attachment-3",
                            "size": payload.count,
                            "sha256":
                                sha256(payload),
                        ]
                    )
                )
            )
        XCTAssertEqual(
            controlType(in: finishActions),
            "file-complete"
        )
        let attachment = try XCTUnwrap(
            remoteChatFile(in: finishActions)
        )
        XCTAssertEqual(
            attachment.attachmentID,
            "attachment-3"
        )
        XCTAssertEqual(
            attachment.conversationID,
            "conversation-1"
        )
        XCTAssertEqual(attachment.kind, .image)
        XCTAssertEqual(
            try Data(contentsOf: attachment.fileURL),
            payload
        )
        XCTAssertTrue(
            attachment.fileURL.path
                .contains("/Partial/Features/")
        )
        XCTAssertNil(
            receivedFile(in: finishActions)
        )
    }

    func testStructuredChatAttachmentsAreAccepted()
        async
    {
        let fixture = makeFixture()
        defer { fixture.remove() }
        let documents = [
            (
                name: "table.xlsx",
                mimeType:
                    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            ),
            (
                name: "legacy.xls",
                mimeType:
                    "application/vnd.ms-excel"
            ),
            (
                name: "document.hwp",
                mimeType:
                    "application/x-hwp"
            ),
            (
                name: "document.hwpx",
                mimeType:
                    "application/hwp+zip"
            ),
        ]

        for (index, document) in
                documents.enumerated() {
            let attachmentID =
                "structured-\(index)"
            let actions = await fixture
                .receiver.receive(
                    .control(
                        controlData(
                            [
                                "type":
                                    "file-start",
                                "transferId":
                                    attachmentID,
                                "attachmentId":
                                    attachmentID,
                                "conversationId":
                                    "conversation-1",
                                "purpose":
                                    "visioncraft-chat-attachment",
                                "attachmentKind":
                                    "document",
                                "name":
                                    document.name,
                                "kind": "file",
                                "mimeType":
                                    document
                                    .mimeType,
                                "size": 100,
                            ]
                        )
                    )
                )
            XCTAssertEqual(
                controlType(in: actions),
                "file-accepted"
            )
        }
        _ = await fixture.receiver.receive(
            .closed
        )
    }

    func testInvalidChatAttachmentMetadataIsRejected()
        async
    {
        let fixture = makeFixture()
        defer { fixture.remove() }

        let mismatchedID = await fixture.receiver
            .receive(
                .control(
                    controlData(
                        [
                            "type": "file-start",
                            "transferId":
                                "transfer-1",
                            "attachmentId":
                                "attachment-1",
                            "conversationId":
                                "conversation-1",
                            "purpose":
                                "visioncraft-chat-attachment",
                            "attachmentKind":
                                "document",
                            "name": "document.pdf",
                            "kind": "file",
                            "mimeType":
                                "application/pdf",
                            "size": 100,
                        ]
                    )
                )
            )
        XCTAssertEqual(
            controlType(in: mismatchedID),
            "file-error"
        )

        let oversizedPDF = await fixture.receiver
            .receive(
                .control(
                    controlData(
                        [
                            "type": "file-start",
                            "transferId":
                                "attachment-2",
                            "attachmentId":
                                "attachment-2",
                            "conversationId":
                                "conversation-1",
                            "purpose":
                                "visioncraft-chat-attachment",
                            "attachmentKind":
                                "document",
                            "name": "document.pdf",
                            "kind": "file",
                            "mimeType":
                                "application/pdf",
                            "size":
                                VisionLinkDataReceiver
                                .maximumChatPDFSize
                                + 1,
                        ]
                    )
                )
            )
        XCTAssertEqual(
            controlType(in: oversizedPDF),
            "file-error"
        )
    }

    func testFeatureControlEncodesLimits()
    {
        let progress = controlObject(
            in: [
                .sendControl(
                    VisionLinkFeatureControl.progress(
                        requestID: "request-1",
                        feature: .imageAnalysis,
                        stage: "analyzing"
                    )
                ),
            ]
        )
        XCTAssertEqual(
            progress?["type"] as? String,
            "feature-progress"
        )
        XCTAssertEqual(
            progress?["feature"] as? String,
            "image-analysis"
        )

        let oversized = controlObject(
            in: [
                .sendControl(
                    VisionLinkFeatureControl.result(
                        requestID: "request-2",
                        feature: .ocr,
                        text: String(
                            repeating: "a",
                            count:
                                VisionLinkFeatureControl
                                .maximumResultSize + 1
                        )
                    )
                ),
            ]
        )
        XCTAssertEqual(
            oversized?["type"] as? String,
            "feature-error"
        )

        let longMessage = String(
            repeating: "가",
            count: 700
        )
        let error = controlObject(
            in: [
                .sendControl(
                    VisionLinkFeatureControl.error(
                        requestID: "request-3",
                        feature: .translation,
                        message: longMessage
                    )
                ),
            ]
        )
        XCTAssertEqual(
            (error?["message"] as? String)?.count,
            500
        )

        let ready = controlObject(
            in: [
                .sendControl(
                    VisionLinkChatControl
                        .attachmentReady(
                            attachmentID:
                                "attachment-1",
                            conversationID:
                                "conversation-1",
                            name: "메모"
                        )
                ),
            ]
        )
        XCTAssertEqual(
            ready?["type"] as? String,
            "chat-attachment-ready"
        )

        let chatError = controlObject(
            in: [
                .sendControl(
                    VisionLinkChatControl
                        .attachmentError(
                            attachmentID:
                                "attachment-1",
                            conversationID:
                                "conversation-1",
                            message: longMessage
                        )
                ),
            ]
        )
        XCTAssertEqual(
            (
                chatError?["message"] as? String
            )?.count,
            500
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

    private func makeFixture(
        availableCapacity: Int64? = nil,
        minimumFreeSpaceReserve: Int64 =
            VisionLinkDataReceiver
            .minimumFreeSpaceReserve
    ) -> Fixture {
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
        let receiver: VisionLinkDataReceiver
        if let availableCapacity {
            receiver = VisionLinkDataReceiver(
                destinationDirectory: destination,
                partialDirectory: partial,
                minimumFreeSpaceReserve:
                    minimumFreeSpaceReserve,
                availableCapacityProvider: {
                    _ in availableCapacity
                }
            )
        } else {
            receiver = VisionLinkDataReceiver(
                destinationDirectory: destination,
                partialDirectory: partial
            )
        }
        return Fixture(
            root: root,
            destination: destination,
            partial: partial,
            receiver: receiver
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

    private func remoteFeatureRequest(
        in actions: [VisionLinkDataAction]
    ) -> VisionLinkRemoteFeatureRequest? {
        for action in actions {
            if case .event(
                .remoteFeatureRequested(let request)
            ) = action {
                return request
            }
        }
        return nil
    }

    private func remoteChatRequest(
        in actions: [VisionLinkDataAction]
    ) -> VisionLinkChatRequest? {
        for action in actions {
            if case .event(
                .remoteChatRequested(let request)
            ) = action {
                return request
            }
        }
        return nil
    }

    private func remoteChatContext(
        in actions: [VisionLinkDataAction]
    ) -> VisionLinkChatContextAttachment? {
        for action in actions {
            if case .event(
                .remoteChatContextReceived(
                    let attachment
                )
            ) = action {
                return attachment
            }
        }
        return nil
    }

    private func remoteChatFile(
        in actions: [VisionLinkDataAction]
    ) -> VisionLinkChatFileAttachment? {
        for action in actions {
            if case .event(
                .remoteChatAttachmentReceived(
                    let attachment
                )
            ) = action {
                return attachment
            }
        }
        return nil
    }

    private func pngPayload() -> Data {
        Data(
            base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB"
                + "CAQAAAC1HAwCAAAAC0lEQVR42mNk"
                + "YAAAAAYAAjCB0C8AAAAASUVORK5CYII="
        )!
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
