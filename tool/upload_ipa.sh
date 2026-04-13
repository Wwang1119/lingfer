#!/bin/sh
set -eu

KEY_ID="${APP_STORE_CONNECT_KEY_ID:-3RQARU5L3G}"
ISSUER_ID="${APP_STORE_CONNECT_ISSUER_ID:-7c6bdc98-9222-4f8e-b45d-f4bca56946d9}"
P8_SOURCE="${APP_STORE_CONNECT_P8_PATH:-/Users/wang/keys/AuthKey_3RQARU5L3G.p8}"

if [ "${1:-}" != "" ]; then
  IPA_PATH="$1"
else
  IPA_PATH="$(find build/ios/ipa -maxdepth 1 -type f -name '*.ipa' | head -n 1)"
fi

if [ -z "$IPA_PATH" ]; then
  echo "未找到 IPA 文件。请先执行 flutter build ipa。" >&2
  exit 1
fi

if [ ! -f "$IPA_PATH" ]; then
  echo "IPA 文件不存在：$IPA_PATH" >&2
  exit 1
fi

if [ ! -f "$P8_SOURCE" ]; then
  echo "API 私钥文件不存在：$P8_SOURCE" >&2
  exit 1
fi

PRIVATE_KEY_DIR="$HOME/.appstoreconnect/private_keys"
PRIVATE_KEY_TARGET="$PRIVATE_KEY_DIR/AuthKey_${KEY_ID}.p8"

mkdir -p "$PRIVATE_KEY_DIR"
cp "$P8_SOURCE" "$PRIVATE_KEY_TARGET"
chmod 600 "$PRIVATE_KEY_TARGET"

echo "准备上传：$IPA_PATH"
echo "Key ID: $KEY_ID"
echo "Issuer ID: $ISSUER_ID"

xcrun altool \
  --upload-app \
  --type ios \
  --file "$IPA_PATH" \
  --apiKey "$KEY_ID" \
  --apiIssuer "$ISSUER_ID"
