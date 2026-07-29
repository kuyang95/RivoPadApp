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

            ScrollView {
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
                        appRouter.route = .rivoRemote
                    } label: {
                        Text("리모컨")
                            .font(.system(size: 56, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: 520)
                            .frame(height: 120)
                            .background(Color.orange)
                            .cornerRadius(28)
                    }
                    .accessibilityHint(
                        "Rivo Three 또는 Mini를 검색하고 연결합니다."
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
