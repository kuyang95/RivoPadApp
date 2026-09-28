import SwiftUI
import UIKit

nonisolated struct HWPShapeObjectEditingContext: Sendable {
    var selectedID: String?
    var groupedSelectionIDs: Set<String> = []
    var isSelectingGroup = false
    var onSelect: @MainActor @Sendable (String, HWPDocumentCanvasObject) -> Void = { _, _ in }
    var onSelectChild: @MainActor @Sendable (String, HWPDocumentCanvasObject, Int) -> Void = { _, _, _ in }
    var onDirectManipulation: @MainActor @Sendable (
        String, HWPDocumentCanvasObject, HWPShapeEditing.DirectManipulation
    ) -> Void = { _, _, _ in }
}

struct HWPShapeKeyboardNudgeReceiver: UIViewRepresentable {
    let isActive: Bool
    let onNudge: @MainActor @Sendable (Double, Double) -> Void

    func makeUIView(context: Context) -> ArrowKeyView {
        let view = ArrowKeyView()
        view.isHidden = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: ArrowKeyView, context: Context) {
        view.onNudge = onNudge
        guard isActive else {
            if view.isFirstResponder { view.resignFirstResponder() }
            return
        }
        DispatchQueue.main.async { [weak view] in
            guard let view, view.window != nil, !view.isFirstResponder else { return }
            view.becomeFirstResponder()
        }
    }

    final class ArrowKeyView: UIView {
        var onNudge: (@MainActor @Sendable (Double, Double) -> Void)?

        override var canBecomeFirstResponder: Bool { true }

        override var keyCommands: [UIKeyCommand]? {
            let inputs = [
                UIKeyCommand.inputLeftArrow,
                UIKeyCommand.inputRightArrow,
                UIKeyCommand.inputUpArrow,
                UIKeyCommand.inputDownArrow
            ]
            return inputs.flatMap { input in
                [command(input: input, modifiers: []),
                 command(input: input, modifiers: .shift)]
            }
        }

