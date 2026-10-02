import RivoDocumentEngine
import XCTest
import SwiftUI
import ZIPFoundation
@testable import shortcuts_example

final class HWPXViewerTests: XCTestCase {
    func testResolvesFontsMixedStylesPaperAndCachedTextPositions() throws {
        let package = try makePackage(body: """
        <hp:p id="1" paraPrIDRef="1" styleIDRef="0"><hp:run charPrIDRef="1"><hp:secPr><hp:pagePr landscape="NARROWLY" width="59528" height="84188"><hp:margin left="3000" right="4000" top="2000" bottom="2000" header="1000" footer="1000"/></hp:pagePr></hp:secPr><hp:t>한글</hp:t><hp:tab/><hp:t>문서</hp:t></hp:run><hp:run charPrIDRef="2"><hp:t>ABC</hp:t></hp:run><hp:linesegarray><hp:lineseg textpos="0" vertpos="2500" vertsize="2000" textheight="1400" baseline="1200" horzpos="500" horzsize="40000" flags="0"/><hp:lineseg textpos="20" vertpos="4500" vertsize="2000" textheight="1000" baseline="850" horzpos="500" horzsize="40000" flags="0"/></hp:linesegarray></hp:p>
        """)
        let block = try XCTUnwrap(package.blocks.first)
        XCTAssertEqual(package.pageLayouts[0].widthPoints, 841.88, accuracy: 0.01)
        XCTAssertEqual(package.pageLayouts[0].leftMarginPoints, 30)
        XCTAssertEqual(block.presentation.alignment, .centered)
        XCTAssertEqual(block.presentation.textRuns.first?.fontName, "바탕")
        XCTAssertEqual(block.presentation.textRuns.first?.fontSizePoints, 14)
        XCTAssertEqual(block.presentation.textRuns.first?.textColorRGB, 0xCC0000)
        XCTAssertEqual(block.presentation.textRuns.first?.isBold, true)
        XCTAssertEqual(block.presentation.textRuns.last?.fontName, "Arial")
        XCTAssertEqual(block.lineLayouts.map(\.text), ["한글\t문서", "ABC"])
        XCTAssertEqual(block.lineLayouts.map(\.verticalPositionPoints), [25, 45])
        XCTAssertEqual(block.lineLayouts.first?.columnStartPoints, 5)
    }

    func testResolvesMergedCellBordersPaddingAndOwningParagraphAnchor() throws {
        let package = try makePackage(body: """
        <hp:p paraPrIDRef="1"><hp:run><hp:tbl pageBreak="CELL" repeatHeader="1"><hp:sz width="30000" height="4000"/><hp:pos treatAsChar="1"/><hp:outMargin left="200" right="300" top="100" bottom="100"/><hp:inMargin left="200" right="300" top="100" bottom="100"/><hp:tr><hp:tc borderFillIDRef="1" hasMargin="0"><hp:subList vertAlign="CENTER"><hp:p><hp:run charPrIDRef="1"><hp:t>병합 셀</hp:t></hp:run><hp:linesegarray><hp:lineseg textpos="0" vertpos="0" horzsize="28000"/></hp:linesegarray></hp:p></hp:subList><hp:cellAddr rowAddr="0" colAddr="0"/><hp:cellSpan rowSpan="2" colSpan="3"/><hp:cellSz width="30000" height="4000"/></hp:tc></hp:tr></hp:tbl></hp:run><hp:linesegarray><hp:lineseg textpos="0" vertpos="8000" vertsize="4000" horzsize="40000"/></hp:linesegarray></hp:p>
        """)
        let cell = try XCTUnwrap(package.blocks.last?.tableLocation)
        XCTAssertEqual(cell.rowSpan, 2)
        XCTAssertEqual(cell.columnSpan, 3)
        XCTAssertEqual(cell.tableAnchor?.verticalPositionPoints, 80)
        XCTAssertEqual(cell.tablePlacement?.widthPoints, 300)
        XCTAssertEqual(cell.cellMarginLeftPoints, 2)
        XCTAssertEqual(cell.cellVerticalAlignment, .center)
        XCTAssertEqual(cell.boxStyle?.backgroundColorRGB, 0xDDEEFF)
        XCTAssertEqual(cell.boxStyle?.bottom.kind, 1)
        XCTAssertEqual(cell.boxStyle?.left.kind, 0)
        let placement = try XCTUnwrap(cell.tablePlacement)
        let offset = placement.inlineOffset(lineWidth: 400, paragraphAlignment: .centered)
        XCTAssertEqual(offset.x, placement.xPoints, accuracy: 0.001,
            "HWPX에서 이미 계산한 정렬과 바깥 여백을 다시 더하면 안 됩니다.")
        XCTAssertEqual(offset.y, 1, accuracy: 0.001)
    }

