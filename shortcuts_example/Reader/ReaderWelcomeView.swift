import SwiftUI

/// Draws on the shared launcher wallpaper without adding a separate page background.
struct ReaderWelcomeView: View {
    var lastBookTitle: String?
    var enabled: Bool
    var onContinue: () -> Void
    var onChoose: () -> Void

    private let text = VisionCraftUI.fixedColor(0xF4F5EF)
    private let secondary = VisionCraftUI.fixedColor(0xD4DFD8)
    private let accent = VisionCraftUI.fixedColor(0xCCE7D3)
    private let ink = VisionCraftUI.fixedColor(0x14271E)
    private let glass = LinearGradient(
        colors: [.white.opacity(0.12), .white.opacity(0.045)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let lastBookTitle {
                Text("최근 읽은 책")
                    .visionCraftAndroidText(17, weight: .medium)
                    .foregroundStyle(secondary)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 16)
                recentBook(lastBookTitle)
                    .padding(.bottom, 17)
            } else {
                Text("도서 읽기")
                    .visionCraftAndroidText(39, weight: .medium, relativeTo: .largeTitle)
                    .foregroundStyle(text)
                    .accessibilityAddTraits(.isHeader)
                Text("읽을 책을 선택하세요.")
                    .visionCraftAndroidText(17)
                    .foregroundStyle(secondary)
                    .padding(.top, 17)
                    .padding(.bottom, 39)
            }
            chooseFile
        }
        .frame(maxWidth: lastBookTitle == nil ? 520 : 560, alignment: .leading)
        .padding(.top, 58)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chooseFile: some View {
        let showFormat = lastBookTitle == nil
        let shape = RoundedRectangle(cornerRadius: showFormat ? 23 : 20, style: .continuous)
        return Button(action: onChoose) {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("파일 선택")
                        .visionCraftAndroidText(showFormat ? 22 : 18, weight: showFormat ? .semibold : .medium)
                        .foregroundStyle(text)
                    if showFormat {
                        Text(verbatim: "EPUB · DAISY ZIP")
                            .visionCraftAndroidText(14, relativeTo: .footnote)
                            .foregroundStyle(secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "plus")
                    .font(.title2)
                    .foregroundStyle(showFormat ? ink : text)
                    .frame(width: showFormat ? 49 : 35, height: showFormat ? 49 : 35)
                    .background(showFormat ? accent : .clear, in: Circle())
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, showFormat ? 25 : 22)
            .padding(.vertical, showFormat ? 24 : 17)
            .frame(maxWidth: .infinity, minHeight: showFormat ? 108 : 72, alignment: .leading)
            .background(glass, in: shape)
            .overlay(shape.strokeBorder(.white.opacity(0.24)))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .multilineTextAlignment(.leading)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.38)
    }

    private func recentBook(_ title: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: 25, style: .continuous)
        return Button(action: onContinue) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 28) {
                    bookCover(title, compact: false)
                    VStack(alignment: .leading, spacing: 24) {
                        bookTitle(title)
                        continueLabel
                    }
                    .frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 18) {
                        bookCover(title, compact: true)
                        bookTitle(title)
                    }
                    continueLabel
                }
            }
            .padding(27)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(glass, in: shape)
            .overlay(shape.strokeBorder(.white.opacity(0.24)))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .multilineTextAlignment(.leading)
        .accessibilityLabel(Text("이어서 읽기") + Text(verbatim: ", " + title))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.38)
    }

    private func bookTitle(_ title: String) -> some View {
        Text(verbatim: title)
            .visionCraftAndroidText(29, weight: .medium, relativeTo: .title)
            .foregroundStyle(text)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bookCover(_ title: String, compact: Bool) -> some View {
        Text(verbatim: title)
            .visionCraftAndroidText(18, weight: .semibold)
            .foregroundStyle(VisionCraftUI.fixedColor(0x344B3A))
            .lineLimit(4)
            .padding(compact ? 12 : 16)
            .frame(width: compact ? 84 : 112, height: compact ? 128 : 159, alignment: .topLeading)
            .background(VisionCraftUI.fixedColor(0xE4E0CA), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityHidden(true)
    }

    private var continueLabel: some View {
        HStack(spacing: 9) {
            Image(systemName: "play.fill")
                .font(.body)
                .accessibilityHidden(true)
            Text("이어서 읽기")
                .visionCraftAndroidText(16, weight: .semibold)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 21)
        .padding(.vertical, 13)
        .frame(minHeight: 48)
        .background(accent, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}
