import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

nonisolated struct HWPImageObjectEditingContext: Sendable {
    var selectedID: String?
    var onSelect: @MainActor @Sendable (String, HWPDocumentCanvasObject) -> Void = { _, _ in }
    var onDirectManipulation: @MainActor @Sendable (
        String, HWPDocumentCanvasObject, HWPImageEditing.DirectManipulation
    ) -> Void = { _, _, _ in }
}

private struct HWPImageObjectEditingKey: EnvironmentKey {
    static let defaultValue = HWPImageObjectEditingContext()
}

extension EnvironmentValues {
    var hwpImageObjectEditing: HWPImageObjectEditingContext {
        get { self[HWPImageObjectEditingKey.self] }
        set { self[HWPImageObjectEditingKey.self] = newValue }
    }
}

struct HWPImageInsertionButton: View {
    let enabled: Bool
    let selection: () -> HWPImageEditing.Selection?
    let restoreFocus: () -> Void
    let onApply: (HWPImageEditing.Request) -> Void
    let onError: (String) -> Void

    @State private var pendingSelection: HWPImageEditing.Selection?
    @State private var showsSource = false
    @State private var showsPhotos = false
    @State private var showsFiles = false
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        Button {
            guard let value = selection() else { return }
            pendingSelection = value
            showsSource = true
        } label: {
            Label("그림", systemImage: "photo")
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 48, minHeight: 48)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel("그림 삽입")
        .accessibilityIdentifier("hwp-image-insert")
        .confirmationDialog("그림 삽입", isPresented: $showsSource, titleVisibility: .visible) {
            Button("사진 보관함") { showsPhotos = true }
            Button("파일 선택") { showsFiles = true }
            Button("취소", role: .cancel) { cancel() }
        }
        .photosPicker(isPresented: $showsPhotos, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw HWPDocumentEditingError.invalidDocument
                    }
                    await importImage(data)
                } catch { await fail(error) }
            }
        }
        .fileImporter(isPresented: $showsFiles, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                Task {
                    do {
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        await importImage(try Data(contentsOf: url, options: [.mappedIfSafe]))
                    } catch { await fail(error) }
                }
            case .failure(let error): Task { await fail(error) }
            }
        }
    }

    @MainActor private func importImage(_ data: Data) async {
        do {
            guard let pendingSelection else { return }
            let image = try await Task.detached(priority: .userInitiated) { try HWPImageEditing.normalize(data) }.value
            let size = image.displaySize(maxWidth: pendingSelection.width)
            self.pendingSelection = nil
            photoItem = nil
            onApply(.init(selection: pendingSelection, image: image,
                widthPoints: size.width, heightPoints: size.height))
        } catch { await fail(error) }
    }

    @MainActor private func fail(_ error: Error) async {
        pendingSelection = nil
        photoItem = nil
        onError(error.localizedDescription)
        restoreFocus()
    }

    private func cancel() {
        pendingSelection = nil
        restoreFocus()
    }
}

struct HWPImageSizeSheet: View {
    let target: HWPImageEditing.Target
    let onApply: (HWPImageEditing.Action) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var width = ""
    @State private var height = ""
    @State private var keepsRatio = true
    @State private var editingHeight = false
    @State private var cropLeft = 0.0
    @State private var cropRight = 0.0
    @State private var cropTop = 0.0
    @State private var cropBottom = 0.0
    @State private var rotation = 0.0
    @State private var flipHorizontal = false
    @State private var flipVertical = false
    @State private var isInline = true
    @State private var horizontalReference = HWPDocumentLayoutReference.paragraph
    @State private var verticalReference = HWPDocumentLayoutReference.paragraph
    @State private var horizontalAlignment = HWPDocumentRelativeAlignment.start
    @State private var verticalAlignment = HWPDocumentRelativeAlignment.start
    @State private var wrap = HWPDocumentObjectWrap.topAndBottom
    @State private var marginLeft = ""
    @State private var marginRight = ""
    @State private var marginTop = ""
    @State private var marginBottom = ""
    @State private var zOrder = 0
    @State private var hasBorder = false
    @State private var borderColor: UInt32 = 0
    @State private var borderWidth = 0.75
    @State private var borderStyle = 1
    @State private var brightness = 0.0
    @State private var contrast = 0.0
    @State private var effect = HWPDocumentImageEffect.original
    @State private var transparency = 0.0

