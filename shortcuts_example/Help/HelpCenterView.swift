import SwiftUI

struct HelpCenterView: View {
    private let manual:
        HelpManualDocument?
    private let releaseNotes:
        [HelpReleaseNote]
    private let loadError: String?

    init(
        bundle: Bundle = .main,
        language: AppLanguage =
            .current()
    ) {
        var loadedManual:
            HelpManualDocument?
        var loadedReleaseNotes:
            [HelpReleaseNote] = []
        var loadedError: String?
        do {
            loadedManual =
                try HelpContentLibrary
                .manual(
                    bundle: bundle,
                    language: language
                )
            loadedReleaseNotes =
                try HelpContentLibrary
                .releaseNotes(
                    bundle: bundle,
                    language: language
                )
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
                        .visionCraftRouteBackButton()
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
                        .visionCraftRouteBackButton()
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
                Label(
                    "웹 검색을 선택하면 질문을 Gemini와 Google Search로 보냅니다. 이미지 분석은 사진을 Gemini로 보내 처리합니다. OCR 오타 자동 교정을 켜면 문서 이미지와 OCR 원문도 Gemini로 보냅니다. AI 대화와 문서 질문 답변은 이 iPad에서 처리합니다.",
                    systemImage:
                        "globe.badge.chevron.backward"
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
                NavigationLink("내장 글꼴 및 라이선스") {
                    BundledFontLicensesView()
                        .visionCraftRouteBackButton()
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.defaultMinListRowHeight, VisionCraftUI.minTouchTarget)
        .visionCraftListScreen()
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
                Text(
                    LocalizedStringKey(title)
                )
                    .font(.headline)
                Text(
                    LocalizedStringKey(
                        subtitle
                    )
                )
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

private struct BundledFontLicensesView: View {
    private struct LicenseDocument: Identifiable {
        let id: String
        let title: String
        let resource: String
    }

    private let licenses = [
        LicenseDocument(
            id: "legacy-serif",
            title: "바탕 · 궁서",
            resource: "OFL-Batang-Gungsuh"
        ),
        LicenseDocument(
            id: "legacy-sans",
            title: "굴림 · 돋움",
            resource: "OFL-Gulim-Dotum"
        ),
        LicenseDocument(
            id: "pretendard",
            title: "Pretendard",
            resource: "OFL-Pretendard"
        ),
        LicenseDocument(
            id: "suit",
            title: "SUIT",
            resource: "OFL-SUIT"
        ),
        LicenseDocument(
            id: "naver",
            title: "나눔스퀘어 네오 · 마루 부리",
            resource: "OFL-Naver-Nanum-Maru"
        ),
        LicenseDocument(
            id: "sunbatang",
            title: "순바탕",
            resource: "LICENSE-SunBatang"
        ),
    ]

    var body: some View {
        List {
            Section("HWP 호환 글꼴") {
                Text("Pretendard · SUIT · 나눔스퀘어 네오 · 마루 부리 · 순바탕")
                    .textSelection(.enabled)
                Text(
                    "원본 글꼴이 설치되어 있으면 원본을 우선하며, 없을 때만 문서 성격에 맞는 내장 글꼴로 대체합니다."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section("라이선스 전문") {
                ForEach(licenses) { license in
                    NavigationLink(license.title) {
                        BundledLicenseTextView(
                            title: license.title,
                            resource: license.resource
                        )
                        .visionCraftRouteBackButton()
                    }
                }
            }

            Section("공식 배포처") {
                Link(
                    "Pretendard",
                    destination: URL(
                        string: "https://github.com/orioncactus/pretendard"
                    )!
                )
                Link(
                    "SUIT",
                    destination: URL(string: "https://sun.fo/suit/")!
                )
                Link(
                    "네이버 글꼴 모음",
                    destination: URL(string: "https://hangeul.naver.com/font")!
                )
                Link(
                    "순바탕",
                    destination: URL(string: "https://baro.kpipa.or.kr/font/")!
                )
            }
        }
        .environment(\.defaultMinListRowHeight, VisionCraftUI.minTouchTarget)
        .visionCraftListScreen()
        .navigationTitle("내장 글꼴")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct BundledLicenseTextView: View {
    let title: String
    let resource: String

    private var text: String {
        guard let url = Bundle.main.url(
            forResource: resource,
            withExtension: "txt"
        ),
        let value = try? String(contentsOf: url, encoding: .utf8) else {
            return "라이선스 문서를 불러올 수 없습니다."
        }
        return value
    }

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .visionCraftNavigationScreen()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
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
        .environment(\.defaultMinListRowHeight, VisionCraftUI.minTouchTarget)
        .visionCraftListScreen()
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
                    AppLocalization.string(
                        allSectionsExpanded
                            ? "모두 접기"
                            : "모두 펼치기"
                    ),
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

/// Android `FullChangeLogsScreen` + `ChangeLogInfoUI`: 버전마다 카드(버전 24 Bold + "(날짜)" 한 줄,
/// 구분선, 항목마다 "- " 16). 내용은 iPad 자체 릴리스 노트(`RivoPadChangelog.txt`)를 그대로 쓴다.
struct HelpReleaseNotesView: View {
    let notes: [HelpReleaseNote]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(notes) { note in
                    releaseNoteCard(note)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
        }
        .background(VisionCraftUI.background.ignoresSafeArea())
        .visionCraftNavigationScreen()
        .navigationTitle(AppLocalization.string("전체 업데이트 기록"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("help.release-notes")
    }

    private func releaseNoteCard(_ note: HelpReleaseNote) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(note.version)
                    .visionCraftAndroidText(24, weight: .bold, relativeTo: .title2)
                    .foregroundStyle(VisionCraftUI.primaryText)
                Text("(\(note.date))")
                    .visionCraftAndroidText(14)
                    .foregroundStyle(VisionCraftUI.secondaryText)
            }
            .accessibilityElement(children: .combine)
            Divider()
                .overlay(VisionCraftUI.outline.opacity(0.4))
                .padding(.vertical, 8)
            ForEach(Array(note.texts.enumerated()), id: \.offset) { _, text in
                Text("- \(text)")
                    .visionCraftAndroidText(16)
                    .foregroundStyle(VisionCraftUI.primaryText)
                    .textSelection(.enabled)
                    .padding(.leading, 16)
                    .padding(.bottom, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .visionCraftSurfaceCard(cornerRadius: 16)
    }
}
