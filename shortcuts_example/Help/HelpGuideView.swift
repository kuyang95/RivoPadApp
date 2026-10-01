import SwiftUI

struct HelpGuideView: View {
    private let topics: [HelpGuideTopic]
    private let loadError: String?
    let language: AppLanguage
    let onAction: (HelpGuideAction) -> Void
    @State private var showsFeatures = false
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    init(
        bundle: Bundle = .main,
        language: AppLanguage = .current(),
        onAction: @escaping (HelpGuideAction) -> Void
    ) {
        self.language = language
        self.onAction = onAction
        do {
            topics = try HelpGuideContent.load(bundle: bundle, language: language)
            loadError = nil
        } catch {
            topics = []
            loadError = error.localizedDescription
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    categoryButton("상황별", features: false)
                    categoryButton("기능별", features: true)
                }
                .padding(5)
                .background(VisionCraftUI.surfaceVariant, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityIdentifier("guide.categories")
                .padding(.bottom, 12)

                searchField
                    .padding(.bottom, 16)

                if let loadError {
                    ContentUnavailableView(
                        localized("도움말을 열 수 없습니다"),
                        systemImage: "exclamationmark.triangle",
                        description: Text(loadError)
                    )
                } else if filteredTopics.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    topicRows(
                        showsFeatures
                            ? HelpGuideContent.features(filteredTopics)
                            : HelpGuideContent.situations(filteredTopics),
                        showsSubtitle: showsFeatures
                    )
                    if filteredTopics.contains(where: { $0.group == .problem }) {
                        Text(localized("문제 해결"))
                            .visionCraftAndroidText(22, weight: .semibold, relativeTo: .title2)
                            .foregroundStyle(VisionCraftUI.primaryText)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.top, 32)
                            .padding(.bottom, 8)
                        topicRows(filteredTopics.filter { $0.group == .problem }, showsSubtitle: false)
                    }
                }

