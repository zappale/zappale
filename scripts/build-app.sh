#!/bin/bash
# 构建 zappale.app：swift build → 组装 bundle → 签名。
# 默认 ad-hoc 签名（本地开发）；CI 中可通过环境变量注入正式身份：
#   SIGN_IDENTITY  证书 Common Name，如 "Developer ID Application: ..."（默认 "-" 即 ad-hoc）
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG"

APP_NAME="zappale"
BUNDLE_ID="dev.zappale.app"
APP_DIR="build/${APP_NAME}.app"
BIN=".build/$CONFIG/${APP_NAME}"

rm -rf build
mkdir -p "${APP_DIR}/Contents/MacOS"
cp "${BIN}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

SIGN_IDENTITY="${SIGN_IDENTITY:--}"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    # 本地 ad-hoc 签名：无需证书，无法分发
    codesign --force --sign - "${APP_DIR}"
else
    # 正式证书签名：hardened runtime + 时间戳（公证 notarization 的前置要求）
    # Team 信息已包含在证书身份内，无需另行传参
    codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "${APP_DIR}"
    codesign verify --strict "${APP_DIR}"
fi

echo "✔ 已生成 ${APP_DIR}（签名身份：${SIGN_IDENTITY}）"
