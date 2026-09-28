#!/usr/bin/env python3
"""End-to-end test of MonitorHop on the real window server.

Starts build/MonitorHop.app if needed and drives it through its CLI (commands are forwarded to
the running app, so they use MonitorHop's own Accessibility permission). Opens two test windows
(one per monitor) and verifies:
  * focus N  -> the right window becomes key and the cursor lands on monitor N
  * move N   -> the focused window moves to monitor N, for every placement mode
Needs >= 2 monitors and Accessibility permission for MonitorHop. Restores settings and focus afterwards.

Usage: scripts/integration-test.py   (after `make app`)
"""
import json
import os
import plistlib
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "build", "MonitorHop.app")
TOOLS = os.path.join(ROOT, "build", "test-tools")
BUNDLE_ID = "com.alencup.MonitorHop"
WORK = tempfile.mkdtemp(prefix="monitorhop-it-")
STATUS = os.path.join(WORK, "status.json")

passed, failed = [], []


def check(name, condition, detail=""):
    (passed if condition else failed).append(name)
    print(("  PASS  " if condition else "  FAIL  ") + name + ("" if condition else f"  → {detail}"))


def run(*cmd, **kw):
    return subprocess.run(cmd, check=True, capture_output=True, text=True, **kw).stdout


def build_tools():
    os.makedirs(TOOLS, exist_ok=True)
    support = os.path.join(ROOT, "scripts", "test-support")
    run("swiftc", "-O", os.path.join(support, "hoptool.swift"), "-o", os.path.join(TOOLS, "hoptool"))
    app = os.path.join(TOOLS, "MonitorHopTestWindow.app", "Contents")
    os.makedirs(os.path.join(app, "MacOS"), exist_ok=True)
    run("swiftc", "-O", os.path.join(support, "TestWindow.swift"), "-o", os.path.join(app, "MacOS", "MonitorHopTestWindow"))
    with open(os.path.join(app, "Info.plist"), "wb") as f:
        plistlib.dump({
            "CFBundleIdentifier": "com.alencup.MonitorHop.testwindow",
            "CFBundleExecutable": "MonitorHopTestWindow",
            "CFBundleName": "MonitorHopTestWindow",
            "CFBundlePackageType": "APPL",
            "LSMinimumSystemVersion": "13.0",
        }, f)
    run("codesign", "--force", "--sign", "-", os.path.dirname(app))
    return os.path.dirname(app)


BIN = os.path.join(APP, "Contents", "MacOS", "MonitorHop")


def mh(*args):
    """Runs a MonitorHop CLI command (forwarded to the running app) and returns its output."""
    r = subprocess.run([BIN, *args], capture_output=True, text=True, timeout=30)
    return r.stdout + r.stderr


def list_json():
    """--list-json, or None while the app is starting and not answering yet."""
    try:
        return json.loads(mh("--list-json"))
    except json.JSONDecodeError:
        return None


def app_under_test_running(info):
    """True when the running app is exactly build/MonitorHop.app, current, with dev tools on."""
    if not info or not info.get("appRunning"):
        return False
    same_bundle = os.path.realpath(info.get("bundlePath", "")) == os.path.realpath(APP)
    fresh = info.get("executableMTime", 0) >= os.path.getmtime(BIN) - 1
    return same_bundle and fresh and info.get("devTools", False)


def ensure_app_running():
    """Makes sure the app under test is the one answering. Returns the bundle path of a
    different MonitorHop that was running before (to relaunch afterwards), or "" if none."""
    info = list_json()
    if app_under_test_running(info):
        return ""
    running = bool(info and info.get("appRunning")) or subprocess.run(["pgrep", "-x", "MonitorHop"],
                                                                       capture_output=True).returncode == 0
    # An older build may not report its path: relaunch build/ afterwards in that case.
    previous = ((info or {}).get("bundlePath") or APP) if running else ""
    if running:
        subprocess.run(["pkill", "-x", "MonitorHop"])
        for _ in range(50):
            time.sleep(0.1)
            if not (list_json() or {}).get("appRunning"):
                break
    # Dev tools (--simulate-hotkey) are opt-in per launch.
    subprocess.run(["open", "--env", "MONITORHOP_DEVTOOLS=1", APP], check=True)
    for _ in range(100):
        time.sleep(0.2)
        if app_under_test_running(list_json()):
            return previous or APP
    sys.exit("could not start build/MonitorHop.app")


def restore_app(previous):
    """Relaunch whatever MonitorHop the user had running (without dev tools)."""
    if not previous:
        return
    subprocess.run(["pkill", "-x", "MonitorHop"])
    time.sleep(0.8)
    subprocess.run(["open", previous])


def visible_frames():
    """Fresh visible areas: the Dock can resize (e.g. when an app icon appears), changing them."""
    monitors = json.loads(mh("--list-json"))["monitors"]
    return monitors[0]["axVisibleFrame"], monitors[1]["axVisibleFrame"]


