import SwiftUI
import UIKit

private enum ListeningMorePage: Hashable { case settings, episodes, speed, sleep, schedule }

/// Center the podcast content beneath its navigation tools.
private struct ListeningPodcastWideLayout: Layout {
    let minimumHeight: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let heights = subviews.map { $0.sizeThatFits(.init(width: width, height: nil)).height }
        return .init(width: width, height: max(minimumHeight, heights.reduce(0, +) + 48))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let toolbar = subviews[0].sizeThatFits(.init(width: bounds.width, height: nil))
        let panel = subviews[1].sizeThatFits(.init(width: bounds.width, height: nil))
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: .init(width: bounds.width, height: toolbar.height))
        let y = bounds.minY + toolbar.height + max(24, (bounds.height - toolbar.height - panel.height) / 2)
        subviews[1].place(at: .init(x: bounds.midX, y: y), anchor: .top, proposal: .init(width: bounds.width, height: panel.height))
    }
}

/// Keep related information close and give playback a deliberate lower position.
private struct ListeningPodcastPageLayout: Layout {
    let minimumHeight: CGFloat
    private func sizes(_ views: Subviews, width: CGFloat) -> [CGSize] {
        views.map { $0.sizeThatFits(.init(width: width, height: nil)) }
    }
    private func naturalHeight(_ sizes: [CGSize]) -> CGFloat {
        sizes.reduce(0) { $0 + $1.height } + 32 + (sizes[2].height > 0 ? 32 : 0) + 48
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        return .init(width: width, height: max(minimumHeight, naturalHeight(sizes(subviews, width: width))))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let s = sizes(subviews, width: bounds.width)
        let headingY = bounds.minY + s[0].height + 32
        let chapterY = headingY + s[1].height + (s[2].height > 0 ? 32 : 0)
        let lift = min(64, max(0, bounds.height - naturalHeight(s)) / 4)
        let playbackY = bounds.maxY - s[3].height - lift
        for (index, y) in [bounds.minY, headingY, chapterY, playbackY].enumerated() {
            subviews[index].place(at: .init(x: bounds.minX, y: y), anchor: .topLeading, proposal: .init(width: bounds.width, height: s[index].height))
        }
    }
}

private enum ListeningAppearance {
    static let text = VisionCraftUI.fixedColor(0xF4F5EF)
    static let secondary = VisionCraftUI.fixedColor(0xD4DFD8)
    static let accent = VisionCraftUI.fixedColor(0xCCE7D3)
    static let ink = VisionCraftUI.fixedColor(0x14271E)
}
private struct ListeningPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.visionCraftAndroidText(20, weight: .medium).foregroundStyle(ListeningAppearance.text)
            .padding(.horizontal, 18).padding(.vertical, 14).frame(minHeight: 56)
            .background(.white.opacity(configuration.isPressed ? 0.16 : 0.07), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.3)))
            .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}

/// Distributes free viewport space without measuring through view state.
private struct ListeningPlayerPageLayout: Layout {
    let minimumHeight: CGFloat
    private let spacing: CGFloat = 24
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let height = subviews.reduce(CGFloat.zero) { $0 + $1.sizeThatFits(.init(width: width, height: nil)).height }
        return CGSize(width: width, height: max(minimumHeight, height + spacing * CGFloat(max(0, subviews.count - 1))))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.init(width: bounds.width, height: nil)) }
        let total = sizes.reduce(CGFloat.zero) { $0 + $1.height }
        let gap = max(spacing, (bounds.height - total) / CGFloat(max(1, subviews.count - 1)))
        var y = bounds.minY
        for (view, size) in zip(subviews, sizes) {
            view.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: .init(width: bounds.width, height: size.height))
            y += size.height + gap
        }
    }
}

struct ListeningView: View {
    private enum ReadingFocus: Hashable {
        case player, radioTab, podcastTab, feedRadioTab, feedPodcastTab, feed
        case podcast(String, subscribed: Bool)
        case moreButton, moreHeading(ListeningMorePage)
    }

