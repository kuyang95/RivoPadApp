import Foundation

nonisolated struct AuthorizedDocumentItem:
    Identifiable,
    Equatable,
    Hashable,
    Sendable
{
    var id: String {
        relativePath
    }

    let name: String
    let relativePath: String
    let pathExtension: String
    let fileSize: Int64?
    let modificationDate: Date?
}

nonisolated struct AuthorizedDocumentSearchResult:
    Equatable,
    Sendable
{
    let items: [AuthorizedDocumentItem]
    let isTruncated: Bool
}

nonisolated enum AuthorizedDocumentLibraryError:
    Error,
    LocalizedError,
    Equatable,
    Sendable
{
    case noFolder
    case invalidBookmark
    case invalidItem
    case unsupportedDocument
    case resultLimitExceeded(maximum: Int)

    var errorDescription: String? {
        switch self {
        case .noFolder:
            return AppLocalization.string(
                "먼저 검색할 폴더를 선택해 주세요."
            )
        case .invalidBookmark:
            return AppLocalization.string(
                "저장된 폴더 권한을 다시 사용할 수 없습니다. 폴더를 다시 선택해 주세요."
            )
        case .invalidItem:
            return AppLocalization.string(
                "선택한 문서가 허용된 폴더 밖에 있거나 더 이상 존재하지 않습니다."
            )
        case .unsupportedDocument:
            return AppLocalization.string(
                "PDF, TXT, XLSX, XLS와 HWP 문서만 검색할 수 있습니다."
            )
        case .resultLimitExceeded(
            let maximum
        ):
            return AppLocalization.format(
                "문서가 너무 많아 최근 %lld개만 표시합니다.",
                maximum
            )
        }
    }
}

