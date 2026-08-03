import SwiftUI
import UIKit

struct TranslationView: View {
    @StateObject private var viewModel:
        TranslationViewModel
    @State private var
        didAutomaticallyStart = false
    @State private var
        shouldSpeakAutomaticResult = false

    private let tts = TTSManager.shared
    private let automaticallyStarts: Bool

    init(
        initialText: String? = nil,
        automaticallyStarts: Bool = false
    ) {
        self.automaticallyStarts =
            automaticallyStarts
        _viewModel = StateObject(
            wrappedValue:
                TranslationViewModel(
                    initialText:
                        initialText
                )
        )
    }

    var body: some View {
        VStack(spacing: 16) {
            targetPicker

            HStack(spacing: 12) {
                Label(
                    "원문",
                    systemImage:
                        "text.alignleft"
                )
                .font(.headline)

                Spacer()

                Button(
                    "붙여넣기",
                    systemImage:
                        "doc.on.clipboard"
                ) {
                    paste()
                }
                .disabled(
                    viewModel.isBusy
                )

                Button(
                    "지우기",
                    systemImage: "xmark"
                ) {
                    viewModel.clear()
                }
                .disabled(
                    viewModel.isBusy
                        || viewModel
                        .sourceText.isEmpty
                )
            }

            TextEditor(
                text:
                    $viewModel.sourceText
            )
            .font(.body)
            .padding(10)
            .scrollContentBackground(
                .hidden
            )
            .background(VisionCraftUI.surface)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
                .stroke(
                    VisionCraftUI.outline.opacity(0.85)
                )
            }
            .frame(
                minHeight: 170,
                maxHeight: 280
            )
            .disabled(
                viewModel.isBusy
            )
            .accessibilityLabel(
                "번역할 원문"
            )

            HStack(spacing: 12) {
                if viewModel.isTranslating {
                    Button(
                        "중지",
                        systemImage:
                            "stop.fill"
                    ) {
                        viewModel.cancel()
                    }
                    .buttonStyle(
                        .borderedProminent
                    )
                    .buttonBorderShape(.roundedRectangle(radius: 14))
                    .tint(.red)
                } else {
                    Button(
                        "번역",
                        systemImage:
                            "character.book.closed"
                    ) {
                        tts.stop()
                        SoundEffectManager
                            .shared
                            .play(
                                .startingLLM
                            )
                        viewModel
                            .startTranslation()
                    }
                    .buttonStyle(
                        .borderedProminent
                    )
                    .buttonBorderShape(.roundedRectangle(radius: 14))
                    .tint(VisionCraftUI.primary)
                    .disabled(
                        !viewModel
                        .canTranslate
                    )
                }

                if viewModel.isBusy {
                    ProgressView()
                        .accessibilityLabel(
                            "번역 진행 중"
                        )
                }

                Text(viewModel.status)
                    .font(.subheadline)
                    .foregroundStyle(
                        .secondary
                    )

                Spacer()
            }
            .controlSize(.large)

            resultSection
        }
        .padding(20)
        .frame(maxWidth: 820)
        .frame(maxWidth: .infinity)
        .visionCraftNavigationScreen()
        .navigationTitle("로컬 번역")
        .navigationBarTitleDisplayMode(
            .inline
        )
        .safeAreaInset(edge: .bottom) {
            if let error =
                    viewModel
                    .errorDescription {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )
                    .padding()
                    .background(.bar)
                    .accessibilityLabel(
                        "오류: \(error)"
                    )
            }
        }
        .task {
            guard automaticallyStarts,
                  !didAutomaticallyStart,
                  viewModel.canTranslate else {
                return
            }
            didAutomaticallyStart = true
            shouldSpeakAutomaticResult =
                true
            tts.stop()
            SoundEffectManager.shared.play(
                .startingLLM
            )
            viewModel.startTranslation()
        }
        .onChange(
            of: viewModel.isTranslating
        ) {
            wasTranslating,
            isTranslating in
            guard wasTranslating,
                  !isTranslating,
                  shouldSpeakAutomaticResult
            else {
                return
            }
            shouldSpeakAutomaticResult =
                false
            guard viewModel.canUseResult
            else {
                return
            }
            tts.speak(viewModel.result)
        }
        .onDisappear {
            viewModel.cancel()
            tts.stop()
        }
    }

    private var targetPicker:
        some View
    {
        HStack(spacing: 16) {
            Text("번역할 언어")
                .font(.headline)
            Picker(
                "번역할 언어",
                selection:
                    $viewModel
                    .targetLanguage
            ) {
                ForEach(
                    TranslationTargetLanguage
                        .allCases
                ) { language in
                    Text(
                        LocalizedStringKey(
                            language
                                .localizationKey
                        )
                    )
                    .tag(language)
                }
            }
            .pickerStyle(.segmented)
            .disabled(viewModel.isBusy)
        }
        .padding(14)
        .visionCraftSurfaceCard(cornerRadius: 16)
    }

    private var resultSection:
        some View
    {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Label(
                    "번역 결과",
                    systemImage:
                        "character.book.closed.fill"
                )
                .font(.headline)

                Spacer()

                Button(
                    "복사",
                    systemImage:
                        "doc.on.doc"
                ) {
                    UIPasteboard
                        .general.string =
                        viewModel.result
                    UIAccessibility.post(
                        notification:
                            .announcement,
                        argument:
                            AppLocalization
                            .string(
                                "번역 결과를 복사했습니다."
                            )
                    )
                }
                .disabled(
                    !viewModel.canUseResult
                )

                Button(
                    "읽기",
                    systemImage:
                        "speaker.wave.2"
                ) {
                    tts.stop()
                    tts.speak(
                        viewModel.result
                    )
                }
                .disabled(
                    !viewModel.canUseResult
                )
            }

            ScrollView {
                Text(
                    viewModel.result.isEmpty
                        ? AppLocalization
                        .string(
                            "번역 결과가 여기에 표시됩니다."
                        )
                        : viewModel.result
                )
                .foregroundStyle(
                    viewModel.result.isEmpty
                        ? .secondary
                        : .primary
                )
                .textSelection(.enabled)
                .frame(
                    maxWidth: .infinity,
                    alignment: .topLeading
                )
                .padding(14)
            }
            .visionCraftSurfaceCard(cornerRadius: 14)
            .accessibilityLabel(
                viewModel.result.isEmpty
                    ? AppLocalization.string(
                        "번역 결과 없음"
                    )
                    : AppLocalization.format(
                        "번역 결과: %@",
                        viewModel.result
                    )
            )
        }
        .frame(
            maxHeight: .infinity
        )
    }

    private func paste() {
        guard let text =
                UIPasteboard
                .general.string,
              !text.isEmpty else {
            return
        }
        viewModel.replaceSource(
            with: text
        )
    }
}
