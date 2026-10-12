import SwiftUI
import UIKit

/// Android `VcCamStatusOverlay`: 글자색 88% 면(`VisionCraftUI.overlay`), 모서리 14,
/// 17pt Bold, 글자는 배경색. 진행 상태·안내를 사진 위 가운데에 띄운다(라이브 영역).
struct VisionCraftCameraStatusBand: View {
    let text: String
    var isLive = true

    var body: some View {
        Text(text)
            .visionCraftAndroidText(17, weight: .bold, relativeTo: .headline)
            .foregroundStyle(VisionCraftUI.background)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .frame(minHeight: 56)
            .frame(maxWidth: 360)
            .background(
                VisionCraftUI.overlay,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .accessibilityAddTraits(isLive ? .updatesFrequently : [])
    }
}

/// Android `PhotoReviewActivity.ZoomablePhoto` / 문서 스캔 `setupCapturedDocZoom`:
/// 두 손가락으로 확대·이동, 두 번 탭하면 원래 크기로.
struct VisionCraftZoomablePhoto<Overlay: View>: View {
    let image: UIImage
    var maximumScale: CGFloat = 6
    var accessibilityLabel: String
    /// 사진과 함께 확대되는 겹침(예: 문서 스캔의 OCR 상자).
    @ViewBuilder var overlay: () -> Overlay

    init(
        image: UIImage,
        maximumScale: CGFloat = 6,
        accessibilityLabel: String,
        @ViewBuilder overlay: @escaping () -> Overlay = { EmptyView() }
    ) {
        self.image = image
        self.maximumScale = maximumScale
        self.accessibilityLabel = accessibilityLabel
        self.overlay = overlay
    }

    @State private var scale: CGFloat = 1
    @State private var scaleAtGestureStart: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var offsetAtGestureStart: CGSize = .zero

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .overlay { overlay() }
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        scale = min(max(scaleAtGestureStart * value.magnification, 1), maximumScale)
                    }
                    .onEnded { _ in
                        scaleAtGestureStart = scale
                        if scale == 1 {
                            offset = .zero
                            offsetAtGestureStart = .zero
                        }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        guard scale > 1 else { return }
                        offset = CGSize(
                            width: offsetAtGestureStart.width + value.translation.width,
                            height: offsetAtGestureStart.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        offsetAtGestureStart = offset
                    }
            )
            .onTapGesture(count: 2) {
                scale = 1
                scaleAtGestureStart = 1
                offset = .zero
                offsetAtGestureStart = .zero
            }
            .onChange(of: image) { _, _ in
                scale = 1
                scaleAtGestureStart = 1
                offset = .zero
                offsetAtGestureStart = .zero
            }
            .accessibilityLabel(AppLocalization.string(accessibilityLabel))
    }
}

/// 카메라 기본 모드에서 촬영해 저장한 사진을 `.photoReview` 라우트로 넘길 때 쓰는 손잡이.
/// Android `PhotoReviewActivity.createIntent(imageUri, fromCamera = true)` 의 인텐트 추가값 역할이다.
@MainActor
enum PhotoReviewHandoff {
    static var pendingCapturedImage: UIImage?

    static func take() -> UIImage? {
        defer { pendingCapturedImage = nil }
        return pendingCapturedImage
    }
}

/// Android `GeminiApiConnector.describeImage` 에 해당하는 한 번짜리 이미지 설명.
/// LLM 화면(`.capturedImageAnalysis`)이 쓰는 것과 같은 `GeminiVisionService` 경로를 쓰되
/// 화면을 옮기지 않고 결과 문자열만 돌려준다(카메라 이미지 분석 모드, 사진 분석, 문서 스캔 결과).
@MainActor
enum CameraImageDescriber {
    static func describe(_ image: UIImage) async throws -> String {
        let source = downscaled(image, maximumEdge: 2_048)
        guard let ciImage = CIImage(image: source)
                ?? source.cgImage.map({ CIImage(cgImage: $0) }) else {
            throw GeminiVisionService.ServiceError.imageEncodingFailed
        }
        let language = AppLanguage.current()
        let stream = try await GeminiVisionService.stream(
            system: LocalImageDescriptionPrompt.system(language: language),
            prompt: LocalImageDescriptionPrompt.defaultQuestion(language: language),
            images: [ciImage]
        )
        var text = ""
        for try await chunk in stream {
            text += chunk
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Android `GeminiResultState` 분기와 같은 사용자 문구.
    static func userMessage(for error: Error) -> String {
        if error is CloudAITokenBudgetError {
            return AppLocalization.string("일일 할당량이 소진되었습니다.")
        }
        let nsError = error as NSError
        if error is URLError || nsError.domain == NSURLErrorDomain {
            return AppLocalization.string("인터넷 연결을 확인해주세요.")
        }
        return AppLocalization.string("사진을 해석하지 못했어요.")
    }

    private static func downscaled(_ image: UIImage, maximumEdge: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maximumEdge, longest > 0 else { return image }
        let scale = maximumEdge / longest
        let size = CGSize(
            width: (image.size.width * scale).rounded(.down),
            height: (image.size.height * scale).rounded(.down)
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
