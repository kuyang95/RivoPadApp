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
    case help
    case chatHistory
    case localChat(conversationID: UUID?)
    case translation(
        initialText: String?,
        automaticallyStarts: Bool = false
    )
    case webQuestion(
        initialURL: String?,
        autoLoad: Bool
    )
    case sharedWebQuestion(
        initialURL: String,
        automaticallyStartsVoiceInput:
            Bool
    )
    case webSearch(
        initialQuery: String?,
        autoSearch: Bool,
        speaksAnswer: Bool
    )
    case webPageQuestion(
        content: WebPageContent,
        question: String
    )
    case webSearchQuestion(
        response: WebSearchResponse,
        question: String,
        speaksResponse: Bool
    )
    case voiceQuestion(question: String)
    case sharedTextQuestion(
        text: String,
        automaticallyStartsVoiceInput:
            Bool
    )
    case sharedAttachmentQuestion(
        attachment:
            StoredChatFileAttachment,
        automaticallyStartsVoiceInput:
            Bool
    )
    case voiceAction
    case sharedInbox
    case documentLibrary
    case localDocument(fileURL: URL)
    case localTextDocument(
        title: String,
        text: String
    )
    case documentQuestion(document: String, question: String)
    case readerLibrary
    case epubReader(fileURL: URL)
    case rivoRemote
    case visionLink
    case cameraTools
    case magnifier
    case liveTextReader
    case imageDescriptionCamera
    case capturedImageAnalysis(
        image: UIImage,
        question: String
    )
    case documentScanning
    case OCRResult(image: UIImage)
}
