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
            return "책 안의 오디오 파일을 찾을 수 없습니다."
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
            return "오디오"
        case .textToSpeech:
            return "로컬 음성"
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
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var errorDescription: String?
    @Published private(set) var playbackMode:
        EPUBReadAloudPlaybackMode = .none

    private let player = AVPlayer()
    private let speechSynthesizer =
        AVSpeechSynthesizer()
    private let resourceStore:
        EPUBMediaOverlayResourceStore
    private var items: [EPUBMediaOverlayItem] = []
    private var steps: [EPUBReadAloudStep] = []
    private var speechLanguage = "ko-KR"
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var loadedItemID: String?
    private var currentUtteranceID:
        ObjectIdentifier?
    private var spokenStepID: String?
    private var playbackRate: Float = 1

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

    var canMovePrevious: Bool {
        currentItemIndex > 0
    }

    var canMoveNext: Bool {
        steps.indices.contains(
            currentItemIndex + 1
        )
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
        items = book.mediaOverlayItems
        steps = EPUBReadAloudSequence.steps(
            for: book
        )
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
        playbackMode = .none
        errorDescription = nil
    }

    func setRate(_ value: Double) {
        playbackRate = Float(
            min(max(value, 0.5), 2)
        )
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
            startStep(
                index: currentItemIndex,
                autoplay: true
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
        playbackMode = .none
    }

    func move(by delta: Int) {
        let target = currentItemIndex + delta
        guard steps.indices.contains(target) else {
            return
        }
        startStep(
            index: target,
            autoplay: true
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
        currentTimeSeconds =
            clipBegin(forStepAt: index) ?? 0
        guard autoplay else {
            return
        }
        if let audioItemIndex =
                steps[index].audioItemIndex {
            scheduleAudioLoad(
                stepIndex: index,
                audioItemIndex:
                    audioItemIndex
            )
        } else {
            startSpeech(stepIndex: index)
        }
    }

    private func scheduleAudioLoad(
        stepIndex: Int,
        audioItemIndex: Int
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
                        audioItemIndex
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
                    "오디오를 열 수 없어 로컬 음성으로 읽습니다."
                self.startSpeech(
                    stepIndex: stepIndex
                )
            }
        }
    }

    private func finishAudioLoad(
        url: URL,
        stepIndex: Int,
        audioItemIndex: Int
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
        player.seek(
            to: CMTime(
                seconds: overlay.clipBeginSeconds,
                preferredTimescale: 600
            ),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
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
        stepIndex: Int
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
        let utterance = AVSpeechUtterance(
            string: text
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
        currentLocation = location(
            forStepAt: stepIndex
        )
        AppAudioManager.shared.configure()
        playbackMode = .textToSpeech
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
        finishCurrentStep(
            expectedStepID: spokenStepID
        )
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
