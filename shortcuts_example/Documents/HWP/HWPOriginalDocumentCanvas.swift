import RivoDocumentEngine
import SwiftUI
import UIKit

struct HWPOriginalDocumentCanvas: View {
    let blocks: [HWPDocumentBlock]
    let pageLayouts: [HWPDocumentPageLayout]
    @ObservedObject var navigation: HWPDocumentNavigation
    @Environment(\.hwpInlineEditing) private var editing

    var body: some View {
        Group {
            if navigation.pages.isEmpty {
                Color.clear
            } else {
                HWPDocumentZoomView(contentSize: navigation.viewport.contentSize,
                    scrollRequest: navigation.scrollRequest, zoomRequest: navigation.zoomRequest,
                    onViewport: navigation.didScroll, onZoom: navigation.didZoom) { visible, scale in
                    let size = navigation.viewport.contentSize
                    let selectionID = navigation.searchSelectionID
                    ZStack(alignment: .topLeading) {
                        ForEach(visiblePageIndices(in: visible), id: \.self) { index in
                            let page = navigation.pages[index]
                            let rect = navigation.viewport.pageRects[index]
                            HWPOriginalCanvasPageView(page: page)
                                .environment(\.hwpDocumentSearch, HWPDocumentSearchContext(
                                    result: navigation.selectedResult, pageIndex: index))
                                .environment(\.hwpPageAccessibility, pageAccessibility(index))
                                .offset(x: rect.minX, y: rect.minY)
                        }
                    }
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .coordinateSpace(name: "hwp-document-paper")
                    .onPreferenceChange(HWPDocumentSearchRectKey.self) { rect in
                        guard let rect else { return }
                        Task { @MainActor in
                            navigation.resolveSearchRect(rect, selectionID: selectionID)
                        }
                    }
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
                }
            }
        }
        .background(Color(uiColor: .systemGray5))
        .onChange(of: blocks, initial: true) { _, _ in
            navigation.update(blocks: blocks, layouts: pageLayouts)
        }
        .onChange(of: pageLayouts) { _, _ in
            navigation.update(blocks: blocks, layouts: pageLayouts)
        }
    }

    private func pageAccessibility(_ index: Int) -> HWPPageAccessibilityContext {
        let navigation = navigation
        let count = navigation.pages.count
        func go(_ target: Int) -> @MainActor @Sendable () -> Void {
            {
                editing.session?.finish()
                navigation.goToPage(target)
                UIAccessibility.post(notification: .announcement, argument: AppLocalization.format(
                    "%lld / %lld쪽", target + 1, count))
            }
        }
        return HWPPageAccessibilityContext(previous: index > 0 ? go(index - 1) : nil,
            next: index < count - 1 ? go(index + 1) : nil)
    }

    private func visiblePageIndices(in rect: CGRect) -> [Int] {
        navigation.pages.indices.filter { index in
            navigation.viewport.pageRects[index].intersects(rect)
                // Keep marked Korean text and selection alive even if the user
                // pans the paragraph outside the buffered viewport.
                || (editing.activeID.map { id in
                    navigation.pages[index].bodyBlocks.contains { HWPInlineParagraphGeometry.sourceID($0.id) == id }
                } ?? false)
        }
    }
}





