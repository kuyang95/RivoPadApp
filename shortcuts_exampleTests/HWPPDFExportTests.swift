import PDFKit
import UIKit
import Vision
import XCTest
@testable import shortcuts_example

@MainActor final class HWPPDFExportTests: XCTestCase {
    func testRenderedPDFContainsBodyHeaderFooterAndPageNumber() async throws {
        var source = try HWPTableStructureDocument.load(LegacyHWPXConverter.convert(text: "PDF 출력 테스트\n본문 내용 12345"))
        source = try await HWPHeaderFooterEditing.applying(.init(kind: .header, texts: ["머리말 제목"], sections: [0], alignment: .centered), source: source, drafts: source.blocks)
        source = try await HWPHeaderFooterEditing.applying(.init(kind: .footer, texts: ["꼬리말 안내"], sections: [0]), source: source, drafts: source.blocks)
        source = try await HWPPageNumberEditing.applying(.init(style: .init(position: "BOTTOM_CENTER", sideCharacter: "-", startsAt: 7), sections: [0]), source: source, drafts: source.blocks)
        var progress: [Int] = []
        let asset = try await HWPPDFRenderer.render(.init(title: "출력 검증", blocks: source.blocks, layouts: source.layouts)) { current, _ in progress.append(current) }
        let pdf = try XCTUnwrap(PDFDocument(url: asset.url)); XCTAssertEqual(pdf.pageCount, 1); XCTAssertEqual(progress, [0, 1])
        let page = try XCTUnwrap(pdf.page(at: 0)); XCTAssertEqual(page.bounds(for: .mediaBox).width, source.layouts[0].widthPoints, accuracy: 0.01)
        let text = try recognize(page)
        XCTAssertTrue(text.contains("PDF"), text); XCTAssertTrue(text.contains("12345"), text)
        XCTAssertTrue(text.contains("머리말"), text); XCTAssertTrue(text.contains("꼬리말"), text); XCTAssertTrue(text.contains("7"), text)
        try attach(asset, name: "header-footer-number")
    }
    func testMixedPaperSizesTablesAndColorsArePreserved() async throws {
        let base = try HWPTableStructureDocument.load(LegacyHWPXConverter.convert(text: "가로 세로 출력\n표 아래 본문"))
        let selection = try XCTUnwrap(HWPTableInsertion.selection(blocks: base.blocks, selectedID: base.blocks[0].id,
            range: .init(location: base.blocks[0].text.utf16.count, length: 0), layouts: base.layouts))
        let table = try await HWPTableInsertion.applying(.init(selection: selection, rows: 2, columns: 2), source: base, drafts: base.blocks)
        var drafts = table.document.blocks
        let i = try XCTUnwrap(drafts.firstIndex { $0.tableLocation != nil })
        drafts[i] = HWPTextRunEditing.replacingText(in: drafts[i], with: "표 안 글자 56789")
        var style = HWPCellFormat(try XCTUnwrap(drafts[i].tableLocation)); style.setFill(0xFFF2CC)
        drafts[i] = HWPCellFormatting.apply(style, to: drafts[i])
        let data = try table.document.serialized(drafts), archive = try HWPXEditingArchive(data: data)
        let manifest = "<opf:package xmlns:opf=\"http://www.idpf.org/2007/opf\"><opf:manifest><opf:item id=\"first\" href=\"section0.xml\"/><opf:item id=\"second\" href=\"section7.xml\"/></opf:manifest><opf:spine><opf:itemref idref=\"first\"/><opf:itemref idref=\"second\"/></opf:spine></opf:package>"
        let doubled = try HWPTableStructureDocument.load(archive.repack(replacing: ["Contents/section7.xml": archive.data(at: "Contents/section0.xml"), "Contents/content.hpf": Data(manifest.utf8)]))
        var settings = HWPPageSettings(doubled.layouts[1]); settings.orient(landscape: true)
        let source = try await HWPPageSetup.applying(.init(settings: settings, sections: [7]), source: doubled, drafts: doubled.blocks)
        let asset = try await HWPPDFRenderer.render(.init(title: "가로 세로 표 출력", blocks: source.blocks, layouts: source.layouts))
        let pdf = try XCTUnwrap(PDFDocument(url: asset.url)); XCTAssertEqual(pdf.pageCount, 2)
        for index in 0..<2 {
            let page = try XCTUnwrap(pdf.page(at: index)), layout = source.layouts[index]
            XCTAssertEqual(page.bounds(for: .mediaBox).width, layout.widthPoints, accuracy: 0.02)
            XCTAssertEqual(page.bounds(for: .mediaBox).height, layout.heightPoints, accuracy: 0.02)
            // This fixture puts the first cell at (85, 132) pt. Inspect its
            // text separately: Vision may skip a colored cell in a full page.
            let text = try recognize(page, crop: CGRect(x: 90, y: 134, width: 205, height: 22))
            XCTAssertTrue(text.contains("56789"), "Page \(index + 1): \(text)")
        }
        try attach(asset, name: "mixed-paper-tables")
    }
    func testCancellationBetweenPagesRemovesPartialOutput() async throws {
        let base = try HWPTableStructureDocument.load(LegacyHWPXConverter.convert(text: "첫 쪽\n둘째 쪽"))
        var blocks = base.blocks
        var style = blocks[1].presentation; style.pageBreakBefore = true
        blocks[1] = HWPDocumentFormatting.replacingPresentation(of: blocks[1], with: style)
        func files() throws -> Set<String> { Set(try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path).filter { $0.hasPrefix("HWP-PDF-") }) }
        let before = try files()
        var task: Task<HWPPDFAsset, Error>?
        task = Task {
            try await HWPPDFRenderer.render(.init(title: "중간 취소", blocks: blocks, layouts: base.layouts)) { current, _ in
                if current == 1 { task?.cancel() }
            }
        }
        do { _ = try await task?.value; XCTFail("Must cancel") } catch { XCTAssertTrue(error is CancellationError) }
        task = nil; XCTAssertEqual(try files(), before)
    }
    func testReadOnlyHWPFormsRenderAllOriginalPages() async throws {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "hangul_design_application", withExtension: "hwp") ?? bundle.url(forResource: "hangul_design_application", withExtension: "hwp", subdirectory: "HWPXViewerFixtures"))
        let data = try Data(contentsOf: url), source = try HWPTableStructureDocument.load(data)
        let count = HWPOriginalCanvasPageBuilder.makePages(blocks: source.blocks, layouts: source.layouts).count
        let asset = try await HWPPDFRenderer.render(.init(title: "한글 신청서", blocks: source.blocks, layouts: source.layouts))
        let document = try XCTUnwrap(PDFDocument(url: asset.url)); XCTAssertEqual(document.pageCount, count)
        XCTAssertTrue(try recognize(XCTUnwrap(document.page(at: 0))).contains("신청서"))
        XCTAssertEqual(try Data(contentsOf: url), data)
        try attach(asset, name: "hwp-form")
    }
    func testInvalidEmptyAndCancelledOutputAndSafeFilename() async throws {
        XCTAssertEqual(HWPPDFRenderer.filename(" /제목:내용\\"), "제목 내용.pdf")
        let base = try HWPTableStructureDocument.load(LegacyHWPXConverter.convert(text: "본문"))
        do { _ = try await HWPPDFRenderer.render(.init(title: "빈 문서", blocks: [], layouts: [])); XCTFail("Empty output") }
        catch { XCTAssertTrue(error is HWPPDFError) }
        let task = Task { try await HWPPDFRenderer.render(.init(title: "취소", blocks: base.blocks, layouts: base.layouts)) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled output") } catch { XCTAssertTrue(error is CancellationError) }
    }
    func testOutputFileAndTemporaryCleanup() async throws {
        let source = try HWPTableStructureDocument.load(LegacyHWPXConverter.convert(text: "임시 출력"))
        var asset: HWPPDFAsset? = try await HWPPDFRenderer.render(.init(title: "임시 출력", blocks: source.blocks, layouts: source.layouts))
        let url = try XCTUnwrap(asset?.url)
        XCTAssertNotNil(PDFDocument(url: url)); XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        asset = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
    func testViewModelPDFIncludesPendingInputAndPreservesDirtyUndoAndOriginalFile() async throws {
        let data = try LegacyHWPXConverter.convert(text: "원본 본문")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hwpx")
        try data.write(to: url); defer { try? FileManager.default.removeItem(at: url) }
        let model = HWPDocumentViewModel(fileURL: url); await model.load()
        model.selectBlock(try XCTUnwrap(model.blocks.first).id); model.editorText = "저장 전 PDF 수정 98765"
        let snapshot = try model.outputSnapshot()
        XCTAssertTrue(model.hasUnsavedChanges); XCTAssertTrue(model.canUndo)
        XCTAssertEqual(snapshot.blocks.first?.text, "저장 전 PDF 수정 98765")
        let asset = try await HWPPDFRenderer.render(snapshot)
        let page = try XCTUnwrap(PDFDocument(url: asset.url)?.page(at: 0))
        XCTAssertTrue(try recognize(page).contains("98765"))
        XCTAssertEqual(try Data(contentsOf: url), data); XCTAssertTrue(model.hasUnsavedChanges)
        model.undo(); XCTAssertFalse(model.hasUnsavedChanges); XCTAssertEqual(model.blocks.first?.text, "원본 본문")
        XCTAssertEqual(snapshot.blocks.first?.text, "저장 전 PDF 수정 98765")
    }
    private func recognize(_ page: PDFPage, crop: CGRect? = nil) throws -> String {
        let bounds = page.bounds(for: .mediaBox)
        let size = bounds.width > bounds.height ? CGSize(width: 2100, height: 1500) : CGSize(width: 1500, height: 2100)
        let image = page.thumbnail(of: size, for: .mediaBox)
        var pixels = try XCTUnwrap(image.cgImage)
        if let crop {
            let scale = CGFloat(pixels.width) / bounds.width
            pixels = try XCTUnwrap(pixels.cropping(to: crop.applying(CGAffineTransform(scaleX: scale, y: scale))))
        }
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.recognitionLanguages = ["ko-KR", "en-US"]
        try VNImageRequestHandler(cgImage: pixels).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
    private func attach(_ asset: HWPPDFAsset, name: String) throws {
        let attachment = XCTAttachment(data: try Data(contentsOf: asset.url), uniformTypeIdentifier: "com.adobe.pdf")
        attachment.name = name + ".pdf"; attachment.lifetime = .keepAlways; add(attachment)
        // Keep standalone QA PDFs for independent Poppler inspection.
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("PDF-QA", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(contentsOf: asset.url).write(to: directory.appendingPathComponent(name + ".pdf"))
    }
}
