import Foundation
import Combine
import CoreImage
import UIKit

@MainActor
final class ChatViewModel: ObservableObject {

    struct Msg: Identifiable {
        let id = UUID()
        let role: String              // "user" / "assistant"
        var text: String = ""
        var image: UIImage? = nil     // user 이미지 1장 표시용
    }

    @Published var messages: [Msg] = []
    @Published var input: String = ""
    @Published var status: String = ""
    @Published var isLoadingModel: Bool = false
    @Published var isInitialQueryRunning: Bool = false

    let llm: LLMService
    private var genTask: Task<Void, Never>?

    // ✅ 이미지 분석 모드일 때 고정 이미지(후속 질문에도 계속 같이 보냄)
    private var pinnedCIImages: [CIImage] = []

    // ✅ 한번 로드하면 재로드/모델 변경 방지
    private var didLoadOnce = false
    private var loadedKind: LoadedKind?

    private enum LoadedKind { case text, vision }

    init(llm: LLMService) {
        self.llm = llm
    }

    // MARK: - System Prompts (모드별로 다르게)

    private var systemForDocumentQA: String {
        """
        너는 한국어로 간결하게 답하는 도우미야.
        유저가 "Document:" 뒤에 제공하는 내용은 참고 문서고,
        "Question:" 뒤의 질문에 문서 내용을 근거로 답해.
        문서에 없는 내용은 추측하지 말고 모른다고 말해.
        """
    }

    private var systemForImageAnalysis: String {
        """
        너는 한국어로 답하는 이미지 분석 도우미야.
        제공된 이미지를 관찰해서 질문에 답해.
        보이지 않는 내용은 추측하지 말고, 확인 불가하다고 말해.
        """
    }

    // MARK: - Load Model (Intent에 따라 1회만)

    func loadModel(for intent: ChatIntentInput) async {
        guard !didLoadOnce else { return }

        do {
            isLoadingModel = true
            llm.configureForIPadProM4_12GB()

            switch intent {
            case .imageAnalysis:
                try await llm.activateModel(.qwen3_vl_8b_4bit)
                loadedKind = .vision
            case .documentQA:
                try await llm.activateModel(.qwen3_8b_4bit)
                loadedKind = .text
            }

            didLoadOnce = true
            isLoadingModel = false
            status = "Ready"
        } catch {
            isLoadingModel = false
            status = "Load failed: \(error)"
        }
    }

    // MARK: - Initial run (Intent 들어온 순간 1회 실행)

    func runInitialIntent(_ intent: ChatIntentInput) {
        switch intent {
        case .imageAnalysis(let imageURL, let question):

            do {
                let data = try Data(contentsOf: imageURL)
                RVLogger.d("✅ data size: \(data.count)")

                if let uiImage = UIImage(data: data) {
                    RVLogger.d("✅ image size: \(uiImage.size)")

                    messages.append(.init(role: "user", text: "", image: uiImage))
                    messages.append(.init(role: "user", text: question, image: nil))

                    pinnedCIImages = toCIImages([uiImage])
                    startImageAnalysis(question: question)

                } else {
                    print("❌ UIImage 변환 실패")
                    status = "UIImage 변환 실패"
                }

            } catch {
                print("❌ Data load error:", error)
                status = "이미지 로드 실패: \(error.localizedDescription)"
            }

        case .documentQA(let document, let question):
            messages.append(.init(role: "user", text: question, image: nil))
            startDocumentQA(document: document, question: question)
        }
    }

    // MARK: - Start flows (초기 실행 전용 이름)

    private func startDocumentQA(document: String, question: String) {
        let fullPrompt = buildDocumentPrompt(document: document, question: question)
        startStreamingResponse(
            mode: .text,
            system: systemForDocumentQA,
            prompt: fullPrompt
        )
    }

    private func startImageAnalysis(question: String) {
        startStreamingResponse(
            mode: .vision,
            system: systemForImageAnalysis,
            prompt: question
        )
    }

    // MARK: - Manual Chat (후속 질문)

