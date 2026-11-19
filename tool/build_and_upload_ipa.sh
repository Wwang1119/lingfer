#!/bin/sh
set -eu

PROXY_URL="${DEEPSEEK_PROXY_URL:?Set DEEPSEEK_PROXY_URL}"
APP_SECRET_VALUE="${APP_SECRET:-}"

if [ -z "$APP_SECRET_VALUE" ]; then
  echo "缺少 APP_SECRET。请先导出环境变量，例如：" >&2
  echo "export APP_SECRET='你的暗号'" >&2
  exit 1
fi

./tool/export_ipa.sh
./tool/upload_ipa.sh
