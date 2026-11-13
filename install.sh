#!/bin/zsh
set -euo pipefail

source_dir="${0:A:h}"
output_dir="${PHOTOS_STORAGE_BUILD_DIR:-$HOME/Library/Caches/PhotosStorage/build}"
app="$HOME/Applications/Photos Storage.app"
pane="$HOME/Library/PreferencePanes/PhotosStorage.prefPane"
if pgrep -f '^/System/Applications/System Settings.app/Contents/MacOS/System Settings$' >/dev/null; then
  print -u2 'Quit System Settings before installing.'
  exit 1
fi
if pgrep -f '^.*/(FotoBudget.app/Contents/MacOS/FotoBudget|Photos Storage.app/Contents/MacOS/PhotosStorage)$' >/dev/null; then
  print -u2 'Stop the existing Photos Storage or FotoBudget process before installing.'
  exit 1
fi
for product in "Photos Storage.app" PhotosStorage.prefPane; do
  codesign --verify --deep --strict "$output_dir/$product"
done
mkdir -p "${app:h}" "${pane:h}"
mkdir -p "$HOME/Library/Application Support/FotoBudget"
backup_dir="$(mktemp -d "$HOME/Library/Application Support/FotoBudget/install-backup.XXXXXXXX")"
if [[ -e "$app" ]]; then mv "$app" "$backup_dir/Photos Storage.app"; fi
if [[ -e "$pane" ]]; then mv "$pane" "$backup_dir/PhotosStorage.prefPane"; fi
cp -R "$output_dir/Photos Storage.app" "$app"
cp -R "$output_dir/PhotosStorage.prefPane" "$pane"
print 'Installed Photos Storage. Open System Settings → Photos Storage.'
