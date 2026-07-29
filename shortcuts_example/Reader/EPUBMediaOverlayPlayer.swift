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
            return "EPUB 안의 오디오 파일을 찾을 수 없습니다."
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

@MainActor
final class EPUBMediaOverlayPlaybackController:
    ObservableObject
{
    @Published private(set) var items:
        [EPUBMediaOverlayItem] = []
    @Published private(set) var currentItemIndex = 0
    @Published private(set) var currentLocation:
        EPUBMediaOverlayLocation?
    @Published private(set) var currentTimeSeconds = 0.0
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var errorDescription: String?

    private let player = AVPlayer()
    private let resourceStore:
        EPUBMediaOverlayResourceStore
    private var chapters: [EPUBChapter] = []
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var loadedItemID: String?
    private var playbackRate: Float = 1

    init(fileURL: URL) {
        resourceStore =
            EPUBMediaOverlayResourceStore(
                bookURL: fileURL
            )
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
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default
                .removeObserver(endObserver)
        }
    }

    var hasAudio: Bool {
        !items.isEmpty
    }

    var canMovePrevious: Bool {
        currentItemIndex > 0
    }

    var canMoveNext: Bool {
        items.indices.contains(
            currentItemIndex + 1
        )
    }

    var positionDescription: String {
        guard !items.isEmpty else {
            return ""
        }
        return "\(currentItemIndex + 1) / \(items.count)"
    }

    func configure(
        book: EPUBBook,
        chapterIndex: Int,
        segmentIndex: Int
    ) {
        pause()
        cancelLoad()
        removeEndObserver()
        player.replaceCurrentItem(with: nil)
        items = book.mediaOverlayItems
        chapters = book.chapters
        currentItemIndex =
            EPUBMediaOverlayLocationResolver
            .nearestItemIndex(
                chapterIndex: chapterIndex,
                segmentIndex: segmentIndex,
                items: items,
                chapters: chapters
            ) ?? 0
        currentLocation = nil
        currentTimeSeconds =
            items.indices.contains(
                currentItemIndex
            )
            ? items[currentItemIndex]
                .clipBeginSeconds
            : 0
        loadedItemID = nil
        errorDescription = nil
    }

    func setRate(_ value: Double) {
        playbackRate = Float(
            min(max(value, 0.5), 2)
        )
        if isPlaying {
            player.rate = playbackRate
        }
    }

    func togglePlayback() {
        if isPlaying {
            pause()
            return
        }
        guard items.indices.contains(
            currentItemIndex
        ) else {
            return
        }
        if loadedItemID
            == items[currentItemIndex].id {
            AppAudioManager.shared.configure()
            currentLocation =
                EPUBMediaOverlayLocationResolver
                .location(
                    for: currentItemIndex,
                    items: items,
                    chapters: chapters
                )
            isPlaying = true
            player.playImmediately(
                atRate: playbackRate
            )
        } else {
            scheduleLoad(
                index: currentItemIndex,
                autoplay: true
            )
        }
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func stop() {
        pause()
        cancelLoad()
        guard items.indices.contains(
            currentItemIndex
        ) else {
            return
        }
        let begin = items[currentItemIndex]
            .clipBeginSeconds
        player.seek(
            to: CMTime(
                seconds: begin,
                preferredTimescale: 600
            ),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        currentTimeSeconds = begin
    }

    func move(by delta: Int) {
        let target = currentItemIndex + delta
        guard items.indices.contains(target) else {
            return
        }
        scheduleLoad(
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
                EPUBMediaOverlayLocationResolver
                .nearestItemIndex(
                    chapterIndex: chapterIndex,
                    segmentIndex: segmentIndex,
                    items: items,
                    chapters: chapters
                ) else {
            pause()
            return
        }
        if target == currentItemIndex,
           loadedItemID == items[target].id {
            if autoplay {
                togglePlayback()
            } else {
                pause()
            }
            return
        }
        scheduleLoad(
            index: target,
            autoplay: autoplay
        )
    }

    private func scheduleLoad(
        index: Int,
        autoplay: Bool
    ) {
        guard items.indices.contains(index) else {
            return
        }
        cancelLoad()
        player.pause()
        isPlaying = false
        isLoading = true
        errorDescription = nil
        currentItemIndex = index
        if autoplay {
            currentLocation =
                EPUBMediaOverlayLocationResolver
                .location(
                    for: index,
                    items: items,
                    chapters: chapters
                )
        }
        currentTimeSeconds =
            items[index].clipBeginSeconds
        loadGeneration &+= 1
        let generation = loadGeneration
        let audioPath = items[index].audioPath
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
                self.finishLoad(
                    url: url,
                    index: index,
                    autoplay: autoplay
                )
            } catch {
                guard !Task.isCancelled,
                      generation
                        == self.loadGeneration else {
                    return
                }
                self.isLoading = false
                self.errorDescription =
                    error.localizedDescription
            }
        }
    }

    private func finishLoad(
        url: URL,
        index: Int,
        autoplay: Bool
    ) {
        guard items.indices.contains(index),
              index == currentItemIndex else {
            return
        }
        removeEndObserver()
        let overlay = items[index]
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
        let expectedItemID = overlay.id
        endObserver = NotificationCenter.default
            .addObserver(
                forName:
                    .AVPlayerItemDidPlayToEndTime,
                object: playerItem,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.finishCurrentItem(
                        expectedItemID:
                            expectedItemID
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
        if autoplay {
            AppAudioManager.shared.configure()
            isPlaying = true
            player.playImmediately(
                atRate: playbackRate
            )
        }
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
              !isLoading,
              items.indices.contains(
                  currentItemIndex
              ),
              let end = items[
                  currentItemIndex
              ].clipEndSeconds,
              end > items[
                  currentItemIndex
              ].clipBeginSeconds,
              currentTimeSeconds
                >= end - 0.03 else {
            return
        }
        finishCurrentItem(
            expectedItemID:
                items[currentItemIndex].id
        )
    }

    private func finishCurrentItem(
        expectedItemID: String
    ) {
        guard isPlaying,
              loadedItemID == expectedItemID else {
            return
        }
        if canMoveNext {
            scheduleLoad(
                index: currentItemIndex + 1,
                autoplay: true
            )
        } else {
            pause()
            let begin = items[
                currentItemIndex
            ].clipBeginSeconds
            player.seek(
                to: CMTime(
                    seconds: begin,
                    preferredTimescale: 600
                ),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
            currentTimeSeconds = begin
        }
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
