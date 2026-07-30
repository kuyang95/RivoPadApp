import CryptoKit
import Foundation

nonisolated struct EPUBLibraryBook:
    Identifiable,
    Equatable,
    Sendable
{
    let id: String
    let fileURL: URL
    let title: String
    let importedAt: Date
    let lastOpenedAt: Date?
    let fileSize: Int64
    let contentDigest: String?
    let publicationIdentifier: String?

    var activityDate: Date {
        lastOpenedAt ?? importedAt
    }

    var formatDescription: String {
        fileURL.pathExtension.lowercased() == "epub"
            ? "EPUB"
            : AppLocalization.string(
                "DAISY ZIP"
            )
    }
}

nonisolated struct EPUBLibraryImportResult:
    Equatable,
    Sendable
{
    let book: EPUBLibraryBook
    let reusedExistingBook: Bool
}

nonisolated enum EPUBLibraryError:
    LocalizedError
{
    case unsupportedFormat
    case libraryCapacityReached(
        maximumBooks: Int
    )

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return AppLocalization.string(
                "EPUB 또는 DAISY ZIP 파일만 가져올 수 있습니다."
            )
        case .libraryCapacityReached(
            let maximumBooks
        ):
            return AppLocalization.format(
                "서재에는 책을 최대 %lld권까지 보관할 수 있습니다.",
                maximumBooks
            )
        }
    }
}

private nonisolated struct EPUBLibraryMetadata:
    Codable,
    Sendable
{
    var version: Int
    var fileName: String
    var title: String
    var importedAt: Date
    var lastOpenedAt: Date?
    var fileSize: Int64
    var contentDigest: String?
    var publicationIdentifier: String?
}

