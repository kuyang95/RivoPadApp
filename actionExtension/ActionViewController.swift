import UIKit
import UniformTypeIdentifiers

private enum ActionInboxKind: String, Codable {
    case text
}

private struct ActionInboxManifest: Codable {
    let id: UUID
    let schemaVersion: Int
    let createdAt: Date
    let kind: ActionInboxKind
    let text: String?
    let payloadFilename: String?
    let originalFilename: String?
    let typeIdentifier: String?
}

private enum ActionExtensionError: LocalizedError {
    case emptyText

    var errorDescription: String? {
        "선택한 텍스트가 비어 있습니다."
    }
}

final class ActionViewController: UIViewController {
    private static let appGroupIdentifier =
        "group.com.rivo.shortcuts.example"
    private static let maximumTextCharacters =
        200_000

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.text = "선택한 텍스트를 준비하는 중입니다."
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
        configuration.title = "VisionCraft에 질문"
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

    private lazy var laterButton: UIButton = {
        var configuration =
            UIButton.Configuration.plain()
        configuration.title = "나중에 열기"
        let button = UIButton(
            configuration: configuration
        )
        button.addTarget(
            self,
            action: #selector(completeForLater),
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
        view.addSubview(laterButton)
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
                constant: -32
            ),
            openButton.topAnchor.constraint(
                equalTo: statusLabel.bottomAnchor,
                constant: 24
            ),
            openButton.centerXAnchor.constraint(
                equalTo: view.centerXAnchor
            ),
            laterButton.topAnchor.constraint(
                equalTo: openButton.bottomAnchor,
                constant: 8
            ),
            laterButton.centerXAnchor.constraint(
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
        receiveSelectedText()
    }

    private func receiveSelectedText() {
        let providers = extensionContext?
            .inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }
            ?? []
        guard let selection = providers
            .compactMap(Self.textSelection)
            .first else {
            finish(
                with:
                    "선택한 텍스트를 이 동작에 전달하지 못했습니다."
            )
            return
        }
        selection.provider.loadItem(
            forTypeIdentifier:
                selection.typeIdentifier,
            options: nil
        ) { [weak self] value, error in
            guard let self else {
                return
            }
            if let error {
                self.finish(
                    with:
                        "선택한 텍스트를 읽지 못했습니다: "
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
            case let data as Data:
                text = String(data: data, encoding: .utf8)
            default:
                text = nil
            }
            guard let text else {
                self.finish(
                    with:
                        "선택한 텍스트 형식을 읽을 수 없습니다."
                )
                return
            }
            do {
                try self.commitText(text)
                self.finishSuccessfully()
            } catch {
                self.finish(
                    with:
                        "선택한 텍스트를 저장하지 못했습니다: "
                        + error.localizedDescription
                )
            }
        }
    }

    private nonisolated static func textSelection(
        from provider: NSItemProvider
    ) -> (
        provider: NSItemProvider,
        typeIdentifier: String
    )? {
        guard let identifier = provider
            .registeredTypeIdentifiers
            .first(where: { identifier in
                UTType(identifier)?
                    .conforms(to: .text) == true
            }) else {
            return nil
        }
        return (provider, identifier)
    }

    private func commitText(_ text: String) throws {
        let trimmed = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else {
            throw ActionExtensionError.emptyText
        }
        let manifest = ActionInboxManifest(
            id: UUID(),
            schemaVersion: 1,
            createdAt: Date(),
            kind: .text,
            text: String(
                trimmed.prefix(
                    Self.maximumTextCharacters
                )
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
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(manifest)
            try data.write(
                to: directory.appendingPathComponent(
                    "manifest.json"
                ),
                options: .atomic
            )
        } catch {
            try? FileManager.default.removeItem(
                at: directory
            )
            throw error
        }
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

    private func finishSuccessfully() {
        DispatchQueue.main.async {
            self.statusLabel.text =
                "선택한 텍스트를 로컬 수신함에 저장했습니다."
            self.openButton.isHidden = false
            self.laterButton.isHidden = false
            UIAccessibility.post(
                notification: .announcement,
                argument:
                    "선택한 텍스트를 저장했습니다. VisionCraft에 질문 버튼을 누르거나 나중에 열 수 있습니다."
            )
        }
    }

    private func finish(with message: String) {
        DispatchQueue.main.async {
            self.statusLabel.text = message
            self.openButton.isHidden = true
            self.laterButton.isHidden = true
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
                self.completeRequest()
            } else {
                self.finish(
                    with:
                        "VisionCraft를 직접 열면 선택한 텍스트가 자동으로 표시됩니다."
                )
                self.laterButton.isHidden = false
            }
        }
    }

    @objc private func completeForLater() {
        completeRequest()
    }

    private func completeRequest() {
        extensionContext?.completeRequest(
            returningItems: nil
        )
    }
}
