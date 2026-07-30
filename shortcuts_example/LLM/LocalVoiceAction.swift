import Foundation

nonisolated enum LocalVoiceActionIntent:
    Equatable,
    Sendable
{
    case readVisibleText
    case describeScene
    case capture
    case openAIChat
    case openChatHistory
    case openAIDocument
    case openReader
    case openDocumentScanner
    case openMagnifier
    case openCamera
    case openTextDocument
    case translate(String)
    case introduce
    case webSearch(String)
    case question(String)
}

nonisolated enum LocalVoiceActionClassifier {
    static func classify(
        _ transcription: String
    ) -> LocalVoiceActionIntent? {
        let original = transcription.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !original.isEmpty else {
            return nil
        }

        let normalized = original
            .lowercased()
            .replacingOccurrences(
                of: "[\\s\\p{P}\\p{S}]+",
                with: "",
                options: .regularExpression
            )

        if containsAny(
            normalized,
            [
                "너는누구",
                "누구니",
                "정체가뭐",
                "자기소개",
            ]
        ) {
            return .introduce
        }
        if containsAny(
            normalized,
            [
                "문서스캔",
                "문서촬영",
                "스캐너열",
                "스캔해",
            ]
        ) {
            return .openDocumentScanner
        }
        if containsAny(
            normalized,
            [
                "채팅기록",
                "대화기록",
                "대화목록",
                "채팅목록",
            ]
        ) {
            return .openChatHistory
        }
        if containsAny(
            normalized,
            [
                "문서질문",
                "문서에질문",
                "문서ai",
                "ai문서",
                "문서분석",
            ]
        ) {
            return .openAIDocument
        }
        if containsAny(
            normalized,
            [
                "새채팅",
                "새대화",
                "자유대화",
                "ai채팅",
                "인공지능채팅",
            ]
        ) {
            return .openAIChat
        }
        if containsAny(
            normalized,
            [
                "데이지",
                "daisy",
                "전자책",
                "독서열",
                "책읽",
            ]
        ) {
            return .openReader
        }
        if containsAny(
            normalized,
            [
                "실시간텍스트",
                "글자읽",
                "텍스트읽",
                "ocr",
                "문자읽",
            ]
        ) {
            return .readVisibleText
        }
        if containsAny(
            normalized,
            [
                "장면설명",
                "이미지설명",
                "사진설명",
                "뭐가보",
                "무엇이보",
            ]
        ) {
            return .describeScene
        }
        if containsAny(
            normalized,
            [
                "사진찍",
                "촬영해",
                "캡처해",
                "화면캡처",
            ]
        ) {
            return .capture
        }
        if containsAny(
            normalized,
            [
                "돋보기",
                "확대경",
                "화면확대",
            ]
        ) {
            return .openMagnifier
        }
        if containsAny(
            normalized,
            [
                "카메라열",
                "카메라켜",
                "카메라모드",
            ]
        ) {
            return .openCamera
        }
        if containsAny(
            normalized,
            [
                "텍스트문서",
                "문서열",
                "파일열",
                "텍스트모드",
            ]
        ) {
            return .openTextDocument
        }
        if containsAny(
            normalized,
            [
                "번역",
                "translate",
            ]
        ) {
            return .translate(original)
        }
        if containsAny(
            normalized,
            [
                "웹검색",
                "인터넷검색",
                "구글검색",
                "검색해",
                "최신뉴스",
                "오늘날씨",
            ]
        ) {
            return .webSearch(original)
        }
        return .question(original)
    }

    private static func containsAny(
        _ value: String,
        _ candidates: [String]
    ) -> Bool {
        candidates.contains {
            value.contains($0)
        }
    }
}