actor EPUBLibraryStore {
    static let shared = EPUBLibraryStore()

    private static let metadataFileName =
        ".rivo-library-book.json"
    private static let supportedExtensions:
        Set<String> = ["epub", "zip"]
    private static let digestChunkSize =
        1_024 * 1_024

    private let fileManager: FileManager
    private let booksDirectory: URL
    private let maximumFileSize: Int64
    private let maximumBookCount: Int

    init(
        fileManager: FileManager = .default,
        booksDirectory: URL? = nil,
        maximumFileSize: Int64 = 250 * 1_024 * 1_024,
        maximumBookCount: Int = 2_000
    ) {
        self.fileManager = fileManager
        self.maximumFileSize = maximumFileSize
        self.maximumBookCount = max(
            maximumBookCount,
            1
        )
        if let booksDirectory {
            self.booksDirectory = booksDirectory
        } else {
            let applicationSupport = try! fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.booksDirectory = applicationSupport
                .appendingPathComponent(
                    "EPUBBooks",
                    isDirectory: true
                )
        }
    }

    func importBook(from sourceURL: URL) throws -> URL {
        try importBookWithResult(
            from: sourceURL
        ).book.fileURL
    }

    func importBookWithResult(
        from sourceURL: URL
    ) throws -> EPUBLibraryImportResult {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        let values = try sourceURL.resourceValues(
            forKeys: [
                .fileSizeKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ]
        )
        if values.isRegularFile == false
            || values.isSymbolicLink == true {
            throw CocoaError(
                .fileReadInvalidFileName
            )
        }
        if let fileSize = values.fileSize,
           Int64(fileSize) > maximumFileSize {
            throw LocalDocumentImportError.fileTooLarge(
                maximumMegabytes: Int(
                    maximumFileSize / 1_024 / 1_024
                )
            )
        }
        let pathExtension = sourceURL
            .pathExtension
            .lowercased()
        guard Self.supportedExtensions
            .contains(pathExtension) else {
            throw EPUBLibraryError
                .unsupportedFormat
        }

        let sourceDigestResult =
            try digest(
                of: sourceURL,
                maximumBytes:
                    maximumFileSize
            )
        let sourceDigest =
            sourceDigestResult.value
        let sourceSize =
            sourceDigestResult.byteCount
        if sourceSize > maximumFileSize {
            throw LocalDocumentImportError
                .fileTooLarge(
                    maximumMegabytes: Int(
                        maximumFileSize
                            / 1_024 / 1_024
                    )
                )
        }
        if let reportedSize = values.fileSize,
           Int64(reportedSize) != sourceSize {
            throw CocoaError(
                .fileReadCorruptFile
            )
        }

        var existingBooks = try books()
        for index in existingBooks.indices
        where existingBooks[index].fileSize
            == sourceSize {
            let existingDigest: String
            if let savedDigest =
                    existingBooks[index]
                        .contentDigest {
                existingDigest = savedDigest
            } else {
                guard let calculatedDigest =
                        try? digest(
                            of:
                                existingBooks[index]
                                    .fileURL
                        ).value else {
                    continue
                }
                existingDigest =
                    calculatedDigest
                existingBooks[index] =
                    try updating(
                        existingBooks[index],
                        contentDigest:
                            existingDigest
                    )
            }
            guard existingDigest
                    == sourceDigest else {
                continue
            }
            let reused = try updating(
                existingBooks[index],
                lastOpenedAt: Date(),
                contentDigest: existingDigest
            )
            return EPUBLibraryImportResult(
                book: reused,
                reusedExistingBook: true
            )
        }

        guard existingBooks.count
                < maximumBookCount else {
            throw EPUBLibraryError
                .libraryCapacityReached(
                    maximumBooks:
                        maximumBookCount
                )
        }

        try ensureBooksDirectory()
        let bookDirectory = booksDirectory
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        try fileManager.createDirectory(
            at: bookDirectory,
            withIntermediateDirectories: true
        )
        let fileName = sourceURL.lastPathComponent.isEmpty
            ? "가져온 책.epub"
            : sourceURL.lastPathComponent
        let destinationURL = bookDirectory
            .appendingPathComponent(fileName)
        let importedAt = Date()
        do {
            try fileManager.copyItem(
                at: sourceURL,
                to: destinationURL
            )
            let copiedValues = try destinationURL
                .resourceValues(
                    forKeys: [.fileSizeKey]
                )
            let copiedDigest = try digest(
                of: destinationURL,
                maximumBytes:
                    maximumFileSize
            )
            guard copiedDigest.byteCount
                    == sourceSize,
                  copiedDigest.value
                    == sourceDigest else {
                throw CocoaError(
                    .fileReadCorruptFile
                )
            }
            let book = EPUBLibraryBook(
                id:
                    bookDirectory.lastPathComponent,
                fileURL: destinationURL,
                title:
                    destinationURL
                        .deletingPathExtension()
                        .lastPathComponent,
                importedAt: importedAt,
                lastOpenedAt: importedAt,
                fileSize: Int64(
                    copiedValues.fileSize
                        ?? Int(sourceSize)
                ),
                contentDigest:
                    copiedDigest.value,
                publicationIdentifier: nil
            )
            try writeMetadata(
                for: book
            )
            return EPUBLibraryImportResult(
                book: book,
                reusedExistingBook: false
            )
        } catch {
            try? fileManager.removeItem(at: bookDirectory)
            throw error
        }
    }

    func books() throws -> [EPUBLibraryBook] {
        try ensureBooksDirectory()
        let directories = try fileManager
            .contentsOfDirectory(
                at: booksDirectory,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                ],
                options: [.skipsHiddenFiles]
            )
        var result: [EPUBLibraryBook] = []
        result.reserveCapacity(
            min(
                directories.count,
                maximumBookCount
            )
        )
        for directory in directories {
            guard result.count
                    < maximumBookCount,
                  let book = try? book(
                      in: directory
                  ) else {
                continue
            }
            result.append(book)
        }
        return result.sorted {
            if $0.activityDate
                != $1.activityDate {
                return $0.activityDate
                    > $1.activityDate
            }
            let titleComparison =
                $0.title.localizedStandardCompare(
                    $1.title
                )
            if titleComparison != .orderedSame {
                return titleComparison
                    == .orderedAscending
            }
            return $0.id < $1.id
        }
    }

    @discardableResult
    func markOpened(
        bookURL: URL,
        publicationIdentifier: String? = nil
    ) throws -> EPUBLibraryBook? {
        guard let book = try books()
            .first(where: {
                $0.fileURL.standardizedFileURL
                    == bookURL
                        .standardizedFileURL
            }) else {
            return nil
        }
        return try updating(
            book,
            lastOpenedAt: Date(),
            publicationIdentifier:
                publicationIdentifier
        )
    }

    @discardableResult
    func deleteBook(
        _ book: EPUBLibraryBook
    ) throws -> EPUBLibraryBook {
        guard isValidIdentifier(book.id) else {
            throw CocoaError(
                .fileWriteInvalidFileName
            )
        }
        let directory = booksDirectory
            .appendingPathComponent(
                book.id,
                isDirectory: true
            )
        let root =
            booksDirectory.standardizedFileURL
        guard directory
                .deletingLastPathComponent()
                .standardizedFileURL
                == root,
              let storedBook = try self.book(
                  in: directory
              ),
              storedBook.fileURL
                .standardizedFileURL
                == book.fileURL
                    .standardizedFileURL else {
            throw CocoaError(
                .fileNoSuchFile
            )
        }
        try fileManager.removeItem(
            at: directory
        )
        return storedBook
    }

    private func ensureBooksDirectory()
        throws
    {
        try fileManager.createDirectory(
            at: booksDirectory,
            withIntermediateDirectories: true
        )
    }

    private func book(
        in directory: URL
    ) throws -> EPUBLibraryBook? {
        let directoryValues =
            try directory.resourceValues(
                forKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                ]
            )
        guard directoryValues.isDirectory
                == true,
              directoryValues.isSymbolicLink
                != true,
              isValidIdentifier(
                  directory.lastPathComponent
              ) else {
            return nil
        }
        let files = try fileManager
            .contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .fileSizeKey,
                    .creationDateKey,
                    .contentModificationDateKey,
                ],
                options: [.skipsHiddenFiles]
            )
            .sorted {
                $0.lastPathComponent
                    .localizedStandardCompare(
                        $1.lastPathComponent
                    )
                    == .orderedAscending
            }
        guard let fileURL = files.first(
            where: { candidate in
                guard Self.supportedExtensions
                    .contains(
                        candidate.pathExtension
                            .lowercased()
                    ),
                    let values = try? candidate
                        .resourceValues(
                            forKeys: [
                                .isRegularFileKey,
                                .isSymbolicLinkKey,
                            ]
                        )
                else {
                    return false
                }
                return values.isRegularFile == true
                    && values.isSymbolicLink != true
            }
        ) else {
            return nil
        }
        let fileValues =
            try fileURL.resourceValues(
                forKeys: [
                    .fileSizeKey,
                    .creationDateKey,
                    .contentModificationDateKey,
                ]
            )
        let fallbackDate =
            fileValues.creationDate
            ?? fileValues.contentModificationDate
            ?? Date.distantPast
        let metadata = try readMetadata(
            in: directory
        )
        let book = EPUBLibraryBook(
            id: directory.lastPathComponent,
            fileURL: fileURL,
            title:
                metadata?.title
                ?? fileURL
                    .deletingPathExtension()
                    .lastPathComponent,
            importedAt:
                metadata?.importedAt
                ?? fallbackDate,
            lastOpenedAt:
                metadata?.lastOpenedAt,
            fileSize: Int64(
                fileValues.fileSize
                    ?? Int(
                        metadata?.fileSize
                            ?? 0
                    )
            ),
            contentDigest:
                metadata?.contentDigest,
            publicationIdentifier:
                metadata?
                    .publicationIdentifier
        )
        if metadata == nil
            || metadata?.fileName
                != fileURL.lastPathComponent {
            try writeMetadata(
                for: book
            )
        }
        return book
    }

    private func readMetadata(
        in directory: URL
    ) throws -> EPUBLibraryMetadata? {
        let metadataURL = directory
            .appendingPathComponent(
                Self.metadataFileName
            )
        guard fileManager.fileExists(
            atPath: metadataURL.path
        ) else {
            return nil
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy =
                .millisecondsSince1970
            return try decoder.decode(
                EPUBLibraryMetadata.self,
                from: Data(
                    contentsOf: metadataURL,
                    options: .mappedIfSafe
                )
            )
        } catch {
            return nil
        }
    }

    private func writeMetadata(
        for book: EPUBLibraryBook
    ) throws {
        let metadata = EPUBLibraryMetadata(
            version: 1,
            fileName:
                book.fileURL.lastPathComponent,
            title: book.title,
            importedAt: book.importedAt,
            lastOpenedAt: book.lastOpenedAt,
            fileSize: book.fileSize,
            contentDigest:
                book.contentDigest,
            publicationIdentifier:
                book.publicationIdentifier
        )
        let directory =
            book.fileURL
                .deletingLastPathComponent()
        let metadataURL = directory
            .appendingPathComponent(
                Self.metadataFileName
            )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy =
            .millisecondsSince1970
        try encoder.encode(metadata).write(
            to: metadataURL,
            options: .atomic
        )
    }

    private func updating(
        _ book: EPUBLibraryBook,
        lastOpenedAt: Date? = nil,
        contentDigest: String? = nil,
        publicationIdentifier: String? = nil
    ) throws -> EPUBLibraryBook {
        let updated = EPUBLibraryBook(
            id: book.id,
            fileURL: book.fileURL,
            title: book.title,
            importedAt: book.importedAt,
            lastOpenedAt:
                lastOpenedAt
                ?? book.lastOpenedAt,
            fileSize: book.fileSize,
            contentDigest:
                contentDigest
                ?? book.contentDigest,
            publicationIdentifier:
                publicationIdentifier
                ?? book.publicationIdentifier
        )
        try writeMetadata(
            for: updated
        )
        return updated
    }

    private func digest(
        of fileURL: URL,
        maximumBytes: Int64? = nil
    ) throws -> (
        value: String,
        byteCount: Int64
    ) {
        let handle = try FileHandle(
            forReadingFrom: fileURL
        )
        defer {
            try? handle.close()
        }
        var hasher = SHA256()
        var byteCount: Int64 = 0
        while true {
            let data = try handle.read(
                upToCount:
                    Self.digestChunkSize
            ) ?? Data()
            guard !data.isEmpty else {
                break
            }
            byteCount += Int64(data.count)
            if let maximumBytes,
               byteCount > maximumBytes {
                throw LocalDocumentImportError
                    .fileTooLarge(
                        maximumMegabytes: Int(
                            maximumBytes
                                / 1_024 / 1_024
                        )
                    )
            }
            hasher.update(data: data)
        }
        return (
            hasher.finalize()
                .map {
                    String(
                        format: "%02x",
                        $0
                    )
                }
                .joined(),
            byteCount
        )
    }

    private func isValidIdentifier(
        _ identifier: String
    ) -> Bool {
        !identifier.isEmpty
            && identifier != "."
            && identifier != ".."
            && !identifier.contains("/")
            && !identifier.contains(":")
    }
}

