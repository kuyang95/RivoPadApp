import Combine
import RivoDocumentEngine
import SwiftUI
import UIKit

// The 간편 보기 editors: 문단 편집 (text, split and merge, 글자, 문단, 표 넣기, 링크,
// 각주·미주, 쪽 나누기), the table row's 표 편집, and 다른 색… for the colour menus.
// Every change goes through the view model and the engine as one undo step.

// MARK: - Colours

/// "#RRGGBB" colour codes for 다른 색….
nonisolated enum HWPColorCode {
    static func parse(_ text: String) -> UInt32? {
        var code = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if code.hasPrefix("#") { code.removeFirst() }
        guard code.count == 6, code.allSatisfy(\.isHexDigit) else { return nil }
        return UInt32(code, radix: 16)
    }

    static func string(_ rgb: UInt32) -> String {
        String(format: "#%06X", rgb & 0xFFFFFF)
    }

    static func color(_ rgb: UInt32) -> Color {
        Color(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255,
            blue: Double(rgb & 255) / 255)
    }

    static func rgb(_ color: Color) -> UInt32? {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        func byte(_ value: CGFloat) -> UInt32 { UInt32((min(1, max(0, value)) * 255).rounded()) }
        return byte(red) << 16 | byte(green) << 8 | byte(blue)
    }
}

enum HWPCustomColorTarget: String, Identifiable {
    case text, highlight, fill, border
    var id: String { rawValue }
    var title: String {
        switch self {
        case .text: "글자색"
        case .highlight: "강조색"
        case .fill: "채우기"
        case .border: "선 색상"
        }
    }
}

/// 다른 색…: the system colour picker and a "#RRGGBB" code, so any colour can be chosen
/// without gestures (VoiceOver reads and edits the code field).
struct HWPCustomColorSheet: View {
    let title: String
    let onPick: (UInt32) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var rgb: UInt32
    @State private var code: String

