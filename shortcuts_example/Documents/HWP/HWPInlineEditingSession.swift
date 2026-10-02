import RivoDocumentEngine
import Combine
import SwiftUI
import UIKit

/// Owns the single native input view on the paper. End composition before
/// committing, changing paragraphs, taking an AI snapshot, or saving.
@MainActor
final class HWPInlineEditingSession: ObservableObject {
    struct Activation {
        let token = UUID()
        let block: HWPDocumentBlock
        let point: CGPoint
        var caretOffset: Int? = nil
        var targetID: String? = nil
        var usesFragmentTap = false
        var surfaceID: String { targetID ?? block.id }
    }

    @Published private(set) var activation: Activation?
    @Published private(set) var previewBlock: HWPDocumentBlock?
    private var previewTask: Task<Void, Never>?
    @Published private(set) var hasChanges = false
    @Published private(set) var overflows = false
    @Published private(set) var overflowingBlockIDs: Set<String> = []
    @Published private(set) var selectedRange = NSRange(location: 0, length: 0)
    @Published private(set) var formattingRun = HWPDocumentTextRun(text: "")
    @Published private(set) var paragraphStyle = HWPDocumentBlockPresentation.plain
    @Published private(set) var cellLocation: HWPDocumentTableLocation?
    @Published private(set) var hasMixedFont = false
    @Published private(set) var hasMixedSize = false
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    private var applyingFormatting = false
    private var pendingTyping: (range: NSRange, attributes: [NSAttributedString.Key: Any])?
    private var publishBlock: ((HWPDocumentBlock) -> Void)?
    private weak var inputView: UITextView?
    private var publishText: ((String) -> Void)?
    private var commit: (() -> Void)?
    private var draft = ""
    private var listContext: [HWPDocumentBlock] = []
    private var select: ((String) -> Void)?
    private var structure: ((HWPDocumentBlock, HWPParagraphEdit) -> HWPParagraphEditResult?)?

    func begin(block: HWPDocumentBlock, at point: CGPoint,
               onSelect: @escaping (String) -> Void, onChange: @escaping (String) -> Void,
               onCommit: @escaping () -> Void,
               onCommitBlock: ((HWPDocumentBlock) -> Void)? = nil,
               onStructure: ((HWPDocumentBlock, HWPParagraphEdit) -> HWPParagraphEditResult?)? = nil,
               listContext: [HWPDocumentBlock] = [],
               caretOffset: Int? = nil, targetID: String? = nil,
               usesFragmentTap: Bool = false) {
        // Tapping another paragraph commits the current draft inside begin().
        // Carry that draft into the captured context before choosing a list ID.
        let previousBlock = activation == nil ? nil : currentBlock()
        finish()
        var context = listContext
        if let previousBlock, let index = context.firstIndex(where: { $0.id == previousBlock.id }) {
            context[index] = previousBlock
        }
        context = HWPListFormatting.renumbering(context)
        onSelect(block.id)
        select = onSelect
        structure = onStructure
        publishText = onChange
        commit = onCommit
        draft = block.text
        self.listContext = context
        publishBlock = onCommitBlock
        paragraphStyle = block.presentation
        cellLocation = block.tableLocation
        formattingRun = HWPDocumentFormatting.runs(in: block)[0].withText("")
        selectedRange = NSRange(location: 0, length: 0)
        hasChanges = false
        activation = Activation(block: block, point: point, caretOffset: caretOffset,
            targetID: targetID ?? HWPInlineParagraphGeometry.surfaceID(for: block, caret: caretOffset ?? 0),
            usesFragmentTap: usesFragmentTap)
    }

    @discardableResult
    func editParagraph(_ operation: HWPParagraphEdit) -> Bool {
        guard let structure, let select, let publishText, let commit, activation != nil,
              HWPParagraphEditing.supportsStructure(currentBlock()) else { return false }
        inputView?.unmarkText()
        let blockCommit = publishBlock
        guard let result = structure(currentBlock(), operation),
              let focused = result.blocks.first(where: { $0.id == result.focusedID }) else { return false }
        finish(commitChanges: false)
        begin(block: focused, at: .zero, onSelect: select, onChange: publishText,
            onCommit: commit, onCommitBlock: blockCommit, onStructure: structure, listContext: result.blocks, caretOffset: result.caret)
        return true
    }