/// Whether a tap on an object can select it in this document (the engine's editing
/// targets accept it); objects that cannot are read without button, hint or actions.
nonisolated struct HWPCanvasObjectSelection: Sendable {
    var canSelect: @MainActor @Sendable (_ ownerID: String, _ object: HWPDocumentCanvasObject,
        _ hasText: Bool) -> Bool = { _, _, _ in false }

    /// The objects the document view's editing contexts can select: the ones the engine
    /// gives an editing target for (body owners; equations outside tables).
    static func editingTargets(in blocks: [HWPDocumentBlock]) -> Self {
        let owners = Dictionary(blocks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return Self { ownerID, object, hasText in
            guard let owner = owners[ownerID] else { return false }
            if hasText { return HWPTextBoxEditing.target(owner: owner, object: object, blocks: blocks) != nil }
            switch object.content {
            case .image: return HWPImageEditing.target(owner: owner, object: object) != nil
            case .shape, .group: return HWPShapeEditing.target(owner: owner, object: object) != nil
            case .equation: return HWPEquationEditing.target(owner: owner, object: object) != nil
            default: return false
            }
        }
    }
}

/// A page's VoiceOver `이전 쪽`/`다음 쪽` (Android's page node actions), on the page
/// and everything read on it.
nonisolated struct HWPPageAccessibilityContext: Sendable {
    var previous: (@MainActor @Sendable () -> Void)?
    var next: (@MainActor @Sendable () -> Void)?
}

private struct HWPCanvasObjectSelectionKey: EnvironmentKey {
    static let defaultValue = HWPCanvasObjectSelection()
}

private struct HWPPageAccessibilityKey: EnvironmentKey {
    static let defaultValue = HWPPageAccessibilityContext()
}

extension EnvironmentValues {
    var hwpCanvasObjectSelection: HWPCanvasObjectSelection {
        get { self[HWPCanvasObjectSelectionKey.self] }
        set { self[HWPCanvasObjectSelectionKey.self] = newValue }
    }

    var hwpPageAccessibility: HWPPageAccessibilityContext {
        get { self[HWPPageAccessibilityKey.self] }
        set { self[HWPPageAccessibilityKey.self] = newValue }
    }
}

/// Adds the page's `이전 쪽`/`다음 쪽` VoiceOver actions to an element read on it.
struct HWPPageAccessibilityActions: ViewModifier {
    @Environment(\.hwpPageAccessibility) private var page

    func body(content: Content) -> some View {
        // SwiftUI hands VoiceOver these in reverse: 다음 쪽 is written first.
        content.accessibilityActions {
            if let next = page.next { Button("다음 쪽") { next() } }
            if let previous = page.previous { Button("이전 쪽") { previous() } }
        }
    }
}

extension View {
    func hwpPageAccessibilityActions() -> some View { modifier(HWPPageAccessibilityActions()) }
}

struct HWPOriginalCanvasPageView: View {
    @Environment(\.hwpShapeObjectEditing) private var shapeEditing
    @Environment(\.hwpImageObjectEditing) private var imageEditing
    let page: HWPOriginalCanvasPage
    var showsPaperShadow = true
    @Environment(\.hwpInlineEditing) private var inlineEditing

    private var layout: HWPDocumentPageLayout { page.layout }
    /// HWP PAGE_DEF stores the header/footer bands separately from the
    /// outside top/bottom margins. Cached body line coordinates begin after
    /// both the outside margin and its adjacent header/footer band.
    private var bodyTopPoints: Double {
        layout.topMarginPoints + layout.headerMarginPoints
    }
    private var bodyBottomPoints: Double {
        layout.heightPoints
            - layout.bottomMarginPoints
            - layout.footerMarginPoints
    }
    private var bodyHeightPoints: Double {
        max(1, bodyBottomPoints - bodyTopPoints)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            pageBackground
                // Blank paper (no paragraph or object above it) lets the picked object go
                // and ends editing on the page (Android `tapPage`).
                .contentShape(Rectangle())
                .onTapGesture {
                    if imageEditing.selectedID != nil { imageEditing.onDeselect() }
                    if shapeEditing.selectedID != nil { shapeEditing.onDeselect() }
                    if inlineEditing.session?.activation != nil { inlineEditing.session?.finish() }
                }
                // The page itself, read before its text: touching paper between paragraphs reads the page.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(AppLocalization.format("한글 원본 문서 · %lld쪽", page.pageNumber))
                .accessibilityIdentifier("hwp-page-\(page.id)")
                .accessibilitySortPriority(1)
                .hwpPageAccessibilityActions()
                .zIndex(-30_000)

            if let pageStyle = layout.pageStyle,
               !layout.hidesPageBorder,
               !layout.pageBorderFirstPageOnly || page.sectionPageIndex == 0 {
                HWPPageBorderOverlay(style: pageStyle)
            }

            if !layout.hidesBackground {
                regionLayer(.background, baseY: 0)
                    .zIndex(-20_000)
            }

            columnSeparators
                .zIndex(-10_000)

            objectLayer(behindText: true)
            bodyLayer
            objectLayer(behindText: false)

            if !layout.hidesHeader {
                regionLayer(.header, baseY: layout.topMarginPoints)
                    .zIndex(20_000)
            }
            if !page.noteBlocks.isEmpty {
                noteLayer
                    .zIndex(20_000)
            }
            if !layout.hidesFooter {
                regionLayer(
                    .footer,
                    baseY: bodyBottomPoints
                )
                .zIndex(20_000)
            }
            if let number = layout.pageNumberStyle {
                pageNumberView(number)
                    .zIndex(20_001)
            }
        }
        .frame(
            width: layout.widthPoints,
            height: layout.heightPoints,
            alignment: .topLeading
        )
        .clipped()
        .background(.white)
        .shadow(color: showsPaperShadow ? .black.opacity(0.16) : .clear, radius: 8, y: 3)
        // The page's name is read by its paper node (pageBackground), first on the page.
        .accessibilityElement(children: .contain)
    }

    private func pageNumberView(_ style: HWPDocumentPageNumberStyle) -> some View {
        let atTop = style.position.hasPrefix("TOP")
        let alignment: Alignment = style.position.hasSuffix("LEFT") ? .leading
            : style.position.hasSuffix("RIGHT") ? .trailing : .center
        return Text(page.pageNumberText ?? "")
            .accessibilityIdentifier("hwp-page-number-\(page.id)")
            .font(.system(size: 10))
            .foregroundStyle(.black)
            .frame(width: max(1, layout.widthPoints - layout.leftMarginPoints - layout.rightMarginPoints),
                   height: 14, alignment: alignment)
            .offset(x: layout.leftMarginPoints,
                y: atTop ? max(0, layout.topMarginPoints - 14)
                    : layout.heightPoints - layout.bottomMarginPoints - 14)
    }

    @ViewBuilder
    private var pageBackground: some View {
        let style = layout.pageStyle
        ZStack {
            Color.white
            if !layout.hidesPageBackground,
               !layout.pageBackgroundFirstPageOnly || page.sectionPageIndex == 0 {
                style?.backgroundColorRGB.map(hwpColor) ?? .clear
            }
            if !layout.hidesPageBackground,
               !layout.pageBackgroundFirstPageOnly || page.sectionPageIndex == 0,
               let image = style?.backgroundImage,
               let uiImage = UIImage(data: image.data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: layout.widthPoints, height: layout.heightPoints)
        .clipped()
    }

    @ViewBuilder
    private var columnSeparators: some View {
        if let separator = layout.columnLayout.separator,
           layout.columnLayout.columns.count > 1 {
            ForEach(
                Array(layout.columnLayout.columns.dropLast().enumerated()),
                id: \.offset
            ) { _, column in
                Rectangle()
                    .fill(hwpColor(separator.colorRGB))
                    .frame(
                        width: max(0.5, separator.widthPoints),
                        height: max(
                            1,
                            bodyHeightPoints
                        )
                    )
                    .offset(
                        x: layout.leftMarginPoints
                            + column.xPoints
                            + column.widthPoints
                            + layout.columnLayout.gapPoints / 2,
                        y: bodyTopPoints
                    )
            }
        }
    }

    private var bodyLayer: some View {
        let root = page.bodyBlocks.filter { $0.layoutContainerID == nil }
        let groupedTables = Dictionary(grouping: root.compactMap { block in
            block.tableLocation.map { ($0.table, block) }
        }, by: { $0.0 })
        let tables = groupedTables.mapValues { $0.map(\.1) }
        let fallbackOffsets = fallbackVerticalOffsets(for: root)
        return ZStack(alignment: .topLeading) {
            ForEach(root) { block in
                if block.tableLocation == nil {
                    positionedBlock(
                        block,
                        fallbackY: fallbackOffsets[block.id] ?? 0
                    )
                        // Large auto-growing table cells can overlap the
                        // preceding anchor/title area. Paragraph glyphs are
                        // part of the foreground text layer in HWP.
                        .zIndex(10_000)
                }
            }
            ForEach(tables.keys.sorted(), id: \.self) { tableIndex in
                let tableBlocks = tables[tableIndex] ?? []
                let origin = tableOrigin(
                    tableIndex: tableIndex,
                    tables: tables
                )
                let pageWidth = max(
                    1,
                    layout.widthPoints
                        - layout.rightMarginPoints
                        - max(origin.x, 0)
                )
                let declaredWidth = tableBlocks.first?.tableLocation?
                    .tablePlacement?.widthPoints ?? pageWidth
                let maximumWidth = min(pageWidth, max(declaredWidth, 1))
                let tracks = HWPTableTrackLayoutSolver.make(
                    blocks: tableBlocks,
                    maximumWidth: maximumWidth
                )
                HWPPositionedTableView(
                    blocks: tableBlocks,
                    maximumWidth: maximumWidth,
                    sectionBlocks: page.sectionBlocks
                )
                    .frame(
                        width: tracks.size.width,
                        height: tracks.size.height,
                        alignment: .topLeading
                    )
                    .offset(x: origin.x, y: origin.y)
                    .zIndex(
                        Double(tableBlocks.first?.tableLocation?.tablePlacement?.zOrder ?? 0)
                    )
            }
        }
        // Keep HWP page coordinates anchored to the paper's top-left. Without
        // an explicit coordinate-space size, SwiftUI may recenter this layer
        // when an auto-growing table becomes taller than its declared frame.
        .frame(
            width: layout.widthPoints,
            height: layout.heightPoints,
            alignment: .topLeading
        )
    }

    /// Body-relative Y for root paragraphs that carry no cached line
    /// geometry. They flow directly below the previous positioned content so
    /// a paragraph rewritten without PARA_LINE_SEG keeps its place instead of
    /// being stacked from the top of the page.
    private func fallbackVerticalOffsets(
        for root: [HWPDocumentBlock]
    ) -> [String: Double] {
        var result: [String: Double] = [:]
        var runningY = 0.0
        for block in root {
            if let location = block.tableLocation {
                if let anchor = location.tableAnchor {
                    runningY = max(
                        runningY,
                        anchor.verticalPositionPoints + max(
                            location.tablePlacement?.heightPoints ?? 0,
                            anchor.lineHeightPoints
                        )
                    )
                }
                continue
            }
            if let last = block.lineLayouts.last {
                runningY = max(
                    runningY,
                    last.verticalPositionPoints + max(last.lineHeightPoints, 12)
                )
                continue
            }
            guard !block.text.isEmpty else { continue }
            let fontSize = block.presentation.textRuns
                .compactMap(\.fontSizePoints)
                .max() ?? 12
            let lineCount = max(
                1,
                block.text.split(
                    separator: "\n",
                    omittingEmptySubsequences: false
                ).count
            )
            let top = runningY + max(0, block.presentation.spacingBeforePoints)
            result[block.id] = top
            runningY = top
                + Double(lineCount) * fontSize * 1.6
                + max(0, block.presentation.spacingAfterPoints)
        }
        return result
    }

    @ViewBuilder
    private func positionedBlock(
        _ block: HWPDocumentBlock,
        fallbackY: Double
    ) -> some View {
        if !block.lineLayouts.isEmpty {
            HWPParagraphBorderView(block: block)
                .offset(x: layout.leftMarginPoints, y: bodyTopPoints)
            ForEach(block.lineLayouts) { line in
                if !line.isEmpty, !line.text.isEmpty {
                    HWPMetricLineText(
                        text: line.text,
                        runs: line.textRuns,
                        fallbackSize: max(line.textHeightPoints, 10),
                        alignment: block.presentation.alignment,
                        baselinePoints: line.baselinePoints,
                        baselineAlignment: line.baselineAlignment,
                        isLastLine: line.endsParagraph ?? (line.id == block.lineLayouts.last?.id),
                        listMarker: line.listMarker,
                        showsListMarker: line.showsListMarker,
                        searchBlock: block, searchLine: line
                    )
                    .frame(
                        width: max(line.widthPoints - line.textInsetPoints, 1),
                        height: max(
                            line.lineHeightPoints,
                            line.textHeightPoints,
                            line.textRuns.compactMap(\.fontSizePoints).max() ?? 0,
                            12
                        ),
                        alignment: frameAlignment(block.presentation.alignment)
                    )
                    .opacity(inlineEditing.hidesText(block) ? 0 : 1)
                    .accessibilityHidden(inlineEditing.source(for: block) != nil)
                    .hwpPageAccessibilityActions()
                    .allowsHitTesting(false)
                    .offset(
                        x: layout.leftMarginPoints
                            + line.columnStartPoints
                            + line.textInsetPoints,
                        y: bodyTopPoints + line.verticalPositionPoints
                    )
                }
            }
        } else if !block.text.isEmpty {
            HWPStyledRunsText(
                text: block.text,
                runs: block.presentation.textRuns,
                fallbackSize: 12
            )
            .frame(
                width: max(
                    1,
                    layout.widthPoints
                        - layout.leftMarginPoints
                        - layout.rightMarginPoints
                ),
                alignment: frameAlignment(block.presentation.alignment)
            )
            .opacity(inlineEditing.hidesText(block) ? 0 : 1)
            .accessibilityHidden(inlineEditing.source(for: block) != nil)
            .hwpPageAccessibilityActions()
            .allowsHitTesting(false)
            .offset(
                x: layout.leftMarginPoints + block.presentation.leftMarginPoints,
                y: bodyTopPoints + fallbackY
            )
        }
        HWPInlineParagraphTarget(block: block,
            rect: HWPInlineParagraphGeometry.rect(block: block,
                width: layout.widthPoints - layout.leftMarginPoints - layout.rightMarginPoints,
                fallbackY: fallbackY)
                .offsetBy(dx: layout.leftMarginPoints, dy: bodyTopPoints))
    }

    private func objectLayer(behindText: Bool) -> some View {
        // Objects anchored in a table cell use cell-local coordinates and are
        // rendered by HWPPositionedTableCellContent. Rendering them again in
        // page coordinates creates clipped duplicates at the paper edge.
        let owners = page.bodyBlocks.filter { $0.tableLocation == nil }
        return ZStack(alignment: .topLeading) {
            ForEach(owners.flatMap { owner in
                owner.canvasObjects.filter {
                    // Selection mode must also reach shapes intentionally placed behind text.
                    ($0.placement.wrap == .behindText && !shapeEditing.isSelectingGroup) == behindText
                }.map { (owner, $0) }
            }, id: \.1.id) { owner, object in
                let origin = objectOrigin(object, owner: owner)
                let objectTextBlocks = object.textContainerID.map { containerID in
                    page.sectionBlocks.filter {
                        $0.layoutContainerID == containerID
                    }
                } ?? []
                HWPDocumentCanvasObjectView(
                    object: object,
                    textBlocks: objectTextBlocks,
                    ownerID: owner.id
                )
                .frame(
                    width: object.placement.widthPoints,
                    height: object.placement.heightPoints,
                    alignment: .topLeading
                )
                .rotationEffect(.degrees(object.placement.rotationDegrees))
                .offset(x: origin.x, y: origin.y)
                .zIndex(objectZIndex(object))
            }
        }
    }

    private func objectZIndex(_ object: HWPDocumentCanvasObject) -> Double {
        let base = Double(object.placement.zOrder)
        switch object.placement.wrap {
        case .behindText: return -1_000 + base
        case .inFrontOfText: return 1_000 + base
        default: return base
        }
    }

    private func objectOrigin(
        _ object: HWPDocumentCanvasObject,
        owner: HWPDocumentBlock
    ) -> CGPoint {
        let line = object.placement.sourceCharacterPosition.flatMap { position in
            owner.lineLayouts.last { $0.startCharacter <= position }
        } ?? owner.lineLayouts.first
        var origin = resolvedOrigin(
            placement: object.placement,
            anchorColumnStart: line?.columnStartPoints ?? 0,
            anchorVerticalPosition: line?.verticalPositionPoints ?? 0,
            anchorWidth: line?.widthPoints,
            anchorHeight: line?.lineHeightPoints,
            paragraphAlignment: owner.presentation.alignment
        )
        if object.placement.isInline {
            origin.x += object.placement.inlineLeadingPoints + (line?.textInsetPoints ?? 0)
            origin.y += object.placement.inlineBaselineOffset(in: line)
        }
        return origin
    }

    @ViewBuilder
    private func regionLayer(
        _ kind: HWPDocumentRegionKind,
        baseY: Double
    ) -> some View {
        let blocks = page.regionBlocks(kind)
        ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
            let line = block.lineLayouts.first
            ZStack(alignment: .topLeading) {
                if !block.text.isEmpty, !block.lineLayouts.isEmpty, kind == .header || kind == .footer {
                    ForEach(block.lineLayouts) { line in
                        HWPMetricLineText(text: line.text, runs: line.textRuns,
                            fallbackSize: max(line.textHeightPoints, 8), alignment: block.presentation.alignment,
                            baselinePoints: line.baselinePoints, baselineAlignment: line.baselineAlignment,
                            isLastLine: line.endsParagraph ?? (line.id == block.lineLayouts.last?.id))
                            .frame(width: max(1, line.widthPoints - line.textInsetPoints), height: max(1, line.lineHeightPoints))
                            .offset(x: layout.leftMarginPoints + line.columnStartPoints + line.textInsetPoints,
                                    y: baseY + line.verticalPositionPoints)
                    }
                    .accessibilityElement(children: .ignore).accessibilityLabel(block.text)
                    .accessibilityIdentifier("hwp-region-\(kind.rawValue)-\(page.id)-\(index)")
                    .hwpPageAccessibilityActions()
                } else if !block.text.isEmpty {
                    HWPStyledRunsText(
                        text: block.text,
                        runs: block.presentation.textRuns,
                        fallbackSize: max(line?.textHeightPoints ?? 10, 8)
                    )
                    .frame(
                        width: max(
                            line?.widthPoints ?? 0,
                            layout.widthPoints
                                - layout.leftMarginPoints
                                - layout.rightMarginPoints
                        ),
                        alignment: frameAlignment(block.presentation.alignment)
                    )
                    .offset(
                        x: layout.leftMarginPoints + (line?.columnStartPoints ?? 0),
                        y: baseY + (line?.verticalPositionPoints ?? Double(index) * 16)
                    )
                }
                ForEach(block.canvasObjects) { object in
                    let origin = regionObjectOrigin(
                        object,
                        owner: block,
                        baseY: baseY
                    )
                    let objectTextBlocks = object.textContainerID.map { containerID in
                        page.sectionBlocks.filter {
                            $0.layoutContainerID == containerID
                        }
                    } ?? []
                    HWPDocumentCanvasObjectView(
                        object: object,
                        textBlocks: objectTextBlocks,
                        ownerID: block.id
                    )
                    .frame(
                        width: object.placement.widthPoints,
                        height: object.placement.heightPoints,
                        alignment: .topLeading
                    )
                    .rotationEffect(.degrees(object.placement.rotationDegrees))
                    .offset(x: origin.x, y: origin.y)
                    .zIndex(objectZIndex(object))
                }
            }
        }
    }

    private func regionObjectOrigin(
        _ object: HWPDocumentCanvasObject,
        owner: HWPDocumentBlock,
        baseY: Double
    ) -> CGPoint {
        var origin = objectOrigin(object, owner: owner)
        if object.placement.isInline
            || object.placement.verticalReference == .paragraph {
            origin.y += baseY - bodyTopPoints
        }
        return origin
    }

    @ViewBuilder
    private var noteLayer: some View {
        let notes = page.noteBlocks
        if !notes.isEmpty {
            let height = min(180, max(50, Double(notes.count) * 24 + 20))
            VStack(alignment: .leading, spacing: 4) {
                Rectangle()
                    .fill(.black.opacity(0.65))
                    .frame(width: 120, height: 0.7)
                ForEach(notes) { block in
                    HWPStyledRunsText(
                        text: block.text,
                        runs: block.presentation.textRuns,
                        fallbackSize: 9
                    )
                }
            }
            .frame(
                width: layout.widthPoints - layout.leftMarginPoints - layout.rightMarginPoints,
                height: height,
                alignment: .topLeading
            )
            .offset(
                x: layout.leftMarginPoints,
                y: bodyBottomPoints - height
            )
        }
    }

    private func tableOrigin(
        tableIndex: Int,
        tables: [Int: [HWPDocumentBlock]],
        visited: Set<Int> = []
    ) -> CGPoint {
        guard !visited.contains(tableIndex),
              let blocks = tables[tableIndex],
              let location = blocks.first?.tableLocation else {
            return CGPoint(x: layout.leftMarginPoints, y: bodyTopPoints)
        }
        if let parent = location.parent,
           let parentBlocks = tables[parent.table],
           let parentLocation = parentBlocks.first?.tableLocation {
            var nextVisited = visited
            nextVisited.insert(tableIndex)
            let parentOrigin = tableOrigin(
                tableIndex: parent.table,
                tables: tables,
                visited: nextVisited
            )
            let parentAvailableWidth = min(
                max(
                    1,
                    layout.widthPoints
                        - layout.rightMarginPoints
                        - max(parentOrigin.x, 0)
                ),
                max(parentLocation.tablePlacement?.widthPoints ?? 1, 1)
            )
            let parentTracks = HWPTableTrackLayoutSolver.make(
                blocks: parentBlocks,
                maximumWidth: parentAvailableWidth
            )
            let cellX = parentTracks.columnWidths
                .prefix(parent.column)
                .reduce(0, +)
            let cellY = parentTracks.rowHeights
                .prefix(parent.row)
                .reduce(0, +)
            // The nested table sits inside the parent cell's padding. Without
            // it the child lands exactly on the parent's top-left corner and
            // paints over the parent's top and left border lines.
            let parentCell = parentBlocks.first {
                $0.tableLocation?.row == parent.row
                    && $0.tableLocation?.column == parent.column
            }?.tableLocation
            let anchor = location.tableAnchor
            let placement = location.tablePlacement
            return CGPoint(
                x: parentOrigin.x
                    + cellX
                    + (parentCell?.cellMarginLeftPoints ?? 0)
                    + max(anchor?.columnStartPoints ?? 0, 0)
                    + (placement?.xPoints ?? 0),
                y: parentOrigin.y
                    + cellY
                    + (parentCell?.cellMarginTopPoints ?? 0)
                    + max(anchor?.verticalPositionPoints ?? 0, 0)
                    + (placement?.yPoints ?? 0)
            )
        }
        return rootTableOrigin(blocks)
    }

    private func rootTableOrigin(_ blocks: [HWPDocumentBlock]) -> CGPoint {
        guard let placement = blocks.first?.tableLocation?.tablePlacement else {
            return CGPoint(x: layout.leftMarginPoints, y: bodyTopPoints)
        }
        if let anchor = blocks.first?.tableLocation?.tableAnchor {
            return resolvedOrigin(
                placement: placement,
                anchorColumnStart: anchor.columnStartPoints,
                anchorVerticalPosition: anchor.verticalPositionPoints,
                anchorWidth: anchor.widthPoints,
                anchorHeight: anchor.lineHeightPoints,
                paragraphAlignment: anchor.paragraphAlignment
            )
        }
        return resolvedOrigin(
            placement: placement,
            anchorLine: blocks.first?.lineLayouts.first
        )
    }

    private func resolvedOrigin(
        placement: HWPDocumentObjectPlacement,
        anchorLine: HWPDocumentLineLayout?
    ) -> CGPoint {
        resolvedOrigin(
            placement: placement,
            anchorColumnStart: anchorLine?.columnStartPoints ?? 0,
            anchorVerticalPosition: anchorLine?.verticalPositionPoints ?? 0,
            anchorWidth: anchorLine?.widthPoints,
            anchorHeight: anchorLine?.lineHeightPoints
        )
    }

    private func resolvedOrigin(
        placement: HWPDocumentObjectPlacement,
        anchorColumnStart: Double,
        anchorVerticalPosition: Double,
        anchorWidth: Double?,
        anchorHeight: Double?,
        paragraphAlignment: HWPParagraphAlignment = .leading
    ) -> CGPoint {
        let content = CGRect(
            x: layout.leftMarginPoints,
            y: bodyTopPoints,
            width: max(1, layout.widthPoints - layout.leftMarginPoints - layout.rightMarginPoints),
            height: bodyHeightPoints
        )
        let paper = CGRect(x: 0, y: 0, width: layout.widthPoints, height: layout.heightPoints)
        let column = columnRect(
            forColumnStart: anchorColumnStart,
            fallback: content
        )
        // The owner paragraph for a floating table is commonly an empty
        // control-only line whose cached width is zero. In HWP that means
        // "use the paragraph/column area", not a one-point alignment box.
        // Treating it as one point makes a centered full-width table start
        // half a page offscreen.
        let paragraphWidth = (anchorWidth ?? 0) > 0
            ? anchorWidth!
            : column.width
        let paragraph = CGRect(
            x: layout.leftMarginPoints + anchorColumnStart,
            y: bodyTopPoints + anchorVerticalPosition,
            width: max(paragraphWidth, 1),
            height: max(anchorHeight ?? 14, 1)
        )
        if placement.isInline {
            let offset = placement.inlineOffset(lineWidth: paragraph.width,
                paragraphAlignment: paragraphAlignment)
            return CGPoint(
                x: paragraph.minX + offset.x,
                y: paragraph.minY + offset.y
            )
        }
        let horizontalRect: CGRect
        switch placement.horizontalReference {
        case .paper: horizontalRect = paper
        case .page: horizontalRect = content
        case .column: horizontalRect = column
        // A floating object may leave only a narrow text strip beside itself.
        // That cached strip is not the paragraph's horizontal reference area.
        case .paragraph: horizontalRect = column
        case .absolute: horizontalRect = CGRect(x: 0, y: 0, width: 0, height: 0)
        }
        let verticalRect: CGRect
        switch placement.verticalReference {
        case .paper: verticalRect = paper
        case .page: verticalRect = content
        case .column: verticalRect = column
        case .paragraph: verticalRect = paragraph
        case .absolute: verticalRect = CGRect(x: 0, y: 0, width: 0, height: 0)
        }
        return CGPoint(
            x: alignedOrigin(
                in: horizontalRect,
                objectLength: placement.widthPoints,
                offset: placement.xPoints,
                alignment: placement.horizontalAlignment,
                horizontal: true
            ) + (placement.horizontalAlignment == .start ? placement.marginLeftPoints : 0),
            y: alignedOrigin(
                in: verticalRect,
                objectLength: placement.heightPoints,
                offset: placement.yPoints,
                alignment: placement.verticalAlignment,
                horizontal: false
            ) + (placement.verticalAlignment == .start ? placement.marginTopPoints : 0)
        )
    }

    private func columnRect(
        for line: HWPDocumentLineLayout?,
        fallback: CGRect
    ) -> CGRect {
        columnRect(
            forColumnStart: line?.columnStartPoints ?? 0,
            fallback: fallback
        )
    }

    private func columnRect(
        forColumnStart start: Double,
        fallback: CGRect
    ) -> CGRect {
        guard !layout.columnLayout.columns.isEmpty else { return fallback }
        let column = layout.columnLayout.columns.min {
            abs($0.xPoints - start) < abs($1.xPoints - start)
        } ?? layout.columnLayout.columns[0]
        return CGRect(
            x: layout.leftMarginPoints + column.xPoints,
            y: bodyTopPoints,
            width: column.widthPoints,
            height: fallback.height
        )
    }

    private func alignedOrigin(
        in rect: CGRect,
        objectLength: Double,
        offset: Double,
        alignment: HWPDocumentRelativeAlignment,
        horizontal: Bool
    ) -> Double {
        let minimum = horizontal ? rect.minX : rect.minY
        let maximum = horizontal ? rect.maxX : rect.maxY
        let middle = horizontal ? rect.midX : rect.midY
        let effective: HWPDocumentRelativeAlignment
        switch alignment {
        case .inside:
            effective = page.pageNumber.isMultiple(of: 2) ? .end : .start
        case .outside:
            effective = page.pageNumber.isMultiple(of: 2) ? .start : .end
        default:
            effective = alignment
        }
        switch effective {
        case .center:
            return middle - objectLength / 2 + offset
        case .end:
            return maximum - objectLength + offset
        default:
            return minimum + offset
        }
    }

}





