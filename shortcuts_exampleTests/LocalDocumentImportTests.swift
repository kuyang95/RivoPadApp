import Foundation
import XCTest

@testable import shortcuts_example

final class LocalDocumentImportTests: XCTestCase {
    func testTextDecoderSupportsUTF8AndUTF16() throws {
        let korean = "로컬 문서 테스트"

        XCTAssertEqual(
            try LocalTextDecoder.decode(
                try XCTUnwrap(
                    korean.data(using: .utf8)
                )
            ),
            korean
        )
        XCTAssertEqual(
            try LocalTextDecoder.decode(
                try XCTUnwrap(
                    korean.data(using: .utf16)
                )
            ),
            korean
        )
    }

    func testImportCopiesFileIntoSandbox() async throws {
        let fixtureDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "RivoDocumentImportTests-\(UUID().uuidString)",
                isDirectory: true
            )
        let sourceDirectory = fixtureDirectory
            .appendingPathComponent("Source", isDirectory: true)
        let importDirectory = fixtureDirectory
            .appendingPathComponent("Imported", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(
                at: fixtureDirectory
            )
        }

        let sourceURL = sourceDirectory
            .appendingPathComponent("sample.txt")
        let expected = Data("테스트 문서".utf8)
        try expected.write(to: sourceURL)

        let service = LocalDocumentImportService(
            importDirectory: importDirectory
        )
        let importedURL = try await service.importDocument(
            from: sourceURL
        )

        XCTAssertNotEqual(importedURL, sourceURL)
        XCTAssertEqual(importedURL.lastPathComponent, "sample.txt")
        XCTAssertEqual(try Data(contentsOf: importedURL), expected)
    }

    func testImportRejectsFileOverConfiguredLimit() async throws {
        let fixtureDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "RivoDocumentLimitTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: fixtureDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(
                at: fixtureDirectory
            )
        }

        let sourceURL = fixtureDirectory
            .appendingPathComponent("large.txt")
        try Data(repeating: 1, count: 2).write(to: sourceURL)
        let service = LocalDocumentImportService(
            importDirectory: fixtureDirectory
                .appendingPathComponent("Imported"),
            maximumFileSize: 1
        )

        do {
            _ = try await service.importDocument(from: sourceURL)
            XCTFail("제한을 넘는 파일은 가져오지 않아야 합니다.")
        } catch let error as LocalDocumentImportError {
            guard case .fileTooLarge = error else {
                return XCTFail("예상하지 못한 오류: \(error)")
            }
        }
    }
}
