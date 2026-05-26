#!/usr/bin/env bash
# 构建 Easy Paste beta 版 .app 包并打包成 zip。
# 用法：./scripts/build_app.sh
# 输出：dist/EasyPaste.app  +  dist/EasyPaste-beta.zip

set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="EasyPaste"
DISPLAY_NAME="Easy Paste"
BUNDLE_ID="com.easypaste.app"
VERSION="0.1.0-beta"
BUILD_NUMBER="$(date +%Y%m%d%H%M)"
MIN_MACOS_VERSION="13.0"

DIST="dist"
APP_DIR="$DIST/$APP_NAME.app"

echo "==> 清理旧产物"
rm -rf "$APP_DIR" "$DIST/$APP_NAME-beta.zip"

echo "==> Release 编译"
swift build -c release --arch arm64 --arch x86_64 2>/dev/null || swift build -c release

# 找到产物路径（universal 走 apple/ 子目录，单架构走 <arch>/release/）
BIN=""
for cand in \
  ".build/apple/Products/Release/$APP_NAME" \
  ".build/release/$APP_NAME" \
  ".build/arm64-apple-macosx/release/$APP_NAME" \
  ".build/x86_64-apple-macosx/release/$APP_NAME"; do
  if [ -x "$cand" ]; then BIN="$cand"; break; fi
done
if [ -z "$BIN" ]; then
  echo "找不到 release 二进制" >&2
  exit 1
fi
echo "==> 二进制：$BIN"

echo "==> 构造 .app bundle"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$DISPLAY_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS_VERSION</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Easy Paste 通过模拟 ⌘V 把内容粘贴回前台应用</string>
    <key>NSAccessibilityUsageDescription</key>
    <string>Easy Paste 需要辅助功能权限以便监听全局快捷键并把粘贴动作发送到前台应用</string>
</dict>
</plist>
EOF

# 简单的 PkgInfo
printf "APPL????" > "$APP_DIR/Contents/PkgInfo"

# 移除可能残留的扩展属性，避免 Gatekeeper 干扰
xattr -cr "$APP_DIR" 2>/dev/null || true

# 优先用稳定的本机 Apple Development 证书签名。
# ad-hoc 签名每次重打包都会改变代码身份，macOS 辅助功能/TCC 可能要求反复重新授权。
SIGN_IDENTITY="${EASYPASTE_CODESIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
    | head -1)"
fi

if [ -n "$SIGN_IDENTITY" ]; then
  echo "==> 签名：$SIGN_IDENTITY"
  codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"
else
  echo "==> Ad-hoc 签名（未找到本机代码签名证书）"
  codesign --force --deep --sign - "$APP_DIR" 2>&1 | tail -3 || true
fi

echo "==> 打 zip"
( cd "$DIST" && zip -qr "$APP_NAME-beta.zip" "$APP_NAME.app" )

echo
echo "完成 ✓"
echo "  - $APP_DIR"
echo "  - $DIST/$APP_NAME-beta.zip"
echo
echo "使用方法："
echo "  1) open $DIST/  ，把 $APP_NAME.app 拖到 /Applications"
echo "  2) 首次运行右键 → 打开（绕过 Gatekeeper 提示）"
echo "  3) 系统设置 → 隐私与安全 → 辅助功能，给 $DISPLAY_NAME 打勾"
echo "  4) ⌘⇧V 呼出面板"
