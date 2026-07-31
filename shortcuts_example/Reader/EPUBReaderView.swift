import Combine
import SwiftUI
import UIKit

nonisolated struct EPUBSearchResult:
    Identifiable,
    Equatable,
    Sendable
{
    let id: String
    let chapterIndex: Int
    let chapterTitle: String
    let segmentIndex: Int
    let snippet: String
    let matchStartInSnippet: Int
    let matchStartInSegment: Int
    let matchLength: Int
}

nonisolated struct EPUBTextSegment:
    Identifiable,
    Equatable,
    Sendable
{
    let id: String
    let text: String
}

nonisolated enum EPUBTextSegmenter {
    static func segments(
        in chapter: EPUBChapter
    ) -> [EPUBTextSegment] {
        chapter.text
            .components(separatedBy: "\n\n")
            .map {
                $0.split(whereSeparator: \.isWhitespace)
                    .joined(separator: " ")
            }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { index, text in
                EPUBTextSegment(
                    id:
                        "\(chapter.id)-segment-\(index)",
                    text: text
                )
            }
    }
}

nonisolated enum EPUBReaderSheetPlaybackAction:
    Equatable,
    Sendable
{
    case none
    case pause
    case resume
}

nonisolated struct EPUBReaderSheetPlaybackCoordinator:
    Equatable,
    Sendable
{
    private(set) var resumesAfterSheet =
        false

    mutating func presentationChanged(
        isPresented: Bool,
        isPlaying: Bool
    ) -> EPUBReaderSheetPlaybackAction {
        if isPresented {
            guard isPlaying else {
                return .none
            }
            resumesAfterSheet = true
            return .pause
        }
        guard resumesAfterSheet else {
            return .none
        }
        resumesAfterSheet = false
        return .resume
    }
}

nonisolated enum EPUBReaderAutoplayPolicy {
    static func delayNanoseconds(
        isVoiceOverRunning: Bool
    ) -> UInt64 {
        isVoiceOverRunning
            ? 2_000_000_000
            : 500_000_000
    }

    static func shouldStart(
        canPlay: Bool,
        isPlaying: Bool,
        isSheetPresented: Bool
    ) -> Bool {
        canPlay
            && !isPlaying
            && !isSheetPresented
    }
}

nonisolated struct PublicationNavigationLocation:
    Equatable,
    Sendable
{
    let chapterIndex: Int
    let segmentIndex: Int
}

