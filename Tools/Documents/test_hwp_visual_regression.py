import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageDraw
from check_hwp_visual_regression import DEFAULT_LIMITS, check, compare


class VisualRegressionTests(unittest.TestCase):
    def page(self, title=True, table_offset=0):
        page = Image.new('RGB', (600, 800), 'white')
        draw = ImageDraw.Draw(page)
        if title:
            for x in range(80, 400, 24):
                draw.rectangle((x, 60, x + 16, 77), fill='black')
        for y in range(220, 600, 40):
            draw.line((70, y + table_offset, 530, y + table_offset), fill='black', width=2)
        for x in range(70, 531, 115):
            draw.line((x, 220 + table_offset, x, 580 + table_offset), fill='black', width=2)
        return page

    def test_unchanged_page_and_minor_color_noise_pass(self):
        reference = self.page()
        self.assertTrue(compare(reference, reference.copy(), DEFAULT_LIMITS)[0]['passed'])
        noisy = reference.point(lambda channel: max(0, channel - 3))
        self.assertTrue(compare(reference, noisy, DEFAULT_LIMITS)[0]['passed'])

    def test_missing_title_fails_even_when_global_change_is_small(self):
        result, _ = compare(self.page(), self.page(title=False), DEFAULT_LIMITS)
        self.assertLess(result['pageChangedFraction'], DEFAULT_LIMITS['pageChangedFraction'])
        self.assertFalse(result['passed'])

    def test_table_displacement_and_page_resizing_fail(self):
        self.assertFalse(compare(self.page(), self.page(table_offset=6), DEFAULT_LIMITS)[0]['passed'])
        self.assertFalse(compare(self.page(), self.page().resize((599, 800)), DEFAULT_LIMITS)[0]['passed'])

    def test_missing_capture_fails_and_corrupt_baseline_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.page().save(root / 'baseline.png')
            (root / 'manifest.json').write_text('[]')
            spec = {'version': 1, 'deviceId': 'M4', 'limits': DEFAULT_LIMITS,
                    'pages': [{'id': 'FP01_example-page-001', 'file': 'baseline.png',
                               'sha256': hashlib.sha256((root / 'baseline.png').read_bytes()).hexdigest()}]}
            baseline = root / 'baseline.json'
            baseline.write_text(json.dumps(spec))
            result = check(root, baseline, root / 'result')
            self.assertFalse(result['passed'])
            self.assertEqual(result['failedPages'], 1)
            (root / 'baseline.png').write_bytes(b'changed')
            with self.assertRaises(ValueError):
                check(root, baseline, root / 'result')


if __name__ == '__main__':
    unittest.main()
