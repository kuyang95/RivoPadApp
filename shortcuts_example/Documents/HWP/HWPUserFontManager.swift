import RivoDocumentEngine
import CoreText
import Combine
import SwiftUI
import UniformTypeIdentifiers

nonisolated struct HWPImportedFont: Identifiable, Hashable, Sendable {
    let url: URL
    let displayName: String
    let postScriptNames: [String]
    let aliases: [String]

    var id: URL { url }
}

nonisolated struct HWPFontDiagnostic: Identifiable, Hashable, Sendable {
    let declaredName: String
    let resolvedName: String?
    let kind: HWPFontResolutionKind
    let detail: String

    var id: String { declaredName.precomposedStringWithCompatibilityMapping.lowercased() }

    @MainActor
    static func make(blocks: [HWPDocumentBlock]) -> [HWPFontDiagnostic] {
        var runs: [HWPDocumentTextRun] = []
        for block in blocks {
            runs.append(contentsOf: block.presentation.textRuns)
            runs.append(contentsOf: block.lineLayouts.flatMap(\.textRuns))
        }
        var seen: Set<String> = []
        return runs.compactMap { run in
            guard let declared = run.fontName?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !declared.isEmpty else { return nil }
            let key = normalize(declared)
            guard seen.insert(key).inserted else { return nil }
            let resolution = HWPDocumentFontResolver.resolution(for: run)
            return HWPFontDiagnostic(
                declaredName: declared,
                resolvedName: resolution.resolvedName,
                kind: resolution.kind,
                detail: resolution.detail
            )
        }.sorted {
            if $0.kind != $1.kind { return rank($0.kind) < rank($1.kind) }
            return $0.declaredName.localizedStandardCompare($1.declaredName) == .orderedAscending
        }
    }

    private static func rank(_ kind: HWPFontResolutionKind) -> Int {
        switch kind {
        case .systemFallback: return 0
        case .compatible: return 1
        case .documentAlternative: return 2
        case .exact: return 3
        }
    }

    private static func normalize(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
    }
}

@MainActor
final class HWPUserFontManager: ObservableObject {
    static let shared = HWPUserFontManager()

    @Published private(set) var importedFonts: [HWPImportedFont] = []
    @Published private(set) var revision = 0
    @Published var errorDescription: String?

    private var aliasMap: [String: String] = [:]
    private let maximumFontBytes = 64 * 1_024 * 1_024

    private init() {
        reloadStoredFonts()
    }

    func resolvedPostScriptName(for declaredName: String) -> String? {
        aliasMap[normalize(declaredName)]
    }

    func importFonts(from urls: [URL]) {
        errorDescription = nil
        do {
            let directory = try fontDirectory()
            var importedCount = 0
            for source in urls {
                let accessing = source.startAccessingSecurityScopedResource()
                defer {
                    if accessing { source.stopAccessingSecurityScopedResource() }
                }
                let values = try source.resourceValues(forKeys: [.fileSizeKey])
                guard let size = values.fileSize, size > 0, size <= maximumFontBytes else {
                    throw FontImportError.invalidSize
                }
                let data = try Data(contentsOf: source, options: [.mappedIfSafe])
                guard Self.isSupportedFont(data) else {
                    throw FontImportError.unsupportedFormat
                }
                let name = Self.sanitizedFileName(source.lastPathComponent)
                let destination = directory.appendingPathComponent(
                    "\(UUID().uuidString)-\(name)"
                )
                try data.write(to: destination, options: .atomic)
                guard Self.metadata(for: destination) != nil else {
                    try? FileManager.default.removeItem(at: destination)
                    throw FontImportError.unsupportedFormat
                }
                importedCount += 1
            }
            reloadStoredFonts()
            if importedCount == 0 { throw FontImportError.unsupportedFormat }
        } catch {
            errorDescription = error.localizedDescription
        }
    }

