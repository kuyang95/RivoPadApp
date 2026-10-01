import XCTest
@testable import shortcuts_example

@MainActor
final class DocumentAISourceTests: XCTestCase {
    func testSelectionDoesNotReorderOriginalParagraphsOrRewriteWhitespace() throws {
        let blocks = (0..<300).map { index in
            WordDocumentBlock(id: "p\(index)", paragraphIndex: index, text: "  원문 \(index)\n다음 줄  ",
                styleID: nil, isNumbered: false, tableLocation: nil, isEditable: true)
        }
        let catalog = WordAIRetrievalCatalogBuilder.make(documentName: "원문", blocks: blocks, userRequest: "내용 알려줘")
        XCTAssertFalse(catalog.requiresRouting)
        XCTAssertTrue(catalog.sections.isEmpty)
        XCTAssertTrue(catalog.candidates.isEmpty)
        let snapshot = WordAISnapshotBuilder.make(documentName: "원문", blocks: blocks, selectedBlockID: "p200")
        XCTAssertEqual(snapshot.blocks.map(\.id), blocks.map(\.id))
        XCTAssertEqual(snapshot.blocks.map(\.text), blocks.map(\.text))
        XCTAssertFalse(snapshot.contextWasTruncated)
    }

    func testHWPAndHWPXProjectionKeepsBlankMergedAndNestedCells() throws {
        let source = [HWPDocumentBlock(id: "p0", sectionPath: "Contents/section0.xml", paragraphIndex: 0,
            text: "", tableLocation: .init(table: 2, row: 3, column: 4, paragraph: 1, rowSpan: 2, columnSpan: 3,
                parent: .init(table: 0, row: 1, column: 2)), isEditable: true)]
        let snapshot = WordAISnapshotBuilder.make(documentName: "양식.hwpx", blocks: HWPAISource.blocks(source), selectedBlockID: nil)
        XCTAssertNil(snapshot.formContext)
        let block = try XCTUnwrap(snapshot.blocks.first)
        XCTAssertEqual(block.text, "")
        XCTAssertTrue(block.isEditable)
        XCTAssertEqual(block.tableGeometry?.rowSpan, 2)
        XCTAssertEqual(block.tableGeometry?.columnSpan, 3)
        XCTAssertEqual(block.tableGeometry?.parent?.table, 0)
        XCTAssertEqual(block.tableGeometry?.sectionPath, "Contents/section0.xml")
        let json = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        XCTAssertTrue(json.contains("tableGeometry"))
        XCTAssertFalse(json.contains("targetFieldIDs"))
    }

    func testActualHWPSourcePreservesAllParsedTextAndGeometry() throws {
        let blocks = try hwpBlocks()
        let source = HWPAISource.blocks(blocks)
        XCTAssertEqual(source.map(\.text), blocks.map(\.text))
        for (original, projected) in zip(blocks, source) {
            XCTAssertEqual(projected.tableLocation?.rowSpan, original.tableLocation?.rowSpan)
            XCTAssertEqual(projected.tableLocation?.columnSpan, original.tableLocation?.columnSpan)
        }
        let snapshot = WordAISnapshotBuilder.make(documentName: "신청서.hwp", blocks: source, selectedBlockID: source.last?.id)
        XCTAssertFalse(snapshot.contextWasTruncated)
        XCTAssertEqual(snapshot.blocks.map(\.text), blocks.map(\.text))
        XCTAssertNil(snapshot.formContext)
    }

    func testLiveHWPReadsAndEditsUsingOnlyOriginalBlocks() async throws {
        guard ProcessInfo.processInfo.environment["EXCEL_AI_REFERENCE_LIVE"] == "1" else { throw XCTSkip("Explicit live run only") }
        FirebaseRuntime.configureIfAvailable()
        let blocks = try hwpBlocks()
        var snapshot = WordAISnapshotBuilder.make(documentName: "신청서.hwp", blocks: HWPAISource.blocks(blocks), selectedBlockID: nil)
        snapshot.supportedOperations = ["replaceText"]
        let request = "제품명을 별빛 의자로 입력해줘"
        let plan = try await WordAICommandService.plan(userRequest: request, snapshot: snapshot, history: [])
        print("SOURCE_HWP \(plan.intent) \(plan.assistantMessage) \(plan.operations)")
        XCTAssertEqual(plan.intent, .edit, plan.assistantMessage)
        let validated = try XCTUnwrap(WordAICommandValidator.validate(plan, snapshot: snapshot, userRequest: request))
        XCTAssertTrue(validated.operations.contains { $0.newText?.contains("별빛 의자") == true })
        let labels = blocks.filter { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == "제품명" }
        XCTAssertFalse(labels.isEmpty)
        XCTAssertFalse(validated.operations.contains { operation in labels.contains { $0.id == operation.blockID } })
        // Verify the target is the neighboring original table cell, not an unrelated blank.
        let target = try XCTUnwrap(blocks.first { $0.id == validated.operations.first?.blockID }?.tableLocation)
        XCTAssertTrue(labels.contains { $0.tableLocation?.table == target.table && $0.tableLocation?.row == target.row })
    }

    private func hwpBlocks() throws -> [HWPDocumentBlock] {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "hangul_design_application", withExtension: "hwp")
            ?? bundle.url(forResource: "hangul_design_application", withExtension: "hwp", subdirectory: "HWPXViewerFixtures"))
        return try HWP5StructuredDocumentParser.parse(from: Data(contentsOf: url)).blocks
    }
}
