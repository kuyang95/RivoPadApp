import UIKit
import XCTest

@testable import shortcuts_example

@MainActor
final class MagnifierPhotoSaveTests:
    XCTestCase
{
    func testPhotoFilenameMatchesAndroidTimestampShape()
    {
        var calendar = Calendar(
            identifier: .gregorian
        )
        let timeZone =
            TimeZone(
                secondsFromGMT:
                    9 * 60 * 60
            )!
        calendar.timeZone = timeZone
        let date = calendar.date(
            from: DateComponents(
                year: 2026,
                month: 7,
                day: 30,
                hour: 16,
                minute: 45,
                second: 12,
                nanosecond: 345_000_000
            )
        )!

        XCTAssertEqual(
            MagnifierPhotoNaming.filename(
                for: date,
                timeZone: timeZone
            ),
            "VisionCraft-2026-07-30-16-45-12-345.jpg"
        )
    }

    func testTemporaryFilesExportAndCleanUp()
        throws
    {
        let root =
            FileManager.default
                .temporaryDirectory
                .appendingPathComponent(
                    UUID().uuidString,
                    isDirectory: true
                )
        defer {
            try? FileManager.default
                .removeItem(at: root)
        }
        let renderer =
            UIGraphicsImageRenderer(
                size: CGSize(
                    width: 4,
                    height: 4
                )
            )
        let image = renderer.image {
            context in
            UIColor.systemIndigo
                .setFill()
            context.fill(
                CGRect(
                    origin: .zero,
                    size: CGSize(
                        width: 4,
                        height: 4
                    )
                )
            )
        }
        let capture =
            try MagnifierPhotoCapture(
                image: image,
                date: Date(
                    timeIntervalSince1970: 0
                ),
                timeZone:
                    TimeZone(
                        secondsFromGMT: 0
                    )!
            )
        let service =
            MagnifierPhotoSaveService(
                temporaryDirectory: root
            )

        let url =
            try service
                .makeTemporaryExportURL(
                    for: capture
                )

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: url.path
            )
        )
        XCTAssertEqual(
            try Data(contentsOf: url),
            capture.jpegData
        )

        service.removeTemporaryExport(
            at: url
        )

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: url.path
            )
        )
    }
}
