import Foundation
import XCTest

@testable import shortcuts_example

final class SharedInboxStoreTests: XCTestCase {
    private var rootURL: URL!
    private var store: SharedInboxStore!

    override func setUpWithError() throws {
        rootURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        store = SharedInboxStore(
            rootURL: rootURL
        )
    }

    override func tearDownWithError() throws {
        if let rootURL {
            try? FileManager.default
                .removeItem(at: rootURL)
        }
        store = nil
        rootURL = nil
    }

    func testTextAndImageItemsCommitInCreationOrder()
        throws
    {
        let later = Date(
            timeIntervalSince1970: 200
        )
        let earlier = Date(
            timeIntervalSince1970: 100
        )
        let text = try store.enqueueText(
            "  선택한 문장  ",
            createdAt: later
        )
        let image = try store.enqueuePayload(
            Data([0x89, 0x50, 0x4E, 0x47]),
            kind: .image,
            originalFilename: "../sample.png",
            typeIdentifier: "public.png",
            createdAt: earlier
        )

        let pending = try store.pendingItems()

        XCTAssertEqual(
            pending.map(\.id),
            [image.id, text.id]
        )
        XCTAssertEqual(text.text, "선택한 문장")
        XCTAssertEqual(
            image.payloadFilename,
            "sample.png"
        )
        XCTAssertEqual(
            try Data(
                contentsOf:
                    store.payloadURL(for: image)
            ),
            Data([0x89, 0x50, 0x4E, 0x47])
        )
    }

    func testRemovingItemDeletesOnlyItsDirectory()
        throws
    {
        let first = try store.enqueueText("첫 항목")
        let second = try store.enqueueText("둘째 항목")

        try store.remove(first)

        XCTAssertEqual(
            try store.pendingItems()
                .map(\.id),
            [second.id]
        )
    }

    func testRejectsEmptyTextAndOversizedMetadata()
        throws
    {
        XCTAssertThrowsError(
            try store.enqueueText(" \n ")
        )

        let invalidDirectory = rootURL
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        try FileManager.default
            .createDirectory(
                at: invalidDirectory,
                withIntermediateDirectories: true
            )
        try Data("{}".utf8).write(
            to: invalidDirectory
                .appendingPathComponent(
                    SharedInboxStore
                        .manifestFilename
                )
        )

        XCTAssertTrue(
            try store.pendingItems().isEmpty
        )
    }

    func testIgnoresCommittedFileWhosePayloadDisappeared()
        throws
    {
        let item = try store.enqueuePayload(
            Data([0x25, 0x50, 0x44, 0x46]),
            kind: .file,
            originalFilename: "sample.pdf",
            typeIdentifier: "com.adobe.pdf"
        )
        try FileManager.default.removeItem(
            at: try store.payloadURL(for: item)
        )

        XCTAssertTrue(
            try store.pendingItems().isEmpty
        )
    }
}