private struct HWPPositionedTableView: View {
    let blocks: [HWPDocumentBlock]
    let maximumWidth: Double
    let sectionBlocks: [HWPDocumentBlock]

    private var cells: [HWPTableCanvasCell] {
        let grouped = Dictionary(grouping: blocks) {
            "\($0.tableLocation?.row ?? 0)-\($0.tableLocation?.column ?? 0)"
        }
        return grouped.values.compactMap { items in
            guard let location = items.first?.tableLocation else { return nil }
            return HWPTableCanvasCell(location: location, blocks: items)
        }
    }

    var body: some View {
        let tracks = HWPTableTrackLayoutSolver.make(
            blocks: blocks,
            maximumWidth: maximumWidth
        )
        let widths = tracks.columnWidths
        let heights = tracks.rowHeights
        ZStack(alignment: .topLeading) {
            ForEach(Array((blocks.first?.tableLocation?.backgroundZones ?? []).enumerated()), id: \.offset) { _, zone in
                if zone.endColumn < widths.count, zone.endRow < heights.count {
                    HWPBoxBackgroundView(style: zone.style)
                        .frame(
                            width: widths[zone.startColumn...zone.endColumn].reduce(0, +),
                            height: heights[zone.startRow...zone.endRow].reduce(0, +)
                        )
                        .clipped()
                        .offset(x: widths.prefix(zone.startColumn).reduce(0, +),
                                y: heights.prefix(zone.startRow).reduce(0, +))
                }
            }
            ForEach(cells) { cell in
                let x = widths.prefix(cell.location.column).reduce(0, +)
                let y = heights.prefix(cell.location.row).reduce(0, +)
                let width = widths[
                    cell.location.column..<min(
                        widths.count,
                        cell.location.column + cell.location.columnSpan
                    )
                ].reduce(0, +)
                let height = heights[
                    cell.location.row..<min(
                        heights.count,
                        cell.location.row + cell.location.rowSpan
                    )
                ].reduce(0, +)
                HWPPositionedTableCellContent(
                    blocks: cell.blocks,
                    sectionBlocks: sectionBlocks
                )
                .frame(width: width, height: height, alignment: .topLeading)
                .background {
                    HWPBoxBackgroundView(style: cell.location.boxStyle)
                }
                .overlay {
                    if let style = cell.location.boxStyle {
                        HWPPageBorderOverlay(style: style)
                    } else {
                        Rectangle().stroke(.black.opacity(0.55), lineWidth: 0.7)
                    }
                }
                .clipped()
                .offset(x: x, y: y)
            }
        }
        // Cell offsets do not participate in SwiftUI's intrinsic-size
        // calculation. Pin the table's internal coordinate space to the
        // solved grid or later columns can be laid out outside a smaller
        // implicit ZStack and clipped near the middle of the page.
        .frame(
            width: tracks.size.width,
            height: tracks.size.height,
            alignment: .topLeading
        )
    }
}

private struct HWPPositionedTableCellContent: View {
    let blocks: [HWPDocumentBlock]
    let sectionBlocks: [HWPDocumentBlock]
    @Environment(\.hwpInlineEditing) private var inlineEditing

    private var location: HWPDocumentTableLocation? {
        blocks.first?.tableLocation
    }

    private var contentHeight: Double {
        let lineBottom = blocks.flatMap(\.lineLayouts).map { line in
            line.verticalPositionPoints
                + max(
                    line.lineHeightPoints,
                    line.textHeightPoints,
                    line.textRuns.compactMap(\.fontSizePoints).max() ?? 0,
                    10
                )
        }.max() ?? 0
        let fallbackBottom = blocks.enumerated().compactMap { index, block in
            block.lineLayouts.isEmpty && !block.text.isEmpty
                ? Double(index) * 16 + 16
                : nil
        }.max() ?? 0
        return max(lineBottom, fallbackBottom)
    }

