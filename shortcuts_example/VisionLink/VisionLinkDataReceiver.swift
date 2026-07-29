import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated struct VisionLinkTransferProgress:
    Equatable,
    Sendable
{
    let transferID: String
    let kind: String
    let fileName: String
    let receivedBytes: Int64
    let totalBytes: Int64

    var fractionCompleted: Double {
        guard totalBytes > 0 else {
            return 0
        }
        return min(
            max(
                Double(receivedBytes)
                    / Double(totalBytes),
                0
            ),
            1
        )
    }
}

nonisolated struct VisionLinkReceivedFile:
    Identifiable,
    Equatable,
    Sendable
{
    var id: String {
        transferID
    }

    let transferID: String
    let kind: String
    let fileName: String
    let size: Int64
    let url: URL
    let mimeType: String
}

nonisolated enum VisionLinkDataEvent:
    Equatable,
    Sendable
{
    case cameraShareChanged(Bool)
    case clipboardReceived(String)
    case transferStarted(VisionLinkTransferProgress)
    case transferProgress(VisionLinkTransferProgress)
    case fileReceived(VisionLinkReceivedFile)
    case failed(String)
}

nonisolated enum VisionLinkDataInput:
    Sendable
{
    case opened
    case control(Data)
    case binary(Data)
    case closed
}

nonisolated enum VisionLinkDataAction:
    Equatable,
    Sendable
{
    case sendControl(Data)
    case event(VisionLinkDataEvent)
}

