import SwiftUI
import Vision
import AVFoundation

struct OCRResultView: View {

    let image: UIImage

    @EnvironmentObject private var appRouter:
        AppRouter
    @StateObject private var vm = OCRResultViewModel()

    @State private var showBoxes: Bool = false

    @State private var hasActivatedPreview = false
    @State private var previewHoldWorkItem: DispatchWorkItem?
    @State private var isTouching: Bool = false

    @State private var isTTSEnabled: Bool = true
    @State private var isPreviewImageEnabled: Bool = true

    @State private var previewText: String? = nil
    @State private var lastPreviewIndex: Int? = nil
    @State private var previewCroppedImage: UIImage? = nil

    @State private var ttsWorkItem: DispatchWorkItem?

    @State private var touchQuadrant: TouchQuadrant?
    @State private var hasRequestedOCR = false

    var body: some View {
        ZStack {

            imageLayer

            if vm.isExtracting {
                ThinkingOverlayView(
                    title:
                        vm.extractionStatus,
                    activeDotIndex: vm.activeDotIndex
                )
                .transition(.opacity)
            }

            if vm.isGeneratingAI {
                ThinkingOverlayView(
                    title: "AI 답변 생성중",
                    activeDotIndex: vm.activeDotIndex
                )
                .transition(.opacity)
            }
        }
        .tint(VisionCraftUI.primary)
        .safeAreaInset(edge: .top) {
            if hasRequestedOCR,
               !vm.isExtracting {
                topBar
            }
        }
        .overlay(
            Group {
                if hasActivatedPreview {
                    previewPanel(text: previewText ?? "")
                }
            }
        )
        .onAppear {
            hasRequestedOCR = true

            if vm.extractedText.isEmpty {

                if isTTSEnabled {
                    TTSManager.shared.stop()
                    TTSManager.shared.speakFeedback(
                        "텍스트 추출중"
                    )
                }

                vm.runOCR(image: image)
            }
        }
        .onDisappear {
            Task {
                await vm.resetConversation()
            }
        }
    }
}

enum TouchQuadrant {
    case q1
    case q2
    case q3
    case q4
}

extension OCRResultView {

    private func quadrant(
        for location: CGPoint,
        imageRect: CGRect
    ) -> TouchQuadrant? {
        guard imageRect.contains(location) else { return nil }

        let localX = location.x - imageRect.origin.x
        let localY = location.y - imageRect.origin.y

        let midX = imageRect.width / 2
        let midY = imageRect.height / 2

        if localX < midX && localY < midY { return .q1 }
        if localX >= midX && localY < midY { return .q2 }
        if localX < midX && localY >= midY { return .q3 }
        return .q4
    }
}

extension OCRResultView {

