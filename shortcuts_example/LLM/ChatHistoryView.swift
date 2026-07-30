import SwiftUI

struct ChatHistoryView: View {
    @State private var conversations: [StoredChatConversation] = []
    @State private var errorDescription: String?
    @State private var isLoading = true

    private let historyStore: ChatHistoryStore

    init(historyStore: ChatHistoryStore = .shared) {
        self.historyStore = historyStore
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("대화 기록을 불러오는 중")
            } else if conversations.isEmpty {
                ContentUnavailableView(
                    "저장된 대화가 없습니다",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text(
                        "오른쪽 위의 새 대화 버튼으로 시작하세요."
                    )
                )
            } else {
                List {
                    ForEach(conversations) { conversation in
                        NavigationLink(
                            value: AppRoute.localChat(
                                conversationID: conversation.id
                            )
                        ) {
                            conversationRow(conversation)
                        }
                        .accessibilityHint(
                            "저장된 로컬 AI 대화를 엽니다."
                        )
                    }
                    .onDelete(perform: delete)
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("AI 대화")
        .toolbar {
            ToolbarItem(
                placement: .topBarTrailing
            ) {
                NavigationLink(
                    value:
                        AppRoute.translation(
                            initialText: nil
                        )
                ) {
                    Label(
                        "번역",
                        systemImage:
                            "character.book.closed"
                    )
                }
                .accessibilityHint(
                    "M4 로컬 AI 번역 화면을 엽니다."
                )
            }
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(
                    value: AppRoute.localChat(
                        conversationID: nil
                    )
                ) {
                    Label("새 대화", systemImage: "square.and.pencil")
                }
                .accessibilityHint("빈 로컬 AI 대화를 시작합니다.")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let errorDescription {
                Text(errorDescription)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.bar)
                    .accessibilityLabel("오류: \(errorDescription)")
            }
        }
        .onAppear {
            Task {
                await reload()
            }
        }
    }

    private func conversationRow(
        _ conversation: StoredChatConversation
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(conversation.title)
                .font(.headline)
                .lineLimit(1)
            Text(conversation.preview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(
                conversation.updatedAt.formatted(
                    date: .abbreviated,
                    time: .shortened
                )
            )
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func reload() async {
        isLoading = true
        defer {
            isLoading = false
        }
        do {
            conversations = try await historyStore.allConversations()
            errorDescription = nil
        } catch {
            errorDescription =
                "대화 기록을 불러오지 못했습니다: "
                + error.localizedDescription
        }
    }

    private func delete(at offsets: IndexSet) {
        let ids = offsets.map {
            conversations[$0].id
        }
        conversations.remove(atOffsets: offsets)

        Task {
            for id in ids {
                do {
                    try await historyStore.deleteConversation(id: id)
                } catch {
                    errorDescription =
                        "대화를 삭제하지 못했습니다: "
                        + error.localizedDescription
                    await reload()
                    return
                }
            }
        }
    }
}
