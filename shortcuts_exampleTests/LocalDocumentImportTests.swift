import Foundation
import PDFKit
import XCTest

@testable import shortcuts_example

final class LocalDocumentImportTests: XCTestCase {
    func testDocumentLibraryFilePolicyNeverAllowsBookFormats() {
        XCTAssertFalse(
            DocumentLibraryFilePolicy
                .allows(pathExtension: "epub")
        )
        XCTAssertFalse(
            DocumentLibraryFilePolicy
                .allows(pathExtension: "EPUB")
        )
        XCTAssertFalse(
            DocumentLibraryFilePolicy
                .allows(pathExtension: "zip")
        )
        XCTAssertTrue(
            DocumentLibraryFilePolicy
                .allows(pathExtension: "xls")
        )
        XCTAssertTrue(
            DocumentLibraryFilePolicy
                .allows(pathExtension: "xlsx")
        )
    }

    @MainActor
    func testInMemoryClipboardDocumentLoadsExactText()
        async
    {
        let expected =
            "첫 줄\n\n공백을 보존한 두 번째 줄 "
        let viewModel =
            LocalDocumentViewModel(
                title: "클립보드 텍스트",
                text: expected
            )

        await viewModel.load()
        await viewModel.load()

        XCTAssertEqual(
            viewModel.fileName,
            "클립보드 텍스트"
        )
        XCTAssertEqual(
            viewModel.text,
            expected
        )
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(
            viewModel.errorDescription
        )
        XCTAssertNil(viewModel.pdfDocument)
    }

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

    func testTextEditorLayoutMatchesAndroidScalePolicy() {
        XCTAssertEqual(
            TextEditorLayoutPolicy.fontSize(
                level: 1,
                availableWidth: 700
            ),
            58,
            accuracy: 0.001
        )
        XCTAssertEqual(
            TextEditorLayoutPolicy.fontSize(
                level: 5,
                availableWidth: 600
            ),
            100,
            accuracy: 0.001
        )
        XCTAssertEqual(
            TextEditorLayoutPolicy.fontSize(
                level: 10,
                availableWidth: 600
            ),
            600,
            accuracy: 0.001
        )
        XCTAssertEqual(
            TextEditorLayoutPolicy.lineSpacing(
                level: 5,
                fontSize: 100
            ),
            28,
            accuracy: 0.001
        )
    }

