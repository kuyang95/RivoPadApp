import Darwin
import Foundation
import MetricKit
import SwiftUI
import UniformTypeIdentifiers
import UIKit

nonisolated struct LocalDiagnosticAppSnapshot:
    Equatable,
    Sendable
{
    let version: String
    let build: String
    let bundleIdentifier: String
}

nonisolated struct LocalDiagnosticDeviceSnapshot:
    Equatable,
    Sendable
{
    let hardwareIdentifier: String
    let systemName: String
    let systemVersion: String
    let memoryTier: String
    let physicalMemoryBytes: UInt64
    let availableAppMemoryBytes: UInt64
    let metalWorkingSetBytes: UInt64?
    let availableStorageBytes: UInt64?
    let thermalLevel: String
    let isLowPowerModeEnabled: Bool
}

nonisolated struct LocalDiagnosticSettingsSnapshot:
    Equatable,
    Sendable
{
    let appLanguage: String
    let appFontKey: String
    let soundEffectsEnabled: Bool
    let voiceFeedbackEnabled: Bool
    let automaticCaptureEnabled: Bool
    let curvedPageCorrectionEnabled: Bool
    let colorEnhancementEnabled: Bool
    let ocrCorrectionEnabled: Bool
    let webSearchEnabled: Bool
    let webSearchAPIKeyStored: Bool
}

nonisolated struct LocalDiagnosticReportSource:
    Sendable
{
    let generatedAt: Date
    let app: LocalDiagnosticAppSnapshot
    let device: LocalDiagnosticDeviceSnapshot
    let settings:
        LocalDiagnosticSettingsSnapshot
    let metricPayloads: [Data]
    let diagnosticPayloads: [Data]
}

nonisolated struct LocalDiagnosticSummary:
    Equatable,
    Sendable
{
    let app: LocalDiagnosticAppSnapshot
    let device: LocalDiagnosticDeviceSnapshot
    let metricPayloadCount: Int
    let diagnosticPayloadCount: Int
}

nonisolated enum LocalMetricKitSnapshot {
    static let maximumPayloadCount = 4

    static func metricPayloads() -> [Data] {
        Array(
            MXMetricManager.shared
                .pastPayloads
                .suffix(maximumPayloadCount)
        ).map {
            $0.jsonRepresentation()
        }
    }

    static func diagnosticPayloads()
        -> [Data]
    {
        Array(
            MXMetricManager.shared
                .pastDiagnosticPayloads
                .suffix(maximumPayloadCount)
        ).map {
            $0.jsonRepresentation()
        }
    }
}

