import RivoDocumentEngine
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DocumentLibraryViewModel:
    ObservableObject
{
    static let maximumAppFolderItems = 500

    @Published private(set) var recentDocuments:
        [RecentOriginalDocument] = []
    @Published private(set) var appFolderDocuments:
        [AuthorizedDocumentItem] = []
    @Published private(set) var isAppFolderTruncated =
        false
    @Published var errorDescription: String?

    /// 앱 샌드박스의 Documents 폴더. 파일 앱에서는
    /// 나의 iPad > VisionCraft 로 보이는 위치와 같다.
    let appFolderURL: URL?

    private let recentStore:
        RecentOriginalDocumentStore
    private var didLoad = false
    private var isRefreshingAppFolder = false

    init(
        recentStore:
            RecentOriginalDocumentStore =
                .shared,
        appFolderURL: URL? =
            FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first
    ) {
        self.recentStore = recentStore
        self.appFolderURL = appFolderURL
    }

    func load() async {
        guard !didLoad else { return }
        didLoad = true
        await refreshAll()
    }

    func refreshAll() async {
        await refreshRecentDocuments()
        await refreshAppFolderDocuments()
    }

    func refreshRecentDocuments() async {
        recentDocuments = await recentStore
            .documents()
    }

    func refreshAppFolderDocuments() async {
        guard let appFolderURL,
              !isRefreshingAppFolder else { return }
        isRefreshingAppFolder = true
        defer { isRefreshingAppFolder = false }
        let maximum = Self.maximumAppFolderItems
        let result = await Task.detached(
            priority: .userInitiated
        ) {
            try? AuthorizedDocumentSearch.scan(
                rootURL: appFolderURL,
                maximumResults: maximum
            )
        }.value
        appFolderDocuments = result?.items ?? []
        isAppFolderTruncated =
            result?.isTruncated ?? false
    }

    func appFolderDocumentURL(
        for item: AuthorizedDocumentItem
    ) -> URL? {
        appFolderURL?.appendingPathComponent(
            item.relativePath
        )
    }

    func removeRecentDocument(
        _ item: RecentOriginalDocument
    ) async {
        await recentStore.remove(id: item.id)
        await refreshRecentDocuments()
    }
}

private enum NewDocumentKind: String, Identifiable {
    case excel
    case word
    case hangul

    var id: String { rawValue }

    var contentType: UTType {
        switch self {
        case .excel:
            return VisionCraftFileTypes.xlsx
        case .word:
            return VisionCraftFileTypes.docx
        case .hangul:
            return VisionCraftFileTypes.hwpx
        }
    }

    var defaultFilename: String {
        switch self {
        case .excel:
            return AppLocalization.string("새 스프레드시트") + ".xlsx"
        case .word:
            return AppLocalization.string("새 Word 문서") + ".docx"
        case .hangul:
            return AppLocalization.string("새 한글 문서") + ".hwpx"
        }
    }

    func makeData() throws -> Data {
        switch self {
        case .excel:
            return try ExcelWorkbookDocument.blankWorkbookData()
        case .word:
            return try LegacyDOCXConverter.convert(text: "")
        case .hangul:
            return try LegacyHWPXConverter.convert(text: "")
        }
    }
}

struct DocumentLibraryView: View {
    @EnvironmentObject private var appRouter:
        AppRouter
    @StateObject private var viewModel =
        DocumentLibraryViewModel()
    @State private var isFilePickerPresented =
        false
    @State private var isNewDocumentTypePickerPresented =
        false
    @State private var isNewDocumentExporterPresented =
        false
    @State private var newDocumentKind =
        NewDocumentKind.excel
    @State private var newDocument:
        NewOfficeFileDocument?

