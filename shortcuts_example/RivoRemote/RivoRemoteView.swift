import SwiftUI

struct RivoRemoteView: View {
    @EnvironmentObject private var manager: RivoRemoteManager

    var body: some View {
        List {
            statusSection

            if !manager.discoveredDevices.isEmpty,
               !manager.state.isReady {
                discoveredDevicesSection
            }

            connectionDiagnosticsSection
            controlsSection
            eventSection
            limitationsSection
        }
        .navigationTitle("Rivo 리모컨")
        .task {
            manager.activateAndScan()
        }
    }

    private var statusSection: some View {
        Section("연결 상태") {
            HStack(spacing: 18) {
                Image(
                    systemName: manager.state.isReady
                        ? "dot.radiowaves.left.and.right"
                        : "antenna.radiowaves.left.and.right"
                )
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(
                    manager.state.isReady
                        ? Color.green
                        : Color.orange
                )
                .frame(width: 54)

                VStack(alignment: .leading, spacing: 6) {
                    Text(manager.state.title)
                        .font(.title3.bold())
                    if let type = manager.connectedDeviceType {
                        Text(type.title)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)

            if manager.state.isReady {
                HStack(alignment: .firstTextBaseline) {
                    Label(
                        manager.timeSyncState.title,
                        systemImage: "clock"
                    )
                    Spacer()
                    if case .sent(let date) =
                        manager.timeSyncState {
                        Text(date, style: .time)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            stateActions
        }
    }

    @ViewBuilder
    private var stateActions: some View {
        if manager.state.isReady {
            Button(
                "시간 다시 맞추기",
                systemImage: "clock.arrow.circlepath"
            ) {
                manager.syncTime()
            }
            .disabled(
                manager.timeSyncState == .sending
            )

            Button(
                "연결 끊기",
                systemImage: "personalhotspot.slash"
            ) {
                manager.disconnect()
            }

            Button(
                "이 리모컨 지우기",
                systemImage: "trash",
                role: .destructive
            ) {
                manager.forgetDevice()
            }
        } else if manager.state == .scanning {
            HStack {
                ProgressView()
                Text("Rivo Three와 Mini를 찾고 있습니다.")
            }
            Button("검색 중지", systemImage: "stop.fill") {
                manager.stopScanning()
            }
        } else {
            Button(
                "Rivo 리모컨 검색",
                systemImage: "antenna.radiowaves.left.and.right"
            ) {
                manager.startScanning()
            }
            .font(.headline)
        }
    }

    private var discoveredDevicesSection: some View {
        Section("발견한 리모컨") {
            ForEach(manager.discoveredDevices) { device in
                Button {
                    manager.connect(to: device)
                } label: {
                    HStack {
                        VStack(
                            alignment: .leading,
                            spacing: 5
                        ) {
                            Text(device.name)
                                .font(.headline)
                            Text(device.type.title)
                                .foregroundStyle(.secondary)
                            Text(
                                "\(device.discoverySource.title)으로 식별"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 5) {
                            Image(
                                systemName:
                                    "wifi",
                                variableValue: signalValue(
                                    for: device.signalStrength
                                )
                            )
                            Text(device.signalDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .accessibilityLabel(
                    "\(device.name), \(device.type.title)"
                )
                .accessibilityHint("이 리모컨에 연결합니다.")
            }
        }
    }

    @ViewBuilder
    private var connectionDiagnosticsSection:
        some View
    {
        Section {
            if manager.connectionDiagnostics.isEmpty {
                Text(
                    "검색하거나 연결하면 단계별 기록이 여기에 표시됩니다."
                )
                .foregroundStyle(.secondary)
            } else {
                ForEach(
                    manager.connectionDiagnostics.prefix(12)
                ) { diagnostic in
                    HStack(alignment: .top, spacing: 12) {
                        Image(
                            systemName: diagnosticIcon(
                                for: diagnostic.level
                            )
                        )
                        .foregroundStyle(
                            diagnosticColor(
                                for: diagnostic.level
                            )
                        )
                        .frame(width: 22)

                        VStack(
                            alignment: .leading,
                            spacing: 4
                        ) {
                            HStack {
                                Text(diagnostic.stage.title)
                                    .font(.headline)
                                Text(diagnostic.level.title)
                                    .font(.caption.bold())
                                    .foregroundStyle(
                                        diagnosticColor(
                                            for:
                                                diagnostic.level
                                        )
                                    )
                                Spacer()
                                Text(
                                    diagnostic.recordedAt,
                                    style: .time
                                )
                                .font(
                                    .caption
                                        .monospacedDigit()
                                )
                                .foregroundStyle(.secondary)
                            }
                            Text(diagnostic.message)
                                .font(.subheadline)
                        }
                    }
                    .accessibilityElement(
                        children: .combine
                    )
                }
            }
        } header: {
            HStack {
                Text("연결 진단")
                Spacer()
                if !manager.connectionDiagnostics.isEmpty {
                    Button("지우기") {
                        manager
                            .clearConnectionDiagnostics()
                    }
                    .textCase(nil)
                }
            }
        } footer: {
            Text(
                "최근 80개 기록은 앱을 다시 열어도 이 iPad에 남습니다."
            )
        }
    }

    private var controlsSection: some View {
        Section("앱 내부 빠른 메뉴") {
            Label(
                "L1: 메뉴 열기/닫기 · 두 번: 안내 열기",
                systemImage: "rectangle.rightthird.inset.filled"
            )
            Label(
                "2/4: 이전 · 6/8: 다음 · 5: 선택",
                systemImage: "move.3d"
            )
            Label(
                "1: 첫 항목 · 7: 마지막 · 0: 홈",
                systemImage: "list.number"
            )
            Label(
                "별표: 메뉴 닫기 · R3: 음성 읽기 정지",
                systemImage: "speaker.slash"
            )
            Label(
                "돋보기: 4 닫기 · 5 전환 · 6 토치 · 7 읽기",
                systemImage: "plus.magnifyingglass"
            )
            Label(
                "돋보기: 별표 축소 · 0 초기화 · 샵 확대",
                systemImage: "camera.metering.center.weighted"
            )
            Label(
                "실시간 읽기: 7 일시정지와 재개",
                systemImage: "text.viewfinder"
            )
            Label(
                "문서 스캔: 4 닫기 · 7 수동 촬영",
                systemImage: "doc.viewfinder"
            )
            Label(
                "독서: 4 이전 · 5 재생 · 6 다음",
                systemImage: "book"
            )
            Label(
                "독서: 2 이전 단위 · 8 다음 단위",
                systemImage: "arrow.left.arrow.right"
            )
            Label(
                "TXT/PDF: 1 처음 · 2/8 줄 · 3/9 페이지 · 7 끝",
                systemImage: "doc.text"
            )
            Label(
                "TXT/PDF: 4/5/6 글자 · 별표/0/샵 줄 간격",
                systemImage: "textformat.size"
            )
        }
    }

    @ViewBuilder
    private var eventSection: some View {
        Section {
            if manager.recentEvents.isEmpty {
                ContentUnavailableView(
                    "아직 버튼 입력이 없습니다",
                    systemImage: "button.programmable",
                    description: Text(
                        "연결 후 Rivo 버튼을 누르면 "
                            + "해석 결과와 원본 패킷이 표시됩니다."
                    )
                )
            } else {
                ForEach(manager.recentEvents.prefix(12)) {
                    event in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(event.input.summary)
                                .font(.headline)
                            Spacer()
                            Text(
                                event.receivedAt,
                                style: .time
                            )
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }
                        Text(event.packetHex)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } header: {
            HStack {
                Text("버튼 진단")
                Spacer()
                if !manager.recentEvents.isEmpty
                    || manager.invalidPacketCount > 0 {
                    Button("지우기") {
                        manager.clearEventHistory()
                    }
                    .textCase(nil)
                }
            }
        } footer: {
            if manager.invalidPacketCount > 0 {
                Text(
                    "해석하지 못한 패킷 "
                        + "\(manager.invalidPacketCount)개"
                )
            }
        }
    }

    private var limitationsSection: some View {
        Section("iPad 동작 범위") {
            Text(
                "이 단계에서는 VisionCraft가 열려 있을 때 "
                    + "Rivo 버튼으로 앱 내부 기능을 조작합니다. "
                    + "다른 앱의 터치·홈·VoiceOver를 제어하지는 "
                    + "않습니다."
            )
            .foregroundStyle(.secondary)
        }
    }

    private func signalValue(for rssi: Int) -> Double {
        min(
            max(
                Double(rssi + 100) / 55,
                0
            ),
            1
        )
    }

    private func diagnosticIcon(
        for level: RivoConnectionDiagnosticLevel
    ) -> String {
        switch level {
        case .info:
            return "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .failure:
            return "xmark.octagon.fill"
        }
    }

    private func diagnosticColor(
        for level: RivoConnectionDiagnosticLevel
    ) -> Color {
        switch level {
        case .info:
            return .blue
        case .success:
            return .green
        case .warning:
            return .orange
        case .failure:
            return .red
        }
    }
}
