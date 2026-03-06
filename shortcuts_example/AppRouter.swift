//
//  AppRoute.swift
//  shortcuts_example
//
//  Created by meee on 2/23/26.
//

import SwiftUI
import Combine

final class AppRouter: ObservableObject {
    
    @Published var route: AppRoute?
}

enum AppRoute: Hashable {
    case documentScanning
    case OCRResult(image: UIImage)
}
