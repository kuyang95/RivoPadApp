import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct HomeView: View {
    @EnvironmentObject var appRouter: AppRouter
    @EnvironmentObject private var rivoRemoteManager:
        RivoRemoteManager
    @State private var isFileImporterPresented = false
    @State private var fileImportError: String?
    
    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    rivoConnectionStatus

                    Button {
                        appRouter.route = .chatHistory
                    } label: {
                        Text("AI 채팅")
                            .font(.system(size: 56, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: 520)
                            .frame(height: 120)
                            .background(Color.indigo)
                            .cornerRadius(28)
                    }
                    .accessibilityHint(
                        "저장된 대화를 보거나 새 로컬 AI 대화를 시작합니다."
                    )

                    Button {
                        appRouter.route = .readerLibrary
                    } label: {
                        Text("독서")
                            .font(.system(size: 56, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: 520)
                            .frame(height: 120)
                            .background(Color.green)
                            .cornerRadius(28)
                    }
                    .accessibilityHint(
                        "EPUB 책을 열거나 마지막 책을 이어서 읽습니다."
                    )

                    Button {
                        appRouter.route = .cameraTools
                    } label: {
                        Text("카메라")
                            .font(.system(size: 56, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: 520)
                            .frame(height: 120)
                            .background(Color.black)
                            .cornerRadius(28)
                    }
                    .accessibilityHint(
                        "카메라 돋보기 또는 문서 스캐너를 선택합니다."
                    )

                    Button {
                        appRouter.route = .visionLink
                    } label: {
                        Text("VisionLink")
                            .font(.system(size: 56, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: 520)
                            .frame(height: 120)
                            .background(Color.teal)
                            .cornerRadius(28)
                    }
                    .accessibilityHint(
                        "다른 기기의 VisionLink와 연결합니다."
                    )

                    Button {
                        isFileImporterPresented = true
                    } label: {
                        Text("파일")
                            .font(.system(size: 56, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: 520)
                            .frame(height: 120)
                            .background(Color.black)
                            .cornerRadius(28)
                    }
                    .accessibilityHint(
                        "이미지, PDF, 텍스트 또는 EPUB 파일을 엽니다."
                    )
                }
                .padding(32)
                .frame(maxWidth: .infinity)
            }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [
                .image,
                .pdf,
                .plainText,
                UTType(filenameExtension: "epub") ?? .data
            ],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .alert(
            "파일을 열 수 없습니다",
            isPresented: Binding(
                get: { fileImportError != nil },
                set: { isPresented in
                    if !isPresented {
                        fileImportError = nil
                    }
                }
            )
        ) {
            Button("확인", role: .cancel) {
                fileImportError = nil
            }
        } message: {
            Text(fileImportError ?? "")
        }
        .onChange(
            of: appRouter.fileImportRequestID
        ) { oldValue, newValue in
            guard newValue != oldValue else {
                return
            }
            isFileImporterPresented = true
        }
    }

    private var rivoConnectionStatus: some View {
        Button {
            appRouter.route = .rivoRemote
        } label: {
            HStack(spacing: 14) {
                if isRivoTransitioning {
                    ProgressView()
                        .tint(rivoStatusColor)
                } else {
                    Image(systemName: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(rivoStatusColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Rivo 리모컨")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(rivoHomeStatusTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: 520)
            .frame(height: 68)
            .background(Color.secondary.opacity(0.09))
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Rivo 리모컨, \(rivoHomeStatusTitle)"
        )
        .accessibilityHint("연결 관리 화면을 엽니다.")
    }

    private var rivoHomeStatusTitle: String {
        switch rivoRemoteManager.state {
        case .inactive:
            return "연결 안 됨"
        default:
            return rivoRemoteManager.state.title
        }
    }

    private var rivoStatusColor: Color {
        switch rivoRemoteManager.state {
        case .ready:
            return .green
        case .permissionDenied,
             .unsupported,
             .bluetoothOff,
             .failed:
            return .red
        case .preparing,
             .scanning,
             .connecting,
             .discovering:
            return .orange
        case .inactive,
             .disconnected:
            return .secondary
        }
    }

    private var isRivoTransitioning: Bool {
        switch rivoRemoteManager.state {
        case .preparing,
             .scanning,
             .connecting,
             .discovering:
            return true
        default:
            return false
        }
    }

    private func handleFileImport(
        _ result: Result<[URL], Error>
    ) {
        Task {
            do {
                guard let sourceURL = try result.get().first else {
                    return
                }
                let contentType = try sourceURL.resourceValues(
                    forKeys: [.contentTypeKey]
                ).contentType
                    ?? UTType(
                        filenameExtension: sourceURL.pathExtension
                    )

                if sourceURL.pathExtension.lowercased() == "epub" {
                    let bookURL = try await EPUBLibraryStore.shared
                        .importBook(from: sourceURL)
                    EPUBProgressStore.lastBookURL = bookURL
                    appRouter.route = .epubReader(
                        fileURL: bookURL
                    )
                } else if contentType?.conforms(to: .image) == true {
                    let didAccess = sourceURL
                        .startAccessingSecurityScopedResource()
                    defer {
                        if didAccess {
                            sourceURL
                                .stopAccessingSecurityScopedResource()
                        }
                    }
                    let data = try Data(contentsOf: sourceURL)
                    guard let image = UIImage(data: data) else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    appRouter.route = .OCRResult(image: image)
                } else {
                    let importedURL = try await
                        LocalDocumentImportService.shared
                        .importDocument(from: sourceURL)
                    appRouter.route = .localDocument(
                        fileURL: importedURL
                    )
                }
            } catch {
                fileImportError = error.localizedDescription
            }
        }
    }
}
