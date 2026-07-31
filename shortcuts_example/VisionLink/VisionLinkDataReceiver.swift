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

nonisolated enum VisionLinkRemoteFeature:
    String,
    Equatable,
    Sendable
{
    case ocr
    case imageAnalysis = "image-analysis"
    case aiChat = "ai-chat"
    case liveReading = "live-reading"
    case translation

    var title: String {
        switch self {
        case .ocr:
            return "OCR"
        case .imageAnalysis:
            return AppLocalization.string(
                "이미지 설명"
            )
        case .aiChat:
            return AppLocalization.string(
                "AI 대화"
            )
        case .liveReading:
            return AppLocalization.string(
                "실시간 읽기"
            )
        case .translation:
            return AppLocalization.string(
                "번역"
            )
        }
    }
}

nonisolated struct VisionLinkFeatureImageRequest:
    Equatable,
    Sendable
{
    let requestID: String
    let feature: VisionLinkRemoteFeature
    let fileURL: URL
}

nonisolated struct VisionLinkTextTranslationRequest:
    Equatable,
    Sendable
{
    let requestID: String
    let text: String
}

nonisolated enum VisionLinkRemoteFeatureRequest:
    Equatable,
    Sendable
{
    case image(VisionLinkFeatureImageRequest)
    case translationText(
        VisionLinkTextTranslationRequest
    )

    var requestID: String {
        switch self {
        case .image(let request):
            return request.requestID
        case .translationText(let request):
            return request.requestID
        }
    }

    var feature: VisionLinkRemoteFeature {
        switch self {
        case .image(let request):
            return request.feature
        case .translationText:
            return .translation
        }
    }

    var temporaryFileURL: URL? {
        guard case .image(let request) = self else {
            return nil
        }
        return request.fileURL
    }
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
    case remoteFeatureRequested(
        VisionLinkRemoteFeatureRequest
    )
    case remoteChatRequested(
        VisionLinkChatRequest
    )
    case remoteChatContextReceived(
        VisionLinkChatContextAttachment
    )
    case remoteChatAttachmentReceived(
        VisionLinkChatFileAttachment
    )
    case liveReadingStarted(String)
    case liveReadingStopped(String)
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

nonisolated enum VisionLinkFeatureControl {
    static let maximumResultSize =
        256 * 1_024
    static let maximumErrorLength = 500

    static func progress(
        requestID: String,
        feature: VisionLinkRemoteFeature,
        stage: String
    ) -> Data {
        controlData(
            [
                "type": "feature-progress",
                "requestId": requestID,
                "feature": feature.rawValue,
                "stage": stage,
            ]
        )
    }

    static func result(
        requestID: String,
        feature: VisionLinkRemoteFeature,
        text: String
    ) -> Data {
        guard text.utf8.count
                <= maximumResultSize else {
            return error(
                requestID: requestID,
                feature: feature,
                message:
                    AppLocalization.string(
                        "기능 결과가 전송 가능한 크기를 초과했습니다."
                    )
            )
        }
        return controlData(
            [
                "type": "feature-result",
                "requestId": requestID,
                "feature": feature.rawValue,
                "text": text,
            ]
        )
    }

    static func error(
        requestID: String,
        feature: VisionLinkRemoteFeature,
        message: String
    ) -> Data {
        controlData(
            [
                "type": "feature-error",
                "requestId": requestID,
                "feature": feature.rawValue,
                "message": String(
                    message.prefix(maximumErrorLength)
                ),
            ]
        )
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

actor VisionLinkDataReceiver {
    static let maximumFileSize: Int64 =
        1_073_741_824
    static let maximumFeatureImageSize: Int64 =
        25 * 1_024 * 1_024
    static let maximumClipboardSize =
        128 * 1_024
    static let maximumFeatureRequestSize =
        40 * 1_024
    static let maximumTranslationTextSize =
        32 * 1_024
    static let maximumRequestIDLength = 80
    static let maximumChatRequestSize =
        128 * 1_024
    static let maximumChatMessageSize =
        16 * 1_024
    static let maximumChatContextSize =
        64 * 1_024
    static let maximumChatAttachmentSize: Int64 =
        25 * 1_024 * 1_024
    static let maximumChatPDFSize: Int64 =
        14 * 1_024 * 1_024
    static let maximumChatMessages = 40
    static let maximumLiveReadingSessionIDLength =
        80

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
                        AppLocalization.string(
                            "VisionLink 데이터 제어 메시지를 읽지 못했습니다."
                        )
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
            return receiveFeatureRequest(
                message,
                rawSize: data.count
            )
        case "chat-context-attachment":
            return receiveChatContextAttachment(message)
        case "live-reading-start":
            return receiveLiveReading(
                message,
                started: true
            )
        case "live-reading-stop":
            return receiveLiveReading(
                message,
                started: false
            )
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
                    .failed(
                        AppLocalization.string(
                            "파일 전송 ID가 비어 있습니다."
                        )
                    )
                ),
            ]
        }
        guard let size = Self.int64(
            message["size"]
        ),
              size >= 0,
              size <= Self.maximumFileSize else {
            return transferError(
                AppLocalization.string(
                    "파일 크기가 올바르지 않습니다."
                ),
                transferID: transferID
            )
        }

        let purpose = message["purpose"] as? String
        let fileName = Self.sanitizeFileName(
            message["name"] as? String
        )
        let declaredKind =
            message["kind"] as? String
        let kind = declaredKind == "image"
            ? "image"
            : "file"
        let isFeatureRequest =
            purpose == "visioncraft-feature"
        let isChatAttachment =
            purpose == "visioncraft-chat-attachment"
        let feature: VisionLinkRemoteFeature?
        let requestID: String?
        let chatAttachment:
            IncomingChatAttachment?
        let mimeType: String

        if isFeatureRequest {
            feature = (
                message["feature"] as? String
            ).flatMap(
                VisionLinkRemoteFeature.init(
                    rawValue:
                )
            )
            requestID = Self.validRequestID(
                message["requestId"]
            )
            guard let feature,
                  feature == .ocr
                    || feature == .imageAnalysis
                    || feature == .translation,
                  requestID != nil,
                  declaredKind == "image" else {
                return transferError(
                    AppLocalization.string(
                        "지원하지 않는 VisionCraft 기능 요청입니다."
                    ),
                    transferID: transferID
                )
            }
            guard size > 0,
                  size <= Self
                    .maximumFeatureImageSize else {
                return transferError(
                    AppLocalization.string(
                        "기능 이미지는 25MB 이하만 사용할 수 있습니다."
                    ),
                    transferID: transferID
                )
            }
            let declaredMimeType = (
                message["mimeType"] as? String
            )?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            mimeType = declaredMimeType?
                .isEmpty == false
                ? declaredMimeType!
                : Self.mimeType(
                    for: fileName,
                    kind: "image"
                ) ?? "image/*"
            chatAttachment = nil
        } else if isChatAttachment {
            feature = nil
            requestID = nil
            let attachmentID = Self.validRequestID(
                message["attachmentId"]
            )
            let conversationID = Self.validRequestID(
                message["conversationId"]
            )
            let attachmentKind = (
                message["attachmentKind"] as? String
            ).flatMap(
                VisionLinkChatAttachmentKind.init(
                    rawValue:
                )
            )
            let declaredMimeType = (
                message["mimeType"] as? String
            )?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard let attachmentID,
                  attachmentID == transferID,
                  let conversationID,
                  let attachmentKind,
                  let declaredMimeType,
                  Self.isValidChatAttachment(
                    fileName: fileName,
                    transferKind: kind,
                    attachmentKind:
                        attachmentKind,
                    mimeType: declaredMimeType,
                    size: size
                  ) else {
                return transferError(
                    AppLocalization.string(
                        "지원하지 않거나 잘못된 대화 첨부입니다."
                    ),
                    transferID: transferID
                )
            }
            mimeType = declaredMimeType
            chatAttachment =
                IncomingChatAttachment(
                    attachmentID: attachmentID,
                    conversationID:
                        conversationID,
                    kind: attachmentKind
                )
        } else {
            feature = nil
            requestID = nil
            chatAttachment = nil
            guard let resolvedMimeType =
                    Self.mimeType(
                        for: fileName,
                        kind: kind
                    ) else {
                return transferError(
                    AppLocalization.string(
                        "지원하지 않는 파일 형식입니다."
                    ),
                    transferID: transferID
                )
            }
            mimeType = resolvedMimeType
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
                fileHandle: handle,
                feature: feature,
                requestID: requestID,
                chatAttachment: chatAttachment
            )
            lastProgressPercent = -1
        } catch {
            if let createdPartialURL {
                try? FileManager.default.removeItem(
                    at: createdPartialURL
                )
            }
            return transferError(
                AppLocalization.format(
                    "파일 저장 준비에 실패했습니다: %@",
                    error.localizedDescription
                ),
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
                AppLocalization.string(
                    "선언된 파일 크기를 초과한 데이터가 수신되었습니다."
                ),
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
                AppLocalization.format(
                    "파일 쓰기에 실패했습니다: %@",
                    error.localizedDescription
                ),
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
                        AppLocalization.string(
                            "완료할 파일 전송이 없습니다."
                        )
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
                AppLocalization.string(
                    "파일 전송 ID가 일치하지 않습니다."
                ),
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
                AppLocalization.string(
                    "파일 검증 정보가 올바르지 않습니다."
                ),
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
                AppLocalization.format(
                    "파일 저장 완료 처리에 실패했습니다: %@",
                    error.localizedDescription
                ),
                transferID: transferID
            )
        }
        activeTransfer = nil

        guard transfer.receivedBytes
                == transfer.expectedSize else {
            abort(transfer)
            return transferError(
                AppLocalization.format(
                    "파일 크기가 다릅니다: %lld/%lld bytes",
                    transfer.receivedBytes,
                    transfer.expectedSize
                ),
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
                AppLocalization.string(
                    "파일 SHA-256 검증에 실패했습니다."
                ),
                transferID: transfer.transferID
            )
        }
        guard transfer.kind != "image"
                || Self.containsDecodableImage(
                    at: transfer.partialURL
                ) else {
            abort(transfer)
            return transferError(
                AppLocalization.string(
                    "수신한 이미지 형식이 올바르지 않습니다."
                ),
                transferID: transfer.transferID
            )
        }

        let finalURL: URL
        if transfer.feature != nil
            || transfer.chatAttachment != nil {
            finalURL = uniqueFeatureURL(
                fileName: transfer.fileName
            )
        } else {
            finalURL = uniqueDestinationURL(
                fileName: transfer.fileName
            )
        }
        do {
            try FileManager.default.createDirectory(
                at: finalURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(
                at: transfer.partialURL,
                to: finalURL
            )
        } catch {
            abort(transfer)
            return transferError(
                AppLocalization.format(
                    "파일 저장 완료 처리에 실패했습니다: %@",
                    error.localizedDescription
                ),
                transferID: transfer.transferID
            )
        }

        var actions: [VisionLinkDataAction] = [
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
        ]
        if let feature = transfer.feature,
           let requestID = transfer.requestID {
            actions.append(
                .event(
                    .remoteFeatureRequested(
                        .image(
                            VisionLinkFeatureImageRequest(
                                requestID: requestID,
                                feature: feature,
                                fileURL: finalURL
                            )
                        )
                    )
                )
            )
        } else if let chatAttachment =
                    transfer.chatAttachment {
            actions.append(
                .event(
                    .remoteChatAttachmentReceived(
                        VisionLinkChatFileAttachment(
                            attachmentID:
                                chatAttachment
                                .attachmentID,
                            conversationID:
                                chatAttachment
                                .conversationID,
                            name:
                                transfer.fileName,
                            kind:
                                chatAttachment.kind,
                            mimeType:
                                transfer.mimeType,
                            fileURL: finalURL
                        )
                    )
                )
            )
        } else {
            let receivedFile = VisionLinkReceivedFile(
                transferID: transfer.transferID,
                kind: transfer.kind,
                fileName: finalURL.lastPathComponent,
                size: transfer.receivedBytes,
                url: finalURL,
                mimeType: transfer.mimeType
            )
            actions.append(
                .event(.fileReceived(receivedFile))
            )
        }
        return actions
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
                .failed(
                    AppLocalization.string(
                        "파일 전송이 취소되었습니다."
                    )
                )
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
                                AppLocalization.string(
                                    "클립보드 텍스트가 비어 있거나 128KB를 초과했습니다."
                                ),
                        ]
                    )
                ),
                .event(
                    .failed(
                        AppLocalization.string(
                            "클립보드 텍스트가 128KB를 초과했습니다."
                        )
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

    private func receiveFeatureRequest(
        _ message: [String: Any],
        rawSize: Int
    ) -> [VisionLinkDataAction] {
        guard let requestID = Self.validRequestID(
            message["requestId"]
        ) else {
            return []
        }
        let rawFeature =
            message["feature"] as? String ?? ""
        if rawFeature
                == VisionLinkRemoteFeature
                    .aiChat.rawValue {
            return receiveChatRequest(
                message,
                requestID: requestID,
                rawSize: rawSize
            )
        }
        guard rawFeature
                == VisionLinkRemoteFeature
                    .translation.rawValue else {
            let feature =
                VisionLinkRemoteFeature(
                    rawValue: rawFeature
                )
            let data: Data
            if let feature {
                data = VisionLinkFeatureControl.error(
                    requestID: requestID,
                    feature: feature,
                    message:
                        AppLocalization.string(
                            "지원하지 않는 VisionCraft 기능입니다."
                        )
                )
            } else {
                data = Self.controlData(
                    [
                        "type": "feature-error",
                        "requestId": requestID,
                        "feature": rawFeature,
                        "message":
                            AppLocalization.string(
                                "지원하지 않는 VisionCraft 기능입니다."
                            ),
                    ]
                )
            }
            return [
                .sendControl(data),
                .event(
                    .failed(
                        AppLocalization.format(
                            "지원하지 않는 원격 기능 요청입니다: %@",
                            rawFeature
                        )
                    )
                ),
            ]
        }

        guard rawSize <= Self
                .maximumFeatureRequestSize else {
            return featureRequestError(
                requestID: requestID,
                message:
                    AppLocalization.string(
                        "번역할 텍스트가 너무 깁니다."
                    )
            )
        }
        let text = (
            message["payload"]
                as? [String: Any]
        )?["text"] as? String
        guard let text,
              !text.trimmingCharacters(
                in: .whitespacesAndNewlines
              ).isEmpty,
              text.utf8.count
                <= Self.maximumTranslationTextSize else {
            return featureRequestError(
                requestID: requestID,
                message:
                    AppLocalization.string(
                        "번역할 텍스트가 비어 있거나 32KB를 초과했습니다."
                    )
            )
        }
        return [
            .event(
                .remoteFeatureRequested(
                    .translationText(
                        VisionLinkTextTranslationRequest(
                            requestID: requestID,
                            text: text
                        )
                    )
                )
            ),
        ]
    }

    private func featureRequestError(
        requestID: String,
        message: String
    ) -> [VisionLinkDataAction] {
        [
            .sendControl(
                VisionLinkFeatureControl.error(
                    requestID: requestID,
                    feature: .translation,
                    message: message
                )
            ),
            .event(.failed(message)),
        ]
    }

    private func receiveChatRequest(
        _ message: [String: Any],
        requestID: String,
        rawSize: Int
    ) -> [VisionLinkDataAction] {
        guard rawSize
                <= Self.maximumChatRequestSize else {
            return chatRequestError(
                requestID: requestID,
                message:
                    AppLocalization.string(
                        "대화 요청이 전송 가능한 크기를 초과했습니다."
                    )
            )
        }
        guard let conversationID =
                Self.validRequestID(
                    message["conversationId"]
                ),
              let payload =
                message["payload"]
                    as? [String: Any],
              let rawMessages =
                payload["messages"] as? [Any],
              (1...Self.maximumChatMessages)
                .contains(rawMessages.count) else {
            return chatRequestError(
                requestID: requestID,
                message:
                    AppLocalization.string(
                        "대화 요청 형식이 올바르지 않습니다."
                    )
            )
        }

        var messages: [VisionLinkChatMessage] =
            []
        messages.reserveCapacity(rawMessages.count)
        for rawMessage in rawMessages {
            guard let item =
                    rawMessage as? [String: Any],
                  let roleValue =
                    item["role"] as? String,
                  let role = VisionLinkChatRole(
                    rawValue: roleValue
                  ),
                  let content =
                    item["content"] as? String,
                  !content.trimmingCharacters(
                    in: .whitespacesAndNewlines
                  ).isEmpty,
                  content.utf8.count
                    <= Self.maximumChatMessageSize else {
                return chatRequestError(
                    requestID: requestID,
                    message:
                        AppLocalization.string(
                            "대화 메시지 형식이 올바르지 않습니다."
                        )
                )
            }
            messages.append(
                VisionLinkChatMessage(
                    role: role,
                    content: content
                )
            )
        }
        guard messages.last?.role == .user else {
            return chatRequestError(
                requestID: requestID,
                message:
                    AppLocalization.string(
                        "대화 메시지 형식이 올바르지 않습니다."
                    )
            )
        }
        return [
            .event(
                .remoteChatRequested(
                    VisionLinkChatRequest(
                        requestID: requestID,
                        conversationID:
                            conversationID,
                        messages: messages
                    )
                )
            ),
        ]
    }

    private func chatRequestError(
        requestID: String,
        message: String
    ) -> [VisionLinkDataAction] {
        [
            .sendControl(
                VisionLinkFeatureControl.error(
                    requestID: requestID,
                    feature: .aiChat,
                    message: message
                )
            ),
            .event(.failed(message)),
        ]
    }

    private func receiveChatContextAttachment(
        _ message: [String: Any]
    ) -> [VisionLinkDataAction] {
        guard let attachmentID =
                Self.validRequestID(
                    message["attachmentId"]
                ),
              let conversationID =
                Self.validRequestID(
                    message["conversationId"]
                ) else {
            return []
        }
        let trimmedName = (
            message["name"] as? String ?? ""
        )
        .trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let name = trimmedName.isEmpty
            ? AppLocalization.string(
                "클립보드"
            )
            : String(trimmedName.prefix(120))
        guard let text = message["text"] as? String,
              !text.trimmingCharacters(
                in: .whitespacesAndNewlines
              ).isEmpty,
              text.utf8.count
                <= Self.maximumChatContextSize else {
            return [
                .sendControl(
                    VisionLinkChatControl
                        .attachmentError(
                            attachmentID:
                                attachmentID,
                            conversationID:
                                conversationID,
                            message:
                                AppLocalization.string(
                                    "클립보드 첨부가 비어 있거나 64KB를 초과했습니다."
                                )
                        )
                ),
            ]
        }
        return [
            .event(
                .remoteChatContextReceived(
                    VisionLinkChatContextAttachment(
                        attachmentID: attachmentID,
                        conversationID:
                            conversationID,
                        name: name,
                        text: text
                    )
                )
            ),
        ]
    }

    private func receiveLiveReading(
        _ message: [String: Any],
        started: Bool
    ) -> [VisionLinkDataAction] {
        guard let sessionID =
                Self.nonemptyString(
                    message["sessionId"]
                ),
              sessionID.count <= Self
                .maximumLiveReadingSessionIDLength
        else {
            return []
        }
        return [
            .event(
                started
                    ? .liveReadingStarted(
                        sessionID
                    )
                    : .liveReadingStopped(
                        sessionID
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

    private func uniqueFeatureURL(
        fileName: String
    ) -> URL {
        let directory = partialDirectory
            .appendingPathComponent(
                "Features",
                isDirectory: true
            )
        let pathExtension = URL(
            fileURLWithPath: fileName
        )
        .pathExtension
        var name = UUID().uuidString
        if !pathExtension.isEmpty {
            name += ".\(pathExtension)"
        }
        return directory.appendingPathComponent(
            name,
            isDirectory: false
        )
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

    private static func isValidChatAttachment(
        fileName: String,
        transferKind: String,
        attachmentKind:
            VisionLinkChatAttachmentKind,
        mimeType: String,
        size: Int64
    ) -> Bool {
        guard size > 0,
              size <= maximumChatAttachmentSize,
              !mimeType.isEmpty else {
            return false
        }
        if attachmentKind == .image {
            return transferKind == "image"
                && mimeType.hasPrefix("image/")
        }
        guard transferKind == "file" else {
            return false
        }
        let pathExtension = URL(
            fileURLWithPath: fileName
        )
        .pathExtension
        .lowercased()
        guard [
            "pdf",
            "txt",
            "hwp",
            "xls",
            "xlsx",
        ].contains(pathExtension) else {
            return false
        }
        return pathExtension != "pdf"
            || (
                mimeType == "application/pdf"
                    && size <= maximumChatPDFSize
            )
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

    private static func validRequestID(
        _ value: Any?
    ) -> String? {
        guard let value = nonemptyString(value),
              value.count
                <= maximumRequestIDLength else {
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
    let feature: VisionLinkRemoteFeature?
    let requestID: String?
    let chatAttachment:
        IncomingChatAttachment?
    var receivedBytes: Int64 = 0
    var hasher = SHA256()
}

private struct IncomingChatAttachment {
    let attachmentID: String
    let conversationID: String
    let kind: VisionLinkChatAttachmentKind
}

nonisolated private enum VisionLinkDataReceiverError:
    Error,
    LocalizedError
{
    case cannotCreateFile

    var errorDescription: String? {
        AppLocalization.string(
            "임시 파일을 만들 수 없습니다."
        )
    }
}
