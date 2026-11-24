"""Check the actual binaries, not only their declared minimum macOS version."""

import os
from pathlib import Path
import plistlib
import re
import subprocess

root = Path(os.environ.get("PHOTOS_STORAGE_BUILD_DIR", Path.home() / "Library/Caches/PhotosStorage/build"))
app = root / "Photos Storage.app"
pane = root / "PhotosStorage.prefPane"
for bundle in [app, pane, app / "Contents/PlugIns/PhotosStorage.prefPane"]:
    info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
    assert info["LSMinimumSystemVersion"] == "13.0", bundle

for binary in [app / "Contents/MacOS/PhotosStorage", app / "Contents/MacOS/FotoBudgetCacheHelper",
               pane / "Contents/MacOS/PhotosStoragePane"]:
    assert subprocess.check_output(["lipo", "-archs", binary], text=True).strip() == "arm64", binary
    commands = subprocess.check_output(["xcrun", "vtool", "-show-build", binary], text=True)
    assert re.search(r"\bminos\s+13\.0\b", commands), (binary, commands)

for binary in [app, app / "Contents/MacOS/FotoBudgetCacheHelper"]:
    signed = subprocess.run(["codesign", "-d", "--entitlements", "-", "--xml", binary],
                            check=True, capture_output=True).stdout
    entitlements = plistlib.loads(signed[signed.index(b"<?xml"):]) if b"<?xml" in signed else {}
    assert entitlements.get("com.apple.security.personal-information.photos-library") is True, (binary, entitlements)

print("PASS Hardened-runtime app and helper carry the Photos library entitlement.")
print("PASS Apple silicon app, helper and Settings pane have a real macOS 13.0 deployment target.")
