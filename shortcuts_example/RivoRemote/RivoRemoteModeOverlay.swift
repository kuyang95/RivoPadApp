import SwiftUI

/// Android `KeyMode` 가운데 iPadOS에서 쓰는 리모컨 모드. 모드 이름 표시와 키 안내 키패드의 출처다.
/// (JUMP/SCROLL은 다른 앱 화면 확대 이동이라 iPadOS에서는 없다.)
nonisolated enum RivoRemoteKeyMode:
    String,
    Equatable,
    Sendable
{
    case command
    case display
    case textView
    case menu
    case daisy

    /// Android `RemoteModeOverlay.modeTitle`: 영문 대문자 모드 이름.
    var title: String {
        switch self {
        case .command:
            return "COMMAND"
        case .display:
            return "DISPLAY"
        case .textView:
            return "TEXTVIEW"
        case .menu:
            return "MENU"
        case .daisy:
            return "DAISY"
        }
    }

    /// Android `MODE_NAME_VISIBLE_MS` = 1,150ms.
    static let modeNameVisibleNanoseconds: UInt64 =
        1_150_000_000

    /// Android `RemoteModeOverlay.guideForMode`: 3×4 키패드 순서(1…9, *, 0, #). 빈 문자열은 미사용.
    var keyGuide: [(key: String, description: String)] {
        switch self {
        case .command:
            return [
                ("1", ""),
                ("2", AppLocalization.string("번역")),
                ("3", "OCR"),
                ("4", AppLocalization.string("카메라")),
                ("5", AppLocalization.string("전/후면")),
                ("6", AppLocalization.string("조명")),
                ("7", AppLocalization.string("캡처 저장")),
                ("8", ""),
                ("9", AppLocalization.string("이미지 설명")),
                ("*", AppLocalization.string("줌 축소")),
                ("0", AppLocalization.string("줌 초기화")),
                ("#", AppLocalization.string("줌 확대")),
            ]
        case .display:
            return [
                ("1", AppLocalization.string("반시계 회전")),
                ("2", AppLocalization.string("자동회전")),
                ("3", AppLocalization.string("시계 회전")),
                ("4", AppLocalization.string("이전 색상")),
                ("5", AppLocalization.string("원본 색상")),
                ("6", AppLocalization.string("다음 색상")),
                ("7", AppLocalization.string("임계값 -")),
                ("8", AppLocalization.string("임계값 기본")),
                ("9", AppLocalization.string("임계값 +")),
                ("*", AppLocalization.string("밝기 낮춤")),
                ("0", AppLocalization.string("자동밝기")),
                ("#", AppLocalization.string("밝기 높임")),
            ]
        case .textView:
            return [
                ("1", AppLocalization.string("문서 처음")),
                ("2", AppLocalization.string("이전 줄")),
                ("3", AppLocalization.string("페이지 위")),
                ("4", AppLocalization.string("글자 작게")),
                ("5", AppLocalization.string("글자 기본")),
                ("6", AppLocalization.string("글자 크게")),
                ("7", AppLocalization.string("문서 끝")),
                ("8", AppLocalization.string("다음 줄")),
                ("9", AppLocalization.string("페이지 아래")),
                ("*", AppLocalization.string("줄간격 줄임")),
                ("0", AppLocalization.string("줄간격 기본")),
                ("#", AppLocalization.string("줄간격 늘림")),
            ]
        case .menu:
            return [
                ("1", AppLocalization.string("처음 메뉴")),
                ("2", AppLocalization.string("값 올림")),
                ("3", ""),
                ("4", AppLocalization.string("이전 메뉴")),
                ("5", AppLocalization.string("선택/기본")),
                ("6", AppLocalization.string("다음 메뉴")),
                ("7", AppLocalization.string("마지막 메뉴")),
                ("8", AppLocalization.string("값 내림")),
                ("9", ""),
                ("*", AppLocalization.string("뒤로")),
                ("0", AppLocalization.string("홈")),
                ("#", ""),
            ]
        case .daisy:
            return [
                ("1", ""),
                ("2", AppLocalization.string("단위 이전")),
                ("3", ""),
                ("4", AppLocalization.string("이전")),
                ("5", AppLocalization.string("재생/일시정지")),
                ("6", AppLocalization.string("다음")),
                ("7", ""),
                ("8", AppLocalization.string("단위 다음")),
                ("9", ""),
                ("*", ""),
                ("0", ""),
                ("#", ""),
            ]
        }
    }

    /// Android `RemoteModeOverlay.sideGuideForMode`: L1/R2/R3 옆 키 안내.
    var sideGuide: [(key: String, description: String)] {
        switch self {
        case .menu:
            return [
                ("L1", AppLocalization.string("메뉴 열기/닫기")),
                ("R3", AppLocalization.string("그만듣기")),
            ]
        case .command, .textView:
            return [
                ("R3", AppLocalization.string("그만듣기")),
            ]
        case .display:
            return [
                ("R2", AppLocalization.string("시스템 반전")),
            ]
        case .daisy:
            return []
        }
    }

    var accessibilitySummary: String {
        let used = keyGuide
            .filter { !$0.description.isEmpty }
            .map { "\($0.key) \($0.description)" }
        let side = sideGuide
            .map { "\($0.key) \($0.description)" }
        return AppLocalization.format(
            "%@ 모드 키 안내. %@",
            title,
            (used + side).joined(separator: ", ")
        )
    }
}

