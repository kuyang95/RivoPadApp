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
            let pathExtension = fileURL
                .pathExtension
                .lowercased()
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
            } else if
                LocalStructuredDocumentTextExtractor
                .supportedExtensions
                .contains(pathExtension)
            {
                status =
                    AppLocalization.string(
                        "문서 텍스트 추출 중…"
                    )
                text = try await
                    LocalStructuredDocumentTextExtractor
                    .extract(at: fileURL)
                status =
                    "\(text.count.formatted())자"
            } else {
                throw CocoaError(
                    .fileReadUnsupportedScheme,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            AppLocalization.string(
                                "PDF, TXT, XLSX, XLS와 HWP 문서만 지원합니다."
                            )
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
            if let recognizedText =
                try? await
                recognizeAndCorrectText(
                    from: pageImage,
                    pageNumber:
                        pageIndex + 1,
                    pageCount:
                        document.pageCount
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

    private func recognizeAndCorrectText(
        from image: UIImage,
        pageNumber: Int,
        pageCount: Int
    ) async throws -> String {
        let original = try await
            recognizeText(from: image)
        let isEnabled =
            AppSettingsStore.shared
            .ocrAutoCorrectionEnabled
        if isEnabled,
           !original.trimmingCharacters(
               in: .whitespacesAndNewlines
           ).isEmpty {
            status =
                AppLocalization.format(
                    "PDF %lld/%lld페이지 OCR 오타 교정 중",
                    pageNumber,
                    pageCount
                )
        }
        return await LocalOCRCorrectionService
            .shared
            .correct(
                image: image,
                originalText: original,
                isEnabled: isEnabled
            )
    }
}

struct LocalDocumentView: View {
    private enum DisplayMode: String, CaseIterable, Identifiable {
        case original = "원본"
        case text = "텍스트"

        var id: Self { self }
    }

    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var remoteControl:
        RivoScreenRemoteControlCenter
    @StateObject private var viewModel: LocalDocumentViewModel
    @StateObject private var speechController:
        LocalDocumentSpeechController

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
        _speechController = StateObject(
            wrappedValue:
                LocalDocumentSpeechController()
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
                    startDocumentReading()
                }
                .disabled(viewModel.text.isEmpty)

                Button("정지", systemImage: "speaker.slash") {
                    speechController.stop()
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
                    speechController.stop()
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
                    speechBar
                    Divider()
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
            speechController.stop()
        }
        .onChange(of: viewModel.text) {
            _, _ in
            speechController.reset()
        }
        .onChange(
            of:
                speechController
                .selection.currentIndex
        ) {
            _, _ in
            guard let lineIndex =
                    speechController
                    .currentSegment?
                    .lineIndex else {
                return
            }
            moveToLine(lineIndex)
        }
        .onChange(of: appearance) {
            _, value in
            appearanceStore.save(value)
        }
        .onChange(
            of: remoteControl.latestEvent
        ) { _, event in
            handleRemoteEvent(event)
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
            if usesSingleLineLayout(
                size: geometry.size
            ) {
                singleLineReadableText(
                    lines: lines,
                    size: geometry.size
                )
            } else {
                verticalReadableText(
                    lines: lines,
                    size: geometry.size
                )
            }
        }
    }

    private func verticalReadableText(
        lines: [LocalDocumentLine],
        size: CGSize
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(
                    alignment: .leading,
                    spacing: 0
                ) {
                    ForEach(lines) { line in
                        Text(
                            attributedText(
                                for: line
                            )
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
                        .accessibilityValue(
                            speechAccessibilityValue(
                                for: line
                            )
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
                await scrollToCurrentLine(
                    lines: lines,
                    proxy: proxy,
                    anchor: .top
                )
            }
            .onAppear {
                updateVisibleLineCapacity(
                    height: size.height
                )
            }
            .onChange(of: size) {
                _, updatedSize in
                updateVisibleLineCapacity(
                    height:
                        updatedSize.height
                )
            }
            .onChange(
                of: appearance.fontLevel
            ) {
                _, _ in
                updateVisibleLineCapacity(
                    height: size.height
                )
            }
            .onChange(
                of:
                    appearance
                    .lineHeightLevel
            ) {
                _, _ in
                updateVisibleLineCapacity(
                    height: size.height
                )
            }
        }
    }

    private func singleLineReadableText(
        lines: [LocalDocumentLine],
        size: CGSize
    ) -> some View {
        let line =
            lines.indices.contains(
                currentLineIndex
            )
            ? lines[currentLineIndex]
            : LocalDocumentLine(
                index: 0,
                text: ""
            )
        return ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    Color.clear
                        .frame(
                            width: 1,
                            height: 1
                        )
                        .id(
                            singleLineStartID(
                                for: line
                            )
                        )
                    ForEach(
                        singleLinePieces(
                            for: line
                        )
                    ) { piece in
                        Text(piece.text)
                            .background(
                                piece.isHighlighted
                                    ? documentForeground
                                    .opacity(0.28)
                                    : Color.clear
                            )
                            .id(piece.id)
                    }
                }
                .font(
                    .system(
                        size: documentFontSize
                    )
                )
                .fixedSize(
                    horizontal: true,
                    vertical: false
                )
                .frame(
                    minWidth:
                        max(size.width - 56, 1),
                    minHeight:
                        max(size.height - 40, 1),
                    alignment: .leading
                )
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
                .id(line.id)
                .accessibilityLabel(
                    line.text.isEmpty
                        ? "한 줄 읽기, 빈 줄"
                        : "한 줄 읽기, \(line.text)"
                )
                .accessibilityValue(
                    speechAccessibilityValue(
                        for: line
                    )
                )
            }
            .background(documentBackground)
            .foregroundStyle(documentForeground)
            .textSelection(.enabled)
            .task(id: navigationRevision) {
                await Task.yield()
                withAnimation(
                    .easeInOut(
                        duration: 0.2
                    )
                ) {
                    proxy.scrollTo(
                        singleLineTargetID(
                            for: line
                        ),
                        anchor:
                            speechController
                            .currentSegment?
                            .lineIndex
                                == line.index
                            ? .center
                            : .leading
                    )
                }
            }
            .onAppear {
                visibleLineCapacity = 1
            }
            .onChange(of: size) {
                _, _ in
                visibleLineCapacity = 1
            }
        }
    }

    private func singleLinePieces(
        for line: LocalDocumentLine
    ) -> [LocalDocumentLinePiece] {
        let source = line.text as NSString
        let segments =
            speechController
            .selection.segments
            .filter {
                $0.lineIndex == line.index
                    && $0.utf16Location >= 0
                    && NSMaxRange(
                        $0.utf16Range
                    ) <= source.length
            }
            .sorted {
                $0.utf16Location
                    < $1.utf16Location
            }
        guard !segments.isEmpty else {
            return [
                LocalDocumentLinePiece(
                    id:
                        "line-\(line.index)-all",
                    text:
                        line.text.isEmpty
                        ? " "
                        : line.text,
                    isHighlighted: false
                ),
            ]
        }

        var pieces:
            [LocalDocumentLinePiece] = []
        var cursor = 0
        for segment in segments {
            if segment.utf16Location
                > cursor {
                let gapRange = NSRange(
                    location: cursor,
                    length:
                        segment.utf16Location
                        - cursor
                )
                pieces.append(
                    LocalDocumentLinePiece(
                        id:
                            "line-\(line.index)-gap-\(cursor)",
                        text:
                            source.substring(
                                with: gapRange
                            ),
                        isHighlighted:
                            false
                    )
                )
            }
            pieces.append(
                LocalDocumentLinePiece(
                    id:
                        singleLineSegmentID(
                            segment.id
                        ),
                    text: source.substring(
                        with:
                            segment.utf16Range
                    ),
                    isHighlighted:
                        speechController
                        .currentSegment?.id
                            == segment.id
                )
            )
            cursor = NSMaxRange(
                segment.utf16Range
            )
        }
        if cursor < source.length {
            pieces.append(
                LocalDocumentLinePiece(
                    id:
                        "line-\(line.index)-tail-\(cursor)",
                    text: source.substring(
                        from: cursor
                    ),
                    isHighlighted: false
                )
            )
        }
        return pieces
    }

    private func singleLineStartID(
        for line: LocalDocumentLine
    ) -> String {
        "line-\(line.index)-start"
    }

    private func singleLineSegmentID(
        _ segmentID: Int
    ) -> String {
        "document-sentence-\(segmentID)"
    }

    private func singleLineTargetID(
        for line: LocalDocumentLine
    ) -> String {
        guard let segment =
                speechController
                .currentSegment,
              segment.lineIndex
                == line.index else {
            return singleLineStartID(
                for: line
            )
        }
        return singleLineSegmentID(
            segment.id
        )
    }

    private func speechAccessibilityValue(
        for line: LocalDocumentLine
    ) -> String {
        guard let segment =
                speechController
                .currentSegment,
              segment.lineIndex
                == line.index else {
            return ""
        }
        return AppLocalization.format(
            "현재 발화 문장, %@",
            segment.text
        )
    }

    @MainActor
    private func scrollToCurrentLine(
        lines: [LocalDocumentLine],
        proxy: ScrollViewProxy,
        anchor: UnitPoint
    ) async {
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
                anchor: anchor
            )
        }
    }

    private var speechBar: some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            HStack {
                Label(
                    "문장 음성",
                    systemImage:
                        "text.bubble.waveform"
                )
                .font(.subheadline.bold())
                Spacer()
                Text(
                    speechController
                        .currentPositionDescription
                        ?? "현재 줄에서 시작"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                documentSpeechButton(
                    title: "이전 문장",
                    systemImage:
                        "backward.end.fill"
                ) {
                    _ = speechController
                        .previous(
                            text:
                                viewModel.text,
                            startingAtLine:
                                currentLineIndex
                        )
                }

                documentSpeechButton(
                    title:
                        "현재 문장 다시 읽기",
                    systemImage:
                        "arrow.counterclockwise"
                ) {
                    _ = speechController
                        .replay(
                            text:
                                viewModel.text,
                            startingAtLine:
                                currentLineIndex
                        )
                }

                documentSpeechButton(
                    title:
                        speechController
                            .isSpeaking
                            ? "문서 읽기 정지"
                            : "문서 읽기",
                    systemImage:
                        speechController
                            .isSpeaking
                            ? "stop.fill"
                            : "play.fill"
                ) {
                    _ = speechController
                        .toggle(
                            text:
                                viewModel.text,
                            startingAtLine:
                                currentLineIndex
                        )
                }

                documentSpeechButton(
                    title: "다음 문장",
                    systemImage:
                        "forward.end.fill"
                ) {
                    _ = speechController
                        .next(
                            text:
                                viewModel.text,
                            startingAtLine:
                                currentLineIndex
                        )
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
        .accessibilityElement(
            children: .contain
        )
    }

    private func documentSpeechButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(
                    maxWidth: .infinity
                )
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(title)
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
                    Toggle(
                        "가로 화면 한 줄 읽기",
                        isOn:
                            $appearance
                            .usesSingleLineInLandscape
                    )
                    .accessibilityHint(
                        "iPad를 가로로 돌리면 현재 논리 줄 하나를 줄바꿈 없이 표시합니다."
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

    private func usesSingleLineLayout(
        size: CGSize
    ) -> Bool {
        LocalDocumentLayoutPolicy
            .usesSingleLine(
                preferenceEnabled:
                    appearance
                    .usesSingleLineInLandscape,
                width: size.width,
                height: size.height
            )
    }

    private func attributedText(
        for line: LocalDocumentLine
    ) -> AttributedString {
        let source =
            line.text.isEmpty
            ? " "
            : line.text
        guard let segment =
                speechController
                .currentSegment,
              segment.lineIndex
                == line.index,
              !line.text.isEmpty else {
            return AttributedString(source)
        }
        let sourceText =
            line.text as NSString
        let range = segment.utf16Range
        guard range.location != NSNotFound,
              range.location >= 0,
              range.length > 0,
              NSMaxRange(range)
                <= sourceText.length else {
            return AttributedString(source)
        }

        var result = AttributedString(
            sourceText.substring(
                to: range.location
            )
        )
        var highlighted =
            AttributedString(
                sourceText.substring(
                    with: range
                )
            )
        highlighted.backgroundColor =
            documentForeground.opacity(0.28)
        result += highlighted
        result += AttributedString(
            sourceText.substring(
                from: NSMaxRange(range)
            )
        )
        return result
    }

    private func startDocumentReading() {
        guard speechController.play(
            text: viewModel.text,
            startingAtLine:
                currentLineIndex
        ) else {
            feedback =
                "읽을 문서 텍스트가 없습니다."
            return
        }
        feedback =
            "\(currentLineIndex + 1)번째 줄부터 문장 읽기를 시작했습니다."
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
        moveText(
            by: direction,
            unit: navigationUnit
        )
    }

    private func moveText(
        by direction: Int,
        unit: LocalDocumentNavigationUnit
    ) {
        guard let target =
                LocalDocumentTextNavigator
                .targetLine(
                    from:
                        currentLineIndex,
                    direction: direction,
                    unit: unit,
                    lineCount:
                        documentLines.count,
                    linesPerPage:
                        visibleLineCapacity
                ) else {
            return
        }
        moveToLine(target)
    }

    private func handleRemoteEvent(
        _ event: RivoScreenRemoteEvent?
    ) {
        guard let event,
              case .localDocumentReader(
                let action
              ) = event.action else {
            return
        }

        displayMode = .text
        isEditing = false
        if let updated =
                action.updatedAppearance(
                    from: appearance
                ) {
            appearance = updated
            switch action {
            case .decreaseFont,
                 .defaultFont,
                 .increaseFont:
                announceRemoteFeedback(
                    "글자 크기 \(updated.fontLevel)"
                )
            case .decreaseLineHeight,
                 .defaultLineHeight,
                 .increaseLineHeight:
                announceRemoteFeedback(
                    "줄 간격 \(updated.lineHeightLevel)"
                )
            case .previousColor,
                 .originalColor,
                 .nextColor,
                 .invertColor:
                let theme =
                    LocalDocumentColorTheme.all[
                        updated.colorIndex
                    ]
                announceRemoteFeedback(
                    "색상 \(theme.name)"
                )
            default:
                break
            }
            return
        }

        switch action {
        case .enterTextMode(let showGuide):
            announceRemoteFeedback(
                showGuide
                    ? "문서 조작 모드. 1 처음, 2 이전 줄, 3 이전 페이지, 4 5 6 글자 크기, 7 끝, 8 다음 줄, 9 다음 페이지, 별표 0 샵 줄 간격"
                    : "문서 조작 모드"
            )
        case .enterDisplayMode(let showGuide):
            announceRemoteFeedback(
                showGuide
                    ? "색상 조작 모드. 4 이전 색상, 5 원본 색상, 6 다음 색상, R2 반전, L3 문서 조작"
                    : "색상 조작 모드"
            )
        case .beginning:
            moveToDocumentBoundary(isEnd: false)
            announceRemoteFeedback("문서 처음")
        case .previousLine:
            moveText(by: -1, unit: .line)
            announceRemoteFeedback(
                "이전 줄, \(currentLineIndex + 1)번째 줄"
            )
        case .previousPage:
            moveText(by: -1, unit: .page)
            announceRemoteFeedback(
                "이전 페이지, \(currentLineIndex + 1)번째 줄"
            )
        case .end:
            moveToDocumentBoundary(isEnd: true)
            announceRemoteFeedback("문서 끝")
        case .nextLine:
            moveText(by: 1, unit: .line)
            announceRemoteFeedback(
                "다음 줄, \(currentLineIndex + 1)번째 줄"
            )
        case .nextPage:
            moveText(by: 1, unit: .page)
            announceRemoteFeedback(
                "다음 페이지, \(currentLineIndex + 1)번째 줄"
            )
        case .toggleReading:
            toggleDocumentReadingFromRemote()
        default:
            break
        }
    }

    private func toggleDocumentReadingFromRemote() {
        if speechController.isSpeaking {
            speechController.stop()
            announceRemoteFeedback(
                "문서 읽기를 중지했습니다."
            )
            return
        }
        guard speechController.play(
            text: viewModel.text,
            startingAtLine:
                currentLineIndex
        ) else {
            announceRemoteFeedback(
                "읽을 문서 텍스트가 없습니다."
            )
            return
        }
        feedback =
            "\(currentLineIndex + 1)번째 줄부터 문장 읽기를 시작했습니다."
    }

    private func announceRemoteFeedback(
        _ message: String
    ) {
        feedback = message
        UIAccessibility.post(
            notification: .announcement,
            argument: message
        )
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

private struct LocalDocumentLinePiece:
    Identifiable
{
    let id: String
    let text: String
    let isHighlighted: Bool
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
