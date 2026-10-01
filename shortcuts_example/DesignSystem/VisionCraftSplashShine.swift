import SwiftUI

/// Android `SplashActivity` + `SplashShineView` + `a_splash.xml`.
///
/// 정적 런치 화면과 같은 구성(LaunchBackground 위에 LaunchLogo 192pt 가운데)을 SwiftUI로 잠시 더 보여 주고,
/// 로고 위로 빛 띠를 한 번(-20°, 140ms 뒤 480ms, 폭 38%, 흰색 0x8C) 지나가게 한 뒤 사라진다.
/// 최소 700ms 노출. 동작 줄이기가 켜져 있으면 빛 띠는 생략한다. 라우팅은 막지 않는다(오버레이만 그림).
struct VisionCraftSplashShine: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPresented = !Self.isRunningTests
    @State private var progress: CGFloat = 0

    private static let logoSize: CGFloat = 192
    private static let minimumExposure: Duration = .milliseconds(700)
    private static let shineStartDelay: Double = 0.14
    private static let shineDuration: Double = 0.48
    private static let shineAngleDegrees: Double = -20
    private static let bandWidthRatio: CGFloat = 0.38
    private static let fadeDuration: Double = 0.25
    private static let shineColor = Color.white.opacity(Double(0x8C) / 255)

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    var body: some View {
        if isPresented {
            ZStack {
                Color("LaunchBackground")
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: Self.logoSize, height: Self.logoSize)
                    .overlay {
                        if !reduceMotion {
                            shineBand
                        }
                    }
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
            .transition(.opacity)
            .task {
                if !reduceMotion {
                    withAnimation(
                        .easeInOut(duration: Self.shineDuration)
                            .delay(Self.shineStartDelay)
                    ) {
                        progress = 1
                    }
                }
                try? await Task.sleep(for: Self.minimumExposure)
                withAnimation(.easeOut(duration: Self.fadeDuration)) {
                    isPresented = false
                }
            }
        }
    }

    /// Android `SplashShineView.onDraw`: 로고 크기의 층 안에서 띠를 왼쪽 밖에서 오른쪽 밖으로 옮기고,
    /// 층 전체를 로고 가운데 기준 -20° 기울인다. 띠는 로고 그림의 알파로 잘라 모서리 밖으로 새지 않게 한다.
    private var shineBand: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let bandWidth = width * Self.bandWidthRatio
            let tiltMargin = height * abs(sin(Self.shineAngleDegrees * .pi / 180))
            let start = -(bandWidth + tiltMargin)
            let end = width + tiltMargin
            let x = start + (end - start) * progress
            Rectangle()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: Self.shineColor, location: 0.5),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: bandWidth, height: height * 2)
                .offset(x: x, y: -height / 2)
                .frame(width: width, height: height, alignment: .topLeading)
                .rotationEffect(.degrees(Self.shineAngleDegrees))
        }
        .mask {
            Image("LaunchLogo")
                .resizable()
                .scaledToFit()
        }
        .allowsHitTesting(false)
    }
}
