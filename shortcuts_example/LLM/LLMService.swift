//
//  LLMService.swift
//  shortcuts_example
//
//  Created by meee on 2/5/26.
//

import Combine
import CoreImage
import Foundation
import Hub
import MLX
import MLXLLM
import MLXLMCommon
import MLXVLM

enum LoadedModel: Equatable, Sendable {
    case none
    case qwen3_8b_4bit
    case qwen35_4b_4bit
    case qwen35_9b_4bit
    case ministral3_8b_instruct_4bit
    case qwen3_vl_8b_4bit

    static var preferredTextModel: LoadedModel {
        #if DEBUG
        // Explicit device trial; ordinary launches retain the device policy.
        if ProcessInfo.processInfo.arguments.contains("--local-llm-model=ministral3-8b") {
            return .ministral3_8b_instruct_4bit
        }
        #endif
        return preferredTextModel(for: DeviceCapabilityProfiler.snapshot().memoryTier)
    }

    static func preferredTextModel(for tier: DeviceMemoryTier) -> LoadedModel {
        tier == .standard ? .qwen35_4b_4bit : .qwen35_9b_4bit
    }

    var displayName: String {
        switch self {
        case .none:
            return "None"
        case .qwen3_8b_4bit:
            return "Qwen3-8B-4bit"
        case .qwen35_4b_4bit:
            return "Qwen3.5-4B-4bit"
        case .qwen35_9b_4bit:
            return "Qwen3.5-9B-4bit"
        case .ministral3_8b_instruct_4bit:
            return "Ministral-3-8B-Instruct-4bit"
        case .qwen3_vl_8b_4bit:
            return "Qwen3-VL-8B-Instruct-4bit"
        }
    }
}

struct LocalModelMetadata: Equatable, Sendable {
    let displayName: String
    let expectedDownloadBytes: Int64
}

struct LocalModelDownloadProgress: Equatable, Sendable {
    let model: LocalModelMetadata
    let downloadedBytes: Int64
    let bytesPerSecond: Double?

    var fractionCompleted: Double {
        guard model.expectedDownloadBytes > 0 else {
            return 0
        }
        return min(
            max(
                Double(downloadedBytes)
                    / Double(model.expectedDownloadBytes),
                0
            ),
            1
        )
    }
}

enum LocalModelPreparationPhase: Equatable, Sendable {
    case idle
    case checking(LocalModelMetadata)
    case downloading(LocalModelDownloadProgress)
    case loading(LocalModelMetadata)
}

struct LocalModelPreparationFailure: Equatable, Sendable {
    let title: String
    let message: String
    let technicalDetail: String?

    static func make(from error: Error) -> Self {
        let nsError = error as NSError
        let detail = error.localizedDescription

        if error is CancellationError
            || (
                nsError.domain == NSURLErrorDomain
                    && nsError.code
                        == URLError.cancelled.rawValue
            ) {
            return .init(
                title: AppLocalization.string(
                    "AI 모델 다운로드를 중단했습니다."
                ),
                message: AppLocalization.string(
                    "받은 데이터는 보관됩니다. 다음 시도에서 이어받습니다."
                ),
                technicalDetail: nil
            )
        }

        if nsError.domain == NSURLErrorDomain {
            return .init(
                title: AppLocalization.string(
                    "AI 모델을 다운로드하지 못했습니다."
                ),
                message: AppLocalization.string(
                    "인터넷 연결을 확인한 뒤 다시 시도해 주세요. 받은 데이터부터 이어받습니다."
                ),
                technicalDetail: detail
            )
        }

        if nsError.domain == NSCocoaErrorDomain,
           nsError.code
            == CocoaError.fileWriteOutOfSpace.rawValue {
            return .init(
                title: AppLocalization.string(
                    "저장 공간이 부족합니다."
                ),
                message: AppLocalization.string(
                    "공간을 확보한 뒤 다시 시도해 주세요. 이미 받은 데이터는 보관됩니다."
                ),
                technicalDetail: detail
            )
        }

        return .init(
            title: AppLocalization.string(
                "AI 모델을 준비하지 못했습니다."
            ),
            message: AppLocalization.string(
                "네트워크 연결과 저장 공간을 확인한 뒤 다시 시도해 주세요."
            ),
            technicalDetail: detail
        )
    }
}

enum LocalModelSnapshotValidationError: LocalizedError {
    case missingFiles([String])
    case invalidWeightIndex(String)