    init(title: String, initial: UInt32?, onPick: @escaping (UInt32) -> Void) {
        self.title = title
        self.onPick = onPick
        let start = (initial ?? 0) & 0xFFFFFF
        _rgb = State(initialValue: start)
        _code = State(initialValue: HWPColorCode.string(start))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(HWPColorCode.color(rgb))
                            .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.4)) }
                            .frame(width: 48, height: 48)
                        Text(HWPColorCode.string(rgb)).monospaced()
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(AppLocalization.format("고른 색: %@", HWPColorCode.string(rgb)))
                    ColorPicker(selection: Binding(get: { HWPColorCode.color(rgb) }, set: { color in
                        guard let value = HWPColorCode.rgb(color) else { return }
                        rgb = value
                        code = HWPColorCode.string(value)
                    }), supportsOpacity: false) {
                        Text("색 고르기")
                    }
                    .frame(minHeight: 48)
                    .accessibilityIdentifier("hwp-custom-color-picker")
                }
                Section {
                    TextField("색 코드 (#RRGGBB)", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .monospaced()
                        .onChange(of: code) { _, value in
                            if let parsed = HWPColorCode.parse(value) { rgb = parsed }
                        }
                        .accessibilityLabel("색 코드 (#RRGGBB)")
                        .accessibilityIdentifier("hwp-custom-color-code")
                } footer: {
                    Text("#과 16진수 여섯 자리로 입력하세요. 예: #1F6FB2")
                }
            }
            .navigationTitle(AppLocalization.string(title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("이 색 사용") {
                        guard let value = HWPColorCode.parse(code) else { return }
                        onPick(value)
                        dismiss()
                    }
                    .disabled(HWPColorCode.parse(code) == nil)
                    .accessibilityIdentifier("hwp-custom-color-use")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// A Form row whose menu lists named colours, optional choices (유지, 없음) and 다른 색….
private struct HWPColorMenuRow<Choice: Hashable>: View {
    let title: String
    let selection: Choice
    let choices: [(Choice, String)]
    let named: [HWPFormattingColor]
    let value: (Choice) -> UInt32?
    let make: (UInt32) -> Choice
    let onSelect: (Choice) -> Void
    let onOther: () -> Void

    private var valueName: String {
        if let choice = choices.first(where: { $0.0 == selection }) { return AppLocalization.string(choice.1) }
        guard let rgb = value(selection) else { return "" }
        return named.first(where: { $0.rgb == rgb }).map { AppLocalization.string($0.name) } ?? HWPColorCode.string(rgb)
    }

    var body: some View {
        Menu {
            ForEach(choices, id: \.0) { choice, name in
                Button { onSelect(choice) } label: {
                    if choice == selection { Label(AppLocalization.string(name), systemImage: "checkmark") }
                    else { Text(AppLocalization.string(name)) }
                }
            }
            if !choices.isEmpty { Divider() }
            ForEach(named, id: \.rgb) { color in
                Button { onSelect(make(color.rgb)) } label: {
                    Label(AppLocalization.string(color.name),
                        systemImage: value(selection) == color.rgb ? "checkmark.circle.fill" : "circle.fill")
                        .tint(color.color)
                }
            }
            Divider()
            Button("다른 색…", systemImage: "paintpalette", action: onOther)
        } label: {
            HStack {
                Text(AppLocalization.string(title)).foregroundStyle(VisionCraftUI.primaryText)
                Spacer()
                Text(valueName).foregroundStyle(.secondary)
                if let rgb = value(selection) {
                    Circle().fill(HWPColorCode.color(rgb))
                        .overlay { Circle().stroke(Color.secondary.opacity(0.4)) }
                        .frame(width: 24, height: 24)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(AppLocalization.string(title))
        .accessibilityValue(valueName)
    }
}

// MARK: - 글자

/// The 글자 sheet's on/off effects. Each starts on only when every selected character has it
/// (as the ribbon shows a selection), and every control the user touches is sent with the value
/// it ends on — even when that equals where it started — so a mixed selection can be made all
/// on or all off.
nonisolated struct HWPCharacterEffects {
    enum Effect: CaseIterable { case bold, italic, underline, strikethrough, superscript, `subscript` }

    private(set) var values: [Effect: Bool] = [:]
    private(set) var touched: Set<Effect> = []

    init(runs: [HWPDocumentTextRun]) {
        let runs = runs.isEmpty ? [HWPDocumentTextRun(text: "")] : runs
        for effect in Effect.allCases { values[effect] = runs.allSatisfy { Self.value(effect, of: $0) } }
    }

    subscript(effect: Effect) -> Bool { values[effect] ?? false }

    mutating func set(_ effect: Effect, _ on: Bool) {
        values[effect] = on
        touched.insert(effect)
        // Superscript and subscript exclude each other, as in the engine.
        if on, effect == .superscript { values[.subscript] = false; touched.insert(.subscript) }
        if on, effect == .subscript { values[.superscript] = false; touched.insert(.superscript) }
    }

    var commands: [HWPFormattingCommand] {
        Effect.allCases.filter(touched.contains).map { effect in
            let on = self[effect]
            switch effect {
            case .bold: return .bold(on)
            case .italic: return .italic(on)
            case .underline: return .underline(on)
            case .strikethrough: return .strikethrough(on)
            case .superscript: return .superscript(on)
            case .subscript: return .subscript(on)
            }
        }
    }

    /// The runs a command on `range` changes (the whole paragraph without a selection).
    static func runs(in block: HWPDocumentBlock, range: NSRange) -> [HWPDocumentTextRun] {
        let all = HWPDocumentFormatting.runs(in: block)
        guard range.length > 0 else { return all }
        var offset = 0
        let selected = all.filter { run in
            let span = NSRange(location: offset, length: run.text.utf16.count)
            offset += span.length
            return NSIntersectionRange(span, range).length > 0
        }
        return selected.isEmpty ? [HWPDocumentFormatting.run(at: range.location, in: block)] : selected
    }

    private static func value(_ effect: Effect, of run: HWPDocumentTextRun) -> Bool {
        switch effect {
        case .bold: run.isBold
        case .italic: run.isItalic
        case .underline: run.isUnderlined
        case .strikethrough: run.isStruckThrough
        case .superscript: run.isSuperscript
        case .subscript: run.isSubscript
        }
    }
}

private enum HWPHighlightChoice: Hashable {
    case keep, none, color(UInt32)
    var rgb: UInt32? { if case .color(let rgb) = self { rgb } else { nil } }
}

private enum HWPTextColorChoice: Hashable {
    case keep, color(UInt32)
    var rgb: UInt32? { if case .color(let rgb) = self { rgb } else { nil } }
}

/// The 글자 tools as a sheet, for the selection (the whole paragraph without one): font, size,
/// bold to subscript, colour and highlight, or 글자 서식 지우기. Font, size and colours start
/// from the selection's first character and are sent when chosen; the effects follow
/// `HWPCharacterEffects`.
struct HWPCharacterFormattingSheet: View {
    let run: HWPDocumentTextRun
    let selectedRuns: [HWPDocumentTextRun]
    let scope: String
    let documentFonts: [String]
    let onApply: ([HWPFormattingCommand]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var font: String?
    @State private var showsFonts = false
    @State private var sizeText = ""
    @State private var effects: HWPCharacterEffects
    @State private var color = HWPTextColorChoice.keep
    @State private var highlight = HWPHighlightChoice.keep
    @State private var customColor: HWPCustomColorTarget?

    init(run: HWPDocumentTextRun, selectedRuns: [HWPDocumentTextRun], scope: String, documentFonts: [String],
         onApply: @escaping ([HWPFormattingCommand]) -> Void) {
        self.run = run
        self.selectedRuns = selectedRuns
        self.scope = scope
        self.documentFonts = documentFonts
        self.onApply = onApply
        _effects = State(initialValue: HWPCharacterEffects(runs: selectedRuns.isEmpty ? [run] : selectedRuns))
    }

    private func effect(_ effect: HWPCharacterEffects.Effect) -> Binding<Bool> {
        Binding(get: { effects[effect] }, set: { effects.set(effect, $0) })
    }

    private var currentSize: Double { run.fontSizePoints ?? 10 }
    private var size: Double? {
        Double(sizeText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }
    private var sizeValid: Bool {
        sizeText.trimmingCharacters(in: .whitespaces).isEmpty || (size.map { $0.isFinite && $0 > 0 } ?? false)
    }

    var commands: [HWPFormattingCommand] {
        var result: [HWPFormattingCommand] = []
        if let font { result.append(.font(font)) }
        if let size, size.isFinite, size > 0 { result.append(.size(size)) }
        result += effects.commands
        if let rgb = color.rgb { result.append(.color(rgb)) }
        switch highlight {
        case .keep: break
        case .none: result.append(.highlight(nil))
        case .color(let rgb): result.append(.highlight(rgb))
        }
        return result
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { showsFonts = true } label: {
                        HStack {
                            Text("글꼴").foregroundStyle(VisionCraftUI.primaryText)
                            Spacer()
                            Text(font ?? run.fontName ?? AppLocalization.string("유지")).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 44)
                    }
                    .accessibilityLabel("글꼴")
                    .accessibilityValue(font ?? run.fontName ?? AppLocalization.string("유지"))
                    .accessibilityIdentifier("hwp-character-font")
                    HStack {
                        Text("글자 크기")
                        Spacer()
                        TextField(String(format: "%g", currentSize), text: $sizeText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 90)
                            .foregroundStyle(sizeValid ? VisionCraftUI.primaryText : Color.red)
                            .accessibilityLabel("글자 크기")
                            .accessibilityValue(sizeText.isEmpty
                                ? AppLocalization.format("유지, %@ pt", String(format: "%g", currentSize)) : sizeText + " pt")
                            .accessibilityIdentifier("hwp-character-size")
                        Text("pt").foregroundStyle(.secondary)
                        Stepper("글자 크기") { stepSize(1) } onDecrement: { stepSize(-1) }
                            .labelsHidden()
                            .fixedSize()
                    }
                } footer: {
                    Text(scope)
                }
                Section {
                    Toggle("굵게", isOn: effect(.bold)).accessibilityIdentifier("hwp-character-bold")
                    Toggle("기울임", isOn: effect(.italic))
                    Toggle("밑줄", isOn: effect(.underline))
                    Toggle("취소선", isOn: effect(.strikethrough))
                    Toggle("위 첨자", isOn: effect(.superscript))
                    Toggle("아래 첨자", isOn: effect(.subscript))
                }
                Section {
                    HWPColorMenuRow(title: "글자색", selection: color, choices: [(.keep, "유지")],
                        named: HWPFormattingColor.all, value: \.rgb, make: { .color($0) },
                        onSelect: { color = $0 }, onOther: { customColor = .text })
                        .accessibilityIdentifier("hwp-character-color")
                    HWPColorMenuRow(title: "강조색", selection: highlight, choices: [(.keep, "유지"), (.none, "없음")],
                        named: HWPFormattingColor.highlights, value: \.rgb, make: { .color($0) },
                        onSelect: { highlight = $0 }, onOther: { customColor = .highlight })
                        .accessibilityIdentifier("hwp-character-highlight")
                }
                Section {
                    Button("글자 서식 지우기") { onApply([.clearCharacterFormatting]) }
                        .accessibilityHint("바탕 10pt, 검정색 기본 글자로 변경")
                        .accessibilityIdentifier("hwp-character-clear")
                }
            }
            .navigationTitle("글자")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("적용") { onApply(commands) }
                        .disabled(!sizeValid)
                        .accessibilityIdentifier("hwp-character-apply")
                }
            }
            .sheet(isPresented: $showsFonts) {
                HWPFormattingFontPicker(documentFonts: documentFonts, selected: font ?? run.fontName) { name in
                    font = name
                    showsFonts = false
                }
            }
            .sheet(item: $customColor) { target in
                HWPCustomColorSheet(title: target.title,
                    initial: target == .text ? (color.rgb ?? run.textColorRGB) : (highlight.rgb ?? run.backgroundColorRGB)) { rgb in
                    if target == .text { color = .color(rgb) } else { highlight = .color(rgb) }
                }
            }
        }
    }

    private func stepSize(_ delta: Double) {
        let base = (size.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? currentSize).rounded()
        sizeText = String(format: "%g", min(144, max(6, base + delta)))
    }
}

// MARK: - 문단 편집

struct HWPAccessibleParagraphRequest: Identifiable {
    let id = UUID()
    let blockID: String
    let text: String
    /// UTF-16 caret in `text`; nil puts it at the end.
    var caret: Int?
}

nonisolated enum HWPAccessibleTextRange {
    /// A TextEditor selection as the engine's UTF-16 range in the normalized text
    /// (no selection: the end of the text).
    static func utf16Range(_ range: Range<String.Index>?, in text: String) -> NSRange {
        let length = HWPInlineTextInput.normalized(text).utf16.count
        guard let range, range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex else {
            return NSRange(location: length, length: 0)
        }
        func offset(_ index: String.Index) -> Int {
            HWPInlineTextInput.normalized(String(text[..<index])).utf16.count
        }
        let lower = offset(range.lowerBound), upper = offset(range.upperBound)
        return NSRange(location: lower, length: max(0, upper - lower))
    }

    static func index(utf16Offset offset: Int, in text: String) -> String.Index {
        let clamped = min(max(0, offset), text.utf16.count)
        if clamped == text.utf16.count { return text.endIndex }
        let index = String.Index(utf16Offset: clamped, in: text)
        // A caret inside a character goes to its start.
        return text.indices.last(where: { $0 <= index }) ?? text.startIndex
    }
}

/// 문단 편집 for one paragraph of the 간편 보기: its text, then 구조 (split at the cursor,
/// merge with the paragraph before), 글자 and 문단, and 삽입 (table, link, notes, page break).
/// Tools open over this sheet; cancelling one comes back here with the text as typed.
struct HWPAccessibleParagraphEditor: View {
    let request: HWPAccessibleParagraphRequest
    @ObservedObject var viewModel: HWPDocumentViewModel
    let documentFonts: [String]
    /// The sheet is done; `true` when something was changed and the status should be read out.
    let onClose: (Bool) -> Void
    /// After a split or a page break: edit the new paragraph.
    let onReopen: (HWPAccessibleParagraphRequest) -> Void
    /// Tools that rewrite the file. The sheet stays open, with the text as typed, until they
    /// succeed; a failure is shown here.
    let onLink: ([HWPDocumentBlock], HWPHyperlinkEditing.Action, HWPHyperlinkEditing.Selection) async throws -> Void
    let onNote: ([HWPDocumentBlock], HWPNoteEditing.Action) async throws -> Void
    let onInsertTable: ([HWPDocumentBlock], HWPTableInsertion.Request) async throws -> Void

    private struct ToolSheet: Identifiable {
        enum Kind {
            case character(HWPDocumentTextRun, [HWPDocumentTextRun], NSRange, String)
            case paragraph(HWPDocumentBlock)
            case table([HWPDocumentBlock], HWPTableInsertion.Selection)
            case link([HWPDocumentBlock], HWPHyperlinkEditing.Selection)
            case notes([HWPDocumentBlock], HWPNoteEditing.Selection)
        }
        let id = UUID()
        let kind: Kind
    }

    @State private var text: String
    @State private var selection: TextSelection?
    @State private var message: String?
    @State private var tool: ToolSheet?
    @StateObject private var runner = HWPAccessibleToolRunner()
    @FocusState private var focused: Bool

    init(request: HWPAccessibleParagraphRequest, viewModel: HWPDocumentViewModel, documentFonts: [String],
         onClose: @escaping (Bool) -> Void,
         onReopen: @escaping (HWPAccessibleParagraphRequest) -> Void,
         onLink: @escaping ([HWPDocumentBlock], HWPHyperlinkEditing.Action, HWPHyperlinkEditing.Selection) async throws -> Void,
         onNote: @escaping ([HWPDocumentBlock], HWPNoteEditing.Action) async throws -> Void,
         onInsertTable: @escaping ([HWPDocumentBlock], HWPTableInsertion.Request) async throws -> Void) {
        self.request = request
        self.viewModel = viewModel
        self.documentFonts = documentFonts
        self.onClose = onClose
        self.onReopen = onReopen
        self.onLink = onLink
        self.onNote = onNote
        self.onInsertTable = onInsertTable
        _text = State(initialValue: request.text)
        let caret = HWPAccessibleTextRange.index(utf16Offset: request.caret ?? request.text.utf16.count, in: request.text)
        _selection = State(initialValue: TextSelection(insertionPoint: caret))
    }

    private var block: HWPDocumentBlock? { viewModel.blocks.first { $0.id == request.blockID } }

    private var range: NSRange {
        guard case .selection(let selected)? = selection?.indices else {
            return HWPAccessibleTextRange.utf16Range(nil, in: text)
        }
        return HWPAccessibleTextRange.utf16Range(selected, in: text)
    }

    private var caret: NSRange { NSRange(location: range.location, length: 0) }

    private var canBreakPage: Bool {
        guard let block, HWPParagraphEditing.supports(block),
              let layout = viewModel.pageLayouts.first(where: {
                  $0.sectionIndex == HWPPageSetup.sectionIndex(block.sectionPath)
              }) else { return false }
        return layout.columnLayout.columns.count <= 1
    }

    var body: some View {
        NavigationStack {
            Form {
                if let message {
                    Section {
                        Label(message, systemImage: "exclamationmark.circle")
                            .foregroundStyle(VisionCraftUI.secondaryText)
                    }
                }
                if isBusy {
                    Section {
                        ProgressView(viewModel.status).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Section {
                    TextEditor(text: $text, selection: $selection)
                        .focused($focused)
                        .disabled(isBusy)
                        .frame(minHeight: 120, maxHeight: 320)
                        .accessibilityLabel(block.flatMap(HWPAccessibleDocument.label(for:))
                            ?? AppLocalization.string("선택한 한글 문단 편집"))
                        .accessibilityIdentifier("hwp-paragraph-editor-text")
                }
                Section("구조") {
                    row("커서에서 문단 나누기", icon: "return", id: "split",
                        enabled: block.map(HWPParagraphEditing.supportsStructure) ?? false) {
                        structure(.split(range))
                    }
                    row("앞 문단과 합치기", icon: "arrow.up.to.line", id: "merge",
                        enabled: block.map(HWPParagraphEditing.supportsStructure) ?? false) {
                        structure(.mergeBackward)
                    }
                }
                Section {
                    row("글자", icon: "textformat", id: "character", navigates: true) { openCharacter() }
                    row("문단", icon: "paragraph", id: "paragraph", navigates: true) { openParagraph() }
                }
                Section("삽입") {
                    row("커서에 표 넣기", icon: "tablecells", id: "table", navigates: true,
                        enabled: block.map(HWPParagraphEditing.supports) ?? false) { openTable() }
                    row("링크", icon: "link", id: "link", navigates: true,
                        enabled: block.map(HWPParagraphEditing.supports) ?? false) { openLink() }
                    row("각주·미주", icon: "text.badge.plus", id: "notes", navigates: true) { openNotes() }
                    row("쪽 나누기", icon: "doc.badge.plus", id: "page-break", enabled: canBreakPage) {
                        structure(.insertPageBreak(caret))
                    }
                    if block?.presentation.pageBreakBefore == true {
                        row("쪽 나누기 없애기", icon: "doc.badge.ellipsis", id: "page-break-remove", enabled: canBreakPage) {
                            structure(.removePageBreak)
                        }
                    }
                }
            }
            .navigationTitle("문단 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { onClose(false) }
                        .disabled(isBusy)
                        .accessibilityIdentifier("hwp-paragraph-editor-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("적용") {
                        let changed = block?.text != HWPInlineTextInput.normalized(text)
                        if viewModel.applyAccessibleParagraphText(request.blockID, text: text) { onClose(changed) }
                    }
                    .disabled(isBusy)
                    .accessibilityIdentifier("hwp-paragraph-editor-apply")
                }
            }
            .sheet(item: $tool) { sheet in toolView(sheet) }
            .onAppear { focused = true }
        }
        .presentationDetents([.large])
        // A file-rewriting tool is running: the sheet stays until it has finished.
        .interactiveDismissDisabled(isBusy)
    }

    private var isBusy: Bool { runner.isRunning || viewModel.isSaving }

    private func row(_ title: String, icon: String, id: String, navigates: Bool = false,
                     enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(AppLocalization.string(title), systemImage: icon)
                    .foregroundStyle(enabled ? VisionCraftUI.primaryText : VisionCraftUI.secondaryText)
                Spacer()
                if navigates {
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .disabled(!enabled || isBusy)
        .accessibilityIdentifier("hwp-paragraph-editor-\(id)")
    }

    @ViewBuilder
    private func toolView(_ sheet: ToolSheet) -> some View {
        switch sheet.kind {
        case .character(let run, let runs, let range, let scope):
            HWPCharacterFormattingSheet(run: run, selectedRuns: runs, scope: scope, documentFonts: documentFonts) { commands in
                format(commands, range: range)
            }
        case .paragraph(let draft):
            HWPParagraphFormattingSheet(style: draft.presentation, includesAlignment: true,
                canApplyList: HWPListFormatting.supports(draft),
                listStyle: { kind in HWPListFormatting.style(kind, for: draft, in: viewModel.blocks) }) { commands in
                format(commands, range: NSRange(location: 0, length: 0))
            }
        case .table(let drafts, let selection):
            HWPTableInsertionSheet(selection: selection) { request in
                tool = nil
                run { try await onInsertTable(drafts, request) }
            }
        case .link(let drafts, let selection):
            HWPHyperlinkSheet(selection: selection) { action in
                tool = nil
                run { try await onLink(drafts, action, selection) }
            }
        case .notes(let drafts, let selection):
            HWPNoteManager(selection: selection) { action in
                tool = nil
                run { try await onNote(drafts, action) }
            }
        }
    }

    /// Runs a file-rewriting tool; the sheet is locked meanwhile (the tool writes the text as it
    /// was when it opened), closes only after it succeeded, else shows why and keeps the text.
    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        message = nil
        focused = false
        Task { @MainActor in
            guard let outcome = await runner.perform(work) else { return }
            if let failure = outcome.failure { show(failure) } else { onClose(true) }
        }
    }

    private func show(_ text: String) {
        message = text
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    private func structure(_ operation: HWPParagraphEdit) {
        guard let result = viewModel.editAccessibleParagraph(request.blockID, text: text, operation: operation) else {
            show(HWPParagraphEditing.unavailableMessage)
            return
        }
        switch operation {
        case .split, .insertPageBreak:
            guard let focused = result.blocks.first(where: { $0.id == result.focusedID }) else { return onClose(true) }
            onReopen(HWPAccessibleParagraphRequest(blockID: focused.id, text: focused.text, caret: result.caret))
        case .mergeBackward, .removePageBreak:
            onClose(true)
        }
    }

    private func format(_ commands: [HWPFormattingCommand], range: NSRange) {
        tool = nil
        guard !commands.isEmpty else { return }
        if viewModel.formatAccessibleParagraph(request.blockID, text: text, range: range, commands: commands) {
            onClose(true)
        }
    }

    private func openCharacter() {
        guard let draft = viewModel.accessibleParagraphDraft(request.blockID, text: text) else { return }
        let range = range
        let run = HWPDocumentFormatting.run(at: range.length > 0 ? range.location : 0, in: draft)
        let scope: String
        if range.length > 0, let selected = Range(range, in: draft.text) {
            scope = AppLocalization.format("선택한 글자 ‘%@’에 적용합니다.", String(draft.text[selected].prefix(40)))
        } else {
            scope = AppLocalization.string("문단 전체에 적용합니다.")
        }
        message = nil
        tool = ToolSheet(kind: .character(run, HWPCharacterEffects.runs(in: draft, range: range), range, scope))
    }

    private func openParagraph() {
        guard let draft = viewModel.accessibleParagraphDraft(request.blockID, text: text) else { return }
        message = nil
        tool = ToolSheet(kind: .paragraph(draft))
    }

    private func openTable() {
        guard let drafts = viewModel.accessibleParagraphDrafts(request.blockID, text: text),
              let selection = HWPTableInsertion.selection(blocks: drafts, selectedID: request.blockID,
                range: caret, layouts: viewModel.pageLayouts) else {
            return show(AppLocalization.string("이 위치에는 표를 넣을 수 없습니다."))
        }
        message = nil
        tool = ToolSheet(kind: .table(drafts, selection))
    }

    private func openLink() {
        guard let drafts = viewModel.accessibleParagraphDrafts(request.blockID, text: text),
              let selection = HWPHyperlinkEditing.selection(blocks: drafts, selectedID: request.blockID, range: range) else {
            return show(AppLocalization.string("링크로 만들 글자를 선택하세요."))
        }
        message = nil
        tool = ToolSheet(kind: .link(drafts, selection))
    }

    private func openNotes() {
        guard let drafts = viewModel.accessibleParagraphDrafts(request.blockID, text: text),
              let draft = drafts.first(where: { $0.id == request.blockID }) else { return }
        let insertion = HWPNoteEditing.insertion(blocks: drafts, selectedID: request.blockID, range: caret)
        message = nil
        tool = ToolSheet(kind: .notes(drafts, HWPNoteEditing.selection(blocks: drafts,
            sectionPath: draft.sectionPath, insertion: insertion)))
    }
}

/// Runs one file-rewriting tool of the 문단 편집 sheet at a time; `isRunning` locks the sheet.
@MainActor
final class HWPAccessibleToolRunner: ObservableObject {
    struct Outcome { let failure: String? }

    @Published private(set) var isRunning = false

    /// nil when another tool is still running (nothing was done); otherwise the outcome, with
    /// the message to show when `work` failed.
    func perform(_ work: @MainActor () async throws -> Void) async -> Outcome? {
        guard !isRunning else { return nil }
        isRunning = true
        defer { isRunning = false }
        do {
            try await work()
            return Outcome(failure: nil)
        } catch {
            return Outcome(failure: error.localizedDescription)
        }
    }
}

// MARK: - 표 편집

/// 표 편집 from a table row of the 간편 보기: pick the cell the change is made at, then its
/// 셀 서식, 행·열 크기, or a change to the table (rows, columns, merging, deleting).
struct HWPAccessibleTableEditSheet: View {
    let row: HWPAccessibleRow
    let fieldNames: [String: String]
    let actions: (String) -> [HWPTableStructureAction]
    let sizing: (String) -> HWPTableSizing.Selection?
    let onAction: (HWPTableStructureAction, String) -> Void
    let onFormat: (String, HWPCellFormat) -> Void
    let onResize: (String, HWPTableDimensions) -> Void
    @Environment(\.dismiss) private var dismiss

    init(row: HWPAccessibleRow, fieldNames: [String: String],
         actions: @escaping (String) -> [HWPTableStructureAction],
         sizing: @escaping (String) -> HWPTableSizing.Selection?,
         onAction: @escaping (HWPTableStructureAction, String) -> Void,
         onFormat: @escaping (String, HWPCellFormat) -> Void,
         onResize: @escaping (String, HWPTableDimensions) -> Void) {
        self.row = row
        self.fieldNames = fieldNames
        self.actions = actions
        self.sizing = sizing
        self.onAction = onAction
        self.onFormat = onFormat
        self.onResize = onResize
    }

    /// Cells that have a paragraph the engine can edit, with that paragraph as the anchor.
    static func cells(of row: HWPAccessibleRow) -> [(cell: HWPAccessibleCell, anchor: HWPDocumentBlock)] {
        row.cells.compactMap { cell in cell.blocks.first(where: \.isEditable).map { (cell, $0) } }
    }

    private func title(_ cell: HWPAccessibleCell) -> String {
        [fieldNames[cell.id], cell.columnDescription, cell.mergeDescription].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Self.cells(of: row), id: \.anchor.id) { item in
                        NavigationLink(value: item.anchor.id) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(title(item.cell))
                                Text(item.cell.displayText)
                                    .font(.footnote)
                                    .foregroundStyle(VisionCraftUI.secondaryText)
                                    .lineLimit(2)
                            }
                            .frame(minHeight: 44, alignment: .leading)
                        }
                        .accessibilityIdentifier("hwp-table-edit-cell-\(item.cell.location.column)")
                    }
                } header: {
                    Text(row.tableTitle + " · " + row.title)
                }
            }
            .navigationTitle("기준 칸 고르기")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { id in
                if let item = Self.cells(of: row).first(where: { $0.anchor.id == id }) {
                    HWPAccessibleTableCellActions(title: title(item.cell), anchor: item.anchor,
                        actions: actions(id), sizing: sizing(id),
                        onAction: onAction, onFormat: onFormat, onResize: onResize)
                        .visionCraftRouteBackButton()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }.accessibilityIdentifier("hwp-table-edit-cancel")
                }
            }
        }
    }
}

