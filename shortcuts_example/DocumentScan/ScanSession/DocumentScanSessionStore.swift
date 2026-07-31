import Foundation
import UIKit

nonisolated enum DocumentScanSessionError:
    LocalizedError,
    Equatable,
    Sendable
{
    case pageLimitReached(maximum: Int)
    case imageEncodingFailed
    case imageDecodingFailed
    case noPages

    var errorDescription: String? {
        switch self {
        case .pageLimitReached(let maximum):
            return AppLocalization.format(
                "문서는 최대 %lld페이지까지 촬영할 수 있습니다.",
                maximum
            )
        case .imageEncodingFailed:
            return AppLocalization.string(
                "스캔 페이지를 저장할 수 없습니다."
            )
        case .imageDecodingFailed:
            return AppLocalization.string(
                "저장된 스캔 페이지를 열 수 없습니다."
            )
        case .noPages:
            return AppLocalization.string(
                "저장하거나 열 스캔 페이지가 없습니다."
            )
        }
    }
}

nonisolated struct DocumentScanPageRecord:
    Identifiable,
    Codable,
    Equatable,
    Hashable,
    Sendable
{
    let id: UUID
    let filename: String
    let capturedAt: Date
    var clockwiseQuarterTurns: Int

    var normalizedQuarterTurns: Int {
        (
            (clockwiseQuarterTurns % 4)
                + 4
        ) % 4
    }

    mutating func rotateClockwise() {
        clockwiseQuarterTurns =
            (normalizedQuarterTurns + 1) % 4
    }
}

nonisolated private struct DocumentScanSessionManifest:
    Codable,
    Sendable
{
    let schemaVersion: Int
    let updatedAt: Date
    let pages: [DocumentScanPageRecord]
}

