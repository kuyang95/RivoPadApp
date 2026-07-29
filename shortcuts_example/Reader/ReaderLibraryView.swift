import SwiftUI
import UniformTypeIdentifiers

struct ReaderLibraryView: View {
    @EnvironmentObject private var appRouter: AppRouter
    @State private var isImporterPresented = false
    @State private var lastBookURL: URL?
    @State private var errorDescription: String?

    private var epubType: UTType {
        UTType(filenameExtension: "epub") ?? .data
    }

    var body: some View {
        List {
            Section {
                Button {
                    isImporterPresented = true
                } label: {
                    Label(
                        "EPUB 파일 열기",
                        systemImage: "plus.rectangle.on.folder"
                    )
                    .font(.title2.bold())
                    .padding(.vertical, 12)
                }
                .accessibilityHint(
                    "Files에서 EPUB 책을 가져옵니다."
                )
            }

            if let lastBookURL {
                Section("최근 책") {
                    NavigationLink(
                        value: AppRoute.epubReader(
                            fileURL: lastBookURL
                        )
                    ) {
                        Label(
                            lastBookURL.deletingPathExtension()
                                .lastPathComponent,
                            systemImage: "book.fill"
                        )
                        .font(.title3)
                        .padding(.vertical, 8)
                    }
                    .accessibilityHint(
                        "마지막으로 읽던 장부터 계속합니다."
                    )
                }
            }
        }
        .navigationTitle("독서")
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [epubType],
            allowsMultipleSelection: false
        ) { result in
            importBook(result)
        }
        .alert(
            "책을 열 수 없습니다",
            isPresented: Binding(
                get: { errorDescription != nil },
                set: { isPresented in
                    if !isPresented {
                        errorDescription = nil
                    }
                }
            )
        ) {
            Button("확인", role: .cancel) {
                errorDescription = nil
            }
        } message: {
            Text(errorDescription ?? "")
        }
        .onAppear {
            lastBookURL = EPUBProgressStore.lastBookURL
        }
    }

    private func importBook(
        _ result: Result<[URL], Error>
    ) {
        Task {
            do {
                guard let sourceURL = try result.get().first else {
                    return
                }
                let bookURL = try await EPUBLibraryStore.shared
                    .importBook(from: sourceURL)
                EPUBProgressStore.lastBookURL = bookURL
                lastBookURL = bookURL
                appRouter.route = .epubReader(fileURL: bookURL)
            } catch {
                errorDescription = error.localizedDescription
            }
        }
    }
}
