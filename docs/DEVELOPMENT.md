# Development and implementation

[Back to Photos Storage](../README.md)

## Build and package

Run these commands from the repository root.

Requires Xcode command-line tools with a Swift 6 compiler and a macOS SDK.

```sh
zsh tests/run.sh
zsh build.sh
zsh package.sh
```

This creates **Photos Storage.dmg** in the build directory. The app includes
its settings pane, so a fresh install needs no Terminal commands. Developers
can still use the direct installer:

Quit System Settings and any previous instance of Photos Storage or FotoBudget,
then install:

```sh
zsh install.sh
```

Turn on **Optimize storage**. **Options…** contains **Start at login**, the
last check and its result, **Check Now**, and **Open Photos**. Turning
optimization off stops automatic cleanup; changing the target still applies
it manually. The most recent prefetch setting remains in effect.

Build products are written to `~/Library/Caches/PhotosStorage/build`, outside
iCloud Drive. Set `PHOTOS_STORAGE_BUILD_DIR` to override that location for both
scripts. Installed files are:

- `~/Applications/Photos Storage.app` — the background agent
- `~/Library/PreferencePanes/PhotosStorage.prefPane` — the settings pane

The build downloads the pinned Sparkle 2.10.1 SDK from its official release and
checks its SHA-256 digest. Sparkle's license is included inside the app.

Local builds use ad-hoc signatures. Set `PHOTOS_STORAGE_SIGN_IDENTITY` to a
Developer ID Application identity for both build and package scripts to sign
the app, embedded pane, helper, and local disk image with a secure timestamp.
Public releases use the notarized app export and ZIP flow described below.
Running Sparkle with hardened runtime requires a real
Developer ID signature. See [RELEASING.md](../RELEASING.md) for the verified
Xcode-account release process. No notarization credentials are stored in this repo.

To revisit setup, quit the running agent and open it with `--setup`:

```sh
open -a 'Photos Storage' --args --setup
```

## What it does

- Measures allocated files in the registered System Photo Library.
- Confirms iCloud Photos and Optimize Mac Storage using small, per-library
  settings and status files. Unknown or disabled settings block cleanup.
- Adjusts `PLPrefetchMinimumFreeDiskGB` to discourage optional prefetch above
  the target, with a minimum working-space allowance of 13 GiB.
- Asks only `com.apple.photolibraryd.cacheDelete` to release eligible local
  resources. macOS chooses the resources; the app never selects media files
  to unlink and never calls a Photos asset-deletion API.
- Rechecks safety immediately before each native cleanup request.

The app does not read the Photos database or upload photo content. These
checks are not an independent verification of every original in iCloud and
do not replace a backup. There is no reliable “only keep the last N days” API.

## Architecture

The settings pane reads a small status snapshot and sends typed commands to
the background agent through a private directory for the current account.
Only the agent holds the existing Photos access and runs the native helper.
Closing the pane or setup window does not own or stop the monitoring timer.

The local protocol rejects unknown actions, malformed values, stale requests,
symlinks, and linked command files. A temporary native-helper timeout leaves
enabled monitoring on for a later retry. Safety failures turn it off.

The original `nl.emieljanson.FotoBudget` preference domain and internal helper
identity are retained so an existing installation keeps its settings and
access. They do not create another running app.

## Tests

```sh
zsh tests/run.sh
```

The isolated tests do not open or purge a real Photos library. They cover
allocated-size accounting, iCloud/optimization guards, metadata consistency,
helper timeouts, the Objective-C-to-Swift command format, command validation,
private status storage, setup progression, silent login routing, and safe
settings-pane installation and updates. Build scripts treat compiler warnings as errors
and verify the local code signatures.

The opt-in `tests/run-update-integration.py` test uses an isolated app and a
local update server. It verifies rejection of a tampered archive, a signed
feed and payload, deferral while busy, automatic installation, and relaunch
into the new signed executable. It needs a Developer ID signing identity and
the release update key in Keychain; it never accesses a real Photos library.

For visual checks, run `zsh preview.sh`. The native preview offers demo,
worst-case, empty, permission, safety, small-volume, and stopped-agent states,
plus light, dark, and high-contrast appearances. It reads disposable fixture
snapshots and cannot start the agent or send it commands. Close the preview
before rebuilding it.

## References

- [Apple Preference Panes](https://developer.apple.com/documentation/preferencepanes)
- [Interface design decisions and Apple HIG references](../DESIGN.md)
- [Apple's System Settings compatibility explanation](https://developer.apple.com/videos/play/wwdc2022/10074/?time=294)
- [CacheDelete ABI reference in MacSpace](https://github.com/1architect/macspace-releases/blob/main/Platform/CacheDelete/CacheDelete.swift)
