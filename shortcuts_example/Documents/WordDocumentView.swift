import Combine
import QuickLook
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private nonisolated enum WordLoadedDocument: Sendable {
    case editable(WordDocumentPackage)
    case legacy(text: String)
}

@MainActor
final class WordDocumentViewModel: ObservableObject {
    private struct Mutation {
        let index: Int
        let oldBlock: WordDocumentBlock
        let newBlock: WordDocumentBlock
    }

    private struct MutationGroup {
        let mutations: [Mutation]
    }

    @Published private(set) var blocks: [WordDocumentBlock] = []
    @Published private(set) var isLoading = true
    @Published private(set) var isSaving = false
    @Published private(set) var isLegacyReadOnly = false
    @Published private(set) var requiresSaveAs = false
    @Published private(set) var hasUnsavedChanges = false
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var originalPreviewURL: URL?
    @Published private(set) var isPreparingOriginalPreview = false
    @Published private(set) var originalPreviewErrorDescription: String?
    @Published private(set) var status = ""
    @Published private(set) var errorDescription: String?
    @Published var selectedBlockID: String?
    @Published var editorText = ""
    @Published var editorStyleID = "Normal"

    let fileURL: URL
    let originalDocumentID: UUID?

    private var package: WordDocumentPackage?
    private var legacyText: String?
    private var undoStack: [MutationGroup] = []
    private var redoStack: [MutationGroup] = []
    private var didLoad = false
    private var originalPreviewSequence = 0
    private let originalPreviewDirectoryURL: URL

