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
    @EnvironmentObject private var remoteControl:
        RivoScreenRemoteControlCenter
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> DocumentScannerViewController {
        let vc = DocumentScannerViewController()

        vc.onScanCompleted = { image in
            appRouter.route = .OCRResult(image: image)
        }
        vc.onCancel = {
            dismiss()
        }
        vc.synchronizeRemoteEventCursor(
            to: remoteControl.latestEvent?.id
        )

        return vc
    }

    func updateUIViewController(
        _ uiViewController: DocumentScannerViewController,
        context: Context
    ) {
        guard let event = remoteControl.latestEvent,
              case .documentScanner(let action) =
                event.action else {
            return
        }
        uiViewController.performRemoteAction(
            action,
            eventID: event.id
        )
    }
}
