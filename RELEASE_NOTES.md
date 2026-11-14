# Photos Storage 0.3.1

An experimental preview for Apple silicon Macs running **macOS 27.2, build
26B123**. Cleanup is disabled on other builds.

- A new glass Photos and silver storage icon for the app and System Settings.
- Matching icons at standard and Retina resolutions.

Storage targets, background monitoring, and photo safety checks work as before.

The app is signed with Developer ID and notarized by Apple. Unzip the
download, move **Photos Storage.app** to **Applications**, then open it.
After permissions are granted, choose **Open System Settings** to reach
**Photos Storage** directly.

The storage target is approximate. macOS decides which cached resources it
can release. iCloud Photos and Optimize Mac Storage must be enabled; unknown
settings stop cleanup. The app never calls a Photos asset-deletion API.

Known macOS host limitations: this third-party pane uses a wider Settings
window than Apple's own panes. Navigating away and back can leave it blank;
open Photos Storage again to reload it.
