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

            controlsSection
        }
        .listStyle(.insetGrouped)
        .visionCraftListScreen()
        .navigationTitle("리모컨 연결")
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
                        ? VisionCraftUI.success
                        : VisionCraftUI.warning
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

            if let reconnectAttempt =
                manager.reconnectAttempt {
                HStack {
                    ProgressView()
                    Text(reconnectAttempt.title)
                }
                .accessibilityElement(children: .combine)

                Button(
                    "지금 다시 연결",
                    systemImage: "bolt.horizontal.circle"
                ) {
                    manager.retryConnectionNow()
                }

                if manager.canReturnToSavedDevice {
                    Button(
                        "저장된 리모컨으로 돌아가기",
                        systemImage: "arrow.uturn.backward.circle"
                    ) {
                        manager.reconnectSavedDevice()
                    }
                }
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
                "다른 리모컨 연결",
                systemImage: "arrow.triangle.swap"
            ) {
                manager.searchForAnotherDevice()
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
        } else if manager.reconnectAttempt == nil {
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
            ForEach(
                manager.strongestDiscoveredDevice.map { [$0] }
                    ?? []
            ) { device in
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
                                AppLocalization.format(
                                    "%@으로 식별",
                                    device
                                        .discoverySource
                                        .title
                                )
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
                    AppLocalization.format(
                        "%@, %@",
                        device.name,
                        device.type.title
                    )
                )
                .accessibilityHint("이 리모컨에 연결합니다.")
            }
        }
    }

    private var controlsSection: some View {
        Section("앱 내부 빠른 메뉴") {
            Label(
                "L1: 메뉴 열기/닫기 · 두 번: 안내 열기",
                systemImage: "rectangle.rightthird.inset.filled"
            )
            Label(
                "4/6: 메뉴 이동 · 2/8: 선택 항목 조절 · 5: 선택 또는 기본값",
                systemImage: "move.3d"
            )
            Label(
                "1: 첫 항목 · 7: 마지막 · 0: 홈",
                systemImage: "list.number"
            )
            Label(
                "별표: 메뉴 닫기 · R3: 문서 읽기/전역 정지",
                systemImage: "speaker.slash"
            )
            Label(
                "돋보기 R1 카메라 모드: 4 닫기 · 5 전환 · 6 토치 · 7 사진 저장 · R2 초점",
                systemImage: "plus.magnifyingglass"
            )
            Label(
                "카메라 모드: 별표 축소 · 0 초기화 · 샵 확대",
                systemImage: "camera.metering.center.weighted"
            )
            Label(
                "돋보기 L2 화면 모드: 4/5/6 색상 · 7/8/9 임계값",
                systemImage: "camera.filters"
            )
            Label(
                "화면 모드: 별표/0/샵 미리보기 밝기 · R2 반전",
                systemImage: "sun.max"
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
                "모드 버튼 두 번: 현재 화면의 키 안내",
                systemImage: "questionmark.circle"
            )
            Label(
                "L4/R4: Android 전역 화면 이동은 iPadOS에서 제한",
                systemImage: "hand.raised"
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
            Label(
                "TXT/PDF: L2 색상 · 4/5/6 이전/원본/다음",
                systemImage: "paintpalette"
            )
            Label(
                "TXT/PDF 색상: R2 반전 · L3 문서 조작",
                systemImage: "circle.lefthalf.filled"
            )
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
}
