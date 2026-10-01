import XCTest
import FirebaseAILogic
import UIKit
import ZIPFoundation
@testable import shortcuts_example

final class ExcelWorkbookDocumentTests: XCTestCase {
    func testBlankWorkbookCanBeCreatedEditedAndReloaded() throws {
        let source = try ExcelWorkbookDocument.blankWorkbookData()
        let workbook = try ExcelWorkbookDocument.load(from: source)
        let sheet = try XCTUnwrap(workbook.sheets.first)

        XCTAssertEqual(sheet.name, "시트1")
        XCTAssertTrue(sheet.cells.isEmpty)
        XCTAssertEqual(workbook.styles.count, 1)

        let saved = try ExcelWorkbookDocument.applying(
            [
                ExcelWorksheetEdits(
                    partPath: sheet.partPath,
                    cells: [
                        address("A1"): ExcelCellEdit(
                            input: .text("상품"),
                            styleIndex: nil
                        ),
                    ]
                ),
            ],
            to: source,
            workbook: workbook
        )
        let reloaded = try ExcelWorkbookDocument.load(from: saved)

        XCTAssertEqual(
            reloaded.sheets.first?.cell(at: address("A1"))?.displayValue,
            "상품"
        )
    }

    @MainActor
    func testExcelAICreatesNativeTableInBlankWorkbook() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ExcelAICreateTable-\(UUID().uuidString).xlsx"
            )
        try ExcelWorkbookDocument.blankWorkbookData().write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let viewModel = ExcelWorkbookViewModel(fileURL: fileURL)
        await viewModel.load()
        let snapshot = try XCTUnwrap(viewModel.makeAISnapshot())
        XCTAssertTrue(snapshot.cells.isEmpty)
        XCTAssertTrue(snapshot.regions.isEmpty)

        let command = ExcelAICommandPlan(
            intent: .edit,
            assistantMessage: "상품 입력 표를 만들었습니다.",
            edits: [],
            appendedRows: [],
            createdTables: [
                .init(
                    startRow: 1,
                    startColumn: 1,
                    headers: ["상품", "수량", "단가", "금액"],
                    blankRowCount: 5
                ),
            ]
        )
        let validated = try XCTUnwrap(
            ExcelAICommandValidator.validate(
                command,
                snapshot: snapshot
            )
        )

        XCTAssertEqual(validated.createdTables.count, 1)
        _ = try viewModel.applyAIPlan(validated)
        XCTAssertEqual(viewModel.selectedSheet?.tables.count, 1)
        XCTAssertEqual(
            viewModel.selectedSheet?.tables.first?.range.reference,
            "A1:D6"
        )
        XCTAssertEqual(
            viewModel.selectedSheet?.cell(at: address("A1"))?.displayValue,
            "상품"
        )
        XCTAssertEqual(
            viewModel.selectedSheet?.cell(at: address("D1"))?.displayValue,
            "금액"
        )

        viewModel.undo()
        XCTAssertTrue(viewModel.selectedSheet?.tables.isEmpty == true)
        XCTAssertFalse(viewModel.hasUnsavedChanges)
        viewModel.redo()
        XCTAssertEqual(viewModel.selectedSheet?.tables.count, 1)

        let exported = try await viewModel.exportData()
        let reloaded = try ExcelWorkbookDocument.load(from: exported)
        let table = try XCTUnwrap(reloaded.sheets.first?.tables.first)
        XCTAssertEqual(table.range.reference, "A1:D6")
        XCTAssertEqual(table.columnNames, ["상품", "수량", "단가", "금액"])
        XCTAssertEqual(
            reloaded.sheets.first?.cell(at: address("A1"))?.displayValue,
            "상품"
        )
        XCTAssertEqual(
            reloaded.sheets.first?.cell(at: address("D1"))?.displayValue,
            "금액"
        )
    }

    func testExcelAITrustsStructuredTableIntentWithoutReparsingWords() throws {
        let workbook = try ExcelWorkbookDocument.load(
            from: ExcelWorkbookDocument.blankWorkbookData()
        )
        let snapshot = try XCTUnwrap(
            ExcelAISnapshotBuilder.make(
                workbookName: "새 스프레드시트",
                workbook: workbook,
                selectedSheetIndex: 0,
                selectedAddress: nil
            )
        )
        let command = ExcelAICommandPlan(
            intent: .edit,
            assistantMessage: "상품 입력 표를 만들었습니다.",
            edits: [],
            appendedRows: [],
            createdTables: [
                .init(
                    startRow: 1,
                    startColumn: 1,
                    headers: ["상품", "수량", "단가", "금액"],
                    blankRowCount: 5
                ),
            ]
        )

        let validated = try XCTUnwrap(
            ExcelAICommandValidator.validate(
                command,
                snapshot: snapshot
            )
        )
        XCTAssertEqual(validated.createdTables.count, 1)
    }

    @MainActor
    func testExcelAICanPopulateReservedBlankTableRows() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ExcelAIPopulateBlankRows-\(UUID().uuidString).xlsx"
            )
        try ExcelWorkbookDocument.blankWorkbookData().write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let viewModel = ExcelWorkbookViewModel(fileURL: fileURL)
        await viewModel.load()
        let emptySnapshot = try XCTUnwrap(viewModel.makeAISnapshot())
        let createTable = ExcelAICommandPlan(
            intent: .edit,
            assistantMessage: "상품 표를 만들었습니다.",
            edits: [],
            appendedRows: [],
            createdTables: [
                .init(
                    startRow: 1,
                    startColumn: 1,
                    headers: ["상품", "수량"],
                    blankRowCount: 2
                ),
            ]
        )
        _ = try viewModel.applyAIPlan(
            XCTUnwrap(
                ExcelAICommandValidator.validate(
                    createTable,
                    snapshot: emptySnapshot
                )
            )
        )

        let tableSnapshot = try XCTUnwrap(viewModel.makeAISnapshot())
        XCTAssertTrue(tableSnapshot.regions.first?.dataRows.isEmpty == true)
        let region = try XCTUnwrap(tableSnapshot.regions.first)
        let headerEdit = ExcelAICommandPlan(
            intent: .edit,
            assistantMessage: "머리글을 바꿨습니다.",
            edits: [.init(row: 1, column: 1, newValue: "품목")],
            appendedRows: []
        )
        XCTAssertThrowsError(
            try ExcelAICommandValidator.validate(
                headerEdit,
                snapshot: tableSnapshot
            )
        ) { error in
            guard case ExcelAICommandValidationError.invalidTarget = error else {
                return XCTFail("잘못된 오류: \(error)")
            }
        }
        let fillRows = ExcelAICommandPlan(
            intent: .edit,
            assistantMessage: "빈 입력 행에 값을 채웠습니다.",
            edits: [
                .init(row: 2, column: 1, newValue: "연필"),
                .init(row: 2, column: 2, newValue: "12"),
                .init(row: 3, column: 1, newValue: "공책"),
                .init(row: 3, column: 2, newValue: "5"),
            ],
            appendedRows: [],
            actions: [
                .init(
                    type: .setNumberFormat,
                    target: .init(
                        scope: .column,
                        regionID: region.id,
                        row: nil,
                        column: 2
                    ),
                    format: "integer"
                ),
            ]
        )
        let validated = try XCTUnwrap(
            ExcelAICommandValidator.validate(
                fillRows,
                snapshot: tableSnapshot
            )
        )
        _ = try viewModel.applyAIPlan(validated)

        let exported = try await viewModel.exportData()
        let reloaded = try ExcelWorkbookDocument.load(from: exported)
        let sheet = try XCTUnwrap(reloaded.sheets.first)
        XCTAssertEqual(sheet.cell(at: address("A2"))?.displayValue, "연필")
        XCTAssertEqual(sheet.cell(at: address("B2"))?.displayValue, "12")
        XCTAssertEqual(sheet.cell(at: address("A3"))?.displayValue, "공책")
        XCTAssertEqual(sheet.cell(at: address("B3"))?.displayValue, "5")
        XCTAssertEqual(
            ExcelNumberFormat.matching(
                reloaded.style(
                    at: sheet.cell(at: address("B2"))?.styleIndex
                )
            ),
            .integer
        )
    }

    func testExcelAIDoesNotCreateTableOverExistingData() throws {
        let workbook = try ExcelWorkbookDocument.load(
            from: makeWorkbookData()
        )
        let snapshot = try XCTUnwrap(
            ExcelAISnapshotBuilder.make(
                workbookName: "연락처",
                workbook: workbook,
                selectedSheetIndex: 0,
                selectedAddress: nil
            )
        )
        let command = ExcelAICommandPlan(
            intent: .edit,
            assistantMessage: "새 표를 만들었습니다.",
            edits: [],
            appendedRows: [],
            createdTables: [
                .init(
                    startRow: 1,
                    startColumn: 1,
                    headers: ["상품", "수량", "단가", "금액"],
                    blankRowCount: 5
                ),
            ]
        )

        XCTAssertThrowsError(
            try ExcelAICommandValidator.validate(
                command,
                snapshot: snapshot
            )
        ) { error in
            guard case ExcelAICommandValidationError.invalidTarget = error else {
                return XCTFail("잘못된 오류: \(error)")
            }
        }
    }

    func testLoadsSheetsCellsStylesMergesAndTables() throws {
        let workbook = try ExcelWorkbookDocument.load(
            from: makeWorkbookData()
        )

        XCTAssertEqual(workbook.sheets.count, 1)
        let sheet = try XCTUnwrap(workbook.sheets.first)
        XCTAssertEqual(sheet.name, "연락처")
        XCTAssertEqual(
            sheet.cells[ExcelCellAddress(row: 1, column: 1)]?.displayValue,
            "이름"
        )
        XCTAssertTrue(
            workbook.style(
                at: sheet.cells[
                    ExcelCellAddress(row: 1, column: 1)
                ]?.styleIndex
            ).isBold
        )
        XCTAssertEqual(
            sheet.cells[ExcelCellAddress(row: 2, column: 3)]?.formula,
            "1+2"
        )
        XCTAssertEqual(
            sheet.cells[ExcelCellAddress(row: 2, column: 3)]?.displayValue,
            "3"
        )
        XCTAssertEqual(sheet.mergedRanges.first?.reference, "D1:E1")
        XCTAssertEqual(sheet.tables.first?.range.reference, "A1:C2")
        XCTAssertEqual(sheet.columnWidths[1], 20)
    }

    func testSavesIntegerFormatAndKeepsUnderlyingNumber() throws {
        let source = try makeWorkbookData()
        let workbook = try ExcelWorkbookDocument.load(from: source)
        let sheet = try XCTUnwrap(workbook.sheets.first)
        let styleEdit = ExcelStyleEdit(
            styleIndex: workbook.styles.count,
            baseStyleIndex: nil,
            numberFormat: .integer
        )
        let edits = ExcelWorksheetEdits(
            partPath: sheet.partPath,
            cells: [
                address("A2"): ExcelCellEdit(
                    input: .number("1.0"),
                    styleIndex: styleEdit.styleIndex
                ),
            ]
        )

        let saved = try ExcelWorkbookDocument.applying(
            [edits],
            to: source,
            workbook: workbook,
            styleEdits: [styleEdit]
        )
        let reloaded = try ExcelWorkbookDocument.load(from: saved)
        let cell = try XCTUnwrap(
            reloaded.sheets.first?.cell(at: address("A2"))
        )

        XCTAssertEqual(cell.rawValue, "1.0")
        XCTAssertEqual(cell.displayValue, "1")
        XCTAssertEqual(
            reloaded.style(at: cell.styleIndex).numberFormatCode,
            "#,##0"
        )
        XCTAssertTrue(
            try archiveText("xl/styles.xml", in: saved)
                .contains(#"<cellXfs count="3">"#)
        )
        XCTAssertEqual(
            try archiveText("docProps/custom.xml", in: saved),
            "보존할 데이터"
        )
    }

    func testReadsAndPreservesPrintProtectionAndExternalLinkMetadata() throws {
        let source = try makeWorkbookData(
            includeCompatibilityMetadata: true
        )
        let workbook = try ExcelWorkbookDocument.load(from: source)
        let sheet = try XCTUnwrap(workbook.sheets.first)

        XCTAssertTrue(workbook.protection.lockStructure)
        XCTAssertEqual(workbook.protection.workbookPasswordHash, "ABCD")
        XCTAssertTrue(sheet.protection.isEnabled)
        XCTAssertTrue(sheet.protection.protectsObjects)
        XCTAssertEqual(sheet.protection.passwordHash, "CAFE")
        XCTAssertEqual(sheet.printSettings.orientation, .landscape)
        XCTAssertEqual(sheet.printSettings.paperSize, 9)
        XCTAssertEqual(sheet.printSettings.fitToWidth, 1)
        XCTAssertEqual(sheet.printSettings.fitToHeight, 2)
        XCTAssertEqual(sheet.printSettings.margins?.left, 0.25)
        XCTAssertEqual(
            sheet.printSettings.printAreaFormula,
            "'연락처'!$A$1:$C$20"
        )
        XCTAssertEqual(
            sheet.printSettings.printTitlesFormula,
            "'연락처'!$1:$2"
        )
        XCTAssertEqual(workbook.externalLinks.count, 1)
        XCTAssertEqual(
            workbook.externalLinks.first?.sourceTarget,
            "file:///Volumes/Shared/source.xlsx"
        )

        let saved = try ExcelWorkbookDocument.applying(
            [ExcelWorksheetEdits(
                partPath: sheet.partPath,
                cells: [
                    address("A2"): ExcelCellEdit(
                        input: .text("수정됨"),
                        styleIndex: nil
                    ),
                ]
            )],
            to: source,
            workbook: workbook
        )
        let savedSheetXML = try archiveText(
            "xl/worksheets/sheet1.xml",
            in: saved
        )
        let savedWorkbookXML = try archiveText("xl/workbook.xml", in: saved)

        XCTAssertEqual(try archivePaths(in: saved), try archivePaths(in: source))
        XCTAssertTrue(savedSheetXML.contains("<sheetProtection"))
        XCTAssertTrue(savedSheetXML.contains("<pageMargins"))
        XCTAssertTrue(savedSheetXML.contains("<pageSetup"))
        XCTAssertTrue(savedSheetXML.contains("<headerFooter>"))
        XCTAssertTrue(savedSheetXML.contains("opaquePayload"))
        XCTAssertTrue(savedWorkbookXML.contains("<workbookProtection"))
        XCTAssertTrue(savedWorkbookXML.contains("<externalReferences>"))
        for path in [
            "customXml/item1.xml",
            "xl/externalLinks/externalLink1.xml",
            "xl/externalLinks/_rels/externalLink1.xml.rels",
        ] {
            XCTAssertEqual(
                try archiveText(path, in: saved),
                try archiveText(path, in: source)
            )
        }
    }

    func testStyleOnlyEditPreservesFormulaAndCachedValue() throws {
        let source = try makeWorkbookData()
        let workbook = try ExcelWorkbookDocument.load(from: source)
        let sheet = try XCTUnwrap(workbook.sheets.first)
        let styleEdit = ExcelStyleEdit(
            styleIndex: workbook.styles.count,
            baseStyleIndex: nil,
            numberFormat: .integer
        )
        let edits = ExcelWorksheetEdits(
            partPath: sheet.partPath,
            cells: [
                address("C2"): ExcelCellEdit(
                    input: .formula("1+2"),
                    styleIndex: styleEdit.styleIndex,
                    preservesExistingContent: true
                ),
            ]
        )

        let saved = try ExcelWorkbookDocument.applying(
            [edits],
            to: source,
            workbook: workbook,
            styleEdits: [styleEdit]
        )
        let sheetXML = try archiveText(
            "xl/worksheets/sheet1.xml",
            in: saved
        )
        let reloaded = try ExcelWorkbookDocument.load(from: saved)
        let cell = try XCTUnwrap(
            reloaded.sheets.first?.cell(at: address("C2"))
        )

        XCTAssertTrue(sheetXML.contains("<f>1+2</f><v>3</v>"))
        XCTAssertEqual(cell.formula, "1+2")
        XCTAssertEqual(cell.rawValue, "3")
        XCTAssertEqual(cell.displayValue, "3")
    }

    func testSavesAndReloadsInlineListDataValidation() throws {
        let source = try makeWorkbookData()
        let workbook = try ExcelWorkbookDocument.load(from: source)
        let sheet = try XCTUnwrap(workbook.sheets.first)
        let rule = ExcelDataValidationRule.inlineList(
            ranges: [ExcelCellRange("B2:B4")!],
            values: ["재학", "전학", "졸업"],
            allowsBlank: true
        )

        let saved = try ExcelWorkbookDocument.applying(
            [],
            to: source,
            workbook: workbook,
            validationEdits: [
                ExcelWorksheetValidationEdits(
                    partPath: sheet.partPath,
                    rules: [rule]
                ),
            ]
        )
        let sheetXML = try archiveText(
            "xl/worksheets/sheet1.xml",
            in: saved
        )
        let reloaded = try ExcelWorkbookDocument.load(from: saved)
        let loadedRule = try XCTUnwrap(
            reloaded.sheets.first?.dataValidations.first
        )

        XCTAssertEqual(loadedRule.type, "list")
        XCTAssertEqual(loadedRule.inlineListValues, ["재학", "전학", "졸업"])
        XCTAssertTrue(loadedRule.allowsBlank)
        XCTAssertTrue(loadedRule.contains(address("B3")))
        XCTAssertTrue(sheetXML.contains(#"<dataValidations count="1">"#))
        XCTAssertTrue(sheetXML.contains(#"sqref="B2:B4""#))
        XCTAssertLessThan(
            try XCTUnwrap(sheetXML.range(of: "<dataValidations")?.lowerBound),
            try XCTUnwrap(sheetXML.range(of: "<tableParts")?.lowerBound)
        )
    }

    func testValidationWriterPreservesSpreadsheetPrefix() throws {
        let source = try makeWorkbookData(
            usesSpreadsheetNamespacePrefix: true
        )
        let workbook = try ExcelWorkbookDocument.load(from: source)
        let sheet = try XCTUnwrap(workbook.sheets.first)
        let rule = ExcelDataValidationRule.inlineList(
            ranges: [ExcelCellRange("A2")!],
            values: ["예", "아니요"],
            allowsBlank: false
        )

        let saved = try ExcelWorkbookDocument.applying(
            [],
            to: source,
            workbook: workbook,
            validationEdits: [
                ExcelWorksheetValidationEdits(
                    partPath: sheet.partPath,
                    rules: [rule]
                ),
            ]
        )
        let sheetXML = try archiveText(
            "xl/worksheets/sheet1.xml",
            in: saved
        )

        XCTAssertTrue(sheetXML.contains("<x:dataValidations"))
        XCTAssertTrue(sheetXML.contains("<x:dataValidation"))
        XCTAssertTrue(sheetXML.contains("<x:formula1>"))
        XCTAssertFalse(sheetXML.contains("<dataValidation "))
    }

    func testValidationRoundTripKeepsUnsupportedRulesAndX14Extension() throws {
        let source =
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
              xmlns:x14="http://schemas.microsoft.com/office/spreadsheetml/2009/9/main">
              <sheetData/>
              <dataValidations count="1">
                <dataValidation type="whole" operator="between" sqref="A:A">
                  <formula1>1</formula1><formula2>10</formula2>
                </dataValidation>
              </dataValidations>
              <extLst><ext uri="test"><x14:dataValidations count="0"/></ext></extLst>
            </worksheet>
            """
        let rules = try ExcelDataValidationXMLParser.parse(Data(source.utf8))
        let rule = try XCTUnwrap(rules.first)

        XCTAssertEqual(rule.type, "whole")
        XCTAssertEqual(rule.unparsedRangeReferences, ["A:A"])
        XCTAssertEqual(rule.formula1, "1")
        XCTAssertEqual(rule.formula2, "10")

        let saved = try ExcelDataValidationXMLWriter.applying(
            rules,
            to: source
        )
        XCTAssertTrue(saved.contains(#"sqref="A:A""#))
        XCTAssertTrue(saved.contains("<formula2>10</formula2>"))
        XCTAssertTrue(saved.contains("<x14:dataValidations count=\"0\"/>"))
    }

    func testSavesAndReloadsConditionalFormattingAndDifferentialStyle()
        throws {
        let source = try makeWorkbookData()
        let workbook = try ExcelWorkbookDocument.load(from: source)
        let sheet = try XCTUnwrap(workbook.sheets.first)
        let style = ExcelConditionalHighlight.yellow.style
        let block = ExcelConditionalFormattingBlock(
            ranges: [ExcelCellRange("C2:C4")!],
            rules: [
                ExcelConditionalFormattingRule(
                    kind: .greaterThan,
                    comparisonValue: "2",
                    differentialStyleIndex: 0,
                    priority: 1
                ),
            ]
        )

        let saved = try ExcelWorkbookDocument.applying(
            [],
            to: source,
            workbook: workbook,
            conditionalFormattingEdits: [
                ExcelWorksheetConditionalFormattingEdits(
                    partPath: sheet.partPath,
                    blocks: [block]
                ),
            ],
            differentialStyleEdits: [
                ExcelDifferentialStyleEdit(styleIndex: 0, style: style),
            ]
        )
        let reloaded = try ExcelWorkbookDocument.load(from: saved)
        let loadedSheet = try XCTUnwrap(reloaded.sheets.first)
        let loadedRule = try XCTUnwrap(
            loadedSheet.conditionalFormatting.first?.rules.first
        )

        XCTAssertEqual(loadedRule.kind, .greaterThan)
        XCTAssertEqual(loadedRule.comparisonValue, "2")
        XCTAssertEqual(reloaded.differentialStyles, [style])
        XCTAssertTrue(loadedRule.matches(loadedSheet.cell(at: address("C2"))))
        XCTAssertEqual(
            loadedSheet.matchingConditionalRule(at: address("C2"))?.id,
            loadedRule.id
        )
        XCTAssertTrue(
            try archiveText("xl/styles.xml", in: saved)
                .contains(#"<dxfs count="1">"#)
        )
        XCTAssertTrue(
            try archiveText("xl/worksheets/sheet1.xml", in: saved)
                .contains(#"<conditionalFormatting sqref="C2:C4">"#)
        )
    }

    func testConditionalFormattingPreservesUnsupportedColorScale() throws {
        let source =
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
              <sheetData/>
              <conditionalFormatting sqref="A1:A10">
                <cfRule type="colorScale" priority="1">
                  <colorScale><cfvo type="min"/><cfvo type="max"/><color rgb="FFFF0000"/><color rgb="FF00FF00"/></colorScale>
                </cfRule>
              </conditionalFormatting>
            </worksheet>
            """
        let blocks = try ExcelConditionalFormattingXMLParser.parse(source)
        let block = try XCTUnwrap(blocks.first)

        XCTAssertFalse(block.isEditable)
        XCTAssertTrue(block.rules.isEmpty)

        let saved = try ExcelConditionalFormattingXMLWriter.applying(
            blocks,
            to: source
        )
        XCTAssertTrue(saved.contains("<colorScale>"))
        XCTAssertTrue(saved.contains(#"<cfvo type="max"/>"#))
        XCTAssertTrue(saved.contains(#"sqref="A1:A10""#))
    }

    @MainActor
    func testHyperlinkAndNoteSupportUndoRedoExportAndReload() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("xlsx")
        try makeWorkbookData().write(to: fileURL)
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }
        let viewModel = ExcelWorkbookViewModel(fileURL: fileURL)
        await viewModel.load()
        viewModel.selectCell(address("A2"))

        XCTAssertTrue(
            viewModel.applyCellAnnotations(
                hyperlinkTarget: "https://example.com/student?id=1&lang=ko",
                hyperlinkTooltip: "학생 상세 정보",
                noteText: "보호자 확인이 필요합니다.",
                noteAuthor: "담임 교사"
            )
        )
        XCTAssertEqual(
            viewModel.selectedHyperlink?.target,
            "https://example.com/student?id=1&lang=ko"
        )
        XCTAssertEqual(viewModel.selectedNote?.author, "담임 교사")
        XCTAssertTrue(viewModel.hasUnsavedChanges)

        viewModel.undo()
        XCTAssertNil(viewModel.selectedHyperlink)
        XCTAssertNil(viewModel.selectedNote)
        viewModel.redo()
        XCTAssertNotNil(viewModel.selectedHyperlink)
        XCTAssertNotNil(viewModel.selectedNote)

        let commentsPath = try XCTUnwrap(
            viewModel.selectedSheet?.annotations.commentsPartPath
        )
        let vmlPath = try XCTUnwrap(
            viewModel.selectedSheet?.annotations.vmlDrawingPartPath
        )
        let exported = try await viewModel.exportData()
        let archive = try Archive(data: exported, accessMode: .read)

        XCTAssertNotNil(archive[commentsPath])
        XCTAssertNotNil(archive[vmlPath])
        XCTAssertNotNil(
            archive["xl/worksheets/_rels/sheet1.xml.rels"]
        )
        XCTAssertTrue(
            try archiveText("[Content_Types].xml", in: exported)
                .contains("spreadsheetml.comments+xml")
        )
        XCTAssertTrue(
            try archiveText("xl/worksheets/sheet1.xml", in: exported)
                .contains("<hyperlinks>")
        )
        XCTAssertTrue(
            try archiveText(
                "xl/worksheets/_rels/sheet1.xml.rels",
                in: exported
            ).contains("relationships/hyperlink")
        )

        let reloaded = try ExcelWorkbookDocument.load(from: exported)
        let annotations = try XCTUnwrap(reloaded.sheets.first?.annotations)
        XCTAssertEqual(
            annotations.hyperlink(at: address("A2"))?.target,
            "https://example.com/student?id=1&lang=ko"
        )
        XCTAssertEqual(
            annotations.hyperlink(at: address("A2"))?.tooltip,
            "학생 상세 정보"
        )
        XCTAssertEqual(
            annotations.note(at: address("A2"))?.text,
            "보호자 확인이 필요합니다."
        )
        XCTAssertEqual(
            annotations.note(at: address("A2"))?.author,
            "담임 교사"
        )
    }

    @MainActor
    func testInternalHyperlinkRoundTripAndAnnotationRemoval() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("xlsx")
        try makeWorkbookData().write(to: fileURL)
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }
        let viewModel = ExcelWorkbookViewModel(fileURL: fileURL)
        await viewModel.load()
        viewModel.selectCell(address("B2"))
        XCTAssertTrue(
            viewModel.applyCellAnnotations(
                hyperlinkTarget: "#연락처!A1",
                hyperlinkTooltip: "첫 셀로 이동",
                noteText: "임시 메모",
                noteAuthor: "VisionCraft"
            )
        )

        let firstExport = try await viewModel.exportData()
        let firstReload = try ExcelWorkbookDocument.load(from: firstExport)
        XCTAssertEqual(
            firstReload.sheets.first?.annotations
                .hyperlink(at: address("B2"))?.target,
            "#연락처!A1"
        )

        XCTAssertTrue(
            viewModel.applyCellAnnotations(
                hyperlinkTarget: "",
                hyperlinkTooltip: "",
                noteText: "",
                noteAuthor: "VisionCraft"
            )
        )
        let removedExport = try await viewModel.exportData()
        let removedReload = try ExcelWorkbookDocument.load(from: removedExport)
        XCTAssertNil(
            removedReload.sheets.first?.annotations
                .hyperlink(at: address("B2"))
        )
        XCTAssertNil(
            removedReload.sheets.first?.annotations.note(at: address("B2"))
        )
    }

    @MainActor
    func testSheetImageSupportsAddReplaceUndoRedoAndReload() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("xlsx")
        try makeWorkbookData().write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let viewModel = ExcelWorkbookViewModel(fileURL: fileURL)
        await viewModel.load()
        viewModel.selectCell(address("B2"))
        let redImage = makeTestImageData(color: .red)
        let blueImage = makeTestImageData(color: .blue)

        XCTAssertTrue(viewModel.addSheetImage(data: redImage))
        let imageID = try XCTUnwrap(viewModel.selectedSheetImages.first?.id)
        XCTAssertEqual(
            viewModel.selectedSheetImages.first?.anchor.start,
            address("B2")
        )
        XCTAssertTrue(
            viewModel.replaceSheetImage(id: imageID, data: blueImage)
        )
        XCTAssertNotEqual(viewModel.selectedSheetImages.first?.data, redImage)

        viewModel.undo()
        XCTAssertEqual(viewModel.selectedSheetImages.first?.data, redImage)
        viewModel.redo()
        XCTAssertNotEqual(viewModel.selectedSheetImages.first?.data, redImage)

        let exported = try await viewModel.exportData()
        let reloaded = try ExcelWorkbookDocument.load(from: exported)
        let objects = try XCTUnwrap(reloaded.sheets.first?.drawingObjects)
        let loadedImage = try XCTUnwrap(objects.images.first)
        XCTAssertEqual(loadedImage.anchor.start, address("B2"))
        XCTAssertEqual(loadedImage.anchor.end, address("D7"))
        XCTAssertEqual(loadedImage.contentType, "image/png")
        XCTAssertNotEqual(loadedImage.data, redImage)
        XCTAssertTrue(
            try archiveText("xl/worksheets/sheet1.xml", in: exported)
                .contains("<drawing r:id=")
        )
        XCTAssertTrue(
            try archiveText(
                try XCTUnwrap(objects.drawingPartPath),
                in: exported
            ).contains("<xdr:pic>")
        )
        let contentTypes = try archiveText("[Content_Types].xml", in: exported)
        XCTAssertTrue(contentTypes.contains("drawing+xml"))
        XCTAssertTrue(contentTypes.contains("image/png"))
    }

    @MainActor
    func testRemovingImagePreservesChartAndPivotTableParts() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("xlsx")
        try makeWorkbookData(includeDrawingObjects: true).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let viewModel = ExcelWorkbookViewModel(fileURL: fileURL)
        await viewModel.load()

        XCTAssertEqual(viewModel.selectedSheetImages.count, 1)
        XCTAssertEqual(viewModel.selectedSheetChartCount, 1)
        XCTAssertEqual(viewModel.selectedSheetPivotTableCount, 1)
        let imageID = try XCTUnwrap(viewModel.selectedSheetImages.first?.id)
        viewModel.removeSheetImage(id: imageID)
        XCTAssertTrue(viewModel.selectedSheetImages.isEmpty)

        let exported = try await viewModel.exportData()
        let drawingXML = try archiveText(
            "xl/drawings/drawing1.xml",
            in: exported
        )
        XCTAssertFalse(drawingXML.contains("<xdr:pic>"))
        XCTAssertTrue(drawingXML.contains("<xdr:graphicFrame>"))
        XCTAssertEqual(
            try archiveText("xl/charts/chart1.xml", in: exported),
            "CHART_KEEP"
        )
        XCTAssertEqual(
            try archiveText(
                "xl/pivotTables/pivotTable1.xml",
                in: exported
            ),
            "PIVOT_KEEP"
        )
        let reloaded = try ExcelWorkbookDocument.load(from: exported)
        let objects = try XCTUnwrap(reloaded.sheets.first?.drawingObjects)
        XCTAssertTrue(objects.images.isEmpty)
        XCTAssertEqual(objects.chartCount, 1)
        XCTAssertEqual(objects.pivotTableCount, 1)
    }

    @MainActor
    func testChartSupportsAddEditUndoRedoExportAndRemoval() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("xlsx")
        try makeWorkbookData().write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let viewModel = ExcelWorkbookViewModel(fileURL: fileURL)
        await viewModel.load()

        XCTAssertTrue(
            viewModel.addSheetChart(
                title: "연락처 현황",
                kind: .column,
                sourceReference: "A1:C2"
            )
        )
        let chartID = try XCTUnwrap(viewModel.selectedSheetCharts.first?.id)
        XCTAssertEqual(viewModel.selectedSheetChartCount, 1)
        XCTAssertTrue(
            viewModel.updateSheetChart(
                id: chartID,
                title: "연락처 추이",
                kind: .line,
                sourceReference: "A1:C2"
            )
        )
        XCTAssertEqual(viewModel.selectedSheetCharts.first?.kind, .line)

        viewModel.undo()
        XCTAssertEqual(viewModel.selectedSheetCharts.first?.kind, .column)
        viewModel.redo()
        XCTAssertEqual(viewModel.selectedSheetCharts.first?.kind, .line)

        let exported = try await viewModel.exportData()
        let reloaded = try ExcelWorkbookDocument.load(from: exported)
        let chart = try XCTUnwrap(
            reloaded.sheets.first?.drawingObjects.charts.first
        )
        XCTAssertEqual(chart.title, "연락처 추이")
        XCTAssertEqual(chart.kind, .line)
        XCTAssertEqual(chart.sourceRange?.reference, "A1:C2")
        let chartXML = try archiveText(chart.chartPartPath, in: exported)
        XCTAssertTrue(XMLParser(data: Data(chartXML.utf8)).parse())
        XCTAssertTrue(chartXML.contains("<c:lineChart>"))
        XCTAssertTrue(chartXML.contains("'연락처'!$A$2"))
        XCTAssertTrue(chartXML.contains("'연락처'!$B$2"))
        XCTAssertTrue(
            try archiveText("[Content_Types].xml", in: exported)
                .contains("drawingml.chart+xml")
        )

        viewModel.removeSheetChart(id: chartID)
        XCTAssertTrue(viewModel.selectedSheetCharts.isEmpty)
        let removedExport = try await viewModel.exportData()
        let removedReload = try ExcelWorkbookDocument.load(
            from: removedExport
        )
        XCTAssertTrue(
            removedReload.sheets.first?.drawingObjects.charts.isEmpty == true
        )
    }

    @MainActor
    func testCreatesAllSupportedChartKinds() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("xlsx")
        try makeWorkbookData().write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let viewModel = ExcelWorkbookViewModel(fileURL: fileURL)
        await viewModel.load()
        let kinds: [ExcelChartKind] = [
            .column, .bar, .line, .pie,
            .area, .scatter, .doughnut, .radar,
        ]
        for kind in kinds {
            XCTAssertTrue(
                viewModel.addSheetChart(
                    title: kind.title,
                    kind: kind,
                    sourceReference: "A1:C2"
                )
            )
        }

        let exported = try await viewModel.exportData()
        let reloaded = try ExcelWorkbookDocument.load(from: exported)
        let charts = try XCTUnwrap(
            reloaded.sheets.first?.drawingObjects.charts
        )
        XCTAssertEqual(charts.map(\.kind), kinds)
        XCTAssertEqual(Set(charts.map(\.anchor.start.row)).count, kinds.count)
        for chart in charts {
            let xml = try archiveText(chart.chartPartPath, in: exported)
            XCTAssertTrue(XMLParser(data: Data(xml.utf8)).parse())
        }
    }

    @MainActor
    func testShapeAndTextBoxSupportAddEditUndoExportAndRemoval() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("xlsx")
        try makeWorkbookData().write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let viewModel = ExcelWorkbookViewModel(fileURL: fileURL)
        await viewModel.load()
        viewModel.selectCell(address("B2"))

        XCTAssertTrue(viewModel.addSheetShape(
            name: "안내 상자",
            text: "첫 줄\n둘째 줄",
            kind: .textBox
        ))
        let shapeID = try XCTUnwrap(viewModel.selectedSheetShapes.first?.id)
        XCTAssertEqual(
            viewModel.selectedSheetShapes.first?.anchor.start,
            address("B2")
        )
        XCTAssertTrue(viewModel.updateSheetShape(
            id: shapeID,
            name: "강조 안내",
            text: "수정된 내용",
            kind: .roundedRectangle
        ))
        viewModel.undo()
        XCTAssertEqual(viewModel.selectedSheetShapes.first?.kind, .textBox)
        viewModel.redo()
        XCTAssertEqual(
            viewModel.selectedSheetShapes.first?.kind,
            .roundedRectangle
        )

        let exported = try await viewModel.exportData()
        let reloaded = try ExcelWorkbookDocument.load(from: exported)
        let loaded = try XCTUnwrap(
            reloaded.sheets.first?.drawingObjects.shapes.first
        )
        XCTAssertEqual(loaded.name, "강조 안내")
        XCTAssertEqual(loaded.text, "수정된 내용")
        XCTAssertEqual(loaded.kind, .roundedRectangle)
        XCTAssertEqual(loaded.anchor.start, address("B2"))
        let drawingPath = try XCTUnwrap(
            reloaded.sheets.first?.drawingObjects.drawingPartPath
        )
        let drawingXML = try archiveText(drawingPath, in: exported)
        XCTAssertTrue(XMLParser(data: Data(drawingXML.utf8)).parse())
        XCTAssertTrue(drawingXML.contains("<xdr:sp"))
        XCTAssertTrue(drawingXML.contains("prst=\"roundRect\""))
        XCTAssertTrue(drawingXML.contains("수정된 내용"))

        viewModel.removeSheetShape(id: shapeID)
        XCTAssertTrue(viewModel.selectedSheetShapes.isEmpty)
        let removed = try await viewModel.exportData()
        let removedReload = try ExcelWorkbookDocument.load(from: removed)
        XCTAssertTrue(
            removedReload.sheets.first?.drawingObjects.shapes.isEmpty == true
        )
    }

    @MainActor
    func testRemovingExistingChartPreservesImageAndPivotTable() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("xlsx")
        try makeWorkbookData(includeDrawingObjects: true).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let viewModel = ExcelWorkbookViewModel(fileURL: fileURL)
        await viewModel.load()
        let chartID = try XCTUnwrap(viewModel.selectedSheetCharts.first?.id)

        viewModel.removeSheetChart(id: chartID)
        let exported = try await viewModel.exportData()
        let drawingXML = try archiveText(
            "xl/drawings/drawing1.xml",
            in: exported
        )
        XCTAssertFalse(drawingXML.contains("<xdr:graphicFrame>"))
        XCTAssertTrue(drawingXML.contains("<xdr:pic>"))
        XCTAssertEqual(
            try archiveText("xl/media/image1.png", in: exported),
            "ORIGINAL_IMAGE"
        )
        XCTAssertEqual(
            try archiveText(
                "xl/pivotTables/pivotTable1.xml",
                in: exported
            ),
            "PIVOT_KEEP"
        )
        let reloaded = try ExcelWorkbookDocument.load(from: exported)
        let objects = try XCTUnwrap(reloaded.sheets.first?.drawingObjects)
        XCTAssertTrue(objects.charts.isEmpty)
        XCTAssertEqual(objects.images.count, 1)
        XCTAssertEqual(objects.pivotTableCount, 1)
    }

    @MainActor
    func testPivotSupportsAddEditUndoRedoExportAndReload() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("xlsx")
        try makeWorkbookData().write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let viewModel = ExcelWorkbookViewModel(fileURL: fileURL)
        await viewModel.load()

        XCTAssertEqual(
            viewModel.pivotFieldNames(sourceReference: "A1:C2"),
            ["이름", "전화번호", "비고"]
        )
        XCTAssertTrue(
            viewModel.addPivotTable(
                name: "연락처 요약",
                sourceReference: "A1:C2",
                destinationReference: "G1",
                rowFieldIndex: 0,
                dataFieldIndex: 2,
                aggregation: .sum,
                refreshOnLoad: true
            )
        )
        let pivotID = try XCTUnwrap(
            viewModel.selectedSheetPivotTables.first?.id
        )
        XCTAssertEqual(viewModel.selectedSheetPivotTableCount, 1)
        XCTAssertEqual(
            viewModel.selectedSheet?.cells[address("G1")]?.displayValue,
            "연락처 요약"
        )
        XCTAssertEqual(
            viewModel.selectedSheet?.cells[address("H3")]?.rawValue,
            "3"
        )

        XCTAssertTrue(
            viewModel.updatePivotTable(
                id: pivotID,
                name: "연락처 개수",
                sourceReference: "A1:C2",
                destinationReference: "G1",
                rowFieldIndex: 0,
                dataFieldIndex: 2,
                aggregation: .count,
                refreshOnLoad: false
            )
        )
        XCTAssertEqual(
            viewModel.selectedSheet?.cells[address("H3")]?.rawValue,
            "1"
        )
        viewModel.undo()
        XCTAssertEqual(
            viewModel.selectedSheetPivotTables.first?.aggregation,
            .sum
        )
        XCTAssertEqual(
            viewModel.selectedSheet?.cells[address("H3")]?.rawValue,
            "3"
        )
        viewModel.redo()
        XCTAssertEqual(
            viewModel.selectedSheetPivotTables.first?.aggregation,
            .count
        )

        let exported = try await viewModel.exportData()
        let reloaded = try ExcelWorkbookDocument.load(from: exported)
        let pivot = try XCTUnwrap(reloaded.sheets.first?.pivotTables.first)
        XCTAssertEqual(pivot.name, "연락처 개수")
        XCTAssertEqual(pivot.sourceSheetName, "연락처")
        XCTAssertEqual(pivot.sourceRange?.reference, "A1:C2")
        XCTAssertEqual(pivot.destinationRange?.reference, "G1:H4")
        XCTAssertEqual(pivot.fieldNames, ["이름", "전화번호", "비고"])
        XCTAssertEqual(pivot.rowFieldIndex, 0)
        XCTAssertEqual(pivot.dataFieldIndex, 2)
        XCTAssertEqual(pivot.aggregation, .count)
        XCTAssertFalse(pivot.refreshOnLoad)

        let pivotXML = try archiveText(pivot.partPath, in: exported)
        let cachePath = try XCTUnwrap(pivot.cacheDefinitionPath)
        let cacheXML = try archiveText(cachePath, in: exported)
        XCTAssertTrue(XMLParser(data: Data(pivotXML.utf8)).parse())
        XCTAssertTrue(XMLParser(data: Data(cacheXML.utf8)).parse())
        XCTAssertTrue(pivotXML.contains("subtotal=\"count\""))
        XCTAssertTrue(cacheXML.contains("refreshOnLoad=\"0\""))
        XCTAssertTrue(
            try archiveText("xl/workbook.xml", in: exported)
                .contains("<pivotCaches>")
        )
        XCTAssertTrue(
            try archiveText("[Content_Types].xml", in: exported)
                .contains("pivotCacheDefinition+xml")
        )
    }

    @MainActor
    func testRemovingExistingPivotPreservesImageAndChart() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("xlsx")
        try makeWorkbookData(includeDrawingObjects: true).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let viewModel = ExcelWorkbookViewModel(fileURL: fileURL)
        await viewModel.load()
        let pivotID = try XCTUnwrap(
            viewModel.selectedSheetPivotTables.first?.id
        )

        viewModel.removePivotTable(id: pivotID)
        XCTAssertEqual(viewModel.selectedSheetPivotTableCount, 0)
        let exported = try await viewModel.exportData()
        let reloaded = try ExcelWorkbookDocument.load(from: exported)
        let objects = try XCTUnwrap(reloaded.sheets.first?.drawingObjects)
        XCTAssertTrue(reloaded.sheets.first?.pivotTables.isEmpty == true)
        XCTAssertEqual(objects.images.count, 1)
        XCTAssertEqual(objects.charts.count, 1)
        XCTAssertEqual(
            try archiveText("xl/media/image1.png", in: exported),
            "ORIGINAL_IMAGE"
        )
        XCTAssertEqual(
            try archiveText("xl/charts/chart1.xml", in: exported),
            "CHART_KEEP"
        )
    }

    @MainActor
    func testConditionalFormattingSupportsUndoRedoAndExport() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("xlsx")
        try makeWorkbookData().write(to: fileURL)
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }
        let viewModel = ExcelWorkbookViewModel(fileURL: fileURL)
        await viewModel.load()
        viewModel.selectCell(address("C2"))

        XCTAssertTrue(
            viewModel.applyConditionalFormatting(
                kind: .greaterThan,
                comparisonValue: "2",
                highlight: .green,
                toCurrentColumn: false
            )
        )
        XCTAssertEqual(viewModel.selectedConditionalFormattingCount, 1)
        XCTAssertNotNil(
            viewModel.selectedSheet?.matchingConditionalRule(
                at: address("C2")
            )
        )
        viewModel.undo()
        XCTAssertEqual(viewModel.selectedConditionalFormattingCount, 0)
        viewModel.redo()
        XCTAssertEqual(viewModel.selectedConditionalFormattingCount, 1)

        let exported = try await viewModel.exportData()
        let reloaded = try ExcelWorkbookDocument.load(from: exported)
        let reloadedSheet = try XCTUnwrap(reloaded.sheets.first)
        let rule = try XCTUnwrap(
            reloadedSheet.matchingConditionalRule(at: address("C2"))
        )
        XCTAssertEqual(rule.kind, .greaterThan)
        XCTAssertEqual(
            ExcelConditionalHighlight.matching(
                reloaded.differentialStyles[rule.differentialStyleIndex]
            ),
            .green
        )
    }

    @MainActor
    func testDropdownEditSupportsWarningUndoRedoAndExport() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("xlsx")
        try makeWorkbookData().write(to: fileURL)
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }
        let viewModel = ExcelWorkbookViewModel(fileURL: fileURL)
        await viewModel.load()
        viewModel.selectCell(address("B2"))

        XCTAssertTrue(
            viewModel.applyDropdown(
                values: ["보호자", "학생"],
                allowsBlank: false,
                toCurrentColumn: false
            )
        )
        XCTAssertEqual(viewModel.selectedDropdownValues, ["보호자", "학생"])
        XCTAssertNotNil(viewModel.validationWarning)
        XCTAssertTrue(viewModel.hasUnsavedChanges)

        viewModel.chooseDropdownValue("학생")
        XCTAssertNil(viewModel.validationWarning)
        viewModel.undo()
        XCTAssertNotNil(viewModel.validationWarning)
        viewModel.undo()
        XCTAssertTrue(viewModel.selectedDropdownValues.isEmpty)
        viewModel.redo()
        XCTAssertEqual(viewModel.selectedDropdownValues, ["보호자", "학생"])
        viewModel.redo()
        XCTAssertNil(viewModel.validationWarning)

        let exported = try await viewModel.exportData()
        let reloaded = try ExcelWorkbookDocument.load(from: exported)
        let reloadedSheet = try XCTUnwrap(reloaded.sheets.first)
        XCTAssertEqual(
            reloadedSheet.cell(at: address("B2"))?.displayValue,
            "학생"
        )
        XCTAssertEqual(
            reloadedSheet.dataValidations.first?.inlineListValues,
            ["보호자", "학생"]
        )
    }

    func testCustomFormatWriterPreservesSpreadsheetPrefix() throws {
        let source = try makeWorkbookData(
            usesSpreadsheetNamespacePrefix: true
        )
        let workbook = try ExcelWorkbookDocument.load(from: source)
        let styleEdit = ExcelStyleEdit(
            styleIndex: workbook.styles.count,
            baseStyleIndex: nil,
            numberFormat: .currencyWon
        )

        let saved = try ExcelWorkbookDocument.applying(
            [],
            to: source,
            workbook: workbook,
            styleEdits: [styleEdit]
        )
        let stylesXML = try archiveText("xl/styles.xml", in: saved)

        XCTAssertTrue(stylesXML.contains("<x:numFmts count=\"1\">"))
        XCTAssertTrue(stylesXML.contains("<x:numFmt "))
        XCTAssertTrue(stylesXML.contains("₩"))
        XCTAssertTrue(stylesXML.contains("<x:cellXfs count=\"3\">"))
        XCTAssertFalse(stylesXML.contains("<numFmt "))
    }

    func testSelectedDateAndTimeFormatsMatchTheirMenuExamples() {
        let dateStyle = ExcelCellStyle(
            numberFormatID: ExcelNumberFormat.date.displayNumberFormatID,
            numberFormatCode: ExcelNumberFormat.date.formatCode,
            isBold: false,
            fillARGB: nil,
            horizontalAlignment: nil
        )
        let timeStyle = ExcelCellStyle(
            numberFormatID: ExcelNumberFormat.time.displayNumberFormatID,
            numberFormatCode: ExcelNumberFormat.time.formatCode,
            isBold: false,
            fillARGB: nil,
            horizontalAlignment: nil
        )

        XCTAssertEqual(
            ExcelValueFormatter.displayValue(
                "46265",
                type: nil,
                style: dateStyle,
                uses1904DateSystem: false
            ),
            "2026-08-31"
        )
        XCTAssertEqual(
            ExcelValueFormatter.displayValue(
                "0.6041666667",
                type: nil,
                style: timeStyle,
                uses1904DateSystem: false
            ),
            "14:30"
        )
    }

    @MainActor
    func testViewModelNumberFormatSupportsUndoAndRedo() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ExcelFormatViewModelTests-\(UUID().uuidString).xlsx"
            )
        try makeWorkbookData().write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let viewModel = ExcelWorkbookViewModel(fileURL: fileURL)
        await viewModel.load()
        viewModel.selectCell(address("C2"))

        viewModel.applyNumberFormat(.integer, toCurrentColumn: false)

        XCTAssertEqual(viewModel.selectedNumberFormat, .integer)
        XCTAssertEqual(viewModel.selectedCell?.formula, "1+2")
        XCTAssertEqual(viewModel.selectedCell?.rawValue, "3")
        XCTAssertTrue(viewModel.hasUnsavedChanges)
        XCTAssertTrue(viewModel.canUndo)

        viewModel.undo()
        XCTAssertEqual(viewModel.selectedCell?.styleIndex, nil)
        XCTAssertEqual(viewModel.selectedCell?.formula, "1+2")
        XCTAssertFalse(viewModel.hasUnsavedChanges)
        let revertedExport = try await viewModel.exportData()
        XCTAssertEqual(
            try ExcelWorkbookDocument.load(from: revertedExport)
                .styles.count,
            2
        )

        viewModel.redo()
        XCTAssertEqual(viewModel.selectedNumberFormat, .integer)
        XCTAssertEqual(viewModel.selectedCell?.formula, "1+2")
        await viewModel.save()
        let reloaded = try ExcelWorkbookDocument.load(
            from: Data(contentsOf: fileURL)
        )
        let savedCell = try XCTUnwrap(
            reloaded.sheets.first?.cell(at: address("C2"))
        )
        XCTAssertEqual(savedCell.formula, "1+2")
        XCTAssertEqual(
            ExcelNumberFormat.matching(
                reloaded.style(at: savedCell.styleIndex)
            ),
            .integer
        )
    }

    func testEditsCellsAppendsRowAndPreservesPackageParts() throws {
        let source = try makeWorkbookData()
        let workbook = try ExcelWorkbookDocument.load(from: source)
        let sheet = try XCTUnwrap(workbook.sheets.first)
        let edits = ExcelWorksheetEdits(
            partPath: sheet.partPath,
            cells: [
                ExcelCellAddress(row: 2, column: 1):
                    ExcelCellEdit(
                        input: .text("김영희"),
                        styleIndex: 1
                    ),
                ExcelCellAddress(row: 3, column: 1):
                    ExcelCellEdit(
                        input: .text("박철수"),
                        styleIndex: 1
                    ),
                ExcelCellAddress(row: 3, column: 2):
                    ExcelCellEdit(
                        input: .text("010-1234-5678"),
                        styleIndex: nil
                    ),
                ExcelCellAddress(row: 3, column: 3):
                    ExcelCellEdit(
                        input: .formula("1+4"),
                        styleIndex: nil
                    ),
            ]
        )

        let saved = try ExcelWorkbookDocument.applying(
            [edits],
            to: source,
            workbook: workbook
        )
        let reloaded = try ExcelWorkbookDocument.load(from: saved)
        let reloadedSheet = try XCTUnwrap(reloaded.sheets.first)

        XCTAssertEqual(
            reloadedSheet.cells[
                ExcelCellAddress(row: 2, column: 1)
            ]?.displayValue,
            "김영희"
        )
        XCTAssertEqual(
            reloadedSheet.cells[
                ExcelCellAddress(row: 3, column: 2)
            ]?.displayValue,
            "010-1234-5678"
        )
        XCTAssertEqual(
            reloadedSheet.cells[
                ExcelCellAddress(row: 3, column: 3)
            ]?.formula,
            "1+4"
        )
        XCTAssertEqual(reloadedSheet.tables.first?.range.reference, "A1:C3")
        XCTAssertEqual(
            try archiveText("docProps/custom.xml", in: saved),
            "보존할 데이터"
        )
        XCTAssertTrue(
            try archiveText("xl/workbook.xml", in: saved)
                .contains("fullCalcOnLoad=\"1\"")
        )
    }

    func testEditsPrefixedSpreadsheetNamespaceAndPreservesPrefixes() throws {
        let source = try makeWorkbookData(
            usesSpreadsheetNamespacePrefix: true
        )
        let workbook = try ExcelWorkbookDocument.load(from: source)
        let sheet = try XCTUnwrap(workbook.sheets.first)
        let edits = ExcelWorksheetEdits(
            partPath: sheet.partPath,
            cells: [
                address("A2"): ExcelCellEdit(
                    input: .text("김영희"),
                    styleIndex: 1
                ),
                address("F2"): ExcelCellEdit(
                    input: .text("기존 행의 새 셀"),
                    styleIndex: nil
                ),
                address("A3"): ExcelCellEdit(
                    input: .text("박철수"),
                    styleIndex: 1
                ),
                address("B3"): ExcelCellEdit(
                    input: .text("010-1234-5678"),
                    styleIndex: nil
                ),
                address("C3"): ExcelCellEdit(
                    input: .formula("1+4"),
                    styleIndex: nil
                ),
            ]
        )

        let saved = try ExcelWorkbookDocument.applying(
            [edits],
            to: source,
            workbook: workbook
        )
        let reloaded = try ExcelWorkbookDocument.load(from: saved)
        let reloadedSheet = try XCTUnwrap(reloaded.sheets.first)

        XCTAssertEqual(
            reloadedSheet.cell(at: address("A2"))?.displayValue,
            "김영희"
        )
        XCTAssertEqual(
            reloadedSheet.cell(at: address("F2"))?.displayValue,
            "기존 행의 새 셀"
        )
        XCTAssertEqual(
            reloadedSheet.cell(at: address("C3"))?.formula,
            "1+4"
        )
        XCTAssertEqual(reloadedSheet.maximumRow, 3)
        XCTAssertEqual(reloadedSheet.maximumColumn, 6)
        XCTAssertEqual(reloadedSheet.tables.first?.range.reference, "A1:C3")

        let sheetXML = try archiveText(
            "xl/worksheets/sheet1.xml",
            in: saved
        )
        XCTAssertTrue(sheetXML.contains(#"<x:dimension ref="A1:F3""#))
        XCTAssertTrue(sheetXML.contains(#"<x:c r="A2""#))
        XCTAssertTrue(sheetXML.contains(#"<x:c r="F2""#))
        XCTAssertTrue(sheetXML.contains(#"<x:row r="3""#))
        XCTAssertFalse(sheetXML.contains("<c "))
        XCTAssertFalse(sheetXML.contains("<row "))

        let workbookXML = try archiveText("xl/workbook.xml", in: saved)
        XCTAssertTrue(workbookXML.contains("<x:calcPr "))
        XCTAssertFalse(workbookXML.contains("<calcPr "))
        XCTAssertTrue(
            try archiveText("xl/tables/table1.xml", in: saved)
                .contains(#"<x:table "#)
        )
        XCTAssertTrue(
            try archiveText("xl/tables/table1.xml", in: saved)
                .contains(#"ref="A1:C3""#)
        )
        XCTAssertEqual(
            try archiveText("docProps/custom.xml", in: saved),
            "보존할 데이터"
        )
    }

    func testUserInputKeepsLeadingZeroValuesAsText() {
        XCTAssertEqual(
            ExcelCellInput(userText: "01012345678"),
            .text("01012345678")
        )
        XCTAssertEqual(
            ExcelCellInput(userText: "12.5"),
            .number("12.5")
        )
        XCTAssertEqual(
            ExcelCellInput(userText: "=SUM(A1:A2)"),
            .formula("SUM(A1:A2)")
        )
        XCTAssertEqual(
            ExcelFormulaTranslator.shiftingRelativeRows(
                in: "SUM(A2:B2)+$C$1+D$4+$E2",
                by: 1
            ),
            "SUM(A3:B3)+$C$1+D$4+$E3"
        )
    }

    func testFormulaCalculatorHandlesReferencesRangesAndConditions() {
        let cells: [ExcelCellAddress: ExcelCell] = [
            address("A1"): numericCell("A1", "10"),
            address("A2"): numericCell("A2", "20"),
            address("B1"): formulaCell("B1", "SUM(A1:A2)", cached: "0"),
            address("B2"): formulaCell(
                "B2",
                "AVERAGE(A1:A2)+MAX(A1:A2)",
                cached: "0"
            ),
            address("C1"): formulaCell(
                "C1",
                "IF(B1>=30,\"통과\",\"미달\")",
                cached: ""
            ),
            address("C2"): formulaCell(
                "C2",
                "COUNT(A1:A2)&\"개\"",
                cached: ""
            ),
        ]

        let result = ExcelFormulaCalculator.recalculate(
            cells: cells,
            styles: [.plain],
            uses1904DateSystem: false
        )

        XCTAssertEqual(result.unsupportedFormulaCount, 0)
        XCTAssertEqual(result.values[address("B1")]?.rawValue, "30")
        XCTAssertEqual(result.values[address("B2")]?.rawValue, "35")
        XCTAssertEqual(result.values[address("C1")]?.rawValue, "통과")
        XCTAssertEqual(result.values[address("C1")]?.cachedXMLType, "str")
        XCTAssertEqual(result.values[address("C2")]?.rawValue, "2개")
    }

    func testFormulaCalculatorLeavesUnsupportedAndCircularFormulasAlone() {
        let cells: [ExcelCellAddress: ExcelCell] = [
            address("A1"): formulaCell("A1", "A2+1", cached: "7"),
            address("A2"): formulaCell("A2", "A1+1", cached: "8"),
            address("B1"): formulaCell(
                "B1",
                "VLOOKUP(1,A1:A2,1,FALSE)",
                cached: "7"
            ),
        ]

        let result = ExcelFormulaCalculator.recalculate(
            cells: cells,
            styles: [.plain],
            uses1904DateSystem: false
        )

        XCTAssertTrue(result.values.isEmpty)
        XCTAssertEqual(result.unsupportedFormulaCount, 3)
    }

    func testFormulaAggregatesMatchExcelReferenceCoercionRules() {
        let cells: [ExcelCellAddress: ExcelCell] = [
            address("A1"): cell("A1", "5"),
            address("A2"): booleanCell("A2", true),
            address("A3"): numericCell("A3", "10"),
            address("B1"): formulaCell(
                "B1",
                "SUM(A1:A3)",
                cached: "0"
            ),
            address("B2"): formulaCell(
                "B2",
                "SUM(A1,A2,2)",
                cached: "0"
            ),
            address("B3"): formulaCell(
                "B3",
                "SUM(\"5\",15,TRUE)",
                cached: "0"
            ),
            address("C1"): formulaCell(
                "C1",
                "COUNT(A1:A3)",
                cached: "0"
            ),
            address("C2"): formulaCell(
                "C2",
                "COUNT(A1,A2,\"7\",TRUE)",
                cached: "0"
            ),
            address("C3"): formulaCell(
                "C3",
                "COUNTA(A1:A4)",
                cached: "0"
            ),
            address("C4"): formulaCell(
                "C4",
                "COUNTA(\"\")",
                cached: "0"
            ),
        ]

        let result = ExcelFormulaCalculator.recalculate(
            cells: cells,
            styles: [.plain],
            uses1904DateSystem: false
        )

        XCTAssertEqual(result.unsupportedFormulaCount, 0)
        XCTAssertEqual(result.values[address("B1")]?.rawValue, "10")
        XCTAssertEqual(result.values[address("B2")]?.rawValue, "2")
        XCTAssertEqual(result.values[address("B3")]?.rawValue, "21")
        XCTAssertEqual(result.values[address("C1")]?.rawValue, "1")
        XCTAssertEqual(result.values[address("C2")]?.rawValue, "2")
        XCTAssertEqual(result.values[address("C3")]?.rawValue, "3")
        XCTAssertEqual(result.values[address("C4")]?.rawValue, "1")
    }

    func testFormulaErrorsPropagateWithoutBreakingLazyIf() {
        let cells: [ExcelCellAddress: ExcelCell] = [
            address("A1"): numericCell("A1", "8"),
            address("A2"): errorCell("A2", "#VALUE!"),
            address("B1"): formulaCell("B1", "A1/0", cached: "0"),
            address("B2"): formulaCell(
                "B2",
                "SUM(A1:A2)",
                cached: "0"
            ),
            address("B3"): formulaCell(
                "B3",
                "COUNT(A1:A2)",
                cached: "0"
            ),
            address("B4"): formulaCell(
                "B4",
                "IF(FALSE,A1/0,42)",
                cached: "0"
            ),
            address("B5"): formulaCell("B5", "#REF!+1", cached: "0"),
            address("B6"): formulaCell(
                "B6",
                "AVERAGE(A3:A4)",
                cached: "0"
            ),
            address("B7"): formulaCell(
                "B7",
                "IF(AND(A1>0,NOT(FALSE)),SUM(A1,2),0)",
                cached: "0"
            ),
            address("B8"): formulaCell(
                "B8",
                "(-1)^0.5",
                cached: "0"
            ),
        ]

        let result = ExcelFormulaCalculator.recalculate(
            cells: cells,
            styles: [.plain],
            uses1904DateSystem: false
        )

        XCTAssertEqual(result.unsupportedFormulaCount, 0)
        XCTAssertEqual(result.values[address("B1")]?.rawValue, "#DIV/0!")
        XCTAssertEqual(result.values[address("B1")]?.cachedXMLType, "e")
        XCTAssertEqual(result.values[address("B2")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("B3")]?.rawValue, "1")
        XCTAssertEqual(result.values[address("B4")]?.rawValue, "42")
        XCTAssertEqual(result.values[address("B5")]?.rawValue, "#REF!")
        XCTAssertEqual(result.values[address("B6")]?.rawValue, "#DIV/0!")
        XCTAssertEqual(result.values[address("B7")]?.rawValue, "10")
        XCTAssertEqual(result.values[address("B8")]?.rawValue, "#NUM!")
    }

    func testFormulaCalculatorSupportsCommonMathAndTextFunctions() {
        let cells: [ExcelCellAddress: ExcelCell] = [
            address("A1"): numericCell("A1", "-12.345"),
            address("B1"): formulaCell(
                "B1",
                "ROUND(A1,2)",
                cached: "0"
            ),
            address("B2"): formulaCell(
                "B2",
                "ROUNDDOWN(A1,2)",
                cached: "0"
            ),
            address("B3"): formulaCell(
                "B3",
                "ROUNDUP(A1,2)",
                cached: "0"
            ),
            address("B4"): formulaCell(
                "B4",
                "ROUND(1234,-2)",
                cached: "0"
            ),
            address("B5"): formulaCell("B5", "ABS(A1)", cached: "0"),
            address("B6"): formulaCell("B6", "INT(A1)", cached: "0"),
            address("C1"): formulaCell(
                "C1",
                "LEN(\"가나다 abc\")",
                cached: "0"
            ),
            address("C2"): formulaCell(
                "C2",
                "LEFT(\"가나다\",2)",
                cached: ""
            ),
            address("C3"): formulaCell(
                "C3",
                "RIGHT(\"가나다\",2)",
                cached: ""
            ),
            address("C4"): formulaCell(
                "C4",
                "LEFT(\"abc\")",
                cached: ""
            ),
            address("C5"): formulaCell(
                "C5",
                "RIGHT(\"abc\",0)",
                cached: ""
            ),
            address("C6"): formulaCell(
                "C6",
                "LEFT(\"abc\",-1)",
                cached: ""
            ),
        ]

        let result = ExcelFormulaCalculator.recalculate(
            cells: cells,
            styles: [.plain],
            uses1904DateSystem: false
        )

        XCTAssertEqual(result.unsupportedFormulaCount, 0)
        XCTAssertEqual(result.values[address("B1")]?.rawValue, "-12.35")
        XCTAssertEqual(result.values[address("B2")]?.rawValue, "-12.34")
        XCTAssertEqual(result.values[address("B3")]?.rawValue, "-12.35")
        XCTAssertEqual(result.values[address("B4")]?.rawValue, "1200")
        XCTAssertEqual(result.values[address("B5")]?.rawValue, "12.345")
        XCTAssertEqual(result.values[address("B6")]?.rawValue, "-13")
        XCTAssertEqual(result.values[address("C1")]?.rawValue, "7")
        XCTAssertEqual(result.values[address("C2")]?.rawValue, "가나")
        XCTAssertEqual(result.values[address("C3")]?.rawValue, "나다")
        XCTAssertEqual(result.values[address("C4")]?.rawValue, "a")
        XCTAssertEqual(result.values[address("C5")]?.rawValue, "")
        XCTAssertEqual(result.values[address("C6")]?.rawValue, "#VALUE!")
    }

    func testFormulaCalculatorSupportsDateFunctionsAndDateSystems() throws {
        let dateStyle = ExcelCellStyle(
            numberFormatID: ExcelNumberFormat.date.displayNumberFormatID,
            numberFormatCode: ExcelNumberFormat.date.formatCode,
            isBold: false,
            fillARGB: nil,
            horizontalAlignment: nil
        )
        let cells: [ExcelCellAddress: ExcelCell] = [
            address("A1"): ExcelCell(
                address: address("A1"),
                rawValue: "0",
                displayValue: "0",
                formula: "DATE(2024,2,29)",
                styleIndex: 1,
                cellType: nil
            ),
            address("A2"): formulaCell(
                "A2",
                "DATE(2024,14,2)",
                cached: "0"
            ),
            address("A3"): formulaCell(
                "A3",
                "DATE(2024,1,-15)",
                cached: "0"
            ),
            address("A4"): formulaCell("A4", "TODAY()", cached: "0"),
            address("A5"): formulaCell(
                "A5",
                "DATE(124,2,29)",
                cached: "0"
            ),
            address("B1"): formulaCell("B1", "YEAR(A1)", cached: "0"),
            address("B2"): formulaCell("B2", "MONTH(A1)", cached: "0"),
            address("B3"): formulaCell("B3", "DAY(A1)", cached: "0"),
            address("B4"): formulaCell("B4", "YEAR(A2)", cached: "0"),
            address("B5"): formulaCell("B5", "MONTH(A2)", cached: "0"),
            address("B6"): formulaCell("B6", "DAY(A2)", cached: "0"),
            address("B7"): formulaCell("B7", "YEAR(A3)", cached: "0"),
            address("B8"): formulaCell("B8", "MONTH(A3)", cached: "0"),
            address("B9"): formulaCell("B9", "DAY(A3)", cached: "0"),
            address("C1"): formulaCell("C1", "YEAR(60)", cached: "0"),
            address("C2"): formulaCell("C2", "MONTH(60)", cached: "0"),
            address("C3"): formulaCell("C3", "DAY(60)", cached: "0"),
            address("C4"): formulaCell("C4", "YEAR(0)", cached: "0"),
            address("C5"): formulaCell("C5", "DAY(0)", cached: "0"),
            address("D1"): formulaCell("D1", "DATE(-1,1,1)", cached: "0"),
            address("D2"): formulaCell(
                "D2",
                "DATE(10000,1,1)",
                cached: "0"
            ),
            address("D3"): formulaCell("D3", "YEAR(-1)", cached: "0"),
            address("D4"): formulaCell("D4", "TODAY(1)", cached: "0"),
            address("D5"): formulaCell(
                "D5",
                "DATE(\"날짜\",1,1)",
                cached: "0"
            ),
        ]
        let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let leapDay = try XCTUnwrap(calendar.date(
            from: DateComponents(
                timeZone: utc,
                year: 2024,
                month: 2,
                day: 29,
                hour: 12
            )
        ))

        let result1900 = ExcelFormulaCalculator.recalculate(
            cells: cells,
            styles: [.plain, dateStyle],
            uses1904DateSystem: false,
            now: leapDay,
            timeZone: utc
        )

        XCTAssertEqual(result1900.unsupportedFormulaCount, 0)
        XCTAssertEqual(result1900.values[address("A1")]?.rawValue, "45351")
        XCTAssertEqual(
            result1900.values[address("A1")]?.displayValue,
            "2024-02-29"
        )
        XCTAssertEqual(result1900.values[address("A4")]?.rawValue, "45351")
        XCTAssertEqual(result1900.values[address("A5")]?.rawValue, "45351")
        XCTAssertEqual(result1900.values[address("B1")]?.rawValue, "2024")
        XCTAssertEqual(result1900.values[address("B2")]?.rawValue, "2")
        XCTAssertEqual(result1900.values[address("B3")]?.rawValue, "29")
        XCTAssertEqual(result1900.values[address("B4")]?.rawValue, "2025")
        XCTAssertEqual(result1900.values[address("B5")]?.rawValue, "2")
        XCTAssertEqual(result1900.values[address("B6")]?.rawValue, "2")
        XCTAssertEqual(result1900.values[address("B7")]?.rawValue, "2023")
        XCTAssertEqual(result1900.values[address("B8")]?.rawValue, "12")
        XCTAssertEqual(result1900.values[address("B9")]?.rawValue, "16")
        XCTAssertEqual(result1900.values[address("C1")]?.rawValue, "1900")
        XCTAssertEqual(result1900.values[address("C2")]?.rawValue, "2")
        XCTAssertEqual(result1900.values[address("C3")]?.rawValue, "29")
        XCTAssertEqual(result1900.values[address("C4")]?.rawValue, "1900")
        XCTAssertEqual(result1900.values[address("C5")]?.rawValue, "0")
        XCTAssertEqual(result1900.values[address("D1")]?.rawValue, "#NUM!")
        XCTAssertEqual(result1900.values[address("D2")]?.rawValue, "#NUM!")
        XCTAssertEqual(result1900.values[address("D3")]?.rawValue, "#NUM!")
        XCTAssertEqual(result1900.values[address("D4")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result1900.values[address("D5")]?.rawValue, "#VALUE!")

        let result1904 = ExcelFormulaCalculator.recalculate(
            cells: cells,
            styles: [.plain, dateStyle],
            uses1904DateSystem: true,
            now: leapDay,
            timeZone: utc
        )

        XCTAssertEqual(result1904.unsupportedFormulaCount, 0)
        XCTAssertEqual(result1904.values[address("A1")]?.rawValue, "43889")
        XCTAssertEqual(result1904.values[address("A4")]?.rawValue, "43889")
        let serial1900 = try XCTUnwrap(
            Int(result1900.values[address("A1")]?.rawValue ?? "")
        )
        let serial1904 = try XCTUnwrap(
            Int(result1904.values[address("A1")]?.rawValue ?? "")
        )
        XCTAssertEqual(serial1900 - serial1904, 1462)
    }

    func testFormulaCalculatorSupportsExtendedDateAndTimeFunctions() throws {
        let cells: [ExcelCellAddress: ExcelCell] = [
            address("A1"): formulaCell("A1", "NOW()", cached: "0"),
            address("A2"): formulaCell(
                "A2", "TIME(12,34,56)", cached: "0"
            ),
            address("A3"): formulaCell("A3", "TIME(27,0,0)", cached: "0"),
            address("A4"): formulaCell("A4", "TIME(0,750,0)", cached: "0"),
            address("A5"): formulaCell(
                "A5", "TIME(0,0,2000)", cached: "0"
            ),
            address("A6"): formulaCell("A6", "TIME(24,0,0)", cached: "0"),
            address("A7"): formulaCell("A7", "TIME(-1,0,0)", cached: "0"),
            address("A8"): formulaCell(
                "A8", "TIME(32768,0,0)", cached: "0"
            ),
            address("A9"): formulaCell(
                "A9", "TIME(\"bad\",0,0)", cached: "0"
            ),
            address("A10"): formulaCell(
                "A10", "TIME(#N/A,0,0)", cached: "0"
            ),
            address("A11"): formulaCell("A11", "NOW(1)", cached: "0"),
            address("A12"): formulaCell(
                "A12", "TIME(1.9,2.9,3.9)", cached: "0"
            ),
            address("B1"): formulaCell("B1", "HOUR(A2)", cached: "0"),
            address("B2"): formulaCell("B2", "MINUTE(A2)", cached: "0"),
            address("B3"): formulaCell("B3", "SECOND(A2)", cached: "0"),
            address("B4"): formulaCell("B4", "HOUR(A1)", cached: "0"),
            address("B5"): formulaCell("B5", "MINUTE(A1)", cached: "0"),
            address("B6"): formulaCell("B6", "SECOND(A1)", cached: "0"),
            address("B7"): formulaCell(
                "B7", "HOUR(DATE(2024,2,29))", cached: "0"
            ),
            address("B8"): formulaCell("B8", "SECOND(-0.5)", cached: "0"),
            address("B9"): formulaCell(
                "B9", "MINUTE(\"bad\")", cached: "0"
            ),
            address("B10"): formulaCell("B10", "HOUR()", cached: "0"),
            address("B11"): formulaCell(
                "B11", "SECOND(TIME(0,0,59))", cached: "0"
            ),
            address("B12"): formulaCell(
                "B12", "SECOND(TIME(0,0,60))", cached: "0"
            ),
            address("B13"): formulaCell(
                "B13", "MINUTE(TIME(0,0,60))", cached: "0"
            ),
            address("C1"): formulaCell(
                "C1", "EDATE(DATE(2024,1,31),1)", cached: "0"
            ),
            address("C2"): formulaCell(
                "C2", "EDATE(DATE(2023,1,31),1)", cached: "0"
            ),
            address("C3"): formulaCell(
                "C3", "EDATE(DATE(2024,3,31),-1)", cached: "0"
            ),
            address("C4"): formulaCell(
                "C4", "EDATE(DATE(2024,1,15),1.9)", cached: "0"
            ),
            address("C5"): formulaCell("C5", "EDATE(60,1)", cached: "0"),
            address("C6"): formulaCell("C6", "EDATE(-1,1)", cached: "0"),
            address("C7"): formulaCell(
                "C7", "EDATE(DATE(9999,12,31),1)", cached: "0"
            ),
            address("C8"): formulaCell(
                "C8", "EDATE(#N/A,1)", cached: "0"
            ),
            address("C9"): formulaCell(
                "C9", "DATE(1900,2,29)", cached: "0"
            ),
            address("C10"): formulaCell(
                "C10", "DATE(1900,3,0)", cached: "0"
            ),
            address("C11"): formulaCell(
                "C11", "DATE(1900,2,30)", cached: "0"
            ),
            address("D1"): formulaCell(
                "D1", "EOMONTH(DATE(2024,1,15),1)", cached: "0"
            ),
            address("D2"): formulaCell(
                "D2", "EOMONTH(DATE(2023,2,15),0)", cached: "0"
            ),
            address("D3"): formulaCell(
                "D3", "EOMONTH(60,0)", cached: "0"
            ),
            address("D4"): formulaCell(
                "D4", "EOMONTH(DATE(2024,5,5),-2.9)", cached: "0"
            ),
            address("D5"): formulaCell(
                "D5", "EOMONTH(-1,1)", cached: "0"
            ),
            address("D6"): formulaCell(
                "D6", "EOMONTH(DATE(9999,12,31),1)", cached: "0"
            ),
            address("D7"): formulaCell(
                "D7", "EOMONTH(#REF!,0)", cached: "0"
            ),
            address("E1"): formulaCell(
                "E1", "WEEKDAY(DATE(2024,1,1))", cached: "0"
            ),
            address("E2"): formulaCell(
                "E2", "WEEKDAY(DATE(2024,1,1),2)", cached: "0"
            ),
            address("E3"): formulaCell(
                "E3", "WEEKDAY(DATE(2024,1,1),3)", cached: "0"
            ),
            address("E4"): formulaCell(
                "E4", "WEEKDAY(DATE(2024,1,1),11)", cached: "0"
            ),
            address("E5"): formulaCell(
                "E5", "WEEKDAY(DATE(2024,1,1),12)", cached: "0"
            ),
            address("E6"): formulaCell(
                "E6", "WEEKDAY(DATE(2024,1,1),13)", cached: "0"
            ),
            address("E7"): formulaCell(
                "E7", "WEEKDAY(DATE(2024,1,1),17)", cached: "0"
            ),
            address("E8"): formulaCell(
                "E8", "WEEKDAY(DATE(2024,1,1),10)", cached: "0"
            ),
            address("E9"): formulaCell(
                "E9", "WEEKDAY(-1)", cached: "0"
            ),
            address("E10"): formulaCell(
                "E10", "WEEKDAY(#N/A)", cached: "0"
            ),
            address("E11"): formulaCell(
                "E11", "WEEKDAY(DATE(2024,1,1),2.5)", cached: "0"
            ),
            address("F1"): formulaCell("F1", "WEEKDAY(1)", cached: "0"),
            address("F2"): formulaCell("F2", "WEEKDAY(60)", cached: "0"),
            address("F3"): formulaCell("F3", "WEEKDAY(61)", cached: "0"),
            address("F4"): formulaCell("F4", "WEEKDAY(0)", cached: "0"),
        ]
        let seoul = try XCTUnwrap(TimeZone(secondsFromGMT: 9 * 3_600))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = seoul
        let now = try XCTUnwrap(calendar.date(
            from: DateComponents(
                timeZone: seoul,
                year: 2024,
                month: 2,
                day: 29,
                hour: 23,
                minute: 45,
                second: 6
            )
        ))

        let result1900 = ExcelFormulaCalculator.recalculate(
            cells: cells,
            styles: [.plain],
            uses1904DateSystem: false,
            now: now,
            timeZone: seoul
        )

        XCTAssertEqual(result1900.unsupportedFormulaCount, 0)
        let now1900 = try XCTUnwrap(Double(
            result1900.values[address("A1")]?.rawValue ?? ""
        ))
        XCTAssertEqual(
            now1900,
            45_351 + Double(23 * 3_600 + 45 * 60 + 6) / 86_400,
            accuracy: 0.000_000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(Double(
                result1900.values[address("A2")]?.rawValue ?? ""
            )),
            Double(12 * 3_600 + 34 * 60 + 56) / 86_400,
            accuracy: 0.000_000_000_001
        )
        XCTAssertEqual(result1900.values[address("A3")]?.rawValue, "0.125")
        XCTAssertEqual(
            try XCTUnwrap(Double(
                result1900.values[address("A4")]?.rawValue ?? ""
            )),
            Double(12 * 3_600 + 30 * 60) / 86_400,
            accuracy: 0.000_000_000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(Double(
                result1900.values[address("A5")]?.rawValue ?? ""
            )),
            Double(2_000) / 86_400,
            accuracy: 0.000_000_000_001
        )
        XCTAssertEqual(result1900.values[address("A6")]?.rawValue, "0")
        XCTAssertEqual(result1900.values[address("A7")]?.rawValue, "#NUM!")
        XCTAssertEqual(result1900.values[address("A8")]?.rawValue, "#NUM!")
        XCTAssertEqual(result1900.values[address("A9")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result1900.values[address("A10")]?.rawValue, "#N/A")
        XCTAssertEqual(result1900.values[address("A11")]?.rawValue, "#VALUE!")
        XCTAssertEqual(
            try XCTUnwrap(Double(
                result1900.values[address("A12")]?.rawValue ?? ""
            )),
            Double(3_723) / 86_400,
            accuracy: 0.000_000_000_001
        )
        XCTAssertEqual(result1900.values[address("B1")]?.rawValue, "12")
        XCTAssertEqual(result1900.values[address("B2")]?.rawValue, "34")
        XCTAssertEqual(result1900.values[address("B3")]?.rawValue, "56")
        XCTAssertEqual(result1900.values[address("B4")]?.rawValue, "23")
        XCTAssertEqual(result1900.values[address("B5")]?.rawValue, "45")
        XCTAssertEqual(result1900.values[address("B6")]?.rawValue, "6")
        XCTAssertEqual(result1900.values[address("B7")]?.rawValue, "0")
        XCTAssertEqual(result1900.values[address("B8")]?.rawValue, "#NUM!")
        XCTAssertEqual(result1900.values[address("B9")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result1900.values[address("B10")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result1900.values[address("B11")]?.rawValue, "59")
        XCTAssertEqual(result1900.values[address("B12")]?.rawValue, "0")
        XCTAssertEqual(result1900.values[address("B13")]?.rawValue, "1")
        XCTAssertEqual(result1900.values[address("C1")]?.rawValue, "45351")
        XCTAssertEqual(result1900.values[address("C2")]?.rawValue, "44985")
        XCTAssertEqual(result1900.values[address("C3")]?.rawValue, "45351")
        XCTAssertEqual(result1900.values[address("C4")]?.rawValue, "45337")
        XCTAssertEqual(result1900.values[address("C5")]?.rawValue, "89")
        XCTAssertEqual(result1900.values[address("C6")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result1900.values[address("C7")]?.rawValue, "#NUM!")
        XCTAssertEqual(result1900.values[address("C8")]?.rawValue, "#N/A")
        XCTAssertEqual(result1900.values[address("C9")]?.rawValue, "60")
        XCTAssertEqual(result1900.values[address("C10")]?.rawValue, "60")
        XCTAssertEqual(result1900.values[address("C11")]?.rawValue, "61")
        XCTAssertEqual(result1900.values[address("D1")]?.rawValue, "45351")
        XCTAssertEqual(result1900.values[address("D2")]?.rawValue, "44985")
        XCTAssertEqual(result1900.values[address("D3")]?.rawValue, "60")
        XCTAssertEqual(result1900.values[address("D4")]?.rawValue, "45382")
        XCTAssertEqual(result1900.values[address("D5")]?.rawValue, "#NUM!")
        XCTAssertEqual(result1900.values[address("D6")]?.rawValue, "#NUM!")
        XCTAssertEqual(result1900.values[address("D7")]?.rawValue, "#REF!")
        XCTAssertEqual(result1900.values[address("E1")]?.rawValue, "2")
        XCTAssertEqual(result1900.values[address("E2")]?.rawValue, "1")
        XCTAssertEqual(result1900.values[address("E3")]?.rawValue, "0")
        XCTAssertEqual(result1900.values[address("E4")]?.rawValue, "1")
        XCTAssertEqual(result1900.values[address("E5")]?.rawValue, "7")
        XCTAssertEqual(result1900.values[address("E6")]?.rawValue, "6")
        XCTAssertEqual(result1900.values[address("E7")]?.rawValue, "2")
        XCTAssertEqual(result1900.values[address("E8")]?.rawValue, "#NUM!")
        XCTAssertEqual(result1900.values[address("E9")]?.rawValue, "#NUM!")
        XCTAssertEqual(result1900.values[address("E10")]?.rawValue, "#N/A")
        XCTAssertEqual(result1900.values[address("E11")]?.rawValue, "#NUM!")
        XCTAssertEqual(result1900.values[address("F1")]?.rawValue, "1")
        XCTAssertEqual(result1900.values[address("F2")]?.rawValue, "4")
        XCTAssertEqual(result1900.values[address("F3")]?.rawValue, "5")
        XCTAssertEqual(result1900.values[address("F4")]?.rawValue, "7")

        let result1904 = ExcelFormulaCalculator.recalculate(
            cells: cells,
            styles: [.plain],
            uses1904DateSystem: true,
            now: now,
            timeZone: seoul
        )
        XCTAssertEqual(result1904.unsupportedFormulaCount, 0)
        let now1904 = try XCTUnwrap(Double(
            result1904.values[address("A1")]?.rawValue ?? ""
        ))
        XCTAssertEqual(now1900 - now1904, 1_462, accuracy: 0.000_000_001)
        XCTAssertEqual(result1904.values[address("E1")]?.rawValue, "2")
        XCTAssertEqual(result1904.values[address("E2")]?.rawValue, "1")
        XCTAssertEqual(result1904.values[address("F4")]?.rawValue, "6")
    }

    func testFormulaCalculatorSupportsDateDifferencesAndWeekNumbers() {
        let cells: [ExcelCellAddress: ExcelCell] = [
            address("A1"): formulaCell(
                "A1", "DAYS(DATE(2024,3,1),DATE(2024,2,28))", cached: "0"
            ),
            address("A2"): formulaCell(
                "A2", "DAYS(DATE(2024,2,28),DATE(2024,3,1))", cached: "0"
            ),
            address("A3"): formulaCell("A3", "DAYS(61,59)", cached: "0"),
            address("A4"): formulaCell("A4", "DAYS(-1,1)", cached: "0"),
            address("A5"): formulaCell(
                "A5", "DAYS(\"bad\",1)", cached: "0"
            ),
            address("A6"): formulaCell(
                "A6", "DAYS(#REF!,1)", cached: "0"
            ),
            address("A7"): formulaCell(
                "A7", "DAYS(2.75,1.25)", cached: "0"
            ),
            address("B1"): formulaCell(
                "B1",
                "DATEDIF(DATE(2001,1,1),DATE(2003,1,1),\"Y\")",
                cached: "0"
            ),
            address("B2"): formulaCell(
                "B2",
                "DATEDIF(DATE(2001,6,1),DATE(2002,8,15),\"D\")",
                cached: "0"
            ),
            address("B3"): formulaCell(
                "B3",
                "DATEDIF(DATE(2001,6,1),DATE(2002,8,15),\"YD\")",
                cached: "0"
            ),
            address("B4"): formulaCell(
                "B4",
                "DATEDIF(DATE(2001,6,1),DATE(2002,8,15),\"M\")",
                cached: "0"
            ),
            address("B5"): formulaCell(
                "B5",
                "DATEDIF(DATE(2001,6,1),DATE(2002,8,15),\"YM\")",
                cached: "0"
            ),
            address("B6"): formulaCell(
                "B6",
                "DATEDIF(DATE(2001,6,1),DATE(2002,8,15),\"MD\")",
                cached: "0"
            ),
            address("B7"): formulaCell(
                "B7",
                "DATEDIF(DATE(2024,2,2),DATE(2024,2,1),\"D\")",
                cached: "0"
            ),
            address("B8"): formulaCell(
                "B8",
                "DATEDIF(DATE(2024,1,1),DATE(2024,2,1),\"Q\")",
                cached: "0"
            ),
            address("B9"): formulaCell(
                "B9", "DATEDIF(59,61,\"D\")", cached: "0"
            ),
            address("B10"): formulaCell(
                "B10", "DATEDIF(#N/A,61,\"D\")", cached: "0"
            ),
            address("B11"): formulaCell(
                "B11",
                "DATEDIF(DATE(2001,6,1),DATE(2002,8,15),\"ym\")",
                cached: "0"
            ),
            address("C1"): formulaCell(
                "C1", "WEEKNUM(DATE(2012,3,9))", cached: "0"
            ),
            address("C2"): formulaCell(
                "C2", "WEEKNUM(DATE(2012,3,9),2)", cached: "0"
            ),
            address("C3"): formulaCell(
                "C3", "WEEKNUM(DATE(2012,3,9),11)", cached: "0"
            ),
            address("C4"): formulaCell(
                "C4", "WEEKNUM(DATE(2012,3,9),12)", cached: "0"
            ),
            address("C5"): formulaCell(
                "C5", "WEEKNUM(DATE(2012,3,9),17)", cached: "0"
            ),
            address("C6"): formulaCell(
                "C6", "WEEKNUM(DATE(2012,3,9),21)", cached: "0"
            ),
            address("C7"): formulaCell(
                "C7", "WEEKNUM(DATE(2012,3,9),3)", cached: "0"
            ),
            address("C8"): formulaCell("C8", "WEEKNUM(-1)", cached: "0"),
            address("C9"): formulaCell(
                "C9", "WEEKNUM(\"bad\")", cached: "0"
            ),
            address("C10"): formulaCell(
                "C10", "WEEKNUM(#N/A)", cached: "0"
            ),
            address("D1"): formulaCell(
                "D1", "ISOWEEKNUM(DATE(2021,1,1))", cached: "0"
            ),
            address("D2"): formulaCell(
                "D2", "ISOWEEKNUM(DATE(2021,1,4))", cached: "0"
            ),
            address("D3"): formulaCell(
                "D3", "WEEKNUM(DATE(2021,1,1))", cached: "0"
            ),
            address("D4"): formulaCell(
                "D4", "ISOWEEKNUM(60)", cached: "0"
            ),
            address("D5"): formulaCell("D5", "WEEKNUM(60)", cached: "0"),
            address("D6"): formulaCell(
                "D6", "ISOWEEKNUM(-1)", cached: "0"
            ),
            address("D7"): formulaCell(
                "D7", "ISOWEEKNUM(\"bad\")", cached: "0"
            ),
            address("D8"): formulaCell(
                "D8", "ISOWEEKNUM(#REF!)", cached: "0"
            ),
        ]

        let result = ExcelFormulaCalculator.recalculate(
            cells: cells,
            styles: [.plain],
            uses1904DateSystem: false
        )

        XCTAssertEqual(result.unsupportedFormulaCount, 0)
        XCTAssertEqual(result.values[address("A1")]?.rawValue, "2")
        XCTAssertEqual(result.values[address("A2")]?.rawValue, "-2")
        XCTAssertEqual(result.values[address("A3")]?.rawValue, "2")
        XCTAssertEqual(result.values[address("A4")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("A5")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("A6")]?.rawValue, "#REF!")
        XCTAssertEqual(result.values[address("A7")]?.rawValue, "1.5")
        XCTAssertEqual(result.values[address("B1")]?.rawValue, "2")
        XCTAssertEqual(result.values[address("B2")]?.rawValue, "440")
        XCTAssertEqual(result.values[address("B3")]?.rawValue, "75")
        XCTAssertEqual(result.values[address("B4")]?.rawValue, "14")
        XCTAssertEqual(result.values[address("B5")]?.rawValue, "2")
        XCTAssertEqual(result.values[address("B6")]?.rawValue, "14")
        XCTAssertEqual(result.values[address("B7")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("B8")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("B9")]?.rawValue, "2")
        XCTAssertEqual(result.values[address("B10")]?.rawValue, "#N/A")
        XCTAssertEqual(result.values[address("B11")]?.rawValue, "2")
        XCTAssertEqual(result.values[address("C1")]?.rawValue, "10")
        XCTAssertEqual(result.values[address("C2")]?.rawValue, "11")
        XCTAssertEqual(result.values[address("C3")]?.rawValue, "11")
        XCTAssertEqual(result.values[address("C4")]?.rawValue, "11")
        XCTAssertEqual(result.values[address("C5")]?.rawValue, "10")
        XCTAssertEqual(result.values[address("C6")]?.rawValue, "10")
        XCTAssertEqual(result.values[address("C7")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("C8")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("C9")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("C10")]?.rawValue, "#N/A")
        XCTAssertEqual(result.values[address("D1")]?.rawValue, "53")
        XCTAssertEqual(result.values[address("D2")]?.rawValue, "1")
        XCTAssertEqual(result.values[address("D3")]?.rawValue, "1")
        XCTAssertEqual(result.values[address("D4")]?.rawValue, "9")
        XCTAssertEqual(result.values[address("D5")]?.rawValue, "9")
        XCTAssertEqual(result.values[address("D6")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("D7")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("D8")]?.rawValue, "#REF!")
    }

    func testFormulaCalculatorSupportsBusinessDayFunctions() {
        let cells: [ExcelCellAddress: ExcelCell] = [
            address("A1"): formulaCell(
                "A1", "WORKDAY(DATE(2024,1,5),1)", cached: "0"
            ),
            address("A2"): formulaCell(
                "A2", "WORKDAY(DATE(2024,1,8),-1)", cached: "0"
            ),
            address("A3"): formulaCell(
                "A3", "WORKDAY(DATE(2024,1,6),0)", cached: "0"
            ),
            address("A4"): formulaCell(
                "A4", "WORKDAY(DATE(2024,1,5),1,H1:H3)", cached: "0"
            ),
            address("A5"): formulaCell(
                "A5", "WORKDAY(DATE(2024,1,5),1.9)", cached: "0"
            ),
            address("A6"): formulaCell(
                "A6", "WORKDAY(-1,1)", cached: "0"
            ),
            address("A7"): formulaCell(
                "A7", "WORKDAY(DATE(9999,12,31),1)", cached: "0"
            ),
            address("A8"): formulaCell(
                "A8", "WORKDAY(#REF!,1)", cached: "0"
            ),
            address("A9"): formulaCell(
                "A9", "WORKDAY(DATE(2024,1,5),1,H1)", cached: "0"
            ),
            address("A10"): formulaCell(
                "A10", "WORKDAY(DATE(2024,1,5),1,H7)", cached: "0"
            ),
            address("B1"): formulaCell(
                "B1", "WORKDAY.INTL(DATE(2024,1,5),1,11)", cached: "0"
            ),
            address("B2"): formulaCell(
                "B2",
                "WORKDAY.INTL(DATE(2024,1,5),1,\"0000011\")",
                cached: "0"
            ),
            address("B3"): formulaCell(
                "B3",
                "WORKDAY.INTL(DATE(2024,1,5),1,\"1111111\")",
                cached: "0"
            ),
            address("B4"): formulaCell(
                "B4", "WORKDAY.INTL(DATE(2024,1,5),1,0)", cached: "0"
            ),
            address("B5"): formulaCell(
                "B5",
                "WORKDAY.INTL(DATE(2024,1,5),1,\"0000011\",H1:H3)",
                cached: "0"
            ),
            address("B6"): formulaCell(
                "B6", "WORKDAY.INTL(-1,1,1)", cached: "0"
            ),
            address("B7"): formulaCell(
                "B7", "WORKDAY.INTL(DATE(2024,1,6),0,1)", cached: "0"
            ),
            address("B8"): formulaCell(
                "B8",
                "WORKDAY.INTL(DATE(2024,1,5),1,\"000011\")",
                cached: "0"
            ),
            address("B9"): formulaCell(
                "B9", "WORKDAY.INTL(DATE(2024,1,5),1,1.5)", cached: "0"
            ),
            address("B10"): formulaCell(
                "B10", "WORKDAY.INTL(DATE(2024,1,5),#REF!,1)",
                cached: "0"
            ),
            address("B11"): formulaCell(
                "B11", "WORKDAY.INTL(DATE(2024,1,5),1,1,H6)",
                cached: "0"
            ),
            address("B12"): formulaCell(
                "B12", "WORKDAY.INTL(DATE(2024,1,5),1,1,H7)",
                cached: "0"
            ),
            address("C1"): formulaCell(
                "C1",
                "NETWORKDAYS(DATE(2024,1,1),DATE(2024,1,7))",
                cached: "0"
            ),
            address("C2"): formulaCell(
                "C2",
                "NETWORKDAYS(DATE(2024,1,1),DATE(2024,1,7),H4:H5)",
                cached: "0"
            ),
            address("C3"): formulaCell(
                "C3",
                "NETWORKDAYS(DATE(2024,1,7),DATE(2024,1,1))",
                cached: "0"
            ),
            address("C4"): formulaCell(
                "C4",
                "NETWORKDAYS(DATE(2024,1,6),DATE(2024,1,6))",
                cached: "0"
            ),
            address("C5"): formulaCell(
                "C5", "NETWORKDAYS(-1,DATE(2024,1,7))", cached: "0"
            ),
            address("C6"): formulaCell(
                "C6", "NETWORKDAYS(#N/A,DATE(2024,1,7))", cached: "0"
            ),
            address("C7"): formulaCell(
                "C7",
                "NETWORKDAYS(DATE(2024,1,1),DATE(2024,1,7),H6)",
                cached: "0"
            ),
            address("D1"): formulaCell(
                "D1",
                "NETWORKDAYS.INTL(DATE(2024,1,1),DATE(2024,1,7),11)",
                cached: "0"
            ),
            address("D2"): formulaCell(
                "D2",
                "NETWORKDAYS.INTL(DATE(2024,1,1),DATE(2024,1,7),\"0000011\")",
                cached: "0"
            ),
            address("D3"): formulaCell(
                "D3",
                "NETWORKDAYS.INTL(DATE(2024,1,1),DATE(2024,1,7),\"1111111\")",
                cached: "0"
            ),
            address("D4"): formulaCell(
                "D4",
                "NETWORKDAYS.INTL(DATE(2024,1,1),DATE(2024,1,7),\"000011\")",
                cached: "0"
            ),
            address("D5"): formulaCell(
                "D5",
                "NETWORKDAYS.INTL(DATE(2024,1,1),DATE(2024,1,7),0)",
                cached: "0"
            ),
            address("D6"): formulaCell(
                "D6",
                "NETWORKDAYS.INTL(DATE(2024,1,1),DATE(2024,1,7),11,H4:H5)",
                cached: "0"
            ),
            address("D7"): formulaCell(
                "D7",
                "NETWORKDAYS.INTL(DATE(2024,1,7),DATE(2024,1,1),11)",
                cached: "0"
            ),
            address("D8"): formulaCell(
                "D8", "NETWORKDAYS.INTL(-1,DATE(2024,1,7),1)",
                cached: "0"
            ),
            address("D9"): formulaCell(
                "D9", "NETWORKDAYS.INTL(#N/A,DATE(2024,1,7),1)",
                cached: "0"
            ),
            address("D10"): formulaCell(
                "D10",
                "NETWORKDAYS.INTL(DATE(2024,1,1),DATE(2024,1,7),1.5)",
                cached: "0"
            ),
            address("D11"): formulaCell(
                "D11",
                "NETWORKDAYS.INTL(DATE(2024,1,1),DATE(2024,1,7),1,H7)",
                cached: "0"
            ),
            address("H1"): formulaCell(
                "H1", "DATE(2024,1,8)", cached: "0"
            ),
            address("H2"): formulaCell(
                "H2", "DATE(2024,1,8)", cached: "0"
            ),
            address("H3"): formulaCell(
                "H3", "DATE(2024,1,7)", cached: "0"
            ),
            address("H4"): formulaCell(
                "H4", "DATE(2024,1,3)", cached: "0"
            ),
            address("H5"): formulaCell(
                "H5", "DATE(2024,1,1)", cached: "0"
            ),
            address("H6"): cell("H6", "bad"),
            address("H7"): numericCell("H7", "-1"),
        ]

        let result = ExcelFormulaCalculator.recalculate(
            cells: cells,
            styles: [.plain],
            uses1904DateSystem: false
        )

        XCTAssertEqual(result.unsupportedFormulaCount, 0)
        XCTAssertEqual(result.values[address("A1")]?.rawValue, "45299")
        XCTAssertEqual(result.values[address("A2")]?.rawValue, "45296")
        XCTAssertEqual(result.values[address("A3")]?.rawValue, "45297")
        XCTAssertEqual(result.values[address("A4")]?.rawValue, "45300")
        XCTAssertEqual(result.values[address("A5")]?.rawValue, "45299")
        XCTAssertEqual(result.values[address("A6")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("A7")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("A8")]?.rawValue, "#REF!")
        XCTAssertEqual(result.values[address("A9")]?.rawValue, "45300")
        XCTAssertEqual(result.values[address("A10")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("B1")]?.rawValue, "45297")
        XCTAssertEqual(result.values[address("B2")]?.rawValue, "45299")
        XCTAssertEqual(result.values[address("B3")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("B4")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("B5")]?.rawValue, "45300")
        XCTAssertEqual(result.values[address("B6")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("B7")]?.rawValue, "45297")
        XCTAssertEqual(result.values[address("B8")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("B9")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("B10")]?.rawValue, "#REF!")
        XCTAssertEqual(result.values[address("B11")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("B12")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("C1")]?.rawValue, "5")
        XCTAssertEqual(result.values[address("C2")]?.rawValue, "3")
        XCTAssertEqual(result.values[address("C3")]?.rawValue, "-5")
        XCTAssertEqual(result.values[address("C4")]?.rawValue, "0")
        XCTAssertEqual(result.values[address("C5")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("C6")]?.rawValue, "#N/A")
        XCTAssertEqual(result.values[address("C7")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("D1")]?.rawValue, "6")
        XCTAssertEqual(result.values[address("D2")]?.rawValue, "5")
        XCTAssertEqual(result.values[address("D3")]?.rawValue, "0")
        XCTAssertEqual(result.values[address("D4")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("D5")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("D6")]?.rawValue, "4")
        XCTAssertEqual(result.values[address("D7")]?.rawValue, "-6")
        XCTAssertEqual(result.values[address("D8")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("D9")]?.rawValue, "#N/A")
        XCTAssertEqual(result.values[address("D10")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("D11")]?.rawValue, "#NUM!")
    }

    func testFormulaCalculatorSupportsExtendedMathAndStatisticsFunctions() {
        let cells: [ExcelCellAddress: ExcelCell] = [
            address("A1"): formulaCell(
                "A1", "PRODUCT(J1:J7)", cached: "0"
            ),
            address("A2"): formulaCell(
                "A2", "PRODUCT(J1:J7,2)", cached: "0"
            ),
            address("A3"): formulaCell(
                "A3", "PRODUCT(TRUE,2)", cached: "0"
            ),
            address("A4"): formulaCell(
                "A4", "PRODUCT(\"3\",2)", cached: "0"
            ),
            address("A5"): formulaCell(
                "A5", "PRODUCT(J7)", cached: "0"
            ),
            address("A6"): formulaCell(
                "A6", "PRODUCT(#N/A,2)", cached: "0"
            ),
            address("A7"): formulaCell(
                "A7", "MEDIAN(J1:J7)", cached: "0"
            ),
            address("A8"): formulaCell(
                "A8", "MEDIAN(1,TRUE,\"3\")", cached: "0"
            ),
            address("A9"): formulaCell(
                "A9", "MEDIAN(J7)", cached: "0"
            ),
            address("A10"): formulaCell(
                "A10", "MEDIAN(#REF!,1)", cached: "0"
            ),
            address("B1"): formulaCell(
                "B1", "LARGE(J1:J7,2)", cached: "0"
            ),
            address("B2"): formulaCell(
                "B2", "SMALL(J1:J7,2)", cached: "0"
            ),
            address("B3"): formulaCell(
                "B3", "LARGE(J1:J7,1.9)", cached: "0"
            ),
            address("B4"): formulaCell(
                "B4", "LARGE(J1:J7,0)", cached: "0"
            ),
            address("B5"): formulaCell(
                "B5", "SMALL(J1:J7,5)", cached: "0"
            ),
            address("B6"): formulaCell(
                "B6", "LARGE(J1:J7,\"bad\")", cached: "0"
            ),
            address("B7"): formulaCell(
                "B7", "SMALL(K1,1)", cached: "0"
            ),
            address("B8"): formulaCell(
                "B8", "SUMPRODUCT(L1:L3,M1:M3)", cached: "0"
            ),
            address("B9"): formulaCell(
                "B9", "SUMPRODUCT(L1:L3)", cached: "0"
            ),
            address("B10"): formulaCell(
                "B10", "SUMPRODUCT(L1:L3,M1:M2)", cached: "0"
            ),
            address("B11"): formulaCell(
                "B11", "SUMPRODUCT(L1:L3,O1:O3)", cached: "0"
            ),
            address("B12"): formulaCell(
                "B12", "SUMPRODUCT(L1:L3,P1:P3)", cached: "0"
            ),
            address("B13"): formulaCell(
                "B13", "SUMPRODUCT(2,3)", cached: "0"
            ),
            address("C1"): formulaCell("C1", "MOD(3,2)", cached: "0"),
            address("C2"): formulaCell("C2", "MOD(-3,2)", cached: "0"),
            address("C3"): formulaCell("C3", "MOD(3,-2)", cached: "0"),
            address("C4"): formulaCell("C4", "MOD(1,0)", cached: "0"),
            address("C5"): formulaCell(
                "C5", "MOD(\"bad\",2)", cached: "0"
            ),
            address("C6"): formulaCell("C6", "MOD(#N/A,2)", cached: "0"),
            address("C7"): formulaCell("C7", "POWER(2,10)", cached: "0"),
            address("C8"): formulaCell("C8", "POWER(-2,3)", cached: "0"),
            address("C9"): formulaCell(
                "C9", "POWER(-2,0.5)", cached: "0"
            ),
            address("C10"): formulaCell("C10", "POWER(0,-1)", cached: "0"),
            address("C11"): formulaCell(
                "C11", "POWER(10,400)", cached: "0"
            ),
            address("C12"): formulaCell(
                "C12", "POWER(#REF!,2)", cached: "0"
            ),
            address("D1"): formulaCell("D1", "SQRT(16)", cached: "0"),
            address("D2"): formulaCell("D2", "SQRT(-16)", cached: "0"),
            address("D3"): formulaCell("D3", "SIGN(-3)", cached: "0"),
            address("D4"): formulaCell("D4", "SIGN(0)", cached: "0"),
            address("D5"): formulaCell("D5", "SIGN(3)", cached: "0"),
            address("D6"): formulaCell(
                "D6", "SIGN(\"bad\")", cached: "0"
            ),
            address("D7"): formulaCell("D7", "SIGN(#N/A)", cached: "0"),
            address("D8"): formulaCell("D8", "TRUNC(8.9)", cached: "0"),
            address("D9"): formulaCell("D9", "TRUNC(-8.9)", cached: "0"),
            address("D10"): formulaCell(
                "D10", "TRUNC(123.456,2)", cached: "0"
            ),
            address("D11"): formulaCell(
                "D11", "TRUNC(-123.456,-1)", cached: "0"
            ),
            address("D12"): formulaCell(
                "D12", "TRUNC(1,\"bad\")", cached: "0"
            ),
            address("D13"): formulaCell(
                "D13", "TRUNC(1,#REF!)", cached: "0"
            ),
            address("E1"): formulaCell(
                "E1", "QUOTIENT(5,2)", cached: "0"
            ),
            address("E2"): formulaCell(
                "E2", "QUOTIENT(-10,3)", cached: "0"
            ),
            address("E3"): formulaCell(
                "E3", "QUOTIENT(4.5,3.1)", cached: "0"
            ),
            address("E4"): formulaCell(
                "E4", "QUOTIENT(1,0)", cached: "0"
            ),
            address("E5"): formulaCell(
                "E5", "QUOTIENT(\"bad\",2)", cached: "0"
            ),
            address("E6"): formulaCell(
                "E6", "QUOTIENT(#N/A,2)", cached: "0"
            ),
            address("J1"): numericCell("J1", "3"),
            address("J2"): numericCell("J2", "5"),
            address("J3"): numericCell("J3", "3"),
            address("J4"): numericCell("J4", "9"),
            address("J5"): cell("J5", "ignored"),
            address("J6"): booleanCell("J6", true),
            address("K1"): errorCell("K1", "#REF!"),
            address("L1"): numericCell("L1", "2"),
            address("L2"): numericCell("L2", "3"),
            address("L3"): numericCell("L3", "4"),
            address("M1"): numericCell("M1", "5"),
            address("M2"): numericCell("M2", "6"),
            address("M3"): numericCell("M3", "7"),
            address("O1"): numericCell("O1", "5"),
            address("O2"): cell("O2", "ignored"),
            address("O3"): numericCell("O3", "7"),
            address("P1"): numericCell("P1", "5"),
            address("P2"): errorCell("P2", "#N/A"),
            address("P3"): numericCell("P3", "7"),
        ]

        let result = ExcelFormulaCalculator.recalculate(
            cells: cells,
            styles: [.plain],
            uses1904DateSystem: false
        )

        XCTAssertEqual(result.unsupportedFormulaCount, 0)
        XCTAssertEqual(result.values[address("A1")]?.rawValue, "405")
        XCTAssertEqual(result.values[address("A2")]?.rawValue, "810")
        XCTAssertEqual(result.values[address("A3")]?.rawValue, "2")
        XCTAssertEqual(result.values[address("A4")]?.rawValue, "6")
        XCTAssertEqual(result.values[address("A5")]?.rawValue, "0")
        XCTAssertEqual(result.values[address("A6")]?.rawValue, "#N/A")
        XCTAssertEqual(result.values[address("A7")]?.rawValue, "4")
        XCTAssertEqual(result.values[address("A8")]?.rawValue, "1")
        XCTAssertEqual(result.values[address("A9")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("A10")]?.rawValue, "#REF!")
        XCTAssertEqual(result.values[address("B1")]?.rawValue, "5")
        XCTAssertEqual(result.values[address("B2")]?.rawValue, "3")
        XCTAssertEqual(result.values[address("B3")]?.rawValue, "9")
        XCTAssertEqual(result.values[address("B4")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("B5")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("B6")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("B7")]?.rawValue, "#REF!")
        XCTAssertEqual(result.values[address("B8")]?.rawValue, "56")
        XCTAssertEqual(result.values[address("B9")]?.rawValue, "9")
        XCTAssertEqual(result.values[address("B10")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("B11")]?.rawValue, "38")
        XCTAssertEqual(result.values[address("B12")]?.rawValue, "#N/A")
        XCTAssertEqual(result.values[address("B13")]?.rawValue, "6")
        XCTAssertEqual(result.values[address("C1")]?.rawValue, "1")
        XCTAssertEqual(result.values[address("C2")]?.rawValue, "1")
        XCTAssertEqual(result.values[address("C3")]?.rawValue, "-1")
        XCTAssertEqual(result.values[address("C4")]?.rawValue, "#DIV/0!")
        XCTAssertEqual(result.values[address("C5")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("C6")]?.rawValue, "#N/A")
        XCTAssertEqual(result.values[address("C7")]?.rawValue, "1024")
        XCTAssertEqual(result.values[address("C8")]?.rawValue, "-8")
        XCTAssertEqual(result.values[address("C9")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("C10")]?.rawValue, "#DIV/0!")
        XCTAssertEqual(result.values[address("C11")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("C12")]?.rawValue, "#REF!")
        XCTAssertEqual(result.values[address("D1")]?.rawValue, "4")
        XCTAssertEqual(result.values[address("D2")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("D3")]?.rawValue, "-1")
        XCTAssertEqual(result.values[address("D4")]?.rawValue, "0")
        XCTAssertEqual(result.values[address("D5")]?.rawValue, "1")
        XCTAssertEqual(result.values[address("D6")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("D7")]?.rawValue, "#N/A")
        XCTAssertEqual(result.values[address("D8")]?.rawValue, "8")
        XCTAssertEqual(result.values[address("D9")]?.rawValue, "-8")
        XCTAssertEqual(result.values[address("D10")]?.rawValue, "123.45")
        XCTAssertEqual(result.values[address("D11")]?.rawValue, "-120")
        XCTAssertEqual(result.values[address("D12")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("D13")]?.rawValue, "#REF!")
        XCTAssertEqual(result.values[address("E1")]?.rawValue, "2")
        XCTAssertEqual(result.values[address("E2")]?.rawValue, "-3")
        XCTAssertEqual(result.values[address("E3")]?.rawValue, "1")
        XCTAssertEqual(result.values[address("E4")]?.rawValue, "#DIV/0!")
        XCTAssertEqual(result.values[address("E5")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("E6")]?.rawValue, "#N/A")
    }

    func testFormulaCalculatorSupportsInformationFunctions() {
        let cells: [ExcelCellAddress: ExcelCell] = [
            address("A1"): formulaCell("A1", "ISBLANK(J1)", cached: "0"),
            address("A2"): formulaCell("A2", "ISBLANK(J2)", cached: "0"),
            address("A3"): formulaCell("A3", "ISBLANK(\"\")", cached: "0"),
            address("A4"): formulaCell("A4", "ISNUMBER(J3)", cached: "0"),
            address("A5"): formulaCell("A5", "ISNUMBER(\"19\")", cached: "0"),
            address("A6"): formulaCell("A6", "ISTEXT(J4)", cached: "0"),
            address("A7"): formulaCell("A7", "ISTEXT(J3)", cached: "0"),
            address("A8"): formulaCell("A8", "ISLOGICAL(J5)", cached: "0"),
            address("A9"): formulaCell(
                "A9", "ISLOGICAL(\"TRUE\")", cached: "0"
            ),
            address("B1"): formulaCell("B1", "ISERROR(#N/A)", cached: "0"),
            address("B2"): formulaCell("B2", "ISERROR(1/0)", cached: "0"),
            address("B3"): formulaCell("B3", "ISERROR(1)", cached: "0"),
            address("B4"): formulaCell("B4", "ISERR(#REF!)", cached: "0"),
            address("B5"): formulaCell("B5", "ISERR(#N/A)", cached: "0"),
            address("B6"): formulaCell("B6", "ISNA(#N/A)", cached: "0"),
            address("B7"): formulaCell("B7", "ISNA(#VALUE!)", cached: "0"),
            address("B8"): formulaCell(
                "B8", "IF(ISERROR(1/0),99,0)", cached: "0"
            ),
            address("C1"): formulaCell("C1", "N(7)", cached: "0"),
            address("C2"): formulaCell("C2", "N(TRUE)", cached: "0"),
            address("C3"): formulaCell("C3", "N(FALSE)", cached: "0"),
            address("C4"): formulaCell("C4", "N(\"7\")", cached: "0"),
            address("C5"): formulaCell("C5", "N(J1)", cached: "0"),
            address("C6"): formulaCell("C6", "N(#DIV/0!)", cached: "0"),
            address("C7"): formulaCell("C7", "NA()", cached: "0"),
            address("C8"): formulaCell("C8", "NA(1)", cached: "0"),
            address("D1"): formulaCell("D1", "TYPE(J3)", cached: "0"),
            address("D2"): formulaCell("D2", "TYPE(J4)", cached: "0"),
            address("D3"): formulaCell("D3", "TYPE(J5)", cached: "0"),
            address("D4"): formulaCell("D4", "TYPE(#REF!)", cached: "0"),
            address("D5"): formulaCell("D5", "TYPE(J1)", cached: "0"),
            address("D6"): formulaCell("D6", "TYPE(J3:J5)", cached: "0"),
            address("D7"): formulaCell("D7", "TYPE()", cached: "0"),
            address("D8"): formulaCell("D8", "ISERROR()", cached: "0"),
            address("J2"): cell("J2", ""),
            address("J3"): numericCell("J3", "19"),
            address("J4"): cell("J4", "학생"),
            address("J5"): booleanCell("J5", true),
        ]

        let result = ExcelFormulaCalculator.recalculate(
            cells: cells,
            styles: [.plain],
            uses1904DateSystem: false
        )

        XCTAssertEqual(result.unsupportedFormulaCount, 0)
        XCTAssertEqual(result.values[address("A1")]?.rawValue, "TRUE")
        XCTAssertEqual(result.values[address("A2")]?.rawValue, "TRUE")
        XCTAssertEqual(result.values[address("A3")]?.rawValue, "FALSE")
        XCTAssertEqual(result.values[address("A4")]?.rawValue, "TRUE")
        XCTAssertEqual(result.values[address("A5")]?.rawValue, "FALSE")
        XCTAssertEqual(result.values[address("A6")]?.rawValue, "TRUE")
        XCTAssertEqual(result.values[address("A7")]?.rawValue, "FALSE")
        XCTAssertEqual(result.values[address("A8")]?.rawValue, "TRUE")
        XCTAssertEqual(result.values[address("A9")]?.rawValue, "FALSE")
        XCTAssertEqual(result.values[address("B1")]?.rawValue, "TRUE")
        XCTAssertEqual(result.values[address("B2")]?.rawValue, "TRUE")
        XCTAssertEqual(result.values[address("B3")]?.rawValue, "FALSE")
        XCTAssertEqual(result.values[address("B4")]?.rawValue, "TRUE")
        XCTAssertEqual(result.values[address("B5")]?.rawValue, "FALSE")
        XCTAssertEqual(result.values[address("B6")]?.rawValue, "TRUE")
        XCTAssertEqual(result.values[address("B7")]?.rawValue, "FALSE")
        XCTAssertEqual(result.values[address("B8")]?.rawValue, "99")
        XCTAssertEqual(result.values[address("C1")]?.rawValue, "7")
        XCTAssertEqual(result.values[address("C2")]?.rawValue, "1")
        XCTAssertEqual(result.values[address("C3")]?.rawValue, "0")
        XCTAssertEqual(result.values[address("C4")]?.rawValue, "0")
        XCTAssertEqual(result.values[address("C5")]?.rawValue, "0")
        XCTAssertEqual(result.values[address("C6")]?.rawValue, "#DIV/0!")
        XCTAssertEqual(result.values[address("C7")]?.rawValue, "#N/A")
        XCTAssertEqual(result.values[address("C8")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("D1")]?.rawValue, "1")
        XCTAssertEqual(result.values[address("D2")]?.rawValue, "2")
        XCTAssertEqual(result.values[address("D3")]?.rawValue, "4")
        XCTAssertEqual(result.values[address("D4")]?.rawValue, "16")
        XCTAssertEqual(result.values[address("D5")]?.rawValue, "1")
        XCTAssertEqual(result.values[address("D6")]?.rawValue, "64")
        XCTAssertEqual(result.values[address("D7")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("D8")]?.rawValue, "#VALUE!")
    }

    func testFormulaCalculatorSupportsConditionalStatistics() {
        let cells: [ExcelCellAddress: ExcelCell] = [
            address("A1"): formulaCell(
                "A1", "COUNTBLANK(N1:N5)", cached: "0"
            ),
            address("A2"): formulaCell(
                "A2", "COUNTBLANK(N4)", cached: "0"
            ),
            address("A3"): formulaCell(
                "A3", "COUNTBLANK(1)", cached: "0"
            ),
            address("A4"): formulaCell(
                "A4", "AVERAGEIF(K1:K6,\"A\",J1:J6)", cached: "0"
            ),
            address("A5"): formulaCell(
                "A5", "AVERAGEIF(K1:K6,\"Z\",J1:J6)", cached: "0"
            ),
            address("A6"): formulaCell(
                "A6", "AVERAGEIF(K1:K6,\"A\",P1)", cached: "0"
            ),
            address("A7"): formulaCell(
                "A7",
                "AVERAGEIFS(J1:J6,K1:K6,\"A\",L1:L6,1)",
                cached: "0"
            ),
            address("A8"): formulaCell(
                "A8", "AVERAGEIFS(J1:J6,K1:K6,\"Z\")", cached: "0"
            ),
            address("A9"): formulaCell(
                "A9", "AVERAGEIFS(J1:J6,K1:K5,\"A\")", cached: "0"
            ),
            address("B1"): formulaCell(
                "B1", "MAXIFS(J1:J6,K1:K6,\"A\")", cached: "0"
            ),
            address("B2"): formulaCell(
                "B2", "MINIFS(J1:J6,K1:K6,\"A\")", cached: "0"
            ),
            address("B3"): formulaCell(
                "B3", "MAXIFS(J1:J6,K1:K6,\"Z\")", cached: "0"
            ),
            address("B4"): formulaCell(
                "B4", "MINIFS(J1:J6,K1:K5,\"A\")", cached: "0"
            ),
            address("B5"): formulaCell(
                "B5", "MAXIFS(J1:J6,L1:L6,O1)", cached: "0"
            ),
            address("J1"): numericCell("J1", "10"),
            address("J2"): numericCell("J2", "20"),
            address("J3"): numericCell("J3", "30"),
            address("J4"): numericCell("J4", "60"),
            address("J5"): numericCell("J5", "50"),
            address("J6"): cell("J6", "제외"),
            address("K1"): cell("K1", "A"),
            address("K2"): cell("K2", "A"),
            address("K3"): cell("K3", "B"),
            address("K4"): cell("K4", "A"),
            address("K5"): cell("K5", "B"),
            address("K6"): cell("K6", "A"),
            address("L1"): numericCell("L1", "1"),
            address("L2"): numericCell("L2", "0"),
            address("L3"): numericCell("L3", "1"),
            address("L4"): numericCell("L4", "1"),
            address("L5"): numericCell("L5", "0"),
            address("L6"): numericCell("L6", "1"),
            address("N2"): cell("N2", ""),
            address("N3"): formulaCell("N3", "\"\"", cached: ""),
            address("N4"): numericCell("N4", "0"),
            address("N5"): cell("N5", "값"),
            address("P1"): numericCell("P1", "100"),
        ]

        let result = ExcelFormulaCalculator.recalculate(
            cells: cells,
            styles: [.plain],
            uses1904DateSystem: false
        )

        XCTAssertEqual(result.unsupportedFormulaCount, 0)
        XCTAssertEqual(result.values[address("A1")]?.rawValue, "3")
        XCTAssertEqual(result.values[address("A2")]?.rawValue, "0")
        XCTAssertEqual(result.values[address("A3")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("A4")]?.rawValue, "30")
        XCTAssertEqual(result.values[address("A5")]?.rawValue, "#DIV/0!")
        XCTAssertEqual(result.values[address("A6")]?.rawValue, "100")
        XCTAssertEqual(result.values[address("A7")]?.rawValue, "35")
        XCTAssertEqual(result.values[address("A8")]?.rawValue, "#DIV/0!")
        XCTAssertEqual(result.values[address("A9")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("B1")]?.rawValue, "60")
        XCTAssertEqual(result.values[address("B2")]?.rawValue, "10")
        XCTAssertEqual(result.values[address("B3")]?.rawValue, "0")
        XCTAssertEqual(result.values[address("B4")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("B5")]?.rawValue, "50")
    }

    func testFormulaCalculatorSupportsVarianceDeviationAndRanks() {
        let cells: [ExcelCellAddress: ExcelCell] = [
            address("A1"): formulaCell("A1", "STDEV.S(J1:J6)", cached: "0"),
            address("A2"): formulaCell("A2", "VAR.S(J1:J6)", cached: "0"),
            address("A3"): formulaCell("A3", "STDEV.P(K1:K8)", cached: "0"),
            address("A4"): formulaCell("A4", "VAR.P(K1:K8)", cached: "0"),
            address("A5"): formulaCell("A5", "VAR.P(TRUE,\"3\")", cached: "0"),
            address("A6"): formulaCell("A6", "STDEV.S(1)", cached: "0"),
            address("A7"): formulaCell("A7", "VAR.P(J4:J6)", cached: "0"),
            address("A8"): formulaCell("A8", "STDEV.S(#N/A,1)", cached: "0"),
            address("A9"): formulaCell("A9", "VAR.S(\"bad\",1)", cached: "0"),
            address("B1"): formulaCell(
                "B1", "RANK.EQ(7,L1:L7,1)", cached: "0"
            ),
            address("B2"): formulaCell(
                "B2", "RANK.EQ(2,L1:L7)", cached: "0"
            ),
            address("B3"): formulaCell(
                "B3", "RANK.EQ(3.5,L1:L7,1)", cached: "0"
            ),
            address("B4"): formulaCell(
                "B4", "RANK.AVG(3.5,L1:L7,1)", cached: "0"
            ),
            address("B5"): formulaCell(
                "B5", "RANK.AVG(6,L1:L7)", cached: "0"
            ),
            address("B6"): formulaCell(
                "B6", "RANK.EQ(1,L1:L7,\"bad\")", cached: "0"
            ),
            address("B7"): formulaCell(
                "B7", "RANK.EQ(1,2)", cached: "0"
            ),
            address("J1"): numericCell("J1", "1"),
            address("J2"): numericCell("J2", "2"),
            address("J3"): numericCell("J3", "3"),
            address("J4"): cell("J4", "제외"),
            address("J5"): booleanCell("J5", true),
            address("J6"): errorCell("J6", "#N/A"),
            address("K1"): numericCell("K1", "2"),
            address("K2"): numericCell("K2", "4"),
            address("K3"): numericCell("K3", "4"),
            address("K4"): numericCell("K4", "4"),
            address("K5"): numericCell("K5", "5"),
            address("K6"): numericCell("K6", "5"),
            address("K7"): numericCell("K7", "7"),
            address("K8"): numericCell("K8", "9"),
            address("L1"): numericCell("L1", "7"),
            address("L2"): numericCell("L2", "3.5"),
            address("L3"): numericCell("L3", "3.5"),
            address("L4"): numericCell("L4", "1"),
            address("L5"): numericCell("L5", "2"),
            address("L6"): cell("L6", "제외"),
            address("L7"): errorCell("L7", "#REF!"),
        ]

        let result = ExcelFormulaCalculator.recalculate(
            cells: cells,
            styles: [.plain],
            uses1904DateSystem: false
        )

        XCTAssertEqual(result.unsupportedFormulaCount, 0)
        XCTAssertEqual(result.values[address("A1")]?.rawValue, "1")
        XCTAssertEqual(result.values[address("A2")]?.rawValue, "1")
        XCTAssertEqual(result.values[address("A3")]?.rawValue, "2")
        XCTAssertEqual(result.values[address("A4")]?.rawValue, "4")
        XCTAssertEqual(result.values[address("A5")]?.rawValue, "1")
        XCTAssertEqual(result.values[address("A6")]?.rawValue, "#DIV/0!")
        XCTAssertEqual(result.values[address("A7")]?.rawValue, "#DIV/0!")
        XCTAssertEqual(result.values[address("A8")]?.rawValue, "#N/A")
        XCTAssertEqual(result.values[address("A9")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("B1")]?.rawValue, "5")
        XCTAssertEqual(result.values[address("B2")]?.rawValue, "4")
        XCTAssertEqual(result.values[address("B3")]?.rawValue, "3")
        XCTAssertEqual(result.values[address("B4")]?.rawValue, "3.5")
        XCTAssertEqual(result.values[address("B5")]?.rawValue, "2")
        XCTAssertEqual(result.values[address("B6")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("B7")]?.rawValue, "#VALUE!")
    }

    func testFormulaCalculatorSupportsTextConversionFunctions() {
        let cells: [ExcelCellAddress: ExcelCell] = [
            address("A1"): formulaCell(
                "A1", "EXACT(\"Excel\",\"Excel\")", cached: ""
            ),
            address("A2"): formulaCell(
                "A2", "EXACT(\"Excel\",\"excel\")", cached: ""
            ),
            address("A3"): formulaCell("A3", "CHAR(65)", cached: ""),
            address("A4"): formulaCell("A4", "CODE(\"A\")", cached: "0"),
            address("A5"): formulaCell(
                "A5", "UNICHAR(128512)", cached: ""
            ),
            address("A6"): formulaCell(
                "A6", "UNICODE(\"😀\")", cached: "0"
            ),
            address("A7"): formulaCell("A7", "CHAR(0)", cached: ""),
            address("A8"): formulaCell("A8", "UNICHAR(0)", cached: ""),
            address("A9"): formulaCell(
                "A9", "UNICHAR(55296)", cached: ""
            ),
            address("A10"): formulaCell(
                "A10", "UNICODE(\"\")", cached: ""
            ),
            address("B1"): formulaCell(
                "B1", "VALUE(\"$1,000\")", cached: "0"
            ),
            address("B2"): formulaCell(
                "B2", "VALUE(\"16:48:00\")", cached: "0"
            ),
            address("B3"): formulaCell(
                "B3", "VALUE(\"28.5%\")", cached: "0"
            ),
            address("B4"): formulaCell(
                "B4", "VALUE(\"1 1/2\")", cached: "0"
            ),
            address("B5"): formulaCell(
                "B5", "VALUE(\"bad\")", cached: "0"
            ),
            address("B6"): formulaCell("B6", "VALUE(TRUE)", cached: "0"),
            address("C1"): formulaCell(
                "C1", "TEXT(1234.567,\"$#,##0.00\")", cached: ""
            ),
            address("C2"): formulaCell(
                "C2", "TEXT(0.285,\"0.0%\")", cached: ""
            ),
            address("C3"): formulaCell(
                "C3", "TEXT(1234,\"0000000\")", cached: ""
            ),
            address("C4"): formulaCell(
                "C4",
                "TEXT(DATE(2024,2,3),\"yyyy-mm-dd\")",
                cached: ""
            ),
            address("C5"): formulaCell(
                "C5", "TEXT(TIME(13,5,9),\"hh:mm:ss\")", cached: ""
            ),
            address("C6"): formulaCell(
                "C6", "TEXT(-12.3,\"0.00;(0.00);zero\")", cached: ""
            ),
            address("C7"): formulaCell(
                "C7", #"TEXT(0,"0.00;(0.00);""zero""")"#, cached: ""
            ),
            address("C8"): formulaCell(
                "C8", "TEXT(12200000,\"0.00E+00\")", cached: ""
            ),
            address("C9"): formulaCell(
                "C9", "TRIM(TEXT(4.34,\"# ?/?\"))", cached: ""
            ),
        ]

        let result = ExcelFormulaCalculator.recalculate(
            cells: cells,
            styles: [.plain],
            uses1904DateSystem: false,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        XCTAssertEqual(result.unsupportedFormulaCount, 0)
        XCTAssertEqual(result.values[address("A1")]?.rawValue, "TRUE")
        XCTAssertEqual(result.values[address("A2")]?.rawValue, "FALSE")
        XCTAssertEqual(result.values[address("A3")]?.rawValue, "A")
        XCTAssertEqual(result.values[address("A4")]?.rawValue, "65")
        XCTAssertEqual(result.values[address("A5")]?.rawValue, "😀")
        XCTAssertEqual(result.values[address("A6")]?.rawValue, "128512")
        XCTAssertEqual(result.values[address("A7")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("A8")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("A9")]?.rawValue, "#N/A")
        XCTAssertEqual(result.values[address("A10")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("B1")]?.rawValue, "1000")
        XCTAssertEqual(result.values[address("B2")]?.rawValue, "0.7")
        XCTAssertEqual(result.values[address("B3")]?.rawValue, "0.285")
        XCTAssertEqual(result.values[address("B4")]?.rawValue, "1.5")
        XCTAssertEqual(result.values[address("B5")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("B6")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("C1")]?.rawValue, "$1,234.57")
        XCTAssertEqual(result.values[address("C2")]?.rawValue, "28.5%")
        XCTAssertEqual(result.values[address("C3")]?.rawValue, "0001234")
        XCTAssertEqual(result.values[address("C4")]?.rawValue, "2024-02-03")
        XCTAssertEqual(result.values[address("C5")]?.rawValue, "13:05:09")
        XCTAssertEqual(result.values[address("C6")]?.rawValue, "(12.30)")
        XCTAssertEqual(result.values[address("C7")]?.rawValue, "zero")
        XCTAssertEqual(result.values[address("C8")]?.rawValue, "1.22E+07")
        XCTAssertEqual(result.values[address("C9")]?.rawValue, "4 1/3")
    }

    func testFormulaCalculatorSupportsTextBoundaryFunctions() {
        let cells: [ExcelCellAddress: ExcelCell] = [
            address("A1"): formulaCell(
                "A1", "TEXTBEFORE(\"red-Blue-red\",\"-\",2)", cached: ""
            ),
            address("A2"): formulaCell(
                "A2", "TEXTAFTER(\"red-Blue-red\",\"-\",2)", cached: ""
            ),
            address("A3"): formulaCell(
                "A3", "TEXTBEFORE(\"red-Blue-red\",\"-\",-1)", cached: ""
            ),
            address("A4"): formulaCell(
                "A4", "TEXTAFTER(\"red-Blue-red\",\"-\",-2)", cached: ""
            ),
            address("A5"): formulaCell(
                "A5", "TEXTBEFORE(\"red-Blue-red\",\"BLUE\",1,1)", cached: ""
            ),
            address("A6"): formulaCell(
                "A6", "TEXTAFTER(\"Socrates\",\" \",,,1)", cached: ""
            ),
            address("A7"): formulaCell(
                "A7", "TEXTBEFORE(\"Socrates\",\" \",,,1)", cached: ""
            ),
            address("A8"): formulaCell(
                "A8",
                "TEXTAFTER(\"abc\",\"x\",1,0,0,\"없음\")",
                cached: ""
            ),
            address("A9"): formulaCell(
                "A9", "TEXTBEFORE(\"abc\",\"x\")", cached: ""
            ),
            address("A10"): formulaCell(
                "A10", "TEXTBEFORE(\"abc\",\"b\",0)", cached: ""
            ),
            address("A11"): formulaCell(
                "A11", "TEXTAFTER(\"abc\",\"b\",4)", cached: ""
            ),
            address("B1"): formulaCell(
                "B1", "TEXTBEFORE(\"abc\",\"\")", cached: ""
            ),
            address("B2"): formulaCell(
                "B2", "TEXTAFTER(\"abc\",\"\")", cached: ""
            ),
            address("B3"): formulaCell(
                "B3", "TEXTBEFORE(\"abc\",\"\",-1)", cached: ""
            ),
            address("B4"): formulaCell(
                "B4", "TEXTAFTER(\"abc\",\"\",-1)", cached: ""
            ),
            address("B5"): formulaCell("B5", "IF(,1,2)", cached: "0"),
            address("B6"): formulaCell(
                "B6", "TEXTBEFORE(\"abc\",\"x\",1,2)", cached: ""
            ),
            address("B7"): formulaCell(
                "B7", "TEXTBEFORE(\"abc\",\"x\",1,0,0,99)", cached: "0"
            ),
        ]

        let result = ExcelFormulaCalculator.recalculate(
            cells: cells,
            styles: [.plain],
            uses1904DateSystem: false
        )

        XCTAssertEqual(result.unsupportedFormulaCount, 0)
        XCTAssertEqual(result.values[address("A1")]?.rawValue, "red-Blue")
        XCTAssertEqual(result.values[address("A2")]?.rawValue, "red")
        XCTAssertEqual(result.values[address("A3")]?.rawValue, "red-Blue")
        XCTAssertEqual(result.values[address("A4")]?.rawValue, "Blue-red")
        XCTAssertEqual(result.values[address("A5")]?.rawValue, "red-")
        XCTAssertEqual(result.values[address("A6")]?.rawValue, "")
        XCTAssertEqual(result.values[address("A7")]?.rawValue, "Socrates")
        XCTAssertEqual(result.values[address("A8")]?.rawValue, "없음")
        XCTAssertEqual(result.values[address("A9")]?.rawValue, "#N/A")
        XCTAssertEqual(result.values[address("A10")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("A11")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("B1")]?.rawValue, "")
        XCTAssertEqual(result.values[address("B2")]?.rawValue, "abc")
        XCTAssertEqual(result.values[address("B3")]?.rawValue, "abc")
        XCTAssertEqual(result.values[address("B4")]?.rawValue, "")
        XCTAssertEqual(result.values[address("B5")]?.rawValue, "2")
        XCTAssertEqual(result.values[address("B6")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("B7")]?.rawValue, "99")
    }

    func testFormulaCalculatorSupportsLogarithmicAndTrigonometricFunctions() {
        let cells: [ExcelCellAddress: ExcelCell] = [
            address("A1"): formulaCell(
                "A1", "ROUND(PI(),10)", cached: "0"
            ),
            address("A2"): formulaCell(
                "A2", "DEGREES(PI())", cached: "0"
            ),
            address("A3"): formulaCell(
                "A3", "ROUND(RADIANS(180),12)", cached: "0"
            ),
            address("A4"): formulaCell(
                "A4", "ROUND(EXP(1),10)", cached: "0"
            ),
            address("A5"): formulaCell(
                "A5", "ROUND(LN(EXP(3)),10)", cached: "0"
            ),
            address("A6"): formulaCell("A6", "LOG(8,2)", cached: "0"),
            address("A7"): formulaCell("A7", "LOG10(1000)", cached: "0"),
            address("B1"): formulaCell(
                "B1", "ROUND(SIN(RADIANS(30)),10)", cached: "0"
            ),
            address("B2"): formulaCell(
                "B2", "ROUND(COS(RADIANS(60)),10)", cached: "0"
            ),
            address("B3"): formulaCell(
                "B3", "ROUND(TAN(RADIANS(45)),10)", cached: "0"
            ),
            address("B4"): formulaCell(
                "B4", "ROUND(DEGREES(ASIN(0.5)),10)", cached: "0"
            ),
            address("B5"): formulaCell(
                "B5", "ROUND(DEGREES(ACOS(0.5)),10)", cached: "0"
            ),
            address("B6"): formulaCell(
                "B6", "ROUND(DEGREES(ATAN(1)),10)", cached: "0"
            ),
            address("B7"): formulaCell(
                "B7", "ROUND(DEGREES(ATAN2(1,1)),10)", cached: "0"
            ),
            address("B8"): formulaCell(
                "B8", "ROUND(DEGREES(ATAN2(-1,-1)),10)", cached: "0"
            ),
            address("C1"): formulaCell("C1", "LN(0)", cached: "0"),
            address("C2"): formulaCell("C2", "LOG(-1)", cached: "0"),
            address("C3"): formulaCell("C3", "LOG(8,1)", cached: "0"),
            address("C4"): formulaCell("C4", "ASIN(2)", cached: "0"),
            address("C5"): formulaCell("C5", "ACOS(-2)", cached: "0"),
            address("C6"): formulaCell("C6", "ATAN2(0,0)", cached: "0"),
            address("C7"): formulaCell("C7", "EXP(1000)", cached: "0"),
            address("C8"): formulaCell("C8", "PI(1)", cached: "0"),
            address("C9"): formulaCell("C9", "SIN(\"bad\")", cached: "0"),
            address("C10"): formulaCell("C10", "LOG(100,)", cached: "0"),
            address("C11"): formulaCell("C11", "COS(#N/A)", cached: "0"),
        ]

        let result = ExcelFormulaCalculator.recalculate(
            cells: cells,
            styles: [.plain],
            uses1904DateSystem: false
        )

        XCTAssertEqual(result.unsupportedFormulaCount, 0)
        XCTAssertEqual(result.values[address("A1")]?.rawValue, "3.1415926536")
        XCTAssertEqual(result.values[address("A2")]?.rawValue, "180")
        XCTAssertEqual(result.values[address("A3")]?.rawValue, "3.14159265359")
        XCTAssertEqual(result.values[address("A4")]?.rawValue, "2.7182818285")
        XCTAssertEqual(result.values[address("A5")]?.rawValue, "3")
        XCTAssertEqual(result.values[address("A6")]?.rawValue, "3")
        XCTAssertEqual(result.values[address("A7")]?.rawValue, "3")
        XCTAssertEqual(result.values[address("B1")]?.rawValue, "0.5")
        XCTAssertEqual(result.values[address("B2")]?.rawValue, "0.5")
        XCTAssertEqual(result.values[address("B3")]?.rawValue, "1")
        XCTAssertEqual(result.values[address("B4")]?.rawValue, "30")
        XCTAssertEqual(result.values[address("B5")]?.rawValue, "60")
        XCTAssertEqual(result.values[address("B6")]?.rawValue, "45")
        XCTAssertEqual(result.values[address("B7")]?.rawValue, "45")
        XCTAssertEqual(result.values[address("B8")]?.rawValue, "-135")
        XCTAssertEqual(result.values[address("C1")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("C2")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("C3")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("C4")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("C5")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("C6")]?.rawValue, "#DIV/0!")
        XCTAssertEqual(result.values[address("C7")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("C8")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("C9")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("C10")]?.rawValue, "2")
        XCTAssertEqual(result.values[address("C11")]?.rawValue, "#N/A")
    }

    func testFormulaCalculatorSupportsMultipleAndParityRoundingFunctions() {
        let cells: [ExcelCellAddress: ExcelCell] = [
            address("A1"): formulaCell("A1", "CEILING(2.5,1)", cached: "0"),
            address("A2"): formulaCell("A2", "CEILING(-2.5,-2)", cached: "0"),
            address("A3"): formulaCell("A3", "CEILING(-2.5,2)", cached: "0"),
            address("A4"): formulaCell("A4", "CEILING(2.5,-2)", cached: "0"),
            address("A5"): formulaCell("A5", "CEILING(0.3,0.1)", cached: "0"),
            address("B1"): formulaCell("B1", "FLOOR(3.7,2)", cached: "0"),
            address("B2"): formulaCell("B2", "FLOOR(-2.5,-2)", cached: "0"),
            address("B3"): formulaCell("B3", "FLOOR(-2.5,2)", cached: "0"),
            address("B4"): formulaCell("B4", "FLOOR(2.5,-2)", cached: "0"),
            address("C1"): formulaCell("C1", "CEILING.MATH(-5.5,2)", cached: "0"),
            address("C2"): formulaCell("C2", "CEILING.MATH(-5.5,2,1)", cached: "0"),
            address("C3"): formulaCell("C3", "FLOOR.MATH(-5.5,2)", cached: "0"),
            address("C4"): formulaCell("C4", "FLOOR.MATH(-5.5,2,1)", cached: "0"),
            address("C5"): formulaCell("C5", "CEILING.PRECISE(-5.5,2)", cached: "0"),
            address("C6"): formulaCell("C6", "FLOOR.PRECISE(-5.5,2)", cached: "0"),
            address("D1"): formulaCell("D1", "MROUND(10,3)", cached: "0"),
            address("D2"): formulaCell("D2", "MROUND(-10,-3)", cached: "0"),
            address("D3"): formulaCell("D3", "MROUND(5,2)", cached: "0"),
            address("D4"): formulaCell("D4", "MROUND(10,-3)", cached: "0"),
            address("D5"): formulaCell("D5", "EVEN(3.2)", cached: "0"),
            address("D6"): formulaCell("D6", "EVEN(-3.2)", cached: "0"),
            address("D7"): formulaCell("D7", "ODD(2)", cached: "0"),
            address("D8"): formulaCell("D8", "ODD(-2)", cached: "0"),
        ]

        let result = ExcelFormulaCalculator.recalculate(
            cells: cells,
            styles: [.plain],
            uses1904DateSystem: false
        )

        XCTAssertEqual(result.unsupportedFormulaCount, 0)
        XCTAssertEqual(result.values[address("A1")]?.rawValue, "3")
        XCTAssertEqual(result.values[address("A2")]?.rawValue, "-4")
        XCTAssertEqual(result.values[address("A3")]?.rawValue, "-2")
        XCTAssertEqual(result.values[address("A4")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("A5")]?.rawValue, "0.3")
        XCTAssertEqual(result.values[address("B1")]?.rawValue, "2")
        XCTAssertEqual(result.values[address("B2")]?.rawValue, "-2")
        XCTAssertEqual(result.values[address("B3")]?.rawValue, "-4")
        XCTAssertEqual(result.values[address("B4")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("C1")]?.rawValue, "-4")
        XCTAssertEqual(result.values[address("C2")]?.rawValue, "-6")
        XCTAssertEqual(result.values[address("C3")]?.rawValue, "-6")
        XCTAssertEqual(result.values[address("C4")]?.rawValue, "-4")
        XCTAssertEqual(result.values[address("C5")]?.rawValue, "-4")
        XCTAssertEqual(result.values[address("C6")]?.rawValue, "-6")
        XCTAssertEqual(result.values[address("D1")]?.rawValue, "9")
        XCTAssertEqual(result.values[address("D2")]?.rawValue, "-9")
        XCTAssertEqual(result.values[address("D3")]?.rawValue, "6")
        XCTAssertEqual(result.values[address("D4")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("D5")]?.rawValue, "4")
        XCTAssertEqual(result.values[address("D6")]?.rawValue, "-4")
        XCTAssertEqual(result.values[address("D7")]?.rawValue, "3")
        XCTAssertEqual(result.values[address("D8")]?.rawValue, "-3")
    }

    func testFormulaCalculatorSupportsCombinatoricsAndIntegerMathFunctions() {
        let cells: [ExcelCellAddress: ExcelCell] = [
            address("A1"): formulaCell("A1", "FACT(5.9)", cached: "0"),
            address("A2"): formulaCell("A2", "FACTDOUBLE(7.9)", cached: "0"),
            address("A3"): formulaCell("A3", "COMBIN(8,2)", cached: "0"),
            address("A4"): formulaCell("A4", "COMBINA(3,2)", cached: "0"),
            address("A5"): formulaCell("A5", "PERMUT(10,3)", cached: "0"),
            address("A6"): formulaCell("A6", "PERMUTATIONA(3,2)", cached: "0"),
            address("A7"): formulaCell("A7", "COMBIN(2,3)", cached: "0"),
            address("A8"): formulaCell("A8", "PERMUT(0,0)", cached: "0"),
            address("B1"): formulaCell("B1", "GCD(24.9,36.8)", cached: "0"),
            address("B2"): formulaCell("B2", "LCM(24,36)", cached: "0"),
            address("B3"): formulaCell("B3", "GCD(J1:J4)", cached: "0"),
            address("B4"): formulaCell("B4", "LCM(J1:J4)", cached: "0"),
            address("B5"): formulaCell("B5", "GCD(-1,2)", cached: "0"),
            address("B6"): formulaCell(
                "B6", "GCD(9007199254740992)", cached: "0"
            ),
            address("B7"): formulaCell("B7", "SUMSQ(J1:J4,TRUE,\"3\")", cached: "0"),
            address("J1"): numericCell("J1", "24"),
            address("J2"): numericCell("J2", "36"),
            address("J3"): cell("J3", "제외"),
            address("J4"): booleanCell("J4", true),
        ]

        let result = ExcelFormulaCalculator.recalculate(
            cells: cells,
            styles: [.plain],
            uses1904DateSystem: false
        )

        XCTAssertEqual(result.unsupportedFormulaCount, 0)
        XCTAssertEqual(result.values[address("A1")]?.rawValue, "120")
        XCTAssertEqual(result.values[address("A2")]?.rawValue, "105")
        XCTAssertEqual(result.values[address("A3")]?.rawValue, "28")
        XCTAssertEqual(result.values[address("A4")]?.rawValue, "6")
        XCTAssertEqual(result.values[address("A5")]?.rawValue, "720")
        XCTAssertEqual(result.values[address("A6")]?.rawValue, "9")
        XCTAssertEqual(result.values[address("A7")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("A8")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("B1")]?.rawValue, "12")
        XCTAssertEqual(result.values[address("B2")]?.rawValue, "72")
        XCTAssertEqual(result.values[address("B3")]?.rawValue, "12")
        XCTAssertEqual(result.values[address("B4")]?.rawValue, "72")
        XCTAssertEqual(result.values[address("B5")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("B6")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("B7")]?.rawValue, "1882")
    }

    func testFormulaCalculatorSupportsHyperbolicAndReciprocalTrigFunctions() {
        let cells: [ExcelCellAddress: ExcelCell] = [
            address("A1"): formulaCell("A1", "SINH(0)", cached: "0"),
            address("A2"): formulaCell("A2", "COSH(0)", cached: "0"),
            address("A3"): formulaCell("A3", "TANH(0)", cached: "0"),
            address("A4"): formulaCell("A4", "ROUND(ASINH(SINH(1)),10)", cached: "0"),
            address("A5"): formulaCell("A5", "ROUND(ACOSH(COSH(1)),10)", cached: "0"),
            address("A6"): formulaCell("A6", "ROUND(ATANH(TANH(0.5)),10)", cached: "0"),
            address("B1"): formulaCell("B1", "ROUND(DEGREES(ACOT(0)),10)", cached: "0"),
            address("B2"): formulaCell("B2", "ROUND(DEGREES(ACOT(-1)),10)", cached: "0"),
            address("B3"): formulaCell("B3", "ROUND(COT(PI()/4),10)", cached: "0"),
            address("B4"): formulaCell("B4", "ROUND(CSC(PI()/2),10)", cached: "0"),
            address("B5"): formulaCell("B5", "SEC(0)", cached: "0"),
            address("B6"): formulaCell("B6", "ROUND(ACOTH(COTH(2)),10)", cached: "0"),
            address("B7"): formulaCell("B7", "ROUND(CSCH(ASINH(2)),10)", cached: "0"),
            address("B8"): formulaCell("B8", "ROUND(SECH(ACOSH(2)),10)", cached: "0"),
            address("B9"): formulaCell("B9", "ROUND(SQRTPI(1),10)", cached: "0"),
            address("C1"): formulaCell("C1", "ACOSH(0.5)", cached: "0"),
            address("C2"): formulaCell("C2", "ATANH(1)", cached: "0"),
            address("C3"): formulaCell("C3", "ACOTH(1)", cached: "0"),
            address("C4"): formulaCell("C4", "SQRTPI(-1)", cached: "0"),
            address("C5"): formulaCell("C5", "COT(0)", cached: "0"),
            address("C6"): formulaCell("C6", "CSC(0)", cached: "0"),
            address("C7"): formulaCell("C7", "COTH(0)", cached: "0"),
            address("C8"): formulaCell("C8", "CSCH(0)", cached: "0"),
            address("C9"): formulaCell("C9", "SEC(134217728)", cached: "0"),
            address("C10"): formulaCell("C10", "SINH(1000)", cached: "0"),
        ]

        let result = ExcelFormulaCalculator.recalculate(
            cells: cells,
            styles: [.plain],
            uses1904DateSystem: false
        )

        XCTAssertEqual(result.unsupportedFormulaCount, 0)
        XCTAssertEqual(result.values[address("A1")]?.rawValue, "0")
        XCTAssertEqual(result.values[address("A2")]?.rawValue, "1")
        XCTAssertEqual(result.values[address("A3")]?.rawValue, "0")
        XCTAssertEqual(result.values[address("A4")]?.rawValue, "1")
        XCTAssertEqual(result.values[address("A5")]?.rawValue, "1")
        XCTAssertEqual(result.values[address("A6")]?.rawValue, "0.5")
        XCTAssertEqual(result.values[address("B1")]?.rawValue, "90")
        XCTAssertEqual(result.values[address("B2")]?.rawValue, "135")
        XCTAssertEqual(result.values[address("B3")]?.rawValue, "1")
        XCTAssertEqual(result.values[address("B4")]?.rawValue, "1")
        XCTAssertEqual(result.values[address("B5")]?.rawValue, "1")
        XCTAssertEqual(result.values[address("B6")]?.rawValue, "2")
        XCTAssertEqual(result.values[address("B7")]?.rawValue, "0.5")
        XCTAssertEqual(result.values[address("B8")]?.rawValue, "0.5")
        XCTAssertEqual(result.values[address("B9")]?.rawValue, "1.7724538509")
        XCTAssertEqual(result.values[address("C1")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("C2")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("C3")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("C4")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("C5")]?.rawValue, "#DIV/0!")
        XCTAssertEqual(result.values[address("C6")]?.rawValue, "#DIV/0!")
        XCTAssertEqual(result.values[address("C7")]?.rawValue, "#DIV/0!")
        XCTAssertEqual(result.values[address("C8")]?.rawValue, "#DIV/0!")
        XCTAssertEqual(result.values[address("C9")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("C10")]?.rawValue, "#NUM!")
    }

    func testFormulaCalculatorSupportsDescriptiveAndSeriesFunctions() {
        let cells: [ExcelCellAddress: ExcelCell] = [
            address("A1"): formulaCell("A1", "ROUND(AVEDEV(J1:J5),10)", cached: "0"),
            address("A2"): formulaCell("A2", "ROUND(DEVSQ(J1:J5),10)", cached: "0"),
            address("A3"): formulaCell("A3", "GEOMEAN(J1:J5)", cached: "0"),
            address("A4"): formulaCell("A4", "ROUND(HARMEAN(J1:J5),10)", cached: "0"),
            address("A5"): formulaCell("A5", "GEOMEAN(J1:J6)", cached: "0"),
            address("A6"): formulaCell("A6", "HARMEAN(-1,2)", cached: "0"),
            address("A7"): formulaCell("A7", "AVEDEV(TRUE,\"3\")", cached: "0"),
            address("B1"): formulaCell("B1", "SUMX2MY2(J1:J3,L1:L3)", cached: "0"),
            address("B2"): formulaCell("B2", "SUMX2PY2(J1:J3,L1:L3)", cached: "0"),
            address("B3"): formulaCell("B3", "SUMXMY2(J1:J3,L1:L3)", cached: "0"),
            address("B4"): formulaCell("B4", "SUMXMY2(J1:J3,L1:L2)", cached: "0"),
            address("B5"): formulaCell("B5", "SERIESSUM(2,0,1,K1:K3)", cached: "0"),
            address("C1"): formulaCell("C1", "ROUND(FISHER(0.75),10)", cached: "0"),
            address("C2"): formulaCell("C2", "ROUND(FISHERINV(FISHER(0.75)),10)", cached: "0"),
            address("C3"): formulaCell("C3", "ROUND(STANDARDIZE(42,40,1.5),10)", cached: "0"),
            address("C4"): formulaCell("C4", "FISHER(1)", cached: "0"),
            address("C5"): formulaCell("C5", "STANDARDIZE(1,1,0)", cached: "0"),
            address("J1"): numericCell("J1", "2"),
            address("J2"): numericCell("J2", "4"),
            address("J3"): numericCell("J3", "8"),
            address("J4"): cell("J4", "제외"),
            address("J5"): booleanCell("J5", true),
            address("J6"): numericCell("J6", "0"),
            address("K1"): numericCell("K1", "1"),
            address("K2"): numericCell("K2", "2"),
            address("K3"): numericCell("K3", "3"),
            address("L1"): numericCell("L1", "6"),
            address("L2"): numericCell("L2", "5"),
            address("L3"): numericCell("L3", "11"),
        ]

        let result = ExcelFormulaCalculator.recalculate(
            cells: cells,
            styles: [.plain],
            uses1904DateSystem: false
        )

        XCTAssertEqual(result.unsupportedFormulaCount, 0)
        XCTAssertEqual(result.values[address("A1")]?.rawValue, "2.2222222222")
        XCTAssertEqual(result.values[address("A2")]?.rawValue, "18.6666666667")
        XCTAssertEqual(result.values[address("A3")]?.rawValue, "4")
        XCTAssertEqual(result.values[address("A4")]?.rawValue, "3.4285714286")
        XCTAssertEqual(result.values[address("A5")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("A6")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("A7")]?.rawValue, "1")
        XCTAssertEqual(result.values[address("B1")]?.rawValue, "-98")
        XCTAssertEqual(result.values[address("B2")]?.rawValue, "266")
        XCTAssertEqual(result.values[address("B3")]?.rawValue, "26")
        XCTAssertEqual(result.values[address("B4")]?.rawValue, "#N/A")
        XCTAssertEqual(result.values[address("B5")]?.rawValue, "17")
        XCTAssertEqual(result.values[address("C1")]?.rawValue, "0.9729550745")
        XCTAssertEqual(result.values[address("C2")]?.rawValue, "0.75")
        XCTAssertEqual(result.values[address("C3")]?.rawValue, "1.3333333333")
        XCTAssertEqual(result.values[address("C4")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("C5")]?.rawValue, "#NUM!")
    }

    func testFormulaCalculatorSupportsPairedStatisticalFunctions() {
        let cells: [ExcelCellAddress: ExcelCell] = [
            address("A1"): formulaCell("A1", "ROUND(CORREL(N1:N6,O1:O6),10)", cached: "0"),
            address("A2"): formulaCell("A2", "COVARIANCE.P(N1:N6,O1:O6)", cached: "0"),
            address("A3"): formulaCell("A3", "COVARIANCE.S(N1:N6,O1:O6)", cached: "0"),
            address("A4"): formulaCell("A4", "ROUND(PEARSON(N1:N6,O1:O6),10)", cached: "0"),
            address("A5"): formulaCell("A5", "ROUND(RSQ(O1:O6,N1:N6),10)", cached: "0"),
            address("B1"): formulaCell("B1", "ROUND(SLOPE(O1:O6,N1:N6),10)", cached: "0"),
            address("B2"): formulaCell("B2", "ROUND(INTERCEPT(O1:O6,N1:N6),10)", cached: "0"),
            address("B3"): formulaCell("B3", "ROUND(STEYX(O1:O6,N1:N6),10)", cached: "0"),
            address("B4"): formulaCell("B4", "CORREL(N1:N2,P1:P3)", cached: "0"),
            address("B5"): formulaCell("B5", "SLOPE(O1:O5,P1:P5)", cached: "0"),
            address("N1"): numericCell("N1", "1"),
            address("N2"): numericCell("N2", "2"),
            address("N3"): numericCell("N3", "3"),
            address("N4"): numericCell("N4", "4"),
            address("N5"): numericCell("N5", "5"),
            address("N6"): cell("N6", "제외"),
            address("O1"): numericCell("O1", "2"),
            address("O2"): numericCell("O2", "4"),
            address("O3"): numericCell("O3", "5"),
            address("O4"): numericCell("O4", "4"),
            address("O5"): numericCell("O5", "5"),
            address("O6"): numericCell("O6", "100"),
            address("P1"): numericCell("P1", "7"),
            address("P2"): numericCell("P2", "7"),
            address("P3"): numericCell("P3", "7"),
            address("P4"): numericCell("P4", "7"),
            address("P5"): numericCell("P5", "7"),
        ]

        let result = ExcelFormulaCalculator.recalculate(
            cells: cells,
            styles: [.plain],
            uses1904DateSystem: false
        )

        XCTAssertEqual(result.unsupportedFormulaCount, 0)
        XCTAssertEqual(result.values[address("A1")]?.rawValue, "0.7745966692")
        XCTAssertEqual(result.values[address("A2")]?.rawValue, "1.2")
        XCTAssertEqual(result.values[address("A3")]?.rawValue, "1.5")
        XCTAssertEqual(result.values[address("A4")]?.rawValue, "0.7745966692")
        XCTAssertEqual(result.values[address("A5")]?.rawValue, "0.6")
        XCTAssertEqual(result.values[address("B1")]?.rawValue, "0.6")
        XCTAssertEqual(result.values[address("B2")]?.rawValue, "2.2")
        XCTAssertEqual(result.values[address("B3")]?.rawValue, "0.894427191")
        XCTAssertEqual(result.values[address("B4")]?.rawValue, "#N/A")
        XCTAssertEqual(result.values[address("B5")]?.rawValue, "#DIV/0!")
    }

    func testFormulaCalculatorSupportsNumeralSystemAndEngineeringComparisons() {
        let cells: [ExcelCellAddress: ExcelCell] = [
            address("A1"): formulaCell("A1", "DEC2BIN(100)", cached: ""),
            address("A2"): formulaCell("A2", "DEC2BIN(4,6)", cached: ""),
            address("A3"): formulaCell("A3", "DEC2BIN(-1)", cached: ""),
            address("A4"): formulaCell("A4", "DEC2BIN(512)", cached: ""),
            address("A5"): formulaCell("A5", "DEC2BIN(5,2)", cached: ""),
            address("A6"): formulaCell("A6", "DEC2OCT(100)", cached: ""),
            address("A7"): formulaCell("A7", "DEC2OCT(-1)", cached: ""),
            address("A8"): formulaCell("A8", "DEC2HEX(165)", cached: ""),
            address("A9"): formulaCell("A9", "DEC2HEX(-165)", cached: ""),
            address("A10"): formulaCell("A10", "DEC2HEX(165,4)", cached: ""),
            address("B1"): formulaCell("B1", "BIN2DEC(1100100)", cached: "0"),
            address("B2"): formulaCell("B2", "BIN2DEC(1111111111)", cached: "0"),
            address("B3"): formulaCell("B3", "BIN2DEC(102)", cached: "0"),
            address("B4"): formulaCell("B4", "BIN2OCT(111)", cached: ""),
            address("B5"): formulaCell("B5", "BIN2HEX(11111111)", cached: ""),
            address("B6"): formulaCell("B6", "BIN2HEX(1111111111)", cached: ""),
            address("C1"): formulaCell("C1", "OCT2DEC(144)", cached: "0"),
            address("C2"): formulaCell("C2", "OCT2DEC(7777777777)", cached: "0"),
            address("C3"): formulaCell("C3", "OCT2DEC(128)", cached: "0"),
            address("C4"): formulaCell("C4", "OCT2BIN(7777777777)", cached: ""),
            address("C5"): formulaCell("C5", "OCT2HEX(7777777777)", cached: ""),
            address("D1"): formulaCell("D1", "HEX2DEC(\"A5\")", cached: "0"),
            address("D2"): formulaCell("D2", "HEX2DEC(\"FFFFFFFF5B\")", cached: "0"),
            address("D3"): formulaCell("D3", "HEX2BIN(\"1FF\")", cached: ""),
            address("D4"): formulaCell("D4", "HEX2BIN(\"200\")", cached: ""),
            address("D5"): formulaCell("D5", "HEX2OCT(\"1FFFFFFF\")", cached: ""),
            address("D6"): formulaCell("D6", "HEX2OCT(\"FFFFFFFFFF\")", cached: ""),
            address("E1"): formulaCell("E1", "BASE(31,16,4)", cached: ""),
            address("E2"): formulaCell("E2", "DECIMAL(\"FF\",16)", cached: "0"),
            address("E3"): formulaCell("E3", "DECIMAL(\"2\",2)", cached: "0"),
            address("E4"): formulaCell("E4", "DELTA(5,5)", cached: "0"),
            address("E5"): formulaCell("E5", "DELTA(5)", cached: "0"),
            address("E6"): formulaCell("E6", "GESTEP(5,4)", cached: "0"),
            address("E7"): formulaCell("E7", "GESTEP(3,4)", cached: "0"),
            address("E8"): formulaCell("E8", "GESTEP(-1)", cached: "0"),
        ]

        let result = ExcelFormulaCalculator.recalculate(
            cells: cells,
            styles: [.plain],
            uses1904DateSystem: false
        )

        XCTAssertEqual(result.unsupportedFormulaCount, 0)
        XCTAssertEqual(result.values[address("A1")]?.rawValue, "1100100")
        XCTAssertEqual(result.values[address("A2")]?.rawValue, "000100")
        XCTAssertEqual(result.values[address("A3")]?.rawValue, "1111111111")
        XCTAssertEqual(result.values[address("A4")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("A5")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("A6")]?.rawValue, "144")
        XCTAssertEqual(result.values[address("A7")]?.rawValue, "7777777777")
        XCTAssertEqual(result.values[address("A8")]?.rawValue, "A5")
        XCTAssertEqual(result.values[address("A9")]?.rawValue, "FFFFFFFF5B")
        XCTAssertEqual(result.values[address("A10")]?.rawValue, "00A5")
        XCTAssertEqual(result.values[address("B1")]?.rawValue, "100")
        XCTAssertEqual(result.values[address("B2")]?.rawValue, "-1")
        XCTAssertEqual(result.values[address("B3")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("B4")]?.rawValue, "7")
        XCTAssertEqual(result.values[address("B5")]?.rawValue, "FF")
        XCTAssertEqual(result.values[address("B6")]?.rawValue, "FFFFFFFFFF")
        XCTAssertEqual(result.values[address("C1")]?.rawValue, "100")
        XCTAssertEqual(result.values[address("C2")]?.rawValue, "-1")
        XCTAssertEqual(result.values[address("C3")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("C4")]?.rawValue, "1111111111")
        XCTAssertEqual(result.values[address("C5")]?.rawValue, "FFFFFFFFFF")
        XCTAssertEqual(result.values[address("D1")]?.rawValue, "165")
        XCTAssertEqual(result.values[address("D2")]?.rawValue, "-165")
        XCTAssertEqual(result.values[address("D3")]?.rawValue, "111111111")
        XCTAssertEqual(result.values[address("D4")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("D5")]?.rawValue, "3777777777")
        XCTAssertEqual(result.values[address("D6")]?.rawValue, "7777777777")
        XCTAssertEqual(result.values[address("E1")]?.rawValue, "001F")
        XCTAssertEqual(result.values[address("E2")]?.rawValue, "255")
        XCTAssertEqual(result.values[address("E3")]?.rawValue, "#NUM!")
        XCTAssertEqual(result.values[address("E4")]?.rawValue, "1")
        XCTAssertEqual(result.values[address("E5")]?.rawValue, "0")
        XCTAssertEqual(result.values[address("E6")]?.rawValue, "1")
        XCTAssertEqual(result.values[address("E7")]?.rawValue, "0")
        XCTAssertEqual(result.values[address("E8")]?.rawValue, "0")
    }

    func testFormulaCalculatorSupportsLogicalBranchingAndReferenceFunctions() {
        let cells: [ExcelCellAddress: ExcelCell] = [
            address("A1"): formulaCell(
                "A1", "IFS(FALSE,1,2>1,\"yes\",TRUE,1/0)", cached: ""
            ),
            address("A2"): formulaCell(
                "A2", "IFS(FALSE,1,FALSE,2)", cached: ""
            ),
            address("A3"): formulaCell("A3", "IFS(\"bad\",10)", cached: ""),
            address("A4"): formulaCell(
                "A4", "SWITCH(\"b\",\"a\",1,\"B\",2,3)", cached: "0"
            ),
            address("A5"): formulaCell(
                "A5", "SWITCH(9,1,\"one\",2,\"two\",\"other\")", cached: ""
            ),
            address("A6"): formulaCell(
                "A6", "SWITCH(9,1,\"one\",2,\"two\")", cached: ""
            ),
            address("B1"): formulaCell(
                "B1", "CHOOSE(2,1/0,\"picked\",3)", cached: ""
            ),
            address("B2"): formulaCell(
                "B2", "CHOOSE(2.9,\"a\",\"b\",\"c\")", cached: ""
            ),
            address("B3"): formulaCell("B3", "CHOOSE(0,\"a\")", cached: ""),
            address("B4"): formulaCell(
                "B4", "XOR(TRUE,FALSE,TRUE)", cached: "0"
            ),
            address("B5"): formulaCell(
                "B5", "XOR(TRUE,FALSE,FALSE)", cached: "0"
            ),
            address("B6"): formulaCell("B6", "TRUE()", cached: "0"),
            address("B7"): formulaCell("B7", "FALSE()", cached: "1"),
            address("C1"): formulaCell("C1", "ROW(J5:L7)", cached: "0"),
            address("C2"): formulaCell("C2", "COLUMN(J5:L7)", cached: "0"),
            address("C3"): formulaCell("C3", "ROWS(J5:L7)", cached: "0"),
            address("C4"): formulaCell("C4", "COLUMNS(J5:L7)", cached: "0"),
            address("C5"): formulaCell("C5", "ROWS(99)", cached: "0"),
            address("C6"): formulaCell("C6", "ROW()", cached: "0"),
            address("D1"): formulaCell("D1", "ADDRESS(2,3)", cached: ""),
            address("D2"): formulaCell("D2", "ADDRESS(2,3,4)", cached: ""),
            address("D3"): formulaCell(
                "D3", "ADDRESS(2,3,2,FALSE)", cached: ""
            ),
            address("D4"): formulaCell(
                "D4", "ADDRESS(2,3,1,TRUE,\"Sheet 1\")", cached: ""
            ),
            address("D5"): formulaCell("D5", "ADDRESS(2,3,,)", cached: ""),
            address("D6"): formulaCell("D6", "COLUMN()", cached: "0"),
            address("E1"): formulaCell("E1", "FORMULATEXT(J5)", cached: ""),
            address("E2"): formulaCell("E2", "ISFORMULA(J5)", cached: "0"),
            address("E3"): formulaCell("E3", "ISFORMULA(J6)", cached: "1"),
            address("E4"): formulaCell("E4", "FORMULATEXT(J6)", cached: ""),
            address("J5"): formulaCell("J5", "SUM(1,2)", cached: "0"),
            address("J6"): numericCell("J6", "42"),
        ]

        let result = ExcelFormulaCalculator.recalculate(
            cells: cells,
            styles: [.plain],
            uses1904DateSystem: false
        )

        XCTAssertEqual(result.unsupportedFormulaCount, 0)
        XCTAssertEqual(result.values[address("A1")]?.rawValue, "yes")
        XCTAssertEqual(result.values[address("A2")]?.rawValue, "#N/A")
        XCTAssertEqual(result.values[address("A3")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("A4")]?.rawValue, "2")
        XCTAssertEqual(result.values[address("A5")]?.rawValue, "other")
        XCTAssertEqual(result.values[address("A6")]?.rawValue, "#N/A")
        XCTAssertEqual(result.values[address("B1")]?.rawValue, "picked")
        XCTAssertEqual(result.values[address("B2")]?.rawValue, "b")
        XCTAssertEqual(result.values[address("B3")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("B4")]?.rawValue, "FALSE")
        XCTAssertEqual(result.values[address("B5")]?.rawValue, "TRUE")
        XCTAssertEqual(result.values[address("B6")]?.rawValue, "TRUE")
        XCTAssertEqual(result.values[address("B7")]?.rawValue, "FALSE")
        XCTAssertEqual(result.values[address("C1")]?.rawValue, "5")
        XCTAssertEqual(result.values[address("C2")]?.rawValue, "10")
        XCTAssertEqual(result.values[address("C3")]?.rawValue, "3")
        XCTAssertEqual(result.values[address("C4")]?.rawValue, "3")
        XCTAssertEqual(result.values[address("C5")]?.rawValue, "1")
        XCTAssertEqual(result.values[address("C6")]?.rawValue, "6")
        XCTAssertEqual(result.values[address("D1")]?.rawValue, "$C$2")
        XCTAssertEqual(result.values[address("D2")]?.rawValue, "C2")
        XCTAssertEqual(result.values[address("D3")]?.rawValue, "R2C[3]")
        XCTAssertEqual(
            result.values[address("D4")]?.rawValue,
            "'Sheet 1'!$C$2"
        )
        XCTAssertEqual(result.values[address("D5")]?.rawValue, "$C$2")
        XCTAssertEqual(result.values[address("D6")]?.rawValue, "4")
        XCTAssertEqual(result.values[address("E1")]?.rawValue, "=SUM(1,2)")
        XCTAssertEqual(result.values[address("E2")]?.rawValue, "TRUE")
        XCTAssertEqual(result.values[address("E3")]?.rawValue, "FALSE")
        XCTAssertEqual(result.values[address("E4")]?.rawValue, "#N/A")
    }

    func testFormulaCalculatorSupportsAdditionalTextAndValueFunctions() {
        let cells: [ExcelCellAddress: ExcelCell] = [
            address("A1"): formulaCell("A1", "REPT(\"*-\",3)", cached: ""),
            address("A2"): formulaCell("A2", "REPT(\"x\",2.9)", cached: ""),
            address("A3"): formulaCell("A3", "REPT(\"x\",0)", cached: ""),
            address("A4"): formulaCell("A4", "REPT(\"x\",-1)", cached: ""),
            address("A5"): formulaCell("A5", "T(\"hello\")", cached: ""),
            address("A6"): formulaCell("A6", "T(42)", cached: "x"),
            address("A7"): formulaCell("A7", "T(TRUE)", cached: "x"),
            address("A8"): formulaCell("A8", "T(#N/A)", cached: ""),
            address("B1"): formulaCell("B1", "FIXED(1234.567,1)", cached: ""),
            address("B2"): formulaCell("B2", "FIXED(1234.567,-1)", cached: ""),
            address("B3"): formulaCell(
                "B3", "FIXED(-1234.567,-1,TRUE)", cached: ""
            ),
            address("B4"): formulaCell("B4", "FIXED(44.332)", cached: ""),
            address("B5"): formulaCell("B5", "DOLLAR(1234.567,2)", cached: ""),
            address("B6"): formulaCell(
                "B6", "DOLLAR(-1234.567,2)", cached: ""
            ),
            address("B7"): formulaCell("B7", "DOLLAR(1234.567,-1)", cached: ""),
            address("C1"): formulaCell(
                "C1", "NUMBERVALUE(\"2.500,27\",\",\",\".\")", cached: "0"
            ),
            address("C2"): formulaCell(
                "C2", "NUMBERVALUE(\"3.5%\",\".\",\",\")", cached: "0"
            ),
            address("C3"): formulaCell(
                "C3", "NUMBERVALUE(\"9%%\",\".\",\",\")", cached: "0"
            ),
            address("C4"): formulaCell(
                "C4", "NUMBERVALUE(\" 3 000 \",\".\",\",\")", cached: "0"
            ),
            address("C5"): formulaCell(
                "C5", "NUMBERVALUE(\"1.2.3\",\".\",\",\")", cached: "0"
            ),
            address("C6"): formulaCell(
                "C6", "NUMBERVALUE(\"1.2,3\",\".\",\",\")", cached: "0"
            ),
            address("C7"): formulaCell(
                "C7", "NUMBERVALUE(\"\",\".\",\",\")", cached: "0"
            ),
            address("C8"): formulaCell(
                "C8", "NUMBERVALUE(\"1\",#N/A,\",\")", cached: "0"
            ),
            address("C9"): formulaCell(
                "C9", "NUMBERVALUE(\"1\",\".\",#REF!)", cached: "0"
            ),
            address("D1"): formulaCell(
                "D1", "CONCATENATE(\"Hello\",\" \",42,TRUE)", cached: ""
            ),
            address("D2"): formulaCell("D2", "CONCATENATE(J1:J2)", cached: ""),
            address("J1"): cell("J1", "a"),
            address("J2"): cell("J2", "b"),
        ]

        let result = ExcelFormulaCalculator.recalculate(
            cells: cells,
            styles: [.plain],
            uses1904DateSystem: false
        )

        XCTAssertEqual(result.unsupportedFormulaCount, 0)
        XCTAssertEqual(result.values[address("A1")]?.rawValue, "*-*-*-")
        XCTAssertEqual(result.values[address("A2")]?.rawValue, "xx")
        XCTAssertEqual(result.values[address("A3")]?.rawValue, "")
        XCTAssertEqual(result.values[address("A4")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("A5")]?.rawValue, "hello")
        XCTAssertEqual(result.values[address("A6")]?.rawValue, "")
        XCTAssertEqual(result.values[address("A7")]?.rawValue, "")
        XCTAssertEqual(result.values[address("A8")]?.rawValue, "#N/A")
        XCTAssertEqual(result.values[address("B1")]?.rawValue, "1,234.6")
        XCTAssertEqual(result.values[address("B2")]?.rawValue, "1,230")
        XCTAssertEqual(result.values[address("B3")]?.rawValue, "-1230")
        XCTAssertEqual(result.values[address("B4")]?.rawValue, "44.33")
        XCTAssertEqual(result.values[address("B5")]?.rawValue, "$1,234.57")
        XCTAssertEqual(result.values[address("B6")]?.rawValue, "($1,234.57)")
        XCTAssertEqual(result.values[address("B7")]?.rawValue, "$1,230")
        XCTAssertEqual(result.values[address("C1")]?.rawValue, "2500.27")
        XCTAssertEqual(result.values[address("C2")]?.rawValue, "0.035")
        XCTAssertEqual(result.values[address("C3")]?.rawValue, "0.0009")
        XCTAssertEqual(result.values[address("C4")]?.rawValue, "3000")
        XCTAssertEqual(result.values[address("C5")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("C6")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("C7")]?.rawValue, "0")
        XCTAssertEqual(result.values[address("C8")]?.rawValue, "#N/A")
        XCTAssertEqual(result.values[address("C9")]?.rawValue, "#REF!")
        XCTAssertEqual(
            result.values[address("D1")]?.rawValue,
            "Hello 42TRUE"
        )
        XCTAssertEqual(result.values[address("D2")]?.rawValue, "#VALUE!")
    }

    func testFormulaCalculatorSupportsCoreFinancialFunctions() {
        let cells: [ExcelCellAddress: ExcelCell] = [
            address("A1"): formulaCell(
                "A1", "ROUND(PV(0.08/12,12*20,500,,0),2)", cached: "0"
            ),
            address("A2"): formulaCell(
                "A2", "ROUND(FV(0.06/12,10,-200,-500,1),2)", cached: "0"
            ),
            address("A3"): formulaCell(
                "A3", "ROUND(PMT(0.08/12,10,10000),2)", cached: "0"
            ),
            address("A4"): formulaCell(
                "A4", "ROUND(PMT(0.08/12,10,10000,,1),2)", cached: "0"
            ),
            address("A5"): formulaCell(
                "A5", "ROUND(NPER(0.03/12,-150,2500),2)", cached: "0"
            ),
            address("B1"): formulaCell("B1", "PV(0,10,-100)", cached: "0"),
            address("B2"): formulaCell(
                "B2", "FV(0,10,-100,-500)", cached: "0"
            ),
            address("B3"): formulaCell("B3", "PMT(0,10,1000)", cached: "0"),
            address("B4"): formulaCell("B4", "NPER(0,-100,1000)", cached: "0"),
            address("B5"): formulaCell("B5", "PMT(0,0,1000)", cached: "0"),
            address("B6"): formulaCell(
                "B6", "PMT(0.1,10,1000,,2)", cached: "0"
            ),
            address("C1"): formulaCell(
                "C1", "ROUND(NPV(0.1,J1:J4),2)", cached: "0"
            ),
            address("C2"): formulaCell(
                "C2", "NPV(0,\"10\",TRUE)", cached: "0"
            ),
            address("C3"): formulaCell("C3", "NPV(0,J5:J7)", cached: "0"),
            address("C4"): formulaCell("C4", "NPV(-1,100)", cached: "0"),
            address("C5"): formulaCell("C5", "NPV(0.1,#N/A)", cached: "0"),
            address("J1"): numericCell("J1", "-10000"),
            address("J2"): numericCell("J2", "3000"),
            address("J3"): numericCell("J3", "4200"),
            address("J4"): numericCell("J4", "6800"),
            address("J5"): cell("J5", "10"),
            address("J6"): booleanCell("J6", true),
            address("J7"): cell("J7", ""),
        ]

        let result = ExcelFormulaCalculator.recalculate(
            cells: cells,
            styles: [.plain],
            uses1904DateSystem: false
        )

        XCTAssertEqual(result.unsupportedFormulaCount, 0)
        XCTAssertEqual(result.values[address("A1")]?.rawValue, "-59777.15")
        XCTAssertEqual(result.values[address("A2")]?.rawValue, "2581.4")
        XCTAssertEqual(result.values[address("A3")]?.rawValue, "-1037.03")
        XCTAssertEqual(result.values[address("A4")]?.rawValue, "-1030.16")
        XCTAssertEqual(result.values[address("A5")]?.rawValue, "17.05")
        XCTAssertEqual(result.values[address("B1")]?.rawValue, "1000")
        XCTAssertEqual(result.values[address("B2")]?.rawValue, "1500")
        XCTAssertEqual(result.values[address("B3")]?.rawValue, "-100")
        XCTAssertEqual(result.values[address("B4")]?.rawValue, "10")
        XCTAssertEqual(result.values[address("B5")]?.rawValue, "#DIV/0!")
        XCTAssertEqual(result.values[address("B6")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("C1")]?.rawValue, "1188.44")
        XCTAssertEqual(result.values[address("C2")]?.rawValue, "11")
        XCTAssertEqual(result.values[address("C3")]?.rawValue, "0")
        XCTAssertEqual(result.values[address("C4")]?.rawValue, "#DIV/0!")
        XCTAssertEqual(result.values[address("C5")]?.rawValue, "#N/A")
    }

    func testFormulaCalculatorSupportsLookupFunctions() {
        let cells: [ExcelCellAddress: ExcelCell] = [
            address("A2"): numericCell("A2", "10"),
            address("A3"): numericCell("A3", "20"),
            address("A4"): numericCell("A4", "30"),
            address("A5"): numericCell("A5", "30"),
            address("A6"): numericCell("A6", "40"),
            address("B2"): cell("B2", "민지"),
            address("B3"): cell("B3", "준호"),
            address("B4"): cell("B4", "서연"),
            address("B5"): cell("B5", "중복"),
            address("B6"): errorCell("B6", "#REF!"),
            address("C2"): numericCell("C2", "70"),
            address("C3"): numericCell("C3", "80"),
            address("C4"): numericCell("C4", "90"),
            address("C5"): numericCell("C5", "95"),
            address("C6"): numericCell("C6", "100"),
            address("D1"): formulaCell(
                "D1",
                "VLOOKUP(20,A2:C6,2,FALSE)",
                cached: ""
            ),
            address("D2"): formulaCell(
                "D2",
                "VLOOKUP(25,A2:C6,3,TRUE)",
                cached: "0"
            ),
            address("D3"): formulaCell(
                "D3",
                "VLOOKUP(5,A2:C6,2,TRUE)",
                cached: ""
            ),
            address("D4"): formulaCell(
                "D4",
                "VLOOKUP(20,A2:C6,4,FALSE)",
                cached: ""
            ),
            address("D5"): formulaCell(
                "D5",
                "VLOOKUP(20,A2:C6,0,FALSE)",
                cached: ""
            ),
            address("D6"): formulaCell(
                "D6",
                "VLOOKUP(\"서*\",B2:C6,2,FALSE)",
                cached: "0"
            ),
            address("D7"): formulaCell(
                "D7",
                "VLOOKUP(40,A2:C6,2,FALSE)",
                cached: ""
            ),
            address("E1"): formulaCell(
                "E1",
                "MATCH(30,A2:A6,0)",
                cached: "0"
            ),
            address("E2"): formulaCell(
                "E2",
                "MATCH(25,A2:A6,1)",
                cached: "0"
            ),
            address("E3"): formulaCell(
                "E3",
                "MATCH(\"서*\",B2:B6,0)",
                cached: "0"
            ),
            address("E4"): formulaCell(
                "E4",
                "INDEX(A2:C6,2,2)",
                cached: ""
            ),
            address("E5"): formulaCell(
                "E5",
                "INDEX(B2:B6,MATCH(30,A2:A6,0))",
                cached: ""
            ),
            address("E6"): formulaCell(
                "E6",
                "MATCH(99,A2:A6,0)",
                cached: ""
            ),
            address("E7"): formulaCell(
                "E7",
                "INDEX(A2:C6,9,2)",
                cached: ""
            ),
            address("F1"): formulaCell(
                "F1",
                "XLOOKUP(20,A2:A6,B2:B6)",
                cached: ""
            ),
            address("F2"): formulaCell(
                "F2",
                "XLOOKUP(25,A2:A6,B2:B6,\"없음\")",
                cached: ""
            ),
            address("F3"): formulaCell(
                "F3",
                "XLOOKUP(25,A2:A6,C2:C6,\"없음\",-1)",
                cached: "0"
            ),
            address("F4"): formulaCell(
                "F4",
                "XLOOKUP(25,A2:A6,C2:C6,\"없음\",1)",
                cached: "0"
            ),
            address("F5"): formulaCell(
                "F5",
                "XLOOKUP(30,A2:A6,B2:B6,\"없음\",0,-1)",
                cached: ""
            ),
            address("F6"): formulaCell(
                "F6",
                "XLOOKUP(\"서*\",B2:B6,C2:C6,\"없음\",2)",
                cached: "0"
            ),
            address("F7"): formulaCell(
                "F7",
                "XLOOKUP(20,A2:A6,B2:B5,\"없음\")",
                cached: ""
            ),
            address("F8"): formulaCell(
                "F8",
                "XLOOKUP(20,A2:A6,B2:B6,1/0)",
                cached: ""
            ),
            address("J2"): numericCell("J2", "40"),
            address("J3"): numericCell("J3", "30"),
            address("J4"): numericCell("J4", "20"),
            address("J5"): numericCell("J5", "10"),
            address("K2"): numericCell("K2", "400"),
            address("K3"): numericCell("K3", "300"),
            address("K4"): numericCell("K4", "200"),
            address("K5"): numericCell("K5", "100"),
            address("G1"): formulaCell(
                "G1",
                "MATCH(25,J2:J5,-1)",
                cached: "0"
            ),
            address("G2"): formulaCell(
                "G2",
                "XLOOKUP(25,J2:J5,K2:K5,\"없음\",1,-2)",
                cached: "0"
            ),
        ]

        let result = ExcelFormulaCalculator.recalculate(
            cells: cells,
            styles: [.plain],
            uses1904DateSystem: false
        )

        XCTAssertEqual(result.unsupportedFormulaCount, 0)
        XCTAssertEqual(result.values[address("D1")]?.rawValue, "준호")
        XCTAssertEqual(result.values[address("D2")]?.rawValue, "80")
        XCTAssertEqual(result.values[address("D3")]?.rawValue, "#N/A")
        XCTAssertEqual(result.values[address("D4")]?.rawValue, "#REF!")
        XCTAssertEqual(result.values[address("D5")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("D6")]?.rawValue, "90")
        XCTAssertEqual(result.values[address("D7")]?.rawValue, "#REF!")
        XCTAssertEqual(result.values[address("E1")]?.rawValue, "3")
        XCTAssertEqual(result.values[address("E2")]?.rawValue, "2")
        XCTAssertEqual(result.values[address("E3")]?.rawValue, "3")
        XCTAssertEqual(result.values[address("E4")]?.rawValue, "준호")
        XCTAssertEqual(result.values[address("E5")]?.rawValue, "서연")
        XCTAssertEqual(result.values[address("E6")]?.rawValue, "#N/A")
        XCTAssertEqual(result.values[address("E7")]?.rawValue, "#REF!")
        XCTAssertEqual(result.values[address("F1")]?.rawValue, "준호")
        XCTAssertEqual(result.values[address("F2")]?.rawValue, "없음")
        XCTAssertEqual(result.values[address("F3")]?.rawValue, "80")
        XCTAssertEqual(result.values[address("F4")]?.rawValue, "90")
        XCTAssertEqual(result.values[address("F5")]?.rawValue, "중복")
        XCTAssertEqual(result.values[address("F6")]?.rawValue, "90")
        XCTAssertEqual(result.values[address("F7")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("F8")]?.rawValue, "준호")
        XCTAssertEqual(result.values[address("G1")]?.rawValue, "2")
        XCTAssertEqual(result.values[address("G2")]?.rawValue, "300")
    }

    func testFormulaCalculatorSupportsConditionalAggregationAndIfError() {
        let cells: [ExcelCellAddress: ExcelCell] = [
            address("A1"): cell("A1", "급식"),
            address("A2"): cell("A2", "교통"),
            address("A3"): cell("A3", "급식"),
            address("A4"): cell("A4", "준비물"),
            address("A5"): cell("A5", "급식"),
            address("A7"): cell("A7", "*"),
            address("B1"): numericCell("B1", "100"),
            address("B2"): numericCell("B2", "200"),
            address("B3"): numericCell("B3", "150"),
            address("B4"): numericCell("B4", "300"),
            address("B5"): numericCell("B5", "50"),
            address("B6"): errorCell("B6", "#VALUE!"),
            address("B7"): numericCell("B7", "25"),
            address("C1"): cell("C1", "완료"),
            address("C2"): cell("C2", "완료"),
            address("C3"): cell("C3", "예정"),
            address("C4"): cell("C4", "완료"),
            address("C5"): cell("C5", "완료"),
            address("C6"): cell("C6", "완료"),
            address("C7"): cell("C7", "완료"),
            address("E1"): formulaCell(
                "E1", "COUNTIF(A1:A7,\"급식\")", cached: "0"
            ),
            address("E2"): formulaCell(
                "E2", "COUNTIF(A1:A7,\"급*\")", cached: "0"
            ),
            address("E3"): formulaCell(
                "E3", "COUNTIF(B1:B5,\">=150\")", cached: "0"
            ),
            address("E4"): formulaCell(
                "E4", "COUNTIF(A1:A7,\"\")", cached: "0"
            ),
            address("E5"): formulaCell(
                "E5", "COUNTIF(A1:A7,\"<>\")", cached: "0"
            ),
            address("E6"): formulaCell(
                "E6",
                "COUNTIFS(A1:A7,\"급식\",C1:C7,\"완료\")",
                cached: "0"
            ),
            address("E7"): formulaCell(
                "E7",
                "COUNTIFS(B1:B5,\">=100\",B1:B5,\"<200\")",
                cached: "0"
            ),
            address("E8"): formulaCell(
                "E8", "COUNTIF(A1:A7,\"준?물\")", cached: "0"
            ),
            address("E9"): formulaCell(
                "E9", "COUNTIF(A1:A7,\"~*\")", cached: "0"
            ),
            address("E10"): formulaCell(
                "E10",
                "COUNTIFS(A1:A7,\"급식\",C1:C6,\"완료\")",
                cached: "0"
            ),
            address("F1"): formulaCell(
                "F1", "SUMIF(A1:A7,\"급식\",B1:B7)", cached: "0"
            ),
            address("F2"): formulaCell(
                "F2", "SUMIF(B1:B5,\">=150\")", cached: "0"
            ),
            address("F3"): formulaCell(
                "F3",
                "SUMIFS(B1:B7,A1:A7,\"급식\",C1:C7,\"완료\")",
                cached: "0"
            ),
            address("F4"): formulaCell(
                "F4",
                "SUMIFS(B1:B5,B1:B5,\">100\",B1:B5,\"<300\")",
                cached: "0"
            ),
            address("F5"): formulaCell(
                "F5", "IFERROR(1/0,\"대체\")", cached: ""
            ),
            address("F6"): formulaCell(
                "F6",
                "IFERROR(VLOOKUP(99,B1:C5,2,FALSE),\"없음\")",
                cached: ""
            ),
            address("F7"): formulaCell(
                "F7", "IFERROR(42,1/0)", cached: "0"
            ),
            address("F8"): formulaCell(
                "F8", "SUMIF(A1:A7,\"\",B1:B7)", cached: "0"
            ),
            address("F9"): formulaCell(
                "F9",
                "SUMIFS(B1:B7,A1:A7,\"급식\",C1:C6,\"완료\")",
                cached: "0"
            ),
            address("F10"): formulaCell(
                "F10", "COUNTIF(B1:B5,\">\"&B1)", cached: "0"
            ),
            address("G1"): formulaCell(
                "G1", "SUMIF(A1:A3,\"급식\",B1:B1)", cached: "0"
            ),
        ]

        let result = ExcelFormulaCalculator.recalculate(
            cells: cells,
            styles: [.plain],
            uses1904DateSystem: false
        )

        XCTAssertEqual(result.unsupportedFormulaCount, 0)
        XCTAssertEqual(result.values[address("E1")]?.rawValue, "3")
        XCTAssertEqual(result.values[address("E2")]?.rawValue, "3")
        XCTAssertEqual(result.values[address("E3")]?.rawValue, "3")
        XCTAssertEqual(result.values[address("E4")]?.rawValue, "1")
        XCTAssertEqual(result.values[address("E5")]?.rawValue, "6")
        XCTAssertEqual(result.values[address("E6")]?.rawValue, "2")
        XCTAssertEqual(result.values[address("E7")]?.rawValue, "2")
        XCTAssertEqual(result.values[address("E8")]?.rawValue, "1")
        XCTAssertEqual(result.values[address("E9")]?.rawValue, "1")
        XCTAssertEqual(result.values[address("E10")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("F1")]?.rawValue, "300")
        XCTAssertEqual(result.values[address("F2")]?.rawValue, "650")
        XCTAssertEqual(result.values[address("F3")]?.rawValue, "150")
        XCTAssertEqual(result.values[address("F4")]?.rawValue, "350")
        XCTAssertEqual(result.values[address("F5")]?.rawValue, "대체")
        XCTAssertEqual(result.values[address("F6")]?.rawValue, "없음")
        XCTAssertEqual(result.values[address("F7")]?.rawValue, "42")
        XCTAssertEqual(result.values[address("F8")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("F9")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("F10")]?.rawValue, "3")
        XCTAssertEqual(result.values[address("G1")]?.rawValue, "250")
    }

    func testFormulaCalculatorSupportsHorizontalLookupExtendedMatchAndIfNA() {
        let cells: [ExcelCellAddress: ExcelCell] = [
            address("A1"): numericCell("A1", "10"),
            address("B1"): numericCell("B1", "20"),
            address("C1"): numericCell("C1", "30"),
            address("D1"): numericCell("D1", "30"),
            address("E1"): numericCell("E1", "40"),
            address("A2"): cell("A2", "민지"),
            address("B2"): cell("B2", "준호"),
            address("C2"): cell("C2", "서연"),
            address("D2"): cell("D2", "중복"),
            address("E2"): errorCell("E2", "#REF!"),
            address("A3"): numericCell("A3", "70"),
            address("B3"): numericCell("B3", "80"),
            address("C3"): numericCell("C3", "90"),
            address("D3"): numericCell("D3", "95"),
            address("E3"): numericCell("E3", "100"),
            address("A5"): cell("A5", "김"),
            address("B5"): cell("B5", "박"),
            address("C5"): cell("C5", "서연"),
            address("D5"): cell("D5", "서준"),
            address("E5"): cell("E5", "*"),
            address("A6"): numericCell("A6", "1"),
            address("B6"): numericCell("B6", "2"),
            address("C6"): numericCell("C6", "3"),
            address("D6"): numericCell("D6", "4"),
            address("E6"): numericCell("E6", "5"),
            address("G1"): formulaCell(
                "G1", "HLOOKUP(20,A1:E3,2,FALSE)", cached: ""
            ),
            address("G2"): formulaCell(
                "G2", "HLOOKUP(25,A1:E3,3,TRUE)", cached: "0"
            ),
            address("G3"): formulaCell(
                "G3", "HLOOKUP(5,A1:E3,2,TRUE)", cached: ""
            ),
            address("G4"): formulaCell(
                "G4", "HLOOKUP(20,A1:E3,4,FALSE)", cached: ""
            ),
            address("G5"): formulaCell(
                "G5", "HLOOKUP(20,A1:E3,0,FALSE)", cached: ""
            ),
            address("G6"): formulaCell(
                "G6", "HLOOKUP(\"서*\",A5:E6,2,FALSE)", cached: "0"
            ),
            address("G7"): formulaCell(
                "G7", "HLOOKUP(\"~*\",A5:E6,2,FALSE)", cached: "0"
            ),
            address("H1"): formulaCell(
                "H1", "XMATCH(30,A1:E1)", cached: "0"
            ),
            address("H2"): formulaCell(
                "H2", "XMATCH(30,A1:E1,0,-1)", cached: "0"
            ),
            address("H3"): formulaCell(
                "H3", "XMATCH(25,A1:E1,-1)", cached: "0"
            ),
            address("H4"): formulaCell(
                "H4", "XMATCH(25,A1:E1,1)", cached: "0"
            ),
            address("H5"): formulaCell(
                "H5", "XMATCH(\"서*\",A5:E5,2)", cached: "0"
            ),
            address("H6"): formulaCell(
                "H6", "XMATCH(99,A1:E1)", cached: "0"
            ),
            address("H7"): formulaCell(
                "H7", "XMATCH(20,A1:E1,3)", cached: "0"
            ),
            address("H8"): formulaCell(
                "H8", "XMATCH(20,A1:E1,0,0)", cached: "0"
            ),
            address("H9"): formulaCell(
                "H9", "XMATCH(30,A1:E1,0,2)", cached: "0"
            ),
            address("H10"): formulaCell(
                "H10", "XMATCH(25,A1:E1,-1,2)", cached: "0"
            ),
            address("I1"): formulaCell(
                "I1", "IFNA(XMATCH(99,A1:E1),\"없음\")", cached: ""
            ),
            address("I2"): formulaCell(
                "I2", "IFNA(1/0,\"대체\")", cached: ""
            ),
            address("I3"): formulaCell(
                "I3", "IFNA(42,1/0)", cached: "0"
            ),
            address("I4"): formulaCell(
                "I4",
                "IFNA(HLOOKUP(99,A1:E3,2,FALSE),\"없음\")",
                cached: ""
            ),
            address("J1"): numericCell("J1", "50"),
            address("J2"): numericCell("J2", "40"),
            address("J3"): numericCell("J3", "30"),
            address("J4"): numericCell("J4", "20"),
            address("J5"): numericCell("J5", "10"),
            address("I5"): formulaCell(
                "I5", "XMATCH(25,J1:J5,1,-2)", cached: "0"
            ),
        ]

        let result = ExcelFormulaCalculator.recalculate(
            cells: cells,
            styles: [.plain],
            uses1904DateSystem: false
        )

        XCTAssertEqual(result.unsupportedFormulaCount, 0)
        XCTAssertEqual(result.values[address("G1")]?.rawValue, "준호")
        XCTAssertEqual(result.values[address("G2")]?.rawValue, "80")
        XCTAssertEqual(result.values[address("G3")]?.rawValue, "#N/A")
        XCTAssertEqual(result.values[address("G4")]?.rawValue, "#REF!")
        XCTAssertEqual(result.values[address("G5")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("G6")]?.rawValue, "3")
        XCTAssertEqual(result.values[address("G7")]?.rawValue, "5")
        XCTAssertEqual(result.values[address("H1")]?.rawValue, "3")
        XCTAssertEqual(result.values[address("H2")]?.rawValue, "4")
        XCTAssertEqual(result.values[address("H3")]?.rawValue, "2")
        XCTAssertEqual(result.values[address("H4")]?.rawValue, "3")
        XCTAssertEqual(result.values[address("H5")]?.rawValue, "3")
        XCTAssertEqual(result.values[address("H6")]?.rawValue, "#N/A")
        XCTAssertEqual(result.values[address("H7")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("H8")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("H9")]?.rawValue, "3")
        XCTAssertEqual(result.values[address("H10")]?.rawValue, "2")
        XCTAssertEqual(result.values[address("I1")]?.rawValue, "없음")
        XCTAssertEqual(result.values[address("I2")]?.rawValue, "#DIV/0!")
        XCTAssertEqual(result.values[address("I3")]?.rawValue, "42")
        XCTAssertEqual(result.values[address("I4")]?.rawValue, "없음")
        XCTAssertEqual(result.values[address("I5")]?.rawValue, "3")
    }

    func testFormulaCalculatorSupportsAdvancedTextFunctions() {
        let maximumText = String(repeating: "x", count: 32_767)
        let cells: [ExcelCellAddress: ExcelCell] = [
            address("A1"): cell("A1", "가나다라마바사"),
            address("A2"): cell("A2", "Alpha beta ALPHA"),
            address("A6"): cell("A6", "문자*표시"),
            address("A7"): cell("A7", "가"),
            address("B7"): cell("B7", "나"),
            address("B8"): cell("B8", "다"),
            address("B5"): errorCell("B5", "#N/A"),
            address("A10"): cell("A10", maximumText),
            address("A11"): cell("A11", "y"),
            address("D1"): formulaCell(
                "D1", "MID(A1,2,3)", cached: ""
            ),
            address("D2"): formulaCell(
                "D2", "MID(A1,20,3)", cached: ""
            ),
            address("D3"): formulaCell(
                "D3", "MID(A1,0,3)", cached: ""
            ),
            address("D4"): formulaCell(
                "D4", "MID(A1,2,-1)", cached: ""
            ),
            address("D5"): formulaCell(
                "D5", "MID(A1,2,99)", cached: ""
            ),
            address("E1"): formulaCell(
                "E1", "FIND(\"A\",A2)", cached: "0"
            ),
            address("E2"): formulaCell(
                "E2", "FIND(\"a\",A2)", cached: "0"
            ),
            address("E3"): formulaCell(
                "E3", "FIND(\"ALPHA\",A2,2)", cached: "0"
            ),
            address("E4"): formulaCell(
                "E4", "FIND(\"없\",A1)", cached: "0"
            ),
            address("E5"): formulaCell(
                "E5", "FIND(\"\",A1,3)", cached: "0"
            ),
            address("F1"): formulaCell(
                "F1", "SEARCH(\"alpha\",A2)", cached: "0"
            ),
            address("F2"): formulaCell(
                "F2", "SEARCH(\"ALPHA\",A2,2)", cached: "0"
            ),
            address("F3"): formulaCell(
                "F3", "SEARCH(\"b?t*\",A2)", cached: "0"
            ),
            address("F4"): formulaCell(
                "F4", "SEARCH(\"~*\",A6)", cached: "0"
            ),
            address("F5"): formulaCell(
                "F5", "SEARCH(\"zzz\",A2)", cached: "0"
            ),
            address("F6"): formulaCell(
                "F6", "SEARCH(\"a\",A2,99)", cached: "0"
            ),
            address("G1"): formulaCell(
                "G1",
                "SUBSTITUTE(A2,\"Alpha\",\"X\")",
                cached: ""
            ),
            address("G2"): formulaCell(
                "G2",
                "SUBSTITUTE(\"1-2-1-2\",\"1\",\"X\",2)",
                cached: ""
            ),
            address("G3"): formulaCell(
                "G3",
                "SUBSTITUTE(\"aaaa\",\"aa\",\"X\",2)",
                cached: ""
            ),
            address("G4"): formulaCell(
                "G4", "SUBSTITUTE(\"abc\",\"\",\"X\")", cached: ""
            ),
            address("G5"): formulaCell(
                "G5",
                "SUBSTITUTE(\"abc\",\"a\",\"x\",0)",
                cached: ""
            ),
            address("G6"): formulaCell(
                "G6",
                "SUBSTITUTE(\"abc\",\"a\",\"x\",9)",
                cached: ""
            ),
            address("H1"): formulaCell(
                "H1", "CONCAT(A7:B8)", cached: ""
            ),
            address("H2"): formulaCell(
                "H2", "CONCAT(\"값:\",10,TRUE)", cached: ""
            ),
            address("H3"): formulaCell(
                "H3", "CONCAT(A7:B8,\"!\")", cached: ""
            ),
            address("H4"): formulaCell(
                "H4", "CONCAT(B5)", cached: ""
            ),
            address("H5"): formulaCell(
                "H5", "CONCAT(A10,A11)", cached: ""
            ),
            address("H6"): formulaCell(
                "H6", "CONCAT(A10)", cached: ""
            ),
            address("I1"): formulaCell(
                "I1", "TEXTJOIN(\",\",TRUE,A7:B8)", cached: ""
            ),
            address("I2"): formulaCell(
                "I2", "TEXTJOIN(\",\",FALSE,A7:B8)", cached: ""
            ),
            address("I3"): formulaCell(
                "I3", "TEXTJOIN(K7:N7,TRUE,K8:N9)", cached: ""
            ),
            address("I4"): formulaCell(
                "I4", "TEXTJOIN(\"\",TRUE,A7:B8)", cached: ""
            ),
            address("I5"): formulaCell(
                "I5", "TEXTJOIN(\",\",TRUE,B5)", cached: ""
            ),
            address("I6"): formulaCell(
                "I6", "TEXTJOIN(\",\",TRUE,\"\",A7)", cached: ""
            ),
            address("I7"): formulaCell(
                "I7", "TEXTJOIN(\"\",TRUE,A10,A11)", cached: ""
            ),
            address("K7"): cell("K7", ","),
            address("L7"): cell("L7", ","),
            address("M7"): cell("M7", ","),
            address("N7"): cell("N7", ";"),
            address("K8"): cell("K8", "A"),
            address("L8"): cell("L8", "B"),
            address("M8"): cell("M8", "C"),
            address("N8"): cell("N8", "D"),
            address("K9"): cell("K9", "E"),
            address("L9"): cell("L9", "F"),
            address("M9"): cell("M9", "G"),
            address("N9"): cell("N9", "H"),
        ]

        let result = ExcelFormulaCalculator.recalculate(
            cells: cells,
            styles: [.plain],
            uses1904DateSystem: false
        )

        XCTAssertEqual(result.unsupportedFormulaCount, 0)
        XCTAssertEqual(result.values[address("D1")]?.rawValue, "나다라")
        XCTAssertEqual(result.values[address("D2")]?.rawValue, "")
        XCTAssertEqual(result.values[address("D3")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("D4")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("D5")]?.rawValue, "나다라마바사")
        XCTAssertEqual(result.values[address("E1")]?.rawValue, "1")
        XCTAssertEqual(result.values[address("E2")]?.rawValue, "5")
        XCTAssertEqual(result.values[address("E3")]?.rawValue, "12")
        XCTAssertEqual(result.values[address("E4")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("E5")]?.rawValue, "3")
        XCTAssertEqual(result.values[address("F1")]?.rawValue, "1")
        XCTAssertEqual(result.values[address("F2")]?.rawValue, "12")
        XCTAssertEqual(result.values[address("F3")]?.rawValue, "7")
        XCTAssertEqual(result.values[address("F4")]?.rawValue, "3")
        XCTAssertEqual(result.values[address("F5")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("F6")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("G1")]?.rawValue, "X beta ALPHA")
        XCTAssertEqual(result.values[address("G2")]?.rawValue, "1-2-X-2")
        XCTAssertEqual(result.values[address("G3")]?.rawValue, "aaX")
        XCTAssertEqual(result.values[address("G4")]?.rawValue, "abc")
        XCTAssertEqual(result.values[address("G5")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("G6")]?.rawValue, "abc")
        XCTAssertEqual(result.values[address("H1")]?.rawValue, "가나다")
        XCTAssertEqual(result.values[address("H2")]?.rawValue, "값:10TRUE")
        XCTAssertEqual(result.values[address("H3")]?.rawValue, "가나다!")
        XCTAssertEqual(result.values[address("H4")]?.rawValue, "#N/A")
        XCTAssertEqual(result.values[address("H5")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("H6")]?.rawValue.count, 32_767)
        XCTAssertEqual(result.values[address("I1")]?.rawValue, "가,나,다")
        XCTAssertEqual(result.values[address("I2")]?.rawValue, "가,나,,다")
        XCTAssertEqual(
            result.values[address("I3")]?.rawValue,
            "A,B,C,D;E,F,G,H"
        )
        XCTAssertEqual(result.values[address("I4")]?.rawValue, "가나다")
        XCTAssertEqual(result.values[address("I5")]?.rawValue, "#N/A")
        XCTAssertEqual(result.values[address("I6")]?.rawValue, "가")
        XCTAssertEqual(result.values[address("I7")]?.rawValue, "#VALUE!")
    }

    func testFormulaCalculatorSupportsTextCleanupFunctions() {
        let nonbreakingSpace = "\u{00A0}"
        let maximumText = String(repeating: "x", count: 32_767)
        let cells: [ExcelCellAddress: ExcelCell] = [
            address("A1"): cell("A1", "  Alpha   beta  "),
            address("A2"): cell(
                "A2", "\(nonbreakingSpace)A\(nonbreakingSpace)"
            ),
            address("A3"): cell(
                "A3", "\u{0000}\tA\nB\u{001F}\u{007F}\(nonbreakingSpace)"
            ),
            address("A4"): errorCell("A4", "#N/A"),
            address("A5"): cell("A5", maximumText),
            address("B1"): formulaCell(
                "B1", "LOWER(\"AbC123-가\")", cached: ""
            ),
            address("B2"): formulaCell(
                "B2", "UPPER(\"aBc123-가\")", cached: ""
            ),
            address("B3"): formulaCell(
                "B3", "PROPER(\"this is a TITLE\")", cached: ""
            ),
            address("B4"): formulaCell(
                "B4", "PROPER(\"2-way 76BudGet\")", cached: ""
            ),
            address("B5"): formulaCell(
                "B5", "PROPER(\"don't STOP\")", cached: ""
            ),
            address("B6"): formulaCell(
                "B6", "LOWER(123)", cached: ""
            ),
            address("B7"): formulaCell(
                "B7", "UPPER(A4)", cached: ""
            ),
            address("B8"): formulaCell(
                "B8", "UPPER(\"a\",\"b\")", cached: ""
            ),
            address("C1"): formulaCell(
                "C1", "TRIM(A1)", cached: ""
            ),
            address("C2"): formulaCell(
                "C2", "TRIM(A2)", cached: ""
            ),
            address("C3"): formulaCell(
                "C3", "CLEAN(A3)", cached: ""
            ),
            address("C4"): formulaCell(
                "C4", "CLEAN(A2)", cached: ""
            ),
            address("C5"): formulaCell(
                "C5", "TRIM(A4)", cached: ""
            ),
            address("D1"): formulaCell(
                "D1", "REPLACE(\"abcdefghijk\",6,5,\"*\")", cached: ""
            ),
            address("D2"): formulaCell(
                "D2", "REPLACE(\"123456\",1,3,\"@\")", cached: ""
            ),
            address("D3"): formulaCell(
                "D3", "REPLACE(\"abc\",2,0,\"X\")", cached: ""
            ),
            address("D4"): formulaCell(
                "D4", "REPLACE(\"가나다라\",2,2,\"X\")", cached: ""
            ),
            address("D5"): formulaCell(
                "D5", "REPLACE(\"abc\",0,1,\"X\")", cached: ""
            ),
            address("D6"): formulaCell(
                "D6", "REPLACE(\"abc\",1,-1,\"X\")", cached: ""
            ),
            address("D7"): formulaCell(
                "D7", "REPLACE(\"abc\",9,2,\"X\")", cached: ""
            ),
            address("D8"): formulaCell(
                "D8", "REPLACE(\"abcd\",2.9,1.9,\"X\")", cached: ""
            ),
            address("D9"): formulaCell(
                "D9", "REPLACE(A4,1,1,\"X\")", cached: ""
            ),
            address("D10"): formulaCell(
                "D10", "REPLACE(A5,1,0,\"y\")", cached: ""
            ),
            address("D11"): formulaCell(
                "D11", "REPLACE(A5,1,1,\"y\")", cached: ""
            ),
        ]

        let result = ExcelFormulaCalculator.recalculate(
            cells: cells,
            styles: [.plain],
            uses1904DateSystem: false
        )

        XCTAssertEqual(result.unsupportedFormulaCount, 0)
        XCTAssertEqual(result.values[address("B1")]?.rawValue, "abc123-가")
        XCTAssertEqual(result.values[address("B2")]?.rawValue, "ABC123-가")
        XCTAssertEqual(result.values[address("B3")]?.rawValue, "This Is A Title")
        XCTAssertEqual(result.values[address("B4")]?.rawValue, "2-Way 76Budget")
        XCTAssertEqual(result.values[address("B5")]?.rawValue, "Don'T Stop")
        XCTAssertEqual(result.values[address("B6")]?.rawValue, "123")
        XCTAssertEqual(result.values[address("B7")]?.rawValue, "#N/A")
        XCTAssertEqual(result.values[address("B8")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("C1")]?.rawValue, "Alpha beta")
        XCTAssertEqual(
            result.values[address("C2")]?.rawValue,
            "\(nonbreakingSpace)A\(nonbreakingSpace)"
        )
        XCTAssertEqual(
            result.values[address("C3")]?.rawValue,
            "AB\u{007F}\(nonbreakingSpace)"
        )
        XCTAssertEqual(
            result.values[address("C4")]?.rawValue,
            "\(nonbreakingSpace)A\(nonbreakingSpace)"
        )
        XCTAssertEqual(result.values[address("C5")]?.rawValue, "#N/A")
        XCTAssertEqual(result.values[address("D1")]?.rawValue, "abcde*k")
        XCTAssertEqual(result.values[address("D2")]?.rawValue, "@456")
        XCTAssertEqual(result.values[address("D3")]?.rawValue, "aXbc")
        XCTAssertEqual(result.values[address("D4")]?.rawValue, "가X라")
        XCTAssertEqual(result.values[address("D5")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("D6")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("D7")]?.rawValue, "abcX")
        XCTAssertEqual(result.values[address("D8")]?.rawValue, "aXcd")
        XCTAssertEqual(result.values[address("D9")]?.rawValue, "#N/A")
        XCTAssertEqual(result.values[address("D10")]?.rawValue, "#VALUE!")
        XCTAssertEqual(result.values[address("D11")]?.rawValue.count, 32_767)
    }

    func testFormulaCalculatorSpillsDynamicArraysAndReferencesThem() {
        let cells: [ExcelCellAddress: ExcelCell] = [
            address("A1"): formulaCell(
                "A1", "SEQUENCE(3,2,1,1)", cached: ""
            ),
            address("C1"): formulaCell("C1", "SUM(A1#)", cached: ""),
            address("D1"): formulaCell("D1", "B2*10", cached: ""),
            address("F1"): cell("F1", "가"),
            address("G1"): numericCell("G1", "90"),
            address("F2"): cell("F2", "나"),
            address("G2"): numericCell("G2", "70"),
            address("F3"): cell("F3", "가"),
            address("G3"): numericCell("G3", "90"),
            address("F4"): cell("F4", "다"),
            address("G4"): numericCell("G4", "80"),
            address("F5"): cell("F5", "라"),
            address("G5"): numericCell("G5", "60"),
            address("J1"): formulaCell(
                "J1", "SORT(UNIQUE(F1:G5),2,-1)", cached: ""
            ),
            address("M1"): formulaCell(
                "M1", "FILTER(F1:G5,G1:G5>=80,\"없음\")", cached: ""
            ),
            address("P1"): formulaCell(
                "P1", "SUM(SEQUENCE(3))", cached: ""
            ),
            address("R1"): formulaCell(
                "R1", "_xlfn.SEQUENCE(1,2,5,5)", cached: ""
            ),
        ]

        let result = ExcelFormulaCalculator.recalculate(
            cells: cells,
            styles: [.plain],
            uses1904DateSystem: false
        )

        XCTAssertEqual(result.unsupportedFormulaCount, 0)
        XCTAssertEqual(result.spillRanges[address("A1")]?.reference, "A1:B3")
        XCTAssertEqual(result.values[address("A1")]?.rawValue, "1")
        XCTAssertEqual(result.values[address("B1")]?.rawValue, "2")
        XCTAssertEqual(result.values[address("A2")]?.rawValue, "3")
        XCTAssertEqual(result.values[address("B2")]?.rawValue, "4")
        XCTAssertEqual(result.values[address("A3")]?.rawValue, "5")
        XCTAssertEqual(result.values[address("B3")]?.rawValue, "6")
        XCTAssertEqual(result.values[address("C1")]?.rawValue, "21")
        XCTAssertEqual(result.values[address("D1")]?.rawValue, "40")
        XCTAssertEqual(result.values[address("J1")]?.rawValue, "가")
        XCTAssertEqual(result.values[address("K1")]?.rawValue, "90")
        XCTAssertEqual(result.values[address("J2")]?.rawValue, "다")
        XCTAssertEqual(result.values[address("K4")]?.rawValue, "60")
        XCTAssertEqual(result.values[address("M1")]?.rawValue, "가")
        XCTAssertEqual(result.values[address("N1")]?.rawValue, "90")
        XCTAssertEqual(result.values[address("M2")]?.rawValue, "가")
        XCTAssertEqual(result.values[address("M3")]?.rawValue, "다")
        XCTAssertEqual(result.values[address("P1")]?.rawValue, "6")
        XCTAssertEqual(result.values[address("R1")]?.rawValue, "5")
        XCTAssertEqual(result.values[address("S1")]?.rawValue, "10")
        XCTAssertEqual(result.spillOwners[address("B3")], address("A1"))
    }

    func testFormulaCalculatorReportsBlockedAndEmptySpills() {
        let cells: [ExcelCellAddress: ExcelCell] = [
            address("A1"): formulaCell("A1", "SEQUENCE(3)", cached: ""),
            address("A2"): numericCell("A2", "99"),
            address("C1"): formulaCell(
                "C1", "FILTER(E1:E2,E1:E2>10)", cached: ""
            ),
            address("E1"): numericCell("E1", "1"),
            address("E2"): numericCell("E2", "2"),
            address("G1"): formulaCell("G1", "SEQUENCE(1,2)", cached: ""),
        ]

        let result = ExcelFormulaCalculator.recalculate(
            cells: cells,
            styles: [.plain],
            uses1904DateSystem: false,
            mergedRanges: [ExcelCellRange(
                start: address("H1"),
                end: address("H2")
            )]
        )

        XCTAssertEqual(result.unsupportedFormulaCount, 0)
        XCTAssertEqual(result.values[address("A1")]?.rawValue, "#SPILL!")
        XCTAssertNil(result.spillRanges[address("A1")])
        XCTAssertNil(result.values[address("A2")])
        XCTAssertEqual(result.values[address("C1")]?.rawValue, "#CALC!")
        XCTAssertEqual(result.values[address("G1")]?.rawValue, "#SPILL!")
    }

    func testFormulaCalculatorSupportsOtherSheetsNamesAndTableReferences() {
        let sourceCells: [ExcelCellAddress: ExcelCell] = [
            address("A1"): cell("A1", "상품"),
            address("B1"): cell("B1", "금액"),
            address("C1"): cell("C1", "두배"),
            address("A2"): cell("A2", "연필"),
            address("B2"): numericCell("B2", "10"),
            address("C2"): formulaCell("C2", "[@금액]*2", cached: ""),
            address("A3"): cell("A3", "공책"),
            address("B3"): numericCell("B3", "20"),
            address("A4"): cell("A4", "가방"),
            address("B4"): numericCell("B4", "30"),
        ]
        let table = ExcelTable(
            id: "1",
            name: "Sales",
            range: ExcelCellRange(start: address("A1"), end: address("C4")),
            partPath: "xl/tables/table1.xml",
            columnNames: ["상품", "금액", "두배"]
        )
        let sourceSheet = ExcelWorksheet(
            id: "source",
            name: "원본 데이터",
            partPath: "xl/worksheets/sheet1.xml",
            cells: sourceCells,
            mergedRanges: [],
            tables: [table],
            columnWidths: [:],
            rowHeights: [:],
            maximumRow: 4,
            maximumColumn: 3,
            didTruncate: false
        )
        let calculationCells: [ExcelCellAddress: ExcelCell] = [
            address("A1"): formulaCell(
                "A1", "SUM('원본 데이터'!B2:B4)", cached: ""
            ),
            address("A2"): formulaCell(
                "A2", "'원본 데이터'!B2*2", cached: ""
            ),
            address("A3"): formulaCell(
                "A3", "SUM(Sales[금액])", cached: ""
            ),
            address("A4"): formulaCell(
                "A4", "COUNTA(Sales[[#Headers],[금액]])", cached: ""
            ),
            address("A5"): formulaCell(
                "A5", "세율*SUM(Sales[금액])", cached: ""
            ),
            address("A6"): formulaCell("A6", "지역값", cached: ""),
            address("D1"): formulaCell("D1", "Sales[금액]", cached: ""),
        ]
        let calculationSheet = ExcelWorksheet(
            id: "calculation",
            name: "계산",
            partPath: "xl/worksheets/sheet2.xml",
            cells: calculationCells,
            mergedRanges: [],
            tables: [],
            columnWidths: [:],
            rowHeights: [:],
            maximumRow: 6,
            maximumColumn: 4,
            didTruncate: false
        )
        let workbook = ExcelWorkbook(
            sheets: [sourceSheet, calculationSheet],
            styles: [.plain],
            definedNames: [
                ExcelDefinedName(
                    name: "세율",
                    formula: "0.1",
                    localSheetIndex: nil,
                    isHidden: false
                ),
                ExcelDefinedName(
                    name: "지역값",
                    formula: "'원본 데이터'!$B$3",
                    localSheetIndex: 1,
                    isHidden: false
                ),
            ],
            uses1904DateSystem: false
        )

        let sourceResult = ExcelFormulaCalculator.recalculate(
            cells: sourceCells,
            styles: [.plain],
            uses1904DateSystem: false,
            tableRanges: [table.range],
            workbook: workbook,
            currentSheetName: sourceSheet.name
        )
        XCTAssertEqual(sourceResult.values[address("C2")]?.rawValue, "20")

        let result = ExcelFormulaCalculator.recalculate(
            cells: calculationCells,
            styles: [.plain],
            uses1904DateSystem: false,
            workbook: workbook,
            currentSheetName: calculationSheet.name
        )

        XCTAssertEqual(result.unsupportedFormulaCount, 0)
        XCTAssertEqual(result.values[address("A1")]?.rawValue, "60")
        XCTAssertEqual(result.values[address("A2")]?.rawValue, "20")
        XCTAssertEqual(result.values[address("A3")]?.rawValue, "60")
        XCTAssertEqual(result.values[address("A4")]?.rawValue, "1")
        XCTAssertEqual(result.values[address("A5")]?.rawValue, "6")
        XCTAssertEqual(result.values[address("A6")]?.rawValue, "20")
        XCTAssertEqual(result.spillRanges[address("D1")]?.reference, "D1:D3")
        XCTAssertEqual(result.values[address("D1")]?.rawValue, "10")
        XCTAssertEqual(result.values[address("D2")]?.rawValue, "20")
        XCTAssertEqual(result.values[address("D3")]?.rawValue, "30")
    }

    @MainActor
    func testViewModelRefreshesCrossSheetFormulaAfterEditAndUndo() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("xlsx")
        try makeCrossSheetWorkbookData().write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let viewModel = ExcelWorkbookViewModel(fileURL: fileURL)
        await viewModel.load()

        // Loading must finish recalculation before publishing the workbook.
        // Selecting a sheet also recalculates and would hide stale load results.
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorDescription)
        XCTAssertEqual(
            viewModel.workbook?.sheets[1].cells[address("A1")]?.rawValue,
            "20"
        )
        XCTAssertFalse(viewModel.hasUnsavedChanges)

        viewModel.selectSheet(1)
        XCTAssertEqual(
            viewModel.selectedSheet?.cells[address("A1")]?.rawValue,
            "20"
        )
        viewModel.selectSheet(0)
        viewModel.selectCell(address("A1"))
        viewModel.updateEditorText("7")
        viewModel.selectSheet(1)
        XCTAssertEqual(
            viewModel.selectedSheet?.cells[address("A1")]?.rawValue,
            "14"
        )

        viewModel.undo()
        XCTAssertEqual(
            viewModel.selectedSheet?.cells[address("A1")]?.rawValue,
            "20"
        )
        viewModel.redo()
        XCTAssertEqual(
            viewModel.selectedSheet?.cells[address("A1")]?.rawValue,
            "14"
        )
    }

    @MainActor
    func testViewModelSpillEditingResizeUndoRedoAndSave() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("xlsx")
        try makeWorkbookData(includeNativeTable: false).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let viewModel = ExcelWorkbookViewModel(fileURL: fileURL)
        await viewModel.load()

        viewModel.selectCell(address("H1"))
        viewModel.updateEditorText("=SEQUENCE(2,2,1,1)")
        XCTAssertEqual(viewModel.selectedSheet?.cells[address("H1")]?.rawValue, "1")
        XCTAssertEqual(viewModel.selectedSheet?.cells[address("I2")]?.rawValue, "4")
        XCTAssertEqual(
            viewModel.selectedSheet?.cells[address("I2")]?.spillAnchor,
            address("H1")
        )

        viewModel.selectCell(address("I2"))
        XCTAssertTrue(viewModel.selectedCellIsSpillResult)
        viewModel.updateEditorText("999")
        XCTAssertEqual(viewModel.selectedSheet?.cells[address("I2")]?.rawValue, "4")

        viewModel.selectCell(address("H1"))
        viewModel.updateEditorText("=SEQUENCE(3,1,10,10)")
        XCTAssertEqual(viewModel.selectedSheet?.cells[address("H3")]?.rawValue, "30")
        XCTAssertNil(viewModel.selectedSheet?.cells[address("I1")])
        XCTAssertNil(viewModel.selectedSheet?.cells[address("I2")])

        viewModel.undo()
        XCTAssertEqual(viewModel.selectedSheet?.cells[address("I2")]?.rawValue, "4")
        viewModel.redo()
        XCTAssertEqual(viewModel.selectedSheet?.cells[address("H3")]?.rawValue, "30")
        XCTAssertNil(viewModel.selectedSheet?.cells[address("I2")])

        await viewModel.save()
        let reloaded = try ExcelWorkbookDocument.load(
            from: Data(contentsOf: fileURL)
        )
        let sheet = try XCTUnwrap(reloaded.sheets.first)
        XCTAssertEqual(sheet.cells[address("H1")]?.formula, "SEQUENCE(3,1,10,10)")
        XCTAssertEqual(sheet.cells[address("H1")]?.spillRange?.reference, "H1:H3")
        XCTAssertEqual(sheet.cells[address("H2")]?.spillAnchor, address("H1"))
        XCTAssertEqual(sheet.cells[address("H3")]?.rawValue, "30")
        XCTAssertTrue(
            try archiveText("xl/worksheets/sheet1.xml", in: Data(contentsOf: fileURL))
                .contains(#"<f t="array" ref="H1:H3" aca="1">SEQUENCE(3,1,10,10)</f>"#)
        )
    }

    func testFormulaCalculatorPreservesArrayReturningLookupFunctions() {
        let cells: [ExcelCellAddress: ExcelCell] = [
            address("A1"): numericCell("A1", "10"),
            address("A2"): numericCell("A2", "20"),
            address("B1"): numericCell("B1", "100"),
            address("B2"): numericCell("B2", "200"),
            address("C1"): formulaCell(
                "C1",
                "INDEX(A1:B2,0,2)",
                cached: "200"
            ),
            address("C2"): formulaCell(
                "C2",
                "XLOOKUP(20,A1:A2,A1:B2)",
                cached: "200"
            ),
        ]

        let result = ExcelFormulaCalculator.recalculate(
            cells: cells,
            styles: [.plain],
            uses1904DateSystem: false
        )

        XCTAssertTrue(result.values.isEmpty)
        XCTAssertEqual(result.unsupportedFormulaCount, 2)
    }

    @MainActor
    func testViewModelRecalculatesDependentFormulasAndUndoTogether()
        async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("xlsx")
        try makeWorkbookData().write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let viewModel = ExcelWorkbookViewModel(fileURL: fileURL)
        await viewModel.load()

        viewModel.selectCell(address("D2"))
        viewModel.updateEditorText("=C2*2")
        XCTAssertEqual(
            viewModel.selectedSheet?.cells[address("D2")]?.rawValue,
            "6"
        )
        viewModel.selectCell(address("C2"))
        viewModel.updateEditorText("=1+4")
        XCTAssertEqual(
            viewModel.selectedSheet?.cells[address("C2")]?.rawValue,
            "5"
        )
        XCTAssertEqual(
            viewModel.selectedSheet?.cells[address("D2")]?.rawValue,
            "10"
        )
        XCTAssertEqual(viewModel.lastFormulaRecalculationCount, 2)

        viewModel.undo()
        XCTAssertEqual(
            viewModel.selectedSheet?.cells[address("C2")]?.rawValue,
            "3"
        )
        XCTAssertEqual(
            viewModel.selectedSheet?.cells[address("D2")]?.rawValue,
            "6"
        )
        viewModel.redo()
        XCTAssertEqual(
            viewModel.selectedSheet?.cells[address("D2")]?.rawValue,
            "10"
        )

        let exported = try await viewModel.exportData()
        let sheetXML = try archiveText(
            "xl/worksheets/sheet1.xml",
            in: exported
        )
        XCTAssertTrue(sheetXML.contains("<f>1+4</f><v>5</v>"))
        XCTAssertTrue(sheetXML.contains("<f>C2*2</f><v>10</v>"))
        let reloaded = try ExcelWorkbookDocument.load(from: exported)
        XCTAssertEqual(
            reloaded.sheets.first?.cells[address("D2")]?.rawValue,
            "10"
        )
    }

    @MainActor
    func testViewModelStoresCalculatedFormulaErrorInXML() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("xlsx")
        try makeWorkbookData().write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let viewModel = ExcelWorkbookViewModel(fileURL: fileURL)
        await viewModel.load()

        viewModel.selectCell(address("D2"))
        viewModel.updateEditorText("=1/0")
        XCTAssertEqual(
            viewModel.selectedSheet?.cells[address("D2")]?.rawValue,
            "#DIV/0!"
        )
        XCTAssertEqual(
            viewModel.selectedSheet?.cells[address("D2")]?.cellType,
            "e"
        )

        let exported = try await viewModel.exportData()
        let sheetXML = try archiveText(
            "xl/worksheets/sheet1.xml",
            in: exported
        )
        XCTAssertTrue(
            sheetXML.contains(
                #"<c r="D2" t="e"><f>1/0</f><v>#DIV/0!</v></c>"#
            )
        )
        let reloaded = try ExcelWorkbookDocument.load(from: exported)
        XCTAssertEqual(
            reloaded.sheets.first?.cells[address("D2")]?.rawValue,
            "#DIV/0!"
        )
        XCTAssertEqual(
            reloaded.sheets.first?.cells[address("D2")]?.cellType,
            "e"
        )
    }

    func testPreflightIgnoresInflatedDimensionWhenActualCellsAreSmall() throws {
        let data = try makeWorkbookData(
            dimensionOverride: "A1:XFD1048576"
        )

        let preflight = try ExcelWorkbookDocument.preflight(from: data)
        let sheet = try XCTUnwrap(preflight.sheets.first)

        XCTAssertFalse(preflight.requiresLargeMode)
        XCTAssertEqual(sheet.maximumRow, 2)
        XCTAssertEqual(sheet.maximumColumn, 5)
        XCTAssertEqual(sheet.cellCount, 7)
    }

    func testLargeWorkbookPreflightWindowSearchEditAndSave() throws {
        let source = try makeLargeWorkbookData(rowCount: 2_205)
        let preflight = try ExcelWorkbookDocument.preflight(from: source)
        let summary = try XCTUnwrap(preflight.sheets.first)

        XCTAssertTrue(preflight.requiresLargeMode)
        XCTAssertEqual(summary.maximumRow, 2_205)
        XCTAssertEqual(summary.maximumColumn, 2)
        XCTAssertEqual(summary.populatedRows.count, 2_205)
        XCTAssertEqual(summary.tableHeaderRows, [1])

        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ExcelLargeWorkbookDocumentTests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        let cache = try ExcelWorkbookDocument.buildLargeCache(
            from: source,
            preflight: preflight,
            directoryURL: cacheDirectory
        )
        let cachedSheet = try XCTUnwrap(
            cache.sheet(partPath: summary.partPath)
        )
        XCTAssertEqual(
            try cachedSheet.cells(in: [2_205])[
                address("B2205")
            ]?.displayValue,
            "마지막 검색 대상"
        )
        XCTAssertEqual(
            try cachedSheet.searchRows(query: "마지막 검색 대상"),
            [2_205]
        )

        let initial = try ExcelWorkbookDocument.loadWindowed(
            from: source,
            preflight: preflight
        )
        let initialSheet = try XCTUnwrap(initial.sheets.first)
        XCTAssertTrue(initialSheet.isWindowed)
        XCTAssertEqual(initialSheet.maximumRow, 2_205)
        XCTAssertNotNil(initialSheet.cell(at: address("A200")))
        XCTAssertNil(initialSheet.cell(at: address("A201")))
        XCTAssertNil(initialSheet.cell(at: address("A2205")))

        let finalRows = summary.windowRows(startingAt: 2_200)
        let finalSheet = try ExcelWorkbookDocument.loadSheetWindow(
            from: source,
            summary: summary,
            includedRows: finalRows
        )
        XCTAssertNotNil(finalSheet.cell(at: address("A1")))
        XCTAssertNil(finalSheet.cell(at: address("A200")))
        XCTAssertEqual(
            finalSheet.cell(at: address("B2205"))?.displayValue,
            "마지막 검색 대상"
        )
        XCTAssertEqual(
            try ExcelWorkbookDocument.searchRows(
                in: source,
                sheetPartPath: summary.partPath,
                query: "마지막 검색 대상"
            ),
            [2_205]
        )

        let saved = try ExcelWorkbookDocument.applying(
            [
                ExcelWorksheetEdits(
                    partPath: summary.partPath,
                    cells: [
                        address("B2205"): ExcelCellEdit(
                            input: .text("저장 후 검색 대상"),
                            styleIndex: nil
                        ),
                    ]
                ),
            ],
            to: source,
            workbook: initial
        )
        XCTAssertEqual(
            try ExcelWorkbookDocument.searchRows(
                in: saved,
                sheetPartPath: summary.partPath,
                query: "저장 후 검색 대상"
            ),
            [2_205]
        )
    }

    @MainActor
    func testLargeWorkbookViewModelNavigatesSearchesAndSaves() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ExcelLargeViewModelTests-\(UUID().uuidString).xlsx"
            )
        try makeLargeWorkbookData(rowCount: 2_205).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let viewModel = ExcelWorkbookViewModel(fileURL: fileURL)
        await viewModel.load()

        XCTAssertTrue(viewModel.isLargeWorkbook)
        XCTAssertEqual(viewModel.selectedLargeWindowRows.first, 1)
        XCTAssertEqual(viewModel.selectedLargeWindowRows.last, 200)
        XCTAssertEqual(viewModel.selectedSheet?.cells.count, 400)

        await viewModel.jumpToLargeRow(2_205)
        XCTAssertEqual(viewModel.selectedLargeWindowRows.last, 2_205)
        XCTAssertEqual(
            viewModel.selectedSheet?.cell(at: address("B2205"))?
                .displayValue,
            "마지막 검색 대상"
        )

        await viewModel.searchLargeWorkbook("마지막 검색 대상")
        XCTAssertEqual(viewModel.largeSearchRows, [2_205])

        viewModel.selectCell(address("B2205"))
        viewModel.editorText = "화면 모델 저장 대상"
        viewModel.commitEditorText()
        await viewModel.save()

        let saved = try Data(contentsOf: fileURL)
        let preflight = try ExcelWorkbookDocument.preflight(from: saved)
        let summary = try XCTUnwrap(preflight.sheets.first)
        XCTAssertEqual(
            try ExcelWorkbookDocument.searchRows(
                in: saved,
                sheetPartPath: summary.partPath,
                query: "화면 모델 저장 대상"
            ),
            [2_205]
        )
    }

    @MainActor
    func testEditorTextAppliesImmediatelyAndCoalescesUndo() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ExcelLiveCellEditingTests-\(UUID().uuidString).xlsx"
            )
        try makeWorkbookData().write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let viewModel = ExcelWorkbookViewModel(fileURL: fileURL)
        await viewModel.load()
        viewModel.selectCell(address("A2"))
        let originalValue = viewModel.selectedCell?.displayValue

        viewModel.updateEditorText("김")
        XCTAssertEqual(viewModel.selectedCell?.displayValue, "김")
        XCTAssertTrue(viewModel.hasUnsavedChanges)

        viewModel.updateEditorText("김영희")
        XCTAssertEqual(viewModel.selectedCell?.displayValue, "김영희")

        viewModel.commitEditorText()
        viewModel.undo()
        XCTAssertEqual(viewModel.selectedCell?.displayValue, originalValue)
        XCTAssertFalse(viewModel.hasUnsavedChanges)
    }

    @MainActor
    func testLargeWorkbookAISearchRetrievesTailRowAndStaysReadOnly() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ExcelLargeAISearchTests-\(UUID().uuidString).xlsx"
            )
        try makeLargeWorkbookData(rowCount: 2_205).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let viewModel = ExcelWorkbookViewModel(fileURL: fileURL)
        await viewModel.load()

        let optionalSnapshot = try await viewModel.makeAISnapshot(
            for: "마지막 검색 대상을 찾아줘"
        )
        let snapshot = try XCTUnwrap(optionalSnapshot)
        XCTAssertFalse(snapshot.supportsEdits)
        XCTAssertTrue(snapshot.searchedWholeSheet)
        XCTAssertEqual(snapshot.searchTerms, ["마지막", "대상"])
        XCTAssertEqual(snapshot.searchResultRowCount, 1)
        XCTAssertFalse(snapshot.searchResultsWereTruncated)
        XCTAssertEqual(snapshot.retrievedRows, [2_205])
        XCTAssertTrue(snapshot.contextWasTruncated)
        XCTAssertEqual(
            snapshot.cell(row: 2_205, column: 2)?.value,
            "마지막 검색 대상"
        )

        let editCommand = ExcelAICommandPlan(
            intent: .edit,
            assistantMessage: "마지막 행을 수정했습니다.",
            edits: [
                .init(row: 2_205, column: 2, newValue: "수정값"),
            ],
            appendedRows: []
        )
        XCTAssertThrowsError(
            try ExcelAICommandValidator.validate(
                editCommand,
                snapshot: snapshot
            )
        ) { error in
            guard case ExcelAICommandValidationError.editingUnavailable = error else {
                return XCTFail("잘못된 오류: \(error)")
            }
        }
    }

    func testLargeAIQueryTokenizerKeepsIdentifiersAndRemovesPromptWords() {
        XCTAssertEqual(
            ExcelLargeAIQueryTokenizer.terms(
                in: "TX-2026-02500을 찾아주세요"
            ),
            ["tx-2026-02500"]
        )
        XCTAssertEqual(
            ExcelLargeAIQueryTokenizer.terms(
                in: "김민준의 예산 초과 항목을 보여줘"
            ),
            ["김민준", "예산", "초과"]
        )
    }

    func testAccessibilityAnalyzerUsesNativeTableHeadersAndRows() throws {
        let workbook = try ExcelWorkbookDocument.load(
            from: makeWorkbookData()
        )
        let sheet = try XCTUnwrap(workbook.sheets.first)

        let region = try XCTUnwrap(
            ExcelAccessibilityAnalyzer.regions(in: sheet).first
        )

        XCTAssertTrue(region.isNativeTable)
        XCTAssertEqual(region.headerRow, 1)
        XCTAssertEqual(region.columns.map(\.title), [
            "이름",
            "전화번호",
            "비고",
        ])
        XCTAssertEqual(region.rowNumbers, [2])
    }

    func testAccessibilityAnalyzerSkipsTitlesAndBlankRows() throws {
        let sheet = ExcelWorksheet(
            id: "sheet",
            name: "학생 명단",
            partPath: "xl/worksheets/sheet1.xml",
            cells: [
                address("A1"): cell("A1", "코덱스초등학교"),
                address("A2"): cell("A2", "가상 자료"),
                address("A4"): cell("A4", "이름"),
                address("B4"): cell("B4", "생일"),
                address("C4"): cell("C4", "키"),
                address("A5"): cell("A5", "김하늘"),
                address("B5"): cell("B5", "2019-03-02"),
                address("C5"): cell("C5", "118.2"),
                address("A7"): cell("A7", "이바다"),
                address("B7"): cell("B7", "2019-06-10"),
                address("C7"): cell("C7", "121.0"),
            ],
            mergedRanges: [
                ExcelCellRange(
                    start: address("A1"),
                    end: address("C1")
                ),
            ],
            tables: [],
            columnWidths: [:],
            rowHeights: [:],
            maximumRow: 7,
            maximumColumn: 3,
            didTruncate: false
        )

        let regions = ExcelAccessibilityAnalyzer.regions(in: sheet)
        let region = try XCTUnwrap(
            regions.first(where: { $0.headerRow == 4 })
        )

        XCTAssertEqual(regions.count, 2)
        XCTAssertFalse(region.isNativeTable)
        XCTAssertEqual(region.headerRow, 4)
        XCTAssertEqual(region.columns.map(\.title), ["이름", "생일", "키"])
        XCTAssertEqual(region.rowNumbers, [5, 7])
        XCTAssertEqual(region.range.reference, "A4:C7")
    }

    func testAccessibilityAnalyzerSeparatesSummaryBlocksAndTable() throws {
        let totalBudgetAddress = address("B4")
        let sheet = ExcelWorksheet(
            id: "sheet",
            name: "요약",
            partPath: "xl/worksheets/sheet1.xml",
            cells: [
                address("A1"): cell("A1", "코덱스 개발팀 재정지출보고서"),
                address("A2"): cell("A2", "2026년 8월"),
                address("A4"): cell("A4", "총 예산"),
                totalBudgetAddress: ExcelCell(
                    address: totalBudgetAddress,
                    rawValue: "6610000",
                    displayValue: "6,610,000",
                    formula: "SUM('지출내역'!E6:E17)",
                    styleIndex: nil,
                    cellType: nil
                ),
                address("A5"): cell("A5", "총 지출"),
                address("B5"): cell("B5", "6,177,000"),
                address("D4"): cell("D4", "보고 조직"),
                address("E4"): cell("E4", "코덱스 개발팀"),
                address("D5"): cell("D5", "보고 기간"),
                address("E5"): cell("E5", "2026년 8월"),
                address("A10"): cell("A10", "비용 분류별 요약"),
                address("A11"): cell("A11", "비용 분류"),
                address("B11"): cell("B11", "예산액(원)"),
                address("C11"): cell("C11", "실제 지출액(원)"),
                address("D11"): cell("D11", "예산 잔액(원)"),
                address("A12"): cell("A12", "개발도구"),
                address("B12"): cell("B12", "500,000"),
                address("C12"): cell("C12", "430,000"),
                address("D12"): cell("D12", "70,000"),
            ],
            mergedRanges: [
                ExcelCellRange(
                    start: address("A1"),
                    end: address("E1")
                ),
                ExcelCellRange(
                    start: address("A2"),
                    end: address("E2")
                ),
                ExcelCellRange(
                    start: address("A10"),
                    end: address("D10")
                ),
            ],
            tables: [],
            columnWidths: [:],
            rowHeights: [:],
            maximumRow: 12,
            maximumColumn: 5,
            didTruncate: false
        )

        let regions = ExcelAccessibilityAnalyzer.regions(in: sheet)

        XCTAssertEqual(regions.count, 4)
        let budget = try XCTUnwrap(
            regions.first(where: { $0.range.reference == "A4:B5" })
        )
        XCTAssertNil(budget.headerRow)
        XCTAssertEqual(budget.columns.map(\.title), ["항목", "값"])
        XCTAssertEqual(budget.rowNumbers, [4, 5])

        let report = try XCTUnwrap(
            regions.first(where: { $0.range.reference == "D4:E5" })
        )
        XCTAssertNil(report.headerRow)
        XCTAssertEqual(report.columns.map(\.title), ["항목", "값"])
        XCTAssertEqual(report.rowNumbers, [4, 5])

        let category = try XCTUnwrap(
            regions.first(where: { $0.name == "비용 분류별 요약" })
        )
        XCTAssertEqual(category.headerRow, 11)
        XCTAssertEqual(category.columns.map(\.title), [
            "비용 분류",
            "예산액(원)",
            "실제 지출액(원)",
            "예산 잔액(원)",
        ])
        XCTAssertEqual(category.rowNumbers, [12])
        XCTAssertFalse(
            regions.flatMap(\.columns).map(\.title).contains("6,610,000")
        )

        let workbook = ExcelWorkbook(
            sheets: [sheet],
            styles: [.plain],
            uses1904DateSystem: false
        )
        let snapshot = try XCTUnwrap(
            ExcelAISnapshotBuilder.make(
                workbookName: "재정지출보고서",
                workbook: workbook,
                selectedSheetIndex: 0,
                selectedAddress: address("E5")
            )
        )
        let command = ExcelAICommandPlan(
            intent: .edit,
            assistantMessage: "보고 기간을 2026년 9월로 수정했습니다.",
            edits: [
                .init(
                    row: 5,
                    column: 5,
                    newValue: "2026년 9월"
                ),
            ],
            appendedRows: []
        )
        let validated = try ExcelAICommandValidator.validate(
            command,
            snapshot: snapshot
        )
        XCTAssertEqual(validated?.edits.first?.column, 5)
    }

    func testAccessibilityAnalyzerIncludesInformationOutsideNativeTable() throws {
        let summaryCountAddress = address("H2")
        let sheet = ExcelWorksheet(
            id: "sheet",
            name: "1학년 5반",
            partPath: "xl/worksheets/sheet1.xml",
            cells: [
                address("A1"): cell("A1", "코덱스초등학교 학생 명단"),
                address("A2"): cell("A2", "가상 학생 자료입니다."),
                address("G1"): cell("G1", "학급 요약"),
                address("G2"): cell("G2", "학생 수"),
                summaryCountAddress: ExcelCell(
                    address: summaryCountAddress,
                    rawValue: "20",
                    displayValue: "20",
                    formula: "COUNTA(B5:B24)",
                    styleIndex: nil,
                    cellType: nil
                ),
                address("G3"): cell("G3", "평균 키"),
                address("H3"): cell("H3", "121.85"),
                address("A4"): cell("A4", "번호"),
                address("B4"): cell("B4", "이름"),
                address("C4"): cell("C4", "생일"),
                address("D4"): cell("D4", "키(cm)"),
                address("E4"): cell("E4", "특이사항"),
                address("A5"): cell("A5", "1"),
                address("B5"): cell("B5", "김민준"),
                address("C5"): cell("C5", "2019-01-14"),
                address("D5"): cell("D5", "121.4"),
                address("E5"): cell("E5", "없음"),
            ],
            mergedRanges: [
                ExcelCellRange(
                    start: address("A1"),
                    end: address("E1")
                ),
                ExcelCellRange(
                    start: address("A2"),
                    end: address("E2")
                ),
                ExcelCellRange(
                    start: address("G1"),
                    end: address("H1")
                ),
            ],
            tables: [
                ExcelTable(
                    id: "1",
                    name: "학생명단",
                    range: ExcelCellRange(
                        start: address("A4"),
                        end: address("E5")
                    ),
                    partPath: "xl/tables/table1.xml"
                ),
            ],
            columnWidths: [:],
            rowHeights: [:],
            maximumRow: 5,
            maximumColumn: 8,
            didTruncate: false
        )

        let regions = ExcelAccessibilityAnalyzer.regions(in: sheet)

        XCTAssertEqual(regions.count, 3)
        XCTAssertEqual(regions[0].name, "학생명단")
        XCTAssertTrue(regions[0].isNativeTable)

        let information = try XCTUnwrap(
            regions.first(where: { $0.name == "문서 정보" })
        )
        XCTAssertEqual(information.range.reference, "A1:E2")
        XCTAssertEqual(information.columns.map(\.title), ["내용"])
        XCTAssertEqual(information.rowNumbers, [1, 2])

        let summary = try XCTUnwrap(
            regions.first(where: { $0.name == "학급 요약" })
        )
        XCTAssertEqual(summary.range.reference, "G1:H3")
        XCTAssertEqual(summary.columns.map(\.title), ["항목", "값"])
        XCTAssertEqual(summary.rowNumbers, [2, 3])
        XCTAssertFalse(summary.isNativeTable)
    }

    func testAISnapshotDescribesTableCellsFormulaAndRevision() throws {
        let workbook = try ExcelWorkbookDocument.load(
            from: makeWorkbookData()
        )

        let first = try XCTUnwrap(
            ExcelAISnapshotBuilder.make(
                workbookName: "연락처",
                workbook: workbook,
                selectedSheetIndex: 0,
                selectedAddress: ExcelCellAddress(row: 2, column: 1)
            )
        )
        let second = try XCTUnwrap(
            ExcelAISnapshotBuilder.make(
                workbookName: "연락처",
                workbook: workbook,
                selectedSheetIndex: 0,
                selectedAddress: ExcelCellAddress(row: 2, column: 1)
            )
        )

        XCTAssertEqual(first.sheetName, "연락처")
        XCTAssertEqual(first.selectedCell, "A2")
        XCTAssertTrue(first.supportsEdits)
        XCTAssertFalse(first.worksheetIsProtected)
        XCTAssertEqual(
            first.capabilities,
            ExcelAICommandCapability.allCases
        )
        XCTAssertFalse(first.searchedWholeSheet)
        XCTAssertEqual(first.regions.first?.id, "table:1")
        XCTAssertEqual(first.regions.first?.dataRows, [2])
        XCTAssertEqual(
            first.cell(row: 2, column: 3)?.formula,
            "1+2"
        )
        XCTAssertEqual(first.mergedRanges, ["D1:E1"])
        XCTAssertEqual(first.revision, second.revision)
    }

    func testAICommandDecoderAcceptsLegacyResponseWithoutActions() throws {
        let data = Data(
            #"{"intent":"answer","assistantMessage":"확인했습니다.","edits":[],"appendedRows":[]}"#.utf8
        )

        let command = try JSONDecoder().decode(
            ExcelAICommandPlan.self,
            from: data
        )

        XCTAssertEqual(command.intent, .answer)
        XCTAssertTrue(command.actions.isEmpty)
    }

    func testAIValidatorAcceptsExistingCellEditAndRowAppend() throws {
        let workbook = try ExcelWorkbookDocument.load(
            from: makeWorkbookData()
        )
        let snapshot = try XCTUnwrap(
            ExcelAISnapshotBuilder.make(
                workbookName: "연락처",
                workbook: workbook,
                selectedSheetIndex: 0,
                selectedAddress: nil
            )
        )
        let command = ExcelAICommandPlan(
            intent: .edit,
            assistantMessage: "전화번호 수정과 새 행 추가를 준비했습니다.",
            edits: [
                .init(
                    row: 2,
                    column: 2,
                    newValue: "010-1111-2222"
                ),
            ],
            appendedRows: [
                .init(
                    regionID: "table:1",
                    values: [
                        .init(column: 1, newValue: "박서준"),
                        .init(column: 2, newValue: "010-3333-4444"),
                    ]
                ),
            ]
        )

        let validated = try XCTUnwrap(
            ExcelAICommandValidator.validate(
                command,
                snapshot: snapshot
            )
        )

        XCTAssertEqual(validated.changeCount, 3)
        XCTAssertEqual(validated.previewLines.count, 2)
        XCTAssertEqual(validated.sourceRevision, snapshot.revision)
    }

    @MainActor
    func testAIPlanEditsAndAppendsToGeneralCellRange() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("xlsx")
        try makeWorkbookData(includeNativeTable: false).write(to: fileURL)
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }
        let viewModel = ExcelWorkbookViewModel(fileURL: fileURL)
        await viewModel.load()
        XCTAssertNil(viewModel.errorDescription)

        let snapshot = try XCTUnwrap(viewModel.makeAISnapshot())
        let region = try XCTUnwrap(snapshot.regions.first)
        XCTAssertFalse(region.isNativeTable)
        XCTAssertEqual(region.range, "A1:C2")
        XCTAssertEqual(
            region.columns.map(\.title),
            ["이름", "전화번호", "비고"]
        )

        let command = ExcelAICommandPlan(
            intent: .edit,
            assistantMessage: "일반 범위의 연락처를 수정하고 새 행을 추가했습니다.",
            edits: [
                .init(
                    row: 2,
                    column: 2,
                    newValue: "010-1111-2222"
                ),
            ],
            appendedRows: [
                .init(
                    regionID: region.id,
                    values: [
                        .init(column: 1, newValue: "박서준"),
                        .init(column: 2, newValue: "010-3333-4444"),
                    ]
                ),
            ]
        )
        let validated = try XCTUnwrap(
            ExcelAICommandValidator.validate(
                command,
                snapshot: snapshot
            )
        )

        _ = try viewModel.applyAIPlan(validated)

        XCTAssertEqual(
            viewModel.selectedSheet?.cell(at: address("B2"))?.displayValue,
            "010-1111-2222"
        )
        XCTAssertEqual(
            viewModel.selectedSheet?.cell(at: address("A3"))?.displayValue,
            "박서준"
        )
        XCTAssertEqual(
            viewModel.selectedSheet?.cell(at: address("B3"))?.displayValue,
            "010-3333-4444"
        )
        XCTAssertTrue(viewModel.hasUnsavedChanges)
    }

    func testAIValidatorResolvesTypedFormattingActions() throws {
        let workbook = try ExcelWorkbookDocument.load(
            from: makeWorkbookData()
        )
        let snapshot = try XCTUnwrap(
            ExcelAISnapshotBuilder.make(
                workbookName: "연락처",
                workbook: workbook,
                selectedSheetIndex: 0,
                selectedAddress: nil
            )
        )
        let region = try XCTUnwrap(snapshot.regions.first)
        let command = ExcelAICommandPlan(
            intent: .edit,
            assistantMessage: "표시 형식과 드롭다운을 설정했습니다.",
            edits: [],
            appendedRows: [],
            actions: [
                .init(
                    type: .setNumberFormat,
                    target: .init(
                        scope: .cell,
                        regionID: region.id,
                        row: 2,
                        column: 3
                    ),
                    format: "integer"
                ),
                .init(
                    type: .setDropdown,
                    target: .init(
                        scope: .column,
                        regionID: region.id,
                        row: nil,
                        column: 1
                    ),
                    values: ["재학", "전학", "재학"],
                    allowsBlank: false
                ),
            ]
        )

        let validated = try XCTUnwrap(
            ExcelAICommandValidator.validate(
                command,
                snapshot: snapshot
            )
        )

        XCTAssertEqual(validated.actions.count, 2)
        XCTAssertEqual(validated.changeCount, 2)
        guard case .setNumberFormat(let addresses, let format) =
                validated.actions[0] else {
            return XCTFail("표시 형식 액션이 아닙니다.")
        }
        XCTAssertEqual(addresses, [address("C2")])
        XCTAssertEqual(format, .integer)
        guard case .setDropdown(
            let dropdownAddresses,
            let values,
            let allowsBlank
        ) = validated.actions[1] else {
            return XCTFail("드롭다운 액션이 아닙니다.")
        }
        XCTAssertEqual(dropdownAddresses, [address("A2")])
        XCTAssertEqual(values, ["재학", "전학"])
        XCTAssertFalse(allowsBlank)
    }

    func testAIValidatorRejectsOverlappingActionTargets() throws {
        let workbook = try ExcelWorkbookDocument.load(
            from: makeWorkbookData()
        )
        let snapshot = try XCTUnwrap(
            ExcelAISnapshotBuilder.make(
                workbookName: "연락처",
                workbook: workbook,
                selectedSheetIndex: 0,
                selectedAddress: nil
            )
        )
        let region = try XCTUnwrap(snapshot.regions.first)
        let command = ExcelAICommandPlan(
            intent: .edit,
            assistantMessage: "드롭다운을 설정했습니다.",
            edits: [],
            appendedRows: [],
            actions: [
                .init(
                    type: .setDropdown,
                    target: .init(
                        scope: .column,
                        regionID: region.id,
                        row: nil,
                        column: 1
                    ),
                    values: ["사과", "배"]
                ),
                .init(
                    type: .setDropdown,
                    target: .init(
                        scope: .cell,
                        regionID: region.id,
                        row: 2,
                        column: 1
                    ),
                    values: ["사과", "배"]
                ),
            ]
        )

        XCTAssertThrowsError(
            try ExcelAICommandValidator.validate(
                command,
                snapshot: snapshot
            )
        ) { error in
            guard case ExcelAICommandValidationError.invalidResponse = error
            else {
                return XCTFail("잘못된 오류: \(error)")
            }
        }
    }

    func testAIValidatorOnlyChecksStructureOfValueAndFormatPlan() throws {
        let workbook = try ExcelWorkbookDocument.load(
            from: makeWorkbookData()
        )
        let snapshot = try XCTUnwrap(
            ExcelAISnapshotBuilder.make(
                workbookName: "연락처",
                workbook: workbook,
                selectedSheetIndex: 0,
                selectedAddress: nil
            )
        )
        let region = try XCTUnwrap(snapshot.regions.first)
        let command = ExcelAICommandPlan(
            intent: .edit,
            assistantMessage: "정수로 표시했습니다.",
            edits: [
                .init(row: 2, column: 3, newValue: "3"),
            ],
            appendedRows: [],
            actions: [
                .init(
                    type: .setNumberFormat,
                    target: .init(
                        scope: .cell,
                        regionID: region.id,
                        row: 2,
                        column: 3
                    ),
                    format: "integer"
                ),
            ]
        )

        let validated = try XCTUnwrap(
            ExcelAICommandValidator.validate(
                command,
                snapshot: snapshot
            )
        )
        // C2 holds =1+2; a display-format request that also rewrites the
        // formula with its cached value is destructive, so the edit is
        // dropped and only the format action survives.
        XCTAssertEqual(validated.edits.count, 0)
        XCTAssertEqual(validated.actions.count, 1)
        XCTAssertEqual(validated.changeCount, 1)
    }

    func testAIValidatorRejectsProtectedWorksheetEdit() throws {
        var workbook = try ExcelWorkbookDocument.load(
            from: makeWorkbookData()
        )
        workbook.sheets[0].protection.isEnabled = true
        let snapshot = try XCTUnwrap(
            ExcelAISnapshotBuilder.make(
                workbookName: "연락처",
                workbook: workbook,
                selectedSheetIndex: 0,
                selectedAddress: nil
            )
        )
        let command = ExcelAICommandPlan(
            intent: .edit,
            assistantMessage: "수정했습니다.",
            edits: [
                .init(row: 2, column: 2, newValue: "010-1111-2222"),
            ],
            appendedRows: []
        )

        XCTAssertTrue(snapshot.worksheetIsProtected)
        XCTAssertThrowsError(
            try ExcelAICommandValidator.validate(
                command,
                snapshot: snapshot
            )
        ) { error in
            guard case ExcelAICommandValidationError.protectedWorksheet =
                    error else {
                return XCTFail("잘못된 오류: \(error)")
            }
        }
    }

    @MainActor
    func testAIPlanAppliesMixedActionsAtomicallyAndRoundTrips()
        async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("xlsx")
        try makeWorkbookData().write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let viewModel = ExcelWorkbookViewModel(fileURL: fileURL)
        await viewModel.load()
        let snapshot = try XCTUnwrap(viewModel.makeAISnapshot())
        let region = try XCTUnwrap(snapshot.regions.first)
        let originalStyleIndex = viewModel.selectedSheet?
            .cell(at: address("C2"))?.styleIndex
        let originalStyleCount = viewModel.workbook?.styles.count
        let originalDifferentialStyleCount = viewModel.workbook?
            .differentialStyles.count
        let command = ExcelAICommandPlan(
            intent: .edit,
            assistantMessage: "값과 표시 규칙을 함께 적용했습니다.",
            edits: [
                .init(
                    row: 2,
                    column: 2,
                    newValue: "010-1111-2222"
                ),
            ],
            appendedRows: [],
            actions: [
                .init(
                    type: .setNumberFormat,
                    target: .init(
                        scope: .cell,
                        regionID: region.id,
                        row: 2,
                        column: 3
                    ),
                    format: "integer"
                ),
                .init(
                    type: .setDropdown,
                    target: .init(
                        scope: .cell,
                        regionID: region.id,
                        row: 2,
                        column: 1
                    ),
                    values: ["김철수", "박서준"],
                    allowsBlank: false
                ),
                .init(
                    type: .setConditionalFormatting,
                    target: .init(
                        scope: .cell,
                        regionID: region.id,
                        row: 2,
                        column: 3
                    ),
                    condition: "greaterThan",
                    comparisonValue: "2",
                    highlight: "red"
                ),
            ]
        )
        let validated = try XCTUnwrap(
            ExcelAICommandValidator.validate(
                command,
                snapshot: snapshot
            )
        )

        _ = try viewModel.applyAIPlan(validated)

        var workbook = try XCTUnwrap(viewModel.workbook)
        var sheet = try XCTUnwrap(workbook.sheets.first)
        XCTAssertEqual(sheet.cell(at: address("B2"))?.rawValue, "010-1111-2222")
        XCTAssertEqual(sheet.cell(at: address("C2"))?.formula, "1+2")
        XCTAssertEqual(
            ExcelNumberFormat.matching(
                workbook.style(at: sheet.cell(at: address("C2"))?.styleIndex)
            ),
            .integer
        )
        XCTAssertEqual(
            sheet.dataValidations.first?.inlineListValues,
            ["김철수", "박서준"]
        )
        XCTAssertTrue(
            sheet.dataValidations.first?.contains(address("A2")) == true
        )
        XCTAssertEqual(
            sheet.matchingConditionalRule(at: address("C2"))?.kind,
            .greaterThan
        )

        viewModel.undo()

        workbook = try XCTUnwrap(viewModel.workbook)
        sheet = try XCTUnwrap(workbook.sheets.first)
        XCTAssertEqual(sheet.cell(at: address("B2"))?.rawValue, "010-0000-0000")
        XCTAssertEqual(sheet.cell(at: address("C2"))?.styleIndex, originalStyleIndex)
        XCTAssertTrue(sheet.dataValidations.isEmpty)
        XCTAssertTrue(sheet.conditionalFormatting.isEmpty)
        XCTAssertEqual(workbook.styles.count, originalStyleCount)
        XCTAssertEqual(
            workbook.differentialStyles.count,
            originalDifferentialStyleCount
        )
        XCTAssertFalse(viewModel.hasUnsavedChanges)
        XCTAssertTrue(viewModel.canRedo)

        viewModel.redo()

        let exported = try await viewModel.exportData()
        workbook = try ExcelWorkbookDocument.load(from: exported)
        sheet = try XCTUnwrap(workbook.sheets.first)
        XCTAssertEqual(sheet.cell(at: address("B2"))?.rawValue, "010-1111-2222")
        XCTAssertEqual(sheet.cell(at: address("C2"))?.formula, "1+2")
        XCTAssertEqual(
            ExcelNumberFormat.matching(
                workbook.style(at: sheet.cell(at: address("C2"))?.styleIndex)
            ),
            .integer
        )
        XCTAssertEqual(
            sheet.dataValidations.first?.inlineListValues,
            ["김철수", "박서준"]
        )
        XCTAssertEqual(
            sheet.matchingConditionalRule(at: address("C2"))?.kind,
            .greaterThan
        )
    }

    func testAIValidatorRejectsTargetsOutsideDetectedTable() throws {
        let workbook = try ExcelWorkbookDocument.load(
            from: makeWorkbookData()
        )
        let snapshot = try XCTUnwrap(
            ExcelAISnapshotBuilder.make(
                workbookName: "연락처",
                workbook: workbook,
                selectedSheetIndex: 0,
                selectedAddress: nil
            )
        )
        let command = ExcelAICommandPlan(
            intent: .edit,
            assistantMessage: "수정안을 준비했습니다.",
            edits: [
                .init(row: 2, column: 4, newValue: "표 밖 값"),
            ],
            appendedRows: []
        )

        XCTAssertThrowsError(
            try ExcelAICommandValidator.validate(
                command,
                snapshot: snapshot
            )
        ) { error in
            guard case ExcelAICommandValidationError.invalidTarget = error else {
                return XCTFail("잘못된 오류: \(error)")
            }
        }
    }

    func testAIValidatorAcceptsFormulaFromStructuredPlan() throws {
        let workbook = try ExcelWorkbookDocument.load(
            from: makeWorkbookData()
        )
        let snapshot = try XCTUnwrap(
            ExcelAISnapshotBuilder.make(
                workbookName: "연락처",
                workbook: workbook,
                selectedSheetIndex: 0,
                selectedAddress: nil
            )
        )
        let command = ExcelAICommandPlan(
            intent: .edit,
            assistantMessage: "수정안을 준비했습니다.",
            edits: [
                .init(row: 2, column: 3, newValue: "=SUM(A2:B2)"),
            ],
            appendedRows: []
        )

        let validated = try XCTUnwrap(
            ExcelAICommandValidator.validate(
                command,
                snapshot: snapshot
            )
        )
        XCTAssertEqual(validated.edits.first?.newValue, "=SUM(A2:B2)")
    }

    func testAIValidatorAcceptsClearsFromStructuredPlan() throws {
        let workbook = try ExcelWorkbookDocument.load(
            from: makeWorkbookData()
        )
        let snapshot = try XCTUnwrap(
            ExcelAISnapshotBuilder.make(
                workbookName: "연락처",
                workbook: workbook,
                selectedSheetIndex: 0,
                selectedAddress: nil
            )
        )
        let command = ExcelAICommandPlan(
            intent: .edit,
            assistantMessage: "행 삭제를 준비했습니다.",
            edits: [
                .init(row: 2, column: 1, newValue: ""),
                .init(row: 2, column: 2, newValue: ""),
            ],
            appendedRows: []
        )

        let validated = try XCTUnwrap(
            ExcelAICommandValidator.validate(
                command,
                snapshot: snapshot
            )
        )
        XCTAssertEqual(validated.edits.count, 2)
        XCTAssertTrue(validated.edits.allSatisfy(\.newValue.isEmpty))
    }

    func testAIValidatorDoesNotTurnAnswersIntoEdits() throws {
        let workbook = try ExcelWorkbookDocument.load(
            from: makeWorkbookData()
        )
        let snapshot = try XCTUnwrap(
            ExcelAISnapshotBuilder.make(
                workbookName: "연락처",
                workbook: workbook,
                selectedSheetIndex: 0,
                selectedAddress: nil
            )
        )
        let command = ExcelAICommandPlan(
            intent: .answer,
            assistantMessage: "현재 표에는 데이터 행이 1개 있습니다.",
            edits: [],
            appendedRows: []
        )

        XCTAssertNil(
            try ExcelAICommandValidator.validate(
                command,
                snapshot: snapshot
            )
        )
    }

    func testAIValidatorTreatsClarificationAsNoEdit() throws {
        let workbook = try ExcelWorkbookDocument.load(
            from: makeWorkbookData()
        )
        let snapshot = try XCTUnwrap(
            ExcelAISnapshotBuilder.make(
                workbookName: "연락처",
                workbook: workbook,
                selectedSheetIndex: 0,
                selectedAddress: nil
            )
        )
        let command = ExcelAICommandPlan(
            intent: .clarify,
            assistantMessage: "김철수가 두 명입니다. 전화번호가 010-1234-5678인 행을 수정할까요?",
            edits: [],
            appendedRows: []
        )

        XCTAssertNil(
            try ExcelAICommandValidator.validate(
                command,
                snapshot: snapshot
            )
        )
    }

    @MainActor
    func testAIChatAutomaticallyAppliesValidatedEdit() throws {
        let workbook = try ExcelWorkbookDocument.load(
            from: makeWorkbookData()
        )
        let snapshot = try XCTUnwrap(
            ExcelAISnapshotBuilder.make(
                workbookName: "연락처",
                workbook: workbook,
                selectedSheetIndex: 0,
                selectedAddress: nil
            )
        )
        let command = ExcelAICommandPlan(
            intent: .edit,
            assistantMessage: "김철수의 전화번호를 010-1111-2222로 수정했습니다.",
            edits: [
                .init(
                    row: 2,
                    column: 2,
                    newValue: "010-1111-2222"
                ),
            ],
            appendedRows: []
        )
        let chat = ExcelAIChatViewModel()
        var appliedPlan: ExcelAIValidatedPlan?

        try chat.handle(
            command,
            snapshot: snapshot
        ) { plan in
            appliedPlan = plan
            return "1개 셀을 수정했습니다."
        }

        XCTAssertEqual(appliedPlan?.changeCount, 1)
        XCTAssertEqual(chat.messages.count, 1)
        XCTAssertEqual(chat.messages[0].role, .assistant)
        XCTAssertEqual(chat.spokenResponse?.id, chat.messages[0].id)
    }

    @MainActor
    func testAIChatDoesNotApplyClarification() throws {
        let workbook = try ExcelWorkbookDocument.load(
            from: makeWorkbookData()
        )
        let snapshot = try XCTUnwrap(
            ExcelAISnapshotBuilder.make(
                workbookName: "연락처",
                workbook: workbook,
                selectedSheetIndex: 0,
                selectedAddress: nil
            )
        )
        let command = ExcelAICommandPlan(
            intent: .clarify,
            assistantMessage: "어느 김철수인지 전화번호로 알려주세요.",
            edits: [],
            appendedRows: []
        )
        let chat = ExcelAIChatViewModel()
        var didApply = false

        try chat.handle(
            command,
            snapshot: snapshot
        ) { _ in
            didApply = true
            return "수정했습니다."
        }

        XCTAssertFalse(didApply)
        XCTAssertEqual(chat.messages.count, 1)
        XCTAssertEqual(chat.messages[0].role, .assistant)
        XCTAssertEqual(chat.messages[0].text, command.assistantMessage)
    }

    func testExcelAIErrorUnwrapsFirebaseAuthenticationFailure() {
        let backendError = NSError(
            domain: "com.google.firebase.FirebaseAI.BackendError",
            code: 403,
            userInfo: [
                NSLocalizedDescriptionKey: "Requests from this app are blocked.",
            ]
        )
        let wrapped = GenerateContentError.internalError(
            underlying: backendError
        )

        guard case .authenticationFailed =
                ExcelAICommandService.userFacingError(for: wrapped) else {
            return XCTFail("Firebase 내부 HTTP 오류를 해제하지 못했습니다.")
        }
    }

    func testExcelAIErrorMapsNetworkFailure() {
        let error = URLError(.notConnectedToInternet)

        guard case .networkUnavailable =
                ExcelAICommandService.userFacingError(for: error) else {
            return XCTFail("네트워크 오류 안내가 잘못되었습니다.")
        }
    }

    private func address(_ reference: String) -> ExcelCellAddress {
        ExcelCellAddress(reference)!
    }

    private func cell(
        _ reference: String,
        _ value: String
    ) -> ExcelCell {
        ExcelCell(
            address: address(reference),
            rawValue: value,
            displayValue: value,
            formula: nil,
            styleIndex: nil,
            cellType: "inlineStr"
        )
    }

    private func numericCell(
        _ reference: String,
        _ value: String
    ) -> ExcelCell {
        ExcelCell(
            address: address(reference),
            rawValue: value,
            displayValue: value,
            formula: nil,
            styleIndex: nil,
            cellType: nil
        )
    }

    private func booleanCell(
        _ reference: String,
        _ value: Bool
    ) -> ExcelCell {
        ExcelCell(
            address: address(reference),
            rawValue: value ? "TRUE" : "FALSE",
            displayValue: value ? "참" : "거짓",
            formula: nil,
            styleIndex: nil,
            cellType: "b"
        )
    }

    private func errorCell(
        _ reference: String,
        _ value: String
    ) -> ExcelCell {
        ExcelCell(
            address: address(reference),
            rawValue: value,
            displayValue: value,
            formula: nil,
            styleIndex: nil,
            cellType: "e"
        )
    }

    private func formulaCell(
        _ reference: String,
        _ formula: String,
        cached value: String
    ) -> ExcelCell {
        ExcelCell(
            address: address(reference),
            rawValue: value,
            displayValue: value,
            formula: formula,
            styleIndex: nil,
            cellType: nil
        )
    }

    func testExcelAIValidatorRejectsEditsThatCollideInsideMergedRange() throws {
        let snapshot = ExcelAIWorkbookSnapshot(
            workbookName: "병합",
            sheetName: "시트1",
            sheetPartPath: "xl/worksheets/sheet1.xml",
            selectedCell: "B2",
            supportsEdits: true,
            worksheetIsProtected: false,
            capabilities: ExcelAICommandCapability.allCases,
            searchedWholeSheet: false,
            searchTerms: [],
            searchResultRowCount: 0,
            searchResultsWereTruncated: false,
            retrievedRows: [],
            regions: [
                .init(
                    id: "range:A1:C2",
                    name: "범위",
                    range: "A1:C2",
                    headerRow: 1,
                    columns: [
                        .init(number: 1, letter: "A", title: "이름"),
                        .init(number: 2, letter: "B", title: "금액"),
                        .init(number: 3, letter: "C", title: "비고"),
                    ],
                    dataRows: [2],
                    isNativeTable: false
                ),
            ],
            mergedRanges: ["B2:C2"],
            cells: [],
            contextWasTruncated: false,
            revision: "merged"
        )
        XCTAssertEqual(
            snapshot.canonicalAddress(row: 2, column: 3),
            ExcelCellAddress(row: 2, column: 2)
        )

        let command = ExcelAICommandPlan(
            intent: .edit,
            assistantMessage: "B2와 C2를 수정했습니다.",
            edits: [
                .init(row: 2, column: 2, newValue: "100"),
                .init(row: 2, column: 3, newValue: "200"),
            ],
            appendedRows: []
        )

        XCTAssertThrowsError(
            try ExcelAICommandValidator.validate(command, snapshot: snapshot)
        ) { error in
            guard case ExcelAICommandValidationError.invalidResponse? =
                error as? ExcelAICommandValidationError
            else {
                return XCTFail("unexpected error \(error)")
            }
        }

        // A single edit through the merged range's non-anchor cell is fine.
        let single = ExcelAICommandPlan(
            intent: .edit,
            assistantMessage: "C2를 수정했습니다.",
            edits: [.init(row: 2, column: 3, newValue: "200")],
            appendedRows: []
        )
        XCTAssertNoThrow(
            try ExcelAICommandValidator.validate(single, snapshot: snapshot)
        )
    }

    @MainActor
    func testExcelAIApplyRejectsCollidingMergedCellEditsWithoutTrapping() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ExcelAIMergedCollision-\(UUID().uuidString).xlsx"
            )
        try makeMergedDataWorkbookData().write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let viewModel = ExcelWorkbookViewModel(fileURL: fileURL)
        await viewModel.load()
        XCTAssertNil(viewModel.errorDescription)
        let sheet = try XCTUnwrap(viewModel.selectedSheet)
        XCTAssertEqual(
            sheet.canonicalAddress(for: address("C2")),
            address("B2")
        )
        let snapshot = try XCTUnwrap(viewModel.makeAISnapshot())
        XCTAssertEqual(snapshot.mergedRanges, ["B2:C2"])

        // Bypass the validator to exercise the apply-side guard directly.
        let plan = ExcelAIValidatedPlan(
            assistantMessage: "B2와 C2를 수정했습니다.",
            edits: [
                .init(row: 2, column: 2, newValue: "100"),
                .init(row: 2, column: 3, newValue: "200"),
            ],
            appendedRows: [],
            createdTables: [],
            actions: [],
            sheetPartPath: snapshot.sheetPartPath,
            sourceRevision: snapshot.revision,
            previewLines: []
        )

        XCTAssertThrowsError(try viewModel.applyAIPlan(plan)) { error in
            guard case ExcelAIApplyError.conflictingEdits? =
                error as? ExcelAIApplyError
            else {
                return XCTFail("unexpected error \(error)")
            }
        }
        XCTAssertEqual(
            viewModel.selectedSheet?.cell(at: address("B2"))?.displayValue,
            "10"
        )
        XCTAssertFalse(viewModel.hasUnsavedChanges)
        XCTAssertFalse(viewModel.canUndo)
    }

    func testExcelAIValidatorDropsEditsThatRewriteFormattedCells() throws {
        let snapshot = ExcelAIWorkbookSnapshot(
            workbookName: "성적",
            sheetName: "시트1",
            sheetPartPath: "xl/worksheets/sheet1.xml",
            selectedCell: "C2",
            supportsEdits: true,
            worksheetIsProtected: false,
            capabilities: ExcelAICommandCapability.allCases,
            searchedWholeSheet: false,
            searchTerms: [],
            searchResultRowCount: 0,
            searchResultsWereTruncated: false,
            retrievedRows: [],
            regions: [
                .init(
                    id: "table:1",
                    name: "성적",
                    range: "A1:C3",
                    headerRow: 1,
                    columns: [
                        .init(number: 1, letter: "A", title: "이름"),
                        .init(number: 2, letter: "B", title: "점수"),
                        .init(number: 3, letter: "C", title: "평균"),
                    ],
                    dataRows: [2, 3],
                    isNativeTable: true
                ),
            ],
            mergedRanges: [],
            cells: [
                .init(address: "A2", row: 2, column: 1, header: "이름",
                      value: "철수", formula: nil, numberFormat: nil),
                .init(address: "B2", row: 2, column: 2, header: "점수",
                      value: "90.375", formula: nil, numberFormat: nil),
                .init(address: "C2", row: 2, column: 3, header: "평균",
                      value: "90.375", formula: "B2/1", numberFormat: nil),
                .init(address: "A3", row: 3, column: 1, header: "이름",
                      value: "영희", formula: nil, numberFormat: nil),
                .init(address: "B3", row: 3, column: 2, header: "점수",
                      value: "80", formula: nil, numberFormat: nil),
                .init(address: "C3", row: 3, column: 3, header: "평균",
                      value: "80", formula: "B3/1", numberFormat: nil),
            ],
            contextWasTruncated: false,
            revision: "grades"
        )

        // The model formats the 평균 column but also "helpfully" rewrites the
        // formula cells with rounded numbers and re-sends an unchanged score.
        let command = ExcelAICommandPlan(
            intent: .edit,
            assistantMessage: "평균을 정수로 표시했습니다.",
            edits: [
                .init(row: 2, column: 3, newValue: "90"),
                .init(row: 3, column: 3, newValue: "80"),
                .init(row: 3, column: 2, newValue: "80.0"),
                // Stray copy of round(C2) into the unformatted 점수 column.
                .init(row: 2, column: 2, newValue: "90"),
                .init(row: 2, column: 1, newValue: "김철수"),
            ],
            appendedRows: [],
            createdTables: [],
            actions: [
                .init(
                    type: .setNumberFormat,
                    target: .init(
                        scope: .column,
                        regionID: "table:1",
                        row: nil,
                        column: 3
                    ),
                    format: "integer",
                    values: nil,
                    allowsBlank: nil,
                    condition: nil,
                    comparisonValue: nil,
                    highlight: nil
                ),
                .init(
                    type: .setNumberFormat,
                    target: .init(
                        scope: .cell,
                        regionID: "table:1",
                        row: 3,
                        column: 2
                    ),
                    format: "integer",
                    values: nil,
                    allowsBlank: nil,
                    condition: nil,
                    comparisonValue: nil,
                    highlight: nil
                ),
            ]
        )
        let validated = try XCTUnwrap(
            ExcelAICommandValidator.validate(command, snapshot: snapshot)
        )

        // Formula rewrites, the no-op numeric rewrite, and the stray rounded
        // copy are dropped; the explicit text change is kept.
        XCTAssertEqual(
            validated.edits.map { "\($0.row):\($0.column)=\($0.newValue)" },
            ["2:1=김철수"]
        )
        XCTAssertEqual(validated.actions.count, 2)
    }

    @MainActor
    func testExcelAINumberFormatOnUnsavedCellsStillExports() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ExcelAIFormatUnsaved-\(UUID().uuidString).xlsx"
            )
        try ExcelWorkbookDocument.blankWorkbookData().write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let viewModel = ExcelWorkbookViewModel(fileURL: fileURL)
        await viewModel.load()

        // Turn 1: create a table.
        var snapshot = try XCTUnwrap(viewModel.makeAISnapshot())
        var validated = try XCTUnwrap(
            ExcelAICommandValidator.validate(
                ExcelAICommandPlan(
                    intent: .edit,
                    assistantMessage: "표를 만들었습니다.",
                    edits: [],
                    appendedRows: [],
                    createdTables: [
                        .init(
                            startRow: 1,
                            startColumn: 1,
                            headers: ["Region", "Amount"],
                            blankRowCount: 2
                        ),
                    ]
                ),
                snapshot: snapshot
            )
        )
        _ = try viewModel.applyAIPlan(validated)

        // Turn 2: fill the reserved rows with plain numbers (unsaved).
        snapshot = try XCTUnwrap(viewModel.makeAISnapshot())
        validated = try XCTUnwrap(
            ExcelAICommandValidator.validate(
                ExcelAICommandPlan(
                    intent: .edit,
                    assistantMessage: "값을 채웠습니다.",
                    edits: [
                        .init(row: 2, column: 1, newValue: "Denmark"),
                        .init(row: 2, column: 2, newValue: "1148"),
                        .init(row: 3, column: 1, newValue: "Finland"),
                        .init(row: 3, column: 2, newValue: "192.1"),
                    ],
                    appendedRows: []
                ),
                snapshot: snapshot
            )
        )
        _ = try viewModel.applyAIPlan(validated)

        // Turn 3: format the Amount column of those still-unsaved cells.
        snapshot = try XCTUnwrap(viewModel.makeAISnapshot())
        let region = try XCTUnwrap(snapshot.regions.first)
        validated = try XCTUnwrap(
            ExcelAICommandValidator.validate(
                ExcelAICommandPlan(
                    intent: .edit,
                    assistantMessage: "소수 둘째 자리로 표시했습니다.",
                    edits: [],
                    appendedRows: [],
                    actions: [
                        .init(
                            type: .setNumberFormat,
                            target: .init(
                                scope: .column,
                                regionID: region.id,
                                row: nil,
                                column: 2
                            ),
                            format: "decimalTwo"
                        ),
                    ]
                ),
                snapshot: snapshot
            )
        )
        _ = try viewModel.applyAIPlan(validated)
        XCTAssertEqual(
            viewModel.selectedSheet?.cell(at: address("B2"))?.displayValue,
            "1,148.00"
        )

        // Exporting used to fail with `.cannotSave` because the format
        // action turned the unsaved cell edit into a style-only patch.
        let exported = try await viewModel.exportData()
        let reloaded = try ExcelWorkbookDocument.load(from: exported)
        let sheet = try XCTUnwrap(reloaded.sheets.first)
        XCTAssertEqual(sheet.cell(at: address("B2"))?.rawValue, "1148")
        XCTAssertEqual(sheet.cell(at: address("B2"))?.displayValue, "1,148.00")
        XCTAssertEqual(sheet.cell(at: address("B3"))?.rawValue, "192.1")
        XCTAssertEqual(sheet.cell(at: address("A3"))?.displayValue, "Finland")
        XCTAssertEqual(
            ExcelNumberFormat.matching(
                reloaded.style(at: sheet.cell(at: address("B3"))?.styleIndex)
            ),
            .decimalTwo
        )
    }

    func testConditionalFormattingSupportsInclusiveComparisons() throws {
        let source = try makeWorkbookData()
        let workbook = try ExcelWorkbookDocument.load(from: source)
        let sheet = try XCTUnwrap(workbook.sheets.first)
        let block = ExcelConditionalFormattingBlock(
            ranges: [ExcelCellRange("C2:C4")!],
            rules: [
                ExcelConditionalFormattingRule(
                    kind: .greaterThanOrEqual,
                    comparisonValue: "3",
                    differentialStyleIndex: 0,
                    priority: 1
                ),
                ExcelConditionalFormattingRule(
                    kind: .lessThanOrEqual,
                    comparisonValue: "2",
                    differentialStyleIndex: 0,
                    priority: 2
                ),
            ]
        )
        let saved = try ExcelWorkbookDocument.applying(
            [],
            to: source,
            workbook: workbook,
            conditionalFormattingEdits: [
                ExcelWorksheetConditionalFormattingEdits(
                    partPath: sheet.partPath,
                    blocks: [block]
                ),
            ],
            differentialStyleEdits: [
                ExcelDifferentialStyleEdit(
                    styleIndex: 0,
                    style: ExcelConditionalHighlight.green.style
                ),
            ]
        )
        let xml = try archiveText("xl/worksheets/sheet1.xml", in: saved)
        XCTAssertTrue(xml.contains(#"operator="greaterThanOrEqual""#))
        XCTAssertTrue(xml.contains(#"operator="lessThanOrEqual""#))

        let reloaded = try ExcelWorkbookDocument.load(from: saved)
        let loadedSheet = try XCTUnwrap(reloaded.sheets.first)
        let rules = try XCTUnwrap(loadedSheet.conditionalFormatting.first?.rules)
        XCTAssertEqual(rules.map(\.kind), [.greaterThanOrEqual, .lessThanOrEqual])
        // C2 holds =1+2 (cached 3): >= 3 matches, <= 2 does not.
        let c2 = loadedSheet.cell(at: address("C2"))
        XCTAssertTrue(rules[0].matches(c2))
        XCTAssertFalse(rules[1].matches(c2))
        XCTAssertTrue(ExcelConditionalRuleKind.greaterThanOrEqual.requiresNumber)
        XCTAssertTrue(ExcelConditionalRuleKind.lessThanOrEqual.requiresNumber)
    }

    func testTypedDateInputRecognizesOnlyUnambiguousDates() {
        XCTAssertEqual(
            ExcelDateInput.serial(fromUserText: "2024-03-05", uses1904DateSystem: false),
            "45356"
        )
        XCTAssertEqual(
            ExcelDateInput.serial(fromUserText: " 2024.3.5 ", uses1904DateSystem: false),
            "45356"
        )
        XCTAssertEqual(
            ExcelDateInput.serial(fromUserText: "2024/03/05", uses1904DateSystem: false),
            "45356"
        )
        // The app maps serials from 1899-12-30 uniformly (Excel's 1900
        // leap-year quirk is ignored), so use a date after 1900-02-28.
        XCTAssertEqual(
            ExcelDateInput.serial(fromUserText: "1900-03-01", uses1904DateSystem: false),
            "61"
        )
        XCTAssertEqual(
            ExcelDateInput.serial(fromUserText: "1904-01-02", uses1904DateSystem: true),
            "1"
        )
        XCTAssertNil(
            ExcelDateInput.serial(fromUserText: "2024-02-30", uses1904DateSystem: false)
        )
        XCTAssertNil(
            ExcelDateInput.serial(fromUserText: "10-20", uses1904DateSystem: false)
        )
        XCTAssertNil(
            ExcelDateInput.serial(fromUserText: "20240305", uses1904DateSystem: false)
        )
        XCTAssertNil(
            ExcelDateInput.serial(fromUserText: "1010-GL120-3C", uses1904DateSystem: false)
        )
    }

    @MainActor
    func testTypedDatesBecomeDateSerialsWithDateStyle() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ExcelTypedDate-\(UUID().uuidString).xlsx"
            )
        try ExcelWorkbookDocument.blankWorkbookData().write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let viewModel = ExcelWorkbookViewModel(fileURL: fileURL)
        await viewModel.load()

        // Manual path: the row form.
        viewModel.appendRow(fields: [
            ExcelWorkbookViewModel.RowField(
                id: 1, column: 1, title: "날짜", value: "2024-03-05"
            ),
            ExcelWorkbookViewModel.RowField(
                id: 2, column: 2, title: "메모", value: "품번 10-20"
            ),
        ])
        var sheet = try XCTUnwrap(viewModel.selectedSheet)
        var dateCell = try XCTUnwrap(sheet.cell(at: address("A1")))
        XCTAssertEqual(dateCell.rawValue, "45356")
        XCTAssertEqual(dateCell.displayValue, "2024-03-05")
        XCTAssertEqual(
            ExcelNumberFormat.matching(
                try XCTUnwrap(viewModel.workbook).style(at: dateCell.styleIndex)
            ),
            .date
        )
        XCTAssertEqual(sheet.cell(at: address("B1"))?.displayValue, "품번 10-20")
        XCTAssertTrue(viewModel.canUndo)

        // Undo restores the untouched style registry as well as the cell.
        let stylesAfterDate = try XCTUnwrap(viewModel.workbook).styles.count
        viewModel.undo()
        XCTAssertNil(viewModel.selectedSheet?.cell(at: address("A1")))
        XCTAssertLessThan(try XCTUnwrap(viewModel.workbook).styles.count, stylesAfterDate)
        viewModel.redo()
        XCTAssertEqual(
            viewModel.selectedSheet?.cell(at: address("A1"))?.displayValue,
            "2024-03-05"
        )

        // AI path: a chat edit writing a date into a created table.
        var snapshot = try XCTUnwrap(viewModel.makeAISnapshot())
        XCTAssertEqual(snapshot.cell(row: 1, column: 1)?.value, "2024-03-05")
        XCTAssertEqual(snapshot.cell(row: 1, column: 1)?.numberFormat, "date")
        let region = try XCTUnwrap(snapshot.regions.first)
        let validated = try XCTUnwrap(
            ExcelAICommandValidator.validate(
                ExcelAICommandPlan(
                    intent: .edit,
                    assistantMessage: "날짜 행을 추가했습니다.",
                    edits: [],
                    appendedRows: [
                        .init(
                            regionID: region.id,
                            values: [
                                .init(column: 1, newValue: "2024-12-31"),
                                .init(column: 2, newValue: "연말"),
                            ]
                        ),
                    ]
                ),
                snapshot: snapshot
            )
        )
        _ = try viewModel.applyAIPlan(validated)
        sheet = try XCTUnwrap(viewModel.selectedSheet)
        dateCell = try XCTUnwrap(sheet.cell(at: address("A2")))
        XCTAssertEqual(dateCell.rawValue, "45657")
        XCTAssertEqual(dateCell.displayValue, "2024-12-31")

        // Exported file keeps the serial and the date style.
        let exported = try await viewModel.exportData()
        let reloaded = try ExcelWorkbookDocument.load(from: exported)
        let reloadedSheet = try XCTUnwrap(reloaded.sheets.first)
        XCTAssertEqual(reloadedSheet.cell(at: address("A1"))?.rawValue, "45356")
        XCTAssertEqual(reloadedSheet.cell(at: address("A1"))?.displayValue, "2024-03-05")
        XCTAssertEqual(reloadedSheet.cell(at: address("A2"))?.displayValue, "2024-12-31")
        snapshot = try XCTUnwrap(viewModel.makeAISnapshot())
        XCTAssertEqual(snapshot.cell(row: 2, column: 1)?.value, "2024-12-31")
    }

    @MainActor
    func testExcelAIConditionalRulesAccumulateAndSameRuleReplaces() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExcelAICFStack-\(UUID().uuidString).xlsx")
        try makeWorkbookData().write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let viewModel = ExcelWorkbookViewModel(fileURL: fileURL)
        await viewModel.load()

        func apply(_ condition: String, _ value: String, _ highlight: String) throws {
            let snapshot = try XCTUnwrap(viewModel.makeAISnapshot())
            let region = try XCTUnwrap(snapshot.regions.first)
            let validated = try XCTUnwrap(
                ExcelAICommandValidator.validate(
                    ExcelAICommandPlan(
                        intent: .edit,
                        assistantMessage: "조건부 서식을 적용했습니다.",
                        edits: [],
                        appendedRows: [],
                        actions: [
                            .init(
                                type: .setConditionalFormatting,
                                target: .init(
                                    scope: .column,
                                    regionID: region.id,
                                    row: nil,
                                    column: 2
                                ),
                                condition: condition,
                                comparisonValue: value,
                                highlight: highlight
                            ),
                        ]
                    ),
                    snapshot: snapshot
                )
            )
            _ = try viewModel.applyAIPlan(validated)
        }
        func rules() -> [(String, String, ExcelConditionalHighlight?)] {
            let sheet = viewModel.selectedSheet!
            let styles = viewModel.workbook!.differentialStyles
            return sheet.conditionalFormatting.flatMap(\.rules).map {
                ($0.kind.rawValue, $0.comparisonValue,
                 ExcelConditionalHighlight.matching(styles[$0.differentialStyleIndex]))
            }
        }

        try apply("containsText", "Overdue", "red")
        try apply("containsText", "Complete", "green")
        XCTAssertEqual(rules().map(\.1), ["Overdue", "Complete"])

        // Same condition again only changes the color.
        try apply("containsText", "overdue", "yellow")
        XCTAssertEqual(rules().map(\.1), ["Complete", "overdue"])
        XCTAssertEqual(rules().map(\.2), [.green, .yellow])

        // Manual editor path follows the same semantics.
        viewModel.selectCell(address("B2"))
        _ = viewModel.applyConditionalFormatting(
            kind: .containsText,
            comparisonValue: "010",
            highlight: .red,
            toCurrentColumn: true
        )
        XCTAssertEqual(rules().count, 3)

        // Exported file keeps all three rules on the column.
        let exported = try await viewModel.exportData()
        let reloaded = try ExcelWorkbookDocument.load(from: exported)
        XCTAssertEqual(
            reloaded.sheets.first?.conditionalFormatting.flatMap(\.rules).count,
            3
        )
    }

    func testAIValidatorAllowsSeveralConditionalRulesOnOneColumn() throws {
        let workbook = try ExcelWorkbookDocument.load(from: makeWorkbookData())
        let snapshot = try XCTUnwrap(
            ExcelAISnapshotBuilder.make(
                workbookName: "연락처",
                workbook: workbook,
                selectedSheetIndex: 0,
                selectedAddress: nil
            )
        )
        let region = try XCTUnwrap(snapshot.regions.first)
        func action(_ value: String, _ highlight: String) -> ExcelAICommandPlan.Action {
            .init(
                type: .setConditionalFormatting,
                target: .init(scope: .column, regionID: region.id, row: nil, column: 2),
                condition: "containsText",
                comparisonValue: value,
                highlight: highlight
            )
        }
        let stacked = ExcelAICommandPlan(
            intent: .edit,
            assistantMessage: "규칙 두 개를 걸었습니다.",
            edits: [],
            appendedRows: [],
            actions: [action("010", "red"), action("02", "green")]
        )
        let validated = try XCTUnwrap(
            ExcelAICommandValidator.validate(stacked, snapshot: snapshot)
        )
        XCTAssertEqual(validated.actions.count, 2)

        let duplicated = ExcelAICommandPlan(
            intent: .edit,
            assistantMessage: "같은 규칙을 두 번 걸었습니다.",
            edits: [],
            appendedRows: [],
            actions: [action("010", "red"), action("010", "green")]
        )
        XCTAssertThrowsError(
            try ExcelAICommandValidator.validate(duplicated, snapshot: snapshot)
        )
    }

    func testAIValidatorAllowsOutOfRegionEditsOnlyForExplicitAddresses() throws {
        XCTAssertEqual(
            ExcelAICommandValidator.explicitCellAddresses(in: "b2에 제목, $I$6 에 0.1, Table6[Sales] 말고 D3:E4"),
            Set([
                address("B2"), address("I6"),
                address("D3"), address("E3"), address("D4"), address("E4"),
            ])
        )

        let workbook = try ExcelWorkbookDocument.load(from: makeWorkbookData())
        let snapshot = try XCTUnwrap(
            ExcelAISnapshotBuilder.make(
                workbookName: "연락처",
                workbook: workbook,
                selectedSheetIndex: 0,
                selectedAddress: nil
            )
        )
        let command = ExcelAICommandPlan(
            intent: .edit,
            assistantMessage: "H6에 Tax를 썼습니다.",
            edits: [.init(row: 6, column: 8, newValue: "Tax")],
            appendedRows: []
        )
        XCTAssertThrowsError(
            try ExcelAICommandValidator.validate(
                command, snapshot: snapshot, userRequest: "표 옆에 Tax 라고 써줘"
            )
        )
        let validated = try XCTUnwrap(
            ExcelAICommandValidator.validate(
                command, snapshot: snapshot, userRequest: "H6 셀에 Tax 라고 써줘"
            )
        )
        XCTAssertEqual(validated.explicitAddresses, [address("H6")])
        XCTAssertEqual(validated.edits.count, 1)
    }

    @MainActor
    func testExcelAIWritesExplicitlyAddressedCellsOutsideRegions() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExcelAIExplicit-\(UUID().uuidString).xlsx")
        try ExcelWorkbookDocument.blankWorkbookData().write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let viewModel = ExcelWorkbookViewModel(fileURL: fileURL)
        await viewModel.load()

        // Blank sheet, no regions at all: a titled cell named by the user.
        var snapshot = try XCTUnwrap(viewModel.makeAISnapshot())
        XCTAssertTrue(snapshot.regions.isEmpty)
        var validated = try XCTUnwrap(
            ExcelAICommandValidator.validate(
                ExcelAICommandPlan(
                    intent: .edit,
                    assistantMessage: "제목을 썼습니다.",
                    edits: [
                        .init(row: 2, column: 2, newValue: "Excel Sample Data"),
                        .init(row: 6, column: 8, newValue: "Tax"),
                        .init(row: 6, column: 9, newValue: "0.1"),
                    ],
                    appendedRows: []
                ),
                snapshot: snapshot,
                userRequest: "B2에 Excel Sample Data, H6에 Tax, I6에 0.1 을 써줘"
            )
        )
        _ = try viewModel.applyAIPlan(validated)
        XCTAssertEqual(
            viewModel.selectedSheet?.cell(at: address("B2"))?.displayValue,
            "Excel Sample Data"
        )
        XCTAssertEqual(viewModel.selectedSheet?.cell(at: address("I6"))?.rawValue, "0.1")

        // A plan that targets an unnamed cell outside every region is
        // still rejected at apply time even if it slipped past validation.
        snapshot = try XCTUnwrap(viewModel.makeAISnapshot())
        let sneaky = ExcelAIValidatedPlan(
            assistantMessage: "몰래 썼습니다.",
            edits: [.init(row: 20, column: 20, newValue: "x")],
            appendedRows: [],
            createdTables: [],
            actions: [],
            sheetPartPath: snapshot.sheetPartPath,
            sourceRevision: snapshot.revision,
            previewLines: []
        )
        XCTAssertThrowsError(try viewModel.applyAIPlan(sneaky))

        // The explicit cells survive export.
        let exported = try await viewModel.exportData()
        let reloaded = try ExcelWorkbookDocument.load(from: exported)
        XCTAssertEqual(reloaded.sheets.first?.cell(at: address("H6"))?.displayValue, "Tax")
        XCTAssertEqual(reloaded.sheets.first?.cell(at: address("B2"))?.displayValue, "Excel Sample Data")
    }

    private func makeMergedDataWorkbookData() throws -> Data {
        try makeZIPData(entries: [
            "[Content_Types].xml":
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>
                """,
            "xl/workbook.xml":
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
                  xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
                  <sheets><sheet name="병합" sheetId="1" r:id="rId1"/></sheets>
                </workbook>
                """,
            "xl/_rels/workbook.xml.rels":
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
                  <Relationship Id="rId1"
                    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet"
                    Target="worksheets/sheet1.xml"/>
                </Relationships>
                """,
            "xl/styles.xml":
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
                  <fonts count="1"><font/></fonts>
                  <fills count="1"><fill><patternFill patternType="none"/></fill></fills>
                  <cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0"/></cellXfs>
                </styleSheet>
                """,
            "xl/worksheets/sheet1.xml":
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
                  <dimension ref="A1:C2"/>
                  <sheetData>
                    <row r="1">
                      <c r="A1" t="inlineStr"><is><t>이름</t></is></c>
                      <c r="B1" t="inlineStr"><is><t>금액</t></is></c>
                      <c r="C1" t="inlineStr"><is><t>비고</t></is></c>
                    </row>
                    <row r="2">
                      <c r="A2" t="inlineStr"><is><t>김철수</t></is></c>
                      <c r="B2"><v>10</v></c>
                    </row>
                  </sheetData>
                  <mergeCells count="1"><mergeCell ref="B2:C2"/></mergeCells>
                </worksheet>
                """,
        ])
    }

    private func makeWorkbookData(
        includeNativeTable: Bool = true,
        usesSpreadsheetNamespacePrefix: Bool = false,
        dimensionOverride: String? = nil,
        includeDrawingObjects: Bool = false,
        includeCompatibilityMetadata: Bool = false
    ) throws -> Data {
        let dimensionReference = dimensionOverride
            ?? (includeNativeTable ? "A1:E2" : "A1:C2")
        let mergedTitleCell = includeNativeTable
            ? #"<c r="D1" t="inlineStr"><is><t>병합 제목</t></is></c>"#
            : ""
        let mergeCells = includeNativeTable
            ? #"<mergeCells count="1"><mergeCell ref="D1:E1"/></mergeCells>"#
            : ""
        let tableParts = includeNativeTable
            ? #"<tableParts count="1"><tablePart r:id="rIdTable1"/></tableParts>"#
            : ""
        let drawingElement = includeDrawingObjects
            ? #"<drawing r:id="rIdDrawing1"/>"#
            : ""
        var entries = [
                "[Content_Types].xml":
                    """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>
                    """,
                "docProps/custom.xml": "보존할 데이터",
                "xl/workbook.xml":
                    """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
                      xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
                      <sheets><sheet name="연락처" sheetId="1" r:id="rId1"/></sheets>
                    </workbook>
                    """,
                "xl/_rels/workbook.xml.rels":
                    """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
                      <Relationship Id="rId1"
                        Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet"
                        Target="worksheets/sheet1.xml"/>
                    </Relationships>
                    """,
                "xl/sharedStrings.xml":
                    """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
                      <si><t>이름</t></si><si><t>전화번호</t></si><si><t>비고</t></si>
                      <si><t>김철수</t></si><si><t>010-0000-0000</t></si>
                    </sst>
                    """,
                "xl/styles.xml":
                    """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
                      <fonts count="2"><font/><font><b/></font></fonts>
                      <fills count="1"><fill><patternFill patternType="none"/></fill></fills>
                      <cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0"/><xf numFmtId="0" fontId="1" fillId="0"/></cellXfs>
                    </styleSheet>
                    """,
                "xl/worksheets/sheet1.xml":
                    """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
                      xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
                      <dimension ref="\(dimensionReference)"/>
                      <cols><col min="1" max="1" width="20" customWidth="1"/></cols>
                      <sheetData>
                        <row r="1">
                          <c r="A1" s="1" t="s"><v>0</v></c>
                          <c r="B1" s="1" t="s"><v>1</v></c>
                          <c r="C1" s="1" t="s"><v>2</v></c>
                          \(mergedTitleCell)
                        </row>
                        <row r="2">
                          <c r="A2" t="s"><v>3</v></c>
                          <c r="B2" t="s"><v>4</v></c>
                          <c r="C2"><f>1+2</f><v>3</v></c>
                        </row>
                      </sheetData>
                      <autoFilter ref="A1:C2"/>
                      \(mergeCells)
                      \(drawingElement)
                      \(tableParts)
                    </worksheet>
                    """,
                "xl/worksheets/_rels/sheet1.xml.rels":
                    """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
                      <Relationship Id="rIdTable1"
                        Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/table"
                        Target="../tables/table1.xml"/>
                    </Relationships>
                    """,
                "xl/tables/table1.xml":
                    """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <table xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
                      id="1" name="연락처표" displayName="연락처표" ref="A1:C2">
                      <autoFilter ref="A1:C2"/>
                      <tableColumns count="3"><tableColumn id="1" name="이름"/><tableColumn id="2" name="전화번호"/><tableColumn id="3" name="비고"/></tableColumns>
                    </table>
                    """,
            ]
        if usesSpreadsheetNamespacePrefix {
            let spreadsheetParts = [
                "xl/workbook.xml",
                "xl/sharedStrings.xml",
                "xl/styles.xml",
                "xl/worksheets/sheet1.xml",
                "xl/tables/table1.xml",
            ]
            for path in spreadsheetParts {
                if let xml = entries[path] {
                    entries[path] = prefixedSpreadsheetXML(xml)
                }
            }
        }
        if includeDrawingObjects {
            entries["xl/worksheets/_rels/sheet1.xml.rels"] = entries[
                "xl/worksheets/_rels/sheet1.xml.rels"
            ]?.replacingOccurrences(
                of: "</Relationships>",
                with:
                    """
                    <Relationship Id="rIdDrawing1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing1.xml"/>
                    <Relationship Id="rIdPivot1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/pivotTable" Target="../pivotTables/pivotTable1.xml"/>
                    </Relationships>
                    """
            )
            entries["xl/drawings/drawing1.xml"] =
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
                  <xdr:twoCellAnchor><xdr:from><xdr:col>0</xdr:col><xdr:row>0</xdr:row></xdr:from><xdr:to><xdr:col>2</xdr:col><xdr:row>5</xdr:row></xdr:to><xdr:pic><xdr:nvPicPr><xdr:cNvPr id="1" name="원본 이미지" descr="보존 테스트"/></xdr:nvPicPr><xdr:blipFill><a:blip r:embed="rIdImage1"/></xdr:blipFill></xdr:pic><xdr:clientData/></xdr:twoCellAnchor>
                  <xdr:twoCellAnchor><xdr:from><xdr:col>3</xdr:col><xdr:row>0</xdr:row></xdr:from><xdr:to><xdr:col>8</xdr:col><xdr:row>12</xdr:row></xdr:to><xdr:graphicFrame><a:graphic><a:graphicData><c:chart r:id="rIdChart1"/></a:graphicData></a:graphic></xdr:graphicFrame><xdr:clientData/></xdr:twoCellAnchor>
                </xdr:wsDr>
                """
            entries["xl/drawings/_rels/drawing1.xml.rels"] =
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
                  <Relationship Id="rIdImage1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image1.png"/>
                  <Relationship Id="rIdChart1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" Target="../charts/chart1.xml"/>
                </Relationships>
                """
            entries["xl/media/image1.png"] = "ORIGINAL_IMAGE"
            entries["xl/charts/chart1.xml"] = "CHART_KEEP"
            entries["xl/pivotTables/pivotTable1.xml"] = "PIVOT_KEEP"
        }
        if includeCompatibilityMetadata {
            entries["xl/workbook.xml"] = entries["xl/workbook.xml"]?
                .replacingOccurrences(
                    of: "</workbook>",
                    with:
                        """
                        <workbookProtection lockStructure="1" workbookPassword="ABCD"/>
                        <definedNames>
                          <definedName name="_xlnm.Print_Area" localSheetId="0">'연락처'!$A$1:$C$20</definedName>
                          <definedName name="_xlnm.Print_Titles" localSheetId="0">'연락처'!$1:$2</definedName>
                        </definedNames>
                        <externalReferences><externalReference r:id="rIdExternal1"/></externalReferences>
                        </workbook>
                        """
                )
            entries["xl/_rels/workbook.xml.rels"] = entries[
                "xl/_rels/workbook.xml.rels"
            ]?.replacingOccurrences(
                of: "</Relationships>",
                with:
                    """
                    <Relationship Id="rIdExternal1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/externalLink" Target="externalLinks/externalLink1.xml"/>
                    </Relationships>
                    """
            )
            entries["xl/worksheets/sheet1.xml"] = entries[
                "xl/worksheets/sheet1.xml"
            ]?.replacingOccurrences(
                of: "</worksheet>",
                with:
                    """
                    <sheetProtection sheet="1" objects="1" password="CAFE"/>
                    <pageMargins left="0.25" right="0.4" top="0.5" bottom="0.6" header="0.2" footer="0.2"/>
                    <pageSetup orientation="landscape" paperSize="9" fitToWidth="1" fitToHeight="2"/>
                    <headerFooter><oddHeader>보존 머리글</oddHeader></headerFooter>
                    <extLst><ext uri="{opaque}"><opaquePayload value="KEEP"/></ext></extLst>
                    </worksheet>
                    """
            )
            entries["xl/externalLinks/externalLink1.xml"] =
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <externalLink xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><externalBook r:id="rIdSource"/></externalLink>
                """
            entries["xl/externalLinks/_rels/externalLink1.xml.rels"] =
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rIdSource" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/externalLinkPath" Target="file:///Volumes/Shared/source.xlsx" TargetMode="External"/></Relationships>
                """
            entries["customXml/item1.xml"] =
                "<opaque xmlns=\"urn:rivopad:test\">KEEP</opaque>"
        }
        return try makeZIPData(entries: entries)
    }

    private func makeTestImageData(color: UIColor) -> Data {
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: 4, height: 4)
        )
        let image = renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        return image.pngData()!
    }

    private func makeLargeWorkbookData(
        rowCount: Int
    ) throws -> Data {
        precondition(rowCount > ExcelWorkbookDocument.maximumRowsPerSheet)
        var rows = [
            """
            <row r="1">
              <c r="A1" t="inlineStr"><is><t>번호</t></is></c>
              <c r="B1" t="inlineStr"><is><t>내용</t></is></c>
            </row>
            """,
        ]
        rows.reserveCapacity(rowCount)
        for row in 2 ... rowCount {
            let value = row == rowCount
                ? "마지막 검색 대상"
                : "데이터 \(row)"
            rows.append(
                """
                <row r="\(row)">
                  <c r="A\(row)"><v>\(row - 1)</v></c>
                  <c r="B\(row)" t="inlineStr"><is><t>\(value)</t></is></c>
                </row>
                """
            )
        }
        return try makeZIPData(entries: [
            "[Content_Types].xml":
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>
                """,
            "xl/workbook.xml":
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
                  xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
                  <sheets><sheet name="긴 데이터" sheetId="1" r:id="rId1"/></sheets>
                </workbook>
                """,
            "xl/_rels/workbook.xml.rels":
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
                  <Relationship Id="rId1"
                    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet"
                    Target="worksheets/sheet1.xml"/>
                </Relationships>
                """,
            "xl/worksheets/sheet1.xml":
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
                  xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
                  <dimension ref="A1:B\(rowCount)"/>
                  <sheetData>\(rows.joined())</sheetData>
                  <tableParts count="1"><tablePart r:id="rIdTable1"/></tableParts>
                </worksheet>
                """,
            "xl/worksheets/_rels/sheet1.xml.rels":
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
                  <Relationship Id="rIdTable1"
                    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/table"
                    Target="../tables/table1.xml"/>
                </Relationships>
                """,
            "xl/tables/table1.xml":
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <table xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
                  id="1" name="긴데이터" displayName="긴데이터" ref="A1:B\(rowCount)">
                  <autoFilter ref="A1:B\(rowCount)"/>
                  <tableColumns count="2"><tableColumn id="1" name="번호"/><tableColumn id="2" name="내용"/></tableColumns>
                </table>
                """,
        ])
    }

    private func makeCrossSheetWorkbookData() throws -> Data {
        try makeZIPData(entries: [
            "[Content_Types].xml":
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>
                """,
            "xl/workbook.xml":
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="원본" sheetId="1" r:id="rId1"/><sheet name="계산" sheetId="2" r:id="rId2"/></sheets></workbook>
                """,
            "xl/_rels/workbook.xml.rels":
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/></Relationships>
                """,
            "xl/worksheets/sheet1.xml":
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1"><c r="A1"><v>10</v></c></row></sheetData></worksheet>
                """,
            "xl/worksheets/sheet2.xml":
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1"><c r="A1"><f>원본!A1*2</f><v>0</v></c></row></sheetData></worksheet>
                """,
        ])
    }

    private func prefixedSpreadsheetXML(_ source: String) -> String {
        source
            .replacingOccurrences(
                of: #"<(/?)([A-Za-z][A-Za-z0-9]*)\b"#,
                with: "<$1x:$2",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main""#,
                with: #"xmlns:x="http://schemas.openxmlformats.org/spreadsheetml/2006/main""#
            )
    }

    private func makeZIPData(entries: [String: String]) throws -> Data {
        let archive = try Archive(accessMode: .create)
        for (path, string) in entries.sorted(by: { $0.key < $1.key }) {
            let data = Data(string.utf8)
            try archive.addEntry(
                with: path,
                type: .file,
                uncompressedSize: Int64(data.count),
                compressionMethod: .deflate
            ) { position, size in
                let lower = Int(position)
                let upper = min(data.count, lower + size)
                return lower < upper
                    ? data.subdata(in: lower..<upper)
                    : Data()
            }
        }
        return try XCTUnwrap(archive.data)
    }

    private func archiveText(_ path: String, in data: Data) throws -> String {
        let archive = try Archive(data: data, accessMode: .read)
        let entry = try XCTUnwrap(archive[path])
        var extracted = Data()
        _ = try archive.extract(entry) { extracted.append($0) }
        return try XCTUnwrap(String(data: extracted, encoding: .utf8))
    }

    private func archivePaths(in data: Data) throws -> [String] {
        let archive = try Archive(data: data, accessMode: .read)
        return archive.map(\.path).sorted()
    }
}
