#!/bin/zsh
set -euo pipefail

source_dir="${0:A:h}"
source "$source_dir/scripts/sparkle.sh"
output_dir="${PHOTOS_STORAGE_BUILD_DIR:-$HOME/Library/Caches/PhotosStorage/build}"
sign_identity="${PHOTOS_STORAGE_SIGN_IDENTITY:--}"
sign_options=(--force --sign "$sign_identity" --options runtime)
if [[ "$sign_identity" != '-' ]]; then sign_options+=(--timestamp); fi
mkdir -p "$output_dir"
build_dir="$(mktemp -d /tmp/photos-storage-build.XXXXXXXX)"
trap 'rm -rf -- "$build_dir"' EXIT
app="$build_dir/Photos Storage.app"
pane="$build_dir/PhotosStorage.prefPane"
mkdir -p "$app/Contents/MacOS" "$pane/Contents/MacOS" "$pane/Contents/Resources" "$app/Contents/Frameworks" "$app/Contents/Resources"
cp "$source_dir/Sources/Agent/Info.plist" "$app/Contents/Info.plist"
cp "$source_dir/Sources/Pane/Info.plist" "$pane/Contents/Info.plist"
iconset="$build_dir/PhotosStorage.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$source_dir/Resources/AppIcon.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  retina_size=$((size * 2))
  sips -z "$retina_size" "$retina_size" "$source_dir/Resources/AppIcon.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/PhotosStorage.icns"
cp "$app/Contents/Resources/PhotosStorage.icns" "$pane/Contents/Resources/PhotosStorage.icns"
ditto "$sparkle_dir/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
cp "$sparkle_dir/LICENSE" "$app/Contents/Resources/Sparkle-LICENSE.txt"
xcrun clang -Wall -Wextra -Werror -fobjc-arc -framework Foundation -framework Photos \
  "$source_dir/Sources/Agent/LibraryHelper.m" -o "$app/Contents/MacOS/FotoBudgetCacheHelper"
xcrun swiftc -swift-version 6 -warnings-as-errors \
  -framework AppKit -framework SwiftUI -framework ServiceManagement -framework UniformTypeIdentifiers \
  -F "$sparkle_dir" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  "$source_dir/Sources/Agent/CacheClient.swift" "$source_dir/Sources/Shared/ControlProtocol.swift" \
  "$source_dir/Sources/Agent/SetupSupport.swift" "$source_dir/Sources/Agent/Onboarding.swift" \
  "$source_dir/Sources/Agent/AppUpdates.swift" \
  "$source_dir/Sources/Agent/Agent.swift" "$source_dir/Sources/Agent/main.swift" \
  -o "$app/Contents/MacOS/PhotosStorage"
xcrun clang -Wall -Wextra -Werror -fobjc-arc -bundle -framework Cocoa -framework PreferencePanes \
  "$source_dir/Sources/Pane/PhotosStoragePane.m" -o "$pane/Contents/MacOS/PhotosStoragePane"
codesign "${sign_options[@]}" --identifier nl.emieljanson.FotoBudget.CacheHelper "$app/Contents/MacOS/FotoBudgetCacheHelper"
codesign "${sign_options[@]}" "$pane"
sparkle_framework="$app/Contents/Frameworks/Sparkle.framework"
for code in Versions/B/Autoupdate Versions/B/Updater.app Versions/B/XPCServices/Installer.xpc Versions/B/XPCServices/Downloader.xpc; do
  codesign "${sign_options[@]}" --preserve-metadata=entitlements "$sparkle_framework/$code"
done
codesign "${sign_options[@]}" "$sparkle_framework"
mkdir -p "$app/Contents/PlugIns"
ditto "$pane" "$app/Contents/PlugIns/PhotosStorage.prefPane"
codesign "${sign_options[@]}" "$app"
codesign --verify --deep --strict "$app"
codesign --verify --deep --strict "$pane"
for product in "Photos Storage.app" PhotosStorage.prefPane; do
  if [[ -e "$output_dir/$product" ]]; then rm -rf -- "$output_dir/$product"; fi
  cp -R "$build_dir/$product" "$output_dir/$product"
done
print "Built: $output_dir"
