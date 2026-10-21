import RivoDocumentEngine
import SwiftUI
import UIKit
import XCTest
@testable import shortcuts_example

/// HWP features carried over from Android: the empty document's `글 쓰기` band,
/// the notice band's button, and VoiceOver actions on a picked object.
@MainActor
final class HWPAndroidParityTests: XCTestCase {
    func testBlankParagraphOnlyForAnEmptyEditableDocument() async throws {
        let empty = try await load(LegacyHWPXConverter.convert(text: ""))
        let blank = try XCTUnwrap(empty.blankParagraphID)
        let block = try XCTUnwrap(empty.blocks.first { $0.id == blank })
        XCTAssertTrue(block.isEditable)
        XCTAssertNil(block.tableLocation)
        XCTAssertEqual(block.region.kind, .body)

        let written = try await load(LegacyHWPXConverter.convert(text: "첫 문단"))
        XCTAssertNil(written.blankParagraphID)
    }

    func testNoticeBandActionIsAButton() async throws {
        var pressed = 0
        let window = host(HWPDocumentNoticeBand(text: "아직 내용이 없는 문서입니다.", detail: nil,
            action: "글 쓰기", identifier: "hwp-notice-start-writing", onAction: { pressed += 1 })
            .frame(width: 700))
        defer { window.isHidden = true }
        let button = try await element(in: window) { $0.identifier == "hwp-notice-start-writing" }
        XCTAssertTrue(button.accessibilityTraits.contains(.button))
        XCTAssertTrue(matches(button.accessibilityLabel ?? "", "글 쓰기"))
        XCTAssertTrue(button.accessibilityActivate())
        XCTAssertEqual(pressed, 1)
        let notice = try await element(in: window) {
            self.matches($0.accessibilityLabel ?? "", "아직 내용이 없는 문서입니다.")
        }
        XCTAssertFalse(notice.accessibilityTraits.contains(.button))
    }

    func testPickedPictureOffersMoveResizeSettingsAndDeselectActions() async throws {
        let (blocks, layouts) = try await documentWithPicture()
        let owner = try XCTUnwrap(blocks.first { !$0.canvasObjects.isEmpty })
        let object = try XCTUnwrap(owner.canvasObjects.first)
        let navigation = HWPDocumentNavigation()
        navigation.update(blocks: blocks, layouts: layouts)
        let page = try XCTUnwrap(navigation.pages.first { page in
            page.bodyBlocks.contains { HWPInlineParagraphGeometry.sourceID($0.id) == owner.id }
        })
        var operations: [HWPImageEditing.DirectManipulation] = []
        var selections = 0
        var deselections = 0
        let session = HWPInlineEditingSession()

        func pageView(selected: Bool) -> some View {
            HWPOriginalCanvasPageView(page: page)
                .environment(\.hwpInlineEditing, HWPInlineEditingContext(session: session))
                .environment(\.hwpCanvasObjectSelection, .editingTargets(in: blocks))
                .environment(\.hwpImageObjectEditing, HWPImageObjectEditingContext(
                    selectedID: selected ? object.id : nil,
                    onSelect: { _, _ in selections += 1 },
                    onDirectManipulation: { _, _, operation in operations.append(operation) },
                    onDeselect: { deselections += 1 }))
        }

        // Not picked: double-tap picks it; no move actions yet.
        let window = host(pageView(selected: false))
        defer { window.isHidden = true }
        let identifier = "hwp-canvas-object-\(object.id)"
        var node = try await element(in: window) { $0.identifier == identifier }
        XCTAssertTrue(node.accessibilityTraits.contains(.button))
        XCTAssertFalse(node.accessibilityTraits.contains(.selected))
        // Read by kind without a description, as on Android.
        XCTAssertEqual(node.accessibilityLabel, expectedLabel(object), "description, else 그림")
        XCTAssertTrue(names(node).isEmpty, "\(names(node))")
        XCTAssertTrue(node.accessibilityActivate())
        XCTAssertEqual(selections, 1)

        // Picked: selected, with Android's object actions.
        (window.rootViewController as? UIHostingController<AnyView>)?.rootView = AnyView(pageView(selected: true))
        node = try await element(in: window) {
            $0.identifier == identifier && $0.accessibilityTraits.contains(.selected)
        }
        let expected = ["위로 이동", "아래로 이동", "왼쪽으로 이동", "오른쪽으로 이동",
                        "개체 크게", "개체 작게", "개체 설정", "선택 해제"]
        XCTAssertEqual(names(node).count, expected.count, "\(names(node))")
        for (name, key) in zip(names(node), expected) { XCTAssertTrue(matches(name, key), "\(name) ≠ \(key)") }

        try perform("위로 이동", on: node)
        try perform("오른쪽으로 이동", on: node)
        try perform("개체 크게", on: node)
        try perform("개체 작게", on: node)
        try perform("개체 설정", on: node)
        try perform("선택 해제", on: node)
        XCTAssertEqual(selections, 2)
        XCTAssertEqual(deselections, 1)
        XCTAssertEqual(operations.count, 4)
        guard operations.count == 4 else { return }
        if case .move(let dx, let dy) = operations[0] { XCTAssertEqual([dx, dy], [0, -20]) } else { XCTFail("\(operations[0])") }
        if case .move(let dx, let dy) = operations[1] { XCTAssertEqual([dx, dy], [20, 0]) } else { XCTFail("\(operations[1])") }
        if case .resize(let anchor, let dx, let dy) = operations[2] {
            XCTAssertEqual(anchor, .bottomTrailing); XCTAssertEqual([dx, dy], [20, 20])
        } else { XCTFail("\(operations[2])") }
        if case .resize(let anchor, let dx, let dy) = operations[3] {
            XCTAssertEqual(anchor, .bottomTrailing); XCTAssertEqual([dx, dy], [-20, -20])
        } else { XCTFail("\(operations[3])") }
    }

