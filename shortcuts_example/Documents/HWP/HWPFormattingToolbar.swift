import RivoDocumentEngine
import SwiftUI
import UIKit

enum HWPRibbonTab: String, CaseIterable, Identifiable {
    case character, paragraph, insert, page, find, table, object
    var id: String { rawValue }
    var title: String {
        switch self {
        case .character: "글자"
        case .paragraph: "문단"
        case .insert: "삽입"
        case .page: "쪽"
        case .find: "찾기"
        case .table: "표"
        case .object: "개체"
        }
    }
}

struct HWPRibbonTabBar: View {
    let tabs: [HWPRibbonTab]
    let selected: HWPRibbonTab
    @Binding var isCollapsed: Bool
    let onSelect: (HWPRibbonTab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(tabs) { tab in
                            Button { onSelect(tab) } label: {
                                Text(AppLocalization.string(tab.title))
                                    .font(.subheadline.weight(selected == tab ? .semibold : .regular))
                                    .foregroundStyle(selected == tab ? Color.accentColor : .primary)
                                    .padding(.horizontal, 16)
                                    .frame(minHeight: 48)
                                    .background(selected == tab ? Color.accentColor.opacity(0.12) : .clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                            }
                            .id(tab)
                            .accessibilityIdentifier("hwp-ribbon-\(tab.rawValue)")
                            .accessibilityAddTraits(selected == tab ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .onChange(of: selected) { _, tab in proxy.scrollTo(tab, anchor: .trailing) }
            }
            Button { isCollapsed.toggle() } label: {
                Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                    .frame(width: 48, height: 48)
            }
            .accessibilityLabel(isCollapsed ? "도구 펼치기" : "도구 접기")
            .accessibilityIdentifier("hwp-ribbon-collapse")
        }
        .frame(height: 48)
        .buttonStyle(.plain)
        .background(VisionCraftUI.surface)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("문서 도구 탭")
    }
}

struct HWPFormattingToolbar: View {
    enum ToolSection { case all, character, paragraph, table }
    var section: ToolSection = .all
    @ObservedObject var editor: HWPInlineEditingSession
    let documentFonts: [String]
    var tableActions: [HWPTableStructureAction] = []
    var cellActions: [HWPTableStructureAction] = []
    var onTableAction: ((HWPTableStructureAction) -> Void)? = nil
    var tableSizing: (() -> HWPTableSizing.Selection?)? = nil
    var onTableResize: ((String, HWPTableDimensions) -> Void)? = nil
    @State private var showsFonts = false
    @State private var showsParagraph = false
    @State private var showsSize = false
    @State private var showsCell = false
    @State private var sizeText = ""
    @State private var pendingCommand: HWPFormattingCommand?
    @State private var sizingSelection: HWPTableSizing.Selection?
    @State private var pendingSize: (String, HWPTableDimensions)?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                if (section == .all || section == .table), let block = editor.activation?.block, HWPCellFormatting.supports(block) {
                    Button { showsCell = true } label: {
                        Label("셀", systemImage: "square.grid.2x2").frame(minHeight: 48).padding(.horizontal, 8)
                    }.accessibilityIdentifier("hwp-format-cell")
                    if let onTableAction, !tableActions.isEmpty {
                        Menu {
                            ForEach(HWPTableStructureAction.trackActions, id: \.self) { action in
                                Button(role: action.isDeletion ? .destructive : nil) { onTableAction(action) } label: {
                                    Text(AppLocalization.string(action.title))
                                }.disabled(!tableActions.contains(action))
                                    .accessibilityIdentifier("hwp-table-\(action.rawValue)")
                            }
                            Divider()
                            Button(role: .destructive) { onTableAction(.deleteTable) } label: { Text("표 삭제") }
                                .disabled(!tableActions.contains(.deleteTable))
                                .accessibilityIdentifier("hwp-table-deleteTable")
                        } label: {
                            Text("표 편집").frame(minHeight: 48).padding(.horizontal, 8)
                        }.accessibilityIdentifier("hwp-format-table-structure")
                    }
                    if let onTableAction, !cellActions.isEmpty {
                        Menu {
                            Section {
                                ForEach([HWPTableStructureAction.mergeRight, .mergeBelow], id: \.self) { action in
                                    Button(AppLocalization.string(action.title)) { onTableAction(action) }
                                        .disabled(!cellActions.contains(action))
                                        .accessibilityIdentifier("hwp-table-\(action.rawValue)")
                                }
                            }
                            Section {
                                ForEach([HWPTableStructureAction.splitColumns, .splitRows, .unmerge], id: \.self) { action in
                                    Button(AppLocalization.string(action.title)) { onTableAction(action) }
                                        .disabled(!cellActions.contains(action))
                                        .accessibilityIdentifier("hwp-table-\(action.rawValue)")
                                }
                            } header: { Text("나누면 내용은 첫 번째 셀에 남습니다.") }
                        } label: {
                            Text("병합·분할").frame(minHeight: 48).padding(.horizontal, 8)
                        }.accessibilityIdentifier("hwp-format-cell-structure")
                    }
                    if let tableSizing, onTableResize != nil, !tableActions.isEmpty {
                        Button { sizingSelection = tableSizing() } label: {
                            Label("크기", systemImage: "arrow.up.left.and.arrow.down.right")
                                .frame(minHeight: 48).padding(.horizontal, 8)
                        }.accessibilityIdentifier("hwp-format-table-size")
                    }
                    if section == .all { separator }
                }
                if section == .all || section == .character {
                    Button {
                        showsFonts = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(editor.hasMixedFont ? AppLocalization.string("혼합") : editor.formattingRun.fontName ?? AppLocalization.string("글꼴"))
                                .lineLimit(1).truncationMode(.middle)
                            Image(systemName: "chevron.down").font(.caption)
                        }.frame(width: 126, height: 48)
                    }
                    .accessibilityLabel("글꼴 변경")
                    .accessibilityIdentifier("hwp-format-font")
                    Menu {
                        ForEach([8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 36, 48, 72], id: \.self) { size in
                            Button("\(size) pt") { editor.applyFormatting(.size(Double(size))) }
                        }
                        Button("직접 입력") {
                            sizeText = String(format: "%g", editor.formattingRun.fontSizePoints ?? 10)
                            showsSize = true
                        }
                    } label: {
                        Text(editor.hasMixedSize ? AppLocalization.string("혼합") : String(format: "%g pt", editor.formattingRun.fontSizePoints ?? 10))
                            .monospacedDigit().frame(minWidth: 64, minHeight: 48)
                    }
                    .accessibilityLabel("글자 크기")
                    .accessibilityIdentifier("hwp-format-size")
                    separator
                    formatButton("굵게", icon: "bold", active: editor.formattingRun.isBold, id: "bold") {
                        editor.applyFormatting(.bold(!editor.formattingRun.isBold))
                    }
                    formatButton("기울임", icon: "italic", active: editor.formattingRun.isItalic, id: "italic") {
                        editor.applyFormatting(.italic(!editor.formattingRun.isItalic))
                    }
                    formatButton("밑줄", icon: "underline", active: editor.formattingRun.isUnderlined, id: "underline") {
                        editor.applyFormatting(.underline(!editor.formattingRun.isUnderlined))
                    }
                    Menu {
                        ForEach(HWPFormattingColor.all, id: \.rgb) { color in
                            Button {
                                editor.applyFormatting(.color(color.rgb))
                            } label: {
                                Label(AppLocalization.string(color.name), systemImage: editor.formattingRun.textColorRGB == color.rgb ? "checkmark.circle.fill" : "circle.fill")
                                    .tint(color.color)
                            }
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "textformat")
                            Rectangle().fill(HWPFormattingColor.color(editor.formattingRun.textColorRGB ?? 0)).frame(width: 20, height: 3)
                        }.frame(width: 48, height: 48)
                    }
                    .accessibilityLabel("글자색")
                    .accessibilityIdentifier("hwp-format-color")
                    Menu {
                        Button("없음", systemImage: "nosign") { editor.applyFormatting(.highlight(nil)) }
                            .accessibilityIdentifier("hwp-highlight-none")
                        ForEach(HWPFormattingColor.highlights, id: \.rgb) { color in
                            Button {
                                editor.applyFormatting(.highlight(color.rgb))
                            } label: {
                                Label(AppLocalization.string(color.name), systemImage: editor.formattingRun.backgroundColorRGB == color.rgb ? "checkmark.circle.fill" : "circle.fill")
                                    .tint(color.color)
                            }.accessibilityIdentifier("hwp-highlight-\(color.rgb)")
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "highlighter")
                            Rectangle().fill(HWPFormattingColor.color(editor.formattingRun.backgroundColorRGB ?? 0xFFFF00))
                                .frame(width: 20, height: 3)
                        }.frame(width: 48, height: 48)
                    }
                    .accessibilityLabel("강조색")
                    .accessibilityIdentifier("hwp-format-highlight")
                    Menu {
                        characterEffect("취소선", icon: "strikethrough", active: editor.formattingRun.isStruckThrough, id: "strike") {
                            editor.applyFormatting(.strikethrough(!editor.formattingRun.isStruckThrough))
                        }
                        characterEffect("위 첨자", icon: "superscript", active: editor.formattingRun.isSuperscript, id: "superscript") {
                            editor.applyFormatting(.superscript(!editor.formattingRun.isSuperscript))
                        }
                        characterEffect("아래 첨자", icon: "subscript", active: editor.formattingRun.isSubscript, id: "subscript") {
                            editor.applyFormatting(.subscript(!editor.formattingRun.isSubscript))
                        }
                        Divider()
                        Button("글자 서식 지우기", systemImage: "eraser") { editor.applyFormatting(.clearCharacterFormatting) }
                            .accessibilityIdentifier("hwp-format-clear")
                            .accessibilityHint("바탕 10pt, 검정색 기본 글자로 변경")
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "textformat")
                            Image(systemName: "chevron.down").font(.caption)
                        }.frame(width: 48, height: 48)
                    }
                    .accessibilityLabel("글자 효과")
                    .accessibilityIdentifier("hwp-format-effects")
                }
                if section == .all || section == .paragraph {
                    if section == .all { separator }
                    formatButton("글머리표", icon: "list.bullet", active: editor.paragraphStyle.list?.kind == .bullet, id: "bullet") {
                        editor.applyList(.bullet)
                    }.disabled(!editor.canApplyList)
                    formatButton("번호 매기기", icon: "list.number", active: editor.paragraphStyle.list?.kind == .number, id: "number") {
                        editor.applyList(.number)
                    }.disabled(!editor.canApplyList)
                    separator
                    alignmentButton("왼쪽 정렬", icon: "text.alignleft", alignment: .leading, id: "left")
                    alignmentButton("가운데 정렬", icon: "text.aligncenter", alignment: .centered, id: "center")
                    alignmentButton("오른쪽 정렬", icon: "text.alignright", alignment: .trailing, id: "right")
                    alignmentButton("양쪽 정렬", icon: "text.justify", alignment: .justified, id: "justify")
                    separator
                    Button { showsParagraph = true } label: {
                        Label("문단", systemImage: "paragraph").frame(minHeight: 48).padding(.horizontal, 8)
                    }
                    .accessibilityIdentifier("hwp-format-paragraph")
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 48)
        .font(.subheadline)
        .buttonStyle(.plain)
        .background(VisionCraftUI.surface)
        .overlay(alignment: .bottom) { Divider() }
        .disabled(editor.activation == nil)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("문서 서식")
        .sheet(isPresented: $showsFonts, onDismiss: applyPendingCommand) {
            HWPFormattingFontPicker(documentFonts: documentFonts,
                selected: editor.hasMixedFont ? nil : editor.formattingRun.fontName) { name in
                    pendingCommand = .font(name)
                    showsFonts = false
                }
        }
        .sheet(isPresented: $showsParagraph, onDismiss: applyPendingCommand) {
            HWPParagraphFormattingSheet(style: editor.paragraphStyle) { command in
                pendingCommand = command
                showsParagraph = false
            }
        }
        .sheet(isPresented: $showsCell, onDismiss: applyPendingCommand) {
            if let cell = editor.cellLocation {
                HWPCellFormattingSheet(cell: cell) { format in
                    pendingCommand = .cell(format)
                    showsCell = false
                }
            }
        }
        .sheet(item: $sizingSelection, onDismiss: {
            guard let pendingSize else { editor.restoreFocus(); return }
            self.pendingSize = nil
            onTableResize?(pendingSize.0, pendingSize.1)
        }) { selection in
            HWPTableSizingSheet(selection: selection) { dimensions in
                pendingSize = (selection.id, dimensions)
                sizingSelection = nil
            }
        }
        .alert("글자 크기", isPresented: $showsSize) {
            TextField("6~144 pt", text: $sizeText).keyboardType(.decimalPad)
            Button("취소", role: .cancel) {}
            Button("적용") {
                if let size = Double(sizeText.replacingOccurrences(of: ",", with: ".")), size.isFinite {
                    editor.applyFormatting(.size(size))
                }
            }.disabled(Double(sizeText.replacingOccurrences(of: ",", with: ".")) == nil)
        }
    }

    private var separator: some View { Divider().frame(height: 24).padding(.horizontal, 3) }

    private func characterEffect(_ title: String, icon: String, active: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(AppLocalization.string(title), systemImage: active ? "checkmark" : icon)
        }
        .accessibilityValue(AppLocalization.string(active ? "켜짐" : "꺼짐"))
        .accessibilityIdentifier("hwp-format-\(id)")
    }

    private func alignmentButton(_ title: String, icon: String, alignment: HWPParagraphAlignment, id: String) -> some View {
        formatButton(title, icon: icon, active: editor.paragraphStyle.alignment == alignment, id: id) {
            editor.applyFormatting(.alignment(alignment))
        }
    }

    private func formatButton(_ title: String, icon: String, active: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).frame(width: 48, height: 48)
                .background(active ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(active ? Color.accentColor : VisionCraftUI.primaryText)
        }
        .accessibilityLabel(AppLocalization.string(title))
        .accessibilityValue(AppLocalization.string(active ? "켜짐" : "꺼짐"))
        .accessibilityIdentifier("hwp-format-\(id)")
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func applyPendingCommand() {
        editor.restoreFocus()
        guard let command = pendingCommand else { return }
        pendingCommand = nil
        editor.applyFormatting(command)
    }
}

