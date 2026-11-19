#!/bin/sh
set -eu

PROXY_URL="${DEEPSEEK_PROXY_URL:?Set DEEPSEEK_PROXY_URL}"
APP_SECRET_VALUE="${APP_SECRET:-}"
ARCHIVE_PATH="${ARCHIVE_PATH:-build/ios/archive/Runner.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-build/ios/ipa}"
EXPORT_OPTIONS_PATH="${EXPORT_OPTIONS_PATH:-/tmp/lingfer_export_options.plist}"

if [ -z "$APP_SECRET_VALUE" ]; then
  echo "缺少 APP_SECRET。请先导出环境变量，例如：" >&2
  echo "export APP_SECRET='你的暗号'" >&2
  exit 1
fi

mkdir -p "$(dirname "$ARCHIVE_PATH")" "$EXPORT_PATH"

flutter build ios --release --config-only \
  --dart-define=DEEPSEEK_PROXY_URL="$PROXY_URL" \
  --dart-define=APP_SECRET="$APP_SECRET_VALUE"

xcodebuild \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=iOS" \
  archive

./tool/fix_ios_archive_symbols.sh "$ARCHIVE_PATH"

cat > "$EXPORT_OPTIONS_PATH" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store-connect</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>8MRN4PZDSG</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>uploadSymbols</key>
  <true/>
</dict>
</plist>
EOF

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PATH" \
  -allowProvisioningUpdates

echo "IPA 已导出到：$EXPORT_PATH"
