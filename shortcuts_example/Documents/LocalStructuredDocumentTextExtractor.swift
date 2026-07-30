import Foundation

/// Shared, bounded local extraction for structured document formats that do
/// not have a native iPadOS text reader. The format-specific readers never
/// evaluate formulas, macros, scripts, or embedded objects.
nonisolated enum
    LocalStructuredDocumentTextExtractor
{
    static let supportedExtensions:
        Set<String> = [
            "xlsx",
            "xls",
            "hwp",
        ]

    static func extract(
        at url: URL
    ) async throws -> String {
        let pathExtension = url.pathExtension
            .lowercased()
        return try await Task.detached(
            priority: .userInitiated
        ) {
            let maximumBytes: Int
            switch pathExtension {
            case "xlsx":
                maximumBytes =
                    XLSXTextExtractor
                    .maximumWorkbookBytes
            case "xls":
                maximumBytes =
                    LegacyXLSExtractor
                    .maximumWorkbookBytes
            case "hwp":
                maximumBytes =
                    HWP5TextExtractor
                    .maximumDocumentBytes
            default:
                throw ChatAttachmentError
                    .unsupportedDocument
            }

            let values = try url.resourceValues(
                forKeys: [
                    .fileSizeKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                ]
            )
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true
            else {
                throw ChatAttachmentError
                    .unsupportedDocument
            }
            if let fileSize = values.fileSize,
               fileSize > maximumBytes {
                throw ChatAttachmentError
                    .fileTooLarge(
                        maximumMegabytes:
                            maximumBytes
                            / 1_024
                            / 1_024
                    )
            }
            let data = try Data(
                contentsOf: url,
                options: .mappedIfSafe
            )

            switch pathExtension {
            case "xlsx":
                return try XLSXTextExtractor
                    .extract(from: data)
            case "xls":
                return try LegacyXLSExtractor
                    .extract(from: data)
            case "hwp":
                return try HWP5TextExtractor
                    .extract(from: data)
            default:
                throw ChatAttachmentError
                    .unsupportedDocument
            }
        }
        .value
    }
}
