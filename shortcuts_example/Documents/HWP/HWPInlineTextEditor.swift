import RivoDocumentEngine
import SwiftUI
import UIKit

/// A real text input surface on the page, with UIKit caret/selection, IME,
/// dictation, keyboard navigation and the standard editing menu.
struct HWPInlineTextEditor: UIViewRepresentable {
    let activation: HWPInlineEditingSession.Activation
    let session: HWPInlineEditingSession

    func makeCoordinator() -> Coordinator { Coordinator(activation: activation, session: session) }

    func makeUIView(context: Context) -> HWPInlineTextView {
        let view = HWPInlineTextView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.contentInsetAdjustmentBehavior = .never
        view.showsHorizontalScrollIndicator = false
        view.showsVerticalScrollIndicator = true
        view.alwaysBounceVertical = false
        view.keyboardDismissMode = .none
        view.allowsEditingTextAttributes = false
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        view.autocorrectionType = .no
        view.spellCheckingType = .no
        view.autocapitalizationType = .none
        view.tintColor = .systemBlue
        view.accessibilityLabel = AppLocalization.string("원본 문단 편집")
        view.accessibilityIdentifier = "hwp-inline-editor"
        view.setListMarker(activation.block.presentation.list?.marker(in: activation.block)
            ?? activation.block.lineLayouts.first?.listMarker)
        view.attributedText = HWPInlineTextAttributes.make(block: activation.block)
        view.typingAttributes = HWPInlineTextAttributes.typingAttributes(block: activation.block)
        view.delegate = context.coordinator
        view.didLayOut = { [weak coordinator = context.coordinator] input in
            coordinator?.layout(input)
        }
        view.onDone = { [weak session] in session?.finish() }
        view.willInsertText = { [weak session] input in
            session?.prepareForInput(input, replacing: input.selectedRange)
        }
        view.onParagraphEdit = { [weak session] operation in session?.editParagraph(operation) ?? false }
        let bar = UIToolbar()
        bar.items = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(title: AppLocalization.string("완료"), style: .done,
                target: view, action: #selector(HWPInlineTextView.finishEditing))
        ]
        bar.sizeToFit()
        view.inputAccessoryView = bar
        session.attach(view, token: activation.token)
        return view
    }

    func updateUIView(_ view: HWPInlineTextView, context: Context) {
        // The input view owns its text while active. Replacing attributedText
        // here destroys markedTextRange and breaks Korean syllable assembly.
        session.attach(view, token: activation.token)
    }

