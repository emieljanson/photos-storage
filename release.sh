#!/bin/zsh
set -euo pipefail

source_dir="${0:A:h}"
output_dir="${PHOTOS_STORAGE_BUILD_DIR:-$HOME/Library/Caches/PhotosStorage/distribution}"
archive="$output_dir/PhotosStorage.xcarchive"
export_dir="$output_dir/notarized"
assets="$output_dir/release"

case "${1:-}" in
  submit)
    : "${PHOTOS_STORAGE_TEAM_ID:?Set the Apple Developer team ID}"
    : "${PHOTOS_STORAGE_SIGN_IDENTITY:?Set a Developer ID Application identity}"
    [[ "$PHOTOS_STORAGE_SIGN_IDENTITY" == 'Developer ID Application:'* ]] || { print -u2 'Developer ID Application signing is required.'; exit 1; }
    export PHOTOS_STORAGE_BUILD_DIR="$output_dir"
    zsh "$source_dir/build.sh"
    export PHOTOS_STORAGE_RELEASE_ARCHIVE="$archive"
    python3 - <<'PY'
import datetime
import os
import plistlib
import subprocess
from pathlib import Path

archive = Path(os.environ['PHOTOS_STORAGE_RELEASE_ARCHIVE'])
app = Path(os.environ['PHOTOS_STORAGE_BUILD_DIR']) / 'Photos Storage.app'
destination = archive / 'Products/Applications/Photos Storage.app'
if destination.exists():
    raise SystemExit('Archive already exists. Use a new build directory for a new submission.')
subprocess.run(['ditto', str(app), str(destination)], check=True)
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
properties = {
    'ApplicationPath': 'Applications/Photos Storage.app',
    'CFBundleIdentifier': info['CFBundleIdentifier'],
    'CFBundleShortVersionString': info['CFBundleShortVersionString'],
    'CFBundleVersion': info['CFBundleVersion'],
    'Architectures': ['arm64'],
    'SigningIdentity': os.environ['PHOTOS_STORAGE_SIGN_IDENTITY'],
    'Team': os.environ['PHOTOS_STORAGE_TEAM_ID'],
}
(archive / 'Info.plist').write_bytes(plistlib.dumps({
    'ArchiveVersion': 2, 'CreationDate': datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None),
    'Name': 'Photos Storage', 'SchemeName': 'PhotosStorage', 'ApplicationProperties': properties,
}))
(archive.parent / 'ExportOptions.plist').write_bytes(plistlib.dumps({
    'method': 'developer-id', 'destination': 'upload', 'signingStyle': 'manual',
    'signingCertificate': 'Developer ID Application', 'teamID': os.environ['PHOTOS_STORAGE_TEAM_ID'],
    'uploadSymbols': False, 'manageAppVersionAndBuildNumber': False,
}))
PY
    xcodebuild -exportArchive -archivePath "$archive" -exportPath "$output_dir/upload" \
      -exportOptionsPlist "$output_dir/ExportOptions.plist" -allowProvisioningUpdates
    print 'Submitted to Apple. Run release.sh package after notarization completes.'
    ;;
  package)
    xcodebuild -exportNotarizedApp -archivePath "$archive" -exportPath "$export_dir"
    app="$export_dir/Photos Storage.app"
    codesign --verify --deep --strict "$app"
    xcrun stapler validate "$app"
    spctl --assess --type execute --verbose=2 "$app"
    version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
    asset="Photos-Storage-$version-arm64"
    mkdir -p "$assets"
    ditto -c -k --sequesterRsrc --keepParent "$app" "$assets/$asset.zip"
    cp "$source_dir/RELEASE_NOTES.md" "$assets/$asset.md"
    if [[ -f "$source_dir/appcast.xml" ]]; then cp "$source_dir/appcast.xml" "$assets/appcast.xml"; fi
    source "$source_dir/scripts/sparkle.sh"
    "$sparkle_dir/bin/generate_appcast" --account photos-storage --maximum-deltas 0 \
      --embed-release-notes --download-url-prefix "https://github.com/emieljanson/photos-storage/releases/download/v$version/" "$assets"
    (cd "$assets" && shasum -a 256 "$asset.zip" > SHA256SUMS.txt)
    print "Verified release files: $assets"
    ;;
  *)
    print -u2 'Usage: zsh release.sh submit | package'
    exit 1
    ;;
esac
