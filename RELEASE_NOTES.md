# Photos Storage 0.4.3

For Apple silicon Macs running **macOS 13 or later**.
Runtime checks pass on macOS 15, 26, and 27. macOS 13 and 14 have not been
runtime-tested.

- Fixes setup for libraries where Photos has never saved an explicit storage choice. Switching between Download Originals and Optimize Mac Storage is no longer needed.
- Requests Photos Full Access only when needed to verify that missing choice, with clear recovery when access is denied.
- Keeps cleanup paused for Originals mode, unavailable settings, or iCloud settings changed during verification.

Existing iCloud Photos and Optimize Mac Storage checks remain in place;
unverifiable or disabled settings stop cleanup. Photos Storage asks macOS to
release eligible local copies; it does not delete items
from your photo library. The storage target is approximate.

The app is Developer ID signed and notarized by Apple, with signed automatic
updates. Unzip the download, move **Photos Storage.app** to **Applications**, and
open it. Setup takes you to **System Settings → Photos Storage**.

If a third-party settings pane appears blank after navigating away and back,
reopen Photos Storage. macOS may display a wider window for third-party panes.
