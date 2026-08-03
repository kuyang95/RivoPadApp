import Combine
import SwiftUI

@MainActor
final class SharedInboxViewModel:
    ObservableObject
{
    @Published private(set) var items:
        [SharedInboxItem] = []
    @Published var errorDescription: String?

    private let store: SharedInboxStore

    init(
        store: SharedInboxStore? = nil
    ) {
        self.store = store ?? .shared
    }

    func reload() {
        do {
            items = try store.pendingItems()
            errorDescription = nil
        } catch {
            errorDescription =
                error.localizedDescription
        }
    }

    func remove(
        _ item: SharedInboxItem
    ) {
        do {
            try store.remove(item)
            items.removeAll {
                $0.id == item.id
            }
        } catch {
            errorDescription =
                error.localizedDescription
        }
    }

    func discardOpenedItem(
        _ item: SharedInboxItem
    ) {
        items.removeAll {
            $0.id == item.id
        }
    }
}

struct SharedInboxView: View {
    @StateObject private var viewModel:
        SharedInboxViewModel
    let onOpen:
        (SharedInboxItem) async -> Bool

    init(
        store: SharedInboxStore = .shared,
        onOpen:
            @escaping (SharedInboxItem)
                async -> Bool
    ) {
        _viewModel = StateObject(
            wrappedValue:
                SharedInboxViewModel(
                    store: store
                )
        )
        self.onOpen = onOpen
    }

    var body: some View {
        List {
            if viewModel.items.isEmpty {
                ContentUnavailableView(
                    "대기 중인 공유 항목 없음",
                    systemImage:
                        "tray",
                    description:
                        Text(
                            "다른 앱에서 VisionCraft로 공유한 항목이 여기에 표시됩니다."
                        )
                )
                .listRowBackground(
                    Color.clear
                )
            } else {
                Section {
                    ForEach(
                        viewModel.items
                    ) { item in
                        Button {
                            Task {
                                if await onOpen(
                                    item
                                ) {
                                    viewModel
                                        .discardOpenedItem(
                                            item
                                        )
                                }
                            }
                        } label: {
                            SharedInboxItemRow(
                                item: item
                            )
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(
                                "삭제",
                                role: .destructive
                            ) {
                                viewModel
                                    .remove(item)
                            }
                        }
                    }
                } header: {
                    Text(
                        AppLocalization.format(
                            "대기 중 %lld개",
                            viewModel.items
                                .count
                        )
                    )
                } footer: {
                    Text(
                        "열지 않은 공유 항목은 7일 뒤 기기에서 자동으로 삭제됩니다."
                    )
                }
            }
        }
        .visionCraftListScreen()
        .navigationTitle("공유 수신함")
        .task {
            viewModel.reload()
        }
        .refreshable {
            viewModel.reload()
        }
        .alert(
            "공유 수신함을 열 수 없습니다",
            isPresented: Binding(
                get: {
                    viewModel
                        .errorDescription != nil
                },
                set: { isPresented in
                    if !isPresented {
                        viewModel
                            .errorDescription = nil
                    }
                }
            )
        ) {
            Button(
                "확인",
                role: .cancel
            ) {
                viewModel.errorDescription =
                    nil
            }
        } message: {
            Text(
                viewModel.errorDescription
                    ?? AppLocalization.string(
                        "알 수 없는 오류입니다."
                    )
            )
        }
    }
}

private struct SharedInboxItemRow: View {
    let item: SharedInboxItem

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: iconName)
                .font(.title2)
                .frame(width: 32)
                .foregroundStyle(.tint)
            VStack(
                alignment: .leading,
                spacing: 4
            ) {
                Text(title)
                    .lineLimit(2)
                    .foregroundStyle(
                        .primary
                    )
                HStack {
                    Text(kindName)
                    Text("·")
                    Text(
                        item.createdAt,
                        style: .relative
                    )
                }
                .font(.caption)
                .foregroundStyle(
                    .secondary
                )
            }
            Spacer()
            Image(
                systemName:
                    "chevron.right"
            )
            .font(.caption)
            .foregroundStyle(
                .tertiary
            )
        }
        .contentShape(Rectangle())
        .accessibilityElement(
            children: .combine
        )
        .accessibilityHint(
            "공유 항목을 열고 처리한 뒤 수신함에서 삭제합니다."
        )
    }

    private var title: String {
        if item.kind == .text,
           let text = item.text {
            let normalized = text
                .split(
                    whereSeparator:
                        \.isWhitespace
                )
                .joined(separator: " ")
            if !normalized.isEmpty {
                return String(
                    normalized.prefix(100)
                )
            }
        }
        if let filename =
                item.originalFilename,
           !filename.isEmpty {
            return filename
        }
        switch item.kind {
        case .text:
            return AppLocalization.string(
                "공유 텍스트"
            )
        case .image:
            return AppLocalization.string(
                "공유 사진"
            )
        case .file:
            return AppLocalization.string(
                "공유 파일"
            )
        }
    }

    private var kindName: String {
        switch item.kind {
        case .text:
            return AppLocalization.string(
                "텍스트"
            )
        case .image:
            return AppLocalization.string(
                "사진"
            )
        case .file:
            return AppLocalization.string(
                "파일"
            )
        }
    }

    private var iconName: String {
        switch item.kind {
        case .text:
            return "text.quote"
        case .image:
            return "photo"
        case .file:
            return "doc"
        }
    }
}