    init(fileURL: URL, originalDocumentID: UUID? = nil) {
        self.fileURL = fileURL
        self.originalDocumentID = originalDocumentID
        originalPreviewDirectoryURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "VisionCraft-WordPreview-\(UUID().uuidString)",
                isDirectory: true
            )
    }

    deinit {
        try? FileManager.default.removeItem(
            at: originalPreviewDirectoryURL
        )
    }

    var documentName: String {
        fileURL.deletingPathExtension().lastPathComponent
    }

    var selectedBlock: WordDocumentBlock? {
        guard let selectedBlockID else { return nil }
        return blocks.first { $0.id == selectedBlockID }
    }

    var canEditSelectedBlock: Bool {
        selectedBlock?.isEditable == true && package != nil
    }

    var isEditableDocument: Bool { package != nil }

    func load() async {
        guard !didLoad else { return }
        didLoad = true
        isLoading = true
        errorDescription = nil
        status = AppLocalization.string("Word 문서를 여는 중…")
        do {
            let url = fileURL
            let loaded = try await Task.detached(
                priority: .userInitiated
            ) {
                let data = try CoordinatedDocumentFileAccess
                    .readData(from: url)
                if data.starts(with: [0x50, 0x4B]) {
                    return WordLoadedDocument.editable(
                        try WordDocumentPackage.load(from: data)
                    )
                }
                let text = try WordDocumentTextExtractor.extract(from: data)
                return WordLoadedDocument.legacy(text: text)
            }.value
            switch loaded {
            case .editable(let package):
                install(package: package)
                isLegacyReadOnly = false
                requiresSaveAs = false
                status = documentStatus(package.blocks)
            case .legacy(let text):
                legacyText = text
                blocks = legacyBlocks(text: text)
                isLegacyReadOnly = true
                requiresSaveAs = false
                status = AppLocalization.format(
                    "DOC 읽기 전용 · 본문 %lld자",
                    text.count
                )
                selectInitialBlock()
            }
        } catch {
            errorDescription = error.localizedDescription
            status = AppLocalization.string("Word 문서를 열지 못했습니다.")
        }
        isLoading = false
    }

    func convertLegacyForEditing() async {
        guard let legacyText, package == nil, !isSaving else { return }
        isSaving = true
        errorDescription = nil
        status = AppLocalization.string("DOCX 편집본을 만드는 중…")
        do {
            let package = try await Task.detached(
                priority: .userInitiated
            ) {
                try WordDocumentPackage.load(
                    from: LegacyDOCXConverter.convert(text: legacyText)
                )
            }.value
            install(package: package)
            isLegacyReadOnly = false
            requiresSaveAs = true
            hasUnsavedChanges = true
            status = AppLocalization.string(
                "DOC를 DOCX 편집본으로 변환했습니다. 저장하면 새 DOCX 파일로 내보냅니다."
            )
        } catch {
            errorDescription = error.localizedDescription
        }
        isSaving = false
    }

    func selectBlock(_ id: String) {
        commitEditorChange()
        selectedBlockID = id
        syncEditor()
    }

    func commitEditorChange() {
        guard let selectedBlockID,
              let index = blocks.firstIndex(where: { $0.id == selectedBlockID }),
              blocks[index].isEditable,
              package != nil else { return }
        let oldBlock = blocks[index]
        var newBlock = oldBlock
        newBlock.text = editorText
        newBlock.styleID = editorStyleID == "Normal"
            ? nil
            : editorStyleID
        guard newBlock != oldBlock else { return }
        apply(
            MutationGroup(
                mutations: [Mutation(
                    index: index,
                    oldBlock: oldBlock,
                    newBlock: newBlock
                )]
            ),
            forward: true,
            registeringUndo: true
        )
        status = AppLocalization.string(
            "문단을 수정했습니다. 저장하면 DOCX 파일에 반영됩니다."
        )
    }

    func undo() {
        commitEditorChange()
        guard let group = undoStack.popLast() else { return }
        apply(group, forward: false, registeringUndo: false)
        redoStack.append(group)
        updateHistoryState()
        syncEditor()
    }

    func redo() {
        commitEditorChange()
        guard let group = redoStack.popLast() else { return }
        apply(group, forward: true, registeringUndo: false)
        undoStack.append(group)
        updateHistoryState()
        syncEditor()
    }

    func save() async {
        commitEditorChange()
        guard !isSaving,
              !requiresSaveAs,
              let package else { return }
        isSaving = true
        errorDescription = nil
        status = AppLocalization.string("DOCX 저장 중…")
        do {
            let editedBlocks = blocks
            let destination = fileURL
            let data = try await Task.detached(
                priority: .userInitiated
            ) {
                let data = try package.serializedData(
                    applying: editedBlocks
                )
                try CoordinatedDocumentFileAccess.replaceContents(
                    at: destination,
                    with: data
                )
                return data
            }.value
            let reloaded = try await Task.detached {
                try WordDocumentPackage.load(from: data)
            }.value
            let selectedIndex = selectedBlock.flatMap { selected in
                blocks.firstIndex(where: { $0.id == selected.id })
            }
            install(package: reloaded, selectedIndex: selectedIndex)
            hasUnsavedChanges = false
            undoStack.removeAll()
            redoStack.removeAll()
            updateHistoryState()
            if let originalDocumentID {
                try? await RecentOriginalDocumentStore.shared.refreshBookmark(
                    id: originalDocumentID,
                    fileURL: fileURL
                )
            }
            status = AppLocalization.string("DOCX 문서에 저장했습니다.")
        } catch {
            errorDescription = error.localizedDescription
            status = AppLocalization.format(
                "저장하지 못했습니다: %@",
                error.localizedDescription
            )
        }
        isSaving = false
    }

    func exportData() async throws -> Data {
        commitEditorChange()
        guard let package else {
            throw WordDocumentEditingError.cannotSave
        }
        let editedBlocks = blocks
        return try await Task.detached(priority: .userInitiated) {
            try package.serializedData(applying: editedBlocks)
        }.value
    }

    func markExported() {
        hasUnsavedChanges = false
        status = AppLocalization.string("DOCX 편집본을 저장했습니다.")
    }

    func prepareOriginalPreview() async {
        commitEditorChange()
        guard !isPreparingOriginalPreview else { return }
        isPreparingOriginalPreview = true
        originalPreviewErrorDescription = nil
        originalPreviewSequence += 1

        let sequence = originalPreviewSequence
        let package = package
        let blocks = blocks
        let sourceURL = fileURL
        let previewDirectoryURL = originalPreviewDirectoryURL
        let sourceExtension = sourceURL.pathExtension.lowercased()
        let pathExtension = package == nil
            ? (sourceExtension.isEmpty ? "doc" : sourceExtension)
            : "docx"
        let destination = previewDirectoryURL.appendingPathComponent(
            "preview-\(sequence).\(pathExtension)"
        )

        do {
            let previewURL = try await Task.detached(
                priority: .userInitiated
            ) {
                let data: Data
                if let package {
                    data = try package.serializedData(applying: blocks)
                } else {
                    data = try CoordinatedDocumentFileAccess.readData(
                        from: sourceURL
                    )
                }
                try FileManager.default.createDirectory(
                    at: previewDirectoryURL,
                    withIntermediateDirectories: true
                )
                try data.write(to: destination, options: .atomic)
                return destination
            }.value
            originalPreviewURL = previewURL
            status = package == nil
                ? AppLocalization.string("원본 Word 문서를 표시합니다.")
                : AppLocalization.string("현재 편집 내용을 원본 Word 레이아웃으로 표시합니다.")
        } catch {
            originalPreviewErrorDescription = error.localizedDescription
            status = AppLocalization.string("원본 Word 화면을 만들지 못했습니다.")
        }
        isPreparingOriginalPreview = false
    }

    func makeAIRetrievalCatalog(
        for userRequest: String
    ) -> WordAIRetrievalCatalog? {
        commitEditorChange()
        guard package != nil else { return nil }
        return WordAIRetrievalCatalogBuilder.make(
            documentName: documentName,
            blocks: blocks,
            userRequest: userRequest
        )
    }

    func makeAISnapshot(
        for userRequest: String,
        catalog: WordAIRetrievalCatalog,
        retrievalPlan: WordAIRetrievalPlan?
    ) -> WordAIDocumentSnapshot? {
        commitEditorChange()
        guard package != nil,
              catalog.queryTerms == WordAIQueryTokenizer.terms(
                  in: userRequest
              ),
              catalog.revision == WordAISnapshotBuilder.revision(
                  blocks: blocks
              ) else { return nil }
        guard catalog.requiresRouting else {
            return WordAISnapshotBuilder.make(
                documentName: documentName,
                blocks: blocks,
                selectedBlockID: selectedBlockID
            )
        }
        guard let retrievalPlan,
              retrievalPlan.intent == .retrieve else { return nil }
        return WordAISnapshotBuilder.makeRetrieved(
            documentName: documentName,
            blocks: blocks,
            selectedBlockID: selectedBlockID,
            catalog: catalog,
            retrievalPlan: retrievalPlan
        )
    }

    @discardableResult
    func applyAIPlan(_ plan: WordAIValidatedPlan) throws -> String {
        commitEditorChange()
        guard WordAISnapshotBuilder.revision(blocks: blocks)
            == plan.sourceRevision else {
            throw WordAIApplyError.staleProposal
        }
        var updated = blocks
        var mutations: [Mutation] = []
        for operation in plan.operations {
            guard let index = updated.firstIndex(where: {
                $0.id == operation.blockID
            }), updated[index].isEditable else {
                throw WordAIApplyError.invalidTarget
            }
            let oldBlock = updated[index]
            var newBlock = oldBlock
            switch operation.kind {
            case .replaceText:
                guard let newText = operation.newText else {
                    throw WordAIApplyError.invalidTarget
                }
                newBlock.text = newText
            case .setStyle:
                guard let styleID = operation.styleID else {
                    throw WordAIApplyError.invalidTarget
                }
                newBlock.styleID = styleID == "Normal" ? nil : styleID
            }
            guard newBlock != oldBlock else { continue }
            updated[index] = newBlock
            mutations.append(
                Mutation(
                    index: index,
                    oldBlock: oldBlock,
                    newBlock: newBlock
                )
            )
        }
        guard !mutations.isEmpty else {
            throw WordAIApplyError.noChanges
        }
        apply(
            MutationGroup(mutations: mutations),
            forward: true,
            registeringUndo: true
        )
        selectedBlockID = mutations.first?.newBlock.id
        syncEditor()
        let message = AppLocalization.format(
            "AI 수정안으로 %lld개 항목을 변경했습니다. 저장하면 DOCX 파일에 반영됩니다.",
            mutations.count
        )
        status = message
        return message
    }

    private func apply(
        _ group: MutationGroup,
        forward: Bool,
        registeringUndo: Bool
    ) {
        let mutations = forward
            ? group.mutations
            : Array(group.mutations.reversed())
        for mutation in mutations {
            guard blocks.indices.contains(mutation.index) else { continue }
            blocks[mutation.index] = forward
                ? mutation.newBlock
                : mutation.oldBlock
        }
        if registeringUndo {
            undoStack.append(group)
            redoStack.removeAll()
        }
        hasUnsavedChanges = true
        updateHistoryState()
    }

    private func updateHistoryState() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    private func install(
        package: WordDocumentPackage,
        selectedIndex: Int? = nil
    ) {
        self.package = package
        blocks = package.blocks
        let preferred = selectedIndex.flatMap { index in
            blocks.indices.contains(index) ? blocks[index].id : nil
        }
        selectedBlockID = preferred
            ?? blocks.first(where: { !$0.text.isEmpty })?.id
            ?? blocks.first?.id
        syncEditor()
    }

    private func selectInitialBlock() {
        selectedBlockID = blocks.first(where: { !$0.text.isEmpty })?.id
            ?? blocks.first?.id
        syncEditor()
    }

    private func syncEditor() {
        guard let block = selectedBlock else {
            editorText = ""
            editorStyleID = "Normal"
            return
        }
        editorText = block.text
        editorStyleID = block.styleID ?? "Normal"
    }

    private func legacyBlocks(text: String) -> [WordDocumentBlock] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .prefix(WordDocumentPackage.maximumBlocks)
            .enumerated()
            .map { index, line in
                WordDocumentBlock(
                    id: "legacy-word-paragraph-\(index)",
                    paragraphIndex: index,
                    text: String(line),
                    styleID: nil,
                    isNumbered: false,
                    tableLocation: nil,
                    isEditable: false
                )
            }
    }

    private func documentStatus(_ blocks: [WordDocumentBlock]) -> String {
        let tableCells = blocks.filter { $0.tableLocation != nil }.count
        return AppLocalization.format(
            "%lld개 문단 · %lld개 표 셀",
            blocks.count,
            tableCells
        )
    }
}