    func tableInsertionSelection(blocks: [HWPDocumentBlock], layouts: [HWPDocumentPageLayout], prepare: Bool = false) -> HWPTableInsertion.Selection? {
        if prepare { inputView?.unmarkText() }
        return HWPTableInsertion.selection(blocks: previewing(blocks, layouts: layouts), selectedID: activation?.block.id,
            range: activation == nil ? NSRange(location: 0, length: 0) : inputView?.selectedRange ?? selectedRange, layouts: layouts)
    }

    func imageInsertionSelection(blocks: [HWPDocumentBlock], layouts: [HWPDocumentPageLayout],
                                 prepare: Bool = false) -> HWPImageEditing.Selection? {
        if prepare { inputView?.unmarkText() }
        return HWPImageEditing.selection(blocks: previewing(blocks, layouts: layouts),
            selectedID: activation?.block.id,
            range: activation == nil ? NSRange(location: 0, length: 0) : inputView?.selectedRange ?? selectedRange,
            layouts: layouts)
    }

    func shapeInsertionSelection(blocks: [HWPDocumentBlock], layouts: [HWPDocumentPageLayout],
                                 prepare: Bool = false) -> HWPShapeEditing.Selection? {
        if prepare { inputView?.unmarkText() }
        return HWPShapeEditing.selection(blocks: previewing(blocks, layouts: layouts),
            selectedID: activation?.block.id,
            range: activation == nil ? NSRange(location: 0, length: 0) : inputView?.selectedRange ?? selectedRange,
            layouts: layouts)
    }

    func equationInsertionSelection(blocks: [HWPDocumentBlock], layouts: [HWPDocumentPageLayout],
                                    prepare: Bool = false) -> HWPEquationEditing.Selection? {
        if prepare { inputView?.unmarkText() }
        return HWPEquationEditing.selection(blocks: previewing(blocks, layouts: layouts),
            selectedID: activation?.block.id,
            range: activation == nil ? NSRange(location: 0, length: 0) : inputView?.selectedRange ?? selectedRange,
            layouts: layouts)
    }

    func hyperlinkSelection(blocks: [HWPDocumentBlock], layouts: [HWPDocumentPageLayout],
                            prepare: Bool = false) -> HWPHyperlinkEditing.Selection? {
        if prepare { inputView?.unmarkText() }
        return HWPHyperlinkEditing.selection(blocks: previewing(blocks, layouts: layouts),
            selectedID: activation?.block.id,
            range: activation == nil ? NSRange(location: 0, length: 0) : inputView?.selectedRange ?? selectedRange)
    }

    func noteInsertion(blocks: [HWPDocumentBlock], layouts: [HWPDocumentPageLayout],
                       prepare: Bool = false) -> HWPNoteEditing.Insertion? {
        if prepare { inputView?.unmarkText() }
        return HWPNoteEditing.insertion(blocks: previewing(blocks, layouts: layouts),
            selectedID: activation?.block.id,
            range: activation == nil ? NSRange(location: 0, length: 0) : inputView?.selectedRange ?? selectedRange)
    }

    func supportsPageBreak(layouts: [HWPDocumentPageLayout]) -> Bool {
        guard let block = activation?.block, HWPParagraphEditing.supports(block),
              let layout = layouts.first(where: { $0.sectionIndex == HWPPageSetup.sectionIndex(block.sectionPath) }) else { return false }
        return layout.columnLayout.columns.count <= 1
    }

    func insertPageBreak() {
        inputView?.unmarkText()
        _ = editParagraph(.insertPageBreak(inputView?.selectedRange ?? selectedRange))
    }

    func attach(_ view: UITextView, token: UUID) {
        guard activation?.token == token else { return }
        inputView = view
    }

    func changed(_ text: String, token: UUID) {
        guard let activation, activation.token == token else { return }
        draft = text
        let changed = text != activation.block.text || !HWPDocumentFormatting.matches(currentBlock(), activation.block)
        if hasChanges != changed { hasChanges = changed }
        schedulePreview()
    }

