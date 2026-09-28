#if DEBUG
import CryptoKit
import Foundation
import SwiftUI

nonisolated struct HWPComparisonReviewNote: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case unchecked, viewerIssue, sourceDifference
        var id: String { rawValue }
        var title: String {
            switch self {
            case .unchecked: "확인 필요"
            case .viewerIssue: "뷰어 문제"
            case .sourceDifference: "원본 자료 차이"
            }
        }
    }
    var kind: Kind
    var text: String
}

/// Notes belong to the exact source/reference pair, not its filename. Replacing
/// either file must never carry a previously verified explanation onto new data.
nonisolated struct HWPComparisonReviewStore: Sendable {
    let fileURL: URL
    private struct Archive: Codable {
        var version = 1
        var pages: [String: HWPComparisonReviewNote] = [:]
    }
    enum StoreError: LocalizedError {
        case invalidArchive, invalidNote
        var errorDescription: String? {
            switch self {
            case .invalidArchive: "기존 비교 기록을 읽지 못했습니다. 기록을 덮어쓰지 않았습니다."
            case .invalidNote: "쪽 번호와 기록 내용을 확인해 주세요. 내용은 2,000자까지 저장할 수 있습니다."
            }
        }
    }

    init(document: URL, reference: URL?, directory: URL) throws {
        let source = try Self.digest(document)
        let referenceHash = try reference.map(Self.digest) ?? "-"
        let identity = "hwp-comparison-v1|\(source)|\(referenceHash)"
        let key = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        fileURL = directory.appendingPathComponent(".HWPComparisonReview", isDirectory: true)
            .appendingPathComponent(key + ".json")
    }

    private static func digest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 256 * 1024), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func note(pageIndex: Int) throws -> HWPComparisonReviewNote? { try read().pages[String(pageIndex)] }

    func save(_ note: HWPComparisonReviewNote?, pageIndex: Int) throws {
        guard (0..<10_000).contains(pageIndex), note.map({ $0.text.count <= 2_000 }) ?? true else {
            throw StoreError.invalidNote
        }
        var archive = try read()
        archive.pages[String(pageIndex)] = note
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(archive).write(to: fileURL, options: .atomic)
    }

    private func read() throws -> Archive {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return Archive() }
        let data = try Data(contentsOf: fileURL)
        guard let archive = try? JSONDecoder().decode(Archive.self, from: data), archive.version == 1 else {
            throw StoreError.invalidArchive
        }
        return archive
    }
}

struct HWPComparisonReviewBar: View {
    let documentURL: URL
    let referenceURL: URL?
    let pageIndex: Int
    var directory: URL = HWPComparisonLibrary.current.documentsDirectory
    @State private var store: HWPComparisonReviewStore?
    @State private var note: HWPComparisonReviewNote?
    @State private var draft = HWPComparisonReviewNote(kind: .unchecked, text: "")
    @State private var showingEditor = false
    @State private var error: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let note {
                Image(systemName: note.kind == .sourceDifference ? "doc.on.doc" : "text.bubble")
                VStack(alignment: .leading, spacing: 3) {
                    Text(note.kind.title).font(.caption.weight(.semibold))
                    if !note.text.isEmpty { Text(note.text).font(.caption).lineLimit(2) }
                }
            } else if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            } else {
                Text("다르게 보이는 부분을 이 쪽에 기록해 둘 수 있어요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(note == nil ? "차이 기록" : "기록 보기") {
                draft = note ?? HWPComparisonReviewNote(kind: .unchecked, text: "")
                showingEditor = true
            }.font(.caption).disabled(store == nil || error != nil)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(note?.kind == .sourceDifference ? Color.blue.opacity(0.07) : Color.clear)
        .task {
            let document = documentURL, reference = referenceURL, root = directory
            do {
                store = try await Task.detached(priority: .utility) {
                    try HWPComparisonReviewStore(document: document, reference: reference, directory: root)
                }.value
                loadNote()
            } catch { self.error = error.localizedDescription }
        }
        .onChange(of: pageIndex) { _, _ in loadNote() }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                Form {
                    Section("\(pageIndex + 1)쪽의 차이") {
                        Picker("구분", selection: $draft.kind) {
                            ForEach(HWPComparisonReviewNote.Kind.allCases) { Text($0.title).tag($0) }
                        }
                        TextField("예: PDF에만 노란 강조가 있음", text: $draft.text, axis: .vertical)
                            .lineLimit(3...8)
                    }
                    Section {
                        Text("직접 확인한 내용만 기록해 주세요. 원본이나 정답 PDF가 바뀌면 새 자료로 구분합니다.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if note != nil { Button("기록 지우기", role: .destructive) { save(nil) } }
                    if let error { Text(error).foregroundStyle(.red) }
                }
                .navigationTitle("비교 기록")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("취소") { showingEditor = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("저장") { save(draft) }.disabled(draft.text.count > 2_000)
                    }
                }
            }.presentationDetents([.medium, .large])
        }
    }

    private func loadNote() {
        do { note = try store?.note(pageIndex: pageIndex); error = nil }
        catch { note = nil; self.error = error.localizedDescription }
    }

    private func save(_ value: HWPComparisonReviewNote?) {
        do {
            guard let store else { return }
            try store.save(value, pageIndex: pageIndex)
            note = value; error = nil; showingEditor = false
        } catch { self.error = error.localizedDescription }
    }
}
#endif