    var body: some View {
        List {
            Section {
                Button {
                    isNewDocumentTypePickerPresented = true
                } label: {
                    Label(
                        "새 문서 만들기",
                        systemImage: "square.and.pencil"
                    )
                }
                .accessibilityHint(
                    "Excel, Word 또는 한글 문서 형식을 선택해 새 문서를 만듭니다."
                )

                Button {
                    isFilePickerPresented = true
                } label: {
                    Label(
                        "파일 불러오기",
                        systemImage:
                            "doc.badge.plus"
                    )
                }
                .accessibilityHint(
                    "파일 앱에서 문서 하나를 선택해 원본 위치에서 엽니다."
                )
                .fileImporter(
                    isPresented:
                        $isFilePickerPresented,
                    allowedContentTypes:
                        VisionCraftFileTypes.documents,
                    allowsMultipleSelection: false
                ) { result in
                    handleFilePickerResult(result)
                }
            } footer: {
                Text(
                    "새 Excel, Word, 한글 문서를 만들거나 기존 문서를 불러올 수 있습니다."
                )
            }

            if !viewModel.recentDocuments.isEmpty {
                Section {
                    ForEach(
                        viewModel.recentDocuments
                    ) { item in
                        recentDocumentRow(item)
                    }
                } header: {
                    Text("최근에 연 문서")
                } footer: {
                    Text(
                        "처음 선택한 원본 파일을 다시 열며, 지원되는 수정 내용은 원본에 저장합니다."
                    )
                }
            }

            if viewModel.appFolderURL != nil {
                Section {
                    if viewModel.appFolderDocuments.isEmpty {
                        Text("아직 앱 문서 폴더에 문서가 없습니다.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(
                            viewModel.appFolderDocuments
                        ) { item in
                            appFolderDocumentRow(item)
                        }
                    }
                } header: {
                    Text("앱 문서 폴더")
                } footer: {
                    if viewModel.isAppFolderTruncated {
                        Text(
                            AppLocalization.format(
                                "문서가 많아 최근 수정된 %lld개만 표시합니다.",
                                DocumentLibraryViewModel
                                    .maximumAppFolderItems
                            )
                        )
                    } else {
                        Text(
                            "파일 앱의 나의 iPad > VisionCraft 폴더와 같은 위치입니다. 파일 앱, USB, AirDrop으로 넣은 문서가 여기에 표시됩니다."
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .visionCraftListScreen()
        .navigationTitle("문서 작업")
        .refreshable {
            await viewModel.refreshAll()
        }
        .confirmationDialog(
            "새 문서 만들기",
            isPresented: $isNewDocumentTypePickerPresented,
            titleVisibility: .visible
        ) {
            Button {
                prepareNewDocument(.excel)
            } label: {
                Label("Excel (.xlsx)", systemImage: "tablecells")
            }
            Button {
                prepareNewDocument(.word)
            } label: {
                Label("Word (.docx)", systemImage: "doc.text")
            }
            Button {
                prepareNewDocument(.hangul)
            } label: {
                Label("한글 (.hwpx)", systemImage: "doc.richtext")
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("만들 문서 형식을 선택하세요.")
        }
        .fileExporter(
            isPresented: $isNewDocumentExporterPresented,
            document: newDocument,
            contentType: newDocumentKind.contentType,
            defaultFilename: newDocumentKind.defaultFilename
        ) { result in
            handleNewDocumentExportResult(result)
        }
        .task {
            await viewModel.load()
        }
        .onAppear {
            Task {
                await viewModel.refreshAll()
            }
        }
        .alert(
            "문서를 열 수 없습니다",
            isPresented: Binding(
                get: {
                    viewModel
                        .errorDescription != nil
                },
                set: { isPresented in
                    if !isPresented {
                        viewModel
                            .errorDescription = nil
                    }
                }
            )
        ) {
            Button("확인", role: .cancel) {
                viewModel.errorDescription = nil
            }
        } message: {
            Text(viewModel.errorDescription ?? "")
        }
    }

    private func prepareNewDocument(
        _ kind: NewDocumentKind
    ) {
        do {
            newDocumentKind = kind
            newDocument = NewOfficeFileDocument(
                data: try kind.makeData()
            )
            isNewDocumentExporterPresented = true
        } catch {
            viewModel.errorDescription = error.localizedDescription
        }
    }

    private func handleNewDocumentExportResult(
        _ result: Result<URL, Error>
    ) {
        newDocument = nil
        Task {
            do {
                let fileURL = try result.get()
                appRouter.route = try await
                    PersistentOriginalDocumentOpening.documentLibraryRoute(
                        for: fileURL
                    )
                await viewModel.refreshRecentDocuments()
            } catch {
                let nsError = error as NSError
                guard nsError.code != NSUserCancelledError else {
                    return
                }
                viewModel.errorDescription = error.localizedDescription
            }
        }
    }

    private func handleFilePickerResult(
        _ result: Result<[URL], Error>
    ) {
        Task {
            do {
                guard let sourceURL =
                        try result.get().first
                else {
                    return
                }
                appRouter.route =
                    try await
                        PersistentOriginalDocumentOpening
                    .documentLibraryRoute(
                        for: sourceURL
                    )
                await viewModel
                    .refreshRecentDocuments()
            } catch {
                viewModel.errorDescription =
                    error.localizedDescription
            }
        }
    }

    private func openAppFolderDocument(
        _ item: AuthorizedDocumentItem
    ) {
        guard let sourceURL =
                viewModel.appFolderDocumentURL(
                    for: item
                )
        else {
            return
        }
        Task {
            do {
                appRouter.route =
                    try await
                        PersistentOriginalDocumentOpening
                    .documentLibraryRoute(
                        for: sourceURL
                    )
                await viewModel
                    .refreshRecentDocuments()
            } catch {
                viewModel.errorDescription =
                    error.localizedDescription
            }
        }
    }

    private func appFolderSubtitle(
        _ item: AuthorizedDocumentItem
    ) -> String {
        let folder = (item.relativePath as NSString)
            .deletingLastPathComponent
        var parts: [String] = [
            folder.isEmpty
                ? AppLocalization.string("앱 문서 폴더")
                : folder
        ]
        if let fileSize = item.fileSize {
            parts.append(
                ByteCountFormatter.string(
                    fromByteCount: fileSize,
                    countStyle: .file
                )
            )
        }
        return parts.joined(separator: " · ")
    }

    private func appFolderDocumentRow(
        _ item: AuthorizedDocumentItem
    ) -> some View {
        Button {
            openAppFolderDocument(item)
        } label: {
            HStack(spacing: 14) {
                documentTypeBadge(item.pathExtension)

                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {
                    Text(item.name)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(appFolderSubtitle(item))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if let modificationDate =
                    item.modificationDate
                {
                    Text(
                        modificationDate,
                        format: .dateTime
                            .year()
                            .month()
                            .day()
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(item.name), \(appFolderSubtitle(item))"
        )
        .accessibilityHint(
            "앱 문서 폴더의 문서를 원본 위치에서 엽니다."
        )
    }

    private func documentTypeBadge(
        _ pathExtension: String
    ) -> some View {
        Text(
            pathExtension.isEmpty
                ? "문서"
                : pathExtension.uppercased()
        )
        .font(.caption.bold())
        .foregroundStyle(.white)
        .frame(width: 52, height: 42)
        .background(Color.indigo)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 9,
                style: .continuous
            )
        )
    }

    private func recentDocumentRow(
        _ item: RecentOriginalDocument
    ) -> some View {
        Button {
            appRouter.route = .originalDocument(
                documentID: item.id
            )
        } label: {
            HStack(spacing: 14) {
                documentTypeBadge(item.pathExtension)

                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {
                    Text(item.displayName)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(item.locationName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(
                    item.lastOpenedAt,
                    format: .dateTime
                        .year()
                        .month()
                        .day()
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(item.displayName), \(item.locationName)"
        )
        .accessibilityHint(
            "탐색기를 열지 않고 원본 문서를 다시 엽니다."
        )
        .swipeActions(edge: .trailing) {
            Button(
                "최근 목록에서 제거",
                role: .destructive
            ) {
                Task {
                    await viewModel
                        .removeRecentDocument(item)
                }
            }
        }
    }
}

private struct NewOfficeFileDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [
            VisionCraftFileTypes.xlsx,
            VisionCraftFileTypes.docx,
            VisionCraftFileTypes.hwpx,
        ]
    }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(
        configuration: WriteConfiguration
    ) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
