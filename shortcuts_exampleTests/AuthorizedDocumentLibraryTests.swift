import Foundation
import XCTest

@testable import shortcuts_example

final class AuthorizedDocumentLibraryTests:
    XCTestCase
{
    func testScanFindsSupportedDocumentsAndSkipsUnsafeDescendants()
        throws
    {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let nested = fixture.root
            .appendingPathComponent(
                "업무/2026",
                isDirectory: true
            )
        try FileManager.default
            .createDirectory(
                at: nested,
                withIntermediateDirectories:
                    true
            )
        try write(
            "보고서",
            to: fixture.root
                .appendingPathComponent(
                    "보고서.pdf"
                )
        )
        try write(
            "표",
            to: nested
                .appendingPathComponent(
                    "매출.XLSX"
                )
        )
        try write(
            "문서",
            to: nested
                .appendingPathComponent(
                    "문서.hwp"
                )
        )
        try write(
            "개방형 문서",
            to: nested
                .appendingPathComponent(
                    "문서.HWPX"
                )
        )
        try write(
            "사진",
            to: fixture.root
                .appendingPathComponent(
                    "사진.jpg"
                )
        )
        try write(
            "숨김",
            to: fixture.root
                .appendingPathComponent(
                    ".숨김.pdf"
                )
        )
        let package = fixture.root
            .appendingPathComponent(
                "앱.app",
                isDirectory: true
            )
        try FileManager.default
            .createDirectory(
                at: package,
                withIntermediateDirectories:
                    true
            )
        try write(
            "패키지 내부",
            to: package
                .appendingPathComponent(
                    "inside.pdf"
                )
        )
        let outside = fixture.root
            .deletingLastPathComponent()
            .appendingPathComponent(
                "outside-"
                    + UUID().uuidString,
                isDirectory: true
            )
        try FileManager.default
            .createDirectory(
                at: outside,
                withIntermediateDirectories:
                    true
            )
        defer {
            try? FileManager.default
                .removeItem(at: outside)
        }
        try write(
            "외부",
            to: outside
                .appendingPathComponent(
                    "outside.pdf"
                )
        )
        try FileManager.default
            .createSymbolicLink(
                at: fixture.root
                    .appendingPathComponent(
                        "외부 링크"
                    ),
                withDestinationURL:
                    outside
            )

        let result =
            try AuthorizedDocumentSearch.scan(
                rootURL: fixture.root
            )

        XCTAssertEqual(
            Set(
                result.items.map(
                    \.relativePath
                )
            ),
            [
                "보고서.pdf",
                "업무/2026/매출.XLSX",
                "업무/2026/문서.hwp",
                "업무/2026/문서.HWPX",
            ]
        )
        XCTAssertFalse(result.isTruncated)
    }

    func testScanCapsResultsAndDepth()
        throws
    {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let deep = fixture.root
            .appendingPathComponent(
                "one/two/three",
                isDirectory: true
            )
        try FileManager.default
            .createDirectory(
                at: deep,
                withIntermediateDirectories:
                    true
            )
        for index in 0..<4 {
            try write(
                "\(index)",
                to: fixture.root
                    .appendingPathComponent(
                        "file-\(index).txt"
                    )
            )
        }
        try write(
            "deep",
            to: deep
                .appendingPathComponent(
                    "deep.pdf"
                )
        )

        let capped =
            try AuthorizedDocumentSearch.scan(
                rootURL: fixture.root,
                maximumResults: 2
            )
        XCTAssertEqual(
            capped.items.count,
            2
        )
        XCTAssertTrue(capped.isTruncated)

        let shallow =
            try AuthorizedDocumentSearch.scan(
                rootURL: fixture.root,
                maximumDepth: 2
            )
        XCTAssertFalse(
            shallow.items.contains {
                $0.name == "deep.pdf"
            }
        )
    }

    func testCappedScanKeepsMostRecentlyModifiedDocuments()
        throws
    {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let fileManager = FileManager.default
        let old = fixture.root
            .appendingPathComponent(
                "old.txt"
            )
        let middle = fixture.root
            .appendingPathComponent(
                "middle.txt"
            )
        let newest = fixture.root
            .appendingPathComponent(
                "newest.txt"
            )
        try write("old", to: old)
        try write("middle", to: middle)
        try write("newest", to: newest)
        try fileManager.setAttributes(
            [
                .modificationDate:
                    Date(timeIntervalSince1970: 10),
            ],
            ofItemAtPath: old.path
        )
        try fileManager.setAttributes(
            [
                .modificationDate:
                    Date(timeIntervalSince1970: 20),
            ],
            ofItemAtPath: middle.path
        )
        try fileManager.setAttributes(
            [
                .modificationDate:
                    Date(timeIntervalSince1970: 30),
            ],
            ofItemAtPath: newest.path
        )

        let result =
            try AuthorizedDocumentSearch.scan(
                rootURL: fixture.root,
                maximumResults: 2
            )

        XCTAssertEqual(
            result.items.map(\.name),
            [
                "newest.txt",
                "middle.txt",
            ]
        )
        XCTAssertTrue(result.isTruncated)
    }

    func testSearchMatchesFoldedNameAndRelativePath()
    {
        let item = AuthorizedDocumentItem(
            name: "Ｒésumé 보고서.PDF",
            relativePath:
                "서울 업무/Ｒésumé 보고서.PDF",
            pathExtension: "pdf",
            fileSize: 120,
            modificationDate: nil
        )

        XCTAssertEqual(
            AuthorizedDocumentSearch.filter(
                [item],
                query: "resume 서울"
            ),
            [item]
        )
        XCTAssertTrue(
            AuthorizedDocumentSearch.filter(
                [item],
                query: "부산"
            ).isEmpty
        )
    }

    func testRelativePathRejectsSiblingAndTraversal()
        throws
    {
        let root = URL(
            fileURLWithPath:
                "/tmp/VisionCraftDocs"
        )
        XCTAssertEqual(
            AuthorizedDocumentSearch
                .relativePath(
                    for: root
                        .appendingPathComponent(
                            "folder/file.pdf"
                        ),
                    rootURL: root
                ),
            "folder/file.pdf"
        )
        XCTAssertNil(
            AuthorizedDocumentSearch
                .relativePath(
                    for: URL(
                        fileURLWithPath:
                            "/tmp/VisionCraftDocs2/file.pdf"
                    ),
                    rootURL: root
                )
        )
    }

    private func makeFixture()
        throws -> Fixture
    {
        let root = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "AuthorizedDocuments-"
                    + UUID().uuidString,
                isDirectory: true
            )
        try FileManager.default
            .createDirectory(
                at: root,
                withIntermediateDirectories:
                    true
            )
        return Fixture(root: root)
    }

    private func write(
        _ text: String,
        to url: URL
    ) throws {
        try Data(text.utf8).write(
            to: url
        )
    }
}

private struct Fixture {
    let root: URL

    func remove() {
        try? FileManager.default
            .removeItem(at: root)
    }
}
