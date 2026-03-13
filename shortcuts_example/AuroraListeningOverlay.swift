//
//  AuroraListeningOverlay.swift
//  shortcuts_example
//
//  Created by me on 3/10/26.
//

import SwiftUI

struct AuroraListeningOverlay: View {

    let amplitude: Float

    private var normalizedAmplitude: CGFloat {
        min(max(CGFloat(amplitude) * 35.0, 0), 1.2)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in

            let t = timeline.date.timeIntervalSinceReferenceDate
            let energy = normalizedAmplitude
            let baseOpacity = 0.18 + energy * 0.22
            let blurRadius = 90 + energy * 50
            let scale = 1.0 + energy * 0.18

            ZStack {

                Color.black.opacity(0.12)
                    .ignoresSafeArea()

                auroraBlob(
                    colors: [
                        Color.red.opacity(0.95),
                        Color.orange.opacity(0.9),
                        Color.pink.opacity(0.75)
                    ],
                    size: CGSize(width: 700, height: 700),
                    offset: CGSize(
                        width: sin(t * 0.55) * 180,
                        height: cos(t * 0.42) * 160
                    ),
                    rotation: .degrees(t * 18),
                    blur: blurRadius,
                    opacity: baseOpacity + 0.08,
                    scale: scale + 0.06
                )

                auroraBlob(
                    colors: [
                        Color.yellow.opacity(0.95),
                        Color.green.opacity(0.85),
                        Color.mint.opacity(0.75)
                    ],
                    size: CGSize(width: 760, height: 760),
                    offset: CGSize(
                        width: cos(t * 0.47) * -210,
                        height: sin(t * 0.63) * 180
                    ),
                    rotation: .degrees(-t * 14),
                    blur: blurRadius + 10,
                    opacity: baseOpacity,
                    scale: scale
                )

                auroraBlob(
                    colors: [
                        Color.cyan.opacity(0.95),
                        Color.blue.opacity(0.85),
                        Color.purple.opacity(0.8)
                    ],
                    size: CGSize(width: 720, height: 720),
                    offset: CGSize(
                        width: sin(t * 0.72) * 220,
                        height: cos(t * 0.58) * -170
                    ),
                    rotation: .degrees(t * 22),
                    blur: blurRadius + 20,
                    opacity: baseOpacity + 0.02,
                    scale: scale + 0.04
                )

                auroraBlob(
                    colors: [
                        Color.purple.opacity(0.8),
                        Color.indigo.opacity(0.75),
                        Color.blue.opacity(0.65)
                    ],
                    size: CGSize(width: 680, height: 680),
                    offset: CGSize(
                        width: cos(t * 0.31) * 120,
                        height: sin(t * 0.36) * 210
                    ),
                    rotation: .degrees(-t * 12),
                    blur: blurRadius + 30,
                    opacity: baseOpacity * 0.85,
                    scale: scale + 0.02
                )

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                .white.opacity(0.04 + energy * 0.04),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.screen)
                    .ignoresSafeArea()

                VStack(spacing: 22) {

                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.08 + energy * 0.06))
                            .frame(width: 146, height: 146)
                            .blur(radius: 6)

                        Circle()
                            .stroke(.white.opacity(0.20 + energy * 0.18), lineWidth: 1.2)
                            .frame(width: 132 + energy * 26, height: 132 + energy * 26)

                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 118, height: 118)
                            .overlay(
                                Circle()
                                    .stroke(.white.opacity(0.18), lineWidth: 1)
                            )

                        Image(systemName: "mic.fill")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(.white)
                            .scaleEffect(1 + energy * 0.08)
                    }

                    VStack(spacing: 8) {
                        Text("듣는중")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)

                        Text("말하는 동안 음성을 인식하고 있어요")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.76))
                    }
                }
                .padding(.bottom, 36)
            }
            .compositingGroup()
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.25), value: amplitude)
        }
    }

    private func auroraBlob(
        colors: [Color],
        size: CGSize,
        offset: CGSize,
        rotation: Angle,
        blur: CGFloat,
        opacity: CGFloat,
        scale: CGFloat
    ) -> some View {
        Ellipse()
            .fill(
                LinearGradient(
                    colors: colors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size.width, height: size.height)
            .scaleEffect(scale)
            .rotationEffect(rotation)
            .offset(offset)
            .blur(radius: blur)
            .opacity(opacity)
            .blendMode(.plusLighter)
    }
}
