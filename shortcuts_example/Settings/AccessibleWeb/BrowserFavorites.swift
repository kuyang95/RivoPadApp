import SwiftUI

struct BrowserFavorite: Codable {
    var name: String
    var url: String
    var icon: String?
}
@MainActor
enum BrowserFavorites {
    static var items: [BrowserFavorite] { UserDefaults.standard.data(forKey: "browser.favorites.v1").flatMap { try? JSONDecoder().decode([BrowserFavorite].self, from: $0) } ?? [] }
    static var json: String { (try? JSONEncoder().encode(items)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]" }
    private static func normalized(_ address: String) -> String {
        guard var parts = URLComponents(string: address) else { return address }
        if parts.path.isEmpty { parts.path = "/" }
        return parts.url?.absoluteString ?? address
    }
    static func add(name: String, address: String) async -> Bool {
        let input = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, input.count <= 2048, !input.contains(where: \.isWhitespace),
              var parts = URLComponents(string: input.contains("://") ? input : "https://" + input),
              ["https", "http"].contains(parts.scheme?.lowercased() ?? ""), parts.host?.isEmpty == false, parts.user == nil, parts.password == nil else { return false }
        parts.scheme = "https"
        if parts.path.isEmpty { parts.path = "/" }
        guard let addressURL = parts.url else { return false }
        let url = addressURL.absoluteString
        guard items.filter({ normalized($0.url) != url }).count < 24 else { return false }
        let metadata = await BrowserFavoriteMetadata.fetch(addressURL)
        guard !Task.isCancelled else { return false }
        let customName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        let title = customName.isEmpty ? metadata.name : customName
        var list = items.filter { normalized($0.url) != url }
        guard list.count < 24 else { return false }
        list.append(BrowserFavorite(name: title, url: url, icon: metadata.icon))
        guard let data = try? JSONEncoder().encode(list) else { return false }
        UserDefaults.standard.set(data, forKey: "browser.favorites.v1")
        return true
    }
}
struct BrowserAddFavoriteView: View {
    var save: (String, String) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var saveTask: Task<Void, Never>?
    @State private var address = ""
    @State private var invalid = false
    var body: some View {
        NavigationStack {
            Form {
                TextField("웹 주소", text: $address).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).frame(minHeight: 52).disabled(saving)
                if saving { ProgressView("사이트 정보를 가져오는 중…") }
                if invalid { Text("올바른 웹 주소를 입력해 주세요. 즐겨찾기는 최대 24개까지 추가할 수 있습니다.") }
            }.navigationTitle("즐겨찾기 추가")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("추가") {
                            saving = true; invalid = false
                            saveTask = Task { @MainActor in
                                let added = await save("", address)
                                guard !Task.isCancelled else { return }
                                saving = false
                                if added { dismiss() } else { invalid = true }
                            }
                        }.disabled(saving || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }.presentationDetents([.medium, .large]).onChange(of: address) { _, _ in invalid = false }.onDisappear { saveTask?.cancel() }
    }
}
