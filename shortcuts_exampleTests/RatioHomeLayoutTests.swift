import XCTest
@testable import shortcuts_example

final class RatioHomeLayoutTests: XCTestCase {
    func testFullPageInstallPreservesOrdinaryWidgetsAndDoesNotDuplicateFeatures() {
        let shortcut = RatioHomeItem(id: "test", name: "Shortcut", textOnly: true, columns: 2, rows: 1, colorKey: "sky")
        let browser = RatioHomeItem(id: "widget:browser", name: "Browser", columns: 4, rows: 9)
        let items = installFullPageWidgets([shortcut, browser])
        XCTAssertEqual(items.map(\.id), ["test", "widget:youtube", "widget:browser", "widget:daisy"])
        XCTAssertEqual(items.first?.columns, 2)
        XCTAssertEqual(items.first?.colorKey, "sky")
        XCTAssertEqual(items.first(where: \.isBrowser)?.rows, 9)
        XCTAssertEqual(installFullPageWidgets(items).map(\.id), items.map(\.id))
    }
    func testHomePagesContainEachSourceRowExactlyOnce() {
        let pages = ratioPageRows([188, 188, 88, 1000, 1000, 1000], available: 600, fullPageRows: [3, 4, 5])
        XCTAssertEqual(pages, [[0, 1, 2], [3], [4], [5]])
        XCTAssertEqual(pages.flatMap { $0 }, Array(0..<6))
    }

    func testDedicatedPagesRemainSeparateEvenWithSmallMeasuredHeights() {
        let items = installFullPageWidgets([RatioHomeItem(id: "test", name: "Shortcut")])
        let rows = ratioItemRows(items)
        XCTAssertEqual(rows.map(\.count), [1, 1, 1, 1])
        XCTAssertEqual(ratioPageRows([88, 0, 1, 50], available: 1000, fullPageRows: [1, 2, 3]), [[0], [1], [2], [3]])
    }
}
