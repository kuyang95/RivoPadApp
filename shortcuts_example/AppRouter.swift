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
    case chatHistory
    case localChat(conversationID: UUID?)
    case localDocument(fileURL: URL)
    case documentQuestion(document: String, question: String)
    case cameraTools
    case magnifier
    case liveTextReader
    case documentScanning
    case OCRResult(image: UIImage)
}
