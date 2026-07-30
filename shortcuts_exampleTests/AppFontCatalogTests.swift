import CryptoKit
import Foundation
import XCTest

@testable import shortcuts_example

final class AppFontCatalogTests:
    XCTestCase
{
    func testManifestParsesLabelsFilesAndLanguageVisibility()
        throws
    {
        let manifest =
            try AppFontManifestParser
            .parse(
                Self.manifestData()
            )

        XCTAssertEqual(
            manifest.schemaVersion,
            1
        )
        XCTAssertEqual(
            manifest.fonts.count,
            1
        )
        let option =
            try XCTUnwrap(
                manifest.fonts.first
            )
        XCTAssertEqual(
            option.key,
            "sample_font"
        )
        XCTAssertEqual(
            option.label(
                languageCode: "ko"
            ),
            "한국어 · Sample"
        )
        XCTAssertEqual(
            option.label(
                languageCode: "ja"
            ),
            "Korean · Sample"
        )
        XCTAssertTrue(
            option.isVisible(for: "ko")
        )
        XCTAssertFalse(
            option.isVisible(for: "en")
        )
        XCTAssertEqual(
            option.files?.regular.bytes,
            4
        )
    }

    func testManifestRejectsUntrustedFontURL()
    {
        XCTAssertThrowsError(
            try AppFontManifestParser
                .parse(
                    Self.manifestData(
                        fontURL:
                            "https://example.com/font.ttf"
                    )
                )
        ) { error in
            XCTAssertEqual(
                error
                    as? AppFontCatalogError,
                .invalidFileURL
            )
        }
    }

    func testManifestRejectsPathTraversal()
    {
        XCTAssertThrowsError(
            try AppFontManifestParser
                .parse(
                    Self.manifestData(
                        path:
                            "../font.ttf"
                    )
                )
        ) { error in
            XCTAssertEqual(
                error
                    as? AppFontCatalogError,
                .invalidFilePath
            )
        }
    }

    func testManifestRejectsInvalidHash()
    {
        XCTAssertThrowsError(
            try AppFontManifestParser
                .parse(
                    Self.manifestData(
                        sha256: "1234"
                    )
                )
        ) { error in
            XCTAssertEqual(
                error
                    as? AppFontCatalogError,
                .invalidSHA256
            )
        }
    }

    func testManifestRejectsDuplicateKeys()
    {
        let one =
            String(
                data:
                    Self.manifestData(),
                encoding: .utf8
            )!
        let fontObject =
            one.components(
                separatedBy:
                    "\"fonts\": ["
            )[1]
            .components(
                separatedBy: "\n  ]"
            )[0]
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
        let duplicate =
            one.replacingOccurrences(
                of: fontObject,
                with:
                    fontObject
                    + ",\n"
                    + fontObject
            )

        XCTAssertThrowsError(
            try AppFontManifestParser
                .parse(
                    Data(
                        duplicate.utf8
                    )
                )
        ) { error in
            XCTAssertEqual(
                error
                    as? AppFontCatalogError,
                .duplicateKey
            )
        }
    }

    func testIntegrityChecksSizeAndSHA256()
        throws
    {
        let directory =
            FileManager.default
            .temporaryDirectory
            .appending(
                path:
                    "AppFontCatalogTests-"
                    + UUID().uuidString,
                directoryHint:
                    .isDirectory
            )
        try FileManager.default
            .createDirectory(
                at: directory,
                withIntermediateDirectories:
                    true
            )
        defer {
            try? FileManager.default
                .removeItem(at: directory)
        }
        let fileURL =
            directory.appending(
                path: "font.ttf"
            )
        let data = Data("font".utf8)
        try data.write(to: fileURL)
        let digest =
            SHA256.hash(data: data)
            .map {
                String(
                    format: "%02x",
                    $0
                )
            }
            .joined()

        XCTAssertTrue(
            try AppFontIntegrity.verify(
                fileURL,
                expectedBytes: 4,
                expectedSHA256: digest
            )
        )
        XCTAssertFalse(
            try AppFontIntegrity.verify(
                fileURL,
                expectedBytes: 5,
                expectedSHA256: digest
            )
        )
        XCTAssertFalse(
            try AppFontIntegrity.verify(
                fileURL,
                expectedBytes: 4,
                expectedSHA256:
                    String(
                        repeating: "0",
                        count: 64
                    )
            )
        )
    }

    @MainActor
    func testBuiltInSelectionPersistsAndResets()
        async
    {
        let suiteName =
            "AppFontCatalogTests."
            + UUID().uuidString
        let defaults =
            UserDefaults(
                suiteName: suiteName
            )!
        defer {
            defaults
                .removePersistentDomain(
                    forName:
                        suiteName
                )
        }
        let rootURL =
            FileManager.default
            .temporaryDirectory
            .appending(
                path:
                    "AppFontCatalogTests-"
                    + UUID().uuidString,
                directoryHint:
                    .isDirectory
            )
        defer {
            try? FileManager.default
                .removeItem(
                    at: rootURL
                )
        }
        let store =
            AppFontCatalogStore(
                defaults: defaults,
                rootURL: rootURL
            )

        XCTAssertEqual(
            store.selectedKey,
            AppFontOption
                .bundledNanumKey
        )
        let selectedSystem =
            await store.select(.system)
        XCTAssertTrue(selectedSystem)
        XCTAssertEqual(
            defaults.string(
                forKey:
                    AppFontCatalogStore
                    .preferenceKey
            ),
            AppFontOption.systemKey
        )

        store.resetSelection()

        XCTAssertEqual(
            store.selectedKey,
            AppFontOption
                .bundledNanumKey
        )
        XCTAssertNotNil(
            store.font(
                languageCode: "ko"
            )
        )
    }

    @MainActor
    func testPrepareDownloadsRegistersAndRestoresVerifiedFont()
        async throws
    {
        let bundledURL =
            try XCTUnwrap(
                Bundle.main.url(
                    forResource:
                        "NanumSquareRoundOTFEB",
                    withExtension: "otf"
                )
            )
        let fontData =
            try Data(
                contentsOf: bundledURL
            )
        let digest =
            SHA256.hash(data: fontData)
            .map {
                String(
                    format: "%02x",
                    $0
                )
            }
            .joined()
        let remoteFontURL = URL(
            string:
                "https://rivo.me/app/VisionCraft/fonts/test_font.otf"
        )!
        let manifestData =
            Self.manifestData(
                path: "test_font.otf",
                fontURL:
                    remoteFontURL
                    .absoluteString,
                bytes:
                    fontData.count,
                sha256: digest
            )
        AppFontURLProtocolStub.handler = {
            request in
            let url =
                try XCTUnwrap(
                    request.url
                )
            let data: Data
            if url
                == AppFontCatalogStore
                .manifestURL {
                data = manifestData
            } else if url
                == remoteFontURL {
                data = fontData
            } else {
                throw URLError(.badURL)
            }
            let response =
                try XCTUnwrap(
                    HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: [
                            "Content-Length":
                                "\(data.count)",
                        ]
                    )
                )
            return (response, data)
        }
        defer {
            AppFontURLProtocolStub
                .handler = nil
        }
        let configuration =
            URLSessionConfiguration
            .ephemeral
        configuration.protocolClasses = [
            AppFontURLProtocolStub.self,
        ]
        let session =
            URLSession(
                configuration:
                    configuration
            )
        let suiteName =
            "AppFontCatalogTests."
            + UUID().uuidString
        let defaults =
            try XCTUnwrap(
                UserDefaults(
                    suiteName: suiteName
                )
            )
        defer {
            defaults
                .removePersistentDomain(
                    forName:
                        suiteName
                )
        }
        let rootURL =
            FileManager.default
            .temporaryDirectory
            .appending(
                path:
                    "AppFontCatalogTests-"
                    + UUID().uuidString,
                directoryHint:
                    .isDirectory
            )
        defer {
            try? FileManager.default
                .removeItem(
                    at: rootURL
                )
        }
        let store =
            AppFontCatalogStore(
                defaults: defaults,
                session: session,
                rootURL: rootURL
            )

        await store.prepare()
        let remoteOption =
            try XCTUnwrap(
                store.options.first {
                    $0.key
                        == "sample_font"
                }
            )
        let selected =
            await store.select(
                remoteOption
            )

        XCTAssertTrue(
            selected,
            store.errorMessage ?? ""
        )
        XCTAssertEqual(
            store.selectedKey,
            "sample_font"
        )
        XCTAssertEqual(
            store.activeRemoteKey,
            "sample_font"
        )
        XCTAssertNotNil(
            store.activeRemoteFontName
        )
        XCTAssertTrue(
            FileManager.default
                .fileExists(
                    atPath:
                        rootURL
                        .appending(
                            path:
                                "sample_font/test_font.otf"
                        )
                        .path
                )
        )

        let restored =
            AppFontCatalogStore(
                defaults: defaults,
                session: session,
                rootURL: rootURL
            )
        await restored.prepare()

        XCTAssertEqual(
            restored.activeRemoteKey,
            "sample_font"
        )
        XCTAssertNotNil(
            restored.font(
                languageCode: "ko"
            )
        )
    }

    private static func manifestData(
        path: String = "font.ttf",
        fontURL: String =
            "https://rivo.me/app/VisionCraft/fonts/font.ttf",
        bytes: Int = 4,
        sha256: String =
            String(
                repeating: "a",
                count: 64
            )
    ) -> Data {
        Data(
            """
            {
              "schemaVersion": 1,
              "generatedAt": "2026-07-08T07:41:44.989Z",
              "baseUrl": "https://rivo.me/app/VisionCraft/fonts/",
              "fonts": [
                {
                  "key": "sample_font",
                  "labels": {
                    "ko": "한국어 · Sample",
                    "en": "Korean · Sample"
                  },
                  "scripts": ["ko", "en"],
                  "license": "SIL Open Font License 1.1",
                  "licenseUrl": "https://rivo.me/app/VisionCraft/fonts/licenses/sample.txt",
                  "files": {
                    "regular": {
                      "path": "\(path)",
                      "url": "\(fontURL)",
                      "bytes": \(bytes),
                      "sha256": "\(sha256)"
                    },
                    "bold": {
                      "path": "\(path)",
                      "url": "\(fontURL)",
                      "bytes": \(bytes),
                      "sha256": "\(sha256)"
                    }
                  }
                }
              ]
            }
            """.utf8
        )
    }
}

private final class AppFontURLProtocolStub:
    URLProtocol
{
    static var handler:
        ((
            URLRequest
        ) throws -> (
            HTTPURLResponse,
            Data
        ))?

    override class func canInit(
        with request: URLRequest
    ) -> Bool {
        true
    }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler =
                Self.handler else {
            client?.urlProtocol(
                self,
                didFailWithError:
                    URLError(
                        .badServerResponse
                    )
            )
            return
        }
        do {
            let (response, data) =
                try handler(request)
            client?.urlProtocol(
                self,
                didReceive: response,
                cacheStoragePolicy:
                    .notAllowed
            )
            client?.urlProtocol(
                self,
                didLoad: data
            )
            client?
                .urlProtocolDidFinishLoading(
                    self
                )
        } catch {
            client?.urlProtocol(
                self,
                didFailWithError: error
            )
        }
    }

    override func stopLoading() {}
}
