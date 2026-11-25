import SwiftUI
import Combine
import AVFoundation

@MainActor final class ListeningPlayerModel: ObservableObject {
    @Published var tab = "radio"
    @Published var query = ""
    @Published var results: [ListeningItem] = []
    @Published var showingPopularPodcasts = false
    @Published var episodes: [ListeningItem] = []
    @Published var show: ListeningItem?
    @Published var busy = false
    @Published var message = ""
    @Published var saved: [ListeningItem] = []
    @Published var current: ListeningItem?
    @Published var playbackEpisodes: [ListeningItem] = []
    @Published var playing = false
    @Published var buffering = false
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var speed: Float = 1
    @Published var sleepMinutes = 0
    private let player = AVPlayer()
    @Published var playerVisible = false
    @Published var playbackError = false
    @Published var programs: [RadioProgram] = []
    @Published var scheduleBusy = false
    @Published var scheduleFailed = false
    private var scheduleStationID = ""
    private var chaptersLoadedID = ""

    func refreshChapters() async {
        guard let item = current, item.kind == "episode", item.chaptersURL != nil,
              (item.chapters ?? []).isEmpty, chaptersLoadedID != item.id else { return }
        do {
            let chapters = try await ListeningCatalog.chapters(item)
            try Task.checkCancellation()
            guard current?.id == item.id else { return }
            chaptersLoadedID = item.id
            var updated = item; updated.chapters = chapters; current = updated
            playbackEpisodes = playbackEpisodes.map { $0.id == item.id ? updated : $0 }
            defaults.set(try? JSONEncoder().encode(updated), forKey: "listening.current.v1")
            defaults.set(try? JSONEncoder().encode(playbackEpisodes), forKey: "listening.queue.v1")
        } catch { /* Optional chapter metadata must never interrupt audio. */ }
    }

    var currentProgram: RadioProgram? { programs.first { $0.isCurrent(Date()) } }
    var currentArtworkURL: String? {
        guard let current else { return nil }
        guard current.kind == "radio" else { return current.artworkURL }
        if RadioSchedule.supports(current), scheduleStationID != current.id || (scheduleBusy && programs.isEmpty) { return nil }
        return currentProgram?.artworkURL ?? current.artworkURL
    }
    var currentArtworkIsStationLogo: Bool {
        guard let current, current.kind == "radio" else { return false }
        if RadioSchedule.supports(current), scheduleStationID != current.id || (scheduleBusy && programs.isEmpty) { return false }
        return currentProgram?.artworkURL == nil
    }
    var currentChapters: [ListeningChapter] { current?.chapters ?? [] }
    var currentChapterIndex: Int? { currentChapters.lastIndex { $0.start <= position } }
    func adjacentItem(_ direction: Int) -> ListeningItem? {
        guard let current else { return nil }
        if current.kind == "radio" { return RadioStations.adjacent(current, direction: direction) }
        guard let index = playbackEpisodes.firstIndex(where: { $0.id == current.id }) else { return nil }
        // RSS order is newest first: previous is older, next is newer.
        let target = index - direction
        return playbackEpisodes.indices.contains(target) ? playbackEpisodes[target] : nil
    }
    func moveItem(_ direction: Int) { if let item = adjacentItem(direction) { play(item) } }
    private func chapterTarget(_ direction: Int) -> Int? {
        let index = currentChapterIndex ?? -1
        if direction < 0 && index < 0 { return nil }
        let target = direction < 0 && position > currentChapters[index].start + 3 ? index : index + direction
        guard currentChapters.indices.contains(target), duration > 0, currentChapters[target].start < duration else { return nil }
        return target
    }
    func canMoveChapter(_ direction: Int) -> Bool { chapterTarget(direction) != nil }
    func moveChapter(_ direction: Int) { if let target = chapterTarget(direction) { seek(currentChapters[target].start) } }

    func refreshSchedule() async {
        guard let item = current, item.kind == "radio", RadioSchedule.supports(item) else { return }
        let id = item.id
        if scheduleStationID != id { programs = []; scheduleStationID = id; scheduleBusy = true }
        do {
            let rows = try await RadioSchedule.load(item)
            try Task.checkCancellation()
            guard current?.id == id else { return }
            programs = rows; scheduleBusy = false; scheduleFailed = false
        } catch {
            guard !Task.isCancelled, current?.id == id else { return }
            programs = []; scheduleBusy = false; scheduleFailed = true
        }
    }

    private var request: Task<Void, Never>?
    private var popularCache: (items: [ListeningItem], fetchedAt: Date)?
    private var sleepTask: Task<Void, Never>?
    private var playRequest: Task<Void, Never>?
    private var playGeneration = UUID()
    private var wantsPlayback = false
    private var retriedRadio = false
    private var observer: Any?
    private var itemObserver: NSKeyValueObservation?
    private var playbackObserver: NSKeyValueObservation?
    private var interruptionObserver: NSObjectProtocol?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var sessionActive = false
    private let defaults = UserDefaults.standard
    private var progress: [String: Double] = [:]
    private var progressOrder: [String] = []

