import XCTest

@testable import shortcuts_example

final class SharedEntryPlanTests:
    XCTestCase
{
    private let attachment =
        StoredChatFileAttachment(
            name: "shared-photo.jpg",
            kind: .image,
            mimeType: "image/jpeg",
            storedName: "stored-photo.jpg",
            extractedText: nil
        )

    func testVoiceModePreservesAttachmentAndStartsListening() {
        let plan =
            SharedAttachmentEntryPlan
            .make(
                attachment: attachment,
                mode: .voice
            )

        XCTAssertEqual(
            plan.attachment,
            attachment
        )
        XCTAssertTrue(
            plan
                .automaticallyStartsVoiceInput
        )
    }

    func testChatModeWaitsForTypedQuestion() {
        let plan =
            SharedAttachmentEntryPlan
            .make(
                attachment: attachment,
                mode: .chat
            )

        XCTAssertFalse(
            plan
                .automaticallyStartsVoiceInput
        )
    }

    func testSharedWebContextKeepsSourceAndBody() {
        let content = WebPageContent(
            requestedURL:
                URL(
                    string:
                        "https://example.com/start"
                )!,
            sourceURL:
                URL(
                    string:
                        "https://example.com/final"
                )!,
            title: "Example Title",
            text: "Page body",
            wasTruncated: false
        )

        let context =
            SharedWebContext.make(
                content: content
            )

        XCTAssertTrue(
            context.contains(
                "Example Title"
            )
        )
        XCTAssertTrue(
            context.contains(
                "https://example.com/final"
            )
        )
        XCTAssertTrue(
            context.contains(
                "Page body"
            )
        )
    }
}
