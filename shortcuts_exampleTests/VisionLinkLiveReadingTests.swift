import Foundation
@testable import shortcuts_example
import XCTest

final class VisionLinkLiveReadingTests:
    XCTestCase
{
    func testStartStopControlsProduceSessionEvents()
        async
    {
        let fixture = makeFixture()
        defer { fixture.remove() }

        let start = await fixture.receiver.receive(
            .control(
                controlData(
                    [
                        "type":
                            "live-reading-start",
                        "sessionId": "session-1",
                    ]
                )
            )
        )
        XCTAssertEqual(
            start,
            [
                .event(
                    .liveReadingStarted(
                        "session-1"
                    )
                ),
            ]
        )

        let stop = await fixture.receiver.receive(
            .control(
                controlData(
                    [
                        "type":
                            "live-reading-stop",
                        "sessionId": "session-1",
                    ]
                )
            )
        )
        XCTAssertEqual(
            stop,
            [
                .event(
                    .liveReadingStopped(
                        "session-1"
                    )
                ),
            ]
        )

        let invalid = await fixture.receiver
            .receive(
                .control(
                    controlData(
                        [
                            "type":
                                "live-reading-start",
                            "sessionId": String(
                                repeating: "a",
                                count: 81
                            ),
                        ]
                    )
                )
            )
        XCTAssertEqual(invalid, [])
    }

    func testControlMessagesMatchAndroidLimits()
        throws
    {
        let status = try controlObject(
            VisionLinkLiveReadingControl.status(
                sessionID: "session-1",
                state: "started"
            )
        )
        XCTAssertEqual(
            status["type"] as? String,
            "live-reading-status"
        )
        XCTAssertEqual(
            status["state"] as? String,
            "started"
        )

        let result = try controlObject(
            VisionLinkLiveReadingControl.result(
                sessionID: "session-1",
                sequence: 3,
                text: "인식 결과"
            )
        )
        XCTAssertEqual(
            result["type"] as? String,
            "live-reading-result"
        )
        XCTAssertEqual(
            result["sequence"] as? Int,
            3
        )

        let oversized = try controlObject(
            VisionLinkLiveReadingControl.result(
                sessionID: "session-1",
                sequence: 4,
                text: String(
                    repeating: "a",
                    count:
                        VisionLinkLiveReadingControl
                        .maximumResultSize + 1
                )
            )
        )
        XCTAssertEqual(
            oversized["type"] as? String,
            "live-reading-error"
        )

        let longError = try controlObject(
            VisionLinkLiveReadingControl.error(
                sessionID: "session-1",
                message: String(
                    repeating: "가",
                    count: 700
                )
            )
        )
        XCTAssertEqual(
            (
                longError["message"] as? String
            )?.count,
            500
        )
    }

    func testTextFilterNormalizesAndSuppressesRecentDuplicates()
    {
        var filter =
            VisionLinkLiveReadingTextFilter()
        XCTAssertNil(filter.accept(" \n\t "))
        XCTAssertEqual(
            filter.accept(
                "첫 번째\n 인식   문장"
            ),
            "첫 번째 인식 문장"
        )
        XCTAssertNil(
            filter.accept(
                "첫 번째 인식 문장"
            )
        )

        let original = String(
            repeating: "가나다라마바사",
            count: 8
        )
        let nearDuplicate =
            original.dropLast() + "아"
        XCTAssertEqual(
            filter.accept(original),
            original
        )
        XCTAssertNil(
            filter.accept(
                String(nearDuplicate)
            )
        )
        XCTAssertEqual(
            filter.accept("완전히 다른 글자"),
            "완전히 다른 글자"
        )
    }

    func testTextFilterHistoryLimitAndReset()
    {
        var filter =
            VisionLinkLiveReadingTextFilter(
                historyLimit: 2
            )
        let first = "첫 번째 고유한 긴 문장"
        XCTAssertEqual(
            filter.accept(first),
            first
        )
        _ = filter.accept(
            "두 번째 전혀 다른 문장"
        )
        _ = filter.accept(
            "세 번째 별개의 내용"
        )
        XCTAssertEqual(
            filter.accept(first),
            first
        )

        filter.reset()
        XCTAssertEqual(
            filter.accept(
                "세 번째 별개의 내용"
            ),
            "세 번째 별개의 내용"
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
        _ data: Data
    ) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: data
            ) as? [String: Any]
        )
    }

    private func makeFixture() -> Fixture {
        let root = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "VisionLinkLiveReadingTests-"
                    + UUID().uuidString,
                isDirectory: true
            )
        return Fixture(
            root: root,
            receiver: VisionLinkDataReceiver(
                destinationDirectory: root
                    .appendingPathComponent(
                        "Destination",
                        isDirectory: true
                    ),
                partialDirectory: root
                    .appendingPathComponent(
                        "Partial",
                        isDirectory: true
                    )
            )
        )
    }
}

private struct Fixture {
    let root: URL
    let receiver: VisionLinkDataReceiver

    func remove() {
        try? FileManager.default.removeItem(
            at: root
        )
    }
}