        private func command(input: String,
                             modifiers: UIKeyModifierFlags) -> UIKeyCommand {
            let command = UIKeyCommand(input: input, modifierFlags: modifiers,
                action: #selector(handleArrowKey(_:)))
            command.wantsPriorityOverSystemBehavior = true
            return command
        }

        @objc private func handleArrowKey(_ command: UIKeyCommand) {
            let distance = command.modifierFlags.contains(.shift) ? 10.0 : 1.0
            let delta: (Double, Double)
            switch command.input {
            case UIKeyCommand.inputLeftArrow: delta = (-distance, 0)
            case UIKeyCommand.inputRightArrow: delta = (distance, 0)
            case UIKeyCommand.inputUpArrow: delta = (0, -distance)
            case UIKeyCommand.inputDownArrow: delta = (0, distance)
            default: return
            }
            onNudge?(delta.0, delta.1)
        }
    }
}

struct HWPShapeGroupingControl: View {
    let isSelecting: Bool
    let selectionCount: Int
    let enabled: Bool
    let onStart: () -> Void
    let onApply: () -> Void
    let onArrange: (HWPShapeEditing.Arrangement) -> Void
    let onMatchSize: (HWPShapeEditing.SizeMatch) -> Void
    let onFlip: (HWPShapeEditing.Flip) -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        if isSelecting {
            HStack(spacing: 4) {
                Button(action: onApply) {
                    Label("그룹 \(selectionCount)", systemImage: "square.3.layers.3d")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .disabled(selectionCount < 2)
                .accessibilityIdentifier("hwp-shape-group-apply")
                Menu {
                    Section("가로 정렬") {
                        ForEach([HWPShapeEditing.Arrangement.alignLeft, .alignCenter, .alignRight]) { action in
                            Button { onArrange(action) } label: {
                                Label(action.title, systemImage: action.systemImage)
                            }
                            .disabled(selectionCount < action.minimumSelectionCount)
                        }
                    }
                    Section("세로 정렬") {
                        ForEach([HWPShapeEditing.Arrangement.alignTop, .alignMiddle, .alignBottom]) { action in
                            Button { onArrange(action) } label: {
                                Label(action.title, systemImage: action.systemImage)
                            }
                            .disabled(selectionCount < action.minimumSelectionCount)
                        }
                    }
                    Section("맞쪽 정렬") {
                        ForEach([HWPShapeEditing.Arrangement.alignInside, .alignOutside]) { action in
                            Button { onArrange(action) } label: {
                                Label(action.title, systemImage: action.systemImage)
                            }
                        }
                    }
                    Section("간격") {
                        ForEach([HWPShapeEditing.Arrangement.distributeHorizontally,
                                 .distributeVertically]) { action in
                            Button { onArrange(action) } label: {
                                Label(action.title, systemImage: action.systemImage)
                            }
                            .disabled(selectionCount < action.minimumSelectionCount)
                        }
                    }
                } label: {
                    Label("맞춤", systemImage: "align.horizontal.left")
                        .frame(minHeight: 44)
                }
                .disabled(selectionCount < 1)
                .accessibilityIdentifier("hwp-shape-arrange")
                Menu {
                    ForEach(HWPShapeEditing.SizeMatch.allCases) { action in
                        Button { onMatchSize(action) } label: {
                            Label(action.title, systemImage: action.systemImage)
                        }
                    }
                } label: {
                    Label("크기", systemImage: "arrow.up.left.and.arrow.down.right")
                        .frame(minHeight: 44)
                }
                .disabled(selectionCount < 2)
                .accessibilityIdentifier("hwp-shape-size-match")
                Menu {
                    ForEach(HWPShapeEditing.Flip.allCases) { action in
                        Button { onFlip(action) } label: {
                            Label(action.title, systemImage: action.systemImage)
                        }
                    }
                } label: {
                    Label("뒤집기", systemImage: "arrow.left.and.right")
                        .frame(minHeight: 44)
                }
                .disabled(selectionCount < 1)
                .accessibilityIdentifier("hwp-shape-flip")
                Menu {
                    Button(action: onDuplicate) {
                        Label("선택 도형 복제", systemImage: "plus.square.on.square")
                    }
                    Button(role: .destructive, action: onDelete) {
                        Label("선택 도형 삭제", systemImage: "trash")
                    }
                } label: {
                    Label("작업", systemImage: "ellipsis.circle")
                        .frame(minHeight: 44)
                }
                .disabled(selectionCount < 2)
                .accessibilityIdentifier("hwp-shape-batch-actions")
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .frame(minWidth: 34, minHeight: 44)
                }
                .accessibilityLabel("그룹 선택 취소")
            }
            .buttonStyle(.plain)
        } else {
            Button(action: onStart) {
                Label("선택", systemImage: "square.dashed")
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .accessibilityLabel("도형 선택")
            .accessibilityIdentifier("hwp-shape-group-select")
        }
    }
}

private struct HWPShapeObjectEditingKey: EnvironmentKey {
    static let defaultValue = HWPShapeObjectEditingContext()
}

extension EnvironmentValues {
    var hwpShapeObjectEditing: HWPShapeObjectEditingContext {
        get { self[HWPShapeObjectEditingKey.self] }
        set { self[HWPShapeObjectEditingKey.self] = newValue }
    }
}

struct HWPShapeInsertionButton: View {
    let enabled: Bool
    let selection: () -> HWPShapeEditing.Selection?
    let restoreFocus: () -> Void
    let onApply: (HWPShapeEditing.Request) -> Void