actor VisionLinkDataReceiver {
    static let maximumFileSize: Int64 =
        1_073_741_824
    static let maximumClipboardSize =
        128 * 1_024

    private static let blockedGeneralExtensions:
        Set<String> = [
            "apk",
            "apks",
            "apkm",
            "xapk",
            "aab",
            "dex",
        ]
    private static let imageMimeTypes: [String: String] = [
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "png": "image/png",
        "webp": "image/webp",
        "gif": "image/gif",
        "bmp": "image/bmp",
        "heic": "image/heic",
        "heif": "image/heif",
        "avif": "image/avif",
        "dng": "image/x-adobe-dng",
    ]

    private let destinationDirectory: URL
    private let partialDirectory: URL
    private var activeTransfer: IncomingTransfer?
    private var lastProgressPercent = -1

    init(
        destinationDirectory: URL,
        partialDirectory: URL
    ) {
        self.destinationDirectory =
            destinationDirectory
        self.partialDirectory = partialDirectory
    }

    func receive(
        _ input: VisionLinkDataInput
    ) -> [VisionLinkDataAction] {
        switch input {
        case .opened:
            return []
        case .control(let data):
            return handleControl(data)
        case .binary(let data):
            return handleBinary(data)
        case .closed:
            abortActiveTransfer()
            return []
        }
    }

    func close() {
        abortActiveTransfer()
    }

    private func handleControl(
        _ data: Data
    ) -> [VisionLinkDataAction] {
        guard let object = try? JSONSerialization
                .jsonObject(with: data),
              let message = object as? [String: Any],
              let type = message["type"] as? String else {
            return [
                .event(
                    .failed(
                        "VisionLink 데이터 제어 메시지를 읽지 못했습니다."
                    )
                ),
            ]
        }

        switch type {
        case "file-start":
            return startTransfer(message)
        case "file-end":
            return finishTransfer(message)
        case "file-cancel":
            return cancelTransfer(message)
        case "clipboard-text":
            return receiveClipboard(message)
        case "camera-share-state":
            guard let active =
                    message["active"] as? Bool else {
                return []
            }
            return [
                .event(
                    .cameraShareChanged(active)
                ),
            ]
        case "data-ping":
            return [
                .sendControl(
                    Self.controlData(
                        [
                            "type": "data-pong",
                            "sentAt":
                                message["sentAt"]
                                as? String ?? "",
                        ]
                    )
                ),
            ]
        case "data-pong":
            return []
        case "feature-request":
            return unsupportedFeature(message)
        case "chat-context-attachment":
            return unsupportedChatAttachment(message)
        case "live-reading-start":
            return unsupportedLiveReading(message)
        case "live-reading-stop":
            return []
        default:
            return []
        }
    }

    private func startTransfer(
        _ message: [String: Any]
    ) -> [VisionLinkDataAction] {
        abortActiveTransfer()

        guard let transferID =
                Self.nonemptyString(
                    message["transferId"]
                ) else {
            return [
                .event(
                    .failed("파일 전송 ID가 비어 있습니다.")
                ),
            ]
        }
        guard let size = Self.int64(
            message["size"]
        ),
              size >= 0,
              size <= Self.maximumFileSize else {
            return transferError(
                "파일 크기가 올바르지 않습니다.",
                transferID: transferID
            )
        }

        let purpose = message["purpose"] as? String
        if purpose == "visioncraft-feature"
            || purpose
                == "visioncraft-chat-attachment" {
            return transferError(
                "이 VisionCraft 원격 기능은 아직 지원되지 않습니다.",
                transferID: transferID
            )
        }

        let fileName = Self.sanitizeFileName(
            message["name"] as? String
        )
        let kind = (
            message["kind"] as? String
        ) == "image" ? "image" : "file"
        guard let mimeType = Self.mimeType(
            for: fileName,
            kind: kind
        ) else {
            return transferError(
                "지원하지 않는 파일 형식입니다.",
                transferID: transferID
            )
        }

        var createdPartialURL: URL?
        do {
            try FileManager.default.createDirectory(
                at: destinationDirectory,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: partialDirectory,
                withIntermediateDirectories: true
            )
            let partialURL = partialDirectory
                .appendingPathComponent(
                    UUID().uuidString
                        + ".visionlink-part",
                    isDirectory: false
                )
            createdPartialURL = partialURL
            guard FileManager.default.createFile(
                atPath: partialURL.path,
                contents: nil
            ) else {
                throw VisionLinkDataReceiverError
                    .cannotCreateFile
            }
            let handle = try FileHandle(
                forWritingTo: partialURL
            )
            activeTransfer = IncomingTransfer(
                transferID: transferID,
                fileName: fileName,
                kind: kind,
                expectedSize: size,
                partialURL: partialURL,
                mimeType: mimeType,
                fileHandle: handle
            )
            lastProgressPercent = -1
        } catch {
            if let createdPartialURL {
                try? FileManager.default.removeItem(
                    at: createdPartialURL
                )
            }
            return transferError(
                "파일 저장 준비에 실패했습니다: "
                    + error.localizedDescription,
                transferID: transferID
            )
        }

        let progress = VisionLinkTransferProgress(
            transferID: transferID,
            kind: kind,
            fileName: fileName,
            receivedBytes: 0,
            totalBytes: size
        )
        return [
            .sendControl(
                Self.controlData(
                    [
                        "type": "file-accepted",
                        "transferId": transferID,
                    ]
                )
            ),
            .event(.transferStarted(progress)),
        ]
    }

    private func handleBinary(
        _ data: Data
    ) -> [VisionLinkDataAction] {
        guard var transfer = activeTransfer else {
            return []
        }
        let chunkSize = Int64(data.count)
        let remaining =
            transfer.expectedSize
            - transfer.receivedBytes
        guard remaining >= 0,
              chunkSize <= remaining else {
            let transferID = transfer.transferID
            abort(transfer)
            activeTransfer = nil
            return transferError(
                "선언된 파일 크기를 초과한 데이터가 수신되었습니다.",
                transferID: transferID
            )
        }

        do {
            try transfer.fileHandle.write(
                contentsOf: data
            )
            transfer.hasher.update(data: data)
            transfer.receivedBytes += chunkSize
            activeTransfer = transfer
        } catch {
            let transferID = transfer.transferID
            abort(transfer)
            activeTransfer = nil
            return transferError(
                "파일 쓰기에 실패했습니다: "
                    + error.localizedDescription,
                transferID: transferID
            )
        }

        let percent: Int
        if transfer.expectedSize <= 0 {
            percent = 0
        } else {
            percent = min(
                max(
                    Int(
                        (
                            Double(
                                transfer.receivedBytes
                            )
                            * 100
                            / Double(
                                transfer.expectedSize
                            )
                        ).rounded()
                    ),
                    0
                ),
                100
            )
        }
        guard percent != lastProgressPercent,
              percent == 100
                || percent.isMultiple(of: 5) else {
            return []
        }
        lastProgressPercent = percent
        return [
            .event(
                .transferProgress(
                    Self.progress(for: transfer)
                )
            ),
        ]
    }

    private func finishTransfer(
        _ message: [String: Any]
    ) -> [VisionLinkDataAction] {
        guard let transfer = activeTransfer else {
            return [
                .event(
                    .failed(
                        "완료할 파일 전송이 없습니다."
                    )
                ),
            ]
        }
        guard let announcedID =
                Self.nonemptyString(
                    message["transferId"]
                ),
              announcedID == transfer.transferID else {
            return transferError(
                "파일 전송 ID가 일치하지 않습니다.",
                transferID: Self.nonemptyString(
                    message["transferId"]
                )
            )
        }
        guard let announcedSize = Self.int64(
            message["size"]
        ),
              announcedSize
                == transfer.expectedSize,
              let announcedHash =
                message["sha256"] as? String,
              Self.isSHA256(
                announcedHash.lowercased()
              ) else {
            let transferID = transfer.transferID
            abort(transfer)
            activeTransfer = nil
            return transferError(
                "파일 검증 정보가 올바르지 않습니다.",
                transferID: transferID
            )
        }

        do {
            try transfer.fileHandle.synchronize()
            try transfer.fileHandle.close()
        } catch {
            let transferID = transfer.transferID
            abort(transfer)
            activeTransfer = nil
            return transferError(
                "파일 저장 완료 처리에 실패했습니다: "
                    + error.localizedDescription,
                transferID: transferID
            )
        }
        activeTransfer = nil

        guard transfer.receivedBytes
                == transfer.expectedSize else {
            abort(transfer)
            return transferError(
                "파일 크기가 다릅니다: "
                    + "\(transfer.receivedBytes)/"
                    + "\(transfer.expectedSize) bytes",
                transferID: transfer.transferID
            )
        }

        let receivedHash = transfer.hasher
            .finalize()
            .map {
                String(
                    format: "%02x",
                    $0
                )
            }
            .joined()
        guard receivedHash
                == announcedHash.lowercased() else {
            abort(transfer)
            return transferError(
                "파일 SHA-256 검증에 실패했습니다.",
                transferID: transfer.transferID
            )
        }
        guard transfer.kind != "image"
                || Self.containsDecodableImage(
                    at: transfer.partialURL
                ) else {
            abort(transfer)
            return transferError(
                "수신한 이미지 형식이 올바르지 않습니다.",
                transferID: transfer.transferID
            )
        }

        let finalURL = uniqueDestinationURL(
            fileName: transfer.fileName
        )
        do {
            try FileManager.default.moveItem(
                at: transfer.partialURL,
                to: finalURL
            )
        } catch {
            abort(transfer)
            return transferError(
                "파일 저장 완료 처리에 실패했습니다: "
                    + error.localizedDescription,
                transferID: transfer.transferID
            )
        }

        let receivedFile = VisionLinkReceivedFile(
            transferID: transfer.transferID,
            kind: transfer.kind,
            fileName: finalURL.lastPathComponent,
            size: transfer.receivedBytes,
            url: finalURL,
            mimeType: transfer.mimeType
        )
        return [
            .sendControl(
                Self.controlData(
                    [
                        "type": "file-complete",
                        "transferId":
                            transfer.transferID,
                        "size":
                            transfer.receivedBytes,
                        "sha256": receivedHash,
                    ]
                )
            ),
            .event(.fileReceived(receivedFile)),
        ]
    }

    private func cancelTransfer(
        _ message: [String: Any]
    ) -> [VisionLinkDataAction] {
        guard let transfer = activeTransfer,
              message["transferId"] as? String
                == transfer.transferID else {
            return []
        }
        abort(transfer)
        activeTransfer = nil
        lastProgressPercent = -1
        return [
            .event(
                .failed("파일 전송이 취소되었습니다.")
            ),
        ]
    }

    private func receiveClipboard(
        _ message: [String: Any]
    ) -> [VisionLinkDataAction] {
        guard let transferID =
                Self.nonemptyString(
                    message["transferId"]
                ) else {
            return []
        }
        guard let text = message["text"] as? String,
              text.utf8.count
                <= Self.maximumClipboardSize else {
            return [
                .sendControl(
                    Self.controlData(
                        [
                            "type": "clipboard-error",
                            "transferId": transferID,
                            "message":
                                "클립보드 텍스트가 비어 있거나 "
                                + "128KB를 초과했습니다.",
                        ]
                    )
                ),
                .event(
                    .failed(
                        "클립보드 텍스트가 128KB를 초과했습니다."
                    )
                ),
            ]
        }
        return [
            .sendControl(
                Self.controlData(
                    [
                        "type": "clipboard-complete",
                        "transferId": transferID,
                    ]
                )
            ),
            .event(.clipboardReceived(text)),
        ]
    }

    private func unsupportedFeature(
        _ message: [String: Any]
    ) -> [VisionLinkDataAction] {
        guard let requestID = Self.nonemptyString(
            message["requestId"]
        ) else {
            return []
        }
        let feature =
            message["feature"] as? String ?? ""
        return [
            .sendControl(
                Self.controlData(
                    [
                        "type": "feature-error",
                        "requestId": requestID,
                        "feature": feature,
                        "message":
                            "이 VisionCraft 원격 기능은 "
                            + "아직 지원되지 않습니다.",
                    ]
                )
            ),
            .event(
                .failed(
                    "원격 \(feature) 요청은 다음 구현 대상입니다."
                )
            ),
        ]
    }

    private func unsupportedChatAttachment(
        _ message: [String: Any]
    ) -> [VisionLinkDataAction] {
        guard let attachmentID =
                Self.nonemptyString(
                    message["attachmentId"]
                ),
              let conversationID =
                Self.nonemptyString(
                    message["conversationId"]
                ) else {
            return []
        }
        return [
            .sendControl(
                Self.controlData(
                    [
                        "type": "chat-attachment-error",
                        "attachmentId": attachmentID,
                        "conversationId":
                            conversationID,
                        "message":
                            "원격 AI 대화 첨부는 "
                            + "아직 지원되지 않습니다.",
                    ]
                )
            ),
        ]
    }

    private func unsupportedLiveReading(
        _ message: [String: Any]
    ) -> [VisionLinkDataAction] {
        guard let sessionID = Self.nonemptyString(
            message["sessionId"]
        ) else {
            return []
        }
        return [
            .sendControl(
                Self.controlData(
                    [
                        "type": "live-reading-error",
                        "sessionId": sessionID,
                        "message":
                            "원격 실시간 읽기는 "
                            + "아직 지원되지 않습니다.",
                    ]
                )
            ),
        ]
    }

    private func transferError(
        _ message: String,
        transferID: String?
    ) -> [VisionLinkDataAction] {
        var actions: [VisionLinkDataAction] = []
        if let transferID {
            actions.append(
                .sendControl(
                    Self.controlData(
                        [
                            "type": "file-error",
                            "transferId": transferID,
                            "message":
                                String(message.prefix(500)),
                        ]
                    )
                )
            )
        }
        actions.append(.event(.failed(message)))
        return actions
    }

    private func abortActiveTransfer() {
        guard let transfer = activeTransfer else {
            return
        }
        abort(transfer)
        activeTransfer = nil
        lastProgressPercent = -1
    }

    private func abort(
        _ transfer: IncomingTransfer
    ) {
        try? transfer.fileHandle.close()
        try? FileManager.default.removeItem(
            at: transfer.partialURL
        )
    }

    private func uniqueDestinationURL(
        fileName: String
    ) -> URL {
        let requested = destinationDirectory
            .appendingPathComponent(
                fileName,
                isDirectory: false
            )
        guard FileManager.default.fileExists(
            atPath: requested.path
        ) else {
            return requested
        }

        let pathExtension =
            requested.pathExtension
        let stem = requested
            .deletingPathExtension()
            .lastPathComponent
        var suffix = 2
        while true {
            var candidateName =
                "\(stem) (\(suffix))"
            if !pathExtension.isEmpty {
                candidateName += ".\(pathExtension)"
            }
            let candidate = destinationDirectory
                .appendingPathComponent(
                    candidateName,
                    isDirectory: false
                )
            if !FileManager.default.fileExists(
                atPath: candidate.path
            ) {
                return candidate
            }
            suffix += 1
        }
    }

    private static func progress(
        for transfer: IncomingTransfer
    ) -> VisionLinkTransferProgress {
        VisionLinkTransferProgress(
            transferID: transfer.transferID,
            kind: transfer.kind,
            fileName: transfer.fileName,
            receivedBytes: transfer.receivedBytes,
            totalBytes: transfer.expectedSize
        )
    }

    private static func sanitizeFileName(
        _ rawValue: String?
    ) -> String {
        let trimmed = rawValue?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        let source = (
            trimmed?.isEmpty == false
        ) ? trimmed! : "visionlink-file"
        let invalid =
            CharacterSet(
                charactersIn: "\\/:*?\"<>|"
            )
            .union(.controlCharacters)
        let scalars = source.unicodeScalars.map {
            invalid.contains($0)
                ? "_"
                : String($0)
        }
        let sanitized = String(
            scalars.joined().prefix(120)
        )
        return sanitized.isEmpty
            ? "visionlink-file"
            : sanitized
    }

    private static func mimeType(
        for fileName: String,
        kind: String
    ) -> String? {
        let pathExtension = URL(
            fileURLWithPath: fileName
        )
        .pathExtension
        .lowercased()
        if kind == "image" {
            return imageMimeTypes[pathExtension]
        }
        guard !blockedGeneralExtensions
                .contains(pathExtension) else {
            return nil
        }
        return UTType(
            filenameExtension: pathExtension
        )?.preferredMIMEType
            ?? "application/octet-stream"
    }

    private static func containsDecodableImage(
        at url: URL
    ) -> Bool {
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            nil
        ),
              CGImageSourceGetCount(source) > 0,
              CGImageSourceGetType(source) != nil,
              let properties =
                CGImageSourceCopyPropertiesAtIndex(
                    source,
                    0,
                    nil
                ) as? [CFString: Any],
              let width =
                properties[kCGImagePropertyPixelWidth]
                as? NSNumber,
              let height =
                properties[kCGImagePropertyPixelHeight]
                as? NSNumber else {
            return false
        }
        return width.intValue > 0
            && height.intValue > 0
    }

    private static func nonemptyString(
        _ value: Any?
    ) -> String? {
        guard let value = value as? String,
              !value.trimmingCharacters(
                in: .whitespacesAndNewlines
              ).isEmpty else {
            return nil
        }
        return value
    }

    private static func int64(
        _ value: Any?
    ) -> Int64? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number)
                != CFBooleanGetTypeID() else {
            return nil
        }
        return number.int64Value
    }

    private static func isSHA256(
        _ value: String
    ) -> Bool {
        let scalars = value.unicodeScalars
        return scalars.count == 64
            && scalars.allSatisfy {
                (48...57).contains($0.value)
                    || (97...102).contains($0.value)
            }
    }

    private static func controlData(
        _ object: [String: Any]
    ) -> Data {
        (
            try? JSONSerialization.data(
                withJSONObject: object,
                options: [.sortedKeys]
            )
        ) ?? Data()
    }
}

private struct IncomingTransfer {
    let transferID: String
    let fileName: String
    let kind: String
    let expectedSize: Int64
    let partialURL: URL
    let mimeType: String
    let fileHandle: FileHandle
    var receivedBytes: Int64 = 0
    var hasher = SHA256()
}

nonisolated private enum VisionLinkDataReceiverError:
    Error,
    LocalizedError
{
    case cannotCreateFile

    var errorDescription: String? {
        "임시 파일을 만들 수 없습니다."
    }
}
