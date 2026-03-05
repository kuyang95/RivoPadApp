import SwiftUI
import Vision
import AVFoundation

struct OCRResultView: View {
    
    let image: UIImage
    
    @State private var extractedText: String = ""
    @State private var lineBoxes: [TextBox2] = []
    @State private var isExtracting = false
    @State private var showBoxes: Bool = false
    
    @State private var isTTSEnabled: Bool = true
    @State private var isPreviewImageEnabled: Bool = true
    @State private var previewText: String? = nil
    @State private var previewOnLeft: Bool = false
    @State private var lastPreviewIndex: Int? = nil
    @State private var previewCroppedImage: UIImage? = nil
    
    @State private var ttsWorkItem: DispatchWorkItem?
    
    var body: some View {
        ZStack {
            imageLayer
            
            // 🔥 오른쪽 상단 버튼
            if !extractedText.isEmpty {
                VStack {
                    HStack(spacing: 14) {
                        
                        // 🔊 TTS 토글
                        Button {
                            isTTSEnabled.toggle()
                            
                            if !isTTSEnabled {
                                ttsWorkItem?.cancel()
                                TTSManager.shared.stop()
                            }
                            
                        } label: {
                            Image(systemName: isTTSEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        
                        // 🖼 프리뷰 이미지 토글
                        Button {
                            isPreviewImageEnabled.toggle()
                        } label: {
                            Image(systemName: isPreviewImageEnabled ? "eye.fill" : "eye.slash.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        
                        // 🟨 강조 토글
                        Button {
                            showBoxes.toggle()
                        } label: {
                            Image(systemName: showBoxes ? "rectangle.slash" : "rectangle")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        
                        // 📋 복사
                        Button {
                            UIPasteboard.general.string = extractedText
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.top, 12)
                    .padding(.trailing, 16)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .topTrailing)
            }
            
//            if let previewText {
//                previewPanel(text: previewText)
//            }
            
            if isExtracting {
                ProgressView("텍스트 추출중...")
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
            }
        }
        .overlay(
            Group {
                if let previewText {
                    previewPanel(text: previewText)
                }
            }
        )
        .onAppear {
            if extractedText.isEmpty {
                runOCR()
            }
        }
    }
}

////////////////////////////////////////////////////////////
// MARK: - Image Layer
////////////////////////////////////////////////////////////

extension OCRResultView {
    
    var imageLayer: some View {
        GeometryReader { geo in
            
            let fittedRect = AVMakeRect(
                aspectRatio: image.size,
                insideRect: CGRect(origin: .zero, size: geo.size)
            )
            
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                
                overlayBoxes(fittedRect: fittedRect)
                    .opacity(showBoxes ? 1 : 0)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleTouch(
                            location: value.location,
                            containerSize: geo.size,
                            fittedRect: fittedRect
                        )
                    }
                    .onEnded { _ in
                        clearPreviewAndStop()
                    }
            )
        }
    }
}

////////////////////////////////////////////////////////////
// MARK: - Overlay Boxes
////////////////////////////////////////////////////////////

extension OCRResultView {
    
    func overlayBoxes(fittedRect: CGRect) -> some View {
        ForEach(lineBoxes.indices, id: \.self) { index in
            
            let rect = convertVisionRect(
                lineBoxes[index].box,
                fittedRect: fittedRect
            )
            
            Rectangle()
                .stroke(Color.yellow, lineWidth: 2)
                .background(Color.yellow.opacity(0.18))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
    }
}

////////////////////////////////////////////////////////////
// MARK: - Touch Handling + TTS
////////////////////////////////////////////////////////////

extension OCRResultView {
    
    func handleTouch(
        location: CGPoint,
        containerSize: CGSize,
        fittedRect: CGRect
    ) {
        
        guard fittedRect.contains(location) else {
            clearPreviewAndStop()
            return
        }
        
        var hitIndex: Int? = nil
        var bestArea: CGFloat = .greatestFiniteMagnitude
        
        for (idx, item) in lineBoxes.enumerated() {
            let rect = convertVisionRect(item.box, fittedRect: fittedRect)
            
            if rect.contains(location) {
                let area = rect.width * rect.height
                if area < bestArea {
                    bestArea = area
                    hitIndex = idx
                }
            }
        }
        
        guard let idx = hitIndex else {
            clearPreviewAndStop()
            return
        }
        
        previewOnLeft = location.x > containerSize.width / 2
        
        if lastPreviewIndex != idx {
            
            lastPreviewIndex = idx
            previewText = lineBoxes[idx].text
            previewCroppedImage = cropImage(from: lineBoxes[idx].box)
            
            ttsWorkItem?.cancel()
            
            if TTSManager.shared.isSpeaking {
                TTSManager.shared.stop()
            }
            
            let textToSpeak = lineBoxes[idx].text
            
            let workItem = DispatchWorkItem {
                if lastPreviewIndex == idx && isTTSEnabled {
                    TTSManager.shared.speak(textToSpeak)
                }
            }
            
            ttsWorkItem = workItem
            
            DispatchQueue.main.async {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
            }
        }
    }
    
    func clearPreviewAndStop() {
        previewText = nil
        previewCroppedImage = nil
        lastPreviewIndex = nil
        ttsWorkItem?.cancel()
        
        if TTSManager.shared.isSpeaking {
            TTSManager.shared.stop()
        }
    }
}

////////////////////////////////////////////////////////////
// MARK: - Preview Panel
////////////////////////////////////////////////////////////

extension OCRResultView {
    
    func previewPanel(text: String) -> some View {
        HStack(spacing: 0) {
            if previewOnLeft {
                panelContent(text)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                panelContent(text)
            }
        }
        .ignoresSafeArea()   // 🔥 상태바 영역까지 덮도록
        .animation(.easeInOut(duration: 0.12), value: previewOnLeft)
    }

    func panelContent(_ text: String) -> some View {
        
        let panelWidth = UIScreen.main.bounds.width * 0.5
        let panelHeight = UIScreen.main.bounds.height
        
        return VStack(spacing: 0) {
            
            if isPreviewImageEnabled,
               let cropped = previewCroppedImage {
                
                // 🔥 이미지 ON → 상/하 50%
                VStack(spacing: 0) {
                    
                    Text(text)
                        .font(.system(size: 56, weight: .bold))   // 🔥 글자 크게
                        .foregroundColor(.white)
                        .padding(20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    
                    Divider().background(Color.white.opacity(0.4))
                    
                    Image(uiImage: cropped)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                }
                
            } else {
                
                // 🔥 이미지 OFF → 텍스트가 전체 높이 차지
                Text(text)
                    .font(.system(size: 80, weight: .bold))   // 🔥 더 크게
                    .foregroundColor(.white)
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: panelWidth, height: panelHeight)   // 🔥 항상 절반 전체 높이
        .background(Color.black.opacity(0.92))
    }
}

////////////////////////////////////////////////////////////
// MARK: - OCR
////////////////////////////////////////////////////////////

extension OCRResultView {
    
    func runOCR() {
        guard !isExtracting else { return }
        isExtracting = true
        
        guard let cg = image.cgImage else { return }
        
        let request = VNRecognizeTextRequest { req, _ in
            let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
            var boxes: [TextBox2] = []
            
            for obs in observations {
                guard let best = obs.topCandidates(1).first else { continue }
                boxes.append(TextBox2(text: best.string, box: obs.boundingBox))
            }
            
            boxes = sortReadingOrder(boxes)
            
            DispatchQueue.main.async {
                lineBoxes = boxes
                extractedText = boxes.map(\.text).joined(separator: "\n")
                isExtracting = false
            }
        }
        
        request.recognitionLevel = VNRequestTextRecognitionLevel.accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["ko-KR", "en-US"]
        request.minimumTextHeight = 0.02
        
        DispatchQueue.global(qos: .userInitiated).async {
            try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
        }
    }
}

////////////////////////////////////////////////////////////
// MARK: - Crop Image (Padding 포함)
////////////////////////////////////////////////////////////

extension OCRResultView {
    
    func cropImage(from visionRect: CGRect) -> UIImage? {
        
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
        
        // 🔥 약간의 padding 추가
        let padding: CGFloat = 12
        cropRect = cropRect.insetBy(dx: -padding, dy: -padding)
        cropRect = cropRect.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let croppedCG = cgImage.cropping(to: cropRect) else { return nil }
        
        return UIImage(cgImage: croppedCG)
    }
    
    func sortReadingOrder(_ boxes: [TextBox2]) -> [TextBox2] {
        let tolerance: CGFloat = 0.02
        
        return boxes.sorted { a, b in
            if abs(a.box.maxY - b.box.maxY) > tolerance {
                return a.box.maxY > b.box.maxY
            }
            return a.box.minX < b.box.minX
        }
    }
}

////////////////////////////////////////////////////////////
// MARK: - Rect Conversion
////////////////////////////////////////////////////////////

extension OCRResultView {
    
    func convertVisionRect(
        _ rect: CGRect,
        fittedRect: CGRect
    ) -> CGRect {
        
        let flipped = CGRect(
            x: rect.origin.x,
            y: 1 - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
        
        return CGRect(
            x: fittedRect.origin.x + flipped.origin.x * fittedRect.width,
            y: fittedRect.origin.y + flipped.origin.y * fittedRect.height,
            width: flipped.width * fittedRect.width,
            height: flipped.height * fittedRect.height
        )
    }
}

struct TextBox2 {
    let text: String
    let box: CGRect
}
