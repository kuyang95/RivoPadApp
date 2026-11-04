#if DEBUG
import SwiftUI
import UniformTypeIdentifiers
import ZIPFoundation

struct ScannerCalibrationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var assessment = ""
    @State private var message = ""
    @State private var runs: [URL] = []
    @State private var recorder: ScannerCalibrationRecorder?
    @State private var showingScanner = false
    @State private var busy = false
    @State private var exportURL: URL?
    @State private var showingExport = false
    @State private var confirmDelete = false

    var body: some View {
        VStack(spacing: 0) {
            VisionCraftScreenTitleRow(title: "문서스캔 실측보정", onBack: { dismiss() })
                .padding(.horizontal, 24).padding(.top, 12)
            Form {
                Section("새 테스트") {
                    Text("바닥·그림자·종이를 적고 테스트하세요. 촬영이 안 돼도 테스트를 종료하면 기록이 남습니다.")
                    TextField("예: 나무 책상 / 그림자 / 영수증", text: $label)
                    Text("테스트 장면·촬영 원본·결과 이미지와 OCR 원문이 이 기기에 저장됩니다. 실측 기록은 자동 전송하지 않으며 내보내기 ZIP에 포함됩니다. OCR 교정은 기존 설정대로 동작합니다.")
                        .font(.footnote)
                    Button("테스트 시작") {
                        do {
                            recorder = try ScannerCalibrationRecorder.start(label: label)
                            showingScanner = true
                        } catch { message = error.localizedDescription }
                    }.disabled(busy)
                }
                Section("저장된 테스트 \(runs.count)개") {
                    if !runs.isEmpty {
                        TextField("최근 테스트 평가·추가 메모", text: $assessment)
                        HStack { ForEach(["정상", "잘림", "오탐"], id: \.self) { value in Button(value) { assessment = value } } }
                        HStack { ForEach(["촬영 안 됨", "흐림"], id: \.self) { value in Button(value) { assessment = value } } }
                        Button("최근 테스트 평가 저장") { saveAssessment() }.disabled(busy)
                        Button("전체 기록 ZIP 내보내기") { export() }.disabled(busy)
                        Button("저장된 테스트 전체 삭제", role: .destructive) { confirmDelete = true }.disabled(busy)
                        ForEach(runs.prefix(15), id: \.self) { run in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(runLabel(run))
                                Text(run.lastPathComponent).font(.caption).textSelection(.enabled)
                                Text(runStatus(run)).font(.caption)
                            }
                        }
                    }
                    if busy { ProgressView() }
                    if !message.isEmpty { Text(message).accessibilityLabel(message) }
                }
            }
            .environment(\.defaultMinListRowHeight, VisionCraftUI.minTouchTarget)
            .visionCraftListScreen()
        }
        .background(VisionCraftUI.background.ignoresSafeArea()).tint(VisionCraftUI.primary)
        .toolbar(.hidden, for: .navigationBar)
        .task { refresh() }
        .fullScreenCover(isPresented: $showingScanner, onDismiss: finishTrial) {
            VStack(spacing: 0) {
                Button("테스트 종료하고 기록으로 돌아가기") { showingScanner = false }
                    .buttonStyle(VisionCraftAndroidButtonStyle()).padding(8)
                DocumentScanRootView(calibrationTrial: true)
            }
            .background(VisionCraftUI.background)
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showingExport) {
            if let exportURL { CalibrationShareSheet(url: exportURL) }
        }
        .confirmationDialog("테스트 기록을 모두 삭제할까요? 내보내기 ZIP을 보관한 뒤 삭제하세요.", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("전체 삭제", role: .destructive) {
                do { try FileManager.default.removeItem(at: ScannerCalibrationRecorder.root()); refresh(); message = "기록을 삭제했습니다." }
                catch { message = error.localizedDescription }
            }
        }
        .visionCraftHandlesBackNavigation()
    }

    private func refresh() {
        guard let root = try? ScannerCalibrationRecorder.root() else { return }
        let previous = runs.first
        runs = ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        if runs.first != previous, let run = runs.first,
           let data = try? Data(contentsOf: run.appendingPathComponent("assessment.json")),
           let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { assessment = value["note"] as? String ?? "" }

    }
    private func runLabel(_ url: URL) -> String {
        guard let data = try? Data(contentsOf: url.appendingPathComponent("metadata.json")),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "테스트" }
        let label = value["label"] as? String ?? ""
        return label.isEmpty ? "조건 메모 없음" : label
    }
    private func runStatus(_ url: URL) -> String {
        guard let data = try? Data(contentsOf: url.appendingPathComponent("status.json")),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "중단됨 / 저장 중" }
        return value["state"] as? String == "storage_error" ? "저장 오류: \(value["storageError"] as? String ?? "")" : "종료됨"
    }
    private func finishTrial() {
        busy = true
        Task {
            await recorder?.finish()
            recorder = nil; busy = false
            message = "테스트 기록을 저장했습니다. 결과 평가를 남겨 주세요."
            refresh()
            assessment = ""
        }
    }
    private func saveAssessment() {
        guard let dir = runs.first else { return }
        do {
            let value = ["note": assessment, "at": ISO8601DateFormatter().string(from: Date())]
            try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted]).write(to: dir.appendingPathComponent("assessment.json"), options: .atomic)
            message = "평가를 저장했습니다."
        } catch { message = error.localizedDescription }
    }
    private func export() {
        busy = true
        Task {
            do {
                let root = try ScannerCalibrationRecorder.root()
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("scanner-calibration-\(UUID().uuidString).zip")
                try await Task.detached(priority: .utility) { try FileManager.default.zipItem(at: root, to: url) }.value
                exportURL = url; showingExport = true
            } catch { message = "내보내기 실패: \(error.localizedDescription)" }
            busy = false
        }
    }
}

private struct CalibrationShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