nonisolated enum LocalDiagnosticReportBuilder {
    static let schemaVersion = 1
    static let maximumPayloadBytes =
        1_500_000
    static let payloadByteBudget =
        3_000_000

    static func data(
        from source:
            LocalDiagnosticReportSource
    ) throws -> Data {
        let metrics =
            decodedPayloads(
                source.metricPayloads
            )
        let diagnostics =
            decodedPayloads(
                source.diagnosticPayloads
            )
        let report: [String: Any] = [
            "schemaVersion":
                schemaVersion,
            "generatedAt":
                ISO8601DateFormatter()
                .string(
                    from: source.generatedAt
                ),
            "privacy": [
                "automaticUpload": false,
                "createdOnlyOnUserRequest":
                    true,
                "doesNotIntentionallyInclude": [
                    "conversation text",
                    "photos and scanned images",
                    "OCR and document text",
                    "API keys and credentials",
                    "user and device names",
                ],
            ],
            "app": [
                "version":
                    source.app.version,
                "build":
                    source.app.build,
                "bundleIdentifier":
                    source.app
                    .bundleIdentifier,
            ],
            "device": [
                "hardwareIdentifier":
                    source.device
                    .hardwareIdentifier,
                "systemName":
                    source.device.systemName,
                "systemVersion":
                    source.device
                    .systemVersion,
                "memoryTier":
                    source.device.memoryTier,
                "physicalMemoryBytes":
                    source.device
                    .physicalMemoryBytes,
                "availableAppMemoryBytes":
                    source.device
                    .availableAppMemoryBytes,
                "metalWorkingSetBytes":
                    optionalNumber(
                        source.device
                            .metalWorkingSetBytes
                    ),
                "availableStorageBytes":
                    optionalNumber(
                        source.device
                            .availableStorageBytes
                    ),
                "thermalLevel":
                    source.device
                    .thermalLevel,
                "lowPowerMode":
                    source.device
                    .isLowPowerModeEnabled,
            ],
            "settings": [
                "appLanguage":
                    source.settings
                    .appLanguage,
                "appFontKey":
                    source.settings
                    .appFontKey,
                "soundEffects":
                    source.settings
                    .soundEffectsEnabled,
                "voiceFeedback":
                    source.settings
                    .voiceFeedbackEnabled,
                "scanAutomaticCapture":
                    source.settings
                    .automaticCaptureEnabled,
                "scanCurvedPageCorrection":
                    source.settings
                    .curvedPageCorrectionEnabled,
                "scanColorEnhancement":
                    source.settings
                    .colorEnhancementEnabled,
                "ocrCorrection":
                    source.settings
                    .ocrCorrectionEnabled,
                "webSearchEnabled":
                    source.settings
                    .webSearchEnabled,
                "webSearchAPIKeyStored":
                    source.settings
                    .webSearchAPIKeyStored,
            ],
            "metricKit": [
                "source":
                    "Apple MetricKit",
                "automaticUpload": false,
                "metricPayloadCount":
                    source.metricPayloads
                    .count,
                "includedMetricPayloadCount":
                    metrics.objects.count,
                "skippedMetricPayloadCount":
                    metrics.skipped,
                "diagnosticPayloadCount":
                    source.diagnosticPayloads
                    .count,
                "includedDiagnosticPayloadCount":
                    diagnostics
                    .objects.count,
                "skippedDiagnosticPayloadCount":
                    diagnostics.skipped,
                "metrics":
                    metrics.objects,
                "diagnostics":
                    diagnostics.objects,
            ],
            "androidParity": [
                "remoteCrashCollection":
                    "replaced by user-exported local MetricKit diagnostics",
                "analytics":
                    "not collected",
                "performanceTelemetry":
                    "VisionCraft does not upload the OS-provided MetricKit payloads",
                "silentNotificationBridge":
                    "replaced by direct in-app Rivo, widget, and App Intent routing",
            ],
        ]
        guard JSONSerialization
            .isValidJSONObject(report) else {
            throw CocoaError(
                .propertyListWriteInvalid
            )
        }
        return try JSONSerialization.data(
            withJSONObject: report,
            options: [
                .prettyPrinted,
                .sortedKeys,
                .withoutEscapingSlashes,
            ]
        )
    }

    @MainActor
    static func currentSource()
        -> LocalDiagnosticReportSource
    {
        let settings =
            AppSettingsStore.shared
        let webSearch =
            WebSearchConfigurationStore.shared
        let capability =
            DeviceCapabilityProfiler.snapshot()
        return LocalDiagnosticReportSource(
            generatedAt: Date(),
            app: appSnapshot(),
            device: deviceSnapshot(
                capability: capability
            ),
            settings:
                LocalDiagnosticSettingsSnapshot(
                    appLanguage:
                        settings
                        .appLanguage.rawValue,
                    appFontKey:
                        AppFontCatalogStore
                        .shared.selectedKey,
                    soundEffectsEnabled:
                        settings
                        .soundEffectsEnabled,
                    voiceFeedbackEnabled:
                        settings
                        .voiceFeedbackEnabled,
                    automaticCaptureEnabled:
                        settings
                        .documentScanAutomaticCaptureEnabled,
                    curvedPageCorrectionEnabled:
                        settings
                        .documentScanCurvedPageCorrectionEnabled,
                    colorEnhancementEnabled:
                        settings
                        .documentScanColorEnhancementEnabled,
                    ocrCorrectionEnabled:
                        settings
                        .ocrAutoCorrectionEnabled,
                    webSearchEnabled:
                        webSearch.isEnabled,
                    webSearchAPIKeyStored:
                        webSearch.hasAPIKey
                ),
            metricPayloads:
                LocalMetricKitSnapshot
                .metricPayloads(),
            diagnosticPayloads:
                LocalMetricKitSnapshot
                .diagnosticPayloads()
        )
    }

    @MainActor
    static func currentData() throws
        -> Data
    {
        try data(
            from: currentSource()
        )
    }

    @MainActor
    static func currentSummary()
        -> LocalDiagnosticSummary
    {
        let capability =
            DeviceCapabilityProfiler.snapshot()
        return LocalDiagnosticSummary(
            app: appSnapshot(),
            device: deviceSnapshot(
                capability: capability
            ),
            metricPayloadCount:
                MXMetricManager.shared
                .pastPayloads.count,
            diagnosticPayloadCount:
                MXMetricManager.shared
                .pastDiagnosticPayloads
                .count
        )
    }

    static func defaultFilename(
        date: Date = Date()
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(
            identifier: "en_US_POSIX"
        )
        formatter.timeZone =
            TimeZone.current
        formatter.dateFormat =
            "yyyyMMdd-HHmmss"
        return "VisionCraft-Diagnostics-"
            + formatter.string(from: date)
    }

    private static func appSnapshot()
        -> LocalDiagnosticAppSnapshot
    {
        LocalDiagnosticAppSnapshot(
            version:
                Bundle.main.object(
                    forInfoDictionaryKey:
                        "CFBundleShortVersionString"
                ) as? String
                ?? "unknown",
            build:
                Bundle.main.object(
                    forInfoDictionaryKey:
                        "CFBundleVersion"
                ) as? String
                ?? "unknown",
            bundleIdentifier:
                Bundle.main.bundleIdentifier
                ?? "unknown"
        )
    }

    @MainActor
    private static func deviceSnapshot(
        capability:
            DeviceCapabilitySnapshot
    ) -> LocalDiagnosticDeviceSnapshot {
        LocalDiagnosticDeviceSnapshot(
            hardwareIdentifier:
                hardwareIdentifier(),
            systemName:
                UIDevice.current
                .systemName,
            systemVersion:
                UIDevice.current
                .systemVersion,
            memoryTier:
                capability
                .memoryTier.rawValue,
            physicalMemoryBytes:
                capability
                .physicalMemoryBytes,
            availableAppMemoryBytes:
                capability
                .availableAppMemoryBytes,
            metalWorkingSetBytes:
                capability
                .metalRecommendedWorkingSetBytes,
            availableStorageBytes:
                capability
                .availableStorageBytes,
            thermalLevel:
                capability
                .thermalLevel.rawValue,
            isLowPowerModeEnabled:
                capability
                .isLowPowerModeEnabled
        )
    }

    private static func decodedPayloads(
        _ payloads: [Data]
    ) -> (
        objects: [Any],
        skipped: Int
    ) {
        var objects: [Any] = []
        var usedBytes = 0
        var skipped = 0
        for data in payloads.suffix(
            LocalMetricKitSnapshot
                .maximumPayloadCount
        ) {
            guard data.count
                    <= maximumPayloadBytes,
                  usedBytes + data.count
                    <= payloadByteBudget,
                  let object =
                    try? JSONSerialization
                    .jsonObject(
                        with: data
                    ) else {
                skipped += 1
                continue
            }
            objects.append(object)
            usedBytes += data.count
        }
        skipped += max(
            0,
            payloads.count
                - LocalMetricKitSnapshot
                .maximumPayloadCount
        )
        return (objects, skipped)
    }

    private static func optionalNumber(
        _ value: UInt64?
    ) -> Any {
        value.map {
            NSNumber(value: $0)
        } ?? NSNull()
    }

    private static func hardwareIdentifier()
        -> String
    {
        var info = utsname()
        guard uname(&info) == 0 else {
            return "unknown"
        }
        return withUnsafePointer(
            to: &info.machine
        ) {
            $0.withMemoryRebound(
                to: CChar.self,
                capacity: 1
            ) {
                String(cString: $0)
            }
        }
    }
}

