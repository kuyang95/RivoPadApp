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
    static let guideIcon = color(0xA67C00, 0xD4A72C)
    /// Shared warm gray artwork plate, kept distinct from pale and gray illustration shapes.
    static let tileArtBackground = color(0xB1B3AD, 0xA1A59D)
    static let tileArtIcon = Color(red: 0x28 / 255.0, green: 0x35 / 255.0, blue: 0x46 / 255.0)
    static let launcherPosterCanvas = color(0xE8E9E2, 0x151B18)
    static let launcherPosterTile = color(0xF7F7EF, 0x202A25)
    static let launcherPosterText = color(0x183129, 0xF1F6ED)
    static let launcherPosterOutline = color(0xC9D0C5, 0x54685D)
    static let launcherPosterCorner = color(0xE0E1DB, 0x3A3D38)
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
    let artName: String?
    var systemImage: String? = nil
    var description: String? = nil
    var customImage: UIImage? = nil
    var showsArtwork = true
    var posterAccentIndex: Int? = nil
    let items: [VisionCraftActionItem]
}

/// Android `VcHomeTilePage`: 세로는 첫 화면 중앙, 가로(4열)는 머리 바로 아래에 배치한다.
/// 높이가 부족하면 전폭 타일을 유지해 스크롤하고, 추가 기능 행은 아래에 이어 붙인다.
struct VisionCraftHomeTilePageLayout: Layout {
    let columns: Int
    let referenceItemCount: Int
    let itemCount: Int
    let firstPageHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let metrics = metrics(width: proposal.width ?? 0, subviews: subviews)
        return CGSize(width: metrics.width, height: metrics.pageHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let metrics = metrics(width: bounds.width, subviews: subviews)
        subviews[0].place(
            at: bounds.origin, anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: metrics.headerHeight)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY + metrics.headerHeight + metrics.topSpace),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: metrics.gridHeight)
        )
    }

    private func metrics(width: CGFloat, subviews: Subviews) -> (
        width: CGFloat, headerHeight: CGFloat, gridHeight: CGFloat, topSpace: CGFloat, pageHeight: CGFloat
    ) {
        let headerHeight = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        let gap: CGFloat = 16
        let tileWidth = max(0, (width - gap * CGFloat(columns - 1)) / CGFloat(columns))
        let tileHeight = tileWidth * 5 / 4
        let referenceRows = max(1, (referenceItemCount + columns - 1) / columns)
        let rows = (itemCount + columns - 1) / columns
        let referenceHeight = tileHeight * CGFloat(referenceRows) + gap * CGFloat(referenceRows - 1)
        // 가로 모드의 홈·하위 기능 화면은 위쪽에 붙이고 남는 높이는 아래에 둔다.
        let firstGridHeight = columns == 4
            ? referenceHeight
            : max(referenceHeight, firstPageHeight - headerHeight)
        let extraHeight = CGFloat(max(0, rows - referenceRows)) * (tileHeight + gap)
        let gridHeight = tileHeight * CGFloat(rows) + gap * CGFloat(max(0, rows - 1))
        return (width, headerHeight, gridHeight, (firstGridHeight - referenceHeight) / 2,
                headerHeight + firstGridHeight + extraHeight)
    }
}

private struct PageFillingHomeCategoryGridLayout: Layout {
    let columns: Int

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let rows = (subviews.count + columns - 1) / columns
        let rowGap = min(16, bounds.height / CGFloat(rows))
        let tileHeight = (bounds.height - rowGap * CGFloat(rows - 1)) / CGFloat(rows)
        let columnGap = min(16, bounds.width / CGFloat(columns))
        let tileWidth = (bounds.width - columnGap * CGFloat(columns - 1)) / CGFloat(columns)

        for index in subviews.indices {
            let row = index / columns
            let column = index % columns
            let point = CGPoint(x: bounds.minX + CGFloat(column) * (tileWidth + columnGap),
                                y: bounds.minY + CGFloat(row) * (tileHeight + rowGap))
            subviews[index].place(at: point, anchor: .topLeading,
                proposal: ProposedViewSize(width: tileWidth, height: tileHeight))
        }
    }
}

/// Android `VcTile`(`VcHomeCategoryGrid`): 세로 2열, 가로 4열, 16pt 간격, 4:5 비율.
/// 테두리 없이 큰 그림자와 위아래 밝기 기울기로 띄운다(`raised`).
struct VisionCraftHomeCategoryGrid: View {
    let categories: [VisionCraftHomeCategory]
    let columns: Int
    var minimumTitleSize: CGFloat = 0
    var identifierPrefix = "home.category"
    var fillsHeight = false
    var onPosterLongPress: (() -> Void)? = nil
    var readingFocus: AccessibilityFocusState<String?>.Binding? = nil
    let onOpen: (VisionCraftHomeCategory) -> Void

