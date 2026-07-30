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
    @Published private(set) var fileImportRequestID:
        UInt64 = 0

    func requestFileImport() {
        fileImportRequestID &+= 1
    }
}

enum AppRoute: Hashable {
    case settings
    case chatHistory
    case localChat(conversationID: UUID?)
    case voiceQuestion(question: String)
    case voiceAction
    case localDocument(fileURL: URL)
    case documentQuestion(document: String, question: String)
    case readerLibrary
    case epubReader(fileURL: URL)
    case rivoRemote
    case visionLink
    case cameraTools
    case magnifier
    case liveTextReader
    case documentScanning
    case OCRResult(image: UIImage)
}
