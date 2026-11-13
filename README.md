# Photos Storage

Set a local storage target for Apple Photos in **System Settings**.

See how much space Photos uses and choose a storage target from a compact
menu. Use **Custom…** for another amount. A background agent checks every five
minutes, including when System Settings is closed. There is no menu bar or
Dock icon.

## Early preview

This project uses private macOS interfaces. Cleanup is currently enabled only
on **macOS 27.2, build 26B123**, the build verified during development on an
Apple silicon Mac. Other builds stop cleanup rather than assume compatibility.
This is not a general macOS release or an Apple-supported Photos feature.

The setting is a **target, not a hard quota**. The Photos catalog, temporary
files, requested downloads, and resources macOS will not release can exceed
it. The minimum target is 20 GB. Photos synchronization still needs
free space on the whole disk; other apps can consume that space.

## Install

[Download Photos Storage 0.3.0](https://github.com/emieljanson/photos-storage/releases/download/v0.3.0/Photos-Storage-0.3.0-arm64.zip)
for Apple silicon and **macOS 27.2, build 26B123**.

Unzip the download, move **Photos Storage.app** to **Applications**, and open it.
The app is signed with Developer ID and notarized by Apple.
The welcome screen explains where the controls live. Choose **Continue** to
add the settings pane for your account. If System Settings is open while the
pane needs installing or updating, quit it and choose **Continue** again.

Setup asks only for access that is missing:

1. **Photos Library** — the library is already chosen in the macOS window.
   Click **Allow Library** so its local storage can be measured.
2. **Photos Settings** — the settings file is already selected. Click
   **Allow Settings** so optional downloads can be budgeted.

Each permission is explained before its macOS window opens. Access is checked
against the expected library or settings file before it is saved.

Setup checks iCloud Photos and Optimize Mac Storage before showing the ready
screen. Its **Open System Settings** button opens **Photos Storage** directly.
On the verified macOS build, the app reopens System Settings first to avoid
a third-party-pane reload issue. If Settings refuses to quit, setup asks you
to close it and retry; it does not force-quit it.
Choose a target and turn on **Optimize storage** there. **Start at login** is
optional and stays under **Options…**.

Opening the app later returns directly to that same pane. Starting it at
login or from the pane stays silent. Missing permissions can be restored
from the pane's access button, which reopens the guided setup.

If a pane is blank after navigating away and back inside System Settings,
open Photos Storage again to reload it. This preview cannot repair the
operating system's legacy preference-pane host.

The macOS third-party preference-pane host currently opens a wider window
than Apple's own settings panes. This preview does not bypass that host.

## Updates

**Keep Photos Storage up to date** is offered during setup and can be changed
under **Options… → Automatic updates**. Sparkle checks daily over HTTPS.
Updates and the update feed require Ed25519 signatures, and the installed app
is Developer ID signed and notarized. Usage profiling is disabled.

The agent waits for its current work to finish before automatically installing
an update. It resumes in the background. The embedded settings pane is updated
when System Settings closes. Use **Options… → Check for Updates…** for a manual
check. The current preview receives updates from this repository's public feed.

## Build and package

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
the app, embedded pane, helper, and disk image with a secure timestamp. Submit
the resulting disk image to Apple and staple its notarization ticket before
public distribution. Running Sparkle with hardened runtime requires a real
Developer ID signature. See [RELEASING.md](RELEASING.md) for the verified
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

## Remove

To relax the app's last prefetch budget first, choose **Custom…** and enter
the largest allowed target while iCloud optimization is still enabled. Then
turn off **Optimize storage** and **Options… → Start at login**.
Stop **PhotosStorage** in Activity Monitor,
quit System Settings, and remove the two installed bundles listed above.
The installer retains previous installed versions under the app's private
application-support directory for local rollback.

## References

- [Apple Preference Panes](https://developer.apple.com/documentation/preferencepanes)
- [Interface design decisions and Apple HIG references](DESIGN.md)
- [Apple's System Settings compatibility explanation](https://developer.apple.com/videos/play/wwdc2022/10074/?time=294)
- [CacheDelete ABI reference in MacSpace](https://github.com/1architect/macspace-releases/blob/main/Platform/CacheDelete/CacheDelete.swift)

## License

MIT. See [LICENSE](LICENSE).
