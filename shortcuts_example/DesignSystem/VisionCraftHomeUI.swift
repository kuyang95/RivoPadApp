import SwiftUI
import UIKit

/// Android VisionCraft soft UI 팔레트(`VcSoftHome.kt` `softHomeColors()`).
/// 앱 전체가 이 한 벌을 쓴다. 색·모양·면을 새로 정하지 말고 여기 토큰을 쓴다.
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
    /// Android `VcHomeTileArt`: 회색(Neutral)을 면에 14% 섞은 값, 다크는 회색 다크색을 흰색 쪽으로 50%.
    static let tileArtBackground = color(0xE6E8EA, 0xDBE2EC)
    /// 잉크 버튼 글자 = 배경색(라이트 흰색, 다크 검정). Android `VcHomeSoftButton(ink = true)`.
    static let onPrimary = VisionCraftUI.background
    static let switchOn = color(0x34C759, 0x34C759)
    static let switchOff = color(0xB8BDC7, 0xB8BDC7)
    /// Android `VCColors.Surface3Light` / `Surface3`: 색 견본 테두리.
    static let swatchOutline = color(0xDADADA, 0x303030)
    /// `raised` 면의 위·아래 색: 면을 밝은 면 쪽으로 70%, 그림자 쪽으로 28% 섞은 값.
    static let raisedTop = color(0xFDFDFD, 0x252525)
    static let raisedBottom = color(0xEDEFF1, 0x111111)
    static let logoAccents: [Color] = [
        color(0xB5403C, 0xF2A09B),
        color(0xB2611F, 0xEFB07F),
        color(0x917511, 0xE6C45C),
        color(0x4A7A2C, 0xA6D68A),
        color(0x356AA8, 0x9EC5FF),
        color(0x7655B4, 0xC6B1F5),
    ]

    static func logoAccent(_ index: Int) -> Color {
        logoAccents[((index % logoAccents.count) + logoAccents.count) % logoAccents.count]
    }

    /// 영역 구분 색(섹션 밑줄). Android `HomeSectionTone`.
    enum SectionTone {
        case ai, camera, reading, link, settings, updates, neutral

        var color: Color {
            switch self {
            case .ai: VisionCraftHomeUI.color(0x7655B4, 0xC6B1F5)
            case .camera: VisionCraftHomeUI.color(0x356AA8, 0x9EC5FF)
            case .reading: VisionCraftHomeUI.color(0x28765A, 0x99D8BA)
            case .link: VisionCraftHomeUI.color(0x2A7A86, 0x8FD6E0)
            case .settings: VisionCraftHomeUI.color(0x976026, 0xE7BE80)
            case .updates, .neutral: VisionCraftHomeUI.color(0x69778B, 0xB7C5D9)
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

/// Android `VcTile`(`VcHomeCategoryGrid`): 세로 2열, 가로 4열, 16pt 간격, 4:5 비율.
/// 테두리 없이 큰 그림자와 위아래 밝기 기울기로 띄운다(`raised`).
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

                            VisionCraftHomeTileTitle(
                                title: category.title,
                                tileWidth: geometry.size.width
                            )
                        }
                        .padding(.top, 18)
                        .padding(.bottom, 16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .aspectRatio(4.0 / 5.0, contentMode: .fit)
                    .visionCraftHomeSurface(outlined: false, raised: true)
                    .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(VisionCraftHomePressStyle())
                .accessibilityLabel(accessibilityLabel(for: category))
                .accessibilityIdentifier("home.category.\(category.id)")
            }
        }
    }

    /// 항목이 하나면 타일이 곧 그 기능이므로 기능 설명을, 여럿이면 안에 든 항목 이름을 읽어 준다.
    private func accessibilityLabel(for category: VisionCraftHomeCategory) -> String {
        let title = AppLocalization.string(category.title)
        if category.items.count == 1, let only = category.items.first {
            return "\(title). \(AppLocalization.string(only.description))"
        }
        let names = category.items
            .map { AppLocalization.string($0.title) }
            .joined(separator: ", ")
        return "\(title). \(names)"
    }
}

