"""Launch the real app on a clean hosted runner, with optimization explicitly off."""

import json
import os
from pathlib import Path
import subprocess
import sys
import time

if os.environ.get("GITHUB_ACTIONS") != "true":
    raise SystemExit("This check is for clean GitHub-hosted runners only.")

app = Path(sys.argv[1]).resolve()
state_file = Path.home() / "Library/Application Support/FotoBudget/control/state.json"
preferences = Path.home() / "Library/Preferences/nl.emieljanson.FotoBudget.plist"
occupied = [str(path) for path in [state_file, preferences] if path.exists()]
if occupied:
    raise SystemExit(f"Expected no existing Photos Storage state: {occupied}")

capabilities = json.loads(subprocess.check_output(
    [app / "Contents/MacOS/FotoBudgetCacheHelper", "--capabilities"], timeout=110))
assert capabilities["ok"], capabilities
print(json.dumps(capabilities), flush=True)

process = subprocess.Popen([app / "Contents/MacOS/PhotosStorage", "--background", "-automatic", "NO"])
try:
    deadline = time.monotonic() + 40
    while time.monotonic() < deadline:
        assert process.poll() is None, f"App exited with {process.returncode}"
        try:
            state = json.loads(state_file.read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            state = {}
        if state.get("pid") == process.pid and state.get("checkCount", 0) >= 1 and not state.get("busy", True):
            assert not state["automatic"] and not state["cleanupAllowed"], state
            print("PASS same app launched and completed a read-only check without Photos access.")
            break
        time.sleep(0.2)
    else:
        raise AssertionError("App did not finish its first read-only check.")
finally:
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
