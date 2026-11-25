#!/usr/bin/env python3
"""Write ~/.config/hypr/displays.lua for the monitors this machine has.

hyprland.lua applies that file: one rule per monitor, and workspace ranges
taken from the left-to-right order of their positions (first monitor 1-10,
second 11-20, ...). Without it Hyprland falls back to automatic placement,
which works but picks 60 Hz on most panels and stacks monitors in whatever
order the ports enumerate.

What gets chosen, per monitor:

* mode: the panel's native resolution (its preferred mode, which Hyprland
  lists first) at the highest refresh rate offered for it. Not the highest
  resolution overall: many panels advertise a downscaled 4K@60 they cannot
  show natively.
* scale: from physical pixel density, the nearest of the scales that divide
  the resolution evenly, aiming at ~110 px per inch. Normal desktop monitors
  get 1; HiDPI laptops and 4K panels get 1.25-2.
* position: left to right, in the order Hyprland placed them.
* identity: `desc:<make model serial>`, so swapping cables between ports
  does not swap layouts.

Each combination of monitors gets its own layout. When the set changes
(docking a laptop, plugging in a TV), the current file — with any hand
edits — is filed under its combination in ~/.local/state/hypr/monitor-layouts/
and the new combination's file is restored from there, or generated if it
has never been seen. Hand edits to displays.lua are therefore kept.

Settings → Displays uses the last three: it lists the monitors with --json,
writes the user's choices with --apply (the previous file is kept), and
calls --revert when a change is not confirmed in time.

Usage:
  monitors.py --auto     only act when the connected set changed (login, hotplug);
                         always puts stray workspaces back on their own monitor
  monitors.py --write    regenerate for the current set, keeping nothing
  monitors.py --json     print the connected monitors and every mode they offer
  monitors.py --apply    write the layout given as JSON on stdin:
                         [{"output", "mode", "position", "scale", "transform", "disabled"}, …]
  monitors.py --revert   put back the file --apply replaced
  add --no-reload to leave Hyprland alone afterwards
"""

from __future__ import annotations

import fcntl
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

HOME = Path.home()
ACTIVE = HOME / ".config/hypr/displays.lua"
STATE = Path(os.environ.get("XDG_STATE_HOME") or HOME / ".local/state") / "hypr"
LAYOUTS = STATE / "monitor-layouts"
PREVIOUS = STATE / "displays.lua.previous"
NO_FILE = "-- there was no displays.lua\n"
SCALES = [1.0, 1.25, 1.5, 1.6, 1.75, 2.0, 2.5, 3.0]
TARGET_DPI = 110.0


def hypr_monitors() -> list[dict]:
    out = subprocess.run(["hyprctl", "monitors", "all", "-j"], capture_output=True, text=True, timeout=10)
    if out.returncode != 0:
        return []
    try:
        mons = json.loads(out.stdout)
    except json.JSONDecodeError:
        return []
    return [m for m in mons if m.get("name") and not str(m.get("name")).startswith("HEADLESS")]


WS_PER_MONITOR = 10


def dispatch(lua: str) -> None:
    subprocess.run(["hyprctl", "dispatch", lua], capture_output=True, check=False)


def place_workspaces() -> None:
    """Move every workspace back to the monitor that owns its range.

    Workspace rules only act when a workspace is created. When monitors
    drop off the bus (DisplayPort panels do on DPMS off) and come back one
    by one, the workspaces gather on whichever monitor returned first and
    stay there under the restored rules. hl.dsp.workspace.move only moves
    the focused workspace, so each stray one is focused, moved, and then
    every monitor gets its own workspace back on screen. A returning monitor
    is still settling when monitor.added fires, so it waits a moment first.
    Every move is logged to ~/.local/state/hypr/monitors.log.
    """
    time.sleep(1.0)
    out = subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True, text=True, timeout=10)
    wss = subprocess.run(["hyprctl", "workspaces", "-j"], capture_output=True, text=True, timeout=10)
    try:
        mons = [m for m in json.loads(out.stdout)
                if not m.get("disabled") and not str(m.get("name", "")).startswith("HEADLESS")
                and m.get("mirrorOf", "none") in ("none", "", None)]
        workspaces = json.loads(wss.stdout)
    except (json.JSONDecodeError, TypeError):
        return
    if not mons:
        return
    mons.sort(key=lambda m: (m.get("x", 0), m.get("y", 0)))
    owner = {}
    for rank, m in enumerate(mons):
        for i in range(1, WS_PER_MONITOR + 1):
            owner[rank * WS_PER_MONITOR + i] = m["name"]
    stray = [w for w in workspaces
             if w.get("id", 0) > 0 and w["id"] in owner and owner[w["id"]] != w.get("monitor")]
    if not stray:
        return

    with open(STATE / "monitors.log", "a") as log:
        log.write(time.strftime("%Y-%m-%d %H:%M:%S ") + "moved back: "
                  + ", ".join(f'{w["id"]} {w.get("monitor")}->{owner[w["id"]]}' for w in stray) + "\n")
    shown = {m["name"]: (m.get("activeWorkspace") or {}).get("id", 0) for m in mons}
    focused = next((m["name"] for m in mons if m.get("focused")), mons[0]["name"])
    for w in stray:
        dispatch(f'hl.dsp.focus({{ workspace = "{w["id"]}" }})')
        dispatch(f'hl.dsp.workspace.move({{ monitor = "{owner[w["id"]]}" }})')

    def wanted(rank: int, m: dict) -> int:
        cur = shown.get(m["name"], 0)
        lo = rank * WS_PER_MONITOR + 1
        return cur if lo <= cur < lo + WS_PER_MONITOR else lo
    order = sorted(enumerate(mons), key=lambda rm: rm[1]["name"] == focused)
    for rank, m in order:
        dispatch(f'hl.dsp.focus({{ workspace = "{wanted(rank, m)}" }})')


