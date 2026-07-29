import Foundation
import CoreFoundation
import XCTest
import zlib

@testable import shortcuts_example

final class EPUBReaderTests: XCTestCase {
    func testParsesEPUB3MetadataNavigationAndReadingOrder()
        throws
    {
        let data = try EPUBFixture.makeBook()
        let archive = try EPUBArchive(data: data)

        XCTAssertEqual(
            try archive.text(at: "mimetype"),
            "application/epub+zip"
        )

        let book = try EPUBBookParser.parse(data: data)

        XCTAssertEqual(book.identifier, "rivo-epub-fixture")
        XCTAssertEqual(book.title, "테스트 책")
        XCTAssertEqual(book.creator, "Rivo")
        XCTAssertEqual(book.language, "ko")
        XCTAssertEqual(book.chapters.count, 2)
        XCTAssertEqual(book.chapters[0].title, "첫 번째 장")
        XCTAssertEqual(book.chapters[1].title, "두 번째 장")
        XCTAssertTrue(
            book.chapters[0].text.contains(
                "첫 문장 이어지는 내용"
            )
        )
        XCTAssertFalse(
            book.chapters[0].text.contains("숨은 메뉴")
        )
        XCTAssertFalse(
            book.chapters[0].text.contains("표시하지 않음")
        )
        XCTAssertEqual(
            book.chapters[1]
                .fragmentSegmentIndexes["offline"],
            1
        )
        XCTAssertEqual(
            book.mediaOverlayItems,
            [
                EPUBMediaOverlayItem(
                    id:
                        "OEBPS/chapter2.smil#"
                        + "offline-audio",
                    smilPath:
                        "OEBPS/chapter2.smil",
                    textPath:
                        "OEBPS/chapter2.xhtml",
                    textFragmentID: "offline",
                    audioPath:
                        "OEBPS/audio/chapter2.mp3",
                    clipBeginSeconds: 1.25,
                    clipEndSeconds: 3.5,
                    playOrder: 4
                ),
                EPUBMediaOverlayItem(
                    id:
                        "OEBPS/chapter2.smil#"
                        + "offline-audio-2",
                    smilPath:
                        "OEBPS/chapter2.smil",
                    textPath:
                        "OEBPS/chapter2.xhtml",
                    textFragmentID: "offline",
                    audioPath:
                        "OEBPS/audio/chapter2.mp3",
                    clipBeginSeconds: 3.5,
                    clipEndSeconds: nil,
                    playOrder: 5
                ),
            ]
        )
    }

