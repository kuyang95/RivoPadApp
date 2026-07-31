import Foundation
import XCTest

@testable import shortcuts_example

final class AppLocalizationTests:
    XCTestCase
{
    func testExplicitAppLanguageSelectsBundle()
    {
        XCTAssertEqual(
            AppLocalization.string(
                "설정",
                language: .english
            ),
            "Settings"
        )
        XCTAssertEqual(
            AppLocalization.string(
                "도움말",
                language: .japanese
            ),
            "ヘルプ"
        )
    }

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
        XCTAssertEqual(
            AppLocalization.string(
                "로컬 번역",
                bundle: english
            ),
            "On-Device Translation"
        )
        XCTAssertEqual(
            AppLocalization.string(
                "번역 결과",
                bundle: japanese
            ),
            "翻訳結果"
        )
        XCTAssertEqual(
            AppLocalization.string(
                "웹페이지 질문",
                bundle: english
            ),
            "Ask About a Webpage"
        )
        XCTAssertEqual(
            AppLocalization.string(
                "본문 읽기",
                bundle: japanese
            ),
            "本文を読む"
        )
        XCTAssertEqual(
            AppLocalization.string(
                "웹 검색",
                bundle: english
            ),
            "Web Search"
        )
        XCTAssertEqual(
            AppLocalization.string(
                "선택적 웹 검색",
                bundle: japanese
            ),
            "任意のWeb検索"
        )
        XCTAssertEqual(
            AppLocalization.string(
                "AI 대화",
                bundle: english
            ),
            "AI Conversations"
        )
        XCTAssertEqual(
            AppLocalization.string(
                "모든 대화를 삭제할까요?",
                bundle: japanese
            ),
            "すべての会話を削除しますか？"
        )
        XCTAssertEqual(
            AppLocalization.string(
                "답변 음성",
                bundle: english
            ),
            "Spoken Answer"
        )
        XCTAssertEqual(
            AppLocalization.string(
                "대화에 첨부",
                bundle: english
            ),
            "Attach to Conversation"
        )
        XCTAssertEqual(
            AppLocalization.string(
                "다음 행동",
                bundle: japanese
            ),
            "次の行動"
        )
        XCTAssertEqual(
            AppLocalization.string(
                "선택한 XLSX 문서를 읽을 수 없습니다.",
                bundle: english
            ),
            "The selected XLSX document could not be read."
        )
        XCTAssertEqual(
            AppLocalization.string(
                "가로 화면 한 줄 읽기",
                bundle: japanese
            ),
            "横画面の一行読み"
        )
        XCTAssertEqual(
            AppLocalization.string(
                "내 서재",
                bundle: english
            ),
            "My Library"
        )
        XCTAssertEqual(
            AppLocalization.string(
                "서재에서 삭제",
                bundle: japanese
            ),
            "ライブラリから削除"
        )
        XCTAssertEqual(
            AppLocalization.string(
                "책 재생 위치",
                bundle: english
            ),
            "Book Playback Position"
        )
        XCTAssertEqual(
            AppLocalization.string(
                "오늘 M4 로컬 AI",
                bundle: english
            ),
            "Today’s On-Device M4 AI"
        )
        XCTAssertEqual(
            AppLocalization.string(
                "일일 제한 없음",
                bundle: japanese
            ),
            "1日の上限なし"
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

        XCTAssertEqual(
            String(
                format:
                    AppLocalization.string(
                        "문서 문장 %lld/%lld",
                        bundle: english
                    ),
                2,
                9
            ),
            "Document sentence 2 of 9"
        )
        XCTAssertEqual(
            String(
                format:
                    AppLocalization.string(
                        "책 %lld권",
                        bundle: english
                    ),
                3
            ),
            "3 Books"
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
        let englishWebStatus = String(
            format: AppLocalization.string(
                "웹 서버가 오류 상태 %lld를 반환했습니다.",
                bundle: english
            ),
            404
        )
        let japaneseBodyCount = String(
            format: AppLocalization.string(
                "본문 %lld자",
                bundle: japanese
            ),
            1200
        )
        let englishSearchCount =
            String(
                format:
                    AppLocalization.string(
                        "검색 출처 %lld개",
                        bundle: english
                    ),
                5
            )
        let japaneseMessageCount =
            String(
                format:
                    AppLocalization.string(
                        "메시지 %lld개",
                        bundle: japanese
                    ),
                12
            )
        let englishAnswerPosition =
            String(
                format:
                    AppLocalization.string(
                        "답변 문장 %lld/%lld",
                        bundle: english
                    ),
                2,
                5
            )
        let japaneseAttachmentCount =
            String(
                format:
                    AppLocalization.string(
                        "텍스트 문맥 %lld개",
                        bundle: japanese
                    ),
                3
            )
        let englishSelectedSections =
            String(
                format:
                    AppLocalization.string(
                        "M4 문맥 한도에 맞춰 질문 관련 첨부 구간 %lld/%lld개를 사용합니다. 저장된 첨부는 그대로 유지됩니다.",
                        bundle: english
                    ),
                2,
                7
            )
        let englishLocalAIUsage =
            String(
                format:
                    AppLocalization.string(
                        "%ld자 생성 · 실패 %ld · 취소 %ld",
                        bundle: english
                    ),
                1_240,
                2,
                1
            )

        XCTAssertEqual(englishRate, "1.25×")
        XCTAssertEqual(
            japaneseDevice,
            "Rivo Threeに接続済み"
        )
        XCTAssertEqual(
            englishWebStatus,
            "The web server returned error status 404."
        )
        XCTAssertEqual(
            japaneseBodyCount,
            "本文1200文字"
        )
        XCTAssertEqual(
            englishSearchCount,
            "5 search sources"
        )
        XCTAssertEqual(
            japaneseMessageCount,
            "メッセージ12件"
        )
        XCTAssertEqual(
            englishAnswerPosition,
            "Answer sentence 2 of 5"
        )
        XCTAssertEqual(
            japaneseAttachmentCount,
            "テキストコンテキスト3件"
        )
        XCTAssertEqual(
            englishSelectedSections,
            "To fit the M4 context limit, 2 of 7 attachment sections relevant to the question are used. The saved attachment remains unchanged."
        )
        XCTAssertEqual(
            englishLocalAIUsage,
            "1240 chars generated · 2 failed · 1 canceled"
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
        XCTAssertTrue(
            infoPlistString(
                "NSPhotoLibraryAddUsageDescription",
                bundle: english
            )
            .contains("Photo")
        )
    }

    func testReaderDynamicStringsFollowInAppLanguage()
    {
        let defaults = UserDefaults.standard
        let previous =
            defaults.string(
                forKey:
                    AppLanguage
                    .preferenceKey
            )
        defer {
            if let previous {
                defaults.set(
                    previous,
                    forKey:
                        AppLanguage
                        .preferenceKey
                )
            } else {
                defaults.removeObject(
                    forKey:
                        AppLanguage
                        .preferenceKey
                )
            }
        }

        defaults.set(
            AppLanguage.english.rawValue,
            forKey:
                AppLanguage.preferenceKey
        )
        XCTAssertEqual(
            EPUBReadAloudNavigationUnit
                .paragraph.displayName,
            "Paragraph"
        )
        XCTAssertEqual(
            EPUBReadAloudPlaybackMode
                .textToSpeech.displayName,
            "On-Device Speech"
        )
        XCTAssertEqual(
            EPUBArchiveError
                .missingEntry(
                    "OPS/book.xhtml"
                )
                .localizedDescription,
            "A file inside the EPUB could not be found: OPS/book.xhtml"
        )

        defaults.set(
            AppLanguage.japanese.rawValue,
            forKey:
                AppLanguage.preferenceKey
        )
        XCTAssertEqual(
            EPUBReadAloudNavigationUnit
                .chapter.displayName,
            "章"
        )
        XCTAssertEqual(
            AccessiblePublicationParserError
                .rootDocumentMissing
                .localizedDescription,
            "DAISY図書のNCCまたはOPFファイルが見つかりません。"
        )
        XCTAssertEqual(
            EPUBLibraryError
                .libraryCapacityReached(
                    maximumBooks: 50
                )
                .localizedDescription,
            "ライブラリには最大50冊まで保存できます。"
        )
    }

    func testCameraAndScannerDynamicStringsFollowInAppLanguage()
    {
        let defaults = UserDefaults.standard
        let previous =
            defaults.string(
                forKey:
                    AppLanguage
                    .preferenceKey
            )
        defer {
            if let previous {
                defaults.set(
                    previous,
                    forKey:
                        AppLanguage
                        .preferenceKey
                )
            } else {
                defaults.removeObject(
                    forKey:
                        AppLanguage
                        .preferenceKey
                )
            }
        }

        defaults.set(
            AppLanguage.english.rawValue,
            forKey:
                AppLanguage.preferenceKey
        )
        XCTAssertEqual(
            MagnifierFilter
                .highContrast.title,
            "High Contrast"
        )
        XCTAssertEqual(
            MagnifierPhotoCaptureError
                .photoLibraryPermissionDenied
                .localizedDescription,
            "Photos add permission is unavailable. Save to Files instead."
        )
        XCTAssertEqual(
            DocumentScanSessionError
                .pageLimitReached(maximum: 20)
                .localizedDescription,
            "A document can contain up to 20 pages."
        )
        XCTAssertEqual(
            DocumentTextExtractor
                .ExtractError.noText
                .localizedDescription,
            "No text was found."
        )

        defaults.set(
            AppLanguage.japanese.rawValue,
            forKey:
                AppLanguage.preferenceKey
        )
        XCTAssertEqual(
            MagnifierFilter
                .grayscale.title,
            "グレースケール"
        )
        XCTAssertEqual(
            MagnifierPhotoCaptureError
                .encodingFailed
                .localizedDescription,
            "撮影した写真をJPEGに変換できません。"
        )
        XCTAssertEqual(
            DocumentScanSessionError
                .noPages
                .localizedDescription,
            "保存または開くスキャンページがありません。"
        )
        XCTAssertEqual(
            DocumentTextExtractor
                .ExtractError.cgImageMissing
                .localizedDescription,
            "画像をCGImageに変換できませんでした。"
        )
    }

    func testDocumentDynamicStringsFollowInAppLanguage()
    {
        let defaults = UserDefaults.standard
        let previous =
            defaults.string(
                forKey:
                    AppLanguage
                    .preferenceKey
            )
        defer {
            if let previous {
                defaults.set(
                    previous,
                    forKey:
                        AppLanguage
                        .preferenceKey
                )
            } else {
                defaults.removeObject(
                    forKey:
                        AppLanguage
                        .preferenceKey
                )
            }
        }

        defaults.set(
            AppLanguage.english.rawValue,
            forKey:
                AppLanguage.preferenceKey
        )
        XCTAssertEqual(
            LocalDocumentNavigationUnit
                .line.displayName,
            "Line"
        )
        XCTAssertEqual(
            LocalDocumentColorTheme
                .all[0].displayName,
            "White on Black"
        )
        XCTAssertEqual(
            LocalDocumentImportError
                .fileTooLarge(
                    maximumMegabytes: 250
                )
                .localizedDescription,
            "Files must be 250 MB or smaller."
        )
        XCTAssertEqual(
            AppLocalization.format(
                "문서 줄 위치 %lld / %lld",
                3,
                9
            ),
            "Document line 3 of 9"
        )

        defaults.set(
            AppLanguage.japanese.rawValue,
            forKey:
                AppLanguage.preferenceKey
        )
        XCTAssertEqual(
            LocalDocumentNavigationUnit
                .page.displayName,
            "ページ"
        )
        XCTAssertEqual(
            LocalDocumentColorTheme
                .all[1].displayName,
            "白地に黒"
        )
        XCTAssertEqual(
            LocalDocumentImportError
                .textDecodingFailed
                .localizedDescription,
            "対応していないテキストエンコーディングです。"
        )
        XCTAssertEqual(
            AppLocalization.format(
                "%lld페이지 · %lld자",
                2,
                1_234
            ),
            "2ページ・1,234文字"
        )
    }

    func testVisionLinkDynamicStringsFollowInAppLanguage()
    {
        let defaults = UserDefaults.standard
        let previous =
            defaults.string(
                forKey:
                    AppLanguage
                    .preferenceKey
            )
        defer {
            if let previous {
                defaults.set(
                    previous,
                    forKey:
                        AppLanguage
                        .preferenceKey
                )
            } else {
                defaults.removeObject(
                    forKey:
                        AppLanguage
                        .preferenceKey
                )
            }
        }

        defaults.set(
            AppLanguage.english.rawValue,
            forKey:
                AppLanguage.preferenceKey
        )
        XCTAssertEqual(
            VisionLinkConnectionState
                .reconnecting(attempt: 2)
                .title,
            "Reconnecting to saved device · Attempt 2"
        )
        XCTAssertEqual(
            VisionLinkRemoteFeature
                .imageAnalysis.title,
            "Describe Image"
        )
        XCTAssertEqual(
            VisionLinkProtocolError
                .invalidDescription
                .localizedDescription,
            "The VisionLink connection negotiation information is invalid."
        )
        XCTAssertEqual(
            VisionLinkServerError
                .http(
                    statusCode: 503,
                    responseBody: ""
                )
                .localizedDescription,
            "VisionLink server error 503"
        )

        defaults.set(
            AppLanguage.japanese.rawValue,
            forKey:
                AppLanguage.preferenceKey
        )
        XCTAssertEqual(
            VisionLinkConnectionState
                .mediaConnected.title,
            "映像に接続済み・最初のフレームを待機中"
        )
        XCTAssertEqual(
            VisionLinkRemoteFeature
                .liveReading.title,
            "リアルタイム読み上げ"
        )
        XCTAssertEqual(
            VisionLinkRemoteChatError
                .documentHasNoText
                .localizedDescription,
            "添付した文書からテキストを読み取れませんでした。"
        )
        XCTAssertEqual(
            AppLocalization.format(
                "파일 크기가 다릅니다: %lld/%lld bytes",
                8,
                10
            ),
            "ファイルサイズが一致しません：8/10 bytes"
        )
    }

    @MainActor
    func testRivoRemoteDynamicStringsFollowInAppLanguage()
    {
        let defaults = UserDefaults.standard
        let previous =
            defaults.string(
                forKey:
                    AppLanguage
                    .preferenceKey
            )
        defer {
            if let previous {
                defaults.set(
                    previous,
                    forKey:
                        AppLanguage
                        .preferenceKey
                )
            } else {
                defaults.removeObject(
                    forKey:
                        AppLanguage
                        .preferenceKey
                )
            }
        }

        defaults.set(
            AppLanguage.english.rawValue,
            forKey:
                AppLanguage.preferenceKey
        )
        XCTAssertEqual(
            RivoBluetoothState
                .connecting("Rivo Mini")
                .title,
            "Connecting to Rivo Mini"
        )
        XCTAssertEqual(
            RivoReconnectAttempt(
                number: 3,
                delay: 4
            ).title,
            "Reconnect automatically in 4 seconds. Attempt 3"
        )
        XCTAssertEqual(
            RivoDiscoverySource
                .advertisedName.title,
            "Advertised Name"
        )
        XCTAssertEqual(
            RivoRemoteInput
                .button(
                    button: .star,
                    action: .doubleTapped,
                    rawKey: 0
                )
                .summary,
            "Star Double Press"
        )
        XCTAssertEqual(
            RivoRestorationAction
                .resumeServices
                .diagnosticTitle,
            "Resume discovery of connected services."
        )
        XCTAssertEqual(
            RivoRemoteControlCenter()
                .items[2].title,
            "Camera Magnifier"
        )

        defaults.set(
            AppLanguage.japanese.rawValue,
            forKey:
                AppLanguage.preferenceKey
        )
        XCTAssertEqual(
            RivoBluetoothState
                .discovering("Rivo Three")
                .title,
            "Rivo Threeのサービスを確認中"
        )
        XCTAssertEqual(
            RivoDiscoveredDevice(
                id: UUID(),
                name: "Rivo Mini",
                type: .mini,
                discoverySource: .serviceUUID,
                signalStrength: -50
            ).signalDescription,
            "非常に強い"
        )
        XCTAssertEqual(
            RivoRemoteInput
                .sequence("a/")
                .summary,
            "シーケンス a/"
        )
        let controlCenter =
            RivoRemoteControlCenter()
        controlCenter.dismissCommandMode()
        XCTAssertEqual(
            controlCenter.feedback,
            "コマンドモードを閉じました"
        )
    }

    @MainActor
    func testAIChatAndVoiceStringsFollowInAppLanguage()
    {
        let defaults = UserDefaults.standard
        let previous =
            defaults.string(
                forKey:
                    AppLanguage
                    .preferenceKey
            )
        defer {
            if let previous {
                defaults.set(
                    previous,
                    forKey:
                        AppLanguage
                        .preferenceKey
                )
            } else {
                defaults.removeObject(
                    forKey:
                        AppLanguage
                        .preferenceKey
                )
            }
        }

        defaults.set(
            AppLanguage.english.rawValue,
            forKey:
                AppLanguage.preferenceKey
        )
        XCTAssertEqual(
            AppLanguage.current()
                .speechLanguageCode,
            "en-US"
        )
        XCTAssertEqual(
            AppLanguage.current()
                .localAIResponseLanguageName,
            "영어"
        )
        XCTAssertEqual(
            AppLocalization.format(
                "AI 상태: %@",
                "Ready"
            ),
            "AI Status: Ready"
        )
        XCTAssertEqual(
            STTManager.STTError
                .permissionDenied
                .localizedDescription,
            "Microphone and speech recognition permissions are required."
        )

        defaults.set(
            AppLanguage.japanese.rawValue,
            forKey:
                AppLanguage.preferenceKey
        )
        XCTAssertEqual(
            AppLanguage.current()
                .speechLanguageCode,
            "ja-JP"
        )
        XCTAssertEqual(
            AppLanguage.current()
                .localAIResponseLanguageName,
            "일본어"
        )
        XCTAssertEqual(
            AppLocalization.format(
                "\n\n(스트림 오류: %@)",
                "offline"
            ),
            "\n\n（ストリームエラー：offline）"
        )
        XCTAssertEqual(
            STTManager.STTError
                .onDeviceRecognitionUnavailable
                .localizedDescription,
            "このデバイスでは韓国語のオンデバイス音声認識を利用できません。"
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
