#!/usr/bin/env python3
"""Download public regression documents and optionally install them on an iPad."""

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import subprocess
import time
import urllib.error
import urllib.request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, default=Path(__file__).with_name('hwp_regression_fixtures.json'))
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--device', help='Connected iPad identifier; omit for download only')
    parser.add_argument('--refresh', action='store_true', help='Fetch even if the local SHA-256 already matches')
    args = parser.parse_args()
    items = json.loads(args.manifest.read_text())['documents']
    args.output_dir.mkdir(parents=True, exist_ok=True)

    def download(item):
        name = item['fileName']
        if Path(name).name != name:
            raise ValueError(f'Invalid local fixture name: {name}')
        path = args.output_dir / name
        data = path.read_bytes() if path.exists() else b''
        if not args.refresh and item.get('sha256') == hashlib.sha256(data).hexdigest():
            print(f'Verified cached {name}', flush=True)
            return {**item, 'bytes': len(data), 'resolvedURL': item['url']}
        request = urllib.request.Request(item['url'], headers={'User-Agent': 'RivoPad document regression validation'})
        for attempt in range(3):
            try:
                with urllib.request.urlopen(request, timeout=20) as response:
                    data = response.read(20 * 1024 * 1024 + 1)
                    final_url = response.url
                break
            except (urllib.error.URLError, TimeoutError) as error:
                if attempt == 2:
                    raise RuntimeError(f'Cannot download {name}: {error}') from error
                time.sleep(1)
        if len(data) > 20 * 1024 * 1024:
            raise ValueError(f'Oversized fixture: {name}')
        signature = b'PK\x03\x04' if name.endswith('.hwpx') else bytes.fromhex('d0cf11e0a1b11ae1')
        if not data.startswith(signature):
            raise ValueError(f'Download is not the expected document format: {name}')
        digest = hashlib.sha256(data).hexdigest()
        if item.get('sha256') and digest != item['sha256']:
            raise ValueError(f'Fixture content changed: {name}')
        path.write_bytes(data)
        print(f'Downloaded {name}: {len(data)} bytes', flush=True)
        return {**item, 'sha256': digest, 'bytes': len(data), 'resolvedURL': final_url}

    with ThreadPoolExecutor(max_workers=4) as executor:
        downloaded = list(executor.map(download, items))
    (args.output_dir / 'download-manifest.json').write_text(
        json.dumps({'documents': downloaded}, ensure_ascii=False, indent=2) + '\n')

    if args.device:
        for item in downloaded:
            for target in item['devicePaths']:
                path = Path(target)
                if not target.startswith('Documents/') or '..' in path.parts:
                    raise ValueError(f'Invalid device fixture path: {target}')
                subprocess.run(['xcrun', 'devicectl', 'device', 'copy', 'to',
                    '--device', args.device, '--source', str(args.output_dir / item['fileName']),
                    '--destination', target, '--domain-type', 'appDataContainer',
                    '--domain-identifier', 'net.rivo.visioncraft'], check=True,
                    stdout=subprocess.DEVNULL)
        print(f'Installed {len(downloaded)} public documents.', flush=True)


if __name__ == '__main__':
    main()