    func testSearchFindsMatchingChapterAndBuildsSnippet()
        throws
    {
        let book = try EPUBBookParser.parse(
            data: EPUBFixture.makeBook()
        )

        let results = EPUBSearchEngine.search(
            "오프라인",
            in: book.chapters
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].chapterIndex, 1)
        XCTAssertEqual(results[0].chapterTitle, "두 번째 장")
        XCTAssertTrue(results[0].snippet.contains("오프라인"))
        XCTAssertTrue(
            EPUBSearchEngine.search(
                "없는 단어",
                in: book.chapters
            ).isEmpty
        )
    }

    func testSearchReturnsEveryMatchWithSegmentLocation()
    {
        let chapter = EPUBChapter(
            id: "chapter",
            title: "반복 장",
            href: "chapter.xhtml",
            text:
                "첫 문단 반복 단어와 반복 단어\n\n"
                + "둘째 문단의 반복 단어"
        )

        let results = EPUBSearchEngine.search(
            "반복",
            in: [chapter]
        )

        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(
            results.map(\.segmentIndex),
            [0, 0, 1]
        )
        XCTAssertEqual(
            results.map(\.matchStartInSegment),
            [5, 12, 7]
        )
        for result in results {
            XCTAssertEqual(
                String(
                    result.snippet.dropFirst(
                        result.matchStartInSnippet
                    ).prefix(result.matchLength)
                ),
                "반복"
            )
        }
    }

    @MainActor
    func testProgressRoundTripAndLegacyMigration()
    {
        let suiteName =
            "EPUBProgressStoreTests-"
            + UUID().uuidString
        let defaults = UserDefaults(
            suiteName: suiteName
        )!
        defer {
            defaults.removePersistentDomain(
                forName: suiteName
            )
        }

        let progress = EPUBReaderProgress(
            chapterIndex: 3,
            segmentIndex: 7
        )
        EPUBProgressStore.save(
            progress,
            for: "book",
            defaults: defaults
        )
        XCTAssertEqual(
            EPUBProgressStore.progress(
                for: "book",
                defaults: defaults
            ),
            progress
        )

        let legacyIdentifier = "legacy"
        let encoded = Data(
            legacyIdentifier.utf8
        ).base64EncodedString()
        defaults.set(
            2,
            forKey:
                "reader.epub.chapter.\(encoded)"
        )
        XCTAssertEqual(
            EPUBProgressStore.progress(
                for: legacyIdentifier,
                defaults: defaults
            ),
            EPUBReaderProgress(
                chapterIndex: 2,
                segmentIndex: 0
            )
        )
    }

    func testSMILClockSupportsAndroidClockForms()
    {
        XCTAssertEqual(
            EPUBSMILClock.seconds(
                from: "npt=01:02:03.5"
            ),
            3_723.5
        )
        XCTAssertEqual(
            EPUBSMILClock.seconds(
                from: "02:03.25"
            ),
            123.25
        )
        XCTAssertEqual(
            EPUBSMILClock.seconds(
                from: "1500ms"
            ),
            1.5
        )
        XCTAssertEqual(
            EPUBSMILClock.seconds(
                from: "1.5min"
            ),
            90
        )
        XCTAssertNil(
            EPUBSMILClock.seconds(
                from: "not-a-clock"
            )
        )
    }

    func testMediaOverlayLocationResolvesTextFragment()
        throws
    {
        let book = try EPUBBookParser.parse(
            data: EPUBFixture.makeBook()
        )

        XCTAssertEqual(
            EPUBMediaOverlayLocationResolver
                .location(
                    for: 0,
                    items: book.mediaOverlayItems,
                    chapters: book.chapters
                ),
            EPUBMediaOverlayLocation(
                itemIndex: 0,
                chapterIndex: 1,
                segmentIndex: 1
            )
        )
        XCTAssertEqual(
            EPUBMediaOverlayLocationResolver
                .nearestItemIndex(
                    chapterIndex: 1,
                    segmentIndex: 1,
                    items: book.mediaOverlayItems,
                    chapters: book.chapters
                ),
            0
        )
        XCTAssertNil(
            EPUBMediaOverlayLocationResolver
                .nearestItemIndex(
                    chapterIndex: 0,
                    segmentIndex: 0,
                    items: book.mediaOverlayItems,
                    chapters: book.chapters
                )
        )
    }

    func testReadAloudSequenceInterleavesTTSAndAudio()
    {
        let chapter = EPUBChapter(
            id: "mixed",
            title: "혼합 읽기",
            href: "text.xhtml",
            text:
                "첫 텍스트 문단\n\n"
                + "오디오 연결 문단\n\n"
                + "마지막 텍스트 문단",
            fragmentSegmentIndexes: [
                "audio": 1,
            ]
        )
        let audioItems = [
            EPUBMediaOverlayItem(
                id: "overlay.smil#first",
                smilPath: "overlay.smil",
                textPath: "text.xhtml",
                textFragmentID: "audio",
                audioPath: "audio.mp3",
                clipBeginSeconds: 0,
                clipEndSeconds: 1,
                playOrder: 1
            ),
            EPUBMediaOverlayItem(
                id: "overlay.smil#second",
                smilPath: "overlay.smil",
                textPath: "text.xhtml",
                textFragmentID: "audio",
                audioPath: "audio.mp3",
                clipBeginSeconds: 1,
                clipEndSeconds: 2,
                playOrder: 2
            ),
        ]
        let book = EPUBBook(
            identifier: "mixed",
            title: "혼합",
            creator: nil,
            language: "ko",
            chapters: [chapter],
            mediaOverlayItems: audioItems
        )

        let steps = EPUBReadAloudSequence
            .steps(for: book)

        XCTAssertEqual(
            steps.map(\.audioItemIndex),
            [nil, 0, 1, nil]
        )
        XCTAssertEqual(
            steps.map(\.segmentIndex),
            [0, 1, 1, 2]
        )
        XCTAssertEqual(
            steps.map(\.text),
            [
                "첫 텍스트 문단",
                "오디오 연결 문단",
                "오디오 연결 문단",
                "마지막 텍스트 문단",
            ]
        )
        XCTAssertEqual(
            EPUBReadAloudSequence.stepIndex(
                chapterIndex: 0,
                segmentIndex: 2,
                in: steps
            ),
            3
        )
    }

    func testReadAloudLanguageUsesMetadataAndScript()
    {
        XCTAssertEqual(
            EPUBReadAloudLanguageResolver
                .language(
                    declared: nil,
                    sample: "한국어 본문입니다."
                ),
            "ko-KR"
        )
        XCTAssertEqual(
            EPUBReadAloudLanguageResolver
                .language(
                    declared: nil,
                    sample:
                        "日本語のテキストです。"
                ),
            "ja-JP"
        )
        XCTAssertEqual(
            EPUBReadAloudLanguageResolver
                .language(
                    declared: "en_US",
                    sample:
                        "An English publication"
                ),
            "en-US"
        )
        XCTAssertEqual(
            EPUBReadAloudLanguageResolver
                .language(
                    declared: "ko",
                    sample: "한국어"
                ),
            "ko"
        )
    }

    func testMediaOverlayAudioExtractsToPrivateTemporaryFile()
        async throws
    {
        let testDirectory = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "RivoEPUBAudioTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: testDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(
                at: testDirectory
            )
        }
        let bookURL = testDirectory
            .appendingPathComponent("fixture.epub")
        try EPUBFixture.makeBook().write(to: bookURL)
        let store = EPUBMediaOverlayResourceStore(
            bookURL: bookURL,
            temporaryDirectory: testDirectory
        )

        let firstURL = try await store.audioURL(
            for: "OEBPS/audio/chapter2.mp3"
        )
        let secondURL = try await store.audioURL(
            for: "OEBPS/audio/chapter2.mp3"
        )

        XCTAssertEqual(firstURL, secondURL)
        XCTAssertEqual(
            try Data(contentsOf: firstURL),
            Data([0x49, 0x44, 0x33, 0x04])
        )
        XCTAssertTrue(
            firstURL.path.hasPrefix(
                testDirectory.path
            )
        )
    }

    func testArchiveRejectsPathTraversal() throws {
        let archiveData = try ZIPFixture.make(
            entries: [
                ZIPFixtureEntry(
                    path: "../escape.txt",
                    data: Data("unsafe".utf8),
                    compressionMethod: 0
                )
            ]
        )

        XCTAssertThrowsError(
            try EPUBArchive(data: archiveData)
        ) { error in
            guard let archiveError =
                    error as? EPUBArchiveError,
                  case .unsafePath = archiveError else {
                return XCTFail(
                    "예상하지 못한 오류: \(error)"
                )
            }
        }
    }

    func testArchiveDecodesDeclaredLegacyKoreanText()
        throws
    {
        let encoding = String.Encoding(
            rawValue:
                CFStringConvertEncodingToNSStringEncoding(
                    CFStringEncoding(0x0422)
                )
        )
        let source = """
        <?xml version="1.0" encoding="windows-949"?>
        <html><body><p>오래된 한글 DAISY 본문</p></body></html>
        """
        let encoded = try XCTUnwrap(
            source.data(using: encoding)
        )

        XCTAssertEqual(
            EPUBArchive.decodeText(encoded),
            source
        )
        let extractor = EPUBHTMLTextDelegate()
        try EPUBBookParser.parseXHTML(
            encoded,
            delegate: extractor
        )
        XCTAssertTrue(
            extractor.text.contains(
                "오래된 한글 DAISY 본문"
            )
        )
    }

    func testLibraryImportCopiesBookIntoManagedDirectory()
        async throws
    {
        let testDirectory = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "RivoEPUBLibraryTests-\(UUID().uuidString)",
                isDirectory: true
            )
        let sourceDirectory = testDirectory
            .appendingPathComponent("Source", isDirectory: true)
        let booksDirectory = testDirectory
            .appendingPathComponent("Books", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(
                at: testDirectory
            )
        }

        let sourceURL = sourceDirectory
            .appendingPathComponent("fixture.epub")
        let expected = try EPUBFixture.makeBook()
        try expected.write(to: sourceURL)
        let store = EPUBLibraryStore(
            booksDirectory: booksDirectory
        )

        let importedURL = try await store.importBook(
            from: sourceURL
        )

        XCTAssertNotEqual(importedURL, sourceURL)
        XCTAssertEqual(
            importedURL.lastPathComponent,
            "fixture.epub"
        )
        XCTAssertEqual(
            try Data(contentsOf: importedURL),
            expected
        )
    }

    func testParsesDaisy202NCCNavigationAndSMIL()
        throws
    {
        let book = try AccessiblePublicationParser
            .parse(
                data:
                    DaisyFixture.makeDaisy202()
            )

        XCTAssertEqual(book.format, .daisy202)
        XCTAssertEqual(
            book.identifier,
            "rivo-daisy-202"
        )
        XCTAssertEqual(book.title, "DAISY 2 테스트")
        XCTAssertEqual(book.creator, "Rivo")
        XCTAssertEqual(book.language, "ko")
        XCTAssertEqual(
            book.navigationItems.map(\.label),
            ["첫 장", "첫 장의 절"]
        )
        XCTAssertEqual(
            book.navigationItems.map(\.depth),
            [0, 1]
        )
        XCTAssertEqual(book.chapters.count, 1)
        XCTAssertEqual(book.chapters[0].title, "첫 장")
        XCTAssertTrue(
            book.chapters[0].text.contains(
                "DAISY 2 본문"
            )
        )
        XCTAssertNotNil(
            book.chapters[0]
                .fragmentSegmentIndexes["s1"]
        )
        XCTAssertEqual(
            PublicationNavigationResolver
                .location(
                    for:
                        book.navigationItems[0],
                    in: book
                ),
            PublicationNavigationLocation(
                chapterIndex: 0,
                segmentIndex:
                    try XCTUnwrap(
                        book.chapters[0]
                            .fragmentSegmentIndexes[
                                "s1"
                            ]
                    )
            )
        )
        XCTAssertEqual(
            book.mediaOverlayItems,
            [
                EPUBMediaOverlayItem(
                    id:
                        "Book/smil/part1.smil"
                        + "#par-1",
                    smilPath:
                        "Book/smil/part1.smil",
                    textPath:
                        "Book/text/chapter.html",
                    textFragmentID: "s1",
                    audioPath:
                        "Book/audio/book.mp3",
                    clipBeginSeconds: 1.5,
                    clipEndSeconds: 4,
                    playOrder: 1
                ),
            ]
        )
    }

    func testParsesDaisy3PackageNCXAndDTBook()
        throws
    {
        let book = try AccessiblePublicationParser
            .parse(
                data: DaisyFixture.makeDaisy3()
            )

        XCTAssertEqual(book.format, .daisy3)
        XCTAssertEqual(
            book.identifier,
            "rivo-daisy-3"
        )
        XCTAssertEqual(book.title, "DAISY 3 테스트")
        XCTAssertEqual(book.creator, "Rivo")
        XCTAssertEqual(book.language, "ko")
        XCTAssertEqual(
            book.navigationItems.map(\.label),
            ["첫 장", "하위 절"]
        )
        XCTAssertEqual(
            book.navigationItems.map(\.depth),
            [0, 1]
        )
        XCTAssertEqual(
            book.pageListItems.map(\.label),
            ["1"]
        )
        XCTAssertEqual(
            book.pageListItems.first?.href,
            "DAISY/text/book.xml#page-1"
        )
        XCTAssertEqual(book.chapters.count, 1)
        XCTAssertEqual(book.chapters[0].title, "첫 장")
        XCTAssertTrue(
            book.chapters[0].text.contains(
                "DAISY 3 문장"
            )
        )
        XCTAssertNotNil(
            book.chapters[0]
                .fragmentSegmentIndexes["s1"]
        )
        XCTAssertNotNil(
            book.chapters[0]
                .fragmentSegmentIndexes["page-1"]
        )
        XCTAssertEqual(
            PublicationNavigationResolver
                .location(
                    for:
                        book.navigationItems[1],
                    in: book
                ),
            PublicationNavigationLocation(
                chapterIndex: 0,
                segmentIndex:
                    try XCTUnwrap(
                        book.chapters[0]
                            .fragmentSegmentIndexes[
                                "s2"
                            ]
                    )
            )
        )
        XCTAssertEqual(
            PublicationNavigationResolver
                .location(
                    for:
                        book.pageListItems[0],
                    in: book
                ),
            PublicationNavigationLocation(
                chapterIndex: 0,
                segmentIndex:
                    try XCTUnwrap(
                        book.chapters[0]
                            .fragmentSegmentIndexes[
                                "page-1"
                            ]
                    )
            )
        )
        XCTAssertEqual(
            book.mediaOverlayItems.first,
            EPUBMediaOverlayItem(
                id:
                    "DAISY/audio.smil#par-1",
                smilPath: "DAISY/audio.smil",
                textPath:
                    "DAISY/text/book.xml",
                textFragmentID: "s1",
                audioPath:
                    "DAISY/audio/book.mp3",
                clipBeginSeconds: 0,
                clipEndSeconds: 2.25,
                playOrder: 1
            )
        )
    }

    func testAccessiblePublicationRejectsUnknownZIP()
        throws
    {
        let data = try ZIPFixture.make(
            entries: [
                ZIPFixtureEntry(
                    path: "readme.txt",
                    data: Data("not a book".utf8),
                    compressionMethod: 8
                ),
            ]
        )

        XCTAssertThrowsError(
            try AccessiblePublicationParser
                .parse(data: data)
        ) { error in
            guard let parserError =
                    error as?
                    AccessiblePublicationParserError,
                  case .unsupportedFormat =
                    parserError else {
                return XCTFail(
                    "예상하지 못한 오류: \(error)"
                )
            }
        }
    }
}

