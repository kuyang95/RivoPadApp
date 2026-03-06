//
//  OCRTopBarView.swift
//  shortcuts_example
//
//  Created by meee on 3/4/26.
//

import SwiftUI

struct OCRTopBarView: View {

    @ObservedObject var vm: OCRResultViewModel

    @Binding var showBoxes: Bool
    @Binding var isTTSEnabled: Bool
    @Binding var isPreviewImageEnabled: Bool

    var body: some View {

        HStack(spacing: 14) {

            aiButton

            ttsButton

            previewToggle

            highlightToggle

            copyButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.4), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

extension OCRTopBarView {

    var aiButton: some View {

        Button {

            if vm.llmService.isLoading {

                TTSManager.shared.stop()
                TTSManager.shared.speak("모델 로딩중입니다")

                return
            }

            SoundEffectManager.shared.play(.recording)

            Task {

                do {

                    let stream = try await vm.sttManager.startRecording()

                    for await question in stream {

                        SoundEffectManager.shared.play(.startingLLM)

                        await vm.runDocumentQA(
                            question: question,
                            isTTSEnabled: isTTSEnabled
                        )
                    }

                } catch {
                    print(error)
                }
            }

        } label: {

            ZStack {

                Circle()
                    .fill(Color.black.opacity(0.6))
                    .frame(width: 40, height: 40)

                if vm.llmService.isLoading {

                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)

                } else {

                    Image(systemName: vm.sttManager.isRecording ? "mic.fill" : "brain.head.profile")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
        }
    }

    var ttsButton: some View {

        Button {

            isTTSEnabled.toggle()

            if !isTTSEnabled {
                TTSManager.shared.stop()
            }

        } label: {

            Image(systemName: isTTSEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .padding(10)
                .background(.black.opacity(0.6))
                .clipShape(Circle())
        }
    }

    var previewToggle: some View {

        Button {

            isPreviewImageEnabled.toggle()

        } label: {

            Image(systemName: isPreviewImageEnabled ? "eye.fill" : "eye.slash.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .padding(10)
                .background(.black.opacity(0.6))
                .clipShape(Circle())
        }
    }

    var highlightToggle: some View {

        Button {

            showBoxes.toggle()

        } label: {

            Image(systemName: showBoxes ? "rectangle.slash" : "rectangle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .padding(10)
                .background(.black.opacity(0.6))
                .clipShape(Circle())
        }
    }

    var copyButton: some View {

        Button {

            UIPasteboard.general.string = vm.extractedText
            UIImpactFeedbackGenerator(style: .light).impactOccurred()

        } label: {

            Image(systemName: "doc.on.doc")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .padding(10)
                .background(.black.opacity(0.6))
                .clipShape(Circle())
        }
    }
}
