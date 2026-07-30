import Combine
import Foundation
import SwiftUI
import UIKit

@MainActor
final class DocumentScanSessionModel:
    ObservableObject
{
    @Published private(set) var pages:
        [DocumentScanPageRecord]
    @Published private(set) var errorDescription:
        String?

    let store: DocumentScanSessionStore

    init(
        store: DocumentScanSessionStore =
            .restoringLatest()
    ) {
        self.store = store
        pages = store.loadPages()
        errorDescription = nil
    }

    var canAddPage: Bool {
        pages.count
            < DocumentScanSessionStore
                .maximumPageCount
    }

    @discardableResult
    func append(
        _ image: UIImage
    ) -> Bool {
        do {
            let page = try store.append(
                image: image,
                to: pages
            )
            var updatedPages = pages
            updatedPages.append(page)
            do {
                try store.save(
                    pages: updatedPages
                )
            } catch {
                try? store.removeFile(
                    for: page
                )
                throw error
            }
            pages = updatedPages
            errorDescription = nil
            return true
        } catch {
            errorDescription =
                error.localizedDescription
            return false
        }
    }

    func rotate(
        _ page: DocumentScanPageRecord
    ) {
        guard let index = pages.firstIndex(
            where: { $0.id == page.id }
        ) else {
            return
        }
        var updatedPages = pages
        updatedPages[index].rotateClockwise()
        commit(updatedPages)
    }

    func remove(
        _ page: DocumentScanPageRecord
    ) {
        guard let index = pages.firstIndex(
            where: { $0.id == page.id }
        ) else {
            return
        }
        let removedPage = pages[index]
        var updatedPages = pages
        updatedPages.remove(at: index)
        commit(
            updatedPages,
            removing: [removedPage]
        )
    }

    func remove(
        at offsets: IndexSet
    ) {
        let records = offsets.compactMap {
            pages.indices.contains($0)
                ? pages[$0]
                : nil
        }
        var updatedPages = pages
        updatedPages.remove(
            atOffsets: offsets
        )
        commit(
            updatedPages,
            removing: records
        )
    }

    func move(
        from source: IndexSet,
        to destination: Int
    ) {
        var updatedPages = pages
        updatedPages.move(
            fromOffsets: source,
            toOffset: destination
        )
        commit(updatedPages)
    }

    func image(
        for page: DocumentScanPageRecord
    ) -> UIImage? {
        try? store.image(
            for: page
        )
    }

    func makePDFData() async throws -> Data {
        let snapshot = pages
        let store = store
        return try await Task.detached(
            priority: .userInitiated
        ) {
            try store.makePDFData(
                pages: snapshot
            )
        }.value
    }

    func writeWorkingPDF() async throws -> URL {
        let snapshot = pages
        let store = store
        return try await Task.detached(
            priority: .userInitiated
        ) {
            try store.writeWorkingPDF(
                pages: snapshot
            )
        }.value
    }

    func clearError() {
        errorDescription = nil
    }

    func discard() {
        store.discard()
        pages = []
        errorDescription = nil
    }

    private func commit(
        _ updatedPages:
            [DocumentScanPageRecord],
        removing removedPages:
            [DocumentScanPageRecord] = []
    ) {
        do {
            if updatedPages.isEmpty {
                store.discard()
            } else {
                try store.save(
                    pages: updatedPages
                )
                for page in removedPages {
                    try? store.removeFile(
                        for: page
                    )
                }
            }
            pages = updatedPages
            errorDescription = nil
        } catch {
            errorDescription =
                error.localizedDescription
        }
    }
}
