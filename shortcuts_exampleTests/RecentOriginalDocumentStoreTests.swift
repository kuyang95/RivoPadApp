import Foundation
import XCTest

@testable import shortcuts_example

final class RecentOriginalDocumentStoreTests:
    XCTestCase
{
    func testRegisteredOriginalCanBeReopenedAndUpdatedInPlace()
        async throws
    {
        let suiteName =
            "RecentOriginalDocumentTests-"
            + UUID().uuidString
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: suiteName)
        )
        defer {
            defaults.removePersistentDomain(
                forName: suiteName
            )
        }

        let fixtureDirectory = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "RecentOriginalDocumentFixture-"
                    + UUID().uuidString,
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: fixtureDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(
                at: fixtureDirectory
            )
        }

        let originalURL = fixtureDirectory
            .appendingPathComponent("명단.xlsx")
        let originalData = Data("original".utf8)
        try originalData.write(to: originalURL)

        let store = RecentOriginalDocumentStore(
            defaults: defaults,
            storageKey: "recent-originals"
        )
        let registered = try await store.register(
            fileURL: originalURL
        )
        let duplicate = try await store.register(
            fileURL: originalURL
        )

        XCTAssertEqual(registered.id, duplicate.id)
        let registeredDocuments = await store
            .documents()
        XCTAssertEqual(
            registeredDocuments.count,
            1
        )

        let reopenedStore = RecentOriginalDocumentStore(
            defaults: defaults,
            storageKey: "recent-originals"
        )
        let opened = try await reopenedStore.open(
            id: registered.id
        )
        XCTAssertEqual(
            try CoordinatedDocumentFileAccess
                .readData(from: opened.session.url),
            originalData
        )

        let updatedData = Data("updated".utf8)
        try CoordinatedDocumentFileAccess
            .replaceContents(
                at: opened.session.url,
                with: updatedData
            )
        try await reopenedStore.refreshBookmark(
            id: registered.id,
            fileURL: opened.session.url
        )

        XCTAssertEqual(
            try Data(contentsOf: originalURL),
            updatedData
        )
        let updatedDocuments = await reopenedStore
            .documents()
        XCTAssertEqual(
            updatedDocuments.first?.displayName,
            "명단.xlsx"
        )
    }

    func testRemovingRecentRecordDoesNotDeleteOriginalFile()
        async throws
    {
        let suiteName =
            "RecentOriginalDocumentRemoval-"
            + UUID().uuidString
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: suiteName)
        )
        defer {
            defaults.removePersistentDomain(
                forName: suiteName
            )
        }
        let originalURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "recent-removal-"
                    + UUID().uuidString
                    + ".txt"
            )
        try Data("keep".utf8).write(
            to: originalURL
        )
        defer {
            try? FileManager.default.removeItem(
                at: originalURL
            )
        }

        let store = RecentOriginalDocumentStore(
            defaults: defaults,
            storageKey: "recent-originals"
        )
        let record = try await store.register(
            fileURL: originalURL
        )
        await store.remove(id: record.id)

        let remainingDocuments = await store
            .documents()
        XCTAssertTrue(remainingDocuments.isEmpty)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: originalURL.path
            )
        )
    }
}
