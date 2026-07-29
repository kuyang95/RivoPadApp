import Combine
import PDFKit
import SwiftUI
import UniformTypeIdentifiers
import UIKit

@MainActor
final class LocalDocumentViewModel: ObservableObject {
    @Published var text = ""
    @Published private(set) var pdfDocument: PDFDocument?
    @Published private(set) var isLoading = false
    @Published private(set) var status = ""
    @Published private(set) var errorDescription: String?

    let fileName: String

    private let fileURL: URL
    private var didLoad = false

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.fileName = fileURL.lastPathComponent
    }

    func load() async {
        guard !didLoad else {
            return
        }
        didLoad = true
        isLoading = true
        errorDescription = nil

        do {
            let contentType = try fileURL.resourceValues(
                forKeys: [.contentTypeKey]
            ).contentType
                ?? UTType(
                    filenameExtension: fileURL.pathExtension
                )

            if contentType?.conforms(to: .pdf) == true {
                try await loadPDF()
            } else if contentType?.conforms(to: .plainText) == true {
                let data = try Data(
                    contentsOf: fileURL,
                    options: .mappedIfSafe
                )
                text = try LocalTextDecoder.decode(data)
                status = "\(text.count.formatted())자"
            } else {
                throw CocoaError(
                    .fileReadUnsupportedScheme,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "이미지, PDF, TXT 파일만 지원합니다."
                    ]
                )
            }
        } catch {
            errorDescription = error.localizedDescription
        }

        isLoading = false
    }

    private func loadPDF() async throws {
        guard let document = PDFDocument(url: fileURL) else {
            throw CocoaError(
                .fileReadCorruptFile,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "PDF 파일을 열 수 없습니다."
                ]
            )
        }
        pdfDocument = document

        var pageTexts: [String] = []
        pageTexts.reserveCapacity(document.pageCount)

        for pageIndex in 0 ..< document.pageCount {
            try Task.checkCancellation()
            status = "PDF \(pageIndex + 1)/\(document.pageCount)페이지 처리 중"

            guard let page = document.page(at: pageIndex) else {
                continue
            }
            let embeddedText = (page.string ?? "")
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            if !embeddedText.isEmpty {
                pageTexts.append(embeddedText)
                continue
            }

            let pageImage = page.thumbnail(
                of: CGSize(width: 1_800, height: 2_400),
                for: .mediaBox
            )
            if let recognizedText = try? await recognizeText(
                from: pageImage
            ) {
                let trimmed = recognizedText.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                if !trimmed.isEmpty {
                    pageTexts.append(trimmed)
                }
            }
        }

        text = pageTexts.joined(separator: "\n\n")
        guard !text.isEmpty else {
            throw DocumentTextExtractor.ExtractError.noText
        }
        status = "\(document.pageCount)페이지 · \(text.count.formatted())자"
    }

    private func recognizeText(from image: UIImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DocumentTextExtractor().extractPlainText(
                from: image
            ) { result in
                continuation.resume(with: result)
            }
        }
    }
}

struct LocalDocumentView: View {
    private enum DisplayMode: String, CaseIterable, Identifiable {
        case original = "원본"
        case text = "텍스트"

        var id: Self { self }
    }

    @EnvironmentObject private var appRouter: AppRouter
    @StateObject private var viewModel: LocalDocumentViewModel

    private let appearanceStore:
        LocalDocumentAppearanceStore
    @State private var displayMode: DisplayMode = .text
    @State private var question = ""
    @State private var feedback: String?
    @State private var appearance:
        LocalDocumentAppearance
    @State private var isEditing = false
    @State private var currentLineIndex = 0
    @State private var visibleLineCapacity = 8
    @State private var navigationUnit:
        LocalDocumentNavigationUnit = .line
    @State private var navigationRevision = 0
    @State private var isSettingsPresented = false
    @State private var isExporting = false
    @State private var exportFile:
        LocalDocumentExportFile?
    @State private var exportContentType:
        UTType = .plainText
    @State private var exportFileName =
        "VisionCraftText"

    private let tts = TTSManager.shared

