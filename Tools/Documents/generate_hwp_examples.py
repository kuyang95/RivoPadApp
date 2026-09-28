#!/usr/bin/env python3
"""Generate deterministic HWP 5 text and HWPX examples without an SDK."""

from __future__ import annotations

import argparse
import struct
import zipfile
from dataclasses import dataclass
from pathlib import Path
from xml.etree import ElementTree
from xml.sax.saxutils import escape


FREE = 0xFFFFFFFF
END = 0xFFFFFFFE
FAT_SECTOR = 0xFFFFFFFD
SECTOR_SIZE = 512
MINI_SECTOR_SIZE = 64
ZIP_TIMESTAMP = (2026, 8, 31, 0, 0, 0)


def u16(value: int) -> bytes:
    return struct.pack("<H", value)


def u32(value: int) -> bytes:
    return struct.pack("<I", value)


def set_u16(data: bytearray, offset: int, value: int) -> None:
    data[offset : offset + 2] = u16(value)


def set_u32(data: bytearray, offset: int, value: int) -> None:
    data[offset : offset + 4] = u32(value)


def set_u64(data: bytearray, offset: int, value: int) -> None:
    data[offset : offset + 8] = struct.pack("<Q", value)


@dataclass
class OLEEntry:
    name: str
    entry_type: int
    parent_path: str
    right_sibling: int = FREE
    child: int = FREE
    start_sector: int = END
    size: int = 0


def directory_entry(entry: OLEEntry) -> bytes:
    data = bytearray(128)
    encoded_name = (entry.name + "\0").encode("utf-16le")
    if len(encoded_name) > 64:
        raise ValueError(f"OLE name is too long: {entry.name}")
    data[: len(encoded_name)] = encoded_name
    set_u16(data, 64, len(encoded_name))
    data[66] = entry.entry_type
    data[67] = 1
    set_u32(data, 68, FREE)
    set_u32(data, 72, entry.right_sibling)
    set_u32(data, 76, entry.child)
    set_u32(data, 116, entry.start_sector)
    set_u64(data, 120, entry.size)
    return bytes(data)


