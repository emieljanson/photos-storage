#!/bin/zsh
set -euo pipefail
source_dir="${0:A:h}"
output_dir="$HOME/Library/Caches/PhotosStorage/ui-preview"
app="$output_dir/Photos Storage Preview.app"
mkdir -p "$app/Contents/MacOS"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>nl.emieljanson.PhotosStorage.UIPreview</string>
<key>CFBundleName</key><string>Photos Storage Preview</string>
<key>CFBundleExecutable</key><string>Preview</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
xcrun clang -Wall -Wextra -Werror -fobjc-arc -framework Cocoa -framework PreferencePanes \
  "$source_dir/tools/preview.m" -o "$app/Contents/MacOS/Preview"
open "$app"
