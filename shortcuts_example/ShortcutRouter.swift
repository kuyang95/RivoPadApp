import Foundation
import Combine
import SwiftUI
import UIKit

@MainActor
final class ShortcutRouter: ObservableObject {

    enum IntentEvent: Hashable {
        case documentQA(text1: String, text2: String, token: UUID)
        case importImage(url: URL, token: UUID)
        case imageQA(url: URL, question: String, token: UUID) 
        case documentScanning
    }

    @Published var intentEvent: IntentEvent?

    func consumeLastIfNeeded() {
        
        guard let env = ShortcutBridge.takeLastEnvelope() else { return }
        let token = UUID()

        RVLogger.d("consumeLastIfNeeded \(env.route)")
        
        switch env.route {

        case .documentQA:
            let t1 = (env.params["text1"]).flatMap {
                if case .string(let s) = $0 { return s }
                return nil
            } ?? ""

            let t2 = (env.params["text2"]).flatMap {
                if case .string(let s) = $0 { return s }
                return nil
            } ?? ""

            intentEvent = .documentQA(text1: t1, text2: t2, token: token)
            
        case .imageQA:

            guard let ref = env.attachments.first(where: { $0.kind == .image }) else { return }

            let dir = ShortcutBridge.attachmentsDir(for: env.id)
            let url = dir.appendingPathComponent(ref.fileName)

            guard FileManager.default.fileExists(atPath: url.path) else {
                print("⚠️ imageQA attachment missing")
                return
            }

            let question = (env.params["question"]).flatMap {
                if case .string(let s) = $0 { return s }
                return nil
            } ?? ""

            RVLogger.d("intent는? \(url), \(question)")
            intentEvent = .imageQA(url: url, question: question, token: token)


        case .importImage:

            guard let ref = env.attachments.first(where: { $0.kind == .image }) else { return }

            let dir = ShortcutBridge.attachmentsDir(for: env.id)
            let url = dir.appendingPathComponent(ref.fileName)

            guard FileManager.default.fileExists(atPath: url.path) else {
                print("⚠️ attachment file missing")
                return
            }

            intentEvent = .importImage(url: url, token: token)

        case .documentScanning:
            intentEvent = .documentScanning
        }

        // 🔥 consume 이후 안전하게 삭제
       // ShortcutBridge.cleanupAttachments(for: env.id)
    }

    func reset() {
        intentEvent = nil
    }
}


import Foundation

enum ShortcutRoute: String, Codable {
    case documentQA
    case importImage
    case imageQA
    case documentScanning
}

// 필요하면 JSONValue는 이전에 쓰던 그대로 사용
enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        throw DecodingError.typeMismatch(JSONValue.self, .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON"))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}

struct AttachmentRef: Codable {
    enum Kind: String, Codable { case image, file }
    let kind: Kind
    let fileName: String      // attachments 폴더 안의 파일명
    let uti: String?
}

struct ShortcutEnvelope: Codable {
    let id: UUID
    let route: ShortcutRoute
    let createdAt: Date
    let schemaVersion: Int
    var params: [String: JSONValue]
    var attachments: [AttachmentRef]
}

enum ShortcutBridge {

    static let suiteName = "group.com.rivo.shortcuts.example"
    static let lastKey = "shortcut_last_envelope_v1"
    private static let lockQ = DispatchQueue(label: "ShortcutBridge.lock")

    // MARK: - Base Directory

    private static func baseDir() -> URL {
        let base = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: suiteName)!
        return base.appendingPathComponent("ShortcutEnvelopes", isDirectory: true)
    }

    static func attachmentsDir(for id: UUID) -> URL {
        let dir = baseDir().appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Replace

    static func replaceLastEnvelope(_ env: ShortcutEnvelope) async {

        await withCheckedContinuation { continuation in
            lockQ.async {

                let fm = FileManager.default
                let base = baseDir()
                try? fm.createDirectory(at: base, withIntermediateDirectories: true)

                let ud = UserDefaults(suiteName: suiteName)

                // 🔥 1. 이전 envelope 읽기
                if let data = ud?.data(forKey: lastKey),
                   let oldEnv = try? JSONDecoder().decode(ShortcutEnvelope.self, from: data) {

                    let oldDir = base.appendingPathComponent(oldEnv.id.uuidString)
                    try? fm.removeItem(at: oldDir)
                }

                // 🔥 2. 새 envelope 저장
                if let encoded = try? JSONEncoder().encode(env) {
                    ud?.set(encoded, forKey: lastKey)
                    ud?.synchronize()
                }

                continuation.resume()
            }
        }
    }

    // MARK: - Peek

    static func peekLastEnvelope() -> ShortcutEnvelope? {
        lockQ.sync {
            guard let ud = UserDefaults(suiteName: suiteName),
                  let data = ud.data(forKey: lastKey),
                  let env = try? JSONDecoder().decode(ShortcutEnvelope.self, from: data)
            else { return nil }
            return env
        }
    }

    // MARK: - Take

    static func takeLastEnvelope() -> ShortcutEnvelope? {
        lockQ.sync {
            guard let ud = UserDefaults(suiteName: suiteName),
                  let data = ud.data(forKey: lastKey),
                  let env = try? JSONDecoder().decode(ShortcutEnvelope.self, from: data)
            else { return nil }

            ud.removeObject(forKey: lastKey)
            return env
        }
    }

    // MARK: - Cleanup

    static func cleanupAttachments(for id: UUID) {
        lockQ.async {
            let dir = baseDir().appendingPathComponent(id.uuidString)
            try? FileManager.default.removeItem(at: dir)
        }
    }
}

