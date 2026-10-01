#if DEBUG
import Combine
import PDFKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct HWPReferenceComparisonView: View {
    let library: HWPComparisonLibrary
    @Environment(\.scenePhase) private var scenePhase
    @State private var documents: [URL] = []
    @State private var results: [URL] = []
    @State private var loadError: String?
    @State private var search = ""
    @State private var showingImporter = false
    @State private var isImporting = false

    init(library: HWPComparisonLibrary = .current) { self.library = library }

    private var matchingDocuments: [URL] {
        documents.filter { search.isEmpty || $0.lastPathComponent.localizedStandardContains(search) }
    }

    var body: some View {
        List {
            Section {
                Text("문서를 고르면 왼쪽에 정답 PDF, 오른쪽에 현재 앱이 그린 한글 문서가 나옵니다. 앱을 수정한 뒤에는 ‘다시 불러오기’로 같은 자료를 재검사할 수 있습니다.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("비교 자료 추가", systemImage: "plus.circle") { showingImporter = true }
                    .disabled(isImporting)
                if isImporting { ProgressView("자료를 추가하는 중…") }
            } footer: {
                Text("HWP/HWPX와 같은 이름의 PDF를 함께 선택하면 자동으로 연결됩니다. 이름이 다른 PDF도 문서 안에서 연결할 수 있습니다.")
            }
            if let loadError {
                Section { Text(loadError).foregroundStyle(VisionCraftUI.error) }
            }
            if !results.isEmpty {
                Section {
                    ForEach(results, id: \.self) { url in
                        NavigationLink {
                            HWPComparisonPDFView(fileURL: url)
                                .visionCraftRouteBackButton()
                        } label: {
                            Label(url.deletingPathExtension().lastPathComponent, systemImage: "doc.richtext")
                        }
                    }
                } header: { Text("저장된 정답·비교 PDF") }
                footer: { Text("저장 당시의 PDF입니다. 아래 문서 비교는 현재 앱으로 다시 그립니다.") }
            }
            documentSection("정답 PDF와 비교", paired: true)
            documentSection("정답 PDF 연결 전", paired: false)
            if documents.isEmpty {
                ContentUnavailableView("비교 자료를 추가해 주세요", systemImage: "doc.badge.plus")
            }
        }
        .navigationTitle("HWP 비교 테스트")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "문서 이름 검색")
        .toolbar {
            Button("새로고침", systemImage: "arrow.clockwise") { reload() }
        }
        .onAppear(perform: reload)
        .onChange(of: scenePhase) { _, phase in if phase == .active { reload() } }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
            Task {
                isImporting = true
                defer { isImporting = false }
                do {
                    let urls = try result.get()
                    let store = library
                    _ = try await Task.detached(priority: .userInitiated) { try store.importDocuments(urls) }.value
                    reload()
                } catch { loadError = error.localizedDescription }
            }
        }
    }

    @ViewBuilder
    private func documentSection(_ title: String, paired: Bool) -> some View {
        let items = matchingDocuments.filter { (library.referencePDF(for: $0) != nil) == paired }
        if !items.isEmpty {
            Section("\(title) · \(items.count)개") {
                ForEach(items, id: \.self) { url in
                    NavigationLink {
                        HWPReferenceComparisonPageView(hwpURL: url, library: library)
                            .visionCraftRouteBackButton()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(url.deletingPathExtension().lastPathComponent)
                            Text(paired ? "정답 PDF 연결됨 · 현재 앱으로 비교" : "문서를 연 뒤 정답 PDF를 선택하세요")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func reload() {
        do {
            documents = try library.documents()
            results = try library.resultPDFs()
            loadError = nil
        } catch { loadError = error.localizedDescription }
    }
}

private nonisolated struct HWPComparisonParsedDocument: Sendable {
    let blocks: [HWPDocumentBlock]
    let layouts: [HWPDocumentPageLayout]
}

@MainActor
final class HWPReferenceComparisonModel: ObservableObject {
    let hwpURL: URL
    let library: HWPComparisonLibrary
    @Published private(set) var pages: [HWPOriginalCanvasPage] = []
    @Published private(set) var pdf: PDFDocument?
    @Published private(set) var isLoading = false
    @Published private(set) var status = "여는 중…"
    @Published private(set) var error: String?
    @Published private(set) var referenceError: String?
    @Published private(set) var reviewRevision = UUID()

    init(hwpURL: URL, library: HWPComparisonLibrary = .current) {
        self.hwpURL = hwpURL
        self.library = library
    }

    var pageCount: Int { max(pages.count, pdf?.pageCount ?? 0) }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        referenceError = nil
        defer { isLoading = false; reviewRevision = UUID() }
        let url = hwpURL
        do {
            let parsed = try await Task.detached(priority: .userInitiated) {
                let data = try CoordinatedDocumentFileAccess.readData(from: url)
                if data.starts(with: [0x50, 0x4B]) {
                    let package = try HWPXDocumentPackage.load(from: data)
                    return HWPComparisonParsedDocument(blocks: package.blocks, layouts: package.pageLayouts)
                }
                let document = try HWP5StructuredDocumentParser.parse(from: data)
                return HWPComparisonParsedDocument(blocks: document.blocks, layouts: document.pageLayouts)
            }.value
            pages = HWPOriginalCanvasPageBuilder.makePages(blocks: parsed.blocks, layouts: parsed.layouts)
            pdf = nil
            if let url = library.referencePDF(for: hwpURL) {
                if let document = PDFDocument(url: url), !document.isLocked, document.pageCount > 0 {
                    pdf = document
                } else { referenceError = "정답 PDF를 열 수 없습니다. 다른 PDF를 연결해 주세요." }
            }
            let count = pdf?.pageCount ?? 0
            status = "앱 \(pages.count)쪽 · 정답 " + (count == 0 ? "PDF 없음" : "\(count)쪽 · 쪽수 " + (count == pages.count ? "같음" : "다름"))
        } catch { self.error = error.localizedDescription }
    }

    func connectReference(_ url: URL) async throws {
        let store = library
        let document = hwpURL
        try await Task.detached(priority: .userInitiated) { try store.connectReference(url, to: document) }.value
        await load()
    }
}

struct HWPReferenceComparisonPageView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case sideBySide, overlay
        var id: String { rawValue }
        var title: String { self == .sideBySide ? "나란히" : "겹쳐 보기" }
    }

    @StateObject private var model: HWPReferenceComparisonModel
    @State private var pageIndex: Int
    @State private var mode = Mode.sideBySide
    @State private var zoom = 1.0
    @State private var overlayOpacity = 0.5
    @State private var referenceImage: UIImage?
    @State private var showingImporter = false
    @State private var showingJump = false
    @State private var jumpText = ""
    @State private var importError: String?

    init(hwpURL: URL, library: HWPComparisonLibrary = .current, initialPageIndex: Int = 0) {
        _model = StateObject(wrappedValue: HWPReferenceComparisonModel(hwpURL: hwpURL, library: library))
        _pageIndex = State(initialValue: max(initialPageIndex, 0))
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            if !model.isLoading, !model.pages.isEmpty {
                HWPComparisonReviewBar(documentURL: model.hwpURL,
                    referenceURL: model.library.referencePDF(for: model.hwpURL), pageIndex: pageIndex,
                    directory: model.library.documentsDirectory)
                    .id(model.reviewRevision)
            }
            Divider()
            GeometryReader { proxy in
                if model.isLoading {
                    ProgressView("현재 앱으로 문서를 다시 그리는 중…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = model.error {
                    ContentUnavailableView("열 수 없습니다", systemImage: "doc.badge.ellipsis", description: Text(error))
                } else if model.pages.isEmpty {
                    ContentUnavailableView("표시할 쪽이 없습니다", systemImage: "doc")
                } else {
                    ScrollView([.horizontal, .vertical]) { content(in: proxy.size) }
                }
            }
            .background(Color(uiColor: .systemGray5))
        }
        .navigationTitle(model.hwpURL.deletingPathExtension().lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button("다시 불러오기", systemImage: "arrow.clockwise") { Task { await reload() } }
                Button(model.pdf == nil ? "정답 PDF 연결" : "정답 PDF 바꾸기", systemImage: "doc.badge.plus") { showingImporter = true }
            } label: { Label("비교 자료", systemImage: "ellipsis.circle") }
                .disabled(model.isLoading)
        }
        .task { await reload() }
        .onChange(of: pageIndex) { _, _ in updateReferenceImage() }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.pdf]) { result in
            Task {
                do {
                    try await model.connectReference(result.get())
                    clampPage()
                    updateReferenceImage()
                } catch { importError = error.localizedDescription }
            }
        }
        .alert("정답 PDF를 연결하지 못했습니다", isPresented: Binding(
            get: { importError != nil }, set: { if !$0 { importError = nil } }
        )) { Button("확인", role: .cancel) {} } message: { Text(importError ?? "") }
        .sheet(isPresented: $showingJump) {
            NavigationStack {
                Form {
                    TextField("1~\(model.pageCount)쪽", text: $jumpText)
                        .keyboardType(.numberPad).onSubmit(jump)
                    Text("앱과 정답 PDF를 같은 쪽으로 이동합니다.").foregroundStyle(.secondary)
                }
                .navigationTitle("쪽 이동")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("취소") { showingJump = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("이동", action: jump)
                            .disabled(Int(jumpText).map { !(1...max(model.pageCount, 1)).contains($0) } ?? true)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    Button("이전", systemImage: "chevron.left") { pageIndex -= 1 }
                        .labelStyle(.iconOnly).disabled(pageIndex == 0)
                    Button("\(model.pageCount == 0 ? 0 : pageIndex + 1) / \(model.pageCount)쪽") {
                        jumpText = String(pageIndex + 1); showingJump = true
                    }.monospacedDigit().accessibilityLabel("쪽 번호를 눌러 이동")
                    Button("다음", systemImage: "chevron.right") { pageIndex += 1 }
                        .labelStyle(.iconOnly).disabled(pageIndex >= model.pageCount - 1)
                    Picker("보기", selection: $mode) { ForEach(Mode.allCases) { Text($0.title).tag($0) } }
                        .pickerStyle(.segmented).frame(width: 190)
                    Button("축소", systemImage: "minus.magnifyingglass") { zoom = max(1, zoom - 0.5) }
                        .labelStyle(.iconOnly).disabled(zoom == 1)
                    Button(zoom == 1 ? "화면 맞춤" : "\(Int(zoom * 100))%") { zoom = 1 }
                    Button("확대", systemImage: "plus.magnifyingglass") { zoom = min(4, zoom + 0.5) }
                        .labelStyle(.iconOnly).disabled(zoom == 4)
                    Button("다시 불러오기", systemImage: "arrow.clockwise") { Task { await reload() } }
                }
            }
            HStack {
                Text(model.status).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if mode == .overlay {
                    Text("정답 \(Int(overlayOpacity * 100))%").font(.caption)
                    Slider(value: $overlayOpacity, in: 0...1).frame(maxWidth: 180)
                        .accessibilityLabel("정답 PDF 투명도")
                }
                Button(model.pdf == nil ? "정답 PDF 연결" : "정답 PDF 바꾸기") { showingImporter = true }
                    .font(.caption)
            }
        }
        .disabled(model.isLoading)
        .padding(12)
        .background(Color(uiColor: .systemBackground))
    }

    @ViewBuilder
    private func content(in size: CGSize) -> some View {
        let page = model.pages.indices.contains(pageIndex) ? model.pages[pageIndex] : nil
        let bounds = model.pdf?.page(at: pageIndex)?.bounds(for: .mediaBox)
        let width = page?.layout.widthPoints ?? bounds?.width ?? 595.28
        let height = page?.layout.heightPoints ?? bounds?.height ?? 841.88
        let columns = mode == .sideBySide ? 2.0 : 1.0
        let scale = max(0.05, min((size.width - 36) / columns / width, (size.height - 58) / height)) * zoom
        Group {
            if mode == .sideBySide {
                HStack(alignment: .top, spacing: 12) {
                    panel(title: "정답 PDF") { referencePage(width: width * scale, height: height * scale) }
                    panel(title: "현재 앱") { canvasPage(page, width: width, height: height, scale: scale) }
                }
            } else {
                panel(title: "현재 앱 + 정답 PDF") {
                    ZStack(alignment: .topLeading) {
                        canvasPage(page, width: width, height: height, scale: scale)
                        referencePage(width: width * scale, height: height * scale).opacity(overlayOpacity)
                    }
                }
            }
        }
        .padding(12)
        .frame(minWidth: size.width, minHeight: size.height, alignment: .top)
    }

    private func panel<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    @ViewBuilder
    private func canvasPage(_ page: HWPOriginalCanvasPage?, width: Double, height: Double, scale: Double) -> some View {
        if let page {
            HWPOriginalCanvasPageView(page: page)
                .frame(width: width, height: height)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: width * scale, height: height * scale, alignment: .topLeading)
        } else { placeholder("앱에는 이 쪽이 없습니다", width: width * scale, height: height * scale) }
    }

    @ViewBuilder
    private func referencePage(width: Double, height: Double) -> some View {
        if let referenceImage {
            Image(uiImage: referenceImage).resizable().scaledToFit()
                .frame(width: width, height: height, alignment: .top).background(.white)
        } else {
            placeholder(model.referenceError ?? (model.pdf == nil ? "정답 PDF 연결 버튼으로 파일을 선택해 주세요." : "정답 PDF에는 이 쪽이 없습니다"), width: width, height: height)
        }
    }

    private func placeholder(_ text: String, width: Double, height: Double) -> some View {
        Text(text).font(.callout).multilineTextAlignment(.center).foregroundStyle(.secondary)
            .padding().frame(width: max(width, 40), height: max(height, 40)).background(.white.opacity(0.6))
    }

    private func reload() async {
        await model.load()
        clampPage()
        updateReferenceImage()
    }

    private func clampPage() { pageIndex = min(max(pageIndex, 0), max(model.pageCount - 1, 0)) }

    private func jump() {
        guard let value = Int(jumpText), (1...max(model.pageCount, 1)).contains(value) else { return }
        pageIndex = value - 1
        showingJump = false
    }

    private func updateReferenceImage() {
        guard let page = model.pdf?.page(at: pageIndex) else { referenceImage = nil; return }
        let bounds = page.bounds(for: .mediaBox)
        referenceImage = page.thumbnail(of: CGSize(width: bounds.width * 2, height: bounds.height * 2), for: .mediaBox)
    }
}
#endif