    func remove(_ font: HWPImportedFont) {
        do {
            var unregisterError: Unmanaged<CFError>?
            _ = CTFontManagerUnregisterFontsForURL(
                font.url as CFURL,
                .process,
                &unregisterError
            )
            try FileManager.default.removeItem(at: font.url)
            reloadStoredFonts()
        } catch {
            errorDescription = error.localizedDescription
        }
    }

    func reloadStoredFonts() {
        do {
            let directory = try fontDirectory()
            let urls = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ).filter { Self.supportedExtensions.contains($0.pathExtension.lowercased()) }

            var fonts: [HWPImportedFont] = []
            var aliases: [String: String] = [:]
            for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                var registrationError: Unmanaged<CFError>?
                _ = CTFontManagerRegisterFontsForURL(
                    url as CFURL,
                    .process,
                    &registrationError
                )
                guard let metadata = Self.metadata(for: url) else { continue }
                fonts.append(metadata.font)
                for item in metadata.aliasMappings {
                    aliases[normalize(item.alias)] = item.postScriptName
                }
                for postScript in metadata.font.postScriptNames {
                    aliases[normalize(postScript)] = postScript
                }
            }
            importedFonts = fonts
            aliasMap = aliases
            revision &+= 1
        } catch {
            errorDescription = error.localizedDescription
        }
    }

    private func fontDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("HWPFonts", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func normalize(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "#", with: "")
    }

    private static let supportedExtensions = ["ttf", "otf", "ttc", "otc"]

    private static func isSupportedFont(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        let signature = Array(data.prefix(4))
        return signature == [0x00, 0x01, 0x00, 0x00]
            || signature == Array("OTTO".utf8)
            || signature == Array("ttcf".utf8)
            || signature == Array("true".utf8)
    }

    private struct FontMetadata {
        let font: HWPImportedFont
        let aliasMappings: [(alias: String, postScriptName: String)]
    }

    private static func metadata(for url: URL) -> FontMetadata? {
        guard let values = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL)
                as? [CTFontDescriptor],
              !values.isEmpty else { return nil }
        var postScriptNames: [String] = []
        var aliases: [String] = []
        var aliasMappings: [(String, String)] = []
        for descriptor in values {
            guard let postScriptName = CTFontDescriptorCopyAttribute(
                descriptor,
                kCTFontNameAttribute
            ) as? String,
                  !postScriptName.isEmpty else { continue }
            postScriptNames.append(postScriptName)
            for attribute in [
                kCTFontNameAttribute,
                kCTFontFamilyNameAttribute,
                kCTFontDisplayNameAttribute,
                kCTFontStyleNameAttribute,
            ] {
                if let value = CTFontDescriptorCopyAttribute(descriptor, attribute)
                    as? String,
                   !value.isEmpty {
                    aliases.append(value)
                    aliasMappings.append((value, postScriptName))
                }
            }
        }
        let uniquePostScript = Array(Set(postScriptNames)).sorted()
        let uniqueAliases = Array(Set(aliases)).sorted()
        guard !uniquePostScript.isEmpty else { return nil }
        let displayName = uniqueAliases.first(where: {
            !uniquePostScript.contains($0)
        }) ?? uniquePostScript[0]
        if let fileAlias = originalFileStem(for: url),
           let firstPostScript = uniquePostScript.first {
            aliases.append(fileAlias)
            aliasMappings.append((fileAlias, firstPostScript))
        }
        return FontMetadata(
            font: HWPImportedFont(
                url: url,
                displayName: displayName,
                postScriptNames: uniquePostScript,
                aliases: Array(Set(aliases)).sorted()
            ),
            aliasMappings: aliasMappings.map {
                (alias: $0.0, postScriptName: $0.1)
            }
        )
    }

    private static func originalFileStem(for url: URL) -> String? {
        let stored = url.deletingPathExtension().lastPathComponent
        let value: Substring
        if stored.count > 37,
           stored[stored.index(stored.startIndex, offsetBy: 36)] == "-" {
            value = stored.dropFirst(37)
        } else {
            value = Substring(stored)
        }
        let result = String(value).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private static func sanitizedFileName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }
        let result = String(scalars)
        return result.isEmpty ? "ImportedFont.ttf" : result
    }
}

