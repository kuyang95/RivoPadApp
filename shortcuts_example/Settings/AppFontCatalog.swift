import CoreText
import Combine
import CryptoKit
import Foundation
import SwiftUI

nonisolated struct AppFontFile:
    Codable,
    Equatable,
    Sendable
{
    let path: String
    let url: URL
    let bytes: Int64
    let sha256: String
}

nonisolated struct AppFontFiles:
    Codable,
    Equatable,
    Sendable
{
    let regular: AppFontFile
    let bold: AppFontFile

    var uniqueFiles: [AppFontFile] {
        regular == bold
            ? [regular]
            : [regular, bold]
    }
}

nonisolated struct AppFontOption:
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
    private enum CodingKeys:
        String,
        CodingKey
    {
        case key
        case labels
        case scripts
        case license
        case licenseURL = "licenseUrl"
        case files
    }

    static let systemKey = "system"
    static let bundledNanumKey =
        "nanumSquareRound"

    let key: String
    let labels: [String: String]
    let scripts: [String]
    let license: String?
    let licenseURL: URL?
    let files: AppFontFiles?

    var id: String {
        key
    }

    var isSystem: Bool {
        key == Self.systemKey
    }

    var isBundled: Bool {
        key == Self.bundledNanumKey
    }

    var displayLanguageCode: String? {
        scripts.first
    }

    func label(languageCode: String) -> String {
        labels[languageCode]
            ?? labels["en"]
            ?? labels["ko"]
            ?? labels.values.first
            ?? key
    }

    func isVisible(
        for languageCode: String
    ) -> Bool {
        isSystem
            || isBundled
            || displayLanguageCode
                == languageCode
    }

    static let system =
        AppFontOption(
            key: systemKey,
            labels: [
                "ko": "iPad 시스템 글꼴",
                "en": "iPad System Font",
                "ja": "iPadシステムフォント",
            ],
            scripts: [],
            license: nil,
            licenseURL: nil,
            files: nil
        )

    static let bundledNanum =
        AppFontOption(
            key: bundledNanumKey,
            labels: [
                "ko": "나눔스퀘어라운드",
                "en": "NanumSquareRound",
                "ja": "NanumSquareRound",
            ],
            scripts: ["ko", "en", "ja"],
            license:
                "Bundled application font",
            licenseURL: nil,
            files: nil
        )
}

nonisolated struct AppFontManifest:
    Decodable,
    Equatable,
    Sendable
{
    private enum CodingKeys:
        String,
        CodingKey
    {
        case schemaVersion
        case generatedAt
        case baseURL = "baseUrl"
        case fonts
    }

    let schemaVersion: Int
    let generatedAt: String?
    let baseURL: URL
    let fonts: [AppFontOption]
}

nonisolated enum AppFontCatalogError:
    Error,
    Equatable,
    LocalizedError,
    Sendable
{
    case invalidManifest
    case unsupportedSchema
    case tooManyFonts
    case duplicateKey
    case invalidKey
    case invalidLabel
    case invalidScript
    case invalidLicenseURL
    case invalidFilePath
    case invalidFileURL
    case invalidFileSize
    case invalidSHA256
    case responseTooLarge
    case invalidHTTPResponse
    case downloadVerificationFailed
    case unavailableFont
    case registrationFailed

    var errorDescription: String? {
        switch self {
        case .invalidManifest:
            return AppLocalization.string(
                "글꼴 목록 형식이 올바르지 않습니다."
            )
        case .unsupportedSchema:
            return AppLocalization.string(
                "지원하지 않는 글꼴 목록 버전입니다."
            )
        case .tooManyFonts:
            return AppLocalization.string(
                "글꼴 목록 항목이 너무 많습니다."
            )
        case .duplicateKey:
            return AppLocalization.string(
                "글꼴 목록에 중복 항목이 있습니다."
            )
        case .invalidKey:
            return AppLocalization.string(
                "글꼴 식별자가 올바르지 않습니다."
            )
        case .invalidLabel:
            return AppLocalization.string(
                "글꼴 이름이 올바르지 않습니다."
            )
        case .invalidScript:
            return AppLocalization.string(
                "글꼴 언어 정보가 올바르지 않습니다."
            )
        case .invalidLicenseURL:
            return AppLocalization.string(
                "글꼴 라이선스 주소가 안전하지 않습니다."
            )
        case .invalidFilePath:
            return AppLocalization.string(
                "글꼴 파일 이름이 올바르지 않습니다."
            )
        case .invalidFileURL:
            return AppLocalization.string(
                "글꼴 다운로드 주소가 안전하지 않습니다."
            )
        case .invalidFileSize:
            return AppLocalization.string(
                "글꼴 파일 크기가 올바르지 않습니다."
            )
        case .invalidSHA256:
            return AppLocalization.string(
                "글꼴 파일 검증값이 올바르지 않습니다."
            )
        case .responseTooLarge:
            return AppLocalization.string(
                "글꼴 목록 응답이 너무 큽니다."
            )
        case .invalidHTTPResponse:
            return AppLocalization.string(
                "글꼴 서버 응답을 확인할 수 없습니다."
            )
        case .downloadVerificationFailed:
            return AppLocalization.string(
                "다운로드한 글꼴의 크기 또는 검증값이 다릅니다."
            )
        case .unavailableFont:
            return AppLocalization.string(
                "선택한 글꼴을 사용할 수 없습니다."
            )
        case .registrationFailed:
            return AppLocalization.string(
                "다운로드한 글꼴을 iPadOS에 등록하지 못했습니다."
            )
        }
    }
}