struct LocalDiagnosticReportDocument:
    FileDocument
{
    static var readableContentTypes:
        [UTType]
    {
        [.json]
    }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(
        configuration:
            ReadConfiguration
    ) throws {
        data =
            configuration.file
            .regularFileContents
            ?? Data()
    }

    func fileWrapper(
        configuration:
            WriteConfiguration
    ) throws -> FileWrapper {
        FileWrapper(
            regularFileWithContents: data
        )
    }
}

struct LocalDiagnosticsView: View {
    @State private var summary:
        LocalDiagnosticSummary?
    @State private var reportDocument:
        LocalDiagnosticReportDocument?
    @State private var isExporting = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            privacySection
            if let summary {
                deviceSection(summary)
                metricKitSection(summary)
            } else {
                ProgressView(
                    "진단 상태를 확인하는 중"
                )
            }
            exportSection
        }
        .visionCraftListScreen()
        .navigationTitle(
            "진단 및 개인정보"
        )
        .navigationBarTitleDisplayMode(
            .large
        )
        .toolbar {
            Button(
                "새로 고침",
                systemImage:
                    "arrow.clockwise"
            ) {
                refresh()
            }
        }
        .task {
            refresh()
        }
        .fileExporter(
            isPresented: $isExporting,
            document: reportDocument,
            contentType: .json,
            defaultFilename:
                LocalDiagnosticReportBuilder
                .defaultFilename()
        ) { result in
            reportDocument = nil
            switch result {
            case .success:
                statusMessage =
                    AppLocalization.string(
                        "진단 보고서를 저장했습니다."
                    )
                errorMessage = nil
            case .failure(let error):
                statusMessage = nil
                errorMessage =
                    AppLocalization.format(
                        "진단 보고서를 저장하지 못했습니다: %@",
                        error.localizedDescription
                    )
            }
        }
    }

    private var privacySection:
        some View
    {
        Section {
            LabeledContent(
                "자동 진단 전송",
                value: "사용 안 함"
            )
            Label(
                "알림 권한을 요구하지 않음",
                systemImage:
                    "bell.slash"
            )
        } header: {
            Text("개인정보")
        } footer: {
            Text(
                "VisionCraft는 Crashlytics·Analytics·성능 자료를 서버로 자동 전송하지 않습니다. 보고서는 사용자가 내보내기를 누를 때만 만들며 대화, 사진, OCR·문서 내용, API 키와 기기 이름을 직접 추가하지 않습니다. 공유 전에 파일 내용을 확인하세요."
            )
        }
    }

    private func deviceSection(
        _ summary: LocalDiagnosticSummary
    ) -> some View {
        Section("현재 기기 상태") {
            LabeledContent(
                "앱 버전",
                value:
                    summary.app.version
                    + " ("
                    + summary.app.build
                    + ")"
            )
            LabeledContent(
                "하드웨어",
                value:
                    summary.device
                    .hardwareIdentifier
            )
            LabeledContent(
                "iPadOS",
                value:
                    summary.device
                    .systemVersion
            )
            LabeledContent(
                "메모리 등급",
                value:
                    memoryTierTitle(
                        summary.device
                        .memoryTier
                    )
            )
            LabeledContent(
                "현재 사용 가능 메모리",
                value:
                    byteCount(
                        summary.device
                        .availableAppMemoryBytes
                    )
            )
            if let availableStorage =
                summary.device
                .availableStorageBytes {
                LabeledContent(
                    "사용 가능 저장 공간",
                    value:
                        byteCount(
                            availableStorage
                        )
                )
            }
            LabeledContent(
                "온도 상태",
                value:
                    thermalTitle(
                        summary.device
                        .thermalLevel
                    )
            )
            LabeledContent(
                "저전력 모드",
                value:
                    summary.device
                    .isLowPowerModeEnabled
                    ? AppLocalization
                        .string("켜짐")
                    : AppLocalization
                        .string("꺼짐")
            )
        }
    }

    private func metricKitSection(
        _ summary: LocalDiagnosticSummary
    ) -> some View {
        Section {
            LabeledContent(
                "성능 자료",
                value:
                    "\(summary.metricPayloadCount)"
            )
            LabeledContent(
                "충돌·멈춤 자료",
                value:
                    "\(summary.diagnosticPayloadCount)"
            )
        } header: {
            Text("iPadOS 진단 자료")
        } footer: {
            Text(
                "Apple MetricKit 자료는 iPadOS가 조건에 따라 대략 하루 단위로 제공하므로 처음에는 0개일 수 있습니다. VisionCraft가 서버로 전송하지 않으며 사용자가 만든 JSON 보고서에만 복사됩니다."
            )
        }
    }

    private var exportSection:
        some View
    {
        Section {
            Button(
                "진단 보고서 내보내기",
                systemImage:
                    "square.and.arrow.up"
            ) {
                prepareReport()
            }
            if let statusMessage {
                Text(statusMessage)
                    .foregroundStyle(
                        .secondary
                    )
            }
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
        } footer: {
            Text(
                "JSON 보고서에는 앱·iPadOS 버전, M4 메모리·저장 공간·온도 상태, 비밀 값이 없는 기능 설정과 사용 가능한 MetricKit 자료가 들어갑니다."
            )
        }
    }

    private func refresh() {
        summary =
            LocalDiagnosticReportBuilder
            .currentSummary()
    }

    private func prepareReport() {
        do {
            reportDocument =
                LocalDiagnosticReportDocument(
                    data:
                        try LocalDiagnosticReportBuilder
                        .currentData()
                )
            errorMessage = nil
            statusMessage = nil
            isExporting = true
        } catch {
            reportDocument = nil
            statusMessage = nil
            errorMessage =
                AppLocalization.format(
                    "진단 보고서를 준비하지 못했습니다: %@",
                    error.localizedDescription
                )
        }
    }

    private func byteCount(
        _ bytes: UInt64
    ) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(
                min(
                    bytes,
                    UInt64(Int64.max)
                )
            ),
            countStyle: .memory
        )
    }

    private func memoryTierTitle(
        _ value: String
    ) -> String {
        value == DeviceMemoryTier
            .expanded.rawValue
            ? AppLocalization
                .string("확장")
            : AppLocalization
                .string("표준")
    }

    private func thermalTitle(
        _ value: String
    ) -> String {
        switch value {
        case DeviceThermalLevel
            .nominal.rawValue:
            return AppLocalization
                .string("정상")
        case DeviceThermalLevel
            .fair.rawValue:
            return AppLocalization
                .string("약간 높음")
        case DeviceThermalLevel
            .serious.rawValue:
            return AppLocalization
                .string("높음")
        case DeviceThermalLevel
            .critical.rawValue:
            return AppLocalization
                .string("매우 높음")
        default:
            return AppLocalization
                .string("알 수 없음")
        }
    }
}
