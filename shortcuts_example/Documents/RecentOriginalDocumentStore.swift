import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

nonisolated struct RecentOriginalDocument:
    Codable,
    Equatable,
    Hashable,
    Identifiable,
    Sendable
{
    let id: UUID
    var displayName: String
    var pathExtension: String
    var locationName: String
    var sourceIdentifier: String
    var bookmarkData: Data
    var lastOpenedAt: Date
}

nonisolated enum RecentOriginalDocumentError:
    Error,
    LocalizedError,
    Equatable,
    Sendable
{
    case missingRecord
    case invalidBookmark
    case unavailable

    var errorDescription: String? {
        switch self {
        case .missingRecord:
            return AppLocalization.string(
                "최근 문서 목록에서 파일을 찾을 수 없습니다."
            )
        case .invalidBookmark:
            return AppLocalization.string(
                "파일 접근 권한이 만료되었습니다. 파일을 한 번 다시 선택해 주세요."
            )
        case .unavailable:
            return AppLocalization.string(
                "원본 파일을 사용할 수 없습니다. USB 또는 파일 저장 위치를 확인해 주세요."
            )
        }
    }
}

/// Keeps a security-scoped URL active for the complete lifetime of a reader
/// or editor screen. The original file URL is never replaced by an app copy.
nonisolated final class OriginalDocumentAccessSession:
    @unchecked Sendable
{
    let url: URL
    private let didStartAccess: Bool

    init(url: URL) {
        self.url = url
        didStartAccess = url
            .startAccessingSecurityScopedResource()
    }

    deinit {
        if didStartAccess {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

actor RecentOriginalDocumentStore {
    static let shared = RecentOriginalDocumentStore()

    private static let storageKey =
        "RecentOriginalDocumentStore.records.v1"
    private static let maximumRecordCount = 100

    private let defaults: UserDefaults
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = storageKey
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func documents() -> [RecentOriginalDocument] {
        loadRecords().sorted {
            $0.lastOpenedAt > $1.lastOpenedAt
        }
    }

    func register(
        fileURL: URL
    ) throws -> RecentOriginalDocument {
        let didAccess = fileURL
            .startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                fileURL
                    .stopAccessingSecurityScopedResource()
            }
        }

        let values = try fileURL.resourceValues(
            forKeys: [
                .isRegularFileKey,
                .nameKey,
            ]
        )
        guard values.isRegularFile == true else {
            throw RecentOriginalDocumentError
                .unavailable
        }

        let bookmark = try makeBookmark(
            for: fileURL
        )
        let identifier = sourceIdentifier(
            for: fileURL
        )
        var records = loadRecords()
        let now = Date()
        let record: RecentOriginalDocument

        if let index = records.firstIndex(
            where: {
                $0.sourceIdentifier == identifier
            }
        ) {
            records[index].displayName =
                values.name
                ?? fileURL.lastPathComponent
            records[index].pathExtension =
                fileURL.pathExtension.lowercased()
            records[index].locationName =
                locationName(for: fileURL)
            records[index].bookmarkData = bookmark
            records[index].lastOpenedAt = now
            record = records[index]
        } else {
            record = RecentOriginalDocument(
                id: UUID(),
                displayName:
                    values.name
                    ?? fileURL.lastPathComponent,
                pathExtension:
                    fileURL.pathExtension.lowercased(),
                locationName:
                    locationName(for: fileURL),
                sourceIdentifier: identifier,
                bookmarkData: bookmark,
                lastOpenedAt: now
            )
            records.append(record)
        }

        saveRecords(records)
        return record
    }

    func open(
        id: UUID
    ) throws -> (
        record: RecentOriginalDocument,
        session: OriginalDocumentAccessSession
    ) {
        var records = loadRecords()
        guard let index = records.firstIndex(
            where: { $0.id == id }
        ) else {
            throw RecentOriginalDocumentError
                .missingRecord
        }

        var isStale = false
        let resolvedURL: URL
        do {
            resolvedURL = try URL(
                resolvingBookmarkData:
                    records[index].bookmarkData,
                options: [
                    .withoutUI,
                    .withoutImplicitStartAccessing,
                ],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            throw RecentOriginalDocumentError
                .invalidBookmark
        }

        let session = OriginalDocumentAccessSession(
            url: resolvedURL
        )
        do {
            let values = try resolvedURL
                .resourceValues(
                    forKeys: [
                        .isRegularFileKey,
                        .nameKey,
                    ]
                )
            guard values.isRegularFile == true
            else {
                throw RecentOriginalDocumentError
                    .unavailable
            }
            records[index].displayName =
                values.name
                ?? resolvedURL.lastPathComponent
        } catch let error as
            RecentOriginalDocumentError {
            throw error
        } catch {
            throw RecentOriginalDocumentError
                .unavailable
        }

        if isStale,
           let refreshed = try? makeBookmark(
               for: resolvedURL
           ) {
            records[index].bookmarkData = refreshed
        }
        records[index].sourceIdentifier =
            sourceIdentifier(for: resolvedURL)
        records[index].locationName =
            locationName(for: resolvedURL)
        records[index].lastOpenedAt = Date()
        let record = records[index]
        saveRecords(records)
        return (record, session)
    }

    func remove(id: UUID) {
        var records = loadRecords()
        records.removeAll { $0.id == id }
        saveRecords(records)
    }

    func refreshBookmark(
        id: UUID,
        fileURL: URL
    ) throws {
        var records = loadRecords()
        guard let index = records.firstIndex(
            where: { $0.id == id }
        ) else {
            throw RecentOriginalDocumentError
                .missingRecord
        }
        let values = try fileURL.resourceValues(
            forKeys: [
                .isRegularFileKey,
                .nameKey,
            ]
        )
        guard values.isRegularFile == true else {
            throw RecentOriginalDocumentError
                .unavailable
        }
        records[index].displayName =
            values.name
            ?? fileURL.lastPathComponent
        records[index].bookmarkData = try makeBookmark(
            for: fileURL
        )
        records[index].sourceIdentifier =
            sourceIdentifier(for: fileURL)
        records[index].locationName =
            locationName(for: fileURL)
        records[index].lastOpenedAt = Date()
        saveRecords(records)
    }

    func removeAll() {
        defaults.removeObject(forKey: storageKey)
    }

    private func makeBookmark(
        for url: URL
    ) throws -> Data {
        try url.bookmarkData(
            options: bookmarkCreationOptions,
            includingResourceValuesForKeys: [
                .nameKey,
            ],
            relativeTo: nil
        )
    }

    private var bookmarkCreationOptions:
        URL.BookmarkCreationOptions
    {
        #if os(macOS)
        return [.withSecurityScope]
        #else
        // URLs supplied by an iOS/iPadOS document picker carry an
        // implicit security scope that is preserved in bookmark data.
        return []
        #endif
    }

    private func sourceIdentifier(
        for url: URL
    ) -> String {
        url.standardizedFileURL.absoluteString
    }

    private func locationName(
        for url: URL
    ) -> String {
        let name = url.deletingLastPathComponent()
            .lastPathComponent
        return name.isEmpty
            ? AppLocalization.string("외부 저장소")
            : name
    }

    private func loadRecords()
        -> [RecentOriginalDocument]
    {
        guard let data = defaults.data(
            forKey: storageKey
        ),
        let records = try? JSONDecoder()
            .decode(
                [RecentOriginalDocument].self,
                from: data
            ) else {
            return []
        }
        return records
    }

    private func saveRecords(
        _ records: [RecentOriginalDocument]
    ) {
        let trimmed = records
            .sorted {
                $0.lastOpenedAt > $1.lastOpenedAt
            }
            .prefix(Self.maximumRecordCount)
        guard let data = try? JSONEncoder()
            .encode(Array(trimmed)) else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }
}

nonisolated enum DocumentFileAccessError: Error, LocalizedError {
    case documentChanged
    case savingInProgress

    var errorDescription: String? {
        switch self {
        case .documentChanged:
            return AppLocalization.string("다른 앱에서 문서가 변경되어 저장하지 않았습니다. 수정 내용을 복사본으로 내보내거나 문서를 다시 열어 주세요.")
        case .savingInProgress:
            return AppLocalization.string("문서를 저장하는 동안에는 편집할 수 없습니다. 저장이 끝나면 다시 시도해 주세요.")
        }
    }
}

nonisolated enum CoordinatedDocumentFileAccess {
    static func readData(
        from url: URL
    ) throws -> Data {
        let coordinator = NSFileCoordinator(
            filePresenter: nil
        )
        var coordinationError: NSError?
        var result: Result<Data, Error>?
        coordinator.coordinate(
            readingItemAt: url,
            options: [],
            error: &coordinationError
        ) { coordinatedURL in
            result = Result {
                try Data(
                    contentsOf: coordinatedURL,
                    options: .mappedIfSafe
                )
            }
        }
        if let coordinationError {
            throw coordinationError
        }
        guard let result else {
            throw CocoaError(.fileReadUnknown)
        }
        return try result.get()
    }

    static func replaceContents(
        at url: URL,
        with data: Data,
        expectedContents: Data? = nil
    ) throws {
        let coordinator = NSFileCoordinator(
            filePresenter: nil
        )
        var coordinationError: NSError?
        var writeError: Error?
        coordinator.coordinate(
            writingItemAt: url,
            options: .forReplacing,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                // Compare while holding the same coordination used for the
                // replacement, so another coordinated writer cannot slip in
                // between the conflict check and the write.
                if let expectedContents,
                   try Data(contentsOf: coordinatedURL) != expectedContents {
                    throw DocumentFileAccessError.documentChanged
                }
                try data.write(
                    to: coordinatedURL,
                    options: .atomic
                )
            } catch {
                writeError = error
            }
        }
        if let coordinationError {
            throw coordinationError
        }
        if let writeError {
            throw writeError
        }
    }
}

@MainActor
final class OriginalDocumentHostViewModel:
    ObservableObject
{
    @Published private(set) var record:
        RecentOriginalDocument?
    @Published private(set) var session:
        OriginalDocumentAccessSession?
    @Published private(set) var isLoading = true
    @Published private(set) var errorDescription:
        String?

    let documentID: UUID
    private var didLoad = false

    init(documentID: UUID) {
        self.documentID = documentID
    }

    func load() async {
        guard !didLoad else { return }
        didLoad = true
        isLoading = true
        do {
            let opened = try await
                RecentOriginalDocumentStore.shared
                .open(id: documentID)
            record = opened.record
            session = opened.session
        } catch {
            errorDescription = error
                .localizedDescription
        }
        isLoading = false
    }

    func forget() async {
        await RecentOriginalDocumentStore.shared
            .remove(id: documentID)
        session = nil
        record = nil
    }
}

struct OriginalDocumentHostView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel:
        OriginalDocumentHostViewModel

    init(documentID: UUID) {
        _viewModel = StateObject(
            wrappedValue:
                OriginalDocumentHostViewModel(
                    documentID: documentID
                )
        )
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("원본 문서를 여는 중…")
            } else if let session = viewModel.session {
                let pathExtension = session.url
                    .pathExtension.lowercased()
                if pathExtension == "xlsx" {
                    ExcelWorkbookView(
                        fileURL: session.url,
                        originalDocumentID:
                            viewModel.documentID
                    )
                } else if pathExtension == "xls" {
                    LegacyXLSConversionView(
                        fileURL: session.url
                    )
                } else if [
                    "hwp", "hwpx",
                ].contains(pathExtension) {
                    HWPDocumentView(
                        fileURL: session.url,
                        originalDocumentID:
                            viewModel.documentID
                    )
                } else if [
                    "doc", "docx", "docs",
                ].contains(pathExtension) {
                    WordDocumentView(
                        fileURL: session.url,
                        originalDocumentID:
                            viewModel.documentID
                    )
                } else {
                    LocalDocumentView(
                        fileURL: session.url
                    )
                }
            } else {
                ContentUnavailableView {
                    Label(
                        "원본 문서를 열 수 없습니다",
                        systemImage:
                            "externaldrive.badge.exclamationmark"
                    )
                } description: {
                    Text(
                        viewModel.errorDescription
                        ?? "원본 파일의 위치와 접근 권한을 확인해 주세요."
                    )
                } actions: {
                    Button(
                        "최근 목록에서 제거",
                        role: .destructive
                    ) {
                        Task {
                            await viewModel.forget()
                            dismiss()
                        }
                    }
                }
                .navigationTitle(
                    viewModel.record?.displayName
                    ?? "원본 문서"
                )
            }
        }
        .task {
            await viewModel.load()
        }
    }
}

