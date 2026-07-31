import AVFoundation
import Combine
import Foundation

nonisolated enum EPUBMediaOverlayPlaybackError:
    LocalizedError
{
    case audioMissing

    var errorDescription: String? {
        switch self {
        case .audioMissing:
            return AppLocalization.string(
                "책 안의 오디오 파일을 찾을 수 없습니다."
            )
        }
    }
}

nonisolated struct EPUBMediaOverlayLocation:
    Equatable,
    Sendable
{
    let itemIndex: Int
    let chapterIndex: Int
    let segmentIndex: Int
}

nonisolated enum EPUBMediaOverlayLocationResolver {
    static func location(
        for itemIndex: Int,
        items: [EPUBMediaOverlayItem],
        chapters: [EPUBChapter]
    ) -> EPUBMediaOverlayLocation? {
        guard items.indices.contains(itemIndex) else {
            return nil
        }
        let item = items[itemIndex]
        guard let chapterIndex =
                chapters.firstIndex(
                    where: {
                        $0.href == item.textPath
                    }
                ) else {
            return nil
        }
        let segmentIndex = item.textFragmentID.flatMap {
            chapters[chapterIndex]
                .fragmentSegmentIndexes[$0]
        } ?? 0
        return EPUBMediaOverlayLocation(
            itemIndex: itemIndex,
            chapterIndex: chapterIndex,
            segmentIndex: segmentIndex
        )
    }

    static func nearestItemIndex(
        chapterIndex: Int,
        segmentIndex: Int,
        items: [EPUBMediaOverlayItem],
        chapters: [EPUBChapter]
    ) -> Int? {
        var best: (
            itemIndex: Int,
            distance: Int
        )?
        for itemIndex in items.indices {
            guard let location = location(
                for: itemIndex,
                items: items,
                chapters: chapters
            ),
            location.chapterIndex == chapterIndex else {
                continue
            }
            let distance = abs(
                location.segmentIndex - segmentIndex
            )
            if best == nil
                || distance < best!.distance {
                best = (itemIndex, distance)
            }
        }
        return best?.itemIndex
    }
}

actor EPUBMediaOverlayResourceStore {
    private let bookURL: URL
    private let extractionDirectory: URL
    private var archive: EPUBArchive?
    private var extractedURLs: [String: URL] = [:]

    init(
        bookURL: URL,
        temporaryDirectory: URL =
            FileManager.default.temporaryDirectory
    ) {
        self.bookURL = bookURL
        self.extractionDirectory = temporaryDirectory
            .appendingPathComponent(
                "RivoEPUBAudio-\(UUID().uuidString)",
                isDirectory: true
            )
    }

    deinit {
        try? FileManager.default.removeItem(
            at: extractionDirectory
        )
    }

    func audioURL(
        for rawPath: String
    ) throws -> URL {
        let path = try EPUBArchive.normalizedPath(
            rawPath
        )
        if let cached = extractedURLs[path],
           FileManager.default.fileExists(
               atPath: cached.path
           ) {
            return cached
        }

        let archive = try loadedArchive()
        guard archive.contains(path) else {
            throw EPUBMediaOverlayPlaybackError
                .audioMissing
        }
        let audio = try archive.data(at: path)
        let destination = extractionDirectory
            .appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: destination
                .deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try audio.write(
            to: destination,
            options: .atomic
        )
        extractedURLs[path] = destination
        return destination
    }

    private func loadedArchive() throws -> EPUBArchive {
        if let archive {
            return archive
        }
        let data = try Data(
            contentsOf: bookURL,
            options: .mappedIfSafe
        )
        let loaded = try EPUBArchive(data: data)
        archive = loaded
        return loaded
    }
}

nonisolated struct EPUBReadAloudStep:
    Identifiable,
    Equatable,
    Sendable
{
    let id: String
    let chapterIndex: Int
    let segmentIndex: Int
    let text: String
    let audioItemIndex: Int?
}

nonisolated enum EPUBReadAloudSequence {
    static func steps(
        for book: EPUBBook
    ) -> [EPUBReadAloudStep] {
        var audioByLocation:
            [LocationKey: [Int]] = [:]
        for itemIndex
            in book.mediaOverlayItems.indices {
            guard let location =
                    EPUBMediaOverlayLocationResolver
                    .location(
                        for: itemIndex,
                        items:
                            book.mediaOverlayItems,
                        chapters: book.chapters
                    ) else {
                continue
            }
            let key = LocationKey(
                chapterIndex:
                    location.chapterIndex,
                segmentIndex:
                    location.segmentIndex
            )
            audioByLocation[key, default: []]
                .append(itemIndex)
        }

        var result: [EPUBReadAloudStep] = []
        for (chapterIndex, chapter)
            in book.chapters.enumerated() {
            let segments =
                EPUBTextSegmenter.segments(
                    in: chapter
                )
            for (segmentIndex, segment)
                in segments.enumerated() {
                let key = LocationKey(
                    chapterIndex: chapterIndex,
                    segmentIndex: segmentIndex
                )
                let audioIndexes =
                    audioByLocation[key] ?? []
                if audioIndexes.isEmpty {
                    result.append(
                        EPUBReadAloudStep(
                            id:
                                "\(segment.id)-tts",
                            chapterIndex:
                                chapterIndex,
                            segmentIndex:
                                segmentIndex,
                            text: segment.text,
                            audioItemIndex: nil
                        )
                    )
                } else {
                    for itemIndex in audioIndexes {
                        result.append(
                            EPUBReadAloudStep(
                                id:
                                    "\(segment.id)-audio-"
                                    + "\(itemIndex)",
                                chapterIndex:
                                    chapterIndex,
                                segmentIndex:
                                    segmentIndex,
                                text: segment.text,
                                audioItemIndex:
                                    itemIndex
                            )
                        )
                    }
                }
            }
        }
        return result
    }

    static func stepIndex(
        chapterIndex: Int,
        segmentIndex: Int,
        in steps: [EPUBReadAloudStep]
    ) -> Int? {
        steps.firstIndex {
            $0.chapterIndex == chapterIndex
                && $0.segmentIndex
                == segmentIndex
        }
    }

    private struct LocationKey: Hashable {
        let chapterIndex: Int
        let segmentIndex: Int
    }
}

