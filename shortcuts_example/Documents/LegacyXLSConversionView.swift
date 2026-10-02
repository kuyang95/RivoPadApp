import RivoDocumentEngine
import Foundation
import SwiftUI
import Combine
import UniformTypeIdentifiers

@MainActor
private final class LegacyXLSPreviewViewModel:
    ObservableObject
{
    @Published private(set) var workbook:
        LegacyXLSWorkbookSnapshot?
    @Published private(set) var isLoading = true
    @Published private(set) var errorDescription:
        String?

    private let fileURL: URL
    private var didLoad = false

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() async {
        guard !didLoad else { return }
        didLoad = true
        isLoading = true
        errorDescription = nil
        let sourceURL = fileURL
        do {
            workbook = try await Task.detached(
                priority: .userInitiated
            ) {
                let data = try
                    CoordinatedDocumentFileAccess
                    .readData(from: sourceURL)
                return try LegacyXLSExtractor
                    .workbook(from: data)
            }.value
        } catch {
            errorDescription =
                error.localizedDescription
        }
        isLoading = false
    }
}

private struct LegacyXLSPreviewRow:
    Identifiable
{
    let row: Int
    let cells: [LegacyXLSCellSnapshot]

    var id: Int { row }
}

struct LegacyXLSConversionView: View {
    @EnvironmentObject private var appRouter:
        AppRouter

    let fileURL: URL

    @StateObject private var previewViewModel:
        LegacyXLSPreviewViewModel

    @State private var showsLossNotice = false
    @State private var isConverting = false
    @State private var isExporting = false
    @State private var selectedSheetIndex = 0
    @State private var exportDocument:
        LegacyXLSXExportDocument?
    @State private var conversionErrorDescription:
        String?

    init(fileURL: URL) {
        self.fileURL = fileURL
        _previewViewModel = StateObject(
            wrappedValue:
                LegacyXLSPreviewViewModel(
                    fileURL: fileURL
                )
        )
    }

