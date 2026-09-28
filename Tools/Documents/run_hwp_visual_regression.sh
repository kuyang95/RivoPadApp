#!/bin/bash
# Capture reviewed pages on the connected M4, then fail on visual regressions.
set -euo pipefail
cd "$(dirname "$0")/../.."
HWP_PYTHON="${HWP_PYTHON:-python3}"
HWP_DEVICE="${HWP_DEVICE:-00008132-001A61443421801C}"
HWP_RUN="${HWP_RUN:-outputs/hwp_visual_regression_$(date +%Y%m%d_%H%M%S)}"
HWP_DERIVED_DATA="${HWP_DERIVED_DATA:-outputs/hwp_fullpage_validation_20260903_claude_dd}"
HWP_DEVELOPMENT_TEAM="${HWP_DEVELOPMENT_TEAM:-Z3TXJ872H6}"
HWP_DEPLOYMENT_TARGET="${HWP_DEPLOYMENT_TARGET:-26.2}"
mkdir -p "$HWP_RUN"
"$HWP_PYTHON" -c 'import PIL, numpy'
xcodebuild test -workspace shortcuts_example.xcworkspace -scheme shortcuts_example \
    -destination "platform=iOS,id=$HWP_DEVICE" \
    -derivedDataPath "$HWP_DERIVED_DATA" \
    -parallel-testing-enabled NO \
    -only-testing:shortcuts_exampleTests/LegacyDocumentAttachmentTests/testCoastGuardFirstFivePagesPreserveSourceLayout \
    -only-testing:shortcuts_exampleTests/LegacyDocumentAttachmentTests/testSelectedOfficialHWPReviewPages \
    -resultBundlePath "$HWP_RUN/tests.xcresult" \
    DEVELOPMENT_TEAM="$HWP_DEVELOPMENT_TEAM" CODE_SIGN_STYLE=Automatic \
    IPHONEOS_DEPLOYMENT_TARGET="$HWP_DEPLOYMENT_TARGET" > "$HWP_RUN/tests.log" 2>&1
xcrun xcresulttool export attachments --path "$HWP_RUN/tests.xcresult" --output-path "$HWP_RUN/captures"
"$HWP_PYTHON" Tools/Documents/check_hwp_visual_regression.py \
    --captures-dir "$HWP_RUN/captures" --output-dir "$HWP_RUN/comparison"