nonisolated enum AppFontManifestParser {
    static let maximumManifestBytes =
        256 * 1_024
    static let maximumFontCount = 32
    static let maximumFontBytes:
        Int64 = 32 * 1_024 * 1_024

    static func parse(
        _ data: Data
    ) throws -> AppFontManifest {
        guard data.count
                <= maximumManifestBytes else {
            throw AppFontCatalogError
                .responseTooLarge
        }

        let manifest: AppFontManifest
        do {
            manifest =
                try JSONDecoder().decode(
                    AppFontManifest.self,
                    from: data
                )
        } catch {
            throw AppFontCatalogError
                .invalidManifest
        }

        guard manifest.schemaVersion == 1
        else {
            throw AppFontCatalogError
                .unsupportedSchema
        }
        guard manifest.fonts.count
                <= maximumFontCount else {
            throw AppFontCatalogError
                .tooManyFonts
        }
        guard isTrustedFontURL(
            manifest.baseURL
        ) else {
            throw AppFontCatalogError
                .invalidFileURL
        }

        var seenKeys = Set<String>()
        for option in manifest.fonts {
            try validate(
                option,
                seenKeys: &seenKeys
            )
        }
        return manifest
    }

    private static func validate(
        _ option: AppFontOption,
        seenKeys: inout Set<String>
    ) throws {
        guard option.key.range(
            of:
                #"^[A-Za-z0-9_-]{1,64}$"#,
            options: .regularExpression
        ) != nil,
        option.key != AppFontOption.systemKey,
        option.key
            != AppFontOption
            .bundledNanumKey else {
            throw AppFontCatalogError
                .invalidKey
        }
        guard seenKeys.insert(
            option.key
        ).inserted else {
            throw AppFontCatalogError
                .duplicateKey
        }
        guard !option.labels.isEmpty,
              option.labels.count <= 3,
              option.labels.allSatisfy({
                  ["ko", "en", "ja"]
                      .contains($0.key)
                      && !$0.value
                      .trimmingCharacters(
                          in:
                              .whitespacesAndNewlines
                      )
                      .isEmpty
                      && $0.value.count <= 100
              }) else {
            throw AppFontCatalogError
                .invalidLabel
        }
        guard let firstScript =
                option.scripts.first,
              ["ko", "en", "ja"]
                .contains(firstScript),
              option.scripts.count <= 3,
              option.scripts.allSatisfy({
                  ["ko", "en", "ja"]
                      .contains($0)
              }) else {
            throw AppFontCatalogError
                .invalidScript
        }
        guard let licenseURL =
                option.licenseURL,
              isTrustedLicenseURL(
                  licenseURL
              ) else {
            throw AppFontCatalogError
                .invalidLicenseURL
        }
        guard let files = option.files
        else {
            throw AppFontCatalogError
                .invalidManifest
        }
        try validate(files.regular)
        try validate(files.bold)
    }

    private static func validate(
        _ file: AppFontFile
    ) throws {
        let pathURL = URL(
            fileURLWithPath: file.path
        )
        guard !file.path.isEmpty,
              pathURL.lastPathComponent
                == file.path,
              !file.path.contains(".."),
              ["otf", "ttf"].contains(
                  pathURL.pathExtension
                      .lowercased()
              ) else {
            throw AppFontCatalogError
                .invalidFilePath
        }
        guard isTrustedFontURL(
            file.url
        ) else {
            throw AppFontCatalogError
                .invalidFileURL
        }
        guard file.bytes > 0,
              file.bytes
                <= maximumFontBytes else {
            throw AppFontCatalogError
                .invalidFileSize
        }
        guard file.sha256.range(
            of: #"^[0-9a-fA-F]{64}$"#,
            options: .regularExpression
        ) != nil else {
            throw AppFontCatalogError
                .invalidSHA256
        }
    }

    static func isTrustedFontURL(
        _ url: URL
    ) -> Bool {
        isTrustedURL(url)
            && (
                url.path
                    == "/app/VisionCraft/fonts"
                    || url.path.hasPrefix(
                        "/app/VisionCraft/fonts/"
                    )
            )
    }

    static func isTrustedLicenseURL(
        _ url: URL
    ) -> Bool {
        isTrustedFontURL(url)
            && url.path.contains(
                "/fonts/licenses/"
            )
    }

    private static func isTrustedURL(
        _ url: URL
    ) -> Bool {
        guard let components =
                URLComponents(
                    url: url,
                    resolvingAgainstBaseURL:
                        false
                ) else {
            return false
        }
        return (
            components.scheme?
                .lowercased() == "https"
        )
            && (
                components.host?
                    .lowercased()
                    == "rivo.me"
            )
            && components.port == nil
            && components.user == nil
            && components.password == nil
            && components.query == nil
            && components.fragment == nil
    }
}

