import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// 시작 홈(기존 홈·위젯 런처)과 관계없이 홈 루트가 받는 요청: 음성 동작의 파일 열기
/// (`AppRouter.requestFileImport`)와 리모컨·사용법 안내의 텍스트 원본 선택(`AppRouter.requestTextSource`).
/// `AppHomeRoot`가 두 홈 모두에 붙인다.
struct HomeImportRequestPresenter: ViewModifier {
    @EnvironmentObject private var appRouter: AppRouter
    @State private var isFileImporterPresented = false
    @State private var fileImportPurpose: HomeFileImportPurpose = .general
    @State private var isTextViewPhotoPickerPresented = false
    @State private var selectedTextViewPhotoItem: PhotosPickerItem?
    @State private var isLoadingTextViewPhoto = false
    @State private var fileImportError: String?
    @State private var isTextSourceDialogPresented = false
    @State private var textViewClipboardText: String?

    func body(content: Content) -> some View {
        ZStack {
            content
                .accessibilityHidden(isOverlayPresented)
                .allowsHitTesting(!isOverlayPresented)

            if isTextSourceDialogPresented {
                VisionCraftTextSourceDialog(
                    showsClipboard: textViewClipboardText != nil,
                    onImage: { presentTextViewPhotoPicker() },
                    onDocument: { presentTextViewDocumentImporter() },
                    onClipboard: { openClipboardInTextView() },
                    onDismiss: {
                        isTextSourceDialogPresented = false
                        textViewClipboardText = nil
                    }
                )
                .tint(VisionCraftUI.primary)
            }

            if isLoadingTextViewPhoto {
                Color.black.opacity(0.52)
                    .ignoresSafeArea()
                ProgressView(AppLocalization.string("사진을 불러오는 중…"))
                    .font(.headline)
                    .padding(24)
                    .visionCraftHomeSurface(cornerRadius: 24)
                    .tint(VisionCraftUI.primary)
            }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: fileImportPurpose.allowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .photosPicker(
            isPresented: $isTextViewPhotoPickerPresented,
            selection: $selectedTextViewPhotoItem,
            matching: .images
        )
        .alert(
            "파일을 열 수 없습니다",
            isPresented: Binding(
                get: { fileImportError != nil },
                set: { if !$0 { fileImportError = nil } }
            )
        ) {
            Button("확인", role: .cancel) { fileImportError = nil }
        } message: {
            Text(fileImportError ?? "")
        }
        .onChange(of: selectedTextViewPhotoItem) { _, item in
            guard let item else { return }
            Task { await openTextViewPhoto(item) }
        }
        .onChange(of: appRouter.fileImportRequestID) { oldValue, newValue in
            guard newValue != oldValue else { return }
            fileImportPurpose = .general
            isFileImporterPresented = true
        }
        .onChange(of: appRouter.textSourceRequestID) { oldValue, newValue in
            guard newValue != oldValue else { return }
            presentTextSourceDialog()
        }
    }

    private var isOverlayPresented: Bool {
        isTextSourceDialogPresented || isLoadingTextViewPhoto
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        let purpose = fileImportPurpose
        fileImportPurpose = .general
        Task {
            do {
                guard let sourceURL = try result.get().first else { return }
                let route = try await LocalFileOpening.route(for: sourceURL)
                if purpose == .textDocument, case .localDocument(let fileURL) = route {
                    appRouter.route = .textEditorDocument(fileURL: fileURL)
                } else {
                    appRouter.route = route
                }
            } catch {
                fileImportError = error.localizedDescription
            }
        }
    }

    private func presentTextSourceDialog() {
        textViewClipboardText = HomeTextSourcePolicy.availableClipboardText(UIPasteboard.general.string)
        isTextSourceDialogPresented = true
    }

    private func openClipboardInTextView() {
        guard let textViewClipboardText else {
            isTextSourceDialogPresented = false
            return
        }
        isTextSourceDialogPresented = false
        self.textViewClipboardText = nil
        appRouter.route = .textEditorText(
            title: AppLocalization.string("클립보드 텍스트"),
            text: textViewClipboardText
        )
    }

    private func presentTextViewPhotoPicker() {
        isTextSourceDialogPresented = false
        textViewClipboardText = nil
        Task { @MainActor in
            await Task.yield()
            isTextViewPhotoPickerPresented = true
        }
    }

    private func presentTextViewDocumentImporter() {
        isTextSourceDialogPresented = false
        textViewClipboardText = nil
        Task { @MainActor in
            await Task.yield()
            fileImportPurpose = .textDocument
            isFileImporterPresented = true
        }
    }

    @MainActor
    private func openTextViewPhoto(_ item: PhotosPickerItem) async {
        isLoadingTextViewPhoto = true
        defer {
            isLoadingTextViewPhoto = false
            selectedTextViewPhotoItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                throw HomeTextSourceImportError.invalidImage
            }
            appRouter.route = .textEditorImage(image: image)
        } catch {
            fileImportError = error.localizedDescription
        }
    }
}

// MARK: - 파일·텍스트 원본

private enum HomeFileImportPurpose: Equatable {
    case general
    case textDocument

    var allowedContentTypes: [UTType] {
        switch self {
        case .general:
            return VisionCraftFileTypes.openable
        case .textDocument:
            return VisionCraftFileTypes.documents
        }
    }
}

private enum HomeTextSourceImportError:
    LocalizedError
{
    case invalidImage

    var errorDescription: String? {
        AppLocalization.string(
            "선택한 사진을 읽을 수 없습니다."
        )
    }
}

/// 리모컨·사용법 안내에서 텍스트 원본을 고르라고 요청했을 때 쓰는 다이얼로그.
private struct VisionCraftTextSourceDialog: View {
    let showsClipboard: Bool
    let onImage: () -> Void
    let onDocument: () -> Void
    let onClipboard: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VisionCraftDialogCard(
            title: "텍스트 가져오기",
            tone: .reading,
            onDismiss: onDismiss
        ) {
            if showsClipboard {
                VisionCraftDialogOptionRow(
                    title: "클립보드",
                    subtitle: "복사해 둔 텍스트를 붙여 넣습니다.",
                    systemImage: "doc.on.clipboard",
                    isPrimary: true,
                    accent: VisionCraftHomeUI.logoAccent(0),
                    action: onClipboard
                )
            }
            VisionCraftDialogOptionRow(
                title: "이미지",
                subtitle: "사진 앨범에서 고른 이미지의 글자를 읽어옵니다.",
                systemImage: "photo",
                accent: VisionCraftHomeUI.logoAccent(1),
                action: onImage
            )
            VisionCraftDialogOptionRow(
                title: "문서",
                subtitle: "파일 앱에서 텍스트·문서 파일을 엽니다.",
                systemImage: "doc.text",
                accent: VisionCraftHomeUI.logoAccent(2),
                action: onDocument
            )
        }
    }
}
