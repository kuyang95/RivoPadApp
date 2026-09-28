#!/usr/bin/env python3
"""Rebuild the in-app review PDFs from the latest complete M4 capture run."""
from __future__ import annotations

import argparse
import hashlib
import json
import logging
import re
from datetime import datetime
from zoneinfo import ZoneInfo
from pathlib import Path

from PIL import Image
from pypdf import PdfReader, PdfWriter, Transformation
from reportlab import rl_config
from reportlab.lib.colors import HexColor
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas


ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--captures-dir', type=Path, required=True)
parser.add_argument('--result-bundle', required=True)
args = parser.parse_args()
REVIEW_PAGES = [9, 10, 12, 13, 14, 20, 26, 29, 34, 43, 54, 55]
SOURCE_DIFFERENCE = '원본 HWP는 6·7급 문장만 노란색입니다. 정답 PDF는 8·9급 문장도 노란색이며, 앱은 HWP에 저장된 값을 표시합니다.'
OUT = ROOT / 'output/pdf/hwp_comparison_review_20260907'
TMP = ROOT / 'tmp/pdfs'
CAPTURES = args.captures_dir.resolve()
capture_tests = json.loads((CAPTURES / 'manifest.json').read_text())
capture_times = [a['timestamp'] for test in capture_tests
                 if 'testOfficialHWPFullPageCorpus' in test['testIdentifier'] for a in test['attachments']]
CAPTURE_DATE = datetime.fromtimestamp(min(capture_times), ZoneInfo('Asia/Seoul')).date().isoformat()
CAPTURE_LABEL = f'{CAPTURE_DATE} 글꼴·점선·그림자 보정'
OUT.mkdir(parents=True, exist_ok=True)
TMP.mkdir(parents=True, exist_ok=True)
logging.getLogger('pypdf').setLevel(logging.ERROR)
rl_config.useA85 = False
pdfmetrics.registerFont(TTFont('Korean', str(ROOT / 'shortcuts_example/Gulim-Regular.ttf')))

documents = []
for manifest_name, folder in [
    ('hwp_fullpage_corpus.json', 'round1'),
    ('hwp_fullpage_corpus_round2.json', 'round2'),
]:
    manifest = json.loads((ROOT / 'Tools/Documents' / manifest_name).read_text())
    for document in manifest['documents']:
        source = ROOT / 'outputs/hwp_fullpage_corpus_restored' / folder / (document['id'] + '.pdf')
        assert hashlib.sha256(source.read_bytes()).hexdigest() == document['pdfSHA256']
        assert hashlib.sha256(source.with_suffix('.hwp').read_bytes()).hexdigest() == document['hwpSHA256']
        reader = PdfReader(source)
        assert len(reader.pages) == document['expectedPages']
        documents.append({**document, 'source': source, 'reader': reader})

captures = {}
for test in capture_tests:
    if 'testOfficialHWPFullPageCorpus' not in test['testIdentifier']:
        continue
    for attachment in test['attachments']:
        match = re.search(r'(FP\d{2}_[a-z0-9_]+)-page-(\d{3})', attachment['suggestedHumanReadableName'])
        if match:
            key = (match[1], int(match[2]))
            assert key not in captures, key
            captures[key] = CAPTURES / attachment['exportedFileName']
assert len(captures) == 210