    var errorDescription: String? {
        switch self {
        case .missingFiles(let filenames):
            return AppLocalization.format(
                "AI 모델 다운로드가 완전하지 않습니다. 누락된 파일: %@",
                filenames.joined(separator: ", ")
            )
        case .invalidWeightIndex(let filename):
            return AppLocalization.format(
                "AI 모델 파일 목록을 읽을 수 없습니다: %@",
                filename
            )
        }
    }
}

enum LocalModelSnapshotValidator {
    private struct WeightIndex: Decodable {
        let weightMap: [String: String]

        enum CodingKeys: String, CodingKey {
            case weightMap = "weight_map"
        }
    }

    static func validate(
        directory: URL,
        isVision: Bool,
        fileManager: FileManager = .default
    ) throws {
        var missingFiles = [String]()

        for filename in [
            "config.json",
            "tokenizer_config.json",
        ] where !hasNonEmptyFile(
            named: filename,
            in: directory,
            fileManager: fileManager
        ) {
            missingFiles.append(filename)
        }

        let hasTokenizerJSON = hasNonEmptyFile(
            named: "tokenizer.json",
            in: directory,
            fileManager: fileManager
        )
        let hasTokenizerVocabulary = hasNonEmptyFile(
            named: "vocab.json",
            in: directory,
            fileManager: fileManager
        ) && hasNonEmptyFile(
            named: "merges.txt",
            in: directory,
            fileManager: fileManager
        )
        if !hasTokenizerJSON && !hasTokenizerVocabulary {
            missingFiles.append("tokenizer.json 또는 vocab.json/merges.txt")
        }

        if isVision {
            let hasProcessorConfiguration = hasNonEmptyFile(
                named: "preprocessor_config.json",
                in: directory,
                fileManager: fileManager
            ) || hasNonEmptyFile(
                named: "processor_config.json",
                in: directory,
                fileManager: fileManager
            )
            if !hasProcessorConfiguration {
                missingFiles.append(
                    "preprocessor_config.json 또는 processor_config.json"
                )
            }
        }

        let weightIndexFilename = "model.safetensors.index.json"
        let weightIndexURL = directory.appendingPathComponent(
            weightIndexFilename
        )
        if hasNonEmptyFile(
            named: weightIndexFilename,
            in: directory,
            fileManager: fileManager
        ) {
            let weightIndex: WeightIndex
            do {
                let data = try Data(contentsOf: weightIndexURL)
                weightIndex = try JSONDecoder().decode(
                    WeightIndex.self,
                    from: data
                )
            } catch {
                throw LocalModelSnapshotValidationError
                    .invalidWeightIndex(weightIndexFilename)
            }

            let weightFilenames = Set(weightIndex.weightMap.values)
            guard !weightFilenames.isEmpty else {
                throw LocalModelSnapshotValidationError
                    .invalidWeightIndex(weightIndexFilename)
            }
            for filename in weightFilenames.sorted() where !hasNonEmptyFile(
                named: filename,
                in: directory,
                fileManager: fileManager
            ) {
                missingFiles.append(filename)
            }
        } else if !containsNonEmptySafetensors(
            in: directory,
            fileManager: fileManager
        ) {
            missingFiles.append("*.safetensors")
        }

        guard missingFiles.isEmpty else {
            throw LocalModelSnapshotValidationError
                .missingFiles(missingFiles)
        }
    }

    private static func hasNonEmptyFile(
        named filename: String,
        in directory: URL,
        fileManager: FileManager
    ) -> Bool {
        let fileURL = directory.appendingPathComponent(filename)
        guard let attributes = try? fileManager.attributesOfItem(
            atPath: fileURL.path
        ),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber else {
            return false
        }
        return size.int64Value > 0
    }

    private static func containsNonEmptySafetensors(
        in directory: URL,
        fileManager: FileManager
    ) -> Bool {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return false
        }
        return files.contains { fileURL in
            fileURL.pathExtension == "safetensors"
                && hasNonEmptyFile(
                    named: fileURL.lastPathComponent,
                    in: directory,
                    fileManager: fileManager
                )
        }
    }
}

struct LLMConversationID: Hashable, Sendable {
    let rawValue: UUID

    init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    static let legacy = LLMConversationID(
        UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    )
}

@MainActor
final class LLMService: ObservableObject {

    static let shared = LLMService()

