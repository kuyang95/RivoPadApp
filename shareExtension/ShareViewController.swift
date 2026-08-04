import UIKit
import UniformTypeIdentifiers

private func shareLocalized(
    _ key: String
) -> String {
    NSLocalizedString(
        key,
        comment: ""
    )
}

private enum ShareInboxKind: String, Codable {
    case text
    case image
    case file
}

private struct ShareInboxManifest: Codable {
    let id: UUID
    let schemaVersion: Int
    let createdAt: Date
    let kind: ShareInboxKind
    let text: String?
    let payloadFilename: String?
    let originalFilename: String?
    let typeIdentifier: String?
}

final class ShareViewController: UIViewController {
    private static let appGroupIdentifier =
        "group.net.rivo.visioncraft"
    private static let maximumPayloadBytes =
        100 * 1_024 * 1_024
    private static let maximumBatchPayloadBytes =
        250 * 1_024 * 1_024
    private static let maximumBatchItems = 20
    private static let supportedDocumentExtensions:
        Set<String> = [
            "epub",
            "hwp",
            "hwpx",
            "pdf",
            "txt",
            "text",
            "xls",
            "xlsx",
        ]

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.text = shareLocalized(
            "공유 항목을 준비하는 중입니다."
        )
        label.font = .preferredFont(
            forTextStyle: .headline
        )
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints =
            false
        return label
    }()

    private lazy var openButton: UIButton = {
        var configuration =
            UIButton.Configuration.filled()
        configuration.title =
            shareLocalized(
                "VisionCraft 열기"
            )
        configuration.cornerStyle = .capsule
        let button = UIButton(
            configuration: configuration
        )
        button.addTarget(
            self,
            action: #selector(openContainingApp),
            for: .touchUpInside
        )
        button.isHidden = true
        button.translatesAutoresizingMaskIntoConstraints =
            false
        return button
    }()

    private var didStart = false
    private var committedPayloadBytes = 0
    private var batchCreatedAt = Date()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.addSubview(statusLabel)
        view.addSubview(openButton)
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: 28
            ),
            statusLabel.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -28
            ),
            statusLabel.centerYAnchor.constraint(
                equalTo: view.centerYAnchor,
                constant: -24
            ),
            openButton.topAnchor.constraint(
                equalTo: statusLabel.bottomAnchor,
                constant: 24
            ),
            openButton.centerXAnchor.constraint(
                equalTo: view.centerXAnchor
            )
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didStart else {
            return
        }
        didStart = true
        receiveSupportedItems()
    }

    private func receiveSupportedItems() {
        let providers = extensionContext?
            .inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }
            ?? []
        let supported = providers.filter(
            Self.isSupported
        )
        guard !supported.isEmpty else {
            finish(
                with:
                    shareLocalized(
                        "사진, 지원 문서, 텍스트 또는 URL만 공유할 수 있습니다."
                    )
            )
            return
        }
        guard supported.count
                <= Self.maximumBatchItems else {
            finish(
                with:
                    String(
                        format:
                            shareLocalized(
                                "한 번에 공유 항목은 최대 %lld개까지 저장할 수 있습니다."
                            ),
                        Self.maximumBatchItems
                    )
            )
            return
        }
        committedPayloadBytes = 0
        batchCreatedAt = Date()
        let unsupportedCount =
            providers.count
            - supported.count
        process(
            supported,
            at: 0,
            savedCount: 0,
            errors: Array(
                repeating:
                    shareLocalized(
                        "지원하지 않는 공유 항목입니다."
                    ),
                count:
                    max(
                        unsupportedCount,
                        0
                    )
            )
        )
    }

    private func process(
        _ providers: [NSItemProvider],
        at index: Int,
        savedCount: Int,
        errors: [String]
    ) {
        guard index < providers.count
        else {
            finishBatch(
                savedCount: savedCount,
                failedCount: errors.count,
                firstError: errors.first
            )
            return
        }
        let createdAt = batchCreatedAt
            .addingTimeInterval(
                Double(index) / 1_000
            )
        store(
            providers[index],
            createdAt: createdAt
        ) { [weak self] result in
            guard let self else {
                return
            }
            switch result {
            case .success:
                self.process(
                    providers,
                    at: index + 1,
                    savedCount:
                        savedCount + 1,
                    errors: errors
                )
            case .failure(let error):
                self.process(
                    providers,
                    at: index + 1,
                    savedCount:
                        savedCount,
                    errors:
                        errors
                        + [
                            error
                                .localizedDescription
                        ]
                )
            }
        }
    }

    private func store(
        _ provider: NSItemProvider,
        createdAt: Date,
        completion:
            @escaping (Result<Void, Error>)
                -> Void
    ) {
        if provider.hasItemConformingToTypeIdentifier(
            UTType.image.identifier
        ) {
            loadFile(
                from: provider,
                type: .image,
                kind: .image,
                createdAt: createdAt,
                completion: completion
            )
        } else if provider
            .hasItemConformingToTypeIdentifier(
                UTType.pdf.identifier
            ) {
            loadFile(
                from: provider,
                type: .pdf,
                kind: .file,
                createdAt: createdAt,
                completion: completion
            )
        } else if provider
            .hasItemConformingToTypeIdentifier(
                UTType.plainText.identifier
            )
            || provider
                .hasItemConformingToTypeIdentifier(
                    UTType.url.identifier
                ) {
            loadText(
                from: provider,
                createdAt: createdAt,
                completion: completion
            )
        } else if let typeIdentifier =
                    Self.fileTypeIdentifier(
                        for: provider
                    ) {
            loadFile(
                from: provider,
                typeIdentifier:
                    typeIdentifier,
                kind: .file,
                createdAt: createdAt,
                completion: completion
            )
        } else {
            completion(
                .failure(
                    CocoaError(
                        .fileReadUnsupportedScheme,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                shareLocalized(
                                    "지원하지 않는 공유 항목입니다."
                                )
                        ]
                    )
                )
            )
        }
    }

    private nonisolated static func isSupported(
        _ provider: NSItemProvider
    ) -> Bool {
        provider.hasItemConformingToTypeIdentifier(
            UTType.image.identifier
        )
            || provider
                .hasItemConformingToTypeIdentifier(
                    UTType.pdf.identifier
                )
            || provider
                .hasItemConformingToTypeIdentifier(
                    UTType.plainText.identifier
                )
            || provider
                .hasItemConformingToTypeIdentifier(
                    UTType.url.identifier
                )
            || fileTypeIdentifier(
                for: provider
            ) != nil
    }

    private nonisolated static func fileTypeIdentifier(
        for provider: NSItemProvider
    ) -> String? {
        provider.registeredTypeIdentifiers
            .first { identifier in
                guard let type =
                        UTType(identifier)
                else {
                    return false
                }
                return type.conforms(
                    to: .data
                )
                    && !type.conforms(
                        to: .image
                    )
                    && !type.conforms(
                        to: .plainText
                    )
            }
    }

    private func loadText(
        from provider: NSItemProvider,
        createdAt: Date,
        completion:
            @escaping (Result<Void, Error>)
                -> Void
    ) {
        let identifier =
            provider
                .hasItemConformingToTypeIdentifier(
                    UTType.plainText.identifier
                )
            ? UTType.plainText.identifier
            : UTType.url.identifier
        provider.loadItem(
            forTypeIdentifier: identifier,
            options: nil
        ) { [weak self] value, error in
            guard let self else {
                return
            }
            if let error {
                completion(.failure(error))
                return
            }
            let text: String?
            switch value {
            case let string as String:
                text = string
            case let attributed as NSAttributedString:
                text = attributed.string
            case let url as URL:
                text = url.absoluteString
            default:
                text = nil
            }
            guard let text,
                  !text.trimmingCharacters(
                      in: .whitespacesAndNewlines
                  ).isEmpty else {
                completion(
                    .failure(
                        CocoaError(
                            .fileReadCorruptFile,
                            userInfo: [
                                NSLocalizedDescriptionKey:
                                    shareLocalized(
                                        "공유된 텍스트가 비어 있습니다."
                                    )
                            ]
                        )
                    )
                )
                return
            }
            do {
                try self.commitText(
                    text,
                    createdAt: createdAt
                )
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func loadFile(
        from provider: NSItemProvider,
        type: UTType,
        kind: ShareInboxKind,
        createdAt: Date,
        completion:
            @escaping (Result<Void, Error>)
                -> Void
    ) {
        loadFile(
            from: provider,
            typeIdentifier: type.identifier,
            kind: kind,
            createdAt: createdAt,
            completion: completion
        )
    }

    private func loadFile(
        from provider: NSItemProvider,
        typeIdentifier: String,
        kind: ShareInboxKind,
        createdAt: Date,
        completion:
            @escaping (Result<Void, Error>)
                -> Void
    ) {
        provider.loadFileRepresentation(
            forTypeIdentifier: typeIdentifier
        ) { [weak self] sourceURL, error in
            guard let self else {
                return
            }
            if let error {
                completion(.failure(error))
                return
            }
            guard let sourceURL else {
                completion(
                    .failure(
                        CocoaError(
                            .fileNoSuchFile,
                            userInfo: [
                                NSLocalizedDescriptionKey:
                                    shareLocalized(
                                        "공유 파일을 찾지 못했습니다."
                                    )
                            ]
                        )
                    )
                )
                return
            }
            do {
                try self.commitFile(
                    sourceURL,
                    kind: kind,
                    typeIdentifier:
                        typeIdentifier,
                    originalFilename:
                        provider.suggestedName,
                    createdAt: createdAt
                )
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func commitText(
        _ text: String,
        createdAt: Date
    ) throws {
        let trimmed = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let manifest = ShareInboxManifest(
            id: UUID(),
            schemaVersion: 1,
            createdAt: createdAt,
            kind: .text,
            text: String(
                trimmed.prefix(200_000)
            ),
            payloadFilename: nil,
            originalFilename: nil,
            typeIdentifier:
                UTType.plainText.identifier
        )
        let directory = try inboxRoot()
            .appendingPathComponent(
                manifest.id.uuidString,
                isDirectory: true
            )
        do {
            try commit(
                manifest,
                directory: directory
            )
        } catch {
            try? FileManager.default
                .removeItem(at: directory)
            throw error
        }
    }

    private func commitFile(
        _ sourceURL: URL,
        kind: ShareInboxKind,
        typeIdentifier: String,
        originalFilename: String?,
        createdAt: Date
    ) throws {
        let values = try sourceURL.resourceValues(
            forKeys: [
                .isRegularFileKey,
                .fileSizeKey
            ]
        )
        guard values.isRegularFile == true,
              let fileSize = values.fileSize else {
            throw CocoaError(.fileReadUnknown)
        }
        guard fileSize
            <= Self.maximumPayloadBytes else {
            throw CocoaError(
                .fileWriteOutOfSpace,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        shareLocalized(
                            "공유 파일 하나는 최대 100MB까지 저장할 수 있습니다."
                        )
                ]
            )
        }
        guard committedPayloadBytes
                + fileSize
                <= Self
                    .maximumBatchPayloadBytes
        else {
            throw CocoaError(
                .fileWriteOutOfSpace,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        shareLocalized(
                            "공유 파일 합계가 250MB 제한을 초과했습니다."
                        )
                ]
            )
        }
        let id = UUID()
        let trimmedOriginalFilename =
            originalFilename?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
        var sourceFilename =
            trimmedOriginalFilename
                .flatMap {
                    $0.isEmpty ? nil : $0
                }
            ?? sourceURL.lastPathComponent
        if URL(
            fileURLWithPath: sourceFilename
        ).pathExtension.isEmpty,
        !sourceURL.pathExtension.isEmpty {
            sourceFilename +=
                "." + sourceURL.pathExtension
        }
        let pathExtension = URL(
            fileURLWithPath: sourceFilename
        ).pathExtension.lowercased()
        guard kind != .file
                || Self
                    .supportedDocumentExtensions
                    .contains(pathExtension)
        else {
            throw CocoaError(
                .fileReadUnsupportedScheme,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        shareLocalized(
                            "이 문서 형식은 아직 지원하지 않습니다."
                        )
                ]
            )
        }
        let filename = Self.safeFilename(
            sourceFilename,
            fallbackExtension:
                kind == .image
                ? "jpg"
                : (
                    UTType(typeIdentifier)?
                        .preferredFilenameExtension
                    ?? "bin"
                )
        )
        let directory = try inboxRoot()
            .appendingPathComponent(
                id.uuidString,
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        do {
            try FileManager.default.copyItem(
                at: sourceURL,
                to: directory
                    .appendingPathComponent(filename)
            )
            let manifest = ShareInboxManifest(
                id: id,
                schemaVersion: 1,
                createdAt: createdAt,
                kind: kind,
                text: nil,
                payloadFilename: filename,
                originalFilename: filename,
                typeIdentifier: typeIdentifier
            )
            try commit(
                manifest,
                directory: directory
            )
            committedPayloadBytes +=
                fileSize
        } catch {
            try? FileManager.default.removeItem(
                at: directory
            )
            throw error
        }
    }

    private func commit(
        _ manifest: ShareInboxManifest,
        directory explicitDirectory: URL? = nil
    ) throws {
        let directory = try explicitDirectory
            ?? inboxRoot().appendingPathComponent(
                manifest.id.uuidString,
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(
            to: directory
                .appendingPathComponent(
                    "manifest.json"
                ),
            options: .atomic
        )
    }

    private func inboxRoot() throws -> URL {
        guard let group = FileManager.default
            .containerURL(
                forSecurityApplicationGroupIdentifier:
                    Self.appGroupIdentifier
            ) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let root = group.appendingPathComponent(
            "ShareInbox",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        return root
    }

    private static func safeFilename(
        _ filename: String,
        fallbackExtension: String
    ) -> String {
        let source = URL(
            fileURLWithPath: filename
        ).lastPathComponent
        let sanitized = source
            .components(
                separatedBy:
                    CharacterSet.alphanumerics
                    .union(
                        CharacterSet(
                            charactersIn:
                                "._-() "
                        )
                    )
                    .inverted
            )
            .joined(separator: "_")
        let trimmed = String(
            sanitized.prefix(120)
        )
        if trimmed.isEmpty
            || trimmed == "."
            || trimmed == ".." {
            return "shared-item."
                + fallbackExtension
        }
        return trimmed
    }

    private func finishBatch(
        savedCount: Int,
        failedCount: Int,
        firstError: String?
    ) {
        guard savedCount > 0 else {
            let detail = firstError.map {
                ": " + $0
            } ?? ""
            finish(
                with:
                    shareLocalized(
                        "공유 항목을 저장하지 못했습니다"
                    )
                    + detail
            )
            return
        }
        finishSuccessfully(
            savedCount: savedCount,
            failedCount: failedCount
        )
    }

    private func finishSuccessfully(
        savedCount: Int,
        failedCount: Int
    ) {
        DispatchQueue.main.async {
            let message: String
            if savedCount == 1,
               failedCount == 0 {
                message = shareLocalized(
                    "VisionCraft 수신함에 저장했습니다."
                )
            } else if failedCount == 0 {
                message = String(
                    format:
                        shareLocalized(
                            "공유 항목 %lld개를 VisionCraft 수신함에 저장했습니다."
                        ),
                    savedCount
                )
            } else {
                message = String(
                    format:
                        shareLocalized(
                            "공유 항목 %1$lld개를 저장했고 %2$lld개는 저장하지 못했습니다."
                        ),
                    savedCount,
                    failedCount
                )
            }
            self.statusLabel.text = message
            self.openButton.isHidden = false
            UIAccessibility.post(
                notification: .announcement,
                argument:
                    message
                    + " "
                    + shareLocalized(
                        "VisionCraft 열기 버튼을 누르세요."
                    )
            )
        }
    }

    private func finish(with message: String) {
        DispatchQueue.main.async {
            self.statusLabel.text = message
            self.openButton.isHidden = true
            UIAccessibility.post(
                notification: .announcement,
                argument: message
            )
        }
    }

    @objc private func openContainingApp() {
        guard let url = URL(
            string: "rivopad://share-inbox"
        ) else {
            return
        }
        extensionContext?.open(url) {
            [weak self] didOpen in
            guard let self else {
                return
            }
            if didOpen {
                self.extensionContext?
                    .completeRequest(
                        returningItems: nil
                    )
            } else {
                self.finish(
                    with:
                        shareLocalized(
                            "VisionCraft를 직접 열면 공유 항목이 자동으로 표시됩니다."
                        )
                )
            }
        }
    }
}
