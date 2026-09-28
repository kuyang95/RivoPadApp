#if DEBUG
import CryptoKit
import Foundation
import PDFKit

/// App-owned comparison documents and persistent reference overrides.
/// Paths are relative to Documents so links survive app container relocation.
nonisolated struct HWPComparisonLibrary: Sendable {
    let documentsDirectory: URL

    static var current: Self {
        Self(documentsDirectory: FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        )[0])
    }

    var sourceDirectory: URL {
        documentsDirectory.appendingPathComponent("한글 문서", isDirectory: true)
    }

    var resultsDirectory: URL {
        documentsDirectory.appendingPathComponent("HWP 비교 PDF", isDirectory: true)
    }

    func documents() throws -> [URL] {
        let urls = try files(in: sourceDirectory, extensions: ["hwp", "hwpx"])
        return urls.sorted {
            let leftHasReference = referencePDF(for: $0) != nil
            let rightHasReference = referencePDF(for: $1) != nil
            if leftHasReference != rightHasReference { return leftHasReference }
            return $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    func resultPDFs() throws -> [URL] {
        try files(in: resultsDirectory, extensions: ["pdf"])
    }

    func referencePDF(for document: URL) -> URL? {
        if let override = try? referenceOverride(for: document),
           FileManager.default.fileExists(atPath: override.path) {
            return override
        }
        let stem = document.deletingPathExtension().lastPathComponent.lowercased()
        let siblings = (try? FileManager.default.contentsOfDirectory(
            at: document.deletingLastPathComponent(),
            includingPropertiesForKeys: [.isRegularFileKey]
        )) ?? []
        return siblings.first {
            $0.pathExtension.lowercased() == "pdf"
                && $0.deletingPathExtension().lastPathComponent.lowercased() == stem
                && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

    /// Copies a selected PDF without replacing the publisher's original PDF.
    func connectReference(_ source: URL, to document: URL) throws {
        let destination = try referenceOverride(for: document)
        let data = try readImport(source, expectedExtension: "pdf")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: destination, options: .atomic)
    }

    /// Each import gets its own folder; repeated names never overwrite prior cases.
    func importDocuments(_ sources: [URL]) throws -> [URL] {
        guard !sources.isEmpty, sources.count <= 40,
              sources.contains(where: { ["hwp", "hwpx"].contains($0.pathExtension.lowercased()) }) else {
            throw LibraryError.message("HWP 또는 HWPX를 선택해 주세요. 정답 PDF는 함께 선택하거나 문서를 연 뒤 연결할 수 있습니다.")
        }
        var names = Set<String>()
        var contents: [(String, Data)] = []
        var totalBytes = 0
        for source in sources {
            let name = source.lastPathComponent
            guard names.insert(name.lowercased()).inserted else {
                throw LibraryError.message("같은 이름의 파일은 한 번에 추가할 수 없습니다: \(name)")
            }
            let data = try readImport(source)
            totalBytes += data.count
            guard totalBytes <= 200 * 1024 * 1024 else {
                throw LibraryError.message("자료가 큽니다. 나누어 추가해 주세요.")
            }
            contents.append((name, data))
        }
        let folder = sourceDirectory.appendingPathComponent("추가 비교 자료", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (name, data) in contents {
                try data.write(to: folder.appendingPathComponent(name), options: .atomic)
            }
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return contents.filter { ["hwp", "hwpx"].contains(URL(fileURLWithPath: $0.0).pathExtension.lowercased()) }
            .map { folder.appendingPathComponent($0.0) }
    }

    private func files(in root: URL, extensions: Set<String>) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        var failure: Error?
        let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, error in failure = error; return false }
        )
        var result: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { enumerator?.skipDescendants(); continue }
            if values.isRegularFile == true, extensions.contains(url.pathExtension.lowercased()) {
                result.append(url)
            }
        }
        if let failure { throw failure }
        return result.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func referenceOverride(for document: URL) throws -> URL {
        let root = documentsDirectory.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let path = document.resolvingSymlinksInPath().standardizedFileURL.path
        guard path.hasPrefix(root) else { throw LibraryError.message("앱에 추가한 문서만 비교할 수 있습니다.") }
        let relative = String(path.dropFirst(root.count)).precomposedStringWithCanonicalMapping
        let key = SHA256.hash(data: Data(relative.utf8)).map { String(format: "%02x", $0) }.joined()
        return documentsDirectory.appendingPathComponent(".HWPComparisonReferences", isDirectory: true)
            .appendingPathComponent(key + ".pdf")
    }

    private func readImport(_ url: URL, expectedExtension: String? = nil) throws -> Data {
        let ext = url.pathExtension.lowercased()
        guard ["hwp", "hwpx", "pdf"].contains(ext), expectedExtension == nil || ext == expectedExtension else {
            throw LibraryError.message("HWP, HWPX, PDF만 추가할 수 있습니다: \(url.lastPathComponent)")
        }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 128 * 1024 * 1024 else { throw LibraryError.message("파일이 너무 큽니다: \(url.lastPathComponent)") }
        let data = try CoordinatedDocumentFileAccess.readData(from: url)
        let valid: Bool
        switch ext {
        case "hwp": valid = data.starts(with: [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])
        case "hwpx": valid = data.starts(with: [0x50, 0x4B, 0x03, 0x04])
        default:
            if let pdf = PDFDocument(data: data) {
                valid = !pdf.isLocked && pdf.pageCount > 0
            } else { valid = false }
        }
        guard valid else { throw LibraryError.message("읽을 수 있는 \(ext.uppercased()) 파일이 아닙니다: \(url.lastPathComponent)") }
        return data
    }

    private enum LibraryError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
    }
}
#endif
