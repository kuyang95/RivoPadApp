////
////  OCRPreviewLayerView.swift
////  shortcuts_example
////
////  Created by meee on 3/4/26.
////
//
//import SwiftUI
//
//struct OCRPreviewLayerView: View {
//
//    @ObservedObject var controller: OCRPreviewController
//
//    var isPreviewImageEnabled: Bool
//
//    var body: some View {
//
//        ZStack {
//
//            textPreview
//
//            if isPreviewImageEnabled,
//               let img = controller.previewCroppedImage {
//
//                imagePreview(img)
//            }
//        }
//    }
//}
//
//extension OCRPreviewLayerView {
//
//    var textPreview: some View {
//
//        HStack {
//
//            if controller.textPreviewOnLeft {
//
//                textPanel
//
//                Spacer()
//
//            } else {
//
//                Spacer()
//
//                textPanel
//            }
//        }
//    }
//
//    var textPanel: some View {
//
//        Text(controller.previewText ?? "")
//            .font(.system(size: 60, weight: .bold))
//            .foregroundColor(.white)
//            .padding(30)
//            .frame(width: UIScreen.main.bounds.width * 0.5)
//            .frame(maxHeight: .infinity, alignment: .topLeading)
//            .background(Color.black.opacity(0.92))
//    }
//}
//
//extension OCRPreviewLayerView {
//
//    func imagePreview(_ image: UIImage) -> some View {
//
//        VStack {
//
//            if controller.imagePreviewOnTop {
//
//                imageView(image)
//
//                Spacer()
//
//            } else {
//
//                Spacer()
//
//                imageView(image)
//            }
//        }
//    }
//
//    func imageView(_ image: UIImage) -> some View {
//
//        Image(uiImage: image)
//            .resizable()
//            .scaledToFit()
//            .frame(height: UIScreen.main.bounds.height * 0.35)
//            .background(Color.black)
//    }
//}
