#!/usr/bin/env bash
# Switch which VisionCraftDocumentEngine source the iOS app builds against.
#
#   Tools/engine-source.sh remote         GitHub package pinned in Package.resolved (committed default)
#   Tools/engine-source.sh local [path]   Local checkout overrides the GitHub package
#   Tools/engine-source.sh status
#
# The project always declares the GitHub package. Local mode adds the checkout
# to the workspace, and Xcode then uses it instead of the remote package because
# both have the identity "visioncraftdocumentengine". Hence the checkout folder
# must be named VisionCraftDocumentEngine; any location works.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
workspace_rel="shortcuts_example.xcworkspace/contents.xcworkspacedata"
workspace="$root/$workspace_rel"
resolved_rel="shortcuts_example.xcworkspace/xcshareddata/swiftpm/Package.resolved"
resolved="$root/$resolved_rel"
# Xcode drops the engine pin while a local override is active; keep the
# remote Package.resolved here and restore it when switching back.
resolved_backup="$(git -C "$root" rev-parse --git-path engine-source-Package.resolved)"
[[ "$resolved_backup" = /* ]] || resolved_backup="$root/$resolved_backup"
default_path="$root/../../VisionCraftDocumentEngine"

local_ref() {
    python3 - "$workspace" <<'EOF'
import html, re, sys
match = re.search(r'location = "group:([^"]*VisionCraftDocumentEngine)"', open(sys.argv[1]).read())
print(html.unescape(match.group(1)) if match else "")
EOF
}

pinned() {
    python3 - "$resolved" <<'EOF'
import json, sys
for pin in json.load(open(sys.argv[1]))["pins"]:
    if pin["identity"] == "visioncraftdocumentengine":
        s = pin["state"]
        print(f'{pin["location"]} @ {s.get("version") or s.get("branch")} ({s["revision"][:8]})')
EOF
}

remove_ref() {
    python3 - "$workspace" <<'EOF'
import re, sys
path = sys.argv[1]
text = open(path).read()
text = re.sub(r'   <FileRef\n      location = "group:[^"]*VisionCraftDocumentEngine">\n   </FileRef>\n', '', text)
open(path, "w").write(text)
EOF
}

case "${1:-status}" in
local)
    target=${2:-$default_path}
    [[ -f "$target/Package.swift" ]] || { echo "No Package.swift in $target" >&2; exit 1; }
    target=$(cd "$target" && pwd)
    [[ $(basename "$target") == VisionCraftDocumentEngine ]] || {
        echo "The folder must be named VisionCraftDocumentEngine to override the GitHub package." >&2; exit 1; }
    relative=$(python3 -c 'import os, sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$target" "$root")
    if [[ -z "$(local_ref)" ]]; then cp "$resolved" "$resolved_backup"; fi
    remove_ref
    python3 - "$workspace" "$relative" <<'EOF'
import sys
from xml.sax.saxutils import escape
path, relative = sys.argv[1:]
text = open(path).read()
location = escape("group:" + relative, {'"': "&quot;"})
entry = f'   <FileRef\n      location = "{location}">\n   </FileRef>\n'
open(path, "w").write(text.replace("</Workspace>", entry + "</Workspace>"))
EOF
    # Machine-specific; keep it out of commits while local mode is on.
    git -C "$root" update-index --skip-worktree "$workspace_rel" "$resolved_rel"
    echo "local: $target"
    echo "Reopen the workspace in Xcode if it is open."
    ;;
remote)
    remove_ref
    if [[ -f "$resolved_backup" ]]; then mv "$resolved_backup" "$resolved"; fi
    git -C "$root" update-index --no-skip-worktree "$workspace_rel" "$resolved_rel"
    echo "remote: $(pinned)"
    echo "Reopen the workspace in Xcode if it is open. To take newer engine commits:"
    echo "  xcodebuild -resolvePackageDependencies -workspace shortcuts_example.xcworkspace -scheme shortcuts_example"
    echo "  (or Xcode: File > Packages > Update to Latest Package Versions), then commit Package.resolved."
    ;;
status)
    ref=$(local_ref)
    if [[ -n "$ref" ]]; then
        echo "local: $(cd "$root/$ref" 2>/dev/null && pwd || echo "$ref (missing)")"
    else
        echo "remote: $(pinned)"
    fi
    ;;
*)
    sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
