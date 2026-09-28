import CryptoKit
import Foundation
import SwiftUI
import UIKit
import XCTest
import zlib
@testable import shortcuts_example

final class LegacyDocumentAttachmentTests:
    XCTestCase
{
    func testOLEReadsMiniAndRegularNestedStreams()
        throws
    {
        let small = Data(
            "nested mini stream".utf8
        )
        let large = Data(
            (0..<5_000).map {
                UInt8($0 % 251)
            }
        )
        let fixture = try makeOLEFile(
            streams: [
                "BodyText/Section0":
                    small,
                "Workbook": large,
            ]
        )
        let container =
            try OLECompoundFile(
                data: fixture
            )

        XCTAssertEqual(
            try container.stream(
                named:
                    "bodytext/SECTION0"
            ),
            small
        )
        XCTAssertEqual(
            try container.stream(
                named: "workbook"
            ),
            large
        )
    }

    func testOLERejectsRegularFATCycle()
        throws
    {
        var fixture = try makeOLEFile(
            streams: [
                "Workbook": Data(
                    repeating: 0x41,
                    count: 5_000
                ),
            ]
        )
        let fatSectorID = Int(
            try fixture.testUInt32(
                at: 76
            )
        )
        let fatOffset =
            (fatSectorID + 1) * 512
        // Sector 1 is the first regular Workbook sector in this fixture.
        fixture.testSetUInt32(
            1,
            at: fatOffset + 4
        )

        XCTAssertThrowsError(
            try OLECompoundFile(
                data: fixture
            ).stream(named: "Workbook")
        )
    }

    func testLegacyDOCExtractsUnicodePieceTable()
        throws
    {
        let expected = "첫 줄\r둘째 줄"
        let units = Array(expected.utf16)
        let textOffset = 0x0200
        var wordDocument = Data(
            repeating: 0,
            count: textOffset
                + units.count * 2
        )
        wordDocument.testSetUInt16(
            0xA5EC,
            at: 0
        )
        wordDocument.testSetUInt16(
            0x00C1,
            at: 2
        )
        wordDocument.testSetUInt32(
            UInt32(units.count),
            at: 0x004C
        )
        for (index, unit) in units
            .enumerated() {
            wordDocument.testSetUInt16(
                unit,
                at: textOffset + index * 2
            )
        }

        var pieceTable = Data()
        pieceTable.append(0x02)
        pieceTable.testAppendUInt32(16)
        pieceTable.testAppendUInt32(0)
        pieceTable.testAppendUInt32(
            UInt32(units.count)
        )
        pieceTable.testAppendUInt16(0)
        pieceTable.testAppendUInt32(
            UInt32(textOffset)
        )
        pieceTable.testAppendUInt16(0)
        wordDocument.testSetUInt32(
            0,
            at: 0x01A2
        )
        wordDocument.testSetUInt32(
            UInt32(pieceTable.count),
            at: 0x01A6
        )

        let fixture = try makeOLEFile(
            streams: [
                "WordDocument": wordDocument,
                "0Table": pieceTable,
            ]
        )
        let text = try WordDocumentTextExtractor
            .extract(from: fixture)

        XCTAssertEqual(
            text,
            "첫 줄\n둘째 줄"
        )
    }

    func testOLEAcceptsAppleEndOfChainFATSectorMarker()
        throws
    {
        let expected = Data(
            repeating: 0x41,
            count: 5_000
        )
        var fixture = try makeOLEFile(
            streams: [
                "WordDocument": expected,
            ]
        )
        let fatSectorID = Int(
            try fixture.testUInt32(at: 76)
        )
        let fatOffset =
            (fatSectorID + 1) * 512
        fixture.testSetUInt32(
            UInt32.max - 1,
            at: fatOffset
                + fatSectorID * 4
        )

        let container = try OLECompoundFile(
            data: fixture
        )

        XCTAssertEqual(
            try container.stream(
                named: "WordDocument"
            ),
            expected
        )
    }

    func testLegacyXLSExtractsBIFF8ValuesAndStoresOriginal()
        async throws
    {
        let root = try makeTemporaryRoot()
        defer {
            try? FileManager.default
                .removeItem(at: root)
        }
        let source = root
            .appendingPathComponent(
                "legacy.xls"
            )
        let workbook =
            try makeLegacyXLSWorkbook()
        try makeOLEFile(
            streams: [
                "Workbook": workbook,
            ]
        ).write(to: source)

        let store = ChatAttachmentStore(
            attachmentDirectory:
                root.appendingPathComponent(
                    "Attachments",
                    isDirectory: true
                )
        )
        let attachment =
            try await store
            .importLegacySpreadsheet(
                from: source
            )

        XCTAssertEqual(
            attachment.mimeType,
            "application/vnd.ms-excel"
        )
        XCTAssertTrue(
            attachment.extractedText?
                .contains("[매출]") == true
        )
        XCTAssertTrue(
            attachment.extractedText?
                .contains(
                    "제품\t수량\t활성"
                ) == true
        )
        XCTAssertTrue(
            attachment.extractedText?
                .contains(
                    "사과\t12.0\ttrue"
                ) == true
        )
        XCTAssertTrue(
            attachment.extractedText?
                .contains(
                    "3.5\t계산됨"
                ) == true
        )
        XCTAssertTrue(
            attachment.extractedText?
                .contains("[메모]") == true
        )
        XCTAssertTrue(
            attachment.extractedText?
                .contains(
                    "긴 문자열 시작"
                ) == true
        )
        XCTAssertTrue(
            attachment.extractedText?
                .contains(
                    "긴 문자열 끝"
                ) == true
        )
        let storedURL = await store
            .existingURL(for: attachment)
        XCTAssertNotNil(
            storedURL
        )
    }

    func testLegacyXLSConvertsValuesToEditableXLSX()
        throws
    {
        let legacyWorkbook = try
            makeLegacyXLSWorkbook()
        let source = try makeOLEFile(
            streams: [
                "Workbook": legacyWorkbook,
            ]
        )

        let snapshot = try
            LegacyXLSExtractor.workbook(
                from: source
            )
        XCTAssertEqual(
            snapshot.sheets.map(\.name),
            ["매출", "메모"]
        )
        XCTAssertEqual(
            snapshot.sheets[0].cells
                .first(where: {
                    $0.row == 2
                        && $0.column == 2
                })?.value,
            .number(12)
        )
        XCTAssertEqual(
            snapshot.sheets[0].cells
                .first(where: {
                    $0.row == 2
                        && $0.column == 3
                })?.value,
            .boolean(true)
        )

        let converted = try
            LegacyXLSXConverter.convert(
                from: source
            )
        let workbook = try
            ExcelWorkbookDocument.load(
                from: converted
            )
        XCTAssertEqual(
            workbook.sheets.map(\.name),
            ["매출", "메모"]
        )

        let sales = workbook.sheets[0]
        XCTAssertEqual(
            sales.cell(
                at: ExcelCellAddress(
                    row: 1,
                    column: 1
                )
            )?.displayValue,
            "제품"
        )
        XCTAssertEqual(
            sales.cell(
                at: ExcelCellAddress(
                    row: 2,
                    column: 2
                )
            )?.rawValue,
            "12.0"
        )
        XCTAssertEqual(
            sales.cell(
                at: ExcelCellAddress(
                    row: 2,
                    column: 3
                )
            )?.cellType,
            "b"
        )
        XCTAssertNil(
            sales.cell(
                at: ExcelCellAddress(
                    row: 3,
                    column: 1
                )
            )?.formula
        )
        XCTAssertEqual(
            sales.cell(
                at: ExcelCellAddress(
                    row: 3,
                    column: 1
                )
            )?.rawValue,
            "3.5"
        )
        XCTAssertEqual(
            sales.cell(
                at: ExcelCellAddress(
                    row: 3,
                    column: 2
                )
            )?.displayValue,
            "계산됨"
        )
        XCTAssertTrue(
            workbook.sheets[1]
                .cell(
                    at: ExcelCellAddress(
                        row: 1,
                        column: 1
                    )
                )?.displayValue
                .contains("긴 문자열 끝")
                == true
        )
    }

    func testLegacyXLSRejectsFilePass()
        throws
    {
        let workbook =
            try makeLegacyXLSWorkbook(
                includesFilePass: true
            )
        let fixture = try makeOLEFile(
            streams: [
                "Workbook": workbook,
            ]
        )
        XCTAssertThrowsError(
            try LegacyXLSExtractor.extract(
                from: fixture
            )
        ) {
            XCTAssertEqual(
                $0 as? ChatAttachmentError,
                .encryptedSpreadsheet
            )
        }
    }

    func testCompressedHWP5ExtractsParagraphControlsAndStoresOriginal()
        async throws
    {
        let root = try makeTemporaryRoot()
        defer {
            try? FileManager.default
                .removeItem(at: root)
        }
        let source = root
            .appendingPathComponent(
                "local.hwp"
            )
        try makeHWP5File(
            compressed: true
        ).write(to: source)
        let store = ChatAttachmentStore(
            attachmentDirectory:
                root.appendingPathComponent(
                    "Attachments",
                    isDirectory: true
                )
        )

        let attachment =
            try await store.importHWP(
                from: source
            )

        XCTAssertEqual(
            attachment.mimeType,
            "application/x-hwp"
        )
        XCTAssertTrue(
            attachment.extractedText?
                .contains(
                    "첫 문단\t탭 뒤"
                ) == true
        )
        XCTAssertTrue(
            attachment.extractedText?
                .contains(
                    "둘째 문단-끝"
                ) == true
        )
        XCTAssertFalse(
            attachment.extractedText?
                .contains("\0") == true
        )
        let storedURL = await store
            .existingURL(for: attachment)
        XCTAssertNotNil(
            storedURL
        )
    }

    func testHWP5StructuredParserReadsDocInfoStylesAndTextRuns() throws {
        let document = try HWP5StructuredDocumentParser.parse(
            from: makeHWP5File(
                compressed: true,
                docInfoOverride: makeStructuredHWPDocInfo(),
                sectionOverride: makeStructuredHWPSection()
            )
        )

        XCTAssertEqual(document.fidelity, .structured)
        XCTAssertEqual(document.fontCount, 1)
        XCTAssertEqual(document.characterShapeCount, 1)
        XCTAssertEqual(document.paragraphShapeCount, 1)
        XCTAssertEqual(document.styleCount, 1)
        XCTAssertEqual(document.blocks.count, 1)

        let block = try XCTUnwrap(document.blocks.first)
        XCTAssertEqual(block.text, "구조화 제목")
        XCTAssertEqual(block.presentation.styleName, "제목 1")
        XCTAssertEqual(block.presentation.alignment, .centered)
        XCTAssertEqual(block.presentation.outlineLevel, 0)
        XCTAssertEqual(block.presentation.leftMarginPoints, 5, accuracy: 0.001)
        XCTAssertEqual(block.presentation.firstLineIndentPoints, 2.5, accuracy: 0.001)

        let run = try XCTUnwrap(block.presentation.textRuns.first)
        XCTAssertEqual(
            block.presentation.textRuns.map(\.text).joined(),
            "구조화 제목"
        )
        XCTAssertEqual(run.fontName, "함초롬바탕")
        XCTAssertEqual(try XCTUnwrap(run.fontSizePoints), 12, accuracy: 0.001)
        XCTAssertEqual(run.textColorRGB, 0xFF0000)
        XCTAssertTrue(run.isBold)
        XCTAssertTrue(block.isEditable)
    }

    @MainActor
    func testHWP5BlankParagraphCanBeViewedEditedAndSaved() throws {
        let source = try makeHWP5File(compressed: true,
            docInfoOverride: makeStructuredHWPDocInfo(),
            sectionOverride: makeStructuredHWPSection(text: ""))
        let document = try HWP5StructuredDocumentParser.parse(from: source)
        XCTAssertEqual(document.blocks.count, 1)
        XCTAssertEqual(document.blocks.first?.text, "")
        XCTAssertEqual(HWPOriginalCanvasPageBuilder.makePages(
            blocks: document.blocks, layouts: document.pageLayouts).count, 1)

        var edited = document.blocks
        edited[0].text = "빈 한글 문서에 입력한 내용"
        let output = try HWP5DocumentRewriter.rewrite(sourceData: source,
            originalBlocks: document.blocks, editedBlocks: edited)
        let reloaded = try HWP5StructuredDocumentParser.parse(from: output)
        XCTAssertEqual(reloaded.blocks.first?.text, edited[0].text)
        XCTAssertThrowsError(try HWP5StructuredDocumentParser.parse(from:
            makeHWP5File(compressed: true, sectionOverride: Data())))
    }

    @MainActor
    func testHWPFontResolverUsesBundledLegacyKoreanFaces() throws {
        let expected: [(
            declared: String,
            postScript: String,
            resource: String,
            extension: String
        )] = [
            ("바탕", "Batang-Regular", "Batang-Regular", "ttf"),
            ("한양신명조", "Batang-Regular", "Batang-Regular", "ttf"),
            ("궁서", "Gungsuh-Regular", "Gungsuh-Regular", "ttf"),
            ("굴림체", "Gulim-Regular", "Gulim-Regular", "ttf"),
            ("함초롬돋움", "SUIT-Regular", "SUIT-Regular", "otf"),
            ("맑은 고딕", "Pretendard-Regular", "Pretendard-Regular", "otf"),
            ("HCI Poppy", "Pretendard-Regular", "Pretendard-Regular", "otf"),
            ("휴먼명조", "Batang-Regular", "Batang-Regular", "ttf"),
            ("신명 신명조", "PureBatang-Medium", "PureBatang-Medium", "otf"),
            ("HY헤드라인M", "NanumSquareNeo-dEb", "NanumSquareNeoOTF-Eb", "otf"),
        ]
        for item in expected {
            XCTAssertNotNil(
                Bundle.main.url(
                    forResource: item.resource,
                    withExtension: item.extension
                )
            )
            XCTAssertEqual(
                HWPDocumentFontResolver.resolvedName(for: item.declared),
                item.postScript
            )
            XCTAssertNotNil(UIFont(name: item.postScript, size: 12))
        }
        let sunBatang = HWPDocumentFontResolver.resolution(
            declaredName: "SunBatang",
            alternateName: nil,
            baseName: nil,
            signature: nil
        )
        XCTAssertEqual(sunBatang.kind, .exact)
        XCTAssertEqual(sunBatang.resolvedName, "PureBatang-Medium")
        for resource in [
            "OFL-Pretendard",
            "OFL-SUIT",
            "OFL-Naver-Nanum-Maru",
            "LICENSE-SunBatang",
        ] {
            XCTAssertNotNil(
                Bundle.main.url(forResource: resource, withExtension: "txt")
            )
        }
        XCTAssertEqual(
            HWPDocumentFontResolver.resolvedName(for: "Times New Roman"),
            "Times New Roman"
        )
    }

    @MainActor
    func testHWP5PropagatesFontMetadataAndCharacterMetrics() throws {
        let document = try HWP5StructuredDocumentParser.parse(
            from: makeHWP5File(
                compressed: true,
                docInfoOverride: makeStructuredHWPDocInfo(
                    fontWidth: 82,
                    letterSpacing: -7,
                    characterPosition: 12,
                    includesFontMetadata: true
                ),
                sectionOverride: makeStructuredHWPSection()
            )
        )
        let run = try XCTUnwrap(document.blocks.first?.presentation.textRuns.first)
        XCTAssertEqual(run.alternateFontName, "AppleSDGothicNeo-Regular")
        XCTAssertEqual(run.baseFontName, "Batang-Regular")
        XCTAssertEqual(run.fontSignature?.bytes.count, 10)
        XCTAssertEqual(run.fontSignature?.prefersSerif, true)
        XCTAssertEqual(run.fontWidthPercent, 82, accuracy: 0.001)
        XCTAssertEqual(run.letterSpacingPercent, -7, accuracy: 0.001)
        XCTAssertEqual(run.baselinePositionPercent, 12, accuracy: 0.001)
        let resolution = HWPDocumentFontResolver.resolution(for: run)
        XCTAssertEqual(resolution.kind, .documentAlternative)
        XCTAssertEqual(resolution.resolvedName, "AppleSDGothicNeo-Regular")
    }

    @MainActor
    func testHWPUserFontImportRegistersFileAliasInsideApp() throws {
        let manager = HWPUserFontManager.shared
        let existing = Set(manager.importedFonts.map(\.url))
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundled = try XCTUnwrap(
            Bundle.main.url(forResource: "Gulim-Regular", withExtension: "ttf")
        )
        let source = root.appendingPathComponent("테스트굴림.ttf")
        try FileManager.default.copyItem(at: bundled, to: source)

        manager.importFonts(from: [source])
        let imported = manager.importedFonts.filter { !existing.contains($0.url) }
        defer {
            for font in imported { manager.remove(font) }
        }

        XCTAssertNil(manager.errorDescription)
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(
            manager.resolvedPostScriptName(for: "테스트굴림"),
            "Gulim-Regular"
        )
        XCTAssertEqual(
            HWPDocumentFontResolver.resolvedName(for: "테스트굴림"),
            "Gulim-Regular"
        )
    }

    func testHWP5RewriterKeepsHWPContainerAndPreservesOtherStreams() throws {
        let untouched = Data((0..<6_000).map { UInt8($0 % 251) })
        let source = try makeHWP5File(
            compressed: true,
            docInfoOverride: makeStructuredHWPDocInfo(),
            sectionOverride: makeStructuredHWPSection(),
            extraStreams: [
                "Extra/Untouched": untouched,
                "PrvText": Data("기존 미리보기".utf16.flatMap {
                    [UInt8($0 & 0xFF), UInt8($0 >> 8)]
                }),
            ]
        )
        let original = try HWP5StructuredDocumentParser.parse(from: source)
        var edited = original.blocks
        edited[0].text = "HWP 그대로 수정\t확인\n둘째 줄 & 완료"

        let output = try HWP5DocumentRewriter.rewrite(
            sourceData: source,
            originalBlocks: original.blocks,
            editedBlocks: edited
        )
        let reloaded = try HWP5StructuredDocumentParser.parse(from: output)
        let sourceContainer = try OLECompoundFile(data: source)
        let container = try OLECompoundFile(data: output)

        XCTAssertEqual(Array(output.prefix(8)), [
            0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1,
        ])
        XCTAssertEqual(reloaded.blocks.first?.text, edited[0].text)
        XCTAssertEqual(reloaded.blocks.first?.presentation.styleName, "제목 1")
        XCTAssertEqual(container.streamNames, sourceContainer.streamNames)
        XCTAssertEqual(container.streamPaths, sourceContainer.streamPaths)
        for path in sourceContainer.streamNames
        where path != "bodytext/section0" && path != "prvtext" {
            XCTAssertEqual(
                try container.stream(named: path),
                try sourceContainer.stream(named: path),
                "보존되어야 하는 OLE stream이 변경됨: \(path)"
            )
        }
        XCTAssertEqual(try container.stream(named: "Extra/Untouched"), untouched)
        XCTAssertEqual(
            String(
                data: try container.stream(named: "PrvText"),
                encoding: .utf16LittleEndian
            ),
            edited[0].text
        )
    }

    func testHWP5RewriterRejectsComplexPictureParagraphEdit() throws {
        let source = try makeHWP5File(
            compressed: true,
            docInfoOverride: makeRichHWPDocInfo(),
            sectionOverride: makeRichHWPSection(),
            extraStreams: ["BinData/BIN0001.png": try richHWPPNG()]
        )
        let original = try HWP5StructuredDocumentParser.parse(from: source)
        let pictureIndex = try XCTUnwrap(
            original.blocks.firstIndex(where: { !$0.images.isEmpty })
        )
        XCTAssertFalse(original.blocks[pictureIndex].isEditable)
        var edited = original.blocks
        edited[pictureIndex].text += "수정"

        XCTAssertThrowsError(
            try HWP5DocumentRewriter.rewrite(
                sourceData: source,
                originalBlocks: original.blocks,
                editedBlocks: edited
            )
        ) {
            XCTAssertEqual($0 as? HWPDocumentEditingError, .unsupportedEdit)
        }
    }

    func testHWP5RewriterRebuildsLineSegmentsAndHeaderCount() throws {
        let source = try makeHWP5File(
            compressed: false,
            docInfoOverride: makeStructuredHWPDocInfo(),
            sectionOverride: makeLineSegmentHWPSection()
        )
        let original = try HWP5StructuredDocumentParser.parse(from: source)
        XCTAssertEqual(original.blocks.first?.lineLayouts.count, 2)
        XCTAssertEqual(original.blocks.first?.lineLayouts.last?.isEmpty, true)

        var edited = original.blocks
        edited[0].text = "첫 줄\n둘째 줄\n셋째 줄"
        let output = try HWP5DocumentRewriter.rewrite(
            sourceData: source,
            originalBlocks: original.blocks,
            editedBlocks: edited
        )
        let reloaded = try HWP5StructuredDocumentParser.parse(from: output)
        let lines = try XCTUnwrap(reloaded.blocks.first?.lineLayouts)

        XCTAssertEqual(reloaded.blocks.first?.text, edited[0].text)
        XCTAssertEqual(lines.map(\.text), ["첫 줄", "둘째 줄", "셋째 줄"])
        XCTAssertEqual(lines.map(\.startCharacter), [0, 4, 9])
        XCTAssertEqual(lines.map(\.verticalPositionPoints), [10, 26, 42])
        XCTAssertEqual(lines.map(\.lineHeightPoints), [16, 16, 16])
        XCTAssertEqual(lines.map(\.columnStartPoints), [0, 5, 5])
        XCTAssertEqual(lines.map(\.startsPage), [true, false, false])
        XCTAssertTrue(lines.allSatisfy { !$0.isEmpty })

        let section = try OLECompoundFile(data: output)
            .stream(named: "bodytext/section0")
        let header = try XCTUnwrap(firstHWPRecordPayload(tag: 0x42, in: section))
        XCTAssertEqual(
            UInt16(header[16]) | UInt16(header[17]) << 8,
            3,
            "PARA_HEADER의 줄 세그먼트 개수가 재생성된 레코드와 일치해야 함"
        )
        XCTAssertEqual(
            UInt32(header[0]) | UInt32(header[1]) << 8
                | UInt32(header[2]) << 16 | UInt32(header[3]) << 24,
            UInt32(edited[0].text.utf16.count + 1)
        )
    }

    func testHWP5SignedDocumentRemainsViewableButReadOnly() throws {
        let source = try makeHWP5File(
            compressed: false,
            properties: 1 << 7,
            docInfoOverride: makeStructuredHWPDocInfo(),
            sectionOverride: makeStructuredHWPSection()
        )
        let document = try HWP5StructuredDocumentParser.parse(from: source)

        XCTAssertFalse(document.allowsEditing)
        XCTAssertTrue(document.blocks.allSatisfy { !$0.isEditable })
        XCTAssertFalse(document.plainText.isEmpty)
    }

    @MainActor
    func testHWPViewModelDefaultsToHWPEditingAndSavesSameFormat() async throws {
        let source = try makeHWP5File(
            compressed: true,
            docInfoOverride: makeStructuredHWPDocInfo(),
            sectionOverride: makeStructuredHWPSection()
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("hwp")
        try source.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let viewModel = HWPDocumentViewModel(fileURL: url)
        await viewModel.load()
        XCTAssertTrue(viewModel.isLegacyDocument)
        XCTAssertTrue(viewModel.isEditableDocument)
        XCTAssertFalse(viewModel.requiresSaveAs)
        XCTAssertEqual(url.pathExtension.lowercased(), "hwp")

        let block = try XCTUnwrap(viewModel.blocks.first)
        viewModel.selectBlock(block.id)
        viewModel.editorText = "뷰 모델 HWP 직접 저장 확인"
        viewModel.commitEditorChange()
        await viewModel.save()

        XCTAssertNil(viewModel.errorDescription)
        XCTAssertFalse(viewModel.hasUnsavedChanges)
        XCTAssertTrue(viewModel.isLegacyDocument)
        let saved = try Data(contentsOf: url)
        XCTAssertEqual(Array(saved.prefix(8)), [
            0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1,
        ])
        XCTAssertEqual(
            try HWP5StructuredDocumentParser.parse(from: saved).blocks.first?.text,
            "뷰 모델 HWP 직접 저장 확인"
        )
    }

    func testHWP5StructuredParserMapsTableCellsAndMergedSpans() throws {
        let document = try HWP5StructuredDocumentParser.parse(
            from: makeHWP5File(
                compressed: true,
                docInfoOverride: makeStructuredHWPDocInfo(),
                sectionOverride: makeStructuredHWPTableSection()
            )
        )

        XCTAssertEqual(document.fidelity, .simplified)
        XCTAssertEqual(document.tableCount, 1)
        XCTAssertEqual(document.tableCellCount, 3)

        let cells = document.blocks.filter { $0.tableLocation != nil }
        XCTAssertEqual(cells.map(\.text), ["병합 제목", "왼쪽", "오른쪽"])
        XCTAssertEqual(cells[0].tableLocation?.row, 0)
        XCTAssertEqual(cells[0].tableLocation?.column, 0)
        XCTAssertEqual(cells[0].tableLocation?.columnSpan, 2)
        XCTAssertEqual(cells[0].tableLocation?.rowSpan, 1)
        XCTAssertEqual(cells[0].tableLocation?.cellWidthPoints, 80)
        XCTAssertEqual(cells[0].tableLocation?.cellHeightPoints, 20)
        XCTAssertEqual(cells[1].tableLocation?.row, 1)
        XCTAssertEqual(cells[1].tableLocation?.column, 0)
        XCTAssertEqual(cells[2].tableLocation?.row, 1)
        XCTAssertEqual(cells[2].tableLocation?.column, 1)
    }

    func testHWP5StructuredParserRendersPageImagesBordersAndNotes() throws {
        let png = try richHWPPNG()
        let document = try HWP5StructuredDocumentParser.parse(
            from: makeHWP5File(
                compressed: true,
                docInfoOverride: makeRichHWPDocInfo(),
                sectionOverride: makeRichHWPSection(),
                extraStreams: ["BinData/BIN0001.png": png]
            )
        )

        XCTAssertEqual(document.imageCount, 1)
        XCTAssertEqual(document.headerCount, 1)
        XCTAssertEqual(document.footerCount, 1)
        XCTAssertEqual(document.footnoteCount, 1)
        XCTAssertEqual(document.endnoteCount, 1)
        XCTAssertEqual(document.complexControlCount, 0)

        let page = try XCTUnwrap(document.pageLayouts.first)
        XCTAssertEqual(page.widthPoints, 595.28, accuracy: 0.001)
        XCTAssertEqual(page.heightPoints, 841.86, accuracy: 0.001)
        XCTAssertEqual(page.leftMarginPoints, 85.04, accuracy: 0.001)
        XCTAssertEqual(page.pageStyle?.backgroundColorRGB, 0x112233)
        XCTAssertEqual(page.footnoteStyle?.startingNumber, 1)
        XCTAssertEqual(page.endnoteStyle?.startingNumber, 1)

        let image = try XCTUnwrap(
            document.blocks.flatMap(\.images).first
        )
        XCTAssertEqual(image.data, png)
        XCTAssertEqual(image.widthPoints, 120, accuracy: 0.001)
        XCTAssertEqual(image.heightPoints, 80, accuracy: 0.001)
        XCTAssertEqual(image.description, "본문 그림")

        XCTAssertEqual(
            document.blocks.first(where: { $0.text == "머리말 내용" })?.region.kind,
            .header
        )
        XCTAssertEqual(
            document.blocks.first(where: { $0.text == "머리말 내용" })?.region.scope,
            .oddPages
        )
        XCTAssertEqual(
            document.blocks.first(where: { $0.text == "꼬리말 내용" })?.region.kind,
            .footer
        )
        XCTAssertEqual(
            document.blocks.first(where: { $0.text == "각주 내용" })?.region.kind,
            .footnote
        )
        XCTAssertEqual(
            document.blocks.first(where: { $0.text == "미주 내용" })?.region.kind,
            .endnote
        )
        let coloredCell = document.blocks.first(where: { $0.text == "색 있는 셀" })?
            .tableLocation?.boxStyle
        XCTAssertEqual(coloredCell?.backgroundColorRGB, 0x112233)
        // BORDER_FILL stores each side as kind, thickness, color. All four
        // sides of the fixture are solid 0.5 mm lines, so the horizontal
        // borders must be visible too.
        for line in [coloredCell?.left, coloredCell?.right, coloredCell?.top, coloredCell?.bottom] {
            XCTAssertEqual(line?.kind, 1)
            XCTAssertEqual(line?.isVisible, true)
            XCTAssertEqual(line?.widthPoints ?? 0, 0.5 * 72 / 25.4, accuracy: 0.01)
        }
    }

    func testHWP5StructuredParserOpensRealInternetFixture() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let workspaceFixture = repositoryRoot
            .appendingPathComponent("outputs", isDirectory: true)
            .appendingPathComponent(
                "internet_hwp_sample_20260831",
                isDirectory: true
            )
            .appendingPathComponent("pyhwp-sample-5017.hwp")
        let deviceFixture = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("pyhwp-sample-5017.hwp")
        let fixture = FileManager.default.fileExists(
            atPath: workspaceFixture.path
        ) ? workspaceFixture : deviceFixture
        guard let fixture,
              FileManager.default.fileExists(atPath: fixture.path) else {
            throw XCTSkip("실제 HWP fixture가 로컬 작업공간에 없습니다.")
        }

        let document = try HWP5StructuredDocumentParser.parse(
            from: Data(contentsOf: fixture)
        )
        XCTAssertFalse(document.blocks.isEmpty)
        XCTAssertFalse(document.plainText.isEmpty)
        XCTAssertGreaterThan(document.fontCount, 0)
        XCTAssertGreaterThan(document.characterShapeCount, 0)
        XCTAssertGreaterThan(document.paragraphShapeCount, 0)
        XCTAssertTrue(
            document.blocks.contains {
                !$0.presentation.textRuns.isEmpty
            }
        )
        XCTAssertTrue(document.plainText.contains("한글 워드 프로세서"))
        XCTAssertFalse(
            document.plainText.unicodeScalars.contains {
                (0xE0BC...0xF8F7).contains($0.value)
            }
        )

        let tableBlocks = document.blocks.filter {
            $0.tableLocation != nil
        }
        XCTAssertEqual(
            tableBlocks.count,
            10,
            tableBlocks.map {
                "\($0.text)|\($0.tableLocation?.table ?? -1):\($0.tableLocation?.row ?? -1):\($0.tableLocation?.column ?? -1):\($0.tableLocation?.paragraph ?? -1)"
            }.joined(separator: ", ")
        )
        XCTAssertEqual(
            Set(tableBlocks.compactMap { $0.tableLocation?.table }),
            [0, 1, 2]
        )
        XCTAssertEqual(
            document.blocks.first(where: { $0.text == "A0" })?
                .tableLocation?.row,
            0
        )
        XCTAssertEqual(
            document.blocks.first(where: { $0.text == "A0" })?
                .tableLocation?.column,
            0
        )
        XCTAssertEqual(
            document.blocks.first(where: { $0.text == "B11" })?
                .tableLocation?.paragraph,
            1
        )
    }

    func testHWP5ValidationCorpusCoversCoordinateLayoutAndRichObjects() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let workspaceDirectory = repositoryRoot
            .appendingPathComponent("outputs", isDirectory: true)
            .appendingPathComponent("hwp_validation_20260901", isDirectory: true)
            .appendingPathComponent("documents", isDirectory: true)
        let deviceDirectory = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first
            .map {
                $0.appendingPathComponent(".HWPValidation", isDirectory: true)
            }
        let directory = FileManager.default.fileExists(
            atPath: workspaceDirectory.path
        ) ? workspaceDirectory : deviceDirectory
        guard let directory,
              FileManager.default.fileExists(atPath: directory.path) else {
            throw XCTSkip("HWP 실문서 검증 corpus가 로컬 작업공간에 없습니다.")
        }

        let fixtures = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter {
            $0.pathExtension.lowercased() == "hwp"
                && $0.lastPathComponent.hasPrefix("V")
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertEqual(fixtures.count, 35)

        var documents: [String: HWP5StructuredDocument] = [:]
        for fixture in fixtures {
            if fixture.lastPathComponent == "V28-encrypted-negative.hwp" {
                XCTAssertThrowsError(
                    try HWP5StructuredDocumentParser.parse(
                        from: Data(contentsOf: fixture)
                    )
                ) {
                    XCTAssertEqual($0 as? ChatAttachmentError, .encryptedHWP)
                }
                continue
            }
            do {
                let document = try HWP5StructuredDocumentParser.parse(
                    from: Data(contentsOf: fixture)
                )
                XCTAssertFalse(
                    document.blocks.isEmpty,
                    "문단 또는 렌더링 개체가 없음: \(fixture.lastPathComponent)"
                )
                documents[fixture.lastPathComponent] = document
            } catch {
                XCTFail("\(fixture.lastPathComponent) 파싱 실패: \(error)")
            }
        }
        XCTAssertEqual(documents.count, 34)

        let coordinateDocument = try XCTUnwrap(documents["V01-aligns.hwp"])
        XCTAssertTrue(
            coordinateDocument.blocks.contains { !$0.lineLayouts.isEmpty }
        )

        let tableDocument = try XCTUnwrap(documents["V04-table-position.hwp"])
        XCTAssertTrue(
            tableDocument.blocks.compactMap(\.tableLocation).contains {
                $0.cellWidthPoints != nil
                    && $0.cellHeightPoints != nil
                    && $0.tablePlacement != nil
            }
        )

        let columnDocument = try XCTUnwrap(documents["V21-columns-2020.hwp"])
        XCTAssertTrue(columnDocument.pageLayouts.contains {
            $0.columnLayout.count > 1
        })

        let textBoxDocument = try XCTUnwrap(documents["V24-textbox-2020.hwp"])
        let textBoxObjects = textBoxDocument.blocks.flatMap(\.canvasObjects)
        XCTAssertTrue(textBoxObjects.contains { $0.textContainerID != nil })
        XCTAssertTrue(textBoxDocument.blocks.contains {
            $0.layoutContainerID != nil && !$0.text.isEmpty
        })

        let equationDocument = try XCTUnwrap(documents["V26-equation-2020.hwp"])
        XCTAssertEqual(equationDocument.equationCount, 1)
        XCTAssertTrue(equationDocument.blocks.flatMap(\.canvasObjects).contains {
            if case .equation(let equation) = $0.content {
                // Public hwplib sample: the binomial identity, verified from
                // its equation record. The former private fixture used x=1.
                return equation.script == "(a+b) ^{2} =a ^{2} +2ab+b ^{2}"
            }
            return false
        })

        let chartDocument = try XCTUnwrap(documents["V27-chart-2020.hwp"])
        XCTAssertEqual(chartDocument.chartCount, 1)
        XCTAssertTrue(chartDocument.blocks.flatMap(\.canvasObjects).contains {
            if case .chart(let chart) = $0.content {
                return chart.series.count == 3
                    && chart.categories.count == 4
                    && chart.hasRenderableData
                    && $0.placement.widthPoints > 300
                    && $0.placement.heightPoints > 180
            }
            return false
        })

        let shapeDocument = try XCTUnwrap(documents["V34-curves.hwp"])
        let shapes = shapeDocument.blocks.flatMap(\.canvasObjects).flatMap {
            switch $0.content {
            case .shape(let shape): return [shape]
            case .group(let shapes): return shapes
            default: return []
            }
        }
        XCTAssertGreaterThanOrEqual(shapeDocument.shapeCount, 2)
        XCTAssertTrue(shapes.contains {
            if case .arc = $0.geometry { return true }
            return false
        })
        XCTAssertTrue(shapes.contains {
            if case .curve = $0.geometry { return true }
            return false
        })
        let curvePoints = shapes.flatMap { shape -> [HWPDocumentPoint] in
            if case .curve(let points, _) = shape.geometry { return points }
            return []
        }
        XCTAssertFalse(curvePoints.isEmpty)
        XCTAssertTrue(curvePoints.allSatisfy {
            abs($0.x) < 1_000 && abs($0.y) < 1_000
        })

        let backgroundDocument = try XCTUnwrap(
            documents["V35-background-page.hwp"]
        )
        let backgroundBlocks = backgroundDocument.blocks.filter {
            $0.region.kind == .background
        }
        XCTAssertFalse(backgroundBlocks.isEmpty)
        XCTAssertTrue(backgroundBlocks.contains { !$0.text.isEmpty })
        XCTAssertTrue(backgroundDocument.pageLayouts.allSatisfy {
            !$0.hidesBackground
        })
    }

    @MainActor
    func testHWPOriginalCanvasRendersRepresentativeIPadSnapshots() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("대표 HWP 화면 캡처는 iPad에서 검증합니다.")
        }
        let directory = try XCTUnwrap(
            FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first
        )
        let fixtureNames = [
            "V02-borderfill.hwp",
            "V05-table.hwp",
            "V07-charstyle.hwp",
            "V24-textbox-2020.hwp",
            "V26-equation-2020.hwp",
            "V27-chart-2020.hwp",
            "V34-curves.hwp",
            "V35-background-page.hwp",
        ]
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first)

        for fixtureName in fixtureNames {
            let fixture = directory.appendingPathComponent(fixtureName)
            guard FileManager.default.fileExists(atPath: fixture.path) else {
                throw XCTSkip("iPad Documents에 \(fixtureName)이 없습니다.")
            }
            let document = try HWP5StructuredDocumentParser.parse(
                from: Data(contentsOf: fixture)
            )
            let page = try XCTUnwrap(
                HWPOriginalCanvasPageBuilder.makePages(
                    blocks: document.blocks,
                    layouts: document.pageLayouts
                ).first
            )
            let image = try XCTUnwrap(
                renderHWPPageSnapshot(page, scene: scene),
                "\(fixtureName) 캔버스 렌더링 실패"
            )
            XCTAssertEqual(
                image.size.width,
                page.layout.widthPoints,
                accuracy: 0.5
            )
            XCTAssertEqual(
                image.size.height,
                page.layout.heightPoints,
                accuracy: 0.5
            )
            if fixtureName == "V27-chart-2020.hwp" {
                XCTAssertGreaterThan(
                    try hwpSnapshotColoredPixelCount(image),
                    100,
                    "차트 데이터가 있어도 지원하지 않는 WMF 미리보기를 선택하면 화면이 비게 됩니다."
                )
            }
            let attachment = XCTAttachment(image: image, quality: .original)
            attachment.name = fixtureName.replacingOccurrences(
                of: ".hwp",
                with: "-iPad.png"
            )
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func hwpSnapshotColoredPixelCount(_ image: UIImage) throws -> Int {
        let source = try XCTUnwrap(image.cgImage)
        let width = 256
        let height = max(1, Int(Double(source.height) / Double(source.width) * Double(width)))
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return stride(from: 0, to: pixels.count, by: 4).reduce(0) { count, offset in
            let components = pixels[offset..<(offset + 3)].map(Int.init)
            return count + ((components.max()! - components.min()!) > 40 ? 1 : 0)
        }
    }

    @MainActor
    func testDownloadedHWPDocumentsRenderIPadDiagnosticSnapshots() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("다운로드 HWP 화면 캡처는 iPad에서 검증합니다.")
        }
        let documentsDirectory = try XCTUnwrap(
            FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first
        )
        let fixtureDirectory = documentsDirectory.appendingPathComponent(
            "한글 문서",
            isDirectory: true
        )
        let fixtureURLs = try FileManager.default.contentsOfDirectory(
            at: fixtureDirectory,
            includingPropertiesForKeys: nil
        )
        .filter {
            $0.pathExtension.lowercased() == "hwp"
                && ("01"..."05").contains(
                    String($0.lastPathComponent.prefix(2))
                )
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertEqual(fixtureURLs.count, 5)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first)

        for fixtureURL in fixtureURLs {
            let sourceData = try Data(contentsOf: fixtureURL)
            let document = try HWP5StructuredDocumentParser.parse(
                from: sourceData
            )
            let pages = HWPOriginalCanvasPageBuilder.makePages(
                blocks: document.blocks,
                layouts: document.pageLayouts
            )
            XCTAssertFalse(document.blocks.isEmpty)
            XCTAssertFalse(pages.isEmpty)
            if fixtureURL.lastPathComponent.hasPrefix("02") {
                let charts = document.blocks.flatMap(\.canvasObjects).compactMap {
                    if case .chart(let chart) = $0.content { return chart }
                    return nil
                }
                XCTAssertTrue(
                    charts.contains { $0.previewMetafile != nil },
                    "레거시 OLE WMF 차트 미리보기를 찾지 못함"
                )
            }
            if fixtureURL.lastPathComponent.hasPrefix("05") {
                XCTAssertEqual(
                    document.blocks.first { $0.text == "응모분야" }?
                        .tableLocation?.row,
                    1,
                    "자동 높이 셀도 다음 바깥 표 행으로 인식해야 함"
                )
                XCTAssertEqual(
                    document.blocks.first { $0.text == "제품명" }?
                        .tableLocation?.row,
                    2,
                    "중첩 표 뒤의 0 높이 셀 소유권을 잃으면 안 됨"
                )
                XCTAssertTrue(document.blocks.contains {
                    $0.tableLocation?.table == 2
                        && $0.tableLocation?.parent?.table == 0
                        && $0.tableLocation?.parent?.row == 1
                        && $0.tableLocation?.parent?.column == 1
                })
                let consentTable = document.blocks.filter {
                    $0.tableLocation?.table == 3
                }
                let tracks = HWPTableTrackLayoutSolver.make(
                    blocks: consentTable,
                    maximumWidth: 480.2
                )
                XCTAssertGreaterThan(
                    tracks.rowHeights.first ?? 0,
                    580,
                    "셀 최소 높이 대신 실제 줄 콘텐츠 높이를 반영해야 함"
                )
            }

            let layoutPreview = document.blocks.prefix(240).enumerated().map {
                index, block in
                let line = block.lineLayouts.first
                let table = block.tableLocation
                let placement = table?.tablePlacement
                let text = block.text
                    .replacingOccurrences(of: "\n", with: "↵")
                    .prefix(72)
                return [
                    "#\(index)",
                    "region=\(block.region.kind)",
                    "container=\(block.layoutContainerID ?? "-")",
                    "line=(count:\(block.lineLayouts.count),x:\(line?.columnStartPoints ?? -1),y:\(line?.verticalPositionPoints ?? -1),lastY:\(block.lineLayouts.last?.verticalPositionPoints ?? -1),w:\(line?.widthPoints ?? -1),h:\(line?.lineHeightPoints ?? -1),page:\(line?.startsPage == true),column:\(line?.startsColumn == true),flags:\(line?.flags ?? 0))",
                    "table=(t:\(table?.table ?? -1),r:\(table?.row ?? -1),c:\(table?.column ?? -1),parent:\(table?.parent?.table ?? -1):\(table?.parent?.row ?? -1):\(table?.parent?.column ?? -1),anchorX:\(table?.tableAnchor?.columnStartPoints ?? -1),anchorY:\(table?.tableAnchor?.verticalPositionPoints ?? -1),placeX:\(placement?.xPoints ?? -1),placeY:\(placement?.yPoints ?? -1),w:\(placement?.widthPoints ?? -1),h:\(placement?.heightPoints ?? -1),inline:\(placement?.isInline == true),hRef:\(placement?.horizontalReference.rawValue ?? -1),vRef:\(placement?.verticalReference.rawValue ?? -1),hAlign:\(placement?.horizontalAlignment.rawValue ?? -1),vAlign:\(placement?.verticalAlignment.rawValue ?? -1),cellW:\(table?.cellWidthPoints ?? -1),cellH:\(table?.cellHeightPoints ?? -1))",
                    "objects=\(block.canvasObjects.count)",
                    "text=\(text)",
                ].joined(separator: " ")
            }.joined(separator: "\n")
            let fontDiagnostics = HWPFontDiagnostic.make(blocks: document.blocks)
            XCTAssertFalse(
                fontDiagnostics.contains { $0.kind == .systemFallback },
                "검증 문서에 iPadOS 기본 글꼴 대체가 남으면 안 됨: \(fixtureURL.lastPathComponent)"
            )
            let fontPreview = fontDiagnostics
                .map { item in
                    let resolved = item.resolvedName ?? "iPadOS 기본"
                    return "\(item.declaredName) => \(resolved) [\(item.kind.rawValue)]"
                }
                .joined(separator: "\n")

            let report = """
                file=\(fixtureURL.lastPathComponent)
                blocks=\(document.blocks.count)
                pages=\(pages.count)
                pageLayouts=\(document.pageLayouts.map { "section=\($0.sectionIndex),content=\($0.widthPoints - $0.leftMarginPoints - $0.rightMarginPoints),columns=\($0.columnLayout.columns.map { "\($0.xPoints):\($0.widthPoints)" }.joined(separator: "|"))" }.joined(separator: ";"))
                tables=\(document.tableCount)
                tableCells=\(document.tableCellCount)
                images=\(document.imageCount)
                shapes=\(document.shapeCount)
                equations=\(document.equationCount)
                charts=\(document.chartCount)
                headers=\(document.headerCount)
                footers=\(document.footerCount)
                footnotes=\(document.footnoteCount)
                endnotes=\(document.endnoteCount)
                \(fixtureURL.lastPathComponent.hasPrefix("02") ? olePresentationDiagnostics(sourceData) : "")

                fonts:
                \(fontPreview)

                page-blocks:
                \(pages.enumerated().map { pageIndex, page in
                    let groups = Dictionary(grouping: page.bodyBlocks.compactMap { block in
                        block.tableLocation.map { location in
                            "t\(location.table)-p\(location.parent?.table ?? -1)"
                        } ?? "paragraph"
                    }, by: { $0 }).map { "\($0.key)=\($0.value.count)" }.sorted().joined(separator: ",")
                    return "page\(pageIndex + 1): \(groups)"
                }.joined(separator: "\n"))

                layout-preview:
                \(layoutPreview)
                """
            let reportAttachment = XCTAttachment(
                data: Data(report.utf8),
                uniformTypeIdentifier: "public.plain-text"
            )
            reportAttachment.name = "\(fixtureURL.deletingPathExtension().lastPathComponent)-diagnostics.txt"
            reportAttachment.lifetime = .keepAlways
            add(reportAttachment)

            for page in pages {
                // The page includes UIKit text views. ImageRenderer alone can
                // omit those views and produce misleading diagnostic images.
                let image = try XCTUnwrap(
                    renderHWPPageSnapshot(page, scene: scene),
                    "\(fixtureURL.lastPathComponent) \(page.pageNumber)쪽 렌더링 실패"
                )
                let attachment = XCTAttachment(
                    image: image,
                    quality: .original
                )
                attachment.name = String(
                    format: "%@-page-%02d.png",
                    fixtureURL.deletingPathExtension().lastPathComponent,
                    page.pageNumber
                )
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    @MainActor
    func testOfficialHWPFullPageCorpusRendersAllPages() throws {
        try validateOfficialHWPFullPageCorpus(
            fixtureSubdirectory: "전체페이지 검증",
            expectedPageCounts: [
                "FP01_kcg_workshop": 28,
                "FP02_mpva_recruitment": 25,
                "FP03_museum_recruitment": 23,
                "FP04_kbiz_notice": 2,
                "FP05_kbiz_application": 3,
            ],
            expectedLandscapePages: [
                "FP01_kcg_workshop": [28],
                "FP02_mpva_recruitment": [18],
                "FP03_museum_recruitment": [],
                "FP04_kbiz_notice": [],
                "FP05_kbiz_application": [],
            ]
        )
    }

    @MainActor
    func testOfficialHWPFullPageCorpusRound2RendersAllPages() throws {
        try validateOfficialHWPFullPageCorpus(
            fixtureSubdirectory: "추가 전체페이지 검증",
            expectedPageCounts: [
                "FP06_gumc_recruitment": 13,
                "FP07_gwe_exam": 27,
                "FP08_gogung_recruitment": 19,
                "FP09_museum_research": 35,
                "FP10_mois_disaster_research": 35,
            ]
        )
    }

    @MainActor
    private func validateOfficialHWPFullPageCorpus(
        fixtureSubdirectory: String,
        expectedPageCounts: [String: Int],
        expectedLandscapePages: [String: [Int]]? = nil
    ) throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("HWP 전체 페이지 기준 비교는 실제 iPad에서 검증합니다.")
        }
        let documentsDirectory = try XCTUnwrap(
            FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first
        )
        let fixtureDirectory = documentsDirectory
            .appendingPathComponent("한글 문서", isDirectory: true)
            .appendingPathComponent(fixtureSubdirectory, isDirectory: true)
        guard FileManager.default.fileExists(atPath: fixtureDirectory.path) else {
            throw XCTSkip(
                "Tools/Documents/run_hwp_fullpage_validation.sh로 기준 문서를 먼저 설치합니다."
            )
        }
        let fixtureURLs = try FileManager.default.contentsOfDirectory(
            at: fixtureDirectory,
            includingPropertiesForKeys: nil
        )
        .filter {
            $0.pathExtension.lowercased() == "hwp"
                && expectedPageCounts[$0.deletingPathExtension().lastPathComponent] != nil
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertEqual(
            fixtureURLs.count,
            expectedPageCounts.count,
            "전체 페이지 검증용 HWP 5종이 모두 필요합니다."
        )
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first
        )

        for fixtureURL in fixtureURLs {
            let fixtureID = fixtureURL.deletingPathExtension().lastPathComponent
            do {
                let sourceData = try Data(contentsOf: fixtureURL)
                let document = try HWP5StructuredDocumentParser.parse(
                    from: sourceData
                )
                let pages = HWPOriginalCanvasPageBuilder.makePages(
                    blocks: document.blocks,
                    layouts: document.pageLayouts
                )
                XCTAssertFalse(document.blocks.isEmpty, "\(fixtureID) 블록 없음")
                XCTAssertEqual(
                    pages.count,
                    expectedPageCounts[fixtureID],
                    "\(fixtureID) 기준 PDF와 페이지 수 불일치"
                )
                if let expectedLandscapePages {
                    XCTAssertEqual(
                        pages.filter { $0.layout.isLandscape }.map(\.pageNumber),
                        expectedLandscapePages[fixtureID],
                        "\(fixtureID) 기준 PDF와 가로 페이지 위치 불일치"
                    )
                }
                XCTAssertTrue(
                    pages.allSatisfy {
                        $0.layout.isLandscape
                            ? $0.layout.widthPoints > $0.layout.heightPoints
                            : $0.layout.widthPoints < $0.layout.heightPoints
                    },
                    "\(fixtureID) PAGE_DEF 방향과 실제 캔버스 크기가 불일치"
                )

                let diagnostics = HWPFontDiagnostic.make(blocks: document.blocks)
                let fallbackFonts = diagnostics.filter {
                    $0.kind == .systemFallback
                }
                let renderedRuns = document.blocks.flatMap(\.lineLayouts)
                    .flatMap(\.textRuns)
                let pageDetails = pages.enumerated().map { pageIndex, page in
                    let first = page.bodyBlocks.first
                    let last = page.bodyBlocks.last
                    let tableDetails = Dictionary(
                        grouping: page.bodyBlocks.compactMap { block in
                            block.tableLocation.map { ($0.table, block) }
                        },
                        by: { $0.0 }
                    ).map { tableID, entries in
                        let blocks = entries.map(\.1)
                        let location = blocks.first?.tableLocation
                        let paragraphRange = blocks.map(\.paragraphIndex)
                        return "t\(tableID)[p\(paragraphRange.min() ?? -1)-\(paragraphRange.max() ?? -1),a=\(location?.tableAnchor?.verticalPositionPoints ?? -1),h=\(location?.tablePlacement?.heightPoints ?? -1)]"
                    }.sorted().joined(separator: ",")
                    return [
                        "page=\(pageIndex + 1)",
                        "blocks=\(page.bodyBlocks.count)",
                        "first=\(first?.paragraphIndex ?? -1):\(first?.text.prefix(24) ?? "")",
                        "firstY=\(first?.tableLocation?.tableAnchor?.verticalPositionPoints ?? first?.lineLayouts.first?.verticalPositionPoints ?? -1)",
                        "last=\(last?.paragraphIndex ?? -1):\(last?.text.prefix(24) ?? "")",
                        "lastY=\(last?.tableLocation?.tableAnchor?.verticalPositionPoints ?? last?.lineLayouts.last?.verticalPositionPoints ?? -1)",
                        "tables=\(tableDetails)",
                    ].joined(separator: " ")
                }.joined(separator: "\n")
                let boundaryCandidates = document.blocks.filter { block in
                    block.region.kind == .body
                        && block.layoutContainerID == nil
                        && (block.presentation.pageBreakBefore
                            || block.lineLayouts.first?.startsPage == true)
                }.map { block in
                    let location = block.tableLocation
                    let line = block.lineLayouts.first
                    return [
                        "p=\(block.paragraphIndex)",
                        "table=\(location?.table ?? -1)",
                        "cell=\(location?.row ?? -1):\(location?.column ?? -1)",
                        "parent=\(location?.parent?.table ?? -1)",
                        "y=\(line?.verticalPositionPoints ?? -1)",
                        "flags=\(line?.flags ?? 0)",
                        "pageBreak=\(block.presentation.pageBreakBefore)",
                        "text=\(block.text.prefix(42))",
                    ].joined(separator: " ")
                }.joined(separator: "\n")
                let summary = """
                    id=\(fixtureID)
                    bytes=\(sourceData.count)
                    expectedPages=\(expectedPageCounts[fixtureID] ?? -1)
                    renderedPages=\(pages.count)
                    pageLayouts=\(document.pageLayouts.map { "s\($0.sectionIndex):\($0.widthPoints)x\($0.heightPoints):landscape=\($0.isLandscape)" }.joined(separator: ","))
                    landscapePages=\(pages.filter { $0.layout.isLandscape }.map(\.pageNumber))
                    blocks=\(document.blocks.count)
                    tables=\(document.tableCount)
                    tableCells=\(document.tableCellCount)
                    images=\(document.imageCount)
                    shapes=\(document.shapeCount)
                    equations=\(document.equationCount)
                    charts=\(document.chartCount)
                    headers=\(document.headerCount)
                    footers=\(document.footerCount)
                    footnotes=\(document.footnoteCount)
                    endnotes=\(document.endnoteCount)
                    textRuns=\(renderedRuns.count)
                    underlinedRuns=\(renderedRuns.filter(\.isUnderlined).count)
                    struckThroughRuns=\(renderedRuns.filter(\.isStruckThrough).count)
                    superscriptRuns=\(renderedRuns.filter(\.isSuperscript).count)
                    subscriptRuns=\(renderedRuns.filter(\.isSubscript).count)
                    systemFallbackFonts=\(fallbackFonts.map(\.declaredName).joined(separator: ","))

                    pageDetails:
                    \(pageDetails)

                    boundaryCandidates:
                    \(boundaryCandidates)
                    """
                let summaryAttachment = XCTAttachment(
                    data: Data(summary.utf8),
                    uniformTypeIdentifier: "public.plain-text"
                )
                summaryAttachment.name = "\(fixtureID)-summary.txt"
                summaryAttachment.lifetime = .keepAlways
                add(summaryAttachment)

                let pageTextPayload: [[String: Any]] = pages.enumerated().map {
                    pageIndex, page in
                    [
                        "page": pageIndex + 1,
                        "text": page.bodyBlocks.map(\.text)
                            .filter { !$0.isEmpty }
                            .joined(separator: "\n"),
                    ]
                }
                let pageTextData = try JSONSerialization.data(
                    withJSONObject: pageTextPayload,
                    options: [.prettyPrinted, .sortedKeys]
                )
                let pageTextAttachment = XCTAttachment(
                    data: pageTextData,
                    uniformTypeIdentifier: "public.json"
                )
                pageTextAttachment.name = "\(fixtureID)-page-text.json"
                pageTextAttachment.lifetime = .keepAlways
                add(pageTextAttachment)

                for (pageIndex, page) in pages.enumerated() {
                    guard let image = renderHWPPageSnapshot(
                        page,
                        scene: scene
                    ) else {
                        XCTFail("\(fixtureID) \(pageIndex + 1)쪽 렌더링 실패")
                        continue
                    }
                    let attachment = XCTAttachment(
                        image: image,
                        quality: .original
                    )
                    attachment.name = String(
                        format: "%@-page-%03d.png",
                        fixtureID,
                        pageIndex + 1
                    )
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            } catch {
                XCTFail("\(fixtureID) 파싱 실패: \(error)")
            }
        }
    }

    @MainActor
    private func renderHWPPageSnapshot(
        _ page: HWPOriginalCanvasPage,
        scene: UIWindowScene
    ) -> UIImage? {
        let bounds = CGRect(
            x: 0,
            y: 0,
            width: page.layout.widthPoints,
            height: page.layout.heightPoints
        )
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let controller = UIHostingController(
            rootView: HWPOriginalCanvasPageView(page: page)
                .frame(width: bounds.width, height: bounds.height)
        )
        // This is a paper snapshot, not a device-screen snapshot. Safe-area
        // insets otherwise translate the entire page differently per host OS.
        controller.safeAreaRegions = []
        let window = UIWindow(windowScene: scene)
        window.frame = bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = bounds
        controller.view.backgroundColor = .white
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
        let image = renderer.image { _ in
            controller.view.drawHierarchy(
                in: bounds,
                afterScreenUpdates: true
            )
        }
        window.isHidden = true
        window.rootViewController = nil
        return image
    }

    @MainActor
    func testOfficialHWPFullPageCorpusPaginationDiagnostics() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("HWP 페이지 경계 진단은 실제 iPad에서 검증합니다.")
        }
        let documentsDirectory = try XCTUnwrap(
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        )
        // TEST_RUNNER_HWP_DIAGNOSTIC_FIXTURES=FP03_museum_recruitment,FP07_gwe_exam
        // selects fixtures from both installed corpus folders.
        let requested = ProcessInfo.processInfo
            .environment["HWP_DIAGNOSTIC_FIXTURES"]?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            ?? ["FP09_museum_research"]
        let corpusRoot = documentsDirectory
            .appendingPathComponent("한글 문서", isDirectory: true)
        let fixtureURLs = try ["전체페이지 검증", "추가 전체페이지 검증"]
            .map { corpusRoot.appendingPathComponent($0, isDirectory: true) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .flatMap {
                try FileManager.default.contentsOfDirectory(
                    at: $0,
                    includingPropertiesForKeys: nil
                )
            }
            .filter {
                $0.pathExtension.lowercased() == "hwp"
                    && requested.contains($0.deletingPathExtension().lastPathComponent)
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertEqual(fixtureURLs.count, requested.count, "요청한 진단 fixture가 기기에 없습니다.")

        for fixtureURL in fixtureURLs {
            let document = try HWP5StructuredDocumentParser.parse(
                from: Data(contentsOf: fixtureURL)
            )
            let layoutDetails = document.pageLayouts.map {
                "layout=\($0.widthPoints):\($0.heightPoints) margins=\($0.leftMarginPoints):\($0.rightMarginPoints):\($0.topMarginPoints):\($0.bottomMarginPoints) headerFooter=\($0.headerMarginPoints):\($0.footerMarginPoints)"
            }.joined(separator: "\n")
            let details = layoutDetails + "\n" + document.blocks.enumerated().map { index, block in
                let location = block.tableLocation
                let placement = location?.tablePlacement
                let line = block.lineLayouts.first
                let lineDetails = block.lineLayouts.map {
                    "\($0.startCharacter):\($0.columnStartPoints):\($0.verticalPositionPoints):\($0.lineHeightPoints):\($0.widthPoints):\($0.baselinePoints):\($0.flags)"
                }.joined(separator: "|")
                let objectDetails = block.canvasObjects.map { object in
                    let placement = object.placement
                    let kind: String
                    switch object.content {
                    case .image: kind = "image"
                    case .shape(let shape): kind = "shape=\(shape)"
                    case .group: kind = "group"
                    case .equation: kind = "equation"
                    case .chart: kind = "chart"
                    case .unsupported: kind = "unsupported"
                    }
                    return "\(kind)[\(placement.xPoints):\(placement.yPoints):\(placement.widthPoints):\(placement.heightPoints),refs=\(placement.horizontalReference.rawValue):\(placement.verticalReference.rawValue),align=\(placement.horizontalAlignment.rawValue):\(placement.verticalAlignment.rawValue),inline=\(placement.isInline)]"
                }.joined(separator: "|")
                let imageDetails = block.images.map {
                    "\($0.id)[\($0.widthPoints):\($0.heightPoints),bytes=\($0.data.count)]"
                }.joined(separator: "|")
                return [
                    "index=\(index)",
                    "p=\(block.paragraphIndex)",
                    "section=\(block.sectionPath)",
                    "region=\(block.region.kind)",
                    "container=\(block.layoutContainerID ?? "-")",
                    "table=\(location?.table ?? -1)",
                    "cell=\(location?.row ?? -1):\(location?.column ?? -1)",
                    "span=\(location?.rowSpan ?? -1):\(location?.columnSpan ?? -1)",
                    "parent=\(location?.parent?.table ?? -1)",
                    "anchorY=\(location?.tableAnchor?.verticalPositionPoints ?? -1)",
                    "place=\(placement?.xPoints ?? -1):\(placement?.yPoints ?? -1):\(placement?.widthPoints ?? -1):\(placement?.heightPoints ?? -1)",
                    "cellSize=\(location?.cellWidthPoints ?? -1):\(location?.cellHeightPoints ?? -1)",
                    "cellMargins=\(location?.cellMarginLeftPoints ?? -1):\(location?.cellMarginRightPoints ?? -1):\(location?.cellMarginTopPoints ?? -1):\(location?.cellMarginBottomPoints ?? -1)",
                    "cellVAlign=\(location?.cellVerticalAlignment.rawValue ?? -1)",
                    "para=\(block.presentation.alignment):\(block.presentation.leftMarginPoints):\(block.presentation.rightMarginPoints):\(block.presentation.firstLineIndentPoints)",
                    "refs=\(placement?.horizontalReference.rawValue ?? -1):\(placement?.verticalReference.rawValue ?? -1)",
                    "inline=\(placement?.isInline == true)",
                    "line=\(line?.columnStartPoints ?? -1):\(line?.verticalPositionPoints ?? -1):\(line?.widthPoints ?? -1):\(line?.lineHeightPoints ?? -1)",
                    "lines=\(lineDetails)",
                    "runs=\(block.presentation.textRuns.map { "\($0.text.prefix(8)):\($0.fontSizePoints ?? 0):\($0.fontName ?? "-")" }.joined(separator: "|"))",
                    "objects=\(objectDetails)",
                    "images=\(imageDetails)",
                    "flags=\(line?.flags ?? 0)",
                    "pageBreak=\(block.presentation.pageBreakBefore)",
                    "text=\(block.text.replacingOccurrences(of: "\n", with: "↵").prefix(70))",
                ].joined(separator: " ")
            }.joined(separator: "\n")
            let attachment = XCTAttachment(
                data: Data(details.utf8),
                uniformTypeIdentifier: "public.plain-text"
            )
            attachment.name = "\(fixtureURL.deletingPathExtension().lastPathComponent)-pagination.txt"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testSelectedOfficialHWPReviewPages() throws {
        let documents = try XCTUnwrap(FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let selections: [(String, Int, [Int])] = [
            ("FP01_kcg_workshop", 28, [9, 10, 12, 13, 14, 20, 26]),
            ("FP02_mpva_recruitment", 25, [1, 6, 15]),
            ("FP03_museum_recruitment", 23, [1, 2]),
        ]
        let sourceHashes = [
            "FP01_kcg_workshop": "21cd106d4953a437f2bc4f32ff0250e3364a01dff84653f7f0c0ac1f9c622762",
            "FP02_mpva_recruitment": "9fb00cca761f25fb0e2c3b3230a1fa1f3bb038e4c517d6ea06f6d0a016cd7ed5",
            "FP03_museum_recruitment": "499515b2598028a7155e877f0aeb0aca1843199ed287d919b7e25b55408d11b4",
        ]
        for (name, count, selected) in selections {
            let url = documents.appendingPathComponent("한글 문서/전체페이지 검증/\(name).hwp")
            let data = try Data(contentsOf: url)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(digest, sourceHashes[name], "화면 기준과 같은 원본 파일이어야 합니다.")
            let document = try HWP5StructuredDocumentParser.parse(from: data)
            let pages = HWPOriginalCanvasPageBuilder.makePages(blocks: document.blocks, layouts: document.pageLayouts)
            XCTAssertEqual(pages.count, count, name)
            func paragraph(_ index: Int) throws -> HWPDocumentBlock {
                try XCTUnwrap(document.blocks.first { $0.paragraphIndex == index })
            }
            switch name {
            case "FP01_kcg_workshop":
                let homeShape = try XCTUnwrap(document.blocks.flatMap(\.canvasObjects).compactMap { object -> HWPDocumentShape? in
                    if case .shape(let shape) = object.content, shape.shadow != nil { return shape }
                    return nil
                }.first)
                let shadow = try XCTUnwrap(homeShape.shadow)
                XCTAssertEqual(shadow.kind, 4)
                XCTAssertEqual(shadow.colorRGB, 0xB2B2B2)
                XCTAssertEqual(shadow.offset.width, 2.83, accuracy: 0.01)
                XCTAssertEqual(shadow.offset.height, 2.83, accuracy: 0.01)
                for index in [309, 353, 488] {
                    let owner = try paragraph(index)
                    let titles = owner.canvasObjects.filter { $0.placement.isInline }
                    XCTAssertEqual(titles.count, 2, "두 제목 도형은 같은 본문 문단에 속합니다.")
                    XCTAssertGreaterThan(try XCTUnwrap(titles.last).placement.inlineLeadingPoints,
                        try XCTUnwrap(titles.first).placement.widthPoints)
                }
                let tracks = HWPTableTrackLayoutSolver.make(blocks: document.blocks.filter {
                    $0.tableLocation?.table == 22
                })
                XCTAssertEqual(tracks.columnWidths.prefix(2).reduce(0, +), 75.83, accuracy: 0.03)
                XCTAssertEqual(tracks.columnWidths.prefix(3).reduce(0, +), 118.08, accuracy: 0.03)
                let box = HWPTableTrackLayoutSolver.make(blocks: document.blocks.filter {
                    $0.tableLocation?.table == 20
                })
                XCTAssertEqual(box.size.height, 239.05, accuracy: 0.05)
                XCTAssertNotNil(try paragraph(491).presentation.paragraphBorder)
                XCTAssertTrue(try paragraph(499).presentation.textRuns.contains { $0.backgroundColorRGB == 0xFFFF00 })
                // The PDF also highlights the following paragraph, but the HWP
                // explicitly resets it to unshaded character shape 4.
                XCTAssertTrue(try paragraph(500).presentation.textRuns.allSatisfy { $0.backgroundColorRGB == nil })
                let line = try XCTUnwrap(pages[25].bodyBlocks.flatMap(\.lineLayouts).first {
                    $0.text.contains("최종합격자 발표일로부터 5년")
                })
                XCTAssertEqual(line.endsParagraph, true, "강제 줄바꿈의 마지막 줄은 양쪽으로 늘리지 않습니다.")
            case "FP02_mpva_recruitment":
                XCTAssertEqual(try paragraph(13).canvasObjects.count, 1)
                let anchor = try XCTUnwrap(document.blocks.first {
                    $0.tableLocation?.table == 1
                }?.tableLocation?.tableAnchor)
                XCTAssertEqual(anchor.verticalPositionPoints, 267.95, accuracy: 0.02)
                let picture = try XCTUnwrap(try paragraph(179).canvasObjects.first)
                guard case .image(let image) = picture.content else { return XCTFail("신고 안내 그림") }
                XCTAssertEqual(try XCTUnwrap(image.cropRect).width, 1, accuracy: 0.001)
                XCTAssertEqual(try XCTUnwrap(image.cropRect).height, 1, accuracy: 0.001)
                for index in [569, 581] {
                    let owner = try paragraph(index)
                    let line = try XCTUnwrap(owner.canvasObjects.first)
                    XCTAssertLessThanOrEqual(line.placement.heightPoints, 1)
                    XCTAssertGreaterThan(line.placement.inlineBaselineOffset(in: owner.lineLayouts.first), 7)
                }
            case "FP03_museum_recruitment":
                let group = try XCTUnwrap(try paragraph(2).canvasObjects.first)
                XCTAssertEqual(group.placement.widthPoints, 475.46, accuracy: 0.01)
                XCTAssertEqual(group.placement.heightPoints, 71, accuracy: 0.01)
                XCTAssertNotNil(group.groupedTextFrame)
                XCTAssertLessThan(try XCTUnwrap(group.groupedTextFrame).height, group.placement.heightPoints)
            default: break
            }
            for number in selected {
                let page = try XCTUnwrap(pages.indices.contains(number - 1) ? pages[number - 1] : nil)
                let image = try XCTUnwrap(renderHWPPageSnapshot(page, scene: scene))
                let attachment = XCTAttachment(image: image)
                attachment.name = String(format: "%@-page-%03d", name, number)
                attachment.lifetime = .keepAlways
                add(attachment)
                let detail = page.bodyBlocks.map {
                    "p=\($0.paragraphIndex) table=\($0.tableLocation?.table ?? -1) text=\($0.text.prefix(40))"
                }.joined(separator: "\n")
                let metadata = XCTAttachment(data: Data(detail.utf8), uniformTypeIdentifier: "public.plain-text")
                metadata.name = String(format: "%@-page-%03d-blocks", name, number)
                metadata.lifetime = .keepAlways
                add(metadata)
            }
        }
    }

    @MainActor
    func testCoastGuardFirstFivePagesPreserveSourceLayout() throws {
        let documents = try XCTUnwrap(FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first)
        let url = documents.appendingPathComponent(
            "한글 문서/전체페이지 검증/FP01_kcg_workshop.hwp"
        )
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("공식 FP01 HWP 비교 자료가 필요합니다.")
        }
        let document = try HWP5StructuredDocumentParser.parse(from: Data(contentsOf: url))
        let shape = try XCTUnwrap(document.blocks.flatMap(\.canvasObjects).compactMap {
            if case .shape(let shape) = $0.content { return shape }
            return nil
        }.first)
        guard case .rectangle(let radius, let points) = shape.geometry else {
            return XCTFail("공고 제목은 둥근 사각형입니다.")
        }
        XCTAssertEqual(radius, 50)
        XCTAssertEqual(points, [
            HWPDocumentPoint(x: 0, y: 0), HWPDocumentPoint(x: 367.15, y: 0),
            HWPDocumentPoint(x: 367.15, y: 32.66), HWPDocumentPoint(x: 0, y: 32.66),
        ])
        XCTAssertEqual(shape.fill.colorRGB, 0x7A7CC4)
        XCTAssertEqual(shape.stroke.widthPoints, 0.56, accuracy: 0.001)
        XCTAssertEqual(shape.stroke.style, 1)

        let title = try XCTUnwrap(document.blocks.first { $0.text.contains("경력경쟁채용시험 3차 공고") })
        XCTAssertNil(title.tableLocation,
            "표 셀 안 글상자의 문단이 바깥 표 셀로 분류되면 글상자에서 사라집니다.")
        XCTAssertEqual(title.lineLayouts.first?.baselineAlignment, .center)
        let titleObject = try XCTUnwrap(document.blocks.flatMap(\.canvasObjects).first)
        XCTAssertEqual(titleObject.textContainerLayout?.left, 2.83)
        XCTAssertEqual(titleObject.textContainerLayout?.verticalAlignment, .center)
        let heading = try XCTUnwrap(document.blocks.first { $0.text == "임용예정직무" }?.tableLocation)
        let duties = try XCTUnwrap(document.blocks.first { $0.text == "채용분야" }?.tableLocation)
        XCTAssertEqual(try XCTUnwrap(heading.tableAnchor).verticalPositionPoints, 382.22, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(duties.tableAnchor).verticalPositionPoints, 420.74, accuracy: 0.01)
        let zone = try XCTUnwrap(heading.backgroundZones.first)
        XCTAssertEqual(zone.startColumn, 0)
        XCTAssertEqual(zone.endColumn, 1)
        XCTAssertEqual(zone.endRow, 0)
        XCTAssertNotNil(zone.style.backgroundImage)
        XCTAssertEqual(zone.style.backgroundImageFillMode, 5)
        XCTAssertEqual(duties.cellMarginLeftPoints, 2.83, accuracy: 0.01)
        XCTAssertEqual(document.pageLayouts.first?.pageNumberStyle?.text(pageNumber: 1, sectionPageIndex: 0), "- 1 -")

        let consideration = try XCTUnwrap(document.blocks.first { $0.text == "[응시자격요건 고려사항]" })
        let considerationTable = try XCTUnwrap(consideration.tableLocation?.table)
        let tracks = HWPTableTrackLayoutSolver.make(blocks: document.blocks.filter {
            $0.tableLocation?.table == considerationTable
        })
        XCTAssertEqual(tracks.rowHeights.prefix(2).reduce(0, +), 16.64, accuracy: 0.02,
            "3pt 빈 줄이 제목 칸을 늘리면 안 됩니다.")
        XCTAssertEqual(tracks.size.height, 294.78, accuracy: 0.05)
        let scores = try XCTUnwrap(document.blocks.first { $0.text == "시험종류" })
        XCTAssertEqual(scores.tableLocation?.tableAnchor?.paragraphAlignment, .centered)
        let bullet = try XCTUnwrap(document.blocks.first { $0.text.hasPrefix("국가공무원법 33조") })
        XCTAssertEqual(bullet.lineLayouts.first?.listMarker?.run.text, "●")
        XCTAssertEqual(bullet.lineLayouts.first?.listMarker?.run.textColorRGB, 0x667DBA)
        XCTAssertEqual(bullet.lineLayouts.first?.listMarker?.reservedWidthPoints, 13)
        XCTAssertEqual(bullet.lineLayouts.last?.showsListMarker, false)
        let hanging = try XCTUnwrap(document.blocks.first { $0.paragraphIndex == 75 })
        XCTAssertEqual(try XCTUnwrap(hanging.lineLayouts.last).textInsetPoints, 22.48, accuracy: 0.01)
        let tabbed = try XCTUnwrap(document.blocks.first { $0.paragraphIndex == 58 })
        XCTAssertEqual(tabbed.lineLayouts.first?.textRuns.first?.tabWidthPoints, 14.23)
        XCTAssertTrue(bullet.presentation.textRuns.contains { $0.spaceWidthPoints == 7 })
        XCTAssertEqual(HWPDocumentFontResolver.resolvedName(for: "한컴바탕"), "Batang-Regular")

        let pages = HWPOriginalCanvasPageBuilder.makePages(
            blocks: document.blocks, layouts: document.pageLayouts
        )
        XCTAssertEqual(pages.count, 28, "같은 문단의 두 번째 표 앞에 빈 페이지가 생기면 안 됩니다.")
        let continuing = try XCTUnwrap(pages[4].bodyBlocks.first { $0.paragraphIndex == 150 })
        XCTAssertEqual(continuing.lineLayouts.first?.showsListMarker, false,
            "4쪽에서 이어지는 문장에 글머리표를 반복하면 안 됩니다.")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for (index, page) in pages.prefix(5).enumerated() {
            let image = try XCTUnwrap(renderHWPPageSnapshot(page, scene: scene))
            let attachment = XCTAttachment(image: image)
            attachment.name = String(format: "FP01_kcg_workshop-page-%03d", index + 1)
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testDownloadedHWPDocumentsOpenActualViewerModes() async throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("다운로드 HWP 실제 뷰어 캡처는 iPad에서 검증합니다.")
        }
        let documentsDirectory = try XCTUnwrap(
            FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first
        )
        let fixtureDirectory = documentsDirectory.appendingPathComponent(
            "한글 문서",
            isDirectory: true
        )
        let fixtureURLs = try FileManager.default.contentsOfDirectory(
            at: fixtureDirectory,
            includingPropertiesForKeys: nil
        )
        .filter {
            $0.pathExtension.lowercased() == "hwp"
                && ("01"..."05").contains(
                    String($0.lastPathComponent.prefix(2))
                )
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertEqual(fixtureURLs.count, 5)
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first
        )

        for fixtureURL in fixtureURLs {
            let window = UIWindow(windowScene: scene)
            window.frame = scene.screen.bounds
            window.rootViewController = UIHostingController(
                rootView: NavigationStack {
                    HWPDocumentView(fileURL: fixtureURL)
                }
            )
            window.makeKeyAndVisible()
            defer { window.isHidden = true }

            var segmentedControl: UISegmentedControl?
            for _ in 0..<80 where segmentedControl == nil {
                try await Task.sleep(for: .milliseconds(50))
                window.layoutIfNeeded()
                segmentedControl = firstSubview(
                    of: UISegmentedControl.self,
                    in: window
                )
            }
            let picker = try XCTUnwrap(
                segmentedControl,
                "\(fixtureURL.lastPathComponent) 보기 방식 선택기가 나타나지 않음"
            )
            XCTAssertEqual(picker.numberOfSegments, 2)

            picker.selectedSegmentIndex = 1
            picker.sendActions(for: .valueChanged)
            try await Task.sleep(for: .milliseconds(150))
            attachViewerScreenshot(
                window,
                name: "\(fixtureURL.deletingPathExtension().lastPathComponent)-actual-original.png"
            )

            picker.selectedSegmentIndex = 0
            picker.sendActions(for: .valueChanged)
            try await Task.sleep(for: .milliseconds(150))
            attachViewerScreenshot(
                window,
                name: "\(fixtureURL.deletingPathExtension().lastPathComponent)-actual-accessible.png"
            )
        }
    }

    private func firstSubview<T: UIView>(
        of type: T.Type,
        in view: UIView
    ) -> T? {
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let match = firstSubview(of: type, in: subview) {
                return match
            }
        }
        return nil
    }

    private func olePresentationDiagnostics(_ sourceData: Data) -> String {
        guard let outer = try? OLECompoundFile(data: sourceData) else { return "" }
        let signature = Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])
        var lines: [String] = []
        for name in outer.streamNames where name.lowercased().hasSuffix(".ole") {
            guard let stored = try? outer.stream(named: name) else { continue }
            let inflated = try? HWP5TextExtractor.inflateRawDeflate(
                stored,
                maximumBytes: HWP5TextExtractor.maximumSectionBytes
            )
            let candidates = [stored, inflated].compactMap { $0 }
            guard let containerData = candidates.compactMap({ candidate -> Data? in
                guard let range = candidate.range(of: signature),
                      range.lowerBound <= 64 else { return nil }
                return Data(candidate[range.lowerBound...])
            }).first,
                  let inner = try? OLECompoundFile(data: containerData) else { continue }
            for streamName in inner.streamNames where streamName.contains("olepres") {
                guard let presentation = try? inner.stream(named: streamName) else {
                    continue
                }
                let prefix = presentation.prefix(64).map {
                    String(format: "%02X", $0)
                }.joined(separator: " ")
                lines.append(
                    "ole=\(name),stream=\(streamName),bytes=\(presentation.count),prefix=\(prefix)"
                )
                if presentation.count > 58,
                   presentation[4] == 3,
                   presentation[40] == 1,
                   presentation[42] == 9 {
                    var cursor = 58
                    var functions: [UInt16: Int] = [:]
                    while cursor + 6 <= presentation.count {
                        let words = Int(UInt32(presentation[cursor])
                            | UInt32(presentation[cursor + 1]) << 8
                            | UInt32(presentation[cursor + 2]) << 16
                            | UInt32(presentation[cursor + 3]) << 24)
                        let function = UInt16(presentation[cursor + 4])
                            | UInt16(presentation[cursor + 5]) << 8
                        guard words >= 3,
                              words <= 1_048_576,
                              cursor + words * 2 <= presentation.count else { break }
                        functions[function, default: 0] += 1
                        cursor += words * 2
                        if function == 0 { break }
                    }
                    lines.append(
                        "wmf-functions=" + functions.sorted { $0.key < $1.key }.map {
                            String(format: "%04X:%d", $0.key, $0.value)
                        }.joined(separator: ",")
                    )
                }
            }
        }
        return lines.isEmpty ? "ole-presentations=none" : lines.joined(separator: "\n")
    }

    @MainActor
    private func attachViewerScreenshot(_ window: UIWindow, name: String) {
        window.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            bounds: window.bounds,
            format: format
        )
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image, quality: .original)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testHWP5NormalizesHanyangPrivateUseHangul() {
        XCTAssertEqual(
            HanyangPUANormalizer.normalize("\u{F53A}글"),
            "한글"
        )
        XCTAssertEqual(
            HanyangPUANormalizer.normalize("현대 한글"),
            "현대 한글"
        )
    }

    func testHWP5RewriterEditsRealInternetFixtureWithoutConverting() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let workspaceFixture = repositoryRoot
            .appendingPathComponent("outputs", isDirectory: true)
            .appendingPathComponent("internet_hwp_sample_20260831", isDirectory: true)
            .appendingPathComponent("pyhwp-sample-5017.hwp")
        let deviceFixture = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("pyhwp-sample-5017.hwp")
        let fixture = FileManager.default.fileExists(atPath: workspaceFixture.path)
            ? workspaceFixture
            : deviceFixture
        guard let fixture,
              FileManager.default.fileExists(atPath: fixture.path) else {
            throw XCTSkip("실제 HWP fixture가 로컬 작업공간에 없습니다.")
        }

        let source = try Data(contentsOf: fixture)
        let original = try HWP5StructuredDocumentParser.parse(from: source)
        let index = try XCTUnwrap(
            original.blocks.firstIndex(where: { $0.isEditable && !$0.text.isEmpty })
        )
        var edited = original.blocks
        edited[index].text += " · RivoPad HWP 원본 편집 확인"

        let output = try HWP5DocumentRewriter.rewrite(
            sourceData: source,
            originalBlocks: original.blocks,
            editedBlocks: edited
        )
        let reloaded = try HWP5StructuredDocumentParser.parse(from: output)

        XCTAssertEqual(reloaded.blocks[index].text, edited[index].text)
        XCTAssertEqual(reloaded.tableCount, original.tableCount)
        XCTAssertEqual(reloaded.imageCount, original.imageCount)
        XCTAssertEqual(reloaded.headerCount, original.headerCount)
        XCTAssertEqual(reloaded.footnoteCount, original.footnoteCount)
        XCTAssertFalse(output.starts(with: [0x50, 0x4B]))
        XCTAssertEqual(Array(output.prefix(8)), [
            0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1,
        ])
    }

    func testHWP5RejectsProtectedAndMalformedDocuments()
        throws
    {
        let protected = try makeHWP5File(
            compressed: false,
            properties: 1 << 2
        )
        XCTAssertThrowsError(
            try HWP5TextExtractor.extract(
                from: protected
            )
        ) {
            XCTAssertEqual(
                $0 as? ChatAttachmentError,
                .encryptedHWP
            )
        }

        var malformedBody = Data()
        malformedBody.testAppendUInt32(
            UInt32(10 << 20) | 0x43
        )
        malformedBody.append(
            Data(repeating: 0, count: 2)
        )
        let malformed =
            try makeHWP5File(
                compressed: false,
                sectionOverride:
                    malformedBody
            )
        XCTAssertThrowsError(
            try HWP5TextExtractor.extract(
                from: malformed
            )
        ) {
            XCTAssertEqual(
                $0 as? ChatAttachmentError,
                .invalidHWP
            )
        }
    }

    func testHWP5AcceptsModernEncryptionAlgorithmMarkerWithoutProtection()
        throws
    {
        let source = try makeHWP5File(
            compressed: false,
            encryptionVersion: 4,
            docInfoOverride: makeStructuredHWPDocInfo(),
            sectionOverride: makeStructuredHWPSection()
        )

        XCTAssertFalse(
            try HWP5TextExtractor.extract(from: source)
                .isEmpty
        )
        XCTAssertFalse(
            try HWP5StructuredDocumentParser.parse(from: source)
                .blocks
                .isEmpty
        )

        let original = try HWP5StructuredDocumentParser.parse(from: source)
        let editableIndex = try XCTUnwrap(
            original.blocks.firstIndex(where: \.isEditable)
        )
        var edited = original.blocks
        edited[editableIndex].text += " 최신 HWP 저장 확인"
        let rewritten = try HWP5DocumentRewriter.rewrite(
            sourceData: source,
            originalBlocks: original.blocks,
            editedBlocks: edited
        )
        XCTAssertEqual(
            try HWP5StructuredDocumentParser.parse(from: rewritten)
                .blocks[editableIndex]
                .text,
            edited[editableIndex].text
        )
    }

    func testHWP5AcceptsOnlyValidatedCompressionTrailer()
        throws
    {
        let valid = try makeHWP5File(
            compressed: true,
            includesCompressionTrailer: true
        )
        XCTAssertTrue(
            try HWP5TextExtractor.extract(
                from: valid
            ).contains("첫 문단")
        )

        let validLegacy = try makeHWP5File(
            compressed: true,
            includesCompressionTrailer: true,
            usesZeroCompressionChecksumTrailer: true
        )
        XCTAssertTrue(
            try HWP5TextExtractor.extract(
                from: validLegacy
            ).contains("첫 문단")
        )

        let invalid = try makeHWP5File(
            compressed: true,
            includesCompressionTrailer: true,
            corruptsCompressionTrailer: true
        )
        XCTAssertThrowsError(
            try HWP5TextExtractor.extract(
                from: invalid
            )
        ) {
            XCTAssertEqual(
                $0 as? ChatAttachmentError,
                .invalidHWP
            )
        }
    }

    @MainActor
    func testVisionLinkLocallyExtractsLegacyXLSAndHWP()
        async throws
    {
        let root = try makeTemporaryRoot()
        defer {
            try? FileManager.default
                .removeItem(at: root)
        }
        let xlsURL = root
            .appendingPathComponent(
                "remote.xls"
            )
        try makeOLEFile(
            streams: [
                "Workbook":
                    try makeLegacyXLSWorkbook(),
            ]
        ).write(to: xlsURL)
        let hwpURL = root
            .appendingPathComponent(
                "remote.hwp"
            )
        try makeHWP5File(
            compressed: true
        ).write(to: hwpURL)

        let service =
            VisionLinkLocalRemoteChatService
            .shared
        let spreadsheet =
            try await service.extractDocumentText(
                at: xlsURL,
                mimeType:
                    "application/vnd.ms-excel"
            )
        let hwp =
            try await service.extractDocumentText(
                at: hwpURL,
                mimeType:
                    "application/x-hwp"
            )

        XCTAssertTrue(
            spreadsheet.contains(
                "제품\t수량\t활성"
            )
        )
        XCTAssertTrue(
            spreadsheet.contains(
                "사과\t12.0\ttrue"
            )
        )
        XCTAssertTrue(
            hwp.contains(
                "첫 문단\t탭 뒤"
            )
        )
        XCTAssertTrue(
            hwp.contains(
                "둘째 문단-끝"
            )
        )
    }

    private func makeTemporaryRoot()
        throws -> URL
    {
        let root = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "RivoLegacyAttachmentTests-"
                    + UUID().uuidString,
                isDirectory: true
            )
        try FileManager.default
            .createDirectory(
                at: root,
                withIntermediateDirectories:
                    true
            )
        return root
    }

    private func makeLegacyXLSWorkbook(
        includesFilePass: Bool = false
    ) throws -> Data {
        let longString =
            "긴 문자열 시작 "
            + String(
                repeating: "가나다라마바사 ",
                count: 1_100
            )
            + " 긴 문자열 끝"
        let sharedStrings = [
            "제품",
            "수량",
            "활성",
            "사과",
            "계산됨",
            longString,
        ]
        let sstRecords = try makeSSTRecords(
            sharedStrings
        )
        let sheet1 = makeBIFFSheet1()
        let sheet2 = makeBIFFSheet2()

        let globalBOF = biffRecord(
            0x0809,
            payload:
                makeBOFPayload(type: 0x0005)
        )
        let filePass = includesFilePass
            ? biffRecord(
                0x002F,
                payload: Data([0, 0])
            )
            : Data()
        let placeholder1 =
            makeBoundSheetRecord(
                offset: 0,
                name: "매출"
            )
        let placeholder2 =
            makeBoundSheetRecord(
                offset: 0,
                name: "메모"
            )
        let eof = biffRecord(
            0x000A,
            payload: Data()
        )
        let globalLength =
            globalBOF.count
            + filePass.count
            + placeholder1.count
            + placeholder2.count
            + sstRecords.count
            + eof.count
        let sheet1Offset = globalLength
        let sheet2Offset =
            sheet1Offset + sheet1.count

        var workbook = Data()
        workbook.append(globalBOF)
        workbook.append(filePass)
        workbook.append(
            makeBoundSheetRecord(
                offset: sheet1Offset,
                name: "매출"
            )
        )
        workbook.append(
            makeBoundSheetRecord(
                offset: sheet2Offset,
                name: "메모"
            )
        )
        workbook.append(sstRecords)
        workbook.append(eof)
        workbook.append(sheet1)
        workbook.append(sheet2)
        return workbook
    }

    private func makeSSTRecords(
        _ strings: [String]
    ) throws -> Data {
        var logical = Data()
        logical.testAppendUInt32(
            UInt32(strings.count)
        )
        logical.testAppendUInt32(
            UInt32(strings.count)
        )
        for string in strings {
            let units = Array(
                string.utf16
            )
            logical.testAppendUInt16(
                UInt16(units.count)
            )
            logical.append(1)
            for unit in units {
                logical.testAppendUInt16(
                    unit
                )
            }
        }

        // Split only within the final UTF-16 string and prepend the required
        // continuation encoding byte.
        let split = 8_222
        XCTAssertGreaterThan(
            logical.count,
            split
        )
        var result = biffRecord(
            0x00FC,
            payload: logical.subdata(
                in: 0..<split
            )
        )
        var cursor = split
        while cursor < logical.count {
            let end = min(
                logical.count,
                cursor + 8_222
            )
            var continuation = Data([1])
            continuation.append(
                logical.subdata(
                    in: cursor..<end
                )
            )
            result.append(
                biffRecord(
                    0x003C,
                    payload: continuation
                )
            )
            cursor = end
        }
        return result
    }

    private func makeBIFFSheet1() -> Data {
        var sheet = biffRecord(
            0x0809,
            payload:
                makeBOFPayload(type: 0x0010)
        )
        sheet.append(
            labelSST(
                row: 0,
                column: 0,
                index: 0
            )
        )
        sheet.append(
            labelSST(
                row: 0,
                column: 1,
                index: 1
            )
        )
        sheet.append(
            labelSST(
                row: 0,
                column: 2,
                index: 2
            )
        )
        sheet.append(
            labelSST(
                row: 1,
                column: 0,
                index: 3
            )
        )
        var number = cellHeader(
            row: 1,
            column: 1
        )
        number.testAppendDouble(12)
        sheet.append(
            biffRecord(
                0x0203,
                payload: number
            )
        )
        var boolean = cellHeader(
            row: 1,
            column: 2
        )
        boolean.append(contentsOf: [1, 0])
        sheet.append(
            biffRecord(
                0x0205,
                payload: boolean
            )
        )
        sheet.append(
            formulaRecord(
                row: 2,
                column: 0,
                numericValue: 3.5
            )
        )
        sheet.append(
            formulaStringRecord(
                row: 2,
                column: 1,
                string: "계산됨"
            )
        )
        sheet.append(
            biffRecord(
                0x000A,
                payload: Data()
            )
        )
        return sheet
    }

    private func makeBIFFSheet2() -> Data {
        var sheet = biffRecord(
            0x0809,
            payload:
                makeBOFPayload(type: 0x0010)
        )
        sheet.append(
            labelSST(
                row: 0,
                column: 0,
                index: 5
            )
        )
        sheet.append(
            biffRecord(
                0x000A,
                payload: Data()
            )
        )
        return sheet
    }

    private func makeBOFPayload(
        type: UInt16
    ) -> Data {
        var payload = Data()
        payload.testAppendUInt16(0x0600)
        payload.testAppendUInt16(type)
        payload.testAppendUInt16(0x0DBB)
        payload.testAppendUInt16(0x07CC)
        payload.testAppendUInt32(0x0000_0041)
        payload.testAppendUInt32(0x0000_0006)
        return payload
    }

    private func makeBoundSheetRecord(
        offset: Int,
        name: String
    ) -> Data {
        let units = Array(name.utf16)
        var payload = Data()
        payload.testAppendUInt32(
            UInt32(offset)
        )
        payload.append(contentsOf: [
            0, 0,
            UInt8(units.count),
            1,
        ])
        for unit in units {
            payload.testAppendUInt16(unit)
        }
        return biffRecord(
            0x0085,
            payload: payload
        )
    }

    private func labelSST(
        row: UInt16,
        column: UInt16,
        index: UInt32
    ) -> Data {
        var payload = cellHeader(
            row: row,
            column: column
        )
        payload.testAppendUInt32(index)
        return biffRecord(
            0x00FD,
            payload: payload
        )
    }

    private func cellHeader(
        row: UInt16,
        column: UInt16
    ) -> Data {
        var payload = Data()
        payload.testAppendUInt16(row)
        payload.testAppendUInt16(column)
        payload.testAppendUInt16(0)
        return payload
    }

    private func formulaRecord(
        row: UInt16,
        column: UInt16,
        numericValue: Double
    ) -> Data {
        var payload = cellHeader(
            row: row,
            column: column
        )
        payload.testAppendDouble(
            numericValue
        )
        payload.append(
            Data(repeating: 0, count: 8)
        )
        return biffRecord(
            0x0006,
            payload: payload
        )
    }

    private func formulaStringRecord(
        row: UInt16,
        column: UInt16,
        string: String
    ) -> Data {
        var payload = cellHeader(
            row: row,
            column: column
        )
        payload.append(
            contentsOf: [
                0, 0, 0, 0,
                0, 0, 0xFF, 0xFF,
            ]
        )
        payload.append(
            Data(repeating: 0, count: 8)
        )
        var result = biffRecord(
            0x0006,
            payload: payload
        )
        let units = Array(string.utf16)
        var stringPayload = Data()
        stringPayload.testAppendUInt16(
            UInt16(units.count)
        )
        stringPayload.append(1)
        for unit in units {
            stringPayload
                .testAppendUInt16(unit)
        }
        result.append(
            biffRecord(
                0x0207,
                payload: stringPayload
            )
        )
        return result
    }

    private func biffRecord(
        _ id: UInt16,
        payload: Data
    ) -> Data {
        var record = Data()
        record.testAppendUInt16(id)
        record.testAppendUInt16(
            UInt16(payload.count)
        )
        record.append(payload)
        return record
    }

    private func makeHWP5File(
        compressed: Bool,
        properties rawProperties:
            UInt32 = 0,
        encryptionVersion:
            UInt32 = 0,
        docInfoOverride: Data? = nil,
        sectionOverride: Data? = nil,
        extraStreams: [String: Data] = [:],
        includesCompressionTrailer:
            Bool = false,
        usesZeroCompressionChecksumTrailer:
            Bool = false,
        corruptsCompressionTrailer:
            Bool = false
    ) throws -> Data {
        var header = Data(
            repeating: 0,
            count: 256
        )
        header.replaceSubrange(
            0..<17,
            with: Data(
                "HWP Document File".utf8
            )
        )
        header.testSetUInt32(
            0x0500_0300,
            at: 32
        )
        let properties =
            rawProperties
            | (compressed ? 1 : 0)
        header.testSetUInt32(
            properties,
            at: 36
        )
        header.testSetUInt32(
            encryptionVersion,
            at: 44
        )

        let plainSection =
            sectionOverride
            ?? makeHWPSection()
        var section = compressed
            ? try rawDeflate(plainSection)
            : plainSection
        if compressed
            && includesCompressionTrailer {
            var checksum = crc32(0, nil, 0)
            plainSection.withUnsafeBytes {
                rawInput in
                let bytes = rawInput.bindMemory(
                    to: Bytef.self
                )
                if let base = bytes.baseAddress {
                    checksum = crc32(
                        checksum,
                        base,
                        uInt(bytes.count)
                    )
                }
            }
            section.testAppendUInt32(
                usesZeroCompressionChecksumTrailer
                    ? 0
                    : UInt32(
                        truncatingIfNeeded:
                            checksum
                    )
            )
            section.testAppendUInt32(
                UInt32(
                    truncatingIfNeeded:
                        plainSection.count
                )
            )
            if corruptsCompressionTrailer {
                section[section.count - 8] ^= 0x01
            }
        }
        var streams = extraStreams
        streams["FileHeader"] = header
        streams["BodyText/Section0"] = section
        if let docInfoOverride {
            streams["DocInfo"] = compressed
                ? try rawDeflate(docInfoOverride)
                : docInfoOverride
        }
        return try makeOLEFile(streams: streams)
    }

    private func makeStructuredHWPDocInfo(
        fontWidth: UInt8 = 100,
        letterSpacing: Int8 = 0,
        characterPosition: Int8 = 0,
        includesFontMetadata: Bool = false
    ) -> Data {
        var docInfo = Data()

        var mappings = Data()
        let mappingCounts = [
            0, // BinData
            1, // Korean font
            0, 0, 0, 0, 0, 0,
            0, // border/fill
            1, // character shape
            0, 0, 0,
            1, // paragraph shape
            1, // style
            0, 0, 0,
        ]
        for count in mappingCounts {
            mappings.testAppendUInt32(UInt32(count))
        }
        docInfo.append(hwpRecord(tag: 0x11, level: 0, payload: mappings))

        var face = Data([includesFontMetadata ? 0xE0 : 0])
        face.testAppendUTF16String("함초롬바탕")
        if includesFontMetadata {
            face.append(1) // TrueType family classification
            face.testAppendUTF16String("AppleSDGothicNeo-Regular")
            face.append(contentsOf: [2, 2, 5, 3, 5, 4, 5, 2, 3, 4])
            face.testAppendUTF16String("Batang-Regular")
        }
        docInfo.append(hwpRecord(tag: 0x13, level: 0, payload: face))

        var characterShape = Data()
        for _ in 0..<7 { characterShape.testAppendUInt16(0) }
        characterShape.append(contentsOf: Array(repeating: fontWidth, count: 7))
        characterShape.append(contentsOf: Array(
            repeating: UInt8(bitPattern: letterSpacing),
            count: 7
        ))
        characterShape.append(contentsOf: Array(repeating: 100, count: 7))
        characterShape.append(contentsOf: Array(
            repeating: UInt8(bitPattern: characterPosition),
            count: 7
        ))
        characterShape.testAppendUInt32(1_200)
        characterShape.testAppendUInt32(1 << 1)
        characterShape.append(contentsOf: [0, 0])
        characterShape.testAppendUInt32(0x0000_00FF)
        characterShape.testAppendUInt32(0)
        characterShape.testAppendUInt32(0x00FF_FFFF)
        characterShape.testAppendUInt32(0)
        characterShape.testAppendUInt16(0)
        characterShape.testAppendUInt32(0)
        docInfo.append(hwpRecord(tag: 0x15, level: 0, payload: characterShape))

        var paragraphShape = Data()
        paragraphShape.testAppendUInt32((3 << 2) | (1 << 23))
        paragraphShape.testAppendUInt32(1_000)
        paragraphShape.testAppendUInt32(0)
        paragraphShape.testAppendUInt32(500)
        paragraphShape.testAppendUInt32(200)
        paragraphShape.testAppendUInt32(300)
        paragraphShape.testAppendUInt32(0)
        paragraphShape.testAppendUInt16(0)
        paragraphShape.testAppendUInt16(0)
        paragraphShape.testAppendUInt16(0)
        for _ in 0..<4 { paragraphShape.testAppendUInt16(0) }
        paragraphShape.testAppendUInt32(0)
        paragraphShape.testAppendUInt32(0)
        paragraphShape.testAppendUInt32(160)
        docInfo.append(hwpRecord(tag: 0x19, level: 0, payload: paragraphShape))

        var style = Data()
        style.testAppendUTF16String("제목 1")
        style.testAppendUTF16String("Heading 1")
        style.append(contentsOf: [0, 0])
        style.testAppendUInt16(1_042)
        style.testAppendUInt16(0)
        style.testAppendUInt16(0)
        docInfo.append(hwpRecord(tag: 0x1A, level: 0, payload: style))
        return docInfo
    }

    private func makeRichHWPDocInfo() -> Data {
        var docInfo = makeStructuredHWPDocInfo()

        var binary = Data()
        binary.testAppendUInt16(0x21) // embedding + never compressed
        binary.testAppendUInt16(1)
        binary.testAppendUTF16String("png")
        docInfo.append(hwpRecord(tag: 0x12, level: 0, payload: binary))

        var border = Data()
        border.testAppendUInt16(0)
        for _ in 0..<4 {
            border.append(1)
            border.append(7)
            border.testAppendUInt32(0x0000_0000)
        }
        border.append(contentsOf: [0, 0])
        border.testAppendUInt32(0)
        border.testAppendUInt32(1)
        border.testAppendUInt32(0x0033_2211)
        border.testAppendUInt32(0x00FF_FFFF)
        border.testAppendUInt32(UInt32.max)
        docInfo.append(hwpRecord(tag: 0x14, level: 0, payload: border))
        return docInfo
    }

    private func richHWPPNG() throws -> Data {
        try XCTUnwrap(
            Data(
                base64Encoded:
                    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
            )
        )
    }

    private func makeRichHWPSection() -> Data {
        var section = structuredHWPParagraph("본문과 그림", level: 0)

        var sectionControl = Data()
        sectionControl.testAppendUInt32(0x7365_6364)
        sectionControl.testAppendUInt32(0)
        section.append(hwpRecord(tag: 0x47, level: 1, payload: sectionControl))

        var page = Data()
        for value: UInt32 in [59_528, 84_186, 8_504, 8_504, 5_668, 4_252, 4_252, 4_252, 0] {
            page.testAppendUInt32(value)
        }
        page.testAppendUInt32(0)
        section.append(hwpRecord(tag: 0x49, level: 2, payload: page))

        let noteShape = richHWPNoteShape()
        section.append(hwpRecord(tag: 0x4A, level: 2, payload: noteShape))
        section.append(hwpRecord(tag: 0x4A, level: 2, payload: noteShape))

        var pageBorder = Data()
        pageBorder.testAppendUInt32(0)
        for _ in 0..<4 { pageBorder.testAppendUInt16(0) }
        pageBorder.testAppendUInt16(1)
        section.append(hwpRecord(tag: 0x4B, level: 2, payload: pageBorder))

        var pictureControl = Data()
        pictureControl.testAppendUInt32(0x6773_6F20)
        pictureControl.testAppendUInt32(0)
        pictureControl.testAppendUInt32(0)
        pictureControl.testAppendUInt32(0)
        pictureControl.testAppendUInt32(12_000)
        pictureControl.testAppendUInt32(8_000)
        pictureControl.testAppendUInt32(0)
        for _ in 0..<4 { pictureControl.testAppendUInt16(0) }
        pictureControl.testAppendUInt32(1)
        pictureControl.testAppendUInt32(0)
        pictureControl.testAppendUTF16String("본문 그림")
        section.append(hwpRecord(tag: 0x47, level: 1, payload: pictureControl))

        var shape = Data()
        shape.testAppendUInt32(0x2470_6963)
        section.append(hwpRecord(tag: 0x4C, level: 2, payload: shape))
        var picture = Data(repeating: 0, count: 73)
        picture.testSetUInt16(1, at: 71)
        section.append(hwpRecord(tag: 0x55, level: 3, payload: picture))

        var tableControl = Data()
        tableControl.testAppendUInt32(0x7462_6C20)
        section.append(hwpRecord(tag: 0x47, level: 1, payload: tableControl))
        var table = Data()
        table.testAppendUInt32(0)
        table.testAppendUInt16(1)
        table.testAppendUInt16(1)
        table.testAppendUInt16(0)
        for _ in 0..<4 { table.testAppendUInt16(0) }
        table.testAppendUInt16(1)
        table.testAppendUInt16(1)
        table.testAppendUInt16(0)
        section.append(hwpRecord(tag: 0x4D, level: 2, payload: table))
        section.append(
            structuredHWPTableCell(
                text: "색 있는 셀",
                row: 0,
                column: 0,
                rowSpan: 1,
                columnSpan: 1,
                borderFillID: 1
            )
        )

        section.append(richHWPListControl(id: 0x6865_6164, property: 2, text: "머리말 내용"))
        section.append(richHWPListControl(id: 0x666F_6F74, property: 0, text: "꼬리말 내용"))
        section.append(richHWPListControl(id: 0x666E_2020, property: 0, text: "각주 내용"))
        section.append(richHWPListControl(id: 0x656E_2020, property: 0, text: "미주 내용"))
        return section
    }

    private func richHWPNoteShape() -> Data {
        var shape = Data()
        shape.testAppendUInt32(0)
        shape.testAppendUInt16(0)
        shape.testAppendUInt16(0)
        shape.testAppendUInt16(0x29)
        shape.testAppendUInt16(1)
        shape.testAppendUInt16(12_000)
        shape.testAppendUInt16(300)
        shape.testAppendUInt16(300)
        shape.testAppendUInt16(200)
        shape.append(contentsOf: [1, 7])
        shape.testAppendUInt32(0)
        return shape
    }

    private func richHWPListControl(
        id: UInt32,
        property: UInt32,
        text: String
    ) -> Data {
        var control = Data()
        control.testAppendUInt32(id)
        control.testAppendUInt32(property)
        var list = Data()
        list.testAppendUInt32(1)
        list.testAppendUInt32(0)
        var result = hwpRecord(tag: 0x47, level: 1, payload: control)
        result.append(hwpRecord(tag: 0x48, level: 2, payload: list))
        result.append(structuredHWPParagraph(text, level: 3))
        return result
    }

    private func makeStructuredHWPSection(text: String = "구조화 제목") -> Data {
        var units = Array(text.utf16)
        units.append(13)

        var header = Data()
        header.testAppendUInt32(UInt32(units.count))
        header.testAppendUInt32(0)
        header.testAppendUInt16(0)
        header.append(contentsOf: [0, 0])
        header.testAppendUInt16(1)
        header.testAppendUInt16(0)
        header.testAppendUInt16(0)
        header.testAppendUInt32(1)
        header.testAppendUInt16(0)

        var text = Data()
        for unit in units { text.testAppendUInt16(unit) }

        var shapes = Data()
        shapes.testAppendUInt32(0)
        shapes.testAppendUInt32(0)

        var section = Data()
        section.append(hwpRecord(tag: 0x42, level: 0, payload: header))
        section.append(hwpRecord(tag: 0x43, level: 1, payload: text))
        section.append(hwpRecord(tag: 0x44, level: 1, payload: shapes))
        return section
    }

    /// One paragraph whose writer cached two wrapped lines: the second one is
    /// flagged as an empty trailing segment so rebuilding must clear it.
    private func makeLineSegmentHWPSection() -> Data {
        var units = Array("가나다라마바".utf16)
        units.append(13)

        var header = Data()
        header.testAppendUInt32(UInt32(units.count))
        header.testAppendUInt32(0)
        header.testAppendUInt16(0)
        header.append(contentsOf: [0, 0])
        header.testAppendUInt16(1) // char shape count
        header.testAppendUInt16(0) // range tag count
        header.testAppendUInt16(2) // line segment count
        header.testAppendUInt32(1)
        header.testAppendUInt16(0)

        var text = Data()
        for unit in units { text.testAppendUInt16(unit) }

        var shapes = Data()
        shapes.testAppendUInt32(0)
        shapes.testAppendUInt32(0)

        func segment(
            start: UInt32,
            y: Int32,
            columnStart: Int32,
            flags: UInt32
        ) -> Data {
            var data = Data()
            data.testAppendUInt32(start)
            data.testAppendUInt32(UInt32(bitPattern: y))
            data.testAppendUInt32(1_600) // line height
            data.testAppendUInt32(1_200) // text height
            data.testAppendUInt32(1_300) // baseline
            data.testAppendUInt32(400) // line spacing
            data.testAppendUInt32(UInt32(bitPattern: columnStart))
            data.testAppendUInt32(40_000) // width
            data.testAppendUInt32(flags)
            return data
        }
        var segments = segment(start: 0, y: 1_000, columnStart: 0, flags: 0x1)
        segments.append(
            segment(start: 3, y: 2_600, columnStart: 500, flags: 0x0001_0000)
        )

        var section = Data()
        section.append(hwpRecord(tag: 0x42, level: 0, payload: header))
        section.append(hwpRecord(tag: 0x43, level: 1, payload: text))
        section.append(hwpRecord(tag: 0x44, level: 1, payload: shapes))
        section.append(hwpRecord(tag: 0x45, level: 1, payload: segments))
        return section
    }

    private func firstHWPRecordPayload(tag: UInt32, in data: Data) -> Data? {
        var offset = 0
        while offset + 4 <= data.count {
            let header = UInt32(data[offset]) | UInt32(data[offset + 1]) << 8
                | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
            offset += 4
            var size = Int(header >> 20)
            if size == 0x0FFF {
                guard offset + 4 <= data.count else { return nil }
                size = Int(
                    UInt32(data[offset]) | UInt32(data[offset + 1]) << 8
                        | UInt32(data[offset + 2]) << 16
                        | UInt32(data[offset + 3]) << 24
                )
                offset += 4
            }
            guard offset + size <= data.count else { return nil }
            if header & 0x03FF == tag {
                return data.subdata(in: offset..<(offset + size))
            }
            offset += size
        }
        return nil
    }

    private func makeStructuredHWPTableSection() -> Data {
        var section = structuredHWPParagraph("표 앞", level: 0)

        var control = Data()
        control.testAppendUInt32(0x7462_6C20) // "tbl "
        section.append(hwpRecord(tag: 0x47, level: 1, payload: control))

        var table = Data()
        table.testAppendUInt32(0)
        table.testAppendUInt16(2) // rows
        table.testAppendUInt16(2) // columns
        table.testAppendUInt16(0) // cell spacing
        for _ in 0..<4 { table.testAppendUInt16(0) }
        table.testAppendUInt16(1)
        table.testAppendUInt16(2)
        table.testAppendUInt16(0) // border/fill
        table.testAppendUInt16(0) // zone count
        section.append(hwpRecord(tag: 0x4D, level: 2, payload: table))

        section.append(
            structuredHWPTableCell(
                text: "병합 제목",
                row: 0,
                column: 0,
                rowSpan: 1,
                columnSpan: 2
            )
        )
        section.append(
            structuredHWPTableCell(
                text: "왼쪽",
                row: 1,
                column: 0,
                rowSpan: 1,
                columnSpan: 1
            )
        )
        section.append(
            structuredHWPTableCell(
                text: "오른쪽",
                row: 1,
                column: 1,
                rowSpan: 1,
                columnSpan: 1
            )
        )
        section.append(structuredHWPParagraph("표 뒤", level: 0))
        return section
    }

    private func structuredHWPTableCell(
        text: String,
        row: UInt16,
        column: UInt16,
        rowSpan: UInt16,
        columnSpan: UInt16,
        borderFillID: UInt16 = 0
    ) -> Data {
        var header = Data()
        header.testAppendUInt16(1) // paragraph count
        header.testAppendUInt32(0)
        header.testAppendUInt16(column)
        header.testAppendUInt16(row)
        header.testAppendUInt16(columnSpan)
        header.testAppendUInt16(rowSpan)
        header.testAppendUInt32(8_000)
        header.testAppendUInt32(2_000)
        for _ in 0..<4 { header.testAppendUInt16(0) }
        header.testAppendUInt16(borderFillID)

        var result = hwpRecord(tag: 0x48, level: 2, payload: header)
        result.append(structuredHWPParagraph(text, level: 3))
        return result
    }

    private func structuredHWPParagraph(_ text: String, level: UInt32) -> Data {
        var units = Array(text.utf16)
        units.append(13)

        var header = Data()
        header.testAppendUInt32(UInt32(units.count))
        header.testAppendUInt32(0)
        header.testAppendUInt16(0)
        header.append(contentsOf: [0, 0])
        header.testAppendUInt16(1)
        header.testAppendUInt16(0)
        header.testAppendUInt16(0)
        header.testAppendUInt32(1)
        header.testAppendUInt16(0)

        var body = Data()
        for unit in units { body.testAppendUInt16(unit) }
        var shapes = Data()
        shapes.testAppendUInt32(0)
        shapes.testAppendUInt32(0)

        var result = hwpRecord(tag: 0x42, level: level, payload: header)
        result.append(hwpRecord(tag: 0x43, level: level + 1, payload: body))
        result.append(hwpRecord(tag: 0x44, level: level + 1, payload: shapes))
        return result
    }

    private func hwpRecord(tag: UInt32, level: UInt32, payload: Data) -> Data {
        var record = Data()
        record.testAppendUInt32(
            UInt32(payload.count << 20) | (level << 10) | tag
        )
        record.append(payload)
        return record
    }

    private func makeHWPSection()
        -> Data
    {
        var section = Data()
        var first = Array(
            "첫 문단".utf16
        )
        first.append(contentsOf: [
            9, 0, 0, 0, 0, 0, 0, 9,
        ])
        first.append(
            contentsOf:
                Array("탭 뒤".utf16)
        )
        first.append(13)
        section.append(
            hwpParagraphRecord(first)
        )

        var second = Array(
            "둘째 문단".utf16
        )
        second.append(contentsOf: [
            11, 0, 0, 0, 0, 0, 0, 11,
        ])
        second.append(24)
        second.append(
            contentsOf:
                Array("끝".utf16)
        )
        second.append(13)
        section.append(
            hwpParagraphRecord(second)
        )
        return section
    }

    private func hwpParagraphRecord(
        _ units: [UInt16]
    ) -> Data {
        var payload = Data()
        for unit in units {
            payload.testAppendUInt16(unit)
        }
        var record = Data()
        record.testAppendUInt32(
            UInt32(payload.count << 20)
                | UInt32(1 << 10)
                | 0x43
        )
        record.append(payload)
        return record
    }

    private func rawDeflate(
        _ input: Data
    ) throws -> Data {
        var stream = z_stream()
        XCTAssertEqual(
            deflateInit2_(
                &stream,
                Z_DEFAULT_COMPRESSION,
                Z_DEFLATED,
                -MAX_WBITS,
                8,
                Z_DEFAULT_STRATEGY,
                ZLIB_VERSION,
                Int32(
                    MemoryLayout<z_stream>
                        .size
                )
            ),
            Z_OK
        )
        defer {
            deflateEnd(&stream)
        }

        return try input.withUnsafeBytes {
            rawInput in
            let bytes = rawInput.bindMemory(
                to: Bytef.self
            )
            stream.next_in =
                UnsafeMutablePointer(
                    mutating:
                        bytes.baseAddress
                )
            stream.avail_in =
                uInt(input.count)
            var output = Data()
            var chunk = [UInt8](
                repeating: 0,
                count: 1_024
            )
            while true {
                let status = chunk
                    .withUnsafeMutableBytes {
                        rawOutput in
                        let outputBytes =
                            rawOutput.bindMemory(
                                to: Bytef.self
                            )
                        stream.next_out =
                            outputBytes
                                .baseAddress
                        stream.avail_out =
                            uInt(
                                outputBytes
                                    .count
                            )
                        return deflate(
                            &stream,
                            Z_FINISH
                        )
                    }
                let produced =
                    chunk.count
                    - Int(stream.avail_out)
                output.append(
                    contentsOf:
                        chunk.prefix(produced)
                )
                if status == Z_STREAM_END {
                    return output
                }
                guard status == Z_OK
                        || status
                            == Z_BUF_ERROR
                else {
                    throw TestFixtureError
                        .compressionFailed
                }
            }
        }
    }
}

