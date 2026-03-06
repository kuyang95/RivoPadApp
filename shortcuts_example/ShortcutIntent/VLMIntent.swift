import AppIntents
import UniformTypeIdentifiers

struct VMLIntent: AppIntent {

    static var title: LocalizedStringResource = "이미지 질의"
    static var openAppWhenRun: Bool = true

    @Parameter(title: "이미지", supportedContentTypes: [.image])
    var image: IntentFile?

    @Parameter(title: "질의문구")
    var question: String

    static var parameterSummary: some ParameterSummary {
        Summary("이미지 \(\.$image) 에서 \(\.$question) 질의하기")
    }

    func perform() async throws -> some IntentResult {

        let id = UUID()

        var env = ShortcutEnvelope(
            id: id,
            route: .imageQA,
            createdAt: Date(),
            schemaVersion: 1,
            params: [:],
            attachments: []
        )

        env.params["question"] = .string(question)

        // 1) 이미지 존재 확인
        guard let imageFile = image else {
            throw NSError(domain: "VMLIntent", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "이미지가 전달되지 않았습니다."
            ])
        }

        // 2) 어떤 이미지든 처리: (추천) PNG 가능하면 PNG, 아니면 JPEG로 표준화
        //    - 투명(알파) 보존이 필요 없으면 그냥 .jpeg로 고정해도 됨
        let types = imageFile.availableContentTypes
        let chosenType: UTType = types.contains(.png) ? .png : .jpeg

        // ✅ 핵심: fileURL 열지 말고 data(contentType:)로 받기
        let data = try await imageFile.data(contentType: chosenType)

        // 3) 확장자 결정
        let ext = chosenType.preferredFilenameExtension ?? (chosenType == .png ? "png" : "jpg")

        // 4) 고유 파일명 생성
        let fileName = "\(id.uuidString).\(ext)"

        // 5) attachments 폴더에 저장 (폴더가 없으면 생성)
        let dir = ShortcutBridge.attachmentsDir(for: id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let saveURL = dir.appendingPathComponent(fileName)
        try data.write(to: saveURL, options: .atomic)

        // 6) AttachmentRef 추가 (uti도 chosenType으로 넣는 게 정확)
        let attachment = AttachmentRef(
            kind: .image,
            fileName: fileName,
            uti: chosenType.identifier
        )
        env.attachments.append(attachment)
        
        RVLogger.d("이미지 저장완료: \(saveURL.path)")

        // 7) Envelope 저장
        await ShortcutBridge.replaceLastEnvelope(env)

        return .result()
    }
}