                NavigationLink {
                    HelpCenterView(language: language)
                        .visionCraftRouteBackButton()
                        .toolbar(.visible, for: .navigationBar)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "books.vertical")
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(localized("전체 설명서와 앱 정보"))
                                .visionCraftAndroidText(18, weight: .medium, relativeTo: .headline)
                            Text(localized("자세한 설명서, 업데이트 기록, 개인정보와 라이선스"))
                                .visionCraftAndroidText(16)
                                .foregroundStyle(VisionCraftUI.secondaryText)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .accessibilityHidden(true)
                    }
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(VisionCraftUI.primaryText)
                    .padding(20)
                    .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
                    .background(VisionCraftUI.surface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(VisionCraftUI.outline, lineWidth: 1)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(VisionCraftHomePressStyle())
                .accessibilityIdentifier("guide.full-manual")
                .padding(.top, 28)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .modifier(HelpGuidePageStyle(language: language))
        .scrollDismissesKeyboard(.interactively)
        .navigationDestination(for: HelpGuideTopic.self) { topic in
            HelpGuideDetailView(topic: topic, language: language, onAction: onAction)
        }
    }

    private var filteredTopics: [HelpGuideTopic] {
        topics.filter { $0.matches(query) }
    }

    private func localized(_ key: String) -> String {
        AppLocalization.string(key, language: language)
    }

    private func categoryButton(_ label: String, features: Bool) -> some View {
        let selected = showsFeatures == features
        return Button {
            showsFeatures = features
        } label: {
            Text(localized(label))
                .visionCraftAndroidText(16, weight: .medium)
                .foregroundStyle(selected ? VisionCraftHomeUI.onPrimary : VisionCraftUI.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(selected ? VisionCraftUI.primary : Color.clear, in: RoundedRectangle(cornerRadius: 11))
                .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(features ? "guide.category.feature" : "guide.category.situation")
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(VisionCraftUI.secondaryText)
                .accessibilityHidden(true)
            TextField(localized("기능이나 궁금한 내용 검색"), text: $query)
                .textFieldStyle(.plain)
                .visionCraftAndroidText(18)
                .foregroundStyle(VisionCraftUI.primaryText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isSearchFocused)
                .onSubmit { isSearchFocused = false }
                .padding(.vertical, 12)
                .accessibilityLabel(localized("기능이나 궁금한 내용 검색"))
                .accessibilityIdentifier("guide.search")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(VisionCraftUI.secondaryText)
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(localized("지우기"))
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(minHeight: 52)
        .background(VisionCraftUI.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(VisionCraftUI.outline, lineWidth: 1)
        }
    }

    /// Android `GuideRow`: 기능별 보기에서는 상황 문장을 부제로 보여 준다.
    private func topicRows(_ topics: [HelpGuideTopic], showsSubtitle: Bool) -> some View {
        ForEach(topics) { topic in
            NavigationLink(value: topic) {
                HStack(spacing: 12) {
                    Image(systemName: topic.icon)
                        .font(.system(size: 23, weight: .regular))
                        .foregroundStyle(VisionCraftHomeUI.icon)
                        .frame(width: 30)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(showsSubtitle ? topic.feature : topic.situation)
                            .visionCraftAndroidText(18, weight: .medium, relativeTo: .headline)
                            .foregroundStyle(VisionCraftUI.primaryText)
                        if showsSubtitle {
                            Text(topic.situation)
                                .visionCraftAndroidText(16)
                                .foregroundStyle(VisionCraftUI.secondaryText)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(VisionCraftUI.secondaryText)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("guide.topic.\(topic.id)")
            Divider().overlay(VisionCraftUI.outline)
        }
    }
}

struct HelpGuideDetailView: View {
    let topic: HelpGuideTopic
    let language: AppLanguage
    let onAction: (HelpGuideAction) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Label(topic.feature, systemImage: topic.icon)
                        .visionCraftAndroidText(16, weight: .medium)
                        .foregroundStyle(VisionCraftUI.primary)
                    Text(topic.situation)
                        .visionCraftAndroidText(24, weight: .bold, relativeTo: .title)
                        .foregroundStyle(VisionCraftUI.primaryText)
                        .accessibilityAddTraits(.isHeader)
                }

                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(topic.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(index + 1).")
                                .visionCraftAndroidText(18)
                                .foregroundStyle(VisionCraftUI.primaryText)
                            Text(step)
                                .visionCraftAndroidText(18)
                                .foregroundStyle(VisionCraftUI.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label(localized("함께 알아두세요"), systemImage: "lightbulb")
                        .visionCraftAndroidText(18, weight: .medium, relativeTo: .headline)
                        .foregroundStyle(VisionCraftUI.primaryText)
                        .accessibilityAddTraits(.isHeader)
                    Text(topic.tip)
                        .visionCraftAndroidText(16)
                        .foregroundStyle(VisionCraftUI.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(VisionCraftUI.surface, in: RoundedRectangle(cornerRadius: 12))

                if HelpGuideContent.remoteManualTopicIDs.contains(topic.id) {
                    // Android `GuideDetail`: 리모컨 항목에만 리보탭 매뉴얼 글자 버튼.
                    NavigationLink {
                        HelpRemoteManualView(language: language)
                    } label: {
                        Text(localized("리보탭 리모컨 자세히 알아보기"))
                            .visionCraftAndroidText(16, weight: .medium)
                            .foregroundStyle(VisionCraftUI.primary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, -8)
                    .accessibilityIdentifier("guide.remote-manual")
                }

                Button {
                    onAction(topic.action)
                } label: {
                    Label(localized(topic.action.title), systemImage: "arrow.up.right")
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(VisionCraftAndroidButtonStyle(filled: true))
                .padding(.top, 4)
                .accessibilityIdentifier("guide.open-feature")
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .modifier(HelpGuidePageStyle(language: language))
    }

    private func localized(_ key: String) -> String {
        AppLocalization.string(key, language: language)
    }
}

/// Android `RemoteManualScreen` + `ManualScreen`: `assets/manual`을 평면 목록으로 보여 준다.
struct HelpRemoteManualView: View {
    let language: AppLanguage
    private let document: HelpManualDocument?
    private let loadError: String?

    init(bundle: Bundle = .main, language: AppLanguage = .current()) {
        self.language = language
        do {
            document = try HelpContentLibrary.remoteManual(bundle: bundle, language: language)
            loadError = nil
        } catch {
            document = nil
            loadError = error.localizedDescription
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let document {
                    manualBody(document)
                } else {
                    Text(localized("매뉴얼을 불러오지 못했어요. 뒤로 돌아가 다시 열어주세요."))
                        .visionCraftAndroidText(18)
                        .foregroundStyle(VisionCraftUI.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let loadError {
                        Text(loadError)
                            .visionCraftAndroidText(14)
                            .foregroundStyle(VisionCraftUI.secondaryText)
                            .padding(.top, 8)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .modifier(HelpGuidePageStyle(language: language, title: "매뉴얼"))
        .accessibilityIdentifier("guide.remote-manual.screen")
    }

    @ViewBuilder
    private func manualBody(_ document: HelpManualDocument) -> some View {
        Text(document.title)
            .visionCraftAndroidText(20, weight: .bold, relativeTo: .title2)
            .foregroundStyle(VisionCraftUI.primaryText)
            .accessibilityAddTraits(.isHeader)
            .padding(.bottom, 8)
        Text(String(format: localized("버전: %@"), document.version))
            .visionCraftAndroidText(14)
            .foregroundStyle(VisionCraftUI.primaryText)
            .padding(.bottom, 4)
        Text(String(format: localized("날짜: %@"), document.date))
            .visionCraftAndroidText(14)
            .foregroundStyle(VisionCraftUI.primaryText)
            .padding(.bottom, 16)
        ForEach(document.chapters) { chapter in
            Text(chapter.name)
                .visionCraftAndroidText(18, weight: .semibold, relativeTo: .headline)
                .foregroundStyle(VisionCraftUI.primaryText)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 8)
                .padding(.bottom, 4)
            ForEach(chapter.sections) { section in
                Text(section.name)
                    .visionCraftAndroidText(16, weight: .medium)
                    .foregroundStyle(VisionCraftUI.primaryText)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                ForEach(Array(section.texts.enumerated()), id: \.offset) { _, text in
                    manualLine(text, indent: 16)
                        .padding(.vertical, 4)
                }
                ForEach(section.subsections) { subsection in
                    Text(subsection.name)
                        .visionCraftAndroidText(18)
                        .foregroundStyle(VisionCraftUI.primaryText)
                        .padding(.vertical, 2)
                        .padding(.leading, 8)
                    ForEach(Array(subsection.texts.enumerated()), id: \.offset) { _, text in
                        manualLine(text, indent: 24)
                            .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func manualLine(_ text: String, indent: CGFloat) -> some View {
        Text("- \(text)")
            .visionCraftAndroidText(18)
            .lineSpacing(6)
            .foregroundStyle(VisionCraftUI.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, indent)
    }

    private func localized(_ key: String) -> String {
        AppLocalization.string(key, language: language)
    }
}

private struct HelpGuidePageStyle: ViewModifier {
    let language: AppLanguage
    var title = "사용 설명서"
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .background(VisionCraftUI.background.ignoresSafeArea())
            .tint(VisionCraftUI.primary)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 4) {
                    VisionCraftBackButton { dismiss() }
                    .accessibilityLabel(AppLocalization.string("뒤로", language: language))
                    .accessibilityIdentifier("guide.back")
                    Text(AppLocalization.string(title, language: language))
                        .visionCraftAndroidText(22, weight: .semibold, relativeTo: .title2)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(VisionCraftUI.primaryText)
                .padding(.horizontal, 4)
                .frame(minHeight: 64)
                .background(VisionCraftUI.background)
            }
            .navigationTitle(AppLocalization.string(title, language: language))
            .toolbar(.hidden, for: .navigationBar)
            .visionCraftHandlesBackNavigation()
    }
}
