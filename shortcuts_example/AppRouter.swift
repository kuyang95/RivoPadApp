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
    @Published private(set) var textSourceRequestID:
        UInt64 = 0

    func requestFileImport() {
        fileImportRequestID &+= 1
    }

    func requestTextSource() {
        textSourceRequestID &+= 1
    }
}

enum AppRoute: Hashable {
    case settings
    /// 홈 제목 줄의 설정 아이콘 → 전체 설정 화면(Android `AllSettingsScreen`).
    case allSettings
    /// 홈 업데이트 기록 카드의 "이전 업데이트 기록보기"(Android `FullChangeLogsScreen`).
    case releaseNotes
    case help
    case chatHistory
    case aiDocument
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
    case originalDocument(documentID: UUID)
    case localTextDocument(
        title: String,
        text: String
    )
    case imageTextDocument(image: UIImage)
    case textEditorDocument(fileURL: URL)
    case textEditorText(
        title: String,
        text: String
    )
    case textEditorImage(image: UIImage)
    case documentQuestion(document: String, question: String)
    case readerLibrary
    case epubReader(fileURL: URL)
    case rivoRemote
    case visionLink
    case magnifier
    case liveTextReader
    case imageDescriptionCamera
    case cameraAskAI
    case photoReview
    /// 홈 "이미지 분석 > 사진에서": 사진을 고르면 바로 설명한다(Android `ImageAnalysisActivity`).
    case imageAnalysisPhoto
    case capturedImageAnalysis(
        image: UIImage,
        question: String
    )
    case documentScanning
    case OCRResult(image: UIImage)
}