    private var topBar: some View {
        ScrollView(
            .horizontal,
            showsIndicators: false
        ) {
            topBarActions
        }
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.4), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var topBarActions:
        some View
    {
        HStack(spacing: 10) {

            Button {
                openImageDescription()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.65))
                        .frame(height: 40)

                    Text(
                        AppLocalization.string(
                            "이미지 설명"
                        )
                    )
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("이미지 설명")
            .accessibilityHint(
                "원본 사진을 M4 로컬 AI로 설명하고 같은 사진에 후속 질문을 합니다."
            )
            .disabled(
                vm.isGeneratingAI
                    || vm.sttManager
                    .isRecording
            )

            Button {
                if vm.llmService.isLoading {
                    TTSManager.shared.stop()
                    TTSManager.shared.speakFeedback(
                        "모델 로딩중입니다"
                    )
                    return
                }

                SoundEffectManager.shared.play(.recording)

                Task {
                    do {
                        let stream = try await vm.sttManager.startRecording()

                        for await question in stream {
                            SoundEffectManager.shared.play(.startingLLM)

                            await vm.runDocumentQA(
                                question: question,
                                isTTSEnabled: isTTSEnabled
                            )
                        }
                    } catch {
                        print(error)
                    }
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.65))
                        .frame(height: 40)

                    if vm.llmService.isLoading {
                        ProgressView()
                            .progressViewStyle(
                                CircularProgressViewStyle(tint: .white)
                            )
                    } else {
                        Text(
                            AppLocalization.string(
                                vm.sttManager.isRecording
                                    ? "녹음중..."
                                    : "AI 질문"
                            )
                        )
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("AI 질문")
            .accessibilityValue(
                AppLocalization.string(
                    vm.llmService.isLoading
                        ? "모델 로딩 중"
                        : (
                            vm.sttManager.isRecording
                                ? "녹음 중"
                                : "준비됨"
                        )
                )
            )
            .accessibilityHint("이중 탭하면 문서에 대해 질문할 수 있습니다")
            .disabled(
                !hasExtractedText
                    || vm.isGeneratingAI
                    || vm.sttManager
                    .isRecording
            )

            Button {
                openTranslation()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.65))
                        .frame(height: 40)

                    Text(
                        AppLocalization.string(
                            "번역"
                        )
                    )
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("번역")
            .accessibilityHint(
                "추출한 텍스트를 M4 로컬 AI 번역 화면에서 바로 번역합니다."
            )
            .disabled(
                !hasExtractedText
                    || vm.isExtracting
                    || vm.isGeneratingAI
                    || vm.sttManager
                    .isRecording
            )

            Button {
                isTTSEnabled.toggle()

                if !isTTSEnabled {
                    ttsWorkItem?.cancel()
                    TTSManager.shared.stop()
                }
            } label: {
                toolbarTextButton(
                    title: "음성",
                    isOn: isTTSEnabled
                )
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("음성")
            .accessibilityValue(
                AppLocalization.string(
                    isTTSEnabled
                        ? "켜짐"
                        : "꺼짐"
                )
            )
            .accessibilityHint("이중 탭하면 음성 안내를 전환합니다")

            Button {
                isPreviewImageEnabled.toggle()
            } label: {
                toolbarTextButton(
                    title: "이미지",
                    isOn: isPreviewImageEnabled
                )
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("이미지 미리보기")
            .accessibilityValue(
                AppLocalization.string(
                    isPreviewImageEnabled
                        ? "켜짐"
                        : "꺼짐"
                )
            )
            .accessibilityHint("이중 탭하면 이미지 미리보기를 전환합니다")

            Button {
                showBoxes.toggle()
            } label: {
                toolbarTextButton(
                    title: "박스",
                    isOn: showBoxes
                )
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("OCR 박스")
            .accessibilityValue(
                AppLocalization.string(
                    showBoxes
                        ? "켜짐"
                        : "꺼짐"
                )
            )
            .accessibilityHint("이중 탭하면 텍스트 박스 표시를 전환합니다")

            Button {
                UIPasteboard.general.string = vm.extractedText
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.65))
                        .frame(height: 40)

                    Text("복사")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("복사")
            .accessibilityHint("이중 탭하면 추출한 텍스트를 클립보드에 복사합니다")
            .disabled(!hasExtractedText)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func openTranslation() {
        guard let source =
                OCRTranslationSource.make(
                    from: vm.extractedText
                ) else {
            return
        }
        ttsWorkItem?.cancel()
        previewHoldWorkItem?.cancel()
        TTSManager.shared.stop()
        appRouter.route = .translation(
            initialText: source,
            automaticallyStarts: true
        )
    }

    private var hasExtractedText:
        Bool
    {
        !vm.extractedText
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty
    }

    private func openImageDescription() {
        ttsWorkItem?.cancel()
        previewHoldWorkItem?.cancel()
        TTSManager.shared.stop()
        appRouter.route =
            .capturedImageAnalysis(
                image: image,
                question:
                    LocalImageDescriptionPrompt
                    .defaultQuestion(
                        language:
                            AppLanguage
                            .current()
                    )
            )
    }
}

nonisolated enum OCRTranslationSource {
    static func make(
        from text: String
    ) -> String? {
        guard !text
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty else {
            return nil
        }
        return text
    }
}

extension OCRResultView {

    private var imageLayer: some View {

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

                        if !isTouching {
                            isTouching = true
                            hasActivatedPreview = false
                        }

                        touchQuadrant = quadrant(
                            for: value.location,
                            imageRect: fittedRect
                        )

                        handleTouch(
                            location: value.location,
                            containerSize: geo.size,
                            fittedRect: fittedRect
                        )
                    }

                    .onEnded { _ in

                        isTouching = false
                        hasActivatedPreview = false
                        previewHoldWorkItem?.cancel()

                        // 마지막 터치 위치가 글자 박스 안이었는지 확인
                         if let idx = lastPreviewIndex {
                             let text = vm.lineBoxes[idx].text
                             UIPasteboard.general.string = text
                             UIImpactFeedbackGenerator(style: .light).impactOccurred()
                         }
                        
                        clearPreviewAndStop()
                    }
            )
        }
    }
}

extension OCRResultView {