    var embedded = false
    var active = true
    var backRequest = 0
    var showsPlayerBackButton = false
    var onExit: () -> Void = {}
    @StateObject private var model = ListeningPlayerModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var information = false
    @State private var morePage: ListeningMorePage = .settings
    @State private var moreVisible = false
    @State private var showingPlayer = true
    @State private var catalogLoaded = false
    @State private var searchScrollRequest = 0
    @State private var openedShowFocus: ReadingFocus?
    @State private var playerReadingFocus = ReadingFocus.player
    @FocusState private var queryFocused: Bool
    @AccessibilityFocusState(for: .voiceOver) private var readingFocus: ReadingFocus?
    private func text(_ key: String) -> String { AppLocalization.string(key) }
    private func subtitle(_ item: ListeningItem) -> String {
        item.kind == "radio" ? item.subtitle.components(separatedBy: " · ").filter { $0 != "수도권" }.joined(separator: " · ") : item.subtitle
    }
    private func search() {
        queryFocused = false
        openedShowFocus = nil
        model.search()
        searchScrollRequest += 1
    }
    private func back() {
        if moreVisible { if morePage == .settings { moreVisible = false } else { morePage = .settings } }
        else if !showingPlayer {
            if model.show != nil { model.closeShow() } else { showingPlayer = true }
        }
        else if embedded { onExit() }
        else { dismiss() }
    }

