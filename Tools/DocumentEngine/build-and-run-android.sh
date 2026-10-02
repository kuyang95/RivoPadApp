#!/usr/bin/env bash
# Build the real document probe, run it in an isolated Android tmp directory,
# and compare every reported result (including all formula values) with macOS.
set -euo pipefail
rivo_root=$(cd "$(dirname "$0")/../.." && pwd)
: "${RIVO_SWIFT_BIN:?Set RIVO_SWIFT_BIN to the matching Swift toolchain bin directory}"
: "${RIVO_SWIFT_SDKS_PATH:?Set RIVO_SWIFT_SDKS_PATH to the Android artifactbundle parent directory}"
: "${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME to the configured NDK directory}"
rivo_adb=${RIVO_ADB:-adb}
rivo_host_swift=${RIVO_HOST_SWIFT:-swift}
rivo_build=${RIVO_ANDROID_BUILD_DIR:-"$rivo_root/Tools/DocumentEngine/AndroidProbe/.build/android"}
rivo_probe="$rivo_root/Tools/DocumentEngine/AndroidProbe"
rivo_fixtures="$rivo_root/Packages/RivoDocumentEngine/Tests/RivoDocumentEngineTests/Fixtures"
rivo_target=aarch64-unknown-linux-android34
rivo_remote="/data/local/tmp/rivo-engine-probe-$(date +%Y%m%d-%H%M%S)-$$"
rivo_adb_args=()
if [[ -n "${RIVO_ANDROID_SERIAL:-}" ]]; then rivo_adb_args=(-s "$RIVO_ANDROID_SERIAL"); fi
rivo_cxx="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so"
[[ -f "$rivo_cxx" ]] || { echo "Android probe currently expects a macOS NDK and arm64 Android device." >&2; exit 1; }
mkdir -p "$rivo_build"
"$rivo_host_swift" run --package-path "$rivo_probe" RivoEngineProbe "$rivo_fixtures" \
    > "$rivo_build/host-result.json"
"$RIVO_SWIFT_BIN/swift" build --package-path "$rivo_probe" \
    --swift-sdks-path "$RIVO_SWIFT_SDKS_PATH" --swift-sdk "$rivo_target" \
    --scratch-path "$rivo_build" --static-swift-stdlib
rivo_binary="$rivo_build/$rivo_target/debug/RivoEngineProbe"
"$rivo_adb" "${rivo_adb_args[@]}" shell mkdir -p "$rivo_remote"
"$rivo_adb" "${rivo_adb_args[@]}" push "$rivo_binary" "$rivo_remote/RivoEngineProbe"
"$rivo_adb" "${rivo_adb_args[@]}" push "$rivo_cxx" "$rivo_remote/libc++_shared.so"
"$rivo_adb" "${rivo_adb_args[@]}" push "$rivo_fixtures" "$rivo_remote/Fixtures"
"$rivo_adb" "${rivo_adb_args[@]}" shell chmod 755 "$rivo_remote/RivoEngineProbe"
"$rivo_adb" "${rivo_adb_args[@]}" shell \
    "LD_LIBRARY_PATH=$rivo_remote $rivo_remote/RivoEngineProbe $rivo_remote/Fixtures" \
    > "$rivo_build/android-result.json"
# Compare full values, not counts; retain and disclose libm rounding differences.
python3 "$rivo_root/Tools/DocumentEngine/compare-probe-results.py" \
    "$rivo_build/host-result.json" "$rivo_build/android-result.json" \
    > "$rivo_build/comparison.json"
cat "$rivo_build/comparison.json"
echo "PASS: document processing checks passed; review comparison.json for display and rounding differences. Reports: $rivo_build"
# Preserve remote artifacts for inspection; only this newly created directory was used.