    func sendUserMessage() {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        input = ""

        messages.append(.init(role: "user", text: prompt, image: nil))

        // ✅ 로드된 모델 종류에 따라 텍스트/비전 분기
        switch loadedKind {
        case .vision:
            startStreamingResponse(mode: .vision, system: systemForImageAnalysis, prompt: prompt)
        case .text, .none:
            // .none은 로드 전에 호출된 비정상 케이스인데, 일단 text로 처리(또는 return 해도 됨)
            startStreamingResponse(mode: .text, system: systemForDocumentQA, prompt: prompt)
        }
    }

    func stop() {
        genTask?.cancel()
        status = "Stopped"
        isInitialQueryRunning = false
    }

    // MARK: - Core streaming runner

    private enum RunMode { case text, vision }

    private func startStreamingResponse(mode: RunMode, system: String, prompt: String) {
        messages.append(.init(role: "assistant", text: "", image: nil))
        let assistantIndex = messages.count - 1

        genTask?.cancel()
        genTask = Task {
            do {
                // ✅ 초기 실행에만 오버레이를 띄우고 싶다면, 여기서 판단
                // 지금은 "첫 실행"에서만 overlay가 켜져야 하니,
                // startDocumentQA/startImageAnalysis에서만 아래 플래그를 켜도록 분리하는 것도 가능.
                if messages.count <= 3 { // 대충: 초기 intent 메시지 직후
                    isInitialQueryRunning = true
                }
                status = "Generating…"

                let stream: AsyncThrowingStream<String, Error>
                switch mode {
                case .text:
                    stream = try await llm.streamText(system: system, prompt: prompt)
                case .vision:
                    stream = try await llm.streamVision(system: system, prompt: prompt, images: pinnedCIImages)
                }

                await consumeStream50ms(stream, assistantIndex: assistantIndex)

                status = "Done"
                isInitialQueryRunning = false
            } catch {
                status = "Gen failed: \(error)"
                isInitialQueryRunning = false
            }
        }
    }

    // MARK: - Stream 소비 + <think> 제거(기존 로직 공통화)

    private func consumeStream(
        _ stream: AsyncThrowingStream<String, Error>,
        assistantIndex: Int
    ) async {
        var buffer = ""
        var isInsideThink = false

        do {
            for try await chunk in stream {
                if Task.isCancelled { break }
                
                RVLogger.d("chunk: \(chunk)")
                
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
                            messages[assistantIndex].text += visiblePart
                            buffer = String(buffer[startRange.upperBound...])
                            isInsideThink = true
                        } else {
                            messages[assistantIndex].text += buffer
                            buffer = ""
                            break
                        }
                    }
                }
            }
        } catch {
            messages[assistantIndex].text += "\n\n(스트림 오류: \(error))"
        }
    }
    
    private func consumeStream50ms(
        _ stream: AsyncThrowingStream<String, Error>,
        assistantIndex: Int
    ) async {
        var pending = ""
        let flushIntervalNs: UInt64 = 50_000_000 // 50ms
        var lastFlush = DispatchTime.now().uptimeNanoseconds

        func flushIfNeeded(force: Bool = false) {
            let now = DispatchTime.now().uptimeNanoseconds
            let due = (now - lastFlush) >= flushIntervalNs

            guard force || due else { return }
            guard !pending.isEmpty else { return }

            messages[assistantIndex].text += pending
            pending.removeAll(keepingCapacity: true)
            lastFlush = now
        }

        do {
            for try await chunk in stream {
                if Task.isCancelled { break }

                RVLogger.d("chunk: \(chunk)")
                pending += chunk
                flushIfNeeded()
            }

            // 스트림 끝나면 남은 거 강제 반영
            flushIfNeeded(force: true)

        } catch {
            flushIfNeeded(force: true)
            messages[assistantIndex].text += "\n\n(스트림 오류: \(error))"
        }
    }

    // MARK: - Prompt builders

    private func buildDocumentPrompt(document: String, question: String) -> String {
        """
        Document:
        \(document)

        Question:
        \(question)
        """
    }

    // MARK: - UIImage -> CIImage

    private func toCIImages(_ images: [UIImage]) -> [CIImage] {
        images.compactMap { ui in
            if let ci = CIImage(image: ui) { return ci }
            if let cg = ui.cgImage { return CIImage(cgImage: cg) }
            return nil
        }
    }
}
