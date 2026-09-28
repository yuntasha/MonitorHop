#!/usr/bin/env python3
"""End-to-end test of MonitorHop on the real window server.

Runs the MonitorHop CLI through LaunchServices (`open -n -g -W`) so it uses MonitorHop's own
Accessibility permission, opens two test windows (one per monitor) and verifies:
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


def mh(*args):
    """Runs a MonitorHop CLI command as its own LaunchServices app and returns stdout."""
    out = os.path.join(WORK, f"out-{time.time_ns()}.txt")
    subprocess.run(["open", "-g", "-n", "-W", "--stdout", out, "--stderr", out, APP, "--args", *args], check=True)
    with open(out) as f:
        return f.read()


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


def read_config():
    try:
        data = subprocess.run(["defaults", "export", BUNDLE_ID, "-"], check=True, capture_output=True).stdout
        return plistlib.loads(data)
    except subprocess.CalledProcessError:
        return None


def write_placement(original, mode):
    config = json.loads(original["config.v1"]) if original and "config.v1" in original else {}
    config["placement"] = mode
    config["moveCursor"] = True
    blob = json.dumps(config).encode()
    run("defaults", "write", BUNDLE_ID, "config.v1", "-data", blob.hex())


def restore_config(original):
    if original is None:
        subprocess.run(["defaults", "delete", BUNDLE_ID], capture_output=True)
        return
    path = os.path.join(WORK, "restore.plist")
    with open(path, "wb") as f:
        plistlib.dump(original, f)
    run("defaults", "import", BUNDLE_ID, path)


def main():
    if not os.path.isdir(APP):
        sys.exit("build/MonitorHop.app not found — run `make app` first")
    info = json.loads(mh("--list-json"))
    monitors = info["monitors"]
    print(f"MonitorHop {info['version']} · monitors: {len(monitors)} · accessibility: {info['trusted']}")
    if len(monitors) < 2:
        sys.exit("SKIP: needs at least two monitors")
    if not info["trusted"]:
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
        s = window_status()
        if s["key"] != "HopA":
            # Make sure HopA is the focused window for the move tests.
            subprocess.run(["open", test_app], check=True)  # re-activates the running test app
            mh("--focus", "2")
            s = window_status()
        check("HopA focused before move tests", s["key"] == "HopA" and s["active"], s)

        out = mh("--focus", "9")
        check("focus 9 (missing monitor) reports failure", "실패" in out, out)

        print("\n[move · keepSize]")
        frame_a = window_status(0.1)["frames"]["HopA"]
        out = mh("--move", "1")
        s, st = window_status(), hop_state()
        v1, v2 = visible_frames()
        fa = s["frames"]["HopA"]
        check("move 1 → HopA on monitor 1", inside(fa, v1), f"{out.strip()} / {fa} not in {v1}")
        check("move 1 → size kept", close(fa[2:], size_a, 1), fa)
        check("move 1 → HopA still key", s["key"] == "HopA" and s["active"], s)
        check("move 1 → cursor followed", point_in(st["cursor"], m1["axFrame"]), st)

        out = mh("--move", "1")
        check("move to the same monitor is a no-op", "이미" in out, out)

        out = mh("--move", "2")
        fa = window_status()["frames"]["HopA"]
        check("move 2 → back to the original frame", close(fa, frame_a, 3), f"{fa} vs {frame_a}")

        print("\n[move · fill]")
        write_placement(original_config, "fill")
        mh("--move", "1")
        fa = window_status()["frames"]["HopA"]
        v1, v2 = visible_frames()
        check("fill → matches monitor 1 visible area", close(fa, v1, 2), f"{fa} vs {v1}")
        mh("--move", "2")
        fa = window_status()["frames"]["HopA"]
        v1, v2 = visible_frames()
        check("fill → matches monitor 2 visible area", close(fa, v2, 2), f"{fa} vs {v2}")

        print("\n[move · center]")
        write_placement(original_config, "center")
        before = window_status(0.1)["frames"]["HopA"]
        mh("--move", "1")
        fa = window_status()["frames"]["HopA"]
        v1, v2 = visible_frames()
        expected = centered(before[2:], v1)
        check("center → centered on monitor 1", close(fa, expected, 2), f"{fa} vs {expected}")

        print("\n[move · proportional]")
        write_placement(original_config, "proportional")
        # Shrink HopA to a known non-maximized frame first (keepSize keeps it, center re-centers it).
        write_placement(original_config, "keepSize")
        mh("--move", "2")
        write_placement(original_config, "proportional")
        before = window_status()["frames"]["HopA"]
        v1, v2 = visible_frames()
        mh("--move", "1")
        after = window_status()["frames"]["HopA"]
        v1b, _ = visible_frames()
        maximized = close(before, v2, 16)
        expected_size = [v1b[2], v1b[3]] if maximized else [before[2] * v1b[2] / v2[2], before[3] * v1b[3] / v2[3]]
        check("proportional → scaled size", close(after[2:], expected_size, 3), f"{after} expected size {expected_size}")
        check("proportional → on monitor 1", inside(after, v1b), f"{after} not in {v1b}")
    finally:
        subprocess.run(["pkill", "-f", "MonitorHopTestWindow.app/Contents/MacOS/MonitorHopTestWindow"])
        restore_config(original_config)
        if original_front:
            subprocess.run([os.path.join(TOOLS, "hoptool"), "activate", original_front])

    print(f"\n{len(passed)} passed, {len(failed)} failed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