def ident(m: dict, all_desc: list[str]) -> str:
    desc = (m.get("description") or "").strip()
    if desc and all_desc.count(desc) == 1 and '"' not in desc and "\\" not in desc:
        return "desc:" + desc
    return m["name"]


def signature(mons: list[dict]) -> str:
    keys = sorted((m.get("description") or m["name"]) for m in mons)
    return hashlib.sha1("\n".join(keys).encode()).hexdigest()[:12]


MODE = re.compile(r"^(\d+)x(\d+)@([\d.]+)Hz$")


def best_mode(m: dict) -> tuple[int, int, float]:
    modes = [MODE.match(s) for s in m.get("availableModes") or []]
    modes = [(int(g[1]), int(g[2]), float(g[3])) for g in modes if g]
    if not modes:
        return int(m["width"]), int(m["height"]), float(m.get("refreshRate") or 60)
    w, h, _ = modes[0]
    rate = max(r for mw, mh, r in modes if (mw, mh) == (w, h))
    return w, h, rate


def best_scale(m: dict, w: int, h: int) -> float:
    pw = m.get("physicalWidth") or 0
    if pw <= 0:
        return 1.0
    dpi = w / (pw / 25.4)
    if dpi < 140:
        return 1.0
    target = dpi / TARGET_DPI
    fits = [s for s in SCALES if abs(w / s - round(w / s)) < 1e-6 and abs(h / s - round(h / s)) < 1e-6]
    return min(fits or [1.0], key=lambda s: abs(s - target))


def lua_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def entry_line(e: dict) -> str:
    parts = [f"output = {lua_str(e['output'])}"]
    if e.get("disabled"):
        parts.append("disabled = true")
    else:
        parts += [f"mode = {lua_str(e['mode'])}", f"position = {lua_str(e['position'])}",
                  "scale = %g" % float(e.get("scale") or 1)]
        if int(e.get("transform") or 0):
            parts.append("transform = %d" % int(e["transform"]))
    return "        { " + ", ".join(parts) + " },"


def render(sig: str, entries: list[tuple[str, dict]]) -> str:
    lines = []
    for label, e in entries:
        lines.append(f"        -- {label}")
        lines.append(entry_line(e))
    return HEADER + (
        "return {\n"
        f"    signature = {lua_str(sig)},\n"
        "    monitors = {\n" + "\n".join(lines) + "\n    },\n}\n"
    )


def label_of(m: dict) -> str:
    return f"{m['name']}: {(m.get('description') or m['name']).strip()}"


def generate(mons: list[dict]) -> str:
    descs = [(m.get("description") or "").strip() for m in mons]
    ordered = sorted(mons, key=lambda m: (m.get("x", 0), m.get("y", 0), m["name"]))
    entries, x = [], 0
    for m in ordered:
        w, h, rate = best_mode(m)
        scale = best_scale(m, w, h)
        transform = int(m.get("transform") or 0)
        entries.append((label_of(m), {
            "output": ident(m, descs), "mode": f"{w}x{h}@{rate:.2f}",
            "position": f"{x}x0", "scale": scale, "transform": transform,
        }))
        lw, lh = (h, w) if transform % 2 else (w, h)
        x += round(lw / scale)
    return render(signature(mons), entries)


def describe(mons: list[dict]) -> list[dict]:
    descs = [(m.get("description") or "").strip() for m in mons]
    out = []
    for m in sorted(mons, key=lambda m: (m.get("x", 0), m.get("y", 0), m["name"])):
        modes = []
        for s in m.get("availableModes") or []:
            g = MODE.match(s)
            if g:
                modes.append({"width": int(g[1]), "height": int(g[2]), "rate": float(g[3])})
        nw, nh, _ = best_mode(m)
        out.append({
            "name": m["name"], "description": (m.get("description") or "").strip(),
            "make": m.get("make") or "", "model": m.get("model") or "",
            "output": ident(m, descs), "disabled": bool(m.get("disabled")),
            "width": int(m.get("width") or 0), "height": int(m.get("height") or 0),
            "rate": float(m.get("refreshRate") or 0), "scale": float(m.get("scale") or 1),
            "transform": int(m.get("transform") or 0), "x": int(m.get("x") or 0), "y": int(m.get("y") or 0),
            "native": {"width": nw, "height": nh}, "modes": modes,
        })
    return out