    init() {
        saved = (defaults.data(forKey: "listening.saved.v1").flatMap { try? JSONDecoder().decode([ListeningItem].self, from: $0) }) ?? []
        progress = defaults.dictionary(forKey: "listening.progress.v1") as? [String: Double] ?? [:]
        progressOrder = defaults.stringArray(forKey: "listening.progressOrder.v1") ?? Array(progress.keys)
        current = defaults.data(forKey: "listening.current.v1").flatMap { try? JSONDecoder().decode(ListeningItem.self, from: $0) }
        playbackEpisodes = defaults.data(forKey: "listening.queue.v1").flatMap { try? JSONDecoder().decode([ListeningItem].self, from: $0) } ?? []
        saved = saved.map(RadioStations.canonical).reduce(into: []) { result, item in
            if !result.contains(where: { $0.id == item.id }) { result.append(item) }
        }
        current = current.map(RadioStations.canonical)
        defaults.set(try? JSONEncoder().encode(saved), forKey: "listening.saved.v1")
        defaults.set(current.flatMap { try? JSONEncoder().encode($0) }, forKey: "listening.current.v1")
        playbackObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let status = self.player.timeControlStatus
                self.playing = self.wantsPlayback && status == .playing
                self.buffering = self.wantsPlayback && (status == .waitingToPlayAtSpecifiedRate || self.playRequest != nil)
            }
        }
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 1), queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pause() }
        }
        failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, note.object as? AVPlayerItem === self.player.currentItem else { return }
                self.playbackFailed()
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, note.object as? AVPlayerItem === self.player.currentItem else { return }
                if let current = self.current { self.progress[current.id] = 0; self.defaults.set(self.progress, forKey: "listening.progress.v1") }
                self.pause(save: false)
                self.player.seek(to: .zero)
            }
        }
    }

    func search() {
        request?.cancel()
        show = nil; episodes = []; results = []; message = ""
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedTab = tab
        showingPopularPodcasts = selectedTab == "podcast" && term.isEmpty
        let loadPopular = showingPopularPodcasts
        if loadPopular, let cache = popularCache, Date().timeIntervalSince(cache.fetchedAt) < 3600 {
            results = cache.items; busy = false; return
        }
        busy = true
        request = Task {
            do {
                let rows: [ListeningItem]
                if selectedTab == "radio" { rows = try await Task.detached(priority: .userInitiated) { try RadioStations.search(term) }.value }
                else if loadPopular { rows = try await ListeningCatalog.popularPodcasts() }
                else { rows = try await ListeningCatalog.podcasts(term) }
                try Task.checkCancellation()
                if loadPopular && !rows.isEmpty { popularCache = (rows, Date()) }
                results = rows; busy = false
                if rows.isEmpty { message = loadPopular ? "listen.popular_empty" : "listen.empty" }
            } catch {
                guard !Task.isCancelled else { return }
                busy = false; message = "listen.network_error"
            }
        }
    }
    func selectTab(_ value: String) { tab = value; query = ""; search() }
    func open(_ item: ListeningItem) {
        if item.kind != "podcast" {
            if current?.id == RadioStations.canonical(item).id && (playing || buffering) { playerVisible = true }
            else { play(item) }
            return
        }
        request?.cancel(); show = item; episodes = []; results = []; busy = true; message = ""
        request = Task {
            do {
                let page = try await ListeningCatalog.episodes(item)
                try Task.checkCancellation()
                let rows = page.episodes
                show = page.show
                if let index = saved.firstIndex(where: { $0.id == item.id }), saved[index].artworkURL != page.show.artworkURL {
                    saved[index] = page.show
                    defaults.set(try? JSONEncoder().encode(saved), forKey: "listening.saved.v1")
                }
                episodes = rows; busy = false
                if rows.isEmpty { message = "listen.no_episodes" }
            } catch {
                guard !Task.isCancelled else { return }
                busy = false; message = "listen.feed_error"
            }
        }
    }
    func toggleSaved(_ item: ListeningItem) {
        if saved.contains(where: { $0.id == item.id }) { saved.removeAll { $0.id == item.id } }
        else { saved.append(item) }
        defaults.set(try? JSONEncoder().encode(saved), forKey: "listening.saved.v1")
    }
    func play(_ original: ListeningItem, retrying: Bool = false) {
        guard original.kind != "podcast" else { return }
        pause()
        player.replaceCurrentItem(with: nil); itemObserver = nil
        var item = RadioStations.canonical(original)
        if item.kind == "episode" {
            if let cached = playbackEpisodes.first(where: { $0.id == item.id }) {
                if (item.chapters ?? []).isEmpty { item.chapters = cached.chapters }
                item.artworkURL = item.artworkURL ?? cached.artworkURL
            }
            if episodes.contains(where: { $0.id == item.id && $0.feedURL == item.feedURL }) { playbackEpisodes = episodes }
            else if !playbackEpisodes.contains(where: { $0.id == item.id }) { playbackEpisodes = [item] }
            playbackEpisodes = playbackEpisodes.map { $0.id == item.id ? item : $0 }
            defaults.set(try? JSONEncoder().encode(playbackEpisodes), forKey: "listening.queue.v1")
        }
        if current?.id != item.id { programs = []; scheduleStationID = ""; scheduleBusy = false; scheduleFailed = false }
        if !retrying { playerVisible = true }
        current = item; position = 0; duration = 0; message = ""; speed = 1
        retriedRadio = retrying; wantsPlayback = true; buffering = true
        defaults.set(try? JSONEncoder().encode(item), forKey: "listening.current.v1")
        let generation = playGeneration
        playRequest = Task {
            do {
                let url = try await RadioStations.resolve(item)
                try Task.checkCancellation()
                guard playGeneration == generation && wantsPlayback else { return }
                playRequest = nil
                let avItem = AVPlayerItem(url: url)
                player.replaceCurrentItem(with: avItem)
                itemObserver = avItem.observe(\.status, options: [.new]) { [weak self] observed, _ in
                    let failed = observed.status == .failed
                    Task { @MainActor [weak self, weak observed] in
                        guard let self, let observed, self.player.currentItem === observed else { return }
                        if failed { self.playbackFailed() }
                    }
                }
                if item.kind == "episode", let offset = progress[item.id], offset > 0 {
                    player.seek(to: CMTime(seconds: offset, preferredTimescale: 600), completionHandler: { _ in })
                }
                resume()
            } catch {
                guard !Task.isCancelled && playGeneration == generation else { return }
                playRequest = nil
                pause(); playbackError = true
            }
        }
    }
    private func playbackFailed() {
        guard wantsPlayback else { return }
        if let current, current.kind == "radio", !retriedRadio { play(current, retrying: true) }
        else { pause(); playbackError = true }
    }
    func togglePlayback() {
        if playing || buffering { pause() }
        else if let current, current.kind == "radio" { play(current) }
        else if player.currentItem != nil, player.currentItem?.status != .failed { resume() }
        else if let current { play(current) }
    }
    private func resume() {
        playbackError = false
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            sessionActive = true; wantsPlayback = true
            player.playImmediately(atRate: current?.kind == "radio" ? 1 : speed)
        } catch { wantsPlayback = false; buffering = false; playbackError = true }
    }
    func pause(save: Bool = true) {
        if save { saveProgress() }
        playbackError = false; wantsPlayback = false; playGeneration = UUID()
        playRequest?.cancel(); playRequest = nil
        player.pause(); playing = false; buffering = false
        if current?.kind == "radio" { player.replaceCurrentItem(with: nil); itemObserver = nil }
        if sessionActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            sessionActive = false
        }
    }
    func skip(_ seconds: Double) {
        guard current?.kind == "episode", duration > 0 else { return }
        let value = player.currentTime().seconds
        seek((value.isFinite ? value : position) + seconds)
    }
    private func seek(_ seconds: Double) {
        position = min(max(0, seconds), duration)
        player.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    func setSpeed(_ value: Float) { speed = value; if playing { player.rate = value } }
    func setSleep(_ minutes: Int) {
        sleepTask?.cancel(); sleepMinutes = minutes
        guard minutes > 0 else { return }
        sleepTask = Task {
            do { try await Task.sleep(for: .seconds(minutes * 60)); pause(); sleepMinutes = 0 }
            catch { }
        }
    }
    private func tick() {
        let seconds = player.currentTime().seconds
        if seconds.isFinite { position = max(0, seconds) }
        let total = player.currentItem?.duration.seconds ?? 0
        duration = total.isFinite ? max(0, total) : 0
        if playing && Int(position) % 5 == 0 { saveProgress() }
    }
    private func saveProgress() {
        guard let current, current.kind == "episode", player.currentItem != nil else { return }
        let value = player.currentTime().seconds
        guard value.isFinite else { return }
        progress[current.id] = max(0, value)
        progressOrder.removeAll { $0 == current.id }
        progressOrder.append(current.id)
        while progressOrder.count > 200 { progress.removeValue(forKey: progressOrder.removeFirst()) }
        defaults.set(progressOrder, forKey: "listening.progressOrder.v1")
        defaults.set(progress, forKey: "listening.progress.v1")
    }
    func close() { request?.cancel(); sleepTask?.cancel(); sleepMinutes = 0; pause() }
    deinit {
        request?.cancel(); sleepTask?.cancel(); playRequest?.cancel()
        if let observer { player.removeTimeObserver(observer) }
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
    }
}
