import SwiftUI

enum ExcelWorkbookAction {
    case undo
    case redo
}

struct ExcelWorkbookActionsDialog: View {
    var canUndo = false
    var canRedo = false
    let onAction: (ExcelWorkbookAction) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VisionCraftDialogCard(
            title: "더보기",
            cancelTitle: "닫기",
            onDismiss: onDismiss
        ) {
            ViewThatFits(in: .vertical) {
                actions.fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    actions
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .accessibilityAction(.escape, onDismiss)
    }

    private var actions: some View {
        VStack(spacing: VisionCraftUI.actionRowSpacing) {
            VisionCraftDialogOptionRow(
                title: "실행 취소",
                systemImage: "arrow.uturn.backward",
                isEnabled: canUndo
            ) { onAction(.undo) }

            VisionCraftDialogOptionRow(
                title: "다시 실행",
                systemImage: "arrow.uturn.forward",
                isEnabled: canRedo
            ) { onAction(.redo) }
        }
    }
}

#Preview("Workbook actions") {
    ExcelWorkbookActionsDialog(
        onAction: { _ in },
        onDismiss: {}
    )
}
