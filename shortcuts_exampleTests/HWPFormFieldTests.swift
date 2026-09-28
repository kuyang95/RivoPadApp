import Foundation
import XCTest
@testable import shortcuts_example

final class HWPFormFieldTests: XCTestCase {
    private func fixture() throws -> Data {
        let bundle = Bundle(for: Self.self)
        let url = bundle.url(forResource: "hangul_design_application", withExtension: "hwp")
            ?? bundle.url(forResource: "hangul_design_application", withExtension: "hwp", subdirectory: "HWPXViewerFixtures")
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("HWPXViewerFixtures/hangul_design_application.hwp")
        return try Data(contentsOf: url)
    }

    private func application() throws -> (HWP5StructuredDocument, HWPFormFields) {
        let parsed = try HWP5StructuredDocumentParser.parse(from: fixture())
        return (parsed, HWPFormFields.make(document: HWPAccessibleDocument.make(blocks: parsed.blocks)))
    }

    private func wordBlocks(_ blocks: [HWPDocumentBlock]) -> [WordDocumentBlock] {
        blocks.map { block in
            WordDocumentBlock(id: block.id, paragraphIndex: block.paragraphIndex, text: block.text,
                styleID: nil, isNumbered: false, tableLocation: block.tableLocation.map {
                    WordDocumentTableLocation(table: $0.table, row: $0.row, column: $0.column, paragraph: $0.paragraph)
                }, isEditable: block.isEditable)
        }
    }

    private func snapshot(_ blocks: [HWPDocumentBlock], fields: HWPFormFields,
                          request: String, selection: String? = nil) -> WordAIDocumentSnapshot {
        let word = wordBlocks(blocks)
        return HWPFormAISnapshot.addingFormContext(to: WordAISnapshotBuilder.make(
            documentName: "신청서.hwp", blocks: word, selectedBlockID: selection), allBlocks: word,
            context: fields.context(for: request, selectedBlockID: selection))
    }

    private func block(_ id: String, text: String, table: Int? = 0, row: Int = 0, column: Int = 0,
                       paragraph: Int = 0, span: Int = 1, section: String = "Contents/section0.xml") -> HWPDocumentBlock {
        HWPDocumentBlock(id: id, sectionPath: section, paragraphIndex: paragraph, text: text,
            tableLocation: table.map { HWPDocumentTableLocation(table: $0, row: row, column: column,
                paragraph: paragraph, columnSpan: span) }, isEditable: true)
    }

    private func plan(target: String, text: String = "한글빛", kind: WordAICommandPlan.Operation.Kind = .replaceText) -> WordAICommandPlan {
        WordAICommandPlan(intent: .edit, assistantMessage: "입력 칸의 수정안을 만들었습니다.", operations: [
            .init(kind: kind, blockID: target, newText: kind == .replaceText ? text : nil,
                styleID: kind == .setStyle ? "Heading1" : nil)])
    }

    func testApplicationMapsRealLabelsTo14ValueCellsAndKeepsGroupBoundaries() throws {
        let (parsed, fields) = try application()
        XCTAssertEqual(fields.fields.count, 14)
        let product = try XCTUnwrap(fields.field(for: parsed.blocks[18].id))
        XCTAssertEqual(product.label, "제품명")
        XCTAssertEqual(product.labelBlockIDs, [parsed.blocks[17].id])
        XCTAssertEqual(product.valueBlockIDs, [parsed.blocks[18].id])
        XCTAssertEqual(product.location, "표 1 · 3행 · 2–4열")
        XCTAssertEqual(fields.field(for: parsed.blocks[30].id)?.displayName, "출품자 2 · 소속")
        XCTAssertEqual(fields.field(for: parsed.blocks[32].id)?.displayName, "출품자 2 · 연락처")
        XCTAssertEqual(fields.field(for: parsed.blocks[34].id)?.displayName, "출품자 2 · 이메일")
        XCTAssertEqual(fields.field(for: parsed.blocks[44].id)?.displayName, "주소")
        XCTAssertNil(fields.field(for: parsed.blocks[44].id)?.group)
        XCTAssertFalse(fields.fields.contains { $0.valueBlockIDs.contains(parsed.blocks[6].id) })
        XCTAssertFalse(fields.fields.contains { $0.valueBlockIDs.contains(parsed.blocks[7].id) })
        XCTAssertTrue(fields.fields.allSatisfy(\.isEditable))
    }