nonisolated struct EPUBReadAloudTextRange:
    Equatable,
    Sendable
{
    let chapterIndex: Int
    let segmentIndex: Int
    let location: Int
    let length: Int
}

nonisolated enum EPUBReadAloudNavigationUnit:
    Int,
    CaseIterable,
    Equatable,
    Sendable
{
    case word
    case sentence
    case paragraph
    case page
    case chapter

    var displayName: String {
        switch self {
        case .word:
            return AppLocalization.string(
                "단어"
            )
        case .sentence:
            return AppLocalization.string(
                "문장"
            )
        case .paragraph:
            return AppLocalization.string(
                "문단"
            )
        case .page:
            return AppLocalization.string(
                "페이지"
            )
        case .chapter:
            return AppLocalization.string(
                "장"
            )
        }
    }

    func next() -> Self {
        shifted(by: 1)
    }

    func shifted(by delta: Int) -> Self {
        let units = Self.allCases
        let offset =
            (rawValue + delta) % units.count
        return units[
            offset >= 0
                ? offset
                : offset + units.count
        ]
    }
}

nonisolated enum EPUBReadAloudTextNavigator {
    static func ranges(
        in text: String,
        unit: EPUBReadAloudNavigationUnit
    ) -> [NSRange] {
        switch unit {
        case .word:
            return regularExpressionRanges(
                pattern: #"\S+"#,
                in: text
            )
        case .sentence:
            var result: [NSRange] = []
            text.enumerateSubstrings(
                in: text.startIndex ..< text.endIndex,
                options: [
                    .bySentences,
                    .substringNotRequired,
                ]
            ) { _, range, _, _ in
                result.append(
                    NSRange(range, in: text)
                )
            }
            if result.isEmpty,
               !text.isEmpty {
                return [
                    NSRange(
                        location: 0,
                        length:
                            (text as NSString).length
                    ),
                ]
            }
            return result
        case .paragraph, .page, .chapter:
            guard !text.isEmpty else {
                return []
            }
            return [
                NSRange(
                    location: 0,
                    length:
                        (text as NSString).length
                ),
            ]
        }
    }

    static func range(
        atOrAfterUTF16 location: Int,
        in text: String,
        unit: EPUBReadAloudNavigationUnit
    ) -> NSRange? {
        let ranges = ranges(
            in: text,
            unit: unit
        )
        return ranges.first {
            NSMaxRange($0) > location
        } ?? ranges.last
    }

    static func speechRange(
        in text: String,
        fromUTF16 requestedStart: Int
    ) -> NSRange? {
        let string = text as NSString
        guard string.length > 0 else {
            return nil
        }
        let clampedStart = min(
            max(requestedStart, 0),
            string.length
        )
        guard clampedStart < string.length else {
            return nil
        }
        let remaining = NSRange(
            location: clampedStart,
            length: string.length - clampedStart
        )
        let firstContent = string.rangeOfCharacter(
            from:
                CharacterSet
                .whitespacesAndNewlines
                .inverted,
            options: [],
            range: remaining
        )
        guard firstContent.location != NSNotFound else {
            return nil
        }
        let start = firstContent.location
        let sentenceRanges = ranges(
            in: text,
            unit: .sentence
        )
        let sentenceEnd =
            sentenceRanges.first {
                NSMaxRange($0) > start
            }.map(NSMaxRange)
            ?? string.length
        return NSRange(
            location: start,
            length:
                max(sentenceEnd - start, 0)
        )
    }

    private static func regularExpressionRanges(
        pattern: String,
        in text: String
    ) -> [NSRange] {
        guard let expression =
                try? NSRegularExpression(
                    pattern: pattern
                ) else {
            return []
        }
        let fullRange = NSRange(
            location: 0,
            length: (text as NSString).length
        )
        return expression.matches(
            in: text,
            range: fullRange
        ).map(\.range)
    }
}

nonisolated enum EPUBReadAloudPlaybackMode:
    Equatable,
    Sendable
{
    case none
    case audio
    case textToSpeech

    var displayName: String {
        switch self {
        case .none:
            return ""
        case .audio:
            return AppLocalization.string(
                "오디오"
            )
        case .textToSpeech:
            return AppLocalization.string(
                "로컬 음성"
            )
        }
    }
}

