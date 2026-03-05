import Foundation
import Combine
import SwiftUI
import UIKit

@MainActor
final class ShortcutRouter: ObservableObject {

    enum Destination: Identifiable {
        case compareTwoTexts(text1: String, text2: String)
        case importImage(url: URL)

        var id: String {
            switch self {
            case .compareTwoTexts(let a, let b):
                return "compare:\(a.hashValue):\(b.hashValue)"
            case .importImage(let url):
                return "image:\(url.absoluteString)"
            }
        }
    }

    @Published var destination: Destination?

    // JSONValue에서 String 꺼내는 헬퍼
    private func stringParam(_ key: String, from env: ShortcutEnvelope) -> String? {
        guard let v = env.params[key] else { return nil }
        if case .string(let s) = v { return s }
        return nil
    }

    func consumeLastIfNeeded() {
        // ✅ 마지막 1개만 가져오기 (없으면 return)
        guard let env = ShortcutBridge.takeLastEnvelope() else { return }

        switch env.route {

        case .compareTwoTexts:
            let t1 = stringParam("text1", from: env) ?? ""
            let t2 = stringParam("text2", from: env) ?? ""
            destination = .compareTwoTexts(text1: t1, text2: t2)

        case .importImage:
            guard let ref = env.attachments.first(where: { $0.kind == .image }) else { return }
            let url = ShortcutBridge.attachmentsDirURL().appendingPathComponent(ref.fileName)
            destination = .importImage(url: url)

        case .documentScanning:
            // 필요하면 다른 화면으로 보내거나 처리
            destination = nil
        }
    }

    // (선택) 홈으로 돌아가고 싶을 때
    func reset() {
        destination = nil
    }
}

import Foundation

enum ShortcutRoute: String, Codable {
    case compareTwoTexts
    case importImage
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
    static let suiteName = "group.com.yourcompany.yourapp"
    static let lastKey = "shortcut_last_envelope_v1"
    private static let lockQ = DispatchQueue(label: "ShortcutBridge.lock")

    // attachments는 항상 이 폴더에 "마지막 1개"만 유지
    static func attachmentsDirURL() -> URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName)!
        let dir = base.appendingPathComponent("ShortcutLastAttachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 새 인텐트 저장 시작할 때 호출: (1) 이전 Envelope 덮어쓸 준비, (2) 이전 attachments 싹 삭제
    static func beginNewLastEnvelope() {
        lockQ.sync {
            // attachments 폴더 비우기
            let dir = attachmentsDirURL()
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for f in files { try? FileManager.default.removeItem(at: f) }
        }
    }

    /// “마지막 Envelope” 메타데이터 저장(덮어쓰기)
    static func saveLastEnvelope(_ env: ShortcutEnvelope) {
        lockQ.sync {
            guard let ud = UserDefaults(suiteName: suiteName) else { return }
            guard let data = try? JSONEncoder().encode(env) else { return }
            ud.set(data, forKey: lastKey)
        }
    }

    /// 마지막 Envelope 읽기(삭제 안 함)
    static func peekLastEnvelope() -> ShortcutEnvelope? {
        lockQ.sync {
            guard let ud = UserDefaults(suiteName: suiteName),
                  let data = ud.data(forKey: lastKey),
                  let env = try? JSONDecoder().decode(ShortcutEnvelope.self, from: data)
            else { return nil }
            return env
        }
    }

    /// 마지막 Envelope “가져오면서” key 삭제 (주의: attachments는 아직 남아있음)
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
}