nonisolated enum AuthorizedDocumentSearch {
    static let supportedExtensions:
        Set<String> = [
            "pdf",
            "txt",
            "xlsx",
            "xls",
            "hwp",
        ]
    static let maximumResults = 5_000
    static let maximumDepth = 64

    static func scan(
        rootURL: URL,
        fileManager: FileManager = .default,
        maximumResults: Int = maximumResults,
        maximumDepth: Int = maximumDepth
    ) throws -> AuthorizedDocumentSearchResult {
        guard maximumResults > 0,
              maximumDepth >= 0 else {
            return AuthorizedDocumentSearchResult(
                items: [],
                isTruncated: true
            )
        }
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isPackageKey,
            .fileSizeKey,
            .contentModificationDateKey,
        ]
        guard let enumerator =
                fileManager.enumerator(
                    at: rootURL,
                    includingPropertiesForKeys:
                        keys,
                    options: [
                        .skipsHiddenFiles,
                        .skipsPackageDescendants,
                    ],
                    errorHandler: {
                        _,
                        _ in
                        true
                    }
                ) else {
            throw AuthorizedDocumentLibraryError
                .invalidBookmark
        }

        let standardizedRoot =
            rootURL.standardizedFileURL
        var items: [AuthorizedDocumentItem] =
            []
        var isTruncated = false

        for case let url as URL in enumerator {
            let relativePath =
                relativePath(
                    for: url.standardizedFileURL,
                    rootURL: standardizedRoot
                )
            guard let relativePath else {
                enumerator.skipDescendants()
                continue
            }
            let depth = relativePath
                .split(separator: "/")
                .count
            let values = try? url.resourceValues(
                forKeys: Set(keys)
            )

            if values?.isSymbolicLink == true
                || values?.isPackage == true
                || depth > maximumDepth
            {
                enumerator.skipDescendants()
                continue
            }
            if values?.isDirectory == true {
                continue
            }
            guard values?.isRegularFile == true
            else {
                continue
            }

            let pathExtension = url.pathExtension
                .lowercased()
            guard supportedExtensions.contains(
                pathExtension
            ) else {
                continue
            }
            let item = AuthorizedDocumentItem(
                name: url.lastPathComponent,
                relativePath: relativePath,
                pathExtension:
                    pathExtension,
                fileSize: values?.fileSize.map(
                    Int64.init
                ),
                modificationDate:
                    values?
                    .contentModificationDate
            )
            if items.count < maximumResults {
                items.append(item)
                siftLeastRecentUp(
                    &items,
                    from: items.count - 1
                )
            } else {
                isTruncated = true
                guard let leastRecent =
                        items.first,
                      isMoreRecent(
                        item,
                        than: leastRecent
                      ) else {
                    continue
                }
                items[0] = item
                siftLeastRecentDown(
                    &items,
                    from: 0
                )
            }
        }

        items.sort(by: isMoreRecent)
        return AuthorizedDocumentSearchResult(
            items: items,
            isTruncated: isTruncated
        )
    }

    static func filter(
        _ items: [AuthorizedDocumentItem],
        query: String
    ) -> [AuthorizedDocumentItem] {
        let terms = query.split(
            whereSeparator: {
                $0.isWhitespace
            }
        )
        .map {
            normalized(String($0))
        }
        .filter {
            !$0.isEmpty
        }
        guard !terms.isEmpty else {
            return items
        }

        return items.filter {
            let searchable = normalized(
                $0.name
                    + "\n"
                    + $0.relativePath
            )
            return terms.allSatisfy {
                searchable.contains($0)
            }
        }
    }

    static func relativePath(
        for itemURL: URL,
        rootURL: URL
    ) -> String? {
        let rootPath =
            rootURL.standardizedFileURL.path
        let itemPath =
            itemURL.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/")
            ? rootPath
            : rootPath + "/"
        guard itemPath.hasPrefix(prefix)
        else {
            return nil
        }
        let relative = String(
            itemPath.dropFirst(prefix.count)
        )
        guard !relative.isEmpty,
              !relative.hasPrefix("/"),
              !relative.split(separator: "/")
                .contains("..")
        else {
            return nil
        }
        return relative
    }

    private static func normalized(
        _ text: String
    ) -> String {
        text.folding(
            options: [
                .caseInsensitive,
                .diacriticInsensitive,
                .widthInsensitive,
            ],
            locale: .current
        )
    }

    private static func isMoreRecent(
        _ lhs: AuthorizedDocumentItem,
        than rhs: AuthorizedDocumentItem
    ) -> Bool {
        let lhsDate =
            lhs.modificationDate
            ?? .distantPast
        let rhsDate =
            rhs.modificationDate
            ?? .distantPast
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }
        return lhs.relativePath
            .localizedCaseInsensitiveCompare(
                rhs.relativePath
            ) == .orderedAscending
    }

    private static func isLessPreferred(
        _ lhs: AuthorizedDocumentItem,
        than rhs: AuthorizedDocumentItem
    ) -> Bool {
        isMoreRecent(rhs, than: lhs)
    }

    private static func siftLeastRecentUp(
        _ items: inout [AuthorizedDocumentItem],
        from startingIndex: Int
    ) {
        var childIndex = startingIndex
        while childIndex > 0 {
            let parentIndex =
                (childIndex - 1) / 2
            guard isLessPreferred(
                items[childIndex],
                than: items[parentIndex]
            ) else {
                return
            }
            items.swapAt(
                childIndex,
                parentIndex
            )
            childIndex = parentIndex
        }
    }

    private static func siftLeastRecentDown(
        _ items: inout [AuthorizedDocumentItem],
        from startingIndex: Int
    ) {
        var parentIndex = startingIndex
        while true {
            let leftIndex =
                parentIndex * 2 + 1
            guard leftIndex < items.count
            else {
                return
            }
            let rightIndex = leftIndex + 1
            var leastPreferredIndex =
                leftIndex
            if rightIndex < items.count,
               isLessPreferred(
                items[rightIndex],
                than: items[leftIndex]
               ) {
                leastPreferredIndex =
                    rightIndex
            }
            guard isLessPreferred(
                items[leastPreferredIndex],
                than: items[parentIndex]
            ) else {
                return
            }
            items.swapAt(
                parentIndex,
                leastPreferredIndex
            )
            parentIndex =
                leastPreferredIndex
        }
    }
}