    private func schedulePreview() {
        previewTask?.cancel()
        guard let activation, activation.surfaceID == activation.block.id,
              HWPParagraphEditing.supports(activation.block) || HWPTableEditing.supports(activation.block) else { return }
        previewTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            guard let self, self.activation?.token == activation.token,
                  self.inputView?.markedTextRange == nil else { return }
            let block = self.currentBlock()
            if self.previewBlock != block { self.previewBlock = block }
        }
    }

    func previewing(_ blocks: [HWPDocumentBlock], layouts: [HWPDocumentPageLayout]) -> [HWPDocumentBlock] {
        guard let previewBlock, let index = blocks.firstIndex(where: { $0.id == previewBlock.id }),
              !HWPDocumentFormatting.matches(blocks[index], previewBlock) else { return blocks }
        var result = blocks
        result[index] = previewBlock
        result = HWPCellFormatting.propagating(previewBlock, from: blocks[index], in: result)
        if HWPFlowLayout.needsReflow(from: blocks[index], to: previewBlock) {
            result = HWPFlowLayout.reflowingEdit(result, before: blocks, startingAt: previewBlock.id, layouts: layouts)
        }
        // Moving the first line to another page would replace its native input view.
        // Keep that transition for commit so UIKit can finish composition first.
        if result[index].lineLayouts.first?.startsPage == true && blocks[index].lineLayouts.first?.startsPage != true {
            return blocks
        }
        if previewBlock.tableLocation != nil {
            func page(_ source: [HWPDocumentBlock]) -> Int? {
                HWPOriginalCanvasPageBuilder.makePages(blocks: source, layouts: layouts).firstIndex {
                    $0.bodyBlocks.contains { $0.id == activation?.surfaceID }
                }
            }
            if page(result) != page(blocks) { return blocks }
        }
        return result
    }

    func setOverflow(_ value: Bool, token: UUID) {
        guard let activation, activation.token == token else { return }
        if overflows != value { overflows = value }
        if value {
            if !overflowingBlockIDs.contains(activation.block.id) {
                overflowingBlockIDs.insert(activation.block.id)
            }
        } else if overflowingBlockIDs.contains(activation.block.id) {
            overflowingBlockIDs.remove(activation.block.id)
        }
    }

    func selectionChanged(_ input: UITextView) {
        guard !applyingFormatting, activation != nil else { return }
        selectedRange = input.selectedRange
        if pendingTyping?.range != input.selectedRange { pendingTyping = nil }
        let block = currentBlock()
        let all = HWPDocumentFormatting.runs(in: block)
        var offset = 0
        let selected = all.filter { run in
            let range = NSRange(location: offset, length: run.text.utf16.count)
            offset += range.length
            return NSIntersectionRange(range, input.selectedRange).length > 0
        }
        var run = selected.first ?? (pendingTyping?.attributes[.hwpCharacterStyle] as? HWPDocumentTextRun)
            ?? (input.typingAttributes[.hwpCharacterStyle] as? HWPDocumentTextRun)
            ?? HWPDocumentFormatting.run(at: max(0, input.selectedRange.location - 1), in: block)
        hasMixedFont = Set(selected.map(\.fontName)).count > 1
        hasMixedSize = Set(selected.map(\.fontSizePoints)).count > 1
        if !selected.isEmpty {
            run.isBold = selected.allSatisfy(\.isBold)
            run.isItalic = selected.allSatisfy(\.isItalic)
            run.isUnderlined = selected.allSatisfy(\.isUnderlined)
            run.isStruckThrough = selected.allSatisfy(\.isStruckThrough)
            run.isSuperscript = selected.allSatisfy(\.isSuperscript)
            run.isSubscript = selected.allSatisfy(\.isSubscript)
            if Set(selected.map(\.backgroundColorRGB)).count > 1 { run.backgroundColorRGB = nil }
        }
        formattingRun = run.withText("")
        canUndo = input.undoManager?.canUndo == true
        canRedo = input.undoManager?.canRedo == true
    }

    func undo() -> Bool {
        guard let input = inputView, input.undoManager?.canUndo == true else { return false }
        input.unmarkText()
        input.undoManager?.undo()
        selectionChanged(input)
        return true
    }

    func redo() -> Bool {
        guard let input = inputView, input.undoManager?.canRedo == true else { return false }
        input.undoManager?.redo()
        selectionChanged(input)
        return true
    }

    var canApplyList: Bool { activation.map { HWPListFormatting.supports($0.block) } ?? false }

    func applyList(_ kind: HWPListKind?) {
        guard canApplyList else { return }
        let block = currentBlock()
        if let kind, block.presentation.list?.kind != kind {
            applyFormatting(.list(HWPListFormatting.style(kind, for: block, in: listContext)))
        } else { applyFormatting(.list(nil)) }
    }

    func applyFormatting(_ command: HWPFormattingCommand) {
        guard let input = inputView, let activation else { return }
        input.unmarkText()
        let previous = snapshot(input)
        let block = currentBlock()
        let selection = input.selectedRange
        applyingFormatting = true
        if !command.isParagraph, selection.length == 0, !block.text.isEmpty {
            let run = command.applying(to: formattingRun)
            input.typingAttributes = HWPInlineTextAttributes.attributes(run: run, block: block, relativeTo: activation.block)
        } else {
            let updated = HWPDocumentFormatting.apply(command, to: block, range: selection)
            paragraphStyle = updated.presentation
            cellLocation = updated.tableLocation
            updateAttributes(HWPInlineTextAttributes.make(block: updated, relativeTo: activation.block), in: input)
            input.selectedRange = selection
            input.typingAttributes = HWPInlineTextAttributes.attributes(
                run: HWPDocumentFormatting.run(at: max(0, selection.location - 1), in: updated), block: updated, relativeTo: activation.block)
        }
        applyingFormatting = false
        pendingTyping = selection.length == 0 ? (selection, input.typingAttributes) : nil
        input.undoManager?.beginUndoGrouping()
        input.undoManager?.registerUndo(withTarget: self) { target in
            target.restore(previous, token: activation.token)
        }
        input.undoManager?.setActionName(AppLocalization.string("서식 변경"))
        input.undoManager?.endUndoGrouping()
        changed(input.text ?? "", token: activation.token)
        selectionChanged(input)
        // A popover can temporarily take focus. Restore the same input and range.
        input.becomeFirstResponder()
        refreshLayout(input, token: activation.token)
    }

    func restoreFocus() { inputView?.becomeFirstResponder() }

    func prepareForInput(_ input: UITextView, replacing range: NSRange) {
        guard let activation else { return }
        // UIKit drops custom attributes from typingAttributes after a key event.
        // Carry the semantic HWP style forward for every subsequent character.
        if let pendingTyping, pendingTyping.range == range {
            input.typingAttributes = pendingTyping.attributes
        } else {
            let block = currentBlock()
            let position = range.length > 0 ? range.location : max(0, range.location - 1)
            input.typingAttributes = HWPInlineTextAttributes.attributes(
                run: HWPDocumentFormatting.run(at: position, in: block), block: block, relativeTo: activation.block)
        }
    }

    private func refreshLayout(_ input: UITextView, token: UUID) {
        (input as? HWPInlineTextView)?.setListMarker(currentBlock().presentation.list?.marker(in: currentBlock()))
        input.layoutIfNeeded()
        setOverflow(input.sizeThatFits(CGSize(width: input.bounds.width, height: .greatestFiniteMagnitude)).height > input.bounds.height + 1, token: token)
        input.scrollRangeToVisible(input.selectedRange)
    }

    private struct FormatSnapshot {
        let text: NSAttributedString
        let style: HWPDocumentBlockPresentation
        let cell: HWPDocumentTableLocation?
        let selection: NSRange
        let typing: [NSAttributedString.Key: Any]
    }

    private func snapshot(_ input: UITextView) -> FormatSnapshot {
        FormatSnapshot(text: NSAttributedString(attributedString: input.attributedText),
            style: paragraphStyle, cell: cellLocation, selection: input.selectedRange, typing: input.typingAttributes)
    }

    private func updateAttributes(_ text: NSAttributedString, in input: UITextView) {
        // Replacing the characters for a style-only operation makes UITextView
        // discard earlier typing/format undo entries. Edit attributes in place.
        input.textStorage.beginEditing()
        if input.textStorage.string != text.string {
            input.textStorage.setAttributedString(text)
        } else {
            text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
                input.textStorage.setAttributes(attributes, range: range)
            }
        }
        input.textStorage.endEditing()
    }

    private func restore(_ saved: FormatSnapshot, token: UUID) {
        guard activation?.token == token, let input = inputView else { return }
        let inverse = snapshot(input)
        input.undoManager?.registerUndo(withTarget: self) { $0.restore(inverse, token: token) }
        applyingFormatting = true
        paragraphStyle = saved.style
        cellLocation = saved.cell
        updateAttributes(saved.text, in: input)
        input.selectedRange = saved.selection
        input.typingAttributes = saved.typing
        pendingTyping = saved.selection.length == 0 ? (saved.selection, saved.typing) : nil
        applyingFormatting = false
        changed(input.text ?? "", token: token)
        selectionChanged(input)
        refreshLayout(input, token: token)
    }

    private func currentBlock() -> HWPDocumentBlock {
        guard let original = activation?.block else {
            preconditionFailure("An active paragraph is required")
        }
        let text = inputView?.text ?? draft
        let base = HWPTextRunEditing.replacingText(in: original, with: text).withLayout(tableLocation: cellLocation)
        guard let input = inputView else { return base }
        var style = paragraphStyle
        var runs: [HWPDocumentTextRun] = []
        input.attributedText.enumerateAttribute(.hwpCharacterStyle,
            in: NSRange(location: 0, length: input.attributedText.length)) { value, range, _ in
                let template = value as? HWPDocumentTextRun
                    ?? HWPDocumentFormatting.run(at: range.location, in: base)
                runs.append(template.withText((text as NSString).substring(with: range)))
            }
        if runs.isEmpty {
            let template = pendingTyping?.attributes[.hwpCharacterStyle] as? HWPDocumentTextRun
                ?? input.typingAttributes[.hwpCharacterStyle] as? HWPDocumentTextRun
                ?? HWPDocumentFormatting.runs(in: base)[0]
            runs = [template.withText("")]
        }
        style.textRuns = runs
        let updated = HWPDocumentFormatting.replacingPresentation(of: base, with: style)
        return HWPDocumentFormatting.matches(updated, base) ? base : updated
    }

    func finish(commitChanges: Bool = true) {
        guard activation != nil else { return }
        previewTask?.cancel()
        previewTask = nil
        if let inputView {
            inputView.unmarkText()
            draft = inputView.text ?? ""
            inputView.resignFirstResponder()
        }
        let formattedBlock = currentBlock()
        let blockCommit = publishBlock
        // Publish once per editing session, not for every composed syllable.
        // This also avoids rebuilding every rendered page on each keystroke.
        if commitChanges, blockCommit == nil { publishText?(draft) }
        let pendingCommit = commit
        // Clear identity before a late delegate callback can publish a stale
        // draft after undo, AI apply, or opening another paragraph.
        activation = nil
        previewBlock = nil
        inputView = nil
        pendingTyping = nil
        publishText = nil
        publishBlock = nil
        commit = nil
        structure = nil
        select = nil
        overflows = false
        hasChanges = false
        canUndo = false
        canRedo = false
        if commitChanges {
            if let blockCommit { blockCommit(formattedBlock) } else { pendingCommit?() }
        }
    }
}

