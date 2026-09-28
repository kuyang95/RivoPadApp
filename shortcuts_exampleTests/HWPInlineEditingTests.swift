import Foundation
import SwiftUI
import UIKit
import XCTest
@testable import shortcuts_example

@MainActor
final class HWPInlineEditingTests: XCTestCase {
    private func block(_ text: String = "한글 문서", id: String = "body") -> HWPDocumentBlock {
        HWPDocumentBlock(id: id, sectionPath: "Section0", paragraphIndex: 0,
            text: text, tableLocation: nil, isEditable: true,
            presentation: HWPDocumentBlockPresentation(textRuns: [
                HWPDocumentTextRun(text: text, fontSizePoints: 16)
            ]))
    }

    private func shapeData(_ entries: [(UInt32, UInt32)]) -> Data {
        Data(entries.flatMap { pair in
            [pair.0, pair.1].flatMap { value in
                (0..<4).map { UInt8((value >> ($0 * 8)) & 255) }
            }
        })
    }

    func testHWPStyleBoundariesFollowMiddleInsertionsDeletionAndTabs() throws {
        let data = shapeData([(0, 1), (2, 2)])
        XCTAssertEqual(try HWP5DocumentRewriter.adjustedCharacterShapes(data,
            originalText: "가나다라", editedText: "가나다추가라"), shapeData([(0, 1), (2, 2)]))
        XCTAssertEqual(try HWP5DocumentRewriter.adjustedCharacterShapes(data,
            originalText: "가나다라", editedText: "가추가나다라"), shapeData([(0, 1), (4, 2)]))
        XCTAssertEqual(try HWP5DocumentRewriter.adjustedCharacterShapes(data,
            originalText: "가나다라", editedText: "다라"), shapeData([(0, 2)]))
        XCTAssertEqual(try HWP5DocumentRewriter.adjustedCharacterShapes(shapeData([(0, 1), (9, 2)]),
            originalText: "가\t나", editedText: "가추가\t나"), shapeData([(0, 1), (11, 2)]))
        XCTAssertEqual(try HWP5DocumentRewriter.adjustedCharacterShapes(data,
            originalText: "가나다라", editedText: ""), shapeData([(0, 1)]))
    }

    func testInputAcceptsKoreanEmojiAndLineBreaksButRejectsControlAndInvalidRanges() {
        XCTAssertTrue(HWPInlineTextInput.accepts("한👨‍👩‍👧‍👦\t\n", replacing: NSRange(location: 1, length: 1), in: "한글"))
        XCTAssertFalse(HWPInlineTextInput.accepts("\0", replacing: NSRange(location: 0, length: 0), in: ""))
        XCTAssertFalse(HWPInlineTextInput.accepts("가", replacing: NSRange(location: NSNotFound, length: 0), in: ""))
        XCTAssertFalse(HWPInlineTextInput.accepts("가", replacing: NSRange(location: 1, length: 1), in: "가"))
        XCTAssertEqual(HWPInlineTextInput.normalized("가\r\n나\r다\u{2029}라"), "가\n나\n다\n라")
    }

    func testPageFragmentsCannotReplaceTheirSourceParagraph() {
        let source = block()
        let context = HWPInlineEditingContext(session: HWPInlineEditingSession(), sources: [source.id: source])
        XCTAssertNotNil(context.source(for: source))
        XCTAssertNil(context.source(for: block("한글", id: "body-page-fragment-0")))
        XCTAssertNil(context.source(for: block("한글")))
        XCTAssertNil(HWPInlineEditingContext().source(for: source))
    }

    func testChangingParagraphsCommitsOnceAndIgnoresLateOldInput() {
        let session = HWPInlineEditingSession()
        var texts: [String] = []
        var commits = 0
        session.begin(block: block(), at: .zero, onSelect: { _ in },
            onChange: { texts.append($0) }, onCommit: { commits += 1 })
        let oldToken = session.activation!.token
        session.changed("첫 수정", token: oldToken)
        session.begin(block: block("둘째", id: "second"), at: .zero, onSelect: { _ in },
            onChange: { texts.append($0) }, onCommit: { commits += 1 })
        session.changed("늦게 온 첫 수정", token: oldToken)
        XCTAssertEqual(texts, ["첫 수정"])
        XCTAssertEqual(commits, 1)
        session.finish()
        session.finish()
        XCTAssertEqual(commits, 2)
    }

