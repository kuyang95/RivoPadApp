#!/usr/bin/env python3
"""Download and checksum the official HWP/PDF full-page validation corpus."""

from __future__ import annotations

import argparse
import http.cookiejar
import hashlib
import json
from pathlib import Path
import sys
import urllib.request


USER_AGENT = "VisionCraft-HWP-Renderer-Validation/1.0"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download(url: str, destination: Path, referer: str | None = None) -> None:
    cookie_jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(
        urllib.request.HTTPCookieProcessor(cookie_jar)
    )
    if referer:
        landing_request = urllib.request.Request(
            referer,
            headers={"User-Agent": USER_AGENT},
        )
        with opener.open(landing_request, timeout=60) as response:
            response.read(1)
    headers = {"User-Agent": USER_AGENT}
    if referer:
        headers["Referer"] = referer
    request = urllib.request.Request(url, headers=headers)
    temporary = destination.with_suffix(destination.suffix + ".partial")
    with opener.open(request, timeout=60) as response:
        temporary.write_bytes(response.read())
    temporary.replace(destination)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--manifest",
        type=Path,
        default=Path(__file__).with_name("hwp_fullpage_corpus.json"),
    )
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--refresh", action="store_true")
    args = parser.parse_args()

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    args.output_dir.mkdir(parents=True, exist_ok=True)
    failures: list[str] = []

    for document in manifest["documents"]:
        for extension in ("hwp", "pdf"):
            destination = args.output_dir / f"{document['id']}.{extension}"
            expected = document[f"{extension}SHA256"]
            if args.refresh or not destination.exists():
                print(f"download {destination.name}")
                download(
                    document[f"{extension}URL"],
                    destination,
                    referer=document.get("sourcePage"),
                )
            actual = sha256(destination)
            if actual != expected:
                failures.append(
                    f"{destination.name}: expected {expected}, received {actual}"
                )
            else:
                print(f"verified {destination.name} {actual}")

    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
