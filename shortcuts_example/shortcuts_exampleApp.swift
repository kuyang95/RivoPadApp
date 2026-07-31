//
//  shortcuts_exampleApp.swift
//  shortcuts_example
//
//  Created by meee on 1/30/26.
//
import SwiftUI
import UniformTypeIdentifiers
import UIKit

@main
struct shortcuts_exampleApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appSettings =
        AppSettingsStore.shared
    @StateObject private var appFonts =
        AppFontCatalogStore.shared
    @StateObject private var shortcutRouter = ShortcutRouter()
    @StateObject private var appRouter = AppRouter()
    @StateObject private var rivoRemoteManager =
        RivoRemoteManager()
    @StateObject private var rivoButtonGestureInterpreter =
        RivoButtonGestureInterpreter()
    @StateObject private var rivoRemoteControlCenter =
        RivoRemoteControlCenter()
    @StateObject private var rivoScreenRemoteControlCenter =
        RivoScreenRemoteControlCenter()
    @StateObject private var visionLinkManager =
        VisionLinkManager()

    @State private var path = NavigationPath()   // ✅ App이 path 관리
    @State private var didHandleDirectScannerLaunch = false
    @State private var isConsumingSharedInbox = false
    @State private var sharedInboxError: String?

    init() {
        //UIApplication.shared.isIdleTimerDisabled = true

        guard ProcessInfo.processInfo.environment[
            "XCTestConfigurationFilePath"
        ] == nil else {
            return
        }
        AppBootstrap.prepareAppGroup()
        _ = TTSManager.shared
        _ = SoundEffectManager.shared
        SoundEffectManager.shared.preloadAll()
        AppAudioManager.shared.configure()
       }
    
    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $path) {
                HomeView()
                    .environmentObject(shortcutRouter)
                    .navigationDestination(for: AppRoute.self) { event in
                        switch event {
                        case .settings:
                            AppSettingsView()
                        case .help:
                            HelpCenterView(
                                language:
                                    appSettings
                                    .appLanguage
                            )
                        case .chatHistory:
                            ChatHistoryView()
                        case .localChat(let conversationID):
                            LLMContentView(
                                intent: .textChat(
                                    conversationID: conversationID
                                )
                            )
                            .onAppear {
                                rivoScreenRemoteControlCenter
                                    .activate(.localAIChat)
                            }
                            .onDisappear {
                                rivoScreenRemoteControlCenter
                                    .deactivate(.localAIChat)
                            }
                        case .translation(
                            let initialText,
                            let automaticallyStarts
                        ):
                            TranslationView(
                                initialText:
                                    initialText,
                                automaticallyStarts:
                                    automaticallyStarts
                            )
                        case .webQuestion(
                            let initialURL,
                            let autoLoad
                        ):
                            WebQuestionView(
                                initialURL:
                                    initialURL,
                                autoLoad:
                                    autoLoad
                            )
                        case .webSearch(
                            let initialQuery,
                            let autoSearch,
                            let speaksAnswer
                        ):
                            WebSearchView(
                                initialQuery:
                                    initialQuery,
                                autoSearch:
                                    autoSearch,
                                speaksAnswer:
                                    speaksAnswer
                            )
                        case .webPageQuestion(
                            let content,
                            let question
                        ):
                            LLMContentView(
                                intent:
                                    .webPageQA(
                                        content:
                                            content,
                                        question:
                                            question
                                    )
                            )
                            .onAppear {
                                rivoScreenRemoteControlCenter
                                    .activate(
                                        .localAIChat
                                    )
                            }
                            .onDisappear {
                                rivoScreenRemoteControlCenter
                                    .deactivate(
                                        .localAIChat
                                    )
                            }
                        case .webSearchQuestion(
                            let response,
                            let question,
                            let speaksResponse
                        ):
                            LLMContentView(
                                intent:
                                    .webSearchQA(
                                        response:
                                            response,
                                        question:
                                            question,
                                        speaksResponse:
                                            speaksResponse
                                    )
                            )
                            .onAppear {
                                rivoScreenRemoteControlCenter
                                    .activate(
                                        .localAIChat
                                    )
                            }
                            .onDisappear {
                                rivoScreenRemoteControlCenter
                                    .deactivate(
                                        .localAIChat
                                    )
                            }
                        case .voiceQuestion(let question):
                            LLMContentView(
                                intent: .voiceQuestion(
                                    question: question
                                )
                            )
                            .onAppear {
                                rivoScreenRemoteControlCenter
                                    .activate(.localAIChat)
                            }
                            .onDisappear {
                                rivoScreenRemoteControlCenter
                                    .deactivate(.localAIChat)
                            }
                        case .sharedTextQuestion(
                            let text,
                            let automaticallyStartsVoiceInput
                        ):
                            LLMContentView(
                                intent: .sharedTextQuestion(
                                    text: text,
                                    automaticallyStartsVoiceInput:
                                        automaticallyStartsVoiceInput
                                )
                            )
                            .onAppear {
                                rivoScreenRemoteControlCenter
                                    .activate(.localAIChat)
                            }
                            .onDisappear {
                                rivoScreenRemoteControlCenter
                                    .deactivate(.localAIChat)
                            }
                        case .voiceAction:
                            LocalVoiceActionView(
                                onRoute: {
                                    replaceNavigation(
                                        with: $0
                                    )
                                },
                                onFileImport: {
                                    path = NavigationPath()
                                    Task { @MainActor in
                                        await Task.yield()
                                        appRouter
                                            .requestFileImport()
                                    }
                                },
                                onClose: {
                                    path = NavigationPath()
                                }
                            )
                            .onAppear {
                                rivoScreenRemoteControlCenter
                                    .activate(.voiceAction)
                            }
                            .onDisappear {
                                rivoScreenRemoteControlCenter
                                    .deactivate(.voiceAction)
                            }
                        case .sharedInbox:
                            SharedInboxView {
                                item in
                                await openSharedInboxItem(
                                    item
                                )
                            }
                        case .documentLibrary:
                            DocumentLibraryView()
                        case .localDocument(let fileURL):
                            LocalDocumentView(fileURL: fileURL)
                                .onAppear {
                                    rivoScreenRemoteControlCenter
                                        .activate(
                                            .localDocumentReader
                                        )
                                }
                                .onDisappear {
                                    rivoScreenRemoteControlCenter
                                        .deactivate(
                                            .localDocumentReader
                                        )
                                }
                        case .documentQuestion(
                            let document,
                            let question
                        ):
                            LLMContentView(
                                intent: .documentQA(
                                    document: document,
                                    question: question
                                )
                            )
                            .onAppear {
                                rivoScreenRemoteControlCenter
                                    .activate(.localAIChat)
                            }
                            .onDisappear {
                                rivoScreenRemoteControlCenter
                                    .deactivate(.localAIChat)
                            }
                        case .readerLibrary:
                            ReaderLibraryView()
                        case .epubReader(let fileURL):
                            EPUBReaderView(fileURL: fileURL)
                                .onAppear {
                                    rivoScreenRemoteControlCenter
                                        .activate(
                                            .publicationReader
                                        )
                                }
                                .onDisappear {
                                    rivoScreenRemoteControlCenter
                                        .deactivate(
                                            .publicationReader
                                        )
                                }
                        case .rivoRemote:
                            RivoRemoteView()
                        case .visionLink:
                            VisionLinkView()
                        case .cameraTools:
                            CameraToolsView()
                        case .magnifier:
                            MagnifierView(mode: .magnifier)
                                .onAppear {
                                    rivoScreenRemoteControlCenter
                                        .activate(.magnifier)
                                }
                                .onDisappear {
                                    rivoScreenRemoteControlCenter
                                        .deactivate(.magnifier)
                                }
                                .toolbar(
                                    .hidden,
                                    for: .navigationBar
                                )
                                .ignoresSafeArea()
                        case .liveTextReader:
                            MagnifierView(mode: .liveTextReader)
                                .onAppear {
                                    rivoScreenRemoteControlCenter
                                        .activate(
                                            .liveTextReader
                                        )
                                }
                                .onDisappear {
                                    rivoScreenRemoteControlCenter
                                        .deactivate(
                                            .liveTextReader
                                        )
                                }
                                .toolbar(
                                    .hidden,
                                    for: .navigationBar
                                )
                                .ignoresSafeArea()
                        case .imageDescriptionCamera:
                            MagnifierView(
                                mode:
                                    .imageDescription
                            )
                            .onAppear {
                                rivoScreenRemoteControlCenter
                                    .activate(
                                        .magnifier
                                    )
                            }
                            .onDisappear {
                                rivoScreenRemoteControlCenter
                                    .deactivate(
                                        .magnifier
                                    )
                            }
                            .toolbar(
                                .hidden,
                                for: .navigationBar
                            )
                            .ignoresSafeArea()
                        case .capturedImageAnalysis(
                            let image,
                            let question
                        ):
                            LLMContentView(
                                intent:
                                    .capturedImageAnalysis(
                                        image:
                                            image,
                                        question:
                                            question
                                    )
                            )
                            .onAppear {
                                rivoScreenRemoteControlCenter
                                    .activate(
                                        .localAIChat
                                    )
                            }
                            .onDisappear {
                                rivoScreenRemoteControlCenter
                                    .deactivate(
                                        .localAIChat
                                    )
                            }
                        case .documentScanning:
                            DocumentScanRootView()
                                .onAppear {
                                    rivoScreenRemoteControlCenter
                                        .activate(
                                            .documentScanner
                                        )
                                }
                                .onDisappear {
                                    rivoScreenRemoteControlCenter
                                        .deactivate(
                                            .documentScanner
                                        )
                                }
                                .toolbar(.hidden, for: .navigationBar)
                                .ignoresSafeArea()
                        case .OCRResult (let image):
                            OCRResultView(image: image)
                        }
                    }
                    .navigationDestination(for: ShortcutRouter.IntentEvent.self) { event in
                        switch event {
                        case .documentQA(let document, let question, _):
                            LLMContentView(intent: .documentQA(document: document, question: question))
                                .onAppear {
                                    rivoScreenRemoteControlCenter
                                        .activate(.localAIChat)
                                }
                                .onDisappear {
                                    rivoScreenRemoteControlCenter
                                        .deactivate(.localAIChat)
                                }
                            
                        case .imageQA(url: let url, question: let question, token: _):
                            LLMContentView(intent: .imageAnalysis(imageURL: url, question: question))
                                .onAppear {
                                    rivoScreenRemoteControlCenter
                                        .activate(.localAIChat)
                                }
                                .onDisappear {
                                    rivoScreenRemoteControlCenter
                                        .deactivate(.localAIChat)
                                }
                            
                        case .importImage:
                            DocumentScanRootView()
                                .onAppear {
                                    rivoScreenRemoteControlCenter
                                        .activate(
                                            .documentScanner
                                        )
                                }
                                .onDisappear {
                                    rivoScreenRemoteControlCenter
                                        .deactivate(
                                            .documentScanner
                                        )
                                }
                            
                        case .documentScanning:
                            DocumentScanRootView()
                                .onAppear {
                                    rivoScreenRemoteControlCenter
                                        .activate(
                                            .documentScanner
                                        )
                                }
                                .onDisappear {
                                    rivoScreenRemoteControlCenter
                                        .deactivate(
                                            .documentScanner
                                        )
                                }
                            
                        case .voiceQuery(image: let image, document: let document):
                         
                            if let image {
                                  let _ = RVLogger.d("무사히?2")
                                  VoiceQueryResponseView(source: .image(image))
                              } else if let document {
                                  let _ = RVLogger.d("무사히?2")
                                  VoiceQueryResponseView(source: .text(document))
                              } else {
                                  EmptyView()
                              }
                        }
                    }
               
            }
            .environmentObject(appSettings)
            .environmentObject(appRouter)
            .environmentObject(rivoRemoteManager)
            .environmentObject(
                rivoScreenRemoteControlCenter
            )
            .environmentObject(visionLinkManager)
            .overlay {
                if rivoRemoteControlCenter.isMenuPresented {
                    RivoQuickMenuOverlay(
                        controlCenter: rivoRemoteControlCenter,
                        onCommand: performRivoRemoteCommand
                    )
                } else if rivoRemoteControlCenter
                            .isCommandModeActive {
                    RivoCommandModeOverlay(
                        controlCenter:
                            rivoRemoteControlCenter
                    )
                }
            }
            .animation(
                .easeInOut(duration: 0.2),
                value:
                    rivoRemoteControlCenter.isMenuPresented
                        || rivoRemoteControlCenter
                            .isCommandModeActive
            )
            .task {
                visionLinkManager
                    .setApplicationActive(
                        scenePhase == .active
                    )
                openScannerFromLaunchArgumentsIfNeeded()
                shortcutRouter.consumeLastIfNeeded()
                consumeSharedInboxIfNeeded()
                await appFonts.prepare()
            }
            .onOpenURL { url in
                handleIncomingURL(url)
            }
          //  .onAppear { router.consumeLastIfNeeded() }
            .onChange(of: scenePhase) { _, phase in
                visionLinkManager
                    .setApplicationActive(
                        phase == .active
                    )
                if phase == .active {
                   //  UIApplication.shared.isIdleTimerDisabled = true
                    shortcutRouter.consumeLastIfNeeded()
                    consumeSharedInboxIfNeeded()
                }
            }
            .onChange(of: shortcutRouter.intentEvent) { _, dest in
                guard let dest else { return }

                // (선택) 항상 Home부터 시작하고 싶으면:
                // path = NavigationPath()

                path.append(dest)          // ✅ App이 push 처리
                shortcutRouter.intentEvent = nil   // ✅ 이벤트 소비
            }
            .onChange(
                of: shortcutRouter.appDestination
            ) { _, destination in
                guard let destination else {
                    return
                }
                openAppDestination(
                    destination
                )
                shortcutRouter.appDestination = nil
            }
            .onChange(of: appRouter.route) { _, route in
                guard let route else { return }
                path.append(route)
                appRouter.route = nil
            }
            .onReceive(
                rivoRemoteManager.$latestInputBatch
            ) { inputs in
                guard !inputs.isEmpty else {
                    return
                }
                rivoButtonGestureInterpreter
                    .receive(inputs)
            }
            .onReceive(
                rivoButtonGestureInterpreter.$latestBatch
            ) { inputs in
                for input in inputs {
                    routeRivoRemoteInput(input)
                }
            }
            .onChange(of: rivoRemoteManager.state) {
                oldState,
                newState in
                if oldState.isReady,
                   !newState.isReady {
                    rivoButtonGestureInterpreter
                        .releaseAll()
                }
            }
            .alert(
                "공유 항목을 열지 못했습니다",
                isPresented: Binding(
                    get: {
                        sharedInboxError != nil
                    },
                    set: { isPresented in
                        if !isPresented {
                            sharedInboxError = nil
                        }
                    }
                )
            ) {
                Button("확인", role: .cancel) {
                    sharedInboxError = nil
                }
            } message: {
                Text(
                    sharedInboxError
                        ?? "알 수 없는 오류입니다."
                )
            }
            
        }
        .environment(
            \.font,
            appFonts.font(
                languageCode:
                    appSettings
                    .appLanguage
                    .effectiveLanguageCode
            )
        )
        .environment(
            \.locale,
            appSettings.appLanguage.locale
        )
    }

    private func openScannerFromLaunchArgumentsIfNeeded() {
        guard !didHandleDirectScannerLaunch,
              Self.shouldOpenScanner(
                  arguments: ProcessInfo.processInfo.arguments,
                  environment: ProcessInfo.processInfo.environment
              ) else {
            return
        }
        didHandleDirectScannerLaunch = true
        path = NavigationPath()
        path.append(AppRoute.documentScanning)
    }

    private func handleIncomingURL(_ url: URL) {
        if url.scheme?.lowercased() == "rivopad",
           url.host?.lowercased()
            == "share-inbox" {
            consumeSharedInboxIfNeeded()
            return
        }
        guard let destination =
                AppDeepLinkRouter.destination(
                    for: url
                ) else {
            return
        }
        openAppDestination(destination)
    }

    private func openAppDestination(
        _ destination:
            AppDeepLinkDestination
    ) {
        let route: AppRoute
        switch destination {
        case .settings:
            route = .settings
        case .ai:
            route = .chatHistory
        case .aiNew:
            route = .localChat(
                conversationID: nil
            )
        case .aiHistory:
            route = .chatHistory
        case .reader:
            route = .readerLibrary
        case .camera:
            route = .cameraTools
        case .magnifier:
            route = .magnifier
        case .liveText:
            route = .liveTextReader
        case .voiceAction:
            route = .voiceAction
        case .scanner:
            route = .documentScanning
        case .files:
            route = .documentLibrary
        case .rivo:
            route = .rivoRemote
        case .visionLink:
            route = .visionLink
        }
        replaceNavigation(with: route)
    }

    private func consumeSharedInboxIfNeeded() {
        guard !isConsumingSharedInbox else {
            return
        }
        isConsumingSharedInbox = true
        Task { @MainActor in
            defer {
                isConsumingSharedInbox = false
            }
            do {
                let items = try
                        SharedInboxStore.shared
                        .pendingItems()
                guard let item = items.first
                else {
                    return
                }
                if items.count > 1 {
                    replaceNavigation(
                        with: .sharedInbox
                    )
                    return
                }
                let route = try await route(
                    for: item
                )
                try SharedInboxStore.shared
                    .remove(item)
                replaceNavigation(with: route)
            } catch {
                sharedInboxError =
                    error.localizedDescription
            }
        }
    }

    private func openSharedInboxItem(
        _ item: SharedInboxItem
    ) async -> Bool {
        do {
            let destination =
                try await route(
                    for: item
                )
            try SharedInboxStore.shared
                .remove(item)
            path = NavigationPath()
            path.append(
                AppRoute.sharedInbox
            )
            path.append(destination)
            return true
        } catch {
            sharedInboxError =
                error.localizedDescription
            return false
        }
    }

    private func route(
        for item: SharedInboxItem
    ) async throws -> AppRoute {
        switch item.kind {
        case .text:
            guard let text = item.text?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
            !text.isEmpty else {
                throw SharedInboxStoreError
                    .emptyText
            }
            if let url =
                    WebURLInputParser
                    .firstWebURL(
                        in: text
                    ) {
                return .webQuestion(
                    initialURL:
                        url.absoluteString,
                    autoLoad: true
                )
            }
            guard let plan =
                    SharedTextEntryPlan.make(
                        rawText: text,
                        mode:
                            appSettings
                            .sharedTextEntryMode
                    ) else {
                throw SharedInboxStoreError
                    .emptyText
            }
            return .sharedTextQuestion(
                text: plan.text,
                automaticallyStartsVoiceInput:
                    plan
                    .automaticallyStartsVoiceInput
            )
        case .image:
            let url = try SharedInboxStore
                .shared.payloadURL(for: item)
            let data = try Data(contentsOf: url)
            guard let image = UIImage(data: data) else {
                throw CocoaError(
                    .fileReadCorruptFile
                )
            }
            return .OCRResult(image: image)
        case .file:
            let url = try SharedInboxStore
                .shared.payloadURL(for: item)
            let contentType = UTType(
                item.typeIdentifier ?? ""
            )
                ?? UTType(
                    filenameExtension:
                        url.pathExtension
                )
            if contentType?
                .conforms(to: .image) == true {
                let data = try Data(
                    contentsOf: url
                )
                guard let image =
                        UIImage(data: data) else {
                    throw CocoaError(
                        .fileReadCorruptFile
                    )
                }
                return .OCRResult(image: image)
            }
            if url.pathExtension
                .lowercased() == "epub" {
                let bookURL = try await
                    EPUBLibraryStore.shared
                    .importBook(from: url)
                EPUBProgressStore.lastBookURL =
                    bookURL
                return .epubReader(
                    fileURL: bookURL
                )
            }
            let importedURL = try await
                LocalDocumentImportService.shared
                .importDocument(from: url)
            return .localDocument(
                fileURL: importedURL
            )
        }
    }

    static func shouldOpenScanner(
        arguments: [String],
        environment: [String: String]
    ) -> Bool {
        guard environment["XCTestConfigurationFilePath"] == nil else {
            return false
        }
        if arguments.contains("--scanner-open-scanner") {
            return true
        }
        guard let index = arguments.firstIndex(of: "-ScannerOpenScanner"),
              arguments.indices.contains(index + 1) else {
            return false
        }
        return arguments[index + 1] != "0"
    }

    private func performRivoRemoteCommand(
        _ command: RivoRemoteCommand
    ) {
        switch command {
        case .startVoiceAction:
            replaceNavigation(with: .voiceAction)
        case .stopSpeech:
            TTSManager.shared.stop()
        case .home:
            path = NavigationPath()
        case .navigate(let destination):
            let route: AppRoute
            switch destination {
            case .aiChat:
                route = .localChat(conversationID: nil)
            case .reader:
                route = .readerLibrary
            case .translation:
                let clipboardText =
                    UIPasteboard
                    .general.string?
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )
                route = .translation(
                    initialText:
                        clipboardText?
                        .isEmpty == false
                        ? clipboardText
                        : nil,
                    automaticallyStarts:
                        clipboardText?
                        .isEmpty == false
                )
            case .magnifier:
                route = .magnifier
            case .liveTextReader:
                route = .liveTextReader
            case .imageDescription:
                route =
                    .imageDescriptionCamera
            case .scanner:
                route = .documentScanning
            case .remoteSettings:
                route = .rivoRemote
            }
            path = NavigationPath()
            path.append(route)
        }
    }

    private func routeRivoRemoteInput(
        _ input: RivoRemoteInput
    ) {
        if RivoScreenInputPriorityPolicy
            .shouldOfferToScreenFirst(
                input,
                isMenuPresented:
                    rivoRemoteControlCenter
                    .isMenuPresented
            ),
        rivoScreenRemoteControlCenter
            .receivePriorityInput(input) {
            return
        }
        let decision =
            rivoRemoteControlCenter
                .receiveDecision(input)
        if let command = decision.command {
            performRivoRemoteCommand(command)
        }
        if !decision.consumed {
            rivoScreenRemoteControlCenter
                .receive(input)
        }
    }

    private func replaceNavigation(
        with route: AppRoute
    ) {
        path = NavigationPath()
        path.append(route)
    }
}