nonisolated enum EPUBReadAloudLanguageResolver {
    static func language(
        declared: String?,
        sample: String
    ) -> String {
        let declared = declared?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .replacingOccurrences(
                of: "_",
                with: "-"
            )
        let fallback: String
        if let declared,
           !declared.isEmpty {
            fallback = declared
        } else {
            fallback = "ko-KR"
        }
        var scores: [Script: Int] = [:]
        for scalar in sample.unicodeScalars {
            guard let script = script(
                for: scalar.value
            ) else {
                continue
            }
            scores[script, default: 0] += 1
        }
        guard var dominant = scores.max(
            by: { $0.value < $1.value }
        )?.key else {
            return fallback
        }
        if dominant == .chinese,
           scores[.japanese, default: 0] > 0 {
            dominant = .japanese
        }
        guard dominant != .latin else {
            return fallback
        }
        let language = dominant.language
        if fallback.lowercased()
            .hasPrefix(language) {
            return fallback
        }
        return dominant.languageTag
    }

    private static func script(
        for value: UInt32
    ) -> Script? {
        switch value {
        case 0xAC00 ... 0xD7AF,
             0x1100 ... 0x11FF,
             0x3130 ... 0x318F:
            return .korean
        case 0x3040 ... 0x30FF,
             0x31F0 ... 0x31FF:
            return .japanese
        case 0x4E00 ... 0x9FFF:
            return .chinese
        case 0x0E01 ... 0x0E5B:
            return .thai
        case 0x0600 ... 0x06FF,
             0x0750 ... 0x077F:
            return .arabic
        case 0x0400 ... 0x04FF:
            return .cyrillic
        case 0x0041 ... 0x005A,
             0x0061 ... 0x007A,
             0x00C0 ... 0x024F:
            return .latin
        default:
            return nil
        }
    }

    private enum Script: Hashable {
        case korean
        case japanese
        case chinese
        case thai
        case arabic
        case cyrillic
        case latin

        var language: String {
            switch self {
            case .korean:
                return "ko"
            case .japanese:
                return "ja"
            case .chinese:
                return "zh"
            case .thai:
                return "th"
            case .arabic:
                return "ar"
            case .cyrillic:
                return "ru"
            case .latin:
                return "en"
            }
        }

        var languageTag: String {
            switch self {
            case .korean:
                return "ko-KR"
            case .japanese:
                return "ja-JP"
            case .chinese:
                return "zh-CN"
            case .thai:
                return "th-TH"
            case .arabic:
                return "ar-SA"
            case .cyrillic:
                return "ru-RU"
            case .latin:
                return "en-US"
            }
        }
    }
}

