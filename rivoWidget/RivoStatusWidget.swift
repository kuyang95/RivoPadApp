import SwiftUI
import WidgetKit
import AppIntents

private func widgetLocalized(
    _ key: String
) -> String {
    NSLocalizedString(
        key,
        comment: ""
    )
}

private func widgetLocalizedFormat(
    _ key: String,
    _ arguments: CVarArg...
) -> String {
    String(
        format: widgetLocalized(key),
        locale: Locale.current,
        arguments: arguments
    )
}

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
        "group.net.rivo.visioncraft"
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
                widgetLocalizedFormat(
                    "Rivo 리모컨 최근 상태, %@",
                    statusTitle
                )
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
                Text(
                    LocalizedStringKey(title)
                )
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
        .accessibilityLabel(
            Text(
                LocalizedStringKey(title)
            )
        )
        .accessibilityHint(
            widgetLocalizedFormat(
                "VisionCraft %@ 화면을 엽니다.",
                widgetLocalized(title)
            )
        )
    }

    private var statusTitle: String {
        guard let snapshot =
                entry.snapshot else {
            return widgetLocalized(
                "최근 상태 없음"
            )
        }
        switch snapshot.kind {
        case .connected:
            guard let deviceName =
                    snapshot.deviceName else {
                return widgetLocalized(
                    "연결됨"
                )
            }
            return widgetLocalizedFormat(
                "%@ 연결됨",
                deviceName
            )
        case .connecting:
            return widgetLocalized("연결 중")
        case .notConnected:
            return widgetLocalized("연결 안 됨")
        case .unavailable:
            return widgetLocalized(
                "사용할 수 없음"
            )
        case .failed:
            return widgetLocalized("연결 실패")
        }
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

enum VisionCraftWidgetShortcut:
    String,
    CaseIterable,
    AppEnum
{
    case newAIChat
    case chatHistory
    case documentScanner
    case liveTextReader
    case magnifier
    case voiceAction
    case documents
    case reader
    case camera

    static var typeDisplayRepresentation:
        TypeDisplayRepresentation {
        "열 기능"
    }

    static var caseDisplayRepresentations:
        [VisionCraftWidgetShortcut:
            DisplayRepresentation] {
        [
            .newAIChat:
                "새 AI 대화",
            .chatHistory:
                "AI 대화 기록",
            .documentScanner:
                "문서 스캔",
            .liveTextReader:
                "실시간 글자 읽기",
            .magnifier:
                "카메라 돋보기",
            .voiceAction:
                "음성 명령",
            .documents:
                "문서 열기",
            .reader:
                "독서",
            .camera:
                "카메라 도구",
        ]
    }

    var title: LocalizedStringKey {
        switch self {
        case .newAIChat:
            return "새 AI 대화"
        case .chatHistory:
            return "AI 대화 기록"
        case .documentScanner:
            return "문서 스캔"
        case .liveTextReader:
            return "실시간 글자 읽기"
        case .magnifier:
            return "카메라 돋보기"
        case .voiceAction:
            return "음성 명령"
        case .documents:
            return "문서 열기"
        case .reader:
            return "독서"
        case .camera:
            return "카메라 도구"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .newAIChat:
            return widgetLocalized(
                "새 AI 대화"
            )
        case .chatHistory:
            return widgetLocalized(
                "AI 대화 기록"
            )
        case .documentScanner:
            return widgetLocalized(
                "문서 스캔"
            )
        case .liveTextReader:
            return widgetLocalized(
                "실시간 글자 읽기"
            )
        case .magnifier:
            return widgetLocalized(
                "카메라 돋보기"
            )
        case .voiceAction:
            return widgetLocalized(
                "음성 명령"
            )
        case .documents:
            return widgetLocalized(
                "문서 열기"
            )
        case .reader:
            return widgetLocalized(
                "독서"
            )
        case .camera:
            return widgetLocalized(
                "카메라 도구"
            )
        }
    }

    var systemImage: String {
        switch self {
        case .newAIChat:
            return "plus.bubble.fill"
        case .chatHistory:
            return "clock.arrow.circlepath"
        case .documentScanner:
            return "doc.viewfinder"
        case .liveTextReader:
            return "text.viewfinder"
        case .magnifier:
            return "plus.magnifyingglass"
        case .voiceAction:
            return "waveform"
        case .documents:
            return "folder"
        case .reader:
            return "book"
        case .camera:
            return "camera"
        }
    }

    var deepLinkPath: String {
        switch self {
        case .newAIChat:
            return "ai-new"
        case .chatHistory:
            return "ai-history"
        case .documentScanner:
            return "scanner"
        case .liveTextReader:
            return "live-text"
        case .magnifier:
            return "magnifier"
        case .voiceAction:
            return "voice-action"
        case .documents:
            return "files"
        case .reader:
            return "reader"
        case .camera:
            return "camera"
        }
    }

    var deepLinkURL: URL {
        URL(
            string:
                "rivopad://open/"
                + deepLinkPath
        )!
    }
}

struct VisionCraftShortcutConfiguration:
    WidgetConfigurationIntent
{
    static var title:
        LocalizedStringResource =
        "VisionCraft 빠른 실행"
    static var description =
        IntentDescription(
            "홈 화면에서 자주 쓰는 기능 하나를 바로 엽니다."
        )

    @Parameter(
        title: "열 기능",
        default: .newAIChat
    )
    var shortcut:
        VisionCraftWidgetShortcut
}

private struct
    VisionCraftShortcutEntry:
        TimelineEntry
{
    let date: Date
    let shortcut:
        VisionCraftWidgetShortcut
}

private struct
    VisionCraftShortcutProvider:
        AppIntentTimelineProvider
{
    func placeholder(
        in context: Context
    ) -> VisionCraftShortcutEntry {
        VisionCraftShortcutEntry(
            date: Date(),
            shortcut: .newAIChat
        )
    }

    func snapshot(
        for configuration:
            VisionCraftShortcutConfiguration,
        in context: Context
    ) async
        -> VisionCraftShortcutEntry
    {
        entry(for: configuration)
    }

    func timeline(
        for configuration:
            VisionCraftShortcutConfiguration,
        in context: Context
    ) async
        -> Timeline<
            VisionCraftShortcutEntry
        >
    {
        Timeline(
            entries: [
                entry(for: configuration)
            ],
            policy: .never
        )
    }

    private func entry(
        for configuration:
            VisionCraftShortcutConfiguration
    ) -> VisionCraftShortcutEntry {
        VisionCraftShortcutEntry(
            date: Date(),
            shortcut:
                configuration.shortcut
        )
    }
}

private struct
    VisionCraftShortcutWidgetView:
        View
{
    let entry:
        VisionCraftShortcutEntry

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            Image(
                systemName:
                    entry.shortcut
                    .systemImage
            )
            .font(
                .system(
                    size: 34,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                Color.accentColor
            )
            .accessibilityHidden(true)

            Spacer(minLength: 0)

            Text(entry.shortcut.title)
                .font(.headline)
                .lineLimit(2)

            Text("VisionCraft에서 열기")
                .font(.caption)
                .foregroundStyle(
                    .secondary
                )
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .containerBackground(
            for: .widget
        ) {
            Color(
                uiColor:
                    .secondarySystemBackground
            )
        }
        .widgetURL(
            entry.shortcut.deepLinkURL
        )
        .accessibilityElement(
            children: .combine
        )
        .accessibilityLabel(
            entry.shortcut
                .accessibilityTitle
        )
        .accessibilityHint(
            widgetLocalizedFormat(
                "VisionCraft %@ 화면을 엽니다.",
                entry.shortcut
                    .accessibilityTitle
            )
        )
    }
}

struct VisionCraftShortcutWidget:
    Widget
{
    let kind =
        "VisionCraftShortcutWidget"

    var body:
        some WidgetConfiguration
    {
        AppIntentConfiguration(
            kind: kind,
            intent:
                VisionCraftShortcutConfiguration
                .self,
            provider:
                VisionCraftShortcutProvider()
        ) { entry in
            VisionCraftShortcutWidgetView(
                entry: entry
            )
        }
        .configurationDisplayName(
            "VisionCraft 빠른 실행"
        )
        .description(
            "새 AI 대화, 대화 기록, 스캔, 실시간 읽기, 돋보기, 음성 명령, 문서와 독서를 바로 엽니다."
        )
        .supportedFamilies([
            .systemSmall
        ])
    }
}

struct VisionCraftControlConfiguration:
    ControlConfigurationIntent
{
    static let title:
        LocalizedStringResource =
        "VisionCraft 제어 센터"
    static let description =
        IntentDescription(
            "제어 센터와 잠금 화면에서 자주 쓰는 기능 하나를 바로 엽니다."
        )

    @Parameter(
        title: "열 기능",
        default: .newAIChat
    )
    var shortcut:
        VisionCraftWidgetShortcut
}

struct VisionCraftQuickLaunchControl:
    ControlWidget
{
    static let kind =
        "VisionCraftQuickLaunchControl"

    var body:
        some ControlWidgetConfiguration
    {
        AppIntentControlConfiguration(
            kind: Self.kind,
            intent:
                VisionCraftControlConfiguration
                .self
        ) { configuration in
            ControlWidgetButton(
                action: OpenURLIntent(
                    configuration.shortcut
                        .deepLinkURL
                )
            ) {
                Label(
                    configuration.shortcut.title,
                    systemImage:
                        configuration.shortcut
                        .systemImage
                )
            }
        }
        .displayName(
            "VisionCraft 빠른 실행"
        )
        .description(
            "제어 센터나 잠금 화면에서 선택한 VisionCraft 기능을 엽니다."
        )
    }
}

private struct LocalAIUsageWidgetSnapshot:
    Codable
{
    let schemaVersion: Int
    let dayIdentifier: String
    let completedRequests: Int
    let failedRequests: Int
    let cancelledRequests: Int
    let generatedCharacters: Int
    let inferenceSeconds: Double
    let updatedAt: Date

    var totalRequests: Int {
        completedRequests
            + failedRequests
            + cancelledRequests
    }
}

private struct LocalAIUsageEntry:
    TimelineEntry
{
    let date: Date
    let snapshot:
        LocalAIUsageWidgetSnapshot?
}

private struct LocalAIUsageProvider:
    TimelineProvider
{
    private static let suiteName =
        "group.net.rivo.visioncraft"
    private static let snapshotKey =
        "localAI.usage.today.v1"

    func placeholder(
        in context: Context
    ) -> LocalAIUsageEntry {
        LocalAIUsageEntry(
            date: Date(),
            snapshot:
                LocalAIUsageWidgetSnapshot(
                    schemaVersion: 1,
                    dayIdentifier:
                        Self.dayIdentifier(
                            for: Date()
                        ),
                    completedRequests: 4,
                    failedRequests: 0,
                    cancelledRequests: 1,
                    generatedCharacters:
                        2_840,
                    inferenceSeconds: 52,
                    updatedAt: Date()
                )
        )
    }

    func getSnapshot(
        in context: Context,
        completion:
            @escaping (LocalAIUsageEntry)
            -> Void
    ) {
        completion(
            context.isPreview
                ? placeholder(in: context)
                : entry(at: Date())
        )
    }

    func getTimeline(
        in context: Context,
        completion:
            @escaping (
                Timeline<
                    LocalAIUsageEntry
                >
            ) -> Void
    ) {
        let now = Date()
        let calendar = Calendar.current
        let nextMidnight =
            calendar.date(
                byAdding: .day,
                value: 1,
                to:
                    calendar
                    .startOfDay(
                        for: now
                    )
            )
            ?? now.addingTimeInterval(
                86_400
            )
        completion(
            Timeline(
                entries: [entry(at: now)],
                policy:
                    .after(
                        nextMidnight
                        .addingTimeInterval(
                            60
                        )
                    )
            )
        )
    }

    private func entry(
        at date: Date
    ) -> LocalAIUsageEntry {
        LocalAIUsageEntry(
            date: date,
            snapshot:
                loadSnapshot(
                    at: date
                )
        )
    }

    private func loadSnapshot(
        at date: Date
    ) -> LocalAIUsageWidgetSnapshot? {
        guard let defaults =
                UserDefaults(
                    suiteName:
                        Self.suiteName
                ),
              let data =
                defaults.data(
                    forKey:
                        Self.snapshotKey
                ) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy =
            .iso8601
        guard let snapshot =
                try? decoder.decode(
                    LocalAIUsageWidgetSnapshot
                        .self,
                    from: data
                ),
              snapshot.schemaVersion == 1,
              snapshot.dayIdentifier
                == Self.dayIdentifier(
                    for: date
                ),
              snapshot.completedRequests
                >= 0,
              snapshot.completedRequests
                <= 1_000_000,
              snapshot.failedRequests >= 0,
              snapshot.failedRequests
                <= 1_000_000,
              snapshot.cancelledRequests
                >= 0,
              snapshot.cancelledRequests
                <= 1_000_000,
              snapshot.generatedCharacters
                >= 0,
              snapshot.generatedCharacters
                <= 1_000_000_000,
              snapshot.inferenceSeconds
                .isFinite,
              snapshot.inferenceSeconds
                >= 0,
              snapshot.inferenceSeconds
                <= 86_400 else {
            return nil
        }
        return snapshot
    }

    private static func dayIdentifier(
        for date: Date
    ) -> String {
        let components =
            Calendar.current
            .dateComponents(
                [
                    .year,
                    .month,
                    .day,
                ],
                from: date
            )
        return String(
            format:
                "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

private struct
    LocalAIUsageWidgetView:
        View
{
    let entry: LocalAIUsageEntry

    private let newChatURL =
        URL(
            string:
                "rivopad://open/ai-new"
        )!

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 7
        ) {
            HStack {
                Image(
                    systemName:
                        "apple.intelligence"
                )
                .font(.title2)
                .foregroundStyle(.indigo)
                .accessibilityHidden(true)
                Spacer()
                Text("일일 제한 없음")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(
                        .indigo
                    )
            }

            Spacer(minLength: 0)

            Text("오늘 M4 로컬 AI")
                .font(.caption)
                .foregroundStyle(
                    .secondary
                )
            Text(
                widgetLocalizedFormat(
                    "%ld회 완료",
                    completedRequests
                )
            )
            .font(.title2)
            .fontWeight(.bold)
            .lineLimit(1)
            Text(activityDetail)
                .font(.caption2)
                .foregroundStyle(
                    .secondary
                )
                .lineLimit(2)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .containerBackground(
            for: .widget
        ) {
            Color(
                uiColor:
                    .secondarySystemBackground
            )
        }
        .widgetURL(newChatURL)
        .accessibilityElement(
            children: .combine
        )
        .accessibilityLabel(
            widgetLocalizedFormat(
                "오늘 M4 로컬 AI, %ld회 완료, %@, 일일 제한 없음",
                completedRequests,
                activityDetail
            )
        )
        .accessibilityHint(
            "새 AI 대화를 엽니다."
        )
    }

    private var completedRequests:
        Int
    {
        entry.snapshot?
            .completedRequests
            ?? 0
    }

    private var activityDetail:
        String
    {
        guard let snapshot =
                entry.snapshot,
              snapshot.totalRequests > 0
        else {
            return widgetLocalized(
                "오늘 활동 없음"
            )
        }
        if snapshot.failedRequests > 0
            || snapshot.cancelledRequests
                > 0 {
            return widgetLocalizedFormat(
                "%ld자 생성 · %@\n실패 %ld · 취소 %ld",
                snapshot.generatedCharacters,
                durationText(
                    snapshot
                    .inferenceSeconds
                ),
                snapshot.failedRequests,
                snapshot
                    .cancelledRequests
            )
        }
        return widgetLocalizedFormat(
            "%ld자 생성 · %@",
            snapshot.generatedCharacters,
            durationText(
                snapshot.inferenceSeconds
            )
        )
    }

    private func durationText(
        _ seconds: Double
    ) -> String {
        if seconds < 60 {
            return widgetLocalizedFormat(
                "%ld초 처리",
                Int(seconds.rounded())
            )
        }
        return widgetLocalizedFormat(
            "%ld분 처리",
            Int(
                (seconds / 60)
                    .rounded()
            )
        )
    }
}

struct LocalAIUsageWidget: Widget {
    let kind = "LocalAIUsageWidget"

    var body:
        some WidgetConfiguration
    {
        StaticConfiguration(
            kind: kind,
            provider:
                LocalAIUsageProvider()
        ) { entry in
            LocalAIUsageWidgetView(
                entry: entry
            )
        }
        .configurationDisplayName(
            "오늘 M4 로컬 AI 활동"
        )
        .description(
            "로컬 AI의 오늘 완료 응답과 처리량을 표시합니다."
        )
        .supportedFamilies([
            .systemSmall
        ])
    }
}

@main
struct RivoWidgetBundle: WidgetBundle {
    var body: some Widget {
        RivoStatusWidget()
        VisionCraftShortcutWidget()
        LocalAIUsageWidget()
        VisionCraftQuickLaunchControl()
    }
}
