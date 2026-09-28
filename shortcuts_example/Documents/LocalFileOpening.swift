import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit

nonisolated enum VisionCraftFileTypes {
    static let epub =
        UTType(filenameExtension: "epub")
        ?? .data
    static let xlsx =
        UTType(filenameExtension: "xlsx")
        ?? .data
    static let xls =
        UTType(filenameExtension: "xls")
        ?? .data
    static let hwp =
        UTType(filenameExtension: "hwp")
        ?? .data
    static let hwpx =
        UTType(filenameExtension: "hwpx")
        ?? .data
    static let doc =
        UTType(filenameExtension: "doc")
        ?? .data
    static let docx =
        UTType(filenameExtension: "docx")
        ?? .data
    static let docs =
        UTType(filenameExtension: "docs")
        ?? .data

    static let openable: [UTType] = [
        .image,
    ] + documents + [
        epub,
    ]

    static let documents: [UTType] = [
        .pdf,
        .plainText,
        xlsx,
        xls,
        hwp,
        hwpx,
        doc,
        docx,
        docs,
    ]
}

/// The general document picker must never hand a file to the book reader.
/// EPUB and DAISY ZIP imports belong exclusively to ReaderLibraryView.
nonisolated enum DocumentLibraryFilePolicy {
    static func allows(
        pathExtension rawValue: String
    ) -> Bool {
        let pathExtension = rawValue
            .lowercased()
        guard pathExtension != "epub",
              pathExtension != "zip"
        else {
            return false
        }
        return AuthorizedDocumentSearch
            .supportedExtensions
            .contains(pathExtension)
    }
}

@MainActor
enum LocalFileOpening {
    static func route(
        for sourceURL: URL
    ) async throws -> AppRoute {
        // URLs returned by SwiftUI's fileImporter can point outside the
        // sandbox. Start the security-scoped access before even asking for
        // resource values; Files' Recent Items commonly rejects that metadata
        // read when it happens before the scope is active.
        let didAccess = sourceURL
            .startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL
                    .stopAccessingSecurityScopedResource()
            }
        }

        let pathExtension = sourceURL
            .pathExtension
            .lowercased()
        let contentType = try sourceURL
            .resourceValues(
                forKeys: [.contentTypeKey]
            )
            .contentType
            ?? UTType(
                filenameExtension:
                    pathExtension
            )

        if pathExtension == "epub" {
            let bookURL = try await
                EPUBLibraryStore.shared
                .importBook(from: sourceURL)
            EPUBProgressStore.lastBookURL =
                bookURL
            return .epubReader(
                fileURL: bookURL
            )
        }
        if contentType?.conforms(
            to: .image
        ) == true {
            let image = try image(from: sourceURL)
            return .OCRResult(image: image)
        }

        let isSupportedDocument =
            contentType?.conforms(
                to: .pdf
            ) == true
            || contentType?.conforms(
                to: .plainText
            ) == true
            || AuthorizedDocumentSearch
                .supportedExtensions
                .contains(pathExtension)
        guard isSupportedDocument else {
            throw AuthorizedDocumentLibraryError
                .unsupportedDocument
        }
        let importedURL = try await
            LocalDocumentImportService.shared
            .importDocument(from: sourceURL)
        return .localDocument(
            fileURL: importedURL
        )
    }

    static func image(
        from sourceURL: URL
    ) throws -> UIImage {
        let didAccess = sourceURL
            .startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL
                    .stopAccessingSecurityScopedResource()
            }
        }
        let data = try Data(
            contentsOf: sourceURL,
            options: .mappedIfSafe
        )
        guard let image = UIImage(data: data) else {
            throw CocoaError(
                .fileReadCorruptFile
            )
        }
        return image
    }
}