    private func verticalContentOffset(cellHeight: Double) -> Double {
        guard let location else { return 0 }
        let available = max(
            0,
            cellHeight
                - location.cellMarginTopPoints
                - location.cellMarginBottomPoints
        )
        let remaining = max(0, available - contentHeight)
        switch location.cellVerticalAlignment {
        case .center: return remaining / 2
        case .end: return remaining
        default: return 0
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let marginLeft = location?.cellMarginLeftPoints ?? 0
            let marginRight = location?.cellMarginRightPoints ?? 0
            let marginTop = location?.cellMarginTopPoints ?? 0
            let contentOffsetY = verticalContentOffset(
                cellHeight: proxy.size.height
            )
            ZStack(alignment: .topLeading) {
                ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                    HWPParagraphBorderView(block: block)
                        .offset(x: marginLeft, y: marginTop + contentOffsetY)
                    if block.lineLayouts.isEmpty {
                        HWPStyledRunsText(
                            text: block.text,
                            runs: block.presentation.textRuns,
                            fallbackSize: 10
                        )
                        .frame(
                            width: max(
                                proxy.size.width - marginLeft - marginRight,
                                1
                            ),
                            alignment: frameAlignment(block.presentation.alignment)
                        )
                        .opacity(inlineEditing.hidesText(block) ? 0 : 1)
                        .accessibilityHidden(inlineEditing.source(for: block) != nil)
                        .hwpPageAccessibilityActions()
                        .allowsHitTesting(false)
                        .offset(
                            x: marginLeft + block.presentation.leftMarginPoints,
                            y: marginTop + contentOffsetY + Double(index) * 16
                        )
                    } else {
                        ForEach(block.lineLayouts) { line in
                            if !line.isEmpty, !line.text.isEmpty {
                                let fontSize = max(
                                    line.textHeightPoints,
                                    line.textRuns.compactMap(\.fontSizePoints).max() ?? 0,
                                    8
                                )
                                HWPMetricLineText(
                                    text: line.text,
                                    runs: line.textRuns,
                                    fallbackSize: fontSize,
                                    alignment: block.presentation.alignment,
                                    baselinePoints: line.baselinePoints,
                                    baselineAlignment: line.baselineAlignment,
                                    isLastLine: line.endsParagraph ?? (line.id == block.lineLayouts.last?.id),
                                    listMarker: line.listMarker,
                                    showsListMarker: line.showsListMarker,
                        searchBlock: block, searchLine: line
                                )
                                .frame(
                                    width: min(
                                        max(line.widthPoints - line.textInsetPoints, 1),
                                        max(
                                            proxy.size.width
                                                - marginLeft
                                                - marginRight
                                                - max(line.columnStartPoints, 0)
                                                - line.textInsetPoints,
                                            1
                                        )
                                    ),
                                    height: max(line.lineHeightPoints, fontSize, 10),
                                    alignment: frameAlignment(block.presentation.alignment)
                                )
                                .opacity(inlineEditing.hidesText(block) ? 0 : 1)
                                .accessibilityHidden(inlineEditing.source(for: block) != nil)
                                .hwpPageAccessibilityActions()
                                .allowsHitTesting(false)
                                .offset(
                                    x: marginLeft
                                        + max(line.columnStartPoints, 0)
                                        + line.textInsetPoints,
                                    y: marginTop
                                        + contentOffsetY
                                        + max(line.verticalPositionPoints, 0)
                                )
                            }
                        }
                    }
                    HWPInlineParagraphTarget(block: block,
                        rect: HWPInlineParagraphGeometry.rect(block: block,
                            width: max(1, proxy.size.width - marginLeft - marginRight),
                            fallbackY: Double(index) * 16)
                            .offsetBy(dx: marginLeft, dy: marginTop + contentOffsetY))
                    ForEach(block.canvasObjects) { object in
                        let textBlocks = object.textContainerID.map { containerID in
                            sectionBlocks.filter {
                                $0.layoutContainerID == containerID
                            }
                        } ?? []
                        let origin = cellObjectOrigin(
                            object,
                            owner: block,
                            contentOffsetY: contentOffsetY
                        )
                        HWPDocumentCanvasObjectView(
                            object: object,
                            textBlocks: textBlocks,
                            ownerID: block.id
                        )
                        .frame(
                            width: object.placement.widthPoints,
                            height: object.placement.heightPoints,
                            alignment: .topLeading
                        )
                        .rotationEffect(.degrees(object.placement.rotationDegrees))
                        .offset(x: origin.x, y: origin.y)
                        .zIndex(Double(object.placement.zOrder) + 100)
                    }
                }
            }
        }
        .clipped()
    }

    private func cellObjectOrigin(
        _ object: HWPDocumentCanvasObject,
        owner: HWPDocumentBlock,
        contentOffsetY: Double
    ) -> CGPoint {
        let placement = object.placement
        let anchor = placement.sourceCharacterPosition.flatMap { position in
            owner.lineLayouts.last { $0.startCharacter <= position }
        } ?? owner.lineLayouts.first
        let usesParagraphX = placement.isInline
            || placement.horizontalReference == .paragraph
        let usesParagraphY = placement.isInline
            || placement.verticalReference == .paragraph
        let inlineOffset = placement.inlineOffset(lineWidth: anchor?.widthPoints ?? 0,
            paragraphAlignment: owner.presentation.alignment)
        return CGPoint(
            x: (usesParagraphX
                ? (location?.cellMarginLeftPoints ?? 0)
                    + (anchor?.columnStartPoints ?? 0)
                    + (anchor?.textInsetPoints ?? 0)
                : 0)
                + (placement.isInline ? inlineOffset.x + placement.inlineLeadingPoints : placement.xPoints),
            y: (usesParagraphY
                ? (location?.cellMarginTopPoints ?? 0)
                    + contentOffsetY
                    + (anchor?.verticalPositionPoints ?? 0)
                : 0)
                + placement.yPoints + placement.inlineBaselineOffset(in: anchor)
        )
    }
}

private struct HWPBoxBackgroundView: View {
    let style: HWPDocumentBoxStyle?

    var body: some View {
        ZStack {
            // Cells without a fill are transparent in HWP; painting them
            // white hides the parent cell's borders under nested tables.
            style?.backgroundColorRGB.map(hwpColor) ?? .clear
            if let image = style?.backgroundImage,
               let uiImage = UIImage(data: image.data) {
                if style?.backgroundImageFillMode == 5 {
                    Image(uiImage: uiImage).resizable()
                } else {
                    Image(uiImage: uiImage).resizable().scaledToFill()
                }
            }
        }
    }
}

private struct HWPTableCanvasCell: Identifiable {
    let location: HWPDocumentTableLocation
    let blocks: [HWPDocumentBlock]
    var id: String { "\(location.row)-\(location.column)" }
}

/// Keep the document pixels in a stable, stateless subtree. Direct-object
/// manipulation adds state and gestures around this view; separating them
/// prevents UIKit-backed text inside a shape from disappearing in snapshots.
private struct HWPDocumentCanvasObjectContentView: View {
    let object: HWPDocumentCanvasObject
    let textBlocks: [HWPDocumentBlock]
    let selectedShapeID: String?
    let ownerID: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch object.content {
            case .shape(let shape):
                HWPShapeCanvasView(shape: shape)
                    .scaleEffect(
                        x: object.placement.flipHorizontal ? -1 : 1,
                        y: object.placement.flipVertical ? -1 : 1
                    )
            case .group(let shapes):
                HWPShapeGroupView(
                    shapes: shapes,
                    selectedID: selectedShapeID,
                    objectID: object.id,
                    coordinateBounds: object.groupChildBounds
                )
                .scaleEffect(
                    x: object.placement.flipHorizontal ? -1 : 1,
                    y: object.placement.flipVertical ? -1 : 1
                )
            case .image(let image):
                HWPImageCanvasView(image: image)
                    .scaleEffect(
                        x: object.placement.flipHorizontal ? -1 : 1,
                        y: object.placement.flipVertical ? -1 : 1
                    )
            case .equation(let equation):
                HWPEquationCanvasView(equation: equation)
            case .chart(let chart):
                HWPChartCanvasView(chart: chart)
            case .unsupported(let label):
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.08))
                    .overlay {
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(.gray)
                    }
            }

            if !textBlocks.isEmpty {
                if let frame = object.groupedTextFrame {
                    HWPTextContainerView(
                        blocks: textBlocks,
                        layout: object.textContainerLayout
                    )
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                } else {
                    HWPTextContainerView(
                        blocks: textBlocks,
                        layout: object.textContainerLayout
                    )
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
                }
            }
        }
    }
}

private struct HWPDocumentCanvasObjectView: View {
    let object: HWPDocumentCanvasObject
    let textBlocks: [HWPDocumentBlock]
    let ownerID: String
    var interceptsParentTap = false
    @Environment(\.hwpImageObjectEditing) private var imageEditing
    @Environment(\.hwpShapeObjectEditing) private var shapeEditing
    @Environment(\.hwpEquationObjectEditing) private var equationEditing
    @Environment(\.hwpTextBoxObjectEditing) private var textBoxEditing
    @Environment(\.hwpInlineEditing) private var inlineEditing
    @Environment(\.hwpCanvasObjectSelection) private var selection
    @State private var moveTranslation = CGSize.zero
    @State private var resizeAnchor: HWPShapeEditing.ResizeAnchor?
    @State private var resizeTranslation = CGSize.zero
    @State private var isRotating = false
    @State private var rotationDelta = 0.0

    private var isShapeObject: Bool {
        switch object.content {
        case .shape, .group: true
        default: false
        }
    }

    private var isImageObject: Bool {
        if case .image = object.content { return true }
        return false
    }

    private var isDirectlySelected: Bool {
        (isShapeObject && shapeEditing.selectedID == object.id)
            || (isImageObject && imageEditing.selectedID == object.id)
    }

    /// Whether `selectObject` reaches an editing target for this object here (not, for
    /// example, a picture in a header or an equation in a table cell).
    private var isSelectable: Bool {
        selection.canSelect(ownerID, object, !textBlocks.isEmpty)
    }

    private var isGroupChildSelected: Bool {
        guard case .group = object.content else { return false }
        return shapeEditing.selectedID?.hasPrefix(object.id + "#group-child-") == true
    }

    private var isAccessibilitySelected: Bool {
        isDirectlySelected || isGroupChildSelected
            || shapeEditing.groupedSelectionIDs.contains(object.id)
            || equationEditing.selectedID == object.id || textBoxEditing.selectedID == object.id
    }

    private var preview: (offset: CGSize, size: CGSize, rotationDelta: Double) {
        var offset = moveTranslation
        var width = object.placement.widthPoints
        var height = object.placement.heightPoints
        if (isShapeObject || isImageObject), resizeAnchor == nil,
           let localMove = HWPShapeEditing.directLocalVector(
               deltaX: Double(moveTranslation.width),
               deltaY: Double(moveTranslation.height),
               rotationDegrees: object.placement.rotationDegrees,
               flipHorizontal: object.placement.flipHorizontal,
               flipVertical: object.placement.flipVertical) {
            offset = CGSize(width: localMove.x, height: localMove.y)
        }
        if let resizeAnchor {
            if (isShapeObject || isImageObject),
               let geometry = HWPShapeEditing.directResizeGeometry(
                anchor: resizeAnchor,
                deltaX: Double(resizeTranslation.width),
                deltaY: Double(resizeTranslation.height),
                xPoints: object.placement.xPoints,
                yPoints: object.placement.yPoints,
                widthPoints: width, heightPoints: height,
                rotationDegrees: object.placement.rotationDegrees,
                flipHorizontal: object.placement.flipHorizontal,
                flipVertical: object.placement.flipVertical,
                minimumHeight: isImageObject ? 20 : 8) {
                offset = CGSize(width: geometry.localOffsetX, height: geometry.localOffsetY)
                width = geometry.widthPoints
                height = geometry.heightPoints
            } else {
                let requestedWidth = width
                    + (resizeAnchor.movesLeadingEdge ? -resizeTranslation.width : resizeTranslation.width)
                let requestedHeight = height
                    + (resizeAnchor.movesTopEdge ? -resizeTranslation.height : resizeTranslation.height)
                let changedWidth = min(max(requestedWidth, 20), 2_000)
                let changedHeight = min(max(requestedHeight, isImageObject ? 20 : 8), 2_000)
                if resizeAnchor.movesLeadingEdge { offset.width += width - changedWidth }
                if resizeAnchor.movesTopEdge { offset.height += height - changedHeight }
                width = changedWidth
                height = changedHeight
            }
        }
        return (offset, CGSize(width: width, height: height), rotationDelta)
    }

