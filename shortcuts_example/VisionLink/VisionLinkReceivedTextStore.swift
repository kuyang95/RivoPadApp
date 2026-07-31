import Foundation

nonisolated enum VisionLinkReceivedTextStoreError:
    LocalizedError,
    Equatable
{
    case emptyText
    case textTooLarge(maximumKilobytes: Int)

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return AppLocalization.string(
                "받은 텍스트가 비어 있습니다."
            )
        case .textTooLarge(
            let maximumKilobytes
        ):
            return AppLocalization.format(
                "받은 텍스트가 %lldKB를 초과했습니다.",
                maximumKilobytes
            )
        }
    }
}

actor VisionLinkReceivedTextStore {
    static let shared =
        VisionLinkReceivedTextStore()

    private let fileManager: FileManager
    private let rootDirectory: URL
    private let maximumTextBytes: Int
    private let maximumCachedItemCount: Int

    init(
        fileManager: FileManager = .default,
        rootDirectory: URL? = nil,
        maximumTextBytes: Int =
            128 * 1_024,
        maximumCachedItemCount: Int = 4
    ) {
        self.fileManager = fileManager
        self.maximumTextBytes =
            max(maximumTextBytes, 1)
        self.maximumCachedItemCount =
            max(maximumCachedItemCount, 1)
        if let rootDirectory {
            self.rootDirectory =
                rootDirectory
        } else {
            self.rootDirectory =
                fileManager.urls(
                    for: .cachesDirectory,
                    in: .userDomainMask
                )
                .first!
                .appendingPathComponent(
                    "VisionLink/ReceivedText",
                    isDirectory: true
                )
        }
    }

    func save(
        _ text: String
    ) throws -> URL {
        guard !text.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw VisionLinkReceivedTextStoreError
                .emptyText
        }
        let data = Data(text.utf8)
        guard data.count
                <= maximumTextBytes else {
            throw VisionLinkReceivedTextStoreError
                .textTooLarge(
                    maximumKilobytes:
                        maximumTextBytes
                        / 1_024
                )
        }

        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        let itemDirectory =
            rootDirectory
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        try fileManager.createDirectory(
            at: itemDirectory,
            withIntermediateDirectories: true
        )
        let fileURL =
            itemDirectory
            .appendingPathComponent(
                AppLocalization.string(
                    "VisionLink 받은 텍스트.txt"
                )
            )

        do {
            try data.write(
                to: fileURL,
                options: .atomic
            )
            try pruneOldItems()
            return fileURL
        } catch {
            try? fileManager.removeItem(
                at: itemDirectory
            )
            throw error
        }
    }

    private func pruneOldItems() throws {
        let items =
            try fileManager
            .contentsOfDirectory(
                at: rootDirectory,
                includingPropertiesForKeys: [
                    .contentModificationDateKey,
                    .isDirectoryKey,
                ],
                options: [.skipsHiddenFiles]
            )
            .filter { url in
                (
                    try? url.resourceValues(
                        forKeys: [.isDirectoryKey]
                    )
                    .isDirectory
                ) == true
            }
            .sorted { left, right in
                let leftDate =
                    (
                        try? left.resourceValues(
                            forKeys: [
                                .contentModificationDateKey
                            ]
                        )
                        .contentModificationDate
                    ) ?? .distantPast
                let rightDate =
                    (
                        try? right.resourceValues(
                            forKeys: [
                                .contentModificationDateKey
                            ]
                        )
                        .contentModificationDate
                    ) ?? .distantPast
                return leftDate > rightDate
            }

        for item in items.dropFirst(
            maximumCachedItemCount
        ) {
            try? fileManager.removeItem(
                at: item
            )
        }
    }
}
