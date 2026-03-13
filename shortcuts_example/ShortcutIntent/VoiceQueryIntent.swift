import AppIntents
import UniformTypeIdentifiers
import UIKit

struct VoiceQueryIntent: AppIntent {

    static var title: LocalizedStringResource = "음성 질의"
    static var openAppWhenRun: Bool = true

    @Parameter(title: "이미지", supportedContentTypes: [.image])
    var image: IntentFile?

    @Parameter(title: "문서")
    var document: String?

    static var parameterSummary: some ParameterSummary {
        Summary("이미지 \(\.$image) 혹은 문서 \(\.$document) 로 음성 질의")
    }

    func perform() async throws -> some IntentResult {

        let id = UUID()

        var env = ShortcutEnvelope(
            id: id,
            route: .voiceQuery,
            createdAt: Date(),
            schemaVersion: 1,
            params: [:],
            attachments: []
        )

        if let document {
            env.params["document"] = .string(document)
            await ShortcutBridge.replaceLastEnvelope(env)
            return .result()
        }

        guard let imageFile = image else {
            throw NSError(domain: "VoiceQueryIntent", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "이미지가 전달되지 않았습니다."
            ])
        }

        let availableTypes = imageFile.availableContentTypes
        RVLogger.d("전달된 이미지 타입들: \(availableTypes.map(\.identifier))")

        guard let sourceType = pickBestImageType(from: availableTypes) else {
            throw NSError(domain: "VoiceQueryIntent", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "처리 가능한 이미지 타입이 없습니다."
            ])
        }

        RVLogger.d("선택한 원본 타입: \(sourceType.identifier)")

        // 1) 실제 들어온 이미지 representation을 그대로 받아온다.
        let sourceData = try await imageFile.data(contentType: sourceType)

        // 2) 어떤 포맷이든 UIImage로 디코드
        guard let uiImage = UIImage(data: sourceData) else {
            throw NSError(domain: "VoiceQueryIntent", code: -3, userInfo: [
                NSLocalizedDescriptionKey: "이미지를 UIImage로 변환하지 못했습니다. type=\(sourceType.identifier)"
            ])
        }

        // 3) 저장용 표준 포맷으로 재인코딩
        //    - 투명도 있으면 PNG
        //    - 아니면 JPEG
        let saveAsPNG = uiImageHasAlpha(uiImage)

        let finalType: UTType = saveAsPNG ? .png : .jpeg
        let finalExt = finalType.preferredFilenameExtension ?? (saveAsPNG ? "png" : "jpg")

        let finalData: Data?
        if saveAsPNG {
            finalData = uiImage.pngData()
        } else {
            finalData = uiImage.jpegData(compressionQuality: 0.95)
        }

        guard let encodedData = finalData else {
            throw NSError(domain: "VoiceQueryIntent", code: -4, userInfo: [
                NSLocalizedDescriptionKey: "이미지 재인코딩에 실패했습니다."
            ])
        }

        let fileName = "\(id.uuidString).\(finalExt)"

        let dir = ShortcutBridge.attachmentsDir(for: id)
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let saveURL = dir.appendingPathComponent(fileName)
        try encodedData.write(to: saveURL, options: .atomic)

        let attachment = AttachmentRef(
            kind: .image,
            fileName: fileName,
            uti: finalType.identifier
        )
        env.attachments.append(attachment)

        RVLogger.d("이미지 저장 완료: \(saveURL.path)")
        RVLogger.d("저장 포맷: \(finalType.identifier), 크기: \(encodedData.count) bytes")

        await ShortcutBridge.replaceLastEnvelope(env)

        return .result()
    }

    private func pickBestImageType(from types: [UTType]) -> UTType? {
        // abstract .image 보다 실제 concrete 타입을 우선
        if let concrete = types.first(where: { $0.conforms(to: .image) && $0 != .image }) {
            return concrete
        }
        return types.first(where: { $0.conforms(to: .image) })
    }

    private func uiImageHasAlpha(_ image: UIImage) -> Bool {
        guard let alphaInfo = image.cgImage?.alphaInfo else { return false }

        switch alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast:
            return true
        default:
            return false
        }
    }
}
