import Combine
import Foundation

@MainActor
protocol ChatSpeechSynthesizing:
    AnyObject
{
    func speak(
        _ text: String,
        rate: Float?,
        completion: (() -> Void)?
    )

    func stop()
}

extension TTSManager:
    ChatSpeechSynthesizing
{}

nonisolated enum ChatAnswerSentenceSegmenter {
    static func sentences(
        in rawText: String
    ) -> [String] {
        let normalized = rawText
            .replacingOccurrences(
                of: "\r\n",
                with: "\n"
            )
            .replacingOccurrences(
                of: "\r",
                with: "\n"
            )
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        guard !normalized.isEmpty else {
            return []
        }

        var results: [String] = []
        let text = normalized as NSString
        text.enumerateSubstrings(
            in: NSRange(
                location: 0,
                length: text.length
            ),
            options: [
                .bySentences,
                .substringNotRequired,
            ]
        ) { _, range, _, _ in
            let sentence = text
                .substring(with: range)
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            appendLines(
                from: sentence,
                to: &results
            )
        }

        if results.isEmpty {
            appendLines(
                from: normalized,
                to: &results
            )
        }
        return results
    }

    private static func appendLines(
        from sentence: String,
        to results: inout [String]
    ) {
        sentence
            .split(
                whereSeparator: \.isNewline
            )
            .map {
                String($0).trimmingCharacters(
                    in: .whitespaces
                )
            }
            .filter {
                !$0.isEmpty
            }
            .forEach {
                results.append($0)
            }
    }
}

nonisolated struct ChatAnswerSpeechSelection:
    Equatable,
    Sendable
{
    private(set) var sentences: [String]
    private(set) var currentIndex: Int?

    init(text: String) {
        sentences =
            ChatAnswerSentenceSegmenter
            .sentences(in: text)
        currentIndex =
            sentences.isEmpty ? nil : 0
    }

    var currentSentence: String? {
        guard let currentIndex,
              sentences.indices.contains(
                currentIndex
              ) else {
            return nil
        }
        return sentences[currentIndex]
    }

    var canMovePrevious: Bool {
        guard let currentIndex else {
            return false
        }
        return currentIndex > 0
    }

    var canMoveNext: Bool {
        guard let currentIndex else {
            return false
        }
        return currentIndex + 1
            < sentences.count
    }

    @discardableResult
    mutating func movePrevious() -> Bool {
        guard canMovePrevious,
              let currentIndex else {
            return false
        }
        self.currentIndex =
            currentIndex - 1
        return true
    }

    @discardableResult
    mutating func moveNext() -> Bool {
        guard canMoveNext,
              let currentIndex else {
            return false
        }
        self.currentIndex =
            currentIndex + 1
        return true
    }

    mutating func moveToBeginning() {
        currentIndex =
            sentences.isEmpty ? nil : 0
    }
}

@MainActor
final class ChatAnswerSpeechController:
    ObservableObject
{
    @Published private(set) var selection =
        ChatAnswerSpeechSelection(
            text: ""
        )
    @Published private(set) var
        activeMessageID: UUID?
    @Published private(set) var
        isSpeaking = false

    private let tts:
        any ChatSpeechSynthesizing
    private var playbackGeneration:
        UInt64 = 0

    init(
        tts:
            (any ChatSpeechSynthesizing)? =
                nil
    ) {
        self.tts =
            tts ?? TTSManager.shared
    }

    var currentSentence: String? {
        selection.currentSentence
    }

    var currentPositionDescription:
        String?
    {
        guard let index =
                selection.currentIndex else {
            return nil
        }
        return AppLocalization.format(
            "답변 문장 %lld/%lld",
            index + 1,
            selection.sentences.count
        )
    }

    var canMovePrevious: Bool {
        selection.canMovePrevious
    }

    var canMoveNext: Bool {
        selection.canMoveNext
    }

    @discardableResult
    func prepare(
        messageID: UUID,
        text: String
    ) -> Bool {
        let nextSelection =
            ChatAnswerSpeechSelection(
                text: text
            )
        guard !nextSelection
                .sentences.isEmpty else {
            return false
        }

        if activeMessageID == messageID,
           selection.sentences
            == nextSelection.sentences {
            return true
        }

        stop()
        activeMessageID = messageID
        selection = nextSelection
        return true
    }

    @discardableResult
    func play(
        messageID: UUID,
        text: String,
        fromBeginning: Bool = true
    ) -> Bool {
        guard prepare(
            messageID: messageID,
            text: text
        ) else {
            return false
        }
        if fromBeginning {
            selection.moveToBeginning()
        }
        return speakCurrent()
    }

    @discardableResult
    func toggle(
        messageID: UUID,
        text: String
    ) -> Bool {
        if isSpeaking,
           activeMessageID == messageID {
            stop()
            return true
        }
        return play(
            messageID: messageID,
            text: text,
            fromBeginning: true
        )
    }

    @discardableResult
    func previous(
        messageID: UUID,
        text: String
    ) -> Bool {
        guard prepare(
            messageID: messageID,
            text: text
        ) else {
            return false
        }
        _ = selection.movePrevious()
        return speakCurrent()
    }

    @discardableResult
    func replay(
        messageID: UUID,
        text: String
    ) -> Bool {
        guard prepare(
            messageID: messageID,
            text: text
        ) else {
            return false
        }
        return speakCurrent()
    }

    @discardableResult
    func next(
        messageID: UUID,
        text: String
    ) -> Bool {
        guard prepare(
            messageID: messageID,
            text: text
        ) else {
            return false
        }
        _ = selection.moveNext()
        return speakCurrent()
    }

    func stop() {
        playbackGeneration &+= 1
        isSpeaking = false
        tts.stop()
    }

    @discardableResult
    private func speakCurrent() -> Bool {
        guard let sentence =
                selection.currentSentence else {
            return false
        }

        playbackGeneration &+= 1
        let generation =
            playbackGeneration
        isSpeaking = true
        tts.speak(
            sentence,
            rate: nil,
            completion: {
                [weak self] in
                guard let self,
                      self.playbackGeneration
                        == generation else {
                    return
                }
                self.advanceAfterSpeech()
            }
        )
        return true
    }

    private func advanceAfterSpeech() {
        guard selection.moveNext() else {
            isSpeaking = false
            return
        }
        _ = speakCurrent()
    }
}