    func testKoreanFieldRequestsResolveProductParticipantContactAndAliases() throws {
        let (parsed, fields) = try application()
        let cases: [(String, Int)] = [
            ("제품명을 한글빛으로 바꿔줘", 18),
            ("제품명을 이메일로 바꿔줘", 18),
            ("제품명에 '주소'를 넣어줘", 18),
            ("출품자 1을 홍길동으로 바꿔 줘", 20),
            ("출품자2 성명을 홍길동으로 입력해줘", 28),
            ("출품자 2의 연락처를 010-1234-5678로 바꿔줘", 32),
            ("두 번째 출품자 전화번호를 010-1234-5678로 입력해 줘", 32),
            ("출품자 2의 핸드폰 번호를 010-1234-5678로 바꿔줘", 32),
            ("출품자3 전자우편을 hong@example.com으로 바꿔줘", 42),
            ("표 1의 8행 연락처를 비워줘", 32),
            ("표 1 8행 연락처를 비워줘", 32),
            ("Table 1 Row 8 연락처를 비워줘", 32),
        ]
        for (request, index) in cases {
            let context = fields.context(for: request, selectedBlockID: nil)
            XCTAssertEqual(context.resolution, .resolved, request)
            XCTAssertEqual(context.targetFields.flatMap(\.valueBlockIDs), [parsed.blocks[index].id], request)
        }
    }

    func testDuplicateContactsClarifyAndShortReplyRetainsTheOriginalValue() throws {
        let (parsed, fields) = try application()
        let request = "연락처를 010-1234-5678로 바꿔줘"
        let context = fields.context(for: request, selectedBlockID: parsed.blocks[24].id)
        XCTAssertEqual(context.resolution, .ambiguous)
        XCTAssertEqual(context.targetFields.count, 3)
        XCTAssertTrue(try XCTUnwrap(context.clarificationMessage).contains("출품자 2 · 연락처"))
        for reply in ["출품자 2", "2번", "2번째요", "두 번째", "두번째 출품자", "표 1 8행"] {
            let continued = try XCTUnwrap(context.continuing(request, with: reply))
            XCTAssertTrue(continued.contains("010-1234-5678"))
            let resolved = fields.context(for: continued, selectedBlockID: nil)
            XCTAssertEqual(resolved.resolution, .resolved)
            XCTAssertEqual(resolved.targetFields.first?.valueBlockIDs, [parsed.blocks[32].id])
        }
        XCTAssertNil(context.continuing(request, with: "제품명을 새 이름으로 바꿔줘"))
        let nonexistent = try XCTUnwrap(context.continuing(request, with: "출품자 9"))
        let unsupported = fields.context(for: nonexistent, selectedBlockID: nil)
        XCTAssertEqual(unsupported.resolution, .unsupported)
        let corrected = try XCTUnwrap(unsupported.continuing(nonexistent, with: "출품자 2"))
        XCTAssertEqual(fields.context(for: corrected, selectedBlockID: nil).targetFields.first?.valueBlockIDs,
            [parsed.blocks[32].id])
        XCTAssertEqual(fields.context(for: "출품자를 홍길동으로 바꿔줘", selectedBlockID: nil).resolution, .ambiguous)
        XCTAssertThrowsError(try WordAICommandValidator.validate(plan(target: parsed.blocks[24].id),
            snapshot: snapshot(parsed.blocks, fields: fields, request: request), userRequest: request))
    }

    func testUnknownParticipantOrConflictingCoordinatesNeverFallbackToAnotherPerson() throws {
        let (_, fields) = try application()
        for request in ["출품자 4 연락처를 바꿔줘", "출품자 10 연락처를 바꿔줘",
                        "출품자 2의 5행 연락처를 바꿔줘", "표 3의 제품명을 바꿔줘",
                        "출품자 2 학번을 1234로 바꿔줘"] {
            let context = fields.context(for: request, selectedBlockID: nil)
            XCTAssertEqual(context.resolution, .unsupported, request)
            XCTAssertTrue(context.targetFields.isEmpty)
            XCTAssertNotNil(context.clarificationMessage)
        }
    }

