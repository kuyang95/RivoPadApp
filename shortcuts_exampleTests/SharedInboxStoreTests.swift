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
        let later = Date()
        let earlier = later.addingTimeInterval(
            -100
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

    func testCleanupRemovesExpiredAndAbandonedItemsOnly()
        throws
    {
        let now = Date()
        let recent = try store.enqueueText(
            "최근 항목",
            createdAt:
                now.addingTimeInterval(
                    -60 * 60
                )
        )
        let expired = try store.enqueueText(
            "만료 항목",
            createdAt:
                now.addingTimeInterval(
                    -8 * 24 * 60 * 60
                )
        )
        let freshIncomplete =
            rootURL.appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        let staleIncomplete =
            rootURL.appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        let foreignDirectory =
            rootURL.appendingPathComponent(
                "foreign-data",
                isDirectory: true
            )
        for directory in [
            freshIncomplete,
            staleIncomplete,
            foreignDirectory,
        ] {
            try FileManager.default
                .createDirectory(
                    at: directory,
                    withIntermediateDirectories:
                        true
                )
        }
        let staleDate =
            now.addingTimeInterval(
                -2 * 24 * 60 * 60
            )
        try FileManager.default
            .setAttributes(
                [
                    .modificationDate:
                        staleDate,
                ],
                ofItemAtPath:
                    staleIncomplete.path
            )
        try FileManager.default
            .setAttributes(
                [
                    .modificationDate:
                        staleDate,
                ],
                ofItemAtPath:
                    foreignDirectory.path
            )

        let result = try store.cleanup(
            now: now
        )

        XCTAssertEqual(
            result,
            SharedInboxCleanupResult(
                removedExpiredItems: 1,
                removedAbandonedItems: 1,
                failedRemovals: 0
            )
        )
        XCTAssertEqual(
            try store.pendingItems()
                .map(\.id),
            [recent.id]
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath:
                    rootURL
                    .appendingPathComponent(
                        expired.id.uuidString
                    ).path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath:
                    freshIncomplete.path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath:
                    foreignDirectory.path
            )
        )
    }
}