private struct HWPAccessibleTableCellActions: View {
    let title: String
    let anchor: HWPDocumentBlock
    let actions: [HWPTableStructureAction]
    let sizing: HWPTableSizing.Selection?
    let onAction: (HWPTableStructureAction, String) -> Void
    let onFormat: (String, HWPCellFormat) -> Void
    let onResize: (String, HWPTableDimensions) -> Void
    @State private var showsFormat = false
    @State private var sizingSelection: HWPTableSizing.Selection?

    private var canFormat: Bool { HWPCellFormatting.supports(anchor) }

    var body: some View {
        List {
            if canFormat || sizing != nil {
                Section {
                    if canFormat {
                        Button { showsFormat = true } label: {
                            Label("셀 서식", systemImage: "square.grid.2x2").frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("hwp-table-edit-cell-format")
                    }
                    if let sizing {
                        Button { sizingSelection = sizing } label: {
                            Label("행·열 크기", systemImage: "arrow.up.left.and.arrow.down.right").frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("hwp-table-edit-size")
                    }
                }
            }
            if !actions.isEmpty {
                Section {
                    ForEach(actions, id: \.self) { action in
                        Button(role: action.isDeletion ? .destructive : nil) { onAction(action, anchor.id) } label: {
                            Text(action.title).frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("hwp-table-edit-\(action.rawValue)")
                    }
                } footer: {
                    if actions.contains(where: { [.splitColumns, .splitRows, .unmerge].contains($0) }) {
                        Text("나누면 내용은 첫 번째 셀에 남습니다.")
                    }
                }
            }
            if !canFormat, sizing == nil, actions.isEmpty {
                Text("이 표는 행·열을 바꿀 수 없습니다.").foregroundStyle(VisionCraftUI.secondaryText)
            }
        }
        .navigationTitle(AppLocalization.format("%@ 기준 표 편집", title))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsFormat) {
            if let cell = anchor.tableLocation {
                HWPCellFormattingSheet(cell: cell) { format in
                    showsFormat = false
                    onFormat(anchor.id, format)
                }
            }
        }
        .sheet(item: $sizingSelection) { selection in
            HWPTableSizingSheet(selection: selection) { dimensions in
                sizingSelection = nil
                onResize(selection.id, dimensions)
            }
        }
    }
}
