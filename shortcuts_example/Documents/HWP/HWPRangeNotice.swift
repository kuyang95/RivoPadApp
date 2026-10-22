import RivoDocumentEngine
import SwiftUI
import UIKit

/// Why 적용 is dimmed when a value the document brought is outside what the engine accepts
/// (Android `HwpObjectTools` `rangeProblem` and the column setup's notice): each value with its range.
nonisolated enum HWPRangeProblems {
    static let imageBorder = 0.25...32.0
    static let shapeStroke = 0.1...32.0
    static let shadowOffset = -100.0...100.0
    static let percent = 0.0...100.0
    static let adjustment = -100.0...100.0
    /// `HWPColumnSettings.isValid`: a gap of 0–144 pt.
    static let columnGapPoints = 0.0...144.0

    /// "<항목>: 문서의 값 <값>이(가) 적용할 수 있는 범위(<범위>)를 벗어났습니다.", or nil inside the range.
    static func problem(_ label: String, value: Double, range: ClosedRange<Double>, unit: String) -> String? {
        guard !range.contains(value) else { return nil }
        return AppLocalization.format("%@: 문서의 값 %@이(가) 적용할 수 있는 범위(%@)를 벗어났습니다.",
            AppLocalization.string(label), short(value) + unit,
            short(range.lowerBound) + "~" + short(range.upperBound) + unit)
    }

    static var help: String { AppLocalization.string("범위 안으로 바꾸면 적용할 수 있습니다.") }

    /// Up to two decimals without trailing zeros ("0.25", "50.8", "12"), so a range's ends read as they are.
    static func short(_ value: Double) -> String {
        var text = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text == "-0" ? "0" : text
    }

    /// 그림 편집: the border's weight (when it has one), 밝기, 대비 and 투명도 (none unless the picture supports it).
    static func image(hasBorder: Bool, borderWidth: Double, brightness: Double, contrast: Double,
                      transparency: Double, supportsTransparency: Bool) -> [String] {
        [
            hasBorder ? problem("굵기", value: borderWidth, range: imageBorder, unit: " pt") : nil,
            problem("밝기", value: brightness, range: adjustment, unit: ""),
            problem("대비", value: contrast, range: adjustment, unit: ""),
            problem("투명도", value: transparency, range: supportsTransparency ? percent : 0...0, unit: "%"),
        ].compactMap { $0 }
    }

    /// 도형 편집 (not a whole group): the line's weight and, with a shadow, its offsets and 농도.
    static func shape(isGroup: Bool, strokeWidth: Double, hasShadow: Bool, shadowX: Double, shadowY: Double,
                      shadowOpacity: Double) -> [String] {
        guard !isGroup else { return [] }
        return [
            problem("굵기", value: strokeWidth, range: shapeStroke, unit: " pt"),
            hasShadow ? problem("가로 이동", value: shadowX, range: shadowOffset, unit: " pt") : nil,
            hasShadow ? problem("세로 이동", value: shadowY, range: shadowOffset, unit: " pt") : nil,
            hasShadow ? problem("농도", value: shadowOpacity * 100, range: percent, unit: "%") : nil,
        ].compactMap { $0 }
    }

    /// 다단 설정 (`HWPColumnSettings.isValid` for every section in scope): a count other than 1–4, a gap outside
    /// 0–144 pt (shown in mm), or columns under 36 pt. The help line goes with the gap's range only.
    static func columns(count: Int, gapPoints: Double,
                        layouts: [HWPDocumentPageLayout]) -> (problems: [String], showsHelp: Bool) {
        let mm = HWPPageSettings.pointsPerMM
        let gapProblem = (2...4).contains(count) && !columnGapPoints.contains(gapPoints)
        let fits = layouts.allSatisfy { layout in
            layout.widthPoints - layout.leftMarginPoints - layout.rightMarginPoints
                - gapPoints * Double(count - 1) >= Double(count) * 36
        }
        let problems = [
            (1...4).contains(count) ? nil
                : AppLocalization.format("이 구역은 %lld단입니다. 1~4단 중에서 고르면 적용할 수 있습니다.", count),
            gapProblem ? problem("단 사이", value: gapPoints / mm,
                range: columnGapPoints.lowerBound / mm...columnGapPoints.upperBound / mm, unit: " mm") : nil,
            (1...4).contains(count) && !fits
                ? AppLocalization.string("단 너비가 너무 좁습니다. 단 수나 단 사이를 줄여 주세요.") : nil,
        ].compactMap { $0 }
        return (problems, gapProblem)
    }
}

/// The problems at the top of a sheet in red footnote text (Android `HwpRangeNotice`), read out when they
/// appear or change, so VoiceOver users hear why 적용 is dimmed.
struct HWPRangeNotice: View {
    let problems: [String]
    var showsHelp = true

    private var text: String {
        (showsHelp ? problems + [HWPRangeProblems.help] : problems).joined(separator: "\n")
    }

    var body: some View {
        if !problems.isEmpty {
            Section {
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("hwp-range-notice")
            }
            .onAppear { announce(text) }
            .onChange(of: text) { _, text in announce(text) }
        }
    }

    private func announce(_ text: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            UIAccessibility.post(notification: .announcement, argument: text)
        }
    }
}
