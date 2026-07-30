import CoreText
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit

nonisolated struct LocalDocumentAppearance:
    Codable,
    Equatable,
    Sendable
{
    var fontLevel: Int
    var lineHeightLevel: Int
    var colorIndex: Int
    var showsLineSeparators: Bool
    var usesSingleLineInLandscape: Bool

    static let defaultValue =
        LocalDocumentAppearance(
            fontLevel: 5,
            lineHeightLevel: 5,
            colorIndex: 0,
            showsLineSeparators: false,
            usesSingleLineInLandscape:
                false
        )

    init(
        fontLevel: Int,
        lineHeightLevel: Int,
        colorIndex: Int,
        showsLineSeparators: Bool,
        usesSingleLineInLandscape:
            Bool = false
    ) {
        self.fontLevel = fontLevel
        self.lineHeightLevel =
            lineHeightLevel
        self.colorIndex = colorIndex
        self.showsLineSeparators =
            showsLineSeparators
        self.usesSingleLineInLandscape =
            usesSingleLineInLandscape
    }

    private enum CodingKeys:
        String,
        CodingKey
    {
        case fontLevel
        case lineHeightLevel
        case colorIndex
        case showsLineSeparators
        case usesSingleLineInLandscape
    }

    init(from decoder: Decoder) throws {
        let container =
            try decoder.container(
                keyedBy: CodingKeys.self
            )
        self.init(
            fontLevel:
                try container.decode(
                    Int.self,
                    forKey: .fontLevel
                ),
            lineHeightLevel:
                try container.decode(
                    Int.self,
                    forKey: .lineHeightLevel
                ),
            colorIndex:
                try container.decode(
                    Int.self,
                    forKey: .colorIndex
                ),
            showsLineSeparators:
                try container.decode(
                    Bool.self,
                    forKey:
                        .showsLineSeparators
                ),
            usesSingleLineInLandscape:
                try container
                .decodeIfPresent(
                    Bool.self,
                    forKey:
                        .usesSingleLineInLandscape
                )
                ?? false
        )
    }

    func normalized(
        colorCount: Int =
            LocalDocumentColorTheme.all.count
    ) -> Self {
        LocalDocumentAppearance(
            fontLevel:
                min(max(fontLevel, 1), 10),
            lineHeightLevel:
                min(
                    max(lineHeightLevel, 1),
                    10
                ),
            colorIndex:
                min(
                    max(colorIndex, 0),
                    max(colorCount - 1, 0)
                ),
            showsLineSeparators:
                showsLineSeparators,
            usesSingleLineInLandscape:
                usesSingleLineInLandscape
        )
    }
}

@MainActor
final class LocalDocumentAppearanceStore {
    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String =
            "LocalDocumentAppearance.v1"
    ) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> LocalDocumentAppearance {
        guard let data =
                defaults.data(forKey: key),
              let decoded =
                try? JSONDecoder().decode(
                    LocalDocumentAppearance.self,
                    from: data
                ) else {
            return .defaultValue
        }
        return decoded.normalized()
    }

    func save(
        _ appearance: LocalDocumentAppearance
    ) {
        guard let data =
                try? JSONEncoder().encode(
                    appearance.normalized()
                ) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}

nonisolated enum LocalDocumentLayoutPolicy {
    static func usesSingleLine(
        preferenceEnabled: Bool,
        width: CGFloat,
        height: CGFloat
    ) -> Bool {
        preferenceEnabled
            && width > height
    }
}

nonisolated struct LocalDocumentColorTheme:
    Equatable,
    Sendable
{
    let name: String
    let backgroundHex: Int
    let foregroundHex: Int

    static let all: [Self] = [
        Self(
            name: "검정 바탕 흰색",
            backgroundHex: 0x000000,
            foregroundHex: 0xFFFFFF
        ),
        Self(
            name: "흰색 바탕 검정",
            backgroundHex: 0xFFFFFF,
            foregroundHex: 0x000000
        ),
        Self(
            name: "파랑 바탕 흰색",
            backgroundHex: 0x4472C4,
            foregroundHex: 0xFFFFFF
        ),
        Self(
            name: "짙은 회색 바탕 노랑",
            backgroundHex: 0x222222,
            foregroundHex: 0xFFFF00
        ),
        Self(
            name: "검정 바탕 초록",
            backgroundHex: 0x000000,
            foregroundHex: 0x00FF00
        ),
        Self(
            name: "흰색 바탕 빨강",
            backgroundHex: 0xFFFFFF,
            foregroundHex: 0xCC0000
        ),
        Self(
            name: "남색 바탕 분홍",
            backgroundHex: 0x000080,
            foregroundHex: 0xFFDDEE
        ),
        Self(
            name: "검정 바탕 청록",
            backgroundHex: 0x000000,
            foregroundHex: 0x00FFFF
        ),
        Self(
            name: "보라 바탕 흰색",
            backgroundHex: 0x330066,
            foregroundHex: 0xFFFFFF
        ),
        Self(
            name: "초록 바탕 연노랑",
            backgroundHex: 0x003300,
            foregroundHex: 0xFFFF99
        ),
        Self(
            name: "적갈색 바탕 노랑",
            backgroundHex: 0x990000,
            foregroundHex: 0xFFFF66
        ),
        Self(
            name: "검정 바탕 하늘색",
            backgroundHex: 0x1A1A1A,
            foregroundHex: 0x99CCFF
        ),
        Self(
            name: "짙은 파랑 바탕 크림",
            backgroundHex: 0x002B5C,
            foregroundHex: 0xFFFACD
        ),
        Self(
            name: "청록 바탕 밝은 청록",
            backgroundHex: 0x00334D,
            foregroundHex: 0xAFFFFF
        ),
        Self(
            name: "진청록 바탕 회색",
            backgroundHex: 0x005555,
            foregroundHex: 0xEEEEEE
        ),
        Self(
            name: "검정 바탕 주황",
            backgroundHex: 0x1C1C1C,
            foregroundHex: 0xFFA500
        ),
    ]
}

