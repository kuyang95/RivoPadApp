#!/usr/bin/env python3
"""Compare every iPad-rendered HWP page with its official reference PDF page."""

from __future__ import annotations

import argparse
from collections import Counter
import json
import math
from pathlib import Path
import re
import shutil
import subprocess
import sys
import unicodedata

import numpy as np
from PIL import Image, ImageDraw, ImageOps


def find_attachment_file(directory: Path, filename: str) -> Path:
    direct = directory / filename
    if direct.exists():
        return direct
    matches = list(directory.rglob(filename))
    if len(matches) != 1:
        raise FileNotFoundError(f"attachment not found: {filename}")
    return matches[0]


def load_actual_pages(attachments_directory: Path) -> dict[str, dict[int, Path]]:
    manifest_path = attachments_directory / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    pages: dict[str, dict[int, Path]] = {}
    pattern = re.compile(r"(FP\d{2}_[A-Za-z0-9_]+)-page-(\d{3})")
    for test in manifest:
        for attachment in test.get("attachments", []):
            suggested_name = attachment.get("suggestedHumanReadableName", "")
            match = pattern.search(suggested_name)
            if not match:
                continue
            fixture_id, page_text = match.groups()
            pages.setdefault(fixture_id, {})[int(page_text)] = find_attachment_file(
                attachments_directory,
                attachment["exportedFileName"],
            )
    return pages


def load_actual_page_text(attachments_directory: Path) -> dict[str, dict[int, str]]:
    manifest_path = attachments_directory / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    result: dict[str, dict[int, str]] = {}
    pattern = re.compile(r"(FP\d{2}_[A-Za-z0-9_]+)-page-text")
    for test in manifest:
        for attachment in test.get("attachments", []):
            match = pattern.search(
                attachment.get("suggestedHumanReadableName", "")
            )
            if not match:
                continue
            payload = json.loads(
                find_attachment_file(
                    attachments_directory,
                    attachment["exportedFileName"],
                ).read_text(encoding="utf-8")
            )
            result[match.group(1)] = {
                int(item["page"]): str(item.get("text", "")) for item in payload
            }
    return result


