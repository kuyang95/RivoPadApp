import SwiftUI

struct HelpCenterView: View {
    private let manual:
        HelpManualDocument?
    private let releaseNotes:
        [HelpReleaseNote]
    private let loadError: String?

    init(bundle: Bundle = .main) {
        var loadedManual:
            HelpManualDocument?
        var loadedReleaseNotes:
            [HelpReleaseNote] = []
        var loadedError: String?
        do {
            loadedManual =
                try HelpContentLibrary
                .manual(bundle: bundle)
            loadedReleaseNotes =
                try HelpContentLibrary
                .releaseNotes(bundle: bundle)
        } catch {
            loadedError =
                error.localizedDescription
        }
        manual = loadedManual
        releaseNotes = loadedReleaseNotes
        loadError = loadedError
    }

    var body: some View {
        List {
            Section("안내") {
                if let manual {
                    NavigationLink {
                        HelpManualView(
                            document: manual
                        )
                    } label: {
                        helpRow(
                            title: "iPad 사용 설명서",
                            subtitle:
                                "기능 사용법, 접근성, Android와 다른 점",
                            systemImage:
                                "book.pages"
                        )
                    }
                }

                if !releaseNotes.isEmpty {
                    NavigationLink {
                        HelpReleaseNotesView(
                            notes: releaseNotes
                        )
                    } label: {
                        helpRow(
                            title: "변경 내역",
                            subtitle:
                                "포팅된 기능과 최근 개선 사항",
                            systemImage:
                                "clock.arrow.circlepath"
                        )
                    }
                }
            }

            if let latest = releaseNotes.first {
                Section("최근 변경") {
                    LabeledContent(
                        "버전",
                        value: latest.version
                    )
                    LabeledContent(
                        "날짜",
                        value: latest.date
                    )
                    ForEach(
                        Array(
                            latest.texts
                                .prefix(3)
                                .enumerated()
                        ),
                        id: \.offset
                    ) { _, text in
                        bullet(text)
                    }
                }
            }

            Section("개인정보와 로컬 처리") {
                Label(
                    "AI·OCR·문서 처리는 가능한 범위에서 이 iPad 안에서 실행합니다.",
                    systemImage:
                        "lock.shield"
                )
                Label(
                    "공유한 항목은 App Group 수신함을 거쳐 VisionCraft가 로컬로 엽니다.",
                    systemImage:
                        "square.and.arrow.down"
                )
            }

            Section {
                Text(
                    "iPadOS에서는 다른 앱을 임의로 누르거나, 시스템 VoiceOver·밝기·회전 잠금을 VisionCraft가 직접 바꿀 수 없습니다. 사용 설명서에 가능한 대체 경로를 적어 두었습니다."
                )
            } header: {
                Text("Android와 다른 점")
            }

            if let loadError {
                Section {
                    ContentUnavailableView(
                        "도움말을 열 수 없습니다",
                        systemImage:
                            "exclamationmark.triangle",
                        description:
                            Text(loadError)
                    )
                }
            }

            Section("앱 정보") {
                LabeledContent(
                    "버전",
                    value: appVersion
                )
                LabeledContent(
                    "빌드",
                    value: appBuild
                )
            }
        }
        .navigationTitle("도움말")
        .navigationBarTitleDisplayMode(.large)
    }

    @ViewBuilder
    private func helpRow(
        title: String,
        subtitle: String,
        systemImage: String
    ) -> some View {
        Label {
            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .font(.title2)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func bullet(
        _ text: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("•")
                .accessibilityHidden(true)
            Text(text)
        }
        .accessibilityElement(
            children: .combine
        )
    }

    private var appVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey:
                "CFBundleShortVersionString"
        ) as? String ?? "1.0"
    }

    private var appBuild: String {
        Bundle.main.object(
            forInfoDictionaryKey:
                "CFBundleVersion"
        ) as? String ?? "1"
    }
}

private struct HelpManualView: View {
    let document: HelpManualDocument

    @State private var searchText = ""
    @State private var expandedSectionIDs =
        Set<String>()