nonisolated struct LocalDocumentLine:
    Identifiable,
    Equatable,
    Sendable
{
    let index: Int
    let text: String

    var id: Int {
        index
    }
}

nonisolated enum LocalDocumentTextSegmenter {
    static func lines(
        in text: String
    ) -> [LocalDocumentLine] {
        text
            .replacingOccurrences(
                of: "\r\n",
                with: "\n"
            )
            .replacingOccurrences(
                of: "\r",
                with: "\n"
            )
            .split(
                separator: "\n",
                omittingEmptySubsequences: false
            )
            .enumerated()
            .map {
                LocalDocumentLine(
                    index: $0.offset,
                    text: String($0.element)
                )
            }
    }

    static func text(
        fromLine index: Int,
        in text: String
    ) -> String {
        let lines = lines(in: text)
        guard !lines.isEmpty else {
            return ""
        }
        let start = min(
            max(index, 0),
            lines.count - 1
        )
        return lines[start...]
            .map(\.text)
            .joined(separator: "\n")
    }
}

nonisolated enum LocalDocumentNavigationUnit:
    String,
    CaseIterable,
    Equatable,
    Sendable
{
    case line
    case page

    var displayName: String {
        switch self {
        case .line:
            return "줄"
        case .page:
            return "페이지"
        }
    }

    func next() -> Self {
        switch self {
        case .line:
            return .page
        case .page:
            return .line
        }
    }
}

nonisolated enum LocalDocumentTextNavigator {
    static func targetLine(
        from currentLine: Int,
        direction: Int,
        unit: LocalDocumentNavigationUnit,
        lineCount: Int,
        linesPerPage: Int
    ) -> Int? {
        guard lineCount > 0,
              direction != 0 else {
            return nil
        }
        let current = min(
            max(currentLine, 0),
            lineCount - 1
        )
        let distance: Int
        switch unit {
        case .line:
            distance = 1
        case .page:
            distance =
                max(linesPerPage, 1)
        }
        let target = min(
            max(
                current
                    + (direction < 0
                        ? -distance
                        : distance),
                0
            ),
            lineCount - 1
        )
        return target == current
            ? nil
            : target
    }
}

struct LocalDocumentExportFile: FileDocument {
    static var readableContentTypes:
        [UTType] {
        [.plainText, .pdf]
    }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(
        configuration:
            ReadConfiguration
    ) throws {
        data =
            configuration.file
            .regularFileContents ?? Data()
    }

    func fileWrapper(
        configuration:
            WriteConfiguration
    ) throws -> FileWrapper {
        FileWrapper(
            regularFileWithContents: data
        )
    }
}

@MainActor
enum LocalDocumentExportBuilder {
    static func textFile(
        text: String
    ) -> LocalDocumentExportFile {
        LocalDocumentExportFile(
            data: Data(text.utf8)
        )
    }

    static func pdfFile(
        text: String
    ) -> LocalDocumentExportFile {
        let pageBounds = CGRect(
            x: 0,
            y: 0,
            width: 595,
            height: 842
        )
        let contentBounds = pageBounds
            .insetBy(dx: 48, dy: 48)
        let renderer =
            UIGraphicsPDFRenderer(
                bounds: pageBounds
            )
        let attributes:
            [NSAttributedString.Key: Any] = [
                .font:
                    UIFont.systemFont(
                        ofSize: 16
                    ),
                .foregroundColor:
                    UIColor.black,
            ]
        let attributed =
            NSAttributedString(
                string: text,
                attributes: attributes
            )
        let framesetter =
            CTFramesetterCreateWithAttributedString(
                attributed
            )
        let data = renderer.pdfData { context in
            var location = 0
            repeat {
                context.beginPage()
                let path = CGPath(
                    rect: contentBounds,
                    transform: nil
                )
                let frame =
                    CTFramesetterCreateFrame(
                        framesetter,
                        CFRange(
                            location: location,
                            length: 0
                        ),
                        path,
                        nil
                    )
                let graphics =
                    context.cgContext
                graphics.saveGState()
                graphics.translateBy(
                    x: 0,
                    y: pageBounds.height
                )
                graphics.scaleBy(x: 1, y: -1)
                CTFrameDraw(frame, graphics)
                graphics.restoreGState()
                let visible =
                    CTFrameGetVisibleStringRange(
                        frame
                    )
                guard visible.length > 0 else {
                    break
                }
                location += visible.length
            } while location < attributed.length
        }
        return LocalDocumentExportFile(
            data: data
        )
    }
}
