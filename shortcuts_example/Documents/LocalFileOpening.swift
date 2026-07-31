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

    static let openable: [UTType] = [
        .image,
        .pdf,
        .plainText,
        epub,
        xlsx,
        xls,
        hwp,
        hwpx,
    ]
}

@MainActor
enum LocalFileOpening {
    static func route(
        for sourceURL: URL
    ) async throws -> AppRoute {
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
            guard let image = UIImage(data: data)
            else {
                throw CocoaError(
                    .fileReadCorruptFile
                )
            }
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
}
