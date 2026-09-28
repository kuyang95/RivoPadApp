#!/usr/bin/env python3
"""Download the pinned XLSX full-workbook corpus and verify every checksum."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import urllib.request
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for document in manifest["documents"]:
        destination = args.output_dir / document["filename"]
        temporary = destination.with_suffix(destination.suffix + ".download")
        print(f"download {document['filename']}")
        with urllib.request.urlopen(document["url"], timeout=60) as response:
            with temporary.open("wb") as output:
                shutil.copyfileobj(response, output)
        actual = sha256(temporary)
        if actual != document["sha256"]:
            temporary.unlink(missing_ok=True)
            raise SystemExit(
                f"checksum mismatch for {document['filename']}: {actual}"
            )
        temporary.replace(destination)
        print(f"verified {document['filename']} {actual}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
