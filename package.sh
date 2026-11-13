#!/bin/zsh
set -euo pipefail

output_dir="${PHOTOS_STORAGE_BUILD_DIR:-$HOME/Library/Caches/PhotosStorage/build}"
app="$output_dir/Photos Storage.app"
codesign --verify --deep --strict "$app"
image_dir="$(mktemp -d /tmp/photos-storage-image.XXXXXXXX)"
trap 'rm -rf -- "$image_dir"' EXIT
ditto "$app" "$image_dir/Photos Storage.app"
ln -s /Applications "$image_dir/Applications"
cat > "$image_dir/Start Here.txt" <<'TEXT'
Photos Storage

1. Drag Photos Storage to Applications.
2. Open Photos Storage from Applications.
3. Follow the short setup, then choose Open System Settings.

Your controls live in System Settings > Photos Storage.
Opening the app again takes you back there. No menu bar icon is added.

Experimental preview: cleanup supports only macOS 27.2, build 26B123.
The storage setting is a target, not a hard quota.
TEXT
image="$output_dir/Photos Storage.dmg"
hdiutil create -volname 'Photos Storage' -srcfolder "$image_dir" -format UDZO -ov "$image"
if [[ -n "${PHOTOS_STORAGE_SIGN_IDENTITY:-}" && "$PHOTOS_STORAGE_SIGN_IDENTITY" != '-' ]]; then
  codesign --force --sign "$PHOTOS_STORAGE_SIGN_IDENTITY" --timestamp \
    --identifier nl.emieljanson.PhotosStorage.DiskImage "$image"
fi
print "Created: $image"