private struct HWPFormattingFontPicker: View {
    let documentFonts: [String]
    let selected: String?
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    private var fonts: [String] {
        Array(Set(documentFonts + UIFont.familyNames)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .filter { search.isEmpty || $0.localizedStandardContains(search) }
    }
    var body: some View {
        NavigationStack {
            List(fonts, id: \.self) { font in
                Button { onSelect(font) } label: {
                    HStack {
                        Text(font).foregroundStyle(VisionCraftUI.primaryText)
                        Spacer()
                        if font == selected { Image(systemName: "checkmark") }
                    }
                }
            }
            .searchable(text: $search, prompt: "글꼴 검색")
            .navigationTitle("글꼴")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } } }
        }
    }
}

private struct HWPParagraphFormattingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var style: HWPDocumentBlockPresentation
    let onApply: (HWPFormattingCommand) -> Void
    init(style: HWPDocumentBlockPresentation, onApply: @escaping (HWPFormattingCommand) -> Void) {
        _style = State(initialValue: style); self.onApply = onApply
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("들여쓰기") {
                    setting("왼쪽 여백", value: $style.leftMarginPoints, range: 0...360)
                    setting("오른쪽 여백", value: $style.rightMarginPoints, range: 0...360)
                    setting("첫 줄 들여쓰기", value: $style.firstLineIndentPoints, range: -180...180)
                    Text("첫 줄에 음수를 지정하면 내어쓰기가 됩니다.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("간격") {
                    setting("문단 앞 간격", value: $style.spacingBeforePoints, range: 0...144)
                    setting("문단 뒤 간격", value: $style.spacingAfterPoints, range: 0...144)
                    Picker("줄 간격", selection: $style.lineSpacingPercent) {
                        if style.lineSpacingPercent == nil { Text("원본 설정").tag(Optional<Double>.none) }
                        ForEach(Array(Set([100.0, 120, 150, 160, 180, 200, 250, 300] + [style.lineSpacingPercent].compactMap { $0 })).sorted(), id: \.self) { value in
                            Text("\(Int(value))%").tag(Optional(value))
                        }
                    }
                }
            }
            .navigationTitle("문단")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("적용") {
                        onApply(.paragraph(left: style.leftMarginPoints, right: style.rightMarginPoints,
                            indent: style.firstLineIndentPoints, before: style.spacingBeforePoints,
                            after: style.spacingAfterPoints, linePercent: style.lineSpacingPercent))
                    }
                }
            }
        }
    }
    private func setting(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        Stepper(value: value, in: range, step: 1) {
            HStack {
                Text(AppLocalization.string(title))
                Spacer()
                Text(String(format: "%g pt", value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }
}

private struct HWPFormattingColor {
    let name: String
    let rgb: UInt32
    var color: Color { Self.color(rgb) }
    static let highlights: [Self] = [
        .init(name: "노랑", rgb: 0xFFFF00), .init(name: "초록", rgb: 0xB5E6A2),
        .init(name: "파랑", rgb: 0xB2E3FF), .init(name: "분홍", rgb: 0xFFC7DE),
        .init(name: "보라", rgb: 0xDCC8FF)
    ]
    static let all: [Self] = [
        .init(name: "검정", rgb: 0), .init(name: "회색", rgb: 0x666666), .init(name: "흰색", rgb: 0xFFFFFF),
        .init(name: "빨강", rgb: 0xCC0000), .init(name: "주황", rgb: 0xE07000), .init(name: "노랑", rgb: 0xE0B000),
        .init(name: "초록", rgb: 0x008040), .init(name: "파랑", rgb: 0x0066CC), .init(name: "남색", rgb: 0x203080),
        .init(name: "보라", rgb: 0x8030B0), .init(name: "분홍", rgb: 0xC03080), .init(name: "갈색", rgb: 0x804000)
    ]
    static func color(_ rgb: UInt32) -> Color {
        Color(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }
}
