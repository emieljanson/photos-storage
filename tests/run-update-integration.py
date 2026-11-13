#!/usr/bin/env python3
"""Exercise the real updater against a signed, isolated local app and feed."""

from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import hashlib
import os
import plistlib
import shutil
import subprocess
import tempfile
import threading
import time


repo = Path(__file__).resolve().parent.parent
sdk = Path.home() / "Library/Caches/PhotosStorage/Sparkle-2.10.1"
identity = os.environ["PHOTOS_STORAGE_SIGN_IDENTITY"]
build = Path(os.environ.get("PHOTOS_STORAGE_BUILD_DIR", Path.home() / "Library/Caches/PhotosStorage/distribution"))
root = Path(tempfile.mkdtemp(prefix="photos-storage-update-test-"))
app_name = "Photos Storage Update Verification.app"
installed = root / "Installed" / app_name
updated = root / "Updated" / app_name
archives = root / "Downloads"
archives.mkdir()
permit = root / "allow-installation"
checked = root / "idle-checked"
result = root / "launches.txt"
bundle_id = "nl.emieljanson.PhotosStorage.UpdateVerification" + str(int(time.time()))


def run(*args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, **kwargs)


class Handler(SimpleHTTPRequestHandler):
    def log_message(self, *_):
        pass


server = ThreadingHTTPServer(("127.0.0.1", 0), partial(Handler, directory=archives))
threading.Thread(target=server.serve_forever, daemon=True).start()
feed = f"http://127.0.0.1:{server.server_port}/appcast.xml"


def info(app):
    return plistlib.loads((app / "Contents/Info.plist").read_bytes())


try:
    (installed / "Contents/MacOS").mkdir(parents=True)
    (installed / "Contents/Frameworks").mkdir()
    run("ditto", build / "Photos Storage.app/Contents/Frameworks/Sparkle.framework", installed / "Contents/Frameworks/Sparkle.framework")
    metadata = {
        "CFBundleIdentifier": bundle_id, "CFBundleName": "Photos Storage Update Verification",
        "CFBundleExecutable": "Verification", "CFBundlePackageType": "APPL",
        "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0", "LSUIElement": True,
        "SUFeedURL": feed, "SUPublicEDKey": "efeeOqvv19v7sFqLdk3g1zi5p0DcWx7i6DVoXiUKZEU=",
        "SUEnableAutomaticChecks": True, "SUAutomaticallyUpdate": True,
        "SURequireSignedFeed": True, "SUVerifyUpdateBeforeExtraction": True,
        "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True},
        "FixtureRoot": str(root), "LSMinimumSystemVersion": "13.0",
    }
    (installed / "Contents/Info.plist").write_bytes(plistlib.dumps(metadata))
    main = root / "main.swift"
    main.write_text('''import AppKit
import Sparkle

@MainActor final class VerificationDelegate: NSObject, NSApplicationDelegate {
    var updates: AppUpdates?
    var timer: Timer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let root = URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "FixtureRoot") as! String)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
        let log = root.appendingPathComponent("launches.txt")
        var data = (try? Data(contentsOf: log)) ?? Data()
        data.append(Data((version + "\\n").utf8))
        try! data.write(to: log)
        guard version == "1" else { return }
        updates = AppUpdates(isIdle: {
            try! Data().write(to: root.appendingPathComponent("idle-checked"))
            return FileManager.default.fileExists(atPath: root.appendingPathComponent("allow-installation").path)
        }, willRelaunch: {}, stateDidChange: {})
        guard updates!.responds(to: NSSelectorFromString("updater:willInstallUpdateOnQuit:immediateInstallationBlock:")) else {
            fatalError("Sparkle must recognize the automatic installation delegate")
        }
        updates!.start()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                if FileManager.default.fileExists(atPath: root.appendingPathComponent("allow-installation").path) {
                    self?.updates?.resumeInstallationIfIdle()
                }
            }
        }
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = VerificationDelegate()
app.delegate = delegate
app.run()
''')
    run("xcrun", "swiftc", "-swift-version", "6", "-warnings-as-errors", "-framework", "AppKit",
        "-F", sdk, "-framework", "Sparkle", "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
        repo / "Sources/Agent/AppUpdates.swift", main, "-o", installed / "Contents/MacOS/Verification")
    run("codesign", "--force", "--sign", identity, "--options", "runtime", "--timestamp", installed)
    run("ditto", installed, updated)
    metadata.update(CFBundleVersion="2", CFBundleShortVersionString="2.0")
    (updated / "Contents/Info.plist").write_bytes(plistlib.dumps(metadata))
    run("codesign", "--force", "--sign", identity, "--options", "runtime", "--timestamp", updated)
    archive = archives / "Verification-2.zip"
    run("ditto", "-c", "-k", "--keepParent", updated, archive)
    run(sdk / "bin/generate_appcast", "--account", "photos-storage", "--download-url-prefix", feed.removesuffix("appcast.xml"), "--maximum-deltas", "0", archives)
    run(sdk / "bin/sign_update", "--account", "photos-storage", "--verify", archives / "appcast.xml")
    signature = subprocess.check_output([str(sdk / "bin/sign_update"), "--account", "photos-storage", "-p", str(archive)], text=True).strip()
    tampered = root / "Tampered.zip"
    shutil.copyfile(archive, tampered)
    with tampered.open("ab") as file:
        file.write(b"modified after signing")
    rejected = subprocess.run([str(sdk / "bin/sign_update"), "--account", "photos-storage", "--verify", str(tampered), signature], capture_output=True)
    assert rejected.returncode != 0, "An update changed after signing must be rejected"
    print("PASS tampered update rejected by signature verification", flush=True)
    expected = hashlib.sha256((updated / "Contents/MacOS/Verification").read_bytes()).hexdigest()
    run("open", "-n", "-g", installed)
    deadline = time.monotonic() + 100
    while not checked.exists() and time.monotonic() < deadline:
        time.sleep(0.25)
    assert checked.exists(), f"Updater did not reach installation; inspect {root}"
    assert info(installed)["CFBundleVersion"] == "1", "Installation must wait while the storage check is busy"
    assert result.read_text().splitlines() == ["1"], "The busy application must not restart"
    print("PASS automatic update downloaded and verified; installation deferred while busy", flush=True)
    permit.touch()
    deadline = time.monotonic() + 60
    while (not result.exists() or "2" not in result.read_text().splitlines()) and time.monotonic() < deadline:
        time.sleep(0.25)
    assert info(installed)["CFBundleVersion"] == "2", f"Update was not installed; inspect {root}"
    assert result.read_text().splitlines() == ["1", "2"], "The installed update must actually relaunch"
    assert hashlib.sha256((installed / "Contents/MacOS/Verification").read_bytes()).hexdigest() == expected
    run("codesign", "--verify", "--deep", "--strict", installed)
    print("PASS signed feed and payload, automatic installation after idle, and relaunch into version 2", flush=True)
finally:
    server.shutdown()
    process = subprocess.run(["pgrep", "-f", str(installed / "Contents/MacOS/Verification")], capture_output=True, text=True)
    for pid in process.stdout.split():
        subprocess.run(["kill", "-TERM", pid], check=False)
    if result.exists() and result.read_text().splitlines() == ["1", "2"]:
        shutil.rmtree(root)
    else:
        print("Preserved update-test evidence:", root)
