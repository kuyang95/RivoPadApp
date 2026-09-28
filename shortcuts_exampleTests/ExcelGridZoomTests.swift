import SwiftUI
import UIKit
import XCTest
@testable import shortcuts_example

@MainActor
final class ExcelGridZoomTests: XCTestCase {
    private let documentSize = CGSize(width: 4_000, height: 18_000)

    func testReferenceAfterRow400UsesItsOriginalWorksheetRow() throws {
        var workbook = try ExcelWorkbookDocument.load(from: ExcelWorkbookDocument.blankWorkbookData())
        workbook.sheets[0].maximumRow = 701
        let grid = ExcelGridView(sheet: workbook.sheets[0], workbook: workbook,
            regions: [], visibleRows: nil, selectedAddress: nil,
            onSelect: { _ in }, onEdit: { _ in }, revealAddress: .init(row: 695, column: 2))
        XCTAssertEqual(grid.cellAddress(at: CGPoint(x: 60, y: 50)), .init(row: 401, column: 1))
    }

    func testReferenceRevealAtZoomAndOrdinaryRedrawDoesNotSnapBack() throws {
        let controller = controller()
        controller.update(contentSize: documentSize, zoomScale: 2) { _, _ in .clear }
        let target = CGRect(x: 1_100, y: 12_000, width: 100, height: 44)
        controller.requestReveal(target)
        let scroll = controller.scrollView
        let zoomContent = try XCTUnwrap(controller.viewForZooming(in: scroll))
        XCTAssertTrue(scroll.convert(scroll.bounds, to: zoomContent).contains(target))
        scroll.contentOffset = CGPoint(x: 500, y: 1_000)
        controller.requestReveal(target)
        XCTAssertEqual(scroll.contentOffset, CGPoint(x: 500, y: 1_000))
    }

    func testCellTapMappingUsesVisibleRowsAndOriginalColumnWidths() throws {
        let workbook = try ExcelWorkbookDocument.load(from: ExcelWorkbookDocument.blankWorkbookData())
        let source = try XCTUnwrap(workbook.sheets.first)
        let sheet = ExcelWorksheet(
            id: source.id, name: source.name, partPath: source.partPath,
            cells: [:], mergedRanges: [], tables: [],
            columnWidths: [1: 10, 2: 30], rowHeights: [4: 80],
            maximumRow: 30, maximumColumn: 8, didTruncate: false
        )
        let grid = ExcelGridView(
            sheet: sheet, workbook: workbook, regions: [], visibleRows: [4, 10, 30],
            selectedAddress: nil, onSelect: { _ in }, onEdit: { _ in }
        )
        XCTAssertEqual(grid.cellAddress(at: CGPoint(x: 60, y: 50)), .init(row: 4, column: 1))
        XCTAssertEqual(grid.cellAddress(at: CGPoint(x: 150, y: 170)), .init(row: 10, column: 2))
        XCTAssertEqual(grid.cellAddress(at: CGPoint(x: 360, y: 210)), .init(row: 30, column: 2))
        XCTAssertNil(grid.cellAddress(at: CGPoint(x: 27, y: 50)), "Row headers are not cells")
        XCTAssertNil(grid.cellAddress(at: CGPoint(x: 150, y: 20)), "Column headers are not cells")
        XCTAssertNil(grid.cellAddress(at: CGPoint(x: 150, y: 400)), "The notice below the rows is not a cell")
        XCTAssertNil(grid.cellAddress(at: CGPoint(x: 9_000, y: 50)))
    }

    private func controller(
        content: @escaping (CGRect) -> Color = { _ in .clear }
    ) -> ExcelZoomScrollController<Color> {
        let controller = ExcelZoomScrollController(
            contentSize: documentSize,
            zoomRange: 0.5 ... 3,
            content: { rect, _ in content(rect) }
        )
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        return controller
    }