actor AuthorizedDocumentLibrary {
    static let shared =
        AuthorizedDocumentLibrary()

    private static let bookmarkKey =
        "AuthorizedDocumentLibrary.bookmark.v1"
    private static let folderNameKey =
        "AuthorizedDocumentLibrary.folderName.v1"

    private let defaults: UserDefaults

    init(
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
    }

    func folderName() -> String? {
        guard defaults.data(
            forKey: Self.bookmarkKey
        ) != nil else {
            return nil
        }
        return defaults.string(
            forKey: Self.folderNameKey
        )
    }

    func authorize(
        folderURL: URL
    ) async throws
        -> AuthorizedDocumentSearchResult
    {
        let didAccess =
            folderURL
            .startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                folderURL
                    .stopAccessingSecurityScopedResource()
            }
        }
        let values = try folderURL.resourceValues(
            forKeys: [
                .isDirectoryKey,
                .nameKey,
            ]
        )
        guard values.isDirectory == true
        else {
            throw AuthorizedDocumentLibraryError
                .invalidBookmark
        }
        let bookmark = try folderURL.bookmarkData(
            options: [],
            includingResourceValuesForKeys: [
                .nameKey,
            ],
            relativeTo: nil
        )
        defaults.set(
            bookmark,
            forKey: Self.bookmarkKey
        )
        defaults.set(
            values.name
                ?? folderURL.lastPathComponent,
            forKey: Self.folderNameKey
        )
        return try await scan(folderURL)
    }

    func refresh() async throws
        -> AuthorizedDocumentSearchResult
    {
        let folderURL = try resolveFolder()
        let didAccess =
            folderURL
            .startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                folderURL
                    .stopAccessingSecurityScopedResource()
            }
        }
        return try await scan(folderURL)
    }

    func importDocument(
        relativePath: String
    ) async throws -> URL {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath
                .split(separator: "/")
                .contains("..")
        else {
            throw AuthorizedDocumentLibraryError
                .invalidItem
        }
        let pathExtension = URL(
            fileURLWithPath: relativePath
        )
        .pathExtension
        .lowercased()
        guard AuthorizedDocumentSearch
                .supportedExtensions
                .contains(pathExtension) else {
            throw AuthorizedDocumentLibraryError
                .unsupportedDocument
        }

        let folderURL = try resolveFolder()
        let didAccess =
            folderURL
            .startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                folderURL
                    .stopAccessingSecurityScopedResource()
            }
        }
        let itemURL = folderURL
            .appendingPathComponent(
                relativePath,
                isDirectory: false
            )
        let canonicalRoot =
            folderURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let canonicalItem =
            itemURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard AuthorizedDocumentSearch
                .relativePath(
                    for: canonicalItem,
                    rootURL: canonicalRoot
                ) != nil
        else {
            throw AuthorizedDocumentLibraryError
                .invalidItem
        }
        let values = try canonicalItem
            .resourceValues(
                forKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                ]
            )
        guard values.isRegularFile == true,
              values.isSymbolicLink != true
        else {
            throw AuthorizedDocumentLibraryError
                .invalidItem
        }
        return try await
            LocalDocumentImportService.shared
            .importDocument(
                from: canonicalItem
            )
    }

    func forgetFolder() {
        defaults.removeObject(
            forKey: Self.bookmarkKey
        )
        defaults.removeObject(
            forKey: Self.folderNameKey
        )
    }

    private func resolveFolder()
        throws -> URL
    {
        guard let bookmark = defaults.data(
            forKey: Self.bookmarkKey
        ) else {
            throw AuthorizedDocumentLibraryError
                .noFolder
        }
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [
                    .withoutUI,
                    .withoutImplicitStartAccessing,
                ],
                relativeTo: nil,
                bookmarkDataIsStale:
                    &isStale
            )
            guard !isStale else {
                throw AuthorizedDocumentLibraryError
                    .invalidBookmark
            }
            return url
        } catch let error as
            AuthorizedDocumentLibraryError {
            throw error
        } catch {
            throw AuthorizedDocumentLibraryError
                .invalidBookmark
        }
    }

    private func scan(
        _ folderURL: URL
    ) async throws
        -> AuthorizedDocumentSearchResult
    {
        try await Task.detached(
            priority: .userInitiated
        ) {
            try AuthorizedDocumentSearch
                .scan(rootURL: folderURL)
        }
        .value
    }
}