    var body: some View {
        if fillsHeight {
            PageFillingHomeCategoryGridLayout(columns: columns) { tiles }
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: columns),
                spacing: 16) { tiles }
        }
    }

    private var tiles: some View {
        ForEach(categories) { category in
            let tile = Button {
                onOpen(category)
            } label: {
                if fillsHeight {
                    VisionCraftLauncherPosterTile(category: category)
                } else {
                    VisionCraftHomeCategoryTileContent(title: category.title, artName: category.artName,
                        systemImage: category.systemImage, customImage: category.customImage,
                        minimumTitleSize: minimumTitleSize, showsArtwork: category.showsArtwork)
                        .aspectRatio(4.0 / 5.0, contentMode: .fit)
                        .visionCraftHomeSurface(outlined: false, raised: true)
                        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
            }
            .modifier(LauncherPosterLongPress(onTap: { onOpen(category) }, onLongPress: onPosterLongPress))
            .buttonStyle(VisionCraftHomePressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(for: category))
            .accessibilityHint(category.description.map { AppLocalization.string($0) } ?? "")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("\(identifierPrefix).\(category.id)")
            if let readingFocus {
                tile.accessibilityFocused(readingFocus, equals: category.id)
            } else {
                tile
            }
        }
    }

    /// 항목이 하나면 타일이 곧 그 기능이므로 기능 설명을, 여럿이면 안에 든 항목 이름을 읽어 준다.
    private func accessibilityLabel(for category: VisionCraftHomeCategory) -> String {
        let title = AppLocalization.string(category.title)
        if category.items.isEmpty { return title }
        if category.items.count == 1, let only = category.items.first {
            return only.description.isEmpty ? title : "\(title). \(AppLocalization.string(only.description))"
        }
        let names = category.items
            .map { AppLocalization.string($0.title) }
            .joined(separator: ", ")
        return "\(title). \(names)"
    }
}

private struct VisionCraftLauncherPosterTile: View {
    @Environment(\.visionCraftHomePressed) private var pressed
    @Environment(\.colorScheme) private var colorScheme
    let category: VisionCraftHomeCategory

    private var posterArtworkName: String? {
        switch category.id {
        case "ai": "HomePosterAIChat"
        case "camera": "HomePosterCamera"
        case "reading": "HomePosterDocuments"
        case "link": "HomePosterVisionLink"
        case "media": "HomePosterMedia"
        default: category.artName
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let iconTint = colorScheme == .dark ? VisionCraftHomeUI.launcherPosterText : VisionCraftHomeUI.tileArtIcon
        GeometryReader { geometry in
            let size = geometry.size
            let inset = min(32, max(10, size.width * 0.07))
            let titleSize = max(18, min(46, (size.width - inset * 2) * 0.14, size.height * 0.24))
            VStack(alignment: .leading, spacing: 0) {
                GeometryReader { art in
                    if category.showsArtwork {
                        let side = max(0, min(art.size.width * 0.52, art.size.height * 0.90))
                        Group {
                            if let artworkName = posterArtworkName {
                                Image(decorative: artworkName).resizable()
                            } else {
                                Image(systemName: category.systemImage ?? "square.grid.3x3").resizable()
                                    .foregroundStyle(iconTint)
                            }
                        }
                        .scaledToFit()
                        .frame(width: side, height: side)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .accessibilityHidden(true)
                    }
                }
                Text(AppLocalization.string(category.title))
                    .visionCraftAndroidText(titleSize, weight: .bold, relativeTo: .title)
                    .foregroundStyle(VisionCraftHomeUI.launcherPosterText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, inset)
            .padding(.top, size.height * 0.07)
            .padding(.bottom, size.height * 0.08)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .background {
                VisionCraftHomeUI.launcherPosterTile
                Path { path in
                    path.move(to: CGPoint(x: size.width * 0.30, y: 0))
                    path.addCurve(to: CGPoint(x: size.width, y: size.height * 0.74),
                        control1: CGPoint(x: size.width * 0.30, y: size.height * 0.41),
                        control2: CGPoint(x: size.width * 0.61, y: size.height * 0.74))
                    path.addLine(to: CGPoint(x: size.width, y: 0))
                    path.closeSubpath()
                }.fill(VisionCraftHomeUI.launcherPosterCorner)
            }
        }
        .overlay {
            shape.fill(VisionCraftHomeUI.launcherPosterText.opacity(pressed ? 0.1 : 0))
                .allowsHitTesting(false)
        }
        .clipShape(shape)
        .overlay { shape.strokeBorder(VisionCraftHomeUI.launcherPosterOutline, lineWidth: 1) }
        .modifier(VisionCraftLauncherTileDepth(pressed: pressed))
        .contentShape(shape)
    }
}

struct VisionCraftLauncherTileDepth: ViewModifier {
    var pressed = false
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let dark = colorScheme == .dark
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        content
            .overlay {
                shape.fill(LinearGradient(colors: [
                    .white.opacity(dark ? 0.055 : 0.035),
                    .clear,
                    .black.opacity(dark ? 0.04 : 0.018)
                ], startPoint: .top, endPoint: .bottom))
                .allowsHitTesting(false)
            }
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [
                    .white.opacity(dark ? 0.12 : 0.48), .clear
                ], startPoint: .top, endPoint: .bottom), lineWidth: 0.5)
                .padding(1)
                .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(dark ? 0.24 : 0.08),
                    radius: pressed ? 1 : 2, x: 0, y: pressed ? 0.5 : 1.5)
    }
}