struct WordDocumentExportFile: FileDocument {
    static var readableContentTypes: [UTType] {
        [VisionCraftFileTypes.docx]
    }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct WordOriginalDocumentPreview: UIViewControllerRepresentable {
    let fileURL: URL

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var fileURL: URL

        init(fileURL: URL) {
            self.fileURL = fileURL
        }

        func numberOfPreviewItems(
            in controller: QLPreviewController
        ) -> Int {
            1
        }

        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> QLPreviewItem {
            fileURL as NSURL
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(fileURL: fileURL)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(
        _ controller: QLPreviewController,
        context: Context
    ) {
        guard context.coordinator.fileURL != fileURL else { return }
        context.coordinator.fileURL = fileURL
        controller.reloadData()
    }
}

private enum WordDocumentViewMode: String, CaseIterable, Identifiable {
    case accessibleDocument
    case originalDocument

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibleDocument:
            return AppLocalization.string("간편 문서")
        case .originalDocument:
            return AppLocalization.string("원본 문서")
        }
    }
}

struct WordDocumentView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: WordDocumentViewModel
    @State private var isEditing = false
    @State private var showsAI = true
    @State private var showsDiscardConfirmation = false
    @State private var isExporting = false
    @State private var exportFile: WordDocumentExportFile?
    @State private var exportError: String?
    @State private var viewMode = WordDocumentViewMode.accessibleDocument

    init(fileURL: URL, originalDocumentID: UUID? = nil) {
        _viewModel = StateObject(
            wrappedValue: WordDocumentViewModel(
                fileURL: fileURL,
                originalDocumentID: originalDocumentID
            )
        )
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView(
                    viewModel.status.isEmpty
                        ? AppLocalization.string("Word 문서를 여는 중…")
                        : viewModel.status
                )
            } else if let error = viewModel.errorDescription,
                      viewModel.blocks.isEmpty {
                ContentUnavailableView(
                    "Word 문서를 열 수 없습니다",
                    systemImage: "doc.badge.ellipsis",
                    description: Text(error)
                )
            } else {
                content
            }
        }
        .navigationTitle(viewModel.fileURL.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .visionCraftNavigationScreen()
        .navigationBarBackButtonHidden(true)
        .visionCraftHandlesBackNavigation()
        .toolbar { toolbarContent }
        .task {
            await viewModel.load()
            if viewModel.isEditableDocument,
               viewModel.blocks.count == 1,
               viewModel.blocks[0].text.isEmpty {
                isEditing = true
                viewMode = .accessibleDocument
            }
        }
        .onChange(of: viewMode) { _, mode in
            let announcement = mode == .accessibleDocument
                ? AppLocalization.string(
                    "간편 문서 보기. 문단과 표 셀을 한 항목씩 탐색합니다."
                )
                : AppLocalization.string(
                    "원본 문서 보기. Word 페이지 레이아웃을 표시합니다."
                )
            UIAccessibility.post(
                notification: .announcement,
                argument: announcement
            )
            if mode == .originalDocument {
                Task { await viewModel.prepareOriginalPreview() }
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportFile,
            contentType: VisionCraftFileTypes.docx,
            defaultFilename: "\(viewModel.documentName)-편집본.docx"
        ) { result in
            exportFile = nil
            switch result {
            case .success:
                viewModel.markExported()
            case .failure(let error):
                exportError = error.localizedDescription
            }
        }
        .alert(
            "저장하지 않은 변경 사항",
            isPresented: $showsDiscardConfirmation
        ) {
            Button("계속 편집", role: .cancel) {}
            Button("변경 사항 버리기", role: .destructive) {
                dismiss()
            }
        } message: {
            Text("저장하지 않은 Word 문서 변경 사항이 있습니다.")
        }
        .alert(
            "저장할 수 없습니다",
            isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )
        ) {
            Button("확인", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            if viewModel.isLegacyReadOnly {
                legacyBanner
            }
            viewModePicker
            if viewMode == .originalDocument {
                originalDocumentView
            } else {
                documentList
                if isEditing, viewModel.isEditableDocument {
                    Divider()
                    editorPanel
                }
            }
            if showsAI, viewModel.isEditableDocument {
                WordAIChatPanel(
                    isAvailable: FirebaseRuntime.isConfigured,
                    catalogProvider: { request in
                        viewModel.makeAIRetrievalCatalog(for: request)
                    },
                    snapshotProvider: { request, catalog, retrieval in
                        viewModel.makeAISnapshot(
                            for: request,
                            catalog: catalog,
                            retrievalPlan: retrieval
                        )
                    },
                    onApply: applyAIPlan
                )
            }
            statusBar
        }
    }

    private var legacyBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.badge.arrow.up")
                .foregroundStyle(VisionCraftUI.primary)
            VStack(alignment: .leading, spacing: 3) {
                Text("DOC 읽기 전용")
                    .font(.headline)
                Text("편집하려면 DOCX 편집본으로 변환합니다. 원본 DOC는 변경하지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(VisionCraftUI.secondaryText)
            }
            Spacer()
            Button("DOCX로 편집") {
                Task {
                    await viewModel.convertLegacyForEditing()
                    if viewModel.isEditableDocument {
                        isEditing = true
                        viewMode = .accessibleDocument
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isSaving)
        }
        .padding(14)
        .background(VisionCraftUI.surfaceVariant)
    }

    private var viewModePicker: some View {
        Picker("보기 방식", selection: $viewMode) {
            ForEach(WordDocumentViewMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(VisionCraftUI.surface)
        .accessibilityHint(
            "간편 문서는 문단 단위로 탐색하고, 원본 문서는 Word 페이지 모양을 표시합니다."
        )
    }

    @ViewBuilder
    private var originalDocumentView: some View {
        if viewModel.isPreparingOriginalPreview {
            VStack(spacing: 12) {
                ProgressView()
                Text("원본 Word 화면을 준비하는 중…")
                    .foregroundStyle(VisionCraftUI.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.originalPreviewErrorDescription {
            ContentUnavailableView(
                "원본 화면을 표시할 수 없습니다",
                systemImage: "doc.badge.ellipsis",
                description: Text(error)
            )
        } else if let previewURL = viewModel.originalPreviewURL {
            WordOriginalDocumentPreview(fileURL: previewURL)
                .id(previewURL)
                .accessibilityLabel("Word 원본 문서 화면")
        } else {
            ProgressView("원본 Word 화면을 준비하는 중…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task { await viewModel.prepareOriginalPreview() }
        }
    }

    private var documentList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.blocks) { block in
                        blockView(block)
                            .id(block.id)
                    }
                }
                .padding(16)
            }
            .onChange(of: viewModel.selectedBlockID) { _, id in
                guard let id else { return }
                withAnimation {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private func blockView(_ block: WordDocumentBlock) -> some View {
        Button {
            viewModel.selectBlock(block.id)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                blockIcon(block)
                    .frame(width: 22)
                    .foregroundStyle(VisionCraftUI.primary)
                VStack(alignment: .leading, spacing: 4) {
                    if let table = block.tableLocation {
                        Text(table.accessibilityDescription)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(VisionCraftUI.secondaryText)
                    }
                    Text(block.text.isEmpty ? "빈 문단" : block.text)
                        .font(blockFont(block))
                        .foregroundStyle(
                            block.text.isEmpty
                                ? VisionCraftUI.secondaryText
                                : VisionCraftUI.primaryText
                        )
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !block.isEditable {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(VisionCraftUI.secondaryText)
                }
            }
            .padding(12)
            .background(
                viewModel.selectedBlockID == block.id
                    ? VisionCraftUI.primary.opacity(0.13)
                    : VisionCraftUI.surface,
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        viewModel.selectedBlockID == block.id
                            ? VisionCraftUI.primary
                            : VisionCraftUI.outline,
                        lineWidth: viewModel.selectedBlockID == block.id ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(block.accessibilityLabel)
        .accessibilityHint(
            block.isEditable
                ? "두 번 탭하면 이 문단을 선택합니다."
                : "자동 필드가 포함된 읽기 전용 문단입니다."
        )
    }

    @ViewBuilder
    private func blockIcon(_ block: WordDocumentBlock) -> some View {
        switch block.kind {
        case .title:
            Image(systemName: "textformat.size.larger")
        case .heading1, .heading2, .heading3:
            Image(systemName: "textformat")
        case .listItem:
            Image(systemName: "list.bullet")
        case .paragraph:
            Image(systemName: "text.alignleft")
        case .tableCell:
            Image(systemName: "tablecells")
        }
    }

    private func blockFont(_ block: WordDocumentBlock) -> Font {
        switch block.kind {
        case .title:
            return .title.bold()
        case .heading1:
            return .title2.bold()
        case .heading2:
            return .title3.bold()
        case .heading3:
            return .headline
        case .listItem, .paragraph, .tableCell:
            return .body
        }
    }

    private var editorPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("선택한 문단 편집")
                    .font(.headline)
                Spacer()
                Picker("문단 스타일", selection: $viewModel.editorStyleID) {
                    Text("본문").tag("Normal")
                    Text("문서 제목").tag("Title")
                    Text("제목 1").tag("Heading1")
                    Text("제목 2").tag("Heading2")
                    Text("제목 3").tag("Heading3")
                }
                .pickerStyle(.menu)
                .disabled(!viewModel.canEditSelectedBlock)
            }
            TextEditor(text: $viewModel.editorText)
                .font(.body)
                .frame(minHeight: 90, maxHeight: 170)
                .padding(8)
                .background(
                    VisionCraftUI.surfaceVariant,
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .disabled(!viewModel.canEditSelectedBlock)
                .accessibilityLabel("선택한 Word 문단 편집")
            HStack {
                if viewModel.selectedBlock?.isEditable == false {
                    Label(
                        "자동 필드가 포함된 문단은 읽기 전용입니다.",
                        systemImage: "lock.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(VisionCraftUI.secondaryText)
                }
                Spacer()
                Button("문단 적용") {
                    viewModel.commitEditorChange()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canEditSelectedBlock)
            }
        }
        .padding(14)
        .background(VisionCraftUI.surface)
    }

    private var statusBar: some View {
        Text(viewModel.status)
            .font(.footnote)
            .foregroundStyle(VisionCraftUI.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(VisionCraftUI.surface)
            .accessibilityLabel(viewModel.status)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarLeading) {
                documentBackButton
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) {
                documentBackButton
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button("실행 취소", systemImage: "arrow.uturn.backward") {
                viewModel.undo()
                refreshOriginalPreviewIfNeeded()
            }
            .disabled(!viewModel.canUndo)

            Button("다시 실행", systemImage: "arrow.uturn.forward") {
                viewModel.redo()
                refreshOriginalPreviewIfNeeded()
            }
            .disabled(!viewModel.canRedo)

            Button(
                isEditing ? "읽기 보기" : "편집",
                systemImage: isEditing ? "doc.text" : "pencil"
            ) {
                if viewModel.isLegacyReadOnly {
                    Task {
                        await viewModel.convertLegacyForEditing()
                        isEditing = viewModel.isEditableDocument
                        if isEditing {
                            viewMode = .accessibleDocument
                        }
                    }
                } else {
                    if viewMode == .originalDocument {
                        viewMode = .accessibleDocument
                        isEditing = true
                    } else if isEditing {
                        viewModel.commitEditorChange()
                        isEditing = false
                    } else {
                        isEditing = true
                    }
                }
            }

            Button("AI 도우미", systemImage: "sparkles") {
                showsAI.toggle()
            }
            .disabled(!viewModel.isEditableDocument)

            Button("저장", systemImage: "square.and.arrow.down") {
                if viewModel.requiresSaveAs {
                    beginExport()
                } else {
                    Task {
                        await viewModel.save()
                        if viewMode == .originalDocument {
                            await viewModel.prepareOriginalPreview()
                        }
                    }
                }
            }
            .disabled(
                !viewModel.isEditableDocument
                    || viewModel.isSaving
                    || (!viewModel.hasUnsavedChanges && !viewModel.requiresSaveAs)
            )
        }
    }

    private var documentBackButton: some View {
        VisionCraftBackButton {
            viewModel.commitEditorChange()
            if viewModel.hasUnsavedChanges {
                showsDiscardConfirmation = true
            } else {
                dismiss()
            }
        }
    }

    private func beginExport() {
        Task {
            do {
                exportFile = WordDocumentExportFile(
                    data: try await viewModel.exportData()
                )
                isExporting = true
            } catch {
                exportError = error.localizedDescription
            }
        }
    }

    private func applyAIPlan(_ plan: WordAIValidatedPlan) throws -> String {
        let result = try viewModel.applyAIPlan(plan)
        refreshOriginalPreviewIfNeeded()
        return result
    }

    private func refreshOriginalPreviewIfNeeded() {
        guard viewMode == .originalDocument else { return }
        Task { await viewModel.prepareOriginalPreview() }
    }
}