    func testSelectionIsUsedWhenTheUserRefersToTheSelectedField() throws {
        let (parsed, fields) = try application()
        let context = fields.context(for: "선택한 연락처를 비워줘", selectedBlockID: parsed.blocks[32].id)
        XCTAssertEqual(context.resolution, .resolved)
        XCTAssertEqual(context.targetFields.first?.valueBlockIDs, [parsed.blocks[32].id])
        let direct = fields.context(for: "이 칸을 홍길동으로 바꿔줘", selectedBlockID: parsed.blocks[28].id)
        XCTAssertEqual(direct.targetFields.first?.valueBlockIDs, [parsed.blocks[28].id])
    }

    func testValidatorProtectsLabelsOtherParticipantsAndUnsupportedStyles() throws {
        let (parsed, fields) = try application()
        let request = "출품자 2 연락처를 010-1234-5678로 바꿔줘"
        let snapshot = snapshot(parsed.blocks, fields: fields, request: request)
        XCTAssertEqual(snapshot.block(id: parsed.blocks[31].id)?.isEditable, false)
        XCTAssertEqual(snapshot.block(id: parsed.blocks[24].id)?.isEditable, false)
        XCTAssertEqual(snapshot.block(id: parsed.blocks[32].id)?.isEditable, true)
        for index in [17, 18, 24, 31, 40] {
            XCTAssertThrowsError(try WordAICommandValidator.validate(plan(target: parsed.blocks[index].id),
                snapshot: snapshot, userRequest: request), "Wrong target \(index)")
        }
        XCTAssertThrowsError(try WordAICommandValidator.validate(plan(target: parsed.blocks[32].id, kind: .setStyle),
            snapshot: snapshot, userRequest: "출품자 2 연락처를 제목 스타일로 바꿔줘"))
        let accepted = try XCTUnwrap(WordAICommandValidator.validate(
            plan(target: parsed.blocks[32].id, text: "010-1234-5678"), snapshot: snapshot, userRequest: request))
        XCTAssertTrue(accepted.previewLines[0].contains("출품자 2 · 연락처"))
        XCTAssertTrue(accepted.previewLines[0].contains("표 1 · 8행"))
    }

    func testResolvedAIProposalSavesOnlyTheProductValueAndCanBeResolvedAgainAfterReload() throws {
        let data = try fixture()
        let (parsed, fields) = try application()
        let request = "제품명을 한글빛으로 바꿔줘"
        let snapshot = snapshot(parsed.blocks, fields: fields, request: request)
        let target = try XCTUnwrap(snapshot.formContext?.targetFields.first?.valueBlockIDs.first)
        let validated = try XCTUnwrap(WordAICommandValidator.validate(plan(target: target), snapshot: snapshot, userRequest: request))
        var edited = parsed.blocks
        for operation in validated.operations {
            let index = try XCTUnwrap(edited.firstIndex { $0.id == operation.blockID })
            edited[index] = HWPTextRunEditing.replacingText(in: edited[index], with: try XCTUnwrap(operation.newText))
        }
        let saved = try HWP5DocumentRewriter.rewrite(sourceData: data, originalBlocks: parsed.blocks, editedBlocks: edited)
        let reopened = try HWP5StructuredDocumentParser.parse(from: saved)
        XCTAssertEqual(reopened.blocks[18].text, "한글빛")
        XCTAssertEqual(reopened.blocks[17].text, "제품명")
        XCTAssertEqual(reopened.tableCount, 4)
        XCTAssertEqual(reopened.blocks.map(\.tableLocation), parsed.blocks.map(\.tableLocation))
        for index in parsed.blocks.indices where index != 18 { XCTAssertEqual(reopened.blocks[index], parsed.blocks[index]) }
        let newFields = HWPFormFields.make(document: HWPAccessibleDocument.make(blocks: reopened.blocks))
        XCTAssertEqual(newFields.context(for: "제품명을 우리글로 바꿔줘", selectedBlockID: nil)
            .targetFields.first?.valueBlockIDs, [target])
    }

