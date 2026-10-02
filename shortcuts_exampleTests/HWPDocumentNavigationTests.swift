import RivoDocumentEngine
import SwiftUI
import UIKit
import XCTest
@testable import shortcuts_example

@MainActor
final class HWPDocumentNavigationTests: XCTestCase {
    private func block(_ text: String, id: String, pageBreak: Bool = false,
                       table: HWPDocumentTableLocation? = nil) -> HWPDocumentBlock {
        HWPDocumentBlock(id: id, sectionPath: "Contents/section0.xml", paragraphIndex: 0,
            text: text, tableLocation: table, isEditable: true,
            presentation: .init(pageBreakBefore: pageBreak))
    }

    func testSearchFindsKoreanAndCaseInsensitiveTextInPageOrderAndWraps() {
        let navigation = HWPDocumentNavigation()
        navigation.update(blocks: [block("한글 신청서 ABC", id: "first"),
            block("다음 쪽의 한글 abc", id: "second", pageBreak: true)], layouts: [])
        XCTAssertEqual(navigation.pages.count, 2)
        navigation.query = "한글"
        XCTAssertEqual(navigation.results.map(\.pageIndex), [0, 1])
        XCTAssertEqual(navigation.selectedResult?.blockID, "first")
        navigation.moveResult(by: -1)
        XCTAssertEqual(navigation.selectedResult?.blockID, "second")
        XCTAssertEqual(navigation.currentPageIndex, 1)
        navigation.moveResult(by: 1)
        XCTAssertEqual(navigation.currentPageIndex, 0)
        navigation.query = "aBc"
        XCTAssertEqual(navigation.results.count, 2)
        navigation.query = "없는말"
        XCTAssertTrue(navigation.results.isEmpty)
        XCTAssertNil(navigation.selectedResult)
    }

    func testSearchUsesEditedTextAndClosesWithoutChangingDocument() {
        let navigation = HWPDocumentNavigation()
        let original = block("변경 전", id: "body")
        navigation.update(blocks: [original], layouts: [])
        navigation.query = "새 내용"
        XCTAssertTrue(navigation.results.isEmpty)
        navigation.update(blocks: [HWPTextRunEditing.replacingText(in: original, with: "새 내용")], layouts: [])
        XCTAssertEqual(navigation.results.count, 1)
        navigation.showsSearch = true
        navigation.closeSearch()
        XCTAssertFalse(navigation.showsSearch)
        XCTAssertTrue(navigation.results.isEmpty)
        XCTAssertEqual(navigation.pages.first?.bodyBlocks.first?.text, "새 내용")
    }

    func testPageJumpValidationAndStaleSearchGeometry() throws {
        let navigation = HWPDocumentNavigation()
        navigation.update(blocks: [block("찾기", id: "a"),
            block("찾기", id: "b", pageBreak: true)], layouts: [])
        XCTAssertNil(navigation.pageNumber(from: "0"))
        XCTAssertNil(navigation.pageNumber(from: "3"))
        XCTAssertNil(navigation.pageNumber(from: "1.5"))
        XCTAssertEqual(navigation.pageNumber(from: " 2 "), 2)
        navigation.query = "찾기"
        let previousSelection = navigation.searchSelectionID
        navigation.moveResult(by: 1)
        let request = navigation.scrollRequest
        navigation.resolveSearchRect(CGRect(x: 100, y: 100, width: 40, height: 20), selectionID: previousSelection)
        XCTAssertEqual(navigation.scrollRequest, request, "Old page preferences cannot move a new search selection")
        navigation.resolveSearchRect(CGRect(x: 100, y: 1_000, width: 40, height: 20), selectionID: navigation.searchSelectionID)
        XCTAssertNotEqual(navigation.scrollRequest, request)
        let resolved = navigation.scrollRequest
        navigation.resolveSearchRect(CGRect(x: 100, y: 2_000, width: 40, height: 20), selectionID: navigation.searchSelectionID)
        XCTAssertEqual(navigation.scrollRequest, resolved, "Scrolling must not trigger a preference feedback loop")
    }

