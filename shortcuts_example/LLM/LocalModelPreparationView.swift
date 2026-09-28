import SwiftUI

struct LocalModelPreparationView: View {
    let phase: LocalModelPreparationPhase
    let model: LocalModelMetadata?
    let failure: LocalModelPreparationFailure?
    let onRetry: () -> Void
    let onDefer: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: heroIcon)
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(heroColor)
                    .frame(width: 104, height: 104)
                    .background(
                        heroColor.opacity(0.12),
                        in: Circle()
                    )
                    .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Text(title)
                        .font(.largeTitle.bold())
                        .foregroundStyle(
                            VisionCraftUI.primaryText
                        )
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)

                    Text(message)
                        .font(.title3)
                        .foregroundStyle(
                            VisionCraftUI.secondaryText
                        )
                        .multilineTextAlignment(.center)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                }

                if let failure {
                    failureCard(failure)
                } else {
                    progressCard
                }

                informationCard

                VStack(spacing: 12) {
                    if failure != nil {
                        Button(action: onRetry) {
                            Text("다시 시도")
                                .font(.headline)
                                .frame(
                                    maxWidth: .infinity,
                                    minHeight: 56
                                )
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(
                            .roundedRectangle(radius: 14)
                        )
                        .tint(VisionCraftUI.primary)
                    }

                    Button(action: onDefer) {
                        Text("나중에")
                            .font(.headline)
                            .frame(
                                maxWidth: .infinity,
                                minHeight: 54
                            )
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(
                        .roundedRectangle(radius: 14)
                    )
                    .tint(VisionCraftUI.primary)
                    .accessibilityHint(
                        AppLocalization.string(
                            "다운로드를 중단하고 이전 화면으로 돌아갑니다. 받은 데이터는 보관됩니다."
                        )
                    )
                }
            }
            .frame(maxWidth: 680)
            .padding(.horizontal, 28)
            .padding(.vertical, 44)
            .frame(maxWidth: .infinity)
        }
        .background(VisionCraftUI.background)
    }

    private var heroIcon: String {
        failure == nil
            ? "arrow.down.circle.fill"
            : "exclamationmark.triangle.fill"
    }

    private var heroColor: Color {
        failure == nil
            ? VisionCraftUI.primary
            : .orange
    }

    private var title: String {
        if let failure {
            return failure.title
        }
        switch phase {
        case .downloading:
            return AppLocalization.string(
                "AI 모델 다운로드"
            )
        case .loading:
            return AppLocalization.string(
                "AI 모델 준비 중"
            )
        case .idle, .checking:
            return AppLocalization.string(
                "AI 모델 확인 중"
            )
        }
    }

    private var message: String {
        if let failure {
            return failure.message
        }
        switch phase {
        case .downloading:
            return AppLocalization.string(
                "처음 사용할 AI 모델을 이 iPad에 다운로드하고 있습니다."
            )
        case .loading:
            return AppLocalization.string(
                "다운로드가 완료되었습니다. 로컬 AI를 실행할 준비를 하고 있습니다."
            )
        case .idle, .checking:
            return AppLocalization.string(
                "이 iPad에 필요한 AI 모델이 있는지 확인하고 있습니다."
            )
        }
    }

    @ViewBuilder
    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(activeModelName)
                    .font(.headline)
                    .foregroundStyle(
                        VisionCraftUI.primaryText
                    )
                Spacer()
                if case .downloading(let progress) = phase {
                    Text(
                        "\(Int(progress.fractionCompleted * 100))%"
                    )
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(VisionCraftUI.primary)
                }
            }

            switch phase {
            case .downloading(let progress):
                ProgressView(
                    value: progress.fractionCompleted
                )
                .tint(VisionCraftUI.primary)
                .scaleEffect(x: 1, y: 1.6)

                HStack {
                    Text(
                        AppLocalization.format(
                            "%@ / %@ 받음",
                            formattedBytes(
                                progress.downloadedBytes
                            ),
                            formattedBytes(
                                progress.model
                                    .expectedDownloadBytes
                            )
                        )
                    )
                    Spacer()
                    if let speed = progress.bytesPerSecond,
                       speed > 0 {
                        Text(
                            AppLocalization.format(
                                "초당 %@",
                                formattedBytes(
                                    Int64(speed)
                                )
                            )
                        )
                    }
                }
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(
                    VisionCraftUI.secondaryText
                )

            case .idle, .checking, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .controlSize(.large)
            }
        }
        .padding(22)
        .visionCraftSurfaceCard(cornerRadius: 18)
        .accessibilityElement(children: .combine)
    }

    private func failureCard(
        _ failure: LocalModelPreparationFailure
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                "다운로드를 완료하지 못했습니다.",
                systemImage: "wifi.exclamationmark"
            )
            .font(.headline)
            .foregroundStyle(.orange)

            if let detail = failure.technicalDetail,
               !detail.isEmpty {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(
                        VisionCraftUI.secondaryText
                    )
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
            }

            Text(
                "다시 시도하면 이미 받은 부분부터 이어서 다운로드합니다."
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(VisionCraftUI.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(
            Color.orange.opacity(0.10),
            in: RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(Color.orange.opacity(0.35))
        }
    }

    private var informationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            informationRow(
                icon: "checkmark.circle.fill",
                text: "최초 한 번만 다운로드합니다."
            )
            informationRow(
                icon: "internaldrive.fill",
                text: storageDescription
            )
            informationRow(
                icon: "wifi",
                text: "Wi-Fi를 유지하고 다운로드가 끝날 때까지 앱을 열어 두세요."
            )
            informationRow(
                icon: "arrow.clockwise.circle.fill",
                text: "중단되거나 실패해도 받은 데이터는 보관되며 다음 시도에서 이어받습니다."
            )
            informationRow(
                icon: "lock.shield.fill",
                text: "다운로드 후 질문과 문서 분석은 이 iPad에서 처리됩니다."
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .visionCraftSurfaceCard(cornerRadius: 18)
    }

    private func informationRow(
        icon: String,
        text: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(VisionCraftUI.primary)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(AppLocalization.string(text))
                .font(.body)
                .foregroundStyle(
                    VisionCraftUI.primaryText
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
        }
    }

    /// 사용자에게는 어떤 모델인지가 의미 없어서 모델명 대신 공통 표기를 쓴다.
    private var activeModelName: String {
        AppLocalization.string("로컬 AI 모델")
    }

    private var storageDescription: String {
        guard let model else {
            return AppLocalization.string(
                "모델을 저장할 충분한 여유 공간이 필요합니다."
            )
        }
        return AppLocalization.format(
            "다운로드 크기는 약 %@입니다. 충분한 여유 공간을 확보해 주세요.",
            formattedBytes(model.expectedDownloadBytes)
        )
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(
            fromByteCount: bytes,
            countStyle: .file
        )
    }
}
