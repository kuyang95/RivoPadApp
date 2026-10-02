import RivoDocumentEngine
import XCTest
@testable import shortcuts_example

@MainActor
final class HWPNoteEditingTests: XCTestCase {
    func testSelectionRequiresEditableBodyCaret() throws {
        let package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: "본문"))
        let block = package.blocks[0]
        let insertion = HWPNoteEditing.insertion(blocks: package.blocks, selectedID: block.id,
            range: NSRange(location: 1, length: 0))
        XCTAssertEqual(insertion?.caret, 1)
        XCTAssertNil(HWPNoteEditing.insertion(blocks: package.blocks, selectedID: nil,
            range: NSRange(location: 0, length: 0)))
        XCTAssertThrowsError(try HWPNoteEditing.validatedText(String(repeating: "가", count: 2_001)))
    }

    func testHWPXInsertUpdateDeleteRoundTrip() async throws {
        var source = HWPTableStructureDocument.hwpx(
            try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: "앞 뒤")))
        let originalBody = source.blocks.filter { $0.region.kind == .body }.map(\.text)
        let host = try XCTUnwrap(source.blocks.first)
        let insertion = try XCTUnwrap(HWPNoteEditing.insertion(blocks: source.blocks, selectedID: host.id,
            range: NSRange(location: 1, length: 0)))
        var result = try await HWPNoteEditing.applying(.insert(.footNote, "첫 각주", insertion),
            source: source, drafts: source.blocks, selectedID: host.id)
        source = result.document
        XCTAssertEqual(source.blocks.filter { $0.region.kind == .body }.map(\.text), originalBody)
        XCTAssertEqual(source.blocks.filter { $0.region.kind == .footnote }.map(\.text), ["첫 각주"])

        var selection = HWPNoteEditing.selection(blocks: source.blocks,
            sectionPath: source.blocks[0].sectionPath, insertion: nil)
        var note = try XCTUnwrap(selection.notes.first)
        result = try await HWPNoteEditing.applying(.update(note, "고친 각주"),
            source: source, drafts: source.blocks, selectedID: result.focusedID)
        source = result.document
        XCTAssertEqual(source.blocks.filter { $0.region.kind == .footnote }.map(\.text), ["고친 각주"])

        selection = HWPNoteEditing.selection(blocks: source.blocks,
            sectionPath: source.blocks[0].sectionPath, insertion: nil)
        note = try XCTUnwrap(selection.notes.first)
        result = try await HWPNoteEditing.applying(.delete(note), source: source,
            drafts: source.blocks, selectedID: result.focusedID)
        XCTAssertTrue(result.document.blocks.allSatisfy { $0.region.kind != .footnote })
        XCTAssertEqual(result.document.blocks.filter { $0.region.kind == .body }.map(\.text), originalBody)
    }

    func testHWPInsertUpdateDeleteRoundTrip() async throws {
        let data = try fixture("hangul_design_application", "hwp")
        var source = try HWPTableStructureDocument.load(data)
        let originalBody = source.blocks.filter { $0.region.kind == .body }.map(\.text)
        let host = try XCTUnwrap(source.blocks.first(where: {
            $0.isEditable && !$0.text.isEmpty && $0.region.kind == .body && $0.tableLocation == nil
                && $0.layoutContainerID == nil && $0.canvasObjects.isEmpty
        }))
        let insertion = try XCTUnwrap(HWPNoteEditing.insertion(blocks: source.blocks, selectedID: host.id,
            range: NSRange(location: min(1, host.text.utf16.count), length: 0)))
        var result = try await HWPNoteEditing.applying(.insert(.endNote, "첫 미주", insertion),
            source: source, drafts: source.blocks, selectedID: host.id)
        source = result.document
        XCTAssertEqual(source.blocks.filter { $0.region.kind == .body }.map(\.text), originalBody)
        XCTAssertEqual(source.blocks.filter { $0.region.kind == .endnote }.map(\.text), ["첫 미주"])

        var selection = HWPNoteEditing.selection(blocks: source.blocks,
            sectionPath: host.sectionPath, insertion: nil)
        var note = try XCTUnwrap(selection.notes.first(where: { $0.kind == .endNote }))
        result = try await HWPNoteEditing.applying(.update(note, "고친 미주"),
            source: source, drafts: source.blocks, selectedID: result.focusedID)
        source = result.document
        XCTAssertEqual(source.blocks.filter { $0.region.kind == .endnote }.map(\.text), ["고친 미주"])

        selection = HWPNoteEditing.selection(blocks: source.blocks,
            sectionPath: host.sectionPath, insertion: nil)
        note = try XCTUnwrap(selection.notes.first(where: { $0.kind == .endNote }))
        result = try await HWPNoteEditing.applying(.delete(note), source: source,
            drafts: source.blocks, selectedID: result.focusedID)
        XCTAssertTrue(result.document.blocks.allSatisfy { $0.region.kind != .endnote })
        XCTAssertEqual(result.document.blocks.filter { $0.region.kind == .body }.map(\.text), originalBody)
    }

    func testHWPInsertIntoEmptyParagraph() async throws {
        let data = try fixture("hangul_design_application", "hwp")
        let source = try HWPTableStructureDocument.load(data)
        let originalBody = source.blocks.filter { $0.region.kind == .body }.map(\.text)
        let host = try XCTUnwrap(source.blocks.first(where: {
            $0.isEditable && $0.text.isEmpty && $0.region.kind == .body && $0.tableLocation == nil
                && $0.layoutContainerID == nil && $0.canvasObjects.isEmpty
        }))
        let insertion = try XCTUnwrap(HWPNoteEditing.insertion(blocks: source.blocks,
            selectedID: host.id, range: NSRange(location: 0, length: 0)))
        let result = try await HWPNoteEditing.applying(.insert(.footNote, "빈 문단 각주", insertion),
            source: source, drafts: source.blocks, selectedID: host.id)
        XCTAssertEqual(result.document.blocks.filter { $0.region.kind == .body }.map(\.text), originalBody)
        XCTAssertEqual(result.document.blocks.filter { $0.region.kind == .footnote }.map(\.text), ["빈 문단 각주"])
    }

    private func fixture(_ name: String, _ ext: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        return try Data(contentsOf: XCTUnwrap(bundle.url(forResource: name, withExtension: ext)
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "HWPXViewerFixtures")))
    }
}
