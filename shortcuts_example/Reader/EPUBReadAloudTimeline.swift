import Foundation

nonisolated struct EPUBReadAloudTimeline:
    Equatable,
    Sendable
{
    nonisolated struct Entry:
        Equatable,
        Sendable
    {
        let stepIndex: Int
        let startSeconds: Double
        let durationSeconds: Double
        let audioClipBeginSeconds: Double?
        let audioSeekDurationSeconds: Double?
        let textUTF16Length: Int

        var endSeconds: Double {
            startSeconds + durationSeconds
        }
    }

    nonisolated struct Target:
        Equatable,
        Sendable
    {
        let stepIndex: Int
        let timelineSeconds: Double
        let progressWithinStep: Double
        let audioTimeSeconds: Double?
        let textUTF16Offset: Int
    }

    private static let estimatedCharactersPerSecond =
        5.0
    private static let minimumStepDuration =
        0.5

    let entries: [Entry]
    let totalDurationSeconds: Double

    init(
        steps: [EPUBReadAloudStep],
        items: [EPUBMediaOverlayItem],
        speechRate: Double
    ) {
        let normalizedRate = min(
            max(speechRate, 0.5),
            2
        )
        var result: [Entry] = []
        result.reserveCapacity(steps.count)
        var elapsed = 0.0
        for (stepIndex, step)
            in steps.enumerated() {
            let textLength =
                (step.text as NSString).length
            let estimatedSpeechDuration = max(
                Double(max(textLength, 1))
                    / (
                        Self
                            .estimatedCharactersPerSecond
                        * normalizedRate
                    ),
                Self.minimumStepDuration
            )
            let item = step.audioItemIndex.flatMap {
                items.indices.contains($0)
                    ? items[$0]
                    : nil
            }
            let audioDuration: Double?
            if let item,
               let end =
                    item.clipEndSeconds,
               end > item.clipBeginSeconds {
                audioDuration =
                    end - item.clipBeginSeconds
            } else {
                audioDuration = nil
            }
            let duration =
                audioDuration
                ?? estimatedSpeechDuration
            result.append(
                Entry(
                    stepIndex: stepIndex,
                    startSeconds: elapsed,
                    durationSeconds:
                        duration,
                    audioClipBeginSeconds:
                        item?.clipBeginSeconds,
                    audioSeekDurationSeconds:
                        audioDuration,
                    textUTF16Length:
                        textLength
                )
            )
            elapsed += duration
        }
        entries = result
        totalDurationSeconds = elapsed
    }

    func target(
        at requestedSeconds: Double
    ) -> Target? {
        guard let last = entries.last,
              totalDurationSeconds > 0 else {
            return nil
        }
        let seconds = min(
            max(requestedSeconds, 0),
            totalDurationSeconds
        )
        let entry =
            entries.first {
                seconds < $0.endSeconds
            }
            ?? last
        let progress = min(
            max(
                (
                    seconds
                    - entry.startSeconds
                )
                    / max(
                        entry.durationSeconds,
                        Self.minimumStepDuration
                    ),
                0
            ),
            1
        )
        let audioTime =
            entry.audioClipBeginSeconds.map {
                begin in
                begin
                    + (
                        entry
                            .audioSeekDurationSeconds
                        ?? 0
                    )
                    * progress
            }
        let textOffset: Int
        if entry.textUTF16Length > 0 {
            textOffset = min(
                Int(
                    progress
                        * Double(
                            entry.textUTF16Length
                        )
                ),
                entry.textUTF16Length - 1
            )
        } else {
            textOffset = 0
        }
        return Target(
            stepIndex: entry.stepIndex,
            timelineSeconds: seconds,
            progressWithinStep:
                progress,
            audioTimeSeconds: audioTime,
            textUTF16Offset: textOffset
        )
    }

    func position(
        stepIndex: Int,
        audioTimeSeconds: Double?,
        textUTF16Offset: Int?
    ) -> Double {
        guard let entry = entries.first(
            where: {
                $0.stepIndex == stepIndex
            }
        ) else {
            return 0
        }
        let progress: Double
        if let begin =
                entry.audioClipBeginSeconds,
           let audioTimeSeconds {
            let duration =
                entry.audioSeekDurationSeconds
                ?? entry.durationSeconds
            progress = (
                audioTimeSeconds - begin
            ) / max(
                duration,
                Self.minimumStepDuration
            )
        } else if entry.textUTF16Length > 0,
                  let textUTF16Offset {
            progress =
                Double(textUTF16Offset)
                / Double(
                    entry.textUTF16Length
                )
        } else {
            progress = 0
        }
        return min(
            max(
                entry.startSeconds
                    + entry.durationSeconds
                        * min(max(progress, 0), 1),
                0
            ),
            totalDurationSeconds
        )
    }
}