    var body: some View {
        let preview = preview
        HWPDocumentCanvasObjectContentView(
            object: object,
            textBlocks: textBlocks,
            selectedShapeID: shapeEditing.selectedID,
            ownerID: ownerID
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(HWPCanvasObjectLabel.text(object, hasText: !textBlocks.isEmpty))
        .accessibilityValue(textBlocks.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n"))
        .accessibilityIdentifier("hwp-canvas-object-\(object.id)")
        .modifier(HWPCanvasObjectAccessibility(
            isSelectable: isSelectable,
            isSelected: isAccessibilitySelected,
            isPicked: isDirectlySelected && inlineEditing.session != nil,
            canDeselect: isDirectlySelected || isGroupChildSelected,
            onSelect: selectObject,
            onMove: { dx, dy in applyDirectManipulation(.move(deltaX: dx, deltaY: dy)) },
            onResize: { delta in
                applyDirectManipulation(.resize(anchor: .bottomTrailing, deltaX: delta, deltaY: delta))
            },
            onDeselect: isImageObject ? imageEditing.onDeselect : shapeEditing.onDeselect))
        // Applied after the object's actions so VoiceOver lists the page's first (Android order).
        .hwpPageAccessibilityActions()
        .contentShape(Rectangle())
        // A drag on a resize or rotation handle must not also move the object.
        // Keep the move recognizer on the object content, outside the overlay
        // that contains the direct-manipulation handles.
        .simultaneousGesture(moveGesture, including: isDirectlySelected ? .gesture : .none)
        .overlay {
            if imageEditing.selectedID == object.id || shapeEditing.selectedID == object.id
                || shapeEditing.groupedSelectionIDs.contains(object.id)
                || equationEditing.selectedID == object.id || textBoxEditing.selectedID == object.id {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.accentColor,
                        style: StrokeStyle(lineWidth: 2,
                            dash: shapeEditing.groupedSelectionIDs.contains(object.id) ? [5, 3] : []))
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if isDirectlySelected {
                directManipulationHandles
            }
        }
        .scaleEffect(
            x: resizeAnchor == nil
                ? 1
                : preview.size.width / max(object.placement.widthPoints, 1),
            y: resizeAnchor == nil
                ? 1
                : preview.size.height / max(object.placement.heightPoints, 1),
            anchor: .topLeading
        )
        .rotationEffect(.degrees(preview.rotationDelta))
        .offset(preview.offset)
        // Canvas objects sit above paragraph and table-cell editing targets.
        // Give their tap one consistent priority so the underlying text target
        // cannot consume the first selection tap.
        .highPriorityGesture(SpatialTapGesture().onEnded { value in
            if canSelectGroupChildren,
               let index = HWPShapeEditing.groupChildIndex(at: value.location, in: object) {
                shapeEditing.onSelectChild(ownerID, object, index)
            } else {
                selectObject()
            }
        })
    }

    private var canSelectGroupChildren: Bool {
        guard case .group = object.content, !shapeEditing.isSelectingGroup else { return false }
        return shapeEditing.selectedID == object.id
            || shapeEditing.selectedID?.hasPrefix(object.id + "#group-child-") == true
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("hwp-document-paper"))
            .onChanged { value in
                guard resizeAnchor == nil, !isRotating else { return }
                moveTranslation = value.translation
            }
            .onEnded { value in
                guard resizeAnchor == nil, !isRotating else { return }
                moveTranslation = .zero
                let dx = Double(value.translation.width)
                let dy = Double(value.translation.height)
                guard abs(dx) >= 0.25 || abs(dy) >= 0.25 else { return }
                applyDirectManipulation(.move(deltaX: dx, deltaY: dy))
            }
    }

    @ViewBuilder
    private var directManipulationHandles: some View {
        GeometryReader { proxy in
            Path { path in
                path.move(to: CGPoint(x: proxy.size.width / 2, y: 0))
                path.addLine(to: CGPoint(x: proxy.size.width / 2, y: 16))
            }
            .stroke(Color.accentColor, lineWidth: 2)
            .allowsHitTesting(false)
            resizeHandle(.topLeading)
                .position(x: 0, y: 0)
            resizeHandle(.topTrailing)
                .position(x: proxy.size.width, y: 0)
            resizeHandle(.bottomLeading)
                .position(x: 0, y: proxy.size.height)
            resizeHandle(.bottomTrailing)
                .position(x: proxy.size.width, y: proxy.size.height)
            rotationHandle
                // Canvas objects are framed to their document bounds by the
                // page and table-cell layers. A handle outside that frame can
                // be drawn but cannot reliably receive a touch on device.
                .position(x: proxy.size.width / 2, y: 16)
        }
    }

    private var rotationHandle: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                .frame(width: 18, height: 18)
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: 32, height: 32)
        .contentShape(Rectangle())
        .accessibilityLabel(isImageObject ? "그림 회전" : "도형 회전")
        .accessibilityIdentifier(isImageObject ? "hwp-image-rotate" : "hwp-shape-rotate")
        .highPriorityGesture(rotationGesture)
    }

    private func resizeHandle(_ anchor: HWPShapeEditing.ResizeAnchor) -> some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                .frame(width: 13, height: 13)
        }
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .accessibilityLabel(isImageObject ? "그림 크기 조절" : "도형 크기 조절")
            .accessibilityIdentifier("hwp-\(isImageObject ? "image" : "shape")-resize-\(anchor.rawValue)")
            .highPriorityGesture(resizeGesture(anchor))
    }

    private func resizeGesture(_ anchor: HWPShapeEditing.ResizeAnchor) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("hwp-document-paper"))
            .onChanged { value in
                resizeAnchor = anchor
                resizeTranslation = value.translation
            }
            .onEnded { value in
                resizeAnchor = nil
                resizeTranslation = .zero
                let dx = Double(value.translation.width)
                let dy = Double(value.translation.height)
                guard abs(dx) >= 0.25 || abs(dy) >= 0.25 else { return }
                applyDirectManipulation(.resize(anchor: anchor, deltaX: dx, deltaY: dy))
            }
    }

    private var rotationGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("hwp-document-paper"))
            .onChanged { value in
                isRotating = true
                rotationDelta = rotationDelta(for: value.translation)
            }
            .onEnded { value in
                let delta = rotationDelta(for: value.translation)
                isRotating = false
                rotationDelta = 0
                guard abs(delta) >= 0.1 else { return }
                applyDirectManipulation(.rotate(deltaDegrees: delta))
            }
    }

    private func applyDirectManipulation(_ operation: HWPShapeEditing.DirectManipulation) {
        if isImageObject {
            let imageOperation: HWPImageEditing.DirectManipulation = switch operation {
            case .move(let deltaX, let deltaY): .move(deltaX: deltaX, deltaY: deltaY)
            case .resize(let anchor, let deltaX, let deltaY):
                .resize(anchor: anchor, deltaX: deltaX, deltaY: deltaY)
            case .rotate(let deltaDegrees): .rotate(deltaDegrees: deltaDegrees)
            }
            imageEditing.onDirectManipulation(ownerID, object, imageOperation)
        } else {
            shapeEditing.onDirectManipulation(ownerID, object, operation)
        }
    }

    private func rotationDelta(for translation: CGSize) -> Double {
        let base = object.placement.rotationDegrees
        let radians = base * .pi / 180
        let radius = max(object.placement.heightPoints / 2, 12)
        let initialX = sin(radians) * radius
        let initialY = -cos(radians) * radius
        let currentX = initialX + Double(translation.width)
        let currentY = initialY + Double(translation.height)
        guard abs(currentX) + abs(currentY) > 0.001 else { return 0 }
        let current = atan2(currentX, -currentY) * 180 / .pi
        var delta = (current - base).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }

    private func selectObject() {
        if !textBlocks.isEmpty {
            textBoxEditing.onSelect(ownerID, object, textBlocks)
            return
        }
        switch object.content {
        case .image: imageEditing.onSelect(ownerID, object)
        case .shape, .group: shapeEditing.onSelect(ownerID, object)
        case .equation: equationEditing.onSelect(ownerID, object)
        default: break
        }
    }

}

/// VoiceOver for an object on the page, the non-gesture alternative to tapping and
/// dragging it (Android `objectAccessibilityActions`): double-tap selects it as a tap
/// does (again: its settings); a picked picture or shape moves 20 pt 위로·아래로·
/// 왼쪽으로·오른쪽으로, grows or shrinks 20 pt from its bottom-right corner
/// (개체 크게·작게), opens 개체 설정, or is let go (선택 해제).
/// What VoiceOver reads for an object on the 원본 pages, as Android's `HwpPageText.objectText` does: a picture
/// "그림: <설명>", a chart its kind, title (else description) and "계열: …", an equation its script.
nonisolated enum HWPCanvasObjectLabel {
    static func text(_ object: HWPDocumentCanvasObject, hasText: Bool) -> String {
        let description = [object.description, imageDescription(object)]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        switch object.content {
        case .image:
            let image = AppLocalization.string("그림")
            return description.map { AppLocalization.format("그림: %@", $0) } ?? image
        case .equation(let equation):
            let script = equation.script.trimmingCharacters(in: .whitespacesAndNewlines)
            let shown = script.isEmpty ? (description ?? "") : script
            return shown.isEmpty ? AppLocalization.string("수식") : AppLocalization.format("수식 %@", shown)
        case .chart(let chart):
            let title = chart.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let series = chart.series.map(\.name).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            return [
                kind(chart.kind),
                title?.isEmpty == false ? title : description,
                series.isEmpty ? nil : AppLocalization.format("계열: %@", series.joined(separator: ", ")),
            ].compactMap { $0 }.joined(separator: ". ")
        case .shape, .group, .unsupported:
            if let description { return description }
            if hasText { return AppLocalization.string("글상자") }
            switch object.content {
            case .shape: return AppLocalization.string("도형")
            case .group: return AppLocalization.string("묶음 개체")
            case .unsupported(let label):
                return label.isEmpty ? AppLocalization.string("한글 문서 개체") : label
            default: return AppLocalization.string("한글 문서 개체")
            }
        }
    }

    private static func imageDescription(_ object: HWPDocumentCanvasObject) -> String? {
        if case .image(let image) = object.content { return image.description }
        return nil
    }

    private static func kind(_ kind: HWPDocumentChartKind) -> String {
        switch kind {
        case .bar: AppLocalization.string("막대형 차트")
        case .line: AppLocalization.string("꺾은선형 차트")
        case .pie: AppLocalization.string("원형 차트")
        case .area: AppLocalization.string("영역형 차트")
        case .scatter: AppLocalization.string("분산형 차트")
        case .radar: AppLocalization.string("방사형 차트")
        case .unknown: AppLocalization.string("차트")
        }
    }
}

private struct HWPCanvasObjectAccessibility: ViewModifier {
    static let nudgePoints = 20.0

    let isSelectable: Bool
    let isSelected: Bool
    let isPicked: Bool
    let canDeselect: Bool
    let onSelect: () -> Void
    let onMove: (Double, Double) -> Void
    let onResize: (Double) -> Void
    let onDeselect: () -> Void

