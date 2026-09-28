import PDFKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct HWPPDFFile: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    let url: URL
    init(url: URL) { self.url = url }
    init(configuration: ReadConfiguration) throws { throw HWPPDFError.renderingFailed }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { try FileWrapper(url: url, options: .immediate) }
}

struct HWPPDFPreview: View {
    let snapshot: HWPOutputSnapshot
    @Environment(\.dismiss) private var dismiss
    @State private var asset: HWPPDFAsset?
    @State private var completed = 0
    @State private var total = 0
    @State private var currentPage = 1
    @State private var rendering = true
    @State private var failure: String?
    @State private var actionError: String?
    @State private var exporting = false
    @State private var saved = false
    @State private var printing = false
    @State private var printRequest = 0
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let asset {
                    HWPPDFSurface(asset: asset, currentPage: $currentPage)
                        .accessibilityIdentifier("hwp-pdf-preview")
                    HStack {
                        Text(AppLocalization.format("%lld / %lld쪽", currentPage, asset.pageCount))
                            .monospacedDigit().accessibilityIdentifier("hwp-pdf-page-count")
                        Spacer()
                        Text(saved ? "PDF를 저장했습니다." : "현재 편집 내용 포함").foregroundStyle(.secondary)
                            .accessibilityIdentifier("hwp-pdf-status")
                    }.font(.caption).padding(.horizontal).padding(.top, 10)
                    Text("화면 모양을 유지한 PDF입니다. PDF 안에서 글자 선택·검색은 지원하지 않습니다.")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal).padding(.vertical, 10)
                } else if let failure {
                    ContentUnavailableView("PDF를 만들 수 없습니다", systemImage: "doc.badge.ellipsis", description: Text(failure))
                        .accessibilityIdentifier("hwp-pdf-failure")
                } else {
                    Spacer()
                    ProgressView(value: Double(completed), total: Double(max(total, 1))) {
                        Text("PDF를 만드는 중…")
                    }.frame(maxWidth: 280).accessibilityIdentifier("hwp-pdf-progress")
                    if total > 0 { Text(AppLocalization.format("%lld / %lld쪽", completed, total)).font(.caption).monospacedDigit() }
                    Spacer()
                }
            }
                .overlay(alignment: .topTrailing) {
                    HWPPrintAnchor(asset: asset, request: printRequest) { error in
                        printing = false; actionError = error
                    }.frame(width: 1, height: 1).padding(.trailing, 24)
                }
                .navigationTitle("출력 미리보기").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(rendering ? "취소" : "닫기") { dismiss() }.disabled(printing)
                            .accessibilityIdentifier("hwp-pdf-close")
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("PDF로 저장", systemImage: "square.and.arrow.down") { exporting = true }
                            .disabled(asset == nil || printing).accessibilityIdentifier("hwp-pdf-save")
                        Button("인쇄", systemImage: "printer") { printing = true; printRequest += 1 }
                            .disabled(asset == nil || printing).accessibilityIdentifier("hwp-pdf-print")
                    }
                }
        }
        .presentationSizing(.page)
        .interactiveDismissDisabled(printing)
        .task {
            guard asset == nil, failure == nil else { return }
            do {
                asset = try await HWPPDFRenderer.render(snapshot) { completed = $0; total = $1 }
                rendering = false
                if snapshot.opensPrintDialog { printing = true; printRequest += 1 }
            } catch is CancellationError { }
            catch { rendering = false; failure = error.localizedDescription }
        }
        .fileExporter(isPresented: $exporting, document: asset.map { HWPPDFFile(url: $0.url) },
            contentType: .pdf, defaultFilename: HWPPDFRenderer.filename(snapshot.title)) { result in
                switch result {
                case .success: saved = true
                case .failure(let error): actionError = error.localizedDescription
                }
            }
        .alert("출력할 수 없습니다", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("확인", role: .cancel) { actionError = nil }
        } message: { Text(actionError ?? "") }
    }
}

private struct HWPPDFSurface: UIViewRepresentable {
    let asset: HWPPDFAsset
    @Binding var currentPage: Int
    func makeCoordinator() -> Coordinator { Coordinator(currentPage: $currentPage) }
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePageContinuous; view.displayDirection = .vertical
        view.displaysPageBreaks = true; view.backgroundColor = .systemGray5
        context.coordinator.observer = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak view, weak coordinator = context.coordinator] _ in
            MainActor.assumeIsolated {
                guard let view, let page = view.currentPage, let document = view.document else { return }
                coordinator?.currentPage.wrappedValue = document.index(for: page) + 1
            }
        }
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != asset.url { view.document = PDFDocument(url: asset.url); view.autoScales = true }
    }
    final class Coordinator {
        let currentPage: Binding<Int>
        nonisolated(unsafe) var observer: NSObjectProtocol?
        init(currentPage: Binding<Int>) { self.currentPage = currentPage }
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
}

private struct HWPPrintAnchor: UIViewRepresentable {
    let asset: HWPPDFAsset?
    let request: Int
    let completion: (String?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIView { UIView() }
    func updateUIView(_ view: UIView, context: Context) {
        guard request > context.coordinator.lastRequest, let asset else { return }
        context.coordinator.lastRequest = request
        let coordinator = context.coordinator
        DispatchQueue.main.async { [weak view] in
            guard let view, view.window != nil, UIPrintInteractionController.isPrintingAvailable,
                  UIPrintInteractionController.canPrint(asset.url) else {
                completion(AppLocalization.string("인쇄 화면을 열 수 없습니다. PDF로 저장한 뒤 다시 시도해 주세요.")); return
            }
            let controller = UIPrintInteractionController.shared
            let info = UIPrintInfo(dictionary: nil)
            info.jobName = asset.url.deletingPathExtension().lastPathComponent
            info.outputType = .general
            if let bounds = PDFDocument(url: asset.url)?.page(at: 0)?.bounds(for: .mediaBox) {
                info.orientation = bounds.width > bounds.height ? .landscape : .portrait
            }
            controller.printInfo = info; controller.printingItem = asset.url
            controller.showsPageRange = true
            coordinator.presenting = true
            let presented = controller.present(from: view.bounds, in: view, animated: true) { _, _, error in
                _ = asset // Keep the temporary PDF alive until print/cancel completes.
                coordinator.presenting = false
                completion(error?.localizedDescription)
            }
            if !presented {
                coordinator.presenting = false
                completion(AppLocalization.string("인쇄 화면을 열 수 없습니다. PDF로 저장한 뒤 다시 시도해 주세요."))
            }
        }
    }
    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        if coordinator.presenting { UIPrintInteractionController.shared.dismiss(animated: false) }
    }
    final class Coordinator { var lastRequest = 0; var presenting = false }
}
