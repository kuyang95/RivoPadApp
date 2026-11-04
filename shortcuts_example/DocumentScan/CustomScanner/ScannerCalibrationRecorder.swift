import Foundation
import UIKit
import CoreImage
import Darwin

/// Opt-in debug trials; ordinary scans never persist images or recognized text here.
nonisolated final class ScannerCalibrationRecorder: @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var active: ScannerCalibrationRecorder?
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
    private var storageError: String?

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
        guard current == nil else { throw NSError(domain: "ScannerCalibration", code: 1, userInfo: [NSLocalizedDescriptionKey: "진행 중인 테스트를 먼저 종료해 주세요."]) }
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
            "measurementNote": "Debug image serialization adds overhead. Preview <=640px every 2s, max30; capture JPEG95. Interrupted runs may have no session_end."]
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
        eventLock.lock(); defer { eventLock.unlock() }
        guard !closed else { return }
        if name == "frame" { frameCount += 1; if frameCount > 20_000 { return } }
        sequence += 1
        var value = fields
        value["schemaVersion"] = 1; value["event"] = name; value["seq"] = sequence
        value["elapsedMs"] = (ProcessInfo.processInfo.systemUptime - started) * 1000
        value["captureId"] = captureID
        guard var bytes = try? JSONSerialization.data(withJSONObject: Self.jsonValue(value), options: [.sortedKeys, .fragmentsAllowed]) else { return }
        bytes.append(10)
        let data = bytes
        queue.async { [self] in
            do {
                let url = directory.appendingPathComponent("events.jsonl")
                if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd(); try handle.write(contentsOf: data)
            } catch { storageError = error.localizedDescription }
        }
    }

    private static func jsonValue(_ value: Any) -> Any {
        if let number = value as? NSNumber, !number.doubleValue.isFinite { return String(describing: number) }
        if let array = value as? [Any] { return array.map { jsonValue($0) } }
        if let map = value as? [String: Any] { return map.mapValues { jsonValue($0) } }
        return value
    }

    func beginCapture(_ details: String) {
        eventLock.lock(); captureID += 1; eventLock.unlock()
        event("capture_requested", ["details": details])
    }

    func preview(_ tensor: ScannerPreparedTensor) {
        eventLock.lock()
        let now = ProcessInfo.processInfo.systemUptime
        let shouldSave = !closed && previewCount < 30 && now - previewAt >= 2
        if shouldSave { previewAt = now; previewCount += 1 }
        let index = previewCount
        eventLock.unlock()
        guard shouldSave else { return }
        guard tensor.shape.count == 4 else { return }
        let height = tensor.shape[2], width = tensor.shape[3], count = width * height
        guard tensor.values.count == count * 3 else { return }
        var pixels = [UInt8](repeating: 255, count: count * 4)
        for i in 0..<count { for c in 0..<3 { pixels[i*4+c] = UInt8(max(0, min(255, (tensor.values[c*count+i]*255).rounded()))) } }
        if let image = try? ScannerRGBAImage(width: width, height: height, bytes: pixels) { savePixels(image, name: "preview-\(index)") }
    }

    func savePixels(_ image: ScannerRGBAImage, name: String) {
        let ciImage = ScannerCIImageBridge().ciImage(from: image)
        guard let cgImage = imageContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        saveImage(UIImage(cgImage: cgImage), name: name)
    }

    func saveImage(_ image: UIImage, name: String) {
        eventLock.lock()
        guard !closed else { eventLock.unlock(); return }
        sequence += 1
        let file = "capture-\(captureID)-\(name)-\(sequence).jpg"
        eventLock.unlock()
        // Capture encoded bytes before returning; callers may discard their camera buffers.
        let begin = ProcessInfo.processInfo.systemUptime
        guard let data = image.jpegData(compressionQuality: 0.95) else { event("artifact_error", ["file": file]); return }
        event("artifact_queued", ["file": file, "width": image.size.width, "height": image.size.height,
            "encodeMs": (ProcessInfo.processInfo.systemUptime-begin)*1000])
        queue.async { [self] in
            do { try data.write(to: directory.appendingPathComponent(file), options: .atomic) }
            catch { storageError = error.localizedDescription }
        }
    }

    func finish() async {
        event("session_end", ["frames": frameCount])
        eventLock.withLock { closed = true }
        Self.lock.withLock { if Self.active === self { Self.active = nil } }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                let value: [String: Any] = ["state": storageError == nil ? "closed" : "storage_error", "storageError": storageError ?? "", "frames": frameCount]
                if let data = try? JSONSerialization.data(withJSONObject: value) { try? data.write(to: directory.appendingPathComponent("status.json"), options: .atomic) }
                continuation.resume()
            }
        }
    }
}
