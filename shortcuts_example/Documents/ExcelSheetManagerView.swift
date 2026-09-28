import SwiftUI

struct ExcelSheetManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ExcelWorkbookViewModel
    @State private var name = ""
    @State private var pendingDeletion: ExcelWorksheet?
    @State private var confirmsDeletion = false

    private var sheets: [ExcelWorksheet] { viewModel.workbook?.sheets ?? [] }
    private var selected: ExcelWorksheet? { viewModel.selectedSheet }

    var body: some View {
        NavigationStack {
            List {
                if let restriction = viewModel.sheetManagementRestriction {
                    Section { Text(restriction).foregroundStyle(.secondary) }
                }
                Section {
                    ForEach(sheets) { sheet in
                        Button {
                            if let index = sheets.firstIndex(where: { $0.id == sheet.id }) { viewModel.selectSheet(index) }
                            name = sheet.name
                        } label: {
                            HStack {
                                Text(verbatim: sheet.name).foregroundStyle(VisionCraftUI.primaryText)
                                Spacer()
                                if selected?.id == sheet.id {
                                    Text("선택됨").font(.caption).foregroundStyle(VisionCraftUI.primary)
                                }
                            }
                            .frame(minHeight: 34)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(AppLocalization.format("%@ 시트", sheet.name))
                        .accessibilityAddTraits(selected?.id == sheet.id ? .isSelected : [])
                        .moveDisabled(!viewModel.canManageSheets)
                    }
                    .onMove(perform: move)
                } header: { Text("시트 목록") } footer: {
                    Text("시트를 누르면 선택됩니다. 오른쪽 손잡이를 끌어 순서를 바꿀 수 있습니다.")
                }

                Section {
                    TextField("시트 이름", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("이름 변경") {
                        if let selected { run(.rename(path: selected.partPath, name: name)) }
                    }.disabled(selected == nil || name == selected?.name)
                    Button("시트 복제") {
                        if let selected {
                            let copyName = name == selected.name ? ExcelSheetNames.suggested(base: name, existing: sheets.map(\.name)) : name
                            run(.duplicate(path: selected.partPath, name: copyName))
                        }
                    }
                    Button("새 시트 추가") {
                        let base = AppLocalization.string("새 시트")
                        let newName = (try? ExcelSheetNames.validated(base, existing: sheets.map(\.name))) ?? ExcelSheetNames.suggested(base: base, existing: sheets.map(\.name))
                        run(.add(name: name == selected?.name ? newName : name))
                    }
                } header: { Text("이름과 복사") } footer: {
                    Text("이름을 바꾸지 않고 복제·추가하면 새 이름을 자동으로 만듭니다. 복제본에는 현재 편집 중인 내용도 포함됩니다.")
                }
                .disabled(!viewModel.canManageSheets)

                if let selected, let index = sheets.firstIndex(where: { $0.id == selected.id }) {
                    Section("선택한 시트") {
                        Button("시트를 왼쪽으로") { moveOne(index, by: -1) }.disabled(index == 0)
                        Button("시트를 오른쪽으로") { moveOne(index, by: 1) }.disabled(index == sheets.count - 1)
                        Button("시트 삭제", role: .destructive) {
                            pendingDeletion = selected; confirmsDeletion = true
                        }.disabled(sheets.count <= 1)
                    }.disabled(!viewModel.canManageSheets)
                }

                if !viewModel.status.isEmpty {
                    Section { Text(viewModel.status).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .environment(\.editMode, .constant(viewModel.canManageSheets ? .active : .inactive))
            .navigationTitle("시트 관리")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() }.disabled(viewModel.isSaving) }
            }
            .disabled(viewModel.isSaving)
            .overlay { if viewModel.isSaving { ProgressView().padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
        }
        .tint(VisionCraftUI.primary)
        .interactiveDismissDisabled(viewModel.isSaving)
        .onAppear { name = selected?.name ?? AppLocalization.string("새 시트") }
        .alert("시트를 삭제할까요?", isPresented: $confirmsDeletion) {
            Button("삭제", role: .destructive) {
                if let pendingDeletion { run(.delete(path: pendingDeletion.partPath)) }
                pendingDeletion = nil
            }
            Button("취소", role: .cancel) { pendingDeletion = nil }
        } message: {
            if let pendingDeletion {
                Text(AppLocalization.format("%@ 시트의 모든 내용이 삭제되고, 이 시트를 참조하는 수식은 #REF! 오류가 될 수 있습니다. 실행 취소로 복원할 수 있습니다.", pendingDeletion.name))
            }
        }
    }

    private func run(_ edit: ExcelSheetEdit) {
        Task {
            if await viewModel.performSheetEdit(edit) { name = selected?.name ?? AppLocalization.string("새 시트") }
        }
    }
    private func move(_ offsets: IndexSet, to destination: Int) {
        var paths = sheets.map(\.partPath)
        paths.move(fromOffsets: offsets, toOffset: destination)
        guard paths != sheets.map(\.partPath) else { return }
        run(.reorder(paths: paths))
    }
    private func moveOne(_ index: Int, by offset: Int) {
        var paths = sheets.map(\.partPath)
        guard paths.indices.contains(index + offset) else { return }
        paths.swapAt(index, index + offset)
        run(.reorder(paths: paths))
    }
}