    func body(content: Content) -> some View {
        if isSelectable {
            content
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                .accessibilityHint(isPicked
                    ? AppLocalization.string("두 번 탭하면 개체 설정을 엽니다. 동작에서 이동·크기·선택 해제를 고를 수 있습니다.")
                    : AppLocalization.string("두 번 탭하면 개체를 선택합니다."))
                .accessibilityAction { onSelect() }
                // SwiftUI hands VoiceOver these in reverse: written last to first so the
                // rotor reads 위로 이동 … 선택 해제 as on Android (HWPAndroidParityTests).
                .accessibilityActions {
                    if canDeselect {
                        Button("선택 해제") { onDeselect() }
                    }
                    if isPicked {
                        Button("개체 설정") { onSelect() }
                        Button("개체 작게") { onResize(-Self.nudgePoints) }
                        Button("개체 크게") { onResize(Self.nudgePoints) }
                        Button("오른쪽으로 이동") { onMove(Self.nudgePoints, 0) }
                        Button("왼쪽으로 이동") { onMove(-Self.nudgePoints, 0) }
                        Button("아래로 이동") { onMove(0, Self.nudgePoints) }
                        Button("위로 이동") { onMove(0, -Self.nudgePoints) }
                    }
                }
        } else {
            content.accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
}

private struct HWPImageCanvasView: View {
    let image: HWPDocumentImage

    private var decodedImage: UIImage? {
        guard let original = UIImage(data: image.data),
              let crop = image.cropRect,
              let source = original.cgImage else {
            return UIImage(data: image.data)
        }
        let pixelRect = CGRect(
            x: crop.minX * CGFloat(source.width),
            y: crop.minY * CGFloat(source.height),
            width: crop.width * CGFloat(source.width),
            height: crop.height * CGFloat(source.height)
        ).integral.intersection(
            CGRect(
                x: 0,
                y: 0,
                width: CGFloat(source.width),
                height: CGFloat(source.height)
            )
        )
        guard pixelRect.width >= 1,
              pixelRect.height >= 1,
              let cropped = source.cropping(to: pixelRect) else { return original }
        return UIImage(
            cgImage: cropped,
            scale: original.scale,
            orientation: original.imageOrientation
        )
    }

    var body: some View {
        if let decodedImage {
            Image(uiImage: decodedImage)
                .resizable()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .brightness(Double(image.brightness) / 100)
                .contrast((1 + Double(image.contrast) / 100)
                    * (image.effect == .blackAndWhite ? 20 : 1))
                .grayscale(image.effect == .original ? 0 : 1)
                .opacity(1 - Double(image.transparencyPercent) / 100)
                .overlay {
                    if let border = image.borderStroke {
                        Rectangle().stroke(
                            hwpColor(border.colorRGB),
                            style: StrokeStyle(
                                lineWidth: border.widthPoints,
                                lineCap: [3, 7].contains(border.style) ? .round : .butt,
                                dash: HWPStrokePattern.dashes(kind: border.style, width: border.widthPoints)
                            )
                        )
                    }
                }
        } else {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.gray.opacity(0.08))
                .overlay {
                    Text("그림")
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
        }
    }

}

private struct HWPTextContainerView: View {
    let blocks: [HWPDocumentBlock]
    let layout: HWPDocumentTextContainerLayout?

    private var paragraphs: [HWPDocumentBlock] {
        blocks.filter { $0.tableLocation == nil }
    }

    private var tables: [Int: [HWPDocumentBlock]] {
        Dictionary(grouping: blocks.filter {
            $0.tableLocation != nil && $0.tableLocation?.parent == nil
        }) { $0.tableLocation!.table }
    }

    var body: some View {
        GeometryReader { proxy in
            let left = layout?.left ?? 6
            let right = layout?.right ?? 6
            let top = layout?.top ?? 6
            let textHeight = paragraphs.flatMap(\.lineLayouts).map {
                $0.verticalPositionPoints + $0.lineHeightPoints
            }.max() ?? Double(paragraphs.count) * 15
            let tableHeight = tables.values.map { tableBlocks in
                let location = tableBlocks.first?.tableLocation
                let origin = (location?.tableAnchor?.verticalPositionPoints ?? 0)
                    + (location?.tablePlacement?.yPoints ?? 0)
                return origin + HWPTableTrackLayoutSolver.make(
                    blocks: tableBlocks,
                    maximumWidth: max(1, proxy.size.width - left - right)
                ).size.height
            }.max() ?? 0
            let contentHeight = max(textHeight, tableHeight)
            let remaining = max(0, proxy.size.height - top - (layout?.bottom ?? 6) - contentHeight)
            let verticalOffset = layout?.verticalAlignment == .center ? remaining / 2
                : layout?.verticalAlignment == .end ? remaining : 0
            ZStack(alignment: .topLeading) {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, block in
                    if block.lineLayouts.isEmpty {
                        HWPStyledRunsText(
                            text: block.text,
                            runs: block.presentation.textRuns,
                            fallbackSize: 10
                        )
                        .offset(x: left, y: top + verticalOffset + Double(index) * 15)
                    } else {
                        ForEach(Array(block.lineLayouts.enumerated()), id: \.offset) {
                            _, line in
                            let fontSize = max(
                                line.textHeightPoints,
                                line.textRuns.compactMap(\.fontSizePoints).max() ?? 0,
                                8
                            )
                            HWPMetricLineText(
                                text: line.text,
                                runs: line.textRuns,
                                fallbackSize: fontSize,
                                alignment: block.presentation.alignment,
                                baselinePoints: line.baselinePoints,
                                baselineAlignment: line.baselineAlignment,
                                isLastLine: line.id == block.lineLayouts.last?.id
                            )
                            .frame(
                                width: max(line.widthPoints, 1),
                                height: max(
                                    line.lineHeightPoints,
                                    fontSize * 1.35,
                                    14
                                ),
                                alignment: frameAlignment(block.presentation.alignment)
                            )
                            .offset(
                                x: left + line.columnStartPoints,
                                y: top + verticalOffset + line.verticalPositionPoints
                            )
                        }
                    }
                    ForEach(block.canvasObjects) { object in
                        let nestedText = object.textContainerID.map { containerID in
                            blocks.filter { $0.layoutContainerID == containerID }
                        } ?? []
                        let origin = objectOrigin(object, owner: block,
                            left: left, top: top + verticalOffset)
                        AnyView(HWPDocumentCanvasObjectView(object: object,
                            textBlocks: nestedText, ownerID: block.id,
                            interceptsParentTap: true))
                            .frame(width: max(object.placement.widthPoints, 1),
                                height: max(object.placement.heightPoints, 1),
                                alignment: .topLeading)
                            .rotationEffect(.degrees(object.placement.rotationDegrees))
                            .offset(x: origin.x, y: origin.y)
                            .zIndex(Double(object.placement.zOrder) + 10)
                    }
                }
                ForEach(tables.keys.sorted(), id: \.self) { tableIndex in
                    let tableBlocks = tables[tableIndex] ?? []
                    let maximumWidth = max(1, proxy.size.width - left - right)
                    let declaredWidth = tableBlocks.first?.tableLocation?
                        .tablePlacement?.widthPoints ?? maximumWidth
                    let width = min(maximumWidth, max(declaredWidth, 1))
                    let tracks = HWPTableTrackLayoutSolver.make(
                        blocks: tableBlocks,
                        maximumWidth: width
                    )
                    let origin = tableOrigin(tableBlocks,
                        left: left, top: top + verticalOffset)
                    HWPPositionedTableView(
                        blocks: tableBlocks,
                        maximumWidth: width,
                        sectionBlocks: blocks
                    )
                    .frame(width: tracks.size.width, height: tracks.size.height,
                        alignment: .topLeading)
                    .offset(x: origin.x, y: origin.y)
                    .zIndex(20)
                }
            }
        }
        .clipped()
    }

    private func tableOrigin(_ tableBlocks: [HWPDocumentBlock],
                             left: Double, top: Double) -> CGPoint {
        guard let location = tableBlocks.first?.tableLocation else {
            return CGPoint(x: left, y: top)
        }
        let placement = location.tablePlacement
        let anchor = location.tableAnchor
        let paragraphX = placement?.isInline == true
            || placement?.horizontalReference == .paragraph
        let paragraphY = placement?.isInline == true
            || placement?.verticalReference == .paragraph
        return CGPoint(
            x: left + (paragraphX ? max(anchor?.columnStartPoints ?? 0, 0) : 0)
                + (placement?.xPoints ?? anchor?.columnStartPoints ?? 0),
            y: top + (paragraphY ? max(anchor?.verticalPositionPoints ?? 0, 0) : 0)
                + (placement?.yPoints ?? anchor?.verticalPositionPoints ?? 0)
        )
    }

    private func objectOrigin(_ object: HWPDocumentCanvasObject, owner: HWPDocumentBlock,
                              left: Double, top: Double) -> CGPoint {
        let placement = object.placement
        let anchor = placement.sourceCharacterPosition.flatMap { position in
            owner.lineLayouts.last { $0.startCharacter <= position }
        } ?? owner.lineLayouts.first
        let paragraphX = placement.isInline || placement.horizontalReference == .paragraph
        let paragraphY = placement.isInline || placement.verticalReference == .paragraph
        let inline = placement.inlineOffset(lineWidth: anchor?.widthPoints ?? 0,
            paragraphAlignment: owner.presentation.alignment)
        return CGPoint(
            x: left + (paragraphX ? (anchor?.columnStartPoints ?? 0) + (anchor?.textInsetPoints ?? 0) : 0)
                + (placement.isInline ? inline.x + placement.inlineLeadingPoints : placement.xPoints),
            y: top + (paragraphY ? (anchor?.verticalPositionPoints ?? 0) : 0)
                + placement.yPoints + placement.inlineBaselineOffset(in: anchor))
    }
}

private struct HWPShapeGroupView: View {
    let shapes: [HWPDocumentShape]
    let selectedID: String?
    let objectID: String
    let coordinateBounds: CGRect?

    private var drawableShapes: [(index: Int, shape: HWPDocumentShape)] {
        shapes.enumerated().compactMap { index, shape in
            if case .container = shape.geometry { return nil }
            return (index, shape)
        }
    }

    private var bounds: CGRect {
        if let coordinateBounds { return coordinateBounds }
        let frames = drawableShapes.compactMap { $0.shape.localFrame }
        guard let first = frames.first else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        return frames.dropFirst().reduce(first) { $0.union($1) }
    }

    var body: some View {
        GeometryReader { proxy in
            let groupBounds = bounds
            let scaleX = proxy.size.width / max(groupBounds.width, 1)
            let scaleY = proxy.size.height / max(groupBounds.height, 1)
            ZStack(alignment: .topLeading) {
                ForEach(drawableShapes, id: \.index) { item in
                    let shape = item.shape
                    let local = shape.localFrame ?? groupBounds
                    HWPShapeCanvasView(shape: shape)
                        .frame(
                            width: max(1, local.width * scaleX),
                            height: max(1, local.height * scaleY)
                        )
                        .contentShape(Rectangle())
                        .accessibilityIdentifier("hwp-group-child-\(objectID)-\(item.index)")
                        .overlay {
                            if selectedID == HWPShapeEditing.Target.selectionID(
                                objectID: objectID, childIndex: item.index) {
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(Color.accentColor, lineWidth: 2)
                                    .allowsHitTesting(false)
                            }
                        }
                        .scaleEffect(x: shape.flipHorizontal ? -1 : 1,
                            y: shape.flipVertical ? -1 : 1)
                        .rotationEffect(.degrees(shape.rotationDegrees))
                        .offset(
                            x: (local.minX - groupBounds.minX) * scaleX,
                            y: (local.minY - groupBounds.minY) * scaleY
                        )
                }
            }
        }
    }
}

private struct HWPShapeCanvasView: View {
    let shape: HWPDocumentShape

    var body: some View {
        Canvas { context, size in
            let path = path(in: size)
            if shouldFill,
               let fill = shape.fill.colorRGB {
                context.fill(path, with: .color(hwpColor(fill)))
            }
            if shape.stroke.style != 0 {
                // Keep the complete stroke inside the canvas. Sub-point vertical
                // edges otherwise disappear when their outside half is clipped.
                let inset = max(0, shape.stroke.widthPoints / 2)
                let strokePath = self.path(in: CGSize(
                    width: max(0.01, size.width - 2 * inset),
                    height: max(0.01, size.height - 2 * inset)
                )).applying(CGAffineTransform(translationX: inset, y: inset))
                context.stroke(
                    strokePath,
                    with: .color(hwpColor(shape.stroke.colorRGB)),
                    style: StrokeStyle(
                        lineWidth: shape.stroke.widthPoints,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: HWPStrokePattern.dashes(kind: shape.stroke.style, width: shape.stroke.widthPoints)
                    )
                )
            }
            if let (start, end) = arrowEndpoints(in: size) {
                drawArrow(
                    kind: shape.stroke.startArrow,
                    tip: start,
                    toward: end,
                    context: &context
                )
                drawArrow(
                    kind: shape.stroke.endArrow,
                    tip: end,
                    toward: start,
                    context: &context
                )
            }
        }
        .compositingGroup()
        .shadow(color: shape.shadow.map { hwpColor($0.colorRGB).opacity($0.opacity) } ?? .clear,
            radius: 0, x: shape.shadow?.offset.width ?? 0, y: shape.shadow?.offset.height ?? 0)
    }

    private var shouldFill: Bool {
        switch shape.geometry {
        case .line, .curve, .container, .unknown:
            return false
        case .arc(_, _, _, let kind):
            return kind == 1 || kind == 2
        default:
            return true
        }
    }

