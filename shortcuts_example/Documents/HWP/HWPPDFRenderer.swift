import PDFKit
import SwiftUI
import UIKit

struct HWPOutputSnapshot: Identifiable {
    let id = UUID()
    let title: String
    let blocks: [HWPDocumentBlock]
    let layouts: [HWPDocumentPageLayout]
    var opensPrintDialog = false
}

nonisolated final class HWPPDFAsset: Identifiable, @unchecked Sendable {
    let id = UUID()
    let url: URL
    let pageCount: Int
    private let directory: URL
    init(url: URL, pageCount: Int, directory: URL) { self.url = url; self.pageCount = pageCount; self.directory = directory }
    deinit { try? FileManager.default.removeItem(at: directory) }
}

nonisolated enum HWPPDFError: LocalizedError {
    case emptyDocument, invalidPage, tooLarge, renderingFailed
    var errorDescription: String? {
        switch self {
        case .emptyDocument: AppLocalization.string("출력할 문서가 없습니다.")
        case .invalidPage: AppLocalization.string("이 문서의 용지 크기로는 PDF를 만들 수 없습니다.")
        case .tooLarge: AppLocalization.string("문서가 너무 커서 PDF를 만들 수 없습니다. 문서를 나누어 다시 시도해 주세요.")
        case .renderingFailed: AppLocalization.string("PDF를 만들지 못했습니다. 다시 시도해 주세요.")
        }
    }
}

@MainActor enum HWPPDFRenderer {
    static let maximumPages = 500
    static let maximumBytes = 200 * 1024 * 1024
    static func pageBounds(_ layout: HWPDocumentPageLayout) throws -> CGRect {
        guard layout.widthPoints.isFinite, layout.heightPoints.isFinite,
              (72...4_000).contains(layout.widthPoints), (72...4_000).contains(layout.heightPoints) else { throw HWPPDFError.invalidPage }
        return CGRect(x: 0, y: 0, width: layout.widthPoints, height: layout.heightPoints)
    }
    static func filename(_ title: String) -> String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/\\:\n\r\t\0")).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((cleaned.isEmpty ? AppLocalization.string("한글 문서") : cleaned).prefix(120)) + ".pdf"
    }
    static func render(_ snapshot: HWPOutputSnapshot,
                       progress: (Int, Int) -> Void = { _, _ in }) async throws -> HWPPDFAsset {
        try Task.checkCancellation()
        guard !snapshot.blocks.isEmpty else { throw HWPPDFError.emptyDocument }
        for layout in snapshot.layouts { _ = try pageBounds(layout) }
        let pages = HWPOriginalCanvasPageBuilder.makePages(blocks: snapshot.blocks, layouts: snapshot.layouts)
        guard !pages.isEmpty else { throw HWPPDFError.emptyDocument }
        guard pages.count <= maximumPages else { throw HWPPDFError.tooLarge }
        progress(0, pages.count)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HWP-PDF-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(filename(snapshot.title))
        var succeeded = false
        defer { if !succeeded { try? FileManager.default.removeItem(at: directory) } }
        guard let context = CGContext(url as CFURL, mediaBox: nil,
            [kCGPDFContextTitle as String: snapshot.title, kCGPDFContextCreator as String: "VisionCraft"] as CFDictionary) else { throw HWPPDFError.renderingFailed }
        var closed = false
        defer { if !closed { context.closePDF() } }
        for (index, page) in pages.enumerated() {
            try Task.checkCancellation()
            let bounds = try pageBounds(page.layout)
            let host = UIHostingController(rootView: HWPOriginalCanvasPageView(page: page, showsPaperShadow: false)
                .environment(\.colorScheme, .light).dynamicTypeSize(.large))
            host.view.backgroundColor = .white
            host.view.frame = bounds
            host.view.isUserInteractionEnabled = false
            host.view.accessibilityElementsHidden = true
            // Mount outside the visible app bounds so UIKit-backed line and
            // equation views receive a window, without replacing the preview.
            guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows).first(where: \.isKeyWindow) else { throw HWPPDFError.renderingFailed }
            let container = UIView(frame: CGRect(x: -bounds.width - 20, y: 0, width: bounds.width, height: bounds.height))
            container.isUserInteractionEnabled = false; container.accessibilityElementsHidden = true
            window.addSubview(container); container.addSubview(host.view)
            defer { host.view.removeFromSuperview(); container.removeFromSuperview() }
            host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            await Task.yield()
            try Task.checkCancellation()
            try autoreleasepool {
                let format = UIGraphicsImageRendererFormat()
                format.opaque = true
                // One page at a time, up to 300 dpi / 12 megapixels. Drawing
                // the real canvas retains UIKit text, formulas and all objects.
                format.scale = min(300.0 / 72.0, sqrt(12_000_000 / (bounds.width * bounds.height)))
                var drawn = false
                let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { _ in
                    drawn = host.view.drawHierarchy(in: bounds, afterScreenUpdates: true)
                }
                guard drawn else { throw HWPPDFError.renderingFailed }
                var mediaBox = bounds
                let data = NSData(bytes: &mediaBox, length: MemoryLayout<CGRect>.size)
                context.beginPDFPage([kCGPDFContextMediaBox as String: data] as CFDictionary)
                context.saveGState()
                context.translateBy(x: 0, y: bounds.height); context.scaleBy(x: 1, y: -1)
                UIGraphicsPushContext(context); image.draw(in: bounds); UIGraphicsPopContext()
                context.restoreGState(); context.endPDFPage()
            }
            let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
            guard size <= maximumBytes else { throw HWPPDFError.tooLarge }
            progress(index + 1, pages.count)
            await Task.yield()
        }
        context.closePDF(); closed = true
        try Task.checkCancellation()
        guard let document = PDFDocument(url: url), document.pageCount == pages.count else { throw HWPPDFError.renderingFailed }
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size <= maximumBytes else { throw HWPPDFError.tooLarge }
        succeeded = true
        return HWPPDFAsset(url: url, pageCount: pages.count, directory: directory)
    }
}
