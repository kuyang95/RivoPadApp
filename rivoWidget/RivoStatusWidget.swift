import SwiftUI
import WidgetKit

private enum WidgetConnectionKind:
    String,
    Codable
{
    case notConnected
    case connecting
    case connected
    case unavailable
    case failed
}

private struct WidgetSnapshot: Codable {
    let schemaVersion: Int
    let kind: WidgetConnectionKind
    let title: String
    let deviceName: String?
    let updatedAt: Date
}

private struct RivoStatusEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

private struct RivoStatusProvider: TimelineProvider {
    private static let suiteName =
        "group.com.rivo.shortcuts.example"
    private static let snapshotKey =
        "rivo.widget.snapshot.v1"

    func placeholder(
        in context: Context
    ) -> RivoStatusEntry {
        RivoStatusEntry(
            date: Date(),
            snapshot: WidgetSnapshot(
                schemaVersion: 1,
                kind: .connected,
                title: "Rivo Three 연결됨",
                deviceName: "Rivo Three",
                updatedAt: Date()
            )
        )
    }

    func getSnapshot(
        in context: Context,
        completion:
            @escaping (RivoStatusEntry) -> Void
    ) {
        completion(
            RivoStatusEntry(
                date: Date(),
                snapshot:
                    context.isPreview
                    ? placeholder(in: context)
                        .snapshot
                    : loadSnapshot()
            )
        )
    }

    func getTimeline(
        in context: Context,
        completion:
            @escaping (Timeline<RivoStatusEntry>)
            -> Void
    ) {
        let now = Date()
        let entry = RivoStatusEntry(
            date: now,
            snapshot: loadSnapshot()
        )
        let nextRefresh = Calendar.current
            .date(
                byAdding: .minute,
                value: 15,
                to: now
            )
            ?? now.addingTimeInterval(900)
        completion(
            Timeline(
                entries: [entry],
                policy: .after(nextRefresh)
            )
        )
    }

    private func loadSnapshot() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(
            suiteName: Self.suiteName
        ),
        let data = defaults.data(
            forKey: Self.snapshotKey
        ) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(
            WidgetSnapshot.self,
            from: data
        ),
        snapshot.schemaVersion == 1 else {
            return nil
        }
        return snapshot
    }
}

private struct RivoStatusWidgetView: View {
    @Environment(\.widgetFamily)
    private var family

    let entry: RivoStatusEntry

    private let statusURL =
        URL(string: "rivopad://open/rivo")!

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            Link(destination: statusURL) {
                HStack(
                    alignment: .top,
                    spacing: 10
                ) {
                    Image(
                        systemName:
                            statusSymbolName
                    )
                    .font(.title2)
                    .foregroundStyle(
                        statusColor
                    )
                    .accessibilityHidden(true)

                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text("Rivo 리모컨")
                            .font(.headline)
                            .foregroundStyle(
                                .primary
                            )
                        Text(statusTitle)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(
                                .primary
                            )
                            .lineLimit(2)
                        if let updatedAt =
                                entry.snapshot?
                                .updatedAt {
                            HStack(spacing: 3) {
                                Text("마지막 확인")
                                Text(
                                    updatedAt,
                                    style: .relative
                                )
                            }
                            .font(.caption2)
                            .foregroundStyle(
                                .secondary
                            )
                        } else {
                            Text(
                                "앱을 열어 상태를 확인하세요."
                            )
                            .font(.caption2)
                            .foregroundStyle(
                                .secondary
                            )
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .accessibilityLabel(
                "Rivo 리모컨 최근 상태, "
                + statusTitle
            )
            .accessibilityHint(
                "VisionCraft의 Rivo 연결 화면을 엽니다."
            )

            if family == .systemMedium {
                Divider()
                shortcutLinks
            }
        }
        .containerBackground(
            for: .widget
        ) {
            Color(
                uiColor:
                    .secondarySystemBackground
            )
        }
        .widgetURL(
            family == .systemSmall
                ? statusURL
                : nil
        )
    }

    private var shortcutLinks: some View {
        HStack(spacing: 8) {
            shortcut(
                title: "AI",
                symbol:
                    "bubble.left.and.bubble.right",
                path: "ai"
            )
            shortcut(
                title: "스캔",
                symbol: "doc.viewfinder",
                path: "scanner"
            )
            shortcut(
                title: "카메라",
                symbol: "camera",
                path: "camera"
            )
            shortcut(
                title: "독서",
                symbol: "book",
                path: "reader"
            )
        }
    }

    private func shortcut(
        title: String,
        symbol: String,
        path: String
    ) -> some View {
        Link(
            destination: URL(
                string:
                    "rivopad://open/" + path
            )!
        ) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.body)
                Text(title)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                Color.accentColor
                    .opacity(0.12)
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 10,
                    style: .continuous
                )
            )
        }
        .accessibilityLabel(title)
        .accessibilityHint(
            "VisionCraft \(title) 화면을 엽니다."
        )
    }

    private var statusTitle: String {
        entry.snapshot?.title
            ?? "최근 상태 없음"
    }

    private var statusSymbolName: String {
        switch entry.snapshot?.kind {
        case .connected:
            return "checkmark.circle.fill"
        case .connecting:
            return "arrow.trianglehead.2.clockwise"
        case .unavailable,
             .failed:
            return "exclamationmark.circle.fill"
        case .notConnected:
            return "circle"
        case nil:
            return "questionmark.circle"
        }
    }

    private var statusColor: Color {
        switch entry.snapshot?.kind {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .unavailable,
             .failed:
            return .red
        case .notConnected,
             nil:
            return .secondary
        }
    }
}

struct RivoStatusWidget: Widget {
    let kind = "RivoStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: RivoStatusProvider()
        ) { entry in
            RivoStatusWidgetView(
                entry: entry
            )
        }
        .configurationDisplayName(
            "Rivo 상태와 바로가기"
        )
        .description(
            "마지막 Rivo 연결 상태를 보고 VisionCraft 기능을 빠르게 엽니다."
        )
        .supportedFamilies([
            .systemSmall,
            .systemMedium
        ])
    }
}

@main
struct RivoWidgetBundle: WidgetBundle {
    var body: some Widget {
        RivoStatusWidget()
    }
}
