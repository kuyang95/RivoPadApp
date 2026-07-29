import Foundation

actor EPUBLibraryStore {
    static let shared = EPUBLibraryStore()

    private let fileManager: FileManager
    private let booksDirectory: URL
    private let maximumFileSize: Int64

    init(
        fileManager: FileManager = .default,
        booksDirectory: URL? = nil,
        maximumFileSize: Int64 = 250 * 1_024 * 1_024
    ) {
        self.fileManager = fileManager
        self.maximumFileSize = maximumFileSize
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
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        let values = try sourceURL.resourceValues(
            forKeys: [.fileSizeKey]
        )
        if let fileSize = values.fileSize,
           Int64(fileSize) > maximumFileSize {
            throw LocalDocumentImportError.fileTooLarge(
                maximumMegabytes: Int(
                    maximumFileSize / 1_024 / 1_024
                )
            )
        }

        try fileManager.createDirectory(
            at: booksDirectory,
            withIntermediateDirectories: true
        )
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
        do {
            try fileManager.copyItem(
                at: sourceURL,
                to: destinationURL
            )
            return destinationURL
        } catch {
            try? fileManager.removeItem(at: bookDirectory)
            throw error
        }
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
