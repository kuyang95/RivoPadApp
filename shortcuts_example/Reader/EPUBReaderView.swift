import Combine
import SwiftUI

nonisolated struct EPUBSearchResult:
    Identifiable,
    Equatable,
    Sendable
{
    let id: String
    let chapterIndex: Int
    let chapterTitle: String
    let snippet: String
}

nonisolated enum EPUBSearchEngine {
    static func search(
        _ query: String,
        in chapters: [EPUBChapter]
    ) -> [EPUBSearchResult] {
        let query = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !query.isEmpty else {
            return []
        }

        return chapters.enumerated().compactMap {
            chapterIndex,
            chapter in
            guard let range = chapter.text.range(
                of: query,
                options: [
                    .caseInsensitive,
                    .diacriticInsensitive
                ]
            ) else {
                return nil
            }
            let start = chapter.text.index(
                range.lowerBound,
                offsetBy: -60,
                limitedBy: chapter.text.startIndex
            ) ?? chapter.text.startIndex
            let end = chapter.text.index(
                range.upperBound,
                offsetBy: 100,
                limitedBy: chapter.text.endIndex
            ) ?? chapter.text.endIndex
            let snippet = chapter.text[start ..< end]
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            return EPUBSearchResult(
                id: "\(chapter.id)-\(chapterIndex)",
                chapterIndex: chapterIndex,
                chapterTitle: chapter.title,
                snippet: snippet
            )
        }
    }
}

@MainActor
final class EPUBReaderViewModel: ObservableObject {
    @Published private(set) var book: EPUBBook?
    @Published private(set) var isLoading = false
    @Published private(set) var errorDescription: String?
    @Published private(set) var currentChapterIndex = 0

    private let fileURL: URL
    private var didLoad = false

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    var currentChapter: EPUBChapter? {
        guard let book,
              book.chapters.indices.contains(
                  currentChapterIndex
              ) else {
            return nil
        }
        return book.chapters[currentChapterIndex]
    }

    var chapterPositionDescription: String {
        guard let book else {
            return ""
        }
        return "\(currentChapterIndex + 1) / \(book.chapters.count)"
    }

    func load() async {
        guard !didLoad else {
            return
        }
        didLoad = true
        isLoading = true
        errorDescription = nil
        do {
            let data = try Data(
                contentsOf: fileURL,
                options: .mappedIfSafe
            )
            let parsedBook = try await Task.detached(
                priority: .userInitiated
            ) {
                try EPUBBookParser.parse(data: data)
            }.value
            book = parsedBook
            let savedIndex = EPUBProgressStore.chapterIndex(
                for: parsedBook.identifier
            )
            currentChapterIndex = min(
                max(savedIndex, 0),
                parsedBook.chapters.count - 1
            )
            EPUBProgressStore.lastBookURL = fileURL
        } catch {
            errorDescription = error.localizedDescription
        }
        isLoading = false
    }

    func selectChapter(_ index: Int) {
        guard let book,
              book.chapters.indices.contains(index) else {
            return
        }
        currentChapterIndex = index
        EPUBProgressStore.saveChapterIndex(
            index,
            for: book.identifier
        )
    }

    func moveChapter(by delta: Int) {
        selectChapter(currentChapterIndex + delta)
    }
}

private enum EPUBReaderTheme: String, CaseIterable, Identifiable {
    case light
    case sepia
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .light:
            return "밝게"
        case .sepia:
            return "세피아"
        case .dark:
            return "어둡게"
        }
    }

    var background: Color {
        switch self {
        case .light:
            return .white
        case .sepia:
            return Color(
                red: 0.96,
                green: 0.92,
                blue: 0.84
            )
        case .dark:
            return Color(
                red: 0.07,
                green: 0.08,
                blue: 0.09
            )
        }
    }

    var foreground: Color {
        self == .dark
            ? Color(
                red: 0.95,
                green: 0.95,
                blue: 0.96
            )
            : Color(
                red: 0.10,
                green: 0.09,
                blue: 0.08
            )
    }
}

struct EPUBReaderView: View {
    @StateObject private var viewModel: EPUBReaderViewModel
    @State private var isContentsPresented = false
    @State private var isSearchPresented = false
    @State private var isSettingsPresented = false
    @State private var searchQuery = ""

    @AppStorage("reader.epub.theme")
    private var themeID = EPUBReaderTheme.light.rawValue
    @AppStorage("reader.epub.fontScale")
    private var fontScale = 1.0
    @AppStorage("reader.epub.lineHeight")
    private var lineHeight = 1.7
    @AppStorage("reader.epub.speechRate")
    private var speechRate = 1.0

    private let tts = TTSManager.shared

    init(fileURL: URL) {
        _viewModel = StateObject(
            wrappedValue: EPUBReaderViewModel(
                fileURL: fileURL
            )
        )
    }

