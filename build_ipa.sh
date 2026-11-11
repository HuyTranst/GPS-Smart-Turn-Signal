#!/bin/bash
# ==============================================================================
# Script đóng gói file IPA dành cho TrollStore (Không cần tài khoản Apple Developer)
# Chạy trực tiếp trên macOS có cài đặt Xcode
# ==============================================================================

set -e

PROJECT_NAME="GPS-Smart-Turn-Signal.xcodeproj"
SCHEME_NAME="GPSSmartTurnSignal"
APP_NAME="GPSSmartTurnSignal"
BUILD_DIR="build"
OUTPUT_IPA="GPSSmartTurnSignal.ipa"

echo "=== [1/4] Dọn dẹp bản build cũ ==="
rm -rf "$BUILD_DIR" Payload "$OUTPUT_IPA"

echo "=== [2/4] Biên dịch dự án bằng xcodebuild ==="
xcodebuild -project "$PROJECT_NAME" \
           -scheme "$SCHEME_NAME" \
           -configuration Release \
           -destination 'generic/platform=iOS' \
           -sdk iphoneos \
           -derivedDataPath "$BUILD_DIR/DerivedData" \
           CODE_SIGNING_ALLOWED=NO \
           CODE_SIGNING_REQUIRED=NO \
           CODE_SIGN_IDENTITY="" \
           PROVISIONING_PROFILE_SPECIFIER="" \
           DEVELOPMENT_TEAM="" \
           VALIDATE_PRODUCT=NO \
           clean build

echo "=== [3/4] Tìm file .app và đóng gói Payload ==="
APP_PATH=$(find "$BUILD_DIR/DerivedData" -name "$APP_NAME.app" -type d | head -n 1)

if [ -z "$APP_PATH" ]; then
    echo "Lỗi: Không tìm thấy $APP_NAME.app!"
    exit 1
fi

echo "Tìm thấy: $APP_PATH"
mkdir -p Payload
cp -r "$APP_PATH" Payload/

echo "=== [4/4] Nén thành file IPA ==="
zip -qr "$OUTPUT_IPA" Payload
rm -rf Payload

echo "=========================================================="
echo " XUẤT THÀNH CÔNG: $OUTPUT_IPA"
echo " Dung lượng: $(du -sh "$OUTPUT_IPA" | cut -f1)"
echo " Bạn có thể chuyển file này qua iPhone và cài bằng TrollStore!"
echo "=========================================================="
