import SwiftUI
import AVFoundation
import Combine

@MainActor
final class OCRPreviewController: ObservableObject {

    // MARK: - Preview State

    @Published var previewText: String? = nil
    @Published var previewOnLeft: Bool = false
    @Published var previewCroppedImage: UIImage? = nil
    @Published var hasActivatedPreview: Bool = false

    private var lastPreviewIndex: Int? = nil
    private var previewHoldWorkItem: DispatchWorkItem?
    private var ttsWorkItem: DispatchWorkItem?

    var isTouching: Bool = false


    // MARK: - Touch Handling

    func handleTouch(
        location: CGPoint,
        containerSize: CGSize,
        fittedRect: CGRect,
        lineBoxes: [TextBox2],
        image: UIImage,
        isTTSEnabled: Bool
    ) {

        guard fittedRect.contains(location) else {
            clearPreviewAndStop()
            return
        }

        previewOnLeft = location.x > containerSize.width / 2

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

            if hasActivatedPreview {

                previewHoldWorkItem?.cancel()

                let workItem = DispatchWorkItem {

                    if self.isTouching {
                        self.hasActivatedPreview = false
                        self.clearPreviewAndStop()
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
            previewText = lineBoxes[idx].text
            previewCroppedImage = cropImage(from: lineBoxes[idx].box, in: image)

            ttsWorkItem?.cancel()
            TTSManager.shared.stop()

            let textToSpeak = lineBoxes[idx].text

            let workItem = DispatchWorkItem {

                if self.lastPreviewIndex == idx && isTTSEnabled {
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


    // MARK: - Stop Preview

    func clearPreviewAndStop() {

        previewText = nil
        previewCroppedImage = nil
        lastPreviewIndex = nil

        ttsWorkItem?.cancel()

        if TTSManager.shared.isSpeaking {
            TTSManager.shared.stop()
        }
    }


    // MARK: - Helpers

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

        cropRect = cropRect.intersection(
            CGRect(x: 0, y: 0, width: width, height: height)
        )

        guard let croppedCG = cgImage.cropping(to: cropRect) else {
            return nil
        }

        return UIImage(cgImage: croppedCG)
    }


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