    @Published private(set) var isLoading = false
    @Published private(set) var isGenerating = false
    @Published private(set) var loadedModel: LoadedModel = .none
    @Published private(set) var inferencePolicy: LocalInferencePolicy?
    @Published private(set) var modelPreparationPhase:
        LocalModelPreparationPhase = .idle
    @Published private(set) var modelBeingPrepared:
        LocalModelMetadata?

    private struct LocalModelSpec: Sendable {
        let repoID: String
        let isVision: Bool
        let metadata: LocalModelMetadata
    }

    private struct InFlightLoad {
        let id: UUID
        let requestID: UUID
        let target: LoadedModel
        let task: Task<ModelContainer, Error>
    }

    private struct SessionRecord {
        let id: UUID
        let conversationID: LLMConversationID
        let system: String
        let modelEpoch: UUID
        let session: ChatSession
    }

    private var container: ModelContainer?
    private var modelEpoch = UUID()
    private var activeSession: SessionRecord?
    private var inFlightLoad: InFlightLoad?
    private var activationRequestID: UUID?
    private var activationRequestedTarget: LoadedModel?

    private var activeOperationID: UUID?
    private var activeOperationConversationID: LLMConversationID?
    private var generationID: UUID?
    private var generationConversationID: LLMConversationID?
    private var generationTask: Task<Void, Never>?

    private init() {}

    private var allowsModelDownload: Bool {
        #if DEBUG
        !ProcessInfo.processInfo.arguments.contains("--local-llm-benchmark")
        #else
        true
        #endif
    }

    var isReady: Bool {
        container != nil && loadedModel != .none && !isLoading
    }

    // MARK: - Local model store

    private lazy var modelStoreURL: URL = {
        let base = try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("HFModels", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }()

    private func spec(for target: LoadedModel) -> LocalModelSpec? {
        switch target {
        case .none:
            return nil

        case .ministral3_8b_instruct_4bit:
            return .init(
                repoID: "mlx-community/Ministral-3-8B-Instruct-2512-4bit",
                isVision: false,
                metadata: .init(
                    displayName: target.displayName,
                    expectedDownloadBytes: 5_630_654_690
                )
            )

        case .qwen3_8b_4bit:
            return .init(
                repoID: "mlx-community/Qwen3-8B-4bit",
                isVision: false,
                metadata: .init(
                    displayName: target.displayName,
                    expectedDownloadBytes: 4_623_784_971
                )
            )

        case .qwen3_vl_8b_4bit:
            return .init(
                repoID: "mlx-community/Qwen3-VL-8B-Instruct-4bit",
                isVision: true,
                metadata: .init(
                    displayName: target.displayName,
                    expectedDownloadBytes: 5_776_633_051
                )
            )

        case .qwen35_4b_4bit:
            return .init(
                repoID: "mlx-community/Qwen3.5-4B-MLX-4bit",
                isVision: false,
                metadata: .init(
                    displayName: target.displayName,
                    expectedDownloadBytes: 3_061_132_920
                )
            )

        case .qwen35_9b_4bit:
            return .init(
                repoID: "mlx-community/Qwen3.5-9B-MLX-4bit",
                isVision: false,
                metadata: .init(
                    displayName: target.displayName,
                    expectedDownloadBytes: 5_977_074_591
                )
            )
        }
    }

    private func makeHub(offlineOnly: Bool) -> HubApi {
        HubApi(
            downloadBase: modelStoreURL,
            useOfflineMode: offlineOnly
        )
    }

    // MARK: - Device-adaptive policy

    @discardableResult
    func configureForCurrentDevice() -> LocalInferencePolicy {
        let capabilities = DeviceCapabilityProfiler.snapshot()
        let policy = LocalInferencePolicy.make(from: capabilities)

        Memory.memoryLimit = policy.mlxMemoryLimitBytes
        Memory.cacheLimit = policy.mlxCacheLimitBytes
        inferencePolicy = policy

        let mib = 1_048_576
        RVLogger.d(
            "🧭 Local AI profile=\(policy.memoryTier.rawValue) " +
            "mlxLimit=\(policy.mlxMemoryLimitBytes / mib)MiB " +
            "available=\(capabilities.availableAppMemoryBytes / UInt64(mib))MiB " +
            "thermal=\(capabilities.thermalLevel.rawValue)"
        )

        return policy
    }

    // MARK: - Model activation

    func activateModel(_ target: LoadedModel) async throws {
        try await activateModel(
            target,
            preservingOperationID: nil
        )
    }

    private func activateModel(
        _ target: LoadedModel,
        preservingOperationID: UUID?
    ) async throws {
        let requestID: UUID
        if activationRequestedTarget == target,
           let currentRequestID = activationRequestID {
            requestID = currentRequestID
        } else {
            requestID = UUID()
            activationRequestID = requestID
            activationRequestedTarget = target
            invalidateActiveOperation(except: preservingOperationID)
        }

        if target == .none {
            await unloadCurrentModel(requestID: requestID)
            return
        }

        while true {
            try validateActivationRequest(requestID, target: target)

            if loadedModel == target, container != nil {
                return
            }

            if let load = inFlightLoad {
                if load.target != target {
                    load.task.cancel()
                }

                do {
                    let loadedContainer = try await load.task.value
                    let didCommit = commitLoadedContainer(
                        loadedContainer,
                        target: load.target,
                        loadID: load.id,
                        requestID: load.requestID
                    )
                    if !didCommit {
                        clearLoadIfCurrent(load.id)
                    }
                } catch {
                    clearLoadIfCurrent(load.id)
                    if load.target == target,
                       load.requestID == requestID,
                       activationRequestID == requestID {
                        throw error
                    }
                }

                continue
            }

            try validateActivationRequest(requestID, target: target)
            _ = configureForCurrentDevice()

            guard let modelSpec = spec(for: target) else {
                throw NSError(
                    domain: "LLMService",
                    code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            AppLocalization.string(
                                "잘못된 모델 타입입니다."
                            ),
                    ]
                )
            }
            modelBeingPrepared = modelSpec.metadata

            let loadID = UUID()
            let loadRequestID = requestID
            let loadTask = Task { @MainActor [weak self] in
                guard let self else {
                    throw CancellationError()
                }

                try await self.prepareForModelSwitch(
                    loadID: loadID,
                    requestID: loadRequestID,
                    target: target
                )
                try Task.checkCancellation()

                let loadedContainer = try await self.loadContainer(
                    for: modelSpec,
                    allowDownloadIfNeeded: self.allowsModelDownload,
                    loadID: loadID
                )
                try Task.checkCancellation()
                try self.validateLoad(
                    loadID: loadID,
                    requestID: loadRequestID,
                    target: target
                )
                return loadedContainer
            }

            inFlightLoad = .init(
                id: loadID,
                requestID: requestID,
                target: target,
                task: loadTask
            )
            isLoading = true
            RVLogger.d("🚀 모델 활성화 시작: \(target.displayName)")
        }
    }

