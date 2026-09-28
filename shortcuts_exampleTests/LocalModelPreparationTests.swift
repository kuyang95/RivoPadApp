import Foundation
import XCTest

@testable import shortcuts_example

@MainActor
final class LocalModelPreparationTests: XCTestCase {
    private var temporaryDirectories = [URL]()

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try super.tearDownWithError()
    }

    func testDownloadProgressUsesByteCounts() {
        let model = LocalModelMetadata(
            displayName: "Test Model",
            expectedDownloadBytes: 4_000
        )
        let progress = LocalModelDownloadProgress(
            model: model,
            downloadedBytes: 1_000,
            bytesPerSecond: 500
        )

        XCTAssertEqual(
            progress.fractionCompleted,
            0.25,
            accuracy: 0.0001
        )
    }

    func testDownloadProgressIsClamped() {
        let model = LocalModelMetadata(
            displayName: "Test Model",
            expectedDownloadBytes: 100
        )

        XCTAssertEqual(
            LocalModelDownloadProgress(
                model: model,
                downloadedBytes: -1,
                bytesPerSecond: nil
            ).fractionCompleted,
            0
        )
        XCTAssertEqual(
            LocalModelDownloadProgress(
                model: model,
                downloadedBytes: 101,
                bytesPerSecond: nil
            ).fractionCompleted,
            1
        )
    }

    func testLiveDownloadBytesIncreaseBeforeTheFileIsInstalled() throws {
        let directory = try makeModelDirectory()
        let destination = directory.appendingPathComponent("model.safetensors")
        let model = LocalModelMetadata(displayName: "Test", expectedDownloadBytes: 3_100_000_000)
        let transfer = Progress(totalUnitCount: 3_000_000_000)
        var tracker = LocalModelDownloadTracker(model: model, completedFileBytes: 100_000_000)

        transfer.completedUnitCount = 400_000_000
        let first = tracker.sample(fileProgress: transfer, fileSize: 3_000_000_000, now: 1)
        transfer.completedUnitCount = 420_000_000
        let second = tracker.sample(fileProgress: transfer, fileSize: 3_000_000_000, now: 2)

        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(first.downloadedBytes, 500_000_000)
        XCTAssertEqual(second.downloadedBytes, 520_000_000)
        XCTAssertEqual(second.bytesPerSecond, 20_000_000)
        XCTAssertGreaterThan(second.fractionCompleted, first.fractionCompleted)
    }

    func testLiveDownloadProgressWeightsFilesByBytes() {
        let model = LocalModelMetadata(displayName: "Test", expectedDownloadBytes: 1_000)
        var tracker = LocalModelDownloadTracker(model: model, completedFileBytes: 100)
        let transfer = Progress(totalUnitCount: 900)
        transfer.completedUnitCount = 450

        let sample = tracker.sample(fileProgress: transfer, fileSize: 900, now: 1)

        // A small completed file plus half of a large file is 55%, not 75%.
        XCTAssertEqual(sample.downloadedBytes, 550)
        XCTAssertEqual(sample.fractionCompleted, 0.55, accuracy: 0.0001)
    }

    func testResumedDownloadIncludesExistingBytesWithoutInflatingInitialSpeed() {
        let model = LocalModelMetadata(displayName: "Test", expectedDownloadBytes: 1_000)
        var tracker = LocalModelDownloadTracker(model: model, completedFileBytes: 100)
        let transfer = Progress(totalUnitCount: 900)
        transfer.completedUnitCount = 600
        let resumed = tracker.sample(fileProgress: transfer, fileSize: 900, now: 1)
        transfer.completedUnitCount = 650
        let next = tracker.sample(fileProgress: transfer, fileSize: 900, now: 2)

        XCTAssertEqual(resumed.downloadedBytes, 700)
        XCTAssertNil(resumed.bytesPerSecond)
        XCTAssertEqual(next.downloadedBytes, 750)
        XCTAssertEqual(next.bytesPerSecond, 50)
    }

    func testStalledDownloadClearsSpeedAndKeepsReceivedBytes() {
        let model = LocalModelMetadata(displayName: "Test", expectedDownloadBytes: 1_000)
        var tracker = LocalModelDownloadTracker(model: model, completedFileBytes: 0)
        let transfer = Progress(totalUnitCount: 1_000)
        transfer.completedUnitCount = 100
        _ = tracker.sample(fileProgress: transfer, fileSize: 1_000, now: 1)
        transfer.completedUnitCount = 200
        XCTAssertEqual(tracker.sample(fileProgress: transfer, fileSize: 1_000, now: 2).bytesPerSecond, 100)

        let stalled = tracker.sample(fileProgress: transfer, fileSize: 1_000, now: 3)
        XCTAssertEqual(stalled.downloadedBytes, 200)
        XCTAssertNil(stalled.bytesPerSecond)
    }

    func testSwitchingFilesDoesNotDoubleCountOrCarrySpeed() {
        let model = LocalModelMetadata(displayName: "Test", expectedDownloadBytes: 1_000)
        var firstTracker = LocalModelDownloadTracker(model: model, completedFileBytes: 100)
        let firstTransfer = Progress(totalUnitCount: 600)
        firstTransfer.completedUnitCount = 600
        XCTAssertEqual(firstTracker.sample(fileProgress: firstTransfer, fileSize: 600, now: 1).downloadedBytes, 700)

        var secondTracker = LocalModelDownloadTracker(model: model, completedFileBytes: 700)
        let secondTransfer = Progress(totalUnitCount: 300)
        secondTransfer.completedUnitCount = 50
        let sample = secondTracker.sample(fileProgress: secondTransfer, fileSize: 300, now: 2)
        XCTAssertEqual(sample.downloadedBytes, 750)
        XCTAssertNil(sample.bytesPerSecond)
        secondTransfer.completedUnitCount = 300
        XCTAssertEqual(secondTracker.sample(fileProgress: secondTransfer, fileSize: 300, now: 3).fractionCompleted, 1)
    }

    func testRetryResetsSpeedBaselineWhenReceivedBytesDecrease() {
        let model = LocalModelMetadata(displayName: "Test", expectedDownloadBytes: 1_000)
        var tracker = LocalModelDownloadTracker(model: model, completedFileBytes: 0)
        let transfer = Progress(totalUnitCount: 1_000)
        transfer.completedUnitCount = 800
        _ = tracker.sample(fileProgress: transfer, fileSize: 1_000, now: 1)
        transfer.completedUnitCount = 100
        XCTAssertNil(tracker.sample(fileProgress: transfer, fileSize: 1_000, now: 2).bytesPerSecond)
        transfer.completedUnitCount = 200
        XCTAssertEqual(tracker.sample(fileProgress: transfer, fileSize: 1_000, now: 3).bytesPerSecond, 100)
    }

    func testCancellationExplainsResumeBehavior() {
        let failure = LocalModelPreparationFailure.make(
            from: CancellationError()
        )

        XCTAssertNil(failure.technicalDetail)
        XCTAssertFalse(failure.title.isEmpty)
        XCTAssertFalse(failure.message.isEmpty)
    }

    func testNetworkFailureKeepsTechnicalDetail() {
        let error = URLError(.notConnectedToInternet)
        let failure = LocalModelPreparationFailure.make(
            from: error
        )

        XCTAssertEqual(
            failure.technicalDetail,
            error.localizedDescription
        )
        XCTAssertFalse(failure.message.isEmpty)
    }

    func testOutOfSpaceHasStorageSpecificMessage() {
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: CocoaError.fileWriteOutOfSpace
                .rawValue
        )
        let failure = LocalModelPreparationFailure.make(
            from: error
        )

        XCTAssertEqual(
            failure.title,
            AppLocalization.string(
                "저장 공간이 부족합니다."
            )
        )
    }

    func testSnapshotValidationRejectsMissingConfiguration() throws {
        let directory = try makeModelDirectory(
            includingConfiguration: false
        )

        XCTAssertThrowsError(
            try LocalModelSnapshotValidator.validate(
                directory: directory,
                isVision: false
            )
        ) { error in
            guard case .missingFiles(let filenames) = error
                    as? LocalModelSnapshotValidationError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(filenames.contains("config.json"))
        }
    }

    func testSnapshotValidationRejectsMissingIndexedWeight() throws {
        let directory = try makeModelDirectory()
        try write(
            """
            {"weight_map":{"layer":"model-00001-of-00002.safetensors"}}
            """,
            named: "model.safetensors.index.json",
            to: directory
        )

        XCTAssertThrowsError(
            try LocalModelSnapshotValidator.validate(
                directory: directory,
                isVision: false
            )
        ) { error in
            guard case .missingFiles(let filenames) = error
                    as? LocalModelSnapshotValidationError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(
                filenames.contains(
                    "model-00001-of-00002.safetensors"
                )
            )
        }
    }

    func testSnapshotValidationAcceptsCompleteVisionModel() throws {
        let directory = try makeModelDirectory()
        try write(
            "{}",
            named: "preprocessor_config.json",
            to: directory
        )
        try write(
            """
            {"weight_map":{"layer":"model-00001-of-00002.safetensors"}}
            """,
            named: "model.safetensors.index.json",
            to: directory
        )
        try write(
            "weights",
            named: "model-00001-of-00002.safetensors",
            to: directory
        )

        XCTAssertNoThrow(
            try LocalModelSnapshotValidator.validate(
                directory: directory,
                isVision: true
            )
        )
    }

    private func makeModelDirectory(
        includingConfiguration: Bool = true
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(directory)

        if includingConfiguration {
            try write("{}", named: "config.json", to: directory)
        }
        try write("{}", named: "tokenizer_config.json", to: directory)
        try write("{}", named: "tokenizer.json", to: directory)
        return directory
    }

    private func write(
        _ contents: String,
        named filename: String,
        to directory: URL
    ) throws {
        try Data(contents.utf8).write(
            to: directory.appendingPathComponent(filename)
        )
    }
}