nonisolated struct HWPInlineEditingContext: Sendable {
    var session: HWPInlineEditingSession?
    var sources: [String: HWPDocumentBlock] = [:]
    var orderedBlocks: [HWPDocumentBlock] = []
    var activeID: String?
    var onSelect: @MainActor @Sendable (String) -> Void = { _ in }
    var onChange: @MainActor @Sendable (String) -> Void = { _ in }
    var onCommit: @MainActor @Sendable () -> Void = {}
    var onCommitBlock: (@MainActor @Sendable (HWPDocumentBlock) -> Void)? = nil
    var onStructure: (@MainActor @Sendable (HWPDocumentBlock, HWPParagraphEdit) -> HWPParagraphEditResult?)? = nil

    func source(for block: HWPDocumentBlock) -> HWPDocumentBlock? {
        let sourceID = HWPInlineParagraphGeometry.sourceID(block.id)
        guard session != nil, let source = sources[sourceID], source.isEditable,
              source.region.kind == .body,
              source.layoutContainerID == nil
                || (source.tableLocation != nil && source.tableLocation?.parent == nil),
              source.canvasObjects.isEmpty, source.images.isEmpty else { return nil }
        if source.text != block.text || sourceID != block.id {
            guard block.sectionPath == source.sectionPath,
                  block.paragraphIndex == source.paragraphIndex,
                  let first = block.lineLayouts.first,
                  first.startCharacter <= HWPInlineParagraphGeometry.rawLength(source.text) else { return nil }
        }
        return source
    }

    @MainActor func hidesText(_ block: HWPDocumentBlock) -> Bool {
        session?.activation?.surfaceID == block.id && source(for: block) != nil
    }
}

