#!/bin/zsh
# Builds "mAhgic.app" into ./build (release, ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")"

APP="build/mAhgic.app"
swift build -c release --product mAhgic

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/mAhgic "$APP/Contents/MacOS/mAhgic"

ICONSET="build/AppIcon.iconset"
if [[ ! -f build/AppIcon.icns || scripts/make_icon.swift -nt build/AppIcon.icns ]]; then
    rm -rf "$ICONSET"
    swift scripts/make_icon.swift "$ICONSET"
    iconutil -c icns "$ICONSET" -o build/AppIcon.icns
    rm -rf "$ICONSET"
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>mAhgic</string>
    <key>CFBundleDisplayName</key><string>mAhgic</string>
    <key>CFBundleIdentifier</key><string>de.till.mAhgic</string>
    <key>CFBundleExecutable</key><string>mAhgic</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Till</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "Built $APP"
