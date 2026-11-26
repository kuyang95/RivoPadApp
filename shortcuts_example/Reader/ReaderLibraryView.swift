import SwiftUI
import UniformTypeIdentifiers

/// Android `PublicationSummaryCard`에 보이는 값: 형식·제목·읽기 순서·목차·페이지·아카이브 파일 수.
nonisolated struct ReaderBookSummary:
    Equatable,
    Sendable
{
    let fileName: String
    let formatName: String
    let title: String
    let readingOrderCount: Int
    let tocCount: Int
    let pageCount: Int
    let assetCount: Int

    static func load(
        from fileURL: URL
    ) throws -> ReaderBookSummary {
        let data = try Data(
            contentsOf: fileURL,
            options: .mappedIfSafe
        )
        let book = try AccessiblePublicationParser
            .parse(data: data)
        let archive = try EPUBArchive(data: data)
        return ReaderBookSummary(
            fileName: fileURL.lastPathComponent,
            formatName: book.format.displayName,
            title: book.title,
            readingOrderCount: book.chapters.count,
            tocCount: book.navigationItems.count,
            pageCount: book.pageListItems.count,
            assetCount: archive.paths.count
        )
    }
}

/// Android `DaisyFileOpenScreen`: 안내 문장 → VcActionRow(계속 읽기 / 도서 파일 선택) → 로딩·오류·요약 패널.
/// iOS 고유의 "내 서재" 목록은 그 아래에 유지한다.
struct ReaderLibraryView: View {
    var embedded = false
    var onOpenBook: ((URL) -> Void)? = nil
    private func openBook(_ url: URL) {
        if let onOpenBook { onOpenBook(url) } else { appRouter.route = .epubReader(fileURL: url) }
    }
    @EnvironmentObject private var appRouter: AppRouter
    @State private var isImporterPresented = false
    @State private var isImporting = false
    @State private var books: [EPUBLibraryBook] = []
    @State private var isLoading = true
    @State private var bookToDelete:
        EPUBLibraryBook?
    @State private var errorDescription: String?
    @State private var statusDescription: String?
    @State private var summary: ReaderBookSummary?