    private var parsedWidth: Double? { Double(width.replacingOccurrences(of: ",", with: ".")) }
    private var parsedHeight: Double? { Double(height.replacingOccurrences(of: ",", with: ".")) }
    private var dimensions: HWPImageEditing.Dimensions? {
        guard let parsedWidth, let parsedHeight else { return nil }
        let value = HWPImageEditing.Dimensions(widthPoints: parsedWidth, heightPoints: parsedHeight)
        return value.isValid ? value : nil
    }
    private var crop: HWPImageEditing.Crop? {
        HWPImageEditing.Crop(rect: CGRect(
            x: cropLeft / 100,
            y: cropTop / 100,
            width: 1 - (cropLeft + cropRight) / 100,
            height: 1 - (cropTop + cropBottom) / 100
        ))
    }
    private var presentation: HWPImageEditing.Presentation? {
        guard let left = parsed(marginLeft), let right = parsed(marginRight),
              let top = parsed(marginTop), let bottom = parsed(marginBottom) else { return nil }
        let value = HWPImageEditing.Presentation(xPoints: target.xPoints,
            yPoints: target.yPoints, zOrder: zOrder,
            rotationDegrees: rotation, flipHorizontal: flipHorizontal,
            flipVertical: flipVertical, isInline: isInline,
            horizontalReference: horizontalReference,
            verticalReference: verticalReference,
            horizontalAlignment: horizontalAlignment,
            verticalAlignment: verticalAlignment,
            wrap: isInline ? .topAndBottom : wrap,
            marginLeftPoints: left, marginRightPoints: right,
            marginTopPoints: top, marginBottomPoints: bottom)
        return value.isValid ? value : nil
    }
    private var appearance: HWPImageEditing.Appearance? {
        let stroke = hasBorder ? HWPDocumentStroke(colorRGB: borderColor,
            widthPoints: borderWidth, style: borderStyle) : nil
        let value = HWPImageEditing.Appearance(borderStroke: stroke,
            brightness: Int(brightness.rounded()), contrast: Int(contrast.rounded()),
            effect: effect, transparencyPercent: Int(transparency.rounded()))
        return value.isValid ? value : nil
    }
    private var previewImage: UIImage? {
        guard let original = UIImage(data: target.imageData),
              let source = original.cgImage, let crop else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        let region = CGRect(x: crop.rect.minX * CGFloat(source.width),
            y: crop.rect.minY * CGFloat(source.height),
            width: crop.rect.width * CGFloat(source.width),
            height: crop.rect.height * CGFloat(source.height)).integral.intersection(bounds)
        guard region.width >= 1, region.height >= 1,
              let result = source.cropping(to: region) else { return original }
        return UIImage(cgImage: result, scale: original.scale, orientation: original.imageOrientation)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let previewImage {
                    Section("미리보기") {
                        Image(uiImage: previewImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 220)
                            .scaleEffect(x: flipHorizontal ? -1 : 1,
                                y: flipVertical ? -1 : 1)
                            .rotationEffect(.degrees(rotation))
                            .brightness(brightness / 100)
                            .contrast((1 + contrast / 100)
                                * (effect == .blackAndWhite ? 20 : 1))
                            .grayscale(effect == .original ? 0 : 1)
                            .opacity(1 - transparency / 100)
                            .overlay {
                                if hasBorder {
                                    Rectangle().stroke(rgbColor(borderColor),
                                        style: StrokeStyle(lineWidth: borderWidth,
                                            dash: HWPStrokePattern.dashes(kind: borderStyle,
                                                width: borderWidth)))
                                }
                            }
                            .accessibilityLabel("그림 편집 미리보기")
                    }
                }
                Section("색상 효과") {
                    Picker("효과", selection: $effect) {
                        Text("원본").tag(HWPDocumentImageEffect.original)
                        Text("회색조").tag(HWPDocumentImageEffect.grayscale)
                        Text("흑백").tag(HWPDocumentImageEffect.blackAndWhite)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("hwp-image-color-effect")
                    HStack {
                        Text("투명도")
                        Slider(value: $transparency, in: 0...100, step: 1)
                            .disabled(!target.supportsTransparency)
                            .accessibilityIdentifier("hwp-image-transparency")
                        Text("\(Int(transparency.rounded()))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                    if !target.supportsTransparency {
                        Text("HWP 형식은 그림 전체 투명도를 저장하지 않습니다. 회색조와 흑백 효과는 사용할 수 있습니다.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button("효과 초기화") { effect = .original; transparency = 0 }
                        .disabled(effect == .original && transparency < 0.5)
                        .accessibilityIdentifier("hwp-image-effect-reset")
                }
                Section("밝기와 대비") {
                    adjustmentControl("밝기", value: $brightness)
                    adjustmentControl("대비", value: $contrast)
                    Button("보정 초기화") { brightness = 0; contrast = 0 }
                        .disabled(abs(brightness) < 0.5 && abs(contrast) < 0.5)
                        .accessibilityIdentifier("hwp-image-adjustment-reset")
                }
                Section("테두리") {
                    Toggle("테두리 사용", isOn: $hasBorder)
                    if hasBorder {
                        ColorPicker("색", selection: rgbBinding($borderColor), supportsOpacity: false)
                        HStack {
                            Text("굵기")
                            Slider(value: $borderWidth, in: 0.25...12, step: 0.25)
                            Text(String(format: "%.2g pt", borderWidth))
                                .monospacedDigit().frame(width: 58, alignment: .trailing)
                        }
                        Picker("선 종류", selection: $borderStyle) {
                            Text("실선").tag(1)
                            Text("파선").tag(2)
                            Text("점선").tag(3)
                            Text("일점쇄선").tag(4)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                Section("자르기") {
                    cropControl("왼쪽", value: $cropLeft, opposite: cropRight)
                    cropControl("오른쪽", value: $cropRight, opposite: cropLeft)
                    cropControl("위", value: $cropTop, opposite: cropBottom)
                    cropControl("아래", value: $cropBottom, opposite: cropTop)
                    Button("자르기 초기화") { resetCrop(updateSize: true) }
                        .disabled(isFullCrop)
                        .accessibilityIdentifier("hwp-image-crop-reset")
                }
                Section("그림 크기") {
                    HStack {
                        Text("너비")
                        Spacer()
                        TextField("너비", text: $width)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .frame(width: 110)
                            .onChange(of: width) { _, value in updateHeight(value) }
                        Text("pt").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("높이")
                        Spacer()
                        TextField("높이", text: $height, onEditingChanged: { editingHeight = $0 })
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .frame(width: 110)
                            .onChange(of: height) { _, value in updateWidth(value) }
                        Text("pt").foregroundStyle(.secondary)
                    }
                    Toggle("가로세로 비율 유지", isOn: $keepsRatio)
                }
                Section("회전") {
                    HStack {
                        Button("왼쪽 90°") { rotate(-90) }
                        Spacer()
                        Button("오른쪽 90°") { rotate(90) }
                    }
                    HStack {
                        Slider(value: $rotation, in: 0...359, step: 1)
                        Text("\(Int(rotation))°")
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                }
                Section("뒤집기") {
                    Toggle("좌우 뒤집기", isOn: $flipHorizontal)
                    Toggle("상하 뒤집기", isOn: $flipVertical)
                }
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
                Section("바깥 여백") {
                    valueRow("왼쪽", text: $marginLeft)
                    valueRow("오른쪽", text: $marginRight)
                    valueRow("위", text: $marginTop)
                    valueRow("아래", text: $marginBottom)
                }
                Section("배치 순서") {
                    HStack {
                        Button { zOrder = max(zOrder - 1, -100_000) } label: {
                            Label("뒤로 보내기", systemImage: "square.2.layers.3d.bottom.filled")
                        }
                        Spacer()
                        Text("\(zOrder)").foregroundStyle(.secondary).monospacedDigit()
                        Spacer()
                        Button { zOrder = min(zOrder + 1, 100_000) } label: {
                            Label("앞으로 가져오기", systemImage: "square.2.layers.3d.top.filled")
                        }
                    }
                    .labelStyle(.iconOnly)
                }
                Section {
                    Button("원본 비율로 맞춤") {
                        guard let presentation, let appearance else { return }
                        let fitted = target.fittedDimensions(for: .full,
                            width: parsedWidth ?? target.widthPoints)
                        dismiss()
                        onApply(.update(.full, fitted, presentation, appearance))
                    }
                    .accessibilityIdentifier("hwp-image-fit-original-ratio")
                } footer: {
                    Text("자르기를 해제하고 그림의 원래 가로세로 비율로 맞춥니다.")
                }
                Section {
                    Button("그림 삭제", role: .destructive) {
                        dismiss()
                        onDelete()
                    }
                }
            }
            .navigationTitle("그림 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("적용") {
                        guard let dimensions, let crop, let presentation, let appearance else { return }
                        dismiss()
                        onApply(.update(crop, dimensions, presentation, appearance))
                    }
                    .disabled(dimensions == nil || crop == nil || presentation == nil || appearance == nil)
                }
            }
            .onAppear {
                width = formatted(target.widthPoints)
                height = formatted(target.heightPoints)
                cropLeft = target.cropRect.minX * 100
                cropRight = (1 - target.cropRect.maxX) * 100
                cropTop = target.cropRect.minY * 100
                cropBottom = (1 - target.cropRect.maxY) * 100
                rotation = normalizedRotation(target.rotationDegrees)
                flipHorizontal = target.flipHorizontal
                flipVertical = target.flipVertical
                isInline = target.isInline
                horizontalReference = target.horizontalReference
                verticalReference = target.verticalReference
                horizontalAlignment = target.horizontalAlignment
                verticalAlignment = target.verticalAlignment
                wrap = target.isInline ? .topAndBottom : target.wrap
                marginLeft = formatted(target.marginLeftPoints)
                marginRight = formatted(target.marginRightPoints)
                marginTop = formatted(target.marginTopPoints)
                marginBottom = formatted(target.marginBottomPoints)
                zOrder = target.zOrder
                hasBorder = target.borderStroke != nil
                borderColor = target.borderStroke?.colorRGB ?? 0
                borderWidth = target.borderStroke?.widthPoints ?? 0.75
                borderStyle = target.borderStroke?.style ?? 1
                brightness = Double(target.brightness)
                contrast = Double(target.contrast)
                effect = target.effect
                transparency = Double(target.transparencyPercent)
            }
        }
    }

    private func valueRow(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(label, text: text)
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .frame(width: 110)
            Text("pt").foregroundStyle(.secondary)
        }
    }

    private func parsed(_ value: String) -> Double? {
        Double(value.replacingOccurrences(of: ",", with: "."))
    }

    @ViewBuilder
    private func adjustmentControl(_ label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                Spacer()
                Text("\(Int(value.wrappedValue.rounded()))")
                    .foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(value: value, in: -100...100, step: 1)
                .accessibilityLabel(label)
        }
    }

    private func rgbColor(_ rgb: UInt32) -> Color {
        Color(red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255)
    }

    private func rgbBinding(_ value: Binding<UInt32>) -> Binding<Color> {
        Binding(get: { rgbColor(value.wrappedValue) }, set: { newValue in
            let color = UIColor(newValue)
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
            value.wrappedValue = UInt32((red * 255).rounded()) << 16
                | UInt32((green * 255).rounded()) << 8 | UInt32((blue * 255).rounded())
        })
    }

    private func normalizedRotation(_ value: Double) -> Double {
        let result = value.truncatingRemainder(dividingBy: 360)
        return result < 0 ? result + 360 : result
    }

    private func rotate(_ delta: Double) {
        rotation = normalizedRotation(rotation + delta)
    }

    private var isFullCrop: Bool {
        [cropLeft, cropRight, cropTop, cropBottom].allSatisfy { abs($0) < 0.01 }
    }

    @ViewBuilder
    private func cropControl(_ label: String, value: Binding<Double>, opposite: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                Spacer()
                Text("\(Int(value.wrappedValue.rounded()))%")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: 0...max(0, 98 - opposite), step: 1)
                .onChange(of: value.wrappedValue) { _, _ in updateSizeForCrop() }
                .accessibilityLabel("\(label) 자르기")
        }
    }

    private func resetCrop(updateSize: Bool) {
        cropLeft = 0; cropRight = 0; cropTop = 0; cropBottom = 0
        if updateSize, keepsRatio { updateSizeForCrop() }
    }

    private func updateSizeForCrop() {
        guard keepsRatio, !editingHeight, let width = parsedWidth, let crop else { return }
        height = formatted(target.fittedDimensions(for: crop, width: width).heightPoints)
    }

    private func updateHeight(_ value: String) {
        guard keepsRatio, !editingHeight,
              let width = Double(value.replacingOccurrences(of: ",", with: ".")),
              let crop else { return }
        height = formatted(target.fittedDimensions(for: crop, width: width).heightPoints)
    }

    private func updateWidth(_ value: String) {
        guard keepsRatio, editingHeight,
              let height = Double(value.replacingOccurrences(of: ",", with: ".")),
              let crop else { return }
        let visibleAspect = target.sourceAspectRatio * crop.rect.width / crop.rect.height
        width = formatted(height * visibleAspect)
    }

    private func formatted(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}
