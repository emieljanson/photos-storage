# Photos Storage 0.4.1

For Apple silicon Macs running **macOS 13 or later**.
Runtime checks pass on macOS 15, 26, and 27. macOS 13 and 14 have not been
runtime-tested.

- Builds for older macOS versions, including the app, helper, and System Settings pane.
- Checks the installed Photos features and the meaning of its optimization setting instead of requiring one exact macOS build.
- Bounds background helper checks so a stalled process cannot leave monitoring busy indefinitely.
- Handles first use when Photos has not yet stored a prefetch override.
- Shows an unsupported Photos version directly, without sending users to unrelated iCloud settings.

Existing iCloud Photos and Optimize Mac Storage checks remain in place;
unverifiable settings stop cleanup. Photos
Storage asks macOS to release eligible local copies; it does not delete items
from your photo library. The storage target is approximate.

The app is Developer ID signed and notarized by Apple, with signed automatic
updates. Unzip the download, move **Photos Storage.app** to **Applications**, and
open it. Setup takes you to **System Settings → Photos Storage**.

If a third-party settings pane appears blank after navigating away and back,
reopen Photos Storage. macOS may display a wider window for third-party panes.