    var body: some View {
        ZStack {
            Group {
                if previewViewModel.isLoading {
                    ExcelDocumentLoadingView()
                } else if let error =
                    previewViewModel
                        .errorDescription {
                    ContentUnavailableView(
                        "XLS 문서를 열 수 없습니다",
                        systemImage:
                            "tablecells.badge.ellipsis",
                        description: Text(error)
                    )
                } else if let workbook =
                    previewViewModel.workbook {
                    workbookPreview(workbook)
                }
            }

            if isConverting {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                ProgressView(
                    AppLocalization.string(
                        "XLSX로 변환 중…"
                    )
                )
                .font(.headline)
                .padding(24)
                .background(
                    VisionCraftUI.surface,
                    in: RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    )
                )
                .tint(VisionCraftUI.primary)
                .accessibilityAddTraits(
                    .updatesFrequently
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(
            fileURL.lastPathComponent
        )
        .navigationBarTitleDisplayMode(.inline)
        .visionCraftNavigationScreen()
        .toolbar {
            ToolbarItem(
                placement: .primaryAction
            ) {
                Button(
                    "XLSX로 변환",
                    systemImage: "arrow.up.doc"
                ) {
                    showsLossNotice = true
                }
                .disabled(isConverting)
                .accessibilityHint(
                    "셀 값을 새 XLSX 파일로 저장한 뒤 편집기에서 엽니다."
                )
            }
        }
        .alert(
            "XLS를 XLSX로 변환",
            isPresented: $showsLossNotice
        ) {
            Button("취소", role: .cancel) {}
            Button("변환 후 저장") {
                beginConversion()
            }
        } message: {
            Text(
                "시트 이름과 셀의 문자열·숫자·불리언, 저장된 수식 결과만 옮깁니다. 수식 원문, 서식, 병합 셀, 행·열 크기, 차트, 이미지와 매크로는 유지되지 않습니다. 원본 XLS는 변경하지 않습니다."
            )
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType:
                VisionCraftFileTypes.xlsx,
            defaultFilename:
                convertedFileName
        ) { result in
            exportDocument = nil
            switch result {
            case .success(let savedURL):
                registerAndOpen(savedURL)
            case .failure(let error):
                conversionErrorDescription =
                    error.localizedDescription
            }
        }
        .alert(
            "XLSX로 변환할 수 없습니다",
            isPresented: Binding(
                get: {
                    conversionErrorDescription
                        != nil
                },
                set: { isPresented in
                    if !isPresented {
                        conversionErrorDescription = nil
                    }
                }
            )
        ) {
            Button("확인", role: .cancel) {
                conversionErrorDescription = nil
            }
        } message: {
            Text(
                conversionErrorDescription ?? ""
            )
        }
        .task {
            await previewViewModel.load()
        }
    }

    private func workbookPreview(
        _ workbook:
            LegacyXLSWorkbookSnapshot
    ) -> some View {
        VStack(spacing: 0) {
            VStack(
                alignment: .leading,
                spacing: 10
            ) {
                Label(
                    "Excel 97-2003 XLS 읽기 전용 보기",
                    systemImage: "tablecells"
                )
                .font(.headline)
                Text(
                    "이 화면에서는 시트와 셀 값만 확인합니다. XLSX로 변환하면 행과 셀을 편집할 수 있습니다."
                )
                .font(.subheadline)
                .foregroundStyle(
                    VisionCraftUI.secondaryText
                )
                Button(
                    "XLSX로 변환하고 편집",
                    systemImage:
                        "arrow.up.doc"
                ) {
                    showsLossNotice = true
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
            .padding(16)
            .background(
                VisionCraftUI.surfaceVariant
            )

            if workbook.sheets.count > 1 {
                Picker(
                    "시트 선택",
                    selection:
                        $selectedSheetIndex
                ) {
                    ForEach(
                        workbook.sheets.indices,
                        id: \.self
                    ) { index in
                        Text(
                            workbook.sheets[
                                index
                            ].name
                        )
                        .tag(index)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            if workbook.sheets.indices
                .contains(selectedSheetIndex) {
                let sheet = workbook.sheets[
                    selectedSheetIndex
                ]
                sheetHeader(sheet)
                sheetRows(sheet)
            }
        }
    }

    private func sheetHeader(
        _ sheet: LegacyXLSSheetSnapshot
    ) -> some View {
        HStack {
            Text(sheet.name)
                .font(.headline)
            Spacer()
            Text(
                AppLocalization.format(
                    "%lld개 셀",
                    sheet.cells.count
                )
            )
            .font(.subheadline)
            .foregroundStyle(
                VisionCraftUI.secondaryText
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(VisionCraftUI.surface)
        .accessibilityElement(
            children: .combine
        )
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func sheetRows(
        _ sheet: LegacyXLSSheetSnapshot
    ) -> some View {
        let rows = previewRows(in: sheet)
        if rows.isEmpty {
            ContentUnavailableView(
                "표 값이 없습니다.",
                systemImage: "tablecells"
            )
        } else {
            List(rows) { row in
                VStack(
                    alignment: .leading,
                    spacing: 7
                ) {
                    Text(
                        AppLocalization.format(
                            "원본 %lld행",
                            row.row
                        )
                    )
                    .font(.caption.bold())
                    .foregroundStyle(
                        VisionCraftUI.secondaryText
                    )
                    ForEach(
                        row.cells,
                        id: \.column
                    ) { cell in
                        HStack(
                            alignment:
                                .firstTextBaseline,
                            spacing: 10
                        ) {
                            Text(
                                ExcelCellAddress
                                    .columnName(
                                        cell.column
                                    )
                            )
                            .font(
                                .caption.monospaced()
                                    .bold()
                            )
                            .foregroundStyle(
                                VisionCraftUI
                                    .secondaryText
                            )
                            .frame(
                                width: 30,
                                alignment: .leading
                            )
                            Text(
                                cell.value
                                    .displayText
                            )
                            .foregroundStyle(
                                VisionCraftUI
                                    .primaryText
                            )
                        }
                    }
                }
                .padding(.vertical, 5)
                .accessibilityElement(
                    children: .ignore
                )
                .accessibilityLabel(
                    rowAccessibilityLabel(
                        row
                    )
                )
            }
            .listStyle(.plain)
        }
    }

    private func previewRows(
        in sheet: LegacyXLSSheetSnapshot
    ) -> [LegacyXLSPreviewRow] {
        Dictionary(
            grouping: sheet.cells,
            by: \.row
        )
        .map {
            LegacyXLSPreviewRow(
                row: $0.key,
                cells: $0.value.sorted {
                    $0.column < $1.column
                }
            )
        }
        .sorted { $0.row < $1.row }
    }

    private func rowAccessibilityLabel(
        _ row: LegacyXLSPreviewRow
    ) -> String {
        let values = row.cells.map {
            ExcelCellAddress.columnName(
                $0.column
            )
            + "열 "
            + $0.value.displayText
        }
        return AppLocalization.format(
            "원본 %lld행",
            row.row
        )
        + ". "
        + values.joined(separator: ", ")
    }

    private var convertedFileName: String {
        let base = (
            fileURL.lastPathComponent
                as NSString
        ).deletingPathExtension
        return (base.isEmpty
            ? AppLocalization.string(
                "변환한 스프레드시트"
            )
            : base)
            + ".xlsx"
    }

    private func beginConversion() {
        guard !isConverting else {
            return
        }
        isConverting = true
        conversionErrorDescription = nil
        let sourceURL = fileURL
        Task {
            do {
                let converted = try await
                    Task.detached(
                        priority:
                            .userInitiated
                    ) {
                        let source = try
                            CoordinatedDocumentFileAccess
                            .readData(
                                from: sourceURL
                            )
                        return try
                            LegacyXLSXConverter
                            .convert(
                                from: source
                            )
                    }.value
                exportDocument =
                    LegacyXLSXExportDocument(
                        data: converted
                    )
                isExporting = true
            } catch {
                conversionErrorDescription =
                    error.localizedDescription
            }
            isConverting = false
        }
    }

    private func registerAndOpen(
        _ savedURL: URL
    ) {
        Task {
            do {
                let record = try await
                    RecentOriginalDocumentStore
                    .shared.register(
                        fileURL: savedURL
                    )
                appRouter.route =
                    .originalDocument(
                        documentID:
                            record.id
                    )
            } catch {
                conversionErrorDescription =
                    AppLocalization.format(
                        "XLSX는 저장했지만 최근 문서에 추가하지 못했습니다: %@",
                        error.localizedDescription
                    )
            }
        }
    }
}

private struct LegacyXLSXExportDocument:
    FileDocument
{
    static var readableContentTypes:
        [UTType]
    {
        [VisionCraftFileTypes.xlsx]
    }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(
        configuration: ReadConfiguration
    ) throws {
        guard let data = configuration
            .file.regularFileContents else {
            throw ExcelWorkbookDocumentError
                .invalidWorkbook
        }
        self.data = data
    }

    func fileWrapper(
        configuration:
            WriteConfiguration
    ) throws -> FileWrapper {
        FileWrapper(
            regularFileWithContents: data
        )
    }
}