    @discardableResult
    private func commitLoadedContainer(
        _ loadedContainer: ModelContainer,
        target: LoadedModel,
        loadID: UUID,
        requestID: UUID
    ) -> Bool {
        guard inFlightLoad?.id == loadID,
              inFlightLoad?.requestID == requestID,
              activationRequestID == requestID,
              activationRequestedTarget == target else {
            return false
        }

        container = loadedContainer
        loadedModel = target
        modelEpoch = UUID()
        inFlightLoad = nil
        isLoading = false
        modelPreparationPhase = .idle

        RVLogger.d("✅ 새 모델 활성화 완료: \(target.displayName)")
        RVLogger.d(Memory.snapshot().description)
        return true
    }

    private func clearLoadIfCurrent(_ loadID: UUID) {
        guard inFlightLoad?.id == loadID else {
            return
        }

        inFlightLoad = nil
        isLoading = false
        modelPreparationPhase = .idle
    }

    private func validateActivationRequest(
        _ requestID: UUID,
        target: LoadedModel
    ) throws {
        guard activationRequestID == requestID,
              activationRequestedTarget == target else {
            throw CancellationError()
        }
    }

    private func validateLoad(
        loadID: UUID,
        requestID: UUID,
        target: LoadedModel
    ) throws {
        guard inFlightLoad?.id == loadID,
              inFlightLoad?.requestID == requestID else {
            throw CancellationError()
        }
        try validateActivationRequest(requestID, target: target)
    }

    private func prepareForModelSwitch(
        loadID: UUID,
        requestID: UUID,
        target: LoadedModel
    ) async throws {
        try validateLoad(
            loadID: loadID,
            requestID: requestID,
            target: target
        )
        await stopActiveGeneration()
        try validateLoad(
            loadID: loadID,
            requestID: requestID,
            target: target
        )

        if let session = activeSession?.session {
            await session.synchronize()
            try validateLoad(
                loadID: loadID,
                requestID: requestID,
                target: target
            )
        }

        activeSession = nil
        container = nil
        loadedModel = .none
        modelEpoch = UUID()
        modelPreparationPhase = .idle
        modelBeingPrepared = nil
        Memory.clearCache()
        await Task.yield()
        try validateLoad(
            loadID: loadID,
            requestID: requestID,
            target: target
        )
    }

