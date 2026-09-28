#!/usr/bin/env bash
set -euo pipefail

poc_source_dir="${1:-tmp/pdfs/word-rag-poc}"
mkdir -p "$poc_source_dir"

for required_command in curl pdftotext pdfinfo; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
        echo "Required command is missing: $required_command" >&2
        exit 1
    fi
done

download_and_extract() {
    local source_url="$1"
    local base_name="$2"
    local pdf_path="$poc_source_dir/$base_name.pdf"
    local text_path="$poc_source_dir/$base_name.txt"

    curl --fail --location --silent --show-error "$source_url" --output "$pdf_path"
    pdfinfo "$pdf_path" >/dev/null
    pdftotext -enc UTF-8 "$pdf_path" "$text_path"
}

download_and_extract \
    "https://law.go.kr/lbook/lbFileDownload.do?flExt=pdf&lbookConflSeq=102409&lbookSeq=96116" \
    "labor_standards_act"

download_and_extract \
    "https://kostat.go.kr/boardDownload.es?bid=10820&list_no=438832&seq=1" \
    "older_persons_statistics_2025"

download_and_extract \
    "https://www.bok.or.kr/fileSrc/portal/abee0d98aefe40b8abadc5744ec5d613/1/8e9cda349b1049f8be89054aa1d21d18.pdf" \
    "economic_outlook_2026_02"

echo "Sources are ready in $poc_source_dir"