private enum TestFixtureError: Error {
    case invalidPath
    case tooLarge
    case compressionFailed
}

private struct OLETestEntry {
    let name: String
    let type: UInt8
    let parentPath: String
    var rightSibling = UInt32.max
    var child = UInt32.max
    var startSector =
        UInt32.max - 1
    var size: UInt64 = 0
}

private func makeOLEFile(
    streams: [String: Data]
) throws -> Data {
    let sectorSize = 512
    let miniSectorSize = 64
    let normalizedStreams = Dictionary(
        uniqueKeysWithValues:
            try streams.map {
                rawPath,
                data in
                let components =
                    rawPath.split(
                        separator: "/"
                    )
                    .map(String.init)
                guard !components.isEmpty,
                      components.allSatisfy({
                          !$0.isEmpty
                            && $0.utf16.count
                                <= 31
                      })
                else {
                    throw TestFixtureError
                        .invalidPath
                }
                return (
                    components.joined(
                        separator: "/"
                    ),
                    data
                )
            }
    )

    var storagePaths: Set<String> = []
    for path in normalizedStreams.keys {
        let parts = path.split(
            separator: "/"
        )
        if parts.count > 1 {
            for end in 1..<parts.count {
                storagePaths.insert(
                    parts[0..<end]
                        .joined(
                            separator: "/"
                        )
                )
            }
        }
    }

    var entries = [
        OLETestEntry(
            name: "Root Entry",
            type: 5,
            parentPath: ""
        ),
    ]
    var indexForPath = [
        "": 0,
    ]
    for path in storagePaths.sorted() {
        let parts = path.split(
            separator: "/"
        )
        let parent = parts.dropLast()
            .joined(separator: "/")
        indexForPath[path] =
            entries.count
        entries.append(
            OLETestEntry(
                name: String(parts.last!),
                type: 1,
                parentPath: parent
            )
        )
    }
    for path in normalizedStreams.keys
        .sorted()
    {
        let parts = path.split(
            separator: "/"
        )
        let parent = parts.dropLast()
            .joined(separator: "/")
        indexForPath[path] =
            entries.count
        entries.append(
            OLETestEntry(
                name: String(parts.last!),
                type: 2,
                parentPath: parent
            )
        )
    }
    guard entries.count <= 32 else {
        throw TestFixtureError.tooLarge
    }

    var children: [String: [Int]] = [:]
    for index in entries.indices
    where index > 0 {
        children[
            entries[index].parentPath,
            default: []
        ].append(index)
    }
    for (
        parent,
        rawChildren
    ) in children {
        let sorted = rawChildren.sorted {
            entries[$0].name
                < entries[$1].name
        }
        let parentIndex =
            indexForPath[parent]!
        entries[parentIndex].child =
            UInt32(sorted[0])
        for offset in sorted.indices
        where offset + 1 < sorted.count {
            entries[sorted[offset]]
                .rightSibling =
                    UInt32(
                        sorted[offset + 1]
                    )
        }
    }

    var miniStream = Data()
    var miniFAT: [UInt32] = []
    var regularStreams:
        [(entry: Int, data: Data)] = []
    for (
        path,
        streamData
    ) in normalizedStreams.sorted(
        by: {
            $0.key < $1.key
        }
    ) {
        let entryIndex =
            indexForPath[path]!
        entries[entryIndex].size =
            UInt64(streamData.count)
        if streamData.count < 4_096 {
            let firstMiniSector =
                miniFAT.count
            entries[entryIndex]
                .startSector =
                    streamData.isEmpty
                    ? UInt32.max - 1
                    : UInt32(
                        firstMiniSector
                    )
            let count = max(
                1,
                (
                    streamData.count
                    + miniSectorSize - 1
                ) / miniSectorSize
            )
            for miniIndex in 0..<count {
                miniFAT.append(
                    miniIndex == count - 1
                    ? UInt32.max - 1
                    : UInt32(
                        firstMiniSector
                        + miniIndex + 1
                    )
                )
                let start =
                    miniIndex
                    * miniSectorSize
                let end = min(
                    streamData.count,
                    start + miniSectorSize
                )
                if start < end {
                    miniStream.append(
                        streamData[start..<end]
                    )
                }
                if end - start
                    < miniSectorSize {
                    miniStream.append(
                        Data(
                            repeating: 0,
                            count:
                                miniSectorSize
                                - (end - start)
                        )
                    )
                }
            }
        } else {
            regularStreams.append(
                (entryIndex, streamData)
            )
        }
    }

    var sectors: [Data] = []
    var fat: [UInt32] = []
    func appendSectorChain(
        _ bytes: Data
    ) -> UInt32 {
        let first = sectors.count
        let count = max(
            1,
            (
                bytes.count
                + sectorSize - 1
            ) / sectorSize
        )
        for index in 0..<count {
            let start = index * sectorSize
            let end = min(
                bytes.count,
                start + sectorSize
            )
            var sector = Data()
            if start < end {
                sector.append(
                    bytes[start..<end]
                )
            }
            if sector.count < sectorSize {
                sector.append(
                    Data(
                        repeating: 0,
                        count:
                            sectorSize
                            - sector.count
                    )
                )
            }
            sectors.append(sector)
            fat.append(
                index == count - 1
                ? UInt32.max - 1
                : UInt32(first + index + 1)
            )
        }
        return UInt32(first)
    }

    // Reserve enough chained sectors for every 128-byte directory entry.
    let directorySectorCount = max(
        1,
        (entries.count * 128 + sectorSize - 1) / sectorSize
    )
    for index in 0..<directorySectorCount {
        sectors.append(Data(repeating: 0, count: sectorSize))
        fat.append(
            index == directorySectorCount - 1
                ? UInt32.max - 1
                : UInt32(index + 1)
        )
    }

    let firstMiniFATSector:
        UInt32
    let miniFATSectorCount: Int
    if miniFAT.isEmpty {
        firstMiniFATSector =
            UInt32.max - 1
        miniFATSectorCount = 0
    } else {
        var miniFATData = Data()
        for value in miniFAT {
            miniFATData.testAppendUInt32(
                value
            )
        }
        while miniFATData.count
            % sectorSize != 0 {
            miniFATData.testAppendUInt32(
                UInt32.max
            )
        }
        firstMiniFATSector =
            appendSectorChain(
                miniFATData
            )
        miniFATSectorCount =
            miniFATData.count
            / sectorSize
    }

    if miniStream.isEmpty {
        entries[0].startSector =
            UInt32.max - 1
    } else {
        entries[0].startSector =
            appendSectorChain(
                miniStream
            )
        entries[0].size =
            UInt64(miniStream.count)
    }
    for (
        entryIndex,
        streamData
    ) in regularStreams {
        entries[entryIndex]
            .startSector =
                appendSectorChain(
                    streamData
                )
    }

    var directory = Data()
    for entry in entries {
        directory.append(
            makeOLEDirectoryEntry(entry)
        )
    }
    while directory.count < directorySectorCount * sectorSize {
        directory.append(
            Data(
                repeating: 0,
                count: min(
                    128,
                    directorySectorCount * sectorSize
                        - directory.count
                )
            )
        )
    }
    for index in 0..<directorySectorCount {
        let start = index * sectorSize
        sectors[index] = directory.subdata(
            in: start..<(start + sectorSize)
        )
    }

    guard sectors.count + 1 <= 128
    else {
        throw TestFixtureError.tooLarge
    }
    let fatSectorID = sectors.count
    fat.append(UInt32.max - 2)
    var fatSector = Data()
    for value in fat {
        fatSector.testAppendUInt32(value)
    }
    while fatSector.count < sectorSize {
        fatSector.testAppendUInt32(
            UInt32.max
        )
    }
    sectors.append(fatSector)

    var header = Data(
        repeating: 0,
        count: sectorSize
    )
    header.replaceSubrange(
        0..<8,
        with: Data([
            0xD0, 0xCF, 0x11, 0xE0,
            0xA1, 0xB1, 0x1A, 0xE1,
        ])
    )
    header.testSetUInt16(0x003E, at: 24)
    header.testSetUInt16(3, at: 26)
    header.testSetUInt16(0xFFFE, at: 28)
    header.testSetUInt16(9, at: 30)
    header.testSetUInt16(6, at: 32)
    header.testSetUInt32(0, at: 40)
    header.testSetUInt32(1, at: 44)
    header.testSetUInt32(0, at: 48)
    header.testSetUInt32(4_096, at: 56)
    header.testSetUInt32(
        firstMiniFATSector,
        at: 60
    )
    header.testSetUInt32(
        UInt32(miniFATSectorCount),
        at: 64
    )
    header.testSetUInt32(
        UInt32.max - 1,
        at: 68
    )
    header.testSetUInt32(0, at: 72)
    for index in 0..<109 {
        header.testSetUInt32(
            index == 0
                ? UInt32(fatSectorID)
                : UInt32.max,
            at: 76 + index * 4
        )
    }

    var file = header
    for sector in sectors {
        file.append(sector)
    }
    return file
}