nonisolated enum PublicationNavigationResolver {
    static func location(
        for item: PublicationNavigationItem,
        in book: EPUBBook
    ) -> PublicationNavigationLocation? {
        guard let href = item.href else {
            return nil
        }
        let parts = href.split(
            separator: "#",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        let path = parts.first.map(String.init)
            ?? href
        let fragment = parts.count > 1
            ? String(parts[1])
                .removingPercentEncoding
            : nil

        if let chapterIndex =
                chapterIndex(
                    for: path,
                    in: book.chapters
                ) {
            let chapter =
                book.chapters[chapterIndex]
            return PublicationNavigationLocation(
                chapterIndex: chapterIndex,
                segmentIndex:
                    fragment.flatMap {
                        chapter
                            .fragmentSegmentIndexes[
                                $0
                            ]
                    } ?? 0
            )
        }

        let matchingOverlayIndexes =
            book.mediaOverlayItems.indices
            .filter {
                pathsMatch(
                    book.mediaOverlayItems[$0]
                        .smilPath,
                    path
                )
            }
        guard let firstOverlayIndex =
                matchingOverlayIndexes.first else {
            return nil
        }
        let overlayIndex =
            matchingOverlayIndexes.first {
                guard let fragment else {
                    return false
                }
                return book.mediaOverlayItems[$0]
                    .id.split(
                        separator: "#",
                        maxSplits: 1
                    ).last.map(String.init)
                    == fragment
            }
            ?? firstOverlayIndex
        guard let location =
                EPUBMediaOverlayLocationResolver
                .location(
                    for: overlayIndex,
                    items:
                        book.mediaOverlayItems,
                    chapters: book.chapters
                ) else {
            return nil
        }
        return PublicationNavigationLocation(
            chapterIndex:
                location.chapterIndex,
            segmentIndex:
                location.segmentIndex
        )
    }

    private static func chapterIndex(
        for path: String,
        in chapters: [EPUBChapter]
    ) -> Int? {
        chapters.firstIndex {
            pathsMatch($0.href, path)
        }
    }

    private static func pathsMatch(
        _ lhs: String,
        _ rhs: String
    ) -> Bool {
        lhs == rhs
            || lhs.caseInsensitiveCompare(rhs)
                == .orderedSame
    }
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

        var results: [EPUBSearchResult] = []
        for (chapterIndex, chapter)
            in chapters.enumerated() {
            let segments =
                EPUBTextSegmenter.segments(
                    in: chapter
                )
            for (segmentIndex, segment)
                in segments.enumerated() {
                appendMatches(
                    query: query,
                    chapterIndex: chapterIndex,
                    chapter: chapter,
                    segmentIndex: segmentIndex,
                    segment: segment,
                    to: &results
                )
            }
        }
        return results
    }

    private static func appendMatches(
        query: String,
        chapterIndex: Int,
        chapter: EPUBChapter,
        segmentIndex: Int,
        segment: EPUBTextSegment,
        to results: inout [EPUBSearchResult]
    ) {
        var searchStart = segment.text.startIndex
        while searchStart < segment.text.endIndex,
              let range = segment.text.range(
                  of: query,
                  options: [
                      .caseInsensitive,
                      .diacriticInsensitive,
                  ],
                  range:
                      searchStart
                      ..< segment.text.endIndex
              ) {
            let matchStart = segment.text.distance(
                from: segment.text.startIndex,
                to: range.lowerBound
            )
            let matchLength = segment.text.distance(
                from: range.lowerBound,
                to: range.upperBound
            )
            let snippetStart = segment.text.index(
                range.lowerBound,
                offsetBy: -40,
                limitedBy: segment.text.startIndex
            ) ?? segment.text.startIndex
            let snippetEnd = segment.text.index(
                range.upperBound,
                offsetBy: 60,
                limitedBy: segment.text.endIndex
            ) ?? segment.text.endIndex
            let hasPrefix =
                snippetStart != segment.text.startIndex
            let hasSuffix =
                snippetEnd != segment.text.endIndex
            let prefix = hasPrefix ? "…" : ""
            let suffix = hasSuffix ? "…" : ""
            let snippet =
                prefix
                + String(
                    segment.text[
                        snippetStart ..< snippetEnd
                    ]
                )
                + suffix
            results.append(
                EPUBSearchResult(
                    id:
                        "\(chapter.id)-"
                        + "\(segmentIndex)-"
                        + "\(matchStart)",
                    chapterIndex: chapterIndex,
                    chapterTitle: chapter.title,
                    segmentIndex: segmentIndex,
                    snippet: snippet,
                    matchStartInSnippet:
                        prefix.count
                        + segment.text.distance(
                            from: snippetStart,
                            to: range.lowerBound
                        ),
                    matchStartInSegment: matchStart,
                    matchLength: matchLength
                )
            )
            searchStart = range.upperBound
        }
    }
}

@MainActor
final class EPUBReaderViewModel: ObservableObject {
    @Published private(set) var book: EPUBBook?
    @Published private(set) var publicationArchive:
        EPUBArchive?
    @Published private(set) var isLoading = false
    @Published private(set) var errorDescription: String?
    @Published private(set) var currentChapterIndex = 0
    @Published private(set) var currentSegmentIndex = 0
    @Published private(set) var highlightedSearchResult:
        EPUBSearchResult?
    @Published private(set) var navigationRevision = 0
    @Published private(set) var navigationTargetSegmentIndex =
        0