    func testOfficialDocumentSearchIncludesTableCellsOnLastPage() throws {
        let bundle = Bundle(for: Self.self)
        let url = bundle.url(forResource: "mss_voucher", withExtension: "hwpx")
            ?? bundle.url(forResource: "mss_voucher", withExtension: "hwpx", subdirectory: "HWPXViewerFixtures")
        let package = try HWPXDocumentPackage.load(from: Data(contentsOf: XCTUnwrap(url)))
        let navigation = HWPDocumentNavigation()
        navigation.update(blocks: package.blocks, layouts: package.pageLayouts)
        XCTAssertEqual(navigation.pages.count, 5)
        let cell = try XCTUnwrap(navigation.pages[4].bodyBlocks.first {
            $0.tableLocation != nil && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })
        navigation.query = cell.text
        XCTAssertTrue(navigation.results.contains { $0.pageIndex == 4 && $0.blockID == cell.id })
        let layout = navigation.viewport
        XCTAssertEqual(layout.pageIndex(in: layout.pageRects[4]), 4)
        XCTAssertGreaterThan(layout.contentSize.height, layout.pageRects[4].maxY)
    }

    private func controller(size: CGSize = CGSize(width: 635, height: 10_000)) -> HWPDocumentZoomController {
        let controller = HWPDocumentZoomController(contentSize: size)
        controller.loadViewIfNeeded()
        controller.update(contentSize: size, scrollRequest: nil, zoomRequest: nil) { _, _ in AnyView(Color.clear) }
        controller.view.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        return controller
    }

    func testZoomControlsKeepPaperAndCaretCoordinatesStableAcrossRefreshes() throws {
        let size = CGSize(width: 635, height: 10_000)
        let controller = controller(size: size)
        let scroll = controller.scrollView
        let paper = try XCTUnwrap(controller.viewForZooming(in: scroll))
        let input = HWPInlineTextView(frame: CGRect(x: 120, y: 2_000, width: 240, height: 70))
        input.text = "한글 문서"
        input.selectedRange = NSRange(location: 2, length: 0)
        paper.addSubview(input)
        for scale: CGFloat in [2, 0.5, 4, 1, 1.5] {
            let request = HWPDocumentZoomRequest(scale: scale)
            controller.update(contentSize: size, scrollRequest: nil, zoomRequest: request) { _, _ in AnyView(Color.clear) }
            let caret = input.caretRect(for: try XCTUnwrap(input.selectedTextRange).end)
            let onScreen = input.convert(caret, to: scroll)
            let roundTrip = input.convert(onScreen, from: scroll)
            XCTAssertEqual(roundTrip.minX, caret.minX, accuracy: 0.01)
            XCTAssertEqual(roundTrip.minY, caret.minY, accuracy: 0.01)
            XCTAssertEqual(onScreen.height, caret.height * scale, accuracy: 0.01)
            let offset = scroll.contentOffset
            controller.update(contentSize: size, scrollRequest: nil, zoomRequest: request) { _, _ in AnyView(Color.blue) }
            XCTAssertEqual(scroll.contentOffset, offset)
            XCTAssertEqual(paper.bounds.size, size)
            XCTAssertEqual(input.selectedRange, NSRange(location: 2, length: 0))
        }
    }

    func testLastPageJumpClampsOffsetAndFitWidthTracksRotation() throws {
        let size = CGSize(width: 635, height: 10_000)
        let controller = controller(size: size)
        let scroll = controller.scrollView
        controller.update(contentSize: size,
            scrollRequest: .init(rect: CGRect(x: 20, y: 9_700, width: 595, height: 280), alignsPageTop: true),
            zoomRequest: .init(scale: 2)) { _, _ in AnyView(Color.clear) }
        XCTAssertEqual(scroll.contentOffset.y, 19_400 - 40, accuracy: 1)
        XCTAssertLessThanOrEqual(scroll.contentOffset.y, scroll.contentSize.height - scroll.bounds.height)
        controller.update(contentSize: size, scrollRequest: nil, zoomRequest: .init(scale: nil)) { _, _ in AnyView(Color.clear) }
        controller.view.frame.size = CGSize(width: 320, height: 500)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        XCTAssertEqual(scroll.zoomScale, 320 / 635, accuracy: 0.001)
        XCTAssertEqual(scroll.contentSize.width, 320, accuracy: 0.1)
    }

