import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct DocumentScanRootView: View {
    private enum Phase {
        case camera
        case capturedPageReview
        case pageReview
    }

    @EnvironmentObject private var appRouter:
        AppRouter
    @EnvironmentObject private var remoteControl:
        RivoScreenRemoteControlCenter
    @Environment(\.dismiss)
    private var dismiss
    @ObservedObject private var settings =
        AppSettingsStore.shared

    @StateObject private var session:
        DocumentScanSessionModel
    @State private var phase:
        Phase
    @State private var pendingImage:
        UIImage?
    @State private var scannerCommand:
        DocumentScannerCommand?
    @State private var exportDocument:
        ScannedPDFFileDocument?
    @State private var isExporting = false
    @State private var isPreparingDocument =
        false
    @State private var errorMessage:
        String?
    @State private var showsDiscardConfirmation =
        false

    init() {
        let session =
            DocumentScanSessionModel()
        _session = StateObject(
            wrappedValue: session
        )
        _phase = State(
            initialValue:
                session.pages.isEmpty
                    ? .camera
                    : .pageReview
        )
    }

    var body: some View {
        ZStack {
            DocumentScannerController(
                remoteEvent:
                    remoteControl.latestEvent,
                command: scannerCommand,
                isActive:
                    phase == .camera,
                automaticCaptureEnabled:
                    settings
                    .documentScanAutomaticCaptureEnabled,
                curvedPageCorrectionEnabled:
                    settings
                    .documentScanCurvedPageCorrectionEnabled,
                onScanCompleted:
                    reviewCapturedPage,
                onCancel: handleScannerCancel
            )
            .opacity(
                phase == .camera ? 1 : 0
            )
            .allowsHitTesting(
                phase == .camera
            )
            .accessibilityHidden(
                phase != .camera
            )

            switch phase {
            case .camera:
                EmptyView()
            case .capturedPageReview:
                capturedPageReview
            case .pageReview:
                pageReview
            }

            if isPreparingDocument {
                preparingOverlay
            }
        }
        .background(Color.black)
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .pdf,
            defaultFilename:
                defaultPDFFileName
        ) { result in
            if case .failure(let error) =
                result {
                errorMessage =
                    error.localizedDescription
            }
            exportDocument = nil
        }
        .alert(
            "스캔 작업을 완료할 수 없습니다",
            isPresented: Binding(
                get: {
                    errorMessage != nil
                },
                set: { isPresented in
                    if !isPresented {
                        errorMessage = nil
                        session.clearError()
                    }
                }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            "촬영한 페이지를 모두 삭제할까요?",
            isPresented:
                $showsDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                "페이지 삭제 후 닫기",
                role: .destructive
            ) {
                session.discard()
                dismiss()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text(
                "아직 내보내지 않은 스캔 페이지는 복구할 수 없습니다."
            )
        }
        .onReceive(
            session.$errorDescription
        ) { description in
            if let description {
                errorMessage = description
            }
        }
    }

    @ViewBuilder
    private var capturedPageReview:
        some View
    {
        if let pendingImage {
            VStack(spacing: 20) {
                HStack {
                    VStack(
                        alignment: .leading,
                        spacing: 4
                    ) {
                        Text("촬영 결과")
                            .font(.title.bold())
                        Text(
                            "저장된 페이지 \(session.pages.count)개"
                        )
                        .foregroundStyle(
                            .secondary
                        )
                    }
                    Spacer()
                }

                Image(
                    uiImage: pendingImage
                )
                .resizable()
                .scaledToFit()
                .accessibilityLabel(
                    "보정된 문서 미리보기"
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
                .background(Color.black)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 16,
                        style: .continuous
                    )
                )

                HStack(spacing: 12) {
                    Button(
                        "재촬영",
                        systemImage:
                            "arrow.counterclockwise"
                    ) {
                        retakePage()
                    }
                    .buttonStyle(.bordered)

                    if session.pages.isEmpty {
                        Button(
                            "한 장 OCR",
                            systemImage:
                                "text.viewfinder"
                        ) {
                            openSinglePageOCR()
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(
                        "페이지 추가",
                        systemImage:
                            "doc.badge.plus"
                    ) {
                        saveAndContinue()
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        !session.canAddPage
                    )

                    Button(
                        "검토 완료",
                        systemImage:
                            "checkmark.circle"
                    ) {
                        saveAndFinish()
                    }
                    .buttonStyle(
                        .borderedProminent
                    )
                }
                .controlSize(.large)
            }
            .padding(24)
            .background(
                Color(
                    uiColor:
                        .systemBackground
                )
            )
        }
    }

    private var pageReview: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Button(
                    "닫기",
                    systemImage: "xmark"
                ) {
                    requestClose()
                }
                .buttonStyle(.bordered)

                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text("스캔 페이지 검토")
                        .font(.title2.bold())
                    Text(
                        "\(session.pages.count)페이지 · 끌어서 순서 변경"
                    )
                    .font(.subheadline)
                    .foregroundStyle(
                        .secondary
                    )
                }

                Spacer()
                EditButton()
            }
            .padding(20)

            Divider()

            if session.pages.isEmpty {
                ContentUnavailableView(
                    "저장된 페이지가 없습니다",
                    systemImage:
                        "doc.viewfinder",
                    description:
                        Text(
                            "페이지 추가를 눌러 문서를 촬영하세요."
                        )
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
            } else {
                List {
                    ForEach(
                        Array(
                            session.pages
                                .enumerated()
                        ),
                        id: \.element.id
                    ) { index, page in
                        pageRow(
                            page,
                            number: index + 1
                        )
                    }
                    .onMove(
                        perform: session.move
                    )
                    .onDelete(
                        perform: session.remove
                    )
                }
                .listStyle(.plain)
            }

            Divider()

            HStack(spacing: 12) {
                Button(
                    "페이지 추가",
                    systemImage: "camera"
                ) {
                    startAnotherPage()
                }
                .buttonStyle(.bordered)
                .disabled(
                    !session.canAddPage
                )

                Spacer()

                Button(
                    "문서로 열기",
                    systemImage:
                        "doc.text.magnifyingglass"
                ) {
                    openScannedDocument()
                }
                .buttonStyle(.bordered)
                .disabled(
                    session.pages.isEmpty
                )

                Button(
                    "PDF로 저장",
                    systemImage:
                        "square.and.arrow.down"
                ) {
                    exportPDF()
                }
                .buttonStyle(
                    .borderedProminent
                )
                .disabled(
                    session.pages.isEmpty
                )
            }
            .controlSize(.large)
            .padding(20)
        }
        .background(
            Color(
                uiColor:
                    .systemBackground
            )
        )
    }

    private func pageRow(
        _ page: DocumentScanPageRecord,
        number: Int
    ) -> some View {
        HStack(spacing: 16) {
            Group {
                if let image =
                        session.image(
                            for: page
                        ) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(
                        systemName:
                            "exclamationmark.triangle"
                    )
                    .foregroundStyle(.red)
                }
            }
            .frame(
                width: 90,
                height: 110
            )
            .background(Color.black)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 10,
                    style: .continuous
                )
            )
            .accessibilityHidden(true)

            VStack(
                alignment: .leading,
                spacing: 6
            ) {
                Text("페이지 \(number)")
                    .font(.headline)
                Text(
                    page.capturedAt,
                    style: .time
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                Text(
                    "오른쪽으로 \(page.normalizedQuarterTurns * 90)도 회전"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button(
                "회전",
                systemImage:
                    "rotate.right"
            ) {
                session.rotate(page)
            }
            .buttonStyle(.bordered)
            .accessibilityHint(
                "페이지를 오른쪽으로 90도 회전합니다."
            )

            Button(
                "삭제",
                systemImage: "trash",
                role: .destructive
            ) {
                session.remove(page)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 6)
        .accessibilityElement(
            children: .contain
        )
    }

    private var preparingOverlay:
        some View
    {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                Text(
                    "여러 페이지 문서를 만드는 중입니다."
                )
                .font(.headline)
                .foregroundStyle(.white)
            }
            .padding(28)
            .background(
                Color.black.opacity(0.75)
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )
        }
        .accessibilityElement(
            children: .combine
        )
    }

    private var defaultPDFFileName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(
            identifier: "en_US_POSIX"
        )
        formatter.dateFormat =
            "yyyyMMdd_HHmm"
        return "VisionCraft Scan "
            + formatter.string(
                from: Date()
            )
    }

    private func reviewCapturedPage(
        _ image: UIImage
    ) {
        pendingImage = image
        phase = .capturedPageReview
        UIAccessibility.post(
            notification:
                .screenChanged,
            argument: "촬영 결과"
        )
    }

    private func retakePage() {
        pendingImage = nil
        scannerCommand = .resume(
            id: UUID()
        )
        phase = .camera
    }

    private func saveAndContinue() {
        guard let pendingImage,
              session.append(
                pendingImage
              ) else {
            return
        }
        self.pendingImage = nil
        scannerCommand =
            .acceptAndContinue(
                id: UUID(),
                capturedPageCount:
                    session.pages.count
            )
        phase = .camera
    }

    private func saveAndFinish() {
        guard let pendingImage,
              session.append(
                pendingImage
              ) else {
            return
        }
        self.pendingImage = nil
        scannerCommand = .finish(
            id: UUID(),
            capturedPageCount:
                session.pages.count
        )
        phase = .pageReview
        UIAccessibility.post(
            notification:
                .screenChanged,
            argument: "스캔 페이지 검토"
        )
    }

    private func openSinglePageOCR() {
        guard let pendingImage else {
            return
        }
        scannerCommand = .finish(
            id: UUID(),
            capturedPageCount: 1
        )
        session.discard()
        appRouter.route =
            .OCRResult(
                image: pendingImage
            )
    }

    private func startAnotherPage() {
        guard session.canAddPage else {
            return
        }
        scannerCommand = .start(
            id: UUID()
        )
        phase = .camera
    }

    private func openScannedDocument() {
        guard !session.pages.isEmpty else {
            return
        }
        isPreparingDocument = true
        Task {
            do {
                let url =
                    try await session
                    .writeWorkingPDF()
                session.discard()
                isPreparingDocument = false
                appRouter.route =
                    .localDocument(
                        fileURL: url
                    )
            } catch {
                isPreparingDocument = false
                errorMessage =
                    error.localizedDescription
            }
        }
    }

    private func exportPDF() {
        guard !session.pages.isEmpty else {
            return
        }
        isPreparingDocument = true
        Task {
            do {
                let data =
                    try await session
                    .makePDFData()
                exportDocument =
                    ScannedPDFFileDocument(
                        data: data
                    )
                isPreparingDocument = false
                isExporting = true
            } catch {
                isPreparingDocument = false
                errorMessage =
                    error.localizedDescription
            }
        }
    }

    private func handleScannerCancel() {
        pendingImage = nil
        if session.pages.isEmpty {
            session.discard()
            dismiss()
        } else {
            phase = .pageReview
        }
    }

    private func requestClose() {
        guard !session.pages.isEmpty else {
            session.discard()
            dismiss()
            return
        }
        showsDiscardConfirmation = true
    }
}

