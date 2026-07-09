#!/bin/bash
set -e

APP_NAME="TokenHub"
APP_BUNDLE="${APP_NAME}.app"
BUILD_DIR="$(cd "$(dirname "$0")" && pwd)"

SOURCES=(
    "Sources/main.swift"
    "Sources/Preferences.swift"
    "Sources/UsageFetcher.swift"
    "Sources/CodexUsageReader.swift"
    "Sources/UsageViewModel.swift"
    "Sources/TokenHubView.swift"
    "Sources/LoginWindowController.swift"
    "Sources/PreferencesWindowController.swift"
    "Sources/AppDelegate.swift"
)

cd "$BUILD_DIR"

echo "🔨 ビルド中..."

swiftc "${SOURCES[@]}" \
    -framework AppKit \
    -framework Foundation \
    -framework WebKit \
    -framework SwiftUI \
    -O \
    -o "$APP_NAME"

echo "📦 アプリバンドル作成中..."

rm -rf "$APP_BUNDLE"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "$APP_NAME" "${APP_BUNDLE}/Contents/MacOS/"
cp "Info.plist" "${APP_BUNDLE}/Contents/"
rm -f "$APP_NAME"

echo ""
echo "✅ ビルド完了: ${BUILD_DIR}/${APP_BUNDLE}"
echo ""
echo "起動方法:"
echo "  open ${APP_BUNDLE}"
echo ""
echo "アプリケーションフォルダへインストール:"
echo "  cp -r ${APP_BUNDLE} /Applications/"
echo ""
echo "ログイン時に自動起動させるには:"
echo "  システム設定 → 一般 → ログイン項目 → ${APP_NAME} を追加"
