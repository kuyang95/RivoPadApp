import SwiftUI
import UniformTypeIdentifiers

/// Android `FileSelectScreen`: AI 문서 진입, 새 대화와 기록, 최근 문서 검색.
/// iPadOS에서는 사용자가 Files에서 고른 문서 또는 허용한 폴더만 나열한다.
struct AIDocumentSelectionView: View {
    @EnvironmentObject private var appRouter: AppRouter
    @Environment(\.dismiss) private var dismiss

    @State private var documents: [AuthorizedDocumentItem] = []
    @State private var folderName: String?
    @State private var query = ""
    @State private var isFilePickerPresented = false
    @State private var isFolderPickerPresented = false
    @State private var isLoading = false
    @State private var isImporting = false
    @State private var errorMessage: String?

    private let supportedExtensions: Set<String> = [
        "pdf", "xlsx", "xls", "hwp", "hwpx", "txt",
    ]

    private var filteredDocuments: [AuthorizedDocumentItem] {
        AuthorizedDocumentSearch.filter(
            documents.filter { supportedExtensions.contains($0.pathExtension) },
            query: query
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                VisionCraftScreenTitleRow(title: "파일 선택") {
                    dismiss()
                }

                VisionCraftPrimaryActionPanel(
                    icon: "doc.text",
                    title: "AI 문서 질의",
                    description: "기기 안의 PDF, 엑셀, 한글, TXT 문서를 골라 AI에게 질문할 수 있습니다.",
                    primaryTitle: "새 대화",
                    secondaryTitle: "대화 기록",
                    onPrimary: { appRouter.route = .localChat(conversationID: nil) },
                    onSecondary: { appRouter.route = .chatHistory }
                )

                HStack(spacing: 12) {
                    Button("파일 선택") {
                        isFilePickerPresented = true
                    }
                    .buttonStyle(VisionCraftAndroidButtonStyle(emphasized: true))

                    Button(AppLocalization.string(folderName == nil ? "폴더 선택" : "폴더 변경")) {
                        isFolderPickerPresented = true
                    }
                    .buttonStyle(VisionCraftAndroidButtonStyle())
                }
                .disabled(isImporting)

                if folderName != nil {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .accessibilityHidden(true)
                        TextField(
                            AppLocalization.string("파일 이름이나 폴더명"),
                            text: $query
                        )
                        .accessibilityLabel("문서 검색")
                    }
                    .padding(14)
                    .frame(minHeight: VisionCraftUI.minTouchTarget)
                    .visionCraftHomeSurface(cornerRadius: 14)

                    VisionCraftHomeSectionHeader(
                        title: "최근 문서",
                        tone: .ai
                    )

                    if isLoading {
                        ProgressView("파일을 불러오는 중입니다..")
                            .frame(maxWidth: .infinity, minHeight: 80)
                    } else if filteredDocuments.isEmpty {
                        Text(AppLocalization.string(query.isEmpty ? "파일이 없습니다" : "일치하는 문서가 없습니다"))
                            .visionCraftAndroidText(16)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    } else {
                        ForEach(filteredDocuments) { item in
                            AIDocumentSelectionRow(
                                item: item,
                                isImporting: isImporting,
                                onOpen: { Task { await openDocument(item) } },
                                onOpenOriginal: { Task { await openOriginal(item) } }
                            )
                        }
                    }
                }

                if isImporting {
                    ProgressView("첨부를 읽는 중입니다. 잠시만 기다려주세요.")
                        .frame(maxWidth: .infinity, minHeight: 64)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(VisionCraftUI.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .fileImporter(
            isPresented: $isFilePickerPresented,
            allowedContentTypes: [.data]
        ) { result in
            switch result {
            case .success(let url):
                Task { await importForChat(url) }
            case .failure(let error):
                showImportError(error)
            }
        }
        .fileImporter(
            isPresented: $isFolderPickerPresented,
            allowedContentTypes: [.folder]
        ) { result in
            switch result {
            case .success(let url):
                Task { await authorizeFolder(url) }
            case .failure(let error):
                showImportError(error)
            }
        }
        .alert("파일을 열 수 없습니다", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task { await refreshFolder() }
    }

    private func refreshFolder() async {
        folderName = await AuthorizedDocumentLibrary.shared.folderName()
        guard folderName != nil else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            documents = try await AuthorizedDocumentLibrary.shared.refresh().items
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func authorizeFolder(_ url: URL) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await AuthorizedDocumentLibrary.shared.authorize(folderURL: url)
            folderName = await AuthorizedDocumentLibrary.shared.folderName()
            documents = result.items
            query = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openDocument(_ item: AuthorizedDocumentItem) async {
        isImporting = true
        defer { isImporting = false }
        do {
            let url = try await AuthorizedDocumentLibrary.shared.importDocument(relativePath: item.relativePath)
            try await routeForChat(url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 행의 열기 버튼: AI 대화 대신 엑셀 편집기·한글 문서 화면에서 원본을 연다(문서 작업과 같은 경로).
    private func openOriginal(_ item: AuthorizedDocumentItem) async {
        isImporting = true
        defer { isImporting = false }
        do {
            let record = try await AuthorizedDocumentLibrary.shared
                .registerOriginalDocument(relativePath: item.relativePath)
            appRouter.route = .originalDocument(documentID: record.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importForChat(_ url: URL) async {
        isImporting = true
        defer { isImporting = false }
        do {
            try await routeForChat(url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func routeForChat(_ url: URL) async throws {
        let store = ChatAttachmentStore.shared
        let attachment: StoredChatFileAttachment
        switch url.pathExtension.lowercased() {
        case "pdf":
            attachment = try await store.importPDF(from: url)
        case "xlsx":
            attachment = try await store.importSpreadsheet(from: url)
        case "xls":
            attachment = try await store.importLegacySpreadsheet(from: url)
        case "hwp":
            attachment = try await store.importHWP(from: url)
        case "hwpx":
            attachment = try await store.importHWPX(from: url)
        case "txt":
            let text = try await store.readTextDocument(from: url)
            appRouter.route = .sharedTextQuestion(
                text: text,
                automaticallyStartsVoiceInput: false
            )
            return
        default:
            throw AuthorizedDocumentLibraryError.unsupportedDocument
        }
        appRouter.route = .sharedAttachmentQuestion(
            attachment: attachment,
            automaticallyStartsVoiceInput: false
        )
    }

    private func showImportError(_ error: Error) {
        let nsError = error as NSError
        guard nsError.domain != NSCocoaErrorDomain || nsError.code != NSUserCancelledError else {
            return
        }
        errorMessage = error.localizedDescription
    }
}

/// A recent document row of AI 문서 선택: the row opens the AI chat; an xlsx, hwp or hwpx row also has a
/// button at its end opening the original in its editor (Android `FileSelectScreen.DocumentFileRow`).
struct AIDocumentSelectionRow: View {
    let item: AuthorizedDocumentItem
    let isImporting: Bool
    let onOpen: () -> Void
    let onOpenOriginal: () -> Void

    var body: some View {
        let opener = AIDocumentOriginalOpener(pathExtension: item.pathExtension)
        return Button {
            onOpen()
        } label: {
            HStack(spacing: 14) {
                Text(String(item.pathExtension.uppercased().prefix(3)))
                    .visionCraftAndroidText(14, weight: .bold)
                    .frame(width: 52, height: 52)
                    .background(VisionCraftUI.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .visionCraftAndroidText(18, weight: .semibold)
                    Text(item.relativePath)
                        .visionCraftAndroidText(14)
                        .foregroundStyle(VisionCraftUI.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let date = item.modificationDate {
                    Text(date, format: .dateTime.year().month().day())
                        .visionCraftAndroidText(14)
                        .foregroundStyle(VisionCraftUI.secondaryText)
                }
                if opener != nil {
                    // 위에 겹친 열기 버튼 자리.
                    Color.clear
                        .frame(width: VisionCraftUI.minTouchTarget - 8)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(VisionCraftUI.primaryText)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            .visionCraftHomeSurface()
        }
        .buttonStyle(VisionCraftHomePressStyle())
        .disabled(isImporting)
        .accessibilityLabel("\(item.name). \(item.relativePath)")
        .overlay(alignment: .trailing) {
            if let opener {
                Button {
                    onOpenOriginal()
                } label: {
                    Image(systemName: opener.systemImage)
                        .font(.title3)
                        .foregroundStyle(VisionCraftUI.icon)
                        .frame(
                            width: VisionCraftUI.minTouchTarget,
                            height: VisionCraftUI.minTouchTarget
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                .disabled(isImporting)
                .opacity(isImporting ? 0.38 : 1)
                .accessibilityLabel(AppLocalization.string(opener.labelKey))
            }
        }
    }
}

/// Android `FileSelectScreen.DocumentFileRow`의 행 끝 아이콘 버튼: xlsx는 엑셀 편집기로,
/// hwp·hwpx는 한글 문서 화면으로 연다. 다른 형식은 버튼이 없다.
nonisolated struct AIDocumentOriginalOpener: Equatable {
    let systemImage: String
    let labelKey: String

    init?(pathExtension: String) {
        switch pathExtension.lowercased() {
        case "xlsx":
            systemImage = "pencil"
            labelKey = "aiDocument.openSpreadsheetEditor"
        case "hwp", "hwpx":
            systemImage = "book"
            labelKey = "aiDocument.readHangul"
        default:
            return nil
        }
    }
}
