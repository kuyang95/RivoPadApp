import SwiftUI

struct ChatHistoryView: View {
    @State private var conversations:
        [StoredChatConversation] = []
    @State private var searchText = ""
    @State private var errorDescription: String?
    @State private var isLoading = true
    @State private var isMutating = false
    @State private var editingConversationID:
        UUID?
    @State private var titleDraft = ""
    @State private var showsRenameDialog =
        false
    @State private var showsDeleteAllDialog =
        false

    private let historyStore: ChatHistoryStore

    init(
        historyStore:
            ChatHistoryStore = .shared
    ) {
        self.historyStore = historyStore
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView(
                    "대화 기록을 불러오는 중"
                )
            } else if conversations.isEmpty {
                ContentUnavailableView(
                    "저장된 대화가 없습니다",
                    systemImage:
                        "bubble.left.and.bubble.right",
                    description: Text(
                        "오른쪽 위의 새 대화 버튼으로 시작하세요."
                    )
                )
            } else if
                filteredConversations
                .isEmpty {
                ContentUnavailableView(
                    "검색 결과가 없습니다",
                    systemImage:
                        "magnifyingglass",
                    description: Text(
                        "다른 제목이나 메시지 내용으로 검색해 보세요."
                    )
                )
            } else {
                conversationList
            }
        }
        .visionCraftNavigationScreen()
        .navigationTitle("AI 대화")
        .searchable(
            text: $searchText,
            placement:
                .navigationBarDrawer(
                    displayMode: .always
                ),
            prompt:
                "제목 또는 메시지 검색"
        )
        .toolbar {
            managementToolbar
            featureToolbar
        }
        .safeAreaInset(edge: .bottom) {
            if let errorDescription {
                Text(errorDescription)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )
                    .padding()
                    .background(.bar)
                    .accessibilityLabel(
                        "오류: \(errorDescription)"
                    )
            }
        }
        .alert(
            "대화 제목 수정",
            isPresented:
                $showsRenameDialog
        ) {
            TextField(
                "제목",
                text: $titleDraft
            )
            .onChange(
                of: titleDraft
            ) { _, newValue in
                guard newValue.count
                        > StoredChatConversation
                        .maximumCustomTitleCharacters else {
                    return
                }
                titleDraft = String(
                    newValue.prefix(
                        StoredChatConversation
                            .maximumCustomTitleCharacters
                    )
                )
            }
            Button("저장") {
                renameConversation()
            }
            .disabled(
                StoredChatConversation
                    .normalizedTitle(
                        titleDraft
                    ) == nil
            )
            Button(
                "취소",
                role: .cancel
            ) {
                editingConversationID =
                    nil
            }
        } message: {
            Text(
                "목록에 표시할 대화 제목을 최대 120자로 입력하세요."
            )
        }
        .confirmationDialog(
            "모든 대화를 삭제할까요?",
            isPresented:
                $showsDeleteAllDialog,
            titleVisibility: .visible
        ) {
            Button(
                "전체 삭제",
                role: .destructive
            ) {
                deleteAll()
            }
            Button(
                "취소",
                role: .cancel
            ) {}
        } message: {
            Text(
                "삭제한 대화는 다시 불러올 수 없습니다."
            )
        }
        .onAppear {
            Task {
                await reload()
            }
        }
    }

    private var conversationList:
        some View
    {
        List {
            Section {
                ForEach(
                    filteredConversations
                ) { conversation in
                    NavigationLink(
                        value:
                            AppRoute.localChat(
                                conversationID:
                                    conversation
                                    .id
                            )
                    ) {
                        conversationRow(
                            conversation
                        )
                    }
                    .accessibilityHint(
                        "저장된 로컬 AI 대화를 엽니다."
                    )
                    .swipeActions(
                        edge: .leading,
                        allowsFullSwipe: false
                    ) {
                        Button {
                            beginRenaming(
                                conversation
                            )
                        } label: {
                            Label(
                                "제목 수정",
                                systemImage:
                                    "pencil"
                            )
                        }
                        .tint(.indigo)
                    }
                    .swipeActions(
                        edge: .trailing
                    ) {
                        Button(
                            role: .destructive
                        ) {
                            delete(
                                ids: [
                                    conversation.id,
                                ]
                            )
                        } label: {
                            Label(
                                "삭제",
                                systemImage:
                                    "trash"
                            )
                        }
                    }
                    .contextMenu {
                        Button {
                            beginRenaming(
                                conversation
                            )
                        } label: {
                            Label(
                                "제목 수정",
                                systemImage:
                                    "pencil"
                            )
                        }
                        Button(
                            role: .destructive
                        ) {
                            delete(
                                ids: [
                                    conversation.id,
                                ]
                            )
                        } label: {
                            Label(
                                "삭제",
                                systemImage:
                                    "trash"
                            )
                        }
                    }
                }
                .onDelete(
                    perform:
                        deleteFilteredRows
                )
            } header: {
                Text(resultCountDescription)
            }
        }
        .listStyle(.insetGrouped)
        .visionCraftListScreen()
        .disabled(isMutating)
        .overlay {
            if isMutating {
                ProgressView()
                    .padding(18)
                    .background(
                        .regularMaterial,
                        in:
                            RoundedRectangle(
                                cornerRadius: 14
                            )
                    )
            }
        }
    }

    @ToolbarContentBuilder
    private var managementToolbar:
        some ToolbarContent
    {
        ToolbarItem(
            placement: .secondaryAction
        ) {
            Button(
                role: .destructive
            ) {
                showsDeleteAllDialog = true
            } label: {
                Label(
                    "전체 삭제",
                    systemImage: "trash"
                )
            }
            .disabled(
                conversations.isEmpty
                    || isMutating
            )
        }
    }

    @ToolbarContentBuilder
    private var featureToolbar:
        some ToolbarContent
    {
        ToolbarItem(
            placement: .topBarTrailing
        ) {
            NavigationLink(
                value:
                    AppRoute.webSearch(
                        initialQuery: nil,
                        autoSearch: false,
                        speaksAnswer: false
                    )
            ) {
                Label(
                    "웹 검색",
                    systemImage:
                        "magnifyingglass"
                )
            }
            .accessibilityHint(
                "온라인에서 출처를 찾고 M4 로컬 AI로 답변합니다."
            )
        }
        ToolbarItem(
            placement: .topBarTrailing
        ) {
            NavigationLink(
                value:
                    AppRoute.webQuestion(
                        initialURL: nil,
                        autoLoad: false
                    )
            ) {
                Label(
                    "웹페이지",
                    systemImage: "link"
                )
            }
            .accessibilityHint(
                "웹페이지 본문을 읽어 M4 로컬 AI에 질문합니다."
            )
        }
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
        ToolbarItem(
            placement: .primaryAction
        ) {
            NavigationLink(
                value:
                    AppRoute.localChat(
                        conversationID: nil
                    )
            ) {
                Label(
                    "새 대화",
                    systemImage:
                        "square.and.pencil"
                )
            }
            .accessibilityHint(
                "빈 로컬 AI 대화를 시작합니다."
            )
        }
    }

    private var filteredConversations:
        [StoredChatConversation]
    {
        ChatHistorySearch.filtered(
            conversations,
            query: searchText
        )
    }

    private var resultCountDescription:
        String
    {
        let count =
            filteredConversations.count
        if searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty {
            return AppLocalization.format(
                "대화 %lld개",
                count
            )
        }
        return AppLocalization.format(
            "검색 결과 %lld개",
            count
        )
    }

    private func conversationRow(
        _ conversation:
            StoredChatConversation
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 6
        ) {
            Text(conversation.title)
                .font(.headline)
                .lineLimit(1)
            Text(conversation.preview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 10) {
                Text(
                    conversation.updatedAt
                        .formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                )
                Text(
                    "메시지 \(conversation.messages.count)개"
                )
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func reload(
        showsProgress: Bool = true
    ) async {
        if showsProgress {
            isLoading = true
        }
        defer {
            isLoading = false
        }
        do {
            conversations = try await
                historyStore
                .allConversations()
            errorDescription = nil
        } catch {
            errorDescription =
                AppLocalization.format(
                    "대화 기록을 불러오지 못했습니다: %@",
                    error.localizedDescription
                )
        }
    }

    private func beginRenaming(
        _ conversation:
            StoredChatConversation
    ) {
        editingConversationID =
            conversation.id
        titleDraft = conversation.title
        showsRenameDialog = true
    }

    private func renameConversation() {
        guard let id =
                editingConversationID else {
            return
        }
        let newTitle = titleDraft
        editingConversationID = nil

        Task {
            isMutating = true
            defer {
                isMutating = false
            }
            do {
                _ = try await historyStore
                    .renameConversation(
                        id: id,
                        title: newTitle
                    )
                await reload(
                    showsProgress: false
                )
            } catch {
                let message =
                    AppLocalization.format(
                        "대화 제목을 수정하지 못했습니다: %@",
                        error.localizedDescription
                    )
                await reload(
                    showsProgress: false
                )
                errorDescription = message
            }
        }
    }

    private func deleteFilteredRows(
        at offsets: IndexSet
    ) {
        let visible =
            filteredConversations
        let ids = offsets.compactMap {
            index in
            visible.indices.contains(index)
                ? visible[index].id
                : nil
        }
        delete(ids: ids)
    }

    private func delete(
        ids: [UUID]
    ) {
        guard !ids.isEmpty else {
            return
        }
        let idSet = Set(ids)
        conversations.removeAll {
            idSet.contains($0.id)
        }

        Task {
            isMutating = true
            defer {
                isMutating = false
            }
            for id in ids {
                do {
                    try await historyStore
                        .deleteConversation(
                            id: id
                        )
                } catch {
                    let message =
                        AppLocalization.format(
                            "대화를 삭제하지 못했습니다: %@",
                            error
                                .localizedDescription
                        )
                    await reload(
                        showsProgress: false
                    )
                    errorDescription = message
                    return
                }
            }
            errorDescription = nil
        }
    }

    private func deleteAll() {
        Task {
            isMutating = true
            defer {
                isMutating = false
            }
            do {
                try await historyStore
                    .deleteAllConversations()
                conversations = []
                searchText = ""
                errorDescription = nil
            } catch {
                let message =
                    AppLocalization.format(
                        "모든 대화를 삭제하지 못했습니다: %@",
                        error.localizedDescription
                    )
                await reload(
                    showsProgress: false
                )
                errorDescription = message
            }
        }
    }
}
