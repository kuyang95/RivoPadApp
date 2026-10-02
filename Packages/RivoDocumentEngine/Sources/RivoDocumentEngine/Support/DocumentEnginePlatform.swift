import Foundation

/// Policies intentionally preserve the three different existing HWP metrics.
/// A platform must not silently turn replacement, formatting and body flow
/// into one measurement algorithm: line caches are part of the saved document.
public enum HWPTextMeasurementPolicy: Sendable {
    case replacement, formatting, flow, listMarker
}

public struct HWPTextMeasurementRequest: Sendable {
    public let runs: [HWPDocumentTextRun]
    public let fallbackFontSize: Double
    public let policy: HWPTextMeasurementPolicy
    public init(runs: [HWPDocumentTextRun], fallbackFontSize: Double, policy: HWPTextMeasurementPolicy) {
        self.runs = runs
        self.fallbackFontSize = fallbackFontSize
        self.policy = policy
    }
}

/// All ranges and returned lengths are UTF-16, never glyph or byte offsets.
/// A session owns one paragraph's shaping context and supports varying widths
/// as the shared flow algorithm encounters floating objects and columns.
public protocol HWPTextMeasurementSession: AnyObject {
    var string: String { get }
    func suggestLineBreak(atUTF16 offset: Int, widthPoints: Double) -> Int
    func scriptLineHeight(inUTF16 range: NSRange, runs: [HWPDocumentTextRun], minimumPoints: Double) -> Double
    func isMetricEquivalent(to other: any HWPTextMeasurementSession) -> Bool
    var typographicWidthPoints: Double { get }
}

public protocol HWPTextMeasurementProvider: Sendable {
    func makeSession(_ request: HWPTextMeasurementRequest) -> any HWPTextMeasurementSession
}

public struct DocumentEngineImageMetadata: Sendable, Equatable {
    public let pixelWidth: Int
    public let pixelHeight: Int
    public init(pixelWidth: Int, pixelHeight: Int) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

public protocol DocumentEngineImageProvider: Sendable {
    /// Dimensions of the original bitmap before applying its EXIF orientation.
    func metadata(of data: Data) -> DocumentEngineImageMetadata?
    func normalizeHWPImage(_ data: Data) throws -> HWPImageEditing.ImportedImage
}

public enum DocumentEnginePlatform {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var text: (any HWPTextMeasurementProvider)?
        var images: (any DocumentEngineImageProvider)?
        var localize: @Sendable (String) -> String = { $0 }
        var locale: @Sendable () -> Locale = { .current }
    }
    private static let state = State()

    /// Install once during app bootstrap, before opening a document. Providers
    /// are snapshotted under a lock; their work is performed outside that lock.
    public static func configure(
        textMeasurement: any HWPTextMeasurementProvider,
        imageProcessing: any DocumentEngineImageProvider,
        localize: @escaping @Sendable (String) -> String = { $0 },
        locale: @escaping @Sendable () -> Locale = { .current }
    ) {
        state.lock.lock()
        state.text = textMeasurement
        state.images = imageProcessing
        state.localize = localize
        state.locale = locale
        state.lock.unlock()
    }

    public static func textSession(_ request: HWPTextMeasurementRequest) -> any HWPTextMeasurementSession {
        state.lock.lock()
        let provider = state.text
        state.lock.unlock()
        guard let provider else {
            preconditionFailure("Install a HWPTextMeasurementProvider before editing or reflowing HWP text")
        }
        return provider.makeSession(request)
    }

    public static func imageMetadata(of data: Data) -> DocumentEngineImageMetadata? {
        state.lock.lock()
        let provider = state.images
        state.lock.unlock()
        return provider?.metadata(of: data)
    }

    public static func normalizeHWPImage(_ data: Data) throws -> HWPImageEditing.ImportedImage {
        state.lock.lock()
        let provider = state.images
        state.lock.unlock()
        guard let provider else { throw HWPDocumentEditingError.unsupportedEdit }
        return try provider.normalizeHWPImage(data)
    }

    public static func localizedString(_ key: String) -> String {
        state.lock.lock()
        let localize = state.localize
        state.lock.unlock()
        return localize(key)
    }
    public static var locale: Locale {
        state.lock.lock()
        let locale = state.locale
        state.lock.unlock()
        return locale()
    }
}

public enum DocumentEngineLocalization {
    public static func string(_ key: String) -> String { DocumentEnginePlatform.localizedString(key) }
    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: locale, arguments: arguments)
    }
    public static var locale: Locale { DocumentEnginePlatform.locale }
}
