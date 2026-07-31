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
        XCTAssertEqual(
            book.navigationItems.map(\.label),
            ["첫 번째 장", "첫 문단", "두 번째 장"]
        )
        XCTAssertEqual(
            book.navigationItems.map(\.depth),
            [0, 1, 0]
        )
        XCTAssertEqual(
            book.pageListItems.map(\.label),
            ["1", "2"]
        )
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
            PublicationNavigationResolver.location(
                for: book.pageListItems[0],
                in: book
            ),
            PublicationNavigationLocation(
                chapterIndex: 0,
                segmentIndex: 1
            )
        )
        XCTAssertEqual(
            PublicationNavigationResolver.location(
                for: book.pageListItems[1],
                in: book
            ),
            PublicationNavigationLocation(
                chapterIndex: 1,
                segmentIndex: 1
            )
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

    func testParsesEPUB2NCXHierarchyAndPageTargets()
        throws
    {
        let book = try EPUBBookParser.parse(
            data: EPUBFixture.makeEPUB2WithNCX()
        )

        XCTAssertEqual(book.format, .epub)
        XCTAssertEqual(
            book.navigationItems.map(\.label),
            ["첫 장", "첫 절"]
        )
        XCTAssertEqual(
            book.navigationItems.map(\.depth),
            [0, 1]
        )
        XCTAssertEqual(
            book.navigationItems.map(\.playOrder),
            [1, 2]
        )
        XCTAssertEqual(
            book.pageListItems.map(\.label),
            ["10"]
        )
        XCTAssertEqual(
            book.pageListItems.map(\.playOrder),
            [3]
        )
        XCTAssertEqual(
            PublicationNavigationResolver.location(
                for: book.pageListItems[0],
                in: book
            ),
            PublicationNavigationLocation(
                chapterIndex: 0,
                segmentIndex: 1
            )
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

        EPUBProgressStore.removeProgress(
            for: "book",
            defaults: defaults
        )
        XCTAssertNil(
            EPUBProgressStore.progress(
                for: "book",
                defaults: defaults
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

    func testReadAloudTimelineMapsMixedTTSAndAudioSeek()
        throws
    {
        let steps = [
            EPUBReadAloudStep(
                id: "tts",
                chapterIndex: 0,
                segmentIndex: 0,
                text: "12345",
                audioItemIndex: nil
            ),
            EPUBReadAloudStep(
                id: "audio",
                chapterIndex: 0,
                segmentIndex: 1,
                text: "audio",
                audioItemIndex: 0
            ),
        ]
        let items = [
            EPUBMediaOverlayItem(
                id: "clip",
                smilPath: "book.smil",
                textPath: "chapter.xhtml",
                textFragmentID: "p2",
                audioPath: "audio.mp3",
                clipBeginSeconds: 10,
                clipEndSeconds: 14,
                playOrder: 1
            ),
        ]
        let timeline = EPUBReadAloudTimeline(
            steps: steps,
            items: items,
            speechRate: 1
        )

        XCTAssertEqual(
            timeline.totalDurationSeconds,
            5,
            accuracy: 0.001
        )
        let textTarget = timeline.target(
            at: 0.5
        )
        XCTAssertEqual(
            textTarget?.stepIndex,
            0
        )
        XCTAssertEqual(
            textTarget?.textUTF16Offset,
            2
        )

        let audioTarget = timeline.target(
            at: 3
        )
        XCTAssertEqual(
            audioTarget?.stepIndex,
            1
        )
        XCTAssertEqual(
            try XCTUnwrap(
                audioTarget?
                    .progressWithinStep
            ),
            0.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(
                audioTarget?
                    .audioTimeSeconds
            ),
            12,
            accuracy: 0.001
        )
        XCTAssertEqual(
            timeline.position(
                stepIndex: 1,
                audioTimeSeconds: 11,
                textUTF16Offset: nil
            ),
            2,
            accuracy: 0.001
        )
        XCTAssertEqual(
            timeline.position(
                stepIndex: 0,
                audioTimeSeconds: nil,
                textUTF16Offset: 2
            ),
            0.4,
            accuracy: 0.001
        )

        let endTarget = timeline.target(
            at: 99
        )
        XCTAssertEqual(
            endTarget?.stepIndex,
            1
        )
        XCTAssertEqual(
            try XCTUnwrap(
                endTarget?
                    .audioTimeSeconds
            ),
            14,
            accuracy: 0.001
        )
        let fastTimeline =
            EPUBReadAloudTimeline(
                steps: steps,
                items: items,
                speechRate: 2
            )
        XCTAssertEqual(
            fastTimeline
                .totalDurationSeconds,
            4.5,
            accuracy: 0.001
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

    func testReadAloudTextNavigatorUsesUTF16WordRanges()
    {
        let text = "😀 첫 단어, 둘째 단어."
        let ranges =
            EPUBReadAloudTextNavigator.ranges(
                in: text,
                unit: .word
            )
        let words = ranges.compactMap {
            range -> String? in
            guard let range =
                    Range(range, in: text) else {
                return nil
            }
            return String(text[range])
        }

        XCTAssertEqual(
            words,
            ["😀", "첫", "단어,", "둘째", "단어."]
        )
        XCTAssertEqual(ranges.first?.location, 0)
        XCTAssertEqual(ranges.first?.length, 2)
        XCTAssertEqual(
            EPUBReadAloudNavigationUnit
                .word.next(),
            .line
        )
        XCTAssertEqual(
            EPUBReadAloudNavigationUnit
                .chapter.next(),
            .word
        )
        XCTAssertEqual(
            EPUBReadAloudNavigationUnit
                .word.shifted(by: -1),
            .chapter
        )
        XCTAssertEqual(
            EPUBReadAloudNavigationUnit
                .line.shifted(by: 9),
            .word
        )
    }

    func testReadAloudLineNavigationUsesAndroidSentenceBoundaries()
        throws
    {
        let text =
            "첫 줄입니다.\n둘째 줄입니다! 마지막 줄입니다."
        let ranges =
            EPUBReadAloudTextNavigator.ranges(
                in: text,
                unit: .line
            )
        let lines = try ranges.map {
            range -> String in
            let swiftRange = try XCTUnwrap(
                Range(range, in: text)
            )
            return String(text[swiftRange])
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
        }

        XCTAssertEqual(
            lines,
            [
                "첫 줄입니다.",
                "둘째 줄입니다!",
                "마지막 줄입니다.",
            ]
        )
    }

    func testReaderSheetsPauseAndResumeOnlyPriorPlayback()
    {
        var coordinator =
            EPUBReaderSheetPlaybackCoordinator()

        XCTAssertEqual(
            coordinator.presentationChanged(
                isPresented: true,
                isPlaying: true
            ),
            .pause
        )
        XCTAssertTrue(
            coordinator.resumesAfterSheet
        )
        XCTAssertEqual(
            coordinator.presentationChanged(
                isPresented: true,
                isPlaying: false
            ),
            .none
        )
        XCTAssertEqual(
            coordinator.presentationChanged(
                isPresented: false,
                isPlaying: false
            ),
            .resume
        )
        XCTAssertFalse(
            coordinator.resumesAfterSheet
        )
        XCTAssertEqual(
            coordinator.presentationChanged(
                isPresented: false,
                isPlaying: false
            ),
            .none
        )

        var pausedCoordinator =
            EPUBReaderSheetPlaybackCoordinator()
        XCTAssertEqual(
            pausedCoordinator
                .presentationChanged(
                    isPresented: true,
                    isPlaying: false
                ),
            .none
        )
        XCTAssertEqual(
            pausedCoordinator
                .presentationChanged(
                    isPresented: false,
                    isPlaying: false
                ),
            .none
        )
    }

    func testReaderAutoplayMatchesAndroidTimingAndGuards()
    {
        XCTAssertEqual(
            EPUBReaderAutoplayPolicy
                .delayNanoseconds(
                    isVoiceOverRunning: false
                ),
            500_000_000
        )
        XCTAssertEqual(
            EPUBReaderAutoplayPolicy
                .delayNanoseconds(
                    isVoiceOverRunning: true
                ),
            2_000_000_000
        )
        XCTAssertTrue(
            EPUBReaderAutoplayPolicy
                .shouldStart(
                    canPlay: true,
                    isPlaying: false,
                    isSheetPresented: false
                )
        )
        XCTAssertFalse(
            EPUBReaderAutoplayPolicy
                .shouldStart(
                    canPlay: true,
                    isPlaying: false,
                    isSheetPresented: true
                )
        )
        XCTAssertFalse(
            EPUBReaderAutoplayPolicy
                .shouldStart(
                    canPlay: true,
                    isPlaying: true,
                    isSheetPresented: false
                )
        )
        XCTAssertFalse(
            EPUBReaderAutoplayPolicy
                .shouldStart(
                    canPlay: false,
                    isPlaying: false,
                    isSheetPresented: false
                )
        )
    }

    func testReaderProgressIgnoresViewportWhilePlaybackIsActive()
    {
        XCTAssertFalse(
            EPUBReaderProgressTrackingPolicy
                .shouldAdoptVisibleSegment(
                    isPlaybackActive: true
                )
        )
        XCTAssertTrue(
            EPUBReaderProgressTrackingPolicy
                .shouldAdoptVisibleSegment(
                    isPlaybackActive: false
                )
        )
    }

    func testReadAloudSpeechChunksAtSentenceBoundaries()
        throws
    {
        let text =
            "첫 문장입니다. 두 번째 문장입니다! 마지막입니다."
        let first =
            try XCTUnwrap(
                EPUBReadAloudTextNavigator
                    .speechRange(
                        in: text,
                        fromUTF16: 0
                    )
            )
        let second =
            try XCTUnwrap(
                EPUBReadAloudTextNavigator
                    .speechRange(
                        in: text,
                        fromUTF16:
                            NSMaxRange(first)
                    )
            )
        let firstRange =
            try XCTUnwrap(
                Range(first, in: text)
            )
        let secondRange =
            try XCTUnwrap(
                Range(second, in: text)
            )

        XCTAssertEqual(
            String(text[firstRange])
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
            "첫 문장입니다."
        )
        XCTAssertEqual(
            String(text[secondRange])
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
            "두 번째 문장입니다!"
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

    func testLibraryDeduplicatesPersistsAndDeletesBooks()
        async throws
    {
        let testDirectory = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "RivoEPUBLibraryDedupTests-\(UUID().uuidString)",
                isDirectory: true
            )
        let sourceDirectory = testDirectory
            .appendingPathComponent(
                "Source",
                isDirectory: true
            )
        let booksDirectory = testDirectory
            .appendingPathComponent(
                "Books",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(
                at: testDirectory
            )
        }

        let expected = try EPUBFixture.makeBook()
        let firstSource = sourceDirectory
            .appendingPathComponent("first.epub")
        let duplicateSource = sourceDirectory
            .appendingPathComponent("duplicate.epub")
        try expected.write(to: firstSource)
        try expected.write(to: duplicateSource)

        let store = EPUBLibraryStore(
            booksDirectory: booksDirectory
        )
        let first = try await store
            .importBookWithResult(
                from: firstSource
            )
        let duplicate = try await store
            .importBookWithResult(
                from: duplicateSource
            )

        XCTAssertFalse(
            first.reusedExistingBook
        )
        XCTAssertTrue(
            duplicate.reusedExistingBook
        )
        XCTAssertEqual(
            first.book.fileURL,
            duplicate.book.fileURL
        )
        let booksAfterDuplicate =
            try await store.books()
        XCTAssertEqual(
            booksAfterDuplicate.count,
            1
        )
        XCTAssertEqual(
            duplicate.book.contentDigest?
                .count,
            64
        )

        let opened = try await store.markOpened(
            bookURL: first.book.fileURL,
            publicationIdentifier:
                "fixture-publication"
        )
        XCTAssertEqual(
            opened?.publicationIdentifier,
            "fixture-publication"
        )

        let reopenedStore = EPUBLibraryStore(
            booksDirectory: booksDirectory
        )
        let restored = try await
            reopenedStore.books()
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(
            restored.first?
                .publicationIdentifier,
            "fixture-publication"
        )
        XCTAssertEqual(
            restored.first?.contentDigest,
            duplicate.book.contentDigest
        )

        if let book = restored.first {
            _ = try await reopenedStore
                .deleteBook(book)
        }
        let booksAfterDelete =
            try await reopenedStore.books()
        XCTAssertTrue(
            booksAfterDelete.isEmpty
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: firstSource.path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: duplicateSource.path
            )
        )
    }

    func testLibraryMigratesLegacyManagedBook()
        async throws
    {
        let testDirectory = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "RivoEPUBLegacyLibraryTests-\(UUID().uuidString)",
                isDirectory: true
            )
        let booksDirectory = testDirectory
            .appendingPathComponent(
                "Books",
                isDirectory: true
            )
        let legacyDirectory = booksDirectory
            .appendingPathComponent(
                "legacy-book",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: legacyDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(
                at: testDirectory
            )
        }
        let legacyURL = legacyDirectory
            .appendingPathComponent(
                "오래된 책.zip"
            )
        try Data("legacy".utf8).write(
            to: legacyURL
        )

        let store = EPUBLibraryStore(
            booksDirectory: booksDirectory
        )
        let books = try await store.books()

        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(
            books.first?.title,
            "오래된 책"
        )
        XCTAssertEqual(
            books.first?.formatDescription,
            "DAISY ZIP"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: legacyDirectory
                    .appendingPathComponent(
                        ".rivo-library-book.json"
                    )
                    .path
            )
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

    func testParsesDaisy202LooseNCCNavigationBlocks()
        throws
    {
        let book = try AccessiblePublicationParser
            .parse(
                data:
                    DaisyFixture
                    .makeDaisy202WithLooseNavigation()
            )

        XCTAssertEqual(book.format, .daisy202)
        XCTAssertEqual(
            book.navigationItems.map(\.label),
            [
                "첫 장",
                "첫 페이지",
                "보충 설명",
            ]
        )
        XCTAssertEqual(
            book.navigationItems.map(\.depth),
            [0, 1, 1]
        )
        XCTAssertEqual(
            book.navigationItems.compactMap(
                \.href
            ),
            [
                "Book/smil/part1.smil#nav-1",
                "Book/smil/part1.smil#nav-2",
                "Book/smil/part1.smil#nav-3",
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

    func testParserPreservesOriginalChapterMarkup()
        throws
    {
        let book = try EPUBBookParser.parse(
            data: EPUBFixture.makeBook()
        )
        let markup = try XCTUnwrap(
            book.chapters.first?
                .sourceMarkup
        )

        XCTAssertTrue(
            markup.contains(
                "<p id=\"first-text\">"
            )
        )
        XCTAssertTrue(
            markup.contains(
                "<script>표시하지 않음</script>"
            )
        )
    }

    func testOriginalMarkupCacheRejectsOversizedChapter() {
        XCTAssertNil(
            EPUBBookParser.sourceMarkup(
                Data(
                    repeating: 0x61,
                    count:
                        5 * 1_024 * 1_024
                        + 1
                )
            )
        )
    }

    func testOriginalMarkupAddsLocalOnlyPolicyAndAdaptiveStyle() {
        let source = """
        <html>
          <head>
            <base href="https://example.com/">
            <meta http-equiv="Content-Security-Policy" content="default-src *">
          </head>
          <body>
            <strong>강조</strong>
            <table><tr><td>셀</td></tr></table>
          </body>
        </html>
        """
        let rendered =
            EPUBOriginalMarkupRenderer
            .document(
                sourceMarkup: source,
                style:
                    EPUBOriginalMarkupStyle(
                        backgroundColor:
                            "#121417",
                        foregroundColor:
                            "#F2F2F5",
                        linkColor:
                            "#66AFFF",
                        fontScale: 1.2,
                        lineHeight: 1.8
                    )
            )

        XCTAssertFalse(
            rendered.localizedCaseInsensitiveContains(
                "<base"
            )
        )
        XCTAssertEqual(
            rendered
                .lowercased()
                .components(
                    separatedBy:
                        "content-security-policy"
                )
                .count,
            2
        )
        XCTAssertTrue(
            rendered.contains(
                "default-src 'none'"
            )
        )
        XCTAssertTrue(
            rendered.contains(
                "script-src 'none'"
            )
        )
        XCTAssertTrue(
            rendered.contains(
                "<strong>강조</strong>"
            )
        )
        XCTAssertTrue(
            rendered.contains(
                "<table>"
            )
        )
        XCTAssertTrue(
            rendered.contains(
                "font-size: 26.4px"
            )
        )
    }

    func testOriginalResourcePolicyAllowsOnlyPassiveBookAssets()
        throws
    {
        let base = try XCTUnwrap(
            EPUBOriginalResourcePolicy
                .publicationURL(
                    for:
                        "OEBPS/Text/chapter.xhtml"
                )
        )
        let imageURL = try XCTUnwrap(
            URL(
                string:
                    "../Images/cover.png",
                relativeTo: base
            )?.absoluteURL
        )
        XCTAssertEqual(
            EPUBOriginalResourcePolicy
                .archivePath(
                    forResourceURL:
                        imageURL
                ),
            "OEBPS/Images/cover.png"
        )
        XCTAssertNil(
            EPUBOriginalResourcePolicy
                .archivePath(
                    forResourceURL:
                        URL(
                            string:
                                "rivo-epub://book/OEBPS/evil.js"
                        )!
                )
        )
        XCTAssertNil(
            EPUBOriginalResourcePolicy
                .archivePath(
                    forResourceURL:
                        URL(
                            string:
                                "https://example.com/cover.png"
                        )!
                )
        )
    }

    func testOriginalLinkPolicySeparatesBookAndWebDestinations()
        throws
    {
        XCTAssertEqual(
            EPUBOriginalResourcePolicy
                .classifyLink(
                    URL(
                        string:
                            "rivo-epub://book/OEBPS/chapter2.xhtml#part"
                    )!
                ),
            .publication(
                path:
                    "OEBPS/chapter2.xhtml",
                fragment: "part"
            )
        )
        let external = URL(
            string:
                "https://example.com/reference"
        )!
        XCTAssertEqual(
            EPUBOriginalResourcePolicy
                .classifyLink(external),
            .external(external)
        )
        XCTAssertEqual(
            EPUBOriginalResourcePolicy
                .classifyLink(
                    URL(
                        string:
                            "javascript:alert(1)"
                    )!
                ),
            .blocked
        )
    }

    func testHTMLNamedEntitiesRemainXMLCompatible()
        throws
    {
        let delegate = EPUBHTMLTextDelegate()
        try EPUBBookParser.parseXHTML(
            Data(
                """
                <html><body><p>
                Caf&eacute; &euro; &unknown; &#0;
                </p></body></html>
                """.utf8
            ),
            delegate: delegate
        )

        XCTAssertTrue(
            delegate.text.contains(
                "Café € &unknown; &#0;"
            )
        )
    }

    func testMalformedChapterUsesSafeTextFallback()
        throws
    {
        let malformed = """
        <html>
          <head><title>깨진 XHTML</title></head>
          <body>
            <h1>깨진 장</h1>
            <p>첫 caf&eacute; 문단
            <p>둘째 &unknown; 문단
            <script>숨기고 실행하지 않음</script>
          </body>
        </html>
        """
        let book = try EPUBBookParser.parse(
            data:
                EPUBFixture.makeBook(
                    firstChapterMarkup:
                        malformed
                )
        )

        XCTAssertEqual(
            book.chapters.count,
            2
        )
        XCTAssertTrue(
            book.chapters[0].text.contains(
                "첫 café 문단"
            )
        )
        XCTAssertTrue(
            book.chapters[0].text.contains(
                "둘째 &unknown; 문단"
            )
        )
        XCTAssertFalse(
            book.chapters[0].text.contains(
                "숨기고 실행하지 않음"
            )
        )
        XCTAssertEqual(
            book.chapters[0]
                .sourceMarkup,
            malformed
        )
    }

    func testMalformedNavigationDoesNotRejectReadableSpine()
        throws
    {
        let malformedNavigation = """
        <html xmlns="http://www.w3.org/1999/xhtml">
          <body>
            <nav type="toc">
              <ol>
                <li><a href="chapter1.xhtml">첫 장</a>
                <li><a href="chapter2.xhtml">둘째 장</a>
              </ol>
            </nav>
          </body>
        </html>
        """
        let book = try EPUBBookParser.parse(
            data:
                EPUBFixture.makeBook(
                    navigationMarkup:
                        malformedNavigation
                )
        )

        XCTAssertEqual(
            book.chapters.count,
            2
        )
        XCTAssertTrue(
            book.navigationItems.isEmpty
        )
        XCTAssertEqual(
            book.chapters[0].title,
            "본문의 첫 제목"
        )
    }
}

private nonisolated enum EPUBFixture {
    static func makeBook(
        firstChapterMarkup:
            String? = nil,
        navigationMarkup:
            String? = nil
    ) throws -> Data {
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
        let defaultNavigation = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html
          xmlns="http://www.w3.org/1999/xhtml"
          xmlns:epub="http://www.idpf.org/2007/ops">
          <head><title>목차</title></head>
          <body>
            <nav epub:type="toc">
              <ol>
                <li>
                  <a href="chapter1.xhtml">첫 번째 장</a>
                  <ol>
                    <li>
                      <a href="chapter1.xhtml#first-text">첫 문단</a>
                    </li>
                  </ol>
                </li>
                <li><a href="chapter2.xhtml">두 번째 장</a></li>
              </ol>
            </nav>
            <nav epub:type="page-list">
              <ol>
                <li><a href="chapter1.xhtml#page-1">1</a></li>
                <li><a href="chapter2.xhtml#page-2">2</a></li>
              </ol>
            </nav>
          </body>
        </html>
        """
        let navigation =
            navigationMarkup
            ?? defaultNavigation
        let defaultFirstChapter = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html
          xmlns="http://www.w3.org/1999/xhtml"
          xmlns:epub="http://www.idpf.org/2007/ops">
          <head>
            <title>내부 제목</title>
            <style>.hidden { display: none; }</style>
          </head>
          <body>
            <nav>숨은 메뉴</nav>
            <h1>본문의 첫 제목</h1>
            <span
              id="page-1"
              epub:type="pagebreak"
              title="1"/>
            <p id="first-text">첫 문장&nbsp;이어지는 내용</p>
            <script>표시하지 않음</script>
          </body>
        </html>
        """
        let firstChapter =
            firstChapterMarkup
            ?? defaultFirstChapter
        let secondChapter = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html
          xmlns="http://www.w3.org/1999/xhtml"
          xmlns:epub="http://www.idpf.org/2007/ops">
          <head><title>둘째</title></head>
          <body>
            <h1>두 번째 장</h1>
            <span
              id="page-2"
              epub:type="pagebreak"
              title="2"/>
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

    static func makeEPUB2WithNCX() throws -> Data {
        let container = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container
          version="1.0"
          xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile
              full-path="OPS/package.opf"
              media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """
        let package = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package
          version="2.0"
          unique-identifier="book-id"
          xmlns="http://www.idpf.org/2007/opf">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="book-id">rivo-epub2-fixture</dc:identifier>
            <dc:title>EPUB 2 테스트</dc:title>
            <dc:creator>Rivo</dc:creator>
            <dc:language>ko</dc:language>
          </metadata>
          <manifest>
            <item
              id="ncx"
              href="navigation.ncx"
              media-type="application/x-dtbncx+xml"/>
            <item
              id="chapter"
              href="chapter.xhtml"
              media-type="application/xhtml+xml"/>
          </manifest>
          <spine toc="ncx">
            <itemref idref="chapter"/>
          </spine>
        </package>
        """
        let navigation = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/">
          <navMap>
            <navPoint id="nav-1" playOrder="1">
              <navLabel><text>첫 장</text></navLabel>
              <content src="chapter.xhtml#heading"/>
              <navPoint id="nav-2" playOrder="2">
                <navLabel><text>첫 절</text></navLabel>
                <content src="chapter.xhtml#body"/>
              </navPoint>
            </navPoint>
          </navMap>
          <pageList>
            <pageTarget id="page-10" playOrder="3">
              <navLabel><text>10</text></navLabel>
              <content src="chapter.xhtml#page-10"/>
            </pageTarget>
          </pageList>
        </ncx>
        """
        let chapter = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
          <head><title>첫 장</title></head>
          <body>
            <h1 id="heading">첫 장</h1>
            <span id="page-10"/>
            <p id="body">EPUB 2 본문입니다.</p>
          </body>
        </html>
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
                    path: "OPS/package.opf",
                    data: Data(package.utf8),
                    compressionMethod: 8
                ),
                ZIPFixtureEntry(
                    path: "OPS/navigation.ncx",
                    data: Data(navigation.utf8),
                    compressionMethod: 8
                ),
                ZIPFixtureEntry(
                    path: "OPS/chapter.xhtml",
                    data: Data(chapter.utf8),
                    compressionMethod: 8
                ),
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

    static func makeDaisy202WithLooseNavigation()
        throws -> Data
    {
        let ncc = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
          <head>
            <title>느슨한 NCC 목차</title>
            <meta name="dc:identifier" content="rivo-daisy-loose-ncc"/>
            <meta name="dc:language" content="ko"/>
          </head>
          <body>
            <h1 id="n1">
              <a href="smil/part1.smil#nav-1">첫 장</a>
            </h1>
            <span id="n2">
              <a href="smil/part1.smil#nav-2">첫 페이지</a>
            </span>
            <div id="n3">
              <a href="smil/part1.smil#nav-3">보충 설명</a>
            </div>
          </body>
        </html>
        """
        let smil = """
        <?xml version="1.0" encoding="UTF-8"?>
        <smil>
          <body>
            <seq>
              <par id="par-1">
                <text src="../text/chapter.html#s1"/>
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
            <p id="s1">느슨한 NCC 본문입니다.</p>
          </body>
        </html>
        """
        return try ZIPFixture.make(
            entries: [
                ZIPFixtureEntry(
                    path: "Book/ncc.html",
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
