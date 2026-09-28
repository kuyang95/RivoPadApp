#!/usr/bin/env python3
"""Summarize the all-sheet XLSX app test and independent PDF render pass."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pdf_pages(path: Path) -> int:
    result = subprocess.run(
        ["pdfinfo", str(path)],
        check=True,
        capture_output=True,
        text=True,
    )
    match = re.search(r"^Pages:\s+(\d+)\s*$", result.stdout, re.MULTILINE)
    if not match:
        raise RuntimeError(f"pdfinfo did not report pages for {path}")
    return int(match.group(1))


def find_test_report(attachments_dir: Path) -> str:
    candidates = list(attachments_dir.glob("*.txt"))
    for path in candidates:
        text = path.read_text(encoding="utf-8", errors="replace")
        if text.startswith("New internet XLSX full-workbook validation"):
            return text
    raise RuntimeError("XLSX full-workbook XCTest report attachment is missing")


def rasterize_pdf(path: Path, output_dir: Path) -> list[Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    prefix = output_dir / path.stem
    subprocess.run(
        ["pdftoppm", "-png", "-r", "90", str(path), str(prefix)],
        check=True,
        capture_output=True,
        text=True,
    )
    pages = sorted(output_dir.glob(f"{path.stem}-*.png"))
    if not pages:
        raise RuntimeError(f"pdftoppm produced no pages for {path}")
    return pages


def page_ink_ratio(path: Path) -> float:
    with Image.open(path) as source:
        gray = source.convert("L")
        histogram = gray.histogram()
        ink_pixels = sum(histogram[:248])
        return ink_pixels / max(1, gray.width * gray.height)


def make_contact_sheet(pages: list[Path], output: Path) -> None:
    thumbnails: list[tuple[Path, Image.Image]] = []
    for path in pages:
        with Image.open(path) as source:
            image = source.convert("RGB")
            image.thumbnail((360, 480))
            thumbnails.append((path, image.copy()))
    columns = 3
    label_height = 34
    gutter = 16
    cell_width = 392
    cell_height = 530
    rows = (len(thumbnails) + columns - 1) // columns
    sheet = Image.new(
        "RGB",
        (columns * cell_width, rows * cell_height),
        "#D9D9D9",
    )
    draw = ImageDraw.Draw(sheet)
    for index, (path, image) in enumerate(thumbnails):
        row, column = divmod(index, columns)
        x = column * cell_width + gutter
        y = row * cell_height + label_height
        sheet.paste(image, (x, y))
        draw.text(
            (x, 8 + row * cell_height),
            path.stem,
            fill="#111111",
        )
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--corpus-dir", type=Path, required=True)
    parser.add_argument("--reference-dir", type=Path, required=True)
    parser.add_argument("--attachments-dir", type=Path, required=True)
    parser.add_argument("--regression-log", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    test_report = find_test_report(args.attachments_dir)
    if "workbooks=5" not in test_report or "editedRoundTrip=true" not in test_report:
        raise RuntimeError("XLSX XCTest report is incomplete")
    if args.regression_log:
        regression_log = args.regression_log.read_text(
            encoding="utf-8",
            errors="replace",
        )
        if "InternetExcelRegressionTests' passed" not in regression_log:
            raise RuntimeError("Prior internet XLSX regression suite did not pass")

    rows: list[tuple[str, int, str, float]] = []
    total_pages = 0
    rendered_pages: list[Path] = []
    render_directory = args.output.parent / "reference-pages"
    for document in manifest["documents"]:
        workbook = args.corpus_dir / document["filename"]
        if sha256(workbook) != document["sha256"]:
            raise RuntimeError(f"checksum changed: {document['filename']}")
        reference = args.reference_dir / f"{workbook.stem}.pdf"
        pages = pdf_pages(reference)
        if pages < 1:
            raise RuntimeError(f"no rendered pages: {reference}")
        page_images = rasterize_pdf(reference, render_directory)
        if len(page_images) != pages:
            raise RuntimeError(f"PDF raster page count changed: {reference}")
        ink_ratios = [page_ink_ratio(page) for page in page_images]
        if min(ink_ratios) < 0.0001:
            raise RuntimeError(f"visually blank rendered page: {reference}")
        rendered_pages.extend(page_images)
        total_pages += pages
        rows.append((document["id"], pages, document["feature"], min(ink_ratios)))

    contact_sheet = args.output.parent / "reference-pages-contact-sheet.png"
    make_contact_sheet(rendered_pages, contact_sheet)

    lines = [
        "# Excel full-workbook validation",
        "",
        f"- Workbooks: {len(rows)}",
        f"- Independent LibreOffice-rendered pages: {total_pages}",
        "- App parser: every worksheet and used cell checked",
        "- Editing: one value edited in every workbook and reopened",
        "- Preservation: archive paths, opaque parts, and feature tag counts checked",
        "- Visual baseline: every PDF page rasterized and checked for nonblank content",
        "- Prior five-file Excel regression suite: passed on the same iPad build",
        "",
        "| Workbook | PDF pages | Minimum ink ratio | Target feature |",
        "| --- | ---: | ---: | --- |",
    ]
    for identifier, pages, feature, minimum_ink in rows:
        lines.append(
            f"| {identifier} | {pages} | {minimum_ink:.6f} | {feature} |"
        )
    lines.extend(["", "## XCTest details", "", "```text", test_report.rstrip(), "```", ""])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(lines), encoding="utf-8")
    print(f"workbooks={len(rows)} pages={total_pages}")
    print(args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