    func testOnlyObjectsWithAnEditingTargetAreSelectable() async throws {
        let (blocks, _) = try await documentWithPicture()
        let owner = try XCTUnwrap(blocks.first { !$0.canvasObjects.isEmpty })
        let object = try XCTUnwrap(owner.canvasObjects.first)
        let header = HWPDocumentBlock(id: "header-owner", sectionPath: owner.sectionPath,
            paragraphIndex: 0, text: "", tableLocation: nil, isEditable: true,
            region: HWPDocumentRegion(kind: .header), canvasObjects: [object])
        let selection = HWPCanvasObjectSelection.editingTargets(in: blocks + [header])
        XCTAssertTrue(selection.canSelect(owner.id, object, false))
        XCTAssertFalse(selection.canSelect(header.id, object, false), "header pictures have no editing target")
        XCTAssertFalse(selection.canSelect("missing", object, false))
        XCTAssertFalse(selection.canSelect(owner.id, object, true), "not a text box")
    }

    func testUnselectableObjectIsReadWithoutButtonOrActions() async throws {
        let (blocks, layouts) = try await documentWithPicture(clearsDescription: true)
        let owner = try XCTUnwrap(blocks.first { !$0.canvasObjects.isEmpty })
        let object = try XCTUnwrap(owner.canvasObjects.first)
        let navigation = HWPDocumentNavigation()
        navigation.update(blocks: blocks, layouts: layouts)
        let page = try XCTUnwrap(navigation.pages.first)
        let window = host(HWPOriginalCanvasPageView(page: page)
            .environment(\.hwpInlineEditing, HWPInlineEditingContext(session: HWPInlineEditingSession()))
            .environment(\.hwpCanvasObjectSelection, HWPCanvasObjectSelection { _, _, _ in false })
            .environment(\.hwpImageObjectEditing, HWPImageObjectEditingContext(selectedID: object.id)))
        defer { window.isHidden = true }
        let node = try await element(in: window) { $0.identifier == "hwp-canvas-object-\(object.id)" }
        XCTAssertFalse(node.accessibilityTraits.contains(.button))
        XCTAssertTrue(node.accessibilityHint?.isEmpty ?? true, node.accessibilityHint ?? "")
        XCTAssertTrue(names(node).isEmpty, "\(names(node))")
        XCTAssertTrue(object.description?.isEmpty ?? true, object.description ?? "")
        // No description: read by kind, as on Android.
        XCTAssertTrue(matches(node.accessibilityLabel ?? "", "그림"), node.accessibilityLabel ?? "")
    }

    func testOriginalPageOffersPageAndParagraphEditingActions() async throws {
        let model = try await load(LegacyHWPXConverter.convert(text: "첫 문단"))
        let navigation = HWPDocumentNavigation()
        navigation.update(blocks: model.blocks, layouts: model.pageLayouts)
        let page = try XCTUnwrap(navigation.pages.first)
        let paragraph = try XCTUnwrap(model.blocks.first { $0.text == "첫 문단" })
        var moves: [String] = []
        var opened: [String] = []
        let session = HWPInlineEditingSession()
        let window = host(HWPOriginalCanvasPageView(page: page)
            .environment(\.hwpInlineEditing, HWPInlineEditingContext(session: session,
                sources: Dictionary(uniqueKeysWithValues: model.blocks.map { ($0.id, $0) }),
                orderedBlocks: model.blocks,
                onOpenParagraphEditor: { opened.append($0) }))
            .environment(\.hwpPageAccessibility, HWPPageAccessibilityContext(
                previous: { moves.append("previous") }, next: { moves.append("next") })))
        defer { session.finish(); window.isHidden = true }

        // The page reads first by its name, with Android's page actions.
        let paper = try await element(in: window) { $0.identifier == "hwp-page-\(page.id)" }
        XCTAssertTrue(matches(paper.accessibilityLabel ?? "", "한글 원본 문서 · %lld쪽")
            || (paper.accessibilityLabel ?? "").contains("\(page.pageNumber)"), paper.accessibilityLabel ?? "")
        XCTAssertEqual(names(paper).count, 2, "\(names(paper))")
        try perform("이전 쪽", on: paper)
        try perform("다음 쪽", on: paper)
        XCTAssertEqual(moves, ["previous", "next"])

        // A paragraph: 이전 쪽, 다음 쪽, 문단 편집 (Android's order).
        let target = try await element(in: window) { $0.identifier == "hwp-inline-target-\(paragraph.id)" }
        let expected = ["이전 쪽", "다음 쪽", "문단 편집"]
        XCTAssertEqual(names(target).count, expected.count, "\(names(target))")
        for (name, key) in zip(names(target), expected) { XCTAssertTrue(matches(name, key), "\(names(target))") }
        try perform("문단 편집", on: target)
        XCTAssertEqual(opened, [paragraph.id])
    }