private enum DocumentScannerCommand:
    Equatable
{
    case resume(id: UUID)
    case acceptAndContinue(
        id: UUID,
        capturedPageCount: Int
    )
    case finish(
        id: UUID,
        capturedPageCount: Int
    )
    case start(id: UUID)

    var id: UUID {
        switch self {
        case .resume(let id),
             .start(let id):
            return id
        case .acceptAndContinue(
            let id,
            _
        ),
        .finish(let id, _):
            return id
        }
    }
}

private struct DocumentScannerController:
    UIViewControllerRepresentable
{
    let remoteEvent:
        RivoScreenRemoteEvent?
    let command:
        DocumentScannerCommand?
    let isActive: Bool
    let automaticCaptureEnabled: Bool
    let curvedPageCorrectionEnabled: Bool
    let onScanCompleted:
        (UIImage) -> Void
    let onCancel:
        () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(
        context: Context
    ) -> DocumentScannerViewController {
        let controller =
            DocumentScannerViewController()
        controller.allowsAutomaticStart =
            isActive
        controller.automaticCaptureEnabled =
            automaticCaptureEnabled
        controller.curvedPageCorrectionEnabled =
            curvedPageCorrectionEnabled
        controller.onScanCompleted =
            onScanCompleted
        controller.onCancel = onCancel
        controller.synchronizeRemoteEventCursor(
            to: remoteEvent?.id
        )
        return controller
    }

    func updateUIViewController(
        _ controller:
            DocumentScannerViewController,
        context: Context
    ) {
        controller.onScanCompleted =
            onScanCompleted
        controller.onCancel = onCancel
        controller.allowsAutomaticStart =
            isActive
        controller.automaticCaptureEnabled =
            automaticCaptureEnabled
        controller.curvedPageCorrectionEnabled =
            curvedPageCorrectionEnabled

        if let remoteEvent,
           remoteEvent.id
            != context.coordinator
                .lastRemoteEventID,
           case .documentScanner(
               let action
           ) = remoteEvent.action {
            context.coordinator
                .lastRemoteEventID =
                remoteEvent.id
            controller.performRemoteAction(
                action,
                eventID: remoteEvent.id
            )
        }

        guard let command,
              command.id
                != context.coordinator
                    .lastCommandID else {
            return
        }
        context.coordinator.lastCommandID =
            command.id
        switch command {
        case .resume:
            controller.resumeAfterReview()
        case .acceptAndContinue(
            _,
            let capturedPageCount
        ):
            controller
                .acceptPageAndContinue(
                    capturedPageCount:
                        capturedPageCount
                )
        case .finish(
            _,
            let capturedPageCount
        ):
            controller.finishReview(
                capturedPageCount:
                    capturedPageCount
            )
        case .start:
            controller
                .startNewPageSession()
        }
    }

    final class Coordinator {
        var lastRemoteEventID:
            UInt64?
        var lastCommandID:
            UUID?
    }
}

private struct ScannedPDFFileDocument:
    FileDocument
{
    static var readableContentTypes:
        [UTType]
    {
        [.pdf]
    }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(
        configuration:
            ReadConfiguration
    ) throws {
        data =
            configuration.file
            .regularFileContents
            ?? Data()
    }

    func fileWrapper(
        configuration:
            WriteConfiguration
    ) throws -> FileWrapper {
        FileWrapper(
            regularFileWithContents:
                data
        )
    }
}
