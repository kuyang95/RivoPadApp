//
//  shortcuts_exampleApp.swift
//  shortcuts_example
//
//  Created by meee on 1/30/26.
//
import SwiftUI

@main
struct shortcuts_exampleApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var shortcutRouter = ShortcutRouter()
    @StateObject private var appRouter = AppRouter()
    @StateObject private var rivoRemoteManager =
        RivoRemoteManager()
    @StateObject private var rivoRemoteControlCenter =
        RivoRemoteControlCenter()
    @StateObject private var visionLinkManager =
        VisionLinkManager()

    @State private var path = NavigationPath()   // ✅ App이 path 관리
    @State private var didHandleDirectScannerLaunch = false

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
                        case .chatHistory:
                            ChatHistoryView()
                        case .localChat(let conversationID):
                            LLMContentView(
                                intent: .textChat(
                                    conversationID: conversationID
                                )
                            )
                        case .localDocument(let fileURL):
                            LocalDocumentView(fileURL: fileURL)
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
                        case .readerLibrary:
                            ReaderLibraryView()
                        case .epubReader(let fileURL):
                            EPUBReaderView(fileURL: fileURL)
                        case .rivoRemote:
                            RivoRemoteView()
                        case .visionLink:
                            VisionLinkView()
                        case .cameraTools:
                            CameraToolsView()
                        case .magnifier:
                            MagnifierView(mode: .magnifier)
                                .toolbar(
                                    .hidden,
                                    for: .navigationBar
                                )
                                .ignoresSafeArea()
                        case .liveTextReader:
                            MagnifierView(mode: .liveTextReader)
                                .toolbar(
                                    .hidden,
                                    for: .navigationBar
                                )
                                .ignoresSafeArea()
                        case .documentScanning:
                            DocumentScanRootView()
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
                            
                        case .imageQA(url: let url, question: let question, token: _):
                            LLMContentView(intent: .imageAnalysis(imageURL: url, question: question))
                            
                        case .importImage:
                            DocumentScanRootView()
                            
                        case .documentScanning:
                            DocumentScanRootView()
                            
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
            .environmentObject(appRouter)
            .environmentObject(rivoRemoteManager)
            .environmentObject(visionLinkManager)
            .overlay {
                if rivoRemoteControlCenter.isMenuPresented {
                    RivoQuickMenuOverlay(
                        controlCenter: rivoRemoteControlCenter,
                        onCommand: performRivoRemoteCommand
                    )
                }
            }
            .animation(
                .easeInOut(duration: 0.2),
                value:
                    rivoRemoteControlCenter.isMenuPresented
            )
            .task {
                openScannerFromLaunchArgumentsIfNeeded()
            }
          //  .onAppear { router.consumeLastIfNeeded() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                   //  UIApplication.shared.isIdleTimerDisabled = true
                    shortcutRouter.consumeLastIfNeeded() }
            }
            .onChange(of: shortcutRouter.intentEvent) { _, dest in
                guard let dest else { return }

                // (선택) 항상 Home부터 시작하고 싶으면:
                // path = NavigationPath()

                path.append(dest)          // ✅ App이 push 처리
                shortcutRouter.intentEvent = nil   // ✅ 이벤트 소비
            }
            .onChange(of: appRouter.route) { _, route in
                guard let route else { return }
                path.append(route)
                appRouter.route = nil
            }
            .onChange(
                of: rivoRemoteManager.eventSequence
            ) { _, _ in
                guard let input =
                        rivoRemoteManager.lastInput else {
                    return
                }
                if let command =
                    rivoRemoteControlCenter.receive(input) {
                    performRivoRemoteCommand(command)
                }
            }
            
        }.environment(\.font, .custom("NanumSquareRoundOTFEB", size: 16))
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
            case .magnifier:
                route = .magnifier
            case .liveTextReader:
                route = .liveTextReader
            case .scanner:
                route = .documentScanning
            case .remoteSettings:
                route = .rivoRemote
            }
            path = NavigationPath()
            path.append(route)
        }
    }
}
