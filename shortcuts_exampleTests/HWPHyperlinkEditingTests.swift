import XCTest
@testable import shortcuts_example

@MainActor
final class HWPHyperlinkEditingTests: XCTestCase {
    func testSelectionNormalizationAndValidation() throws {
        let package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: "앞 링크 뒤"))
        let block = package.blocks[0]
        let range = (block.text as NSString).range(of: "링크")
        XCTAssertNotNil(HWPHyperlinkEditing.selection(blocks: package.blocks, selectedID: block.id, range: range))
        XCTAssertEqual(HWPHyperlinkEditing.normalizedTarget("example.com/path"), "https://example.com/path")
        XCTAssertNil(HWPHyperlinkEditing.normalizedTarget("javascript:alert(1)"))
    }

    func testHWPXInsertEditAndRemoveRoundTrip() throws {
        var package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: "앞 링크 뒤"))
        let range = (package.blocks[0].text as NSString).range(of: "링크")
        var blocks = package.blocks
        blocks[0] = try HWPHyperlinkEditing.applying(.set("example.com/one"), to: blocks[0], range: range)
        package = try HWPXDocumentPackage.load(from: package.serializedData(applying: blocks))
        XCTAssertEqual(HWPHyperlinkEditing.spans(in: package.blocks[0]), [
            .init(range: range, target: "https://example.com/one")
        ])
        let archive = try HWPXEditingArchive(data: package.sourceData)
        let section = String(decoding: try archive.data(at: package.sectionPaths[0]), as: UTF8.self)
        XCTAssertTrue(section.contains("type=\"HYPERLINK\"")); XCTAssertTrue(section.contains("example.com/one"))

        blocks = package.blocks
        blocks[0] = try HWPHyperlinkEditing.applying(.set("https://example.com/two"), to: blocks[0], range: range)
        package = try HWPXDocumentPackage.load(from: package.serializedData(applying: blocks))
        XCTAssertEqual(HWPHyperlinkEditing.spans(in: package.blocks[0]).first?.target, "https://example.com/two")

        blocks = package.blocks
        blocks[0] = try HWPHyperlinkEditing.applying(.remove, to: blocks[0], range: range)
        package = try HWPXDocumentPackage.load(from: package.serializedData(applying: blocks))
        XCTAssertTrue(HWPHyperlinkEditing.spans(in: package.blocks[0]).isEmpty)
    }

    func testHWPInsertEditAndRemoveRoundTrip() throws {
        var data = try fixture("hangul_design_application", "hwp")
        var document = try HWP5StructuredDocumentParser.parse(from: data)
        let index = try XCTUnwrap(document.blocks.firstIndex { $0.isEditable && $0.text.utf16.count >= 4 })
        let range = NSRange(location: 0, length: 2)
        var blocks = document.blocks
        blocks[index] = try HWPHyperlinkEditing.applying(.set("https://example.com/one"), to: blocks[index], range: range)
        data = try HWP5DocumentRewriter.rewrite(sourceData: data, originalBlocks: document.blocks, editedBlocks: blocks)
        document = try HWP5StructuredDocumentParser.parse(from: data)
        XCTAssertEqual(HWPHyperlinkEditing.spans(in: document.blocks[index]).first?.target, "https://example.com/one")
        XCTAssertTrue(document.blocks[index].isEditable)

        blocks = document.blocks
        blocks[index] = try HWPHyperlinkEditing.applying(.set("https://example.com/two"), to: blocks[index], range: range)
        data = try HWP5DocumentRewriter.rewrite(sourceData: data, originalBlocks: document.blocks, editedBlocks: blocks)
        document = try HWP5StructuredDocumentParser.parse(from: data)
        XCTAssertEqual(HWPHyperlinkEditing.spans(in: document.blocks[index]).first?.target, "https://example.com/two")

        blocks = document.blocks
        blocks[index] = try HWPHyperlinkEditing.applying(.remove, to: blocks[index], range: range)
        data = try HWP5DocumentRewriter.rewrite(sourceData: data, originalBlocks: document.blocks, editedBlocks: blocks)
        document = try HWP5StructuredDocumentParser.parse(from: data)
        XCTAssertTrue(HWPHyperlinkEditing.spans(in: document.blocks[index]).isEmpty)
    }

    private func fixture(_ name: String, _ ext: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        return try Data(contentsOf: XCTUnwrap(bundle.url(forResource: name, withExtension: ext)
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "HWPXViewerFixtures")))
    }
}