    func testRepeatedZoomPreservesContentBoundsAndViewportCenter() throws {
        let controller = controller()
        let scroll = controller.scrollView
        let content = try XCTUnwrap(controller.viewForZooming(in: scroll))
        scroll.contentOffset = CGPoint(x: 1_200, y: 6_000)
        let center = scroll.convert(CGPoint(x: scroll.bounds.midX, y: scroll.bounds.midY), to: content)

        for scale: CGFloat in [2, 0.5, 3, 1, 1.75, 0.75, 2.5, 1] {
            controller.update(contentSize: documentSize, zoomScale: scale) { _, _ in .clear }
            controller.view.layoutIfNeeded()
            let current = scroll.convert(CGPoint(x: scroll.bounds.midX, y: scroll.bounds.midY), to: content)
            XCTAssertEqual(current.x, center.x, accuracy: 1)
            XCTAssertEqual(current.y, center.y, accuracy: 1)
            XCTAssertEqual(content.bounds.size, documentSize)
            XCTAssertEqual(content.frame.minX, 0, accuracy: 0.1)
            XCTAssertEqual(content.frame.minY, 0, accuracy: 0.1)
            XCTAssertEqual(scroll.zoomScale, scale, accuracy: 0.001)
            XCTAssertEqual(scroll.contentSize.height, documentSize.height * scale, accuracy: 1)
        }
    }

    func testContentRefreshAfterZoomDoesNotMoveSelectedCell() throws {
        let controller = controller()
        let scroll = controller.scrollView
        scroll.contentOffset = CGPoint(x: 800, y: 4_000)
        controller.update(contentSize: documentSize, zoomScale: 2) { _, _ in .clear }
        let offset = scroll.contentOffset
        let content = try XCTUnwrap(controller.viewForZooming(in: scroll))
        let bounds = content.bounds
        for _ in 0 ..< 20 {
            controller.update(contentSize: documentSize, zoomScale: 2) { _, _ in .blue }
            controller.view.layoutIfNeeded()
            XCTAssertEqual(scroll.contentOffset, offset)
            XCTAssertEqual(content.bounds, bounds)
            XCTAssertEqual(scroll.zoomScale, 2)
        }
    }

    func testVisibleRowsAreBufferedAndBottomRemainsReachableAfterZoom() throws {
        var rendered = [CGRect]()
        let controller = controller { rect in
            rendered.append(rect)
            return .clear
        }
        let scroll = controller.scrollView
        let initialCount = rendered.count
        for y in 1 ... 100 {
            scroll.contentOffset = CGPoint(x: 0, y: y)
        }
        XCTAssertEqual(rendered.count, initialCount, "Small pans should reuse the mounted rows")

        controller.update(contentSize: documentSize, zoomScale: 0.5) { rect, _ in
            rendered.append(rect)
            return .clear
        }
        scroll.contentOffset = CGPoint(x: 0, y: scroll.contentSize.height - scroll.bounds.height)
        let last = try XCTUnwrap(rendered.last)
        XCTAssertEqual(last.maxY, documentSize.height, accuracy: 1)
        XCTAssertLessThan(last.height, documentSize.height / 4, "Only nearby rows should be mounted")
    }

    func testPinchEndRedrawPreservesViewportAndCellHitCoordinates() throws {
        let controller = controller()
        let scroll = controller.scrollView
        let target = try XCTUnwrap(controller.viewForZooming(in: scroll))
        let drawingView = try XCTUnwrap(target.subviews.first)
        for scale: CGFloat in [3, 0.5, 2.25] {
            scroll.setZoomScale(scale, animated: false)
            scroll.contentOffset = CGPoint(x: 400, y: 2_000)
            let offset = scroll.contentOffset
            let cell = scroll.convert(CGPoint(x: scroll.bounds.midX, y: scroll.bounds.midY), to: target)
            let position = target.convert(cell, to: scroll)
            controller.scrollViewDidEndZooming(scroll, with: target, atScale: scale)
            controller.view.layoutIfNeeded()
            let drawScale = max(1, scale)
            let drawnPosition = drawingView.convert(
                CGPoint(x: cell.x * drawScale, y: cell.y * drawScale), to: scroll
            )
            XCTAssertEqual(scroll.contentOffset, offset)
            XCTAssertEqual(target.bounds.size, documentSize)
            XCTAssertEqual(drawnPosition.x, position.x, accuracy: 0.01)
            XCTAssertEqual(drawnPosition.y, position.y, accuracy: 0.01)
        }
    }

