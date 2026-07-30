import Combine
import Foundation

@MainActor
protocol LocalDocumentSpeechSynthesizing:
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
    LocalDocumentSpeechSynthesizing
{}

nonisolated struct LocalDocumentSpeechSegment:
    Identifiable,
    Equatable,
    Sendable
{
    let id: Int
    let text: String
    let lineIndex: Int
    let utf16Location: Int
    let utf16Length: Int

    var utf16Range: NSRange {
        NSRange(
            location: utf16Location,
            length: utf16Length
        )
    }
}

nonisolated enum
    LocalDocumentSentenceSegmenter
{
    static func segments(
        in text: String
    ) -> [LocalDocumentSpeechSegment] {
        var results:
            [LocalDocumentSpeechSegment] =
            []

        for line in
            LocalDocumentTextSegmenter
            .lines(in: text)
        {
            appendSegments(
                in: line,
                to: &results
            )
        }
        return results
    }

    private static func appendSegments(
        in line: LocalDocumentLine,
        to results:
            inout [LocalDocumentSpeechSegment]
    ) {
        let source = line.text as NSString
        guard source.length > 0 else {
            return
        }
        var lineSegments:
            [LocalDocumentSpeechSegment] =
            []
        source.enumerateSubstrings(
            in: NSRange(
                location: 0,
                length: source.length
            ),
            options: [
                .bySentences,
                .substringNotRequired,
            ]
        ) {
            _,
            range,
            _,
            _ in
            appendTrimmedSegment(
                source: source,
                range: range,
                lineIndex: line.index,
                to: &lineSegments
            )
        }

        if lineSegments.isEmpty {
            appendTrimmedSegment(
                source: source,
                range: NSRange(
                    location: 0,
                    length: source.length
                ),
                lineIndex: line.index,
                to: &lineSegments
            )
        }
        for segment in lineSegments {
            results.append(
                LocalDocumentSpeechSegment(
                    id: results.count,
                    text: segment.text,
                    lineIndex:
                        segment.lineIndex,
                    utf16Location:
                        segment.utf16Location,
                    utf16Length:
                        segment.utf16Length
                )
            )
        }
    }

    private static func appendTrimmedSegment(
        source: NSString,
        range: NSRange,
        lineIndex: Int,
        to results:
            inout [LocalDocumentSpeechSegment]
    ) {
        guard range.location != NSNotFound,
              range.location >= 0,
              range.length >= 0,
              NSMaxRange(range)
                <= source.length else {
            return
        }
        let raw = source.substring(
            with: range
        )
        let text = raw.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !text.isEmpty else {
            return
        }
        let innerRange =
            (raw as NSString).range(of: text)
        guard innerRange.location
                != NSNotFound else {
            return
        }
        results.append(
            LocalDocumentSpeechSegment(
                id: results.count,
                text: text,
                lineIndex: lineIndex,
                utf16Location:
                    range.location
                    + innerRange.location,
                utf16Length:
                    innerRange.length
            )
        )
    }
}

nonisolated struct
    LocalDocumentSpeechSelection:
    Equatable,
    Sendable
{
    private(set) var segments:
        [LocalDocumentSpeechSegment]
    private(set) var currentIndex: Int?

    init(
        text: String,
        startingAtLine lineIndex: Int
    ) {
        segments =
            LocalDocumentSentenceSegmenter
            .segments(in: text)
        currentIndex =
            Self.startingIndex(
                in: segments,
                lineIndex: lineIndex
            )
    }

    var currentSegment:
        LocalDocumentSpeechSegment?
    {
        guard let currentIndex,
              segments.indices.contains(
                currentIndex
              ) else {
            return nil
        }
        return segments[currentIndex]
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
            < segments.count
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

    private static func startingIndex(
        in segments:
            [LocalDocumentSpeechSegment],
        lineIndex: Int
    ) -> Int? {
        guard !segments.isEmpty else {
            return nil
        }
        let safeLineIndex =
            max(lineIndex, 0)
        return segments.firstIndex {
            $0.lineIndex >= safeLineIndex
        } ?? segments.indices.last
    }
}

@MainActor
final class LocalDocumentSpeechController:
    ObservableObject
{
    @Published private(set) var selection =
        LocalDocumentSpeechSelection(
            text: "",
            startingAtLine: 0
        )
    @Published private(set) var isSpeaking =
        false

    private let tts:
        any LocalDocumentSpeechSynthesizing
    private var playbackGeneration:
        UInt64 = 0

    init(
        tts:
            (any LocalDocumentSpeechSynthesizing)?
            = nil
    ) {
        self.tts =
            tts ?? TTSManager.shared
    }

    var currentSegment:
        LocalDocumentSpeechSegment?
    {
        selection.currentSegment
    }

    var currentPositionDescription:
        String?
    {
        guard let currentIndex =
                selection.currentIndex else {
            return nil
        }
        return AppLocalization.format(
            "문서 문장 %lld/%lld",
            currentIndex + 1,
            selection.segments.count
        )
    }

    var canMovePrevious: Bool {
        selection.canMovePrevious
    }

    var canMoveNext: Bool {
        selection.canMoveNext
    }

    @discardableResult
    func play(
        text: String,
        startingAtLine lineIndex: Int
    ) -> Bool {
        setSelection(
            text: text,
            startingAtLine: lineIndex
        )
        return speakCurrent()
    }

    @discardableResult
    func toggle(
        text: String,
        startingAtLine lineIndex: Int
    ) -> Bool {
        if isSpeaking {
            stop()
            return true
        }
        return play(
            text: text,
            startingAtLine: lineIndex
        )
    }

    @discardableResult
    func previous(
        text: String,
        startingAtLine lineIndex: Int
    ) -> Bool {
        guard prepare(
            text: text,
            startingAtLine: lineIndex
        ) else {
            return false
        }
        _ = selection.movePrevious()
        return speakCurrent()
    }

    @discardableResult
    func replay(
        text: String,
        startingAtLine lineIndex: Int
    ) -> Bool {
        guard prepare(
            text: text,
            startingAtLine: lineIndex
        ) else {
            return false
        }
        return speakCurrent()
    }

    @discardableResult
    func next(
        text: String,
        startingAtLine lineIndex: Int
    ) -> Bool {
        guard prepare(
            text: text,
            startingAtLine: lineIndex
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

    func reset() {
        stop()
        selection =
            LocalDocumentSpeechSelection(
                text: "",
                startingAtLine: 0
            )
    }

    private func prepare(
        text: String,
        startingAtLine lineIndex: Int
    ) -> Bool {
        let next =
            LocalDocumentSpeechSelection(
                text: text,
                startingAtLine: lineIndex
            )
        guard !next.segments.isEmpty else {
            return false
        }

        if selection.segments
                == next.segments,
           selection.currentSegment?
            .lineIndex == max(lineIndex, 0) {
            return true
        }
        stop()
        selection = next
        return true
    }

    private func setSelection(
        text: String,
        startingAtLine lineIndex: Int
    ) {
        stop()
        selection =
            LocalDocumentSpeechSelection(
                text: text,
                startingAtLine: lineIndex
            )
    }

    @discardableResult
    private func speakCurrent() -> Bool {
        guard let segment =
                selection.currentSegment else {
            isSpeaking = false
            return false
        }

        playbackGeneration &+= 1
        let generation =
            playbackGeneration
        isSpeaking = true
        tts.speak(
            segment.text,
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
