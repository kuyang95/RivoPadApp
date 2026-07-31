import Foundation

nonisolated enum LocalDocumentImportError: LocalizedError {
    case fileTooLarge(maximumMegabytes: Int)
    case textDecodingFailed

    var errorDescription: String? {
        switch self {
        case .fileTooLarge(let maximumMegabytes):
            return AppLocalization.format(
                "파일은 %lldMB 이하만 열 수 있습니다.",
                maximumMegabytes
            )
        case .textDecodingFailed:
            return AppLocalization.string(
                "지원되는 텍스트 인코딩이 아닙니다."
            )
        }
    }
}

nonisolated enum LocalTextDecoder {
    static func decode(_ data: Data) throws -> String {
        let encodings: [String.Encoding] = [
            .utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            .isoLatin1
        ]

        for encoding in encodings {
            if let text = String(data: data, encoding: encoding) {
                return text
            }
        }
        throw LocalDocumentImportError.textDecodingFailed
    }
}

actor LocalDocumentImportService {
    static let shared = LocalDocumentImportService()

    private let fileManager: FileManager
    private let importDirectory: URL
    private let maximumFileSize: Int64

    init(
        fileManager: FileManager = .default,
        importDirectory: URL? = nil,
        maximumFileSize: Int64 = 250 * 1_024 * 1_024
    ) {
        self.fileManager = fileManager
        self.maximumFileSize = maximumFileSize
        if let importDirectory {
            self.importDirectory = importDirectory
        } else {
            self.importDirectory = fileManager.temporaryDirectory
                .appendingPathComponent(
                    "ImportedDocuments",
                    isDirectory: true
                )
        }
    }

    func importDocument(from sourceURL: URL) throws -> URL {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let values = try sourceURL.resourceValues(
            forKeys: [.fileSizeKey, .isRegularFileKey]
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
            at: importDirectory,
            withIntermediateDirectories: true
        )
        let itemDirectory = importDirectory
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        try fileManager.createDirectory(
            at: itemDirectory,
            withIntermediateDirectories: true
        )

        let fileName = sourceURL.lastPathComponent.isEmpty
            ? AppLocalization.string(
                "가져온 문서"
            )
            : sourceURL.lastPathComponent
        let destinationURL = itemDirectory
            .appendingPathComponent(fileName)

        do {
            try fileManager.copyItem(
                at: sourceURL,
                to: destinationURL
            )
            return destinationURL
        } catch {
            try? fileManager.removeItem(at: itemDirectory)
            throw error
        }
    }
}