reference_path = OUT / 'HWP_정답본_공식원본_210쪽.pdf'
comparison_path = OUT / 'HWP_눈으로비교_왼쪽정답_오른쪽M4_210쪽.pdf'
reference = PdfWriter()
frames_path = TMP / 'hwp_comparison_frames.pdf'
frames = canvas.Canvas(str(frames_path), pageCompression=1)
frames.setTitle('HWP 원본과 M4 앱 화면 비교')
entries = []
page_offset = 0
for document in documents:
    reader = document['reader']
    reference.append(reader, import_outline=False)
    for number, original in enumerate(reader.pages, start=1):
        width, height = float(original.cropbox.width), float(original.cropbox.height)
        if original.rotation in (90, 270):
            width, height = height, width
        page_width, page_height = 2 * width + 72, height + 94
        frames.setPageSize((page_width, page_height))
        frames.setFillColor(HexColor('#F3F5F7'))
        frames.rect(0, 0, page_width, page_height, fill=1, stroke=0)
        frames.setFont('Korean', 11)
        frames.setFillColor(HexColor('#172733'))
        title = f"{document['id'][:4]}  {document['title']}"
        font_size = min(11, 11 * (page_width * 0.64 - 30) / max(1, pdfmetrics.stringWidth(title, 'Korean', 11)))
        frames.setFont('Korean', font_size)
        frames.drawString(24, page_height - 22, title)
        frames.setFont('Korean', 10)
        frames.drawRightString(page_width - 24, page_height - 22,
                               f"원문 {number}/{len(reader.pages)}쪽  |  전체 {page_offset + number}/210쪽")
        frames.setFillColor(HexColor('#145E68'))
        frames.setFont('Korean', 12)
        frames.drawString(24, page_height - 48, '정답  |  기관 공개 원본 PDF')
        frames.setFillColor(HexColor('#2459A7'))
        frames.drawString(width + 48, page_height - 48, '앱  |  M4 iPad 실제 표시')
        frames.setFillColor(HexColor('#FFFFFF'))
        frames.rect(24, 24, width, height, fill=1, stroke=0)
        frames.rect(width + 48, 24, width, height, fill=1, stroke=0)
        image_path = captures[(document['id'], number)]
        with Image.open(image_path) as image:
            image_width, image_height = image.size
        scale = min(width / image_width, height / image_height)
        rendered_width, rendered_height = image_width * scale, image_height * scale
        frames.drawImage(str(image_path), width + 48 + (width - rendered_width) / 2,
                         24 + height - rendered_height, width=rendered_width,
                         height=rendered_height, mask='auto')
        frames.setFillColor(HexColor('#62717E'))
        frames.setFont('Korean', 8)
        footer = ('원본 자료 차이: 8·9급 문장의 노란 강조는 PDF에만 있음'
                  if document['id'] == 'FP01_kcg_workshop' and number == 14 else document['id'])
        frames.drawString(24, 10, footer)
        frames.drawRightString(page_width - 24, 10, f'M4 캡처: {CAPTURE_LABEL} 반영')
        frames.showPage()
        entries.append({
            'document': document['id'], 'originalPage': number,
            'combinedPage': page_offset + number,
            'capture': str(image_path.relative_to(ROOT)),
            'width': width, 'height': height,
        })
    document['startPage'] = page_offset + 1
    page_offset += len(reader.pages)
    document['endPage'] = page_offset
    print(f"Prepared {document['id']}: {document['startPage']}-{document['endPage']}", flush=True)
frames.save()
assert page_offset == 210

frames_reader = PdfReader(frames_path)
comparison = PdfWriter()
index = 0
for document in documents:
    for original in document['reader'].pages:
        page = comparison.add_page(frames_reader.pages[index])
        if original.rotation:
            original.transfer_rotation_to_content()
        page.merge_transformed_page(original, Transformation().translate(
            tx=24 - float(original.cropbox.left), ty=24 - float(original.cropbox.bottom)))
        index += 1

for writer, title in [
    (reference, 'HWP 정답본 - 기관 공개 원본 10개 문서 210쪽'),
    (comparison, 'HWP 눈으로 비교 - 왼쪽 공식 원본, 오른쪽 M4 앱 화면'),
]:
    writer.add_metadata({'/Title': title, '/Author': 'RivoPad document validation',
                         '/Subject': f'공식 HWP/PDF 비교 자료 10개. 문서 순서 FP01-FP10. {CAPTURE_DATE}.'})
    current_focus = writer.add_outline_item('이번 보정: 지정한 12쪽', REVIEW_PAGES[0] - 1)
    for page_number in REVIEW_PAGES:
        entry = entries[page_number - 1]
        writer.add_outline_item(
            f"{page_number}쪽: {entry['document'][:4]} 원문 {entry['originalPage']}쪽",
            page_number - 1, parent=current_focus)
    previous_focus = writer.add_outline_item('이전 보정: FP01 공고 1~5쪽', 0)
    for page_number in range(1, 6):
        writer.add_outline_item(f'{page_number}쪽: 공고 원본과 M4 비교', page_number - 1, parent=previous_focus)
    writer.add_outline_item('14쪽: 원본 HWP와 PDF의 강조색 차이', 13)
    focus = writer.add_outline_item('다른 문서·복잡한 양식 확인', 53)
    writer.add_outline_item('54쪽: FP03 원문 1쪽 - 표와 글상자', 53, parent=focus)
    writer.add_outline_item('152쪽: FP09 원문 12쪽 - 그림 누락', 151, parent=focus)
    writer.add_outline_item('28쪽: FP01 원문 28쪽 - 가로 표 양식', 27, parent=focus)
    for document in documents:
        writer.add_outline_item(
            f"{document['id'][:4]} | {document['title']} | {document['startPage']}-{document['endPage']}쪽",
            document['startPage'] - 1)
    writer.page_mode = '/UseOutlines'
