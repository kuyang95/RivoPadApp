import PDFKit
import UIKit
import XCTest

@testable import shortcuts_example

final class DocumentScanSessionTests:
    XCTestCase
{
    func testPagesPersistAndLatestSessionRestores()
        throws
    {
        let base = temporaryBaseDirectory()
        let store = DocumentScanSessionStore(
            baseDirectory: base,
            sessionID: UUID()
        )
        let image = testImage(
            size: CGSize(
                width: 40,
                height: 30
            ),
            color: .systemBlue
        )
        let first = try store.append(
            image: image,
            to: []
        )
        var second = try store.append(
            image: image,
            to: [first]
        )
        second.rotateClockwise()
        let expected = [first, second]
        try store.save(pages: expected)

        let restored =
            DocumentScanSessionStore
            .restoringLatest(
                baseDirectory: base
            )

        let restoredPages =
            restored.loadPages()
        XCTAssertEqual(
            restoredPages.map(\.id),
            expected.map(\.id)
        )
        XCTAssertEqual(
            restoredPages.map(\.filename),
            expected.map(\.filename)
        )
        XCTAssertEqual(
            restoredPages.map(
                \.clockwiseQuarterTurns
            ),
            expected.map(
                \.clockwiseQuarterTurns
            )
        )
        for (
            restoredPage,
            expectedPage
        ) in zip(
            restoredPages,
            expected
        ) {
            XCTAssertEqual(
                restoredPage.capturedAt
                    .timeIntervalSince1970,
                expectedPage.capturedAt
                    .timeIntervalSince1970,
                accuracy: 0.001
            )
        }
        XCTAssertNotNil(
            try restored.image(
                for: second
            ).cgImage
        )
    }

    func testMultiPagePDFKeepsOrderAndRotation()
        throws
    {
        let base = temporaryBaseDirectory()
        let store = DocumentScanSessionStore(
            baseDirectory: base
        )
        let portrait = testImage(
            size: CGSize(
                width: 30,
                height: 50
            ),
            color: .systemRed
        )
        let landscape = testImage(
            size: CGSize(
                width: 60,
                height: 35
            ),
            color: .systemGreen
        )
        let first = try store.append(
            image: portrait,
            to: []
        )
        var second = try store.append(
            image: landscape,
            to: [first]
        )
        second.rotateClockwise()

        let data = try store.makePDFData(
            pages: [second, first]
        )
        let document = try XCTUnwrap(
            PDFDocument(data: data)
        )

        XCTAssertEqual(
            document.pageCount,
            2
        )
        let firstBounds = try XCTUnwrap(
            document.page(at: 0)
        ).bounds(for: .mediaBox)
        let secondBounds = try XCTUnwrap(
            document.page(at: 1)
        ).bounds(for: .mediaBox)
        XCTAssertGreaterThan(
            firstBounds.height,
            firstBounds.width
        )
        XCTAssertGreaterThan(
            secondBounds.height,
            secondBounds.width
        )
    }

    func testPageLimitAndDiscard()
        throws
    {
        let base = temporaryBaseDirectory()
        let store = DocumentScanSessionStore(
            baseDirectory: base
        )
        let data = try XCTUnwrap(
            testImage(
                size: CGSize(
                    width: 8,
                    height: 8
                ),
                color: .black
            )
            .jpegData(
                compressionQuality: 0.8
            )
        )
        var pages:
            [DocumentScanPageRecord] = []
        for _ in 0 ..<
            DocumentScanSessionStore
                .maximumPageCount {
            pages.append(
                try store.append(
                    jpegData: data,
                    to: pages
                )
            )
        }

        XCTAssertThrowsError(
            try store.append(
                jpegData: data,
                to: pages
            )
        ) { error in
            XCTAssertEqual(
                error as?
                    DocumentScanSessionError,
                .pageLimitReached(
                    maximum:
                        DocumentScanSessionStore
                        .maximumPageCount
                )
            )
        }

        try store.save(pages: pages)
        XCTAssertTrue(
            FileManager.default
                .fileExists(
                    atPath:
                        store.sessionDirectory
                        .path
                )
        )
        store.discard()
        XCTAssertFalse(
            FileManager.default
                .fileExists(
                    atPath:
                        store.sessionDirectory
                        .path
                )
        )
    }

    func testPDFCreationFailsWhenStoredPageIsMissing()
        throws
    {
        let store = DocumentScanSessionStore(
            baseDirectory:
                temporaryBaseDirectory()
        )
        let image = testImage(
            size: CGSize(
                width: 30,
                height: 40
            ),
            color: .systemOrange
        )
        let first = try store.append(
            image: image,
            to: []
        )
        let second = try store.append(
            image: image,
            to: [first]
        )
        try store.removeFile(
            for: second
        )

        XCTAssertThrowsError(
            try store.makePDFData(
                pages: [first, second]
            )
        ) { error in
            XCTAssertEqual(
                error as?
                    DocumentScanSessionError,
                .imageDecodingFailed
            )
        }
    }

    func testSessionModelPersistsReviewEdits()
        throws
    {
        let store = DocumentScanSessionStore(
            baseDirectory:
                temporaryBaseDirectory()
        )
        let model =
            DocumentScanSessionModel(
                store: store
            )
        for color in [
            UIColor.systemRed,
            .systemGreen,
            .systemBlue
        ] {
            XCTAssertTrue(
                model.append(
                    testImage(
                        size: CGSize(
                            width: 24,
                            height: 32
                        ),
                        color: color
                    )
                )
            )
        }

        let rotatedPage = model.pages[1]
        model.rotate(rotatedPage)
        model.move(
            from: IndexSet(integer: 2),
            to: 0
        )
        let removedPage = model.pages[1]
        model.remove(removedPage)

        XCTAssertEqual(
            store.loadPages(),
            model.pages
        )
        XCTAssertEqual(
            model.pages.first?
                .clockwiseQuarterTurns,
            0
        )
        XCTAssertEqual(
            model.pages.last?
                .clockwiseQuarterTurns,
            1
        )
        XCTAssertFalse(
            FileManager.default
                .fileExists(
                    atPath:
                        store.pageURL(
                            for: removedPage
                        ).path
                )
        )
    }

    private func temporaryBaseDirectory()
        -> URL
    {
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "DocumentScanSessionTests-"
                    + UUID().uuidString,
                isDirectory: true
            )
        addTeardownBlock {
            try? FileManager.default
                .removeItem(at: url)
        }
        return url
    }

    private func testImage(
        size: CGSize,
        color: UIColor
    ) -> UIImage {
        UIGraphicsImageRenderer(
            size: size
        ).image { context in
            color.setFill()
            context.fill(
                CGRect(
                    origin: .zero,
                    size: size
                )
            )
        }
    }
}
