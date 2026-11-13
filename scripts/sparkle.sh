#!/bin/zsh

sparkle_version='2.10.1'
sparkle_sha256='1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27'
sparkle_dir="$HOME/Library/Caches/PhotosStorage/Sparkle-$sparkle_version"
sparkle_archive="$sparkle_dir/Sparkle-$sparkle_version.tar.xz"
mkdir -p "$sparkle_dir"
if [[ ! -f "$sparkle_archive" ]]; then
  curl --fail --location --silent --show-error \
    "https://github.com/sparkle-project/Sparkle/releases/download/$sparkle_version/Sparkle-$sparkle_version.tar.xz" \
    --output "$sparkle_archive.download"
  mv "$sparkle_archive.download" "$sparkle_archive"
fi
actual_sha256="$(shasum -a 256 "$sparkle_archive" | cut -d ' ' -f 1)"
if [[ "$actual_sha256" != "$sparkle_sha256" ]]; then
  print -u2 'Sparkle download failed its integrity check.'
  return 1
fi
if [[ ! -d "$sparkle_dir/Sparkle.framework" ]]; then
  tar -xf "$sparkle_archive" -C "$sparkle_dir"
fi
