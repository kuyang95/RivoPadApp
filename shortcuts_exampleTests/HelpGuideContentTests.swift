import Foundation
import XCTest

@testable import shortcuts_example

final class HelpGuideContentTests: XCTestCase {
    func testEveryLanguageLoadsMatchingTopicsAndFeatureActions() throws {
        let korean = try HelpGuideContent.load(language: .korean)
        XCTAssertFalse(korean.filter { $0.group == .feature }.isEmpty)
        XCTAssertFalse(korean.filter { $0.group == .problem }.isEmpty)
        XCTAssertEqual(Set(korean.map(\.action)), Set(HelpGuideAction.allCases))

        for language in [AppLanguage.english, .japanese] {
            let translated = try HelpGuideContent.load(language: language)
            XCTAssertEqual(translated.map(\.id), korean.map(\.id))
            XCTAssertEqual(translated.map(\.action), korean.map(\.action))
            XCTAssertEqual(translated.map(\.group), korean.map(\.group))
            XCTAssertEqual(translated.map(\.icon), korean.map(\.icon))
            for (original, translation) in zip(korean, translated) {
                XCTAssertNotEqual(original.situation, translation.situation)
                XCTAssertEqual(original.steps.count, translation.steps.count)
            }
        }
    }

    func testSearchFindsInstructionsAndTipsAsWellAsTitles() throws {
        let topics = try HelpGuideContent.load(language: .english)
        let image = try XCTUnwrap(topics.first { $0.id == "image" })
        XCTAssertTrue(image.matches("  picture\n"))
        XCTAssertTrue(image.matches("GEMINI"))
        XCTAssertTrue(image.matches("follow-up"))
        XCTAssertTrue(image.matches(" \n"))
        XCTAssertFalse(image.matches("no-such-guide-topic"))
    }

    func testMalformedContentCannotProduceAnEmptyOrAmbiguousGuide() throws {
        let topic = try XCTUnwrap(HelpGuideContent.load(language: .korean).first)
        let data = try JSONEncoder().encode([topic])
        let valid = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertThrowsError(try HelpGuideContent.decode(Data("[]".utf8)))
        XCTAssertThrowsError(try HelpGuideContent.decode(JSONSerialization.data(withJSONObject: valid + valid)))

        for (key, value) in [("steps", [] as [String]), ("steps", ["  "])] {
            var invalid = valid
            invalid[0][key] = value
            XCTAssertThrowsError(try HelpGuideContent.decode(JSONSerialization.data(withJSONObject: invalid)))
        }
        var invalid = valid
        invalid[0]["action"] = "unsupported-feature"
        XCTAssertThrowsError(try HelpGuideContent.decode(JSONSerialization.data(withJSONObject: invalid)))
    }
}
