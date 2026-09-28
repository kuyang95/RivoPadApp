#if DEBUG
import Combine
import PDFKit
import SwiftUI
import UIKit

/// Saved comparison results stay in PDFKit. They must not enter the text,
/// speech, EPUB, or DAISY reading flows used elsewhere in the app.
@MainActor
final class HWPComparisonPDFViewer: NSObject, ObservableObject {
    struct Bookmark: Identifiable {
        let id: Int
        let title: String
        let pageIndex: Int
    }

    let pdfView = PDFView()
    @Published private(set) var pageIndex = 0
    @Published private(set) var pageCount = 0
    @Published private(set) var bookmarks: [Bookmark] = []
    @Published private(set) var error: String?

    override init() {
        super.init()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.backgroundColor = .systemGray5
        NotificationCenter.default.addObserver(
            self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: pdfView
        )
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func open(_ url: URL, page: Int = 0) {
        error = nil
        pdfView.document = nil
        pageCount = 0
        pageIndex = 0
        bookmarks = []
        guard url.pathExtension.lowercased() == "pdf",
              let document = PDFDocument(url: url), !document.isLocked, document.pageCount > 0 else {
            error = "PDF 원본을 열 수 없습니다. 파일이 남아 있는지 확인해 주세요."
            return
        }
        pageCount = document.pageCount
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.layoutDocumentView()
        collectBookmarks(document.outlineRoot, document: document, depth: 0)
        go(to: min(max(page, 0), pageCount - 1))
    }

    func go(to index: Int) {
        guard index >= 0, index < pageCount, let page = pdfView.document?.page(at: index) else { return }
        pdfView.go(to: page)
        pageIndex = index
    }

    func fitToScreen() {
        pdfView.autoScales = true
        pdfView.scaleFactor = pdfView.scaleFactorForSizeToFit
    }

    @objc private func pageChanged() {
        guard let document = pdfView.document, let page = pdfView.currentPage else { return }
        let index = document.index(for: page)
        if index >= 0, index < document.pageCount { pageIndex = index }
    }

    private func collectBookmarks(_ outline: PDFOutline?, document: PDFDocument, depth: Int) {
        guard let outline, depth < 12, bookmarks.count < 200 else { return }
        if let title = outline.label, let page = outline.destination?.page {
            let index = document.index(for: page)
            if index >= 0, index < document.pageCount {
                bookmarks.append(Bookmark(id: bookmarks.count, title: title, pageIndex: index))
            }
        }
        for index in 0..<min(outline.numberOfChildren, 200) {
            collectBookmarks(outline.child(at: index), document: document, depth: depth + 1)
        }
    }
}

struct HWPComparisonPDFView: View {
    let fileURL: URL
    let initialPageIndex: Int
    @StateObject private var viewer = HWPComparisonPDFViewer()
    @State private var showingJump = false
    @State private var jumpText = ""

    init(fileURL: URL, initialPageIndex: Int = 0) {
        self.fileURL = fileURL
        self.initialPageIndex = initialPageIndex
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text("PDF 원본").font(.subheadline.weight(.semibold))
                Spacer()
                Button("이전", systemImage: "chevron.left") { viewer.go(to: viewer.pageIndex - 1) }
                    .labelStyle(.iconOnly).disabled(viewer.pageIndex == 0)
                Button("\(viewer.pageCount == 0 ? 0 : viewer.pageIndex + 1) / \(viewer.pageCount)쪽") {
                    jumpText = String(viewer.pageIndex + 1)
                    showingJump = true
                }
                .monospacedDigit().disabled(viewer.pageCount == 0)
                .accessibilityLabel("PDF 쪽 번호를 눌러 이동")
                Button("다음", systemImage: "chevron.right") { viewer.go(to: viewer.pageIndex + 1) }
                    .labelStyle(.iconOnly).disabled(viewer.pageIndex >= viewer.pageCount - 1)
                Spacer()
                Button("화면 맞춤") { viewer.fitToScreen() }.disabled(viewer.pageCount == 0)
            }
            .padding(12)
            if viewer.pageCount > 0 {
                HWPComparisonReviewBar(documentURL: fileURL, referenceURL: nil, pageIndex: viewer.pageIndex)
                    .id(fileURL)
            }
            Divider()
            if let error = viewer.error {
                ContentUnavailableView("PDF를 열 수 없습니다", systemImage: "doc.badge.ellipsis", description: Text(error))
            } else {
                HWPComparisonPDFSurface(viewer: viewer)
                    .accessibilityIdentifier("hwpComparisonOriginalPDF")
            }
        }
        .navigationTitle(fileURL.deletingPathExtension().lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !viewer.bookmarks.isEmpty {
                Menu {
                    ForEach(viewer.bookmarks) { bookmark in
                        Button(bookmark.title) { viewer.go(to: bookmark.pageIndex) }
                    }
                } label: { Label("책갈피", systemImage: "list.bullet") }
            }
        }
        .task(id: fileURL) { viewer.open(fileURL, page: initialPageIndex) }
        .sheet(isPresented: $showingJump) {
            NavigationStack {
                Form {
                    TextField("1~\(viewer.pageCount)쪽", text: $jumpText)
                        .keyboardType(.numberPad).onSubmit(jump)
                }
                .navigationTitle("PDF 쪽 이동")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("취소") { showingJump = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("이동", action: jump)
                            .disabled(Int(jumpText).map { !(1...max(viewer.pageCount, 1)).contains($0) } ?? true)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func jump() {
        guard let number = Int(jumpText), (1...max(viewer.pageCount, 1)).contains(number) else { return }
        viewer.go(to: number - 1)
        showingJump = false
    }
}

private struct HWPComparisonPDFSurface: UIViewRepresentable {
    let viewer: HWPComparisonPDFViewer
    func makeUIView(context: Context) -> PDFView { viewer.pdfView }
    func updateUIView(_ uiView: PDFView, context: Context) {}
}
#endif