    func testMatchedLabelAndEmptyValueSurviveLongDocumentTruncation() throws {
        var blocks = (0..<700).map { block("body-\($0)", text: "본문 \($0)", table: nil, paragraph: $0) }
        blocks += [block("label", text: "제품명", paragraph: 700),
            block("value", text: "", column: 1, paragraph: 701)]
        let word = wordBlocks(blocks)
        let base = WordAISnapshotBuilder.make(documentName: "긴 신청서", blocks: word, selectedBlockID: nil)
        XCTAssertNil(base.block(id: "value"))
        let fields = HWPFormFields.make(document: HWPAccessibleDocument.make(blocks: blocks))
        let snapshot = HWPFormAISnapshot.addingFormContext(to: base, allBlocks: word,
            context: fields.context(for: "제품명을 한글빛으로 바꿔줘", selectedBlockID: nil))
        XCTAssertNotNil(snapshot.block(id: "label"))
        XCTAssertEqual(snapshot.block(id: "value")?.text, "")
        XCTAssertEqual(snapshot.formContext?.resolution, .resolved)
        XCTAssertTrue(snapshot.contextWasTruncated)
        XCTAssertEqual(snapshot.revision, base.revision)
        XCTAssertLessThanOrEqual(snapshot.blocks.count, WordAISnapshotBuilder.maximumContextBlocks)
    }

    func testSeparateSectionsAndRepeatedLabelsStayDistinctAndProseIsNotAField() {
        let blocks = [block("a-label", text: "연락처"), block("a-value", text: "", column: 1),
            block("b-label", text: "연락처", section: "Contents/section1.xml"),
            block("b-value", text: "", column: 1, section: "Contents/section1.xml"),
            block("prose", text: "개인정보 수집 항목: 성명, 연락처, 이메일", table: 1, row: 0),
            block("space", text: "", table: 1, row: 0, column: 1)]
        let fields = HWPFormFields.make(document: HWPAccessibleDocument.make(blocks: blocks))
        XCTAssertEqual(fields.fields.count, 2)
        XCTAssertEqual(fields.fields.map(\.tableTitle), ["표 1", "표 2"])
        XCTAssertEqual(fields.context(for: "표 2 연락처를 바꿔줘", selectedBlockID: nil)
            .targetFields.first?.valueBlockIDs, ["b-value"])
    }

    func testMultipleParagraphValuesAndHeaderRowsAreNotGuessedAsSingleInputs() {
        let blocks = [block("label", text: "주소"), block("v1", text: "", column: 1),
            block("v2", text: "", column: 1, paragraph: 1),
            block("header1", text: "성명", table: 1), block("header2", text: "연락처", table: 1, column: 1)]
        let fields = HWPFormFields.make(document: HWPAccessibleDocument.make(blocks: blocks))
        XCTAssertEqual(fields.fields.count, 1)
        XCTAssertFalse(fields.fields[0].isEditable)
        XCTAssertEqual(fields.context(for: "주소를 바꿔줘", selectedBlockID: nil).resolution, .unsupported)
    }

    func testQuestionsDoNotTriggerAnEditClarificationAndWordStyleEditingIsUnchanged() throws {
        let (_, fields) = try application()
        let context = fields.context(for: "연락처 입력 칸은 몇 개야?", selectedBlockID: nil)
        // "입력" alone in a question must not turn it into an editing request.
        XCTAssertNil(context.clarificationMessage)
        let word = [WordDocumentBlock(id: "word", paragraphIndex: 0, text: "제목", styleID: nil,
            isNumbered: false, tableLocation: nil, isEditable: true)]
        let snapshot = WordAISnapshotBuilder.make(documentName: "Word", blocks: word, selectedBlockID: nil)
        XCTAssertNil(snapshot.formContext)
        XCTAssertNotNil(try WordAICommandValidator.validate(plan(target: "word", kind: .setStyle),
            snapshot: snapshot, userRequest: "제목 스타일로 바꿔줘"))
    }

    func testOverlappingEmailAddressAliasDoesNotSelectPostalAddress() throws {
        let (_, fields) = try application()
        let context = fields.context(for: "이메일 주소를 hong@example.com으로 바꿔줘", selectedBlockID: nil)
        XCTAssertEqual(context.resolution, .ambiguous)
        XCTAssertEqual(context.targetFields.count, 3)
        XCTAssertTrue(context.targetFields.allSatisfy { $0.label == "이메일" })
    }