/// Android `VcHomeTileTitle`: 타일 안쪽 너비(타일 폭 − 36)의 17%를 글자 크기로 쓰고
/// 사용자 글자 크기 설정을 따른다. 줄바꿈은 낱말 사이에서만 일어나야 하므로
/// 가장 긴 낱말이 한 줄에 들어갈 때까지만 줄인다.
struct VisionCraftHomeTileTitle: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let tileWidth: CGFloat
    var widthFraction: CGFloat = 0.17

    var body: some View {
        let text = AppLocalization.string(title)
        let available = max(1, tileWidth - 36)
        let target = UIFontMetrics.default.scaledValue(for: available * widthFraction)
        let size = fittedSize(text: text, target: target, available: available)
        let _ = dynamicTypeSize
        Text(text)
            .font(.system(size: size, weight: .bold))
            .lineSpacing(size * 0.18)
            .multilineTextAlignment(.center)
            .foregroundStyle(VisionCraftHomeUI.text)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
    }

    private func fittedSize(text: String, target: CGFloat, available: CGFloat) -> CGFloat {
        let words: [String] = text.components(separatedBy: " ")
        let longestWord: String = words.max { $0.count < $1.count } ?? text
        let font = UIFont.systemFont(ofSize: target, weight: .bold)
        let wordWidth = (longestWord as NSString)
            .size(withAttributes: [.font: font]).width
        guard wordWidth > available, wordWidth > 0 else { return target }
        return target * (available / wordWidth) * 0.97
    }
}

/// Android `VcCardDialog`(`VcHomeCategoryDialog`): 카테고리 타일을 눌렀을 때 항목을 보여 주는 카드 다이얼로그.
struct VisionCraftHomeCategoryDialog: View {
    let category: VisionCraftHomeCategory
    let onDismiss: () -> Void

    var body: some View {
        VisionCraftDialogCard(
            title: category.title,
            cancelTitle: "닫기",
            tone: category.tone,
            onDismiss: onDismiss
        ) {
            ForEach(Array(category.items.enumerated()), id: \.element.id) { index, item in
                VisionCraftDialogOptionRow(
                    title: item.title,
                    subtitle: item.description,
                    systemImage: item.icon,
                    badge: item.badge,
                    accent: VisionCraftHomeUI.logoAccent(index)
                ) {
                    onDismiss()
                    item.action()
                }
                .accessibilityIdentifier("home.action.\(item.id)")
            }
        }
    }
}

/// Android `VcSectionHeader`: 22pt SemiBold + heading, 7pt 띄우고 3pt 밑줄.
/// 밑줄 색은 영역 식별용이고 버튼 배경의 두 번째 강조색이 아니다.
struct VisionCraftHomeSectionHeader: View {
    let title: String
    let tone: VisionCraftHomeUI.SectionTone
    var bottomSpacing: CGFloat = VisionCraftUI.sectionHeaderBottomSpacing

    init(
        title: String,
        tone: VisionCraftHomeUI.SectionTone,
        bottomSpacing: CGFloat = VisionCraftUI.sectionHeaderBottomSpacing
    ) {
        self.title = title
        self.tone = tone
        self.bottomSpacing = bottomSpacing
    }

    var body: some View {
        Text(AppLocalization.string(title))
            .visionCraftAndroidText(22, weight: .semibold, relativeTo: .title2)
            .foregroundStyle(VisionCraftHomeUI.text)
            // overlay는 높이를 차지하지 않으므로 공백 7 + 밑줄 3을 확보한다.
            .padding(.bottom, 7 + 3)
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(tone.color)
                    .frame(height: 3)
                    .accessibilityHidden(true)
            }
            .accessibilityAddTraits(.isHeader)
            .padding(.bottom, bottomSpacing)
    }
}

/// Android `VcActionRow` 목록(`VcHomeActionList`): 모서리 22, 최소 88pt, 안쪽 20/18, 간격 16.
/// 목록형 기본 아이콘은 회색 28pt, `useLogoAccents`면 로고 색 VcIconTile Large.
/// `badge`가 있으면 테두리가 강조색이 되고 화살표 자리에 뱃지가 들어간다.
struct VisionCraftHomeActionList: View {
    let items: [VisionCraftActionItem]
    var useLogoAccents = false