def make_ole_file(streams: dict[str, bytes]) -> bytes:
    normalized = {path.replace("\\", "/"): data for path, data in streams.items()}
    storage_paths: set[str] = set()
    for path in normalized:
        parts = path.split("/")
        if not parts or any(not part or len(part.encode("utf-16le")) > 62 for part in parts):
            raise ValueError(f"Invalid OLE path: {path}")
        for end in range(1, len(parts)):
            storage_paths.add("/".join(parts[:end]))

    entries = [OLEEntry("Root Entry", 5, "")]
    index_for_path = {"": 0}
    for path in sorted(storage_paths):
        parent, _, name = path.rpartition("/")
        index_for_path[path] = len(entries)
        entries.append(OLEEntry(name, 1, parent))
    for path in sorted(normalized):
        parent, _, name = path.rpartition("/")
        index_for_path[path] = len(entries)
        entries.append(OLEEntry(name, 2, parent))
    if len(entries) > 4:
        raise ValueError("This compact generator supports one directory sector")

    children: dict[str, list[int]] = {}
    for index, entry in enumerate(entries[1:], start=1):
        children.setdefault(entry.parent_path, []).append(index)
    for parent, indices in children.items():
        ordered = sorted(indices, key=lambda index: entries[index].name.lower())
        entries[index_for_path[parent]].child = ordered[0]
        for current, following in zip(ordered, ordered[1:]):
            entries[current].right_sibling = following

    mini_stream = bytearray()
    mini_fat: list[int] = []
    regular_streams: list[tuple[int, bytes]] = []
    for path, payload in sorted(normalized.items()):
        entry_index = index_for_path[path]
        entries[entry_index].size = len(payload)
        if len(payload) < 4096:
            first = len(mini_fat)
            entries[entry_index].start_sector = END if not payload else first
            count = max(1, (len(payload) + MINI_SECTOR_SIZE - 1) // MINI_SECTOR_SIZE)
            for index in range(count):
                mini_fat.append(END if index == count - 1 else first + index + 1)
                chunk = payload[index * MINI_SECTOR_SIZE : (index + 1) * MINI_SECTOR_SIZE]
                mini_stream.extend(chunk)
                mini_stream.extend(b"\0" * (MINI_SECTOR_SIZE - len(chunk)))
        else:
            regular_streams.append((entry_index, payload))

    sectors: list[bytes] = [bytes(SECTOR_SIZE)]
    fat: list[int] = [END]

    def append_sector_chain(payload: bytes) -> int:
        first = len(sectors)
        count = max(1, (len(payload) + SECTOR_SIZE - 1) // SECTOR_SIZE)
        for index in range(count):
            chunk = payload[index * SECTOR_SIZE : (index + 1) * SECTOR_SIZE]
            sectors.append(chunk.ljust(SECTOR_SIZE, b"\0"))
            fat.append(END if index == count - 1 else first + index + 1)
        return first

    if mini_fat:
        mini_fat_data = b"".join(u32(value) for value in mini_fat)
        while len(mini_fat_data) % SECTOR_SIZE:
            mini_fat_data += u32(FREE)
        first_mini_fat_sector = append_sector_chain(mini_fat_data)
        mini_fat_sector_count = len(mini_fat_data) // SECTOR_SIZE
        entries[0].start_sector = append_sector_chain(bytes(mini_stream))
        entries[0].size = len(mini_stream)
    else:
        first_mini_fat_sector = END
        mini_fat_sector_count = 0

    for entry_index, payload in regular_streams:
        entries[entry_index].start_sector = append_sector_chain(payload)

    directory = b"".join(directory_entry(entry) for entry in entries)
    sectors[0] = directory.ljust(SECTOR_SIZE, b"\0")
    if len(sectors) + 1 > 128:
        raise ValueError("Fixture is too large for one FAT sector")

    fat_sector_id = len(sectors)
    fat.append(FAT_SECTOR)
    fat_sector = b"".join(u32(value) for value in fat).ljust(SECTOR_SIZE, b"\xff")
    sectors.append(fat_sector)

    header = bytearray(SECTOR_SIZE)
    header[:8] = bytes.fromhex("D0CF11E0A1B11AE1")
    set_u16(header, 24, 0x003E)
    set_u16(header, 26, 3)
    set_u16(header, 28, 0xFFFE)
    set_u16(header, 30, 9)
    set_u16(header, 32, 6)
    set_u32(header, 40, 0)
    set_u32(header, 44, 1)
    set_u32(header, 48, 0)
    set_u32(header, 56, 4096)
    set_u32(header, 60, first_mini_fat_sector)
    set_u32(header, 64, mini_fat_sector_count)
    set_u32(header, 68, END)
    set_u32(header, 72, 0)
    for index in range(109):
        set_u32(header, 76 + index * 4, fat_sector_id if index == 0 else FREE)
    return bytes(header) + b"".join(sectors)


def hwp_paragraph_record(text: str) -> bytes:
    payload = text.encode("utf-16le") + u16(13)
    if len(payload) >= 0xFFF:
        raise ValueError("HWP paragraph is too large")
    record_header = (len(payload) << 20) | (1 << 10) | 0x43
    return u32(record_header) + payload


def make_hwp() -> bytes:
    paragraphs = [
        "RivoPad 접근성 기능 점검 회의록",
        "일시: 2026년 8월 31일 오전 10시",
        "참석: 제품 기획, iOS 개발, 접근성 검수 담당",
        "안건 1. 문서 탐색 시 VoiceOver 초점 이동 규칙 확인",
        "안건 2. 외부 키보드와 리모컨의 문단 이동 동작 점검",
        "결정 사항: 읽기 화면의 주요 버튼에는 동작 결과를 설명하는 힌트를 제공한다.",
        "후속 작업: 긴 문서 3종으로 탐색 속도와 음성 안내를 다시 측정한다.",
        "다음 회의: 2026년 9월 7일",
    ]
    file_header = bytearray(256)
    file_header[:17] = b"HWP Document File"
    set_u32(file_header, 32, 0x05000300)
    set_u32(file_header, 36, 0)
    set_u32(file_header, 44, 0)
    section = b"".join(hwp_paragraph_record(paragraph) for paragraph in paragraphs)
    return make_ole_file(
        {
            "FileHeader": bytes(file_header),
            "BodyText/Section0": section,
        }
    )


def hwpx_paragraph(identifier: int, text: str) -> str:
    return (
        f'<hp:p id="{identifier}" paraPrIDRef="0" styleIDRef="0" '
        'pageBreak="0" columnBreak="0" merged="0">'
        f'<hp:run charPrIDRef="0"><hp:t xml:space="preserve">{escape(text)}</hp:t></hp:run>'
        "</hp:p>"
    )


def make_hwpx(output: Path) -> None:
    paragraphs = [
        "제주 무장애 여행 준비 체크리스트",
        "여행 기간: 2026년 10월 12일 ~ 10월 15일",
        "이 문서는 이동·숙박·관광 준비 항목을 출발 전에 확인하기 위한 예시입니다.",
        "이동 준비",
        "휠체어 탑승 가능 차량을 예약하고 기사 연락처를 저장합니다.",
        "숙박 준비",
        "객실 출입문 폭, 침대 높이, 욕실 손잡이 설치 여부를 숙소에 확인합니다.",
        "관광 준비",
        "우천 시 이용할 실내 코스와 휴관일을 함께 확인합니다.",
        "긴급 연락",
        "보조기기 수리점과 가까운 의료기관 주소를 오프라인 메모에 저장합니다.",
    ]
    body = "".join(hwpx_paragraph(index + 1, text) for index, text in enumerate(paragraphs))
    section_xml = f'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<hs:sec xmlns:hs="http://www.hancom.co.kr/hwpml/2011/section" xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph">{body}</hs:sec>'''
    header_xml = '''<?xml version="1.0" encoding="UTF-8"?>
<hh:head xmlns:hh="http://www.hancom.co.kr/hwpml/2011/head" version="1.2" secCnt="1">
  <hh:beginNum page="1" footnote="1" endnote="1" pic="1" tbl="1" equation="1"/>
  <hh:refList>
    <hh:fontfaces itemCnt="1"><hh:fontface lang="HANGUL" fontCnt="1"><hh:font id="0" face="Apple SD Gothic Neo" type="TTF" isEmbedded="0"/></hh:fontface></hh:fontfaces>
    <hh:borderFills itemCnt="0"/>
    <hh:charProperties itemCnt="1"><hh:charPr id="0" height="1000" textColor="#000000" shadeColor="#FFFFFF" useFontSpace="0" useKerning="0" symMark="NONE" borderFillIDRef="0"/></hh:charProperties>
    <hh:tabProperties itemCnt="1"><hh:tabPr id="0" autoTabLeft="0" autoTabRight="0"/></hh:tabProperties>
    <hh:numberings itemCnt="0"/><hh:bullets itemCnt="0"/>
    <hh:paraProperties itemCnt="1"><hh:paraPr id="0" tabPrIDRef="0" condense="0" fontLineHeight="0" snapToGrid="1" suppressLineNumbers="0" checked="0"><hh:align horizontal="LEFT" vertical="BASELINE"/></hh:paraPr></hh:paraProperties>
    <hh:styles itemCnt="1"><hh:style id="0" type="PARA" name="바탕글" engName="Normal" paraPrIDRef="0" charPrIDRef="0" nextStyleIDRef="0" langID="1042" lockForm="0"/></hh:styles>
  </hh:refList>
</hh:head>'''
    content_hpf = '''<?xml version="1.0" encoding="UTF-8"?>
<opf:package xmlns:opf="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/" version="1.0">
  <opf:metadata><dc:title>제주 무장애 여행 준비 체크리스트</dc:title><dc:creator>RivoPad</dc:creator><dc:language>ko-KR</dc:language></opf:metadata>
  <opf:manifest><opf:item id="header" href="header.xml" media-type="application/xml"/><opf:item id="section0" href="section0.xml" media-type="application/xml"/></opf:manifest>
  <opf:spine><opf:itemref idref="section0"/></opf:spine>
</opf:package>'''
    entries = [
        ("mimetype", b"application/hwp+zip", zipfile.ZIP_STORED),
        ("version.xml", b'<?xml version="1.0" encoding="UTF-8"?><hv:HCFVersion xmlns:hv="http://www.hancom.co.kr/hwpml/2011/version" targetApplication="WORDPROCESSOR" major="5" minor="1" micro="0" buildNumber="0" os="IOS" xmlVersion="1.2" application="RivoPad"/>', zipfile.ZIP_DEFLATED),
        ("Contents/header.xml", header_xml.encode(), zipfile.ZIP_DEFLATED),
        ("Contents/section0.xml", section_xml.encode(), zipfile.ZIP_DEFLATED),
        ("Contents/content.hpf", content_hpf.encode(), zipfile.ZIP_DEFLATED),
        ("Preview/PrvText.txt", "\n".join(paragraphs).encode(), zipfile.ZIP_DEFLATED),
        ("META-INF/container.xml", b'<?xml version="1.0" encoding="UTF-8"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="Contents/content.hpf" media-type="application/hwpml-package+xml"/></rootfiles></container>', zipfile.ZIP_DEFLATED),
    ]
    with zipfile.ZipFile(output, "w", allowZip64=False) as archive:
        for name, payload, compression in entries:
            info = zipfile.ZipInfo(name, date_time=ZIP_TIMESTAMP)
            info.compress_type = compression
            info.create_system = 3
            info.external_attr = (0o100644 & 0xFFFF) << 16
            archive.writestr(info, payload)


def validate_hwp(data: bytes) -> None:
    if data[:8] != bytes.fromhex("D0CF11E0A1B11AE1"):
        raise ValueError("HWP output is not an OLE compound file")
    if len(data) % SECTOR_SIZE:
        raise ValueError("HWP output is not sector aligned")
    if b"HWP Document File" not in data:
        raise ValueError("HWP FileHeader signature is missing")
    expected_title = "RivoPad 접근성 기능 점검 회의록".encode("utf-16le")
    if expected_title not in data:
        raise ValueError("HWP example body text is missing")


def validate_hwpx(path: Path) -> None:
    with zipfile.ZipFile(path) as archive:
        infos = archive.infolist()
        if not infos or infos[0].filename != "mimetype":
            raise ValueError("HWPX mimetype must be the first ZIP entry")
        if infos[0].compress_type != zipfile.ZIP_STORED:
            raise ValueError("HWPX mimetype must be stored without compression")
        if archive.read("mimetype") != b"application/hwp+zip":
            raise ValueError("HWPX mimetype is invalid")
        for name in (
            "version.xml",
            "Contents/header.xml",
            "Contents/section0.xml",
            "Contents/content.hpf",
            "META-INF/container.xml",
        ):
            ElementTree.fromstring(archive.read(name))
        preview = archive.read("Preview/PrvText.txt").decode("utf-8")
        if "제주 무장애 여행 준비 체크리스트" not in preview:
            raise ValueError("HWPX example body text is missing")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("outputs/hwp_document_examples_20260831"),
    )
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    hwp_path = args.output_dir / "RivoPad-접근성-회의록.hwp"
    hwpx_path = args.output_dir / "제주-무장애-여행-체크리스트.hwpx"
    hwp_data = make_hwp()
    hwp_path.write_bytes(hwp_data)
    make_hwpx(hwpx_path)
    validate_hwp(hwp_data)
    validate_hwpx(hwpx_path)
    print(hwp_path.resolve())
    print(hwpx_path.resolve())


if __name__ == "__main__":
    main()