    private let fileURL: URL
    private var didLoad = false
    private var progressSaveTask:
        Task<Void, Never>?
    private var isApplyingNavigation = false

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
            let parsedPublication =
                try await Task.detached(
                priority: .userInitiated
            ) {
                let book =
                    try AccessiblePublicationParser
                        .parse(data: data)
                let archive =
                    try EPUBArchive(data: data)
                return (book, archive)
            }.value
            let parsedBook =
                parsedPublication.0
            book = parsedBook
            publicationArchive =
                parsedPublication.1
            let savedProgress =
                EPUBProgressStore.progress(
                for: parsedBook.identifier
            )
            currentChapterIndex = min(
                max(
                    savedProgress?.chapterIndex ?? 0,
                    0
                ),
                parsedBook.chapters.count - 1
            )
            let segmentCount =
                EPUBTextSegmenter.segments(
                    in: parsedBook.chapters[
                        currentChapterIndex
                    ]
                ).count
            currentSegmentIndex = min(
                max(
                    savedProgress?.segmentIndex ?? 0,
                    0
                ),
                max(segmentCount - 1, 0)
            )
            navigationTargetSegmentIndex =
                currentSegmentIndex
            isApplyingNavigation = true
            navigationRevision &+= 1
            EPUBProgressStore.lastBookURL = fileURL
            _ = try? await
                EPUBLibraryStore.shared
                    .markOpened(
                        bookURL: fileURL,
                        publicationIdentifier:
                            parsedBook.identifier
                    )
        } catch {
            errorDescription = error.localizedDescription
        }
        isLoading = false
    }

    func selectChapter(
        _ index: Int,
        segmentIndex: Int = 0,
        highlightedResult:
            EPUBSearchResult? = nil
    ) {
        guard let book,
              book.chapters.indices.contains(index) else {
            return
        }
        let segmentCount =
            EPUBTextSegmenter.segments(
                in: book.chapters[index]
            ).count
        currentChapterIndex = index
        currentSegmentIndex = min(
            max(segmentIndex, 0),
            max(segmentCount - 1, 0)
        )
        navigationTargetSegmentIndex =
            currentSegmentIndex
        isApplyingNavigation = true
        highlightedSearchResult =
            highlightedResult
        navigationRevision &+= 1
        saveProgress()
    }

    func moveChapter(by delta: Int) {
        selectChapter(currentChapterIndex + delta)
    }

    func selectSearchResult(
        _ result: EPUBSearchResult
    ) {
        selectChapter(
            result.chapterIndex,
            segmentIndex: result.segmentIndex,
            highlightedResult: result
        )
    }

    func noteVisibleSegment(_ index: Int) {
        guard !isApplyingNavigation,
              let chapter = currentChapter else {
            return
        }
        let segments =
            EPUBTextSegmenter.segments(
                in: chapter
            )
        guard segments.indices.contains(index),
              index != currentSegmentIndex else {
            return
        }
        currentSegmentIndex = index
        progressSaveTask?.cancel()
        progressSaveTask = Task {
            try? await Task.sleep(
                nanoseconds: 600_000_000
            )
            guard !Task.isCancelled else {
                return
            }
            saveProgress()
            progressSaveTask = nil
        }
    }

    func finishNavigation(
        revision: Int,
        segmentIndex: Int
    ) {
        guard revision == navigationRevision else {
            return
        }
        currentSegmentIndex = segmentIndex
        isApplyingNavigation = false
        saveProgress()
    }

    func flushProgress() {
        progressSaveTask?.cancel()
        progressSaveTask = nil
        saveProgress()
    }

    private func saveProgress() {
        guard let book else {
            return
        }
        EPUBProgressStore.save(
            EPUBReaderProgress(
                chapterIndex:
                    currentChapterIndex,
                segmentIndex:
                    currentSegmentIndex
            ),
            for: book.identifier
        )
    }
}

