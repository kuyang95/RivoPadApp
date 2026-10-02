#if DEBUG
import RivoDocumentEngine
import PDFKit
import SwiftUI
import UIKit
import XCTest
@testable import shortcuts_example

@MainActor
final class HWPReferenceComparisonTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func pdfData(pages: Int = 1) -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842)).pdfData { renderer in
            for page in 1...pages {
                renderer.beginPage()
                ("Reference page \(page)" as NSString).draw(at: CGPoint(x: 30, y: 30), withAttributes: nil)
            }
        }
    }

    func testImportAddsPairedHWPXAndPreservesPreviousCasesWithSameName() throws {
        let root = try temporaryDirectory()
        let source = try temporaryDirectory()
        let hwp = source.appendingPathComponent("양식.hwpx")
        let pdf = source.appendingPathComponent("양식.PDF")
        try LegacyHWPXConverter.convert(text: "첫 번째 문서").write(to: hwp)
        try pdfData().write(to: pdf)
        let library = HWPComparisonLibrary(documentsDirectory: root)
        let first = try XCTUnwrap(library.importDocuments([hwp, pdf]).first)
        let original = try Data(contentsOf: first)
        try LegacyHWPXConverter.convert(text: "두 번째 문서").write(to: hwp)
        let second = try XCTUnwrap(library.importDocuments([hwp, pdf]).first)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: first), original)
        let reopened = HWPComparisonLibrary(documentsDirectory: root)
        XCTAssertEqual(try reopened.documents().count, 2)
        XCTAssertNotNil(reopened.referencePDF(for: first))
        XCTAssertNotNil(reopened.referencePDF(for: second))
    }

    func testReferenceOverrideSurvivesRelocationAndDoesNotOverwriteOriginal() throws {
        let root = try temporaryDirectory()
        let source = try temporaryDirectory()
        let library = HWPComparisonLibrary(documentsDirectory: root)
        try FileManager.default.createDirectory(at: library.sourceDirectory, withIntermediateDirectories: true)
        let hwp = library.sourceDirectory.appendingPathComponent("example.hwpx")
        try LegacyHWPXConverter.convert(text: "참조 문서").write(to: hwp)
        let original = hwp.deletingPathExtension().appendingPathExtension("pdf")
        let originalData = pdfData()
        try originalData.write(to: original)
        let selected = source.appendingPathComponent("다른 이름.pdf")
        let replacement = pdfData(pages: 2)
        try replacement.write(to: selected)
        try library.connectReference(selected, to: hwp)
        XCTAssertEqual(try Data(contentsOf: original), originalData)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(library.referencePDF(for: hwp))), replacement)

        let moved = source.appendingPathComponent("MovedDocuments")
        try FileManager.default.copyItem(at: root, to: moved)
        let reopened = HWPComparisonLibrary(documentsDirectory: moved)
        let movedDocument = reopened.sourceDirectory.appendingPathComponent("example.hwpx")
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(reopened.referencePDF(for: movedDocument))), replacement)

        try Data("not a PDF".utf8).write(to: selected)
        XCTAssertThrowsError(try reopened.connectReference(selected, to: movedDocument))
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(reopened.referencePDF(for: movedDocument))), replacement)
    }

    func testInvalidBatchDoesNotLeaveHalfImportedDocuments() throws {
        let root = try temporaryDirectory()
        let source = try temporaryDirectory()
        let library = HWPComparisonLibrary(documentsDirectory: root)
        let hwp = source.appendingPathComponent("valid.hwpx")
        let badPDF = source.appendingPathComponent("valid.pdf")
        try LegacyHWPXConverter.convert(text: "본문").write(to: hwp)
        try Data("invalid pdf".utf8).write(to: badPDF)
        XCTAssertThrowsError(try library.importDocuments([hwp, badPDF]))
        XCTAssertTrue(try library.documents().isEmpty)
        XCTAssertThrowsError(try library.importDocuments([badPDF]))
    }

    func testReviewNotesFollowContentAndSeparateChangedReferences() throws {
        let root = try temporaryDirectory()
        let source = root.appendingPathComponent("source.hwpx")
        let reference = root.appendingPathComponent("reference.pdf")
        try Data("original document".utf8).write(to: source)
        try pdfData().write(to: reference)
        let store = try HWPComparisonReviewStore(document: source, reference: reference, directory: root)
        let note = HWPComparisonReviewNote(kind: .sourceDifference, text: "PDF에만 노란 강조가 있음")
        try store.save(note, pageIndex: 13)
        try store.save(.init(kind: .viewerIssue, text: "제목 확인"), pageIndex: 0)
        let renamed = root.appendingPathComponent("renamed.hwpx")
        try FileManager.default.moveItem(at: source, to: renamed)
        let reopened = try HWPComparisonReviewStore(document: renamed, reference: reference, directory: root)
        XCTAssertEqual(try reopened.note(pageIndex: 13), note)
        try reopened.save(nil, pageIndex: 0)
        XCTAssertNil(try reopened.note(pageIndex: 0))
        XCTAssertEqual(try reopened.note(pageIndex: 13), note)
        try pdfData(pages: 2).write(to: reference)
        let changed = try HWPComparisonReviewStore(document: renamed, reference: reference, directory: root)
        XCTAssertNil(try changed.note(pageIndex: 13), "다른 정답 PDF에 기존 판정을 적용하지 않습니다.")
        try Data("changed source".utf8).write(to: renamed)
        let changedSource = try HWPComparisonReviewStore(document: renamed, reference: reference, directory: root)
        XCTAssertNotEqual(changedSource.fileURL, changed.fileURL)
        XCTAssertNotEqual(changedSource.fileURL, reopened.fileURL)
    }

    func testSourceDifferenceRecordAppearsOnItsPage() async throws {
        let root = try temporaryDirectory(), source = root.appendingPathComponent("source.pdf")
        try pdfData().write(to: source)
        let store = try HWPComparisonReviewStore(document: source, reference: nil, directory: root)
        try store.save(.init(kind: .sourceDifference,
                            text: "원본 HWP는 6·7급 문장만 노란색입니다. 정답 PDF는 8·9급 문장도 노란색이며, 앱은 HWP에 저장된 값을 표시합니다."), pageIndex: 13)
        XCTAssertNil(try store.note(pageIndex: 12))
        try await snapshot(
            VStack {
                Text("14 / 210쪽").font(.headline)
                HWPComparisonReviewBar(documentURL: source, referenceURL: nil, pageIndex: 13, directory: root)
                Spacer()
            }, name: "HWP-source-difference-page-014")
    }

    func testUnreadableReviewArchiveIsNeverOverwritten() throws {
        let root = try temporaryDirectory(), source = root.appendingPathComponent("source.pdf")
        try pdfData().write(to: source)
        let store = try HWPComparisonReviewStore(document: source, reference: nil, directory: root)
        try store.save(.init(kind: .unchecked, text: "확인 중"), pageIndex: 0)
        let invalid = Data("damaged archive".utf8)
        try invalid.write(to: store.fileURL)
        XCTAssertThrowsError(try store.save(.init(kind: .viewerIssue, text: "다른 기록"), pageIndex: 0))
        XCTAssertEqual(try Data(contentsOf: store.fileURL), invalid)
    }

    func testDocumentDiscoveryRefreshesAndIgnoresFoldersAndHiddenFiles() throws {
        let root = try temporaryDirectory()
        let library = HWPComparisonLibrary(documentsDirectory: root)
        XCTAssertTrue(try library.documents().isEmpty)
        try FileManager.default.createDirectory(at: library.sourceDirectory.appendingPathComponent("folder.hwp"), withIntermediateDirectories: true)
        let url = library.sourceDirectory.appendingPathComponent("NEW.HWPX")
        try LegacyHWPXConverter.convert(text: "새 자료").write(to: url)
        try Data().write(to: library.sourceDirectory.appendingPathComponent(".hidden.hwp"))
        XCTAssertEqual(try library.documents(), [url])
        try pdfData().write(to: library.sourceDirectory.appendingPathComponent("new.PDF"))
        XCTAssertNotNil(library.referencePDF(for: url))
        try FileManager.default.removeItem(at: url)
        XCTAssertTrue(try library.documents().isEmpty)
    }

    func testLiveComparisonReloadsEditedSourceAndReference() async throws {
        let root = try temporaryDirectory()
        let library = HWPComparisonLibrary(documentsDirectory: root)
        try FileManager.default.createDirectory(at: library.sourceDirectory, withIntermediateDirectories: true)
        let url = library.sourceDirectory.appendingPathComponent("live.hwpx")
        try LegacyHWPXConverter.convert(text: "수정 전").write(to: url)
        let model = HWPReferenceComparisonModel(hwpURL: url, library: library)
        await model.load()
        XCTAssertNil(model.error)
        XCTAssertTrue(model.pages.flatMap(\.bodyBlocks).contains { $0.text.contains("수정 전") })
        let reference = root.appendingPathComponent("selected.pdf")
        try pdfData(pages: 2).write(to: reference)
        try LegacyHWPXConverter.convert(text: "수정 후").write(to: url, options: .atomic)
        try await model.connectReference(reference)
        XCTAssertNil(model.error)
        XCTAssertEqual(model.pdf?.pageCount, 2)
        XCTAssertTrue(model.status.contains("쪽수 다름"))
        XCTAssertTrue(model.pages.flatMap(\.bodyBlocks).contains { $0.text.contains("수정 후") })
        XCTAssertFalse(model.pages.flatMap(\.bodyBlocks).contains { $0.text.contains("수정 전") })
    }

    func testSavedResultViewerOpensPDFPagesAndRejectsNonPDFBooks() throws {
        let root = try temporaryDirectory()
        let url = root.appendingPathComponent("comparison.pdf")
        try pdfData(pages: 3).write(to: url)
        let viewer = HWPComparisonPDFViewer()
        viewer.open(url)
        XCTAssertNil(viewer.error)
        XCTAssertEqual(viewer.pageCount, 3)
        XCTAssertEqual(viewer.pdfView.document?.documentURL, url)
        XCTAssertEqual(viewer.pdfView.displayMode, .singlePage)
        viewer.go(to: 2)
        XCTAssertEqual(viewer.pageIndex, 2)
        XCTAssertEqual(viewer.pdfView.currentPage?.string?.trimmingCharacters(in: .whitespacesAndNewlines), "Reference page 3")
        viewer.go(to: 3)
        XCTAssertEqual(viewer.pageIndex, 2)
        let archive = root.appendingPathComponent("book.zip")
        try Data([0x50, 0x4B, 0x03, 0x04]).write(to: archive)
        viewer.open(archive)
        XCTAssertNotNil(viewer.error)
        XCTAssertNil(viewer.pdfView.document)
        XCTAssertEqual(viewer.pageCount, 0)
    }

    func testInstalledSavedPDFsDisplayOriginalPagesOnM4() async throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("저장된 비교 PDF 화면은 자료가 설치된 iPad에서 검증합니다.")
        }
        let results = try HWPComparisonLibrary.current.resultPDFs()
        XCTAssertEqual(results.count, 2)
        for url in results {
            let viewer = HWPComparisonPDFViewer()
            viewer.open(url)
            XCTAssertNil(viewer.error, url.lastPathComponent)
            XCTAssertEqual(viewer.pageCount, 210)
            XCTAssertFalse(viewer.bookmarks.isEmpty)
            XCTAssertEqual(viewer.pdfView.document?.documentURL, url)
            let isComparison = url.lastPathComponent.contains("눈으로비교")
            try await snapshot(
                HWPComparisonPDFView(fileURL: url),
                name: isComparison ? "HWP-saved-comparison-PDF-original" : "HWP-saved-reference-PDF-original",
                expectedPDFURL: url,
                expectedPDFPage: 0
            )
            if isComparison {
                try await snapshot(
                    HWPComparisonPDFView(fileURL: url, initialPageIndex: 53),
                    name: "HWP-saved-comparison-PDF-page-54",
                    expectedPDFURL: url,
                    expectedPDFPage: 53
                )
            }
        }
    }

    func testInstalledSourceDifferenceNotesOnM4() async throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("설치된 비교 기록은 M4에서 검증합니다.")
        }
        let library = HWPComparisonLibrary.current
        let original = try XCTUnwrap(library.documents().first { $0.lastPathComponent == "FP01_kcg_workshop.hwp" })
        let reference = try XCTUnwrap(library.referencePDF(for: original))
        let originalStore = try HWPComparisonReviewStore(document: original, reference: reference,
                                                         directory: library.documentsDirectory)
        XCTAssertEqual(try originalStore.note(pageIndex: 13)?.kind, .sourceDifference)
        for url in try library.resultPDFs() {
            let store = try HWPComparisonReviewStore(document: url, reference: nil, directory: library.documentsDirectory)
            let note = try XCTUnwrap(store.note(pageIndex: 13))
            XCTAssertEqual(note.kind, .sourceDifference)
            XCTAssertTrue(note.text.contains("8·9급"))
            XCTAssertNil(try store.note(pageIndex: 12))
            try await snapshot(
                HWPComparisonPDFView(fileURL: url, initialPageIndex: 13),
                name: url.lastPathComponent.contains("눈으로비교") ? "HWP-installed-comparison-note-014" : "HWP-installed-reference-note-014",
                expectedPDFURL: url, expectedPDFPage: 13)
        }
        try await snapshot(HWPReferenceComparisonPageView(hwpURL: original, library: library, initialPageIndex: 13),
                           name: "HWP-installed-live-note-014")
    }

    func testInstalledM4ComparisonLibraryAndActualScreens() async throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("설정 비교 화면은 자료가 설치된 iPad에서 검증합니다.")
        }
        let library = HWPComparisonLibrary.current
        let documents = try library.documents()
        let official = documents.filter { $0.lastPathComponent.hasPrefix("FP") }
        XCTAssertEqual(official.count, 10)
        for url in official {
            let model = HWPReferenceComparisonModel(hwpURL: url, library: library)
            await model.load()
            XCTAssertNil(model.error, url.lastPathComponent)
            XCTAssertNotNil(model.pdf, url.lastPathComponent)
            XCTAssertEqual(model.pages.count, model.pdf?.pageCount, url.lastPathComponent)
        }
        let results = try library.resultPDFs()
        XCTAssertEqual(results.count, 2)
        for url in results { XCTAssertEqual(PDFDocument(url: url)?.pageCount, 210) }
        try await snapshot(HWPReferenceComparisonView(library: library), name: "HWP-comparison-settings-list")
        let table = try XCTUnwrap(official.first { $0.lastPathComponent.hasPrefix("FP03") })
        try await snapshot(HWPReferenceComparisonPageView(hwpURL: table, library: library), name: "HWP-comparison-live-table")
        let image = try XCTUnwrap(official.first { $0.lastPathComponent.hasPrefix("FP09") })
        try await snapshot(HWPReferenceComparisonPageView(hwpURL: image, library: library, initialPageIndex: 11), name: "HWP-comparison-live-images")
    }

    private func snapshot<Content: View>(
        _ content: Content,
        name: String,
        expectedPDFURL: URL? = nil,
        expectedPDFPage: Int = 0
    ) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let controller = UIHostingController(rootView: NavigationStack { content })
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        try await Task.sleep(for: .seconds(1))
        controller.view.layoutIfNeeded()
        if let expectedPDFURL {
            let pdfView = try XCTUnwrap(findPDFView(in: controller.view), "선택한 결과는 PDF 원본 화면에서 열려야 합니다.")
            let document = try XCTUnwrap(pdfView.document)
            XCTAssertEqual(document.documentURL, expectedPDFURL)
            XCTAssertEqual(document.pageCount, 210)
            XCTAssertEqual(document.index(for: try XCTUnwrap(pdfView.currentPage)), expectedPDFPage)
        }
        let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image, quality: .original)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func findPDFView(in view: UIView) -> PDFView? {
        if let pdf = view as? PDFView { return pdf }
        return view.subviews.lazy.compactMap { self.findPDFView(in: $0) }.first
    }
}
#endif
