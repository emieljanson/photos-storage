#!/bin/zsh
set -euo pipefail

source_dir="${0:A:h}"
output_dir="${PHOTOS_STORAGE_BUILD_DIR:-$HOME/Library/Caches/PhotosStorage/build}"
mkdir -p "$output_dir"
build_dir="$(mktemp -d /tmp/photos-storage-build.XXXXXXXX)"
trap 'rm -rf -- "$build_dir"' EXIT
app="$build_dir/Photos Storage.app"
pane="$build_dir/PhotosStorage.prefPane"
mkdir -p "$app/Contents/MacOS" "$pane/Contents/MacOS"
cp "$source_dir/Sources/Agent/Info.plist" "$app/Contents/Info.plist"
cp "$source_dir/Sources/Pane/Info.plist" "$pane/Contents/Info.plist"
xcrun clang -Wall -Wextra -Werror -fobjc-arc -framework Foundation -framework Photos \
  "$source_dir/Sources/Agent/LibraryHelper.m" -o "$app/Contents/MacOS/FotoBudgetCacheHelper"
xcrun swiftc -swift-version 6 -warnings-as-errors \
  -framework AppKit -framework ServiceManagement -framework UniformTypeIdentifiers \
  "$source_dir/Sources/Agent/CacheClient.swift" "$source_dir/Sources/Shared/ControlProtocol.swift" \
  "$source_dir/Sources/Agent/Agent.swift" "$source_dir/Sources/Agent/main.swift" \
  -o "$app/Contents/MacOS/PhotosStorage"
xcrun clang -Wall -Wextra -Werror -fobjc-arc -bundle -framework Cocoa -framework PreferencePanes \
  "$source_dir/Sources/Pane/PhotosStoragePane.m" -o "$pane/Contents/MacOS/PhotosStoragePane"
codesign --force --sign - --options runtime --identifier nl.emieljanson.FotoBudget.CacheHelper "$app/Contents/MacOS/FotoBudgetCacheHelper"
codesign --force --sign - --options runtime "$app"
codesign --force --sign - --options runtime "$pane"
codesign --verify --deep --strict "$app"
codesign --verify --deep --strict "$pane"
for product in "Photos Storage.app" PhotosStorage.prefPane; do
  if [[ -e "$output_dir/$product" ]]; then rm -rf -- "$output_dir/$product"; fi
  cp -R "$build_dir/$product" "$output_dir/$product"
done
print "Built: $output_dir"