    func unloadCurrentModel() async {
        try? await activateModel(.none)
    }

    private func unloadCurrentModel(requestID: UUID) async {
        if let load = inFlightLoad {
            load.task.cancel()
            _ = try? await load.task.value
            clearLoadIfCurrent(load.id)
        }

        guard activationRequestID == requestID,
              activationRequestedTarget == LoadedModel.none else {
            return
        }

        await stopActiveGeneration()
        guard activationRequestID == requestID,
              activationRequestedTarget == LoadedModel.none else {
            return
        }

        if let session = activeSession?.session {
            await session.synchronize()
            guard activationRequestID == requestID,
                  activationRequestedTarget == LoadedModel.none else {
                return
            }
        }

        activeSession = nil
        container = nil
        loadedModel = .none
        modelEpoch = UUID()
        Memory.clearCache()

        RVLogger.d("🗑️ unload 완료")
        RVLogger.d(Memory.snapshot().description)
    }

    // MARK: - Local resolve / download

    private func resolveLocalModelDirectory(
        for spec: LocalModelSpec,
        allowDownload: Bool,
        loadID: UUID
    ) async throws -> URL {
        RVLogger.d("📦 모델 확인 시작: \(spec.repoID)")
        updateModelPreparationPhase(
            .checking(spec.metadata),
            loadID: loadID
        )

        do {
            let offlineHub = makeHub(offlineOnly: true)
            let localURL = try await offlineHub.snapshot(
                from: spec.repoID,
                matching: "*"
            )
            try LocalModelSnapshotValidator.validate(
                directory: localURL,
                isVision: spec.isVision
            )
            RVLogger.d("✅ 로컬 모델 발견: \(spec.repoID)")
            updateModelPreparationPhase(
                .loading(spec.metadata),
                loadID: loadID
            )
            return localURL
        } catch {
            RVLogger.d("ℹ️ 로컬 모델 없음 또는 메타데이터 불완전: \(spec.repoID)")
            guard allowDownload else {
                throw error
            }
        }

        RVLogger.d("⬇️ 다운로드 시작: \(spec.repoID)")
        publishDownloadProgress(
            for: spec,
            bytesPerSecond: nil,
            loadID: loadID
        )

        let onlineHub = makeHub(offlineOnly: false)

        let downloadedURL = try await LocalModelDownloader.download(
            repoID: spec.repoID,
            displayName: spec.metadata.displayName,
            hub: onlineHub
        ) { [weak self] progress in
            self?.updateModelPreparationPhase(
                .downloading(progress),
                loadID: loadID
            )
        }

        try LocalModelSnapshotValidator.validate(
            directory: downloadedURL,
            isVision: spec.isVision
        )

        RVLogger.d("✅ 다운로드 완료: \(spec.repoID)")
        updateModelPreparationPhase(
            .loading(spec.metadata),
            loadID: loadID
        )
        return downloadedURL
    }

    private func loadContainer(
        for spec: LocalModelSpec,
        allowDownloadIfNeeded: Bool,
        loadID: UUID
    ) async throws -> ModelContainer {
        let modelDirectory = try await resolveLocalModelDirectory(
            for: spec,
            allowDownload: allowDownloadIfNeeded,
            loadID: loadID
        )

        // A load failure can be caused by memory pressure or cancellation.
        // Do not delete a multi-gigabyte model unless a future installer has
        // positively identified a checksum mismatch.
        return try await makeModelContainer(
            from: modelDirectory,
            spec: spec
        )
    }

    private func updateModelPreparationPhase(
        _ phase: LocalModelPreparationPhase,
        loadID: UUID
    ) {
        guard inFlightLoad?.id == loadID else {
            return
        }
        modelPreparationPhase = phase
    }

    private func publishDownloadProgress(
        for spec: LocalModelSpec,
        bytesPerSecond: Double?,
        loadID: UUID
    ) {
        guard inFlightLoad?.id == loadID else {
            return
        }
        let downloadedBytes = downloadedByteCount(
            for: spec
        )
        modelPreparationPhase = .downloading(
            .init(
                model: spec.metadata,
                downloadedBytes: downloadedBytes,
                bytesPerSecond: bytesPerSecond
            )
        )
    }