    var body: some View {
        Menu {
            ForEach(HWPShapeEditing.Kind.allCases) { kind in
                Button {
                    guard let value = selection() else { restoreFocus(); return }
                    let width = min(max(value.width * 0.32, 90), 180)
                    let height = kind == .line ? 48 : width * 0.6
                    onApply(.init(selection: value, kind: kind,
                        widthPoints: width, heightPoints: height))
                } label: {
                    Label(kind.title, systemImage: kind.systemImage)
                }
            }
        } label: {
            Label("도형", systemImage: "square.on.circle")
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel("도형 삽입")
        .accessibilityIdentifier("hwp-shape-insert")
    }
}

struct HWPShapeEditingSheet: View {
    let target: HWPShapeEditing.Target
    let onUpdate: (HWPShapeEditing.Layout) -> Void
    let onDelete: () -> Void
    let onMoveGroupChild: (Int) -> Void
    let onUngroup: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var x = ""
    @State private var y = ""
    @State private var width = ""
    @State private var height = ""
    @State private var zOrder = 0
    @State private var rotation = 0.0
    @State private var flipHorizontal = false
    @State private var flipVertical = false
    @State private var strokeColor: UInt32 = 0
    @State private var strokeWidth = 1.0
    @State private var strokeStyle = 1
    @State private var hasFill = true
    @State private var fillColor: UInt32 = 0xFFFFFF
    @State private var hasShadow = false
    @State private var shadowColor: UInt32 = 0
    @State private var shadowX = 3.0
    @State private var shadowY = 3.0
    @State private var shadowOpacity = 0.5
    @State private var isInline = true
    @State private var horizontalReference = HWPDocumentLayoutReference.paragraph
    @State private var verticalReference = HWPDocumentLayoutReference.paragraph
    @State private var horizontalAlignment = HWPDocumentRelativeAlignment.start
    @State private var verticalAlignment = HWPDocumentRelativeAlignment.start
    @State private var wrap = HWPDocumentObjectWrap.topAndBottom
    @State private var marginLeft = "0"
    @State private var marginRight = "0"
    @State private var marginTop = "0"
    @State private var marginBottom = "0"
    @State private var pathPoints: [HWPShapeEditing.PathPoint] = []
    @State private var startArrow = 0
    @State private var endArrow = 0

    private func number(_ value: String) -> Double? {
        Double(value.replacingOccurrences(of: ",", with: "."))
    }

