import SwiftUI
import UIKit

/// Home-only palette from Android's VcSoftHome. Other screens keep their own surfaces.
enum VisionCraftHomeUI {
    static let background = color(0xFFFFFF, 0x000000)
    static let surface = color(0xFAFAFA, 0x171717)
    static let highlight = color(0xFFFFFF, 0x2B2B2B)
    static let shadow = color(0xCCD1D9, 0x000000)
    static let text = color(0x283546, 0xF0F4FA)
    static let secondaryText = color(0x536176, 0xBBC6D7)
    static let icon = color(0x526580, 0xC9D5E7)
    static let outline = color(0xDDE2E9, 0x39414D)
    static let connected = color(0x247548, 0x83D4A1)
    static let connecting = color(0x8B6517, 0xE8C978)
    static let guideSurface = color(0xFFF9EF, 0x211D18)
    static let guideAccent = color(0x885024, 0xF3C9A4)
    static let guideSecondaryText = color(0x6F604F, 0xD4C4AF)
    static let guideArrow = color(0xFFE1C9, 0x483326)
    static let onPrimary = color(0xFFFFFF, 0x0F0F0F)
    static let switchOn = color(0x34C759, 0x34C759)
    static let switchOff = color(0xB8BDC7, 0xB8BDC7)

    enum SectionTone {
        case ai, camera, reading, settings, updates

        var color: Color {
            switch self {
            case .ai: VisionCraftHomeUI.color(0x7655B4, 0xC6B1F5)
            case .camera: VisionCraftHomeUI.color(0x356AA8, 0x9EC5FF)
            case .reading: VisionCraftHomeUI.color(0x28765A, 0x99D8BA)
            case .settings: VisionCraftHomeUI.color(0x976026, 0xE7BE80)
            case .updates: VisionCraftHomeUI.color(0x69778B, 0xB7C5D9)
            }
        }
    }

    private static func color(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

struct VisionCraftHomeSectionHeader: View {
    let title: String
    let tone: VisionCraftHomeUI.SectionTone

    var body: some View {
        Text(AppLocalization.string(title))
            .visionCraftAndroidText(22, weight: .semibold, relativeTo: .title2)
            .foregroundStyle(VisionCraftHomeUI.text)
            .padding(.bottom, 7)
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(tone.color)
                    .frame(height: 3)
                    .accessibilityHidden(true)
            }
            .accessibilityAddTraits(.isHeader)
            .padding(.bottom, 14)
    }
}

struct VisionCraftHomeActionList: View {
    let items: [VisionCraftActionItem]

    var body: some View {
        VStack(spacing: 16) {
            ForEach(items) { item in
                Button(action: item.action) {
                    HStack(spacing: 16) {
                        Image(systemName: item.icon)
                            .font(.system(size: 28, weight: .regular))
                            .foregroundStyle(VisionCraftHomeUI.icon)
                            .frame(width: 28, height: 28)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(AppLocalization.string(item.title))
                                .visionCraftAndroidText(18, weight: .semibold, relativeTo: .headline)
                                .foregroundStyle(VisionCraftHomeUI.text)
                            Text(AppLocalization.string(item.description))
                                .visionCraftAndroidText(16)
                                .foregroundStyle(VisionCraftHomeUI.secondaryText)
                        }
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(VisionCraftHomeUI.icon)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
                    .visionCraftHomeSurface()
                    .contentShape(RoundedRectangle(cornerRadius: 22))
                }
                .buttonStyle(VisionCraftHomePressStyle())
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("home.action.\(item.id)")
            }
        }
    }
}

struct VisionCraftHomeGuideEntry: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppLocalization.string("앱 사용법이 궁금하신가요?"))
                        .visionCraftAndroidText(18, weight: .semibold, relativeTo: .headline)
                        .foregroundStyle(VisionCraftHomeUI.text)
                    Text(AppLocalization.string("기능과 상황별 사용법을 알려드려요"))
                        .visionCraftAndroidText(16)
                        .foregroundStyle(VisionCraftHomeUI.guideSecondaryText)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(VisionCraftHomeUI.guideAccent)
                    .frame(width: 40, height: 40)
                    .background(VisionCraftHomeUI.guideArrow, in: Circle())
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .visionCraftHomeSurface(fill: VisionCraftHomeUI.guideSurface)
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(VisionCraftHomePressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(AppLocalization.string("사용 설명서 열기"))
        .accessibilityIdentifier("home.user-guide")
    }
}

/// Android VcSoftHome: opaque fill with upper-left light and lower-right shadow.
private struct VisionCraftHomeSurfaceModifier: ViewModifier {
    @Environment(\.visionCraftHomePressed) private var pressed
    @Environment(\.colorSchemeContrast) private var contrast
    let cornerRadius: CGFloat
    let fill: Color?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        let surface = fill ?? VisionCraftHomeUI.surface
        let blur: CGFloat = pressed ? 2 : 5
        let offset: CGFloat = pressed ? 0.75 : 2
        content.background {
            ZStack {
                shape.fill(surface)
                    .shadow(color: VisionCraftHomeUI.highlight, radius: blur, x: -offset, y: -offset)
                shape.fill(surface)
                    .shadow(color: VisionCraftHomeUI.shadow, radius: blur, x: offset, y: offset)
                shape.fill(surface)
                shape.fill(VisionCraftHomeUI.shadow.opacity(pressed ? 0.14 : 0))
                if contrast == .increased {
                    shape.strokeBorder(VisionCraftHomeUI.secondaryText, lineWidth: 1.5)
                }
            }
        }
    }
}

struct VisionCraftHomePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.visionCraftHomePressed, configuration.isPressed)
    }
}

private struct VisionCraftHomePressedKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var visionCraftHomePressed: Bool {
        get { self[VisionCraftHomePressedKey.self] }
        set { self[VisionCraftHomePressedKey.self] = newValue }
    }
}

struct VisionCraftAndroidButtonStyle: ButtonStyle {
    var filled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .visionCraftAndroidText(16, weight: .medium)
            .foregroundStyle(filled ? VisionCraftHomeUI.onPrimary : VisionCraftUI.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 48)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(filled ? VisionCraftUI.primary : Color.clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(configuration.isPressed ? 0.10 : 0))
                    }
            }
    }
}

private struct VisionCraftAndroidTextModifier: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight, relativeTo: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: relativeTo)
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight))
    }
}

extension View {
    func visionCraftHomeSurface(
        cornerRadius: CGFloat = 22,
        fill: Color? = nil
    ) -> some View {
        modifier(VisionCraftHomeSurfaceModifier(
            cornerRadius: cornerRadius,
            fill: fill
        ))
    }

    func visionCraftAndroidText(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo: Font.TextStyle = .body
    ) -> some View {
        modifier(VisionCraftAndroidTextModifier(size: size, weight: weight, relativeTo: relativeTo))
    }

    func visionCraftHomeDialogSurface() -> some View {
        background {
            RoundedRectangle(cornerRadius: 24)
                .fill(VisionCraftHomeUI.surface)
                .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
        }
    }
}
