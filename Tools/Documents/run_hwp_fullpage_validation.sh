#!/bin/zsh
set -euo pipefail

if [[ $# -lt 1 ]]; then
  print -u2 "usage: $0 <device-udid> [output-directory]"
  exit 64
fi

DEVICE_UDID="$1"
SCRIPT_DIRECTORY="${0:A:h}"
PROJECT_DIRECTORY="${SCRIPT_DIRECTORY:h:h}"
RUN_DIRECTORY="${2:-${PROJECT_DIRECTORY}/outputs/hwp_fullpage_validation_$(date +%Y%m%d_%H%M%S)}"
CORPUS_MANIFEST_PATH="${HWP_CORPUS_MANIFEST:-$SCRIPT_DIRECTORY/hwp_fullpage_corpus.json}"
DEVICE_FOLDER_NAME="${HWP_DEVICE_FOLDER_NAME:-전체페이지 검증}"
CORPUS_DIRECTORY="${RUN_DIRECTORY}/corpus"
DERIVED_DATA_DIRECTORY="${HWP_DERIVED_DATA_PATH:-${RUN_DIRECTORY}/DerivedData}"
RESULT_BUNDLE="${RUN_DIRECTORY}/HWPFullPage.xcresult"
ATTACHMENTS_DIRECTORY="${RUN_DIRECTORY}/attachments"
REPORT_DIRECTORY="${RUN_DIRECTORY}/visual-report"
DEVICE_STAGING_DIRECTORY="${RUN_DIRECTORY}/device-staging/$DEVICE_FOLDER_NAME"
DEFAULT_PYTHON_RUNTIME="/Users/me/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3"
PYTHON_RUNTIME="${PYTHON_RUNTIME:-$DEFAULT_PYTHON_RUNTIME}"
if [[ ! -x "$PYTHON_RUNTIME" ]]; then
  PYTHON_RUNTIME="$(command -v python3)"
fi
TEST_IDENTIFIER="${HWP_TEST_IDENTIFIER:-shortcuts_exampleTests/LegacyDocumentAttachmentTests/testOfficialHWPFullPageCorpusRendersAllPages}"

mkdir -p "$CORPUS_DIRECTORY" "$DEVICE_STAGING_DIRECTORY"
"$PYTHON_RUNTIME" \
  "$SCRIPT_DIRECTORY/download_hwp_fullpage_corpus.py" \
  --manifest "$CORPUS_MANIFEST_PATH" \
  --output-dir "$CORPUS_DIRECTORY"
cp "$CORPUS_DIRECTORY"/*.hwp "$DEVICE_STAGING_DIRECTORY/"
cp "$CORPUS_DIRECTORY"/*.pdf "$DEVICE_STAGING_DIRECTORY/"

xcodebuild build-for-testing \
  -workspace "$PROJECT_DIRECTORY/shortcuts_example.xcworkspace" \
  -scheme shortcuts_example \
  -destination "id=$DEVICE_UDID" \
  -derivedDataPath "$DERIVED_DATA_DIRECTORY" \
  -only-testing:"$TEST_IDENTIFIER" \
  | tee "$RUN_DIRECTORY/build.log"

APP_PATH="$DERIVED_DATA_DIRECTORY/Build/Products/Debug-iphoneos/shortcuts_example.app"
xcrun devicectl device install app \
  --device "$DEVICE_UDID" \
  "$APP_PATH"
xcrun devicectl device copy to \
  --device "$DEVICE_UDID" \
  --source "$DEVICE_STAGING_DIRECTORY" \
  --destination "Documents/한글 문서/$DEVICE_FOLDER_NAME" \
  --domain-type appDataContainer \
  --domain-identifier net.rivo.visioncraft

set +e
xcodebuild test-without-building \
  -workspace "$PROJECT_DIRECTORY/shortcuts_example.xcworkspace" \
  -scheme shortcuts_example \
  -destination "id=$DEVICE_UDID" \
  -derivedDataPath "$DERIVED_DATA_DIRECTORY" \
  -only-testing:"$TEST_IDENTIFIER" \
  -resultBundlePath "$RESULT_BUNDLE" \
  | tee "$RUN_DIRECTORY/test.log"
XCODE_STATUS=${pipestatus[1]}
set -e

mkdir -p "$ATTACHMENTS_DIRECTORY"
xcrun xcresulttool export attachments \
  --path "$RESULT_BUNDLE" \
  --output-path "$ATTACHMENTS_DIRECTORY"

set +e
"$PYTHON_RUNTIME" \
  "$SCRIPT_DIRECTORY/validate_hwp_fullpage_renders.py" \
  --corpus-manifest "$CORPUS_MANIFEST_PATH" \
  --corpus-dir "$CORPUS_DIRECTORY" \
  --attachments-dir "$ATTACHMENTS_DIRECTORY" \
  --output-dir "$REPORT_DIRECTORY"
COMPARE_STATUS=$?
set -e

print "Full-page report: $REPORT_DIRECTORY/report.md"
if [[ $XCODE_STATUS -ne 0 || $COMPARE_STATUS -ne 0 ]]; then
  exit 1
fi