    /// Android `bookMimeTypes`: epub+zip, zip, x-zip-compressed, octet-stream(=public.data).
    private var supportedBookTypes: [UTType] {
        let epub =
            UTType(filenameExtension: "epub")
            ?? .data
        return [epub, .zip, .data]
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
            VStack(
                alignment: .leading,
                spacing: 16
            ) {
                if embedded {
                    ReaderWelcomeView(
                        lastBookTitle: lastBook?.title,
                        enabled: !isImporting,
                        onContinue: {
                            guard !isImporting, let lastBook else { return }
                            openBook(lastBook.fileURL)
                        },
                        onChoose: {
                            guard !isImporting else { return }
                            isImporterPresented = true
                        }
                    )
                } else {
                    Text("EPUB 또는 DAISY ZIP 파일을 선택하세요")
                        .visionCraftAndroidText(16)
                        .foregroundStyle(VisionCraftUI.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    VisionCraftHomeActionList(items: actionItems)
                }

                if isImporting {
                    loadingPanel
                }

                if let errorDescription {
                    errorPanel(errorDescription)
                }

                if !embedded, let summary {
                    summaryPanel(summary)
                }

                if let statusDescription {
                    statusPanel(statusDescription)
                }

                if !embedded || !books.isEmpty { librarySection }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, embedded ? 40 : VisionCraftUI.horizontalPadding)
            .padding(.top, embedded ? 32 : 12)
            .padding(.bottom, embedded ? 32 : 24)
            .frame(minHeight: embedded ? geometry.size.height : 0, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .visionCraftListScreen(background: embedded ? .clear : VisionCraftUI.background)
        .navigationTitle(
            "도서 읽기"
        )
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes:
                supportedBookTypes,
            allowsMultipleSelection: true
        ) { result in
            importBook(result)
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
                AppLocalization.format(
                    "\"%@\" 삭제",
                    book.title
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
                AppLocalization.format(
                    "\"%@\" 책을 이 iPad의 서재에서 삭제할까요? 원본 파일은 삭제되지 않습니다.",
                    book.title
                )
            )
        }
        .onAppear {
            reloadBooks()
        }
        .task(id: lastBook?.id) {
            if !embedded { await loadSummary() }
        }
    }

    private var actionItems: [VisionCraftActionItem] {
        var items: [VisionCraftActionItem] = []
        if let lastBook {
            items.append(
                VisionCraftActionItem(
                    id: "reader.continue",
                    icon: "clock",
                    title: "계속 읽기",
                    description: lastBook.title,
                    action: {
                        guard !isImporting else {
                            return
                        }
                        openBook(lastBook.fileURL)
                    }
                )
            )
        }
        items.append(
            VisionCraftActionItem(
                id: "reader.pick",
                icon: "folder",
                title: "도서 파일 선택",
                description:
                    "EPUB 또는 DAISY ZIP 파일을 선택하세요",
                action: {
                    guard !isImporting else {
                        return
                    }
                    isImporterPresented = true
                }
            )
        )
        return items
    }

    private var loadingPanel: some View {
        HStack(spacing: 14) {
            ProgressView()
                .tint(VisionCraftUI.accent)
            Text("도서 불러오는 중")
                .visionCraftAndroidText(16)
                .foregroundStyle(
                    VisionCraftUI.primaryText
                )
        }
        .padding(20)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .visionCraftSurfaceCard()
        .accessibilityElement(children: .combine)
    }

    /// Android `VcPanel(error = true)`: "도서 파일을 해석하지 못했습니다." + 원인.
    private func errorPanel(
        _ message: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                Text("도서 파일을 해석하지 못했습니다.")
                    .visionCraftAndroidText(
                        16,
                        weight: .semibold
                    )
                    .foregroundStyle(
                        VisionCraftUI.accent
                    )
                Spacer(minLength: 0)
                Button {
                    errorDescription = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(
                            .system(
                                size: 18,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(
                            VisionCraftUI.icon
                        )
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("알림 닫기")
            }
            Text(message)
                .visionCraftAndroidText(
                    14,
                    relativeTo: .footnote
                )
                .foregroundStyle(
                    VisionCraftUI.primaryText
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
        }
        .padding(16)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .visionCraftErrorPanel()
    }

    private func statusPanel(
        _ message: String
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(VisionCraftUI.success)
                .accessibilityHidden(true)
            Text(message)
                .visionCraftAndroidText(16)
                .foregroundStyle(
                    VisionCraftUI.primaryText
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
            Spacer(minLength: 0)
            Button {
                statusDescription = nil
            } label: {
                Image(systemName: "xmark")
                    .font(
                        .system(
                            size: 18,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(VisionCraftUI.icon)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("알림 닫기")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .visionCraftSurfaceCard()
    }

    /// Android `PublicationSummaryCard`: 파싱 결과 패널.
    private func summaryPanel(
        _ summary: ReaderBookSummary
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("파싱 결과")
                .visionCraftAndroidText(
                    18,
                    weight: .semibold,
                    relativeTo: .headline
                )
                .foregroundStyle(
                    VisionCraftUI.primaryText
                )
            Text(summary.fileName)
                .visionCraftAndroidText(16)
                .foregroundStyle(
                    VisionCraftUI.secondaryText
                )
                .lineLimit(1)
            summaryRow(
                "형식",
                value: summary.formatName
            )
            summaryRow(
                "제목",
                value: summary.title.isEmpty
                    ? AppLocalization.string("제목 없음")
                    : summary.title
            )
            summaryRow(
                "읽기 순서",
                value: "\(summary.readingOrderCount)"
            )
            summaryRow(
                "목차 항목",
                value: "\(summary.tocCount)"
            )
            summaryRow(
                "페이지 항목",
                value: "\(summary.pageCount)"
            )
            summaryRow(
                "아카이브 파일",
                value: "\(summary.assetCount)"
            )
        }
        .padding(16)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .visionCraftSurfaceCard()
    }

    private func summaryRow(
        _ label: String,
        value: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(AppLocalization.string(label))
                .visionCraftAndroidText(16)
                .foregroundStyle(
                    VisionCraftUI.secondaryText
                )
            Spacer(minLength: 8)
            Text(value)
                .visionCraftAndroidText(
                    16,
                    weight: .medium
                )
                .foregroundStyle(
                    VisionCraftUI.primaryText
                )
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var librarySection: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("내 서재")
                .visionCraftAndroidText(
                    18,
                    weight: .semibold,
                    relativeTo: .headline
                )
                .foregroundStyle(
                    VisionCraftUI.primaryText
                )
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if !isLoading, !books.isEmpty {
                Text(
                    AppLocalization.format(
                        "책 %lld권",
                        books.count
                    )
                )
                .visionCraftAndroidText(
                    14,
                    relativeTo: .footnote
                )
                .foregroundStyle(
                    VisionCraftUI.secondaryText
                )
            }
        }
        .padding(.top, 12)

        Text("99권을 넘으면 오래 읽지 않은 책의 보관 사본과 읽기 위치를 정리합니다.")
            .visionCraftAndroidText(14, relativeTo: .footnote)
            .foregroundStyle(VisionCraftUI.secondaryText)
            .fixedSize(horizontal: false, vertical: true)

        if isLoading {
            HStack(spacing: 14) {
                ProgressView()
                    .tint(VisionCraftUI.accent)
                Text("서재 불러오는 중")
                    .visionCraftAndroidText(16)
                    .foregroundStyle(
                        VisionCraftUI.primaryText
                    )
            }
            .padding(20)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
            .visionCraftSurfaceCard()
            .accessibilityElement(children: .combine)
        } else if books.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("가져온 책이 없습니다")
                    .visionCraftAndroidText(
                        16,
                        weight: .semibold
                    )
                    .foregroundStyle(
                        VisionCraftUI.primaryText
                    )
                Text(
                    "EPUB·DAISY 파일을 가져오면 이 iPad에 보관됩니다."
                )
                .visionCraftAndroidText(
                    14,
                    relativeTo: .footnote
                )
                .foregroundStyle(
                    VisionCraftUI.secondaryText
                )
            }
            .padding(16)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
            .visionCraftSurfaceCard()
            .accessibilityElement(children: .combine)
        } else {
            VStack(spacing: 0) {
                ForEach(
                    Array(books.enumerated()),
                    id: \.element.id
                ) { index, book in
                    bookRow(book)
                    if index < books.count - 1 {
                        Divider()
                            .overlay(
                                VisionCraftUI.outline
                                    .opacity(0.7)
                            )
                            .padding(.leading, 62)
                    }
                }
            }
            .visionCraftSurfaceCard()
        }
    }

    private func bookRow(
        _ book: EPUBLibraryBook
    ) -> some View {
        HStack(spacing: 0) {
            Button {
                openBook(book.fileURL)
            } label: {
                HStack(spacing: 14) {
                    Image(
                        systemName:
                            book.fileURL.pathExtension
                                .lowercased() == "epub"
                            ? "book.closed.fill"
                            : "waveform.badge.plus"
                    )
                    .font(.system(size: 24))
                    .frame(width: 32)
                    .foregroundStyle(
                        VisionCraftUI.icon
                    )
                    .accessibilityHidden(true)

                    VStack(
                        alignment: .leading,
                        spacing: 4
                    ) {
                        Text(book.title)
                            .visionCraftAndroidText(
                                16,
                                weight: .semibold
                            )
                            .foregroundStyle(
                                VisionCraftUI.primaryText
                            )
                            .lineLimit(2)
                        HStack(spacing: 8) {
                            Text(book.formatDescription)
                            if isLastBook(book) {
                                Label(
                                    "최근 읽음",
                                    systemImage: "clock.fill"
                                )
                            }
                            Text(
                                book.activityDate,
                                style: .date
                            )
                        }
                        .visionCraftAndroidText(
                            14,
                            relativeTo: .footnote
                        )
                        .foregroundStyle(
                            VisionCraftUI.secondaryText
                        )
                    }
                    .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 16)
                .padding(.vertical, 12)
                .frame(minHeight: 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(
                AppLocalization.string(
                    isLastBook(book)
                        ? "마지막으로 읽던 위치부터 계속합니다."
                        : "저장된 읽기 위치부터 책을 엽니다."
                )
            )

            Button {
                bookToDelete = book
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 20))
                    .foregroundStyle(VisionCraftUI.icon)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            .accessibilityLabel(
                AppLocalization.format(
                    "\"%@\" 서재에서 삭제",
                    book.title
                )
            )
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

    private var lastBook: EPUBLibraryBook? {
        books.first(where: isLastBook)
    }

    private func loadSummary() async {
        guard let lastBook else {
            summary = nil
            return
        }
        let fileURL = lastBook.fileURL
        let loaded = try? await Task.detached(
            priority: .utility
        ) {
            try ReaderBookSummary.load(from: fileURL)
        }.value
        guard !Task.isCancelled else {
            return
        }
        summary = loaded
    }

    private func importBook(_ result: Result<[URL], Error>) {
        Task {
            isImporting = true
            errorDescription = nil
            statusDescription = nil
            defer { isImporting = false }
            do {
                let sources = try result.get()
                guard sources.count <= 99 else {
                    errorDescription = AppLocalization.string("한 번에 최대 99권을 선택할 수 있습니다.")
                    return
                }
                var imported = 0
                var failures: [String] = []
                var lastImported: URL?
                for source in sources {
                    try Task.checkCancellation()
                    do {
                        let outcome = try await EPUBLibraryStore.shared.importBookWithResult(from: source)
                        imported += 1
                        lastImported = outcome.book.fileURL
                    } catch is CancellationError { throw CancellationError() }
                    catch { failures.append(source.lastPathComponent + ": " + error.localizedDescription) }
                }
                if let lastImported { EPUBProgressStore.lastBookURL = lastImported }
                books = try await EPUBLibraryStore.shared.books()
                statusDescription = AppLocalization.format("%lld권 가져옴 · %lld권 가져오지 못함", imported, failures.count)
                errorDescription = failures.first
            } catch is CancellationError {
                // Every completed import is already durable; unfinished copies are cleaned by the store.
            } catch { errorDescription = error.localizedDescription }
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
                    AppLocalization.string(
                        "서재에서 책을 삭제했습니다. 원본 파일은 그대로입니다."
                    )
            } catch {
                errorDescription =
                    error.localizedDescription
            }
        }
    }
}