private nonisolated struct
    EPUBSegmentOffsetPreferenceKey:
    PreferenceKey
{
    static let defaultValue: [Int: CGFloat] = [:]

    static func reduce(
        value: inout [Int: CGFloat],
        nextValue: () -> [Int: CGFloat]
    ) {
        value.merge(
            nextValue(),
            uniquingKeysWith: { _, newValue in
                newValue
            }
        )
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
            return AppLocalization.string(
                "밝게"
            )
        case .sepia:
            return AppLocalization.string(
                "세피아"
            )
        case .dark:
            return AppLocalization.string(
                "어둡게"
            )
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
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var remoteControl:
        RivoScreenRemoteControlCenter
    @StateObject private var viewModel: EPUBReaderViewModel
    @StateObject private var mediaOverlayPlayer:
        EPUBMediaOverlayPlaybackController
    @State private var isContentsPresented = false
    @State private var isSearchPresented = false
    @State private var isSettingsPresented = false
    @State private var searchQuery = ""
    @State private var isSeekingPlayback = false
    @State private var playbackSeekSeconds = 0.0
    @State private var resumesAfterPlaybackSeek =
        false
    @State private var pendingExternalURL:
        URL?
    @State private var sheetPlaybackCoordinator =
        EPUBReaderSheetPlaybackCoordinator()
    @State private var didTriggerAutoplay =
        false

    @AppStorage("reader.epub.theme")
    private var themeID = EPUBReaderTheme.light.rawValue
    @AppStorage("reader.epub.fontScale")
    private var fontScale = 1.0
    @AppStorage("reader.epub.lineHeight")
    private var lineHeight = 1.7
    @AppStorage("reader.epub.speechRate")
    private var speechRate = 1.0
    @AppStorage("reader.epub.originalLayout")
    private var usesOriginalLayout = true

    init(fileURL: URL) {
        _viewModel = StateObject(
            wrappedValue: EPUBReaderViewModel(
                fileURL: fileURL
            )
        )
        _mediaOverlayPlayer = StateObject(
            wrappedValue:
                EPUBMediaOverlayPlaybackController(
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
                ProgressView("책을 여는 중")
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
            viewModel.book?.title
                ?? AppLocalization.string(
                    "독서"
                )
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("목차", systemImage: "list.bullet") {
                    isContentsPresented = true
                }
                .disabled(viewModel.book == nil)

                Button(
                    "본문 검색",
                    systemImage: "magnifyingglass"
                ) {
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
            if let book = viewModel.book {
                mediaOverlayPlayer.configure(
                    book: book,
                    chapterIndex:
                        viewModel.currentChapterIndex,
                    segmentIndex:
                        viewModel.currentSegmentIndex
                )
                mediaOverlayPlayer.setRate(
                    speechRate
                )
                await startAutoplayIfNeeded()
            }
        }
        .onChange(
            of: mediaOverlayPlayer.currentLocation
        ) { _, location in
            guard let location else {
                return
            }
            viewModel.selectChapter(
                location.chapterIndex,
                segmentIndex: location.segmentIndex
            )
        }
        .onChange(of: speechRate) {
            _, rate in
            mediaOverlayPlayer.setRate(rate)
        }
        .onChange(
            of: remoteControl.latestEvent
        ) { _, event in
            handleRemoteEvent(event)
        }
        .onChange(
            of: isReaderSheetPresented
        ) { _, isPresented in
            handleReaderSheetPresentation(
                isPresented
            )
        }
        .onDisappear {
            viewModel.flushProgress()
            mediaOverlayPlayer.stop()
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
        .alert(
            "외부 링크 열기",
            isPresented: Binding(
                get: {
                    pendingExternalURL != nil
                },
                set: { isPresented in
                    if !isPresented {
                        pendingExternalURL = nil
                    }
                }
            )
        ) {
            Button("Safari에서 열기") {
                if let url =
                        pendingExternalURL {
                    openURL(url)
                }
                pendingExternalURL = nil
            }
            Button("취소", role: .cancel) {
                pendingExternalURL = nil
            }
        } message: {
            Text(
                AppLocalization.format(
                    "책 밖의 웹사이트를 Safari에서 열까요?\n%@",
                    pendingExternalURL?
                        .absoluteString
                        ?? ""
                )
            )
        }
    }

    @ViewBuilder
    private func chapterView(
        _ chapter: EPUBChapter
    ) -> some View {
        if usesOriginalLayout,
           let archive =
                viewModel.publicationArchive,
           chapter.sourceMarkup != nil {
            let segments =
                EPUBTextSegmenter.segments(
                    in: chapter
                )
            EPUBOriginalLayoutView(
                archive: archive,
                chapter: chapter,
                segmentCount:
                    segments.count,
                navigationRevision:
                    viewModel
                    .navigationRevision,
                targetSegmentIndex:
                    viewModel
                    .navigationTargetSegmentIndex,
                style:
                    originalLayoutStyle,
                onVisibleSegment: {
                    viewModel
                        .noteVisibleSegment($0)
                },
                onNavigationFinished: {
                    revision,
                    segmentIndex in
                    viewModel.finishNavigation(
                        revision: revision,
                        segmentIndex:
                            segmentIndex
                    )
                },
                onLink: {
                    handlePublicationLink($0)
                }
            )
            .background(
                theme.background
            )
        } else {
            textChapterView(chapter)
        }
    }

    private func textChapterView(
        _ chapter: EPUBChapter
    ) -> some View {
        let segments =
            EPUBTextSegmenter.segments(
                in: chapter
            )
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(
                    alignment: .leading,
                    spacing: 24
                ) {
                    Text(chapter.title)
                        .font(
                            .system(
                                size: 30 * fontScale,
                                weight: .bold
                            )
                        )
                        .accessibilityAddTraits(
                            .isHeader
                        )
                    ForEach(
                        Array(segments.enumerated()),
                        id: \.element.id
                    ) { index, segment in
                        highlightedText(
                            segment.text,
                            start:
                                highlightStart(
                                    for: index
                                ),
                            length:
                                highlightLength(
                                    for: index
                                ),
                            utf16Range:
                                readAloudTextRange(
                                    for: index
                                )
                        )
                        .font(
                            .system(
                                size: 22 * fontScale
                            )
                        )
                        .lineSpacing(
                            CGFloat(
                                8
                                * max(
                                    lineHeight - 1,
                                    0
                                )
                            )
                        )
                        .textSelection(.enabled)
                        .accessibilityLabel(
                            segment.text
                        )
                        .id(segment.id)
                        .background(
                            isPlayingMediaSegment(
                                index
                            )
                            ? Color.orange.opacity(
                                0.16
                            )
                            : Color.clear
                        )
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 8
                            )
                        )
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key:
                                        EPUBSegmentOffsetPreferenceKey
                                        .self,
                                    value: [
                                        index:
                                            geometry.frame(
                                                in:
                                                    .named(
                                                        "epub-chapter-scroll"
                                                    )
                                            ).minY,
                                    ]
                                )
                            }
                        }
                    }
                }
                .foregroundStyle(theme.foreground)
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                .frame(
                    maxWidth: 860,
                    alignment: .leading
                )
                .frame(maxWidth: .infinity)
            }
            .coordinateSpace(
                name: "epub-chapter-scroll"
            )
            .onPreferenceChange(
                EPUBSegmentOffsetPreferenceKey.self
            ) { offsets in
                guard let visible = offsets.min(
                    by: {
                        abs($0.value)
                            < abs($1.value)
                    }
                )?.key else {
                    return
                }
                viewModel.noteVisibleSegment(
                    visible
                )
            }
            .task(
                id: viewModel.navigationRevision
            ) {
                let revision =
                    viewModel.navigationRevision
                let targetIndex =
                    viewModel
                    .navigationTargetSegmentIndex
                guard segments.indices.contains(
                    targetIndex
                ) else {
                    return
                }
                await Task.yield()
                proxy.scrollTo(
                    segments[
                        targetIndex
                    ].id,
                    anchor: .top
                )
                try? await Task.sleep(
                    nanoseconds: 100_000_000
                )
                guard !Task.isCancelled else {
                    return
                }
                viewModel.finishNavigation(
                    revision: revision,
                    segmentIndex: targetIndex
                )
            }
        }
        .id(viewModel.currentChapterIndex)
    }

    private func highlightStart(
        for segmentIndex: Int
    ) -> Int? {
        guard let result =
                viewModel.highlightedSearchResult,
              result.chapterIndex
                == viewModel.currentChapterIndex,
              result.segmentIndex == segmentIndex else {
            return nil
        }
        return result.matchStartInSegment
    }

    private func highlightLength(
        for segmentIndex: Int
    ) -> Int {
        guard let result =
                viewModel.highlightedSearchResult,
              result.chapterIndex
                == viewModel.currentChapterIndex,
              result.segmentIndex == segmentIndex else {
            return 0
        }
        return result.matchLength
    }

    private var playbackBar: some View {
        VStack(spacing: 8) {
            if mediaOverlayPlayer.canPlay {
                VStack(spacing: 0) {
                    Slider(
                        value: Binding(
                            get: {
                                isSeekingPlayback
                                    ? playbackSeekSeconds
                                    : mediaOverlayPlayer
                                        .timelinePositionSeconds
                            },
                            set: {
                                playbackSeekSeconds =
                                    $0
                            }
                        ),
                        in: 0 ... max(
                            mediaOverlayPlayer
                                .totalTimelineSeconds,
                            0.5
                        ),
                        onEditingChanged: {
                            isEditing in
                            handlePlaybackSeekEditing(
                                isEditing
                            )
                        }
                    )
                    .disabled(
                        mediaOverlayPlayer
                            .totalTimelineSeconds
                            <= 0
                        || mediaOverlayPlayer
                            .isLoading
                    )
                    .accessibilityLabel(
                        "책 재생 위치"
                    )
                    .accessibilityValue(
                        playbackTimelineDescription
                    )
                    .accessibilityHint(
                        "조절을 마치면 선택한 위치로 이동합니다."
                    )

                    HStack {
                        Text(
                            playbackTimelineDescription
                        )
                        Spacer()
                        Text(
                            "\(playbackTimelinePercent)%"
                        )
                    }
                    .font(
                        .caption
                        .monospacedDigit()
                    )
                    .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 16) {
                Button("이전 장", systemImage: "chevron.left") {
                    moveChapter(by: -1)
                }
                .disabled(viewModel.currentChapterIndex <= 0)

                if mediaOverlayPlayer.canPlay {
                    Button(
                        "이전 \(mediaOverlayPlayer.navigationUnitDescription)",
                        systemImage:
                            "backward.end.fill"
                    ) {
                        mediaOverlayPlayer
                            .navigate(by: -1)
                    }
                    .disabled(
                        !mediaOverlayPlayer
                            .canNavigatePrevious
                    )

                    Button(
                        mediaOverlayPlayer.isPlaying
                            ? AppLocalization.string(
                                "일시정지"
                            )
                            : AppLocalization.string(
                                "재생"
                            ),
                        systemImage:
                            mediaOverlayPlayer.isPlaying
                            ? "pause.fill"
                            : "play.fill"
                    ) {
                        mediaOverlayPlayer
                            .togglePlayback()
                    }
                    .disabled(
                        mediaOverlayPlayer.isLoading
                    )

                    Button(
                        "다음 \(mediaOverlayPlayer.navigationUnitDescription)",
                        systemImage:
                            "forward.end.fill"
                    ) {
                        mediaOverlayPlayer
                            .navigate(by: 1)
                    }
                    .disabled(
                        !mediaOverlayPlayer
                            .canNavigateNext
                    )

                    Button(
                        mediaOverlayPlayer
                            .navigationUnitDescription,
                        systemImage:
                            "arrow.left.arrow.right"
                    ) {
                        mediaOverlayPlayer
                            .cycleNavigationUnit()
                    }
                    .accessibilityLabel(
                        "탐색 단위 "
                        + mediaOverlayPlayer
                            .navigationUnitDescription
                    )
                    .accessibilityHint(
                        "두 번 탭하면 단어, 문장, 문단, 페이지, 장 순서로 바뀝니다."
                    )

                    if mediaOverlayPlayer.isLoading {
                        ProgressView()
                    } else {
                        VStack(spacing: 2) {
                            if !mediaOverlayPlayer
                                .playbackModeDescription
                                .isEmpty {
                                Text(
                                    mediaOverlayPlayer
                                        .playbackModeDescription
                                )
                                .font(.caption2)
                            }
                            Text(
                                mediaOverlayPlayer
                                    .positionDescription
                            )
                            .font(
                                .caption
                                .monospacedDigit()
                            )
                        }
                        .accessibilityElement(
                            children: .combine
                        )
                        .accessibilityLabel(
                            "읽기 방식 "
                            + mediaOverlayPlayer
                                .playbackModeDescription
                            + ", 위치 "
                            + mediaOverlayPlayer
                                .positionDescription
                        )
                    }
                    if let error =
                            mediaOverlayPlayer
                            .errorDescription {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }

                Text(viewModel.chapterPositionDescription)
                    .font(.headline.monospacedDigit())
                    .frame(minWidth: 70)
                    .accessibilityLabel(
                        "장 위치 \(viewModel.chapterPositionDescription)"
                    )

                Button("다음 장", systemImage: "chevron.right") {
                    moveChapter(by: 1)
                }
                .disabled(
                    guardLastChapterReached
                )
            }
        }
        .buttonStyle(.bordered)
        .padding()
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var playbackTimelineDescription:
        String
    {
        if isSeekingPlayback {
            return mediaOverlayPlayer
                .timelineDescription(
                    at: playbackSeekSeconds
                )
        }
        return mediaOverlayPlayer
            .timelinePositionDescription
    }

    private var playbackTimelinePercent: Int {
        let total =
            mediaOverlayPlayer
                .totalTimelineSeconds
        guard total > 0 else {
            return 0
        }
        let position =
            isSeekingPlayback
            ? playbackSeekSeconds
            : mediaOverlayPlayer
                .timelinePositionSeconds
        return Int(
            (
                min(
                    max(position / total, 0),
                    1
                )
                * 100
            ).rounded()
        )
    }

    private func handlePlaybackSeekEditing(
        _ isEditing: Bool
    ) {
        if isEditing {
            isSeekingPlayback = true
            playbackSeekSeconds =
                mediaOverlayPlayer
                    .timelinePositionSeconds
            resumesAfterPlaybackSeek =
                mediaOverlayPlayer.isPlaying
            mediaOverlayPlayer.pause()
            return
        }
        guard isSeekingPlayback else {
            return
        }
        let target = playbackSeekSeconds
        let shouldResume =
            resumesAfterPlaybackSeek
        isSeekingPlayback = false
        resumesAfterPlaybackSeek = false
        mediaOverlayPlayer.seek(
            toTimelineSeconds: target,
            autoplay: shouldResume
        )
    }

    private var isReaderSheetPresented:
        Bool
    {
        isContentsPresented
            || isSearchPresented
            || isSettingsPresented
    }

    private func handleReaderSheetPresentation(
        _ isPresented: Bool
    ) {
        let action =
            sheetPlaybackCoordinator
            .presentationChanged(
                isPresented: isPresented,
                isPlaying:
                    mediaOverlayPlayer
                    .isPlaying
            )
        switch action {
        case .none:
            break
        case .pause:
            mediaOverlayPlayer.pause()
        case .resume:
            if !mediaOverlayPlayer.isPlaying {
                mediaOverlayPlayer
                    .togglePlayback()
            }
        }
    }

    @MainActor
    private func startAutoplayIfNeeded()
        async
    {
        guard !didTriggerAutoplay else {
            return
        }
        didTriggerAutoplay = true
        let delay =
            EPUBReaderAutoplayPolicy
            .delayNanoseconds(
                isVoiceOverRunning:
                    UIAccessibility
                    .isVoiceOverRunning
            )
        try? await Task.sleep(
            nanoseconds: delay
        )
        guard !Task.isCancelled,
              EPUBReaderAutoplayPolicy
              .shouldStart(
                  canPlay:
                      mediaOverlayPlayer
                      .canPlay,
                  isPlaying:
                      mediaOverlayPlayer
                      .isPlaying,
                  isSheetPresented:
                      isReaderSheetPresented
              ) else {
            return
        }
        mediaOverlayPlayer.togglePlayback()
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
                if let book = viewModel.book {
                    Section {
                        LabeledContent(
                            "형식",
                            value:
                                book.format
                                .displayName
                        )
                        if let creator =
                                book.creator,
                           !creator.isEmpty {
                            LabeledContent(
                                "저자",
                                value: creator
                            )
                        }
                    }

                    if !book.navigationItems
                        .isEmpty {
                        Section("출판물 목차") {
                            ForEach(
                                book.navigationItems
                            ) { item in
                                navigationButton(
                                    item,
                                    in: book
                                )
                            }
                        }
                    }

                    if !book.pageListItems
                        .isEmpty {
                        Section("페이지") {
                            ForEach(
                                book.pageListItems
                            ) { item in
                                navigationButton(
                                    item,
                                    in: book
                                )
                            }
                        }
                    }

                    Section(
                        AppLocalization.string(
                            book.navigationItems
                                .isEmpty
                                ? "목차"
                                : "읽기 순서"
                        )
                    ) {
                        ForEach(
                            Array(
                                book.chapters
                                    .enumerated()
                            ),
                            id: \.element.id
                        ) { index, chapter in
                            Button {
                                selectLocation(
                                    chapterIndex:
                                        index,
                                    segmentIndex: 0
                                )
                                isContentsPresented =
                                    false
                            } label: {
                                HStack {
                                    Text(
                                        chapter.title
                                    )
                                    Spacer()
                                    if index
                                        == viewModel
                                        .currentChapterIndex {
                                        Image(
                                            systemName:
                                                "checkmark"
                                        )
                                    }
                                }
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

    private func navigationButton(
        _ item: PublicationNavigationItem,
        in book: EPUBBook
    ) -> some View {
        let location =
            PublicationNavigationResolver
            .location(for: item, in: book)
        return Button {
            guard let location else {
                return
            }
            selectLocation(
                chapterIndex:
                    location.chapterIndex,
                segmentIndex:
                    location.segmentIndex
            )
            isContentsPresented = false
        } label: {
            HStack {
                Text(
                    item.label.isEmpty
                        ? AppLocalization.string(
                            "이름 없는 항목"
                        )
                        : item.label
                )
                .padding(
                    .leading,
                    CGFloat(
                        min(
                            max(item.depth, 0),
                            8
                        )
                        * 18
                    )
                )
                Spacer()
                if let location,
                   location.chapterIndex
                    == viewModel
                    .currentChapterIndex,
                   location.segmentIndex
                    == viewModel
                    .currentSegmentIndex {
                    Image(
                        systemName: "checkmark"
                    )
                }
            }
        }
        .disabled(location == nil)
        .accessibilityHint(
            AppLocalization.string(
                location == nil
                    ? "이 목차 위치는 현재 본문과 연결되지 않았습니다."
                    : "해당 본문 위치로 이동합니다."
            )
        )
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
                            selectLocation(
                                chapterIndex:
                                    result.chapterIndex,
                                segmentIndex:
                                    result.segmentIndex,
                                highlightedResult:
                                    result
                            )
                            isSearchPresented = false
                        } label: {
                            VStack(
                                alignment: .leading,
                                spacing: 6
                            ) {
                                Text(result.chapterTitle)
                                    .font(.headline)
                                highlightedText(
                                    result.snippet,
                                    start:
                                        result
                                        .matchStartInSnippet,
                                    length:
                                        result.matchLength
                                )
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
                    Toggle(
                        "출판물 원본 표현",
                        isOn:
                            $usesOriginalLayout
                    )
                    Text(
                        "이미지, 표, 목록, 강조와 책 안 링크를 보존합니다. 정확한 검색·발화 강조가 필요하면 끄세요."
                    )
                    .font(.footnote)
                    .foregroundStyle(
                        .secondary
                    )
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

    private func highlightedText(
        _ text: String,
        start: Int?,
        length: Int,
        utf16Range: NSRange? = nil
    ) -> Text {
        let highlightedRange:
            Range<String.Index>?
        if let utf16Range {
            highlightedRange =
                Range(
                    utf16Range,
                    in: text
                )
        } else if let start,
                  start >= 0,
                  length > 0,
                  let lower = text.index(
                      text.startIndex,
                      offsetBy: start,
                      limitedBy: text.endIndex
                  ),
                  let upper = text.index(
                      lower,
                      offsetBy: length,
                      limitedBy: text.endIndex
                  ) {
            highlightedRange =
                lower ..< upper
        } else {
            highlightedRange = nil
        }
        guard let highlightedRange else {
            return Text(text)
        }
        let lower = highlightedRange.lowerBound
        let upper = highlightedRange.upperBound
        let prefix = Text(
            String(
                text[text.startIndex ..< lower]
            )
        )
        let match = Text(
            String(
                text[highlightedRange]
            )
        )
        .bold()
        .foregroundColor(.orange)
        let suffix = Text(
            String(
                text[upper ..< text.endIndex]
            )
        )
        return Text(
            "\(prefix)\(match)\(suffix)"
        )
    }

    private func isPlayingMediaSegment(
        _ segmentIndex: Int
    ) -> Bool {
        guard let location =
                mediaOverlayPlayer.currentLocation else {
            return false
        }
        return location.chapterIndex
            == viewModel.currentChapterIndex
            && location.segmentIndex == segmentIndex
    }

    private func readAloudTextRange(
        for segmentIndex: Int
    ) -> NSRange? {
        guard let range =
                mediaOverlayPlayer
                .currentTextRange,
              range.chapterIndex
                == viewModel.currentChapterIndex,
              range.segmentIndex
                == segmentIndex else {
            return nil
        }
        return NSRange(
            location: range.location,
            length: range.length
        )
    }

    private var originalLayoutStyle:
        EPUBOriginalMarkupStyle
    {
        let colors:
            (
                background: String,
                foreground: String,
                link: String
            )
        switch theme {
        case .light:
            colors = (
                "#FFFFFF",
                "#1A1714",
                "#005FCC"
            )
        case .sepia:
            colors = (
                "#F5EBD6",
                "#2C2117",
                "#7A3E00"
            )
        case .dark:
            colors = (
                "#121417",
                "#F2F2F5",
                "#66AFFF"
            )
        }
        return EPUBOriginalMarkupStyle(
            backgroundColor:
                colors.background,
            foregroundColor:
                colors.foreground,
            linkColor: colors.link,
            fontScale: fontScale,
            lineHeight: lineHeight
        )
    }

    private func handlePublicationLink(
        _ url: URL
    ) {
        switch EPUBOriginalResourcePolicy
            .classifyLink(url) {
        case .publication(
            let path,
            let fragment
        ):
            guard let book = viewModel.book,
                  let chapterIndex =
                    book.chapters
                    .firstIndex(
                        where: {
                            $0.href == path
                        }
                    ) else {
                return
            }
            let segmentIndex =
                fragment.flatMap {
                    book.chapters[
                        chapterIndex
                    ]
                    .fragmentSegmentIndexes[
                        $0
                    ]
                } ?? 0
            selectLocation(
                chapterIndex: chapterIndex,
                segmentIndex:
                    segmentIndex
            )
        case .external(let url):
            pendingExternalURL = url
        case .blocked:
            break
        }
    }

    private func moveChapter(by delta: Int) {
        let target =
            viewModel.currentChapterIndex + delta
        selectLocation(
            chapterIndex: target,
            segmentIndex: 0
        )
    }

    private func handleRemoteEvent(
        _ event: RivoScreenRemoteEvent?
    ) {
        guard let event,
              case .publicationReader(let action) =
                event.action else {
            return
        }
        switch action {
        case .previous:
            mediaOverlayPlayer.navigate(by: -1)
        case .togglePlayback:
            mediaOverlayPlayer.togglePlayback()
        case .next:
            mediaOverlayPlayer.navigate(by: 1)
        case .previousNavigationUnit:
            mediaOverlayPlayer
                .cycleNavigationUnit(by: -1)
        case .nextNavigationUnit:
            mediaOverlayPlayer
                .cycleNavigationUnit(by: 1)
        case .showContents:
            isContentsPresented = true
        case .showSearch:
            isSearchPresented = true
        case .showSettings:
            isSettingsPresented = true
        }
    }

    private func selectLocation(
        chapterIndex: Int,
        segmentIndex: Int,
        highlightedResult:
            EPUBSearchResult? = nil
    ) {
        mediaOverlayPlayer.selectLocation(
            chapterIndex: chapterIndex,
            segmentIndex: segmentIndex
        )
        viewModel.selectChapter(
            chapterIndex,
            segmentIndex: segmentIndex,
            highlightedResult:
                highlightedResult
        )
    }
}