    var body: some View {
        VStack(spacing: VisionCraftUI.actionRowSpacing) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button(action: item.action) {
                    HStack(spacing: 16) {
                        if useLogoAccents {
                            VisionCraftIconTile(
                                systemImage: item.icon,
                                tint: VisionCraftHomeUI.logoAccent(index),
                                tileSize: .large
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
                        if let badge = item.badge {
                            VisionCraftBadge(text: badge)
                        } else {
                            VisionCraftChevron()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
                    .visionCraftHomeSurface(
                        outlineColor: item.badge == nil ? nil : VisionCraftHomeUI.accent
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(VisionCraftHomePressStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(for: item))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("home.action.\(item.id)")
            }
        }
    }

    /// Android: "제목. 설명"(뱃지가 있으면 "제목, 뱃지. 설명") 한 덩어리.
    private func accessibilityLabel(for item: VisionCraftActionItem) -> String {
        let title = AppLocalization.string(item.title)
        let description = AppLocalization.string(item.description)
        if let badge = item.badge {
            return "\(title), \(AppLocalization.string(badge)). \(description)"
        }
        return "\(title). \(description)"
    }
}

/// Android `VcBadge`: 강조색 채움, 모서리 10, 12/6 여백, 16pt Bold, 글자는 배경색.
struct VisionCraftBadge: View {
    let text: String

    var body: some View {
        Text(AppLocalization.string(text))
            .visionCraftAndroidText(16, weight: .bold)
            .foregroundStyle(VisionCraftUI.background)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                VisionCraftUI.accent,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
    }
}

/// Android `VcChevron`: 오른쪽 18pt / 아래 16pt, 아이콘색.
struct VisionCraftChevron: View {
    var down = false

    var body: some View {
        Image(systemName: down ? "chevron.down" : "chevron.right")
            .font(.system(size: down ? 16 : 18, weight: .medium))
            .foregroundStyle(VisionCraftHomeUI.icon)
            .accessibilityHidden(true)
    }
}

/// Android `VcNoticeCard`(`VcHomeGuideEntry`): 크림색 안내 카드 + 40pt 원형 화살표 칩.
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
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(VisionCraftHomePressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(AppLocalization.string("열기"))
        .accessibilityIdentifier("home.user-guide")
    }
}

/// Android `VcSoftSurface`(`softHomeSurface`): 면 + 1.5pt 테두리 + 양방향 그림자(흐림 5, 오프셋 2).
/// 누르면 흐림 2·오프셋 0.75, 면을 그림자 쪽으로 14% 어둡게. 물결 효과는 쓰지 않는다.
/// `raised`: 테두리 없음, 흐림 10·오프셋 5, 위→아래 밝기 기울기(2x2 타일 전용).
private struct VisionCraftHomeSurfaceModifier: ViewModifier {
    @Environment(\.visionCraftHomePressed) private var pressed
    @Environment(\.colorSchemeContrast) private var contrast
    let cornerRadius: CGFloat
    let fill: Color?
    let outlined: Bool
    let outlineColor: Color?
    let raised: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let surface = fill ?? VisionCraftHomeUI.surface
        let blur: CGFloat = pressed ? 2 : (raised ? 10 : 5)
        let offset: CGFloat = pressed ? 0.75 : (raised ? 5 : 2)
        content.background {
            ZStack {
                shape.fill(surface)
                    .shadow(color: VisionCraftHomeUI.highlight, radius: blur, x: -offset, y: -offset)
                shape.fill(surface)
                    .shadow(color: VisionCraftHomeUI.shadow, radius: blur, x: offset, y: offset)
                if raised, fill == nil {
                    shape.fill(
                        LinearGradient(
                            colors: [VisionCraftHomeUI.raisedTop, VisionCraftHomeUI.raisedBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                } else {
                    shape.fill(surface)
                }
                shape.fill(VisionCraftHomeUI.shadow.opacity(pressed ? 0.14 : 0))
                if outlined {
                    shape.strokeBorder(
                        outlineColor ?? VisionCraftHomeUI.outline,
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

/// Android `VcButton` / `VcButtonAccent` / `VcButtonInk`(`VcHomeSoftButton`).
/// 기본: 면 + 1.5pt 테두리, 모서리 14, 최소 52pt, 양방향 그림자, 누르면 면이 14% 어두워진다.
/// `emphasized`(주황): 면·테두리 강조색, 글자 배경색, 64pt — 뭔가를 실행하는 동작.
/// `filled`(남색 잉크): 면·테두리 글자색, 글자 배경색, 64pt — 확인·이동. 한 화면에 하나만.
struct VisionCraftAndroidButtonStyle: ButtonStyle {
    var filled = false
    var emphasized = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let pressed = configuration.isPressed
        let fill: Color = emphasized
            ? VisionCraftHomeUI.accent
            : (filled ? VisionCraftHomeUI.text : VisionCraftHomeUI.surface)
        let outline: Color = emphasized
            ? VisionCraftHomeUI.accent
            : (filled ? VisionCraftHomeUI.text : VisionCraftHomeUI.outline)
        let blur: CGFloat = pressed ? 2 : 5
        let offset: CGFloat = pressed ? 0.75 : 2
        return configuration.label
            .visionCraftAndroidText(16, weight: .semibold)
            .multilineTextAlignment(.center)
            .foregroundStyle((emphasized || filled) ? VisionCraftHomeUI.onPrimary : VisionCraftHomeUI.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(minHeight: (emphasized || filled) ? 64 : 52)
            .background {
                ZStack {
                    shape.fill(fill)
                        .shadow(color: VisionCraftHomeUI.highlight, radius: blur, x: -offset, y: -offset)
                    shape.fill(fill)
                        .shadow(color: VisionCraftHomeUI.shadow, radius: blur, x: offset, y: offset)
                    shape.fill(fill)
                    shape.fill(VisionCraftHomeUI.shadow.opacity(pressed ? 0.14 : 0))
                    shape.strokeBorder(outline, lineWidth: 1.5)
                }
            }
            .contentShape(shape)
    }
}

/// 앱 글꼴 설정(`AppFontCatalogStore.fontName`)을 공용 글자 스타일에 전달한다. nil = 시스템 글꼴.
struct VisionCraftAppFontNameKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var visionCraftAppFontName: String? {
        get { self[VisionCraftAppFontNameKey.self] }
        set { self[VisionCraftAppFontNameKey.self] = newValue }
    }
}

private struct VisionCraftAndroidTextModifier: ViewModifier {
    @Environment(\.visionCraftAppFontName) private var appFontName
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight, relativeTo: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: relativeTo)
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(VisionCraftHomeUI.font(size: size, weight: weight, appFontName: appFontName))
    }
}

extension VisionCraftHomeUI {
    /// 앱 글꼴 이름이 있으면 그 글꼴로, 없으면 시스템 글꼴로 크기·굵기를 맞춘 Font.
    static func font(size: CGFloat, weight: Font.Weight, appFontName: String?) -> Font {
        if let appFontName {
            return Font.custom(appFontName, size: size).weight(weight)
        }
        return .system(size: size, weight: weight)
    }
}

extension View {
    func visionCraftHomeSurface(
        cornerRadius: CGFloat = 22,
        fill: Color? = nil,
        outlined: Bool = true,
        outlineColor: Color? = nil,
        raised: Bool = false
    ) -> some View {
        modifier(VisionCraftHomeSurfaceModifier(
            cornerRadius: cornerRadius,
            fill: fill,
            outlined: outlined,
            outlineColor: outlineColor,
            raised: raised
        ))
    }

    /// Android 글자 스타일. 크기는 sp처럼 사용자 글자 크기를 따르고, 글꼴은 앱 글꼴 설정을 따른다.
    func visionCraftAndroidText(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo: Font.TextStyle = .body
    ) -> some View {
        modifier(VisionCraftAndroidTextModifier(size: size, weight: weight, relativeTo: relativeTo))
    }

    /// 다이얼로그 카드 면: 모서리 28(값 고르기는 24), 면 색, 1.5pt 테두리, 그림자.
    func visionCraftHomeDialogSurface(cornerRadius: CGFloat = 28) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(VisionCraftHomeUI.surface)
                .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(VisionCraftHomeUI.outline, lineWidth: 1.5)
                }
        }
    }
}
