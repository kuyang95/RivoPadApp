import Foundation
import XCTest

@testable import shortcuts_example

final class AppDeepLinkRouterTests: XCTestCase {
    func testRecognizesEveryWidgetDestination()
        throws
    {
        for destination in
            AppDeepLinkDestination.allCases {
            let url = try XCTUnwrap(
                URL(
                    string:
                        "rivopad://open/"
                        + destination.rawValue
                )
            )
            XCTAssertEqual(
                AppDeepLinkRouter.destination(
                    for: url
                ),
                destination
            )
        }
    }

    func testRejectsOtherSchemesHostsAndNestedPaths()
        throws
    {
        let invalidURLs = [
            "https://open/scanner",
            "rivopad://share-inbox",
            "rivopad://open",
            "rivopad://open/scanner/extra",
            "rivopad://open/unknown"
        ]

        for value in invalidURLs {
            let url = try XCTUnwrap(
                URL(string: value)
            )
            XCTAssertNil(
                AppDeepLinkRouter.destination(
                    for: url
                )
            )
        }
    }

    func testRecognizesDedicatedQuickLaunchDestinations()
        throws
    {
        let expected:
            [String: AppDeepLinkDestination] = [
                "ai-new": .aiNew,
                "ai-history": .aiHistory,
                "voice-action": .voiceAction
            ]

        for (path, destination) in expected {
            let url = try XCTUnwrap(
                URL(
                    string:
                        "rivopad://open/"
                        + path
                )
            )
            XCTAssertEqual(
                AppDeepLinkRouter.destination(
                    for: url
                ),
                destination
            )
        }
    }
}