    static func dismantleUIView(_ view: HWPInlineTextView, coordinator: Coordinator) {
        view.didLayOut = nil
        view.delegate = nil
        view.resignFirstResponder()
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        let activation: HWPInlineEditingSession.Activation
        weak var session: HWPInlineEditingSession?
        private var positioned = false
        private weak var focusedView: UITextView?

        init(activation: HWPInlineEditingSession.Activation, session: HWPInlineEditingSession) {
            self.activation = activation
            self.session = session
            super.init()
            NotificationCenter.default.addObserver(self, selector: #selector(keyboardShown),
                name: UIResponder.keyboardDidShowNotification, object: nil)
        }

        deinit { NotificationCenter.default.removeObserver(self) }

        @objc private func keyboardShown() {
            if let focusedView { revealCaret(focusedView) }
        }

        private func revealCaret(_ view: UITextView) {
            guard view.isFirstResponder, let range = view.selectedTextRange else { return }
            let rect = view.caretRect(for: range.end)
            var ancestor = view.superview
            while let parent = ancestor {
                if let scroll = parent as? UIScrollView {
                    scroll.scrollRectToVisible(view.convert(rect, to: scroll)
                        .insetBy(dx: -16, dy: -24), animated: true)
                }
                ancestor = parent.superview
            }
        }

        func layout(_ view: HWPInlineTextView) {
            guard view.window != nil, view.bounds.width > 0 else { return }
            focusedView = view
            if !positioned {
                positioned = true
                // After SwiftUI installs the view, its bounds and text layout
                // are available for translating the original tap to a caret.
                DispatchQueue.main.async { [weak self, weak view] in
                    guard let self, let view,
                          self.session?.activation?.token == self.activation.token else { return }
                    view.becomeFirstResponder()
                    if let offset = self.activation.caretOffset {
                        view.selectedRange = NSRange(location: min(offset, view.text.utf16.count), length: 0)
                        if self.activation.usesFragmentTap, let selection = view.selectedTextRange {
                            view.layoutIfNeeded()
                            let caret = view.caretRect(for: selection.start)
                            view.setContentOffset(CGPoint(x: 0, y: max(0, caret.minY)), animated: false)
                            let point = CGPoint(x: self.activation.point.x, y: self.activation.point.y + view.contentOffset.y)
                            if let position = view.closestPosition(to: point) {
                                view.selectedTextRange = view.textRange(from: position, to: position)
                            }
                        }
                    } else if let position = view.closestPosition(to: self.activation.point) {
                        view.selectedTextRange = view.textRange(from: position, to: position)
                    }
                    self.updateOverflow(view)
                    self.revealCaret(view)
                }
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            session?.selectionChanged(textView)
        }

        func textViewDidChange(_ textView: UITextView) {
            session?.changed(textView.text ?? "", token: activation.token)
            updateOverflow(textView)
            session?.selectionChanged(textView)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            session?.changed(textView.text ?? "", token: activation.token)
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            guard HWPInlineTextInput.accepts(text, replacing: range, in: textView.text ?? "") else {
                UIAccessibility.post(notification: .announcement,
                    argument: AppLocalization.string("이 문단에 입력할 수 없는 내용입니다."))
                return false
            }
            if text == "\n", (textView as? HWPInlineTextView)?.insertingSoftBreak != true,
               session?.editParagraph(.split(range)) == true { return false }
            session?.prepareForInput(textView, replacing: range)
            return true
        }

        private func updateOverflow(_ view: UITextView) {
            // An active paragraph scrolls internally when it exceeds its old
            // area. Keep every character reachable and make that state visible.
            let token = activation.token
            let overflow = view.sizeThatFits(CGSize(width: view.bounds.width,
                height: .greatestFiniteMagnitude)).height > view.bounds.height + 1
            DispatchQueue.main.async { [weak session] in
                session?.setOverflow(overflow, token: token)
            }
        }
    }
}

final class HWPInlineTextView: UITextView {
    private var marker: HWPDocumentListMarker?
    private lazy var markerLabel: UILabel = {
        let label = UILabel()
        label.isUserInteractionEnabled = false
        label.isAccessibilityElement = false
        addSubview(label)
        return label
    }()
    func setListMarker(_ value: HWPDocumentListMarker?) {
        marker = value
        markerLabel.text = value?.run.text
        let size = value?.run.fontSizePoints ?? 10
        let name = value.flatMap { HWPDocumentFontResolver.resolution(for: $0.run).resolvedName }
        markerLabel.font = name.flatMap { UIFont(name: $0, size: size) } ?? .systemFont(ofSize: size)
        let rgb = value?.run.textColorRGB ?? 0
        markerLabel.textColor = UIColor(red: CGFloat((rgb >> 16) & 255) / 255,
            green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
        markerLabel.isHidden = value == nil
        setNeedsLayout()
    }

    var didLayOut: ((HWPInlineTextView) -> Void)?
    var onDone: (() -> Void)?
    var willInsertText: ((HWPInlineTextView) -> Void)?
    var onParagraphEdit: ((HWPParagraphEdit) -> Bool)?
    private(set) var insertingSoftBreak = false

    override func layoutSubviews() {
        super.layoutSubviews()
        if let marker {
            let height = markerLabel.font.lineHeight
            markerLabel.frame = CGRect(x: 0, y: 0, width: marker.reservedWidthPoints, height: height)
        }
        didLayOut?(self)
    }

    @objc func finishEditing() { onDone?() }

    override func insertText(_ text: String) {
        let normalized = HWPInlineTextInput.normalized(text)
        if normalized == "\n", !insertingSoftBreak, onParagraphEdit?(.split(selectedRange)) == true { return }
        willInsertText?(self)
        super.insertText(normalized)
    }

    override func deleteBackward() {
        if markedTextRange == nil, selectedRange == NSRange(location: 0, length: 0),
           onParagraphEdit?(.mergeBackward) == true { return }
        super.deleteBackward()
    }

    override var keyCommands: [UIKeyCommand]? {
        // Hardware keyboards can report Return as either CR or LF. iPadOS 26
        // currently uses LF for XCUIKeyboardKeyReturn, while some keyboards
        // still deliver CR, so register both forms for each shortcut.
        let commands = [
            UIKeyCommand(input: "\r", modifierFlags: .shift, action: #selector(insertSoftLine(_:))),
            UIKeyCommand(input: "\n", modifierFlags: .shift, action: #selector(insertSoftLine(_:))),
            UIKeyCommand(input: "\r", modifierFlags: .control, action: #selector(insertPageBreak(_:))),
            UIKeyCommand(input: "\n", modifierFlags: .control, action: #selector(insertPageBreak(_:)))
        ]
        // Since iOS 15, text input gets the key event before app key commands
        // unless this flag is set. Return is a text-editing key, so without it
        // Shift-Return can be consumed before insertSoftLine is dispatched.
        commands.forEach { $0.wantsPriorityOverSystemBehavior = true }
        return commands + (super.keyCommands ?? [])
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if let key = presses.compactMap(\.key).first(where: { $0.keyCode.rawValue == 0x28 }) {
            if key.modifierFlags.contains(.shift) {
                insertSoftLine(nil)
                return
            }
            if key.modifierFlags.contains(.control) {
                insertPageBreak(nil)
                return
            }
        }
        super.pressesBegan(presses, with: event)
    }

    @objc private func insertPageBreak(_ sender: UIKeyCommand?) {
        unmarkText()
        _ = onParagraphEdit?(.insertPageBreak(selectedRange))
    }

    @objc private func insertSoftLine(_ sender: UIKeyCommand?) {
        insertingSoftBreak = true
        insertText("\n")
        insertingSoftBreak = false
    }

    override func paste(_ sender: Any?) {
        // HWP's current operation is text insertion, so pasted text inherits
        // the document's character style rather than importing rich objects.
        if let value = UIPasteboard.general.string { insertText(value) }
    }
}



@MainActor
enum HWPInlineTextAttributes {
    static func make(block: HWPDocumentBlock, relativeTo container: HWPDocumentBlock? = nil) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        let runs = block.presentation.textRuns
        if runs.map(\.text).joined() == block.text, !runs.isEmpty {
            for run in runs { result.append(NSAttributedString(string: run.text,
                attributes: attributes(run: run, block: block, relativeTo: container))) }
        } else {
            result.append(NSAttributedString(string: block.text,
                attributes: attributes(run: block.presentation.textRuns.first ?? HWPDocumentTextRun(text: ""), block: block, relativeTo: container)))
        }
        return result
    }

    static func typingAttributes(block: HWPDocumentBlock) -> [NSAttributedString.Key: Any] {
        attributes(run: block.presentation.textRuns.first ?? HWPDocumentTextRun(text: ""), block: block)
    }

    static func attributes(run: HWPDocumentTextRun,
                           block: HWPDocumentBlock, relativeTo container: HWPDocumentBlock? = nil) -> [NSAttributedString.Key: Any] {
        let fallback = block.lineLayouts.first?.textHeightPoints ?? 12
        let size = CGFloat(run.displayFontSize(fallback: fallback))
        let name = HWPDocumentFontResolver.resolution(for: run).resolvedName
        var font = name.flatMap { UIFont(name: $0, size: size) } ?? .systemFont(ofSize: size)
        var traits = font.fontDescriptor.symbolicTraits
        if run.isBold { traits.insert(.traitBold) }
        if run.isItalic { traits.insert(.traitItalic) }
        if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
            font = UIFont(descriptor: descriptor, size: size)
        }
        if run.fontWidthPercent != 100 {
            font = UIFont(descriptor: font.fontDescriptor.withMatrix(
                CGAffineTransform(scaleX: run.fontWidthPercent / 100, y: 1)), size: size)
        }
        let paragraph = NSMutableParagraphStyle()
        switch block.presentation.alignment {
        case .leading: paragraph.alignment = .left
        case .centered: paragraph.alignment = .center
        case .trailing: paragraph.alignment = .right
        case .justified, .distributed: paragraph.alignment = .justified
        }
        // The containing rectangle already includes HWP's page/cell indents.
        // While editing, that rectangle stays fixed to preserve the selection;
        // apply only the new offsets until the canvas lays out the committed block.
        let origin = (container ?? block).presentation
        let left = block.presentation.leftMarginPoints - origin.leftMarginPoints
        let markerWidth = block.presentation.list?.marker(in: block)?.reservedWidthPoints
            ?? block.lineLayouts.first?.listMarker?.reservedWidthPoints ?? 0
        paragraph.headIndent = max(0, left) + markerWidth
        paragraph.firstLineHeadIndent = max(0, left + block.presentation.firstLineIndentPoints - origin.firstLineIndentPoints) + markerWidth
        paragraph.tailIndent = min(0, origin.rightMarginPoints - block.presentation.rightMarginPoints)
        paragraph.paragraphSpacingBefore = max(0, block.presentation.spacingBeforePoints - origin.spacingBeforePoints)
        paragraph.paragraphSpacing = max(0, block.presentation.spacingAfterPoints - origin.spacingAfterPoints)
        paragraph.lineBreakMode = .byWordWrapping
        let largest = block.presentation.textRuns.compactMap(\.fontSizePoints).max() ?? Double(size)
        paragraph.lineSpacing = block.presentation.lineSpacingPercent.map { largest * ($0 / 100 - 1) }
            ?? block.lineLayouts.first?.lineSpacingPoints ?? 0
        if let first = block.lineLayouts.first {
            paragraph.minimumLineHeight = max(first.lineHeightPoints, size)
        }
        var attributes: [NSAttributedString.Key: Any] = [
            .hwpCharacterStyle: run.withText(""),
            .font: font, .foregroundColor: color(run.textColorRGB ?? 0),
            .paragraphStyle: paragraph, .kern: size * run.letterSpacingPercent / 100
        ]
        if run.isUnderlined { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if run.isBold, !font.fontDescriptor.symbolicTraits.contains(.traitBold) {
            attributes[.strokeWidth] = -2.5
        }
        if run.isItalic, !font.fontDescriptor.symbolicTraits.contains(.traitItalic) {
            attributes[.obliqueness] = 0.2
        }
        if run.isStruckThrough { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if let background = run.backgroundColorRGB { attributes[.backgroundColor] = color(background) }
        let baseline = run.displayBaselineOffset(fallback: fallback)
        if baseline != 0 { attributes[.baselineOffset] = baseline }
        return attributes
    }

    private static func color(_ rgb: UInt32) -> UIColor {
        UIColor(red: CGFloat((rgb >> 16) & 255) / 255,
            green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }
}

nonisolated extension NSAttributedString.Key {
    static let hwpCharacterStyle = NSAttributedString.Key("RivoPad.HWPCharacterStyle")
}