    private var layout: HWPShapeEditing.Layout? {
        guard let x = number(x), let y = number(y), let width = number(width), let height = number(height),
              let left = number(marginLeft), let right = number(marginRight),
              let top = number(marginTop), let bottom = number(marginBottom) else {
            return nil
        }
        let value = HWPShapeEditing.Layout(xPoints: x, yPoints: y,
            widthPoints: width, heightPoints: height, zOrder: zOrder,
            rotationDegrees: rotation, flipHorizontal: flipHorizontal,
            flipVertical: flipVertical, strokeColorRGB: strokeColor,
            strokeWidthPoints: strokeWidth, strokeStyle: strokeStyle,
            fillColorRGB: target.kind == .line || target.kind == .connector || !hasFill ? nil : fillColor,
            shadow: hasShadow ? .init(colorRGB: shadowColor, offsetX: shadowX,
                offsetY: shadowY, opacity: shadowOpacity) : nil,
            isInline: isInline, horizontalReference: horizontalReference,
            verticalReference: verticalReference, horizontalAlignment: horizontalAlignment,
            verticalAlignment: verticalAlignment, wrap: isInline ? .topAndBottom : wrap,
            marginLeftPoints: left, marginRightPoints: right,
            marginTopPoints: top, marginBottomPoints: bottom,
            pathPoints: pathPoints, startArrow: startArrow, endArrow: endArrow)
        return value.isValid ? value : nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("위치") {
                    valueRow("가로 X", text: $x)
                    valueRow("세로 Y", text: $y)
                    HStack {
                        Button { step(x: -5, y: 0) } label: { Label("왼쪽", systemImage: "arrow.left") }
                        Spacer()
                        Button { step(x: 0, y: -5) } label: { Label("위", systemImage: "arrow.up") }
                        Spacer()
                        Button { step(x: 0, y: 5) } label: { Label("아래", systemImage: "arrow.down") }
                        Spacer()
                        Button { step(x: 5, y: 0) } label: { Label("오른쪽", systemImage: "arrow.right") }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .accessibilityElement(children: .contain)
                }
                Section("크기") {
                    valueRow("너비", text: $width)
                    valueRow("높이", text: $height)
                }
                Section("회전") {
                    HStack {
                        Slider(value: $rotation, in: 0...359, step: 1)
                            .accessibilityIdentifier("hwp-shape-rotation")
                        Text("\(Int(rotation))°").monospacedDigit().frame(width: 48, alignment: .trailing)
                    }
                }
                Section("뒤집기") {
                    Toggle("좌우 뒤집기", isOn: $flipHorizontal)
                        .accessibilityIdentifier("hwp-shape-flip-horizontal")
                    Toggle("상하 뒤집기", isOn: $flipVertical)
                        .accessibilityIdentifier("hwp-shape-flip-vertical")
                }
                if !target.isGroupChild {
                Section("글 배치") {
                    Toggle("글자처럼 취급", isOn: $isInline)
                    if !isInline {
                        Picker("본문과의 배치", selection: $wrap) {
                            Text("글 둘레").tag(HWPDocumentObjectWrap.square)
                            Text("위아래").tag(HWPDocumentObjectWrap.topAndBottom)
                            Text("글 뒤").tag(HWPDocumentObjectWrap.behindText)
                            Text("글 앞").tag(HWPDocumentObjectWrap.inFrontOfText)
                        }
                        Picker("가로 기준", selection: $horizontalReference) {
                            Text("종이").tag(HWPDocumentLayoutReference.paper)
                            Text("쪽").tag(HWPDocumentLayoutReference.page)
                            Text("단").tag(HWPDocumentLayoutReference.column)
                            Text("문단").tag(HWPDocumentLayoutReference.paragraph)
                        }
                        Picker("가로 정렬", selection: $horizontalAlignment) {
                            Text("왼쪽").tag(HWPDocumentRelativeAlignment.start)
                            Text("가운데").tag(HWPDocumentRelativeAlignment.center)
                            Text("오른쪽").tag(HWPDocumentRelativeAlignment.end)
                            Text("맞쪽 안쪽").tag(HWPDocumentRelativeAlignment.inside)
                            Text("맞쪽 바깥쪽").tag(HWPDocumentRelativeAlignment.outside)
                        }
                        Picker("세로 기준", selection: $verticalReference) {
                            Text("종이").tag(HWPDocumentLayoutReference.paper)
                            Text("쪽").tag(HWPDocumentLayoutReference.page)
                            Text("문단").tag(HWPDocumentLayoutReference.paragraph)
                        }
                        Picker("세로 정렬", selection: $verticalAlignment) {
                            Text("위").tag(HWPDocumentRelativeAlignment.start)
                            Text("가운데").tag(HWPDocumentRelativeAlignment.center)
                            Text("아래").tag(HWPDocumentRelativeAlignment.end)
                        }
                    }
                }
                }
                Section("바깥 여백") {
                    valueRow("왼쪽", text: $marginLeft)
                    valueRow("오른쪽", text: $marginRight)
                    valueRow("위", text: $marginTop)
                    valueRow("아래", text: $marginBottom)
                }
                if !target.isGroup {
                if target.kind == .polygon || target.kind == .connector {
                    Section(target.kind == .polygon ? "꼭짓점" : "연결점") {
                        HWPShapePathPointEditor(points: $pathPoints,
                            closed: target.kind == .polygon)
                            .frame(height: 190)
                            .accessibilityIdentifier("hwp-shape-path-editor")
                        HStack {
                            Button {
                                addPathPoint()
                            } label: { Label("점 추가", systemImage: "plus.circle") }
                            Spacer()
                            Text("\(pathPoints.count)개").foregroundStyle(.secondary)
                            Spacer()
                            Button(role: .destructive) {
                                removePathPoint()
                            } label: { Label("마지막 점 삭제", systemImage: "minus.circle") }
                            .disabled(pathPoints.count <= (target.kind == .polygon ? 3 : 2))
                        }
                        Text("점을 끌어서 모양을 바꿀 수 있습니다.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("선") {
                    ColorPicker("선 색", selection: rgbBinding($strokeColor), supportsOpacity: false)
                    HStack {
                        Text("굵기")
                        Slider(value: $strokeWidth, in: 0.1...12, step: 0.1)
                            .accessibilityIdentifier("hwp-shape-stroke-width")
                        Text(String(format: "%.1f pt", strokeWidth)).monospacedDigit().frame(width: 58)
                    }
                    Picker("선 종류", selection: $strokeStyle) {
                        Text("실선").tag(1)
                        Text("파선").tag(2)
                        Text("점선").tag(3)
                        Text("일점쇄선").tag(4)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("hwp-shape-stroke-style")
                    if target.kind == .connector {
                        Picker("시작 화살표", selection: $startArrow) {
                            arrowChoices
                        }
                        Picker("끝 화살표", selection: $endArrow) {
                            arrowChoices
                        }
                    }
                }
                if target.kind != .line && target.kind != .connector {
                    Section("채우기") {
                        Toggle("채우기 사용", isOn: $hasFill)
                            .accessibilityIdentifier("hwp-shape-fill-enabled")
                        if hasFill {
                            ColorPicker("채우기 색", selection: rgbBinding($fillColor), supportsOpacity: false)
                        }
                    }
                }
                Section("그림자") {
                    Toggle("그림자 사용", isOn: $hasShadow)
                        .accessibilityIdentifier("hwp-shape-shadow-enabled")
                    if hasShadow {
                        ColorPicker("그림자 색", selection: rgbBinding($shadowColor), supportsOpacity: false)
                        HStack {
                            Text("가로 이동")
                            Slider(value: $shadowX, in: -20...20, step: 1)
                                .accessibilityIdentifier("hwp-shape-shadow-x")
                            Text("\(Int(shadowX)) pt").monospacedDigit().frame(width: 48)
                        }
                        HStack {
                            Text("세로 이동")
                            Slider(value: $shadowY, in: -20...20, step: 1)
                                .accessibilityIdentifier("hwp-shape-shadow-y")
                            Text("\(Int(shadowY)) pt").monospacedDigit().frame(width: 48)
                        }
                        HStack {
                            Text("농도")
                            Slider(value: $shadowOpacity, in: 0...1, step: 0.05)
                                .accessibilityIdentifier("hwp-shape-shadow-opacity")
                            Text("\(Int((shadowOpacity * 100).rounded()))%").monospacedDigit().frame(width: 44)
                        }
                    }
                }
                }
                if !target.isGroupChild {
                Section("배치 순서") {
                    HStack {
                        Button { zOrder -= 1 } label: { Label("뒤로 보내기", systemImage: "square.2.layers.3d.bottom.filled") }
                            .accessibilityIdentifier("hwp-shape-send-backward")
                        Spacer()
                        Text("\(zOrder)").foregroundStyle(.secondary).monospacedDigit()
                            .accessibilityIdentifier("hwp-shape-z-order-value")
                        Spacer()
                        Button { zOrder += 1 } label: { Label("앞으로 가져오기", systemImage: "square.2.layers.3d.top.filled") }
                            .accessibilityIdentifier("hwp-shape-bring-forward")
                    }
                    .buttonStyle(.bordered)
                }
                }
                if target.isGroupChild {
                    Section("그룹 안 순서") {
                        HStack {
                            Button {
                                dismiss()
                                onMoveGroupChild(-1)
                            } label: {
                                Label("뒤로 보내기", systemImage: "square.2.layers.3d.bottom.filled")
                            }
                            .disabled(!target.canMoveGroupChildBackward)
                            Spacer()
                            Text("\((target.groupChildIndex ?? 0) + 1) / \(target.groupChildCount)")
                                .foregroundStyle(.secondary).monospacedDigit()
                            Spacer()
                            Button {
                                dismiss()
                                onMoveGroupChild(1)
                            } label: {
                                Label("앞으로 가져오기", systemImage: "square.2.layers.3d.top.filled")
                            }
                            .disabled(!target.canMoveGroupChildForward)
                        }
                        .buttonStyle(.bordered)
                    }
                    Section {
                        Text("그룹 안 좌표를 기준으로 이 도형만 바꿉니다. 순서 변경은 겹친 내부 도형의 표시 순서에 반영됩니다.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    if target.isGroup {
                        Button("그룹 해제") {
                            dismiss()
                            onUngroup()
                        }
                    } else {
                        Button("\(target.title) 삭제", role: .destructive) {
                            dismiss()
                            onDelete()
                        }
                        .disabled(target.isGroupChild && !target.canDeleteGroupChild)
                        if target.isGroupChild && !target.canDeleteGroupChild {
                            Text("그룹에는 도형을 한 개 이상 남겨야 합니다. 마지막 도형은 그룹 해제 후 삭제할 수 있습니다.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("\(target.title) 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("적용") {
                        guard let layout else { return }
                        dismiss()
                        onUpdate(layout)
                    }
                    .disabled(layout == nil)
                    .accessibilityIdentifier("hwp-shape-apply")
                }
            }
            .onAppear {
                x = formatted(target.xPoints); y = formatted(target.yPoints)
                width = formatted(target.widthPoints); height = formatted(target.heightPoints)
                zOrder = target.zOrder
                rotation = min(max(target.rotationDegrees, 0), 359)
                flipHorizontal = target.flipHorizontal
                flipVertical = target.flipVertical
                strokeColor = target.strokeColorRGB
                strokeWidth = min(max(target.strokeWidthPoints, 0.1), 12)
                strokeStyle = (1...4).contains(target.strokeStyle) ? target.strokeStyle : 1
                hasFill = target.fillColorRGB != nil
                fillColor = target.fillColorRGB ?? 0xFFFFFF
                hasShadow = target.shadow != nil
                shadowColor = target.shadow?.colorRGB ?? 0
                shadowX = target.shadow?.offsetX ?? 3
                shadowY = target.shadow?.offsetY ?? 3
                shadowOpacity = target.shadow?.opacity ?? 0.5
                isInline = target.isInline
                horizontalReference = target.horizontalReference
                verticalReference = target.verticalReference == .column ? .paragraph : target.verticalReference
                horizontalAlignment = [.start, .center, .end].contains(target.horizontalAlignment)
                    ? target.horizontalAlignment : .start
                verticalAlignment = [.start, .center, .end].contains(target.verticalAlignment)
                    ? target.verticalAlignment : .start
                wrap = target.isInline ? .topAndBottom : target.wrap
                marginLeft = formatted(target.marginLeftPoints)
                marginRight = formatted(target.marginRightPoints)
                marginTop = formatted(target.marginTopPoints)
                marginBottom = formatted(target.marginBottomPoints)
                pathPoints = target.pathPoints.isEmpty ? (target.kind?.defaultPathPoints ?? []) : target.pathPoints
                startArrow = target.startArrow
                endArrow = target.endArrow
            }
        }
    }

    private func valueRow(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, text: text)
                .multilineTextAlignment(.trailing)
                .keyboardType(.numbersAndPunctuation)
                .frame(width: 110)
                .accessibilityIdentifier(fieldIdentifier(title))
            Text("pt").foregroundStyle(.secondary)
        }
    }

    private func fieldIdentifier(_ title: String) -> String {
        switch title {
        case "가로 X": "hwp-shape-x"
        case "세로 Y": "hwp-shape-y"
        case "너비": "hwp-shape-width"
        case "높이": "hwp-shape-height"
        case "왼쪽": "hwp-shape-margin-left"
        case "오른쪽": "hwp-shape-margin-right"
        case "위": "hwp-shape-margin-top"
        case "아래": "hwp-shape-margin-bottom"
        default: "hwp-shape-field"
        }
    }

    private func step(x dx: Double, y dy: Double) {
        x = formatted((number(x) ?? target.xPoints) + dx)
        y = formatted((number(y) ?? target.yPoints) + dy)
    }

    @ViewBuilder private var arrowChoices: some View {
        Text("없음").tag(0)
        Text("화살표").tag(1)
        Text("창 모양").tag(2)
        Text("오목 화살표").tag(3)
        Text("빈 마름모").tag(4)
        Text("빈 원").tag(5)
        Text("빈 사각형").tag(6)
    }

    private func addPathPoint() {
        guard pathPoints.count < 32 else { return }
        let end = pathPoints.last ?? .init(x: 1, y: 1)
        let previous = pathPoints.dropLast().last ?? .init(x: 0, y: 0)
        pathPoints.insert(.init(x: (previous.x + end.x) / 2, y: (previous.y + end.y) / 2),
            at: max(pathPoints.count - 1, 0))
    }

    private func removePathPoint() {
        let minimum = target.kind == .polygon ? 3 : 2
        guard pathPoints.count > minimum else { return }
        pathPoints.remove(at: max(pathPoints.count - 2, 0))
    }

    private func formatted(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    private func rgbBinding(_ value: Binding<UInt32>) -> Binding<Color> {
        Binding(get: {
            let rgb = value.wrappedValue
            return Color(red: Double((rgb >> 16) & 0xFF) / 255,
                green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
        }, set: { newValue in
            let color = UIColor(newValue)
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
            value.wrappedValue = UInt32((red * 255).rounded()) << 16
                | UInt32((green * 255).rounded()) << 8 | UInt32((blue * 255).rounded())
        })
    }
}

private struct HWPShapePathPointEditor: View {
    @Binding var points: [HWPShapeEditing.PathPoint]
    let closed: Bool
    private let handleInset: CGFloat = 14

    private func position(for point: HWPShapeEditing.PathPoint, in size: CGSize) -> CGPoint {
        let drawableWidth = max(size.width - handleInset * 2, 1)
        let drawableHeight = max(size.height - handleInset * 2, 1)
        return CGPoint(x: handleInset + point.x * drawableWidth,
            y: handleInset + point.y * drawableHeight)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(uiColor: .secondarySystemBackground))
                Canvas { context, size in
                    guard let first = points.first else { return }
                    var path = Path()
                    path.move(to: position(for: first, in: size))
                    for point in points.dropFirst() {
                        path.addLine(to: position(for: point, in: size))
                    }
                    if closed { path.closeSubpath() }
                    if closed { context.fill(path, with: .color(.accentColor.opacity(0.15))) }
                    context.stroke(path, with: .color(.accentColor), lineWidth: 2)
                }
                ForEach(points.indices, id: \.self) { index in
                    Circle()
                        .fill(index == 0 ? Color.orange : Color.accentColor)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .frame(width: 24, height: 24)
                        .position(position(for: points[index], in: proxy.size))
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("shapePath"))
                            .onChanged { value in
                                let drawableWidth = proxy.size.width - handleInset * 2
                                let drawableHeight = proxy.size.height - handleInset * 2
                                guard drawableWidth > 0, drawableHeight > 0,
                                      points.indices.contains(index) else { return }
                                points[index] = .init(
                                    x: (value.location.x - handleInset) / drawableWidth,
                                    y: (value.location.y - handleInset) / drawableHeight)
                            })
                        .accessibilityLabel("점 \(index + 1)")
                }
            }
            .coordinateSpace(name: "shapePath")
        }
    }
}
