#!/usr/bin/env python3
"""Build the wallpaper thumbnail cache and theme index for ThemeSwitcher.qml.

Writes ~/.cache/quickshell/wallpapers/index.json describing every image in the
wallpaper directory and every Wallpaper Engine scene: its thumbnail and the
one colour theme (from ~/.config/hypr/themes.json) it belongs to. A wallpaper
lives in exactly one theme, so the switcher can show a green theme's
wallpapers and nothing else. Thumbnails are regenerated only when the source
is newer, and the theme is recomputed from the thumbnail whenever the
classifier version or the theme set changes.
"""

import colorsys
import concurrent.futures
import hashlib
import json
import os
import subprocess
import sys

from PIL import Image

HOME = os.path.expanduser("~")
WALL_DIR = os.path.join(HOME, "Pictures/Wallpapers")
CACHE_DIR = os.path.join(HOME, ".cache/quickshell/wallpapers")
INDEX = os.path.join(CACHE_DIR, "index.json")
THEMES_FILE = os.path.join(HOME, ".config/hypr/themes.json")
WS = "/mnt/games/SteamLibrary/steamapps/workshop/content/431960"
THUMB_WIDTH = 420
EXTS = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}

# Bumped whenever classify() changes, so cached entries are re-sorted.
CLASSIFIER = 2

# A pixel counts as coloured only when it is lit, saturated and has real
# chroma: dark JPEG noise and grey fog have a hue but no colour. A wallpaper
# needs VIVID_SHARE of its pixels coloured to leave the mono theme; the theme
# is then the hue family carrying the most chroma among those pixels.
SAMPLE = (64, 36)
MIN_VALUE = 0.16
MIN_SAT = 0.30
MIN_CHROMA = 0.07
VIVID_SHARE = 0.04
MONO = "mono"


def load_themes():
    with open(THEMES_FILE) as f:
        return json.load(f)


def theme_for_hue(themes, deg):
    for t in themes:
        hue = t.get("hue")
        if not hue:
            continue
        lo, hi = hue
        if (lo > hi and (deg >= lo or deg < hi)) or (lo <= deg < hi):
            return t["id"]
    return MONO


def classify(themes, thumb):
    try:
        im = Image.open(thumb).convert("RGB").resize(SAMPLE, Image.BILINEAR)
    except Exception:
        return MONO
    pixels = im.get_flattened_data() if hasattr(im, "get_flattened_data") else im.getdata()
    weight, vivid, total = {}, 0, 0
    for r, g, b in pixels:
        total += 1
        r, g, b = r / 255.0, g / 255.0, b / 255.0
        h, s, v = colorsys.rgb_to_hsv(r, g, b)
        chroma = max(r, g, b) - min(r, g, b)
        if v < MIN_VALUE or s < MIN_SAT or chroma < MIN_CHROMA:
            continue
        vivid += 1
        tid = theme_for_hue(themes, h * 360.0)
        weight[tid] = weight.get(tid, 0.0) + chroma * s
    if not total or vivid / total < VIVID_SHARE or not weight:
        return MONO
    return max(weight, key=weight.get)


def thumb_path(key):
    return os.path.join(CACHE_DIR, hashlib.sha1(key.encode("utf-8")).hexdigest()[:16] + ".jpg")


def make_thumb(src, dst):
    if os.path.exists(dst) and os.path.getmtime(dst) >= os.path.getmtime(src):
        return True
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-i", src, "-frames:v", "1",
           "-vf", f"scale={THUMB_WIDTH}:-1:flags=lanczos", "-q:v", "4", dst]
    return subprocess.run(cmd, capture_output=True).returncode == 0


def we_preview(d):
    static, animated = [], []
    try:
        names = sorted(os.listdir(d))
    except OSError:
        return None
    for n in names:
        if n.lower().startswith("preview"):
            (animated if n.lower().endswith(".gif") else static).append(os.path.join(d, n))
    return (static or animated or [None])[0]


def sources():
    """Every wallpaper as (key, source image, base entry)."""
    out = []
    if os.path.isdir(WALL_DIR):
        for f in sorted(os.listdir(WALL_DIR)):
            if os.path.splitext(f)[1].lower() not in EXTS:
                continue
            p = os.path.join(WALL_DIR, f)
            out.append((p, p, {"kind": "image", "path": p,
                               "name": os.path.splitext(f)[0]}))
    if os.path.isdir(WS):
        for wid in sorted(os.listdir(WS)):
            d = os.path.join(WS, wid)
            proj = os.path.join(d, "project.json")
            prev = we_preview(d)
            if not os.path.isfile(proj) or not prev:
                continue
            title = ""
            try:
                with open(proj) as f:
                    title = json.load(f).get("title", "") or ""
            except (OSError, ValueError):
                pass
            out.append(("we:" + wid, prev, {"kind": "we", "id": wid, "path": "",
                                            "name": title or wid}))
    return out


def main():
    os.makedirs(CACHE_DIR, exist_ok=True)
    themes = load_themes()
    stamp = "%d:%s" % (CLASSIFIER, ",".join(
        "%s=%s" % (t["id"], t.get("hue")) for t in themes))

    old = {}
    try:
        with open(INDEX) as f:
            for e in json.load(f):
                old[e.get("key") or e.get("path")] = e
    except (OSError, ValueError, AttributeError):
        pass

    def process(item):
        key, src, base = item
        dst = thumb_path(key)
        cached = old.get(key)
        fresh = (os.path.exists(dst) and os.path.getmtime(dst) >= os.path.getmtime(src))
        if cached and fresh and cached.get("stamp") == stamp:
            return cached
        if not make_thumb(src, dst):
            return None
        e = dict(base)
        e.update({"key": key, "thumb": dst, "theme": classify(themes, dst), "stamp": stamp})
        return e

    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        entries = [e for e in pool.map(process, sources()) if e]

    entries.sort(key=lambda e: (e["kind"] != "image", e["name"].lower()))

    live = {e["thumb"] for e in entries}
    for f in os.listdir(CACHE_DIR):
        p = os.path.join(CACHE_DIR, f)
        if f.endswith(".jpg") and p not in live:
            os.remove(p)

    # Written in place: the switcher's FileView watches this path, and a
    # rename would swap the inode out from under its watch.
    with open(INDEX, "w") as fh:
        json.dump(entries, fh)
    print(INDEX)


if __name__ == "__main__":
    sys.exit(main())