nonisolated final class DocumentScanSessionStore:
    @unchecked Sendable
{
    static let maximumPageCount = 20

    let sessionDirectory: URL

    private let fileManager: FileManager
    private let manifestURL: URL

    init(
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil,
        sessionID: UUID = UUID()
    ) {
        self.fileManager = fileManager
        let base = baseDirectory
            ?? fileManager.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            ).first?
            .appendingPathComponent(
                "DocumentScanSessions",
                isDirectory: true
            )
            ?? fileManager.temporaryDirectory
                .appendingPathComponent(
                    "DocumentScanSessions",
                    isDirectory: true
                )
        sessionDirectory = base
            .appendingPathComponent(
                sessionID.uuidString,
                isDirectory: true
            )
        manifestURL = sessionDirectory
            .appendingPathComponent(
                "manifest.json"
            )
    }

    private init(
        fileManager: FileManager,
        sessionDirectory: URL
    ) {
        self.fileManager = fileManager
        self.sessionDirectory = sessionDirectory
        manifestURL = sessionDirectory
            .appendingPathComponent(
                "manifest.json"
            )
    }

    static func restoringLatest(
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil
    ) -> DocumentScanSessionStore {
        let base = baseDirectory
            ?? fileManager.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            ).first?
            .appendingPathComponent(
                "DocumentScanSessions",
                isDirectory: true
            )
            ?? fileManager.temporaryDirectory
                .appendingPathComponent(
                    "DocumentScanSessions",
                    isDirectory: true
                )
        let directories =
            (
                try? fileManager.contentsOfDirectory(
                    at: base,
                    includingPropertiesForKeys: [
                        .contentModificationDateKey,
                        .isDirectoryKey
                    ],
                    options: [.skipsHiddenFiles]
                )
            ) ?? []
        let latest = directories
            .filter {
                (
                    try? $0.resourceValues(
                        forKeys: [.isDirectoryKey]
                    ).isDirectory
                ) == true
                    && fileManager.fileExists(
                        atPath: $0.appendingPathComponent(
                            "manifest.json"
                        ).path
                    )
            }
            .max {
                let left = (
                    try? $0.resourceValues(
                        forKeys: [
                            .contentModificationDateKey
                        ]
                    ).contentModificationDate
                ) ?? .distantPast
                let right = (
                    try? $1.resourceValues(
                        forKeys: [
                            .contentModificationDateKey
                        ]
                    ).contentModificationDate
                ) ?? .distantPast
                return left < right
            }
        if let latest {
            return DocumentScanSessionStore(
                fileManager: fileManager,
                sessionDirectory: latest
            )
        }
        return DocumentScanSessionStore(
            fileManager: fileManager,
            baseDirectory: base
        )
    }

    func loadPages() -> [DocumentScanPageRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy =
            .millisecondsSince1970
        guard let data = try? Data(
            contentsOf: manifestURL
        ),
        let manifest = try? decoder
            .decode(
                DocumentScanSessionManifest.self,
                from: data
            ),
        manifest.schemaVersion == 1 else {
            return []
        }
        return manifest.pages.filter {
            fileManager.fileExists(
                atPath: pageURL(for: $0).path
            )
        }
    }

    func append(
        image: UIImage,
        to pages: [DocumentScanPageRecord],
        jpegQuality: CGFloat = 0.95
    ) throws -> DocumentScanPageRecord {
        guard let data = image.jpegData(
            compressionQuality: jpegQuality
        ) else {
            throw DocumentScanSessionError
                .imageEncodingFailed
        }
        return try append(
            jpegData: data,
            to: pages
        )
    }

    func append(
        jpegData: Data,
        to pages: [DocumentScanPageRecord]
    ) throws -> DocumentScanPageRecord {
        guard pages.count
                < Self.maximumPageCount else {
            throw DocumentScanSessionError
                .pageLimitReached(
                    maximum:
                        Self.maximumPageCount
                )
        }
        try fileManager.createDirectory(
            at: sessionDirectory,
            withIntermediateDirectories: true
        )
        let id = UUID()
        let filename = "page-\(id.uuidString).jpg"
        let destination = sessionDirectory
            .appendingPathComponent(filename)
        try jpegData.write(
            to: destination,
            options: .atomic
        )
        let capturedAtMilliseconds =
            (
                Date()
                    .timeIntervalSince1970
                    * 1_000
            )
            .rounded(.down)
        return DocumentScanPageRecord(
            id: id,
            filename: filename,
            capturedAt: Date(
                timeIntervalSince1970:
                    capturedAtMilliseconds
                    / 1_000
            ),
            clockwiseQuarterTurns: 0
        )
    }

    func save(
        pages: [DocumentScanPageRecord]
    ) throws {
        try fileManager.createDirectory(
            at: sessionDirectory,
            withIntermediateDirectories: true
        )
        let manifest = DocumentScanSessionManifest(
            schemaVersion: 1,
            updatedAt: Date(),
            pages: pages
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy =
            .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(manifest)
            .write(
                to: manifestURL,
                options: .atomic
            )
    }

    func removeFile(
        for page: DocumentScanPageRecord
    ) throws {
        let url = pageURL(for: page)
        if fileManager.fileExists(
            atPath: url.path
        ) {
            try fileManager.removeItem(at: url)
        }
    }

    func image(
        for page: DocumentScanPageRecord
    ) throws -> UIImage {
        guard let image = UIImage(
            contentsOfFile:
                pageURL(for: page).path
        ) else {
            throw DocumentScanSessionError
                .imageDecodingFailed
        }
        return Self.applyingRotation(
            to: image,
            quarterTurns:
                page.normalizedQuarterTurns
        )
    }

    func makePDFData(
        pages: [DocumentScanPageRecord]
    ) throws -> Data {
        guard let first = pages.first else {
            throw DocumentScanSessionError.noPages
        }
        let firstImage = try image(for: first)
        let defaultBounds = Self.pdfBounds(
            for: firstImage
        )
        let renderer = UIGraphicsPDFRenderer(
            bounds: defaultBounds
        )
        var renderingError: Error?
        let data = renderer.pdfData { context in
            for page in pages {
                guard renderingError == nil else {
                    break
                }
                autoreleasepool {
                    do {
                        let pageImage = try self.image(
                            for: page
                        )
                        let bounds = Self.pdfBounds(
                            for: pageImage
                        )
                        context.beginPage(
                            withBounds: bounds,
                            pageInfo: [:]
                        )
                        pageImage.draw(in: bounds)
                    } catch {
                        renderingError = error
                    }
                }
            }
        }
        if let renderingError {
            throw renderingError
        }
        return data
    }

    func writeWorkingPDF(
        pages: [DocumentScanPageRecord],
        fileName: String = "VisionCraft Scan.pdf"
    ) throws -> URL {
        let data = try makePDFData(
            pages: pages
        )
        let outputDirectory = fileManager
            .temporaryDirectory
            .appendingPathComponent(
                "ScannedDocuments",
                isDirectory: true
            )
        try fileManager.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        let destination = outputDirectory
            .appendingPathComponent(
                UUID().uuidString
                    + "-"
                    + fileName
            )
        try data.write(
            to: destination,
            options: .atomic
        )
        return destination
    }

    func discard() {
        try? fileManager.removeItem(
            at: sessionDirectory
        )
    }

    func pageURL(
        for page: DocumentScanPageRecord
    ) -> URL {
        sessionDirectory
            .appendingPathComponent(
                page.filename
            )
    }

    private static func applyingRotation(
        to image: UIImage,
        quarterTurns: Int
    ) -> UIImage {
        guard let cgImage = image.cgImage else {
            return image
        }
        let orientation: UIImage.Orientation
        switch quarterTurns {
        case 1:
            orientation = .right
        case 2:
            orientation = .down
        case 3:
            orientation = .left
        default:
            orientation = .up
        }
        return UIImage(
            cgImage: cgImage,
            scale: image.scale,
            orientation: orientation
        )
    }

    private static func pdfBounds(
        for image: UIImage
    ) -> CGRect {
        CGRect(
            origin: .zero,
            size: CGSize(
                width: max(image.size.width, 1),
                height: max(image.size.height, 1)
            )
        )
    }
}
