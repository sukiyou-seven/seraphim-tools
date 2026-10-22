#!/bin/bash
# SeraphimTools 构建脚本
# 用法: ./build.sh [Debug|Release] [--no-launch]
set -e
cd "$(dirname "$0")"

CONFIG="${1:-Debug}"

xcodebuild \
    -project SeraphimTools.xcodeproj \
    -scheme SeraphimTools \
    -configuration "$CONFIG" \
    -derivedDataPath build \
    build

APP="build/Build/Products/$CONFIG/SeraphimTools.app"

if [ ! -d "$APP" ]; then
    echo "❌ 构建产物不存在: $APP"
    exit 1
fi

echo ""
echo "✅ 构建完成: $APP"

if [ "$2" != "--no-launch" ] && [ "$1" != "--no-launch" ]; then
    open "$APP"
    echo "🚀 已启动"
fi
