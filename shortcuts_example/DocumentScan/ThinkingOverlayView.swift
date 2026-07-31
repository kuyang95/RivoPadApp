//
//  ThinkingOverlayView.swift
//  shortcuts_example
//
//  Created by meee on 3/4/26.
//

import SwiftUI

struct ThinkingOverlayView: View {

    let title: String
    let activeDotIndex: Int

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 28) {

                Text(
                    AppLocalization.string(
                        title
                    )
                )
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.white)

                HStack(spacing: 16) {
                    DotView(index: 0, activeIndex: activeDotIndex)
                    DotView(index: 1, activeIndex: activeDotIndex)
                    DotView(index: 2, activeIndex: activeDotIndex)
                }
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 36)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.black.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
        }
    }
}

private struct DotView: View {

    let index: Int
    let activeIndex: Int

    var body: some View {
        Circle()
            .fill(Color.white)
            .frame(width: 12, height: 12)
            .scaleEffect(activeIndex == index ? 1.4 : 0.7)
            .opacity(activeIndex == index ? 1 : 0.35)
            .animation(.easeInOut(duration: 0.25), value: activeIndex)
    }
}