/// Displays borderless icons in their Rivo colors and applies the shared grade to other action art.
struct VisionCraftActionArtwork: View {
    let name: String

    var body: some View {
        let appliesTone = name.hasPrefix("HomeAction") && !name.hasSuffix("NoOutline")
        Image(decorative: name)
            .resizable()
            .scaledToFit()
            .saturation(appliesTone ? 0.70 : 1)
            .colorMultiply(appliesTone ? VisionCraftUI.fixedColor(0xF8F5EC) : .white)
    }
}

struct VisionCraftArtworkPlate: View {
    let side: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
            .fill(VisionCraftHomeUI.tileArtBackground)
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}

/// Category home and Ratio share artwork, title sizing and spacing.
struct VisionCraftHomeCategoryTileContent: View {
    let title: String
    var artName: String?
    var systemImage: String?
    var customImage: UIImage? = nil
    var minimumTitleSize: CGFloat = 0
    var showsArtwork = true

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 10) {
                GeometryReader { artGeometry in
                    let side = max(0, min(artGeometry.size.width - 48, artGeometry.size.height - 8))
                    ZStack {
                        if showsArtwork {
                            VisionCraftArtworkPlate(side: side)
                            if let image = customImage {
                                Image(uiImage: image).resizable().scaledToFit()
                                    .frame(width: side * 0.7, height: side * 0.7)
                            } else if let artName = artName {
                                VisionCraftActionArtwork(name: artName)
                                    .frame(width: side * 0.7, height: side * 0.7)
                            } else if let systemImage = systemImage {
                                Image(systemName: systemImage)
                                    .font(.system(size: side * 0.5, weight: .medium))
                                    .foregroundStyle(VisionCraftHomeUI.tileArtIcon)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)

                VisionCraftHomeTileTitle(
                    title: title,
                    tileWidth: geometry.size.width,
                    minimumTextSize: minimumTitleSize
                )
            }
            .padding(.top, 18)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
    var minimumTextSize: CGFloat = 0

    var body: some View {
        let text = AppLocalization.string(title)
        let available = max(1, tileWidth - 36)
        let target = UIFontMetrics.default.scaledValue(for: available * widthFraction)
        let size = max(
            UIFontMetrics.default.scaledValue(for: minimumTextSize),
            fittedSize(text: text, target: target, available: available)
        )
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
    var appIcons: [String: UIImage] = [:]
    var showsIcons = true
    var titleSize: CGFloat = 18

    var body: some View {
        VStack(spacing: VisionCraftUI.actionRowSpacing) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button(action: item.action) {
                    HStack(spacing: 16) {
                        if showsIcons, let appIcon = appIcons[item.id] {
                            Image(uiImage: appIcon).resizable().scaledToFit()
                                .frame(width: 28, height: 28)
                                .accessibilityHidden(true)
                        } else if showsIcons && useLogoAccents {
                            VisionCraftIconTile(
                                systemImage: item.icon,
                                tint: VisionCraftHomeUI.logoAccent(index),
                                tileSize: .large
                            )
                        } else if showsIcons {
                            Image(systemName: item.icon)
                                .font(.system(size: 28))
                                .foregroundStyle(VisionCraftHomeUI.icon)
                                .frame(width: 28, height: 28)
                                .accessibilityHidden(true)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(AppLocalization.string(item.title))
                                .visionCraftAndroidText(titleSize, weight: .semibold, relativeTo: .headline)
                                .foregroundStyle(VisionCraftHomeUI.text)
                            if !item.description.isEmpty {
                                Text(AppLocalization.string(item.description))
                                    .visionCraftAndroidText(16)
                                    .foregroundStyle(VisionCraftHomeUI.secondaryText)
                            }
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
        let label = item.badge.map { "\(title), \(AppLocalization.string($0))" } ?? title
        return description.isEmpty ? label : "\(label). \(description)"
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
    let shadowScale: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let surface = fill ?? VisionCraftHomeUI.surface
        let strength = min(1, max(0, shadowScale))
        let blur: CGFloat = (pressed ? 2 : (raised ? 10 : 5)) * strength
        let offset: CGFloat = (pressed ? 0.75 : (raised ? 5 : 2)) * strength
        content.background {
            ZStack {
                shape.fill(surface)
                    .shadow(color: VisionCraftHomeUI.highlight.opacity(Double(strength)), radius: blur, x: -offset, y: -offset)
                shape.fill(surface)
                    .shadow(color: VisionCraftHomeUI.shadow.opacity(Double(strength)), radius: blur, x: offset, y: offset)
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
        raised: Bool = false,
        shadowScale: CGFloat = 1
    ) -> some View {
        modifier(VisionCraftHomeSurfaceModifier(
            cornerRadius: cornerRadius,
            fill: fill,
            outlined: outlined,
            outlineColor: outlineColor,
            raised: raised,
            shadowScale: shadowScale
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