private func makeOLEDirectoryEntry(
    _ entry: OLETestEntry
) -> Data {
    var data = Data(
        repeating: 0,
        count: 128
    )
    var nameUnits = Array(
        entry.name.utf16
    )
    nameUnits.append(0)
    for (
        index,
        unit
    ) in nameUnits.enumerated() {
        data.testSetUInt16(
            unit,
            at: index * 2
        )
    }
    data.testSetUInt16(
        UInt16(nameUnits.count * 2),
        at: 64
    )
    data[66] = entry.type
    data[67] = 1
    data.testSetUInt32(
        UInt32.max,
        at: 68
    )
    data.testSetUInt32(
        entry.rightSibling,
        at: 72
    )
    data.testSetUInt32(
        entry.child,
        at: 76
    )
    data.testSetUInt32(
        entry.startSector,
        at: 116
    )
    data.testSetUInt64(
        entry.size,
        at: 120
    )
    return data
}

private extension Data {
    mutating func testAppendUTF16String(
        _ value: String
    ) {
        let units = Array(value.utf16)
        testAppendUInt16(UInt16(units.count))
        for unit in units {
            testAppendUInt16(unit)
        }
    }

    mutating func testAppendUInt16(
        _ value: UInt16
    ) {
        append(UInt8(value & 0xFF))
        append(UInt8(value >> 8))
    }

