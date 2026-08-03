import Foundation
import XCTest

@testable import shortcuts_example

final class LocalDiagnosticsTests:
    XCTestCase
{
    func testReportContainsBoundedLocalStateAndPrivacyContract()
        throws
    {
        let metric = Data(
            """
            {"metaData":{"osVersion":"26.2"}}
            """.utf8
        )
        let diagnostic = Data(
            """
            {"crashDiagnostics":[{"signal":"SIGABRT"}]}
            """.utf8
        )
        let data =
            try LocalDiagnosticReportBuilder
            .data(
                from: source(
                    metricPayloads: [metric],
                    diagnosticPayloads:
                        [diagnostic]
                )
            )
        let root =
            try XCTUnwrap(
                try JSONSerialization
                    .jsonObject(
                        with: data
                    ) as? [String: Any]
            )

        XCTAssertEqual(
            root["schemaVersion"] as? Int,
            1
        )
        let privacy =
            try XCTUnwrap(
                root["privacy"]
                    as? [String: Any]
            )
        XCTAssertEqual(
            privacy["automaticUpload"]
                as? Bool,
            false
        )
        XCTAssertEqual(
            privacy[
                "createdOnlyOnUserRequest"
            ] as? Bool,
            true
        )
        XCTAssertNotNil(
            privacy[
                "doesNotIntentionallyInclude"
            ] as? [String]
        )

        let metricKit =
            try XCTUnwrap(
                root["metricKit"]
                    as? [String: Any]
            )
        XCTAssertEqual(
            metricKit[
                "includedMetricPayloadCount"
            ] as? Int,
            1
        )
        XCTAssertEqual(
            metricKit[
                "includedDiagnosticPayloadCount"
            ] as? Int,
            1
        )
        let report = String(
            decoding: data,
            as: UTF8.self
        )
        XCTAssertFalse(
            report.contains("secret-key")
        )
        XCTAssertFalse(
            report.contains(
                "conversation body"
            )
        )
    }

    func testOversizedAndInvalidPayloadsAreSkipped()
        throws
    {
        let oversized = Data(
            repeating: 0,
            count:
                LocalDiagnosticReportBuilder
                .maximumPayloadBytes
                + 1
        )
        let invalid =
            Data("not-json".utf8)
        let valid =
            Data(#"{"ok":true}"#.utf8)
        let data =
            try LocalDiagnosticReportBuilder
            .data(
                from: source(
                    metricPayloads: [
                        oversized,
                        invalid,
                        valid,
                    ]
                )
            )
        let root =
            try XCTUnwrap(
                try JSONSerialization
                    .jsonObject(
                        with: data
                    ) as? [String: Any]
            )
        let metricKit =
            try XCTUnwrap(
                root["metricKit"]
                    as? [String: Any]
            )

        XCTAssertEqual(
            metricKit[
                "includedMetricPayloadCount"
            ] as? Int,
            1
        )
        XCTAssertEqual(
            metricKit[
                "skippedMetricPayloadCount"
            ] as? Int,
            2
        )
    }

    func testFilenameIsPortableAndStable()
    {
        let date = Date(
            timeIntervalSince1970:
                1_700_000_000
        )
        let filename =
            LocalDiagnosticReportBuilder
            .defaultFilename(date: date)

        XCTAssertTrue(
            filename.hasPrefix(
                "VisionCraft-Diagnostics-"
            )
        )
        XCTAssertFalse(
            filename.contains(":")
        )
        XCTAssertEqual(
            filename.count,
            "VisionCraft-Diagnostics-"
                .count + 15
        )
    }

    @MainActor
    func testCurrentSimulatorReportBuilds()
        throws
    {
        let summary =
            LocalDiagnosticReportBuilder
            .currentSummary()
        let data =
            try LocalDiagnosticReportBuilder
            .currentData()
        let root =
            try XCTUnwrap(
                try JSONSerialization
                    .jsonObject(
                        with: data
                    ) as? [String: Any]
            )

        XCTAssertFalse(
            summary.device
                .hardwareIdentifier
                .isEmpty
        )
        XCTAssertNotNil(root["device"])
        XCTAssertNotNil(root["settings"])
        XCTAssertNotNil(root["metricKit"])
    }

    private func source(
        metricPayloads: [Data] = [],
        diagnosticPayloads:
            [Data] = []
    ) -> LocalDiagnosticReportSource {
        LocalDiagnosticReportSource(
            generatedAt: Date(
                timeIntervalSince1970:
                    1_700_000_000
            ),
            app:
                LocalDiagnosticAppSnapshot(
                    version: "1.0",
                    build: "1",
                    bundleIdentifier:
                        "com.rivo.test"
                ),
            device:
                LocalDiagnosticDeviceSnapshot(
                    hardwareIdentifier:
                        "iPad16,3",
                    systemName:
                        "iPadOS",
                    systemVersion:
                        "26.2",
                    memoryTier:
                        "standard",
                    physicalMemoryBytes:
                        8_000_000_000,
                    availableAppMemoryBytes:
                        4_000_000_000,
                    metalWorkingSetBytes:
                        3_000_000_000,
                    availableStorageBytes:
                        20_000_000_000,
                    thermalLevel:
                        "nominal",
                    isLowPowerModeEnabled:
                        false
                ),
            settings:
                LocalDiagnosticSettingsSnapshot(
                    appLanguage: "ko",
                    appFontKey:
                        "nanumSquareRound",
                    soundEffectsEnabled:
                        true,
                    voiceFeedbackEnabled:
                        true,
                    automaticCaptureEnabled:
                        true,
                    curvedPageCorrectionEnabled:
                        true,
                    colorEnhancementEnabled:
                        true,
                    ocrCorrectionEnabled:
                        true,
                    webSearchEnabled:
                        false,
                    webSearchFirebaseConfigured:
                        false
                ),
            metricPayloads:
                metricPayloads,
            diagnosticPayloads:
                diagnosticPayloads
        )
    }
}
