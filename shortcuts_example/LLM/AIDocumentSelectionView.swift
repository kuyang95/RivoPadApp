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
                    secondaryTitle: "대화기록",
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
                            Button {
                                Task { await openDocument(item) }
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
                                }
                                .foregroundStyle(VisionCraftUI.primaryText)
                                .padding(16)
                                .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                                .visionCraftHomeSurface()
                            }
                            .buttonStyle(VisionCraftHomePressStyle())
                            .disabled(isImporting)
                            .accessibilityLabel("\(item.name). \(item.relativePath)")
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
