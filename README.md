# Photos Storage

Set a local storage target for Apple Photos in **System Settings**.

One slider shows the space Photos uses, your target, and total Mac storage.
A background agent checks every five minutes, including when System Settings
is closed. There is no menu bar or Dock icon.

## Early preview

This project uses private macOS interfaces. Cleanup is currently enabled only
on **macOS 27.2, build 26B123**, the build verified during development on an
Apple silicon Mac. Other builds stop cleanup rather than assume compatibility.
This is not a general macOS release or an Apple-supported Photos feature.

The slider sets a **target, not a hard quota**. The Photos catalog, temporary
files, requested downloads, and resources macOS will not release can exceed
it. Zero does not mean an empty library. Photos synchronization still needs
free space on the whole disk; other apps can consume that space.

## Build and install

Requires Xcode command-line tools with a Swift 6 compiler and a macOS SDK.

```sh
zsh tests/run.sh
zsh build.sh
```

Quit System Settings and any previous instance of Photos Storage or FotoBudget,
then install:

```sh
zsh install.sh
```

Open **System Settings → Photos Storage**. On first use, allow access to the
System Photo Library and the single prefetch settings file when prompted.
The pane offers these steps only when access is missing. macOS file pickers
are handled by the background agent that needs the access.

Turn on **Automatic monitoring** and, if wanted, **Start at login**. Turning
monitoring off stops automatic cleanup; changing the slider still applies a
target manually. The most recent prefetch setting remains in effect.

Build products are written to `~/Library/Caches/PhotosStorage/build`, outside
iCloud Drive. Set `PHOTOS_STORAGE_BUILD_DIR` to override that location for both
scripts. Installed files are:

- `~/Applications/Photos Storage.app` — the background agent
- `~/Library/PreferencePanes/PhotosStorage.prefPane` — the settings pane

Local builds use ad-hoc signatures. No Developer ID signing or notarized binary
distribution is configured in this preview.

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
Closing the pane does not own or stop the monitoring timer.

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
and private status storage. Build scripts treat compiler warnings as errors
and verify the local code signatures.

## Remove

To relax the app's last prefetch budget first, move the slider to the far
right while iCloud optimization is still enabled. Then turn off automatic
monitoring and Start at login. Stop **PhotosStorage** in Activity Monitor,
quit System Settings, and remove the two installed bundles listed above.
The installer retains previous installed versions under the app's private
application-support directory for local rollback.

## References

- [Apple Preference Panes](https://developer.apple.com/documentation/preferencepanes)
- [Apple's System Settings compatibility explanation](https://developer.apple.com/videos/play/wwdc2022/10074/?time=294)
- [CacheDelete ABI reference in MacSpace](https://github.com/1architect/macspace-releases/blob/main/Platform/CacheDelete/CacheDelete.swift)

## License

MIT. See [LICENSE](LICENSE).
