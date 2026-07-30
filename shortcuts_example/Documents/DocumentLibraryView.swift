import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DocumentLibraryViewModel:
    ObservableObject
{
    @Published private(set) var folderName:
        String?
    @Published private(set) var items:
        [AuthorizedDocumentItem] = []
    @Published private(set) var isLoading =
        false
    @Published private(set) var isTruncated =
        false
    @Published var searchQuery = ""
    @Published var errorDescription: String?

    private let library:
        AuthorizedDocumentLibrary
    private var didLoad = false

    init(
        library:
            AuthorizedDocumentLibrary =
                .shared
    ) {
        self.library = library
    }

    var filteredItems:
        [AuthorizedDocumentItem] {
        AuthorizedDocumentSearch.filter(
            items,
            query: searchQuery
        )
    }

    func load() async {
        guard !didLoad else {
            return
        }
        didLoad = true
        folderName = await library.folderName()
        guard folderName != nil else {
            return
        }
        await refresh()
    }

    func authorize(
        _ folderURL: URL
    ) async {
        await performScan {
            try await library.authorize(
                folderURL: folderURL
            )
        }
        folderName = await library.folderName()
    }

    func refresh() async {
        await performScan {
            try await library.refresh()
        }
    }

    func importDocument(
        _ item: AuthorizedDocumentItem
    ) async -> URL? {
        isLoading = true
        defer {
            isLoading = false
        }
        do {
            return try await library
                .importDocument(
                    relativePath:
                        item.relativePath
                )
        } catch {
            errorDescription =
                error.localizedDescription
            return nil
        }
    }

    func forgetFolder() async {
        await library.forgetFolder()
        folderName = nil
        items = []
        searchQuery = ""
        isTruncated = false
        errorDescription = nil
    }

    private func performScan(
        _ operation:
            () async throws
                -> AuthorizedDocumentSearchResult
    ) async {
        isLoading = true
        errorDescription = nil
        defer {
            isLoading = false
        }
        do {
            let result = try await operation()
            items = result.items
            isTruncated = result.isTruncated
        } catch {
            errorDescription =
                error.localizedDescription
        }
    }
}

struct DocumentLibraryView: View {
    @EnvironmentObject private var appRouter:
        AppRouter
    @StateObject private var viewModel =
        DocumentLibraryViewModel()
    @State private var isFolderPickerPresented =
        false
    @State private var isFilePickerPresented =
        false
    @State private var confirmsForget = false