private struct HWPInlineEditingKey: EnvironmentKey {
    static let defaultValue = HWPInlineEditingContext()
}

extension EnvironmentValues {
    var hwpInlineEditing: HWPInlineEditingContext {
        get { self[HWPInlineEditingKey.self] }
        set { self[HWPInlineEditingKey.self] = newValue }
    }
}

/// Uses unscaled paper coordinates; the canvas applies one transform to the
/// preview, input view, caret, and selection handles together.
struct HWPInlineParagraphTarget: View {
    let block: HWPDocumentBlock
    let rect: CGRect
    @Environment(\.hwpInlineEditing) private var editing
    @Environment(\.hwpDocumentSearch) private var search

    var body: some View {
        if search.matches(block) {
            Rectangle()
                .fill(Color.yellow.opacity(0.05))
                .overlay { Rectangle().stroke(Color.orange.opacity(0.5), lineWidth: 0.8) }
                .frame(width: max(1, rect.width), height: max(16, rect.height))
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: HWPDocumentSearchRectKey.self,
                            value: proxy.frame(in: .named("hwp-document-paper")))
                    }
                }
                .offset(x: rect.minX, y: rect.minY)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        if let source = editing.source(for: block), let session = editing.session {
            Group {
                if let activation = session.activation, activation.surfaceID == block.id {
                    HWPInlineTextEditor(activation: activation, session: session)
                        .id(activation.token)
                        .overlay(alignment: .bottom) {
                            if session.overflows {
                                Rectangle().fill(.orange).frame(height: 2)
                                    .allowsHitTesting(false)
                            }
                        }
                } else {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { point in
                            session.begin(block: source, at: point,
                                onSelect: editing.onSelect, onChange: editing.onChange,
                                onCommit: editing.onCommit, onCommitBlock: editing.onCommitBlock,
                                onStructure: editing.onStructure, listContext: editing.orderedBlocks,
                                caretOffset: source.id == block.id ? nil : HWPInlineParagraphGeometry.textOffset(in: source.text, raw: block.lineLayouts.first?.startCharacter ?? 0),
                                targetID: block.id, usesFragmentTap: source.id != block.id)
                        }
                        .accessibilityElement()
                        .accessibilityLabel(source.text.isEmpty
                            ? AppLocalization.string("빈 문단") : source.text)
                        .accessibilityHint(AppLocalization.string("두 번 탭하여 문서에서 편집"))
                        .accessibilityIdentifier("hwp-inline-target-\(source.id)")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction {
                            session.begin(block: source, at: .zero,
                                onSelect: editing.onSelect, onChange: editing.onChange,
                                onCommit: editing.onCommit, onCommitBlock: editing.onCommitBlock,
                                onStructure: editing.onStructure, listContext: editing.orderedBlocks,
                                caretOffset: source.id == block.id ? nil : HWPInlineParagraphGeometry.textOffset(in: source.text, raw: block.lineLayouts.first?.startCharacter ?? 0),
                                targetID: block.id, usesFragmentTap: source.id != block.id)
                        }
                }
            }
            .frame(width: max(1, rect.width), height: max(16, rect.height))
            .offset(x: rect.minX, y: rect.minY)
            .zIndex(session.activation?.surfaceID == block.id ? 50_000 : 1)
        }
    }
}