    @MainActor
    func testUncachedTextWrapsAndContinuesAcrossPages() throws {
        let text = String(repeating: "한글 문서 줄바꿈 확인 문장입니다. ", count: 250)
        let package = try makePackage(body: "<hp:p><hp:run charPrIDRef=\"1\"><hp:t>\(text)</hp:t></hp:run></hp:p>")
        let pages = HWPOriginalCanvasPageBuilder.makePages(blocks: package.blocks, layouts: package.pageLayouts)
        XCTAssertGreaterThan(pages.count, 1)
        let lines = pages.flatMap(\.bodyBlocks).flatMap(\.lineLayouts)
        XCTAssertEqual(lines.map(\.text).joined(), text)
        XCTAssertTrue(lines.allSatisfy { $0.verticalPositionPoints + $0.lineHeightPoints <= 700 })
    }

    @MainActor
    func testExplicitBreakWithNoCacheAndNonSequentialSectionsKeepsSpineOrder() throws {
        let archive = try Archive(accessMode: .create)
        try add("mimetype", data: Data("application/hwp+zip".utf8), to: archive)
        try add("Contents/content.hpf", data: Data("<package><manifest><item id='s9' href='section9.xml'/><item id='s2' href='section2.xml'/></manifest><spine><itemref idref='s9'/><itemref idref='s2'/></spine></package>".utf8), to: archive)
        try add("Contents/section9.xml", data: section("<hp:p><hp:run><hp:t>첫째</hp:t></hp:run></hp:p><hp:p pageBreak='1'><hp:run><hp:t>둘째</hp:t></hp:run></hp:p>"), to: archive)
        try add("Contents/section2.xml", data: section("<hp:p><hp:run><hp:t>셋째</hp:t></hp:run></hp:p>"), to: archive)
        let package = try HWPXDocumentPackage.load(from: XCTUnwrap(archive.data))
        let pages = HWPOriginalCanvasPageBuilder.makePages(blocks: package.blocks, layouts: package.pageLayouts)
        XCTAssertEqual(pages.map { $0.bodyBlocks.map(\.text).joined() }, ["첫째", "둘째", "셋째"])
    }

    func testHeaderFooterAreSeparateFromBodyAndKeepOddEvenScope() throws {
        let package = try makePackage(body: """
        <hp:p><hp:run><hp:ctrl><hp:header applyPageType="ODD"><hp:subList><hp:p><hp:run><hp:t>홀수 머리말</hp:t></hp:run></hp:p></hp:subList></hp:header><hp:footer applyPageType="EVEN"><hp:subList><hp:p><hp:run><hp:t>짝수 꼬리말</hp:t></hp:run></hp:p></hp:subList></hp:footer></hp:ctrl><hp:t>본문</hp:t></hp:run></hp:p>
        """)
        XCTAssertEqual(package.blocks.map(\.region.kind), [.body, .header, .footer])
        XCTAssertEqual(package.blocks[1].region.scope, .oddPages)
        XCTAssertEqual(package.blocks[2].region.scope, .evenPages)
        XCTAssertEqual(package.blocks[0].text, "본문")
    }

    func testHeaderRejectsEntities() throws {
        XCTAssertThrowsError(try makePackage(body: "<hp:p/>", header: "<!DOCTYPE head [<!ENTITY file SYSTEM 'file:///tmp/unrelated'>]><head/>"))
    }

    @MainActor
    func testUncachedTableOwnerRetainsFollowingCachedCellPosition() throws {
        let package = try makePackage(body: """
        <hp:p><hp:run><hp:t>앞 문단</hp:t></hp:run><hp:linesegarray><hp:lineseg textpos="0" vertpos="10000" vertsize="1400" textheight="1400" spacing="700" horzsize="40000"/></hp:linesegarray></hp:p>
        <hp:p><hp:run><hp:tbl><hp:sz width="30000" height="4000"/><hp:pos treatAsChar="1"/><hp:tr><hp:tc><hp:subList><hp:p><hp:run><hp:t>표 셀</hp:t></hp:run><hp:linesegarray><hp:lineseg textpos="0" vertpos="0" horzsize="30000"/></hp:linesegarray></hp:p></hp:subList><hp:cellAddr rowAddr="0" colAddr="0"/><hp:cellSz width="30000" height="4000"/></hp:tc></hp:tr></hp:tbl></hp:run></hp:p>
        """)
        let pages = HWPOriginalCanvasPageBuilder.makePages(blocks: package.blocks, layouts: package.pageLayouts)
        let cell = try XCTUnwrap(pages.first?.bodyBlocks.last?.tableLocation)
        XCTAssertEqual(cell.tableAnchor?.verticalPositionPoints, 121)
        XCTAssertEqual(pages.first?.bodyBlocks.last?.lineLayouts.first?.verticalPositionPoints, 0)
    }

    func testMissingPictureDoesNotHideTheReadableDocument() throws {
        let archive = try Archive(accessMode: .create)
        try add("mimetype", data: Data("application/hwp+zip".utf8), to: archive)
        try add("Contents/content.hpf", data: Data("<package><manifest><item id='image1' href='BinData/missing.png'/></manifest></package>".utf8), to: archive)
        try add("Contents/section0.xml", data: section("<hp:p><hp:run><hp:pic><hp:img binaryItemIDRef='image1'/></hp:pic><hp:t>읽을 수 있는 본문</hp:t></hp:run></hp:p>"), to: archive)
        let package = try HWPXDocumentPackage.load(from: XCTUnwrap(archive.data))
        XCTAssertEqual(package.blocks.first?.text, "읽을 수 있는 본문")
        guard case .unsupported = package.blocks.first?.canvasObjects.first?.content else {
            return XCTFail("Missing images must keep a visible placeholder.")
        }
    }

