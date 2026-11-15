# Photos Storage 0.4.2

For Apple silicon Macs running **macOS 13 or later**.
Runtime checks pass on macOS 15, 26, and 27. macOS 13 and 14 have not been
runtime-tested.

- Fixes setup verification for Photos libraries that record iCloud enablement as `CPL` instead of `iCPL`.
- Explains where to check iCloud Photos and select Optimize Mac Storage when settings cannot be verified.

Existing iCloud Photos and Optimize Mac Storage checks remain in place;
unverifiable or missing settings stop cleanup. Photos Storage asks macOS to
release eligible local copies; it does not delete items
from your photo library. The storage target is approximate.

The app is Developer ID signed and notarized by Apple, with signed automatic
updates. Unzip the download, move **Photos Storage.app** to **Applications**, and
open it. Setup takes you to **System Settings → Photos Storage**.

If a third-party settings pane appears blank after navigating away and back,
reopen Photos Storage. macOS may display a wider window for third-party panes.
