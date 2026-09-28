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
    @State private var isSettingsPresented = false

    var body: some View {
        ZStack {
            VisionCraftUI.background
                .ignoresSafeArea()

            if let track = manager.remoteVideoTrack,
               manager.isCameraShareActive {
                VisionLinkVideoView(track: track) {
                    manager.markFirstVideoFrameRendered()
                }
                .ignoresSafeArea()
                .background(Color.black)
            } else if isConnected {
                connectedStage
            } else {
                connectionStage
            }

            VStack {
                HStack {
                    if isConnected {
                        connectionChip
                    }
                    Spacer()
                    Button {
                        isSettingsPresented = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.title3)
                            .foregroundStyle(
                                VisionCraftUI.primaryText
                            )
                            .frame(width: 48, height: 48)
                            .background(
                                VisionCraftUI.surface
                                    .opacity(0.86),
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        "VisionLink 설정"
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                Spacer()
                transferOverlay
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
            }
        }
        .visionCraftNavigationScreen()
        .navigationTitle("스마트폰과 연동")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            manager.activate()
        }
        .quickLookPreview($previewURL)
        .sheet(isPresented: $isSettingsPresented) {
            visionLinkSettings
        }
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
    private var connectionStage: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(
                        VisionCraftUI.linkBlue
                            .opacity(0.14)
                    )
                    .frame(width: 88, height: 88)
                Circle()
                    .fill(
                        VisionCraftUI.linkBlue
                            .opacity(0.24)
                    )
                    .frame(width: 64, height: 64)
                Image(systemName: "link")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(
                        VisionCraftUI.linkBlue
                    )
            }

            Text(connectionTitle)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(
                    VisionCraftUI.primaryText
                )
                .multilineTextAlignment(.center)
                .padding(.top, 18)

            Text(connectionMessage)
                .font(.system(size: 16))
                .foregroundStyle(
                    VisionCraftUI.secondaryText
                )
                .multilineTextAlignment(.center)
                .padding(.top, 6)

            if let code = manager.pairingCode {
                VStack(spacing: 2) {
                    Text(code)
                        .font(
                            .system(
                                size: 30,
                                weight: .bold,
                                design: .monospaced
                            )
                        )
                        .tracking(4)
                        .foregroundStyle(
                            VisionCraftUI.primaryText
                        )
                    if let seconds =
                            manager.remainingSeconds {
                        Text("만료까지 \(seconds)초")
                            .font(.system(size: 14))
                            .foregroundStyle(
                                VisionCraftUI.warning
                            )
                    }
                }
                .frame(minWidth: 260)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    VisionCraftUI.surface,
                    in: RoundedRectangle(
                        cornerRadius: 16,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 16,
                        style: .continuous
                    )
                    .stroke(
                        VisionCraftUI.outline,
                        lineWidth: 1
                    )
                }
                .padding(.top, 16)
            }

            if shouldShowNewCodeButton {
                Button("새 코드 생성") {
                    manager.createNewCode()
                }
                .buttonStyle(.borderedProminent)
                .tint(VisionCraftUI.accent)
                .controlSize(.large)
                .padding(.top, 16)
            }
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, 48)
    }

    private var connectedStage: some View {
        VStack(spacing: 0) {
            ZStack {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                VisionCraftUI.linkBlue,
                                VisionCraftUI.success,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 148, height: 2)

                HStack {
                    connectedNode(
                        "iphone",
                        color:
                            VisionCraftUI.linkBlue
                    )
                    Spacer()
                    connectedNode(
                        "ipad",
                        color:
                            VisionCraftUI.success
                    )
                }
                .frame(width: 220)
            }
            .frame(width: 240, height: 96)

            Text("연결됨")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(
                    VisionCraftUI.primaryText
                )
                .padding(.top, 10)
            Text("VisionLink 에서 작업을 시작하세요.")
                .font(.system(size: 16))
                .foregroundStyle(
                    VisionCraftUI.secondaryText
                )
                .padding(.top, 6)
            Text(
                "카메라 화면공유 · 파일보내기 · 비전크래프트 기능"
            )
            .font(.system(size: 14))
            .foregroundStyle(VisionCraftUI.secondaryText)
            .multilineTextAlignment(.center)
            .padding(.top, 12)

            if let file = manager.lastReceivedFile {
                Button {
                    previewURL = file.url
                } label: {
                    Label(
                        file.fileName,
                        systemImage: "chevron.right"
                    )
                    .lineLimit(1)
                    .frame(minHeight: 48)
                }
                .buttonStyle(.bordered)
                .padding(.top, 18)
            }
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, 48)
    }

    private func connectedNode(
        _ image: String,
        color: Color
    ) -> some View {
        Image(systemName: image)
            .font(.system(size: 25, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 58, height: 58)
            .background(color.opacity(0.20), in: Circle())
            .overlay {
                Circle().strokeBorder(color, lineWidth: 1)
            }
    }

    private var connectionChip: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(VisionCraftUI.success)
                .frame(width: 10, height: 10)
            Text(connectionActivityTitle)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(
                    VisionCraftUI.primaryText
                )
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(
            VisionCraftUI.surface.opacity(0.88),
            in: Capsule()
        )
    }

    @ViewBuilder
    private var transferOverlay: some View {
        if let progress = manager.incomingTransfer {
            VStack(alignment: .leading, spacing: 10) {
                Label(
                    "파일 받는 중",
                    systemImage:
                        "arrow.down.doc.fill"
                )
                .font(.headline)
                Text(progress.fileName)
                    .font(.subheadline)
                    .foregroundStyle(
                        VisionCraftUI.secondaryText
                    )
                    .lineLimit(1)
                ProgressView(
                    value:
                        progress.fractionCompleted
                )
            }
            .visionLinkTransferCard()
        } else if let text =
                    manager.receivedClipboardText {
            Button {
                openReceivedText(text)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "doc.text.fill")
                        .font(.title2)
                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {
                        Text("텍스트를 받았습니다")
                            .font(.headline)
                        Text(text)
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .foregroundStyle(
                    VisionCraftUI.primaryText
                )
                .visionLinkTransferCard()
            }
            .buttonStyle(.plain)
        } else if let message =
                    manager.dataTransferMessage {
            Label(
                message,
                systemImage:
                    "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.red)
            .visionLinkTransferCard()
        }
    }

    private var visionLinkSettings: some View {
        NavigationStack {
            List {
                if manager.hasStoredPair {
                    Button(
                        "기기 등록 해제",
                        systemImage: "link.badge.minus",
                        role: .destructive
                    ) {
                        isSettingsPresented = false
                        isUnregisterConfirmationPresented =
                            true
                    }
                    .frame(minHeight: 64)
                }

                controlsSection
            }
            .visionCraftListScreen()
            .navigationTitle("VisionLink 설정")
            .toolbar {
                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button("완료") {
                        isSettingsPresented = false
                    }
                }
            }
        }
    }

    private var isConnected: Bool {
        switch manager.state {
        case .mediaConnected,
             .mediaIdle,
             .videoReceiving:
            return true
        default:
            return false
        }
    }

    private var shouldShowNewCodeButton: Bool {
        switch manager.state {
        case .codeExpired, .failed, .disconnected:
            return true
        default:
            return false
        }
    }

    private var connectionTitle: String {
        switch manager.state {
        case .waitingForCompanion:
            return AppLocalization.string(
                "VisionLink 연결 대기 중"
            )
        case .codeExpired:
            return AppLocalization.string(
                "연결 코드가 만료되었습니다"
            )
        case .disconnected, .failed:
            return AppLocalization.string(
                "연결이 끊겼습니다"
            )
        default:
            return AppLocalization.string(
                "연결 준비 중"
            )
        }
    }

    private var connectionMessage: String {
        switch manager.state {
        case .waitingForCompanion:
            return AppLocalization.string(
                "휴대폰의 VisionLink에서 아래 연결 코드를 입력해주세요."
            )
        case .codeExpired:
            return AppLocalization.string(
                "새 연결 코드를 만들어 다시 연결할 수 있습니다."
            )
        case .disconnected, .failed:
            return AppLocalization.string(
                "VisionLink의 연결 상태를 확인해주세요."
            )
        default:
            return AppLocalization.string(
                "VisionLink와 안전하게 연결하고 있습니다."
            )
        }
    }

    private var connectionActivityTitle: String {
        if manager.isCameraShareActive {
            return AppLocalization.string(
                "카메라 화면 공유 중"
            )
        }
        if manager.connectedActivity?.isWorking
            == true {
            return manager.connectedActivity?.title
                ?? AppLocalization.string(
                    "연결됨 · 전송 대기 중"
                )
        }
        return AppLocalization.string(
            "연결됨 · 전송 대기 중"
        )
    }

    @ViewBuilder
    private var dataTransferSection: some View {
        Section("데이터 채널") {
            Label(
                AppLocalization.string(
                    manager.isDataChannelReady
                        ? "파일·텍스트 수신 준비됨"
                        : "상대 기기의 데이터 채널 대기 중"
                ),
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

            if let activity =
                manager.connectedActivity {
                HStack(spacing: 12) {
                    if activity.isWorking {
                        ProgressView()
                    } else {
                        Image(
                            systemName:
                                "pause.circle.fill"
                        )
                        .foregroundStyle(
                            Color.secondary
                        )
                    }
                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text(activity.title)
                            .font(.headline)
                        Text(activity.detail)
                            .font(.caption)
                            .foregroundStyle(
                                .secondary
                            )
                    }
                }
                .accessibilityElement(
                    children: .combine
                )
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
                 .mediaIdle,
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
        case .mediaIdle:
            return "checkmark.circle"
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
        case .mediaConnected,
             .mediaIdle,
             .videoReceiving:
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

private extension View {
    func visionLinkTransferCard() -> some View {
        self
            .padding(18)
            .frame(
                maxWidth: 560,
                alignment: .leading
            )
            .background(
                VisionCraftUI.surface.opacity(0.94),
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
                .stroke(
                    VisionCraftUI.outline,
                    lineWidth: 1
                )
            }
            .shadow(
                color: .black.opacity(0.2),
                radius: 10,
                y: 4
            )
    }
}
