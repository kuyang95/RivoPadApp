import Foundation
import XCTest
import ZIPFoundation

@testable import shortcuts_example

final class WordDocumentTextExtractorTests:
    XCTestCase
{
    func testDOCXExtractsParagraphsTabsAndBreaks()
        throws
    {
        let data = try makeDOCXData()

        let text = try WordDocumentTextExtractor
            .extract(from: data)

        XCTAssertEqual(
            text,
            "첫 문단\t탭\n둘째 줄\n표 셀"
        )
    }

    func testDOCSAliasUsesDetectedDOCXContents()
        async throws
    {
        let root = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "RivoWordAliasTests-"
                    + UUID().uuidString,
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default
                .removeItem(at: root)
        }
        let url = root.appendingPathComponent(
            "sample.docs"
        )
        try makeDOCXData().write(to: url)

        let text = try await
            LocalStructuredDocumentTextExtractor
            .extract(at: url)

        XCTAssertTrue(
            text.contains("첫 문단")
        )
        XCTAssertTrue(
            AuthorizedDocumentSearch
                .supportedExtensions
                .isSuperset(
                    of: [
                        "doc",
                        "docx",
                        "docs",
                    ]
                )
        )
    }

    func testDOCXRejectsExternalEntityDeclarations()
        throws
    {
        let data = try makeDOCXData(
            documentXML: """
                <!DOCTYPE document [
                  <!ENTITY payload "hidden">
                ]>
                <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
                  <w:body><w:p><w:r><w:t>&payload;</w:t></w:r></w:p></w:body>
                </w:document>
                """
        )

        XCTAssertThrowsError(
            try WordDocumentTextExtractor
                .extract(from: data)
        ) {
            XCTAssertEqual(
                $0 as?
                    WordDocumentTextExtractorError,
                .invalidDocument
            )
        }
    }

    private func makeDOCXData(
        documentXML: String = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:body>
                <w:p>
                  <w:r><w:t>첫 문단</w:t></w:r>
                  <w:r><w:tab/><w:t>탭</w:t><w:br/><w:t>둘째 줄</w:t></w:r>
                </w:p>
                <w:tbl><w:tr><w:tc><w:p><w:r><w:t>표 셀</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
              </w:body>
            </w:document>
            """
    ) throws -> Data {
        let archive = try Archive(
            accessMode: .create
        )
        let entries = [
            "[Content_Types].xml": """
                <?xml version="1.0" encoding="UTF-8"?>
                <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
                  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
                </Types>
                """,
            "word/document.xml":
                documentXML,
        ]
        for (path, value) in entries.sorted(
            by: { $0.key < $1.key }
        ) {
            let entryData = Data(value.utf8)
            try archive.addEntry(
                with: path,
                type: .file,
                uncompressedSize:
                    Int64(entryData.count),
                compressionMethod: .deflate
            ) { position, size in
                let lower = Int(position)
                let upper = min(
                    entryData.count,
                    lower + size
                )
                guard lower < upper else {
                    return Data()
                }
                return entryData.subdata(
                    in: lower..<upper
                )
            }
        }
        return try XCTUnwrap(archive.data)
    }
}
