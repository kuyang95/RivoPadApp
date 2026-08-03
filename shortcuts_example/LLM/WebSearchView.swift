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
                "검색어는 Brave Search로 보내고, 답변은 이 iPad의 M4에서 만듭니다.",
                systemImage: "lock.shield"
            )
            .font(.headline)

            Text(
                "Brave는 과금·장애 대응·남용 방지를 위해 검색어 로그를 최대 90일 보관할 수 있습니다. VisionCraft는 검색 결과와 답변을 대화 기록에 저장하지 않습니다."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            Link(
                "Brave 개인정보 안내",
                destination: URL(
                    string:
                        "https://api-dashboard.search.brave.com/privacy-policy"
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
                        "출처 검색",
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
                    )
                }

                Text(viewModel.status)
                    .font(.subheadline)
                    .foregroundStyle(
                        .secondary
                    )
            }
            .controlSize(.large)

            if !configuration.isEnabled {
                Label(
                    AppLocalization.string(
                        configuration
                            .hasAPIKey
                            ? "설정에서 온라인 웹 검색을 켜 주세요."
                            : "설정에서 개인 Brave Search API 키를 저장해 주세요."
                    ),
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

            Text(result.snippet)
                .font(.callout)
                .lineLimit(6)
                .textSelection(.enabled)
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
                "로컬 답변",
                systemImage: "sparkles"
            )
            .font(.headline)

            Text(
                "위 출처만 참고 자료로 전달합니다. 검색 결과와 답변은 대화 기록에 저장하지 않습니다."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            Button(
                "M4 로컬 AI로 답변",
                systemImage: "cpu"
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
