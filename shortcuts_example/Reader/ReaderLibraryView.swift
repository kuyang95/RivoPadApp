import SwiftUI
import UniformTypeIdentifiers

struct ReaderLibraryView: View {
    @EnvironmentObject private var appRouter: AppRouter
    @State private var isImporterPresented = false
    @State private var isImporting = false
    @State private var books: [EPUBLibraryBook] = []
    @State private var isLoading = true
    @State private var bookToDelete:
        EPUBLibraryBook?
    @State private var errorDescription: String?
    @State private var statusDescription: String?

    private var supportedBookTypes: [UTType] {
        let epub =
            UTType(filenameExtension: "epub")
            ?? .data
        return [epub, .zip]
    }

    var body: some View {
        List {
            Section {
                Button {
                    isImporterPresented = true
                } label: {
                    Group {
                        if isImporting {
                            ProgressView(
                                "책 확인하고 가져오는 중"
                            )
                        } else {
                            Label(
                                "EPUB·DAISY 파일 열기",
                                systemImage: "plus.rectangle.on.folder"
                            )
                        }
                    }
                    .font(.title2.bold())
                    .padding(.vertical, 12)
                }
                .disabled(isImporting)
                .accessibilityHint(
                    "Files에서 EPUB 또는 ZIP 형식의 DAISY 책을 가져옵니다."
                )
            }

            if let statusDescription {
                Section {
                    HStack(
                        alignment: .firstTextBaseline,
                        spacing: 12
                    ) {
                        Label(
                            statusDescription,
                            systemImage:
                                "checkmark.circle.fill"
                        )
                        .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            self.statusDescription =
                                nil
                        } label: {
                            Image(
                                systemName: "xmark.circle"
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("알림 닫기")
                    }
                }
            }

            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("서재 불러오는 중")
                        Spacer()
                    }
                }
            } else if books.isEmpty {
                Section("내 서재") {
                    ContentUnavailableView(
                        "가져온 책이 없습니다",
                        systemImage: "books.vertical",
                        description: Text(
                            "EPUB·DAISY 파일을 가져오면 이 iPad에 보관됩니다."
                        )
                    )
                }
            } else {
                Section {
                    ForEach(books) { book in
                        bookLink(book)
                    }
                } header: {
                    HStack {
                        Text("내 서재")
                        Spacer()
                        Text(
                            String(
                                localized:
                                    "책 \(books.count)권"
                            )
                        )
                        .textCase(nil)
                    }
                }
            }
        }
        .navigationTitle("독서")
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes:
                supportedBookTypes,
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
        .confirmationDialog(
            "책 삭제",
            isPresented: Binding(
                get: {
                    bookToDelete != nil
                },
                set: { isPresented in
                    if !isPresented {
                        bookToDelete = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: bookToDelete
        ) { book in
            Button(
                String(
                    localized:
                        "\"\(book.title)\" 삭제"
                ),
                role: .destructive
            ) {
                deleteBook(book)
            }
            Button("취소", role: .cancel) {
                bookToDelete = nil
            }
        } message: { book in
            Text(
                String(
                    localized:
                        "\"\(book.title)\" 책을 이 iPad의 서재에서 삭제할까요? 원본 파일은 삭제되지 않습니다."
                )
            )
        }
        .onAppear {
            reloadBooks()
        }
    }

    private func bookLink(
        _ book: EPUBLibraryBook
    ) -> some View {
        NavigationLink(
            value: AppRoute.epubReader(
                fileURL: book.fileURL
            )
        ) {
            HStack(spacing: 14) {
                Image(
                    systemName:
                        book.fileURL.pathExtension
                            .lowercased() == "epub"
                        ? "book.closed.fill"
                        : "waveform.badge.plus"
                )
                .font(.title2)
                .frame(width: 32)
                .foregroundStyle(
                    Color.accentColor
                )

                VStack(
                    alignment: .leading,
                    spacing: 5
                ) {
                    Text(book.title)
                        .font(.headline)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Text(book.formatDescription)
                        if isLastBook(book) {
                            Label(
                                "최근 읽음",
                                systemImage: "clock.fill"
                            )
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    Text(book.activityDate, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 7)
        }
        .accessibilityHint(
            isLastBook(book)
                ? "마지막으로 읽던 위치부터 계속합니다."
                : "저장된 읽기 위치부터 책을 엽니다."
        )
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                bookToDelete = book
            } label: {
                Label(
                    "삭제",
                    systemImage: "trash"
                )
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                bookToDelete = book
            } label: {
                Label(
                    "서재에서 삭제",
                    systemImage: "trash"
                )
            }
        }
    }

    private func isLastBook(
        _ book: EPUBLibraryBook
    ) -> Bool {
        EPUBProgressStore.lastBookURL?
            .standardizedFileURL
            == book.fileURL
                .standardizedFileURL
    }

    private func importBook(
        _ result: Result<[URL], Error>
    ) {
        Task {
            isImporting = true
            defer {
                isImporting = false
            }
            do {
                guard let sourceURL = try result.get().first else {
                    return
                }
                let importResult =
                    try await EPUBLibraryStore.shared
                        .importBookWithResult(
                            from: sourceURL
                        )
                EPUBProgressStore.lastBookURL =
                    importResult.book.fileURL
                books = try await
                    EPUBLibraryStore.shared.books()
                if importResult
                    .reusedExistingBook {
                    statusDescription =
                        String(
                            localized:
                                "같은 내용의 책이 이미 있어 기존 책을 열었습니다."
                        )
                } else {
                    statusDescription = nil
                }
                appRouter.route = .epubReader(
                    fileURL:
                        importResult.book.fileURL
                )
            } catch {
                errorDescription = error.localizedDescription
            }
        }
    }

    private func reloadBooks() {
        Task {
            isLoading = true
            do {
                books = try await
                    EPUBLibraryStore.shared.books()
            } catch {
                errorDescription =
                    error.localizedDescription
            }
            isLoading = false
        }
    }

    private func deleteBook(
        _ book: EPUBLibraryBook
    ) {
        Task {
            do {
                let deletedLastBook =
                    EPUBProgressStore
                        .lastBookURL?
                        .standardizedFileURL
                    == book.fileURL
                        .standardizedFileURL
                let deleted = try await
                    EPUBLibraryStore.shared
                        .deleteBook(book)
                if let identifier =
                        deleted
                            .publicationIdentifier {
                    EPUBProgressStore
                        .removeProgress(
                            for: identifier
                        )
                }
                books = try await
                    EPUBLibraryStore.shared.books()
                if deletedLastBook {
                    EPUBProgressStore
                        .lastBookURL =
                            books.first?.fileURL
                }
                bookToDelete = nil
                statusDescription =
                    String(
                        localized:
                            "서재에서 책을 삭제했습니다. 원본 파일은 그대로입니다."
                    )
            } catch {
                errorDescription =
                    error.localizedDescription
            }
        }
    }
}