    private func path(in size: CGSize) -> Path {
        switch shape.geometry {
        case .line(let start, let end):
            let mapped = map([start, end], into: size)
            var path = Path()
            if mapped.count == 2 {
                path.move(to: mapped[0])
                path.addLine(to: mapped[1])
            }
            return path
        case .rectangle(let radius, let points):
            let mapped = map(points, into: size)
            let isAxisAligned = mapped.count == 4
                && abs(mapped[0].y - mapped[1].y) < 0.01
                && abs(mapped[1].x - mapped[2].x) < 0.01
                && abs(mapped[2].y - mapped[3].y) < 0.01
                && abs(mapped[3].x - mapped[0].x) < 0.01
            if points.isEmpty || isAxisAligned {
                return Path(
                    roundedRect: CGRect(origin: .zero, size: size),
                    cornerRadius: min(size.width, size.height) * min(radius, 50) / 100
                )
            }
            var path = Path()
            if let first = mapped.first {
                path.move(to: first)
                for point in mapped.dropFirst() { path.addLine(to: point) }
                path.closeSubpath()
            }
            return path
        case .ellipse:
            return Path(ellipseIn: CGRect(origin: .zero, size: size))
        case .arc(let center, let axis1, let axis2, let kind):
            let start = atan2(axis1.y - center.y, axis1.x - center.x)
            var end = atan2(axis2.y - center.y, axis2.x - center.x)
            while end <= start { end += Double.pi * 2 }
            var path = Path()
            let visualCenter = CGPoint(x: size.width / 2, y: size.height / 2)
            if kind == 1 { path.move(to: visualCenter) }
            let segmentCount = 40
            for index in 0...segmentCount {
                let progress = Double(index) / Double(segmentCount)
                let angle = start + (end - start) * progress
                let point = CGPoint(
                    x: visualCenter.x + cos(angle) * size.width / 2,
                    y: visualCenter.y + sin(angle) * size.height / 2
                )
                if index == 0 && kind != 1 { path.move(to: point) }
                else { path.addLine(to: point) }
            }
            if kind == 1 || kind == 2 { path.closeSubpath() }
            return path
        case .polygon(let points):
            let mapped = map(points, into: size)
            var path = Path()
            if let first = mapped.first {
                path.move(to: first)
                for point in mapped.dropFirst() { path.addLine(to: point) }
                path.closeSubpath()
            }
            return path
        case .curve(let points, let curved):
            let mapped = map(points, into: size)
            var path = Path()
            guard let first = mapped.first else { return path }
            path.move(to: first)
            for index in 1..<mapped.count {
                if curved.indices.contains(index - 1), curved[index - 1] {
                    let p0 = mapped[max(0, index - 2)]
                    let p1 = mapped[index - 1]
                    let p2 = mapped[index]
                    let p3 = mapped[min(mapped.count - 1, index + 1)]
                    let c1 = CGPoint(
                        x: p1.x + (p2.x - p0.x) / 6,
                        y: p1.y + (p2.y - p0.y) / 6
                    )
                    let c2 = CGPoint(
                        x: p2.x - (p3.x - p1.x) / 6,
                        y: p2.y - (p3.y - p1.y) / 6
                    )
                    path.addCurve(to: p2, control1: c1, control2: c2)
                } else {
                    path.addLine(to: mapped[index])
                }
            }
            return path
        case .container, .unknown:
            return Path(CGRect(origin: .zero, size: size))
        }
    }

    private func map(
        _ points: [HWPDocumentPoint],
        into size: CGSize
    ) -> [CGPoint] {
        guard let minX = points.map(\.x).min(),
              let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(),
              let maxY = points.map(\.y).max() else { return [] }
        let width = max(maxX - minX, 1)
        let height = max(maxY - minY, 1)
        return points.map {
            CGPoint(
                x: ($0.x - minX) / width * size.width,
                y: ($0.y - minY) / height * size.height
            )
        }
    }


    private func arrowEndpoints(in size: CGSize) -> (CGPoint, CGPoint)? {
        switch shape.geometry {
        case .line(let start, let end):
            let points = map([start, end], into: size)
            guard points.count == 2 else { return nil }
            return (points[0], points[1])
        case .curve(let points, _), .polygon(let points):
            let mapped = map(points, into: size)
            guard let first = mapped.first, let last = mapped.last else { return nil }
            return (first, last)
        default:
            return nil
        }
    }

    private func drawArrow(
        kind: Int,
        tip: CGPoint,
        toward other: CGPoint,
        context: inout GraphicsContext
    ) {
        guard kind > 0 else { return }
        let dx = other.x - tip.x
        let dy = other.y - tip.y
        let length = max(hypot(dx, dy), 0.001)
        let ux = dx / length
        let uy = dy / length
        let size = max(5, shape.stroke.widthPoints * 4.5)
        let base = CGPoint(x: tip.x + ux * size, y: tip.y + uy * size)
        let perpendicular = CGPoint(x: -uy * size * 0.48, y: ux * size * 0.48)
        let color = hwpColor(shape.stroke.colorRGB)
        var path = Path()
        switch kind {
        case 3:
            path.move(to: tip)
            path.addLine(to: CGPoint(x: base.x + perpendicular.x, y: base.y + perpendicular.y))
            path.addLine(to: CGPoint(x: tip.x + ux * size * 2, y: tip.y + uy * size * 2))
            path.addLine(to: CGPoint(x: base.x - perpendicular.x, y: base.y - perpendicular.y))
            path.closeSubpath()
            context.stroke(path, with: .color(color), lineWidth: shape.stroke.widthPoints)
        case 4:
            let radius = size * 0.55
            let circle = Path(
                ellipseIn: CGRect(
                    x: tip.x - radius,
                    y: tip.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            )
            context.stroke(circle, with: .color(color), lineWidth: shape.stroke.widthPoints)
        default:
            path.move(to: tip)
            path.addLine(to: CGPoint(x: base.x + perpendicular.x, y: base.y + perpendicular.y))
            if kind == 2 {
                path.addLine(to: CGPoint(x: tip.x + ux * size * 0.62, y: tip.y + uy * size * 0.62))
            }
            path.addLine(to: CGPoint(x: base.x - perpendicular.x, y: base.y - perpendicular.y))
            path.closeSubpath()
            context.fill(path, with: .color(color))
        }
    }
}

private struct HWPChartCanvasView: View {
    let chart: HWPDocumentChart
    private let palette: [UInt32] = [
        0x4E79A7, 0xF28E2B, 0xE15759, 0x76B7B2,
        0x59A14F, 0xEDC948, 0xB07AA1, 0xFF9DA7,
    ]

    var body: some View {
        if let preview = chart.previewImage,
           let image = UIImage(data: preview.data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else if let metafile = chart.previewMetafile,
                  HWPOriginalCanvasSceneBuilder.metafileHasDrawingRecords(metafile) {
            HWPMetafileCanvasView(metafile: metafile)
        } else if chart.hasRenderableData {
            VStack(spacing: 2) {
                if let title = chart.title {
                    Text(title).font(.caption.weight(.semibold)).lineLimit(1)
                }
                Canvas { context, size in
                    draw(context: &context, size: size)
                }
                .padding(5)
                if chart.series.count > 1 {
                    HStack(spacing: 8) {
                        ForEach(Array(chart.series.prefix(4).enumerated()), id: \.element.id) {
                            index, series in
                            Circle()
                                .fill(hwpColor(color(for: index, series: series)))
                                .frame(width: 6, height: 6)
                            Text(series.name)
                                .font(.system(size: 7))
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            .background(.white)
            .overlay { Rectangle().stroke(.gray.opacity(0.25), lineWidth: 0.5) }
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.08))
                .overlay {
                    Label("차트", systemImage: "chart.bar.xaxis")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
        }
    }

    private func draw(context: inout GraphicsContext, size: CGSize) {
        switch chart.kind {
        case .pie:
            drawPie(context: &context, size: size)
        case .radar:
            drawRadar(context: &context, size: size)
        case .area:
            drawLines(context: &context, size: size, fillsArea: true)
        case .line, .scatter:
            drawLines(context: &context, size: size, fillsArea: false)
        default:
            drawBars(context: &context, size: size)
        }
    }

    private func drawBars(context: inout GraphicsContext, size: CGSize) {
        let plot = CGRect(x: 26, y: 8, width: max(1, size.width - 34), height: max(1, size.height - 28))
        drawAxes(context: &context, plot: plot)
        let all = chart.series.flatMap(\.values)
        let minimum = min(all.min() ?? 0, 0)
        let maximum = max(all.max() ?? 1, 1)
        let span = max(maximum - minimum, 1)
        let zeroY = plot.maxY - plot.height * CGFloat((0 - minimum) / span)
        let groupCount = max(chart.categories.count, chart.series.map(\.values.count).max() ?? 1)
        let groupWidth = plot.width / CGFloat(max(groupCount, 1))
        let barWidth = groupWidth * 0.76 / CGFloat(max(chart.series.count, 1))
        for (seriesIndex, series) in chart.series.enumerated() {
            for (valueIndex, value) in series.values.enumerated() {
                let valueY = plot.maxY - plot.height * CGFloat((value - minimum) / span)
                let rect = CGRect(
                    x: plot.minX + CGFloat(valueIndex) * groupWidth
                        + CGFloat(seriesIndex) * barWidth + groupWidth * 0.12,
                    y: min(zeroY, valueY),
                    width: max(1, barWidth - 1),
                    height: max(0.5, abs(zeroY - valueY))
                )
                context.fill(
                    Path(rect),
                    with: .color(hwpColor(color(for: seriesIndex, series: series)))
                )
            }
        }
        drawCategoryLabels(context: &context, plot: plot, count: groupCount)
    }

    private func drawLines(
        context: inout GraphicsContext,
        size: CGSize,
        fillsArea: Bool
    ) {
        let plot = CGRect(x: 26, y: 8, width: max(1, size.width - 34), height: max(1, size.height - 28))
        drawAxes(context: &context, plot: plot)
        let all = chart.series.flatMap(\.values)
        let minimum = min(all.min() ?? 0, 0)
        let maximum = max(all.max() ?? 1, 1)
        let span = max(maximum - minimum, 1)
        let baselineY = plot.maxY - plot.height * CGFloat((0 - minimum) / span)
        for (seriesIndex, series) in chart.series.enumerated() {
            var path = Path()
            var points: [CGPoint] = []
            for (index, value) in series.values.enumerated() {
                let x = plot.minX + plot.width
                    * CGFloat(index) / CGFloat(max(series.values.count - 1, 1))
                let y = plot.maxY - plot.height * CGFloat((value - minimum) / span)
                let point = CGPoint(x: x, y: y)
                points.append(point)
                if index == 0 { path.move(to: point) }
                else { path.addLine(to: point) }
            }
            let seriesColor = hwpColor(color(for: seriesIndex, series: series))
            if fillsArea, let first = points.first, let last = points.last {
                var area = path
                area.addLine(to: CGPoint(x: last.x, y: baselineY))
                area.addLine(to: CGPoint(x: first.x, y: baselineY))
                area.closeSubpath()
                context.fill(area, with: .color(seriesColor.opacity(0.22)))
            }
            context.stroke(
                path,
                with: .color(seriesColor),
                lineWidth: 2
            )
            for point in points {
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - 1.8, y: point.y - 1.8, width: 3.6, height: 3.6)),
                    with: .color(seriesColor)
                )
            }
        }
        drawCategoryLabels(
            context: &context,
            plot: plot,
            count: max(chart.categories.count, chart.series.map(\.values.count).max() ?? 0)
        )
    }

    private func drawRadar(context: inout GraphicsContext, size: CGSize) {
        let count = max(
            chart.categories.count,
            chart.series.map(\.values.count).max() ?? 0
        )
        guard count >= 3 else {
            drawLines(context: &context, size: size, fillsArea: false)
            return
        }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = max(1, min(size.width, size.height) * 0.39)
        let maximum = max(chart.series.flatMap(\.values).max() ?? 1, 1)
        for index in 0..<count {
            let angle = -Double.pi / 2 + Double(index) * 2 * Double.pi / Double(count)
            var axis = Path()
            axis.move(to: center)
            axis.addLine(to: CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            ))
            context.stroke(axis, with: .color(.gray.opacity(0.35)), lineWidth: 0.5)
        }
        for (seriesIndex, series) in chart.series.enumerated() {
            var polygon = Path()
            for index in 0..<count {
                let value = series.values.indices.contains(index)
                    ? max(series.values[index], 0)
                    : 0
                let scaled = radius * CGFloat(value / maximum)
                let angle = -Double.pi / 2 + Double(index) * 2 * Double.pi / Double(count)
                let point = CGPoint(
                    x: center.x + cos(angle) * scaled,
                    y: center.y + sin(angle) * scaled
                )
                if index == 0 { polygon.move(to: point) }
                else { polygon.addLine(to: point) }
            }
            polygon.closeSubpath()
            let seriesColor = hwpColor(color(for: seriesIndex, series: series))
            context.fill(polygon, with: .color(seriesColor.opacity(0.16)))
            context.stroke(polygon, with: .color(seriesColor), lineWidth: 1.5)
        }
    }

