import CoreText
import SwiftUI
import UIKit

@MainActor enum HWPUserFontManager {
    static let shared = HWPUserFontManagerProxy()
}
@MainActor final class HWPUserFontManagerProxy {
    func resolvedPostScriptName(for name: String) -> String? { nil }
}

@main struct InlineQAApp: App {
    var body: some Scene { WindowGroup { InlineQADocument() } }
}

struct InlineQADocument: View {
    @StateObject private var editor = HWPInlineEditingSession()
    @StateObject private var navigation = HWPDocumentNavigation()
    @State private var blocks: [HWPDocumentBlock] = []
    @State private var layouts: [HWPDocumentPageLayout] = []
    @State private var selected: String?
    @State private var draft = ""
    @State private var editing = true
    @State private var result = ""
    @State private var originalData = Data()
    @State private var originals: [HWPDocumentBlock] = []
    @State private var isHWPX = false
    @State private var undoBlocks: [[HWPDocumentBlock]] = []
    @State private var redoBlocks: [[HWPDocumentBlock]] = []
    private struct TableSnapshot { let data: Data; let blocks: [HWPDocumentBlock]; let originals: [HWPDocumentBlock]; let layouts: [HWPDocumentPageLayout] }
    @State private var tableUndo: [TableSnapshot] = []
    @State private var tableRedo: [TableSnapshot] = []
    @State private var changingTable = false
    @State private var outputSnapshot: HWPOutputSnapshot?
    @State private var editingShape: HWPShapeEditing.Target?
    @State private var selectedShape: HWPShapeEditing.Target?
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    HWPFormattingToolbar(editor: editor, documentFonts: ["바탕", "굴림"],
                        tableActions: HWPTableStructureEditing.available(blocks: blocks, selectedID: editor.activation?.block.id, layouts: layouts),
                        cellActions: HWPTableStructureEditing.availableCells(blocks: blocks, selectedID: editor.activation?.block.id, layouts: layouts),
                        onTableAction: { changeTable($0) },
                        tableSizing: { HWPTableSizing.selection(blocks: editor.previewing(blocks, layouts: layouts), selectedID: editor.activation?.block.id, layouts: layouts) },
                        onTableResize: { id, dimensions in changeTable(.resize, selectedID: id, dimensions: dimensions) })
                    HWPTableInsertionButton(enabled: editor.tableInsertionSelection(blocks: blocks, layouts: layouts) != nil,
                        selection: { editor.tableInsertionSelection(blocks: blocks, layouts: layouts, prepare: true) },
                        restoreFocus: editor.restoreFocus, onApply: insertTable)
                    HWPHyperlinkButton(
                        enabled: editor.hyperlinkSelection(blocks: blocks, layouts: layouts) != nil,
                        selection: { editor.hyperlinkSelection(blocks: blocks, layouts: layouts, prepare: true) },
                        restoreFocus: editor.restoreFocus,
                        onApply: editHyperlink)
                    HWPNoteButton(
                        enabled: !blocks.isEmpty,
                        selection: {
                            let insertion = editor.noteInsertion(blocks: blocks, layouts: layouts, prepare: true)
                            let path = insertion?.sectionPath ?? editor.activation?.block.sectionPath
                                ?? blocks.first?.sectionPath ?? ""
                            return HWPNoteEditing.selection(
                                blocks: blocks,
                                sectionPath: path,
                                insertion: insertion
                            )
                        },
                        restoreFocus: editor.restoreFocus,
                        onApply: editNote)
                    HWPShapeInsertionButton(
                        enabled: editor.shapeInsertionSelection(blocks: blocks, layouts: layouts) != nil,
                        selection: {
                            editor.shapeInsertionSelection(blocks: blocks, layouts: layouts, prepare: true)
                        },
                        restoreFocus: editor.restoreFocus,
                        onApply: insertShape)
                    HWPPageSetupButton(selection: {
                        guard let layout = layouts.first else { return nil }
                        return .init(layout: layout, layouts: layouts)
                    }, restoreFocus: editor.restoreFocus, onApply: changePage,
                        onApplyNumber: changePageNumber,
                        onApplyColumn: changeColumn,
                        headerFooterSelection: { kind in
                            guard let source = try? HWPTableStructureDocument.load(originalData), let section = layouts.first?.sectionIndex else { return nil }
                            return HWPHeaderFooterEditing.selection(kind: kind, section: section, source: source, drafts: blocks)
                        }, onApplyHeaderFooter: changeHeaderFooter,
                        canInsertBreak: editor.supportsPageBreak(layouts: layouts),
                        canRemoveBreak: editor.supportsPageBreak(layouts: layouts) && editor.paragraphStyle.pageBreakBefore,
                        onInsertBreak: { editor.insertPageBreak() },
                        onRemoveBreak: { _ = editor.editParagraph(.removePageBreak) })
                    HWPDocumentFindButton(navigation: navigation, finishEditing: prepareSearch)
                }
                .disabled(changingTable)
                if navigation.showsSearch {
                    HWPDocumentSearchBar(navigation: navigation, allowsReplacement: true,
                        finishEditing: prepareSearch, onReplace: replaceMatches)
                }
                HWPOriginalDocumentCanvas(blocks: editor.previewing(blocks, layouts: layouts), pageLayouts: layouts, navigation: navigation)
                    .environment(\.hwpInlineEditing, HWPInlineEditingContext(
                        session: editing ? editor : nil,
                        sources: Dictionary(uniqueKeysWithValues: editor.previewing(blocks, layouts: layouts).map { ($0.id, $0) }),
                        orderedBlocks: blocks, activeID: editor.activation?.block.id,
                        onSelect: { id in selected = id; draft = blocks.first { $0.id == id }?.text ?? "" },
                        onChange: { draft = $0 },
                        onCommit: commit, onCommitBlock: { block in
                            if let index = blocks.firstIndex(where: { $0.id == block.id }) {
                                let before = blocks
                                blocks[index] = block
                                blocks = HWPCellFormatting.propagating(block, from: before[index], in: blocks)
                                blocks = HWPListFormatting.renumbering(blocks)
                                if HWPFlowLayout.needsReflow(from: before[index], to: block) {
                                    blocks = HWPFlowLayout.reflowingEdit(blocks, before: before, startingAt: block.id, layouts: layouts)
                                }
                            }
                        }, onStructure: { block, operation in
                            guard let proposal = HWPParagraphEditing.apply(operation, draft: block, to: blocks) else { return nil }
                            undoBlocks.append(blocks); redoBlocks.removeAll()
                            blocks = HWPParagraphEditing.reflow(proposal, before: blocks, draft: block, operation: operation, layouts: layouts)
                            selected = proposal.focusedID
                            draft = blocks.first { $0.id == selected }?.text ?? ""
                            return HWPParagraphEditResult(blocks: blocks, focusedID: proposal.focusedID, caret: proposal.caret)
                        }))
                    .environment(\.hwpShapeObjectEditing, HWPShapeObjectEditingContext(
                        selectedID: selectedShape?.id,
                        onSelect: { ownerID, object in
                            guard let owner = blocks.first(where: { $0.id == ownerID }),
                                  let target = HWPShapeEditing.target(owner: owner, object: object) else { return }
                            editor.finish()
                            if selectedShape?.id == target.id { editingShape = target }
                            selectedShape = target
                        },
                        onDirectManipulation: applyDirectShapeManipulation
                    ))
                HWPDocumentNavigationControls(
                    navigation: navigation,
                    showsSearchButton: false,
                    finishEditing: { editor.finish() }
                )
                Text(result).accessibilityIdentifier("qa-result")
                if ProcessInfo.processInfo.arguments.contains("--page-fixture") {
                    Text(layouts.first?.pageNumberStyle.map { "\($0.position) \($0.sideCharacter) \($0.startsAt ?? 0)" } ?? "번호 없음")
                        .accessibilityIdentifier("qa-number-style")
                }
                let links = blocks.flatMap { HWPHyperlinkEditing.spans(in: $0) }
                Text("링크 \(links.count)개 " + links.map(\.target).joined(separator: "|"))
                    .accessibilityIdentifier("qa-links")
                let footnotes = blocks.filter { $0.region.kind == .footnote }
                let endnotes = blocks.filter { $0.region.kind == .endnote }
                Text("각주 \(footnotes.count)개 · 미주 \(endnotes.count)개 · "
                    + (footnotes + endnotes).map(\.text).joined(separator: "|"))
                    .accessibilityIdentifier("qa-notes")
                let shapes = blocks.flatMap(\.canvasObjects).compactMap { object -> String? in
                    guard case .shape(let shape) = object.content else { return nil }
                    switch shape.geometry {
                    case .rectangle: return "사각형"
                    case .ellipse: return "타원"
                    case .line: return "선"
                    case .polygon: return "다각형"
                    case .curve: return "연결선"
                    case .arc: return "호"
                    case .container: return "그룹"
                    case .unknown: return "기타"
                    }
                }
                Text("도형 \(shapes.count)개 " + shapes.joined(separator: "|"))
                    .accessibilityIdentifier("qa-shapes")
                if let shape = selectedShape {
                    Text(String(format: "X %.1f · Y %.1f · 너비 %.1f · 높이 %.1f · 회전 %.0f · 순서 %d · 선 %d/%.1f · 채우기 %@ · 그림자 %@",
                        shape.xPoints, shape.yPoints, shape.widthPoints, shape.heightPoints,
                        shape.rotationDegrees, shape.zOrder, shape.strokeStyle, shape.strokeWidthPoints,
                        shape.fillColorRGB == nil ? "끔" : "켬", shape.shadow == nil ? "끔" : "켬"))
                        .accessibilityIdentifier("qa-shape-layout")
                }
                Text("문단 \(blocks.count)").accessibilityIdentifier("qa-paragraph-count")
                Text("선택 \(editor.selectedRange.location):\(editor.selectedRange.length)")
                    .accessibilityIdentifier("qa-selection")
                Text("초안 " + draft.replacingOccurrences(of: "\n", with: "\\n"))
                    .accessibilityIdentifier("qa-draft")
                Text("문단 앞 \(Int(editor.paragraphStyle.spacingBeforePoints)) · 뒤 \(Int(editor.paragraphStyle.spacingAfterPoints)) · 줄 \(Int(editor.paragraphStyle.lineSpacingPercent ?? 0))")
                    .accessibilityIdentifier("qa-paragraph-style")
                if ProcessInfo.processInfo.arguments.contains("--page-fixture") {
                    Text("쪽 \(HWPOriginalCanvasPageBuilder.makePages(blocks: blocks, layouts: layouts).count)개")
                        .accessibilityIdentifier("qa-page-count")
                    Text("나눔 \(blocks.filter { $0.presentation.pageBreakBefore }.count)개")
                        .accessibilityIdentifier("qa-break-count")
                }
                if ProcessInfo.processInfo.arguments.contains("--page-fixture"), let layout = layouts.first {
                    Text(String(format: "%.1f × %.1f mm", layout.widthPoints / HWPPageSettings.pointsPerMM, layout.heightPoints / HWPPageSettings.pointsPerMM))
                        .accessibilityIdentifier("qa-page-size")
                    Text("단 \(layout.columnLayout.count)개 · 간격 \(Int((layout.columnLayout.gapPoints / HWPPageSettings.pointsPerMM).rounded()))mm · 구분선 \(layout.columnLayout.separator?.isVisible == true ? "켜짐" : "꺼짐")")
                        .accessibilityIdentifier("qa-column-style")
                }
                if ProcessInfo.processInfo.arguments.contains("--page-fixture") {
                    let headerBlocks = blocks.filter { $0.region.kind == .header }
                    let headerPages = HWPOriginalCanvasPageBuilder.makePages(blocks: blocks, layouts: layouts)
                        .filter { !$0.regionBlocks(.header).isEmpty }.count
                    Text("머리말 \(headerBlocks.map(\.text).joined(separator: "|"))")
                        .accessibilityIdentifier("qa-header-text")
                    Text("머리말 표시 \(headerPages)쪽")
                        .accessibilityIdentifier("qa-header-pages")
                }
                let cells = blocks.compactMap(\.tableLocation)
                if !cells.isEmpty || ProcessInfo.processInfo.arguments.contains("--insert-table-fixture") || ProcessInfo.processInfo.arguments.contains("--page-fixture") {
                    Text("표 \(cells.map { $0.row + $0.rowSpan }.max() ?? 0)행 \(cells.map { $0.column + $0.columnSpan }.max() ?? 0)열")
                        .accessibilityIdentifier("qa-table-size")
                    Text("셀 \(Set(cells.map { "\($0.table):\($0.row):\($0.column)" }).count)개")
                        .accessibilityIdentifier("qa-cell-count")
                }
            }
            .navigationTitle("원본 문서 편집")
            .toolbar {
                Button("실행 취소") {
                    if editor.undo() { return }
                    editor.finish()
                    if let previous = tableUndo.popLast() { tableRedo.append(tableSnapshot); restoreTable(previous) }
                    else if let previous = undoBlocks.popLast() { redoBlocks.append(blocks); blocks = previous; navigation.update(blocks: blocks, layouts: layouts) }
                }.accessibilityIdentifier("qa-undo")
                Button("다시 실행") {
                    if editor.redo() { return }
                    editor.finish()
                    if let next = tableRedo.popLast() { tableUndo.append(tableSnapshot); restoreTable(next) }
                    else if let next = redoBlocks.popLast() { undoBlocks.append(blocks); blocks = next; navigation.update(blocks: blocks, layouts: layouts) }
                }.accessibilityIdentifier("qa-redo")
                Button("편집") { editor.finish(); editing.toggle() }
                Button("PDF로 저장") { editor.finish(); outputSnapshot = .init(title: "한글 출력 테스트", blocks: blocks, layouts: layouts) }
                    .accessibilityIdentifier("qa-export-pdf")
                Button("인쇄") { editor.finish(); outputSnapshot = .init(title: "한글 출력 테스트", blocks: blocks, layouts: layouts, opensPrintDialog: true) }
                    .accessibilityIdentifier("qa-print-pdf")
                Button("저장 확인") {
                    editor.finish()
                    do {
                        let savedBlocks: [HWPDocumentBlock]
                        let savedLayouts: [HWPDocumentPageLayout]
                        if isHWPX {
                            let data = try HWPXDocumentPackage.load(from: originalData).serializedData(applying: blocks)
                            let package = try HWPXDocumentPackage.load(from: data)
                            savedBlocks = package.blocks; savedLayouts = package.pageLayouts
                        } else {
                            let data = try HWP5DocumentRewriter.rewrite(sourceData: originalData,
                                originalBlocks: originals, editedBlocks: blocks)
                            let parsed = try HWP5StructuredDocumentParser.parse(from: data)
                            savedBlocks = parsed.blocks; savedLayouts = parsed.pageLayouts
                        }
                        result = savedBlocks.count == blocks.count && zip(savedBlocks, blocks).allSatisfy { HWPDocumentFormatting.matches($0, $1) }
                            && savedLayouts.count == layouts.count && zip(savedLayouts, layouts).allSatisfy { HWPPageSettings($0).matches($1) && $0.pageNumberStyle == $1.pageNumberStyle && $0.pageNumberStart == $1.pageNumberStart } ? "저장·재열기 성공" : "불일치"
                    } catch { result = error.localizedDescription }
                }
            }
            .sheet(item: $outputSnapshot) { snapshot in HWPPDFPreview(snapshot: snapshot) }
            .sheet(item: $editingShape) { target in
                HWPShapeEditingSheet(target: target,
                    onUpdate: { editShape(.update($0), target: target) },
                    onDelete: { editShape(.delete, target: target) },
                    onMoveGroupChild: { editShape(.moveGroupChild(offset: $0), target: target) },
                    onUngroup: { editShape(.ungroup, target: target) })
            }
            .task {
                do {
                    for name in ["Batang-Regular", "Gulim-Regular", "Gungsuh-Regular", "Dotum-Regular"] {
                        if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
                        }
                    }
                    let characterFixture = ProcessInfo.processInfo.arguments.contains("--character-fixture")
                    let cellFixture = ProcessInfo.processInfo.arguments.contains("--cell-fixture")
                    let caseFindFixture = ProcessInfo.processInfo.arguments.contains("--case-find-fixture")
                    isHWPX = ProcessInfo.processInfo.arguments.contains("--insert-table-fixture") || cellFixture || characterFixture || ProcessInfo.processInfo.arguments.contains("--page-fixture") || ProcessInfo.processInfo.arguments.contains("--find-fixture") || caseFindFixture || ProcessInfo.processInfo.arguments.contains("--list-fixture")
                    if isHWPX {
                        originalData = try LegacyHWPXConverter.convert(text: characterFixture || ProcessInfo.processInfo.arguments.contains("--insert-table-fixture") ? "" : ProcessInfo.processInfo.arguments.contains("--page-fixture") ? "쪽 설정 문단\n둘째 본문" : ProcessInfo.processInfo.arguments.contains("--list-fixture") ? "목록 첫 항목" : caseFindFixture ? "Case case CASE\n대소문자 검색" : "찾기 찾기 찾기\n다음 문단 찾기")
                        if cellFixture {
                            let base = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: "\n표 뒤"))
                            let section = base.sections[0]
                            let first = try HWPFormattingXML.elements(section.xml, name: "p").first!
                            let paragraph = first.xml.replacingOccurrences(of: "</hp:run>", with: InlineQACellFixture.tableXML + "</hp:run>")
                            let xml = (section.xml as NSString).replacingCharacters(in: first.range, with: paragraph)
                            originalData = try HWPXEditingArchive(data: base.sourceData).repack(replacing: [section.path: Data(xml.utf8)])
                        }
                        if ProcessInfo.processInfo.arguments.contains("--table-structure-fixture") {
                            let base = try HWPXDocumentPackage.load(from: originalData)
                            let styled = base.blocks.map { block -> HWPDocumentBlock in
                                guard let cell = block.tableLocation else { return block }
                                var format = HWPCellFormat(cell)
                                for side in 0..<4 { format.setBorder(side, line: .init(kind: 1, widthPoints: 0.3 * 72 / 25.4, colorRGB: 0x666666)) }
                                return HWPCellFormatting.apply(format, to: block)
                            }
                            originalData = try base.serializedData(applying: styled)
                        }
                        let parsed = try HWPXDocumentPackage.load(from: originalData)
                        blocks = parsed.blocks; originals = parsed.blocks; layouts = parsed.pageLayouts
                    } else {
                        originalData = try Data(contentsOf: Bundle.main.url(forResource: "hangul_design_application", withExtension: "hwp")!)
                        let parsed = try HWP5StructuredDocumentParser.parse(from: originalData)
                        blocks = parsed.blocks; originals = parsed.blocks; layouts = parsed.pageLayouts
                    }
                } catch { result = error.localizedDescription }
            }
        }
    }

    private var tableSnapshot: TableSnapshot { TableSnapshot(data: originalData, blocks: blocks, originals: originals, layouts: layouts) }
    private func changePage(_ request: HWPPageSetupRequest) {
        guard !changingTable else { return }
        let wasEditing = editor.activation != nil, id = editor.activation?.block.id, caret = editor.selectedRange.location
        editor.finish()
        let before = tableSnapshot
        changingTable = true
        Task { @MainActor in
            defer { changingTable = false }
            do {
                let changed = try await HWPPageSetup.applying(request, source: HWPTableStructureDocument.load(originalData), drafts: blocks)
                tableUndo.append(before); tableRedo.removeAll()
                restoreTable(.init(data: changed.data, blocks: changed.blocks, originals: changed.blocks, layouts: changed.layouts))
                navigation.setZoom(nil)
                if wasEditing, let block = blocks.first(where: { $0.id == id }) {
                    editor.begin(block: block, at: .zero, onSelect: { selected = $0 }, onChange: { draft = $0 }, onCommit: commit,
                        onCommitBlock: { edited in
                            guard let index = blocks.firstIndex(where: { $0.id == edited.id }) else { return }
                            let old = blocks; blocks[index] = edited
                            blocks = HWPFlowLayout.reflowingEdit(blocks, before: old, startingAt: edited.id, layouts: layouts)
                        }, listContext: blocks, caretOffset: caret)
                }
            } catch { result = error.localizedDescription }
        }
    }
    private func changePageNumber(_ request: HWPPageNumberRequest) {
        guard !changingTable else { return }
        let wasEditing = editor.activation != nil, id = editor.activation?.block.id, caret = editor.selectedRange.location
        editor.finish()
        let before = tableSnapshot
        changingTable = true
        Task { @MainActor in
            defer { changingTable = false }
            do {
                let changed = try await HWPPageNumberEditing.applying(request, source: HWPTableStructureDocument.load(originalData), drafts: blocks)
                tableUndo.append(before); tableRedo.removeAll()
                restoreTable(.init(data: changed.data, blocks: changed.blocks, originals: changed.blocks, layouts: changed.layouts))
                if wasEditing, let block = blocks.first(where: { $0.id == id }) {
                    editor.begin(block: block, at: .zero, onSelect: { selected = $0 }, onChange: { draft = $0 }, onCommit: commit,
                        onCommitBlock: { edited in
                            guard let index = blocks.firstIndex(where: { $0.id == edited.id }) else { return }
                            let old = blocks; blocks[index] = edited
                            blocks = HWPFlowLayout.reflowingEdit(blocks, before: old, startingAt: edited.id, layouts: layouts)
                        }, listContext: blocks, caretOffset: caret)
                }
            } catch { result = error.localizedDescription }
        }
    }
    private func changeColumn(_ request: HWPColumnSetupRequest) {
        guard !changingTable else { return }
        let wasEditing = editor.activation != nil
        let id = editor.activation?.block.id
        let caret = editor.selectedRange.location
        editor.finish()
        let before = tableSnapshot
        changingTable = true
        Task { @MainActor in
            defer { changingTable = false }
            do {
                let changed = try await HWPColumnSetup.applying(
                    request,
                    source: HWPTableStructureDocument.load(originalData),
                    drafts: blocks
                )
                tableUndo.append(before)
                tableRedo.removeAll()
                restoreTable(.init(
                    data: changed.data,
                    blocks: changed.blocks,
                    originals: changed.blocks,
                    layouts: changed.layouts
                ))
                navigation.setZoom(nil)
                if wasEditing, let block = blocks.first(where: { $0.id == id }) {
                    editor.begin(
                        block: block,
                        at: .zero,
                        onSelect: { selected = $0 },
                        onChange: { draft = $0 },
                        onCommit: commit,
                        onCommitBlock: { edited in
                            guard let index = blocks.firstIndex(where: { $0.id == edited.id }) else { return }
                            let old = blocks
                            blocks[index] = edited
                            blocks = HWPFlowLayout.reflowingEdit(
                                blocks,
                                before: old,
                                startingAt: edited.id,
                                layouts: layouts
                            )
                        },
                        listContext: blocks,
                        caretOffset: caret
                    )
                }
            } catch {
                result = error.localizedDescription
            }
        }
    }
    private func changeHeaderFooter(_ request: HWPHeaderFooterRequest) {
        guard !changingTable else { return }
        let wasEditing = editor.activation != nil, id = editor.activation?.block.id, caret = editor.selectedRange.location
        editor.finish()
        let before = tableSnapshot
        changingTable = true
        Task { @MainActor in
            defer { changingTable = false }
            do {
                let changed = try await HWPHeaderFooterEditing.applying(request, source: HWPTableStructureDocument.load(originalData), drafts: blocks)
                tableUndo.append(before); tableRedo.removeAll()
                restoreTable(.init(data: changed.data, blocks: changed.blocks, originals: changed.blocks, layouts: changed.layouts))
                let focused = HWPHeaderFooterEditing.remappedSelection(id, before: before.blocks, after: blocks, request: request)
                if wasEditing, let block = blocks.first(where: { $0.id == focused }) {
                    editor.begin(block: block, at: .zero, onSelect: { selected = $0 }, onChange: { draft = $0 }, onCommit: commit,
                        onCommitBlock: { edited in
                            guard let index = blocks.firstIndex(where: { $0.id == edited.id }) else { return }
                            let old = blocks; blocks[index] = edited
                            blocks = HWPFlowLayout.reflowingEdit(blocks, before: old, startingAt: edited.id, layouts: layouts)
                        }, listContext: blocks, caretOffset: caret)
                }
            } catch { result = error.localizedDescription }
        }
    }
    private func restoreTable(_ snapshot: TableSnapshot) {
        let previousShape = selectedShape
        originalData = snapshot.data; blocks = snapshot.blocks; originals = snapshot.originals; layouts = snapshot.layouts
        if let previousShape { selectedShape = refreshedShapeTarget(previousShape) }
        editingShape = nil
        navigation.update(blocks: blocks, layouts: layouts)
    }
    private func changeTable(_ action: HWPTableStructureAction, selectedID: String? = nil, dimensions: HWPTableDimensions? = nil) {
        guard let id = selectedID ?? editor.activation?.block.id, !changingTable else { return }
        editor.finish()
        let before = tableSnapshot
        changingTable = true
        Task { @MainActor in
            defer { changingTable = false }
            do {
                let changed = try await HWPTableStructureDocument.load(originalData).editing(action, blocks: blocks, selectedID: id, dimensions: dimensions)
                tableUndo.append(before); tableRedo.removeAll()
                restoreTable(TableSnapshot(data: changed.document.data, blocks: changed.document.blocks,
                    originals: changed.document.blocks, layouts: changed.document.layouts))
                if let page = navigation.pages.firstIndex(where: { $0.bodyBlocks.contains { HWPInlineParagraphGeometry.sourceID($0.id) == changed.focusedID } }) { navigation.goToPage(page) }
                if let block = blocks.first(where: { $0.id == changed.focusedID }) {
                    editor.begin(block: block, at: .zero, onSelect: { selected = $0 }, onChange: { draft = $0 }, onCommit: commit,
                        onCommitBlock: { edited in
                            guard let index = blocks.firstIndex(where: { $0.id == edited.id }) else { return }
                            let old = blocks
                            blocks[index] = edited
                            blocks = HWPCellFormatting.propagating(edited, from: old[index], in: blocks)
                            if HWPFlowLayout.needsReflow(from: old[index], to: edited) {
                                blocks = HWPFlowLayout.reflowingEdit(blocks, before: old, startingAt: edited.id, layouts: layouts)
                            }
                        }, listContext: blocks, caretOffset: 0)
                }
            } catch { result = error.localizedDescription }
        }
    }
    private func insertTable(_ request: HWPTableInsertion.Request) {
        guard !changingTable else { return }
        editor.finish()
        let before = tableSnapshot
        changingTable = true
        Task { @MainActor in
            defer { changingTable = false }
            do {
                let changed = try await HWPTableInsertion.applying(request, source: HWPTableStructureDocument.load(originalData), drafts: blocks)
                tableUndo.append(before); tableRedo.removeAll()
                restoreTable(TableSnapshot(data: changed.document.data, blocks: changed.document.blocks,
                    originals: changed.document.blocks, layouts: changed.document.layouts))
                if let page = navigation.pages.firstIndex(where: { $0.bodyBlocks.contains { HWPInlineParagraphGeometry.sourceID($0.id) == changed.focusedID } }) {
                    navigation.goToPage(page)
                }
                if let block = blocks.first(where: { $0.id == changed.focusedID }) {
                    editor.begin(block: block, at: .zero, onSelect: { selected = $0 }, onChange: { draft = $0 }, onCommit: commit,
                        onCommitBlock: { edited in
                            guard let index = blocks.firstIndex(where: { $0.id == edited.id }) else { return }
                            let old = blocks
                            blocks[index] = edited
                            blocks = HWPCellFormatting.propagating(edited, from: old[index], in: blocks)
                            if HWPFlowLayout.needsReflow(from: old[index], to: edited) {
                                blocks = HWPFlowLayout.reflowingEdit(blocks, before: old, startingAt: edited.id, layouts: layouts)
                            }
                        }, listContext: blocks, caretOffset: 0)
                }
            } catch { result = error.localizedDescription }
        }
    }
    private func editHyperlink(_ action: HWPHyperlinkEditing.Action,
                               selection: HWPHyperlinkEditing.Selection) {
        result = "링크 콜백 · 변경 중 \(changingTable ? "예" : "아니오")"
        guard !changingTable else { return }
        editor.finish()
        let before = tableSnapshot
        changingTable = true
        Task { @MainActor in
            defer { changingTable = false }
            do {
                let changed = try await HWPHyperlinkEditing.applying(
                    action,
                    selection: selection,
                    source: HWPTableStructureDocument.load(originalData),
                    drafts: blocks
                )
                tableUndo.append(before)
                tableRedo.removeAll()
                restoreTable(.init(
                    data: changed.document.data,
                    blocks: changed.document.blocks,
                    originals: changed.document.blocks,
                    layouts: changed.document.layouts
                ))
                result = "링크 적용 성공"
            } catch {
                result = error.localizedDescription
            }
        }
    }
    private func editNote(_ action: HWPNoteEditing.Action) {
        guard !changingTable else { return }
        result = "주석 적용 시작"
        let selectedID = editor.activation?.block.id
        editor.finish()
        let before = tableSnapshot
        changingTable = true
        Task { @MainActor in
            defer { changingTable = false }
            do {
                let changed = try await HWPNoteEditing.applying(
                    action,
                    source: HWPTableStructureDocument.load(originalData),
                    drafts: blocks,
                    selectedID: selectedID
                )
                tableUndo.append(before)
                tableRedo.removeAll()
                restoreTable(.init(
                    data: changed.document.data,
                    blocks: changed.document.blocks,
                    originals: changed.document.blocks,
                    layouts: changed.document.layouts
                ))
                result = "주석 적용 성공"
            } catch {
                result = error.localizedDescription
            }
        }
    }
    private func insertShape(_ request: HWPShapeEditing.Request) {
        guard !changingTable else { return }
        editor.finish()
        let before = tableSnapshot
        changingTable = true
        Task { @MainActor in
            defer { changingTable = false }
            do {
                let changed = try await HWPShapeEditing.inserting(
                    request,
                    source: HWPTableStructureDocument.load(originalData),
                    drafts: blocks
                )
                tableUndo.append(before)
                tableRedo.removeAll()
                restoreTable(.init(
                    data: changed.document.data,
                    blocks: changed.document.blocks,
                    originals: changed.document.blocks,
                    layouts: changed.document.layouts
                ))
                result = "도형 삽입 성공"
            } catch {
                result = error.localizedDescription
            }
        }
    }
    private func editShape(_ action: HWPShapeEditing.Action,
                           target: HWPShapeEditing.Target) {
        guard !changingTable else { return }
        editor.finish()
        let before = tableSnapshot
        changingTable = true
        Task { @MainActor in
            defer { changingTable = false }
            do {
                let changed = try await HWPShapeEditing.applying(
                    action,
                    target: target,
                    source: HWPTableStructureDocument.load(originalData),
                    drafts: blocks
                )
                tableUndo.append(before)
                tableRedo.removeAll()
                restoreTable(.init(
                    data: changed.document.data,
                    blocks: changed.document.blocks,
                    originals: changed.document.blocks,
                    layouts: changed.document.layouts
                ))
                editingShape = nil
                selectedShape = refreshedShapeTarget(target)
                result = "도형 편집 성공"
            } catch {
                result = error.localizedDescription
            }
        }
    }
    private func applyDirectShapeManipulation(_ ownerID: String,
                                              _ object: HWPDocumentCanvasObject,
                                              _ operation: HWPShapeEditing.DirectManipulation) {
        guard !changingTable,
              let owner = blocks.first(where: { $0.id == ownerID }),
              let target = HWPShapeEditing.target(owner: owner, object: object),
              let layout = HWPShapeEditing.directLayout(operation, target: target) else { return }
        editShape(.update(layout), target: target)
    }
    private func refreshedShapeTarget(_ previous: HWPShapeEditing.Target)
        -> HWPShapeEditing.Target? {
        guard let owner = blocks.first(where: { $0.id == previous.ownerID }),
              let object = owner.canvasObjects.first(where: { $0.id == previous.objectID }) else {
            return nil
        }
        return HWPShapeEditing.target(owner: owner, object: object,
            groupChildIndex: previous.groupChildIndex)
    }
    private func prepareSearch() {
        editor.finish()
        navigation.update(blocks: blocks, layouts: layouts)
    }
    private func replaceMatches(_ all: Bool) {
        let selected = navigation.selectedResult?.match
        editor.finish()
        do {
            let proposal = try HWPFindReplace.propose(blocks: blocks, query: navigation.query,
                matchCase: navigation.matchCase, replacement: navigation.replacement, selected: all ? nil : selected)
            if proposal.replacementCount > 0 {
                let before = blocks
                undoBlocks.append(before); redoBlocks = []
                blocks = proposal.blocks
                blocks = HWPFlowLayout.reflowingEdits(blocks, before: before, changedIDs: proposal.changedIDs, layouts: layouts)
            }
            navigation.update(blocks: blocks, layouts: layouts)
            if !all, let selected {
                navigation.selectAfterReplacement(of: selected, insertedLength: navigation.replacement.utf16.count)
            }
            navigation.replacementMessage = AppLocalization.format("%lld개를 바꿨습니다.", proposal.replacementCount)
        } catch { navigation.replacementMessage = error.localizedDescription }
    }
    private func commit() {
        if let index = blocks.firstIndex(where: { $0.id == selected }) {
            blocks[index] = HWPTextRunEditing.replacingText(in: blocks[index], with: draft)
        }
    }
}
