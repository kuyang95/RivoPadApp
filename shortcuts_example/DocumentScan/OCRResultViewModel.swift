//
//  OCRResultViewModel.swift
//  shortcuts_example
//
//  Created by meee on 3/4/26.
//

import Foundation
import Vision
import UIKit
import AVFoundation
import Combine

@MainActor
final class OCRResultViewModel: ObservableObject {

    // MARK: - Dependencies
    let sttManager = STTManager.shared
    let llmService = LLMService.shared

    
    // MARK: - OCR State
    @Published var extractedText: String = ""
    @Published var lineBoxes: [TextBox2] = []
    @Published var isExtracting: Bool = false

    // MARK: - LLM State
    @Published var isRecording = false
    @Published var isModelLoading = false
    @Published var aiAnswer: String = ""
    @Published var isGeneratingAI: Bool = false
    @Published var aiStatus: String = ""

    var spatialIndex: OCRSpatialIndex?
    
    // MARK: - Overlay Dots Animation
    @Published var activeDotIndex: Int = 0
    private var dotTimer: Timer?

    
    // MARK: - System Prompt
    private var systemForDocumentQA: String {
        """
        너는 한국어로 간결하게 답하는 도우미야.
        유저가 "Document:" 뒤에 제공하는 내용은 참고할 내용이고,
        "Question:" 뒤의 질문에 참고 내용을 근거로 답해.
        참고에 없는 내용은 추측하지 말고 모른다고 말해.
        """
    }
    
    init() {

           // 🔥 여기 넣는다
           llmService.$isLoading
               .receive(on: DispatchQueue.main)
               .assign(to: &$isModelLoading)
        
        sttManager.$isRecording
            .receive(on: DispatchQueue.main)
            .assign(to: &$isRecording)
        
       }

    // MARK: - Public: Model loading
    func ensureModelLoaded() async {
        do {
            llmService.configureForIPadProM4_8GB()
            try await llmService.ensureLoaded(.qwen3_8b_4bit)
            RVLogger.d("✅ ready: \(llmService.loadedModel.displayName)")
        } catch {
            RVLogger.d("❌ load failed: \(error)")
        }
    }

    // MARK: - Animation
    func startThinkingAnimation() {
        dotTimer?.invalidate()
        dotTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.activeDotIndex = (self.activeDotIndex + 1) % 3
        }
        RunLoop.main.add(dotTimer!, forMode: .common)
    }

    func stopThinkingAnimation() {
        dotTimer?.invalidate()
        dotTimer = nil
        activeDotIndex = 0
    }

    // MARK: - OCR
    func runOCR(image: UIImage) {
        guard !isExtracting else { return }

        isExtracting = true
        startThinkingAnimation()

        guard let cg = image.cgImage else {
            stopThinkingAnimation()
            isExtracting = false
            return
        }

        let request = VNRecognizeTextRequest { [weak self] req, _ in
            guard let self else { return }

            let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
            var boxes: [TextBox2] = []

            for obs in observations {
                guard let best = obs.topCandidates(1).first else { continue }
                boxes.append(TextBox2(text: best.string, box: obs.boundingBox))
            }

            boxes = self.sortReadingOrder(boxes)

            DispatchQueue.main.async {
                self.lineBoxes = boxes
                self.extractedText = boxes.map(\.text).joined(separator: "\n")
                self.stopThinkingAnimation()
                self.isExtracting = false
            }
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["ko-KR", "en-US"]
        request.minimumTextHeight = 0.02

        DispatchQueue.global(qos: .userInitiated).async {
            try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
        }
    }

    func buildSpatialIndex(
        boxes: [TextBox2],
        image: UIImage
    ) {

        spatialIndex = OCRSpatialIndex(
            screenSize: UIScreen.main.bounds.size
        )

        for (i, box) in boxes.enumerated() {

            let rect = convertVisionRect(
                box.box,
                imageSize: image.size
            )

            spatialIndex?.insert(
                box: rect,
                index: i
            )
        }
    }
    
    func convertVisionRect(
        _ rect: CGRect,
        imageSize: CGSize
    ) -> CGRect {

        let flipped = CGRect(
            x: rect.origin.x,
            y: 1 - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )

        return CGRect(
            x: flipped.origin.x * imageSize.width,
            y: flipped.origin.y * imageSize.height,
            width: flipped.width * imageSize.width,
            height: flipped.height * imageSize.height
        )
    }
    
    // MARK: - STT → LLM QA
    func runDocumentQA(question: String, isTTSEnabled: Bool) async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }

        aiAnswer = ""
        aiStatus = "Generating..."
        isGeneratingAI = true
        startThinkingAnimation()

        if isTTSEnabled {
            TTSManager.shared.stop()
            TTSManager.shared.speak("AI 답변 생성중")
        }

        let fullPrompt = """
        Document:
        \(extractedText)

        Question:
        \(q)
        """

        do {
            let stream = try await llmService.streamText(system: systemForDocumentQA, prompt: fullPrompt)
            try await consumeAIStream(stream)
            aiStatus = "Done"
        } catch {
            aiStatus = "QA 실패: \(error.localizedDescription)"
        }

        stopThinkingAnimation()
        isGeneratingAI = false

        if isTTSEnabled, !aiAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            TTSManager.shared.speak(aiAnswer)
        }
    }

    // MARK: - Stream consumer (with <think> stripping)
    private func consumeAIStream(_ stream: AsyncThrowingStream<String, Error>) async throws {
        var buffer = ""
        var pending = ""
        var isInsideThink = false

        let flushIntervalNs: UInt64 = 50_000_000
        var lastFlush = DispatchTime.now().uptimeNanoseconds

        func flush(force: Bool = false) async {
            let now = DispatchTime.now().uptimeNanoseconds
            let due = (now - lastFlush) >= flushIntervalNs
            guard force || due else { return }
            guard !pending.isEmpty else { return }

            await MainActor.run {
                self.aiAnswer += pending
            }
            pending.removeAll(keepingCapacity: true)
            lastFlush = now
        }

        for try await chunk in stream {
            if Task.isCancelled { break }

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
                        pending += visiblePart
                        buffer = String(buffer[startRange.upperBound...])
                        isInsideThink = true
                    } else {
                        pending += buffer
                        buffer = ""
                        break
                    }
                }
            }

            await flush()
        }

        await flush(force: true)
    }

    // MARK: - Helpers
    func sortReadingOrder(_ boxes: [TextBox2]) -> [TextBox2] {
        let tolerance: CGFloat = 0.02
        return boxes.sorted { a, b in
            if abs(a.box.maxY - b.box.maxY) > tolerance {
                return a.box.maxY > b.box.maxY
            }
            return a.box.minX < b.box.minX
        }
    }

    func cropImage(from visionRect: CGRect, in image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)

        let flipped = CGRect(
            x: visionRect.origin.x,
            y: 1 - visionRect.origin.y - visionRect.height,
            width: visionRect.width,
            height: visionRect.height
        )

        var cropRect = CGRect(
            x: flipped.origin.x * width,
            y: flipped.origin.y * height,
            width: flipped.width * width,
            height: flipped.height * height
        )

        let padding: CGFloat = 12
        cropRect = cropRect.insetBy(dx: -padding, dy: -padding)
        cropRect = cropRect.intersection(CGRect(x: 0, y: 0, width: width, height: height))

        guard let croppedCG = cgImage.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: croppedCG)
    }
}

// MARK: - Models used by View / VM

struct TextBox2: Equatable {
    let text: String
    let box: CGRect
}
