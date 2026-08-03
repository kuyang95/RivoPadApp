import SwiftUI

struct WebSearchView: View {
    @EnvironmentObject private var appRouter:
        AppRouter
    @ObservedObject private var configuration =
        WebSearchConfigurationStore.shared
    @StateObject private var viewModel:
        WebSearchViewModel
    @State private var didAutoSearch = false

    private let autoSearch: Bool
    private let speaksAnswer: Bool

    init(
        initialQuery: String? = nil,
        autoSearch: Bool = false,
        speaksAnswer: Bool = false
    ) {
        self.autoSearch = autoSearch
        self.speaksAnswer = speaksAnswer
        _viewModel = StateObject(
            wrappedValue:
                WebSearchViewModel(
                    initialQuery:
                        initialQuery
                )
        )
    }

    var body: some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: 20
            ) {
                privacyNotice
                querySection

                if let error =
                        viewModel
                        .errorDescription {
                    errorView(error)
                }

                if let response =
                        viewModel.response {
                    resultsSection(
                        response
                    )
                    answerSection(
                        response
                    )
                } else if !viewModel
                    .isSearching {
                    emptyView
                }
            }
            .padding(20)
            .frame(
                maxWidth: 820,
                alignment: .leading
            )
            .frame(maxWidth: .infinity)
        }
        .visionCraftNavigationScreen()
        .navigationTitle("웹 검색")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard autoSearch,
                  !didAutoSearch else {
                return
            }
            didAutoSearch = true
            await viewModel.searchNow()
            guard let route =
                    viewModel.answerRoute(
                        speaksResponse:
                            speaksAnswer
                    ),
                  !Task.isCancelled else {
                return
            }
            appRouter.route = route
        }
        .onChange(
            of: viewModel.query
        ) { _, _ in
            viewModel.queryDidChange()
        }
        .onDisappear {
            viewModel.cancel()
        }
    }

    private var privacyNotice:
        some View
    {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            Label(
                "웹 검색 질문은 Gemini와 Google Search로 전송됩니다.",
                systemImage: "lock.shield"
            )
            .font(.headline)

            Text(
                "일반 채팅과 문서 분석은 M4에서 계속 로컬로 처리합니다. 웹 검색을 선택한 경우에만 Gemini가 Google Search에 근거한 답변을 만듭니다."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            Link(
                "Google 개인정보처리방침",
                destination: URL(
                    string:
                        "https://policies.google.com/privacy"
                )!
            )
            .font(.footnote)
        }
        .padding(16)
        .background(VisionCraftUI.primary.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(VisionCraftUI.primary.opacity(0.25), lineWidth: 1)
        }
    }

    private var querySection:
        some View
    {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            Label(
                "검색어",
                systemImage:
                    "magnifyingglass"
            )
            .font(.headline)

            TextField(
                "최신 정보가 필요한 질문을 입력하세요",
                text: $viewModel.query,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .visionCraftInputSurface()
            .lineLimit(2...5)
            .submitLabel(.search)
            .onSubmit {
                viewModel.startSearching()
            }
            .disabled(viewModel.isSearching)

            HStack(spacing: 12) {
                if viewModel.isSearching {
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
                            "웹 검색 중"
                        )
                } else {
                    Button(
                        "웹 검색",
                        systemImage:
                            "magnifyingglass"
                    ) {
                        viewModel
                            .startSearching()
                    }
                    .buttonStyle(
                        .borderedProminent
                    )
                    .disabled(
                        !viewModel
                        .canSearch
                        || !configuration
                            .isEnabled
                        || !configuration
                            .isFirebaseConfigured
                    )
                }

                Text(viewModel.status)
                    .font(.subheadline)
                    .foregroundStyle(
                        .secondary
                    )
            }
            .controlSize(.large)

            if !configuration
                .isFirebaseConfigured {
                Label(
                    "VisionCraft의 Firebase 연결 설정이 필요합니다.",
                    systemImage:
                        "exclamationmark.triangle"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
            } else if !configuration.isEnabled {
                Label(
                    "설정에서 온라인 웹 검색을 켜 주세요.",
                    systemImage:
                        "exclamationmark.triangle"
                )
                .font(.footnote)
                .foregroundStyle(.orange)

                NavigationLink(
                    "웹 검색 설정 열기",
                    value: AppRoute.settings
                )
            }
        }
        .padding(16)
        .visionCraftSurfaceCard(cornerRadius: 16)
    }

    private func errorView(
        _ error: String
    ) -> some View {
        Label(
            error,
            systemImage:
                "exclamationmark.triangle"
        )
        .font(.footnote)
        .foregroundStyle(.red)
        .accessibilityLabel(
            "오류: \(error)"
        )
    }

    private var emptyView:
        some View
    {
        ContentUnavailableView(
            "검색 출처가 없습니다",
            systemImage:
                "globe.badge.chevron.backward",
            description: Text(
                "최신 정보가 필요한 질문을 검색하면 관련 출처를 먼저 확인할 수 있습니다."
            )
        )
        .frame(maxWidth: .infinity)
        .padding(24)
        .visionCraftSurfaceCard(cornerRadius: 20)
    }

    private func resultsSection(
        _ response: WebSearchResponse
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            HStack {
                Label(
                    "검색 출처",
                    systemImage:
                        "checkmark.shield"
                )
                .font(.headline)
                .foregroundStyle(.green)

                Spacer()

                Text(response.providerName)
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
            }

            if let html = response
                .searchEntryPointHTML,
               !html.isEmpty {
                GoogleSearchEntryPointView(
                    html: html
                )
                .frame(height: 64)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 10,
                        style: .continuous
                    )
                )
                .accessibilityHint(
                    "Google에서 관련 검색을 이어갑니다."
                )
            }

            ForEach(response.results) {
                result in
                resultCard(result)
            }
        }
    }

    private func resultCard(
        _ result: WebSearchResult
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            Link(
                destination: result.url
            ) {
                HStack(
                    alignment:
                        .firstTextBaseline
                ) {
                    Text(
                        "[\(result.id)] \(result.title)"
                    )
                    .font(.headline)
                    .multilineTextAlignment(
                        .leading
                    )

                    Spacer()

                    Image(
                        systemName:
                            "arrow.up.right"
                    )
                }
            }

            Text(
                result.url
                    .absoluteString
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .textSelection(.enabled)

            if let age =
                    result.ageDescription {
                Text(age)
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
            }

            if !result.snippet.isEmpty {
                Text(result.snippet)
                    .font(.callout)
                    .lineLimit(6)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
        .visionCraftSurfaceCard(cornerRadius: 14)
        .accessibilityElement(
            children: .combine
        )
        .accessibilityLabel(
            "출처 \(result.id): \(result.title)"
        )
    }

    private func answerSection(
        _ response: WebSearchResponse
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            Label(
                "Gemini 검색 답변",
                systemImage: "sparkles"
            )
            .font(.headline)

            Text(
                "Google Search에 근거한 답변과 출처를 표시합니다. 검색 결과와 답변은 VisionCraft 대화 기록에 저장하지 않습니다."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            Button(
                "답변 보기",
                systemImage: "text.bubble"
            ) {
                guard let route =
                        viewModel
                        .answerRoute() else {
                    return
                }
                appRouter.route = route
            }
            .buttonStyle(
                .borderedProminent
            )
            .controlSize(.large)
            .disabled(
                response.results.isEmpty
            )
        }
        .padding(16)
        .visionCraftSurfaceCard(cornerRadius: 16)
    }
}
