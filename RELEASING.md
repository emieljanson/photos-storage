# Releasing Photos Storage

Requires a Mac with full Xcode, an Apple Developer account signed into Xcode,
a valid Developer ID Application certificate with its private key, and the
Sparkle Ed25519 signing key stored in Keychain under account `photos-storage`.
Never export signing secrets into this repository.

1. Update the marketing version and increase `CFBundleVersion` in both
   `Sources/Agent/Info.plist` and `Sources/Pane/Info.plist`.
2. Update `RELEASE_NOTES.md`. Keep the supported macOS build explicit; a new
   OS build needs separate engine validation.
3. Run `zsh tests/run.sh` and the signed updater integration test.
4. Set the signing identity, team, and a **new** build directory:

   ```sh
   export PHOTOS_STORAGE_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'
   export PHOTOS_STORAGE_TEAM_ID='TEAMID'
   export PHOTOS_STORAGE_BUILD_DIR="$HOME/Library/Caches/PhotosStorage/release-VERSION"
   zsh release.sh submit
   ```

   This builds and signs the app, constructs an Xcode archive, and submits it
   using the existing Xcode account. Upload success alone does not prove Apple
   has accepted the app. Updated Apple agreements must be accepted by the
   account holder before Apple permits submission.
5. After Apple's processing completes, run `zsh release.sh package`. If the
   notarized export is not ready, wait and retry this step without rebuilding
   or resubmitting. It exports the exact app Xcode submitted, checks its
   stapled ticket and Gatekeeper acceptance, creates a ZIP, and signs the
   appcast. Do not package the original pre-export app: Xcode re-signs it.
6. Inspect the ZIP, English notes, checksum, and signed `release/appcast.xml`.
   The private update key stays in Keychain. Do not edit a signed appcast;
   regenerate it with Sparkle's `generate_appcast` if anything changes.
7. Create a GitHub draft prerelease for the exact source commit. Upload the ZIP
   and `SHA256SUMS.txt` with `gh release upload`. Publish the release, then copy
   its generated appcast to the repository root and push it to `main`.
   Keep old feed entries when preparing future releases. The release script
   copies the current feed before generating new entries.
8. Fetch the public asset and feed, verify their signatures and checksum, and
   test **Check for Updates…** from the previous signed installation. Check
   the installed version, background relaunch, retained permissions, and
   settings-pane refresh after System Settings closes.

Only call the release ready once these checks pass. Keep a failed release in
draft and leave the live feed pointing at the previous verified version.
