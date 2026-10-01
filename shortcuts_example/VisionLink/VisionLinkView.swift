import QuickLook
import SwiftUI
import UIKit

/// VisionLink 전용 색·모양. Android `vc_link_*`, `bg_visionlink_*` (component spec 9절). 이 파일 밖에서는 쓰지 않는다.
private enum VisionLinkStyle {
    /// `VcLinkOrb`: 파랑 채움 알파 0x29(밝게)/0x33(어둡게).
    static func orbFill(_ scheme: ColorScheme) -> Color {
        VisionCraftUI.linkBlue.opacity(
            scheme == .dark ? 0.2 : 0.16
        )
    }
    static let orbOutline = VisionCraftUI.linkBlue
    static let orbOutlineWidth: CGFloat = 1.5
    static let orbSize: CGFloat = 64
    static let orbPulseSize: CGFloat = 88
    /// `VcLinkNode`: 58dp 원, 강조색 20% / 성공색 16% + 1dp 테두리.
    static let nodeSize: CGFloat = 58
    /// `VcLinkChip`: 반투명 면 #E6FAFAFA, 1dp 50% 테두리, 44dp, 모서리 22.
    static let hudChipFill =
        VisionCraftUI.fixedColor(0xFAFAFA).opacity(0.9)
    /// `VcLinkHudCard`: 모서리 16, 반투명 면 #F2FAFAFA, 1dp 테두리, 그림자 16.
    static let hudCardFill =
        VisionCraftUI.fixedColor(0xFAFAFA).opacity(0.95)
    static let hudOutline =
        VisionCraftUI.fixedColor(0x536176).opacity(0.5)
    /// HUD 면은 항상 밝은 색이라 글자는 고정 잉크색을 쓴다.
    static let hudText = VisionCraftUI.fixedColor(0x283546)
    static let hudSecondaryText =
        VisionCraftUI.fixedColor(0x536176)
    /// Android `TRANSFER_COMPLETE_DISPLAY_MS` / `TRANSFER_ERROR_DISPLAY_MS`.
    static let completeDismissSeconds: TimeInterval = 4
    static let noticeDismissSeconds: TimeInterval = 5
}

/// 하단 HUD 카드(Android `transferCard`) 내용.
private enum VisionLinkHUDCard: Equatable {
    case transfer(VisionLinkTransferProgress)
    case complete(VisionLinkReceivedFile)
    case clipboard(String)
    case notice(String)

    var isTransfer: Bool {
        if case .transfer = self {
            return true
        }
        return false
    }
}

/// Android `LastReceivedAction`: 최근 수신 항목(파일 또는 클립보드 텍스트).
private enum VisionLinkLastReceived: Equatable {
    case file(VisionLinkReceivedFile)
    case text(String)
}

