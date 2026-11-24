#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DEST="/Applications/macsvn.app"
BUNDLE_ID="local.macsvn"
EXT_ID="local.macsvn.FinderSync"

cd "$ROOT"
make

rm -rf "$APP_DEST"
ditto "$ROOT/build/macsvn.app" "$APP_DEST"
xattr -cr "$APP_DEST"

# 1) 选择签名身份：优先显式指定，其次系统里可用的证书，最后 ad-hoc。
IDENTITY="${MACSVN_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  # macOS 自带 bash 3.2 没有 mapfile，用 read 逐行读。
  IDENTITY="$(security find-identity -p codesigning -v 2>/dev/null \
    | sed -n 's/.*"\(.*\)"/\1/p' | head -1)"
  if [[ -n "$IDENTITY" ]]; then
    echo "使用签名身份：$IDENTITY"
  else
    IDENTITY="-"
    echo "未找到开发证书，使用 ad-hoc 签名（访达扩展仍可登记，无需证书）。"
  fi
fi

codesign --force --sign "$IDENTITY" --entitlements "$ROOT/Config/FinderSync.entitlements" "$APP_DEST/Contents/PlugIns/FinderSync.appex"
codesign --force --sign "$IDENTITY" --entitlements "$ROOT/Config/App.entitlements" "$APP_DEST"
codesign --verify --deep --strict "$APP_DEST"

# 2) 必须先让 LaunchServices 认识宿主 App，pkd 才能把 appex 关联到它的容器里。
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -f "$APP_DEST" 2>/dev/null || true

# 3) 登记并启用扩展。
pluginkit -r "$APP_DEST/Contents/PlugIns/FinderSync.appex" 2>/dev/null || true
pluginkit -a "$APP_DEST/Contents/PlugIns/FinderSync.appex" 2>/dev/null || true
pluginkit -e use -i "$EXT_ID" 2>/dev/null || true

echo ""
echo "安装完成：$APP_DEST"
echo "自检：pluginkit -m -v -p com.apple.FinderSync | grep macsvn"

if pluginkit -m -v -p com.apple.FinderSync 2>/dev/null | grep -q "$EXT_ID"; then
  echo "扩展已登记：$EXT_ID"
  echo "接着做：系统设置 → 扩展 → 勾选「访达」，然后 killall Finder。"
else
  echo "扩展未登记。查看被拒原因："
  echo "  log show --last 2m --predicate 'process == \"pkd\"' --style compact | grep -i macsvn"
fi