private enum FontImportError: LocalizedError {
    case invalidSize
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .invalidSize:
            return "글꼴 파일은 64MB 이하여야 합니다."
        case .unsupportedFormat:
            return "지원되는 TTF, OTF, TTC 또는 OTC 글꼴 파일이 아닙니다."
        }
    }
}

struct HWPFontManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: HWPUserFontManager
    let diagnosticsProvider: @MainActor () -> [HWPFontDiagnostic]
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            List {
                Section("현재 문서") {
                    let diagnostics = diagnosticsProvider()
                    if diagnostics.isEmpty {
                        Text("문서에서 선언한 글꼴이 없습니다.")
                            .foregroundStyle(.secondary)
                    } else {
                        summary(diagnostics)
                        ForEach(diagnostics) { item in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: icon(item.kind))
                                    .foregroundStyle(color(item.kind))
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.declaredName)
                                    Text(mappingDescription(item))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("가져온 글꼴") {
                    if manager.importedFonts.isEmpty {
                        Text("정식으로 보유한 글꼴을 가져오면 앱 안에서만 등록됩니다.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(manager.importedFonts) { font in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(font.displayName)
                            Text(font.postScriptNames.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button("삭제", role: .destructive) {
                                manager.remove(font)
                            }
                        }
                    }
                    Button("TTF/OTF 글꼴 가져오기", systemImage: "plus.circle") {
                        isImporting = true
                    }
                }

                Section {
                    Text("가져오는 글꼴은 사용자가 적법한 사용권을 보유해야 합니다. 앱은 글꼴을 다른 앱이나 사용자에게 재배포하지 않습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("HWP 글꼴")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.font],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls): manager.importFonts(from: urls)
                case .failure(let error): manager.errorDescription = error.localizedDescription
                }
            }
            .alert(
                "글꼴을 가져올 수 없습니다",
                isPresented: Binding(
                    get: { manager.errorDescription != nil },
                    set: { if !$0 { manager.errorDescription = nil } }
                )
            ) {
                Button("확인", role: .cancel) { manager.errorDescription = nil }
            } message: {
                Text(manager.errorDescription ?? "")
            }
        }
    }

    @ViewBuilder
    private func summary(_ diagnostics: [HWPFontDiagnostic]) -> some View {
        let exact = diagnostics.filter { $0.kind == .exact }.count
        let alternative = diagnostics.filter { $0.kind == .documentAlternative }.count
        let compatible = diagnostics.filter { $0.kind == .compatible }.count
        let fallback = diagnostics.filter { $0.kind == .systemFallback }.count
        Text("원본 일치 \(exact) · 문서 대체 \(alternative) · 호환 \(compatible) · 기본 글꼴 \(fallback)")
            .font(.subheadline.weight(.semibold))
    }

    private func mappingDescription(_ item: HWPFontDiagnostic) -> String {
        let target = item.resolvedName ?? "iPadOS 기본 글꼴"
        return "\(target) · \(item.detail)"
    }

    private func icon(_ kind: HWPFontResolutionKind) -> String {
        switch kind {
        case .exact: return "checkmark.circle.fill"
        case .documentAlternative: return "arrow.triangle.2.circlepath.circle.fill"
        case .compatible: return "arrow.left.arrow.right.circle.fill"
        case .systemFallback: return "exclamationmark.triangle.fill"
        }
    }

    private func color(_ kind: HWPFontResolutionKind) -> Color {
        switch kind {
        case .exact: return .green
        case .documentAlternative: return .blue
        case .compatible: return .orange
        case .systemFallback: return .red
        }
    }
}