nonisolated enum AppFontIntegrity {
    static let bufferSize = 32 * 1_024

    static func sha256(
        of fileURL: URL
    ) throws -> String {
        let handle =
            try FileHandle(
                forReadingFrom: fileURL
            )
        defer {
            try? handle.close()
        }
        var hasher = SHA256()
        while true {
            let data =
                try handle.read(
                    upToCount: bufferSize
                )
                ?? Data()
            guard !data.isEmpty else {
                break
            }
            hasher.update(data: data)
        }
        return hasher.finalize()
            .map {
                String(
                    format: "%02x",
                    $0
                )
            }
            .joined()
    }

    static func verify(
        _ fileURL: URL,
        expectedBytes: Int64,
        expectedSHA256: String
    ) throws -> Bool {
        let values =
            try fileURL.resourceValues(
                forKeys: [
                    .isRegularFileKey,
                    .fileSizeKey,
                ]
            )
        guard values.isRegularFile == true,
              Int64(values.fileSize ?? -1)
                == expectedBytes else {
            return false
        }
        return try sha256(
            of: fileURL
        ).caseInsensitiveCompare(
            expectedSHA256
        ) == .orderedSame
    }
}

actor AppFontDiskStore {
    private let rootURL: URL
    private let fileManager:
        FileManager

    init(
        rootURL: URL,
        fileManager:
            FileManager = .default
    ) {
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    func loadManifest() throws
        -> Data?
    {
        let url = manifestURL
        guard fileManager.fileExists(
            atPath: url.path
        ) else {
            return nil
        }
        return try Data(
            contentsOf: url,
            options: .mappedIfSafe
        )
    }

    func saveManifest(
        _ data: Data
    ) throws {
        try createRootIfNeeded()
        try data.write(
            to: manifestURL,
            options: .atomic
        )
    }

    func hasVerifiedFile(
        optionKey: String,
        file: AppFontFile
    ) -> Bool {
        let target =
            localURL(
                optionKey: optionKey,
                file: file
            )
        return (try? AppFontIntegrity
            .verify(
                target,
                expectedBytes:
                    file.bytes,
                expectedSHA256:
                    file.sha256
            )) == true
    }

    func install(
        downloadedURL: URL,
        optionKey: String,
        file: AppFontFile
    ) throws {
        guard try AppFontIntegrity
            .verify(
                downloadedURL,
                expectedBytes:
                    file.bytes,
                expectedSHA256:
                    file.sha256
            ) else {
            throw AppFontCatalogError
                .downloadVerificationFailed
        }

        let directory =
            rootURL.appending(
                path: optionKey,
                directoryHint:
                    .isDirectory
            )
        try fileManager
            .createDirectory(
                at: directory,
                withIntermediateDirectories:
                    true
            )
        let target =
            localURL(
                optionKey: optionKey,
                file: file
            )
        let staging =
            directory.appending(
                path:
                    ".\(file.path)."
                    + UUID().uuidString
                    + ".tmp"
            )
        try fileManager.copyItem(
            at: downloadedURL,
            to: staging
        )
        guard try AppFontIntegrity
            .verify(
                staging,
                expectedBytes:
                    file.bytes,
                expectedSHA256:
                    file.sha256
            ) else {
            try? fileManager
                .removeItem(at: staging)
            throw AppFontCatalogError
                .downloadVerificationFailed
        }
        if fileManager.fileExists(
            atPath: target.path
        ) {
            try fileManager.removeItem(
                at: target
            )
        }
        try fileManager.moveItem(
            at: staging,
            to: target
        )
    }

    func registerVerifiedFonts(
        for option: AppFontOption
    ) throws -> String {
        guard let files = option.files
        else {
            throw AppFontCatalogError
                .unavailableFont
        }
        var regularDescriptor:
            CTFontDescriptor?
        for file in files.uniqueFiles {
            let url =
                localURL(
                    optionKey: option.key,
                    file: file
                )
            guard try AppFontIntegrity
                .verify(
                    url,
                    expectedBytes:
                        file.bytes,
                    expectedSHA256:
                        file.sha256
                ) else {
                throw AppFontCatalogError
                    .unavailableFont
            }
            let data =
                try Data(
                    contentsOf: url,
                    options: .mappedIfSafe
                )
            guard let descriptors =
                    CTFontManagerCreateFontDescriptorsFromData(
                        data as CFData
                    ) as? [CTFontDescriptor],
                  !descriptors.isEmpty else {
                throw AppFontCatalogError
                    .registrationFailed
            }
            if file == files.regular {
                regularDescriptor =
                    descriptors.first
            }
            try registerFont(
                at: url
            )
        }

        guard let descriptor =
                regularDescriptor,
              let familyName =
                CTFontDescriptorCopyAttribute(
                    descriptor,
                    kCTFontFamilyNameAttribute
                ) as? String,
              !familyName.isEmpty else {
            throw AppFontCatalogError
                .registrationFailed
        }
        return familyName
    }

    private func registerFont(
        at url: URL
    ) throws {
        var unmanagedError:
            Unmanaged<CFError>?
        let registered =
            CTFontManagerRegisterFontsForURL(
                url as CFURL,
                .process,
                &unmanagedError
            )
        guard !registered else {
            return
        }
        if let error =
            unmanagedError?
            .takeRetainedValue() {
            let nsError =
                error as Error
                as NSError
            if nsError.domain
                == kCTFontManagerErrorDomain
                    as String,
               (
                   nsError.code
                    == CTFontManagerError
                    .alreadyRegistered
                    .rawValue
                    || nsError.code
                    == CTFontManagerError
                    .duplicatedName
                    .rawValue
               ) {
                return
            }
        }
        throw AppFontCatalogError
            .registrationFailed
    }

    private var manifestURL: URL {
        rootURL.appending(
            path: "manifest.json"
        )
    }

    private func localURL(
        optionKey: String,
        file: AppFontFile
    ) -> URL {
        rootURL
            .appending(
                path: optionKey,
                directoryHint:
                    .isDirectory
            )
            .appending(path: file.path)
    }

    private func createRootIfNeeded()
        throws
    {
        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories:
                true
        )
    }
}

