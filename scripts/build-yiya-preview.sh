#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
PREVIEW_ROOT="$PROJECT_ROOT/.build/yiya-preview"
PREVIEW_APP="$PREVIEW_ROOT/译芽视觉预览.app"
mkdir -p "$PREVIEW_APP/Contents/MacOS" "$PREVIEW_APP/Contents/Resources"
clang -fobjc-arc -Wall -framework Cocoa -framework QuartzCore design/yiya-reference-preview/Preview.m -o "$PREVIEW_APP/Contents/MacOS/YiyaPreview"
cp design/yiya-reference-preview/reference.png "$PREVIEW_APP/Contents/Resources/reference.png"
cp resources/ui/yiya/art/sakura-cat-v1.png "$PREVIEW_APP/Contents/Resources/sakura-cat-v1.png"
cp resources/AppIcon.icns "$PREVIEW_APP/Contents/Resources/AppIcon.icns"
cat > "$PREVIEW_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>YiyaPreview</string>
<key>CFBundleIdentifier</key><string>com.nanami.yiya.visual-preview</string>
<key>CFBundleName</key><string>译芽视觉预览</string>
<key>CFBundleDisplayName</key><string>译芽视觉预览</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
"$PREVIEW_APP/Contents/MacOS/YiyaPreview" --render "$PROJECT_ROOT/docs/design/yiya-reference-preview"
printf 'Preview built: %s\n' "$PREVIEW_APP"