    @MainActor
    func testOfficialHWPXFivePagesRenderWithTablesAndImage() throws {
        let bundle = Bundle(for: Self.self)
        let url = bundle.url(forResource: "mss_voucher", withExtension: "hwpx")
            ?? bundle.url(forResource: "mss_voucher", withExtension: "hwpx", subdirectory: "HWPXViewerFixtures")
        let package = try HWPXDocumentPackage.load(from: Data(contentsOf: XCTUnwrap(url)))
        let pages = HWPOriginalCanvasPageBuilder.makePages(blocks: package.blocks, layouts: package.pageLayouts)
        XCTAssertEqual(pages.count, 5)
        XCTAssertEqual(package.pageLayouts[0].pageNumberStyle?.text(pageNumber: 3, sectionPageIndex: 2), "- 3 -")
        let bodyText = try XCTUnwrap(package.blocks.first { $0.text.hasPrefix("  중소벤처기업부") })
        XCTAssertFalse(bodyText.presentation.textRuns.contains { $0.isStruckThrough })
        XCTAssertTrue(bodyText.presentation.textRuns.contains { $0.spaceWidthPoints != nil })
        XCTAssertFalse(package.blocks.flatMap(\.images).isEmpty)
        XCTAssertTrue(package.blocks.contains { $0.tableLocation?.boxStyle?.backgroundColorRGB != nil })
        XCTAssertTrue(package.blocks.contains { $0.presentation.textRuns.contains { $0.isBold } })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for page in pages {
            let bounds = CGRect(x: 0, y: 0, width: page.layout.widthPoints, height: page.layout.heightPoints)
            let host = UIHostingController(rootView: HWPOriginalCanvasPageView(page: page))
            host.safeAreaRegions = []
            host.overrideUserInterfaceStyle = .light
            let window = UIWindow(windowScene: scene)
            window.frame = bounds
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.frame = bounds
            host.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            let format = UIGraphicsImageRendererFormat(); format.scale = 2; format.opaque = true
            let image = UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
                host.view.drawHierarchy(in: bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image, quality: .original)
            attachment.name = "hwpx-mss-page-\(page.pageNumber).png"; attachment.lifetime = .keepAlways; add(attachment)
            window.isHidden = true; window.rootViewController = nil
        }
        let details = pages.map { page in
            "Page \(page.pageNumber)\n" + page.bodyBlocks.map { block in
                "\(block.paragraphIndex) [y=\(block.tableLocation?.tableAnchor?.verticalPositionPoints ?? block.lineLayouts.first?.verticalPositionPoints ?? -1)] \(block.text)"
            }.joined(separator: "\n")
        }.joined(separator: "\n\n")
        let attachment = XCTAttachment(data: Data(details.utf8), uniformTypeIdentifier: "public.plain-text")
        attachment.name = "hwpx-mss-pages.txt"; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func makePackage(body: String, header: String? = nil) throws -> HWPXDocumentPackage {
        let archive = try Archive(accessMode: .create)
        try add("mimetype", data: Data("application/hwp+zip".utf8), to: archive)
        try add("Contents/header.xml", data: Data((header ?? Self.header).utf8), to: archive)
        try add("Contents/section0.xml", data: section(body), to: archive)
        return try HWPXDocumentPackage.load(from: XCTUnwrap(archive.data))
    }
    private func section(_ body: String) -> Data {
        Data("<hs:sec xmlns:hs='http://www.hancom.co.kr/hwpml/2011/section' xmlns:hp='http://www.hancom.co.kr/hwpml/2011/paragraph'>\(body)</hs:sec>".utf8)
    }
    private func add(_ path: String, data: Data, to archive: Archive) throws {
        try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { offset, count in
            data.subdata(in: Int(offset)..<min(Int(offset) + count, data.count))
        }
    }
    private static let header = """
    <head><fontfaces><fontface lang="HANGUL"><font id="0" face="바탕"/></fontface><fontface lang="LATIN"><font id="0" face="Arial"/></fontface></fontfaces><charProperties><charPr id="1" height="1400" textColor="#CC0000"><fontRef hangul="0" latin="0"/><bold/></charPr><charPr id="2" height="1000"><fontRef hangul="0" latin="0"/></charPr></charProperties><paraProperties><paraPr id="1"><align horizontal="CENTER"/></paraPr></paraProperties><borderFills><borderFill id="1"><leftBorder type="NONE" width="0.1 mm"/><bottomBorder type="SOLID" width="0.5 mm" color="#112233"/><fillBrush><winBrush faceColor="#DDEEFF"/></fillBrush></borderFill></borderFills></head>
    """
}
