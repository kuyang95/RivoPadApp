import Foundation
import XCTest

@testable import shortcuts_example

@MainActor
final class DocumentLibraryRecentsTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var directory: URL!

    override func setUpWithError() throws {
        suiteName = "DocumentLibraryRecentsTests-" + UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }

    private func registeredStore(
        _ names: [String]
    ) async throws -> RecentOriginalDocumentStore {
        let store = RecentOriginalDocumentStore(
            defaults: defaults,
            storageKey: "recents"
        )
        for name in names {
            let url = directory.appendingPathComponent(name)
            try Data(name.utf8).write(to: url)
            _ = try await store.register(fileURL: url)
            // Distinct opening times keep the newest-first order stable.
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        return store
    }

    func testEditModeDeleteRemovesTheRowsFromRecentsOnly() async throws {
        let store = try await registeredStore(
            ["a.xlsx", "b.hwpx", "c.pdf", "d.txt"]
        )
        let model = DocumentLibraryViewModel(
            recentStore: store,
            appFolderURL: nil
        )
        await model.refreshRecentDocuments()
        XCTAssertEqual(
            model.recentDocuments.map(\.displayName),
            ["d.txt", "c.pdf", "b.hwpx", "a.xlsx"]
        )

        await model.removeRecentDocuments(at: IndexSet([0, 2]))

        XCTAssertEqual(
            model.recentDocuments.map(\.displayName),
            ["c.pdf", "a.xlsx"]
        )
        let stored = await store.documents()
        XCTAssertEqual(
            stored.map(\.displayName),
            ["c.pdf", "a.xlsx"]
        )
        // Only the recent entry goes; the original file stays where it was.
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("d.txt").path
            )
        )
    }

    func testEditModeDeleteMatchesSwipeRemoval() async throws {
        let store = try await registeredStore(["a.xlsx", "b.hwp"])
        let swiped = DocumentLibraryViewModel(
            recentStore: store,
            appFolderURL: nil
        )
        await swiped.refreshRecentDocuments()
        let first = try XCTUnwrap(swiped.recentDocuments.first)
        await swiped.removeRecentDocument(first)
        XCTAssertEqual(swiped.recentDocuments.map(\.displayName), ["a.xlsx"])

        await swiped.removeRecentDocuments(at: IndexSet([0, 5]))
        XCTAssertTrue(swiped.recentDocuments.isEmpty)
    }
}
