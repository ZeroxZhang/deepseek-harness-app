#!/usr/bin/env bash
# Build the local DeepSeek Harness macOS app.
#
# Two modes:
#   normal   — the app launches the harness from this repo checkout (dev use).
#   portable — the harness code AND a bundled node binary are copied inside the
#              app bundle, so the whole thing can be zipped and sent to another
#              Mac (Apple Silicon, macOS 14+). Set PORTABLE=1.
#
# The app is ad-hoc signed only (no certificate, no notarization).
#
# Overridable via environment:
#   APP_NAME    display name           (default: DeepSeek Harness)
#   PORT        server port            (default: 3080)
#   BUNDLE_ID   CFBundleIdentifier     (default: com.deepseek-ai.harness.local)
#   VERSION     CFBundleShortVersion   (default: 0.1.0)
#   NODE_PATH   node binary            (default: auto-detected)
#   INSTALL_DIR                        (default: ~/Applications)
#   NO_INSTALL  1 to skip installing   (default: unset)
#   PORTABLE    1 to bundle harness + node into the app (default: 0)
#   ZIP         1 to also produce a shareable zip in scripts/macos-app/dist (default: 0)
#   DMG         1 to also produce a shareable dmg in scripts/macos-app/dist (default: 0)

set -euo pipefail

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TOOLS_DIR/../.." && pwd)"

APP_NAME="${APP_NAME:-DeepSeek Harness}"
PORT="${PORT:-3080}"
BUNDLE_ID="${BUNDLE_ID:-com.deepseek-ai.harness.local}"
VERSION="${VERSION:-0.1.0}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
NO_INSTALL="${NO_INSTALL:-0}"
PORTABLE="${PORTABLE:-0}"
ZIP="${ZIP:-0}"
DMG="${DMG:-0}"
EXECUTABLE_NAME="DeepSeekHarness"

BUILD_DIR="$TOOLS_DIR/build"
MODULE_CACHE="$BUILD_DIR/ModuleCache"
DIST_DIR="$TOOLS_DIR/dist"
PORTABLE_STAGE="$BUILD_DIR/portable-stage"
APP="$BUILD_DIR/$APP_NAME.app"

if [[ "$PORTABLE" == "1" ]]; then
  # A portable app must not replace the local repo-based one.
  NO_INSTALL=1
fi
if [[ ("$ZIP" == "1" || "$DMG" == "1") && "$PORTABLE" != "1" ]]; then
  echo "error: ZIP/DMG require PORTABLE=1 — a repo-bound app would not run on another Mac" >&2
  exit 1
fi