HEADER = (
    "-- Monitors of this machine, written by ~/.config/hypr/scripts/monitors.py\n"
    "-- and Settings → Displays.\n"
    "--\n"
    "-- Edit freely: a mode, a scale, a rotation (transform 0-3 = 0/90/180/270°),\n"
    "-- or the positions, to match where the monitors stand on your desk\n"
    "-- (\"<x>x<y>\" in pixels, after scaling). The leftmost monitor gets\n"
    "-- workspaces 1-10, the next 11-20, and so on, read from these positions.\n"
    "-- Your edits are kept: this file is only replaced when a different set of\n"
    "-- monitors is connected, and comes back when this set returns.\n"
    "-- `monitors.py --write` starts over from the detected values;\n"
    "-- `hyprctl monitors all` lists every mode a monitor offers.\n"
)


def active_signature() -> str | None:
    try:
        m = re.search(r'signature\s*=\s*"([0-9a-f]+)"', ACTIVE.read_text())
    except OSError:
        return None
    return m.group(1) if m else None


def notify(title: str, body: str) -> None:
    if shutil.which("notify-send"):
        subprocess.run(["notify-send", "-a", "Displays", title, body], check=False)


def main(argv: list[str]) -> int:
    mode = next((a for a in argv if a in ("--auto", "--write", "--json", "--apply", "--revert")), None)
    if mode is None:
        print(__doc__.strip().split("Usage:")[1], file=sys.stderr)
        return 2
    reload = "--no-reload" not in argv

    STATE.mkdir(parents=True, exist_ok=True)
    with open(STATE / "monitors.lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)

        mons = hypr_monitors()
        if mode == "--json":
            print(json.dumps(describe(mons)))
            return 0
        if mode == "--revert":
            if not PREVIOUS.exists():
                print("nothing to revert", file=sys.stderr)
                return 1
            if PREVIOUS.read_text() == NO_FILE:
                ACTIVE.unlink(missing_ok=True)
            else:
                shutil.copy2(PREVIOUS, ACTIVE)
            PREVIOUS.unlink()
            if reload:
                subprocess.run(["hyprctl", "reload"], capture_output=True, check=False)
            print("monitor layout reverted")
            return 0
        if not mons:
            print("no monitors reported by Hyprland; nothing to do", file=sys.stderr)
            return 0
        sig = signature(mons)

        if mode == "--apply":
            try:
                wanted = json.loads(sys.stdin.read())
            except json.JSONDecodeError as e:
                print(f"bad layout JSON: {e}", file=sys.stderr)
                return 1
            if not any(not e.get("disabled") for e in wanted):
                print("refusing a layout with every monitor disabled", file=sys.stderr)
                return 1
            by_out = {d["output"]: d for d in describe(mons)}
            entries = []
            for e in wanted:
                d = by_out.get(e.get("output"))
                label = f"{d['name']}: {d['description'] or d['name']}" if d else e.get("output", "?")
                entries.append((label, e))
            if ACTIVE.exists():
                shutil.copy2(ACTIVE, PREVIOUS)
            else:
                PREVIOUS.write_text(NO_FILE)
            tmp = ACTIVE.with_suffix(".lua.tmp")
            tmp.write_text(render(sig, entries))
            tmp.replace(ACTIVE)
            if reload:
                subprocess.run(["hyprctl", "reload"], capture_output=True, check=False)
            print("monitor layout applied")
            return 0
        old = active_signature()

        if mode == "--auto" and old == sig:
            place_workspaces()
            return 0

        LAYOUTS.mkdir(parents=True, exist_ok=True)
        if old and ACTIVE.exists():
            shutil.copy2(ACTIVE, LAYOUTS / f"{old}.lua")

        saved = LAYOUTS / f"{sig}.lua"
        if mode == "--auto" and saved.exists():
            shutil.copy2(saved, ACTIVE)
            what = "restored"
        else:
            ACTIVE.parent.mkdir(parents=True, exist_ok=True)
            tmp = ACTIVE.with_suffix(".lua.tmp")
            tmp.write_text(generate(mons))
            tmp.replace(ACTIVE)
            what = "set up"

        names = ", ".join(m["name"] for m in sorted(mons, key=lambda m: (m.get("x", 0), m["name"])))
        print(f"monitor layout {what} for {names}")
        if reload:
            subprocess.run(["hyprctl", "reload"], capture_output=True, check=False)
        if mode == "--auto":
            place_workspaces()
        if what == "set up" and mode == "--auto":
            notify("Monitors set up", f"{names} — adjust in ~/.config/hypr/displays.lua")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
