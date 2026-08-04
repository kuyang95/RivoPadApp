import Foundation

nonisolated enum SharedInboxItemKind:
    String,
    Codable,
    Equatable,
    Sendable
{
    case text
    case image
    case file
}

nonisolated struct SharedInboxItem:
    Identifiable,
    Codable,
    Equatable,
    Sendable
{
    static let schemaVersion = 1

    let id: UUID
    let schemaVersion: Int
    let createdAt: Date
    let kind: SharedInboxItemKind
    let text: String?
    let payloadFilename: String?
    let originalFilename: String?
    let typeIdentifier: String?
}

nonisolated struct SharedInboxCleanupResult:
    Equatable,
    Sendable
{
    let removedExpiredItems: Int
    let removedAbandonedItems: Int
    let failedRemovals: Int
}

enum SharedInboxStoreError: LocalizedError {
    case appGroupUnavailable
    case emptyText
    case payloadTooLarge
    case invalidItem
    case missingPayload

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return AppLocalization.string(
                "공유 수신함을 열 수 없습니다."
            )
        case .emptyText:
            return AppLocalization.string(
                "공유된 텍스트가 비어 있습니다."
            )
        case .payloadTooLarge:
            return AppLocalization.string(
                "공유 파일이 100MB 제한을 초과했습니다."
            )
        case .invalidItem:
            return AppLocalization.string(
                "공유 항목 정보가 올바르지 않습니다."
            )
        case .missingPayload:
            return AppLocalization.string(
                "공유 파일을 찾지 못했습니다."
            )
        }
    }
}

/// Cross-process inbox shared by the app and its Share/Action extensions.
///
/// Each item is committed by writing `manifest.json` last into a UUID-named
/// directory. The app therefore never observes a half-copied attachment.
final class SharedInboxStore {
    static let shared = SharedInboxStore()
    static let appGroupIdentifier =
        "group.net.rivo.visioncraft"
    static let directoryName = "ShareInbox"
    static let manifestFilename = "manifest.json"
    static let maximumPayloadBytes = 100 * 1_024 * 1_024
    static let committedItemRetention:
        TimeInterval = 7 * 24 * 60 * 60
    static let abandonedItemRetention:
        TimeInterval = 24 * 60 * 60

    private let fileManager: FileManager
    private let rootURL: URL?

