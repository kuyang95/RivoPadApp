import QuickLook
import SwiftUI
import UIKit

struct VisionLinkView: View {
    @EnvironmentObject private var appRouter:
        AppRouter
    @EnvironmentObject private var manager:
        VisionLinkManager
    @State private var isUnregisterConfirmationPresented =
        false
    @State private var isFileDeletionConfirmationPresented =
        false
    @State private var previewURL: URL?
    @State private var isOpeningReceivedText =
        false
    @State private var receivedTextOpenError:
        String?

    var body: some View {
        List {
            statusSection

            if manager.remoteVideoTrack != nil {
                videoSection
            }

            if let pairingCode = manager.pairingCode {
                pairingSection(code: pairingCode)
            }

            dataTransferSection
            controlsSection
            diagnosticsSection
            currentScopeSection
        }
        .navigationTitle("VisionLink")
        .task {
            manager.activate()
        }
        .quickLookPreview($previewURL)
        .confirmationDialog(
            "저장된 VisionLink 연결을 해제할까요?",
            isPresented:
                $isUnregisterConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(
                "등록 해제 후 새 코드 만들기",
                role: .destructive
            ) {
                manager.unregisterAndCreateNewCode()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text(
                AppLocalization.string(
                    "상대 기기와 서버에 저장된 연결 정보가 삭제됩니다."
                )
            )
        }
        .confirmationDialog(
            "받은 파일을 삭제할까요?",
            isPresented:
                $isFileDeletionConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(
                "파일 삭제",
                role: .destructive
            ) {
                manager.deleteLastReceivedFile()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text(
                AppLocalization.string(
                    "이 파일은 iPad와 파일 앱의 VisionLink 폴더에서 삭제됩니다."
                )
            )
        }
    }

    @ViewBuilder
    private var dataTransferSection: some View {
        Section("데이터 채널") {
            Label(
                manager.isDataChannelReady
                    ? "파일·텍스트 수신 준비됨"
                    : "상대 기기의 데이터 채널 대기 중",
                systemImage:
                    manager.isDataChannelReady
                    ? "arrow.down.circle.fill"
                    : "arrow.down.circle"
            )
            .foregroundStyle(
                manager.isDataChannelReady
                    ? Color.green
                    : Color.secondary
            )

            if manager.isCameraShareActive {
                Label(
                    "상대 카메라 공유 중",
                    systemImage: "camera.fill"
                )
                .foregroundStyle(.green)
            }

            if let status =
                manager.remoteFeatureStatus {
                HStack(spacing: 12) {
                    if status.isWorking {
                        ProgressView()
                    } else {
                        Image(
                            systemName:
                                status.stage == "error"
                                ? "exclamationmark.triangle.fill"
                                : "checkmark.circle.fill"
                        )
                        .foregroundStyle(
                            status.stage == "error"
                                ? Color.red
                                : Color.green
                        )
                    }
                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text(
                            AppLocalization.format(
                                "원격 %@",
                                status.feature.title
                            )
                        )
                        .font(.headline)
                        Text(status.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(
                    children: .combine
                )
            }

            if let progress = manager.incomingTransfer {
                VStack(
                    alignment: .leading,
                    spacing: 8
                ) {
                    Text(progress.fileName)
                        .font(.headline)
                    ProgressView(
                        value:
                            progress.fractionCompleted
                    )
                    Text(
                        byteCount(
                            progress.receivedBytes
                        )
                        + " / "
                        + byteCount(
                            progress.totalBytes
                        )
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                .accessibilityElement(
                    children: .combine
                )
            }

            if let file = manager.lastReceivedFile {
                VStack(
                    alignment: .leading,
                    spacing: 10
                ) {
                    Label {
                        VStack(
                            alignment: .leading,
                            spacing: 3
                        ) {
                            Text(file.fileName)
                                .font(.headline)
                            Text(byteCount(file.size))
                                .font(.caption)
                                .foregroundStyle(
                                    .secondary
                                )
                        }
                    } icon: {
                        Image(
                            systemName:
                                file.kind == "image"
                                ? "photo"
                                : "doc"
                        )
                    }

                    HStack {
                        Button(
                            "미리보기",
                            systemImage:
                                "doc.text.magnifyingglass"
                        ) {
                            previewURL = file.url
                        }
                        .buttonStyle(.bordered)

                        ShareLink(
                            item: file.url,
                            preview: SharePreview(
                                file.fileName
                            )
                        ) {
                            Label(
                                "내보내기",
                                systemImage:
                                    "square.and.arrow.up"
                            )
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) {
                            isFileDeletionConfirmationPresented =
                                true
                        } label: {
                            Label(
                                "삭제",
                                systemImage: "trash"
                            )
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            if let text =
                manager.receivedClipboardText {
                VStack(
                    alignment: .leading,
                    spacing: 10
                ) {
                    Text("받은 클립보드 텍스트")
                        .font(.headline)
                    Text(
                        text.isEmpty
                            ? AppLocalization.string(
                                "(빈 텍스트)"
                            )
                            : text
                    )
                        .lineLimit(6)
                        .textSelection(.enabled)
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                    HStack {
                        Button(
                            "클립보드에 복사",
                            systemImage: "doc.on.doc"
                        ) {
                            UIPasteboard.general
                                .string = text
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            openReceivedText(text)
                        } label: {
                            if isOpeningReceivedText {
                                ProgressView()
                                    .accessibilityLabel(
                                        "받은 텍스트를 여는 중"
                                    )
                            } else {
                                Label(
                                    "텍스트뷰로 열기",
                                    systemImage:
                                        "doc.text.magnifyingglass"
                                )
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(
                            isOpeningReceivedText
                        )

                        Button("닫기") {
                            receivedTextOpenError =
                                nil
                            manager
                                .clearReceivedClipboard()
                        }
                    }
                    if let receivedTextOpenError {
                        Label(
                            receivedTextOpenError,
                            systemImage:
                                "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                }
            }

            if let message =
                manager.dataTransferMessage {
                Label(
                    message,
                    systemImage:
                        "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.red)
                .swipeActions {
                    Button("지우기") {
                        manager
                            .clearDataTransferMessage()
                    }
                }
            }
        }
    }

    private var videoSection: some View {
        Section("원격 화면") {
            VisionLinkVideoView(
                track: manager.remoteVideoTrack
            ) {
                manager.markFirstVideoFrameRendered()
            }
            .aspectRatio(16 / 10, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(Color.black)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
            )
            .accessibilityLabel("VisionLink 원격 카메라 영상")
        }
    }

    private var statusSection: some View {
        Section("연결 상태") {
            HStack(spacing: 18) {
                if manager.state.isWorking {
                    ProgressView()
                        .controlSize(.large)
                        .tint(statusColor)
                        .frame(width: 48)
                } else {
                    Image(systemName: statusIcon)
                        .font(
                            .system(
                                size: 36,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(statusColor)
                        .frame(width: 48)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(manager.state.title)
                        .font(.title3.bold())
                    if let peerName = manager.peerName {
                        Text(peerName)
                            .foregroundStyle(.secondary)
                    } else if let roomID = manager.roomID {
                        Text("방 \(roomID)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 10)
            .accessibilityElement(children: .combine)
        }
    }

    private func pairingSection(
        code: String
    ) -> some View {
        Section("연결 코드") {
            VStack(spacing: 14) {
                Text(code)
                    .font(
                        .system(
                            size: 64,
                            weight: .bold,
                            design: .monospaced
                        )
                    )
                    .tracking(10)
                    .minimumScaleFactor(0.6)
                    .accessibilityLabel(
                        AppLocalization.format(
                            "연결 코드 %@",
                            code.map(String.init)
                                .joined(separator: " ")
                        )
                    )

                if let seconds = manager.remainingSeconds {
                    Text("만료까지 \(seconds)초")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(
                            seconds <= 30
                                ? Color.red
                                : Color.secondary
                        )
                }

                Text(
                    "상대 기기의 VisionLink에 이 코드를 입력하세요."
                )
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

                Button(
                    "코드 복사",
                    systemImage: "doc.on.doc"
                ) {
                    UIPasteboard.general.string = code
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
        }
    }

    @ViewBuilder
    private var controlsSection: some View {
        Section("연결 관리") {
            switch manager.state {
            case .inactive,
                 .disconnected,
                 .codeExpired,
                 .failed:
                Button(
                    "다시 연결",
                    systemImage: "arrow.clockwise"
                ) {
                    manager.retry()
                }
                .font(.headline)

            case .creatingSession, .reconnecting:
                Button(
                    "취소",
                    systemImage: "xmark"
                ) {
                    manager.disconnect()
                }

            case .waitingForCompanion,
                 .companionConnected,
                 .mediaOfferReceived,
                 .mediaConnecting,
                 .mediaConnected,
                 .videoReceiving:
                Button(
                    "신호 연결 끊기",
                    systemImage: "network.slash"
                ) {
                    manager.disconnect()
                }
            }

            if manager.pairingCode != nil {
                Button(
                    "새 코드 생성",
                    systemImage: "number"
                ) {
                    manager.createNewCode()
                }
            }

            if manager.hasStoredPair,
               manager.pairingCode == nil {
                Button(
                    "기기 등록 해제",
                    systemImage: "trash",
                    role: .destructive
                ) {
                    isUnregisterConfirmationPresented = true
                }
            }
        }
    }

    @ViewBuilder
    private var diagnosticsSection: some View {
        Section {
            if manager.recentEvents.isEmpty {
                ContentUnavailableView(
                    "아직 신호 이벤트가 없습니다",
                    systemImage: "wave.3.right",
                    description: Text(
                        AppLocalization.string(
                            "서버나 상대 기기에서 메시지가 오면 여기에 표시됩니다."
                        )
                    )
                )
            } else {
                ForEach(manager.recentEvents.prefix(12)) {
                    event in
                    HStack {
                        Text(event.summary)
                        Spacer()
                        Text(event.date, style: .time)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } header: {
            HStack {
                Text("신호 진단")
                Spacer()
                if !manager.recentEvents.isEmpty {
                    Button("지우기") {
                        manager.clearEventHistory()
                    }
                    .textCase(nil)
                }
            }
        }
    }

    private var currentScopeSection: some View {
        Section("현재 구현 범위") {
            Label(
                "VisionCraft 서버와 같은 코드 페어링",
                systemImage: "checkmark.circle.fill"
            )
            Label(
                "보안 자격정보 저장과 다음 실행 재연결",
                systemImage: "checkmark.circle.fill"
            )
            Label(
                "WebSocket 신호 연결과 상대 기기 감지",
                systemImage: "checkmark.circle.fill"
            )
            Label(
                "WebRTC 원격 영상 수신과 Metal 표시",
                systemImage: "checkmark.circle.fill"
            )
            Label(
                "데이터 채널·파일·클립보드 수신",
                systemImage: "checkmark.circle.fill"
            )
            Label(
                "원격 OCR·이미지 설명·번역",
                systemImage: "checkmark.circle.fill"
            )
            Label(
                "원격 AI 대화·첨부·실시간 읽기",
                systemImage: "checkmark.circle.fill"
            )
        }
    }

    private func byteCount(
        _ value: Int64
    ) -> String {
        ByteCountFormatter.string(
            fromByteCount: value,
            countStyle: .file
        )
    }

    private func openReceivedText(
        _ text: String
    ) {
        guard !isOpeningReceivedText else {
            return
        }
        isOpeningReceivedText = true
        receivedTextOpenError = nil
        Task {
            do {
                let fileURL =
                    try await
                    VisionLinkReceivedTextStore
                    .shared.save(text)
                isOpeningReceivedText = false
                appRouter.route =
                    .localDocument(
                        fileURL: fileURL
                    )
            } catch {
                isOpeningReceivedText = false
                receivedTextOpenError =
                    error.localizedDescription
            }
        }
    }

    private var statusIcon: String {
        switch manager.state {
        case .waitingForCompanion:
            return "antenna.radiowaves.left.and.right"
        case .companionConnected,
             .mediaOfferReceived,
             .mediaConnecting:
            return "arrow.triangle.2.circlepath"
        case .mediaConnected:
            return "video.badge.clock"
        case .videoReceiving:
            return "checkmark.circle.fill"
        case .failed, .codeExpired:
            return "exclamationmark.triangle.fill"
        case .inactive, .disconnected:
            return "network.slash"
        case .creatingSession, .reconnecting:
            return "network"
        }
    }

    private var statusColor: Color {
        switch manager.state {
        case .mediaConnected, .videoReceiving:
            return .green
        case .waitingForCompanion,
             .companionConnected,
             .mediaOfferReceived,
             .mediaConnecting,
             .creatingSession,
             .reconnecting:
            return .orange
        case .failed, .codeExpired:
            return .red
        case .inactive, .disconnected:
            return .secondary
        }
    }
}
