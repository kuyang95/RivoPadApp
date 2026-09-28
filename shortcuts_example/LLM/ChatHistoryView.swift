import SwiftUI

struct ChatHistoryView: View {
    @EnvironmentObject private var appRouter: AppRouter
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
        ZStack {
            VisionCraftUI.background
                .ignoresSafeArea()

            if isLoading {
                ProgressView(
                    "데이터 불러오는 중"
                )
            } else if conversations.isEmpty {
                emptyHistoryCard
            } else {
                conversationList
            }
        }
        .visionCraftNavigationScreen()
        .navigationTitle("대화기록")
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .trailing, spacing: 10) {
                if let errorDescription {
                    Text(errorDescription)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .visionCraftSurfaceCard(cornerRadius: 14)
                        .accessibilityLabel("오류: \(errorDescription)")
                }

                HStack {
                    Spacer()
                    Button {
                        appRouter.route = .localChat(conversationID: nil)
                    } label: {
                        Label("새 대화", systemImage: "plus")
                            .font(.headline)
                            .padding(.horizontal, 8)
                            .frame(minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(
                        .roundedRectangle(
                            radius: 16
                        )
                    )
                    .tint(
                        VisionCraftUI.primary
                    )
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
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
        .onAppear {
            Task {
                await reload()
            }
        }
    }

    private var conversationList:
        some View
    {
        ScrollView {
            LazyVStack(
                alignment: .leading,
                spacing: 10
            ) {
                Text(
                    AppLocalization.format(
                        "대화 %lld개",
                        conversations.count
                    )
                )
                .font(.headline)
                .foregroundStyle(
                    VisionCraftUI.primaryText
                )

                ForEach(
                    conversations
                ) { conversation in
                    HStack(spacing: 12) {
                        Button {
                            appRouter.route = .localChat(
                                conversationID:
                                    conversation.id
                            )
                        } label: {
                            conversationRow(conversation)
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .leading
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(
                            "저장된 로컬 AI 대화를 엽니다."
                        )

                        Button {
                            beginRenaming(
                                conversation
                            )
                        } label: {
                            Image(systemName: "pencil")
                                .font(.title3)
                                .foregroundStyle(
                                    VisionCraftUI.secondaryText
                                )
                                .frame(
                                    width: 48,
                                    height: 48
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("제목 수정")

                        Button(
                            role: .destructive
                        ) {
                            delete(
                                ids: [
                                    conversation.id,
                                ]
                            )
                        } label: {
                            Image(systemName: "trash")
                                .font(.title3)
                                .foregroundStyle(
                                    VisionCraftUI.secondaryText
                                )
                                .frame(
                                    width: 48,
                                    height: 48
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("삭제")
                    }
                    .padding(14)
                    .visionCraftSurfaceCard(
                        cornerRadius: 12,
                        outlineOpacity: 0.6
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
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

    private var emptyHistoryCard: some View {
        VStack(spacing: 12) {
            Image(
                systemName:
                    "bubble.left.and.bubble.right"
            )
            .font(.system(size: 38))
            .foregroundStyle(
                VisionCraftUI.primary
            )
            Text("대화 기록이 없습니다")
                .font(.title3.bold())
                .foregroundStyle(
                    VisionCraftUI.primaryText
                )
            Text(
                "AI 새 채팅을 시작하면 여기에 저장됩니다."
            )
            .foregroundStyle(
                VisionCraftUI.secondaryText
            )
            .multilineTextAlignment(.center)

            Button("새 대화") {
                appRouter.route =
                    .localChat(
                        conversationID: nil
                    )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .visionCraftSurfaceCard(
            cornerRadius: 16,
            outlineOpacity: 0.6
        )
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
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
            spacing: 4
        ) {
            Text(conversation.title)
                .font(.body)
                .foregroundStyle(
                    VisionCraftUI.primaryText
                )
                .lineLimit(1)
            Text(
                conversation.updatedAt
                    .formatted(
                        date: .numeric,
                        time: .shortened
                    )
            )
            .font(.caption)
            .foregroundStyle(
                VisionCraftUI.secondaryText
            )
            .lineLimit(1)
        }
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
