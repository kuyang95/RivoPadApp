//
//  DocumentScanRootView.swift
//  shortcuts_example
//
//  Created by meee on 2/4/26.
//

import SwiftUI
import UIKit

struct DocumentScanRootView: UIViewControllerRepresentable {

    @EnvironmentObject var appRouter: AppRouter

    func makeUIViewController(context: Context) -> DocumentScannerViewController {
        let vc = DocumentScannerViewController()

        vc.onScanCompleted = { image in
            appRouter.route = .OCRResult(image: image)
        }

        return vc
    }

    func updateUIViewController(_ uiViewController: DocumentScannerViewController, context: Context) {}
}