    // MARK: - Helpers

    private func load(_ data: Data) async throws -> HWPDocumentViewModel {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".hwpx")
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let model = HWPDocumentViewModel(fileURL: url)
        await model.load()
        XCTAssertNil(model.errorDescription)
        return model
    }

    private func documentWithPicture(clearsDescription: Bool = false) async throws -> ([HWPDocumentBlock], [HWPDocumentPageLayout]) {
        let package = try HWPXDocumentPackage.load(from: LegacyHWPXConverter.convert(text: "그림"))
        let selection = try XCTUnwrap(HWPImageEditing.selection(blocks: package.blocks,
            selectedID: package.blocks[0].id, range: NSRange(location: 1, length: 0), layouts: package.pageLayouts))
        let png = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20)).pngData { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        }
        let image = try HWPImageEditing.normalize(png)
        let size = image.displaySize(maxWidth: selection.width)
        let inserted = try await HWPImageEditing.inserting(.init(selection: selection, image: image,
            widthPoints: size.width, heightPoints: size.height),
            source: HWPTableStructureDocument.hwpx(package), drafts: package.blocks)
        let model = try await load(inserted.document.data)
        if clearsDescription {
            let owner = try XCTUnwrap(model.blocks.first { !$0.canvasObjects.isEmpty })
            let target = try XCTUnwrap(HWPImageEditing.target(owner: owner, object: try XCTUnwrap(owner.canvasObjects.first)))
            _ = try await model.describeImage("", target: target)
        }
        return (model.blocks, model.pageLayouts)
    }

    private func host<Content: View>(_ view: Content) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1000, height: 1400))
        window.rootViewController = UIHostingController(rootView: AnyView(view))
        window.makeKeyAndVisible()
        window.rootViewController?.view.layoutIfNeeded()
        return window
    }

    private func expectedLabel(_ object: HWPDocumentCanvasObject) -> String {
        if let description = object.description, !description.isEmpty { return description }
        return AppLocalization.string("그림")
    }

    /// The Korean key, or its translation in the app or system language.
    private func matches(_ text: String, _ key: String) -> Bool {
        text == key || text == AppLocalization.string(key) || text == NSLocalizedString(key, comment: "")
            || text == Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    }

    private func names(_ element: NSObject) -> [String] {
        (element.accessibilityCustomActions ?? []).map(\.name)
    }

    private func perform(_ name: String, on element: NSObject) throws {
        let action = try XCTUnwrap(element.accessibilityCustomActions?.first { matches($0.name, name) }, name)
        if let handler = action.actionHandler {
            XCTAssertTrue(handler(action))
        } else if let target = action.target as? NSObject {
            target.perform(action.selector, with: action)
        } else {
            XCTFail("\(name) has no handler")
        }
    }

    private func element(in window: UIWindow, timeout: TimeInterval = 5,
                         _ predicate: (NSObject) -> Bool) async throws -> NSObject {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            var found: [NSObject] = []
            var visited = Set<ObjectIdentifier>()
            collect(window, depth: 0, into: &found, visited: &visited)
            if let match = found.first(where: predicate) { return match }
            try await Task.sleep(for: .milliseconds(100))
        } while Date() < deadline
        XCTFail("Accessibility element not found")
        throw CancellationError()
    }

    private func collect(_ object: NSObject, depth: Int, into found: inout [NSObject],
                         visited: inout Set<ObjectIdentifier>) {
        guard depth < 120, visited.insert(ObjectIdentifier(object)).inserted else { return }
        if let view = object as? UIView, view.isHidden || view.alpha < 0.01 { return }
        if object.isAccessibilityElement { found.append(object) }
        if object.accessibilityElementsHidden { return }
        var children: [NSObject] = []
        if let list = object.accessibilityElements {
            children = list.compactMap { $0 as? NSObject }
        } else {
            let count = object.accessibilityElementCount()
            if count != NSNotFound, count > 0, count < 50_000 {
                for index in 0..<count {
                    if let child = object.accessibilityElement(at: index) as? NSObject { children.append(child) }
                }
            }
        }
        if let view = object as? UIView { children.append(contentsOf: view.subviews) }
        for child in children { collect(child, depth: depth + 1, into: &found, visited: &visited) }
    }
}

private extension NSObject {
    var identifier: String {
        responds(to: NSSelectorFromString("accessibilityIdentifier"))
            ? (value(forKey: "accessibilityIdentifier") as? String ?? "") : ""
    }
}