/// Android `RemoteModeOverlay.showModeName`: 화면 가운데 136pt 검은 띠 + 76pt 흰 글자(테두리 4). 1.15초 뒤 사라진다.
struct RivoRemoteModeNameFlash: View {
    let mode: RivoRemoteKeyMode
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @State private var isShown = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.65))
                .frame(height: 136)
            RivoRemoteContrastText(
                text: mode.title,
                size: 76,
                strokeWidth: 4
            )
            .frame(height: 210)
            .scaleEffect(
                isShown || reduceMotion ? 1 : 0.9
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(isShown ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            AppLocalization.format(
                "%@ 모드",
                mode.title
            )
        )
        .onAppear {
            withAnimation(
                reduceMotion
                    ? .linear(duration: 0.12)
                    : .spring(
                        response: 0.24,
                        dampingFraction: 0.72
                    )
            ) {
                isShown = true
            }
        }
    }
}

/// Android `RemoteModeOverlay.showKeyGuide`: 제목 + 3×4 유리 키캡 + 옆 키(L1/R2/R3) 줄.
struct RivoRemoteKeyGuideView: View {
    let mode: RivoRemoteKeyMode
    var onDismiss: (() -> Void)? = nil

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 12),
        count: 3
    )

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RivoRemoteContrastText(
                    text: mode.title,
                    size: 54,
                    strokeWidth: 4
                )
                .frame(maxWidth: .infinity)
                if let onDismiss {
                    HStack {
                        Spacer()
                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                .font(
                                    .system(
                                        size: 22,
                                        weight: .bold
                                    )
                                )
                                .foregroundStyle(
                                    VisionCraftUI.fixedColor(0xF2F2F2)
                                )
                                .frame(width: 52, height: 52)
                                .background(
                                    Color.white.opacity(0.16),
                                    in: Circle()
                                )
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("키 안내 닫기")
                    }
                }
            }
            .frame(height: 72)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(
                    Array(mode.keyGuide.enumerated()),
                    id: \.offset
                ) { _, item in
                    keyCell(
                        key: item.key,
                        description: item.description
                    )
                }
            }

            if !mode.sideGuide.isEmpty {
                HStack(spacing: 12) {
                    ForEach(
                        Array(mode.sideGuide.enumerated()),
                        id: \.offset
                    ) { _, item in
                        sideKeyCell(
                            key: item.key,
                            description: item.description
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .frame(maxWidth: 720)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mode.accessibilitySummary)
    }

    private func keyCell(
        key: String,
        description: String
    ) -> some View {
        let isUsed = !description.isEmpty
        return VStack(spacing: 6) {
            glassKeyCap(
                key: key,
                isUsed: isUsed,
                size: 48
            )
            .frame(maxWidth: .infinity)
            .frame(height: 74)
            Text(
                isUsed
                    ? description
                    : AppLocalization.string("미사용")
            )
            .visionCraftAndroidText(
                18,
                weight: .semibold,
                relativeTo: .body
            )
            .foregroundStyle(
                isUsed
                    ? VisionCraftUI.fixedColor(0xDCDCDC)
                    : VisionCraftUI.fixedColor(0x969696)
                        .opacity(0.62)
            )
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.75)
        }
        .padding(6)
    }

    private func sideKeyCell(
        key: String,
        description: String
    ) -> some View {
        HStack(spacing: 10) {
            glassKeyCap(key: key, isUsed: true, size: 34)
                .frame(width: 74, height: 56)
            Text(description)
                .visionCraftAndroidText(
                    18,
                    weight: .semibold,
                    relativeTo: .body
                )
                .foregroundStyle(
                    VisionCraftUI.fixedColor(0xDCDCDC)
                )
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(6)
        .frame(maxWidth: .infinity)
    }

    private func glassKeyCap(
        key: String,
        isUsed: Bool,
        size: CGFloat
    ) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: 22,
            style: .continuous
        )
        return ZStack {
            shape.fill(
                LinearGradient(
                    colors: isUsed
                        ? [
                            Color.white.opacity(0.46),
                            Color.white.opacity(0.23),
                            Color.white.opacity(0.13),
                        ]
                        : [
                            Color.white.opacity(0.14),
                            Color.white.opacity(0.08),
                            Color.white.opacity(0.04),
                        ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            shape.strokeBorder(
                Color.white.opacity(isUsed ? 0.59 : 0.21),
                lineWidth: 1
            )
            RivoRemoteContrastText(
                text: key,
                size: size,
                strokeWidth: 3,
                fill: isUsed
                    ? VisionCraftUI.fixedColor(0xE8E8E8)
                    : VisionCraftUI.fixedColor(0x969696)
            )
        }
        .opacity(isUsed ? 1 : 0.46)
        .shadow(
            color: .black.opacity(isUsed ? 0.45 : 0.1),
            radius: isUsed ? 14 : 2,
            y: isUsed ? 6 : 1
        )
    }
}

/// Android `ContrastTextView`: 어두운 테두리 + 밝은 채움 굵은 글자(그림자 10).
struct RivoRemoteContrastText: View {
    let text: String
    let size: CGFloat
    var strokeWidth: CGFloat = 3
    var fill: Color = VisionCraftUI.fixedColor(0xF2F2F2)

    var body: some View {
        ZStack {
            ForEach(0 ..< 8, id: \.self) { index in
                let angle = Double(index) * .pi / 4
                Text(text)
                    .font(.system(size: size, weight: .heavy))
                    .foregroundStyle(
                        Color.black.opacity(0.9)
                    )
                    .offset(
                        x: cos(angle) * strokeWidth * 0.6,
                        y: sin(angle) * strokeWidth * 0.6
                    )
            }
            Text(text)
                .font(.system(size: size, weight: .heavy))
                .foregroundStyle(fill)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .shadow(color: .black.opacity(0.67), radius: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}