    func testActualCanvasKeepsNativeInputAndMarkedTextThroughPinchRedraw() async throws {
        let original = block("한글 문서", id: "body")
        let navigation = HWPDocumentNavigation()
        let session = HWPInlineEditingSession()
        session.begin(block: original, at: .zero, onSelect: { _ in }, onChange: { _ in }, onCommit: {})
        let host = UIHostingController(rootView:
            HWPOriginalDocumentCanvas(blocks: [original], pageLayouts: [], navigation: navigation)
                .environment(\.hwpInlineEditing, HWPInlineEditingContext(session: session,
                    sources: [original.id: original], activeID: original.id)))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 900))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { session.finish(); window.isHidden = true }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        host.view.layoutIfNeeded()
        XCTAssertEqual(navigation.pages.count, 1)
        let input = try XCTUnwrap(find(HWPInlineTextView.self, in: host.view))
        input.setMarkedText("ㅎ", selectedRange: NSRange(location: 1, length: 0))
        let textBefore = input.text
        let scroll = try XCTUnwrap(findScroll(in: host.view))
        let initialScale = scroll.zoomScale
        let initialFrame = input.convert(input.bounds, to: scroll)
        scroll.setZoomScale(2.5, animated: false)
        scroll.delegate?.scrollViewDidEndZooming?(scroll, with: scroll.delegate?.viewForZooming?(in: scroll), atScale: 2.5)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(find(HWPInlineTextView.self, in: host.view) === input)
        XCTAssertEqual(input.text, textBefore)
        XCTAssertNotNil(input.markedTextRange)
        let enlarged = input.convert(input.bounds, to: scroll)
        XCTAssertEqual(enlarged.width, initialFrame.width * 2.5 / initialScale, accuracy: 0.1)
        XCTAssertEqual(enlarged.height, initialFrame.height * 2.5 / initialScale, accuracy: 0.1)
        let caret = input.caretRect(for: try XCTUnwrap(input.selectedTextRange).end)
        XCTAssertTrue(scroll.bounds.intersects(input.convert(caret, to: scroll)),
            "A zoom must leave the active caret reachable in the viewport")
        let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        })
        attachment.name = "HWP original canvas at 250 percent with native input"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSearchScrollsToHighlightedTableParagraphOnPageFive() async throws {
        let bundle = Bundle(for: Self.self)
        let url = bundle.url(forResource: "mss_voucher", withExtension: "hwpx")
            ?? bundle.url(forResource: "mss_voucher", withExtension: "hwpx", subdirectory: "HWPXViewerFixtures")
        let package = try HWPXDocumentPackage.load(from: Data(contentsOf: XCTUnwrap(url)))
        let navigation = HWPDocumentNavigation()
        let host = UIHostingController(rootView: NavigationStack {
            VStack(spacing: 0) {
                HWPDocumentSearchBar(navigation: navigation)
                HWPOriginalDocumentCanvas(blocks: package.blocks,
                    pageLayouts: package.pageLayouts, navigation: navigation)
                HWPDocumentNavigationControls(navigation: navigation, finishEditing: {})
            }
            .navigationTitle("한글 문서")
        })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 900))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        host.view.layoutIfNeeded()
        let cell = try XCTUnwrap(navigation.pages[4].bodyBlocks.first {
            $0.tableLocation != nil && $0.text.contains("특별지원 지역")
        })
        navigation.query = cell.text
        for _ in navigation.results.indices {
            if navigation.selectedResult?.pageIndex == 4 { break }
            navigation.moveResult(by: 1)
        }
        try await Task.sleep(for: .milliseconds(500))
        let request = try XCTUnwrap(navigation.scrollRequest)
        XCTAssertFalse(request.alignsPageTop, "The actual table paragraph must refine the initial page jump")
        XCTAssertGreaterThan(request.rect.minY, navigation.viewport.pageRects[4].minY)
        let scroll = try XCTUnwrap(findScroll(in: host.view))
        let paper = try XCTUnwrap(scroll.delegate?.viewForZooming?(in: scroll))
        let visible = scroll.convert(scroll.bounds, to: paper)
        XCTAssertTrue(visible.intersects(request.rect))
        let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        })
        attachment.name = "HWP page 5 search highlight and navigation controls"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func find<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
        if let result = view as? T { return result }
        for child in view.subviews { if let result = find(type, in: child) { return result } }
        return nil
    }

    private func findScroll(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView, scroll.accessibilityIdentifier == "hwp-document-scroll" { return scroll }
        for child in view.subviews { if let result = findScroll(in: child) { return result } }
        return nil
    }
}
