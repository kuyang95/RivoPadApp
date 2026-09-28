import Foundation

/// Decides whether a chat question can only be answered with current, live
/// information — today's weather, news, prices, scores, schedules.
///
/// Android classifies this with a Gemini call on every message. VisionCraft
/// for iPad promises that AI chat is answered on the device, so the decision
/// itself must not leave it: this is a deterministic match on volatile topics,
/// deliberately conservative. A question that does not clearly need the live
/// web is answered by the local model, exactly as before.
nonisolated enum ChatWebSearchRouter {
    /// Topics whose answer changes from day to day. One of these is enough,
    /// because a question that mentions them cannot be answered from a
    /// model's training data.
    private static let volatileTopics: [String] = [
        // Korean
        // Short, ambiguous words are deliberately left out ("비 와" also
        // matches "나비 와"): a false positive would send a private chat
        // message to the cloud, while a false negative only means the local
        // model answers it.
        "날씨", "기온", "미세먼지", "황사", "자외선",
        "뉴스", "속보", "환율", "달러 환율", "주가", "주식", "코스피",
        "코스닥", "나스닥", "시세", "금값", "유가", "기름값", "물가",
        "경기 결과", "경기결과", "스코어", "순위표", "실시간",
        "개봉일", "출시일", "발매일", "예매율", "박스오피스",
        // English
        "weather", "forecast", "temperature outside", "air quality",
        "news", "headline", "breaking", "exchange rate", "stock price",
        "share price", "nasdaq", "s&p", "market price", "gold price",
        "oil price", "box office", "live score", "match result",
        "release date",
        // Japanese
        "天気", "気温", "ニュース", "速報", "為替", "株価", "相場",
        "ガソリン価格", "試合結果", "公開日", "発売日",
    ]

    /// Words that anchor a question to right now. On their own they are not
    /// enough ("오늘 기분 어때?"), so they only count together with a word
    /// that asks for a looked-up value.
    private static let currentTimeMarkers: [String] = [
        "오늘", "지금", "현재", "이번 주", "이번주", "최근", "최신",
        "올해", "내일", "어제",
        "today", "right now", "currently", "this week", "latest",
        "most recent", "tomorrow",
        "今日", "今", "現在", "今週", "最新", "明日",
    ]

    /// Words that ask for a value to be looked up rather than explained.
    private static let lookupMarkers: [String] = [
        "얼마", "몇 시", "몇시", "며칠", "언제", "어디서 해", "열려",
        "영업", "운행", "상태", "일정", "스케줄", "예보",
        "how much", "what time", "when is", "when does", "schedule",
        "open now", "status",
        "いくら", "何時", "いつ", "予定", "予報", "営業",
    ]

    static func requiresCurrentInformation(_ prompt: String) -> Bool {
        let normalized = prompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else {
            return false
        }
        if contains(normalized, any: volatileTopics) {
            return true
        }
        return contains(normalized, any: currentTimeMarkers)
            && contains(normalized, any: lookupMarkers)
    }

    private static func contains(
        _ text: String,
        any needles: [String]
    ) -> Bool {
        needles.contains { text.contains($0) }
    }
}