    var body: some View {
        List {
            Section {
                Button {
                    isFilePickerPresented = true
                } label: {
                    Label(
                        "파일 하나 선택",
                        systemImage:
                            "doc.badge.plus"
                    )
                }
                .accessibilityHint(
                    "Files에서 파일 하나를 바로 선택해 엽니다."
                )
            } footer: {
                Text(
                    "사진·EPUB 또는 문서 하나를 바로 열 수 있습니다."
                )
            }

            Section("허용된 폴더") {
                if let folderName =
                        viewModel.folderName {
                    Label(
                        folderName,
                        systemImage: "folder"
                    )
                    Button {
                        isFolderPickerPresented =
                            true
                    } label: {
                        Label(
                            "폴더 다시 선택",
                            systemImage:
                                "folder.badge.plus"
                        )
                    }
                    Button {
                        Task {
                            await viewModel.refresh()
                        }
                    } label: {
                        Label(
                            "문서 목록 새로고침",
                            systemImage:
                                "arrow.clockwise"
                        )
                    }
                    .disabled(viewModel.isLoading)
                    Button(
                        role: .destructive
                    ) {
                        confirmsForget = true
                    } label: {
                        Label(
                            "폴더 권한 지우기",
                            systemImage:
                                "folder.badge.minus"
                        )
                    }
                } else {
                    Text(
                        "iPadOS에서는 사용자가 허용한 폴더 안에서만 문서를 검색할 수 있습니다."
                    )
                    .foregroundStyle(.secondary)
                    Button {
                        isFolderPickerPresented =
                            true
                    } label: {
                        Label(
                            "검색할 폴더 선택",
                            systemImage:
                                "folder.badge.plus"
                        )
                    }
                }
            }

            if viewModel.folderName != nil {
                Section(
                    "최근 문서"
                ) {
                    if viewModel.isLoading {
                        HStack {
                            Spacer()
                            ProgressView(
                                "문서 검색 중…"
                            )
                            Spacer()
                        }
                    } else if
                        viewModel.items.isEmpty
                    {
                        Text(
                            "선택한 폴더에서 지원되는 문서를 찾지 못했습니다."
                        )
                        .foregroundStyle(
                            .secondary
                        )
                    } else if viewModel
                        .filteredItems.isEmpty
                    {
                        Text(
                            "검색 결과가 없습니다."
                        )
                        .foregroundStyle(
                            .secondary
                        )
                    } else {
                        ForEach(
                            viewModel
                                .filteredItems
                        ) {
                            item in
                            documentRow(item)
                        }
                    }

                    if viewModel.isTruncated {
                        Label(
                            "문서가 많아 최근 5,000개만 표시합니다.",
                            systemImage:
                                "exclamationmark.triangle"
                        )
                        .foregroundStyle(.orange)
                    }
                }
            }
        }
        .navigationTitle("파일과 문서")
        .searchable(
            text: $viewModel.searchQuery,
            prompt: "파일 이름 또는 폴더 검색"
        )
        .task {
            await viewModel.load()
        }
        .fileImporter(
            isPresented:
                $isFolderPickerPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) {
            result in
            Task {
                do {
                    guard let folderURL =
                            try result.get()
                            .first else {
                        return
                    }
                    await viewModel.authorize(
                        folderURL
                    )
                } catch {
                    viewModel
                        .errorDescription =
                        error.localizedDescription
                }
            }
        }
        .fileImporter(
            isPresented:
                $isFilePickerPresented,
            allowedContentTypes:
                VisionCraftFileTypes.openable,
            allowsMultipleSelection: false
        ) {
            result in
            Task {
                do {
                    guard let sourceURL =
                            try result.get()
                            .first else {
                        return
                    }
                    appRouter.route =
                        try await
                            LocalFileOpening
                            .route(
                                for: sourceURL
                            )
                } catch {
                    viewModel
                        .errorDescription =
                        error.localizedDescription
                }
            }
        }
        .confirmationDialog(
            "저장된 폴더 권한을 지울까요?",
            isPresented: $confirmsForget
        ) {
            Button(
                "폴더 권한 지우기",
                role: .destructive
            ) {
                Task {
                    await viewModel
                        .forgetFolder()
                }
            }
            Button(
                "취소",
                role: .cancel
            ) {}
        } message: {
            Text(
                "원본 파일은 삭제하지 않고 VisionCraft가 기억한 폴더 접근 권한과 목록만 지웁니다."
            )
        }
        .alert(
            "문서를 열 수 없습니다",
            isPresented: Binding(
                get: {
                    viewModel
                        .errorDescription != nil
                },
                set: {
                    isPresented in
                    if !isPresented {
                        viewModel
                            .errorDescription =
                            nil
                    }
                }
            )
        ) {
            Button(
                "확인",
                role: .cancel
            ) {
                viewModel.errorDescription =
                    nil
            }
        } message: {
            Text(
                viewModel.errorDescription
                ?? ""
            )
        }
    }

    private func documentRow(
        _ item: AuthorizedDocumentItem
    ) -> some View {
        Button {
            Task {
                guard let importedURL =
                        await viewModel
                        .importDocument(item)
                else {
                    return
                }
                appRouter.route =
                    .localDocument(
                        fileURL: importedURL
                    )
            }
        } label: {
            HStack(spacing: 14) {
                Text(
                    item.pathExtension
                        .uppercased()
                )
                .font(
                    .caption
                    .bold()
                )
                .foregroundStyle(.white)
                .frame(
                    width: 52,
                    height: 42
                )
                .background(
                    Color.indigo
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 9,
                        style: .continuous
                    )
                )

                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {
                    Text(item.name)
                        .foregroundStyle(
                            .primary
                        )
                        .lineLimit(2)
                    Text(item.relativePath)
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                        .lineLimit(2)
                }
                Spacer()
                VStack(
                    alignment: .trailing,
                    spacing: 4
                ) {
                    if let modificationDate =
                            item.modificationDate {
                        Text(
                            modificationDate,
                            format:
                                .dateTime
                                .year()
                                .month()
                                .day()
                        )
                    }
                    if let fileSize =
                            item.fileSize {
                        Text(
                            ByteCountFormatter
                                .string(
                                    fromByteCount:
                                        fileSize,
                                    countStyle:
                                        .file
                                )
                        )
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(item.name), \(item.pathExtension.uppercased())"
        )
        .accessibilityHint(
            "문서를 앱 안으로 복사해 엽니다."
        )
    }
}