@MainActor
enum PersistentOriginalDocumentOpening {
    static func documentLibraryRoute(
        for sourceURL: URL
    ) async throws -> AppRoute {
        guard DocumentLibraryFilePolicy
            .allows(
                pathExtension:
                    sourceURL.pathExtension
            ) else {
            throw AuthorizedDocumentLibraryError
                .unsupportedDocument
        }
        let didAccess = sourceURL
            .startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL
                    .stopAccessingSecurityScopedResource()
            }
        }
        let record = try await
            RecentOriginalDocumentStore.shared
            .register(fileURL: sourceURL)
        return .originalDocument(
            documentID: record.id
        )
    }

    static func route(
        for sourceURL: URL
    ) async throws -> AppRoute {
        let didAccess = sourceURL
            .startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL
                    .stopAccessingSecurityScopedResource()
            }
        }

        let pathExtension = sourceURL
            .pathExtension.lowercased()
        let contentType = try sourceURL
            .resourceValues(
                forKeys: [.contentTypeKey]
            )
            .contentType
            ?? UTType(
                filenameExtension: pathExtension
            )
        let isDocument = contentType?
            .conforms(to: .pdf) == true
            || contentType?
                .conforms(to: .plainText) == true
            || AuthorizedDocumentSearch
                .supportedExtensions
                .contains(pathExtension)

        guard isDocument else {
            return try await LocalFileOpening
                .route(for: sourceURL)
        }
        let record = try await
            RecentOriginalDocumentStore.shared
            .register(fileURL: sourceURL)
        return .originalDocument(
            documentID: record.id
        )
    }
}