    func testNativeInputKeepsMarkedKoreanTextAcrossSwiftUIUpdatesAndCommitsOnFinish() async throws {
        let source = block("가나다라")
        let session = HWPInlineEditingSession()
        var draft = source.text
        var saved = ""
        session.begin(block: source, at: CGPoint(x: 0, y: 4), onSelect: { _ in },
            onChange: { draft = $0 }, onCommit: { saved = draft })
        let activation = try XCTUnwrap(session.activation)
        let host = UIHostingController(rootView: HWPInlineTextEditor(activation: activation, session: session)
            .frame(width: 300, height: 80))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { session.finish(); window.isHidden = true }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let input = try XCTUnwrap(findInput(host.view))
        XCTAssertTrue(input.isFirstResponder)
        input.selectedRange = NSRange(location: 2, length: 0)
        input.setMarkedText("ㅎ", selectedRange: NSRange(location: 1, length: 0))
        input.setMarkedText("한", selectedRange: NSRange(location: 1, length: 0))
        XCTAssertNotNil(input.markedTextRange)
        host.rootView = HWPInlineTextEditor(activation: activation, session: session)
            .frame(width: 300, height: 80)
        host.view.layoutIfNeeded()
        XCTAssertTrue(findInput(host.view) === input)
        XCTAssertNotNil(input.markedTextRange)
        session.finish()
        XCTAssertNil(input.markedTextRange)
        XCTAssertEqual(saved, "가나한다라")
        XCTAssertFalse(input.isFirstResponder)
    }

    func testNativeSelectionReplacementAndLineBreaksStayInTheParagraph() async throws {
        let source = block("가나다라")
        let session = HWPInlineEditingSession()
        var draft = source.text
        session.begin(block: source, at: .zero, onSelect: { _ in },
            onChange: { draft = $0 }, onCommit: {})
        let activation = try XCTUnwrap(session.activation)
        let host = UIHostingController(rootView: HWPInlineTextEditor(activation: activation, session: session)
            .frame(width: 300, height: 80))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { session.finish(); window.isHidden = true }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let input = try XCTUnwrap(findInput(host.view))
        input.selectedRange = NSRange(location: 1, length: 2)
        input.insertText("한글")
        XCTAssertEqual(input.text, "가한글라")
        try await Task.sleep(for: .milliseconds(50))
        let undo = try XCTUnwrap(input.undoManager)
        XCTAssertTrue(undo.canUndo)
        undo.undo()
        XCTAssertEqual(input.text, "가나다라")
        undo.redo()
        XCTAssertEqual(input.text, "가한글라")
        input.selectedRange = NSRange(location: 4, length: 0)
        input.insertText("\r\n둘째 줄")
        XCTAssertEqual(input.text, "가한글라\n둘째 줄")
        session.finish()
        XCTAssertEqual(draft, "가한글라\n둘째 줄")
    }

    func testShiftReturnCommandInsertsLineBreakWithoutSplittingParagraph() throws {
        let input = HWPInlineTextView()
        input.text = "앞뒤"
        input.selectedRange = NSRange(location: 1, length: 0)
        var paragraphEdit: HWPParagraphEdit?
        input.onParagraphEdit = { operation in
            paragraphEdit = operation
            return true
        }

        let command = try XCTUnwrap(input.keyCommands?.first {
            $0.input == "\r" && $0.modifierFlags == .shift
        })
        XCTAssertTrue(command.wantsPriorityOverSystemBehavior)
        let action = try XCTUnwrap(command.action)
        XCTAssertTrue(input.responds(to: action))
        input.perform(action, with: command)

        XCTAssertEqual(input.text, "앞\n뒤")
        XCTAssertNil(paragraphEdit)
    }

    private func findInput(_ view: UIView) -> HWPInlineTextView? {
        if let input = view as? HWPInlineTextView { return input }
        return view.subviews.lazy.compactMap { self.findInput($0) }.first
    }
}