    func testRealGridRendersAcrossZoomRange() async throws {
        let original = try ExcelWorkbookDocument.blankWorkbookData()
        var workbook = try ExcelWorkbookDocument.load(from: original)
        var sheet = try XCTUnwrap(workbook.sheets.first)
        // Exercise the full grid limit: the enlarged host must remain viable
        // even when the document is much larger than the visible viewport.
        // Populate the model directly; bulk XML writing is outside this UI test.
        for row in 1 ... 400 {
            for column in 1 ... 40 {
                let address = ExcelCellAddress(row: row, column: column)
                let value = "R\(row)C\(column)"
                sheet.cells[address] = ExcelCell(
                    address: address, rawValue: value, displayValue: value,
                    formula: nil, styleIndex: nil, cellType: "inlineStr"
                )
            }
        }
        sheet.maximumRow = 400
        sheet.maximumColumn = 40
        workbook.sheets[0] = sheet
        let grid = ExcelGridView(
            sheet: sheet, workbook: workbook, regions: [], visibleRows: nil,
            selectedAddress: .init(row: 1, column: 1), onSelect: { _ in }, onEdit: { _ in }
        )
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1_000, height: 700)
        let host = UIHostingController(rootView: grid)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(300))
        window.layoutIfNeeded()
        let scroll = try XCTUnwrap(findScrollView(in: host.view))
        let content = try XCTUnwrap(scroll.delegate?.viewForZooming?(in: scroll))
        let originalBounds = content.bounds
        XCTAssertGreaterThan(originalBounds.height, 17_000)

        var beforeRedraw: UIImage?
        for scale: CGFloat in [1, 3, 0.5] {
            scroll.setZoomScale(scale, animated: false)
            scroll.contentOffset = .zero
            if scale == 3 {
                try await Task.sleep(for: .milliseconds(250))
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                beforeRedraw = image
                let attachment = XCTAttachment(image: image)
                attachment.name = "Excel-300-before-redraw"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            // Programmatic zoom does not emit the pinch-end notification;
            // exercise the same scale handoff used when the fingers lift.
            scroll.delegate?.scrollViewDidEndZooming?(scroll, with: content, atScale: scale)
            try await Task.sleep(for: .milliseconds(250))
            window.layoutIfNeeded()
            XCTAssertEqual(content.bounds, originalBounds)
            XCTAssertEqual(scroll.contentOffset.x, 0, accuracy: 1)
            XCTAssertEqual(scroll.contentOffset.y, 0, accuracy: 1)
            XCTAssertEqual(scroll.zoomScale, scale, accuracy: 0.001)
            XCTAssertNotNil(scroll.pinchGestureRecognizer)
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            if scale == 3, let beforeRedraw {
                // Compare actual rendered glyph edges, not just scale settings.
                XCTAssertGreaterThan(
                    try textEdgeEnergy(image), try textEdgeEnergy(beforeRedraw) * 1.2,
                    "300% text should be redrawn sharply, not stretch the 100% raster"
                )
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Excel-native-zoom-\(Int(scale * 100))"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func findScrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.findScrollView(in: $0) }.first
    }

    private func textEdgeEnergy(_ image: UIImage) throws -> Double {
        let source = try XCTUnwrap(image.cgImage)
        // Exclude the toolbar and screen edges; this region contains grid text.
        let crop = CGRect(
            x: Double(source.width) * 0.2, y: Double(source.height) * 0.2,
            width: Double(source.width) * 0.6, height: Double(source.height) * 0.55
        ).integral
        let sample = try XCTUnwrap(source.cropping(to: crop))
        let width = sample.width
        let height = sample.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ))
            context.draw(sample, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var energy = 0.0
        for y in 0 ..< height {
            for x in 1 ..< width {
                let i = y * width + x
                let difference = Double(pixels[i]) - Double(pixels[i - 1])
                energy += difference * difference
            }
        }
        return energy / Double((width - 1) * height)
    }
}
