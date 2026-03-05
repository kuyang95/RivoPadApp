//
//  DocumentScanRootView.swift
//  shortcuts_example
//
//  Created by meee on 2/4/26.
//

import SwiftUI
import UIKit

struct DocumentScanRootView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let root = RootViewController()
        let nav = UINavigationController(rootViewController: root)
        return nav
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // 업데이트 필요 없음
    }
}
