import SwiftUI

enum HWPDocumentAction {
    case toggleAccessibleEditing
    case toggleAI
    case fonts
    case convertToHWPX
    case save
    case exportPDF
    case printDocument
    case exportCopy
}

struct HWPDocumentActionsDialog: View {
    let showsEditingAction: Bool
    let isEditing: Bool
    let showsAI: Bool
    let isEditableDocument: Bool
    let isLegacyDocument: Bool
    let canSave: Bool
    let onAction: (HWPDocumentAction) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VisionCraftDialogCard(
            title: "더보기",
            cancelTitle: "닫기",
            onDismiss: onDismiss
        ) {
            ViewThatFits(in: .vertical) {
                actions
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
            if showsEditingAction {
                VisionCraftDialogOptionRow(
                    title: isEditing ? "읽기 보기" : "편집",
                    systemImage: isEditing ? "doc.text" : "pencil",
                    isEnabled: isEditableDocument
                ) {
                    onAction(.toggleAccessibleEditing)
                }
            }

            VisionCraftDialogOptionRow(
                title: showsAI ? "AI 도우미 숨기기" : "AI 도우미 표시",
                systemImage: "sparkles",
                isEnabled: isEditableDocument
            ) {
                onAction(.toggleAI)
            }

            VisionCraftDialogOptionRow(
                title: "글꼴",
                systemImage: "textformat"
            ) {
                onAction(.fonts)
            }

            if isLegacyDocument {
                VisionCraftDialogOptionRow(
                    title: "HWPX로 변환",
                    systemImage: "doc.badge.arrow.up"
                ) {
                    onAction(.convertToHWPX)
                }
            }

            VisionCraftDialogOptionRow(
                title: "이 문서에 저장",
                systemImage: "checkmark.circle",
                isPrimary: true,
                isEnabled: canSave
            ) {
                onAction(.save)
            }

            VisionCraftDialogOptionRow(title: "PDF로 저장", systemImage: "doc.richtext") {
                onAction(.exportPDF)
            }.accessibilityIdentifier("hwp-action-pdf")

            VisionCraftDialogOptionRow(title: "인쇄", systemImage: "printer") {
                onAction(.printDocument)
            }.accessibilityIdentifier("hwp-action-print")

            VisionCraftDialogOptionRow(
                title: "복사본 내보내기",
                systemImage: "square.and.arrow.up",
                isEnabled: isEditableDocument
            ) {
                onAction(.exportCopy)
            }
        }
    }
}