@MainActor
final class AppFontCatalogStore:
    ObservableObject
{
    nonisolated static let preferenceKey =
        "settings.fontChoice.v1"
    nonisolated static let defaultKey =
        AppFontOption.bundledNanumKey
    nonisolated static let bundledFontName =
        "NanumSquareRoundOTFEB"
    nonisolated static let manifestURL = URL(
        string:
            "https://rivo.me/app/VisionCraft/fonts/manifest.json"
    )!

    static let shared =
        AppFontCatalogStore()

    @Published private(set) var options:
        [AppFontOption] = [
            .system,
            .bundledNanum,
        ]
    @Published private(set) var selectedKey:
        String
    @Published private(set) var
        activeRemoteFontName: String?
    @Published private(set) var
        activeRemoteKey: String?
    @Published private(set) var
        isManifestLoading = false
    @Published private(set) var
        downloadingKey: String?
    @Published private(set) var
        errorMessage: String?

    private let defaults: UserDefaults
    private let session: URLSession
    private let manifestURL: URL
    private let diskStore:
        AppFontDiskStore
    private var didPrepare = false

    init(
        defaults: UserDefaults = .standard,
        session: URLSession? = nil,
        manifestURL: URL =
            AppFontCatalogStore
            .manifestURL,
        rootURL: URL? = nil
    ) {
        self.defaults = defaults
        self.manifestURL = manifestURL
        self.session =
            session
            ?? Self.makeSession()
        let resolvedRoot =
            rootURL
            ?? Self.defaultRootURL()
        diskStore = AppFontDiskStore(
            rootURL: resolvedRoot
        )
        selectedKey =
            defaults.string(
                forKey:
                    Self.preferenceKey
            )
            ?? Self.defaultKey
    }

    var currentOption:
        AppFontOption
    {
        option(
            for: selectedKey
        ) ?? .system
    }

    func visibleOptions(
        languageCode: String
    ) -> [AppFontOption] {
        options.filter {
            $0.isVisible(
                for: languageCode
            )
        }
    }

    func effectiveOption(
        languageCode: String
    ) -> AppFontOption {
        let selected = currentOption
        return selected.isVisible(
            for: languageCode
        )
            ? selected
            : .system
    }

    func selectedLabel(
        languageCode: String
    ) -> String {
        effectiveOption(
            languageCode:
                languageCode
        ).label(
            languageCode:
                languageCode
        )
    }

    func font(
        languageCode: String
    ) -> Font? {
        let option =
            effectiveOption(
                languageCode:
                    languageCode
            )
        if option.isSystem {
            return nil
        }
        if option.isBundled {
            return .custom(
                Self.bundledFontName,
                size: 16
            )
        }
        guard activeRemoteKey
                == option.key,
              let activeRemoteFontName
        else {
            return nil
        }
        return .custom(
            activeRemoteFontName,
            size: 16
        )
    }

    func prepare() async {
        guard !didPrepare else {
            return
        }
        didPrepare = true

        if let data =
            try? await diskStore
                .loadManifest(),
           let manifest =
            try? AppFontManifestParser
                .parse(data) {
            apply(manifest)
            await activateCachedSelection()
        }
        await refreshManifest()
    }

    func refreshManifest() async {
        guard !isManifestLoading else {
            return
        }
        isManifestLoading = true
        errorMessage = nil
        defer {
            isManifestLoading = false
        }

        do {
            let (data, response) =
                try await session.data(
                    from: manifestURL
                )
            try validateHTTPResponse(
                response,
                trustedAs: .manifest
            )
            let manifest =
                try AppFontManifestParser
                .parse(data)
            try await diskStore
                .saveManifest(data)
            apply(manifest)
            await activateCachedSelection()
        } catch {
            errorMessage =
                AppLocalization.format(
                    "글꼴 목록을 불러오지 못했습니다: %@",
                    error.localizedDescription
                )
        }
    }

    func select(
        _ option: AppFontOption
    ) async -> Bool {
        guard downloadingKey == nil
        else {
            return false
        }
        errorMessage = nil

        if option.isSystem {
            persistSelection(
                option.key,
                remoteFontName: nil
            )
            return true
        }
        if option.isBundled {
            persistSelection(
                option.key,
                remoteFontName: nil
            )
            return true
        }
        guard option.files != nil
        else {
            errorMessage =
                AppFontCatalogError
                .unavailableFont
                .localizedDescription
            return false
        }

        downloadingKey = option.key
        defer {
            downloadingKey = nil
        }
        do {
            try await ensureDownloaded(
                option
            )
            let familyName =
                try await diskStore
                .registerVerifiedFonts(
                    for: option
                )
            persistSelection(
                option.key,
                remoteFontName:
                    familyName
            )
            return true
        } catch {
            errorMessage =
                AppLocalization.format(
                    "글꼴을 준비하지 못했습니다: %@",
                    error.localizedDescription
                )
            return false
        }
    }

    func resetSelection() {
        persistSelection(
            Self.defaultKey,
            remoteFontName: nil
        )
        errorMessage = nil
    }

    private func ensureDownloaded(
        _ option: AppFontOption
    ) async throws {
        guard let files = option.files
        else {
            throw AppFontCatalogError
                .unavailableFont
        }
        for file in files.uniqueFiles {
            if await diskStore
                .hasVerifiedFile(
                    optionKey:
                        option.key,
                    file: file
                ) {
                continue
            }
            let (temporaryURL, response) =
                try await session.download(
                    from: file.url
                )
            try validateHTTPResponse(
                response,
                trustedAs: .font
            )
            try await diskStore.install(
                downloadedURL:
                    temporaryURL,
                optionKey: option.key,
                file: file
            )
        }
    }

    private func activateCachedSelection()
        async
    {
        guard let option =
                option(
                    for: selectedKey
                ),
              !option.isSystem,
              !option.isBundled else {
            activeRemoteKey = nil
            activeRemoteFontName =
                nil
            return
        }
        do {
            activeRemoteFontName =
                try await diskStore
                .registerVerifiedFonts(
                    for: option
                )
            activeRemoteKey = option.key
        } catch {
            activeRemoteKey = nil
            activeRemoteFontName =
                nil
        }
    }

    private func apply(
        _ manifest: AppFontManifest
    ) {
        options =
            [
                .system,
                .bundledNanum,
            ]
            + manifest.fonts
    }

    private func option(
        for key: String
    ) -> AppFontOption? {
        options.first {
            $0.key == key
        }
    }

    private func persistSelection(
        _ key: String,
        remoteFontName: String?
    ) {
        selectedKey = key
        defaults.set(
            key,
            forKey:
                Self.preferenceKey
        )
        activeRemoteKey =
            remoteFontName == nil
            ? nil
            : key
        activeRemoteFontName =
            remoteFontName
    }

    private enum TrustedResponseKind {
        case manifest
        case font
    }

    private func validateHTTPResponse(
        _ response: URLResponse,
        trustedAs kind:
            TrustedResponseKind
    ) throws {
        guard let httpResponse =
                response
                as? HTTPURLResponse,
              (200 ... 299).contains(
                  httpResponse.statusCode
              ),
              let finalURL =
                httpResponse.url else {
            throw AppFontCatalogError
                .invalidHTTPResponse
        }
        let isTrusted =
            switch kind {
            case .manifest:
                finalURL
                    == manifestURL
                    && AppFontManifestParser
                    .isTrustedFontURL(
                        finalURL
                    )
            case .font:
                AppFontManifestParser
                    .isTrustedFontURL(
                        finalURL
                    )
            }
        guard isTrusted else {
            throw AppFontCatalogError
                .invalidHTTPResponse
        }
    }

    private static func makeSession()
        -> URLSession
    {
        let configuration =
            URLSessionConfiguration
            .ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy =
            .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest =
            20
        configuration.timeoutIntervalForResource =
            90
        return URLSession(
            configuration: configuration
        )
    }

    private static func defaultRootURL()
        -> URL
    {
        let baseURL =
            FileManager.default.urls(
                for:
                    .applicationSupportDirectory,
                in: .userDomainMask
            ).first
            ?? FileManager.default
                .temporaryDirectory
        return baseURL
            .appending(
                path: "VisionCraft",
                directoryHint:
                    .isDirectory
            )
            .appending(
                path: "AppFonts",
                directoryHint:
                    .isDirectory
            )
    }
}
