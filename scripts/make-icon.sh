#!/bin/bash
# 重新生成 Config/AppIcon.icns。设计在 tools/make-icon.swift 里。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

swift "$ROOT/tools/make-icon.swift" "$TMP/icon-1024.png" >/dev/null
ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"

for spec in "16:icon_16x16" "32:icon_16x16@2x" "32:icon_32x32" "64:icon_32x32@2x" \
            "128:icon_128x128" "256:icon_128x128@2x" "256:icon_256x256" \
            "512:icon_256x256@2x" "512:icon_512x512" "1024:icon_512x512@2x"; do
  px="${spec%%:*}"
  name="${spec##*:}"
  sips -z "$px" "$px" "$TMP/icon-1024.png" --out "$ICONSET/$name.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$ROOT/Config/AppIcon.icns"
echo "已生成 Config/AppIcon.icns"