    var body: some View {
        List {
            Section {
                Text(document.title)
                    .font(.title2.bold())
                LabeledContent(
                    "문서 버전",
                    value: document.version
                )
                LabeledContent(
                    "갱신일",
                    value: document.date
                )
            }

            ForEach(filteredChapters) {
                chapter in
                Section(chapter.name) {
                    ForEach(chapter.sections) {
                        section in
                        DisclosureGroup(
                            isExpanded:
                                expansionBinding(
                                    for: section.id
                                )
                        ) {
                            sectionContent(
                                section
                            )
                        } label: {
                            Text(section.name)
                                .font(.headline)
                        }
                    }
                }
            }

            if filteredChapters.isEmpty {
                ContentUnavailableView.search(
                    text: searchText
                )
            }
        }
        .navigationTitle("사용 설명서")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            prompt: "기능이나 버튼 검색"
        )
        .toolbar {
            ToolbarItem(
                placement: .primaryAction
            ) {
                Button(
                    allSectionsExpanded
                        ? "모두 접기"
                        : "모두 펼치기",
                    systemImage:
                        allSectionsExpanded
                        ? "rectangle.compress.vertical"
                        : "rectangle.expand.vertical"
                ) {
                    if allSectionsExpanded {
                        expandedSectionIDs
                            .removeAll()
                    } else {
                        expandedSectionIDs =
                            allSectionIDs
                    }
                }
            }
        }
    }

    private var filteredChapters:
        [HelpManualChapter]
    {
        let query = searchText
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        guard !query.isEmpty else {
            return document.chapters
        }
        return document.chapters.compactMap {
            chapter in
            let sections =
                chapter.sections.filter {
                    $0.searchableText
                        .localizedCaseInsensitiveContains(
                            query
                        )
                    || chapter.name
                        .localizedCaseInsensitiveContains(
                            query
                        )
                }
            guard !sections.isEmpty else {
                return nil
            }
            return HelpManualChapter(
                id: chapter.id,
                name: chapter.name,
                sections: sections
            )
        }
    }

    private var allSectionIDs:
        Set<String>
    {
        Set(
            document.chapters.flatMap {
                $0.sections.map(\.id)
            }
        )
    }

    private var allSectionsExpanded: Bool {
        !allSectionIDs.isEmpty
            && allSectionIDs
                .isSubset(
                    of: expandedSectionIDs
                )
    }

    private func expansionBinding(
        for id: String
    ) -> Binding<Bool> {
        Binding(
            get: {
                !searchText.isEmpty
                    || expandedSectionIDs
                    .contains(id)
            },
            set: { value in
                guard searchText.isEmpty else {
                    return
                }
                if value {
                    expandedSectionIDs.insert(
                        id
                    )
                } else {
                    expandedSectionIDs.remove(
                        id
                    )
                }
            }
        )
    }

    @ViewBuilder
    private func sectionContent(
        _ section: HelpManualSection
    ) -> some View {
        ForEach(
            Array(section.texts.enumerated()),
            id: \.offset
        ) { _, text in
            bullet(text)
        }
        ForEach(section.subsections) {
            subsection in
            Text(subsection.name)
                .font(.subheadline.bold())
                .padding(.top, 4)
            ForEach(
                Array(
                    subsection.texts
                        .enumerated()
                ),
                id: \.offset
            ) { _, text in
                bullet(text)
                    .padding(.leading, 12)
            }
        }
    }

    @ViewBuilder
    private func bullet(
        _ text: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("•")
                .accessibilityHidden(true)
            Text(text)
                .textSelection(.enabled)
        }
        .accessibilityElement(
            children: .combine
        )
    }
}

private struct HelpReleaseNotesView:
    View
{
    let notes: [HelpReleaseNote]

    var body: some View {
        List(notes) { note in
            Section {
                ForEach(
                    Array(
                        note.texts.enumerated()
                    ),
                    id: \.offset
                ) { _, text in
                    HStack(
                        alignment:
                            .firstTextBaseline
                    ) {
                        Text("•")
                            .accessibilityHidden(
                                true
                            )
                        Text(text)
                            .textSelection(
                                .enabled
                            )
                    }
                    .accessibilityElement(
                        children: .combine
                    )
                }
            } header: {
                VStack(alignment: .leading) {
                    Text("버전 \(note.version)")
                    Text(note.date)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("변경 내역")
        .navigationBarTitleDisplayMode(.inline)
    }
}