    var body: some View {
        ZStack {
            if !showingPlayer || catalogLoaded {
                catalogPage
                    .opacity(showingPlayer ? 0 : 1)
                    .allowsHitTesting(!showingPlayer && !moreVisible)
                    .accessibilityHidden(showingPlayer || moreVisible)
                    .environment(\.listeningImagesActive, active && scenePhase == .active && !showingPlayer)
            }
            if showingPlayer {
                GeometryReader { viewport in
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                if let item = model.current, item.kind == "episode" {
                                    let compact = viewport.size.height - 48 < 650
                                    let wide = compact && min(viewport.size.width, 1000) - 48 >= 900
                                    if wide {
                                        ListeningPodcastWideLayout(minimumHeight: max(0, viewport.size.height - 48)) {
                                            playerToolbar
                                            podcastContent(item, compact: compact, wide: true)
                                        }
                                    } else {
                                        ListeningPodcastPageLayout(minimumHeight: max(0, viewport.size.height - 48)) {
                                            playerToolbar
                                            podcastHeading(item, compact: compact)
                                            podcastChapter(compact: compact)
                                            podcastPlayback(item).padding(.bottom, 24)
                                        }
                                    }
                                } else {
                                    ListeningPlayerPageLayout(minimumHeight: max(0, viewport.size.height - 48)) {
                                        playerToolbar
                                        if let item = model.current {
                                            radioHeading(item, artworkMaxHeight: min(400, max(160, (viewport.size.height - 48) * 0.42)))
                                        } else { playerEmptyState }
                                        if let item = model.current { playbackControls(item).padding(.bottom, 24) }
                                        else { Color.clear.frame(height: 24).accessibilityHidden(true) }
                                    }
                                }
                            }.padding(24).frame(maxWidth: model.current?.kind == "episode" ? .infinity : 1000).frame(maxWidth: .infinity).id("listening.player")
                        }
                        .onChange(of: model.current?.id) { _, _ in proxy.scrollTo("listening.player", anchor: .top) }
                    }
                }
                .allowsHitTesting(!moreVisible)
                .accessibilityHidden(moreVisible)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if !showingPlayer || !embedded || showsPlayerBackButton {
                VisionCraftBackButton(tint: ListeningAppearance.text, action: back)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, embedded ? 0 : 24)
                    .accessibilityHidden(moreVisible)
                    .allowsHitTesting(!moreVisible)
            }
        }
        .overlay { if moreVisible, model.current != nil { moreDialog } }
        .scrollDismissesKeyboard(.interactively)
        .background(embedded ? Color.clear : VisionCraftUI.fixedColor(0x101C17))
        .foregroundStyle(ListeningAppearance.text).environment(\.colorScheme, .dark)
        .environment(\.listeningImagesActive, active && scenePhase == .active)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: showingPlayer) {
            if !showingPlayer && !catalogLoaded { catalogLoaded = true; model.search() }
        }
        .task(id: active && scenePhase == .active ? model.current?.id : nil) {
            guard active && scenePhase == .active else { return }
            while !Task.isCancelled {
                await model.refreshSchedule()
                await model.refreshChapters()
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
        .onDisappear { model.close() }
        .onChange(of: active) { _, value in
            if !value {
                showingPlayer = true; moreVisible = false; playerReadingFocus = .player; queryFocused = false
                model.pause(); model.setSleep(0)
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.pause() } }
        .onChange(of: model.playerVisible) { _, value in
            if value { queryFocused = false; showingPlayer = true; model.playerVisible = false }
        }
        .task(id: active ? preferredReadingFocus : nil) {
            guard active else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            readingFocus = preferredReadingFocus
        }
        .onChange(of: backRequest) { _, _ in if active { back() } }
        .accessibilityAction(.escape) { back() }
    }

    private var preferredReadingFocus: ReadingFocus {
        if moreVisible { return .moreHeading(morePage) }
        if showingPlayer { return playerReadingFocus }
        if model.show != nil { return .feed }
        return openedShowFocus ?? (model.tab == "radio" ? .radioTab : .podcastTab)
    }

    private var playerToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                playerNavigation.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 12)
                if model.current != nil { moreButton.fixedSize(horizontal: true, vertical: false) }
            }
            VStack(alignment: .leading, spacing: 12) {
                playerNavigation
                if model.current != nil { moreButton.frame(maxWidth: .infinity, alignment: .trailing) }
            }
        }
    }
    private var playerNavigation: some View {
        Button { queryFocused = false; playerReadingFocus = .player; showingPlayer = false } label: {
            Label(text("listen.broadcast_list"), systemImage: "list.bullet")
        }.buttonStyle(ListeningPillStyle()).accessibilityLabel(text("listen.open_catalog"))
            .accessibilityFocused($readingFocus, equals: .player)
    }

    private var catalogPage: some View {
        ZStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        catalogTabs(inFeed: false).id("listening.catalog")
                        searchField
                        if model.tab == "podcast" {
                            let saved = model.saved.filter { $0.kind == "podcast" }
                            if !saved.isEmpty {
                                section("listen.subscriptions", count: saved.count)
                                catalog(saved, subscribed: true)
                            }
                        }
                        section(model.tab == "radio" ? "listen.stations" : model.showingPopularPodcasts ? "listen.popular" : "listen.results", count: model.results.count)
                        listStatus(busy: model.searchBusy, message: model.searchMessage, retry: search)
                        catalog(model.results)
                        footer
                    }.padding(24).frame(maxWidth: 1000).frame(maxWidth: .infinity)
                }
                .onChange(of: searchScrollRequest) { _, _ in proxy.scrollTo("listening.catalog", anchor: .top) }
            }
            .opacity(model.show == nil ? 1 : 0)
            .allowsHitTesting(model.show == nil)
            .accessibilityHidden(model.show != nil)
            .environment(\.listeningImagesActive, active && scenePhase == .active && !showingPlayer && model.show == nil)
            if let show = model.show {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        catalogTabs(inFeed: true)
                        Button(text("listen.back_results"), action: model.closeShow).buttonStyle(ListeningPillStyle())
                        HStack(alignment: .top, spacing: 24) {
                            ListeningArtwork(url: show.artworkURL, title: show.title, radio: false).frame(width: 112)
                            VStack(alignment: .leading, spacing: 16) {
                                Text(verbatim: show.title).visionCraftAndroidText(30, weight: .medium)
                                    .accessibilityAddTraits(.isHeader)
                                    .accessibilityFocused($readingFocus, equals: .feed)
                                saveButton(show, expanded: true)
                            }
                        }
                        listStatus(busy: model.feedBusy, message: model.feedMessage) { model.open(show) }
                        catalog(model.episodes)
                        footer
                    }.padding(24).frame(maxWidth: 1000).frame(maxWidth: .infinity)
                }.id(show.id)
            }
        }
    }

    private func catalogTabs(inFeed: Bool) -> some View {
        HStack(spacing: 28) {
            tabButton("radio", "listen.radio", inFeed ? .feedRadioTab : .radioTab)
            tabButton("podcast", "listen.podcast", inFeed ? .feedPodcastTab : .podcastTab)
        }
    }

    @ViewBuilder private func listStatus(busy: Bool, message: String, retry: @escaping () -> Void) -> some View {
        if busy {
            HStack(spacing: 14) {
                ProgressView().tint(ListeningAppearance.accent).accessibilityHidden(true)
                Text(text("listen.loading")).visionCraftAndroidText(20).foregroundStyle(ListeningAppearance.secondary)
            }
        }
        if !message.isEmpty {
            Text(text(message)).visionCraftAndroidText(20).foregroundStyle(ListeningAppearance.secondary)
            if !busy {
                Button(text("listen.retry"), action: retry).buttonStyle(ListeningPillStyle())
            }
        }
    }
    private var playerEmptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "radio").font(.system(size: 64)).foregroundStyle(ListeningAppearance.accent).accessibilityHidden(true)
            Text(text("listen.choose_broadcast")).visionCraftAndroidText(24).multilineTextAlignment(.center)
        }.padding(.vertical, 40).frame(maxWidth: .infinity)
    }

    private var searchField: some View {
        let label = text(model.tab == "radio" ? "listen.radio_hint" : "listen.search_hint")
        return HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.system(size: 24)).accessibilityHidden(true)
            ZStack(alignment: .leading) {
                if model.query.isEmpty {
                    Text(verbatim: label).foregroundStyle(ListeningAppearance.secondary.opacity(0.8))
                        .lineLimit(1).accessibilityHidden(true).allowsHitTesting(false)
                }
                TextField("", text: $model.query).focused($queryFocused).submitLabel(.search).onSubmit(search)
                    .autocorrectionDisabled().textInputAutocapitalization(.never).accessibilityLabel(label)
            }.visionCraftAndroidText(24)
            Button(action: search) {
                Image(systemName: "arrow.right").font(.system(size: 24)).foregroundStyle(ListeningAppearance.ink)
                    .frame(width: 56, height: 56).background(ListeningAppearance.accent, in: Circle())
            }.buttonStyle(.plain).accessibilityLabel(text("listen.search"))
        }.foregroundStyle(ListeningAppearance.secondary).padding(.leading, 20).padding(.trailing, 8).padding(.vertical, 10)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(queryFocused ? ListeningAppearance.accent : .white.opacity(0.4), lineWidth: queryFocused ? 2 : 1))
    }
    private func tabButton(_ value: String, _ title: String, _ target: ReadingFocus) -> some View {
        let selected = model.tab == value
        return Button {
            queryFocused = false
            openedShowFocus = nil
            model.selectTab(value)
            searchScrollRequest += 1
        } label: {
            VStack(alignment: .leading, spacing: 18) {
                Text(text(title)).visionCraftAndroidText(32, weight: .medium, relativeTo: .largeTitle)
                    .foregroundStyle(selected ? ListeningAppearance.text : ListeningAppearance.secondary.opacity(0.65)).frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(selected ? ListeningAppearance.accent : .white.opacity(0.24)).frame(height: selected ? 3 : 1)
            }.padding(.top, 8).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityFocused($readingFocus, equals: target)
    }
    private func section(_ title: String, count: Int) -> some View {
        HStack {
            Text(text(title)).visionCraftAndroidText(28, weight: .medium).accessibilityAddTraits(.isHeader)
            Spacer()
            if count > 0 { Text(verbatim: String(count)).visionCraftAndroidText(20).foregroundStyle(ListeningAppearance.secondary) }
        }
    }
    private func catalog(_ items: [ListeningItem], subscribed: Bool = false) -> some View {
        ForEach(items) { item in row(item, subscribed: subscribed) }
    }
    private func row(_ item: ListeningItem, subscribed: Bool) -> some View {
        let target = ReadingFocus.podcast(item.id, subscribed: subscribed)
        return VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    queryFocused = false
                    if item.kind == "podcast" { openedShowFocus = target }
                    model.open(item)
                } label: {
                    HStack(spacing: 20) {
                        ListeningArtwork(url: item.artworkURL, title: item.title, radio: item.kind == "radio").frame(width: item.kind == "episode" ? 68 : 88)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(verbatim: item.title).visionCraftAndroidText(26, weight: .medium)
                            if !subtitle(item).isEmpty { Text(verbatim: subtitle(item)).visionCraftAndroidText(18).foregroundStyle(ListeningAppearance.secondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: item.kind == "episode" ? "play.fill" : "chevron.right").font(.system(size: 24)).accessibilityHidden(true)
                    }.padding(.vertical, 12).contentShape(Rectangle()).multilineTextAlignment(.leading)
                }.buttonStyle(.plain).accessibilityElement(children: .combine)
                    .accessibilityFocused($readingFocus, equals: target)
                if item.kind == "podcast" { saveButton(item) }
            }
            Rectangle().fill(.white.opacity(0.2)).frame(height: 1).accessibilityHidden(true)
        }
    }
    @ViewBuilder private func saveButton(_ item: ListeningItem, expanded: Bool = false) -> some View {
        let saved = model.saved.contains { $0.id == item.id }
        let label = item.kind == "radio" ? (saved ? "listen.unfavorite" : "listen.favorite") : (saved ? "listen.unsubscribe" : "listen.subscribe")
        if expanded {
            Button(text(label)) { model.toggleSaved(item) }.buttonStyle(ListeningPillStyle()).accessibilityLabel("\(item.title), \(text(label))")
        } else {
            Button { model.toggleSaved(item) } label: {
                Image(systemName: saved ? "star.fill" : "star").font(.system(size: 24)).foregroundStyle(saved ? ListeningAppearance.accent : ListeningAppearance.secondary)
                    .frame(width: 56, height: 56).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("\(item.title), \(text(label))").accessibilityAddTraits(saved ? .isSelected : [])
        }
    }
    private var playbackStatus: String {
        text(model.playbackError ? "listen.connection_failed" : model.buffering ? "listen.buffering" : model.playing ? "listen.playing" : model.current?.kind == "radio" ? "listen.stopped" : "listen.paused")
    }
    private func radioHeading(_ item: ListeningItem, artworkMaxHeight: CGFloat) -> some View {
        VStack(spacing: 20) {
            if typeSize <= .xxLarge {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 36) {
                        ListeningArtwork(url: model.currentArtworkURL, title: item.title, radio: true, naturalAspect: !model.currentArtworkIsStationLogo).frame(maxWidth: model.currentArtworkIsStationLogo ? 320 : 440, maxHeight: model.currentArtworkIsStationLogo ? min(320, artworkMaxHeight) : artworkMaxHeight).frame(width: 440)
                        radioInformation(item, centered: false).frame(minWidth: 440, maxWidth: .infinity, alignment: .leading)
                    }
                    radioStackedHeader(item, artworkMaxHeight: artworkMaxHeight)
                }
            } else {
                radioStackedHeader(item, artworkMaxHeight: artworkMaxHeight)
            }
        }.frame(maxWidth: .infinity)
    }
    private func radioStackedHeader(_ item: ListeningItem, artworkMaxHeight: CGFloat) -> some View {
        VStack(spacing: 16) {
            ListeningArtwork(url: model.currentArtworkURL, title: item.title, radio: true, naturalAspect: !model.currentArtworkIsStationLogo).frame(maxWidth: model.currentArtworkIsStationLogo ? 320 : 640, maxHeight: model.currentArtworkIsStationLogo ? min(320, artworkMaxHeight) : artworkMaxHeight)
            radioInformation(item, centered: true)
        }.frame(maxWidth: .infinity)
    }
    private func radioInformation(_ item: ListeningItem, centered: Bool) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: 8) {
            Text(verbatim: item.title).visionCraftAndroidText(34, weight: .medium, relativeTo: .largeTitle).accessibilityAddTraits(.isHeader)
            if let program = model.currentProgram {
                Text(verbatim: program.title).visionCraftAndroidText(24, weight: .medium)
            }
            Text(verbatim: [subtitle(item), model.currentProgram?.timeRange ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                .visionCraftAndroidText(18).foregroundStyle(ListeningAppearance.secondary)
            if model.playing || model.buffering || model.playbackError {
                Text(verbatim: playbackStatus).visionCraftAndroidText(20).foregroundStyle(ListeningAppearance.accent)
            }
        }.multilineTextAlignment(centered ? .center : .leading)
    }
    private var moreButton: some View {
        Button { playerReadingFocus = .moreButton; morePage = .settings; moreVisible = true } label: {
            Image(systemName: "ellipsis").font(.system(size: 28))
                .frame(width: 56, height: 56)
                .background(.white.opacity(0.07), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.3)))
                .contentShape(Circle())
        }.buttonStyle(.plain).accessibilityLabel(text("listen.more"))
            .accessibilityHint(text("listen.more_hint"))
            .accessibilityFocused($readingFocus, equals: .moreButton)
    }
    private func podcastHeading(_ item: ListeningItem, compact: Bool) -> some View {
        HStack(spacing: 20) {
            ListeningArtwork(url: model.currentArtworkURL, title: item.title, radio: false, naturalAspect: true)
                .frame(width: compact ? 80 : 96, height: compact ? 80 : 96)
            podcastInformation(item)
        }
    }
    @ViewBuilder private func podcastChapter(compact: Bool) -> some View {
        if !model.currentChapters.isEmpty {
            chapterControls(compact: compact).padding(16)
                .background(VisionCraftUI.fixedColor(0x1D3429).opacity(0.94), in: RoundedRectangle(cornerRadius: 18))
        } else { Color.clear.frame(height: 0) }
    }
    private func podcastDetails(_ item: ListeningItem, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 16 : 24) {
            podcastHeading(item, compact: compact)
            if !model.currentChapters.isEmpty { podcastChapter(compact: compact) }
        }
    }
    private func podcastPlayback(_ item: ListeningItem) -> some View {
        let position = clock(model.position)
        let duration = clock(model.duration)
        let playbackTime = String(format: text("listen.playback_time"), position, duration)
        return VStack(spacing: 20) {
            VStack(spacing: 8) {
                ProgressView(value: min(model.position / max(model.duration, 1), 1)).tint(ListeningAppearance.accent).accessibilityHidden(true)
                HStack {
                    Text(position)
                    Spacer()
                    Text(duration)
                }.visionCraftAndroidText(16).monospacedDigit().foregroundStyle(ListeningAppearance.secondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: playbackTime))
                    .accessibilityHidden(model.duration <= 0)
            }
            transport(item)
            if model.playbackError { Text(text("listen.play_error")).visionCraftAndroidText(18).foregroundStyle(ListeningAppearance.secondary) }
        }
    }
    private func podcastContent(_ item: ListeningItem, compact: Bool, wide: Bool) -> some View {
        Group {
            if wide {
                HStack(spacing: 32) {
                    podcastDetails(item, compact: true).frame(maxWidth: .infinity, alignment: .leading)
                    podcastPlayback(item).frame(width: 300)
                }
            } else {
                VStack(spacing: 32) {
                    podcastDetails(item, compact: compact)
                    podcastPlayback(item)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
    private func podcastInformation(_ item: ListeningItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: item.subtitle).visionCraftAndroidText(18).foregroundStyle(ListeningAppearance.accent)
            Text(verbatim: item.title).visionCraftAndroidText(28, weight: .medium, relativeTo: .largeTitle).accessibilityAddTraits(.isHeader)
            if model.buffering || model.playbackError { Text(verbatim: playbackStatus).visionCraftAndroidText(18).foregroundStyle(ListeningAppearance.accent) }
        }.frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
    }
    private func playbackControls(_ item: ListeningItem) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            transport(item)
            if model.playbackError { Text(text("listen.play_error")).visionCraftAndroidText(18).foregroundStyle(ListeningAppearance.secondary) }
        }
    }
    @ViewBuilder private func transport(_ item: ListeningItem) -> some View {
        if item.kind == "radio" {
            ViewThatFits(in: .horizontal) {
                transportRow(item, spacious: true).frame(minWidth: 480)
                transportRow(item, spacious: false)
            }.frame(maxWidth: 640).frame(maxWidth: .infinity)
        } else {
            transportRow(item, spacious: false).frame(maxWidth: 340).frame(maxWidth: .infinity)
        }
    }
    private func transportRow(_ item: ListeningItem, spacious: Bool) -> some View {
        let running = model.playing || model.buffering
        let controlSize: CGFloat = item.kind == "episode" ? 112 : spacious ? 128 : 96
        return HStack(alignment: .center, spacing: spacious ? 24 : 12) {
            if item.kind == "radio" { channelButton(-1, spacious: spacious) }
            if item.kind == "episode" { skipButton(-10, width: 80) }
            Button { model.togglePlayback() } label: {
                VStack(spacing: 10) {
                    Image(systemName: running ? (item.kind == "radio" ? "stop.fill" : "pause.fill") : "play.fill").font(.system(size: spacious ? 44 : 38))
                        .foregroundStyle(ListeningAppearance.ink).frame(width: controlSize, height: controlSize).background(ListeningAppearance.accent, in: Circle())
                }.frame(maxWidth: .infinity).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel(text(running ? (item.kind == "radio" ? "listen.stop" : "listen.pause") : "listen.play"))
            if item.kind == "episode" { skipButton(10, width: 80) }
            if item.kind == "radio" { channelButton(1, spacious: spacious) }
        }
    }
    private func channelButton(_ direction: Int, spacious: Bool) -> some View {
        let width: CGFloat = spacious ? 128 : 80
        let iconHeight: CGFloat = spacious ? 128 : 96
        let circleSize: CGFloat = spacious ? 96 : 64
        let enabled = model.adjacentItem(direction) != nil
        return Button { model.moveItem(direction) } label: {
            Image(systemName: direction < 0 ? "backward.end.fill" : "forward.end.fill").font(.system(size: spacious ? 36 : 30))
                .frame(width: circleSize, height: circleSize)
                .background(.white.opacity(0.07), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.45), lineWidth: 1.5))
                .frame(width: width, height: iconHeight).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(text(direction < 0 ? "listen.previous_station" : "listen.next_station"))
            .disabled(!enabled).opacity(enabled ? 1 : 0.38)
    }
    private func skipButton(_ seconds: Double, width: CGFloat) -> some View {
        Button { model.skip(seconds) } label: {
            Image(systemName: seconds < 0 ? "gobackward.10" : "goforward.10").font(.system(size: 30))
                .frame(width: 64, height: 64).background(.white.opacity(0.07), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.45), lineWidth: 1.5))
                .frame(width: width, height: 96).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(text(seconds < 0 ? "listen.skip_back" : "listen.skip_forward"))
            .disabled(model.duration <= 0).opacity(model.duration <= 0 ? 0.38 : 1)
    }
    private func chapterControls(compact: Bool) -> some View {
        let chapter = model.currentChapterIndex.map { model.currentChapters[$0] }
        let title = chapter.map { $0.title.isEmpty ? clock($0.start) : $0.title } ?? ""
        return HStack(spacing: 24) {
            Group {
                if compact {
                    HStack(spacing: 12) {
                        Text(text("listen.chapter")).visionCraftAndroidText(16).foregroundStyle(ListeningAppearance.secondary)
                        Text(verbatim: title).visionCraftAndroidText(20, weight: .medium)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(text("listen.chapter")).visionCraftAndroidText(16).foregroundStyle(ListeningAppearance.secondary)
                        Text(verbatim: title).visionCraftAndroidText(20, weight: .medium)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
            HStack(spacing: 8) { chapterButton(-1); chapterButton(1) }
        }
    }
    private func chapterButton(_ direction: Int) -> some View {
        Button { model.moveChapter(direction) } label: {
            Image(systemName: direction < 0 ? "backward.end" : "forward.end").font(.system(size: 22))
                .frame(width: 56, height: 56).contentShape(Circle()).background(.white.opacity(0.07), in: Circle())
        }.buttonStyle(.plain).accessibilityLabel(text(direction < 0 ? "listen.previous_chapter" : "listen.next_chapter"))
            .disabled(!model.canMoveChapter(direction)).opacity(model.canMoveChapter(direction) ? 1 : 0.38)
    }
    private var moreTitle: String {
        switch morePage {
        case .settings: return "listen.playback_settings"
        case .episodes: return "listen.episodes"
        case .speed: return "listen.speed"
        case .sleep: return "listen.sleep"
        case .schedule: return "listen.schedule"
        }
    }
    private var sleepValue: String { model.sleepMinutes == 0 ? text("listen.off") : "\(model.sleepMinutes) \(text("listen.minutes"))" }
    private func speedValue(_ value: Float) -> String { String(format: "%g×", Double(value)) }
    private var moreHeader: some View {
        HStack(spacing: 12) {
            if morePage != .settings {
                moreIcon("chevron.left", label: "listen.back") { morePage = .settings }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(text(moreTitle)).visionCraftAndroidText(28, weight: .medium).accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($readingFocus, equals: .moreHeading(morePage))
                if morePage == .settings, let item = model.current {
                    Text(verbatim: item.kind == "episode" ? item.subtitle : item.title)
                        .visionCraftAndroidText(18).foregroundStyle(ListeningAppearance.secondary).lineLimit(2)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            moreIcon("xmark", label: "listen.close") { moreVisible = false }
        }.padding(24)
    }
    private func moreIcon(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 22, weight: .medium))
                .frame(width: 56, height: 56).contentShape(Circle())
                .background(.white.opacity(0.06), in: Circle())
        }.buttonStyle(.plain).accessibilityLabel(text(label))
    }
    private func moreRow(_ label: String, symbol: String, value: String? = nil, selected: Bool? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: symbol).font(.system(size: 24)).foregroundStyle(ListeningAppearance.accent).frame(width: 32).accessibilityHidden(true)
                Text(text(label)).visionCraftAndroidText(22, weight: .medium).frame(maxWidth: .infinity, alignment: .leading)
                if let value { Text(verbatim: value).visionCraftAndroidText(18).foregroundStyle(ListeningAppearance.secondary) }
                Image(systemName: selected == nil ? "chevron.right" : selected == true ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22)).foregroundStyle(selected == true ? ListeningAppearance.accent : ListeningAppearance.secondary)
                    .accessibilityHidden(true)
            }.padding(.horizontal, 24).padding(.vertical, 18).frame(minHeight: 76).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected == true ? .isSelected : [])
    }
    @ViewBuilder private var moreSettings: some View {
        switch morePage {
        case .settings:
            if model.current?.kind == "episode" {
                moreRow("listen.episodes", symbol: "list.bullet.rectangle", value: String(model.playbackEpisodes.count)) { morePage = .episodes }
                Divider().overlay(.white.opacity(0.1)).padding(.horizontal, 24)
                moreRow("listen.speed", symbol: "speedometer", value: speedValue(model.speed)) { morePage = .speed }
            } else {
                moreRow("listen.schedule", symbol: "clock") { morePage = .schedule }
            }
            Divider().overlay(.white.opacity(0.1)).padding(.horizontal, 24)
            moreRow("listen.sleep", symbol: "moon", value: sleepValue) { morePage = .sleep }
        case .speed:
            ForEach([Float(1), 1.25, 1.5, 2], id: \.self) { speed in
                moreRow(speedValue(speed), symbol: "speedometer", selected: model.speed == speed) { model.setSpeed(speed); morePage = .settings }
            }
        case .sleep:
            ForEach([0, 15, 30, 60], id: \.self) { minutes in
                moreRow(minutes == 0 ? text("listen.off") : "\(minutes) \(text("listen.minutes"))", symbol: minutes == 0 ? "moon" : "moon.fill", selected: model.sleepMinutes == minutes) { model.setSleep(minutes); morePage = .settings }
            }
        default: EmptyView()
        }
    }
    private var moreDialog: some View {
        GeometryReader { geometry in
            ZStack {
                VisionCraftDialogScrim { moreVisible = false }
                Group {
                    if morePage == .episodes || morePage == .schedule {
                        VStack(spacing: 0) {
                            moreHeader
                            Divider().overlay(.white.opacity(0.1))
                            ScrollView {
                                if morePage == .episodes {
                                    LazyVStack(spacing: 0) {
                                        ForEach(model.playbackEpisodes) { episode in
                                            Button { model.open(episode); moreVisible = false } label: {
                                                HStack(spacing: 16) {
                                                    ListeningArtwork(url: episode.artworkURL, title: episode.title, radio: false).frame(width: 56)
                                                    Text(verbatim: episode.title).visionCraftAndroidText(22, weight: .medium).frame(maxWidth: .infinity, alignment: .leading)
                                                    if model.current?.id == episode.id {
                                                        Image(systemName: "checkmark.circle.fill")
                                                            .foregroundStyle(ListeningAppearance.accent).accessibilityHidden(true)
                                                    }
                                                }.padding(.horizontal, 24).padding(.vertical, 18).contentShape(Rectangle())
                                            }.buttonStyle(.plain).accessibilityAddTraits(model.current?.id == episode.id ? .isSelected : [])
                                            Divider().overlay(.white.opacity(0.1)).padding(.leading, 96)
                                        }
                                    }
                                } else if let item = model.current { programTimeline(item).padding(24) }
                            }
                        }.frame(height: min(720, max(0, geometry.size.height - 48)))
                    } else {
                        ViewThatFits(in: .vertical) {
                            VStack(spacing: 0) { moreHeader; Divider().overlay(.white.opacity(0.1)); VStack(spacing: 0) { moreSettings }.padding(.vertical, 8) }.fixedSize(horizontal: false, vertical: true)
                            ScrollView { VStack(spacing: 0) { moreHeader; Divider(); moreSettings } }
                        }
                    }
                }
                .frame(width: min(640, max(0, geometry.size.width - 48)))
                .frame(maxHeight: max(0, geometry.size.height - 48))
                .background(VisionCraftUI.fixedColor(0x182820), in: RoundedRectangle(cornerRadius: 28))
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.14)))
                .foregroundStyle(ListeningAppearance.text)
            }
        }.accessibilityAddTraits(.isModal).accessibilityAction(.escape, back)
            .zIndex(100)
    }
    private func programTimeline(_ item: ListeningItem) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if model.scheduleBusy { ProgressView(text("listen.schedule_loading")) }
            else if model.programs.isEmpty {
                Text(text(!RadioSchedule.supports(item) ? "listen.schedule_unsupported" : model.scheduleFailed ? "listen.schedule_error" : "listen.schedule_empty")).visionCraftAndroidText(20)
            } else {
                ForEach(RadioSchedule.window(model.programs, now: Date())) { program in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(program.timeRange) · \(text(program.isCurrent(Date()) ? "listen.on_now" : program.end <= Date() ? "listen.previous" : "listen.up_next"))").visionCraftAndroidText(18).foregroundStyle(ListeningAppearance.secondary)
                        Text(verbatim: program.title).visionCraftAndroidText(26, weight: .medium)
                    }
                }
                Text(text("listen.live_timeline_hint")).visionCraftAndroidText(18).foregroundStyle(ListeningAppearance.secondary)
            }
        }
    }
    private var footer: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button(text("listen.info")) { information.toggle() }.buttonStyle(ListeningPillStyle())
            if information {
                Text(text("listen.foreground_hint")).visionCraftAndroidText(18)
                Text(text(model.tab == "radio" ? "listen.radio_source" : "listen.podcast_source")).visionCraftAndroidText(18)
                Link(model.tab == "radio" ? text("listen.radio_providers") : "Apple Podcasts", destination: URL(string: model.tab == "radio" ? "https://radio.bsod.kr/" : "https://podcasts.apple.com/")!).visionCraftAndroidText(18)
            }
        }.foregroundStyle(ListeningAppearance.secondary)
    }
    private func clock(_ seconds: Double) -> String { String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60) }
}

struct RatioListeningWidgetView: View {
    let active: Bool
    var backRequest = 0
    var showsPlayerBackButton = false
    var onExit: () -> Void
    @State private var seen = false
    var body: some View {
        Group {
            if seen || active {
                ListeningView(embedded: true, active: active, backRequest: backRequest,
                              showsPlayerBackButton: showsPlayerBackButton, onExit: onExit)
            }
        }
            .onAppear { if active { seen = true } }
            .onChange(of: active) { _, value in if value { seen = true } }
    }
}
