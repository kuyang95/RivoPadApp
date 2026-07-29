import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct HomeView: View {
    @EnvironmentObject var appRouter: AppRouter
    @State private var isFileImporterPresented = false
    @State private var fileImportError: String?
    
    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()
            
            VStack(spacing: 32) {
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
                    appRouter.route = .documentScanning
                } label: {
                    Text("카메라")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: 520)
                        .frame(height: 120)
                        .background(Color.black)
                        .cornerRadius(28)
                }
                
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
                    "이미지, PDF 또는 텍스트 파일을 엽니다."
                )
            }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.image, .pdf, .plainText],
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

                if contentType?.conforms(to: .image) == true {
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
