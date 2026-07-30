import Foundation
import XCTest

@testable import shortcuts_example

final class AppLocalizationTests:
    XCTestCase
{
    func testEnglishAndJapaneseShellStringsLoad()
        throws
    {
        let english = try localizedBundle(
            language: "en"
        )
        let japanese = try localizedBundle(
            language: "ja"
        )

        XCTAssertEqual(
            AppLocalization.string(
                "설정",
                bundle: english
            ),
            "Settings"
        )
        XCTAssertEqual(
            AppLocalization.string(
                "도움말",
                bundle: japanese
            ),
            "ヘルプ"
        )
        XCTAssertEqual(
            AppLocalization.string(
                "Rivo 리모컨",
                bundle: english
            ),
            "Rivo Remote"
        )
    }

    func testDynamicFormatTranslationsPreserveArguments()
        throws
    {
        let english = try localizedBundle(
            language: "en"
        )
        let japanese = try localizedBundle(
            language: "ja"
        )

        let englishRate = String(
            format: AppLocalization.string(
                "재생 속도 배수 형식",
                bundle: english
            ),
            "1.25"
        )
        let japaneseDevice = String(
            format: AppLocalization.string(
                "%@ 연결됨",
                bundle: japanese
            ),
            "Rivo Three"
        )

        XCTAssertEqual(englishRate, "1.25×")
        XCTAssertEqual(
            japaneseDevice,
            "Rivo Threeに接続済み"
        )
    }

    func testPermissionDescriptionsAreLocalized()
        throws
    {
        let english = try localizedBundle(
            language: "en"
        )
        let japanese = try localizedBundle(
            language: "ja"
        )

        XCTAssertTrue(
            infoPlistString(
                "NSCameraUsageDescription",
                bundle: english
            )
            .contains("Camera")
        )
        XCTAssertTrue(
            infoPlistString(
                "NSBluetoothAlwaysUsageDescription",
                bundle: japanese
            )
            .contains("Bluetooth")
        )
    }

    private func localizedBundle(
        language: String
    ) throws -> Bundle {
        let url = try XCTUnwrap(
            Bundle.main.url(
                forResource: language,
                withExtension: "lproj"
            )
        )
        return try XCTUnwrap(
            Bundle(url: url)
        )
    }

    private func infoPlistString(
        _ key: String,
        bundle: Bundle
    ) -> String {
        bundle.localizedString(
            forKey: key,
            value: "",
            table: "InfoPlist"
        )
    }
}
