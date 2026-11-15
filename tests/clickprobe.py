#!/usr/bin/env python3
"""
Find the yellow "Yes" button by colour, click it, and report whether the screen
changed. Static screens (age gates, menus) make this decisive: a control capture
right before the click establishes the noise floor.

  python3 clickprobe.py ~/Pictures/Screenshot.png
"""
import ctypes
import os
import subprocess
import sys
import time

from PIL import Image, ImageChops

SHOT = os.path.expanduser("~/Pictures/Screenshot.png")


def capture(path, tries=3):
    # The portal writes the file asynchronously; wait for the mtime to move
    # instead of deleting it (deleting races with the portal's own write).
    for attempt in range(tries):
        before = os.path.getmtime(SHOT) if os.path.exists(SHOT) else 0
        subprocess.run(["gdbus", "call", "--session",
                        "--dest", "org.freedesktop.portal.Desktop",
                        "--object-path", "/org/freedesktop/portal/desktop",
                        "--method", "org.freedesktop.portal.Screenshot.Screenshot",
                        "", "{}"], capture_output=True, timeout=60)
        for _ in range(40):
            try:
                if os.path.exists(SHOT) and os.path.getmtime(SHOT) > before:
                    im = Image.open(SHOT)
                    im.load()
                    im.convert("RGB").save(path)
                    return True
            except Exception:
                pass
            time.sleep(0.25)
    return False


def find_yellow(src):
    """Largest connected blob of saturated yellow -> its centroid."""
    im = Image.open(src).convert("RGB")
    w, h = im.size
    px = im.load()
    pts = []
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            r, g, b = px[x, y]
            if r > 190 and g > 165 and b < 110 and r - b > 90 and g - b > 60:
                pts.append((x, y))
    if not pts:
        return None, im.size
    # centroid of the densest cluster (coarse grid bucket)
    from collections import Counter
    buckets = Counter(((x // 40) * 40, (y // 40) * 40) for x, y in pts)
    (bx, by), _ = buckets.most_common(1)[0]
    cluster = [(x, y) for x, y in pts if bx <= x < bx + 40 and by <= y < by + 40]
    cx = sum(x for x, _ in cluster) // len(cluster)
    cy = sum(y for _, y in cluster) // len(cluster)
    return (cx, cy), im.size


def move_and_click(x, y):
    x11 = ctypes.CDLL("libX11.so.6")
    xtst = ctypes.CDLL("libXtst.so.6")
    x11.XOpenDisplay.restype = ctypes.c_void_p
    dpy = x11.XOpenDisplay(None)
    if not dpy:
        return False
    xtst.XTestFakeMotionEvent(ctypes.c_void_p(dpy), -1, x, y, 0)
    x11.XFlush(ctypes.c_void_p(dpy))
    time.sleep(0.4)
    xtst.XTestFakeButtonEvent(ctypes.c_void_p(dpy), 1, True, 0)
    x11.XFlush(ctypes.c_void_p(dpy))
    time.sleep(0.12)
    xtst.XTestFakeButtonEvent(ctypes.c_void_p(dpy), 1, False, 0)
    x11.XFlush(ctypes.c_void_p(dpy))
    return True


def changed(a, b):
    ia, ib = Image.open(a), Image.open(b)
    if ia.size != ib.size:
        return -1.0
    d = ImageChops.difference(ia, ib).convert("L")
    mask = d.point(lambda v: 255 if v > 12 else 0)
    n = mask.histogram()[255]
    return 100.0 * n / (ia.size[0] * ia.size[1])


def main():
    first = sys.argv[1] if len(sys.argv) > 1 else SHOT
    if not capture(first):
        print("FAIL: no screenshot"); return 1
    pt, size = find_yellow(first)
    print(f"screen: {size[0]}x{size[1]}")
    if not pt:
        print("FAIL: no yellow button found by colour"); return 1
    print(f"yellow button centre: {pt}")

    # control: two captures with no input -> the noise floor of this screen
    capture("/tmp/c1.png"); time.sleep(1.2); capture("/tmp/c2.png")
    base = changed("/tmp/c1.png", "/tmp/c2.png")
    print(f"control (no input): {base:.3f}% pixels changed")

    move_and_click(*pt)
    time.sleep(1.5)
    capture("/tmp/c3.png")
    after = changed("/tmp/c2.png", "/tmp/c3.png")
    print(f"after click at {pt}: {after:.3f}% pixels changed")

    if after > max(1.0, base * 5):
        print("RESULT: the click registered — the screen changed well beyond noise")
    else:
        print("RESULT: no visible response to the click (same as control)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
