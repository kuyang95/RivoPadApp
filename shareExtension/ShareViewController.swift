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
        "group.com.rivo.shortcuts.example"
    private static let maximumPayloadBytes =
        100 * 1_024 * 1_024

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
        receiveFirstSupportedItem()
    }

    private func receiveFirstSupportedItem() {
        let providers = extensionContext?
            .inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }
            ?? []
        guard let provider = providers.first(
            where: Self.isSupported
        ) else {
            finish(
                with:
                    shareLocalized(
                        "사진, PDF 또는 텍스트만 공유할 수 있습니다."
                    )
            )
            return
        }

        if provider.hasItemConformingToTypeIdentifier(
            UTType.image.identifier
        ) {
            loadFile(
                from: provider,
                type: .image,
                kind: .image
            )
        } else if provider
            .hasItemConformingToTypeIdentifier(
                UTType.pdf.identifier
            ) {
            loadFile(
                from: provider,
                type: .pdf,
                kind: .file
            )
        } else {
            loadText(from: provider)
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
    }

    private func loadText(
        from provider: NSItemProvider
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
                self.finish(
                    with:
                        shareLocalized(
                            "텍스트를 읽지 못했습니다: "
                        )
                        + error.localizedDescription
                )
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
                self.finish(
                    with:
                        shareLocalized(
                            "공유된 텍스트가 비어 있습니다."
                        )
                )
                return
            }
            do {
                try self.commitText(text)
                self.finishSuccessfully()
            } catch {
                self.finish(
                    with:
                        shareLocalized(
                            "공유 항목을 저장하지 못했습니다: "
                        )
                        + error.localizedDescription
                )
            }
        }
    }

    private func loadFile(
        from provider: NSItemProvider,
        type: UTType,
        kind: ShareInboxKind
    ) {
        provider.loadFileRepresentation(
            forTypeIdentifier: type.identifier
        ) { [weak self] sourceURL, error in
            guard let self else {
                return
            }
            if let error {
                self.finish(
                    with:
                        shareLocalized(
                            "공유 파일을 읽지 못했습니다: "
                        )
                        + error.localizedDescription
                )
                return
            }
            guard let sourceURL else {
                self.finish(
                    with:
                        shareLocalized(
                            "공유 파일을 찾지 못했습니다."
                        )
                )
                return
            }
            do {
                try self.commitFile(
                    sourceURL,
                    kind: kind,
                    typeIdentifier: type.identifier
                )
                self.finishSuccessfully()
            } catch {
                self.finish(
                    with:
                        shareLocalized(
                            "공유 파일을 저장하지 못했습니다: "
                        )
                        + error.localizedDescription
                )
            }
        }
    }

    private func commitText(_ text: String) throws {
        let trimmed = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let manifest = ShareInboxManifest(
            id: UUID(),
            schemaVersion: 1,
            createdAt: Date(),
            kind: .text,
            text: String(
                trimmed.prefix(200_000)
            ),
            payloadFilename: nil,
            originalFilename: nil,
            typeIdentifier:
                UTType.plainText.identifier
        )
        try commit(manifest)
    }

    private func commitFile(
        _ sourceURL: URL,
        kind: ShareInboxKind,
        typeIdentifier: String
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
            throw CocoaError(.fileWriteOutOfSpace)
        }
        let id = UUID()
        let filename = Self.safeFilename(
            sourceURL.lastPathComponent,
            fallbackExtension:
                kind == .image ? "jpg" : "pdf"
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
                createdAt: Date(),
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

    private func finishSuccessfully() {
        DispatchQueue.main.async {
            self.statusLabel.text =
                shareLocalized(
                    "VisionCraft 수신함에 저장했습니다."
                )
            self.openButton.isHidden = false
            UIAccessibility.post(
                notification: .announcement,
                argument:
                    shareLocalized(
                        "공유 항목을 저장했습니다. VisionCraft 열기 버튼을 누르세요."
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
