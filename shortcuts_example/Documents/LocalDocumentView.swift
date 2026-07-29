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

    @State private var displayMode: DisplayMode = .text
    @State private var question = ""
    @State private var feedback: String?

    private let tts = TTSManager.shared

    init(fileURL: URL) {
        _viewModel = StateObject(
            wrappedValue: LocalDocumentViewModel(
                fileURL: fileURL
            )
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
                    tts.speak(viewModel.text)
                    feedback = "문서 읽기를 시작했습니다."
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
            }
        }
        .safeAreaInset(edge: .bottom) {
            questionBar
        }
        .task {
            await viewModel.load()
        }
        .onDisappear {
            tts.stop()
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
            } else {
                TextEditor(text: $viewModel.text)
                    .font(.system(size: 22))
                    .lineSpacing(6)
                    .padding(.horizontal, 8)
                    .accessibilityLabel("문서 텍스트")
                    .accessibilityHint(
                        "추출된 문서를 읽거나 편집할 수 있습니다."
                    )
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
