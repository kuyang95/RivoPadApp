import SwiftUI

/// Android `ConversationListScreen`: title row, "대화 n개" caption, one
/// `VcActionRow` card per conversation and a pinned ink "새 대화" button.
struct ChatHistoryView: View {
    @EnvironmentObject private var appRouter: AppRouter
    @Environment(\.dismiss) private var dismiss
    @State private var conversations:
        [StoredChatConversation] = []
    @State private var errorDescription: String?
    @State private var isLoading = true
    @State private var isMutating = false
    @State private var editingConversationID:
        UUID?
    @State private var titleDraft = ""
    @State private var showsRenameDialog =
        false

    private let historyStore: ChatHistoryStore

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

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

            VStack(spacing: 0) {
                VisionCraftScreenTitleRow(
                    title: "대화기록",
                    onBack: { dismiss() }
                )
                .padding(.bottom, 16)

                Group {
                    if isLoading {
                        loadingState
                    } else if conversations.isEmpty {
                        emptyState
                    } else {
                        conversationList
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let errorDescription {
                    Text(errorDescription)
                        .visionCraftAndroidText(14)
                        .foregroundStyle(VisionCraftUI.error)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .visionCraftErrorPanel()
                        .padding(.top, 12)
                        .accessibilityLabel(
                            AppLocalization.format(
                                "오류: %@",
                                errorDescription
                            )
                        )
                }

                Button {
                    appRouter.route = .localChat(conversationID: nil)
                } label: {
                    Text(AppLocalization.string("새 대화"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VisionCraftAndroidButtonStyle(filled: true))
                .padding(.top, 16)
                .accessibilityIdentifier("chat-history-new")
            }
            .visionCraftScreenPadding()
        }
        .visionCraftNavigationScreen()
        .toolbar(.hidden, for: .navigationBar)
        .visionCraftHandlesBackNavigation()
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
            Button("확인") {
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
        }
        .onAppear {
            Task {
                await reload()
            }
        }
    }

    private var loadingState: some View {
        Text(AppLocalization.string("데이터를 받아오는 중입니다..."))
            .visionCraftAndroidText(16)
            .foregroundStyle(VisionCraftUI.secondaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityAddTraits(.updatesFrequently)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text(AppLocalization.string("대화 기록이 없습니다"))
                .visionCraftAndroidText(22, weight: .semibold, relativeTo: .title2)
                .foregroundStyle(VisionCraftUI.primaryText)
                .multilineTextAlignment(.center)
            Text(
                AppLocalization.string(
                    "새 대화를 시작하면 여기에 저장됩니다."
                )
            )
            .visionCraftAndroidText(16)
            .foregroundStyle(VisionCraftUI.secondaryText)
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var conversationList:
        some View
    {
        ScrollView {
            LazyVStack(
                alignment: .leading,
                spacing: 16
            ) {
                Text(
                    AppLocalization.format(
                        "대화 %lld개",
                        conversations.count
                    )
                )
                .visionCraftAndroidText(14, weight: .semibold, relativeTo: .subheadline)
                .foregroundStyle(
                    VisionCraftUI.secondaryText
                )

                ForEach(
                    conversations
                ) { conversation in
                    conversationRow(conversation)
                }

                Color.clear.frame(height: 4)
            }
        }
        .disabled(isMutating)
        .overlay {
            if isMutating {
                ProgressView()
                    .padding(18)
                    .background(
                        VisionCraftUI.surface,
                        in:
                            RoundedRectangle(
                                cornerRadius: 14,
                                style: .continuous
                            )
                    )
            }
        }
    }

    /// Android `ConversationRow`: `VcActionRow` (corner 22, min 88,
    /// padding 20/8/14/14, spacing 12) with a 28pt clock icon, two-line
    /// semibold title, "yyyy-MM-dd HH:mm" date and two 48pt icon buttons.
    private func conversationRow(
        _ conversation:
            StoredChatConversation
    ) -> some View {
        HStack(spacing: 12) {
            Button {
                appRouter.route = .localChat(
                    conversationID:
                        conversation.id
                )
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "clock")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(VisionCraftUI.icon)
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)

                    VStack(
                        alignment: .leading,
                        spacing: 4
                    ) {
                        Text(conversation.title)
                            .visionCraftAndroidText(18, weight: .semibold, relativeTo: .headline)
                            .foregroundStyle(
                                VisionCraftUI.primaryText
                            )
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(
                            Self.dateFormatter.string(
                                from: conversation.updatedAt
                            )
                        )
                        .visionCraftAndroidText(16)
                        .foregroundStyle(
                            VisionCraftUI.secondaryText
                        )
                        .lineLimit(1)
                    }
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(VisionCraftHomePressStyle())
            .accessibilityLabel(
                AppLocalization.format(
                    "%@, %@",
                    conversation.title,
                    Self.dateFormatter.string(
                        from: conversation.updatedAt
                    )
                )
            )
            .accessibilityHint(
                AppLocalization.string("실행")
            )

            rowIconButton(
                systemImage: "pencil",
                label: "제목 수정"
            ) {
                beginRenaming(conversation)
            }

            rowIconButton(
                systemImage: "trash",
                label: "삭제"
            ) {
                delete(ids: [conversation.id])
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .visionCraftHomeSurface()
    }

    private func rowIconButton(
        systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(VisionCraftUI.icon)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(VisionCraftHomePressStyle())
        .accessibilityLabel(AppLocalization.string(label))
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
}
