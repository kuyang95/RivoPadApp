#!/usr/bin/env python3
"""Compare native M4 page captures with reviewed app images (not official PDFs)."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

CAPTURE_TESTS = ('testCoastGuardFirstFivePagesPreserveSourceLayout', 'testSelectedOfficialHWPReviewPages')
DEFAULT_LIMITS = dict(channelDelta=18, pageChangedFraction=0.02, tileChangedFraction=0.12, tileSize=64)


def captures(directory: Path) -> dict[str, dict]:
    result = {}
    for test in json.loads((directory / 'manifest.json').read_text()):
        if not any(name in test['testIdentifier'] for name in CAPTURE_TESTS):
            continue
        for item in test['attachments']:
            if Path(item['exportedFileName']).suffix.lower() != '.png':
                continue
            match = re.match(r'(FP\d{2}_[a-z0-9_]+-page-\d{3})_', item['suggestedHumanReadableName'])
            if match:
                key = match[1]
                if key in result:
                    raise ValueError(f'Duplicate page capture: {key}')
                result[key] = {**item, 'path': directory / item['exportedFileName']}
    return result


def compare(reference: Image.Image, actual: Image.Image, limits: dict) -> tuple[dict, Image.Image | None]:
    if reference.size != actual.size:
        return {'passed': False, 'reason': 'image size changed',
                'expectedSize': reference.size, 'actualSize': actual.size}, None
    # Subpixel edge antialiasing gets a little tolerance; never resize or align
    # images here, since doing so would hide page margin or scale regressions.
    def pixels(image):
        return np.asarray(image.convert('RGB').filter(ImageFilter.GaussianBlur(0.35)), dtype=np.int16)
    changed = np.max(np.abs(pixels(reference) - pixels(actual)), axis=2) > limits['channelDelta']
    fraction = float(changed.mean())
    tile = limits['tileSize']
    worst = (0.0, 0, 0)
    for y in range(0, changed.shape[0], tile // 2):
        for x in range(0, changed.shape[1], tile // 2):
            area = changed[y:y + tile, x:x + tile]
            score = float(area.sum()) / (tile * tile)
            if score > worst[0]:
                worst = (score, x, y)
    passed = fraction <= limits['pageChangedFraction'] and worst[0] <= limits['tileChangedFraction']
    result = {'passed': passed, 'pageChangedFraction': fraction,
              'worstTileChangedFraction': worst[0], 'worstTileOrigin': list(worst[1:])}
    heat = np.full((*changed.shape, 3), 255, dtype=np.uint8)
    heat[changed] = [230, 45, 70]
    return result, Image.fromarray(heat)


def check(directory: Path, baseline: Path, output: Path) -> dict:
    manifest = json.loads(baseline.read_text())
    if manifest['version'] != 1:
        raise ValueError('Unsupported baseline version')
    current = captures(directory)
    output.mkdir(parents=True, exist_ok=True)
    rows = []
    for page in manifest['pages']:
        key = page['id']
        reference_path = baseline.parent / page['file']
        if hashlib.sha256(reference_path.read_bytes()).hexdigest() != page['sha256']:
            raise ValueError(f'Baseline checksum changed: {key}')
        capture = current.get(key)
        if capture is None:
            rows.append({'id': key, 'passed': False, 'reason': 'missing page capture'})
            continue
        if capture.get('deviceId') != manifest['deviceId']:
            rows.append({'id': key, 'passed': False, 'reason': 'capture device differs from baseline'})
            continue
        with Image.open(reference_path) as reference, Image.open(capture['path']) as actual:
            row, heat = compare(reference, actual, manifest['limits'])
            rows.append({'id': key, **row})
            if not row['passed']:
                reference.convert('RGB').save(output / f'{key}-baseline.png')
                actual.convert('RGB').save(output / f'{key}-actual.png')
                if heat is not None:
                    heat.save(output / f'{key}-difference.png')
    report = {'baseline': str(baseline), 'captures': str(directory),
              'passed': bool(rows) and all(row['passed'] for row in rows),
              'checkedPages': len(rows), 'failedPages': sum(not row['passed'] for row in rows), 'pages': rows}
    (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--captures-dir', type=Path, required=True)
    parser.add_argument('--baseline', type=Path, default=Path(__file__).with_name('HWPVisualBaselines') / 'manifest.json')
    parser.add_argument('--output-dir', type=Path, required=True)
    args = parser.parse_args()
    report = check(args.captures_dir, args.baseline, args.output_dir)
    print(json.dumps({key: report[key] for key in ('passed', 'checkedPages', 'failedPages')}))
    raise SystemExit(0 if report['passed'] else 1)


if __name__ == '__main__':
    main()