nonisolated struct EPUBReaderProgress:
    Codable,
    Equatable,
    Sendable
{
    let chapterIndex: Int
    let segmentIndex: Int

    init(
        chapterIndex: Int,
        segmentIndex: Int
    ) {
        self.chapterIndex = max(chapterIndex, 0)
        self.segmentIndex = max(segmentIndex, 0)
    }
}

@MainActor
enum EPUBProgressStore {
    private static let lastBookPathKey = "reader.epub.lastBookPath"

    static var lastBookURL: URL? {
        get {
            guard let path = UserDefaults.standard.string(
                forKey: lastBookPathKey
            ), FileManager.default.fileExists(atPath: path) else {
                return nil
            }
            return URL(fileURLWithPath: path)
        }
        set {
            UserDefaults.standard.set(
                newValue?.path,
                forKey: lastBookPathKey
            )
        }
    }

    static func progress(
        for bookIdentifier: String,
        defaults: UserDefaults = .standard
    ) -> EPUBReaderProgress? {
        if let data = defaults.data(
            forKey: progressKey(bookIdentifier)
        ),
           let progress = try? JSONDecoder().decode(
               EPUBReaderProgress.self,
               from: data
           ) {
            return progress
        }
        guard defaults.object(
            forKey: chapterKey(bookIdentifier)
        ) != nil else {
            return nil
        }
        return EPUBReaderProgress(
            chapterIndex: defaults.integer(
                forKey: chapterKey(bookIdentifier)
            ),
            segmentIndex: 0
        )
    }

    static func save(
        _ progress: EPUBReaderProgress,
        for bookIdentifier: String,
        defaults: UserDefaults = .standard
    ) {
        let normalized = EPUBReaderProgress(
            chapterIndex: progress.chapterIndex,
            segmentIndex: progress.segmentIndex
        )
        if let data = try? JSONEncoder().encode(
            normalized
        ) {
            defaults.set(
                data,
                forKey: progressKey(bookIdentifier)
            )
        }
        defaults.set(
            normalized.chapterIndex,
            forKey: chapterKey(bookIdentifier)
        )
    }

    static func removeProgress(
        for bookIdentifier: String,
        defaults: UserDefaults = .standard
    ) {
        defaults.removeObject(
            forKey: progressKey(bookIdentifier)
        )
        defaults.removeObject(
            forKey: chapterKey(bookIdentifier)
        )
    }

    private static func chapterKey(_ identifier: String) -> String {
        let encoded = Data(identifier.utf8).base64EncodedString()
        return "reader.epub.chapter.\(encoded)"
    }

    private static func progressKey(
        _ identifier: String
    ) -> String {
        let encoded = Data(identifier.utf8).base64EncodedString()
        return "reader.epub.progress.\(encoded)"
    }
}