def load_reference_page_text(pdf_path: Path) -> dict[int, str]:
    pdftotext = shutil.which("pdftotext")
    if pdftotext is None:
        raise RuntimeError("pdftotext is required (Poppler)")
    completed = subprocess.run(
        [pdftotext, "-layout", str(pdf_path), "-"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    decoded = completed.stdout.decode("utf-8", errors="replace")
    pages = decoded.split("\f")
    if pages and not pages[-1].strip():
        pages.pop()
    return {index + 1: text for index, text in enumerate(pages)}


def render_reference_pages(
    pdf_path: Path,
    output_directory: Path,
    dpi: int,
) -> dict[int, Path]:
    pdftoppm = shutil.which("pdftoppm")
    if pdftoppm is None:
        raise RuntimeError("pdftoppm is required (Poppler)")
    output_directory.mkdir(parents=True, exist_ok=True)
    prefix = output_directory / "page"
    subprocess.run(
        [pdftoppm, "-png", "-r", str(dpi), str(pdf_path), str(prefix)],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    rendered: dict[int, Path] = {}
    for path in output_directory.glob("page-*.png"):
        match = re.search(r"-(\d+)\.png$", path.name)
        if match:
            rendered[int(match.group(1))] = path
    return rendered


def ink_mask(image: Image.Image) -> np.ndarray:
    gray = np.asarray(image.convert("L"), dtype=np.uint8)
    return gray < 245


def dilate(mask: np.ndarray, radius: int = 3) -> np.ndarray:
    if radius <= 0:
        return mask
    size = radius * 2 + 1
    padded = np.pad(mask, ((radius, radius), (radius, radius)))
    integral = np.pad(
        padded.astype(np.uint32),
        ((1, 0), (1, 0)),
    ).cumsum(axis=0).cumsum(axis=1)
    window_sums = (
        integral[size:, size:]
        - integral[:-size, size:]
        - integral[size:, :-size]
        + integral[:-size, :-size]
    )
    return window_sums > 0


def bounding_box(mask: np.ndarray) -> tuple[int, int, int, int] | None:
    ys, xs = np.nonzero(mask)
    if not len(xs):
        return None
    return int(xs.min()), int(ys.min()), int(xs.max() + 1), int(ys.max() + 1)


def box_iou(
    left: tuple[int, int, int, int] | None,
    right: tuple[int, int, int, int] | None,
) -> float:
    if left is None and right is None:
        return 1.0
    if left is None or right is None:
        return 0.0
    x0 = max(left[0], right[0])
    y0 = max(left[1], right[1])
    x1 = min(left[2], right[2])
    y1 = min(left[3], right[3])
    intersection = max(0, x1 - x0) * max(0, y1 - y0)
    left_area = (left[2] - left[0]) * (left[3] - left[1])
    right_area = (right[2] - right[0]) * (right[3] - right[1])
    union = left_area + right_area - intersection
    return intersection / union if union else 1.0


def tolerant_ink_f1(
    actual_mask: np.ndarray,
    reference_mask: np.ndarray,
    radius: int,
) -> float:
    actual_ink = int(actual_mask.sum())
    reference_ink = int(reference_mask.sum())
    if actual_ink == 0 and reference_ink == 0:
        return 1.0
    if actual_ink == 0 or reference_ink == 0:
        return 0.0
    precision = float((actual_mask & dilate(reference_mask, radius)).sum()) / actual_ink
    recall = float((reference_mask & dilate(actual_mask, radius)).sum()) / reference_ink
    return 2 * precision * recall / (precision + recall) if precision + recall else 0


def normalized_tokens(text: str) -> list[str]:
    normalized = unicodedata.normalize("NFKC", text).casefold()
    return re.findall(r"[가-힣a-z0-9]+", normalized)


def token_f1(actual: str, reference: str) -> float:
    actual_tokens = Counter(normalized_tokens(actual))
    reference_tokens = Counter(normalized_tokens(reference))
    actual_count = sum(actual_tokens.values())
    reference_count = sum(reference_tokens.values())
    if actual_count == 0 and reference_count == 0:
        return 1.0
    if actual_count == 0 or reference_count == 0:
        return 0.0
    overlap = sum((actual_tokens & reference_tokens).values())
    precision = overlap / actual_count
    recall = overlap / reference_count
    return 2 * precision * recall / (precision + recall) if precision + recall else 0


def compare_page(
    actual: Image.Image,
    reference: Image.Image,
    actual_text: str,
    reference_text: str,
) -> dict[str, float]:
    actual = ImageOps.exif_transpose(actual).convert("RGB")
    reference = ImageOps.exif_transpose(reference).convert("RGB")
    if reference.size != actual.size:
        reference = reference.resize(actual.size, Image.Resampling.LANCZOS)

    actual_mask = ink_mask(actual)
    reference_mask = ink_mask(reference)
    actual_ink = int(actual_mask.sum())
    reference_ink = int(reference_mask.sum())
    ink_f1 = tolerant_ink_f1(actual_mask, reference_mask, radius=3)
    layout_ink_f1 = tolerant_ink_f1(actual_mask, reference_mask, radius=12)

    actual_gray = np.asarray(actual.convert("L"), dtype=np.int16)
    reference_gray = np.asarray(reference.convert("L"), dtype=np.int16)
    mean_absolute_error = float(
        np.abs(actual_gray - reference_gray).mean() / 255.0
    )
    coverage_ratio = actual_ink / reference_ink if reference_ink else math.inf
    return {
        "inkF1": ink_f1,
        "layoutInkF1": layout_ink_f1,
        "grayMAE": mean_absolute_error,
        "inkCoverageRatio": coverage_ratio,
        "textTokenF1": token_f1(actual_text, reference_text),
        "contentBoxIoU": box_iou(
            bounding_box(actual_mask),
            bounding_box(reference_mask),
        ),
    }


def comparison_image(
    actual: Image.Image,
    reference: Image.Image,
    title: str,
) -> Image.Image:
    actual = ImageOps.exif_transpose(actual).convert("RGB")
    reference = ImageOps.exif_transpose(reference).convert("RGB").resize(
        actual.size,
        Image.Resampling.LANCZOS,
    )
    actual_mask = ink_mask(actual)
    reference_mask = ink_mask(reference)
    overlay_data = np.full((*actual_mask.shape, 3), 255, dtype=np.uint8)
    both = actual_mask & reference_mask
    overlay_data[reference_mask & ~actual_mask] = (0, 145, 190)
    overlay_data[actual_mask & ~reference_mask] = (225, 45, 45)
    overlay_data[both] = (28, 28, 28)
    overlay = Image.fromarray(overlay_data)

    thumb_width = 360
    thumb_height = round(thumb_width * actual.height / actual.width)
    label_height = 28
    canvas = Image.new(
        "RGB",
        (thumb_width * 3, thumb_height + label_height),
        "white",
    )
    for index, (label, image) in enumerate(
        (("REFERENCE", reference), ("IPAD", actual), ("OVERLAY", overlay))
    ):
        thumbnail = image.resize(
            (thumb_width, thumb_height),
            Image.Resampling.LANCZOS,
        )
        canvas.paste(thumbnail, (index * thumb_width, label_height))
        ImageDraw.Draw(canvas).text(
            (index * thumb_width + 8, 7),
            f"{title}  {label}",
            fill="black",
        )
    return canvas


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--corpus-manifest", type=Path, required=True)
    parser.add_argument("--corpus-dir", type=Path, required=True)
    parser.add_argument("--attachments-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--dpi", type=int, default=144)
    parser.add_argument("--minimum-ink-f1", type=float, default=0.35)
    parser.add_argument("--minimum-layout-ink-f1", type=float, default=0.55)
    parser.add_argument("--minimum-text-token-f1", type=float, default=0.80)
    parser.add_argument("--report-only", action="store_true")
    args = parser.parse_args()

    corpus = json.loads(args.corpus_manifest.read_text(encoding="utf-8"))
    actual_pages = load_actual_pages(args.attachments_dir)
    actual_page_text = load_actual_page_text(args.attachments_dir)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    comparison_directory = args.output_dir / "comparisons"
    comparison_directory.mkdir(parents=True, exist_ok=True)

    results: list[dict[str, object]] = []
    page_count_failures: list[str] = []
    for document in corpus["documents"]:
        fixture_id = document["id"]
        references = render_reference_pages(
            args.corpus_dir / f"{fixture_id}.pdf",
            args.output_dir / "references" / fixture_id,
            args.dpi,
        )
        reference_page_text = load_reference_page_text(
            args.corpus_dir / f"{fixture_id}.pdf"
        )
        actuals = actual_pages.get(fixture_id, {})
        actual_text = actual_page_text.get(fixture_id, {})
        expected_pages = int(document["expectedPages"])
        if len(references) != expected_pages:
            page_count_failures.append(
                f"{fixture_id}: PDF {len(references)} != manifest {expected_pages}"
            )
        if len(actuals) != expected_pages:
            page_count_failures.append(
                f"{fixture_id}: iPad {len(actuals)} != PDF {expected_pages}"
            )

        for page_number in sorted(set(references) & set(actuals)):
            with Image.open(actuals[page_number]) as actual_image, Image.open(
                references[page_number]
            ) as reference_image:
                metrics = compare_page(
                    actual_image,
                    reference_image,
                    actual_text.get(page_number, ""),
                    reference_page_text.get(page_number, ""),
                )
                comparison_name = f"{fixture_id}-page-{page_number:03d}.png"
                comparison_image(
                    actual_image,
                    reference_image,
                    f"{fixture_id} p.{page_number}",
                ).save(comparison_directory / comparison_name)
            results.append(
                {
                    "document": fixture_id,
                    "page": page_number,
                    "comparison": f"comparisons/{comparison_name}",
                    **metrics,
                }
            )

    results.sort(key=lambda item: float(item["inkF1"]))
    strict_severe = [
        result
        for result in results
        if float(result["inkF1"]) < args.minimum_ink_f1
    ]
    layout_failures = [
        result
        for result in results
        if float(result["layoutInkF1"]) < args.minimum_layout_ink_f1
    ]
    text_failures = [
        result
        for result in results
        if float(result["textTokenF1"]) < args.minimum_text_token_f1
    ]
    document_summaries = []
    for document in corpus["documents"]:
        fixture_id = document["id"]
        pages = [item for item in results if item["document"] == fixture_id]
        document_summaries.append(
            {
                "document": fixture_id,
                "pages": len(pages),
                "averageInkF1": sum(float(item["inkF1"]) for item in pages)
                / max(len(pages), 1),
                "averageLayoutInkF1": sum(
                    float(item["layoutInkF1"]) for item in pages
                )
                / max(len(pages), 1),
                "averageTextTokenF1": sum(
                    float(item["textTokenF1"]) for item in pages
                )
                / max(len(pages), 1),
            }
        )
    report = {
        "documents": len(corpus["documents"]),
        "expectedPages": sum(
            int(document["expectedPages"]) for document in corpus["documents"]
        ),
        "comparedPages": len(results),
        "minimumInkF1": args.minimum_ink_f1,
        "strictSeverePages": len(strict_severe),
        "layoutFailurePages": len(layout_failures),
        "textFailurePages": len(text_failures),
        "pageCountFailures": page_count_failures,
        "documentSummaries": document_summaries,
        "pages": results,
    }
    (args.output_dir / "report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    markdown = [
        "# HWP full-page visual validation",
        "",
        f"- Documents: {report['documents']}",
        f"- Expected pages: {report['expectedPages']}",
        f"- Compared pages: {report['comparedPages']}",
        f"- Strict pixel failures (3 px ink F1 < {args.minimum_ink_f1:.2f}): {len(strict_severe)}",
        f"- Layout failures (12 px ink F1 < {args.minimum_layout_ink_f1:.2f}): {len(layout_failures)}",
        f"- Text failures (token F1 < {args.minimum_text_token_f1:.2f}): {len(text_failures)}",
        "",
    ]
    if page_count_failures:
        markdown.extend(["## Page-count failures", ""])
        markdown.extend(f"- {failure}" for failure in page_count_failures)
        markdown.append("")
    markdown.extend(
        [
            "## Document averages",
            "",
            "| Document | Pages | Ink F1 | Layout F1 | Text F1 |",
            "| --- | ---: | ---: | ---: | ---: |",
        ]
    )
    for summary in document_summaries:
        markdown.append(
            "| {document} | {pages} | {averageInkF1:.3f} | "
            "{averageLayoutInkF1:.3f} | {averageTextTokenF1:.3f} |".format(
                **summary
            )
        )
    markdown.extend(
        [
            "",
            "## Worst pages",
            "",
            "| Page | Ink F1 | Layout F1 | Text F1 | Gray MAE | Ink ratio | Box IoU | Comparison |",
            "| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |",
        ]
    )
    for result in results[:20]:
        markdown.append(
            "| {document} p.{page} | {inkF1:.3f} | {layoutInkF1:.3f} | "
            "{textTokenF1:.3f} | {grayMAE:.3f} | {inkCoverageRatio:.3f} | "
            "{contentBoxIoU:.3f} | [open]({comparison}) |".format(
                **result
            )
        )
    (args.output_dir / "report.md").write_text(
        "\n".join(markdown) + "\n",
        encoding="utf-8",
    )

    for failure in page_count_failures:
        print(f"PAGE COUNT: {failure}")
    print(
        f"compared={len(results)} strict={len(strict_severe)} "
        f"layout={len(layout_failures)} text={len(text_failures)} "
        f"worstInkF1={float(results[0]['inkF1']) if results else 0:.3f}"
    )
    print(args.output_dir / "report.md")
    if not args.report_only and (
        page_count_failures or layout_failures or text_failures
    ):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
