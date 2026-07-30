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
                            .onAppear {
                                rivoScreenRemoteControlCenter
                                    .activate(.localAIChat)
                            }
                            .onDisappear {
                                rivoScreenRemoteControlCenter
                                    .deactivate(.localAIChat)
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

    private func routeRivoRemoteInput(
        _ input: RivoRemoteInput
    ) {
        guard !rivoScreenRemoteControlCenter
            .receivePriorityInput(input) else {
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