    private var theme: EPUBReaderTheme {
        EPUBReaderTheme(rawValue: themeID) ?? .light
    }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            if viewModel.isLoading {
                ProgressView("EPUB을 여는 중")
                    .tint(theme.foreground)
                    .foregroundStyle(theme.foreground)
            } else if let error = viewModel.errorDescription {
                ContentUnavailableView(
                    "책을 열 수 없습니다",
                    systemImage: "book.closed",
                    description: Text(error)
                )
            } else if let chapter = viewModel.currentChapter {
                chapterView(chapter)
            }
        }
        .navigationTitle(
            viewModel.book?.title ?? "EPUB 독서"
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("목차", systemImage: "list.bullet") {
                    isContentsPresented = true
                }
                .disabled(viewModel.book == nil)

                Button("검색", systemImage: "magnifyingglass") {
                    isSearchPresented = true
                }
                .disabled(viewModel.book == nil)

                Button("보기 설정", systemImage: "textformat.size") {
                    isSettingsPresented = true
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            playbackBar
        }
        .task {
            await viewModel.load()
        }
        .onChange(of: viewModel.currentChapterIndex) {
            _, _ in
            tts.stop()
        }
        .onDisappear {
            tts.stop()
        }
        .sheet(isPresented: $isContentsPresented) {
            contentsSheet
        }
        .sheet(isPresented: $isSearchPresented) {
            searchSheet
        }
        .sheet(isPresented: $isSettingsPresented) {
            settingsSheet
                .presentationDetents([.medium])
        }
    }

    private func chapterView(
        _ chapter: EPUBChapter
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(chapter.title)
                    .font(
                        .system(
                            size: 30 * fontScale,
                            weight: .bold
                        )
                    )
                    .accessibilityAddTraits(.isHeader)

                Text(chapter.text)
                    .font(
                        .system(
                            size: 22 * fontScale
                        )
                    )
                    .lineSpacing(
                        CGFloat(
                            8 * max(lineHeight - 1, 0)
                        )
                    )
                    .textSelection(.enabled)
                    .accessibilityLabel(chapter.text)
            }
            .foregroundStyle(theme.foreground)
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .id(viewModel.currentChapterIndex)
    }

    private var playbackBar: some View {
        HStack(spacing: 16) {
            Button("이전 장", systemImage: "chevron.left") {
                viewModel.moveChapter(by: -1)
            }
            .disabled(viewModel.currentChapterIndex <= 0)

            Button("읽기", systemImage: "play.fill") {
                guard let text = viewModel.currentChapter?.text else {
                    return
                }
                tts.speak(
                    text,
                    rate: Float(speechRate * 0.5)
                )
            }
            .disabled(viewModel.currentChapter == nil)

            Button("정지", systemImage: "stop.fill") {
                tts.stop()
            }

            Text(viewModel.chapterPositionDescription)
                .font(.headline.monospacedDigit())
                .frame(minWidth: 70)
                .accessibilityLabel(
                    "장 위치 \(viewModel.chapterPositionDescription)"
                )

            Button("다음 장", systemImage: "chevron.right") {
                viewModel.moveChapter(by: 1)
            }
            .disabled(
                guardLastChapterReached
            )
        }
        .buttonStyle(.bordered)
        .padding()
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var guardLastChapterReached: Bool {
        guard let count = viewModel.book?.chapters.count else {
            return true
        }
        return viewModel.currentChapterIndex >= count - 1
    }

    private var contentsSheet: some View {
        NavigationStack {
            List {
                ForEach(
                    Array(
                        (viewModel.book?.chapters ?? [])
                            .enumerated()
                    ),
                    id: \.element.id
                ) { index, chapter in
                    Button {
                        viewModel.selectChapter(index)
                        isContentsPresented = false
                    } label: {
                        HStack {
                            Text(chapter.title)
                            Spacer()
                            if index
                                == viewModel.currentChapterIndex {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            .navigationTitle("목차")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        isContentsPresented = false
                    }
                }
            }
        }
    }

    private var searchSheet: some View {
        NavigationStack {
            Group {
                let results = EPUBSearchEngine.search(
                    searchQuery,
                    in: viewModel.book?.chapters ?? []
                )
                if searchQuery.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty {
                    ContentUnavailableView(
                        "책 검색",
                        systemImage: "text.magnifyingglass",
                        description: Text(
                            "찾을 단어나 문장을 입력하세요."
                        )
                    )
                } else if results.isEmpty {
                    ContentUnavailableView.search(
                        text: searchQuery
                    )
                } else {
                    List(results) { result in
                        Button {
                            viewModel.selectChapter(
                                result.chapterIndex
                            )
                            isSearchPresented = false
                        } label: {
                            VStack(
                                alignment: .leading,
                                spacing: 6
                            ) {
                                Text(result.chapterTitle)
                                    .font(.headline)
                                Text(result.snippet)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        }
                    }
                }
            }
            .navigationTitle("본문 검색")
            .searchable(
                text: $searchQuery,
                prompt: "책에서 검색"
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        isSearchPresented = false
                    }
                }
            }
        }
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("화면") {
                    Picker("테마", selection: $themeID) {
                        ForEach(EPUBReaderTheme.allCases) {
                            theme in
                            Text(theme.title)
                                .tag(theme.rawValue)
                        }
                    }
                    Slider(
                        value: $fontScale,
                        in: 0.8 ... 1.8,
                        step: 0.1
                    ) {
                        Text("글자 크기")
                    } minimumValueLabel: {
                        Text("작게")
                    } maximumValueLabel: {
                        Text("크게")
                    }
                    Slider(
                        value: $lineHeight,
                        in: 1.2 ... 2.2,
                        step: 0.1
                    ) {
                        Text("줄 간격")
                    } minimumValueLabel: {
                        Text("좁게")
                    } maximumValueLabel: {
                        Text("넓게")
                    }
                }

                Section("음성") {
                    Slider(
                        value: $speechRate,
                        in: 0.5 ... 2.0,
                        step: 0.1
                    ) {
                        Text("읽기 속도")
                    } minimumValueLabel: {
                        Text("느리게")
                    } maximumValueLabel: {
                        Text("빠르게")
                    }
                }
            }
            .navigationTitle("독서 설정")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        isSettingsPresented = false
                    }
                }
            }
        }
    }
}