def hop_state():
    return json.loads(run(os.path.join(TOOLS, "hoptool"), "state"))


def window_status(wait=0.6):
    time.sleep(wait)
    with open(STATUS) as f:
        return json.load(f)


def inside(rect, bounds, tol=1.0):
    x, y, w, h = rect
    bx, by, bw, bh = bounds
    return x >= bx - tol and y >= by - tol and x + w <= bx + bw + tol and y + h <= by + bh + tol


def point_in(p, bounds):
    bx, by, bw, bh = bounds
    return bx <= p[0] < bx + bw and by <= p[1] < by + bh


def close(a, b, tol):
    return all(abs(x - y) <= tol for x, y in zip(a, b))


def centered(size, bounds):
    w, h = min(size[0], bounds[2]), min(size[1], bounds[3])
    return [round(bounds[0] + (bounds[2] - w) / 2), round(bounds[1] + (bounds[3] - h) / 2), w, h]


CONFIG_KEY = "config.v1"


def read_config():
    """MonitorHop's settings blob (bytes) or None. Only this key is touched: macOS keeps other
    keys (status item position, …) in the same domain while the app runs."""
    try:
        data = subprocess.run(["defaults", "export", BUNDLE_ID, "-"], check=True, capture_output=True).stdout
        return plistlib.loads(data).get(CONFIG_KEY)
    except subprocess.CalledProcessError:
        return None


def write_config_blob(blob):
    if blob is None:
        subprocess.run(["defaults", "delete", BUNDLE_ID, CONFIG_KEY], capture_output=True)
    else:
        run("defaults", "write", BUNDLE_ID, CONFIG_KEY, "-data", blob.hex())


def write_placement(original, mode):
    config = json.loads(original) if original else {}
    config["placement"] = mode
    config["moveCursor"] = True
    write_config_blob(json.dumps(config).encode())
    mh("--reload")


def restore_config(original):
    for attempt in range(3):
        write_config_blob(original)
        time.sleep(0.3)
        if read_config() == original:
            break
        print(f"  warn  settings not restored yet (attempt {attempt + 1}), retrying")
    else:
        print("  WARN  could not restore MonitorHop settings; check 설정 › 일반")
    mh("--reload")


