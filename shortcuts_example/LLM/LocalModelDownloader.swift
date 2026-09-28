import Foundation
import Hub
import HuggingFace

/// Combines completed files with the downloader's live byte count. The latter
/// includes data still in URLSession's temporary file, outside HFModels.
struct LocalModelDownloadTracker {
    let model: LocalModelMetadata
    let completedFileBytes: Int64
    private var previousBytes: Int64?
    private var previousTime: TimeInterval?

    init(model: LocalModelMetadata, completedFileBytes: Int64) {
        self.model = model
        self.completedFileBytes = completedFileBytes
    }

    mutating func sample(
        fileProgress: Progress,
        fileSize: Int64,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> LocalModelDownloadProgress {
        let currentBytes = min(max(fileProgress.completedUnitCount, 0), fileSize)
        var speed: Double?
        if let previousBytes, let previousTime,
           now > previousTime, currentBytes > previousBytes {
            speed = Double(currentBytes - previousBytes) / (now - previousTime)
        }
        previousBytes = currentBytes
        previousTime = now
        return .init(
            model: model,
            downloadedBytes: completedFileBytes + currentBytes,
            bytesPerSecond: speed
        )
    }

}

@MainActor
enum LocalModelDownloader {
    private struct File {
        let name: String
        let commit: String
        let etag: String
        let size: Int64
        let destination: URL
        let metadataDestination: URL
        let isDownloaded: Bool
    }

    static func download(
        repoID: String,
        displayName: String,
        hub: HubApi,
        onProgress: @escaping @MainActor (LocalModelDownloadProgress) -> Void
    ) async throws -> URL {
        let client = HuggingFace.HubClient.default
        guard let repository = HuggingFace.Repo.ID(rawValue: repoID) else {
            throw HubApi.EnvironmentError.invalidMetadataError(repoID)
        }
        let destination = hub.localRepoLocation(Hub.Repo(id: repoID))
        let metadataDirectory = destination.appending(path: ".cache/huggingface/download")
        let names = try await hub.getFilenames(from: repoID).sorted()
        var files = [File]()
        var revision = "main"

        for name in names {
            try Task.checkCancellation()
            let source = client.host.appending(path: repoID)
                .appending(path: "resolve").appending(component: revision)
                .appending(path: name)
            let metadata = try await hub.getFileMetadata(url: source)
            guard let size = metadata.size, size >= 0,
                  let commit = metadata.commitHash,
                  let etag = metadata.etag else {
                throw HubApi.EnvironmentError.invalidMetadataError(name)
            }
            revision = commit
            let fileDestination = destination.appending(path: name)
            let metadataDestination = metadataDirectory.appending(path: name + ".metadata")
            let localMetadata = try hub.readDownloadMetadata(metadataPath: metadataDestination)
            let attributes = try? FileManager.default.attributesOfItem(atPath: fileDestination.path)
            let isDownloaded = attributes?[.type] as? FileAttributeType == .typeRegular
                && (attributes?[.size] as? NSNumber)?.int64Value == Int64(size)
                && localMetadata?.etag == etag
            files.append(.init(
                name: name, commit: commit, etag: etag, size: Int64(size),
                destination: fileDestination, metadataDestination: metadataDestination,
                isDownloaded: isDownloaded
            ))
        }

        let model = LocalModelMetadata(
            displayName: displayName,
            expectedDownloadBytes: files.reduce(0) { $0 + $1.size }
        )
        var completedBytes = files.filter(\.isDownloaded).reduce(0) { $0 + $1.size }
        onProgress(.init(model: model, downloadedBytes: completedBytes, bytesPerSecond: nil))

        for file in files {
            try Task.checkCancellation()
            if !file.isDownloaded {
                try await downloadFile(
                    file, repo: repository, client: client,
                    model: model, completedBytes: completedBytes,
                    onProgress: onProgress
                )
                completedBytes += file.size
            }
            // Retain HubApi's metadata format so existing offline validation
            // and previously installed models continue to work.
            try hub.writeDownloadMetadata(
                commitHash: file.commit, etag: file.etag,
                metadataPath: file.metadataDestination
            )
            onProgress(.init(model: model, downloadedBytes: completedBytes, bytesPerSecond: nil))
        }
        try Task.checkCancellation()
        return destination
    }

    private static func downloadFile(
        _ file: File,
        repo: HuggingFace.Repo.ID,
        client: HuggingFace.HubClient,
        model: LocalModelMetadata,
        completedBytes: Int64,
        onProgress: @escaping @MainActor (LocalModelDownloadProgress) -> Void
    ) async throws {
        let progress = Progress(totalUnitCount: file.size)
        let monitor = Task { @MainActor in
            var tracker = LocalModelDownloadTracker(model: model, completedFileBytes: completedBytes)
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(200))
                    try Task.checkCancellation()
                } catch {
                    return
                }
                onProgress(tracker.sample(fileProgress: progress, fileSize: file.size))
            }
        }
        defer { monitor.cancel() }

        _ = try await client.downloadFile(
            at: file.name, from: repo, to: file.destination,
            revision: file.commit, progress: progress
        )
        try Task.checkCancellation()
    }
}
