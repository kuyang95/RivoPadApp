import Foundation
import UIKit
import CoreImage
import Darwin

/// Opt-in debug trials; ordinary scans never persist images or recognized text here.
nonisolated final class ScannerCalibrationRecorder: @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var active: ScannerCalibrationRecorder?
    nonisolated(unsafe) private static var starting = false

    // Call sites supply value snapshots made of JSON primitives and collections.
    private struct EventFields: @unchecked Sendable {
        let values: [String: Any]
    }
    static var current: ScannerCalibrationRecorder? {
        #if DEBUG
        lock.lock(); defer { lock.unlock() }; return active
        #else
        return nil
        #endif
    }
    let directory: URL
    private let queue = DispatchQueue(label: "net.rivo.scanner.calibration", qos: .utility)
    private let eventLock = NSLock()
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private let started = ProcessInfo.processInfo.systemUptime
    private var sequence = 0
    private var captureID = 0
    private var closed = false
    private var frameCount = 0
    private var previewCount = 0
    private var previewAt = 0.0
    // Accessed exclusively on queue.
    private var storageError: String?
    private var eventFile: FileHandle?

    private init(directory: URL) { self.directory = directory }

    static func root() throws -> URL {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("ScannerCalibration", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var excluded = root
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
        return root
    }

    static func start(label: String) throws -> ScannerCalibrationRecorder {
        #if DEBUG
        let reserved = lock.withLock {
            guard active == nil, !starting else { return false }
            starting = true
            return true
        }
        guard reserved else { throw NSError(domain: "ScannerCalibration", code: 1, userInfo: [NSLocalizedDescriptionKey: "진행 중인 테스트를 먼저 종료해 주세요."]) }
        defer { lock.withLock { starting = false } }
        let root = try root()
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey])
        var total = 0
        while let file = files?.nextObject() as? URL { total += (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
        guard total < 1_073_741_824 else { throw NSError(domain: "ScannerCalibration", code: 2, userInfo: [NSLocalizedDescriptionKey: "기록이 1GB를 넘었습니다. 내보낸 기록을 정리해 주세요."]) }
        let dir = root.appendingPathComponent("\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let metadata: [String: Any] = ["schemaVersion": 1, "platform": "ios", "startedAt": ISO8601DateFormatter().string(from: Date()),
            "label": String(label.prefix(1000)), "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "device": deviceModel(), "physicalMemory": ProcessInfo.processInfo.physicalMemory,
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            "measurementNote": "Preview JPEG95 uses the 256 × 256 letterboxed model input, sampled at least 2 seconds apart, up to 30 images. Capture images are JPEG95. Logging may add overhead. Interrupted runs may have no session_end."]
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys]).write(to: dir.appendingPathComponent("metadata.json"), options: .atomic)
        let recorder = ScannerCalibrationRecorder(directory: dir)
        lock.lock(); active = recorder; lock.unlock()
        recorder.event("session_start")
        return recorder
        #else
        throw NSError(domain: "ScannerCalibration", code: 3)
        #endif
    }

    private static func deviceModel() -> String {
        var info = utsname(); uname(&info)
        let capacity = MemoryLayout.size(ofValue: info.machine)
        return withUnsafePointer(to: &info.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
        }
    }

    func event(_ name: String, _ fields: [String: Any] = [:]) {
        eventLock.withLock {
            guard !closed else { return }
            if name == "frame" {
                frameCount += 1
                guard frameCount <= 20_000 else { return }
            }
            enqueueEvent(name, fields)
        }
    }

    // Call with eventLock held to preserve admission order and original timestamps.
    private func envelope(_ name: String, _ fields: [String: Any] = [:]) -> [String: Any] {
        sequence += 1
        var value = fields
        value["schemaVersion"] = 1
        value["event"] = name
        value["seq"] = sequence
        value["elapsedMs"] = (ProcessInfo.processInfo.systemUptime - started) * 1000
        value["captureId"] = captureID
        return value
    }

    private func enqueueEvent(_ name: String, _ fields: [String: Any]) {
        let event = EventFields(values: envelope(name, fields))
        queue.async { [self] in appendEvent(event.values) }
    }

    private func appendEvent(_ fields: [String: Any]) {
        do {
            var data = try JSONSerialization.data(withJSONObject: Self.jsonValue(fields), options: [.sortedKeys])
            data.append(10)
            if eventFile == nil {
                let url = directory.appendingPathComponent("events.jsonl")
                if !FileManager.default.fileExists(atPath: url.path) {
                    try Data().write(to: url)
                }
                let handle = try FileHandle(forWritingTo: url)
                do {
                    try handle.seekToEnd()
                } catch {
                    try? handle.close()
                    throw error
                }
                eventFile = handle
            }
            try eventFile?.write(contentsOf: data)
        } catch {
            storageError = error.localizedDescription
        }
    }

    private static func jsonValue(_ value: Any) -> Any {
        if let number = value as? NSNumber, !number.doubleValue.isFinite { return String(describing: number) }
        if let array = value as? [Any] { return array.map { jsonValue($0) } }
        if let map = value as? [String: Any] { return map.mapValues { jsonValue($0) } }
        return value
    }

    func beginCapture(_ details: String) {
        eventLock.withLock {
            guard !closed else { return }
            captureID += 1
            enqueueEvent("capture_requested", ["details": details])
        }
    }

    func preview(_ tensor: ScannerPreparedTensor) {
        eventLock.withLock {
            let now = ProcessInfo.processInfo.systemUptime
            guard !closed, previewCount < 30, now - previewAt >= 2 else { return }
            guard tensor.shape.count == 4 else { return }
            let height = tensor.shape[2]
            let width = tensor.shape[3]
            let count = width * height
            guard count > 0, tensor.values.count == count * 3 else { return }
            previewAt = now
            previewCount += 1
            enqueueImage(name: "preview-\(previewCount)") { [self] in
                var pixels = [UInt8](repeating: 255, count: count * 4)
                for i in 0..<count {
                    for channel in 0..<3 {
                        let value = tensor.values[channel * count + i] * 255
                        pixels[i * 4 + channel] = UInt8(max(0, min(255, value.rounded())))
                    }
                }
                guard let image = try? ScannerRGBAImage(width: width, height: height, bytes: pixels) else { return nil }
                return makeImage(image)
            }
        }
    }

    func savePixels(_ image: ScannerRGBAImage, name: String) {
        eventLock.withLock {
            guard !closed else { return }
            enqueueImage(name: name) { [self] in makeImage(image) }
        }
    }

    func saveImage(_ image: UIImage, name: String) {
        eventLock.withLock {
            guard !closed else { return }
            enqueueImage(name: name) { image }
        }
    }

    private func makeImage(_ image: ScannerRGBAImage) -> UIImage? {
        let ciImage = ScannerCIImageBridge().ciImage(from: image)
        return imageContext.createCGImage(ciImage, from: ciImage.extent).map { UIImage(cgImage: $0) }
    }

    private func enqueueImage(name: String, makeImage: @escaping @Sendable () -> UIImage?) {
        let event = EventFields(values: envelope("artifact_queued"))
        let file = "capture-\(captureID)-\(name)-\(sequence).jpg"
        queue.async { [self] in
            var fields = event.values
            fields["file"] = file
            let start = ProcessInfo.processInfo.systemUptime
            guard let image = makeImage(), let data = image.jpegData(compressionQuality: 0.95) else {
                fields["event"] = "artifact_error"
                storageError = "이미지를 JPEG로 변환할 수 없습니다."
                appendEvent(fields)
                return
            }
            fields["width"] = image.cgImage?.width ?? Int(image.size.width * image.scale)
            fields["height"] = image.cgImage?.height ?? Int(image.size.height * image.scale)
            fields["encodeMs"] = (ProcessInfo.processInfo.systemUptime - start) * 1000
            appendEvent(fields)
            do {
                try data.write(to: directory.appendingPathComponent(file), options: .atomic)
            } catch {
                storageError = error.localizedDescription
            }
        }
    }

    func finish() async -> String? {
        await withCheckedContinuation { continuation in
            eventLock.withLock {
                let firstClose = !closed
                let frames = frameCount
                if firstClose {
                    enqueueEvent("session_end", ["frames": frames])
                    closed = true
                }
                queue.async { [self] in
                    if firstClose {
                        do { try eventFile?.close() }
                        catch { storageError = error.localizedDescription }
                        eventFile = nil
                        do {
                            let status: [String: Any] = [
                                "state": storageError == nil ? "closed" : "storage_error",
                                "storageError": storageError ?? "",
                                "frames": frames,
                            ]
                            try JSONSerialization.data(withJSONObject: status)
                                .write(to: directory.appendingPathComponent("status.json"), options: .atomic)
                        } catch {
                            storageError = error.localizedDescription
                        }
                        Self.lock.withLock { if Self.active === self { Self.active = nil } }
                    }
                    continuation.resume(returning: storageError)
                }
            }
        }
    }
}