    mutating func testAppendUInt32(
        _ value: UInt32
    ) {
        append(UInt8(value & 0xFF))
        append(
            UInt8((value >> 8) & 0xFF)
        )
        append(
            UInt8((value >> 16) & 0xFF)
        )
        append(
            UInt8((value >> 24) & 0xFF)
        )
    }

    mutating func testAppendDouble(
        _ value: Double
    ) {
        testAppendUInt64(
            value.bitPattern
        )
    }

    mutating func testAppendUInt64(
        _ value: UInt64
    ) {
        testAppendUInt32(
            UInt32(
                value & 0xFFFF_FFFF
            )
        )
        testAppendUInt32(
            UInt32(value >> 32)
        )
    }

    mutating func testSetUInt16(
        _ value: UInt16,
        at offset: Int
    ) {
        self[offset] =
            UInt8(value & 0xFF)
        self[offset + 1] =
            UInt8(value >> 8)
    }

    mutating func testSetUInt32(
        _ value: UInt32,
        at offset: Int
    ) {
        self[offset] =
            UInt8(value & 0xFF)
        self[offset + 1] =
            UInt8(
                (value >> 8) & 0xFF
            )
        self[offset + 2] =
            UInt8(
                (value >> 16) & 0xFF
            )
        self[offset + 3] =
            UInt8(
                (value >> 24) & 0xFF
            )
    }

    mutating func testSetUInt64(
        _ value: UInt64,
        at offset: Int
    ) {
        testSetUInt32(
            UInt32(
                value & 0xFFFF_FFFF
            ),
            at: offset
        )
        testSetUInt32(
            UInt32(value >> 32),
            at: offset + 4
        )
    }

    func testUInt32(
        at offset: Int
    ) throws -> UInt32 {
        guard offset >= 0,
              offset + 4 <= count else {
            throw TestFixtureError
                .tooLarge
        }
        return UInt32(self[offset])
            | UInt32(self[offset + 1])
                << 8
            | UInt32(self[offset + 2])
                << 16
            | UInt32(self[offset + 3])
                << 24
    }
}
