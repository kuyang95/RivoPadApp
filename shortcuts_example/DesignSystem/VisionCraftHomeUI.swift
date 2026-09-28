import SwiftUI
import UIKit

/// Shared soft UI palette from Android VisionCraft.
enum VisionCraftHomeUI {
    static let background = VisionCraftUI.background
    static let surface = VisionCraftUI.surface
    static let surfaceVariant = VisionCraftUI.surfaceVariant
    static let highlight = color(0xFFFFFF, 0x2B2B2B)
    static let shadow = color(0xCCD1D9, 0x000000)
    static let text = VisionCraftUI.primaryText
    static let secondaryText = VisionCraftUI.secondaryText
    static let icon = VisionCraftUI.icon
    static let outline = VisionCraftUI.outline
    static let accent = VisionCraftUI.accent
    static let connected = VisionCraftUI.success
    static let connecting = VisionCraftUI.warning
    static let guideSurface = color(0xFFF9EF, 0x211D18)
    static let guideAccent = color(0x885024, 0xF3C9A4)
    static let guideSecondaryText = color(0x6F604F, 0xD4C4AF)
    static let guideArrow = color(0xFFE1C9, 0x483326)
    // Android VcHomeTileArt: neutral tint blended with the home surface.
    static let tileArtBackground = color(0xE6E8EA, 0xDBE2EC)
    static let onPrimary = color(0xFFFFFF, 0x171717)
    static let switchOn = color(0x34C759, 0x34C759)
    static let switchOff = color(0xB8BDC7, 0xB8BDC7)
    static let logoAccents: [Color] = [
        color(0xB5403C, 0xF2A09B),
        color(0xB2611F, 0xEFB07F),
        color(0x917511, 0xE6C45C),
        color(0x4A7A2C, 0xA6D68A),
        color(0x356AA8, 0x9EC5FF),
        color(0x7655B4, 0xC6B1F5),
    ]

    enum SectionTone {
        case ai, camera, reading, link, settings, updates

        var color: Color {
            switch self {
            case .ai: VisionCraftHomeUI.color(0x7655B4, 0xC6B1F5)
            case .camera: VisionCraftHomeUI.color(0x356AA8, 0x9EC5FF)
            case .reading: VisionCraftHomeUI.color(0x28765A, 0x99D8BA)
            case .link: VisionCraftHomeUI.color(0x2A7A86, 0x8FD6E0)
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

struct VisionCraftHomeCategory: Identifiable {
    let id: String
    let title: String
    let tone: VisionCraftHomeUI.SectionTone
    let artName: String
    let items: [VisionCraftActionItem]
}

/// Android VcHomeCategoryGrid: two columns, 16pt gap, 4:5 tile ratio.
struct VisionCraftHomeCategoryGrid: View {
    let categories: [VisionCraftHomeCategory]
    let columns: Int
    let onOpen: (VisionCraftHomeCategory) -> Void

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: columns),
            spacing: 16
        ) {
            ForEach(categories) { category in
                Button {
                    onOpen(category)
                } label: {
                    GeometryReader { geometry in
                        VStack(spacing: 10) {
                            GeometryReader { artGeometry in
                                let side = max(0, min(artGeometry.size.width - 48, artGeometry.size.height - 8))
                                ZStack {
                                    RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
                                        .fill(VisionCraftHomeUI.tileArtBackground)
                                        .frame(width: side, height: side)
                                    Image(category.artName)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: side * 0.7, height: side * 0.7)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                            Text(AppLocalization.string(category.title))
                                .font(.system(size: min(geometry.size.width * 0.17, 94), weight: .bold))
                                .minimumScaleFactor(0.65)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(VisionCraftHomeUI.text)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 18)
                        }
                        .padding(.top, 18)
                        .padding(.bottom, 16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .aspectRatio(4.0 / 5.0, contentMode: .fit)
                    .visionCraftHomeSurface(outlined: false)
                    .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(VisionCraftHomePressStyle())
                .accessibilityLabel("\(AppLocalization.string(category.title)). \(category.items.map { AppLocalization.string($0.title) }.joined(separator: ", "))")
                .accessibilityIdentifier("home.category.\(category.id)")
            }
        }
    }
}

struct VisionCraftHomeCategoryDialog: View {
    let category: VisionCraftHomeCategory
    let onDismiss: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VisionCraftDialogScrim(onTap: onDismiss)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        VisionCraftHomeSectionHeader(title: category.title, tone: category.tone)
                        VisionCraftHomeActionList(items: category.items.map { item in
                            VisionCraftActionItem(
                                id: item.id,
                                icon: item.icon,
                                title: item.title,
                                description: item.description,
                                accent: item.accent,
                                action: {
                                    onDismiss()
                                    item.action()
                                }
                            )
                        }, useLogoAccents: true)
                        Button(AppLocalization.string("닫기"), action: onDismiss)
                            .frame(maxWidth: .infinity)
                            .buttonStyle(VisionCraftAndroidButtonStyle())
                            .padding(.top, 24)
                    }
                    .padding(24)
                }
                .frame(maxWidth: 560, maxHeight: geometry.size.height - 48)
                .background(VisionCraftHomeUI.background, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(VisionCraftHomeUI.outline, lineWidth: 1.5)
                }
                .padding(.horizontal, 20)
            }
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onDismiss)
        .zIndex(100)
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
    var useLogoAccents = false

