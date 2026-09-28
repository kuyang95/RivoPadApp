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
                    topicRows(group: .feature)
                    if filteredTopics.contains(where: { $0.group == .problem }) {
                        Text(localized("문제 해결"))
                            .visionCraftAndroidText(22, weight: .semibold, relativeTo: .title2)
                            .foregroundStyle(VisionCraftUI.primaryText)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.top, 32)
                            .padding(.bottom, 8)
                        topicRows(group: .problem)
                    }
                }

                NavigationLink {
                    HelpCenterView(language: language)
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
                        .frame(width: 44, height: 44)
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

    private func topicRows(group: HelpGuideTopic.Group) -> some View {
        ForEach(filteredTopics.filter { $0.group == group }) { topic in
            NavigationLink(value: topic) {
                HStack(spacing: 12) {
                    Image(systemName: topic.icon)
                        .font(.system(size: 23, weight: .regular))
                        .foregroundStyle(VisionCraftHomeUI.icon)
                        .frame(width: 30)
                        .accessibilityHidden(true)
                    Text(showsFeatures && group == .feature ? topic.feature : topic.situation)
                        .visionCraftAndroidText(18, weight: .medium, relativeTo: .headline)
                        .foregroundStyle(VisionCraftUI.primaryText)
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

                Button {
                    onAction(topic.action)
                } label: {
                    Label(localized(topic.action.title), systemImage: "arrow.up.right")
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(VisionCraftAndroidButtonStyle())
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

private struct HelpGuidePageStyle: ViewModifier {
    let language: AppLanguage
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .background(VisionCraftUI.background.ignoresSafeArea())
            .tint(VisionCraftUI.primary)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 4) {
                    Button { dismiss() } label: {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 24, weight: .regular))
                            .frame(width: 48, height: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppLocalization.string("뒤로", language: language))
                    .accessibilityIdentifier("guide.back")
                    Text(AppLocalization.string("사용 설명서", language: language))
                        .visionCraftAndroidText(22, weight: .semibold, relativeTo: .title2)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(VisionCraftUI.primaryText)
                .padding(.horizontal, 4)
                .frame(minHeight: 64)
                .background(VisionCraftUI.background)
            }
            .navigationTitle(AppLocalization.string("사용 설명서", language: language))
            .toolbar(.hidden, for: .navigationBar)
            .visionCraftHandlesBackNavigation()
    }
}
