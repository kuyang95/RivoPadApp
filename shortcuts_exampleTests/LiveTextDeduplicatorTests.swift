import XCTest

@testable import shortcuts_example

final class LiveTextDeduplicatorTests: XCTestCase {
    func testFirstMeaningfulTextIsAnnounced() {
        XCTAssertTrue(
            LiveTextDeduplicator.shouldAnnounce(
                "안녕하세요",
                after: ""
            )
        )
        XCTAssertFalse(
            LiveTextDeduplicator.shouldAnnounce(
                " ",
                after: ""
            )
        )
    }

    func testWhitespaceAndMinorPartialChangesAreSuppressed() {
        XCTAssertFalse(
            LiveTextDeduplicator.shouldAnnounce(
                "같은   문장입니다",
                after: "같은 문장입니다"
            )
        )
        XCTAssertFalse(
            LiveTextDeduplicator.shouldAnnounce(
                "문서를 읽고 있습니다.",
                after: "문서를 읽고 있습니다"
            )
        )
    }

    func testSubstantiallyDifferentTextIsAnnounced() {
        XCTAssertTrue(
            LiveTextDeduplicator.shouldAnnounce(
                "출입구는 오른쪽에 있습니다.",
                after: "오늘의 메뉴는 김치찌개입니다."
            )
        )
    }
}
