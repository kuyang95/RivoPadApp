import SwiftUI
import ImageIO

private struct ListeningImagesActiveKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var listeningImagesActive: Bool {
        get { self[ListeningImagesActiveKey.self] }
        set { self[ListeningImagesActiveKey.self] = newValue }
    }
}

/// Only decoded thumbnails are cached; original images never enter the persistent library.
@MainActor private final class ListeningArtworkCache {
    static let shared = ListeningArtworkCache()
    private let images = NSCache<NSString, UIImage>()
    private struct Pending {
        let id: UUID
        let task: Task<UIImage?, Never>
        var users: Set<UUID>
    }
    private var pending: [String: Pending] = [:]
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpMaximumConnectionsPerHost = 3
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()
    private init() { images.totalCostLimit = 12 * 1024 * 1024; images.countLimit = 64 }
    func cached(_ value: String?) -> UIImage? { value.flatMap { images.object(forKey: $0 as NSString) } }
    func load(_ value: String) async -> UIImage? {
        guard let url = ListeningCatalog.webURL(value) else { return nil }
        if let cached = images.object(forKey: value as NSString) { return cached }
        let user = UUID()
        var entry = pending[value] ?? Pending(id: UUID(), task: Task { await self.fetch(url) }, users: [])
        entry.users.insert(user)
        pending[value] = entry
        let requestID = entry.id
        let task = entry.task
        return await withTaskCancellationHandler {
            let result = await task.value
            release(value, requestID: requestID, user: user)
            return Task.isCancelled ? nil : result
        } onCancel: {
            Task { @MainActor in self.release(value, requestID: requestID, user: user) }
        }
    }
    private func release(_ value: String, requestID: UUID, user: UUID) {
        guard var entry = pending[value], entry.id == requestID else { return }
        entry.users.remove(user)
        if entry.users.isEmpty { entry.task.cancel(); pending.removeValue(forKey: value) }
        else { pending[value] = entry }
    }
    private func fetch(_ url: URL) async -> UIImage? {
        guard let data = try? await ListeningCatalog.data(url, session: session), !Task.isCancelled else { return nil }
        let decoder = Task.detached(priority: .utility) { () -> CGImage? in
            guard !Task.isCancelled, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 720,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary)
        }
        let decoded = await withTaskCancellationHandler { await decoder.value } onCancel: { decoder.cancel() }
        guard let image = decoded, !Task.isCancelled else { return nil }
        let result = UIImage(cgImage: image)
        images.setObject(result, forKey: url.absoluteString as NSString, cost: image.bytesPerRow * image.height)
        return result
    }
}

struct ListeningArtwork: View {
    let url: String?
    let title: String
    let radio: Bool
    var naturalAspect = false
    @Environment(\.listeningImagesActive) private var active
    @State private var image: UIImage?
    @State private var loadedURL: String?
    @State private var lastAspectRatio: CGFloat?
    private var displayImage: UIImage? {
        guard active else { return nil }
        if loadedURL == url, let image { return image }
        return ListeningArtworkCache.shared.cached(url)
    }
    private var aspectRatio: CGFloat {
        guard naturalAspect else { return 1 }
        guard let image = displayImage, image.size.width > 0, image.size.height > 0 else { return lastAspectRatio ?? (radio ? 16.0 / 9.0 : 1) }
        return image.size.width / image.size.height
    }
    var body: some View {
        GeometryReader { geometry in ZStack {
            if let image = displayImage {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(width: geometry.size.width, height: geometry.size.height)
            } else {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(VisionCraftUI.fixedColor(0xE9EEE7))
                VStack(spacing: 12) {
                    Image(systemName: radio ? "radio" : "waveform").font(.system(size: 36, weight: .light))
                    if geometry.size.width >= 150 {
                        Text(verbatim: title).visionCraftAndroidText(22, weight: .medium).multilineTextAlignment(.center).lineLimit(3)
                    }
                }.foregroundStyle(VisionCraftUI.fixedColor(0x233E30)).padding(16)
            }
        } }
        .aspectRatio(aspectRatio, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityHidden(true)
        .task(id: active ? url : nil) {
            guard active else { image = nil; loadedURL = nil; return }
            guard let url else { image = nil; loadedURL = nil; return }
            if loadedURL != url { image = nil; loadedURL = url }
            let result = await ListeningArtworkCache.shared.load(url)
            guard !Task.isCancelled else { return }
            if naturalAspect, let result, result.size.height > 0 { lastAspectRatio = result.size.width / result.size.height }
            image = result
        }
    }
}