def main():
    if not os.path.isdir(APP):
        sys.exit("build/MonitorHop.app not found — run `make app` first")
    previous_app = ensure_app_running()
    info = list_json()
    monitors = info["monitors"]
    print(f"MonitorHop {info['version']} · monitors: {len(monitors)} · app accessibility: {info.get('appTrusted')}")
    if len(monitors) < 2:
        sys.exit("SKIP: needs at least two monitors")
    if not info.get("appTrusted"):
        sys.exit("SKIP: MonitorHop has no Accessibility permission (grant it, then re-run)")

    m1, m2 = monitors[0], monitors[1]
    v1, v2 = m1["axVisibleFrame"], m2["axVisibleFrame"]
    size_a, size_b = [800, 500], [600, 400]
    frame_a = [v2[0] + 120, v2[1] + 90] + size_a      # on monitor 2
    frame_b = [v1[0] + 150, v1[1] + 120] + size_b      # on monitor 1

    test_app = build_tools()
    original_front = hop_state()["frontmost"]
    original_config = read_config()
    try:
        write_placement(original_config, "keepSize")
        subprocess.run(["open", "-n", test_app, "--args", STATUS,
                        "HopB", *map(str, frame_b), "HopA", *map(str, frame_a)], check=True)
        for _ in range(50):
            if os.path.exists(STATUS):
                break
            time.sleep(0.1)
        s = window_status(2.0)  # let Stage Manager / the window server settle
        check("test windows opened", bool(s["frames"].get("HopA") and s["frames"].get("HopB")), s)
        frame_a = s["frames"]["HopA"]  # the window server may have adjusted it slightly

        print("\n[focus]")
        same_app_switches = 0

        def focus_and_check(n, monitor):
            nonlocal same_app_switches
            expected = json.loads(run(os.path.join(TOOLS, "hoptool"), "front", *map(str, monitor["axFrame"])))
            before_key = window_status(0.05)["key"]
            out = mh("--focus", str(n))
            s, st = window_status(), hop_state()
            label = f"focus {n} → front window on monitor {n} ({expected.get('owner', 'none')})"
            if not expected:
                check(label + " → cursor only", point_in(st["cursor"], monitor["axFrame"]), f"{out.strip()} / {st}")
                return
            ok = st["frontmostPID"] == expected["pid"]
            if expected["pid"] == s["pid"]:
                key_id = s["ids"].get(s["key"], -1)
                ok = ok and s["active"] and key_id == expected["id"]
                if before_key and s["key"] != before_key:
                    same_app_switches += 1
            check(label, ok, f"{out.strip()} / expected {expected} / status {s} / state {st}")
            check(f"focus {n} → cursor on monitor {n}", point_in(st["cursor"], monitor["axFrame"]), st)

        for n, monitor in ((2, m2), (1, m1), (2, m2), (1, m1), (2, m2)):
            focus_and_check(n, monitor)
        print(f"  info  window-level switches inside the test app: {same_app_switches}"
              + ("" if same_app_switches else " (Stage Manager kept only one test window on stage)"))
        print("\n[real hotkeys]")
        # The app presses its own registered shortcut: window server → Carbon hotkey → action.
        # Checked at app + cursor level: window-level precision is covered by [focus] above, and
        # with Stage Manager the stage of a monitor may be reshuffled right after activation.
        for n, monitor in ((1, m1), (2, m2)):
            expected = json.loads(run(os.path.join(TOOLS, "hoptool"), "front", *map(str, monitor["axFrame"])))
            out = mh("--simulate-hotkey", f"focus.{n}")
            st = hop_state() if not time.sleep(0.8) else None
            ok = bool(expected) and st["frontmostPID"] == expected["pid"] and point_in(st["cursor"], monitor["axFrame"])
            check(f"hotkey focus.{n} → {expected.get('owner', '?')} active, cursor on monitor {n}", ok,
                  f"{out.strip()} / expected {expected} / state {st}")

        s = window_status()
        for _ in range(3):
            if s["key"] == "HopA" and s["active"]:
                break
            # Make sure HopA is the focused window for the move tests.
            subprocess.run(["open", test_app], check=True)  # re-activates the running test app
            time.sleep(0.8)
            mh("--focus", "2")
            s = window_status(1.0)
        check("HopA focused before move tests", s["key"] == "HopA" and s["active"], s)
        test_pid = str(s["pid"])

        def move(n):
            # --pid: MonitorHop refuses to act unless the test app is frontmost, so a Stage
            # Manager reshuffle can never make this test move one of the user's windows.
            return mh("--move", str(n), "--pid", test_pid)

        out = mh("--focus", "9")
        check("focus 9 (missing monitor) reports failure", "실패" in out, out)

        print("\n[move · keepSize]")
        frame_a = window_status(0.1)["frames"]["HopA"]
        out = move(1)
        s, st = window_status(), hop_state()
        v1, v2 = visible_frames()
        fa = s["frames"]["HopA"]
        check("move 1 → HopA on monitor 1", inside(fa, v1), f"{out.strip()} / {fa} not in {v1}")
        check("move 1 → size kept", close(fa[2:], size_a, 1), fa)
        check("move 1 → HopA still key", s["key"] == "HopA" and s["active"], s)
        check("move 1 → cursor followed", point_in(st["cursor"], m1["axFrame"]), st)

        out = move(1)
        check("move to the same monitor is a no-op", "이미" in out, out)

        out = move(2)
        fa = window_status()["frames"]["HopA"]
        check("move 2 → back to the original frame", close(fa, frame_a, 3), f"{fa} vs {frame_a}")

        print("\n[move · fill]")
        write_placement(original_config, "fill")
        move(1)
        fa = window_status()["frames"]["HopA"]
        v1, v2 = visible_frames()
        check("fill → matches monitor 1 visible area", close(fa, v1, 2), f"{fa} vs {v1}")
        move(2)
        fa = window_status()["frames"]["HopA"]
        v1, v2 = visible_frames()
        check("fill → matches monitor 2 visible area", close(fa, v2, 2), f"{fa} vs {v2}")

        print("\n[move · center]")
        write_placement(original_config, "center")
        before = window_status(0.1)["frames"]["HopA"]
        move(1)
        fa = window_status()["frames"]["HopA"]
        v1, v2 = visible_frames()
        expected = centered(before[2:], v1)
        check("center → centered on monitor 1", close(fa, expected, 2), f"{fa} vs {expected}")

        print("\n[move · proportional]")
        write_placement(original_config, "proportional")
        # Shrink HopA to a known non-maximized frame first (keepSize keeps it, center re-centers it).
        write_placement(original_config, "keepSize")
        move(2)
        write_placement(original_config, "proportional")
        before = window_status()["frames"]["HopA"]
        v1, v2 = visible_frames()
        move(1)
        after = window_status()["frames"]["HopA"]
        v1b, _ = visible_frames()
        maximized = close(before, v2, 16)
        expected_size = [v1b[2], v1b[3]] if maximized else [before[2] * v1b[2] / v2[2], before[3] * v1b[3] / v2[3]]
        check("proportional → scaled size", close(after[2:], expected_size, 3), f"{after} expected size {expected_size}")
        check("proportional → on monitor 1", inside(after, v1b), f"{after} not in {v1b}")
    finally:
        subprocess.run(["pkill", "-f", "MonitorHopTestWindow.app/Contents/MacOS/MonitorHopTestWindow"])
        restore_config(original_config)
        restore_app(previous_app)
        if original_front:
            subprocess.run([os.path.join(TOOLS, "hoptool"), "activate", original_front])

    print(f"\n{len(passed)} passed, {len(failed)} failed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
