//
//  LLMService.swift
//  shortcuts_example
//
//  Created by meee on 2/5/26.
//

import Foundation
import Hub
import MLXLMCommon
import MLX
import MLXLLM
import MLXVLM
import Combine
import CoreImage

enum LoadedModel: Equatable {
    case none
    case qwen3_8b_4bit
    case qwen3_vl_8b_4bit

    var displayName: String {
        switch self {
        case .none: return "None"
        case .qwen3_8b_4bit: return "Qwen3-8B-4bit"
        case .qwen3_vl_8b_4bit: return "Qwen3-VL-8B-Instruct-4bit"
        }
    }
}

@MainActor
final class LLMService: ObservableObject {

    static let shared = LLMService()

    @Published var isLoading = false
    @Published var isGenerating = false
    @Published private(set) var loadedModel: LoadedModel = .none

    private var session: ChatSession?
    private var generationTask: Task<Void, Never>?

    var isReady: Bool {
        session != nil && loadedModel != .none && !isLoading
    }

    // MARK: - Local model store

    private lazy var modelStoreURL: URL = {
        let base = try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("HFModels", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private struct LocalModelSpec {
        let kind: LoadedModel
        let repoId: String
        let isVision: Bool
    }

    private func spec(for target: LoadedModel) -> LocalModelSpec? {
        switch target {
        case .none:
            return nil

        case .qwen3_8b_4bit:
            return .init(
                kind: .qwen3_8b_4bit,
                repoId: "mlx-community/Qwen3-8B-4bit",
                isVision: false
            )

        case .qwen3_vl_8b_4bit:
            return .init(
                kind: .qwen3_vl_8b_4bit,
                repoId: "mlx-community/Qwen3-VL-8B-Instruct-4bit",
                isVision: true
            )
        }
    }

    private func makeHub(offlineOnly: Bool) -> HubApi {
        HubApi(
            downloadBase: modelStoreURL,
            useOfflineMode: offlineOnly
        )
    }

    // MARK: - Memory config

    func configureForIPadProM4_8GB() {
        let gb = 1024 * 1024 * 1024
        Memory.memoryLimit = 5 * gb
        Memory.cacheLimit = 20 * 1024 * 1024
    }

    func configureForIPadProM4_12GB() {
        let gb = 1024 * 1024 * 1024
        Memory.memoryLimit = 5 * gb
        Memory.cacheLimit = 20 * 1024 * 1024
    }

    // MARK: - Local resolve / download

    private func resolveLocalModelDirectory(
        for spec: LocalModelSpec,
        allowDownload: Bool
    ) async throws -> URL {

        RVLogger.d("📦 모델 확인 시작: \(spec.repoId)")
        RVLogger.d("📁 modelStoreURL: \(modelStoreURL.path)")

        // 1) 먼저 오프라인으로 로컬 설치본 확인
        do {
            let offlineHub = makeHub(offlineOnly: true)
            let localURL = try await offlineHub.snapshot(from: spec.repoId, matching: "*")
            RVLogger.d("✅ 로컬 모델 발견: \(localURL.path)")
            return localURL
        } catch {
            RVLogger.d("ℹ️ 로컬 모델 없음 또는 메타데이터 불완전: \(spec.repoId)")
            guard allowDownload else { throw error }
        }

        // 2) 없으면 그때만 다운로드
        RVLogger.d("⬇️ 다운로드 시작: \(spec.repoId)")

        let onlineHub = makeHub(offlineOnly: false)

        var lastLoggedPercent = -1

        let downloadedURL = try await onlineHub.snapshot(
            from: spec.repoId,
            matching: "*"
        ) { progress in
            let percent = Int(progress.fractionCompleted * 100)

            // 로그 과다 방지: 5% 단위 + 100%
            if percent >= lastLoggedPercent + 5 || percent == 100 {
                lastLoggedPercent = percent
                RVLogger.d(
                    "⬇️ [\(spec.repoId)] 다운로드 진행률: \(percent)% " +
                    "(\(progress.completedUnitCount)/\(progress.totalUnitCount))"
                )
            }
        }

        RVLogger.d("✅ 다운로드 완료: \(downloadedURL.path)")
        return downloadedURL
    }

    // MARK: - Load

    private func loadSession(
        for target: LoadedModel,
        allowDownloadIfNeeded: Bool
    ) async throws -> ChatSession {

        guard let spec = spec(for: target) else {
            throw NSError(
                domain: "LLMService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "잘못된 모델 타입입니다."]
            )
        }

        let modelDir = try await resolveLocalModelDirectory(
            for: spec,
            allowDownload: allowDownloadIfNeeded
        )

        do {
            return try await makeChatSession(from: modelDir, spec: spec)

        } catch {
            RVLogger.d("❌ 1차 로컬 로드 실패: \(error)")

            guard allowDownloadIfNeeded else {
                throw error
            }

            RVLogger.d("🛠️ 로컬 캐시 삭제 후 재다운로드를 시도합니다: \(spec.repoId)")

            do {
                try deleteLocalModelCache(for: spec, resolvedModelDir: modelDir)
            } catch {
                RVLogger.d("⚠️ 캐시 삭제 중 오류: \(error)")
            }

            Memory.clearCache()
            await Task.yield()

            let redownloadedDir = try await redownloadModelDirectory(for: spec)

            do {
                return try await makeChatSession(from: redownloadedDir, spec: spec)
            } catch {
                RVLogger.d("❌ 재다운로드 후 로드도 실패: \(error)")
                throw error
            }
        }
    }

    // MARK: - Activate / Unload

    func activateModel(_ target: LoadedModel) async throws {
        if isLoading { return }
        if loadedModel == target, session != nil { return }

        isLoading = true
        defer { isLoading = false }

        // 1) 생성 중지
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false

        // 2) 기존 세션 해제
        session = nil
        loadedModel = .none

        // 3) MLX 캐시 비우기
        Memory.clearCache()

        RVLogger.d("🧹 clearCache 이후")
        RVLogger.d(Memory.snapshot().description)

        // 4) 해제/캐시정리 타이밍 한 번 양보
        await Task.yield()

        RVLogger.d("🚀 모델 활성화 시작: \(target.displayName)")

        switch target {
        case .none:
            RVLogger.d("ℹ️ target == .none 이므로 로드 없이 종료")
            return

        case .qwen3_8b_4bit:
            let newSession = try await loadSession(
                for: .qwen3_8b_4bit,
                allowDownloadIfNeeded: true
            )
            session = newSession
            loadedModel = .qwen3_8b_4bit

        case .qwen3_vl_8b_4bit:
            let newSession = try await loadSession(
                for: .qwen3_vl_8b_4bit,
                allowDownloadIfNeeded: true
            )
            session = newSession
            loadedModel = .qwen3_vl_8b_4bit
        }

        RVLogger.d("✅ 새 모델 활성화 완료: \(loadedModel.displayName)")
        RVLogger.d(Memory.snapshot().description)
    }
    
    private func makeChatSession(
        from modelDir: URL,
        spec: LocalModelSpec
    ) async throws -> ChatSession {

        RVLogger.d("🧠 로드 시작: \(spec.repoId)")
        RVLogger.d("📂 로드 경로: \(modelDir.path)")

        let cfg = ModelConfiguration(directory: modelDir)
        let hub = makeHub(offlineOnly: true)

        var lastLoggedPercent = -1

        if spec.isVision {
            let container = try await VLMModelFactory.shared.loadContainer(
                hub: hub,
                configuration: cfg
            ) { progress in
                let percent = Int(progress.fractionCompleted * 100)

                if percent >= lastLoggedPercent + 5 || percent == 100 {
                    lastLoggedPercent = percent
                    RVLogger.d("🧠 [\(spec.repoId)] VLM 로드 진행률: \(percent)%")
                }
            }

            RVLogger.d("✅ VLM 로드 완료: \(spec.repoId)")
            return ChatSession(container)

        } else {
            let container = try await LLMModelFactory.shared.loadContainer(
                hub: hub,
                configuration: cfg
            ) { progress in
                let percent = Int(progress.fractionCompleted * 100)

                if percent >= lastLoggedPercent + 5 || percent == 100 {
                    lastLoggedPercent = percent
                    RVLogger.d("🧠 [\(spec.repoId)] LLM 로드 진행률: \(percent)%")
                }
            }

            RVLogger.d("✅ LLM 로드 완료: \(spec.repoId)")
            return ChatSession(container)
        }
    }

    private func redownloadModelDirectory(
        for spec: LocalModelSpec
    ) async throws -> URL {

        RVLogger.d("⬇️ 복구용 재다운로드 시작: \(spec.repoId)")

        let onlineHub = makeHub(offlineOnly: false)
        var lastLoggedPercent = -1

        let downloadedURL = try await onlineHub.snapshot(
            from: spec.repoId,
            matching: "*"
        ) { progress in
            let percent = Int(progress.fractionCompleted * 100)

            if percent >= lastLoggedPercent + 5 || percent == 100 {
                lastLoggedPercent = percent
                RVLogger.d(
                    "⬇️ [\(spec.repoId)] 복구 다운로드 진행률: \(percent)% " +
                    "(\(progress.completedUnitCount)/\(progress.totalUnitCount))"
                )
            }
        }

        RVLogger.d("✅ 복구 다운로드 완료: \(downloadedURL.path)")
        return downloadedURL
    }
    
    private func deleteLocalModelCache(
        for spec: LocalModelSpec,
        resolvedModelDir: URL?
    ) throws {

        let fm = FileManager.default

        var targets: [URL] = []

        if let resolvedModelDir {
            targets.append(resolvedModelDir)
        }

        let repoDir = modelStoreURL
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent(spec.repoId, isDirectory: true)

        targets.append(repoDir)

        var removedPaths = Set<String>()

        for url in targets {
            let path = url.path

            guard !removedPaths.contains(path) else { continue }
            guard fm.fileExists(atPath: path) else { continue }

            RVLogger.d("🗑️ 로컬 모델 캐시 삭제: \(path)")
            try fm.removeItem(at: url)
            removedPaths.insert(path)
        }
    }


    func unloadCurrentModel() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false

        session = nil
        loadedModel = .none
        Memory.clearCache()

        RVLogger.d("🗑️ unload 완료")
        RVLogger.d(Memory.snapshot().description)
    }

    // MARK: - Respond / Stream

    func respond(_ prompt: String) async throws -> String {
        guard let session else {
            throw NSError(domain: "LLM", code: 1)
        }

        isGenerating = true
        defer { isGenerating = false }

        return try await session.respond(to: prompt)
    }

    func streamText(system: String, prompt: String) async throws -> AsyncThrowingStream<String, Error> {
        guard let session else {
            throw NSError(domain: "LLM", code: 1)
        }

        session.instructions = system
        isGenerating = true

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let stream = session.streamResponse(to: prompt)
                    for try await chunk in stream {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }

                await MainActor.run {
                    self.isGenerating = false
                    self.generationTask = nil
                }
            }

            self.generationTask = task

            continuation.onTermination = { _ in
                task.cancel()
                Task { @MainActor in
                    self.isGenerating = false
                    self.generationTask = nil
                }
            }
        }
    }

    func streamVision(system: String, prompt: String, images: [CIImage]) async throws -> AsyncThrowingStream<String, Error> {
        guard let session else {
            throw NSError(domain: "LLM", code: 1)
        }

        session.instructions = system
        isGenerating = true

        let uiImages: [UserInput.Image] = images.map { .ciImage($0) }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let stream = session.streamResponse(to: prompt, images: uiImages, videos: [])
                    for try await chunk in stream {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }

                await MainActor.run {
                    self.isGenerating = false
                    self.generationTask = nil
                }
            }

            self.generationTask = task

            continuation.onTermination = { _ in
                task.cancel()
                Task { @MainActor in
                    self.isGenerating = false
                    self.generationTask = nil
                }
            }
        }
    }
}
