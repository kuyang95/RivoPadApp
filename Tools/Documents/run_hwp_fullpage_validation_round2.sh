#!/bin/zsh
set -euo pipefail

SCRIPT_DIRECTORY="${0:A:h}"
HWP_CORPUS_MANIFEST="$SCRIPT_DIRECTORY/hwp_fullpage_corpus_round2.json" \
HWP_DEVICE_FOLDER_NAME="추가 전체페이지 검증" \
HWP_TEST_IDENTIFIER="shortcuts_exampleTests/LegacyDocumentAttachmentTests/testOfficialHWPFullPageCorpusRound2RendersAllPages" \
exec "$SCRIPT_DIRECTORY/run_hwp_fullpage_validation.sh" "$@"