# ---- locate node ----
find_node() {
  if [[ -n "${NODE_PATH:-}" && -x "$NODE_PATH" ]]; then
    printf '%s' "$NODE_PATH"
    return
  fi
  if command -v node >/dev/null 2>&1; then
    command -v node
    return
  fi
  local candidates=(
    "$HOME"/.nvm/versions/node/*/bin/node
    /opt/homebrew/bin/node
    /usr/local/bin/node
  )
  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]]; then
      printf '%s' "$candidate"
      return
    fi
  done
  echo "error: node not found — set NODE_PATH" >&2
  exit 1
}
NODE_BIN="$(find_node)"
REAL_NODE="$("$NODE_BIN" -p 'process.execPath')"
echo "node:   $REAL_NODE"
echo "app:    $APP_NAME (port $PORT, bundle $BUNDLE_ID, portable=$PORTABLE)"
echo "root:   $REPO_ROOT"

# ---- portable payload (built once, reused across builds) ----
if [[ "$PORTABLE" == "1" && ! -d "$PORTABLE_STAGE/harness" ]]; then
  echo "bundling harness into portable stage…"
  rm -rf "$PORTABLE_STAGE"
  mkdir -p "$PORTABLE_STAGE"
  # -c clones on APFS (fast, copy-on-write); the stage is then pruned in place.
  cp -Rc "$REPO_ROOT" "$PORTABLE_STAGE/harness"
  # Strip what the runtime never needs. Keep node_modules, apps, packages,
  # vendor, native — and examples/website/python, which workspace symlinks
  # under node_modules point to (dangling links break codesign verification).
  for junk in .git scripts docs .github .agents .claude; do
    rm -rf "$PORTABLE_STAGE/harness/$junk"
  done
  find "$PORTABLE_STAGE/harness" \
    \( -name "*.tsbuildinfo" -o -name ".env" -o -name ".env.*" -o -name ".DS_Store" \) -delete
  mkdir -p "$PORTABLE_STAGE/node"
  cp -c "$REAL_NODE" "$PORTABLE_STAGE/node/node"
  chmod +x "$PORTABLE_STAGE/node/node"
  echo "stage: harness $(du -sh "$PORTABLE_STAGE/harness" | cut -f1), node $(du -sh "$PORTABLE_STAGE/node" | cut -f1)"
fi

# ---- assemble skeleton ----
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ "$PORTABLE" == "1" ]]; then
  echo "copying portable payload into the app…"
  cp -Rc "$PORTABLE_STAGE/harness" "$APP/Contents/Resources/harness"
  cp -Rc "$PORTABLE_STAGE/node" "$APP/Contents/Resources/node"
fi

# ---- generated config ----
if [[ "$PORTABLE" == "1" ]]; then
  PORTABLE_BOOL="true"
else
  PORTABLE_BOOL="false"
fi
cat > "$BUILD_DIR/GeneratedConfig.swift" <<SWIFT
import Foundation

/// Values injected by build-app.sh; rebuild the app to change them.
enum AppConfig {
    static let appName = "$APP_NAME"
    static let bundleId = "$BUNDLE_ID"
    static let version = "$VERSION"
    static let nodePath = "$REAL_NODE"
    static let harnessRoot = "$REPO_ROOT"
    static let port = "$PORT"
    static let portable = $PORTABLE_BOOL

    /// Harness checkout root. Portable builds resolve it inside the app bundle
    /// at runtime, so the app keeps working wherever the bundle is moved
    /// (including macOS app translocation on other machines).
    static var resolvedHarnessRoot: String {
        if portable {
            return Bundle.main.resourceURL!.appendingPathComponent("harness").path
        }
        return harnessRoot
    }

    /// Node binary; portable builds use the bundled copy.
    static var resolvedNodePath: String {
        if portable {
            return Bundle.main.resourceURL!.appendingPathComponent("node/node").path
        }
        return nodePath
    }
}
SWIFT

# ---- compile the app binary ----
echo "compiling…"
swiftc -O -swift-version 5 -target arm64-apple-macosx14.0 \
  -module-cache-path "$MODULE_CACHE" \
  "$TOOLS_DIR/Sources/main.swift" \
  "$TOOLS_DIR/Sources/AppDelegate.swift" \
  "$TOOLS_DIR/Sources/ServerController.swift" \
  "$TOOLS_DIR/Sources/AppLog.swift" \
  "$BUILD_DIR/GeneratedConfig.swift" \
  -o "$APP/Contents/MacOS/$EXECUTABLE_NAME"

# ---- icon ----
echo "rendering icon…"
swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macosx14.0 \
  -module-cache-path "$MODULE_CACHE" \
  "$TOOLS_DIR/IconTool/icon-main.swift" \
  -o "$BUILD_DIR/icon-gen"
"$BUILD_DIR/icon-gen" \
  "$REPO_ROOT/apps/web/public/favicon.svg" \
  "$APP/Contents/Resources/AppIcon.icns" \
  "$BUILD_DIR/icon-preview.png"

# ---- Info.plist ----
sed -e "s|%%APP_NAME%%|$APP_NAME|g" \
    -e "s|%%BUNDLE_ID%%|$BUNDLE_ID|g" \
    -e "s|%%VERSION%%|$VERSION|g" \
    -e "s|%%EXECUTABLE_NAME%%|$EXECUTABLE_NAME|g" \
    "$TOOLS_DIR/Resources/Info.plist.template" > "$APP/Contents/Info.plist"

# ---- ad-hoc sign (required on Apple Silicon; no certificate involved) ----
echo "signing (sealing resources takes a while for portable builds)…"
xattr -cr "$APP" 2>/dev/null || true
codesign --force --deep -s - "$APP" >/dev/null
if codesign --verify --deep --strict "$APP" >/dev/null 2>&1; then
  echo "sign:   ad-hoc, verified"
else
  echo "warning: codesign verification failed" >&2
fi

echo "built: $APP"

# ---- install (normal mode only) ----
if [[ "$NO_INSTALL" != "1" ]]; then
  mkdir -p "$INSTALL_DIR"
  rm -rf "$INSTALL_DIR/$APP_NAME.app"
  cp -R "$APP" "$INSTALL_DIR/"
  codesign --force -s - "$INSTALL_DIR/$APP_NAME.app" >/dev/null
  echo "installed: $INSTALL_DIR/$APP_NAME.app"
fi

# ---- shareable packages ----
if [[ "$ZIP" == "1" || "$DMG" == "1" ]]; then
  mkdir -p "$DIST_DIR"
  NOTES_FILE="$DIST_DIR/使用说明.txt"
  cat > "$NOTES_FILE" <<'TXT'
DeepSeek Harness（macOS，Apple Silicon 专用）

一、安装
1. 把「DeepSeek Harness.app」拖到「应用程序」文件夹。
2. 首次打开：在 app 上点右键 →「打开」，再点「打开」。
   如果系统没有「打开」按钮：系统设置 → 隐私与安全性 → 拉到最下面 →「仍要打开」。

二、使用
- 双击启动后，app 会在本机后台启动服务，约 10~30 秒后窗口显示界面，请耐心等待。
- 首次使用需要在界面里配置你自己的 DeepSeek API Key（引导页或设置）。
- 所有数据只保存在你自己电脑的 ~/.dsh 目录，不会上传。

三、常见问题
- 一直停在"正在启动"：查看 ~/Library/Logs/DeepSeekHarness/ 下的日志，或退出后重新打开。
- 仅支持 Apple Silicon（M1/M2/M3/M4 芯片）的 Mac，macOS 14 及以上。
TXT
fi

if [[ "$ZIP" == "1" ]]; then
  ZIP_STAGE="$DIST_DIR/DeepSeek-Harness-macOS-arm64"
  rm -rf "$ZIP_STAGE" "$DIST_DIR/DeepSeek-Harness-macOS-arm64.zip"
  mkdir -p "$ZIP_STAGE"
  cp -Rc "$APP" "$ZIP_STAGE/"
  cp -c "$NOTES_FILE" "$ZIP_STAGE/"
  echo "zipping…"
  (cd "$DIST_DIR" && ditto -c -k --keepParent "DeepSeek-Harness-macOS-arm64" "DeepSeek-Harness-macOS-arm64.zip")
  echo "zip: $DIST_DIR/DeepSeek-Harness-macOS-arm64.zip ($(du -sh "$DIST_DIR/DeepSeek-Harness-macOS-arm64.zip" | cut -f1))"
fi

if [[ "$DMG" == "1" ]]; then
  DMG_STAGE="$DIST_DIR/DeepSeek-Harness-macOS-arm64-dmg"
  rm -rf "$DMG_STAGE"
  mkdir -p "$DMG_STAGE"
  cp -Rc "$APP" "$DMG_STAGE/DeepSeek Harness.app"
  cp -c "$NOTES_FILE" "$DMG_STAGE/"
  ln -sfn /Applications "$DMG_STAGE/应用程序"
  echo "creating dmg…"
  rm -f "$DIST_DIR/DeepSeek-Harness-macOS-arm64.dmg"
  hdiutil create -volname "DeepSeek Harness" -srcfolder "$DMG_STAGE" -ov -format UDZO \
    "$DIST_DIR/DeepSeek-Harness-macOS-arm64.dmg" >/dev/null
  echo "dmg: $DIST_DIR/DeepSeek-Harness-macOS-arm64.dmg ($(du -sh "$DIST_DIR/DeepSeek-Harness-macOS-arm64.dmg" | cut -f1))"
fi

echo "done."