    private func overlayBoxes(fittedRect: CGRect) -> some View {

        ForEach(vm.lineBoxes.indices, id: \.self) { index in

            let rect = convertVisionRect(
                vm.lineBoxes[index].box,
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

extension OCRResultView {

    private func previewPanel(text: String) -> some View {

        GeometryReader { geo in

            let halfW = geo.size.width / 2
            let halfH = geo.size.height / 2

            guard let touch = touchQuadrant else {
                return AnyView(EmptyView())
            }

            let showTopText = touch == .q3 || touch == .q4
            let showBottomText = touch == .q1 || touch == .q2

            let imageQuadrant: TouchQuadrant = {
                switch touch {
                case .q1: return .q2
                case .q2: return .q1
                case .q3: return .q4
                case .q4: return .q3
                }
            }()

            return AnyView(

                ZStack {

                    // MARK: TEXT PANEL (TOP)

                    if showTopText {

                        Text(text)
                            .font(.system(size: 96, weight: .bold))
                            .foregroundColor(.white)
                            .padding(24)
                            .frame(width: geo.size.width,
                                   height: halfH,
                                   alignment: .topLeading)
                            .background(Color.black.opacity(0.92))
                            .position(x: geo.size.width/2,
                                      y: halfH/2)
                    }

                    // MARK: TEXT PANEL (BOTTOM)

                    if showBottomText {

                        Text(text)
                            .font(.system(size: 96, weight: .bold))
                            .foregroundColor(.white)
                            .padding(24)
                            .frame(width: geo.size.width,
                                   height: halfH,
                                   alignment: .topLeading)
                            .background(Color.black.opacity(0.92))
                            .position(x: geo.size.width/2,
                                      y: geo.size.height - halfH/2)
                    }

                    // MARK: IMAGE PANEL

                    if isPreviewImageEnabled,
                       let img = previewCroppedImage {

                        switch imageQuadrant {

                        case .q1:

                            imagePanel(img, width: halfW, height: halfH)
                                .position(x: halfW/2,
                                          y: halfH/2)

                        case .q2:

                            imagePanel(img, width: halfW, height: halfH)
                                .position(x: geo.size.width - halfW/2,
                                          y: halfH/2)

                        case .q3:

                            imagePanel(img, width: halfW, height: halfH)
                                .position(x: halfW/2,
                                          y: geo.size.height - halfH/2)

                        case .q4:

                            imagePanel(img, width: halfW, height: halfH)
                                .position(x: geo.size.width - halfW/2,
                                          y: geo.size.height - halfH/2)
                        }
                    }
                }
            )
        }
        .ignoresSafeArea()
    }
    
    private func imagePanel(_ img: UIImage,
                            width: CGFloat,
                            height: CGFloat) -> some View {

        ZStack {

            Color.black.opacity(0.92)

            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .padding(12)
        }
        .frame(width: width, height: height)
    }

}

extension OCRResultView {

    private func toolbarTextButton(
           title: String,
           isOn: Bool
       ) -> some View {

           ZStack {

               RoundedRectangle(cornerRadius: 10)
                   .fill(Color.black.opacity(0.65))
                   .frame(height: 40)
                   .frame(minWidth: 80)

               Text(
                   AppLocalization.string(
                       title
                   )
                   + " "
                   + AppLocalization.string(
                       isOn
                           ? "켜짐"
                           : "꺼짐"
                   )
               )
                   .font(.system(size: 15, weight: .semibold))
                   .foregroundColor(.white)
                   .padding(.horizontal, 14)
           }
       }
    
    private func convertVisionRect(
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

// MARK: - Touch Handling + TTS
extension OCRResultView {

    private func handleTouch(
        location: CGPoint,
        containerSize: CGSize,
        fittedRect: CGRect
    ) {

        guard fittedRect.contains(location) else {

            previewText = nil
            previewCroppedImage = nil
            lastPreviewIndex = nil

            ttsWorkItem?.cancel()
            TTSManager.shared.stop()

            return
        }

        var hitIndex: Int? = nil
        var bestArea: CGFloat = .greatestFiniteMagnitude

        for (idx, item) in vm.lineBoxes.enumerated() {

            let rect = convertVisionRect(
                item.box,
                fittedRect: fittedRect
            )

            if rect.contains(location) {

                let area = rect.width * rect.height

                if area < bestArea {
                    bestArea = area
                    hitIndex = idx
                }
            }
        }

        guard let idx = hitIndex else {

            if hasActivatedPreview {

                previewHoldWorkItem?.cancel()

                let workItem = DispatchWorkItem {

                    if isTouching {

                        hasActivatedPreview = false
                        clearPreviewAndStop()
                    }
                }

                previewHoldWorkItem = workItem

                DispatchQueue.main.asyncAfter(
                    deadline: .now() + 1.0,
                    execute: workItem
                )
            }

            previewText = nil
            previewCroppedImage = nil
            lastPreviewIndex = nil

            ttsWorkItem?.cancel()
            TTSManager.shared.stop()

            return
        }

        if lastPreviewIndex != idx {

            hasActivatedPreview = true

            previewHoldWorkItem?.cancel()

            lastPreviewIndex = idx

            previewText = vm.lineBoxes[idx].text

            previewCroppedImage = vm.cropImage(
                from: vm.lineBoxes[idx].box,
                in: image
            )

            ttsWorkItem?.cancel()

            TTSManager.shared.stop()

            let textToSpeak = vm.lineBoxes[idx].text

            let workItem = DispatchWorkItem {

                if lastPreviewIndex == idx && isTTSEnabled {

                    TTSManager.shared.speak(textToSpeak)
                }
            }

            ttsWorkItem = workItem

            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.3,
                execute: workItem
            )
        }
    }
}

extension OCRResultView {

    private func clearPreviewAndStop() {

        previewText = nil
        previewCroppedImage = nil
        lastPreviewIndex = nil

        ttsWorkItem?.cancel()

        if TTSManager.shared.isSpeaking {

            TTSManager.shared.stop()
        }
    }
}