    private func downloadedByteCount(
        for spec: LocalModelSpec
    ) -> Int64 {
        let repositoryURL = modelStoreURL
            .appendingPathComponent(
                "models",
                isDirectory: true
            )
            .appendingPathComponent(
                spec.repoID,
                isDirectory: true
            )
        guard let enumerator = FileManager.default
            .enumerator(
                at: repositoryURL,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .fileSizeKey,
                ],
                options: []
            ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let path = fileURL.path
            let isIncomplete = fileURL.lastPathComponent
                .hasSuffix(".incomplete")
            if path.contains("/.cache/")
                && !isIncomplete {
                continue
            }
            guard let values = try? fileURL
                    .resourceValues(
                        forKeys: [
                            .isRegularFileKey,
                            .fileSizeKey,
                        ]
                    ),
                  values.isRegularFile == true else {
                continue
            }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    private func makeModelContainer(
        from modelDirectory: URL,
        spec: LocalModelSpec
    ) async throws -> ModelContainer {
        RVLogger.d("🧠 로드 시작: \(spec.repoID)")

        let tokenizerLoader = LocalModelTokenizerLoader()

        if spec.isVision {
            let loadedContainer = try await VLMModelFactory.shared.loadContainer(
                from: modelDirectory,
                using: tokenizerLoader
            )

            RVLogger.d("✅ VLM 로드 완료: \(spec.repoID)")
            return loadedContainer
        }

        let loadedContainer = try await LLMModelFactory.shared.loadContainer(
            from: modelDirectory,
            using: tokenizerLoader
        )

        RVLogger.d("✅ LLM 로드 완료: \(spec.repoID)")
        return loadedContainer
    }

    // MARK: - Conversation lifecycle

    func resetConversation(_ conversationID: LLMConversationID) async {
        if activeOperationConversationID == conversationID {
            invalidateActiveOperation(except: nil)
        }

        if generationConversationID == conversationID {
            await stopActiveGeneration()
        }

        guard let sessionRecord = activeSession,
              sessionRecord.conversationID == conversationID else {
            return
        }

        await sessionRecord.session.synchronize()
        guard activeOperationConversationID != conversationID,
              activeSession?.id == sessionRecord.id else {
            return
        }

        activeSession = nil
        await sessionRecord.session.clear()

        if activeOperationConversationID == conversationID {
            return
        }
    }

    func cancelGeneration(for conversationID: LLMConversationID) async {
        if activeOperationConversationID == conversationID {
            invalidateActiveOperation(except: nil)
        }

        if generationConversationID == conversationID {
            await stopActiveGeneration()
        }
    }

    private func session(
        for conversationID: LLMConversationID,
        system: String,
        expectedModel: LoadedModel,
        expectedModelEpoch: UUID,
        operationID: UUID
    ) async throws -> ChatSession {
        try validateOperation(
            operationID,
            conversationID: conversationID,
            expectedModel: expectedModel,
            expectedModelEpoch: expectedModelEpoch
        )
        await stopActiveGeneration()
        try validateOperation(
            operationID,
            conversationID: conversationID,
            expectedModel: expectedModel,
            expectedModelEpoch: expectedModelEpoch
        )

        if let activeSession,
           activeSession.conversationID == conversationID,
           activeSession.system == system,
           activeSession.modelEpoch == expectedModelEpoch {
            return activeSession.session
        }

        if let previousSession = activeSession {
            await previousSession.session.synchronize()
            try validateOperation(
                operationID,
                conversationID: conversationID,
                expectedModel: expectedModel,
                expectedModelEpoch: expectedModelEpoch
            )

            activeSession = nil
            await previousSession.session.clear()
            try validateOperation(
                operationID,
                conversationID: conversationID,
                expectedModel: expectedModel,
                expectedModelEpoch: expectedModelEpoch
            )
        }

        try validateOperation(
            operationID,
            conversationID: conversationID,
            expectedModel: expectedModel,
            expectedModelEpoch: expectedModelEpoch
        )
        guard let container else {
            throw CancellationError()
        }

        var enableThinking = false
        #if DEBUG
        enableThinking = LocalLLMBenchmark.isThinkingEnabled
        #endif
        let newSession = ChatSession(
            container,
            instructions: system,
            generateParameters: generationParameters(for: expectedModel),
            additionalContext: ["enable_thinking": enableThinking]
        )
        activeSession = .init(
            id: UUID(),
            conversationID: conversationID,
            system: system,
            modelEpoch: expectedModelEpoch,
            session: newSession
        )
        return newSession
    }

    private func beginOperation(
        for conversationID: LLMConversationID
    ) -> UUID {
        let operationID = UUID()
        activeOperationID = operationID
        activeOperationConversationID = conversationID
        return operationID
    }

    private func invalidateActiveOperation(except operationID: UUID?) {
        guard activeOperationID != operationID else {
            return
        }
        activeOperationID = nil
        activeOperationConversationID = nil
    }

    private func clearOperationIfCurrent(_ operationID: UUID) {
        guard activeOperationID == operationID else {
            return
        }
        activeOperationID = nil
        activeOperationConversationID = nil
    }

    private func validateOperation(
        _ operationID: UUID,
        conversationID: LLMConversationID,
        expectedModel: LoadedModel,
        expectedModelEpoch: UUID
    ) throws {
        guard activeOperationID == operationID,
              activeOperationConversationID == conversationID,
              loadedModel == expectedModel,
              modelEpoch == expectedModelEpoch,
              container != nil else {
            throw CancellationError()
        }
    }

    private func generationParameters(
        for model: LoadedModel
    ) -> GenerateParameters {
        let policy = inferencePolicy
            ?? LocalInferencePolicy.make(from: DeviceCapabilityProfiler.snapshot())

        var maxTokens: Int
        let maxKVSize: Int

        switch model {
        case .qwen3_vl_8b_4bit:
            maxTokens = policy.visionMaxTokens
            maxKVSize = policy.visionMaxKVSize
        case .qwen3_8b_4bit, .qwen35_4b_4bit, .qwen35_9b_4bit,
             .ministral3_8b_instruct_4bit, .none:
            maxTokens = policy.textMaxTokens
            maxKVSize = policy.textMaxKVSize
        }

        #if DEBUG
        if model == LoadedModel.preferredTextModel,
           let override = LocalLLMBenchmark.outputTokenLimitOverride {
            maxTokens = override
        }
        #endif

        var parameters = GenerateParameters(
            maxTokens: maxTokens,
            maxKVSize: maxKVSize,
            kvBits: policy.kvBits,
            kvGroupSize: policy.kvGroupSize,
            quantizedKVStart: policy.quantizedKVStart,
            temperature: 0.6,
            topP: 0.9,
            prefillStepSize: 512
        )
        #if DEBUG
        parameters.seed = LocalLLMBenchmark.activeSampleSeed
        if LocalLLMBenchmark.usesRecommendedSampling {
            parameters.temperature = 1.0
            parameters.topP = 0.95
            parameters.topK = 20
            parameters.presencePenalty = 1.5
            parameters.presenceContextSize = 8192
            parameters.repetitionPenalty = 1.0
        }
        if LocalLLMBenchmark.usesGreedySampling {
            parameters.temperature = 0
        }
        #endif
        return parameters
    }

    // MARK: - Streaming

    func streamText(
        conversationID: LLMConversationID,
        system: String,
        prompt: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        let expectedModel = LoadedModel.preferredTextModel
        let operationID = beginOperation(for: conversationID)

        do {
            try await activateModel(
                expectedModel,
                preservingOperationID: operationID
            )
            let expectedModelEpoch = modelEpoch
            try validateOperation(
                operationID,
                conversationID: conversationID,
                expectedModel: expectedModel,
                expectedModelEpoch: expectedModelEpoch
            )

            let session = try await session(
                for: conversationID,
                system: system,
                expectedModel: expectedModel,
                expectedModelEpoch: expectedModelEpoch,
                operationID: operationID
            )

            return makeTextStream(
                session: session,
                conversationID: conversationID,
                operationID: operationID,
                prompt: prompt
            )
        } catch {
            clearOperationIfCurrent(operationID)
            throw error
        }
    }

    func streamVision(
        conversationID: LLMConversationID,
        system: String,
        prompt: String,
        images: [CIImage]
    ) async throws -> AsyncThrowingStream<String, Error> {
        let expectedModel = LoadedModel.qwen3_vl_8b_4bit
        let operationID = beginOperation(for: conversationID)

        do {
            try await activateModel(
                expectedModel,
                preservingOperationID: operationID
            )
            let expectedModelEpoch = modelEpoch
            try validateOperation(
                operationID,
                conversationID: conversationID,
                expectedModel: expectedModel,
                expectedModelEpoch: expectedModelEpoch
            )

            let session = try await session(
                for: conversationID,
                system: system,
                expectedModel: expectedModel,
                expectedModelEpoch: expectedModelEpoch,
                operationID: operationID
            )

            return makeVisionStream(
                session: session,
                conversationID: conversationID,
                operationID: operationID,
                prompt: prompt,
                images: images
            )
        } catch {
            clearOperationIfCurrent(operationID)
            throw error
        }
    }

    func streamText(
        system: String,
        prompt: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        try await streamText(
            conversationID: .legacy,
            system: system,
            prompt: prompt
        )
    }

    func streamVision(
        system: String,
        prompt: String,
        images: [CIImage]
    ) async throws -> AsyncThrowingStream<String, Error> {
        try await streamVision(
            conversationID: .legacy,
            system: system,
            prompt: prompt,
            images: images
        )
    }

    func respond(_ prompt: String) async throws -> String {
        let stream = try await streamText(
            conversationID: .legacy,
            system: "",
            prompt: prompt
        )

        var response = ""
        for try await chunk in stream {
            response += chunk
        }
        return response
    }

    private func makeTextStream(
        session: ChatSession,
        conversationID: LLMConversationID,
        operationID: UUID,
        prompt: String
    ) -> AsyncThrowingStream<String, Error> {
        let stream = session.streamResponse(to: prompt)
        return managedStream(
            stream,
            conversationID: conversationID,
            operationID: operationID
        )
    }

    private func makeVisionStream(
        session: ChatSession,
        conversationID: LLMConversationID,
        operationID: UUID,
        prompt: String,
        images: [CIImage]
    ) -> AsyncThrowingStream<String, Error> {
        let userImages: [UserInput.Image] = images.map { .ciImage($0) }
        let stream = session.streamResponse(
            to: prompt,
            images: userImages,
            videos: []
        )
        return managedStream(
            stream,
            conversationID: conversationID,
            operationID: operationID
        )
    }

    private func managedStream(
        _ source: AsyncThrowingStream<String, Error>,
        conversationID: LLMConversationID,
        operationID: UUID
    ) -> AsyncThrowingStream<String, Error> {
        generationID = operationID
        generationConversationID = conversationID
        isGenerating = true
        let usageStartedAt = Date()

        return AsyncThrowingStream { continuation in
            let task = Task { @MainActor [weak self] in
                var generatedCharacters = 0
                do {
                    guard self?.activeOperationID == operationID else {
                        throw CancellationError()
                    }

                    for try await chunk in source {
                        try Task.checkCancellation()
                        guard self?.activeOperationID == operationID else {
                            throw CancellationError()
                        }
                        generatedCharacters =
                            min(
                                10_000_000,
                                generatedCharacters
                                    + min(
                                        chunk.count,
                                        10_000_000
                                            - generatedCharacters
                                    )
                            )
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                    LocalAIUsageStore
                        .shared.record(
                            .completed,
                            generatedCharacters:
                                generatedCharacters,
                            duration:
                                Date()
                                .timeIntervalSince(
                                    usageStartedAt
                                )
                        )
                } catch is CancellationError {
                    continuation.finish(
                        throwing:
                            CancellationError()
                    )
                    LocalAIUsageStore
                        .shared.record(
                            .cancelled,
                            generatedCharacters:
                                generatedCharacters,
                            duration:
                                Date()
                                .timeIntervalSince(
                                    usageStartedAt
                                )
                        )
                } catch {
                    continuation.finish(throwing: error)
                    LocalAIUsageStore
                        .shared.record(
                            .failed,
                            generatedCharacters:
                                generatedCharacters,
                            duration:
                                Date()
                                .timeIntervalSince(
                                    usageStartedAt
                                )
                        )
                }

                self?.finishGeneration(operationID)
            }

            generationTask = task

            continuation.onTermination = { _ in
                task.cancel()
                Task { @MainActor [weak self] in
                    self?.finishGeneration(operationID)
                }
            }
        }
    }

    private func stopActiveGeneration() async {
        guard let task = generationTask else {
            return
        }

        generationID = nil
        generationConversationID = nil
        generationTask = nil
        isGenerating = false
        task.cancel()

        if let session = activeSession?.session {
            await session.synchronize()
        }
    }

    private func finishGeneration(_ id: UUID) {
        guard generationID == id else {
            return
        }

        generationID = nil
        generationConversationID = nil
        generationTask = nil
        isGenerating = false

        clearOperationIfCurrent(id)
    }
}