reference.write(reference_path)
comparison.write(comparison_path)

# Same identity as HWPComparisonReviewStore. Copy only absent archives to the
# device: a later rebuild must not replace a user's own review notes.
notes_directory = OUT / 'review-notes' / '.HWPComparisonReview'
notes_directory.mkdir(parents=True, exist_ok=True)
def review_seed(document, reference=None):
    digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
    identity = f'hwp-comparison-v1|{digest(document)}|{digest(reference) if reference else "-"}'
    key = hashlib.sha256(identity.encode()).hexdigest()
    archive = {'version': 1, 'pages': {'13': {'kind': 'sourceDifference', 'text': SOURCE_DIFFERENCE}}}
    destination = notes_directory / f'{key}.json'
    destination.write_text(json.dumps(archive, ensure_ascii=False, indent=2) + '\n')
    return destination.name
seed_files = [review_seed(reference_path), review_seed(comparison_path),
              review_seed(documents[0]['source'].with_suffix('.hwp'), documents[0]['source'])]

# Reopening confirms the official page content and order survived concatenation.
written_reference = PdfReader(reference_path)
written_comparison = PdfReader(comparison_path)
assert len(written_reference.pages) == len(written_comparison.pages) == 210
index = 0
for document in documents:
    for original in document['reader'].pages:
        saved = written_reference.pages[index]
        assert saved.get_contents().get_data() == original.get_contents().get_data(), index
        assert list(saved.mediabox) == list(original.mediabox), index
        assert '정답' in written_comparison.pages[index].extract_text(), index
        index += 1

manifest = {
    'referencePDF': reference_path.name, 'comparisonPDF': comparison_path.name,
    'pageCount': 210, 'captureDate': CAPTURE_DATE,
    'captureResult': args.result_bundle,
    'generatedAt': datetime.now(ZoneInfo('Asia/Seoul')).isoformat(timespec='seconds'),
    'reviewCombinedPages': REVIEW_PAGES,
    'reviewSeedFiles': seed_files,
    'sourceDifferences': [{'combinedPage': 14, 'text': SOURCE_DIFFERENCE}],
    'coverage': 'Existing official HWP/PDF pairs FP01-FP10; excludes the additional unpaired 41 public HWP fixtures.',
    'documents': [{k: v for k, v in d.items() if k not in ('reader', 'source')} for d in documents],
    'pages': entries,
}
(OUT / 'sources_and_page_index.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
rows = ['# HWP 비교용 PDF', '',
        '정답본은 기관에서 HWP와 함께 공개한 공식 PDF 10개를 순서대로 묶은 210쪽이다. 글자·표·그림의 원본 페이지 내용을 보존했다.', '',
        f'비교본은 같은 210쪽에 왼쪽 공식 PDF, 오른쪽 {CAPTURE_DATE} 최종 M4 캡처를 배치했다. 원본의 가로·세로 방향과 화면 비율을 유지했다.', '',
        '두 파일의 전체 쪽 번호가 일치한다. 이번 보정은 전체 9, 10, 12, 13, 14, 20, 26, 29, 34, 43, 54, 55쪽이다. 책갈피의 ‘이번 보정: 지정한 12쪽’에서 바로 열 수 있다. 이전 1~5쪽과 가로 양식 등도 책갈피로 유지했다.', '',
        '14쪽의 8·9급 문장 강조색은 공식 PDF에는 있지만 HWP의 해당 문단은 강조 없음으로 저장되어 있다. 앱 화면은 HWP 값을 따랐다. 비교 화면의 ‘기록 보기’에서도 이 설명을 확인할 수 있다. 대체 글꼴의 모양과 굵기에는 아직 차이가 있다.', '',
        '최근 추가한 공개 HWP 41개 중 공식 PDF가 없는 문서는 포함하지 않았다.', '',
        '| 문서 | 전체 쪽 | 출처 |', '| --- | --- | --- |']
for d in documents:
    rows.append(f"| {d['id'][:4]} {d['title']} | {d['startPage']}-{d['endPage']} | [공식 게시물]({d['sourcePage']}) |")
(OUT / '읽어주세요.md').write_text('\n'.join(rows) + '\n')
print(json.dumps({'referenceBytes': reference_path.stat().st_size,
                  'comparisonBytes': comparison_path.stat().st_size,
                  'verifiedPages': index}, ensure_ascii=False), flush=True)