    init(
        rootURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL
        } else {
            self.rootURL = fileManager
                .containerURL(
                    forSecurityApplicationGroupIdentifier:
                        Self.appGroupIdentifier
                )?
                .appendingPathComponent(
                    Self.directoryName,
                    isDirectory: true
                )
        }
    }

    func pendingItems() throws -> [SharedInboxItem] {
        _ = try? cleanup()
        let root = try preparedRoot()
        let directories = try fileManager
            .contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [
                    .isDirectoryKey
                ],
                options: [.skipsHiddenFiles]
            )
        return directories.compactMap { directory in
            guard UUID(
                uuidString:
                    directory.lastPathComponent
            ) != nil else {
                return nil
            }
            let manifestURL = directory
                .appendingPathComponent(
                    Self.manifestFilename
                )
            guard let data = try? Data(
                contentsOf: manifestURL
            ),
            let item = try? JSONDecoder.sharedInbox
                .decode(
                    SharedInboxItem.self,
                    from: data
                ),
            Self.isValid(
                item,
                directory: directory
            ) else {
                return nil
            }
            if item.kind != .text,
               (try? payloadURL(for: item)) == nil {
                return nil
            }
            return item
        }
        .sorted {
            if $0.createdAt == $1.createdAt {
                return $0.id.uuidString
                    < $1.id.uuidString
            }
            return $0.createdAt < $1.createdAt
        }
    }

    @discardableResult
    func cleanup(
        now: Date = Date()
    ) throws -> SharedInboxCleanupResult {
        let root = try preparedRoot()
        let directories = try fileManager
            .contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                    .creationDateKey,
                    .contentModificationDateKey,
                ],
                options: [.skipsHiddenFiles]
            )
        var removedExpiredItems = 0
        var removedAbandonedItems = 0
        var failedRemovals = 0

        for directory in directories {
            guard UUID(
                uuidString:
                    directory.lastPathComponent
            ) != nil,
            let values =
                try? directory.resourceValues(
                    forKeys: [
                        .isDirectoryKey,
                        .isSymbolicLinkKey,
                        .creationDateKey,
                        .contentModificationDateKey,
                    ]
                ),
            values.isDirectory == true,
            values.isSymbolicLink != true
            else {
                continue
            }

            let manifestURL = directory
                .appendingPathComponent(
                    Self.manifestFilename
                )
            let item: SharedInboxItem?
            if let data = try? Data(
                contentsOf: manifestURL
            ) {
                item = try? JSONDecoder
                    .sharedInbox
                    .decode(
                        SharedInboxItem.self,
                        from: data
                    )
            } else {
                item = nil
            }

            let isCommitted: Bool
            if let item {
                isCommitted = Self.isValid(
                    item,
                    directory: directory
                ) && (
                    item.kind == .text
                    || (try? payloadURL(
                        for: item
                    )) != nil
                )
            } else {
                isCommitted = false
            }

            let shouldRemoveExpired =
                isCommitted
                && item.map {
                    now.timeIntervalSince(
                        $0.createdAt
                    ) >= Self
                        .committedItemRetention
                } == true
            let directoryDate =
                values
                    .contentModificationDate
                ?? values.creationDate
                ?? now
            let shouldRemoveAbandoned =
                !isCommitted
                && now.timeIntervalSince(
                    directoryDate
                ) >= Self
                    .abandonedItemRetention

            guard shouldRemoveExpired
                    || shouldRemoveAbandoned
            else {
                continue
            }
            do {
                try fileManager.removeItem(
                    at: directory
                )
                if shouldRemoveExpired {
                    removedExpiredItems += 1
                } else {
                    removedAbandonedItems += 1
                }
            } catch {
                failedRemovals += 1
            }
        }
        return SharedInboxCleanupResult(
            removedExpiredItems:
                removedExpiredItems,
            removedAbandonedItems:
                removedAbandonedItems,
            failedRemovals:
                failedRemovals
        )
    }

    func payloadURL(
        for item: SharedInboxItem
    ) throws -> URL {
        guard let payloadFilename =
                item.payloadFilename,
              payloadFilename
                == URL(
                    fileURLWithPath:
                        payloadFilename
                ).lastPathComponent,
              !payloadFilename.isEmpty else {
            throw SharedInboxStoreError
                .missingPayload
        }
        let directory = try itemDirectory(
            for: item.id
        )
        let url = directory
            .appendingPathComponent(
                payloadFilename,
                isDirectory: false
            )
        guard fileManager.fileExists(
            atPath: url.path
        ) else {
            throw SharedInboxStoreError
                .missingPayload
        }
        let values = try url.resourceValues(
            forKeys: [
                .isRegularFileKey,
                .fileSizeKey
            ]
        )
        guard values.isRegularFile == true else {
            throw SharedInboxStoreError
                .missingPayload
        }
        guard let fileSize = values.fileSize,
              fileSize
                <= Self.maximumPayloadBytes else {
            throw SharedInboxStoreError
                .payloadTooLarge
        }
        return url
    }

    func remove(_ item: SharedInboxItem) throws {
        let directory = try itemDirectory(
            for: item.id
        )
        if fileManager.fileExists(
            atPath: directory.path
        ) {
            try fileManager.removeItem(
                at: directory
            )
        }
    }

    @discardableResult
    func enqueueText(
        _ text: String,
        createdAt: Date = Date()
    ) throws -> SharedInboxItem {
        let trimmed = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else {
            throw SharedInboxStoreError.emptyText
        }
        let item = SharedInboxItem(
            id: UUID(),
            schemaVersion:
                SharedInboxItem.schemaVersion,
            createdAt: createdAt,
            kind: .text,
            text: String(
                trimmed.prefix(200_000)
            ),
            payloadFilename: nil,
            originalFilename: nil,
            typeIdentifier: "public.plain-text"
        )
        try commit(item)
        return item
    }

    @discardableResult
    func enqueuePayload(
        _ data: Data,
        kind: SharedInboxItemKind,
        originalFilename: String,
        typeIdentifier: String,
        createdAt: Date = Date()
    ) throws -> SharedInboxItem {
        guard kind == .image || kind == .file else {
            throw SharedInboxStoreError.invalidItem
        }
        guard data.count <= Self.maximumPayloadBytes else {
            throw SharedInboxStoreError
                .payloadTooLarge
        }
        let safeName = Self.safeFilename(
            originalFilename
        )
        let item = SharedInboxItem(
            id: UUID(),
            schemaVersion:
                SharedInboxItem.schemaVersion,
            createdAt: createdAt,
            kind: kind,
            text: nil,
            payloadFilename: safeName,
            originalFilename: safeName,
            typeIdentifier: typeIdentifier
        )
        let directory = try itemDirectory(
            for: item.id
        )
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        do {
            try data.write(
                to: directory
                    .appendingPathComponent(
                        safeName
                    ),
                options: .atomic
            )
            try commit(item)
            return item
        } catch {
            try? fileManager.removeItem(
                at: directory
            )
            throw error
        }
    }

    private func commit(
        _ item: SharedInboxItem
    ) throws {
        guard Self.isValid(
            item,
            directory: nil
        ) else {
            throw SharedInboxStoreError.invalidItem
        }
        let directory = try itemDirectory(
            for: item.id
        )
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.sharedInbox
            .encode(item)
        try data.write(
            to: directory
                .appendingPathComponent(
                    Self.manifestFilename
                ),
            options: .atomic
        )
    }

    private func preparedRoot() throws -> URL {
        guard let rootURL else {
            throw SharedInboxStoreError
                .appGroupUnavailable
        }
        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        return rootURL
    }

    private func itemDirectory(
        for id: UUID
    ) throws -> URL {
        try preparedRoot()
            .appendingPathComponent(
                id.uuidString,
                isDirectory: true
            )
    }

    private static func isValid(
        _ item: SharedInboxItem,
        directory: URL?
    ) -> Bool {
        guard item.schemaVersion
                == SharedInboxItem.schemaVersion
        else {
            return false
        }
        if let directory,
           directory.lastPathComponent
            != item.id.uuidString {
            return false
        }
        switch item.kind {
        case .text:
            return item.text?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .isEmpty == false
                && item.payloadFilename == nil
        case .image, .file:
            guard let filename =
                    item.payloadFilename else {
                return false
            }
            return filename
                == URL(
                    fileURLWithPath: filename
                ).lastPathComponent
                && !filename.isEmpty
        }
    }

    private static func safeFilename(
        _ filename: String
    ) -> String {
        let candidate = URL(
            fileURLWithPath: filename
        ).lastPathComponent
        let invalid =
            CharacterSet.alphanumerics
                .union(
                    CharacterSet(
                        charactersIn:
                            "._-() "
                    )
                )
                .inverted
        let sanitized = candidate
            .components(
                separatedBy: invalid
            )
            .joined(separator: "_")
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        if sanitized.isEmpty
            || sanitized == "."
            || sanitized == ".." {
            return "shared-item"
        }
        return String(sanitized.prefix(120))
    }
}

private extension JSONEncoder {
    static var sharedInbox: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy =
            .iso8601
        encoder.outputFormatting = [
            .sortedKeys
        ]
        return encoder
    }
}

private extension JSONDecoder {
    static var sharedInbox: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy =
            .iso8601
        return decoder
    }
}
