import RivoDocumentEngine
import Foundation
import XCTest
import ZIPFoundation

@testable import shortcuts_example

final class WordDocumentEditingTests: XCTestCase {
    func testBlankWordDocumentCanBeCreatedEditedAndReloaded() throws {
        let source = try LegacyDOCXConverter.convert(text: "")
        let package = try WordDocumentPackage.load(from: source)

        XCTAssertEqual(package.blocks.count, 1)
        XCTAssertEqual(package.blocks[0].text, "")
        XCTAssertTrue(package.blocks[0].isEditable)

        var edited = package.blocks
        edited[0].text = "새 Word 문서"
        let saved = try package.serializedData(applying: edited)
        let reloaded = try WordDocumentPackage.load(from: saved)

        XCTAssertEqual(reloaded.blocks[0].text, "새 Word 문서")
    }

    func testLoadsSemanticBlocksAndPreservesPackageWhenSaving() throws {
        let imageBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02])
        let source = try makeDOCXData(
            documentXML: sampleDocumentXML,
            additionalEntries: ["word/media/image1.png": imageBytes]
        )

        let package = try WordDocumentPackage.load(from: source)

        XCTAssertEqual(package.blocks.count, 3)
        XCTAssertEqual(package.blocks[0].kind, .title)
        XCTAssertEqual(package.blocks[1].kind, .listItem)
        XCTAssertEqual(package.blocks[2].kind, .tableCell)
        XCTAssertEqual(package.blocks[2].tableLocation?.row, 0)
        XCTAssertEqual(package.blocks[2].tableLocation?.column, 0)

        var edited = package.blocks
        edited[1].text = "수정 & 검증\n둘째 줄\t탭"
        edited[1].styleID = "Heading2"
        edited[2].text = "새 표 셀"

        let saved = try package.serializedData(applying: edited)
        let reloaded = try WordDocumentPackage.load(from: saved)

        XCTAssertEqual(reloaded.blocks[0].text, "접근성 업무 계획")
        XCTAssertEqual(reloaded.blocks[1].text, "수정 & 검증\n둘째 줄\t탭")
        XCTAssertEqual(reloaded.blocks[1].styleID, "Heading2")
        XCTAssertEqual(reloaded.blocks[2].text, "새 표 셀")
        XCTAssertEqual(
            try archiveData(at: "word/media/image1.png", in: saved),
            imageBytes
        )
    }

    func testRejectsEditingFieldGeneratedParagraph() throws {
        let source = try makeDOCXData(
            documentXML: """
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
                <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
                  <w:body><w:p><w:r><w:fldChar w:fldCharType="begin"/><w:instrText>PAGE</w:instrText><w:t>1</w:t></w:r></w:p></w:body>
                </w:document>
                """
        )
        let package = try WordDocumentPackage.load(from: source)
        XCTAssertFalse(try XCTUnwrap(package.blocks.first).isEditable)

        var edited = package.blocks
        edited[0].text = "2"

        XCTAssertThrowsError(
            try package.serializedData(applying: edited)
        ) { error in
            XCTAssertEqual(
                error as? WordDocumentEditingError,
                .unsupportedEdit
            )
        }
    }

    func testLegacyTextConvertsToEditableDOCX() throws {
        let converted = try LegacyDOCXConverter.convert(
            text: "레거시 DOC 제목\n첫 문단\n\n마지막 문단"
        )
        let package = try WordDocumentPackage.load(from: converted)

        XCTAssertEqual(
            package.blocks.map(\.text),
            ["레거시 DOC 제목", "첫 문단", "", "마지막 문단"]
        )
        XCTAssertTrue(package.blocks.allSatisfy(\.isEditable))

        var edited = package.blocks
        edited[2].styleID = "Heading3"
        let saved = try package.serializedData(applying: edited)
        let reloaded = try WordDocumentPackage.load(from: saved)
        XCTAssertEqual(reloaded.blocks[2].styleID, "Heading3")
    }

    func testAIPlanRequiresPreviewableValidTargets() throws {
        let package = try WordDocumentPackage.load(
            from: makeDOCXData(documentXML: sampleDocumentXML)
        )
        let snapshot = WordAISnapshotBuilder.make(
            documentName: "sample.docx",
            blocks: package.blocks,
            selectedBlockID: package.blocks[1].id
        )
        let operation = WordAICommandPlan.Operation(
            kind: .replaceText,
            blockID: package.blocks[1].id,
            newText: "명확하고 간결한 문장",
            styleID: nil
        )
        let plan = WordAICommandPlan(
            intent: .edit,
            assistantMessage: "한 문단을 다듬었습니다.",
            operations: [operation]
        )

        let validated = try XCTUnwrap(
            WordAICommandValidator.validate(
                plan,
                snapshot: snapshot,
                userRequest: "선택한 문단을 간결하게 다듬어줘"
            )
        )

        XCTAssertEqual(validated.changeCount, 1)
        XCTAssertEqual(validated.sourceRevision, snapshot.revision)
        XCTAssertEqual(validated.previewLines.count, 1)
    }

    func testAIPlanCannotSilentlyClearParagraph() throws {
        let package = try WordDocumentPackage.load(
            from: makeDOCXData(documentXML: sampleDocumentXML)
        )
        let snapshot = WordAISnapshotBuilder.make(
            documentName: "sample.docx",
            blocks: package.blocks,
            selectedBlockID: nil
        )
        let plan = WordAICommandPlan(
            intent: .edit,
            assistantMessage: "수정안을 준비했습니다.",
            operations: [
                WordAICommandPlan.Operation(
                    kind: .replaceText,
                    blockID: package.blocks[0].id,
                    newText: "",
                    styleID: nil
                )
            ]
        )

        XCTAssertThrowsError(
            try WordAICommandValidator.validate(
                plan,
                snapshot: snapshot,
                userRequest: "제목을 다듬어줘"
            )
        ) { error in
            XCTAssertEqual(
                error as? WordAICommandValidationError,
                .destructiveChange
            )
        }
    }

    func testStructuredAIResponseDecodesAndValidatesDateChange() throws {
        let dateXML = sampleDocumentXML.replacingOccurrences(
            of: "핵심 요구사항 정리",
            with: "작성일: 2026-08-25"
        )
        let package = try WordDocumentPackage.load(
            from: makeDOCXData(documentXML: dateXML)
        )
        let snapshot = WordAISnapshotBuilder.make(
            documentName: "sample.docx",
            blocks: package.blocks,
            selectedBlockID: nil
        )
        let response = """
        ```json
        {
          "intent": "edit",
          "assistantMessage": "작성일을 하루 뒤로 변경하는 수정안입니다.",
          "operations": [
            {
              "kind": "replaceText",
              "blockID": "word-paragraph-1",
              "newText": "작성일: 2026-08-26",
              "styleID": null
            }
          ]
        }
        ```
        """

        let decoded = try WordAICommandService.decodeResponse(response)
        let validated = try XCTUnwrap(
            WordAICommandValidator.validate(
                decoded,
                snapshot: snapshot,
                userRequest: "작성일을 하루 뒤로 해줘"
            )
        )

        XCTAssertEqual(validated.changeCount, 1)
        XCTAssertEqual(
            validated.operations.first?.newText,
            "작성일: 2026-08-26"
        )
    }

    func testStructuredAIResponseRejectsWrongFieldNames() throws {
        let response = """
        {
          "intent": "edit",
          "assistantMessage": "수정안입니다.",
          "operations": [
            {
              "kind": "replaceText",
              "blockId": "word-paragraph-1",
              "replacement": "작성일: 2026-08-26"
            }
          ]
        }
        """

        XCTAssertThrowsError(
            try WordAICommandService.decodeResponse(response)
        )
    }

    func testLargeWordCatalogFindsCandidateNearDocumentEnd() throws {
        var blocks = (0..<680).map {
            makeWordBlock(index: $0, text: "일반 본문 \($0)")
        }
        blocks[660].text = "문서 관리 정보"
        blocks[660].styleID = "Heading1"
        blocks[674].text = "작성일: 2026-08-25"

        let catalog = WordAIRetrievalCatalogBuilder.make(
            documentName: "large.docx",
            blocks: blocks,
            userRequest: "작성일을 하루 뒤로 바꿔줘"
        )

        XCTAssertTrue(catalog.requiresRouting)
        XCTAssertEqual(catalog.documentBlockCount, 680)
        XCTAssertTrue(catalog.queryTerms.contains("작성일"))
        XCTAssertEqual(catalog.candidates.first?.blockID, "word-paragraph-674")
        XCTAssertTrue(
            catalog.sections.contains {
                $0.id == catalog.candidates.first?.sectionID
                    && $0.headingPath.contains("문서 관리 정보")
            }
        )
    }

    func testSmallWordCatalogKeepsSingleCallPath() throws {
        let blocks = (0..<12).map {
            makeWordBlock(index: $0, text: "짧은 문서 \($0)")
        }

        let catalog = WordAIRetrievalCatalogBuilder.make(
            documentName: "small.docx",
            blocks: blocks,
            userRequest: "내용을 요약해줘"
        )

        XCTAssertFalse(catalog.requiresRouting)
        XCTAssertFalse(catalog.catalogWasTruncated)
    }

    func testRetrievedSnapshotContainsTargetAndNeighborsNotDocumentPrefix() throws {
        var blocks = (0..<680).map {
            makeWordBlock(index: $0, text: "일반 본문 \($0)")
        }
        blocks[660].text = "문서 관리 정보"
        blocks[660].styleID = "Heading1"
        blocks[674].text = "작성일: 2026-08-25"
        let catalog = WordAIRetrievalCatalogBuilder.make(
            documentName: "large.docx",
            blocks: blocks,
            userRequest: "작성일을 하루 뒤로 바꿔줘"
        )
        let candidate = try XCTUnwrap(catalog.candidates.first)
        let plan = WordAIRetrievalPlan(
            intent: .retrieve,
            assistantMessage: "관련 구역을 찾았습니다.",
            sectionIDs: [],
            blockIDs: [candidate.blockID]
        )

        let snapshot = try XCTUnwrap(
            WordAISnapshotBuilder.makeRetrieved(
                documentName: "large.docx",
                blocks: blocks,
                selectedBlockID: nil,
                catalog: catalog,
                retrievalPlan: plan
            )
        )
        let includedIDs = Set(snapshot.blocks.map(\.id))

        XCTAssertTrue(includedIDs.contains("word-paragraph-674"))
        XCTAssertTrue(includedIDs.contains("word-paragraph-672"))
        XCTAssertTrue(includedIDs.contains("word-paragraph-676"))
        XCTAssertTrue(includedIDs.contains("word-paragraph-660"))
        XCTAssertFalse(includedIDs.contains("word-paragraph-0"))
        XCTAssertTrue(snapshot.contextWasTruncated)
        XCTAssertEqual(
            snapshot.revision,
            WordAISnapshotBuilder.revision(blocks: blocks)
        )
        XCTAssertEqual(snapshot.retrieval?.blockIDs, [candidate.blockID])
    }

    func testRetrievalResponseDecodesAndRejectsUnknownIDs() throws {
        let blocks = (0..<680).map {
            makeWordBlock(
                index: $0,
                text: $0 == 670 ? "작성일: 2026-08-25" : "본문 \($0)"
            )
        }
        let catalog = WordAIRetrievalCatalogBuilder.make(
            documentName: "large.docx",
            blocks: blocks,
            userRequest: "작성일을 바꿔줘"
        )
        let candidate = try XCTUnwrap(catalog.candidates.first)
        let response = """
        {
          "intent": "retrieve",
          "assistantMessage": "관련 구역을 찾았습니다.",
          "sectionIDs": [],
          "blockIDs": ["\(candidate.blockID)"]
        }
        """

        let validated = try WordAIAssistant.retrievalPlan(fromResponse: response, catalog: catalog)
        XCTAssertEqual(validated.blockIDs, [candidate.blockID])

        let invalid = WordAIRetrievalPlan(
            intent: .retrieve,
            assistantMessage: "관련 구역을 찾았습니다.",
            sectionIDs: [],
            blockIDs: ["invented-block-id"]
        )
        XCTAssertThrowsError(
            try WordAIAssistant.validated(
                invalid,
                catalog: catalog
            )
        )
    }

    func testRetrievalClarifyCannotCarryTargets() throws {
        let blocks = (0..<680).map {
            makeWordBlock(
                index: $0,
                text: $0 == 670 ? "작성일: 2026-08-25" : "본문 \($0)"
            )
        }
        let catalog = WordAIRetrievalCatalogBuilder.make(
            documentName: "large.docx",
            blocks: blocks,
            userRequest: "작성일을 바꿔줘"
        )
        let candidate = try XCTUnwrap(catalog.candidates.first)
        let validClarify = WordAIRetrievalPlan(
            intent: .clarify,
            assistantMessage: "어느 작성일을 변경할까요?",
            sectionIDs: [],
            blockIDs: []
        )
        XCTAssertNoThrow(
            try WordAIAssistant.validated(
                validClarify,
                catalog: catalog
            )
        )

        let invalidClarify = WordAIRetrievalPlan(
            intent: .clarify,
            assistantMessage: "어느 작성일을 변경할까요?",
            sectionIDs: [],
            blockIDs: [candidate.blockID]
        )
        XCTAssertThrowsError(
            try WordAIAssistant.validated(
                invalidClarify,
                catalog: catalog
            )
        )
    }

    func testDateEditPreservesExistingRunFormatting() throws {
        let source = try makeDOCXData(
            documentXML: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:body>
                <w:p>
                  <w:r><w:rPr><w:b/></w:rPr><w:t xml:space="preserve">작성일: </w:t></w:r>
                  <w:r><w:t>2026-08-25</w:t></w:r>
                </w:p>
              </w:body>
            </w:document>
            """
        )
        let package = try WordDocumentPackage.load(from: source)
        var edited = package.blocks
        edited[0].text = "작성일: 2026-08-26"

        let saved = try package.serializedData(applying: edited)
        let savedXML = try XCTUnwrap(
            String(
                data: archiveData(at: "word/document.xml", in: saved),
                encoding: .utf8
            )
        )

        XCTAssertTrue(
            savedXML.contains(
                "<w:r><w:rPr><w:b/></w:rPr><w:t xml:space=\"preserve\">작성일: </w:t></w:r>"
            )
        )
        XCTAssertTrue(
            savedXML.contains("<w:r><w:t>2026-08-26</w:t></w:r>")
        )
    }

    @MainActor
    func testViewModelBuildsOriginalPreviewFromUnsavedEdits() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "WordOriginalPreviewTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("sample.docx")
        try makeDOCXData(documentXML: sampleDocumentXML).write(to: sourceURL)
        let viewModel = WordDocumentViewModel(fileURL: sourceURL)
        await viewModel.load()
        let target = try XCTUnwrap(viewModel.blocks.dropFirst().first)
        viewModel.selectBlock(target.id)
        viewModel.editorText = "저장 전 원본 보기 반영"
        viewModel.commitEditorChange()

        await viewModel.prepareOriginalPreview()

        let previewURL = try XCTUnwrap(viewModel.originalPreviewURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: previewURL.path))
        let previewPackage = try WordDocumentPackage.load(
            from: Data(contentsOf: previewURL)
        )
        XCTAssertEqual(previewPackage.blocks[1].text, "저장 전 원본 보기 반영")
    }

    private var sampleDocumentXML: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p><w:pPr><w:pStyle w:val="Title"/></w:pPr><w:r><w:t>접근성 업무 계획</w:t></w:r></w:p>
            <w:p><w:pPr><w:numPr><w:numId w:val="1"/></w:numPr></w:pPr><w:r><w:t>핵심 요구사항 정리</w:t></w:r></w:p>
            <w:tbl><w:tr><w:tc><w:p><w:r><w:t>기존 표 셀</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
          </w:body>
        </w:document>
        """
    }

    private func makeWordBlock(
        index: Int,
        text: String
    ) -> WordDocumentBlock {
        WordDocumentBlock(
            id: "word-paragraph-\(index)",
            paragraphIndex: index,
            text: text,
            styleID: "Normal",
            isNumbered: false,
            tableLocation: nil,
            isEditable: true
        )
    }

    private func makeDOCXData(
        documentXML: String,
        additionalEntries: [String: Data] = [:]
    ) throws -> Data {
        var entries = additionalEntries
        entries["[Content_Types].xml"] = Data(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
              <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
            </Types>
            """.utf8
        )
        entries["word/document.xml"] = Data(documentXML.utf8)

        let archive = try Archive(accessMode: .create)
        for (path, entryData) in entries.sorted(by: { $0.key < $1.key }) {
            try archive.addEntry(
                with: path,
                type: .file,
                uncompressedSize: Int64(entryData.count),
                compressionMethod: .deflate
            ) { position, size in
                let lower = Int(position)
                let upper = min(entryData.count, lower + size)
                guard lower < upper else { return Data() }
                return entryData.subdata(in: lower..<upper)
            }
        }
        return try XCTUnwrap(archive.data)
    }

    private func archiveData(at path: String, in data: Data) throws -> Data {
        let archive = try Archive(data: data, accessMode: .read)
        let entry = try XCTUnwrap(archive[path])
        var result = Data()
        _ = try archive.extract(entry) { result.append($0) }
        return result
    }
}