@MainActor
final class EPUBMediaOverlayPlaybackController:
    NSObject,
    ObservableObject
{
    @Published private(set) var currentItemIndex =
        0
    @Published private(set) var currentLocation:
        EPUBMediaOverlayLocation?
    @Published private(set) var currentTimeSeconds = 0.0
    @Published private(set) var timelinePositionSeconds =
        0.0
    @Published private(set) var totalTimelineSeconds =
        0.0
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var errorDescription: String?
    @Published private(set) var playbackMode:
        EPUBReadAloudPlaybackMode = .none
    @Published private(set) var currentTextRange:
        EPUBReadAloudTextRange?
    @Published private(set) var navigationUnit:
        EPUBReadAloudNavigationUnit = .paragraph

    private let player = AVPlayer()
    private let speechSynthesizer =
        AVSpeechSynthesizer()
    private let resourceStore:
        EPUBMediaOverlayResourceStore
    private var book: EPUBBook?
    private var items: [EPUBMediaOverlayItem] = []
    private var steps: [EPUBReadAloudStep] = []
    private var timeline = EPUBReadAloudTimeline(
        steps: [],
        items: [],
        speechRate: 1
    )
    private var speechLanguage = "ko-KR"
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var loadedItemID: String?
    private var currentUtteranceID:
        ObjectIdentifier?
    private var spokenStepID: String?
    private var speechStartUTF16 = 0
    private var speechEndUTF16 = 0
    private var playbackRate: Float = 1
    private var pendingAudioStartSeconds:
        Double?
    private var pendingSpeechStartUTF16:
        Int?

    init(fileURL: URL) {
        resourceStore =
            EPUBMediaOverlayResourceStore(
                bookURL: fileURL
            )
        super.init()
        speechSynthesizer.delegate = self
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(
                seconds: 0.1,
                preferredTimescale: 600
            ),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.notePlaybackTime(time)
            }
        }
    }

    deinit {
        loadTask?.cancel()
        speechSynthesizer
            .stopSpeaking(at: .immediate)
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default
                .removeObserver(endObserver)
        }
    }

    var canPlay: Bool {
        !steps.isEmpty
    }

    private var canMoveNext: Bool {
        steps.indices.contains(
            currentItemIndex + 1
        )
    }

    var canNavigatePrevious: Bool {
        navigationTarget(
            delta: -1
        ) != nil
    }

    var canNavigateNext: Bool {
        navigationTarget(
            delta: 1
        ) != nil
    }

    var positionDescription: String {
        guard !steps.isEmpty else {
            return ""
        }
        return "\(currentItemIndex + 1) / \(steps.count)"
    }

    var playbackModeDescription: String {
        playbackMode.displayName
    }

    var timelinePositionDescription: String {
        "\(Self.durationDescription(timelinePositionSeconds)) / "
            + Self.durationDescription(
                totalTimelineSeconds
            )
    }

    func timelineDescription(
        at seconds: Double
    ) -> String {
        "\(Self.durationDescription(seconds)) / "
            + Self.durationDescription(
                totalTimelineSeconds
            )
    }

    var timelineProgress: Double {
        guard totalTimelineSeconds > 0 else {
            return 0
        }
        return min(
            max(
                timelinePositionSeconds
                    / totalTimelineSeconds,
                0
            ),
            1
        )
    }

    var navigationUnitDescription: String {
        navigationUnit.displayName
    }

    func configure(
        book: EPUBBook,
        chapterIndex: Int,
        segmentIndex: Int
    ) {
        pause()
        cancelLoad()
        removeEndObserver()
        stopSpeech()
        player.replaceCurrentItem(with: nil)
        self.book = book
        items = book.mediaOverlayItems
        steps = EPUBReadAloudSequence.steps(
            for: book
        )
        rebuildTimeline()
        let languageSample =
            (
                [book.title]
                + steps.map(\.text)
            )
            .joined(separator: " ")
            .prefix(2_000)
        speechLanguage =
            EPUBReadAloudLanguageResolver
            .language(
                declared: book.language,
                sample:
                    String(languageSample)
            )
        currentItemIndex =
            EPUBReadAloudSequence.stepIndex(
                chapterIndex: chapterIndex,
                segmentIndex: segmentIndex,
                in: steps
            ) ?? 0
        currentLocation = location(
            forStepAt: currentItemIndex
        )
        currentTimeSeconds = clipBegin(
            forStepAt: currentItemIndex
        ) ?? 0
        loadedItemID = nil
        spokenStepID = nil
        currentTextRange = nil
        pendingAudioStartSeconds = nil
        pendingSpeechStartUTF16 = nil
        playbackMode = .none
        errorDescription = nil
        updateTimelinePosition()
    }

    func cycleNavigationUnit() {
        cycleNavigationUnit(by: 1)
    }

    func cycleNavigationUnit(by delta: Int) {
        guard delta != 0 else {
            return
        }
        navigationUnit =
            navigationUnit.shifted(by: delta)
    }

    func setRate(_ value: Double) {
        playbackRate = Float(
            min(max(value, 0.5), 2)
        )
        rebuildTimeline()
        updateTimelinePosition()
        if isPlaying,
           playbackMode == .audio {
            player.rate = playbackRate
        }
    }

    func togglePlayback() {
        if isPlaying {
            pause()
            return
        }
        guard steps.indices.contains(
            currentItemIndex
        ) else {
            return
        }
        let step = steps[currentItemIndex]
        if spokenStepID == step.id,
           speechSynthesizer.isPaused {
            isPlaying =
                speechSynthesizer
                .continueSpeaking()
            playbackMode = isPlaying
                ? .textToSpeech
                : .none
        } else if let audioItemIndex =
                step.audioItemIndex,
           items.indices.contains(
               audioItemIndex
           ),
           loadedItemID
            == items[audioItemIndex].id {
            AppAudioManager.shared.configure()
            currentLocation = location(
                forStepAt: currentItemIndex
            )
            isPlaying = true
            playbackMode = .audio
            player.playImmediately(
                atRate: playbackRate
            )
        } else {
            activateStep(
                index: currentItemIndex,
                autoplay: true,
                speechStartUTF16:
                    pendingSpeechStartUTF16,
                selectedTextRange:
                    currentTextRange.map {
                        NSRange(
                            location: $0.location,
                            length: $0.length
                        )
                    },
                audioStartSeconds:
                    pendingAudioStartSeconds
            )
        }
    }

    func pause() {
        player.pause()
        if speechSynthesizer.isSpeaking {
            _ = speechSynthesizer
                .pauseSpeaking(
                    at: .immediate
                )
        }
        isPlaying = false
    }

    func stop() {
        pause()
        cancelLoad()
        stopSpeech()
        if let begin = clipBegin(
            forStepAt: currentItemIndex
        ) {
            player.seek(
                to: CMTime(
                    seconds: begin,
                    preferredTimescale: 600
                ),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
            currentTimeSeconds = begin
        } else {
            currentTimeSeconds = 0
        }
        pendingAudioStartSeconds =
            clipBegin(
                forStepAt: currentItemIndex
            )
        pendingSpeechStartUTF16 = 0
        currentTextRange = nil
        playbackMode = .none
        updateTimelinePosition()
    }

    func seek(
        toTimelineSeconds requestedSeconds: Double,
        autoplay: Bool
    ) {
        guard let target = timeline.target(
            at: requestedSeconds
        ),
        steps.indices.contains(
            target.stepIndex
        ) else {
            return
        }
        let step = steps[target.stepIndex]
        let selectedRange =
            EPUBReadAloudTextNavigator.range(
                atOrAfterUTF16:
                    target.textUTF16Offset,
                in: step.text,
                unit: .word
            )
        activateStep(
            index: target.stepIndex,
            autoplay: autoplay,
            speechStartUTF16:
                target.textUTF16Offset,
            selectedTextRange:
                selectedRange,
            audioStartSeconds:
                target.audioTimeSeconds
        )
        timelinePositionSeconds =
            target.timelineSeconds
    }

    func navigate(by delta: Int) {
        guard delta != 0,
              let target =
                navigationTarget(
                    delta: delta
                ) else {
            return
        }
        let shouldResume = isPlaying
        activateStep(
            index: target.stepIndex,
            autoplay: shouldResume,
            speechStartUTF16:
                target.textRange?.location,
            selectedTextRange:
                target.textRange
        )
    }

    private func navigationTarget(
        delta: Int
    ) -> NavigationTarget? {
        guard steps.indices.contains(
                  currentItemIndex
              ) else {
            return nil
        }
        let direction = delta < 0 ? -1 : 1
        switch navigationUnit {
        case .word, .sentence:
            return inlineNavigationTarget(
                unit: navigationUnit,
                direction: direction
            )
        case .paragraph:
            return distinctLocationTarget(
                direction: direction
            )
        case .page:
            return pageTarget(
                direction: direction
            )
        case .chapter:
            return chapterTarget(
                direction: direction
            )
        }
    }

    private func inlineNavigationTarget(
        unit: EPUBReadAloudNavigationUnit,
        direction: Int
    ) -> NavigationTarget? {
        let step = steps[currentItemIndex]
        guard step.audioItemIndex == nil else {
            return distinctLocationTarget(
                direction: direction
            )
        }
        let ranges =
            EPUBReadAloudTextNavigator.ranges(
                in: step.text,
                unit: unit
            )
        guard !ranges.isEmpty else {
            return distinctLocationTarget(
                direction: direction
            )
        }
        let rangeLocation: Int
        if let currentTextRange,
           currentTextRange.chapterIndex
            == step.chapterIndex,
           currentTextRange.segmentIndex
            == step.segmentIndex {
            rangeLocation =
                currentTextRange.location
        } else {
            rangeLocation = ranges[0].location
        }
        let currentRangeIndex =
            ranges.lastIndex {
                $0.location <= rangeLocation
            } ?? 0
        let targetRangeIndex =
            currentRangeIndex + direction
        if ranges.indices.contains(
            targetRangeIndex
        ) {
            return NavigationTarget(
                stepIndex: currentItemIndex,
                textRange:
                    ranges[targetRangeIndex]
            )
        }

        guard let adjacent =
                distinctLocationTarget(
                    direction: direction
                ) else {
            return nil
        }
        let adjacentStep =
            steps[adjacent.stepIndex]
        guard adjacentStep.audioItemIndex == nil else {
            return adjacent
        }
        let adjacentRanges =
            EPUBReadAloudTextNavigator.ranges(
                in: adjacentStep.text,
                unit: unit
            )
        return NavigationTarget(
            stepIndex: adjacent.stepIndex,
            textRange:
                direction > 0
                ? adjacentRanges.first
                : adjacentRanges.last
        )
    }

    private func distinctLocationTarget(
        direction: Int
    ) -> NavigationTarget? {
        let current = steps[currentItemIndex]
        var index =
            currentItemIndex + direction
        while steps.indices.contains(index) {
            let candidate = steps[index]
            if candidate.chapterIndex
                    != current.chapterIndex
                || candidate.segmentIndex
                    != current.segmentIndex {
                let firstIndex =
                    steps.firstIndex {
                        $0.chapterIndex
                            == candidate.chapterIndex
                            && $0.segmentIndex
                            == candidate.segmentIndex
                    } ?? index
                return NavigationTarget(
                    stepIndex: firstIndex,
                    textRange: nil
                )
            }
            index += direction
        }
        return nil
    }

    private func pageTarget(
        direction: Int
    ) -> NavigationTarget? {
        guard let book else {
            return nil
        }
        let breakpointIndexes: [Int] =
            book.pageListItems.compactMap {
                item -> Int? in
                    guard let location =
                            PublicationNavigationResolver
                            .location(
                                for: item,
                                in: book
                            ) else {
                        return nil
                    }
                    return EPUBReadAloudSequence
                        .stepIndex(
                            chapterIndex:
                                location
                                .chapterIndex,
                            segmentIndex:
                                location
                                .segmentIndex,
                            in: steps
                        )
            }
        let breakpoints =
            Array(Set(breakpointIndexes))
            .sorted()
        guard !breakpoints.isEmpty else {
            return approximatePageTarget(
                direction: direction
            )
        }
        let currentBreakpoint =
            breakpoints.lastIndex {
                $0 <= currentItemIndex
            } ?? 0
        let targetIndex =
            currentBreakpoint + direction
        guard breakpoints.indices.contains(
            targetIndex
        ) else {
            return nil
        }
        return NavigationTarget(
            stepIndex:
                breakpoints[targetIndex],
            textRange: nil
        )
    }

    private func approximatePageTarget(
        direction: Int,
        charactersPerPage: Int = 500
    ) -> NavigationTarget? {
        var paragraphStarts: [Int] = []
        var lastChapter: Int?
        var lastSegment: Int?
        for index in steps.indices {
            let step = steps[index]
            if step.chapterIndex != lastChapter
                || step.segmentIndex != lastSegment {
                paragraphStarts.append(index)
                lastChapter = step.chapterIndex
                lastSegment = step.segmentIndex
            }
        }
        guard let currentParagraph =
                paragraphStarts.lastIndex(
                    where: {
                        $0 <= currentItemIndex
                    }
                ) else {
            return nil
        }
        var targetParagraph =
            currentParagraph
        var accumulated = 0
        if direction > 0 {
            while targetParagraph
                    < paragraphStarts.count - 1,
                  accumulated
                    < charactersPerPage {
                accumulated +=
                    (
                        steps[
                            paragraphStarts[
                                targetParagraph
                            ]
                        ].text
                        as NSString
                    ).length
                targetParagraph += 1
            }
        } else {
            while targetParagraph > 0,
                  accumulated
                    < charactersPerPage {
                targetParagraph -= 1
                accumulated +=
                    (
                        steps[
                            paragraphStarts[
                                targetParagraph
                            ]
                        ].text
                        as NSString
                    ).length
            }
        }
        guard targetParagraph
                != currentParagraph else {
            return nil
        }
        return NavigationTarget(
            stepIndex:
                paragraphStarts[targetParagraph],
            textRange: nil
        )
    }

    private func chapterTarget(
        direction: Int
    ) -> NavigationTarget? {
        let currentChapter =
            steps[currentItemIndex].chapterIndex
        let targetChapter =
            currentChapter + direction
        guard let targetIndex =
                steps.firstIndex(
                    where: {
                        $0.chapterIndex
                            == targetChapter
                    }
                ) else {
            return nil
        }
        return NavigationTarget(
            stepIndex: targetIndex,
            textRange: nil
        )
    }

    func selectLocation(
        chapterIndex: Int,
        segmentIndex: Int,
        autoplay: Bool = false
    ) {
        guard let target =
                EPUBReadAloudSequence.stepIndex(
                    chapterIndex: chapterIndex,
                    segmentIndex: segmentIndex,
                    in: steps
                ) else {
            pause()
            return
        }
        startStep(
            index: target,
            autoplay: autoplay
        )
    }

    private func startStep(
        index: Int,
        autoplay: Bool
    ) {
        activateStep(
            index: index,
            autoplay: autoplay,
            speechStartUTF16: nil,
            selectedTextRange: nil
        )
    }

    private struct NavigationTarget {
        let stepIndex: Int
        let textRange: NSRange?
    }

    private func activateStep(
        index: Int,
        autoplay: Bool,
        speechStartUTF16: Int?,
        selectedTextRange: NSRange?,
        audioStartSeconds: Double? = nil
    ) {
        guard steps.indices.contains(index) else {
            return
        }
        cancelLoad()
        player.pause()
        stopSpeech()
        isPlaying = false
        isLoading = false
        playbackMode = .none
        errorDescription = nil
        currentItemIndex = index
        currentLocation = location(
            forStepAt: index
        )
        currentTextRange =
            selectedTextRange.flatMap {
                textRange(
                    forStepAt: index,
                    range: $0
                )
            }
        let requestedAudioStart =
            audioStartSeconds
            ?? clipBegin(forStepAt: index)
        currentTimeSeconds =
            requestedAudioStart ?? 0
        pendingAudioStartSeconds =
            requestedAudioStart
        pendingSpeechStartUTF16 =
            speechStartUTF16
        if let audioItemIndex =
                steps[index].audioItemIndex,
           items.indices.contains(
               audioItemIndex
           ),
           loadedItemID
            == items[audioItemIndex].id,
           let requestedAudioStart {
            player.seek(
                to: CMTime(
                    seconds:
                        requestedAudioStart,
                    preferredTimescale: 600
                ),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
        }
        updateTimelinePosition()
        guard autoplay else {
            return
        }
        if let audioItemIndex =
                steps[index].audioItemIndex {
            scheduleAudioLoad(
                stepIndex: index,
                audioItemIndex:
                    audioItemIndex,
                startTimeSeconds:
                    requestedAudioStart
            )
        } else {
            startSpeech(
                stepIndex: index,
                fromUTF16:
                    speechStartUTF16 ?? 0
            )
        }
    }

    private func scheduleAudioLoad(
        stepIndex: Int,
        audioItemIndex: Int,
        startTimeSeconds: Double?
    ) {
        guard steps.indices.contains(
                  stepIndex
              ),
              items.indices.contains(
                  audioItemIndex
              ) else {
            return
        }
        isLoading = true
        loadGeneration &+= 1
        let generation = loadGeneration
        let audioPath =
            items[audioItemIndex].audioPath
        loadTask = Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let url = try await resourceStore
                    .audioURL(for: audioPath)
                guard !Task.isCancelled,
                      generation
                        == self.loadGeneration else {
                    return
                }
                self.finishAudioLoad(
                    url: url,
                    stepIndex: stepIndex,
                    audioItemIndex:
                        audioItemIndex,
                    startTimeSeconds:
                        startTimeSeconds
                )
            } catch {
                guard !Task.isCancelled,
                      generation
                        == self.loadGeneration else {
                    return
                }
                self.isLoading = false
                self.loadTask = nil
                self.errorDescription =
                    AppLocalization.string(
                        "오디오를 열 수 없어 로컬 음성으로 읽습니다."
                    )
                self.startSpeech(
                    stepIndex: stepIndex,
                    fromUTF16:
                        self
                            .pendingSpeechStartUTF16
                        ?? 0
                )
            }
        }
    }

    private func finishAudioLoad(
        url: URL,
        stepIndex: Int,
        audioItemIndex: Int,
        startTimeSeconds: Double?
    ) {
        guard steps.indices.contains(
                  stepIndex
              ),
              items.indices.contains(
                  audioItemIndex
              ),
              stepIndex == currentItemIndex else {
            return
        }
        removeEndObserver()
        let overlay = items[audioItemIndex]
        let playerItem = AVPlayerItem(url: url)
        if let end = overlay.clipEndSeconds,
           end > overlay.clipBeginSeconds {
            playerItem.forwardPlaybackEndTime =
                CMTime(
                    seconds: end,
                    preferredTimescale: 600
                )
        }
        player.replaceCurrentItem(
            with: playerItem
        )
        loadedItemID = overlay.id
        let expectedStepID =
            steps[stepIndex].id
        endObserver = NotificationCenter.default
            .addObserver(
                forName:
                    .AVPlayerItemDidPlayToEndTime,
                object: playerItem,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.finishCurrentStep(
                        expectedStepID:
                            expectedStepID
                    )
                }
            }
        let requestedStart = min(
            max(
                startTimeSeconds
                    ?? overlay
                        .clipBeginSeconds,
                overlay.clipBeginSeconds
            ),
            overlay.clipEndSeconds
                ?? Double.greatestFiniteMagnitude
        )
        player.seek(
            to: CMTime(
                seconds: requestedStart,
                preferredTimescale: 600
            ),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        currentTimeSeconds = requestedStart
        pendingAudioStartSeconds =
            requestedStart
        updateTimelinePosition()
        isLoading = false
        loadTask = nil
        AppAudioManager.shared.configure()
        isPlaying = true
        playbackMode = .audio
        player.playImmediately(
            atRate: playbackRate
        )
    }

    private func notePlaybackTime(_ time: CMTime) {
        guard time.isNumeric else {
            return
        }
        currentTimeSeconds = max(
            time.seconds,
            0
        )
        updateTimelinePosition()
        guard isPlaying,
              playbackMode == .audio,
              !isLoading,
              steps.indices.contains(
                  currentItemIndex
              ),
              let audioItemIndex =
                  steps[currentItemIndex]
                  .audioItemIndex,
              items.indices.contains(
                  audioItemIndex
              ),
              let end =
                  items[audioItemIndex]
                  .clipEndSeconds,
              end
                > items[audioItemIndex]
                .clipBeginSeconds,
              currentTimeSeconds
                >= end - 0.03 else {
            return
        }
        finishCurrentStep(
            expectedStepID:
                steps[currentItemIndex].id
        )
    }

    private func startSpeech(
        stepIndex: Int,
        fromUTF16 requestedStart: Int = 0
    ) {
        guard steps.indices.contains(
                  stepIndex
              ),
              stepIndex == currentItemIndex else {
            return
        }
        let step = steps[stepIndex]
        let text = step.text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !text.isEmpty else {
            isPlaying = true
            finishCurrentStep(
                expectedStepID: step.id
            )
            return
        }
        guard let speechRange =
                EPUBReadAloudTextNavigator
                .speechRange(
                    in: text,
                    fromUTF16:
                        requestedStart
                ),
              let range =
                Range(
                    speechRange,
                    in: text
                ) else {
            isPlaying = true
            finishCurrentStep(
                expectedStepID: step.id
            )
            return
        }
        let utterance = AVSpeechUtterance(
            string: String(text[range])
        )
        utterance.voice =
            preferredVoice(
                language: speechLanguage
            )
        utterance.rate = min(
            max(
                AVSpeechUtteranceDefaultSpeechRate
                    * playbackRate,
                AVSpeechUtteranceMinimumSpeechRate
            ),
            AVSpeechUtteranceMaximumSpeechRate
        )
        currentUtteranceID =
            ObjectIdentifier(utterance)
        spokenStepID = step.id
        speechStartUTF16 =
            speechRange.location
        speechEndUTF16 =
            NSMaxRange(speechRange)
        pendingSpeechStartUTF16 =
            speechRange.location
        if let initialRange =
                EPUBReadAloudTextNavigator
                .range(
                    atOrAfterUTF16:
                        speechRange.location,
                    in: text,
                    unit: .word
                ) {
            currentTextRange =
                textRange(
                    forStepAt: stepIndex,
                    range: initialRange
                )
        }
        playbackMode = .textToSpeech
        updateTimelinePosition()
        currentLocation = location(
            forStepAt: stepIndex
        )
        AppAudioManager.shared.configure()
        isPlaying = true
        speechSynthesizer.speak(utterance)
    }

    private func finishCurrentStep(
        expectedStepID: String
    ) {
        guard isPlaying,
              steps.indices.contains(
                  currentItemIndex
              ),
              steps[currentItemIndex].id
                == expectedStepID else {
            return
        }
        if canMoveNext {
            startStep(
                index: currentItemIndex + 1,
                autoplay: true
            )
        } else {
            pause()
            playbackMode = .none
        }
    }

    private func finishSpeech(
        utteranceID: ObjectIdentifier
    ) {
        guard currentUtteranceID
                == utteranceID,
              let spokenStepID else {
            return
        }
        currentUtteranceID = nil
        if steps.indices.contains(
               currentItemIndex
           ),
           steps[currentItemIndex].id
            == spokenStepID,
           speechEndUTF16
            < (
                steps[currentItemIndex].text
                    as NSString
            ).length {
            startSpeech(
                stepIndex: currentItemIndex,
                fromUTF16: speechEndUTF16
            )
            return
        }
        finishCurrentStep(
            expectedStepID: spokenStepID
        )
    }

    private func noteSpeechRange(
        _ range: NSRange,
        utteranceID: ObjectIdentifier
    ) {
        guard currentUtteranceID
                == utteranceID,
              steps.indices.contains(
                  currentItemIndex
              ) else {
            return
        }
        let textLength =
            (
                steps[currentItemIndex].text
                    as NSString
            ).length
        let location = min(
            max(
                speechStartUTF16
                    + range.location,
                0
            ),
            textLength
        )
        let length = min(
            max(range.length, 0),
            max(textLength - location, 0)
        )
        guard length > 0 else {
            return
        }
        currentTextRange =
            textRange(
                forStepAt: currentItemIndex,
                range: NSRange(
                    location: location,
                    length: length
                )
            )
        pendingSpeechStartUTF16 =
            location
        updateTimelinePosition()
    }

    private func stopSpeech() {
        currentUtteranceID = nil
        spokenStepID = nil
        if speechSynthesizer.isSpeaking
            || speechSynthesizer.isPaused {
            speechSynthesizer
                .stopSpeaking(at: .immediate)
        }
    }

    private func preferredVoice(
        language: String?
    ) -> AVSpeechSynthesisVoice? {
        if let language =
                language?.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
           !language.isEmpty,
           let voice =
                AVSpeechSynthesisVoice(
                    language:
                        language.replacingOccurrences(
                            of: "_",
                            with: "-"
                        )
                ) {
            return voice
        }
        return AVSpeechSynthesisVoice(
            language: "ko-KR"
        )
    }

    private func location(
        forStepAt index: Int
    ) -> EPUBMediaOverlayLocation? {
        guard steps.indices.contains(index) else {
            return nil
        }
        let step = steps[index]
        return EPUBMediaOverlayLocation(
            itemIndex: index,
            chapterIndex: step.chapterIndex,
            segmentIndex: step.segmentIndex
        )
    }

    private func textRange(
        forStepAt index: Int,
        range: NSRange
    ) -> EPUBReadAloudTextRange? {
        guard steps.indices.contains(index) else {
            return nil
        }
        let step = steps[index]
        return EPUBReadAloudTextRange(
            chapterIndex: step.chapterIndex,
            segmentIndex: step.segmentIndex,
            location: range.location,
            length: range.length
        )
    }

    private func clipBegin(
        forStepAt index: Int
    ) -> Double? {
        guard steps.indices.contains(index),
              let audioItemIndex =
                  steps[index].audioItemIndex,
              items.indices.contains(
                  audioItemIndex
              ) else {
            return nil
        }
        return items[audioItemIndex]
            .clipBeginSeconds
    }

    private func rebuildTimeline() {
        timeline = EPUBReadAloudTimeline(
            steps: steps,
            items: items,
            speechRate:
                Double(playbackRate)
        )
        totalTimelineSeconds =
            timeline.totalDurationSeconds
    }

    private func updateTimelinePosition() {
        let textOffset: Int?
        if let currentTextRange,
           steps.indices.contains(
               currentItemIndex
           ),
           currentTextRange.chapterIndex
            == steps[currentItemIndex]
                .chapterIndex,
           currentTextRange.segmentIndex
            == steps[currentItemIndex]
                .segmentIndex {
            textOffset =
                currentTextRange.location
        } else {
            textOffset =
                pendingSpeechStartUTF16
        }
        timelinePositionSeconds =
            timeline.position(
                stepIndex: currentItemIndex,
                audioTimeSeconds:
                    steps.indices.contains(
                        currentItemIndex
                    )
                    && steps[currentItemIndex]
                        .audioItemIndex != nil
                    && playbackMode
                        != .textToSpeech
                    ? currentTimeSeconds
                    : nil,
                textUTF16Offset:
                    textOffset
            )
    }

    private static func durationDescription(
        _ seconds: Double
    ) -> String {
        let totalSeconds = max(
            Int(seconds.rounded(.down)),
            0
        )
        let hours = totalSeconds / 3_600
        let minutes =
            (totalSeconds % 3_600) / 60
        let remainingSeconds =
            totalSeconds % 60
        if hours > 0 {
            return String(
                format: "%d:%02d:%02d",
                hours,
                minutes,
                remainingSeconds
            )
        }
        return String(
            format: "%d:%02d",
            minutes,
            remainingSeconds
        )
    }

    private func cancelLoad() {
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
        loadGeneration &+= 1
    }

    private func removeEndObserver() {
        guard let endObserver else {
            return
        }
        NotificationCenter.default
            .removeObserver(endObserver)
        self.endObserver = nil
    }
}

extension EPUBMediaOverlayPlaybackController:
    AVSpeechSynthesizerDelegate
{
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString
            characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        let utteranceID =
            ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.noteSpeechRange(
                characterRange,
                utteranceID:
                    utteranceID
            )
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance:
            AVSpeechUtterance
    ) {
        let utteranceID =
            ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.finishSpeech(
                utteranceID:
                    utteranceID
            )
        }
    }
}