    var body: some View {
        VStack(spacing: 16) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button(action: item.action) {
                    HStack(spacing: 16) {
                        if useLogoAccents {
                            let accent = VisionCraftHomeUI.logoAccents[index % VisionCraftHomeUI.logoAccents.count]
                            VisionCraftIconTile(
                                systemImage: item.icon,
                                foreground: accent,
                                background: accent.opacity(0.14),
                                size: 52,
                                iconSize: 28
                            )
                        } else {
                            Image(systemName: item.icon)
                                .font(.system(size: 28))
                                .foregroundStyle(VisionCraftHomeUI.icon)
                                .frame(width: 28, height: 28)
                                .accessibilityHidden(true)
                        }

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
    let outlined: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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
                if outlined {
                    shape.strokeBorder(
                        VisionCraftHomeUI.outline,
                        lineWidth: contrast == .increased ? 2 : 1.5
                    )
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

/// Basic outlined button; `filled` uses the ink action for navigation.
struct VisionCraftAndroidButtonStyle: ButtonStyle {
    var filled = false
    var emphasized = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return configuration.label
            .visionCraftAndroidText(16, weight: .semibold)
            .foregroundStyle(emphasized ? VisionCraftUI.onAccent : (filled ? VisionCraftHomeUI.onPrimary : VisionCraftHomeUI.text))
            .padding(.horizontal, 16)
            .frame(minHeight: emphasized ? 64 : 52)
            .background {
                shape.fill(emphasized ? VisionCraftHomeUI.accent : (filled ? VisionCraftHomeUI.text : VisionCraftHomeUI.surface))
                    .shadow(color: VisionCraftHomeUI.shadow,
                            radius: configuration.isPressed ? 2 : 5,
                            x: configuration.isPressed ? 0.75 : 2,
                            y: configuration.isPressed ? 0.75 : 2)
                shape.strokeBorder(emphasized ? VisionCraftHomeUI.accent : VisionCraftHomeUI.outline, lineWidth: 1.5)
            }
            .contentShape(shape)
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
        fill: Color? = nil,
        outlined: Bool = true
    ) -> some View {
        modifier(VisionCraftHomeSurfaceModifier(
            cornerRadius: cornerRadius,
            fill: fill,
            outlined: outlined
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
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(VisionCraftHomeUI.surface)
                .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(VisionCraftHomeUI.outline, lineWidth: 1.5)
                }
        }
    }
}