    func testAValueThatHappensToBeALabelDoesNotEraseTheFormsFieldMapping() throws {
        let (parsed, _) = try application()
        var blocks = parsed.blocks
        blocks[18] = HWPTextRunEditing.replacingText(in: blocks[18], with: "이메일")
        blocks[20] = HWPTextRunEditing.replacingText(in: blocks[20], with: "성명")
        blocks[22] = HWPTextRunEditing.replacingText(in: blocks[22], with: "소속")
        let fields = HWPFormFields.make(document: HWPAccessibleDocument.make(blocks: blocks))
        XCTAssertEqual(fields.fields.count, 14)
        XCTAssertEqual(fields.context(for: "제품명을 우리글로 바꿔줘", selectedBlockID: nil)
            .targetFields.first?.valueBlockIDs, [blocks[18].id])
    }

    func testASecondClarificationNarrowsTheTableWithoutLosingTheValue() throws {
        let (parsed, _) = try application()
        let second = parsed.blocks.map { old in
            HWPDocumentBlock(id: "copy-" + old.id, sectionPath: "BodyText/Section1",
                paragraphIndex: old.paragraphIndex + 1_000, text: old.text, tableLocation: old.tableLocation,
                isEditable: old.isEditable, presentation: old.presentation)
        }
        let fields = HWPFormFields.make(document: HWPAccessibleDocument.make(blocks: parsed.blocks + second))
        let original = "연락처를 010-1234-5678로 바꿔줘"
        let context = fields.context(for: original, selectedBlockID: nil)
        XCTAssertEqual(context.targetFields.count, 6)
        let groupReply = try XCTUnwrap(context.continuing(original, with: "출품자 2"))
        let narrowed = fields.context(for: groupReply, selectedBlockID: nil)
        XCTAssertEqual(narrowed.resolution, .ambiguous)
        XCTAssertEqual(narrowed.targetFields.count, 2)
        let tableReply = try XCTUnwrap(narrowed.continuing(groupReply, with: "표 5"))
        let resolved = fields.context(for: tableReply, selectedBlockID: nil)
        XCTAssertEqual(resolved.resolution, .resolved)
        XCTAssertEqual(resolved.targetFields.first?.valueBlockIDs, ["copy-" + parsed.blocks[32].id])
        XCTAssertTrue(tableReply.contains("010-1234-5678"))
    }

    func testIncompleteOversizedFieldCannotBeEditedOrRemainSelectedInTheSnapshot() {
        let blocks = [block("label", text: "제품명"),
            block("value", text: String(repeating: "가", count: 80_001), column: 1)]
        let fields = HWPFormFields.make(document: HWPAccessibleDocument.make(blocks: blocks))
        let snapshot = snapshot(blocks, fields: fields, request: "제품명을 바꿔줘", selection: "value")
        XCTAssertNil(snapshot.block(id: "value"))
        XCTAssertNil(snapshot.selectedBlockID)
        XCTAssertEqual(snapshot.formContext?.resolution, .unsupported)
        XCTAssertNotNil(snapshot.formContext?.clarificationMessage)
        XCTAssertTrue(snapshot.formContext?.fields.isEmpty == true)
    }

    #if canImport(UIKit)
    @MainActor
    func testHWPViewModelUsesFieldSnapshotAndSameUndoSavePipeline() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hwp")
        defer { try? FileManager.default.removeItem(at: url) }
        try fixture().write(to: url)
        let model = HWPDocumentViewModel(fileURL: url)
        await model.load()
        let request = "출품자 2 연락처를 010-1234-5678로 바꿔줘"
        let catalog = try XCTUnwrap(model.makeAIRetrievalCatalog(for: request))
        XCTAssertFalse(catalog.requiresRouting)
        let snapshot = try XCTUnwrap(model.makeAISnapshot(for: request, catalog: catalog, retrievalPlan: nil))
        let field = try XCTUnwrap(snapshot.formContext?.targetFields.first)
        XCTAssertEqual(field.displayName, "출품자 2 · 연락처")
        let target = try XCTUnwrap(field.valueBlockIDs.first)
        let validated = try XCTUnwrap(WordAICommandValidator.validate(plan(target: target, text: "010-1234-5678"),
            snapshot: snapshot, userRequest: request))
        try model.applyAIPlan(validated)
        XCTAssertEqual(model.selectedBlockID, target)
        model.undo()
        XCTAssertEqual(model.blocks.first { $0.id == target }?.text, "")
        model.redo()
        await model.save()
        XCTAssertNil(model.errorDescription)
        XCTAssertEqual(try HWP5StructuredDocumentParser.parse(from: Data(contentsOf: url)).blocks[32].text, "010-1234-5678")
    }
    #endif
}