private nonisolated enum EPUBFixture {
    static func makeBook() throws -> Data {
        let container = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container
          version="1.0"
          xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile
              full-path="OEBPS/content.opf"
              media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """
        let package = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package
          version="3.0"
          unique-identifier="book-id"
          xmlns="http://www.idpf.org/2007/opf">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="book-id">rivo-epub-fixture</dc:identifier>
            <dc:title>테스트 책</dc:title>
            <dc:creator>Rivo</dc:creator>
            <dc:language>ko</dc:language>
          </metadata>
          <manifest>
            <item
              id="nav"
              href="nav.xhtml"
              media-type="application/xhtml+xml"
              properties="nav"/>
            <item
              id="chapter-1"
              href="chapter1.xhtml"
              media-type="application/xhtml+xml"/>
            <item
              id="chapter-2"
              href="chapter2.xhtml"
              media-type="application/xhtml+xml"
              media-overlay="overlay-2"/>
            <item
              id="overlay-2"
              href="chapter2.smil"
              media-type="application/smil+xml"/>
            <item
              id="audio-2"
              href="audio/chapter2.mp3"
              media-type="audio/mpeg"/>
          </manifest>
          <spine>
            <itemref idref="chapter-1"/>
            <itemref idref="chapter-2"/>
          </spine>
        </package>
        """
        let navigation = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html
          xmlns="http://www.w3.org/1999/xhtml"
          xmlns:epub="http://www.idpf.org/2007/ops">
          <head><title>목차</title></head>
          <body>
            <nav epub:type="toc">
              <ol>
                <li><a href="chapter1.xhtml">첫 번째 장</a></li>
                <li><a href="chapter2.xhtml">두 번째 장</a></li>
              </ol>
            </nav>
          </body>
        </html>
        """
        let firstChapter = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
          <head>
            <title>내부 제목</title>
            <style>.hidden { display: none; }</style>
          </head>
          <body>
            <nav>숨은 메뉴</nav>
            <h1>본문의 첫 제목</h1>
            <p>첫 문장&nbsp;이어지는 내용</p>
            <script>표시하지 않음</script>
          </body>
        </html>
        """
        let secondChapter = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
          <head><title>둘째</title></head>
          <body>
            <h1>두 번째 장</h1>
            <p id="offline">오프라인 독서를 위한 두 번째 본문입니다.</p>
          </body>
        </html>
        """
        let mediaOverlay = """
        <?xml version="1.0" encoding="UTF-8"?>
        <smil
          xmlns="http://www.w3.org/ns/SMIL"
          version="3.0">
          <body>
            <seq>
              <par id="offline-par" playOrder="4">
                <text src="chapter2.xhtml#offline"/>
                <audio
                  id="offline-audio"
                  src="audio/chapter2.mp3"
                  clipBegin="1.25s"
                  clipEnd="3.5s"/>
                <audio
                  id="offline-audio-2"
                  src="audio/chapter2.mp3"
                  clipBegin="3.5s"/>
              </par>
            </seq>
          </body>
        </smil>
        """

        return try ZIPFixture.make(
            entries: [
                ZIPFixtureEntry(
                    path: "mimetype",
                    data: Data(
                        "application/epub+zip".utf8
                    ),
                    compressionMethod: 0
                ),
                ZIPFixtureEntry(
                    path: "META-INF/container.xml",
                    data: Data(container.utf8),
                    compressionMethod: 8
                ),
                ZIPFixtureEntry(
                    path: "OEBPS/content.opf",
                    data: Data(package.utf8),
                    compressionMethod: 8
                ),
                ZIPFixtureEntry(
                    path: "OEBPS/nav.xhtml",
                    data: Data(navigation.utf8),
                    compressionMethod: 8
                ),
                ZIPFixtureEntry(
                    path: "OEBPS/chapter1.xhtml",
                    data: Data(firstChapter.utf8),
                    compressionMethod: 8
                ),
                ZIPFixtureEntry(
                    path: "OEBPS/chapter2.xhtml",
                    data: Data(secondChapter.utf8),
                    compressionMethod: 8
                ),
                ZIPFixtureEntry(
                    path: "OEBPS/chapter2.smil",
                    data: Data(mediaOverlay.utf8),
                    compressionMethod: 8
                ),
                ZIPFixtureEntry(
                    path:
                        "OEBPS/audio/chapter2.mp3",
                    data: Data([
                        0x49, 0x44, 0x33, 0x04,
                    ]),
                    compressionMethod: 0
                )
            ]
        )
    }
}

private nonisolated enum DaisyFixture {
    static func makeDaisy202() throws -> Data {
        let ncc = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
          <head>
            <title>DAISY 2 테스트</title>
            <meta name="dc:identifier" content="rivo-daisy-202"/>
            <meta name="dc:title" content="DAISY 2 테스트"/>
            <meta name="dc:creator" content="Rivo"/>
            <meta name="dc:language" content="ko"/>
          </head>
          <body>
            <h1 id="n1">
              <a href="smil/part1.smil#nav-1">첫 장</a>
            </h1>
            <h2 id="n2">
              <a href="smil/part1.smil#nav-2">첫 장의 절</a>
            </h2>
          </body>
        </html>
        """
        let smil = """
        <?xml version="1.0" encoding="UTF-8"?>
        <smil>
          <body>
            <seq>
              <par id="par-1" playOrder="1">
                <text src="../text/chapter.html#s1"/>
                <audio
                  src="../audio/book.mp3"
                  clip-begin="1.5s"
                  clip-end="4s"/>
              </par>
            </seq>
          </body>
        </smil>
        """
        let chapter = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
          <head><title>첫 장</title></head>
          <body>
            <h1>첫 장</h1>
            <p id="s1">DAISY 2 본문입니다.</p>
          </body>
        </html>
        """
        return try ZIPFixture.make(
            entries: [
                ZIPFixtureEntry(
                    path: "Book/NCC.HTML",
                    data: Data(ncc.utf8),
                    compressionMethod: 8
                ),
                ZIPFixtureEntry(
                    path: "Book/smil/part1.smil",
                    data: Data(smil.utf8),
                    compressionMethod: 8
                ),
                ZIPFixtureEntry(
                    path:
                        "Book/text/chapter.html",
                    data: Data(chapter.utf8),
                    compressionMethod: 8
                ),
                ZIPFixtureEntry(
                    path: "Book/audio/book.mp3",
                    data: Data([
                        0x49, 0x44, 0x33, 0x04,
                    ]),
                    compressionMethod: 0
                ),
            ]
        )
    }

    static func makeDaisy3() throws -> Data {
        let package = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package
          unique-identifier="book-id"
          xmlns="http://openebook.org/namespaces/oeb-package/1.0/">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="book-id">rivo-daisy-3</dc:identifier>
            <dc:title>DAISY 3 테스트</dc:title>
            <dc:creator>Rivo</dc:creator>
            <dc:language>ko</dc:language>
          </metadata>
          <manifest>
            <item
              id="ncx"
              href="navigation.ncx"
              media-type="application/x-dtbncx+xml"/>
            <item
              id="smil"
              href="audio.smil"
              media-type="application/smil+xml"/>
            <item
              id="text"
              href="text/book.xml"
              media-type="application/x-dtbook+xml"/>
            <item
              id="audio"
              href="audio/book.mp3"
              media-type="audio/mpeg"/>
          </manifest>
          <spine toc="ncx">
            <itemref idref="smil"/>
          </spine>
        </package>
        """
        let navigation = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/">
          <navMap>
            <navPoint id="nav-1" playOrder="1">
              <navLabel><text>첫 장</text></navLabel>
              <content src="text/book.xml#s1"/>
              <navPoint id="nav-2" playOrder="2">
                <navLabel><text>하위 절</text></navLabel>
                <content src="text/book.xml#s2"/>
              </navPoint>
            </navPoint>
          </navMap>
          <pageList>
            <pageTarget id="page-1" playOrder="3">
              <navLabel><text>1</text></navLabel>
              <content src="text/book.xml#page-1"/>
            </pageTarget>
          </pageList>
        </ncx>
        """
        let smil = """
        <?xml version="1.0" encoding="UTF-8"?>
        <smil xmlns="http://www.w3.org/2001/SMIL20/">
          <body>
            <seq>
              <par id="par-1" playOrder="1">
                <text src="text/book.xml#s1"/>
                <audio
                  src="audio/book.mp3"
                  clipBegin="0s"
                  clipEnd="2.25s"/>
              </par>
            </seq>
          </body>
        </smil>
        """
        let book = """
        <?xml version="1.0" encoding="UTF-8"?>
        <dtbook xmlns="http://www.daisy.org/z3986/2005/dtbook/">
          <head>
            <meta name="dc:Title" content="DAISY 3 테스트"/>
          </head>
          <book>
            <frontmatter>
              <doctitle>DAISY 3 테스트</doctitle>
            </frontmatter>
            <bodymatter>
              <level1>
                <h1>첫 장</h1>
                <p><sent id="s1">DAISY 3 문장입니다.</sent></p>
                <p><sent id="s2">하위 절 본문입니다.</sent></p>
                <pagenum id="page-1">1</pagenum>
              </level1>
            </bodymatter>
          </book>
        </dtbook>
        """
        return try ZIPFixture.make(
            entries: [
                ZIPFixtureEntry(
                    path: "DAISY/package.opf",
                    data: Data(package.utf8),
                    compressionMethod: 8
                ),
                ZIPFixtureEntry(
                    path: "DAISY/navigation.ncx",
                    data: Data(navigation.utf8),
                    compressionMethod: 8
                ),
                ZIPFixtureEntry(
                    path: "DAISY/audio.smil",
                    data: Data(smil.utf8),
                    compressionMethod: 8
                ),
                ZIPFixtureEntry(
                    path: "DAISY/text/book.xml",
                    data: Data(book.utf8),
                    compressionMethod: 8
                ),
                ZIPFixtureEntry(
                    path: "DAISY/audio/book.mp3",
                    data: Data([
                        0x49, 0x44, 0x33, 0x04,
                    ]),
                    compressionMethod: 0
                ),
            ]
        )
    }
}

private nonisolated struct ZIPFixtureEntry {
    let path: String
    let data: Data
    let compressionMethod: UInt16
}

private nonisolated enum ZIPFixture {
    private struct CentralEntry {
        let pathData: Data
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let compressionMethod: UInt16
        let checksum: UInt32
        let localHeaderOffset: UInt32
    }

    static func make(
        entries: [ZIPFixtureEntry]
    ) throws -> Data {
        var archive = Data()
        var centralEntries: [CentralEntry] = []

        for entry in entries {
            let pathData = Data(entry.path.utf8)
            let compressed: Data
            switch entry.compressionMethod {
            case 0:
                compressed = entry.data
            case 8:
                compressed = try rawDeflate(entry.data)
            default:
                throw ZIPFixtureError.unsupportedCompression
            }
            let checksum = crc(of: entry.data)
            let localOffset = try uint32(archive.count)

            archive.appendLittleEndian(UInt32(0x0403_4B50))
            archive.appendLittleEndian(UInt16(20))
            archive.appendLittleEndian(UInt16(0x0800))
            archive.appendLittleEndian(entry.compressionMethod)
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(checksum)
            archive.appendLittleEndian(
                try uint32(compressed.count)
            )
            archive.appendLittleEndian(
                try uint32(entry.data.count)
            )
            archive.appendLittleEndian(
                try uint16(pathData.count)
            )
            archive.appendLittleEndian(UInt16(0))
            archive.append(pathData)
            archive.append(compressed)

            centralEntries.append(
                CentralEntry(
                    pathData: pathData,
                    compressedSize: try uint32(
                        compressed.count
                    ),
                    uncompressedSize: try uint32(
                        entry.data.count
                    ),
                    compressionMethod:
                        entry.compressionMethod,
                    checksum: checksum,
                    localHeaderOffset: localOffset
                )
            )
        }

        let centralOffset = try uint32(archive.count)
        for entry in centralEntries {
            archive.appendLittleEndian(UInt32(0x0201_4B50))
            archive.appendLittleEndian(UInt16(20))
            archive.appendLittleEndian(UInt16(20))
            archive.appendLittleEndian(UInt16(0x0800))
            archive.appendLittleEndian(entry.compressionMethod)
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(entry.checksum)
            archive.appendLittleEndian(entry.compressedSize)
            archive.appendLittleEndian(entry.uncompressedSize)
            archive.appendLittleEndian(
                try uint16(entry.pathData.count)
            )
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt32(0))
            archive.appendLittleEndian(
                entry.localHeaderOffset
            )
            archive.append(entry.pathData)
        }
        let centralSize = try uint32(
            archive.count - Int(centralOffset)
        )
        let entryCount = try uint16(centralEntries.count)

        archive.appendLittleEndian(UInt32(0x0605_4B50))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(entryCount)
        archive.appendLittleEndian(entryCount)
        archive.appendLittleEndian(centralSize)
        archive.appendLittleEndian(centralOffset)
        archive.appendLittleEndian(UInt16(0))
        return archive
    }

    private static func rawDeflate(
        _ data: Data
    ) throws -> Data {
        var stream = z_stream()
        let initialization = deflateInit2_(
            &stream,
            Z_DEFAULT_COMPRESSION,
            Z_DEFLATED,
            -MAX_WBITS,
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initialization == Z_OK else {
            throw ZIPFixtureError.compressionFailed
        }
        defer {
            deflateEnd(&stream)
        }

        let capacity = max(
            Int(deflateBound(&stream, uLong(data.count))),
            1
        )
        var output = Data(count: capacity)
        let status = data.withUnsafeBytes { inputBytes in
            output.withUnsafeMutableBytes { outputBytes in
                stream.next_in = UnsafeMutablePointer<Bytef>(
                    mutating: inputBytes.bindMemory(
                        to: Bytef.self
                    ).baseAddress
                )
                stream.avail_in = uInt(data.count)
                stream.next_out = outputBytes.bindMemory(
                    to: Bytef.self
                ).baseAddress
                stream.avail_out = uInt(capacity)
                return deflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END else {
            throw ZIPFixtureError.compressionFailed
        }
        return Data(output.prefix(Int(stream.total_out)))
    }

    private static func crc(of data: Data) -> UInt32 {
        data.withUnsafeBytes { bytes in
            UInt32(
                crc32(
                    0,
                    bytes.bindMemory(to: Bytef.self).baseAddress,
                    uInt(data.count)
                )
            )
        }
    }

    private static func uint16(_ value: Int) throws -> UInt16 {
        guard let value = UInt16(exactly: value) else {
            throw ZIPFixtureError.valueTooLarge
        }
        return value
    }

    private static func uint32(_ value: Int) throws -> UInt32 {
        guard let value = UInt32(exactly: value) else {
            throw ZIPFixtureError.valueTooLarge
        }
        return value
    }
}

private nonisolated enum ZIPFixtureError: Error {
    case compressionFailed
    case unsupportedCompression
    case valueTooLarge
}

private extension Data {
    nonisolated mutating func appendLittleEndian(
        _ value: UInt16
    ) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) {
            append(contentsOf: $0)
        }
    }

    nonisolated mutating func appendLittleEndian(
        _ value: UInt32
    ) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) {
            append(contentsOf: $0)
        }
    }
}