    private func drawPie(context: inout GraphicsContext, size: CGSize) {
        guard let series = chart.series.first else { return }
        let positive = series.values.map { max($0, 0) }
        let total = positive.reduce(0, +)
        guard total > 0 else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = max(1, min(size.width, size.height) * 0.42)
        var start = -Double.pi / 2
        for (index, value) in positive.enumerated() {
            let end = start + 2 * Double.pi * value / total
            var path = Path()
            path.move(to: center)
            path.addArc(
                center: center,
                radius: radius,
                startAngle: .radians(start),
                endAngle: .radians(end),
                clockwise: false
            )
            path.closeSubpath()
            context.fill(path, with: .color(hwpColor(palette[index % palette.count])))
            start = end
        }
    }

    private func drawAxes(context: inout GraphicsContext, plot: CGRect) {
        for step in 1...4 {
            let y = plot.minY + plot.height * CGFloat(step) / 4
            var grid = Path()
            grid.move(to: CGPoint(x: plot.minX, y: y))
            grid.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.stroke(grid, with: .color(.gray.opacity(0.16)), lineWidth: 0.4)
        }
        var axes = Path()
        axes.move(to: CGPoint(x: plot.minX, y: plot.minY))
        axes.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
        axes.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
        context.stroke(axes, with: .color(.gray), lineWidth: 0.7)
    }

    private func drawCategoryLabels(
        context: inout GraphicsContext,
        plot: CGRect,
        count: Int
    ) {
        guard count > 0 else { return }
        let labels = chart.categories.isEmpty
            ? (0..<count).map { String($0 + 1) }
            : chart.categories
        let stride = max(1, Int(ceil(Double(count) / 8)))
        for index in Swift.stride(from: 0, to: min(count, labels.count), by: stride) {
            let x = plot.minX + plot.width
                * (CGFloat(index) + 0.5) / CGFloat(max(count, 1))
            context.draw(
                Text(labels[index]).font(.system(size: 6)).foregroundStyle(.gray),
                at: CGPoint(x: x, y: plot.maxY + 7),
                anchor: .center
            )
        }
    }

    private func color(
        for index: Int,
        series: HWPDocumentChartSeries
    ) -> UInt32 {
        series.colorRGB ?? palette[index % palette.count]
    }
}

private struct HWPStyledRunsText: View {
    let text: String
    let runs: [HWPDocumentTextRun]
    let fallbackSize: Double

    var body: some View {
        if runs.isEmpty {
            Text(text).font(.system(size: fallbackSize))
        } else {
            runs.reduce(Text("")) { partial, run in
                partial + styled(run)
            }
        }
    }

    private func styled(_ run: HWPDocumentTextRun) -> Text {
        var output = Text(run.text)
        let size = CGFloat(run.fontSizePoints ?? fallbackSize)
        if let name = HWPDocumentFontResolver.resolution(for: run).resolvedName {
            output = output.font(.custom(name, size: size))
        } else {
            output = output.font(.system(size: size))
        }
        let kern = size * CGFloat(run.letterSpacingPercent) / 100
        if kern != 0 { output = output.kerning(kern) }
        if run.isBold { output = output.bold() }
        if run.isItalic { output = output.italic() }
        if run.isUnderlined { output = output.underline() }
        if run.isStruckThrough { output = output.strikethrough() }
        var baseline = size * CGFloat(run.baselinePositionPercent) / 100
        if run.isSuperscript { baseline += size * 0.32 }
        if run.isSubscript { baseline -= size * 0.22 }
        if baseline != 0 { output = output.baselineOffset(baseline) }
        if let color = run.textColorRGB {
            output = output.foregroundColor(hwpColor(color))
        }
        return output
    }
}

private struct HWPParagraphBorderView: View {
    let block: HWPDocumentBlock

    var body: some View {
        if let border = block.presentation.paragraphBorder,
           let first = block.lineLayouts.first, let last = block.lineLayouts.last {
            HWPBoxBackgroundView(style: border.style)
                .overlay { HWPPageBorderOverlay(style: border.style) }
                .frame(width: max(1, first.widthPoints + border.left + border.right),
                    height: max(1, last.verticalPositionPoints + last.lineHeightPoints
                        - first.verticalPositionPoints + border.top + border.bottom))
                .offset(x: first.columnStartPoints - border.left,
                    y: first.verticalPositionPoints - border.top)
                .allowsHitTesting(false)
        }
    }
}

private struct HWPPageBorderOverlay: View {
    let style: HWPDocumentBoxStyle

    var body: some View {
        Canvas { context, size in
            let edges: [(HWPDocumentBorderLine, CGPoint, CGPoint)] = [
                (style.top, .zero, CGPoint(x: size.width, y: 0)),
                (style.bottom, CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height)),
                (style.left, .zero, CGPoint(x: 0, y: size.height)),
                (style.right, CGPoint(x: size.width, y: 0), CGPoint(x: size.width, y: size.height)),
            ]
            // A full-size canvas keeps sub-point dotted edges from being
            // discarded when SwiftUI rounds a narrow child view's bounds.
            for (line, start, end) in edges where line.isVisible {
                let width = max(0.1, line.widthPoints)
                var path = Path()
                if start.y == end.y {
                    let y = start.y == 0 ? width / 2 : size.height - width / 2
                    path.move(to: CGPoint(x: start.x, y: y))
                    path.addLine(to: CGPoint(x: end.x, y: y))
                } else {
                    let x = start.x == 0 ? width / 2 : size.width - width / 2
                    path.move(to: CGPoint(x: x, y: start.y))
                    path.addLine(to: CGPoint(x: x, y: end.y))
                }
                context.stroke(path, with: .color(hwpColor(line.colorRGB)),
                    style: StrokeStyle(lineWidth: width,
                        lineCap: [3, 7].contains(line.kind) ? .round : .butt,
                        dash: HWPStrokePattern.dashes(kind: Int(line.kind), width: width)))
            }
        }
        .allowsHitTesting(false)
    }
}

enum HWPStrokePattern {
    static func dashes(kind: Int, width: CGFloat) -> [CGFloat] {
        let w = max(width, 0.1)
        switch kind {
        case 2: return [6 * w, 3 * w]
        // A zero-length segment with round caps draws a dot. Preserve a
        // visible gap at normal iPad zoom instead of averaging into a line.
        case 3: return [0, max(3 * w, 1.5)]
        case 4: return [6 * w, 2 * w, w, 2 * w]
        case 5: return [6 * w, 2 * w, w, 2 * w, w, 2 * w]
        case 6: return [10 * w, 3 * w]
        case 7: return [0, max(2 * w, 2)]
        default: return []
        }
    }
}

private func textAlignment(_ alignment: HWPParagraphAlignment) -> TextAlignment {
    switch alignment {
    case .trailing: return .trailing
    case .centered: return .center
    default: return .leading
    }
}

/// Paints a chart's WMF preview from the engine's playback (`HWPMetafilePlayback`, shared with
/// Android): filled and stroked paths, then text lines, over white.
struct HWPMetafileCanvasView: View {
    let metafile: HWPDocumentMetafile

    var body: some View {
        Canvas { context, size in
            for item in HWPMetafilePlayback.items(metafile, width: size.width, height: size.height) {
                switch item.type {
                case "path":
                    guard let commands = item.path else { continue }
                    let path = hwpMetafilePath(commands)
                    if let fill = item.fill {
                        context.fill(path, with: .color(hwpColor(fill)))
                    }
                    if let stroke = item.stroke, let width = item.strokeWidth {
                        context.stroke(path, with: .color(hwpColor(stroke)), style: StrokeStyle(lineWidth: width))
                    }
                case "text":
                    guard let text = item.text ?? item.bytes.map({ hwpMetafileText(hex: $0, charset: item.charset) }),
                          !text.isEmpty, let size = item.size, size > 0 else { continue }
                    var font = Font.system(size: size, weight: item.bold == true ? .bold : .regular)
                    if item.italic == true { font = font.italic() }
                    context.draw(
                        Text(text).font(font).foregroundStyle(hwpColor(item.color ?? 0)),
                        at: CGPoint(x: item.x ?? 0, y: item.y ?? 0),
                        anchor: .topLeading
                    )
                default:
                    continue
                }
            }
        }
        .background(.white)
    }
}

private func hwpMetafilePath(_ commands: [HWPCanvasPathCommand]) -> Path {
    // The engine writes a Rectangle record as an axis-aligned closed outline. Draw it as a
    // rectangle so its corners antialias the way the rectangle path always has.
    if commands.map(\.op) == ["M", "L", "L", "L", "Z"], commands.prefix(4).allSatisfy({ $0.values.count >= 2 }) {
        let p = commands.prefix(4).map { CGPoint(x: $0.values[0], y: $0.values[1]) }
        if p[0].y == p[1].y, p[1].x == p[2].x, p[2].y == p[3].y, p[3].x == p[0].x {
            return Path(CGRect(x: p[0].x, y: p[0].y, width: p[2].x - p[0].x, height: p[2].y - p[0].y))
        }
    }
    var path = Path()
    for command in commands {
        let values = command.values
        func point() -> CGPoint {
            CGPoint(x: values.indices.contains(0) ? values[0] : 0, y: values.indices.contains(1) ? values[1] : 0)
        }
        switch command.op {
        case "M": path.move(to: point())
        case "L": path.addLine(to: point())
        case "Z": path.closeSubpath()
        default: break
        }
    }
    return path
}

/// A metafile string the engine left as hex bytes in a Windows charset: that charset's code
/// page (Shift_JIS, CP949, GBK, Big5, Windows-1251), else Windows-1252, else ISO 8859-1.
func hwpMetafileText(hex: String, charset: Int?) -> String {
    var bytes: [UInt8] = []
    bytes.reserveCapacity(hex.utf8.count / 2)
    var index = hex.startIndex
    while let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) {
        guard let byte = UInt8(hex[index..<next], radix: 16) else { break }
        bytes.append(byte)
        index = next
    }
    let data = Data(bytes)
    for encoding in charset.map(hwpMetafileEncodings) ?? [] {
        if let text = String(data: data, encoding: encoding) { return text }
    }
    return String(data: data, encoding: .windowsCP1252)
        ?? String(data: data, encoding: .isoLatin1)
        ?? ""
}

/// The code pages for a Windows font charset, the first that decodes wins (GBK: Foundation's
/// GBK_95 does not decode on iOS, so GB 18030 and CP936 follow, as Android's GBK does).
private func hwpMetafileEncodings(_ charset: Int) -> [String.Encoding] {
    let values: [UInt32]
    switch charset {
    case 128: return [.shiftJIS]
    case 129: values = [0x0422] // Windows CP949 / Unified Hangul Code
    case 134: values = [0x0631, 0x0632, 0x0421] // GBK, GB 18030, CP936
    case 136: values = [0x0A03] // Big5
    case 204: values = [0x0502] // Windows Cyrillic
    default: return []
    }
    return values.map { String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding($0))) }
}

private func frameAlignment(_ alignment: HWPParagraphAlignment) -> Alignment {
    switch alignment {
    case .trailing: return .trailing
    case .centered: return .center
    default: return .leading
    }
}

private func hwpColor(_ rgb: UInt32) -> Color {
    Color(
        red: Double((rgb >> 16) & 0xFF) / 255,
        green: Double((rgb >> 8) & 0xFF) / 255,
        blue: Double(rgb & 0xFF) / 255
    )
}