struct VisionLinkView: View {
    @EnvironmentObject private var appRouter:
        AppRouter
    @EnvironmentObject private var manager:
        VisionLinkManager
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @Environment(\.colorScheme)
    private var colorScheme
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
    @State private var hudCard: VisionLinkHUDCard?
    @State private var hudDismissTask:
        Task<Void, Never>?
    @State private var lastReceived:
        VisionLinkLastReceived?
    @State private var isOrbPulsing = false
    @State private var isLinkDotTravelling = false
    @State private var isNodeBreathing = false

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

            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    if let chipTitle = statusChipTitle {
                        statusChip(chipTitle)
                    }
                    Spacer()
                    Button {
                        isSettingsPresented = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(
                                VisionLinkStyle.hudText
                            )
                            .frame(width: 48, height: 48)
                            .background(
                                VisionLinkStyle.hudChipFill,
                                in: Circle()
                            )
                            .overlay {
                                Circle().strokeBorder(
                                    VisionLinkStyle.hudOutline,
                                    lineWidth: 1
                                )
                            }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        "VisionLink 설정"
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer()

                if let hudCard {
                    hudCardView(hudCard)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 28)
                        .transition(
                            .move(edge: .bottom)
                                .combined(with: .opacity)
                        )
                }
            }
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.2),
            value: hudCard
        )
        // Android `a_vision_link_receiver.xml`: 제목 줄 없는 전체 화면. 뒤로 가기만 남긴다.
        .visionCraftNavigationScreen()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            manager.activate()
        }
        .quickLookPreview($previewURL)
        .sheet(isPresented: $isSettingsPresented) {
            visionLinkSettings
        }
        .alert(
            "기기 등록을 해제할까요?",
            isPresented:
                $isUnregisterConfirmationPresented
        ) {
            Button("등록 해제", role: .destructive) {
                manager.unregisterAndCreateNewCode()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text(
                AppLocalization.format(
                    "%@와의 저장된 연결이 삭제됩니다.",
                    pairedDeviceName
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
                if case .file = lastReceived {
                    lastReceived = nil
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text(
                AppLocalization.string(
                    "이 파일은 iPad와 파일 앱의 VisionLink 폴더에서 삭제됩니다."
                )
            )
        }
        .onChange(of: manager.state) { _, _ in
            announce(
                isConnected
                    ? connectedHeadline.title
                    : connectionTitle + ". " + connectionMessage
            )
        }
        .onChange(of: manager.connectedActivity) {
            _, activity in
            guard let activity else {
                return
            }
            announce(activity.title + ". " + activity.detail)
        }
        .onChange(of: manager.remoteFeatureStatus) {
            _, status in
            guard let status else {
                return
            }
            announce(
                featureStatusTitle(status)
                    + ". " + status.message
            )
        }
        .onChange(of: manager.incomingTransfer) {
            _, progress in
            if let progress {
                let isNewTransfer: Bool
                if case .transfer(let previous) = hudCard,
                   previous.transferID == progress.transferID {
                    isNewTransfer = false
                } else {
                    isNewTransfer = true
                }
                showHUD(.transfer(progress), dismissAfter: nil)
                if isNewTransfer {
                    announce(
                        transferTitle(kind: progress.kind)
                            + ". " + progress.fileName
                    )
                }
            } else if hudCard?.isTransfer == true {
                hudCard = nil
            }
        }
        .onChange(of: manager.lastReceivedFile) {
            _, file in
            guard let file else {
                return
            }
            lastReceived = .file(file)
            showHUD(
                .complete(file),
                dismissAfter:
                    VisionLinkStyle.completeDismissSeconds
            )
            announce(
                AppLocalization.string("수신 완료")
                    + ". "
                    + receivedFileSummary(file)
            )
        }
        .onChange(of: manager.receivedClipboardText) {
            _, text in
            guard let text else {
                return
            }
            lastReceived = .text(text)
            showHUD(
                .clipboard(text),
                dismissAfter:
                    VisionLinkStyle.completeDismissSeconds
            )
            announce(
                AppLocalization.string(
                    "클립보드 텍스트를 받았습니다"
                )
                + ". "
                + AppLocalization.string(
                    "VisionCraft 클립보드에 저장됨"
                )
            )
        }
        .onChange(of: manager.dataTransferMessage) {
            _, message in
            guard let message else {
                return
            }
            showHUD(
                .notice(message),
                dismissAfter:
                    VisionLinkStyle.noticeDismissSeconds
            )
            announce(message)
        }
        .onAppear {
            if let file = manager.lastReceivedFile {
                lastReceived = .file(file)
            } else if let text =
                        manager.receivedClipboardText {
                lastReceived = .text(text)
            }
        }
    }

    // MARK: - 대기 화면 (Android `waitingStage`)

    @ViewBuilder
    private var connectionStage: some View {
        VStack(spacing: 0) {
            waitingOrb

            Text(connectionTitle)
                .visionCraftAndroidText(
                    26,
                    weight: .bold,
                    relativeTo: .title
                )
                .foregroundStyle(
                    VisionCraftUI.primaryText
                )
                .multilineTextAlignment(.center)
                .padding(.top, 18)
                .accessibilityAddTraits(.isHeader)

            Text(connectionMessage)
                .visionCraftAndroidText(16)
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
                        .accessibilityLabel(
                            AppLocalization.format(
                                "연결 코드 %@",
                                code.map(String.init)
                                    .joined(separator: " ")
                            )
                        )
                    if let seconds =
                            manager.remainingSeconds {
                        Text(
                            AppLocalization.format(
                                "만료까지 %lld초",
                                seconds
                            )
                        )
                        .visionCraftAndroidText(
                            14,
                            relativeTo: .footnote
                        )
                        .monospacedDigit()
                        .foregroundStyle(
                            VisionCraftUI.linkWarning
                        )
                    }
                }
                .frame(minWidth: 260)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .visionCraftSurfaceCard()
                .padding(.top, 16)
            }

            if shouldShowNewCodeButton {
                Button("새 코드 생성") {
                    manager.createNewCode()
                }
                .buttonStyle(
                    VisionCraftAndroidButtonStyle(
                        emphasized: true
                    )
                )
                .frame(maxWidth: 320)
                .padding(.top, 16)
            }
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, 48)
    }

    /// Android `VcLinkOrb`: 64pt 파랑 원 + 1.5pt 테두리, 바깥 원은 64→88pt로 커지며 옅어진다(모션 줄이기 존중).
    private var waitingOrb: some View {
        ZStack {
            Circle()
                .fill(VisionLinkStyle.orbFill(colorScheme))
                .overlay {
                    Circle().strokeBorder(
                        VisionLinkStyle.orbOutline,
                        lineWidth: VisionLinkStyle.orbOutlineWidth
                    )
                }
                .frame(
                    width: VisionLinkStyle.orbSize,
                    height: VisionLinkStyle.orbSize
                )
                .scaleEffect(
                    isOrbPulsing
                        ? VisionLinkStyle.orbPulseSize
                            / VisionLinkStyle.orbSize
                        : 1
                )
                .opacity(isOrbPulsing ? 0 : 0.85)

            Circle()
                .fill(VisionLinkStyle.orbFill(colorScheme))
                .overlay {
                    Circle().strokeBorder(
                        VisionLinkStyle.orbOutline,
                        lineWidth: VisionLinkStyle.orbOutlineWidth
                    )
                }
                .frame(
                    width: VisionLinkStyle.orbSize,
                    height: VisionLinkStyle.orbSize
                )

            Image(systemName: "link")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(VisionCraftUI.linkBlue)
        }
        .frame(
            width: VisionLinkStyle.orbPulseSize,
            height: VisionLinkStyle.orbPulseSize
        )
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else {
                return
            }
            withAnimation(
                .easeOut(duration: 1.6)
                    .repeatForever(autoreverses: false)
            ) {
                isOrbPulsing = true
            }
        }
    }

    // MARK: - 연결됨 화면 (Android `connectedIdleStage`)

    private var connectedStage: some View {
        let headline = connectedHeadline
        return VStack(spacing: 0) {
            connectedNodes

            Text(headline.title)
                .visionCraftAndroidText(
                    26,
                    weight: .bold,
                    relativeTo: .title
                )
                .foregroundStyle(
                    VisionCraftUI.primaryText
                )
                .multilineTextAlignment(.center)
                .padding(.top, 10)
                .accessibilityAddTraits(.isHeader)
            if let detail = headline.detail,
               !detail.isEmpty {
                Text(detail)
                    .visionCraftAndroidText(16)
                    .foregroundStyle(
                        VisionCraftUI.secondaryText
                    )
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            }
            if headline.showsCapabilities {
                Text(
                    "카메라 화면공유 · 파일보내기 · 비전크래프트 기능"
                )
                .visionCraftAndroidText(
                    14,
                    relativeTo: .footnote
                )
                .foregroundStyle(VisionCraftUI.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
            }

            if let lastReceived {
                lastReceivedButton(lastReceived)
                    .padding(.top, 18)
            }

            if let file = manager.lastReceivedFile {
                receivedFileActions(file)
                    .padding(.top, 10)
            }

            if let receivedTextOpenError {
                Text(receivedTextOpenError)
                    .visionCraftAndroidText(
                        14,
                        relativeTo: .footnote
                    )
                    .foregroundStyle(VisionCraftUI.error)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, 48)
        .opacity(hudCard == nil ? 1 : 0.42)
        .scaleEffect(hudCard == nil ? 1 : 0.98)
    }

    /// Android `VcLinkNode` 두 개 + 연결선. 선 위를 점이 오가고 노드가 살짝 숨쉰다(모션 줄이기 존중).
    private var connectedNodes: some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            VisionCraftUI.accent,
                            VisionCraftUI.linkSuccess,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 148, height: 2)

            GeometryReader { geometry in
                Circle()
                    .fill(VisionCraftUI.accent)
                    .frame(width: 10, height: 10)
                    .position(
                        x: isLinkDotTravelling
                            ? geometry.size.width - 5
                            : 5,
                        y: geometry.size.height / 2
                    )
            }
            .frame(width: 148, height: 12)
            .opacity(reduceMotion ? 0 : 1)

            HStack {
                connectedNode(
                    "iphone",
                    color: VisionCraftUI.accent,
                    fillOpacity: 0.2
                )
                Spacer()
                connectedNode(
                    "ipad",
                    color: VisionCraftUI.linkSuccess,
                    fillOpacity: 0.16
                )
            }
            .frame(width: 220)
            .scaleEffect(isNodeBreathing ? 1.04 : 1)
        }
        .frame(width: 240, height: 96)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else {
                return
            }
            withAnimation(
                .easeInOut(duration: 1.2)
                    .repeatForever(autoreverses: true)
            ) {
                isLinkDotTravelling = true
            }
            withAnimation(
                .easeInOut(duration: 2.4)
                    .repeatForever(autoreverses: true)
            ) {
                isNodeBreathing = true
            }
        }
    }

    private func connectedNode(
        _ image: String,
        color: Color,
        fillOpacity: Double
    ) -> some View {
        Image(systemName: image)
            .font(.system(size: 25, weight: .semibold))
            .foregroundStyle(color)
            .frame(
                width: VisionLinkStyle.nodeSize,
                height: VisionLinkStyle.nodeSize
            )
            .background(
                color.opacity(fillOpacity),
                in: Circle()
            )
            .overlay {
                Circle().strokeBorder(color, lineWidth: 1)
            }
    }

    /// Android `btnLastReceived`: "최근 수신 · 이름". 사진/파일/텍스트 아이콘, 텍스트는 텍스트뷰로 연다.
    private func lastReceivedButton(
        _ item: VisionLinkLastReceived
    ) -> some View {
        let title: String
        let systemImage: String
        let hint: String
        switch item {
        case .file(let file):
            title = AppLocalization.format(
                "최근 수신 · %@",
                file.fileName
            )
            systemImage = file.kind == "image"
                ? "photo"
                : "doc"
            hint = AppLocalization.string(
                file.kind == "image" ? "사진 열기" : "파일 열기"
            )
        case .text:
            title = AppLocalization.format(
                "최근 수신 · %@",
                AppLocalization.string("클립보드 텍스트")
            )
            systemImage = "doc.text"
            hint = AppLocalization.string("텍스트뷰로 열기")
        }
        return Button {
            switch item {
            case .file(let file):
                previewURL = file.url
            case .text(let text):
                openReceivedText(text)
            }
        } label: {
            HStack(spacing: 12) {
                if isOpeningReceivedText,
                   case .text = item {
                    ProgressView()
                        .tint(VisionCraftUI.accent)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(VisionCraftUI.icon)
                }
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(VisionCraftUI.secondaryText)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(VisionCraftAndroidButtonStyle())
        .disabled(isOpeningReceivedText)
        .accessibilityHint(hint)
    }

    /// 받은 파일 미리보기·내보내기·삭제 줄.
    private func receivedFileActions(
        _ file: VisionLinkReceivedFile
    ) -> some View {
        HStack(spacing: 10) {
            Button {
                previewURL = file.url
            } label: {
                Label("미리보기", systemImage: "eye")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(VisionCraftAndroidButtonStyle())

            ShareLink(
                item: file.url,
                preview: SharePreview(file.fileName)
            ) {
                Label(
                    "내보내기",
                    systemImage: "square.and.arrow.up"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(VisionCraftAndroidButtonStyle())

            Button {
                isFileDeletionConfirmationPresented = true
            } label: {
                Label("삭제", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(VisionCraftAndroidButtonStyle())
        }
    }

    // MARK: - HUD 칩·카드

    /// Android `VcLinkChip`: 영상·바로 읽기 중에만 "연결됨 · …".
    private func statusChip(_ title: String) -> some View {
        HStack(spacing: 9) {
            Circle()
                .fill(VisionCraftUI.linkSuccess)
                .frame(width: 10, height: 10)
            Text(title)
                .visionCraftAndroidText(
                    15,
                    weight: .bold,
                    relativeTo: .subheadline
                )
                .foregroundStyle(VisionLinkStyle.hudText)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(
            VisionLinkStyle.hudChipFill,
            in: RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    VisionLinkStyle.hudOutline,
                    lineWidth: 1
                )
        }
        .accessibilityElement(children: .combine)
    }

    private var statusChipTitle: String? {
        if manager.isCameraShareActive {
            let activity =
                manager.connectedActivity == .liveReading
                ? AppLocalization.string("바로 읽기 처리 중")
                : AppLocalization.string("카메라 화면 공유 중")
            return AppLocalization.string("연결됨")
                + " · " + activity
        }
        if manager.connectedActivity == .liveReading {
            return AppLocalization.string("연결됨")
                + " · "
                + AppLocalization.string("바로 읽기 처리 중")
        }
        return nil
    }

    /// Android `VcLinkHudCard`: 받는 중 / 수신 완료 / 클립보드 / 안내 카드. 탭하면 닫힌다.
    private func hudCardView(
        _ card: VisionLinkHUDCard
    ) -> some View {
        Button {
            guard !card.isTransfer else {
                return
            }
            dismissHUD()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                switch card {
                case .transfer(let progress):
                    hudTitle(
                        transferTitle(kind: progress.kind),
                        systemImage:
                            progress.kind == "image"
                            ? "photo"
                            : "arrow.down.doc"
                    )
                    hudBody(progress.fileName)
                    ProgressView(
                        value: progress.fractionCompleted
                    )
                    .tint(VisionCraftUI.accent)
                    hudMeta(transferProgressText(progress))
                case .complete(let file):
                    hudTitle(
                        AppLocalization.string("수신 완료"),
                        systemImage: "checkmark.circle.fill"
                    )
                    hudBody(receivedFileSummary(file))
                    ProgressView(value: 1)
                        .tint(VisionCraftUI.linkSuccess)
                    hudMeta(
                        AppLocalization.format(
                            "저장 위치 · %@",
                            savedLocationDescription(file)
                        )
                    )
                case .clipboard(let text):
                    hudTitle(
                        AppLocalization.string(
                            "클립보드 텍스트를 받았습니다"
                        ),
                        systemImage: "doc.on.clipboard"
                    )
                    hudBody(
                        text.isEmpty
                            ? AppLocalization.string("(빈 텍스트)")
                            : text
                    )
                    hudMeta(
                        AppLocalization.string(
                            "VisionCraft 클립보드에 저장됨"
                        )
                    )
                case .notice(let message):
                    hudTitle(
                        AppLocalization.string(
                            "연결에 문제가 있습니다"
                        ),
                        systemImage:
                            "exclamationmark.triangle.fill"
                    )
                    hudBody(message)
                }
            }
            .padding(18)
            .frame(maxWidth: 560, alignment: .leading)
            .background(
                VisionLinkStyle.hudCardFill,
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
                .strokeBorder(
                    VisionLinkStyle.hudOutline,
                    lineWidth: 1
                )
            }
            .shadow(
                color: .black.opacity(0.2),
                radius: 16,
                y: 6
            )
            .contentShape(
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(
            card.isTransfer
                ? ""
                : AppLocalization.string("두 번 탭하면 닫힙니다.")
        )
    }

    private func hudTitle(
        _ title: String,
        systemImage: String
    ) -> some View {
        Label {
            Text(title)
                .visionCraftAndroidText(
                    18,
                    weight: .semibold,
                    relativeTo: .headline
                )
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
        }
        .foregroundStyle(VisionLinkStyle.hudText)
    }

    private func hudBody(_ text: String) -> some View {
        Text(text)
            .visionCraftAndroidText(16)
            .foregroundStyle(VisionLinkStyle.hudText)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
    }

    private func hudMeta(_ text: String) -> some View {
        Text(text)
            .visionCraftAndroidText(
                14,
                relativeTo: .footnote
            )
            .monospacedDigit()
            .foregroundStyle(VisionLinkStyle.hudSecondaryText)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private func showHUD(
        _ card: VisionLinkHUDCard,
        dismissAfter seconds: TimeInterval?
    ) {
        hudDismissTask?.cancel()
        hudDismissTask = nil
        hudCard = card
        guard let seconds else {
            return
        }
        hudDismissTask = Task {
            try? await Task.sleep(
                nanoseconds: UInt64(seconds * 1_000_000_000)
            )
            guard !Task.isCancelled else {
                return
            }
            if hudCard == card {
                hudCard = nil
            }
        }
    }

    private func dismissHUD() {
        hudDismissTask?.cancel()
        hudDismissTask = nil
        if case .notice = hudCard {
            manager.clearDataTransferMessage()
        }
        hudCard = nil
    }

    // MARK: - 설정 시트 (Android `VisionLinkSettingsActivity`)

    private var visionLinkSettings: some View {
        NavigationStack {
            List {
                Section {
                    Button(role: .destructive) {
                        isSettingsPresented = false
                        isUnregisterConfirmationPresented =
                            true
                    } label: {
                        HStack(spacing: 12) {
                            Label(
                                AppLocalization.format(
                                    "%@ 기기 등록 해제",
                                    pairedDeviceName
                                ),
                                systemImage: "link.badge.minus"
                            )
                            Spacer()
                            if manager.isUnregistering {
                                ProgressView()
                                    .tint(VisionCraftUI.accent)
                            }
                        }
                        .frame(minHeight: 64)
                    }
                    .disabled(
                        !manager.hasStoredPair
                        || manager.isUnregistering
                    )

                    if let error =
                            manager.unregisterErrorDescription {
                        Text(error)
                            .visionCraftAndroidText(
                                14,
                                relativeTo: .footnote
                            )
                            .foregroundStyle(VisionCraftUI.error)
                    }
                }

                controlsSection
            }
            .visionCraftListScreen()
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
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
                .frame(minHeight: 48)

            case .creatingSession, .reconnecting:
                Button(
                    "취소",
                    systemImage: "xmark"
                ) {
                    manager.disconnect()
                }
                .frame(minHeight: 48)

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
                .frame(minHeight: 48)
            }

            if manager.pairingCode != nil {
                Button(
                    "새 코드 생성",
                    systemImage: "number"
                ) {
                    manager.createNewCode()
                }
                .frame(minHeight: 48)
            }
        }
    }

    // MARK: - 문구

    private var pairedDeviceName: String {
        manager.peerName
            ?? AppLocalization.string("VisionLink")
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

    /// Android `showOfferTimeoutIfWaiting` / `showFirstFrameTimeoutIfWaiting`: 시간 초과는 "연결에 문제가 있습니다".
    private var isMediaTimeoutFailure: Bool {
        guard case .failed = manager.state else {
            return false
        }
        return manager.lastMediaWatchdogTimeout != nil
    }

    private var connectionTitle: String {
        if isMediaTimeoutFailure {
            return AppLocalization.string(
                "연결에 문제가 있습니다"
            )
        }
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
        if isMediaTimeoutFailure {
            switch manager.lastMediaWatchdogTimeout {
            case .offer:
                return AppLocalization.string(
                    "VisionLink 앱은 연결됐지만 연결 협상 메시지가 오지 않았습니다. 앱의 연결 상태를 확인해주세요."
                )
            case .firstFrame:
                return AppLocalization.string(
                    "영상 프레임이 들어오지 않습니다. 카메라 앱의 송출 상태를 확인해주세요."
                )
            case .stalledFrame:
                return AppLocalization.string(
                    "영상 프레임 수신이 멈췄습니다."
                )
            case nil:
                break
            }
        }
        switch manager.state {
        case .waitingForCompanion:
            if manager.pairingCode == nil,
               manager.hasStoredPair {
                return AppLocalization.string(
                    "페어링된 VisionLink에서 전송을 시작해주세요."
                )
            }
            return AppLocalization.string(
                "휴대폰의 VisionLink에서 아래 연결 코드를 입력해주세요."
            )
        case .reconnecting:
            return AppLocalization.string(
                "저장된 VisionLink 연결로 재연결 중입니다."
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

    /// Android `applyConnectedActivity`: 활동이 있으면 제목·설명이 바뀌고 기능 안내 줄은 숨는다.
    private var connectedHeadline:
        (title: String, detail: String?, showsCapabilities: Bool)
    {
        if let progress = manager.incomingTransfer {
            return (
                transferTitle(kind: progress.kind),
                progress.fileName + " · "
                    + transferProgressText(progress),
                false
            )
        }
        if let hudCard {
            switch hudCard {
            case .complete(let file):
                return (
                    AppLocalization.string("수신 완료"),
                    receivedFileSummary(file),
                    false
                )
            case .clipboard:
                return (
                    AppLocalization.string(
                        "클립보드 텍스트를 받았습니다"
                    ),
                    AppLocalization.string(
                        "VisionCraft 클립보드에 저장됨"
                    ),
                    false
                )
            case .notice(let message):
                return (
                    AppLocalization.string(
                        "연결에 문제가 있습니다"
                    ),
                    message,
                    false
                )
            case .transfer:
                break
            }
        }
        if let status = manager.remoteFeatureStatus {
            return (
                featureStatusTitle(status),
                status.message,
                false
            )
        }
        if let activity = manager.connectedActivity {
            return (activity.title, activity.detail, false)
        }
        return (
            AppLocalization.string("연결됨"),
            AppLocalization.string(
                "VisionLink 에서 작업을 시작하세요."
            ),
            true
        )
    }

    /// Android `visionlink_feature_*_title`: 기능별 처리 중 / 완료 / 실패 제목.
    private func featureStatusTitle(
        _ status: VisionLinkRemoteFeatureStatus
    ) -> String {
        let isFailure = status.stage == "error"
            || status.stage == "failed"
        switch status.feature {
        case .ocr:
            if status.isWorking {
                return AppLocalization.string("OCR 처리 중")
            }
            return AppLocalization.string(
                isFailure ? "OCR 처리 실패" : "OCR 완료"
            )
        case .imageAnalysis:
            if status.isWorking {
                return AppLocalization.string("이미지 분석 중")
            }
            return AppLocalization.string(
                isFailure ? "이미지 분석 실패" : "이미지 분석 완료"
            )
        case .aiChat:
            let isAttachment =
                status.stage.hasPrefix("attachment")
            if status.isWorking {
                return AppLocalization.string(
                    isAttachment
                        ? "대화 첨부 처리 중"
                        : "AI 답변 생성 중"
                )
            }
            if isFailure {
                return AppLocalization.string(
                    isAttachment ? "대화 첨부 실패" : "AI 대화 실패"
                )
            }
            return AppLocalization.string(
                isAttachment
                    ? "대화 첨부 준비 완료"
                    : "AI 답변 전송 완료"
            )
        case .translation:
            if status.isWorking {
                return AppLocalization.string("번역 중")
            }
            return AppLocalization.string(
                isFailure ? "번역 실패" : "번역 완료"
            )
        case .liveReading:
            return AppLocalization.string(
                status.isWorking
                    ? "바로 읽기 처리 중"
                    : "바로 읽기 중지됨"
            )
        }
    }

    private func transferTitle(kind: String) -> String {
        AppLocalization.string(
            kind == "image" ? "사진을 받는 중" : "파일을 받는 중"
        )
    }

    /// Android `visionlink_file_progress`: "%d%% · a / b".
    private func transferProgressText(
        _ progress: VisionLinkTransferProgress
    ) -> String {
        AppLocalization.format(
            "%lld%% · %@ / %@",
            Int(
                (progress.fractionCompleted * 100)
                    .rounded(.down)
            ),
            byteCount(progress.receivedBytes),
            byteCount(progress.totalBytes)
        )
    }

    /// Android `visionlink_ui_received_file_summary`: "이름 · 크기".
    private func receivedFileSummary(
        _ file: VisionLinkReceivedFile
    ) -> String {
        file.fileName + " · " + byteCount(file.size)
    }

    private func savedLocationDescription(
        _ file: VisionLinkReceivedFile
    ) -> String {
        let folder = file.url
            .deletingLastPathComponent()
            .lastPathComponent
        return folder.isEmpty
            ? file.url.lastPathComponent
            : folder + "/" + file.url.lastPathComponent
    }

    private func byteCount(
        _ value: Int64
    ) -> String {
        ByteCountFormatter.string(
            fromByteCount: value,
            countStyle: .file
        )
    }

    private func announce(_ text: String) {
        guard UIAccessibility.isVoiceOverRunning else {
            return
        }
        UIAccessibility.post(
            notification: .announcement,
            argument: text
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
}
