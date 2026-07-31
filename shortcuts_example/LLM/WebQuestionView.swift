import SwiftUI
import UIKit

struct WebQuestionView: View {
    @EnvironmentObject private var appRouter:
        AppRouter
    @StateObject private var viewModel:
        WebQuestionViewModel
    @State private var didAutoLoad = false
    @State private var didRouteSharedContent =
        false

    private let autoLoad: Bool
    private let
        automaticallyStartsSharedVoiceInput:
            Bool?

    init(
        initialURL: String? = nil,
        autoLoad: Bool = false,
        automaticallyStartsSharedVoiceInput:
            Bool? = nil
    ) {
        self.autoLoad = autoLoad
        self
            .automaticallyStartsSharedVoiceInput =
            automaticallyStartsSharedVoiceInput
        _viewModel = StateObject(
            wrappedValue:
                WebQuestionViewModel(
                    initialURL:
                        initialURL
                )
        )
    }

    var body: some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: 20
            ) {
                urlSection

                if let error =
                        viewModel
                        .errorDescription {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .accessibilityLabel(
                            "오류: \(error)"
                        )
                }

                if let content =
                        viewModel.content {
                    loadedContentSection(
                        content
                    )
                    questionSection
                } else if !viewModel
                    .isLoading {
                    ContentUnavailableView(
                        "웹페이지를 불러오세요",
                        systemImage:
                            "doc.text.magnifyingglass",
                        description: Text(
                            "주소를 읽은 뒤 본문을 M4 로컬 AI에 질문할 수 있습니다."
                        )
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                    .padding(.vertical, 36)
                }
            }
            .padding(20)
            .frame(
                maxWidth: 820,
                alignment: .leading
            )
            .frame(
                maxWidth: .infinity
            )
        }
        .navigationTitle(
            "웹페이지 질문"
        )
        .navigationBarTitleDisplayMode(
            .inline
        )
        .task {
            guard autoLoad,
                  !didAutoLoad,
                  viewModel.canLoad else {
                return
            }
            didAutoLoad = true
            viewModel.startLoading()
        }
        .onChange(
            of: viewModel.urlText
        ) { _, _ in
            viewModel.urlDidChange()
        }
        .onChange(
            of: viewModel.content
        ) { _, content in
            routeSharedContentIfNeeded(
                content
            )
        }
        .onDisappear {
            viewModel.cancel()
        }
    }

    private func routeSharedContentIfNeeded(
        _ content: WebPageContent?
    ) {
        guard !didRouteSharedContent,
              let content,
              let automaticallyStartsSharedVoiceInput,
              let plan =
                SharedTextEntryPlan.make(
                    rawText:
                        SharedWebContext
                        .make(
                            content: content
                        ),
                    mode:
                        automaticallyStartsSharedVoiceInput
                        ? .voice
                        : .chat
                ) else {
            return
        }
        didRouteSharedContent = true
        appRouter.route =
            .sharedTextQuestion(
                text: plan.text,
                automaticallyStartsVoiceInput:
                    plan
                    .automaticallyStartsVoiceInput
            )
    }

    private var urlSection: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            Label(
                "웹 주소",
                systemImage: "link"
            )
            .font(.headline)

            TextField(
                "https://example.com",
                text: $viewModel.urlText
            )
            .textFieldStyle(.roundedBorder)
            .textInputAutocapitalization(
                .never
            )
            .keyboardType(.URL)
            .autocorrectionDisabled()
            .submitLabel(.go)
            .onSubmit {
                viewModel.startLoading()
            }
            .disabled(viewModel.isLoading)
            .accessibilityHint(
                "HTTP 또는 HTTPS 웹 주소를 입력합니다."
            )

            Label(
                "웹페이지를 내려받을 때만 네트워크를 사용하고 AI 답변은 iPad에서 처리합니다.",
                systemImage:
                    "lock.shield"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button(
                    "붙여넣기",
                    systemImage:
                        "doc.on.clipboard"
                ) {
                    if let value =
                            UIPasteboard
                            .general.string {
                        viewModel
                            .replaceURL(
                                with: value
                            )
                    }
                }
                .disabled(viewModel.isLoading)

                if viewModel.isLoading {
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
                    .tint(.red)

                    ProgressView()
                        .accessibilityLabel(
                            "웹페이지를 읽는 중"
                        )
                } else {
                    Button(
                        "본문 읽기",
                        systemImage:
                            "doc.text.magnifyingglass"
                    ) {
                        viewModel
                            .startLoading()
                    }
                    .buttonStyle(
                        .borderedProminent
                    )
                    .disabled(
                        !viewModel.canLoad
                    )
                }

                Text(viewModel.status)
                    .font(.subheadline)
                    .foregroundStyle(
                        .secondary
                    )
            }
            .controlSize(.large)
        }
    }

    private func loadedContentSection(
        _ content: WebPageContent
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            HStack(
                alignment: .firstTextBaseline
            ) {
                Label(
                    "읽은 웹페이지",
                    systemImage:
                        "checkmark.circle.fill"
                )
                .font(.headline)
                .foregroundStyle(.green)

                Spacer()

                Link(
                    destination:
                        content.sourceURL
                ) {
                    Label(
                        "Safari에서 열기",
                        systemImage:
                            "safari"
                    )
                }
            }

            Text(content.title)
                .font(.title3.bold())
                .textSelection(.enabled)

            Text(
                content.sourceURL
                    .absoluteString
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)

            Text(
                AppLocalization.format(
                    "본문 %lld자",
                    content.text.count
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if content.wasTruncated {
                Label(
                    "로컬 모델의 문맥 길이를 위해 본문 앞부분만 사용합니다.",
                    systemImage:
                        "exclamationmark.triangle"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
            }

            if content
                .usedRenderedFallback {
                Label(
                    "동적 웹페이지라서 비공개 WebKit 렌더링을 사용했습니다.",
                    systemImage:
                        "network"
                )
                .font(.footnote)
                .foregroundStyle(
                    .secondary
                )
            }

            DisclosureGroup(
                "추출한 본문 미리보기"
            ) {
                Text(
                    String(
                        content.text
                            .prefix(2_000)
                    )
                )
                .font(.callout)
                .textSelection(.enabled)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                .padding(.top, 8)
            }
        }
        .padding(16)
        .background(
            Color.secondary.opacity(0.08)
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
        )
    }

    private var questionSection:
        some View
    {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            Label(
                "질문",
                systemImage:
                    "questionmark.bubble"
            )
            .font(.headline)

            TextField(
                "웹페이지에 대해 질문하세요",
                text: $viewModel.question,
                axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .lineLimit(2...6)

            Button(
                "M4 로컬 AI로 질문",
                systemImage:
                    "sparkles"
            ) {
                guard let route =
                        viewModel
                        .questionRoute() else {
                    return
                }
                appRouter.route = route
            }
            .buttonStyle(
                .borderedProminent
            )
            .controlSize(.large)
            .disabled(
                !viewModel.canAsk
            )
            .accessibilityHint(
                "웹 본문을 신뢰하지 않는 참고 자료로 구분해 로컬 AI에 전달합니다."
            )
        }
    }
}
