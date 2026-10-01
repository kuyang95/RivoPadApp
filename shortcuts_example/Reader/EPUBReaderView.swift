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

nonisolated enum EPUBReaderProgressTrackingPolicy {
    static func shouldAdoptVisibleSegment(
        isPlaybackActive: Bool
    ) -> Bool {
        !isPlaybackActive
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

    func noteVisibleSegment(
        _ index: Int,
        isPlaybackActive: Bool
    ) {
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
        guard EPUBReaderProgressTrackingPolicy
            .shouldAdoptVisibleSegment(
                isPlaybackActive:
                    isPlaybackActive
            ) else {
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

    /// Android `ReaderTheme`: 밝게 #FFFFFF/#111111, 세피아 #F5EBD8/#2C2117, 어둡게 #111315/#F2F3F5.
    var backgroundHex: String {
        switch self {
        case .light:
            return "#FFFFFF"
        case .sepia:
            return "#F5EBD8"
        case .dark:
            return "#111315"
        }
    }

    var foregroundHex: String {
        switch self {
        case .light:
            return "#111111"
        case .sepia:
            return "#2C2117"
        case .dark:
            return "#F2F3F5"
        }
    }

    var background: Color {
        switch self {
        case .light:
            return VisionCraftUI.fixedColor(0xFFFFFF)
        case .sepia:
            return VisionCraftUI.fixedColor(0xF5EBD8)
        case .dark:
            return VisionCraftUI.fixedColor(0x111315)
        }
    }

    var foreground: Color {
        switch self {
        case .light:
            return VisionCraftUI.fixedColor(0x111111)
        case .sepia:
            return VisionCraftUI.fixedColor(0x2C2117)
        case .dark:
            return VisionCraftUI.fixedColor(0xF2F3F5)
        }
    }

    /// Android `UNIFIED_HIGHLIGHT` #FFF3B0: 읽는 문장·단어 강조는 테마와 무관하게 같은 노랑.
    static let readingHighlight =
        VisionCraftUI.fixedColor(0xFFF3B0)
    static let readingHighlightText =
        VisionCraftUI.fixedColor(0x111111)
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
    @State private var remoteModeFlash:
        RivoRemoteKeyMode?
    @State private var remoteModeFlashTask:
        Task<Void, Never>?
    @State private var didFlashRemoteMode =
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
        .tint(VisionCraftUI.primary)
        .toolbarBackground(VisionCraftUI.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            // Android `DaisyFileOpenScreen` 제목 줄: 목차(List) · 검색(Search) · 설정(Settings).
            // 목차가 없으면 목차 버튼은 비활성(38%).
            ToolbarItemGroup(placement: .primaryAction) {
                if viewModel.book != nil {
                    VisionCraftIconButton(
                        systemImage: "list.bullet",
                        label: "목차",
                        tint: hasContents
                            ? VisionCraftUI.primaryText
                            : VisionCraftUI.primaryText
                                .opacity(0.38)
                    ) {
                        isContentsPresented = true
                    }
                    .disabled(!hasContents)

                    VisionCraftIconButton(
                        systemImage: "magnifyingglass",
                        label: "검색 열기",
                        tint: VisionCraftUI.primaryText
                    ) {
                        isSearchPresented = true
                    }

                    VisionCraftIconButton(
                        systemImage: "gearshape",
                        label: "설정 열기",
                        tint: VisionCraftUI.primaryText
                    ) {
                        isSettingsPresented = true
                    }
                }
            }
        }
        .overlay {
            if let remoteModeFlash {
                RivoRemoteModeNameFlash(
                    mode: remoteModeFlash
                )
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
            of: mediaOverlayPlayer.navigationUnit
        ) { _, unit in
            // Android `DaisyReaderView`: 단위가 바뀌면 TTS 피드백으로 알린다.
            TTSManager.shared.speakFeedback(
                unit.announcement
            )
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
                        .noteVisibleSegment(
                            $0,
                            isPlaybackActive:
                                mediaOverlayPlayer
                                .isPlaying
                        )
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
                        .foregroundStyle(
                            isPlayingMediaSegment(
                                index
                            )
                            ? EPUBReaderTheme
                                .readingHighlightText
                            : theme.foreground
                        )
                        .accessibilityLabel(
                            segment.text
                        )
                        .id(segment.id)
                        .background(
                            isPlayingMediaSegment(
                                index
                            )
                            ? EPUBReaderTheme
                                .readingHighlight
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
                    visible,
                    isPlaybackActive:
                        mediaOverlayPlayer
                        .isPlaying
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

    /// Android `PlayerBottomBar`: 슬라이더(항상) + 시간/퍼센트 + [재생 56][이전 48][단위 알약 56][다음 48].
    private var playbackBar: some View {
        let canPlay = mediaOverlayPlayer.canPlay
        let hasTime =
            mediaOverlayPlayer.totalTimelineSeconds > 0
        return VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: {
                        isSeekingPlayback
                            ? playbackSeekSeconds
                            : mediaOverlayPlayer
                                .timelinePositionSeconds
                    },
                    set: {
                        playbackSeekSeconds = $0
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
                !canPlay
                || !hasTime
                || mediaOverlayPlayer.isLoading
            )
            .tint(VisionCraftUI.accent)
            .opacity(canPlay ? 1 : 0.38)
            .accessibilityLabel("책 재생 위치")
            .accessibilityValue(
                playbackTimelineDescription
            )
            .accessibilityHint(
                "조절을 마치면 선택한 위치로 이동합니다."
            )

            HStack {
                Text(playbackTimelineDescription)
                Spacer()
                Text("\(playbackTimelinePercent)%")
            }
            .visionCraftAndroidText(
                12,
                relativeTo: .caption
            )
            .monospacedDigit()
            .foregroundStyle(
                VisionCraftUI.secondaryText
            )
            .padding(.horizontal, 14)
            .accessibilityElement(children: .combine)

            HStack(spacing: 0) {
                Button {
                    mediaOverlayPlayer.togglePlayback()
                } label: {
                    ZStack {
                        Circle()
                            .fill(
                                canPlay
                                    ? VisionCraftUI.accent
                                    : VisionCraftUI.accent
                                        .opacity(0.4)
                            )
                        if mediaOverlayPlayer.isLoading {
                            ProgressView()
                                .tint(VisionCraftUI.onAccent)
                        } else {
                            Image(
                                systemName:
                                    mediaOverlayPlayer.isPlaying
                                    ? "pause.fill"
                                    : "play.fill"
                            )
                            .font(
                                .system(
                                    size: 28,
                                    weight: .semibold
                                )
                            )
                            .foregroundStyle(
                                VisionCraftUI.onAccent
                                    .opacity(canPlay ? 1 : 0.4)
                            )
                        }
                    }
                    .frame(width: 56, height: 56)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(
                    !canPlay || mediaOverlayPlayer.isLoading
                )
                .accessibilityLabel(
                    mediaOverlayPlayer.isPlaying
                        ? AppLocalization.string("일시정지")
                        : AppLocalization.string("재생")
                )
                .accessibilityValue(
                    Text(
                        verbatim:
                            mediaOverlayPlayer
                            .playbackModeDescription
                    )
                )

                Spacer().frame(width: 12)

                transportButton(
                    systemImage: "backward.end.fill",
                    label: AppLocalization.string("이전"),
                    isEnabled:
                        canPlay
                        && mediaOverlayPlayer
                            .canNavigatePrevious
                ) {
                    mediaOverlayPlayer.navigate(by: -1)
                }

                Spacer().frame(width: 8)

                Button {
                    mediaOverlayPlayer
                        .cycleNavigationUnit()
                } label: {
                    HStack(spacing: 8) {
                        Image(
                            systemName:
                                "arrow.left.arrow.right"
                        )
                        .font(
                            .system(
                                size: 20,
                                weight: .semibold
                            )
                        )
                        Text(
                            mediaOverlayPlayer
                                .navigationUnitDescription
                        )
                        .visionCraftAndroidText(
                            18,
                            weight: .medium,
                            relativeTo: .body
                        )
                    }
                    .foregroundStyle(
                        VisionCraftUI.primaryText
                    )
                    .padding(.horizontal, 18)
                    .frame(minHeight: 56)
                    .background(
                        VisionCraftUI.accent.opacity(0.14),
                        in: Capsule()
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    AppLocalization.format(
                        "이동 단위 %@",
                        mediaOverlayPlayer
                            .navigationUnitDescription
                    )
                )
                .accessibilityHint(
                    "두 번 탭하면 단어, 문장, 문단, 페이지, 목차 순서로 바뀝니다."
                )

                Spacer().frame(width: 8)

                transportButton(
                    systemImage: "forward.end.fill",
                    label: AppLocalization.string("다음"),
                    isEnabled:
                        canPlay
                        && mediaOverlayPlayer
                            .canNavigateNext
                ) {
                    mediaOverlayPlayer.navigate(by: 1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)

            if let error =
                    mediaOverlayPlayer.errorDescription {
                Text(error)
                    .visionCraftAndroidText(
                        12,
                        relativeTo: .caption
                    )
                    .foregroundStyle(VisionCraftUI.error)
                    .lineLimit(2)
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )
                    .padding(.horizontal, 14)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(VisionCraftUI.surface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(
                    VisionCraftUI.secondaryText
                        .opacity(0.7)
                )
                .frame(height: 1)
        }
        .shadow(
            color: VisionCraftHomeUI.shadow.opacity(0.5),
            radius: 16,
            y: -2
        )
    }

    private func transportButton(
        systemImage: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(
                    .system(size: 28, weight: .semibold)
                )
                .foregroundStyle(
                    isEnabled
                        ? VisionCraftUI.primaryText
                        : VisionCraftUI.secondaryText
                )
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
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
        // Android `PlayerBottomBar`: 시간 정보가 없으면 "n / 전체"(비어 있으면 "0 / 0").
        guard mediaOverlayPlayer.totalTimelineSeconds > 0 else {
            let position =
                mediaOverlayPlayer.positionDescription
            return position.isEmpty ? "0 / 0" : position
        }
        return mediaOverlayPlayer
            .timelinePositionDescription
    }

    /// Android `hasToc`: 목차가 없으면 목차 버튼을 끈다(읽기 순서·페이지 목록만 있어도 켠다).
    private var hasContents: Bool {
        guard let book = viewModel.book else {
            return false
        }
        return !book.navigationItems.isEmpty
            || !book.pageListItems.isEmpty
            || book.chapters.count > 1
    }

    /// Android `RemoteModeOverlay.showModeName(DAISY)`: 리모컨이 이 화면을 조작하기 시작하면 모드 이름을 1.15초 띄운다.
    private func flashRemoteModeIfNeeded() {
        guard !didFlashRemoteMode else {
            return
        }
        didFlashRemoteMode = true
        remoteModeFlashTask?.cancel()
        remoteModeFlash = .daisy
        remoteModeFlashTask = Task {
            try? await Task.sleep(
                nanoseconds:
                    RivoRemoteKeyMode
                    .modeNameVisibleNanoseconds
            )
            guard !Task.isCancelled else {
                return
            }
            remoteModeFlash = nil
        }
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
            .visionCraftListScreen()
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

    /// Android `ReaderSearchSheet`: "본문 검색" · "검색어 입력" · 안내/개수 줄 · 2줄 스니펫(일치 부분 강조색).
    private var searchSheet: some View {
        NavigationStack {
            Group {
                let results = EPUBSearchEngine.search(
                    searchQuery,
                    in: viewModel.book?.chapters ?? []
                )
                let isQueryEmpty =
                    searchQuery.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                List {
                    Section {
                        Text(
                            isQueryEmpty
                                ? AppLocalization.string(
                                    "검색어를 입력하면 일치하는 문단을 찾습니다."
                                )
                                : results.isEmpty
                                    ? AppLocalization.string(
                                        "일치하는 결과가 없습니다."
                                    )
                                    : AppLocalization.format(
                                        "%lld개 일치",
                                        results.count
                                    )
                        )
                        .visionCraftAndroidText(
                            14,
                            relativeTo: .footnote
                        )
                        .foregroundStyle(
                            VisionCraftUI.secondaryText
                        )
                        .listRowBackground(Color.clear)
                    }
                    if !results.isEmpty {
                        Section {
                            ForEach(results) { result in
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
                                        spacing: 4
                                    ) {
                                        Text(result.chapterTitle)
                                            .visionCraftAndroidText(
                                                14,
                                                weight: .semibold,
                                                relativeTo: .footnote
                                            )
                                            .foregroundStyle(
                                                VisionCraftUI
                                                    .secondaryText
                                            )
                                            .lineLimit(1)
                                        highlightedText(
                                            result.snippet,
                                            start:
                                                result
                                                .matchStartInSnippet,
                                            length:
                                                result.matchLength
                                        )
                                        .visionCraftAndroidText(16)
                                        .foregroundStyle(
                                            VisionCraftUI.primaryText
                                        )
                                        .lineLimit(2)
                                    }
                                    .frame(
                                        maxWidth: .infinity,
                                        minHeight: 48,
                                        alignment: .leading
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle("본문 검색")
            .searchable(
                text: $searchQuery,
                placement:
                    .navigationBarDrawer(
                        displayMode: .always
                    ),
                prompt: "검색어 입력"
            )
            .visionCraftListScreen()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        isSearchPresented = false
                    }
                }
            }
        }
    }

    /// Android `ReaderSettingsSheet`: 읽기 설정 — 글자 크기(%) → 줄 간격(0.00) → 테마 칩 → 음성 속도(x).
    private var settingsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    readerSettingSlider(
                        label: "글자 크기",
                        value: $fontScale,
                        range: 0.8 ... 1.8,
                        step: 0.1,
                        valueLabel: "\(Int((fontScale * 100).rounded()))%"
                    )

                    readerSettingSlider(
                        label: "줄 간격",
                        value: $lineHeight,
                        range: 1.2 ... 2.2,
                        step: 0.1,
                        valueLabel: String(
                            format: "%.2f",
                            lineHeight
                        )
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("테마")
                            .visionCraftAndroidText(16)
                            .foregroundStyle(
                                VisionCraftUI.primaryText
                            )
                        HStack(spacing: 8) {
                            ForEach(EPUBReaderTheme.allCases) {
                                option in
                                themeChip(option)
                            }
                        }
                    }
                    .accessibilityElement(children: .contain)

                    readerSettingSlider(
                        label: "음성 속도",
                        value: $speechRate,
                        range: 0.5 ... 2.0,
                        step: 0.1,
                        valueLabel: String(
                            format: "%.2fx",
                            speechRate
                        )
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(
                            "출판물 원본 표현",
                            isOn: $usesOriginalLayout
                        )
                        .visionCraftAndroidText(16)
                        .tint(VisionCraftHomeUI.switchOn)
                        .frame(minHeight: 48)
                        Text(
                            "이미지, 표, 목록, 강조와 책 안 링크를 보존합니다. 정확한 검색·발화 강조가 필요하면 끄세요."
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
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .visionCraftListScreen()
            .navigationTitle("읽기 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        isSettingsPresented = false
                    }
                }
            }
        }
    }

    private func readerSettingSlider(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        valueLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(AppLocalization.string(label))
                    .visionCraftAndroidText(16)
                    .foregroundStyle(
                        VisionCraftUI.primaryText
                    )
                Spacer()
                Text(valueLabel)
                    .visionCraftAndroidText(
                        14,
                        weight: .medium,
                        relativeTo: .footnote
                    )
                    .monospacedDigit()
                    .foregroundStyle(
                        VisionCraftUI.secondaryText
                    )
            }
            Slider(
                value: value,
                in: range,
                step: step
            )
            .tint(VisionCraftUI.accent)
            .accessibilityLabel(
                AppLocalization.string(label)
            )
            .accessibilityValue(valueLabel)
        }
    }

    /// Android `ThemeOption`: 알약 칩, 선택 시 강조색 14% 채움 + 2pt 강조색 테두리.
    private func themeChip(
        _ option: EPUBReaderTheme
    ) -> some View {
        let isSelected = option == theme
        return Button {
            themeID = option.rawValue
        } label: {
            Text(option.title)
                .visionCraftAndroidText(16)
                .foregroundStyle(
                    isSelected
                        ? VisionCraftUI.accent
                        : VisionCraftUI.primaryText
                )
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .background(
                    isSelected
                        ? VisionCraftUI.accent.opacity(0.14)
                        : Color.clear,
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .strokeBorder(
                            isSelected
                                ? VisionCraftUI.accent
                                : VisionCraftUI.secondaryText
                                    .opacity(0.55),
                            lineWidth: isSelected ? 2 : 1
                        )
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(
            isSelected ? [.isSelected] : []
        )
    }

    /// 검색 일치는 강조색 굵게(Android `ReaderSearchSheet`), 읽는 단어는 #FFF3B0 배경(Android `UNIFIED_HIGHLIGHT`).
    private func highlightedText(
        _ text: String,
        start: Int?,
        length: Int,
        utf16Range: NSRange? = nil
    ) -> Text {
        var attributed = AttributedString(text)
        if let utf16Range,
           let stringRange = Range(utf16Range, in: text),
           let range = Range(stringRange, in: attributed) {
            attributed[range].backgroundColor =
                EPUBReaderTheme.readingHighlight
            attributed[range].foregroundColor =
                EPUBReaderTheme.readingHighlightText
            return Text(attributed)
        }
        guard let start,
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
              ),
              let range = Range(
                  lower ..< upper,
                  in: attributed
              ) else {
            return Text(text)
        }
        attributed[range].foregroundColor =
            VisionCraftUI.accent
        attributed[range].inlinePresentationIntent =
            .stronglyEmphasized
        return Text(attributed)
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
                theme.backgroundHex,
                theme.foregroundHex,
                "#005FCC"
            )
        case .sepia:
            colors = (
                theme.backgroundHex,
                theme.foregroundHex,
                "#7A3E00"
            )
        case .dark:
            colors = (
                theme.backgroundHex,
                theme.foregroundHex,
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
        flashRemoteModeIfNeeded()
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
