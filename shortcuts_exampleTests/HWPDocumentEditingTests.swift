import Foundation
import XCTest
import ZIPFoundation

@testable import shortcuts_example

final class HWPDocumentEditingTests: XCTestCase {
    func testBlankHangulDocumentCanBeCreatedEditedAndReloaded() throws {
        let source = try LegacyHWPXConverter.convert(text: "")
        let package = try HWPXDocumentPackage.load(from: source)

        XCTAssertEqual(package.blocks.count, 1)
        XCTAssertEqual(package.blocks[0].text, "")
        XCTAssertTrue(package.blocks[0].isEditable)

        var edited = package.blocks
        edited[0].text = "새 한글 문서"
        let saved = try package.serializedData(applying: edited)
        let reloaded = try HWPXDocumentPackage.load(from: saved)

        XCTAssertEqual(reloaded.blocks[0].text, "새 한글 문서")
    }

    func testLoadsSpineOrderControlsAndTableLocation() throws {
        let package = try HWPXDocumentPackage.load(from: makeHWPXData())

        XCTAssertEqual(
            package.sectionPaths,
            ["Contents/section1.xml", "Contents/section0.xml"]
        )
        XCTAssertEqual(package.blocks.count, 3)
        XCTAssertEqual(
            package.blocks[0].text,
            "먼저 읽는 구역\t탭\n줄바꿈-연결"
        )
        XCTAssertEqual(package.blocks[1].text, "나중 구역")
        XCTAssertEqual(package.blocks[2].text, "표의 첫 셀")
        XCTAssertEqual(package.blocks[2].tableLocation?.table, 0)
        XCTAssertEqual(package.blocks[2].tableLocation?.row, 0)
        XCTAssertEqual(package.blocks[2].tableLocation?.column, 0)
        XCTAssertTrue(package.blocks.allSatisfy(\.isEditable))
    }

    func testPatchesOnlyEditedParagraphAndPreservesUnknownEntries() throws {
        let package = try HWPXDocumentPackage.load(from: makeHWPXData())
        var edited = package.blocks
        edited[0].text = "수정\t값\n다음 & <확인>"
        edited[2].text = "표 셀 수정"

        let output = try package.serializedData(applying: edited)
        let reloaded = try HWPXDocumentPackage.load(from: output)

        XCTAssertEqual(reloaded.blocks.map(\.text), edited.map(\.text))
        XCTAssertEqual(
            try archiveData(at: "BinData/keep.bin", in: output),
            Data([0x00, 0x7F, 0xFF])
        )
        XCTAssertEqual(
            String(
                data: try archiveData(
                    at: "Contents/header.xml",
                    in: output
                ),
                encoding: .utf8
            ),
            "<head keep=\"yes\"/>"
        )
    }

    func testRejectsEditingParagraphWithComplexObject() throws {
        let data = try makeZIPData(entries: [
            ("mimetype", Data("application/hwp+zip".utf8)),
            ("Contents/content.hpf", Data("""
                <package><manifest><item id="s0" href="section0.xml"/></manifest><spine><itemref idref="s0"/></spine></package>
                """.utf8)),
            ("Contents/section0.xml", Data("""
                <hs:sec xmlns:hs="urn:section" xmlns:hp="urn:paragraph"><hp:p><hp:run><hp:t>그림 문단</hp:t><hp:pic/></hp:run></hp:p></hs:sec>
                """.utf8)),
        ])
        let package = try HWPXDocumentPackage.load(from: data)
        XCTAssertFalse(try XCTUnwrap(package.blocks.first).isEditable)

        var edited = package.blocks
        edited[0].text = "바꾸기"
        XCTAssertThrowsError(try package.serializedData(applying: edited)) {
            XCTAssertEqual(
                $0 as? HWPDocumentEditingError,
                .unsupportedEdit
            )
        }
    }

    func testLegacyConverterCreatesEditableRoundTripHWPX() throws {
        let package = try HWPXDocumentPackage.load(
            from: LegacyHWPXConverter.convert(
                text: "첫 문단\n\n둘째 & <문단>"
            )
        )

        XCTAssertEqual(
            package.blocks.map(\.text),
            ["첫 문단", "", "둘째 & <문단>"]
        )
        XCTAssertTrue(package.blocks.allSatisfy(\.isEditable))
        XCTAssertEqual(
            try HWPXTextExtractor.extract(from: package.sourceData),
            "첫 문단\n둘째 & <문단>"
        )
    }

    private func makeHWPXData() throws -> Data {
        try makeZIPData(entries: [
            ("mimetype", Data("application/hwp+zip".utf8)),
            ("Contents/header.xml", Data("<head keep=\"yes\"/>".utf8)),
            ("BinData/keep.bin", Data([0x00, 0x7F, 0xFF])),
            ("Contents/content.hpf", Data("""
                <?xml version="1.0" encoding="UTF-8"?>
                <opf:package xmlns:opf="http://www.idpf.org/2007/opf/">
                  <opf:manifest>
                    <opf:item id="section0" href="Contents/section0.xml" media-type="application/xml"/>
                    <opf:item id="section1" href="section1.xml" media-type="application/xml"/>
                  </opf:manifest>
                  <opf:spine>
                    <opf:itemref idref="section1"/>
                    <opf:itemref idref="section0"/>
                  </opf:spine>
                </opf:package>
                """.utf8)),
            ("Contents/section0.xml", Data("""
                <?xml version="1.0" encoding="UTF-8"?>
                <hs:sec xmlns:hs="http://www.hancom.co.kr/hwpml/2011/section" xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph">
                  <hp:p><hp:run><hp:t>나중 구역</hp:t></hp:run></hp:p>
                  <hp:tbl><hp:tr><hp:tc><hp:subList><hp:p><hp:run><hp:t>표의 첫 셀</hp:t></hp:run></hp:p></hp:subList></hp:tc></hp:tr></hp:tbl>
                </hs:sec>
                """.utf8)),
            ("Contents/section1.xml", Data("""
                <?xml version="1.0" encoding="UTF-8"?>
                <hs:sec xmlns:hs="http://www.owpml.org/owpml/2021/section" xmlns:hp="http://www.owpml.org/owpml/2021/paragraph">
                  <hp:p><hp:run><hp:t>먼저 읽는 구역<hp:tab/>탭<hp:lineBreak/>줄바꿈<hp:hypen/>연결</hp:t></hp:run></hp:p>
                </hs:sec>
                """.utf8)),
        ])
    }

    private func makeZIPData(entries: [(String, Data)]) throws -> Data {
        let archive = try Archive(accessMode: .create)
        for (path, data) in entries {
            try archive.addEntry(
                with: path,
                type: .file,
                uncompressedSize: Int64(data.count),
                compressionMethod: path == "mimetype" ? .none : .deflate
            ) { position, size in
                let lower = Int(position)
                let upper = min(data.count, lower + size)
                guard lower < upper else { return Data() }
                return data.subdata(in: lower..<upper)
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
