# Setup and troubleshooting

[Back to Photos Storage](../README.md)

## Install

[Download Photos Storage 0.4.1](https://github.com/emieljanson/photos-storage/releases/download/v0.4.1/Photos-Storage-0.4.1-arm64.zip)
for Apple silicon and **macOS 13 or later**. See the
[tested versions](COMPATIBILITY.md) for runtime verification details.

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
The app reopens System Settings first to avoid
a third-party-pane reload issue. If Settings refuses to quit, setup asks you
to close it and retry; it does not force-quit it.
Choose a target and turn on **Optimize storage** there. **Start at login** is
optional and stays under **Options…**.

Opening the app later returns directly to that same pane. Starting it at
login or from the pane stays silent. Missing permissions can be restored
from the pane's access button, which reopens the guided setup.

If a pane is blank after navigating away and back inside System Settings,
open Photos Storage again to reload it.

The macOS third-party preference-pane host currently opens a wider window
than Apple's own panes.

## Updates

**Keep Photos Storage up to date** is offered during setup and can be changed
under **Options… → Automatic updates**. Sparkle checks daily over HTTPS.
Updates and the update feed require Ed25519 signatures, and the installed app
is Developer ID signed and notarized. Usage profiling is disabled.

The agent waits for its current work to finish before automatically installing
an update. It resumes in the background. The embedded settings pane is updated
when System Settings closes. Use **Options… → Check for Updates…** for a manual
check. Photos Storage receives updates from this repository's signed feed.

## Remove

To relax the app's last prefetch budget first, choose **Custom…** and enter
the largest allowed target while iCloud optimization is still enabled. Then
turn off **Optimize storage** and **Options… → Start at login**.
Stop **PhotosStorage** in Activity Monitor and quit System Settings. Then remove:

- **Photos Storage.app** from Applications (`/Applications/Photos Storage.app`,
  or `~/Applications/Photos Storage.app` if installed for your account).
- `~/Library/PreferencePanes/PhotosStorage.prefPane`.
