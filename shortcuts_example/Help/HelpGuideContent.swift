import Foundation

nonisolated enum HelpGuideAction: String, Codable, CaseIterable, Sendable {
    case home, camera, scan, liveText, image, chat, history, textSource
    case documents, books, translation, webSearch, voice, remote, visionLink
    case settings, permissions

    var title: String {
        switch self {
        case .home: "홈으로 이동"
        case .camera: "카메라 열기"
        case .scan: "문서 스캔 열기"
        case .liveText: "실시간 문자 읽기 열기"
        case .image: "이미지 분석 열기"
        case .chat: "새 대화 열기"
        case .history: "대화기록 열기"
        case .textSource: "텍스트 뷰어 열기"
        case .documents: "문서 작업 열기"
        case .books: "데이지/EPUB 플레이어 열기"
        case .translation: "로컬 번역 열기"
        case .webSearch: "웹 검색 열기"
        case .voice: "음성 명령 시작"
        case .remote: "리모컨 연결 열기"
        case .visionLink: "스마트폰과 연동 열기"
        case .settings: "모든 설정 열기"
        case .permissions: "앱 권한 설정 열기"
        }
    }
}

nonisolated struct HelpGuideTopic: Codable, Hashable, Identifiable, Sendable {
    enum Group: String, Codable, Sendable { case feature, problem }
    let id: String
    let group: Group
    let feature: String
    let situation: String
    let icon: String
    let steps: [String]
    let tip: String
    let action: HelpGuideAction

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || ([feature, situation, tip] + steps)
            .contains { $0.localizedStandardContains(query) }
    }
}

nonisolated enum HelpGuideContent {
    /// Android `UserGuideContent.situations` 순서. iOS 전용 항목은 이웃한 항목 뒤에 둔다.
    static let situationOrder: [String] = [
        "start", "printed_text", "live", "scan", "image", "chat", "books", "text",
        "documents", "editing", "translation", "web", "voice", "history", "remote",
        "visionlink", "share", "widgets", "settings", "accessibility",
    ]

    /// Android처럼 상황별 목록에만 나오는 항목(`printedText`).
    static let situationOnlyIDs: Set<String> = ["printed_text"]

    /// Android처럼 리보탭 리모컨 매뉴얼 링크를 보여 주는 항목.
    static let remoteManualTopicIDs: Set<String> = ["remote", "connection"]

    static func situations(_ topics: [HelpGuideTopic]) -> [HelpGuideTopic] {
        let features = topics.filter { $0.group == .feature }
        let rank = Dictionary(
            uniqueKeysWithValues: situationOrder.enumerated().map { ($1, $0) }
        )
        return features.enumerated().sorted { lhs, rhs in
            let l = rank[lhs.element.id] ?? situationOrder.count + lhs.offset
            let r = rank[rhs.element.id] ?? situationOrder.count + rhs.offset
            return l < r
        }.map(\.element)
    }

    static func features(_ topics: [HelpGuideTopic]) -> [HelpGuideTopic] {
        topics.filter { $0.group == .feature && !situationOnlyIDs.contains($0.id) }
    }

    static func load(
        bundle: Bundle = .main,
        language: AppLanguage = .current()
    ) throws -> [HelpGuideTopic] {
        let localized = bundle.path(
            forResource: language.effectiveLanguageCode,
            ofType: "lproj"
        ).flatMap(Bundle.init(path:))
        guard let url = localized?.url(forResource: "VisionCraftGuide", withExtension: "json")
            ?? bundle.url(forResource: "VisionCraftGuide", withExtension: "json") else {
            throw HelpDocumentError.missingResource("VisionCraftGuide")
        }
        return try decode(Data(contentsOf: url))
    }

    static func decode(_ data: Data) throws -> [HelpGuideTopic] {
        let topics = try JSONDecoder().decode([HelpGuideTopic].self, from: data)
        guard !topics.isEmpty,
              Set(topics.map(\.id)).count == topics.count,
              topics.allSatisfy({ topic in
                  !topic.steps.isEmpty &&
                  ([topic.id, topic.feature, topic.situation, topic.icon, topic.tip] + topic.steps)
                      .allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
              }) else {
            throw HelpDocumentError.emptyDocument
        }
        return topics
    }
}