    init(fileURL: URL) {
        let appearanceStore =
            LocalDocumentAppearanceStore()
        self.appearanceStore =
            appearanceStore
        _viewModel = StateObject(
            wrappedValue: LocalDocumentViewModel(
                fileURL: fileURL
            )
        )
        _appearance = State(
            initialValue:
                appearanceStore.load()
        )
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView(
                    viewModel.status.isEmpty
                        ? "문서를 여는 중"
                        : viewModel.status
                )
            } else if let error = viewModel.errorDescription {
                ContentUnavailableView(
                    "문서를 열 수 없습니다",
                    systemImage: "doc.badge.ellipsis",
                    description: Text(error)
                )
            } else {
                documentContent
            }
        }
        .navigationTitle(viewModel.fileName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("읽기", systemImage: "speaker.wave.2") {
                    let text =
                        LocalDocumentTextSegmenter
                        .text(
                            fromLine:
                                currentLineIndex,
                            in: viewModel.text
                        )
                    tts.speak(text)
                    feedback =
                        "\(currentLineIndex + 1)번째 줄부터 읽기를 시작했습니다."
                }
                .disabled(viewModel.text.isEmpty)

                Button("정지", systemImage: "speaker.slash") {
                    tts.stop()
                    feedback = "문서 읽기를 중지했습니다."
                }

                Button("복사", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = viewModel.text
                    feedback = "문서 텍스트를 복사했습니다."
                }
                .disabled(viewModel.text.isEmpty)

                Button(
                    isEditing ? "읽기 보기" : "편집",
                    systemImage:
                        isEditing
                        ? "text.alignleft"
                        : "pencil"
                ) {
                    isEditing.toggle()
                    displayMode = .text
                    tts.stop()
                }
                .disabled(viewModel.text.isEmpty)

                Menu(
                    "저장",
                    systemImage:
                        "square.and.arrow.up"
                ) {
                    Button(
                        "TXT로 내보내기",
                        systemImage: "doc.text"
                    ) {
                        beginExport(as: .plainText)
                    }
                    Button(
                        "PDF로 내보내기",
                        systemImage: "doc.richtext"
                    ) {
                        beginExport(as: .pdf)
                    }
                }
                .disabled(viewModel.text.isEmpty)

                Button(
                    "보기 설정",
                    systemImage: "textformat.size"
                ) {
                    isSettingsPresented = true
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if showsTextReadingControls {
                    navigationBar
                    Divider()
                }
                questionBar
            }
        }
        .task {
            await viewModel.load()
        }
        .onDisappear {
            tts.stop()
        }
        .onChange(of: appearance) {
            _, value in
            appearanceStore.save(value)
        }
        .sheet(
            isPresented:
                $isSettingsPresented
        ) {
            settingsSheet
                .presentationDetents(
                    [.medium, .large]
                )
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportFile,
            contentType: exportContentType,
            defaultFilename: exportFileName
        ) { result in
            switch result {
            case .success:
                feedback =
                    exportContentType == .pdf
                    ? "PDF를 저장했습니다."
                    : "TXT를 저장했습니다."
            case .failure(let error):
                feedback =
                    "저장하지 못했습니다: "
                    + error.localizedDescription
            }
            exportFile = nil
        }
    }

    @ViewBuilder
    private var documentContent: some View {
        VStack(spacing: 0) {
            if viewModel.pdfDocument != nil {
                Picker("문서 보기", selection: $displayMode) {
                    ForEach(DisplayMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                .accessibilityHint(
                    "PDF 원본과 추출된 텍스트 보기를 전환합니다."
                )
            }

            if displayMode == .original,
               let document = viewModel.pdfDocument {
                PDFDocumentRepresentable(document: document)
            } else if isEditing {
                TextEditor(text: $viewModel.text)
                    .font(
                        .system(
                            size: documentFontSize
                        )
                    )
                    .lineSpacing(
                        documentLineSpacing
                    )
                    .foregroundStyle(
                        documentForeground
                    )
                    .scrollContentBackground(
                        .hidden
                    )
                    .background(
                        documentBackground
                    )
                    .padding(.horizontal, 8)
                    .accessibilityLabel(
                        "문서 텍스트 편집"
                    )
                    .accessibilityHint(
                        "문서 내용을 수정할 수 있습니다."
                    )
            } else {
                readableText
            }

            if let feedback {
                Text(feedback)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .accessibilityLabel(feedback)
            } else if !viewModel.status.isEmpty {
                Text(viewModel.status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
            }
        }
    }

    private var readableText: some View {
        let lines =
            LocalDocumentTextSegmenter.lines(
                in: viewModel.text
            )
        return GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(
                        alignment: .leading,
                        spacing: 0
                    ) {
                        ForEach(lines) { line in
                            Text(
                                line.text.isEmpty
                                    ? " "
                                    : line.text
                            )
                            .font(
                                .system(
                                    size:
                                        documentFontSize
                                )
                            )
                            .lineSpacing(
                                documentLineSpacing
                            )
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                            .padding(
                                .vertical,
                                max(
                                    documentLineSpacing
                                        / 2,
                                    4
                                )
                            )
                            .overlay(
                                alignment: .bottom
                            ) {
                                if appearance
                                    .showsLineSeparators {
                                    Rectangle()
                                        .fill(
                                            documentForeground
                                                .opacity(
                                                    0.18
                                                )
                                        )
                                        .frame(height: 1)
                                }
                            }
                            .accessibilityLabel(
                                line.text.isEmpty
                                    ? "빈 줄"
                                    : line.text
                            )
                            .id(line.id)
                            .background {
                                GeometryReader {
                                    lineGeometry in
                                    Color.clear
                                        .preference(
                                            key:
                                                LocalDocumentLineOffsetPreferenceKey
                                                .self,
                                            value: [
                                                line.index:
                                                    lineGeometry
                                                    .frame(
                                                        in:
                                                            .named(
                                                                "local-document-scroll"
                                                            )
                                                    )
                                                    .minY,
                                            ]
                                        )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 20)
                    .textSelection(.enabled)
                }
                .coordinateSpace(
                    name:
                        "local-document-scroll"
                )
                .background(documentBackground)
                .foregroundStyle(documentForeground)
                .onPreferenceChange(
                    LocalDocumentLineOffsetPreferenceKey
                        .self
                ) { offsets in
                    guard let visible =
                            offsets.min(
                                by: {
                                    abs($0.value)
                                        < abs($1.value)
                                }
                            )?.key else {
                        return
                    }
                    currentLineIndex =
                        min(
                            max(visible, 0),
                            max(lines.count - 1, 0)
                        )
                }
                .task(id: navigationRevision) {
                    guard lines.indices.contains(
                              currentLineIndex
                          ) else {
                        return
                    }
                    await Task.yield()
                    withAnimation(
                        .easeInOut(
                            duration: 0.2
                        )
                    ) {
                        proxy.scrollTo(
                            currentLineIndex,
                            anchor: .top
                        )
                    }
                }
                .onAppear {
                    updateVisibleLineCapacity(
                        height:
                            geometry.size.height
                    )
                }
                .onChange(of: geometry.size) {
                    _, size in
                    updateVisibleLineCapacity(
                        height: size.height
                    )
                }
                .onChange(
                    of: appearance.fontLevel
                ) {
                    _, _ in
                    updateVisibleLineCapacity(
                        height:
                            geometry.size.height
                    )
                }
                .onChange(
                    of:
                        appearance
                        .lineHeightLevel
                ) {
                    _, _ in
                    updateVisibleLineCapacity(
                        height:
                            geometry.size.height
                    )
                }
            }
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 10) {
            Button(
                "처음",
                systemImage: "backward.end.fill"
            ) {
                moveToDocumentBoundary(
                    isEnd: false
                )
            }
            .disabled(currentLineIndex <= 0)

            Button(
                "이전 \(navigationUnit.displayName)",
                systemImage: "chevron.up"
            ) {
                moveText(by: -1)
            }
            .disabled(
                !canMoveText(by: -1)
            )

            Button(
                navigationUnit.displayName,
                systemImage:
                    "arrow.up.arrow.down"
            ) {
                navigationUnit =
                    navigationUnit.next()
            }
            .accessibilityLabel(
                "탐색 단위 "
                + navigationUnit.displayName
            )
            .accessibilityHint(
                "두 번 탭하면 줄과 페이지 탐색이 바뀝니다."
            )

            Button(
                "다음 \(navigationUnit.displayName)",
                systemImage: "chevron.down"
            ) {
                moveText(by: 1)
            }
            .disabled(
                !canMoveText(by: 1)
            )

            Button(
                "끝",
                systemImage: "forward.end.fill"
            ) {
                moveToDocumentBoundary(
                    isEnd: true
                )
            }
            .disabled(
                currentLineIndex
                    >= documentLines.count - 1
            )

            Text(
                "\(min(currentLineIndex + 1, max(documentLines.count, 1))) / \(max(documentLines.count, 1))"
            )
            .font(.caption.monospacedDigit())
            .accessibilityLabel(
                "문서 줄 위치 "
                + "\(min(currentLineIndex + 1, max(documentLines.count, 1)))"
                + " / \(max(documentLines.count, 1))"
            )
        }
        .buttonStyle(.bordered)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("글자") {
                    Stepper(
                        "글자 크기 \(appearance.fontLevel)",
                        value:
                            $appearance.fontLevel,
                        in: 1 ... 10
                    )
                    Stepper(
                        "줄 간격 \(appearance.lineHeightLevel)",
                        value:
                            $appearance
                            .lineHeightLevel,
                        in: 1 ... 10
                    )
                    Toggle(
                        "줄 구분선",
                        isOn:
                            $appearance
                            .showsLineSeparators
                    )
                }

                Section("색상") {
                    Picker(
                        "색상 조합",
                        selection:
                            $appearance.colorIndex
                    ) {
                        ForEach(
                            Array(
                                LocalDocumentColorTheme
                                    .all
                                    .enumerated()
                            ),
                            id: \.offset
                        ) { index, theme in
                            Text(theme.name)
                                .tag(index)
                        }
                    }
                }

                Section("미리 보기") {
                    Text(
                        "가나다 ABC 123 문서 보기"
                    )
                    .font(
                        .system(
                            size:
                                min(
                                    documentFontSize,
                                    56
                                )
                        )
                    )
                    .lineSpacing(
                        documentLineSpacing
                    )
                    .foregroundStyle(
                        documentForeground
                    )
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 100,
                        alignment: .leading
                    )
                    .padding()
                    .background(
                        documentBackground
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 12
                        )
                    )
                }

                Section {
                    Button("기본값으로 복원") {
                        appearance =
                            .defaultValue
                    }
                }
            }
            .navigationTitle("문서 보기 설정")
            .toolbar {
                ToolbarItem(
                    placement:
                        .confirmationAction
                ) {
                    Button("완료") {
                        isSettingsPresented =
                            false
                    }
                }
            }
        }
    }

    private var documentLines:
        [LocalDocumentLine] {
        LocalDocumentTextSegmenter.lines(
            in: viewModel.text
        )
    }

    private var showsTextReadingControls: Bool {
        displayMode == .text
            && !isEditing
            && !viewModel.text.isEmpty
    }

    private var documentTheme:
        LocalDocumentColorTheme {
        let themes =
            LocalDocumentColorTheme.all
        let index = min(
            max(appearance.colorIndex, 0),
            themes.count - 1
        )
        return themes[index]
    }

    private var documentBackground: Color {
        Color(
            rgbHex:
                documentTheme.backgroundHex
        )
    }

    private var documentForeground: Color {
        Color(
            rgbHex:
                documentTheme.foregroundHex
        )
    }

    private var documentFontSize: CGFloat {
        let sizes: [CGFloat] = [
            22, 26, 30, 36, 44,
            52, 60, 72, 84, 96,
        ]
        return sizes[
            min(
                max(
                    appearance.fontLevel - 1,
                    0
                ),
                sizes.count - 1
            )
        ]
    }

    private var documentLineSpacing: CGFloat {
        documentFontSize
            * CGFloat(
                appearance.lineHeightLevel - 1
            )
            * 0.07
    }

    private func updateVisibleLineCapacity(
        height: CGFloat
    ) {
        let estimatedLineHeight =
            max(
                documentFontSize
                    + documentLineSpacing
                    + 8,
                1
            )
        visibleLineCapacity =
            max(
                Int(
                    max(height - 40, 1)
                        / estimatedLineHeight
                ),
                1
            )
    }

    private func canMoveText(
        by direction: Int
    ) -> Bool {
        LocalDocumentTextNavigator
            .targetLine(
                from: currentLineIndex,
                direction: direction,
                unit: navigationUnit,
                lineCount:
                    documentLines.count,
                linesPerPage:
                    visibleLineCapacity
            ) != nil
    }

    private func moveText(
        by direction: Int
    ) {
        guard let target =
                LocalDocumentTextNavigator
                .targetLine(
                    from:
                        currentLineIndex,
                    direction: direction,
                    unit:
                        navigationUnit,
                    lineCount:
                        documentLines.count,
                    linesPerPage:
                        visibleLineCapacity
                ) else {
            return
        }
        moveToLine(target)
    }

    private func moveToDocumentBoundary(
        isEnd: Bool
    ) {
        guard !documentLines.isEmpty else {
            return
        }
        moveToLine(
            isEnd
                ? documentLines.count - 1
                : 0
        )
    }

    private func moveToLine(_ index: Int) {
        guard !documentLines.isEmpty else {
            return
        }
        currentLineIndex =
            min(
                max(index, 0),
                documentLines.count - 1
            )
        navigationRevision &+= 1
    }

    private func beginExport(
        as contentType: UTType
    ) {
        let baseName =
            (
                viewModel.fileName
                    as NSString
            )
            .deletingPathExtension
        exportContentType = contentType
        if contentType == .pdf {
            exportFile =
                LocalDocumentExportBuilder
                .pdfFile(
                    text: viewModel.text
                )
            exportFileName =
                baseName.isEmpty
                ? "VisionCraftText.pdf"
                : "\(baseName).pdf"
        } else {
            exportFile =
                LocalDocumentExportBuilder
                .textFile(
                    text: viewModel.text
                )
            exportFileName =
                baseName.isEmpty
                ? "VisionCraftText.txt"
                : "\(baseName).txt"
        }
        isExporting = true
    }

    private var questionBar: some View {
        HStack {
            TextField(
                "이 문서에 대해 질문하세요",
                text: $question,
                axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .lineLimit(1 ... 4)
            .submitLabel(.send)
            .onSubmit {
                askQuestion()
            }

            Button("AI 질문") {
                askQuestion()
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                question.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
                    || viewModel.text.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
            )
        }
        .padding()
        .background(.bar)
    }

    private func askQuestion() {
        let trimmedQuestion = question.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let document = viewModel.text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmedQuestion.isEmpty, !document.isEmpty else {
            return
        }
        question = ""
        appRouter.route = .documentQuestion(
            document: document,
            question: trimmedQuestion
        )
    }
}

private nonisolated struct
    LocalDocumentLineOffsetPreferenceKey:
    PreferenceKey
{
    static let defaultValue:
        [Int: CGFloat] = [:]

    static func reduce(
        value: inout [Int: CGFloat],
        nextValue: () -> [Int: CGFloat]
    ) {
        value.merge(
            nextValue(),
            uniquingKeysWith: {
                _, newValue in
                newValue
            }
        )
    }
}

private extension Color {
    init(rgbHex: Int) {
        self.init(
            red:
                Double(
                    (rgbHex >> 16) & 0xFF
                ) / 255,
            green:
                Double(
                    (rgbHex >> 8) & 0xFF
                ) / 255,
            blue:
                Double(rgbHex & 0xFF)
                / 255
        )
    }
}

private struct PDFDocumentRepresentable: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = document
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document !== document {
            uiView.document = document
        }
    }
}
