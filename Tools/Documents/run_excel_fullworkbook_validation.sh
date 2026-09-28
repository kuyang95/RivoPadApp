#!/bin/zsh
set -euo pipefail

if [[ $# -lt 1 ]]; then
  print -u2 "usage: $0 <device-udid> [output-directory]"
  exit 64
fi

DEVICE_UDID="$1"
SCRIPT_DIRECTORY="${0:A:h}"
PROJECT_DIRECTORY="${SCRIPT_DIRECTORY:h:h}"
RUN_DIRECTORY="${2:-${PROJECT_DIRECTORY}/outputs/excel_fullworkbook_validation_$(date +%Y%m%d_%H%M%S)}"
RUN_DIRECTORY="${RUN_DIRECTORY:A}"
CORPUS_DIRECTORY="${RUN_DIRECTORY}/corpus"
REFERENCE_DIRECTORY="${RUN_DIRECTORY}/libreoffice-reference"
DERIVED_DATA_DIRECTORY="${RUN_DIRECTORY}/DerivedData"
RESULT_BUNDLE="${RUN_DIRECTORY}/ExcelFullWorkbook.xcresult"
ATTACHMENTS_DIRECTORY="${RUN_DIRECTORY}/attachments"
DEVICE_STAGING_DIRECTORY="${RUN_DIRECTORY}/device-staging/전체문서 검증"
DEFAULT_PYTHON_RUNTIME="/Users/me/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3"
PYTHON_RUNTIME="${PYTHON_RUNTIME:-$DEFAULT_PYTHON_RUNTIME}"
if [[ ! -x "$PYTHON_RUNTIME" ]]; then
  PYTHON_RUNTIME="$(command -v python3)"
fi
SOFFICE_RUNTIME="${SOFFICE_RUNTIME:-$(command -v soffice)}"
TEST_IDENTIFIERS=(
  "shortcuts_exampleTests/InternetExcelFullWorkbookValidationTests/testEverySheetLoadsAndSurvivesAnEditedRoundTrip"
  "shortcuts_exampleTests/InternetExcelRegressionTests"
)
TEST_SELECTION_ARGUMENTS=()
for identifier in "${TEST_IDENTIFIERS[@]}"; do
  TEST_SELECTION_ARGUMENTS+=("-only-testing:$identifier")
done

mkdir -p \
  "$CORPUS_DIRECTORY" \
  "$REFERENCE_DIRECTORY" \
  "$DEVICE_STAGING_DIRECTORY"
"$PYTHON_RUNTIME" \
  "$SCRIPT_DIRECTORY/download_excel_fullworkbook_corpus.py" \
  --manifest "$SCRIPT_DIRECTORY/excel_fullworkbook_corpus.json" \
  --output-dir "$CORPUS_DIRECTORY"
cp "$CORPUS_DIRECTORY"/*.xlsx "$DEVICE_STAGING_DIRECTORY/"

PROFILE_DIRECTORY="${RUN_DIRECTORY}/libreoffice-profile"
mkdir -p "$PROFILE_DIRECTORY"
for workbook in "$CORPUS_DIRECTORY"/*.xlsx; do
  "$SOFFICE_RUNTIME" \
    -env:UserInstallation="file://$PROFILE_DIRECTORY" \
    --headless \
    --convert-to pdf \
    --outdir "$REFERENCE_DIRECTORY" \
    "$workbook" \
    >> "$RUN_DIRECTORY/libreoffice.log" 2>&1
done

xcodebuild build-for-testing \
  -workspace "$PROJECT_DIRECTORY/shortcuts_example.xcworkspace" \
  -scheme shortcuts_example \
  -destination "id=$DEVICE_UDID" \
  -derivedDataPath "$DERIVED_DATA_DIRECTORY" \
  "${TEST_SELECTION_ARGUMENTS[@]}" \
  > "$RUN_DIRECTORY/build.log" 2>&1

APP_PATH="$DERIVED_DATA_DIRECTORY/Build/Products/Debug-iphoneos/shortcuts_example.app"
xcrun devicectl device install app \
  --device "$DEVICE_UDID" \
  "$APP_PATH"
xcrun devicectl device copy to \
  --device "$DEVICE_UDID" \
  --source "$DEVICE_STAGING_DIRECTORY" \
  --destination "Documents/엑셀 문서/전체문서 검증" \
  --domain-type appDataContainer \
  --domain-identifier net.rivo.visioncraft

xcodebuild test-without-building \
  -workspace "$PROJECT_DIRECTORY/shortcuts_example.xcworkspace" \
  -scheme shortcuts_example \
  -destination "id=$DEVICE_UDID" \
  -derivedDataPath "$DERIVED_DATA_DIRECTORY" \
  "${TEST_SELECTION_ARGUMENTS[@]}" \
  -resultBundlePath "$RESULT_BUNDLE" \
  > "$RUN_DIRECTORY/test.log" 2>&1

mkdir -p "$ATTACHMENTS_DIRECTORY"
xcrun xcresulttool export attachments \
  --path "$RESULT_BUNDLE" \
  --output-path "$ATTACHMENTS_DIRECTORY"

"$PYTHON_RUNTIME" \
  "$SCRIPT_DIRECTORY/validate_excel_fullworkbook.py" \
  --manifest "$SCRIPT_DIRECTORY/excel_fullworkbook_corpus.json" \
  --corpus-dir "$CORPUS_DIRECTORY" \
  --reference-dir "$REFERENCE_DIRECTORY" \
  --attachments-dir "$ATTACHMENTS_DIRECTORY" \
  --regression-log "$RUN_DIRECTORY/test.log" \
  --output "$RUN_DIRECTORY/report.md"

print "Full-workbook report: $RUN_DIRECTORY/report.md"