    func testTextEditorSingleLineChunksKeepLongDocumentVisible() {
        let source = String(repeating: "가나다라마바사", count: 100)
            + "\r\n다음 줄\n마지막 줄"
        let chunks = TextEditorLayoutPolicy.singleLineChunks(
            source,
            maximumCharacterCount: 64
        )

        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 64 })
        XCTAssertEqual(
            chunks.joined(),
            String(repeating: "가나다라마바사", count: 100)
                + "   다음 줄   마지막 줄"
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

    @MainActor
    func testFileOpeningRoutesTextDocumentThroughSandboxCopy()
        async throws
    {
        let fixtureDirectory = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "RivoFileOpeningTests-\(UUID().uuidString)",
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
            .appendingPathComponent("recent-item.txt")
        let expected = Data("최근 항목 문서".utf8)
        try expected.write(to: sourceURL)

        let route = try await LocalFileOpening.route(
            for: sourceURL
        )
        guard case .localDocument(let importedURL) = route
        else {
            return XCTFail(
                "텍스트 문서는 로컬 문서 화면으로 열려야 합니다."
            )
        }

        defer {
            try? FileManager.default.removeItem(
                at: importedURL
                    .deletingLastPathComponent()
            )
        }
        XCTAssertNotEqual(importedURL, sourceURL)
        XCTAssertEqual(
            try Data(contentsOf: importedURL),
            expected
        )
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

    func testDocumentAppearancePersistsNormalizedValues()
        throws
    {
        let suiteName =
            "LocalDocumentAppearanceTests-"
            + UUID().uuidString
        let defaults =
            try XCTUnwrap(
                UserDefaults(
                    suiteName: suiteName
                )
            )
        defer {
            defaults.removePersistentDomain(
                forName: suiteName
            )
        }
        let store =
            LocalDocumentAppearanceStore(
                defaults: defaults,
                key: "appearance"
            )

        store.save(
            LocalDocumentAppearance(
                fontLevel: 99,
                lineHeightLevel: -5,
                colorIndex: 999,
                showsLineSeparators: true,
                usesSingleLineInLandscape:
                    true
            )
        )

        XCTAssertEqual(
            store.load(),
            LocalDocumentAppearance(
                fontLevel: 10,
                lineHeightLevel: 1,
                colorIndex:
                    LocalDocumentColorTheme
                    .all.count - 1,
                showsLineSeparators: true,
                usesSingleLineInLandscape:
                    true
            )
        )
    }

    func testDocumentAppearanceMigratesLegacySavedValues()
        throws
    {
        let suiteName =
            "LocalDocumentLegacyAppearance-"
            + UUID().uuidString
        let defaults =
            try XCTUnwrap(
                UserDefaults(
                    suiteName: suiteName
                )
            )
        defer {
            defaults.removePersistentDomain(
                forName: suiteName
            )
        }
        defaults.set(
            try XCTUnwrap(
                """
                {
                  "fontLevel": 7,
                  "lineHeightLevel": 4,
                  "colorIndex": 2,
                  "showsLineSeparators": true
                }
                """.data(using: .utf8)
            ),
            forKey: "appearance"
        )

        let appearance =
            LocalDocumentAppearanceStore(
                defaults: defaults,
                key: "appearance"
            )
            .load()

        XCTAssertEqual(
            appearance.fontLevel,
            7
        )
        XCTAssertTrue(
            appearance.showsLineSeparators
        )
        XCTAssertFalse(
            appearance
                .usesSingleLineInLandscape
        )
    }

    func testSingleLineLayoutRequiresLandscapeAndPreference()
    {
        XCTAssertTrue(
            LocalDocumentLayoutPolicy
                .usesSingleLine(
                    preferenceEnabled: true,
                    width: 1_024,
                    height: 768
                )
        )
        XCTAssertFalse(
            LocalDocumentLayoutPolicy
                .usesSingleLine(
                    preferenceEnabled: true,
                    width: 768,
                    height: 1_024
                )
        )
        XCTAssertFalse(
            LocalDocumentLayoutPolicy
                .usesSingleLine(
                    preferenceEnabled: false,
                    width: 1_024,
                    height: 768
                )
        )
    }

    func testDocumentTextNavigationPreservesBlankLines()
    {
        let text =
            "첫 줄\r\n\r\n셋째 줄\n마지막 줄"
        let lines =
            LocalDocumentTextSegmenter.lines(
                in: text
            )

        XCTAssertEqual(
            lines.map(\.text),
            [
                "첫 줄",
                "",
                "셋째 줄",
                "마지막 줄",
            ]
        )
        XCTAssertEqual(
            LocalDocumentTextSegmenter.text(
                fromLine: 2,
                in: text
            ),
            "셋째 줄\n마지막 줄"
        )
        XCTAssertEqual(
            LocalDocumentTextNavigator
                .targetLine(
                    from: 0,
                    direction: 1,
                    unit: .line,
                    lineCount: 20,
                    linesPerPage: 6
                ),
            1
        )
        XCTAssertEqual(
            LocalDocumentTextNavigator
                .targetLine(
                    from: 1,
                    direction: 1,
                    unit: .page,
                    lineCount: 20,
                    linesPerPage: 6
                ),
            7
        )
        XCTAssertEqual(
            LocalDocumentTextNavigator
                .targetLine(
                    from: 19,
                    direction: 1,
                    unit: .page,
                    lineCount: 20,
                    linesPerPage: 6
                ),
            nil
        )
    }

    func testDocumentExportsUTF8TextAndMultipagePDF()
        throws
    {
        let text =
            Array(
                repeating:
                    "문서 내보내기 테스트 문장입니다.",
                count: 300
            )
            .joined(separator: "\n")

        let textFile =
            LocalDocumentExportBuilder
            .textFile(text: text)
        let pdfFile =
            LocalDocumentExportBuilder
            .pdfFile(text: text)

        XCTAssertEqual(
            String(
                data: textFile.data,
                encoding: .utf8
            ),
            text
        )
        XCTAssertTrue(
            pdfFile.data.starts(
                with: Data("%PDF".utf8)
            )
        )
        let document =
            try XCTUnwrap(
                PDFDocument(
                    data: pdfFile.data
                )
            )
        XCTAssertGreaterThan(
            document.pageCount,
            1
        )
        XCTAssertTrue(
            document.page(at: 0)?
                .string?
                .contains(
                    "문서 내보내기"
                ) == true
        )
    }

    func testDocumentSentenceSegmentsKeepLineAndExactRanges()
    {
        let text =
            """
              첫 문장입니다. 둘째입니다!

            마지막 줄
            """
        let segments =
            LocalDocumentSentenceSegmenter
            .segments(in: text)

        XCTAssertEqual(
            segments.map(\.text),
            [
                "첫 문장입니다.",
                "둘째입니다!",
                "마지막 줄",
            ]
        )
        XCTAssertEqual(
            segments.map(\.lineIndex),
            [0, 0, 2]
        )
        let firstLine =
            (
                LocalDocumentTextSegmenter
                    .lines(in: text)
                    .first?
                    .text
                ?? ""
            ) as NSString
        XCTAssertEqual(
            firstLine.substring(
                with:
                    segments[0].utf16Range
            ),
            "첫 문장입니다."
        )
    }

    func testDocumentSpeechSelectionStartsAtVisibleLine()
    {
        var selection =
            LocalDocumentSpeechSelection(
                text:
                    "첫째입니다. 둘째입니다.\n\n셋째입니다.",
                startingAtLine: 2
            )

        XCTAssertEqual(
            selection.currentSegment?.text,
            "셋째입니다."
        )
        XCTAssertTrue(
            selection.movePrevious()
        )
        XCTAssertEqual(
            selection.currentSegment?.text,
            "둘째입니다."
        )
        XCTAssertTrue(
            selection.canMovePrevious
        )
        XCTAssertTrue(
            selection.canMoveNext
        )
    }

    func testDocumentSpeechControllerAdvancesAndStops()
    {
        let synthesizer =
            TestDocumentSpeechSynthesizer()
        let controller =
            LocalDocumentSpeechController(
                tts: synthesizer
            )

        XCTAssertTrue(
            controller.play(
                text:
                    "첫 문장입니다. 둘째입니다.",
                startingAtLine: 0
            )
        )
        XCTAssertEqual(
            synthesizer.spokenTexts,
            ["첫 문장입니다."]
        )
        synthesizer.finishCurrent()
        XCTAssertEqual(
            synthesizer.spokenTexts,
            [
                "첫 문장입니다.",
                "둘째입니다.",
            ]
        )
        XCTAssertEqual(
            controller.currentSegment?
                .text,
            "둘째입니다."
        )
        synthesizer.finishCurrent()
        XCTAssertFalse(
            controller.isSpeaking
        )

        _ = controller.previous(
            text:
                "첫 문장입니다. 둘째입니다.",
            startingAtLine: 0
        )
        XCTAssertEqual(
            synthesizer.spokenTexts.last,
            "첫 문장입니다."
        )
        let staleCompletion =
            synthesizer.completion
        controller.stop()
        staleCompletion?()
        XCTAssertFalse(
            controller.isSpeaking
        )
        XCTAssertEqual(
            synthesizer.spokenTexts.last,
            "첫 문장입니다."
        )
    }
}

@MainActor
private final class
    TestDocumentSpeechSynthesizer:
    LocalDocumentSpeechSynthesizing
{
    private(set) var spokenTexts:
        [String] = []
    var completion: (() -> Void)?

    func speak(
        _ text: String,
        rate: Float?,
        completion: (() -> Void)?
    ) {
        spokenTexts.append(text)
        self.completion = completion
    }

    func stop() {
        completion = nil
    }

    func finishCurrent() {
        let current = completion
        completion = nil
        current?()
    }
}

final class DocumentLibraryAppFolderTests: XCTestCase {
    @MainActor
    func testAppFolderScanListsSupportedDocumentsAndSkipsHiddenFolders()
        async throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "DocumentLibraryAppFolderTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let nested = root.appendingPathComponent("여행", isDirectory: true)
        let hidden = root.appendingPathComponent(".HWPValidation", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
        try Data("xlsx".utf8).write(to: root.appendingPathComponent("원소.xlsx"))
        try Data("hwpx".utf8).write(to: nested.appendingPathComponent("제주.hwpx"))
        try Data("png".utf8).write(to: root.appendingPathComponent("사진.png"))
        try Data("hwp".utf8).write(to: hidden.appendingPathComponent("V01.hwp"))

        let viewModel = DocumentLibraryViewModel(
            recentStore: RecentOriginalDocumentStore(
                defaults: UserDefaults(suiteName: "DocumentLibraryAppFolderTests")!,
                storageKey: "test.\(UUID().uuidString)"
            ),
            appFolderURL: root
        )
        await viewModel.refreshAppFolderDocuments()

        let names = Set(viewModel.appFolderDocuments.map(\.name))
        XCTAssertEqual(names, ["원소.xlsx", "제주.hwpx"])
        XCTAssertFalse(viewModel.isAppFolderTruncated)

        let nestedItem = try XCTUnwrap(
            viewModel.appFolderDocuments.first { $0.name == "제주.hwpx" }
        )
        XCTAssertEqual(nestedItem.relativePath, "여행/제주.hwpx")
        XCTAssertEqual(
            viewModel.appFolderDocumentURL(for: nestedItem)?.standardizedFileURL,
            nested.appendingPathComponent("제주.hwpx").standardizedFileURL
        )
    }

    @MainActor
    func testAppFolderScanIsSkippedWithoutFolder() async {
        let viewModel = DocumentLibraryViewModel(
            recentStore: RecentOriginalDocumentStore(
                defaults: UserDefaults(suiteName: "DocumentLibraryAppFolderTests")!,
                storageKey: "test.\(UUID().uuidString)"
            ),
            appFolderURL: nil
        )
        await viewModel.refreshAppFolderDocuments()
        XCTAssertTrue(viewModel.appFolderDocuments.isEmpty)
        XCTAssertNil(viewModel.appFolderDocumentURL(for: AuthorizedDocumentItem(
            name: "a.xlsx", relativePath: "a.xlsx", pathExtension: "xlsx",
            fileSize: nil, modificationDate: nil
        )))
    }
}
