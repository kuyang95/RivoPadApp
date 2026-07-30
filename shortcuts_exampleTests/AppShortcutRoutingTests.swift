import Foundation
import XCTest

@testable import shortcuts_example

final class AppShortcutRoutingTests:
    XCTestCase
{
    func testEveryScreenEnvelopeRoundTrips()
        throws
    {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let date = Date(
            timeIntervalSince1970: 789
        )

        for destination in
            AppDeepLinkDestination.allCases {
            let envelope =
                ShortcutEnvelope.openScreen(
                    destination,
                    id: UUID(),
                    createdAt: date
                )
            let restored = try decoder.decode(
                ShortcutEnvelope.self,
                from: encoder.encode(envelope)
            )

            XCTAssertEqual(
                restored.openScreenDestination,
                destination
            )
            XCTAssertEqual(
                restored.schemaVersion,
                1
            )
            XCTAssertEqual(
                restored.createdAt,
                date
            )
        }
    }

    func testRejectsUnknownOrWrongRoute()
    {
        let unknown = ShortcutEnvelope(
            id: UUID(),
            route: .openScreen,
            createdAt: Date(),
            schemaVersion: 1,
            params: [
                "screen": .string("unknown")
            ],
            attachments: []
        )
        let wrongRoute = ShortcutEnvelope(
            id: UUID(),
            route: .documentScanning,
            createdAt: Date(),
            schemaVersion: 1,
            params: [
                "screen": .string(
                    AppDeepLinkDestination
                        .scanner.rawValue
                )
            ],
            attachments: []
        )

        XCTAssertNil(
            unknown.openScreenDestination
        )
        XCTAssertNil(
            wrongRoute.openScreenDestination
        )
    }
}
