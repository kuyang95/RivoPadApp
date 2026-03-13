//
//  AIResponseChatView.swift
//  shortcuts_example
//
//  Created by me on 3/9/26.
//

import SwiftUI
import AVFoundation


enum QuerySource {
    case text(String)
    case image(UIImage)
}

// MARK: - Message Model

struct Message: Identifiable {

    let id = UUID()
    var text: String?
    let image: UIImage?
    let isMe: Bool

}

// MARK: - Bubble Shape (Tail 포함)

struct BubbleShape: Shape {
    
    func path(in rect: CGRect) -> Path {
        
        let radius: CGFloat = 22
        
        var path = Path()
        
        path.addRoundedRect(
            in: rect,
            cornerSize: CGSize(width: radius, height: radius)
        )
        
        return path
    }
}

// MARK: - Chat Bubble

struct ChatBubble: View {

    let message: Message

    var body: some View {

        VStack(alignment: .leading, spacing: 8) {

            if let image = message.image {

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            if let text = message.text {
                Text(text)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(
            BubbleShape()
                .fill(.ultraThinMaterial)
        )
        .overlay(
            BubbleShape()
                .stroke(Color.white.opacity(0.2), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }
}

// MARK: - Message Row

private struct MessageRow: View {

    let message: Message

    var body: some View {

        HStack(alignment: .top) {

            if message.isMe {

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {

                    if let image = message.image {

                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 360)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    if let text = message.text {

                        ChatBubble(
                            message: Message(
                                text: text,
                                image: nil,
                                isMe: true
                            )
                        )
                    }
                }
                .frame(
                    maxWidth: UIScreen.main.bounds.width * 0.7,
                    alignment: .trailing
                )

            } else {

                VStack(alignment: .leading, spacing: 10) {

                    if let image = message.image {

                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 360)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    if let text = message.text {

                        Text(text)
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.9))
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(
                    maxWidth: UIScreen.main.bounds.width * 0.85,
                    alignment: .leading
                )

                Spacer()
            }
        }
        .padding(.horizontal, 240)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Chat View

struct VoiceQueryResponseView: View {
    
    let source: QuerySource
    private let tts = TTSManager.shared
    private let soundEffectManager = SoundEffectManager.shared
    
    @State private var extractedText: String = ""
    @State private var messages: [Message] = []
    @ObservedObject private var stt = STTManager.shared
    @State private var modelReady = false
    @State private var pendingQuestion: String?
    @State private var pendingDocument: String?
    @State private var pendingImage: UIImage?
    
  
    
    let systemPromptLLM = """
    너는 한국어로 간결하게 답하는 도우미야.
    유저가 "Document:" 뒤에 제공하는 내용은 참고할 내용이고,
    "Question:" 뒤의 질문에 참고 내용을 근거로 답해.
    참고에 없는 내용은 추측하지 말고 모른다고 말해.
    """
    
    let systemPromptVLM = """
    너는 이미지와 질문을 함께 분석하는 한국어 도우미야.
    이미지에 보이는 정보와 사용자의 질문을 기반으로 간결하게 답해.
    확실하지 않으면 추측하지 말고 모른다고 말해.
    """
    
    var body: some View {
        
        ZStack {
            
            LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.08, green: 0.08, blue: 0.1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            ScrollView {
                
                VStack(spacing: 14) {
                    
                    ForEach(messages) { message in
                        MessageRow(message: message)
                    }
                }
                .padding(.vertical, 40)
            }
            
            if stt.isRecording {
                       AuroraListeningOverlay(amplitude: stt.amplitude)
                           .allowsHitTesting(false)
                           .ignoresSafeArea()
                           .transition(.opacity)
                           .zIndex(10)
                   }
        }
        .onAppear {

            switch source {

            case .image:
                handleImageQuery()

            case .text:
                handleTextQuery()
            }
        }
    }
    
    private func handleImageQuery() {

        guard case let .image(image) = source else { return }
        
        pendingImage = image

        // 🔹 먼저 이미지 표시
        messages.append(
            Message(
                text: nil,
                image: image,
                isMe: false
            )
        )

        let extractor = DocumentTextExtractor()

        extractor.extractPlainText(from: image) { result in
            DispatchQueue.main.async {

                switch result {

                case .success(let text):
                    RVLogger.d("이미지 OCR 완료: \(text)")
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

                    if trimmed.count <= 10 {

                        // 🔹 이미지 수신
                        messages.append(
                            Message(
                                text: "이미지 수신",
                                image: nil,
                                isMe: false
                            )
                        )

                        startModelAndSTTForImage(image)

                    } else {

                        // 🔹 문서 수신
                        messages.append(
                            Message(
                                text: "문서 수신",
                                image: nil,
                                isMe: false
                            )
                        )
                        
                      

                        startModelAndSTTForText(trimmed)
                    }

                case .failure(let error):

                    if let extractError = error as? DocumentTextExtractor.ExtractError,
                       extractError == .noText {

                        RVLogger.d("OCR 텍스트 없음 → 이미지 처리")

                        messages.append(
                            Message(
                                text: "이미지 수신",
                                image: nil,
                                isMe: false
                            )
                        )

                        startModelAndSTTForImage(image)

                    } else {

                        RVLogger.d("OCR 실패: \(error)")

                        messages.append(
                            Message(
                                text: "이미지 해석 실패",
                                image: nil,
                                isMe: false
                            )
                        )
                    }
                }
            }
        }
    }
    
    private func handleTextQuery() {

        guard case let .text(text) = source else { return }
           
        pendingDocument = text
        
        messages.append(
            Message(
                text: "문서 수신",
                image: nil,
                isMe: false
            )
        )

        startModelAndSTTForText(text)
    }
    
    private func runLLM(_ text: String) async {

        let service = LLMService.shared

        do {

            service.configureForIPadProM4_12GB()
            try await service.activateModel(.qwen3_8b_4bit)

        } catch {
            print("LLM 오류:", error)
        }
    }
    
    private func runVLM(_ image: UIImage) async {

        let service = LLMService.shared

        guard let ciImage = CIImage(image: image) else { return }

        do {

            service.configureForIPadProM4_12GB()
            try await service.activateModel(.qwen3_vl_8b_4bit)

        } catch {
            print("VLM 오류:", error)
        }
    }
    
    private func runOCR() {

        guard case let .image(image) = source else { return }

        let extractor = DocumentTextExtractor()

        extractor.extractPlainText(from: image) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let text):
                    extractedText = text
                    print("OCR 결과:", text)

                case .failure(let error):
                    print("OCR 실패:", error.localizedDescription)
                }
            }
        }
    }
    
    private func startModelAndSTTForImage(_ image: UIImage) {

        pendingImage = image
         pendingDocument = nil
         
        messages.append(
            Message(
                text: "모델 로딩중",
                image: nil,
                isMe: false
            )
        )

        Task {

            soundEffectManager.play(.recording)

            async let sttTask = startSTT()

            async let modelTask: Void = {

                let service = LLMService.shared

                service.configureForIPadProM4_12GB()

                try await service.activateModel(.qwen3_vl_8b_4bit)

            }()

            do {

                try await modelTask

                await MainActor.run {

                    modelReady = true

                    messages.append(
                        Message(
                            text: "모델 준비됨",
                            image: nil,
                            isMe: false
                        )
                    )

                    Task {
                        await processPendingQueryIfNeeded()
                    }
                }

            } catch {

                print("VLM 오류:", error)
            }

            await sttTask
        }
    }
    
    private func startModelAndSTTForText(_ text: String) {

        pendingImage = nil
           pendingDocument = text
        
        RVLogger.d("들어온 텍스트: \(text)")
        
        messages.append(
            Message(
                text: "모델 로딩중",
                image: nil,
                isMe: false
            )
        )

        Task {

            soundEffectManager.play(.recording)

            async let sttTask = startSTT()

            async let modelTask: Void = {
                let service = LLMService.shared

                service.configureForIPadProM4_12GB()
                try await service.activateModel(.qwen3_8b_4bit)
            }()

            do {
                try await modelTask

                await MainActor.run {

                    modelReady = true

                    messages.append(
                        Message(
                            text: "모델 준비됨",
                            image: nil,
                            isMe: false
                        )
                    )

                    Task {
                        await processPendingQueryIfNeeded()
                    }
                }

            } catch {
                print("LLM 오류:", error)
            }

            await sttTask
        }
    }
    
    private func startSTT() async {

        do {

            let stream = try await stt.startRecording()

            for await text in stream {

                print("UI received STT:", text)

                await MainActor.run {

                    messages.append(
                        Message(
                            text: text,
                            image: nil,
                            isMe: true
                        )
                    )

                    pendingQuestion = text

                    Task {
                        await processPendingQueryIfNeeded()
                    }
                }
            }

        } catch {

            print("STT 오류:", error)
        }
    }
    
    private func processPendingQueryIfNeeded() async {

        guard modelReady else { return }
        guard let question = pendingQuestion else { return }

        let service = LLMService.shared

        pendingQuestion = nil

        if let image = pendingImage {

            guard let ciImage = CIImage(image: image) else { return }

            let stream = try? await service.streamVision(
                system: systemPromptVLM,
                prompt: question,
                images: [ciImage]
            )

            await streamAssistantResponseFiltered(stream)

        } else if let doc = pendingDocument {

            let prompt = """
            Document:
            \(doc)

            Question:
            \(question)
            """

            let stream = try? await service.streamText(
                system: systemPromptLLM,
                prompt: prompt
            )

            await streamAssistantResponseFiltered(stream)
        }
    }
    
    private func streamAssistantResponseFiltered(
        _ stream: AsyncThrowingStream<String, Error>?
    ) async {

        guard let stream else { return }

        await MainActor.run {
            messages.append(
                Message(
                    text: "답변 생성중",
                    image: nil,
                    isMe: false
                )
            )
            soundEffectManager.play(.startingLLM)
            tts.speak("답변 생성중")

            messages.append(
                Message(
                    text: "",
                    image: nil,
                    isMe: false
                )
            )
        }

        let answerIndex = messages.count - 1

        var buffer = ""
        var isInsideThink = false
        var finalText = ""

        do {
            for try await chunk in stream {
                buffer += chunk

                while true {
                    if isInsideThink {
                        if let endRange = buffer.range(of: "</think>") {
                            buffer = String(buffer[endRange.upperBound...])
                            isInsideThink = false
                        } else {
                            buffer = ""
                            break
                        }
                    } else {
                        if let startRange = buffer.range(of: "<think>") {
                            let visiblePart = String(buffer[..<startRange.lowerBound])

                            if !visiblePart.isEmpty {
                                finalText += visiblePart

                                await MainActor.run {
                                    messages[answerIndex].text = finalText
                                }
                            }

                            buffer = String(buffer[startRange.upperBound...])
                            isInsideThink = true
                        } else {
                            let visiblePart = buffer

                            if !visiblePart.isEmpty {
                                finalText += visiblePart

                                await MainActor.run {
                                    messages[answerIndex].text = finalText
                                }
                            }

                            buffer = ""
                            break
                        }
                    }
                }
            }

            if !finalText.isEmpty {
                await MainActor.run {
                    tts.speak(finalText)
                }
            }

        } catch {
            await MainActor.run {
                messages[answerIndex].text =
                    (messages[answerIndex].text ?? "") + "\n\n(스트림 오류)"
            }

            print("LLM stream error:", error)
        }
    }
}
