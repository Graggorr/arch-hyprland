#!/usr/bin/env python3
"""Per-monitor wallpapers and colour themes.

Owns ~/.config/hypr/wallpapers.json, which maps each output to either a static
image (rendered by swww) or a Wallpaper Engine scene (rendered by
linux-wallpaperengine) plus the colour theme that output wears. Both backends
run at once: WE takes the "bottom" layer on the outputs assigned to it, swww
keeps the "background" layer everywhere else.

Themes are colour families defined in ~/.config/hypr/themes.json (Mono, Red,
Orange, ... Pink). Every wallpaper belongs to exactly one of them — the index
built by quickshell/scripts/wallpaper-index.py sorts them by colour — so a
theme only ever shows its own wallpapers. A theme is a matugen seed and
scheme; this script asks matugen for the Material roles and renders every
template listed in ~/.config/matugen/config.toml itself.

Two scopes of colour:
  * per output — the Quickshell bar, island, dock and OSD on a monitor read
    quickshell/colors-<output>.css, the palette of that output's theme;
  * system — GTK, Qt, rofi, wlogout, nvim, Ghostty, btop and the icon
    theme's folder colour exist once per machine, so they follow the theme applied
    most recently (recorded in ~/.config/hypr/theme.json).
Window frames are not themed: Hyprland's border colours in hyprland.lua are
fixed and no template writes them.

Subcommands:
    set <output|all> <image> [theme]   static wallpaper (theme from the index)
    set-we <output|all> <id> [theme]   Wallpaper Engine scene
    apply <output|all> <theme>         theme with random stills from its pool
    random <output|all>                new random still within each output's theme
    restore                            replay saved state (login)
    theme                              rebuild every palette from the state
    theme-list                         themes, swatches and state as JSON
    import-waypaper                    adopt what the waypaper GUI applied
    show                               print state as JSON
"""

import json
import os
import random
import re
import subprocess
import sys

HOME = os.path.expanduser("~")
STATE = os.path.join(HOME, ".config/hypr/wallpapers.json")
WE_MARKER = os.path.join(HOME, ".config/hypr/.we-current")
WALL_DIR = os.path.join(HOME, "Pictures/Wallpapers")
CACHE_DIR = os.path.join(HOME, ".cache/quickshell/wallpapers")
INDEX = os.path.join(CACHE_DIR, "index.json")
INDEXER = os.path.join(HOME, ".config/quickshell/scripts/wallpaper-index.py")

WS = "/mnt/games/SteamLibrary/steamapps/workshop/content/431960"
WE_ASSETS = "/mnt/games/SteamLibrary/steamapps/common/wallpaper_engine/assets"
WE_FPS = 30

EXTS = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}

THEMES_FILE = os.path.join(HOME, ".config/hypr/themes.json")
THEME_FILE = os.path.join(HOME, ".config/hypr/theme.json")
THEME_DEFAULT = "mono"
THEME_CACHE = os.path.join(HOME, ".cache/quickshell/themes")
LAST_FILE = os.path.join(HOME, ".local/state/quickshell/theme-wallpapers.json")
MATUGEN_CONFIG = os.path.join(HOME, ".config/matugen/config.toml")
QS_DIR = os.path.join(HOME, ".config/quickshell")
QS_TEMPLATE = os.path.join(HOME, ".config/matugen/templates/quickshell.css")
SWATCH_ROLES = ["primary", "tertiary", "secondary", "on_secondary_container",
                "inverse_primary", "outline"]


# ── state ────────────────────────────────────────────────────────────────

def load_state():
    try:
        with open(STATE) as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def save_state(state):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    tmp = STATE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(state, f, indent=2, sort_keys=True)
    os.replace(tmp, STATE)
    remember_last(state)


def entry_key(e):
    if e.get("kind") == "we":
        return "we:" + str(e.get("id", ""))
    return e.get("path", "")


def load_last():
    try:
        with open(LAST_FILE) as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def remember_last(state):
    """Each theme's most recently worn wallpaper, so the theme pickers can
    show a picture the user actually chose for it rather than a random one."""
    last = load_last()
    changed = False
    for e in state.values():
        if not isinstance(e, dict):
            continue
        tid, key = e.get("theme", ""), entry_key(e)
        if tid and key and last.get(tid) != key:
            last[tid] = key
            changed = True
    if not changed:
        return
    os.makedirs(os.path.dirname(LAST_FILE), exist_ok=True)
    tmp = LAST_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(last, f, indent=2, sort_keys=True)
    os.replace(tmp, LAST_FILE)


def theme_wallpapers():
    """theme id -> thumbnail of the wallpaper it last wore, falling back to
    the first still the index sorted into it."""
    index = load_index()
    by_key = {e.get("key"): e for e in index}
    out = {}
    for tid, key in load_last().items():
        e = by_key.get(key)
        if e and os.path.isfile(e.get("thumb", "")):
            out[tid] = e["thumb"]
    for e in index:
        tid = e.get("theme", "")
        if tid and tid not in out and e.get("kind") == "image" \
                and os.path.isfile(e.get("thumb", "")):
            out[tid] = e["thumb"]
    return out


def monitors():
    """Connected outputs, left to right, with their pixel geometry."""
    try:
        out = subprocess.check_output(["hyprctl", "monitors", "-j"], text=True)
        mons = json.loads(out)
    except (OSError, ValueError, subprocess.CalledProcessError):
        return []
    live = [m for m in mons if not m.get("disabled")]
    live.sort(key=lambda m: (m.get("x", 0), m.get("y", 0)))
    return [
        {
            "name": m["name"],
            "x": m.get("x", 0),
            "w": int(m.get("width") or 0),
            "h": int(m.get("height") or 0),
        }
        for m in live
        if m.get("width") and m.get("height")
    ]


def targets(arg, mons):
    if arg in ("all", "All", "*"):
        return [m["name"] for m in mons]
    names = [m["name"] for m in mons]
    if arg in names:
        return [arg]
    die(f"unknown output {arg!r}; connected: {', '.join(names) or '(none)'}")


def die(msg):
    notify("Wallpaper", msg, critical=True)
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def notify(title, body, critical=False):
    cmd = ["notify-send"]
    if critical:
        cmd += ["-u", "critical"]
    cmd += [title, body]
    try:
        subprocess.run(cmd, check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        pass


# ── Wallpaper Engine helpers ─────────────────────────────────────────────

def we_dir(wid):
    return os.path.join(WS, str(wid))


def we_preview(wid):
    """Best still image for a scene: the lock screen cannot render the
    animated scene itself, so its preview stands in. The gif is a last
    resort — Pillow reads only its first frame."""
    d = we_dir(wid)
    if not os.path.isdir(d):
        return None
    static, animated = [], []
    try:
        names = sorted(os.listdir(d))
    except OSError:
        return None
    for n in names:
        if not n.lower().startswith("preview"):
            continue
        p = os.path.join(d, n)
        (animated if n.lower().endswith(".gif") else static).append(p)
    return (static or animated or [None])[0]


def we_pids():
    """PIDs of running linux-wallpaperengine processes.

    Matched on the executable in /proc/<pid>/cmdline rather than with pgrep:
    the name is 22 characters, so `pgrep -x` compares it against the 15-char
    comm and never matches, and `pkill -f` would also match the shell running
    this script.
    """
    pids = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                argv = f.read().split(b"\0")
        except OSError:
            continue
        if not argv or not argv[0]:
            continue
        if os.path.basename(argv[0].decode("utf-8", "replace")) == "linux-wallpaperengine":
            pids.append(int(entry))
    return pids


def we_stop():
    import signal
    import time
    pids = we_pids()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except OSError:
            pass
    for _ in range(20):
        if not we_pids():
            return
        time.sleep(0.1)
    for pid in we_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass


def we_sync(state):
    """Restart Wallpaper Engine so it renders exactly the outputs assigned to
    it. One process serves every scene, so any change means a relaunch."""
    assigned = [(o, v["id"]) for o, v in sorted(state.items())
                if v.get("kind") == "we"]
    we_stop()

    if not assigned:
        try:
            os.remove(WE_MARKER)
        except OSError:
            pass
        return

    args = ["linux-wallpaperengine"]
    for output, wid in assigned:
        d = we_dir(wid)
        if not os.path.isdir(d):
            continue
        args += ["--screen-root", output, "--bg", d, "--scaling", "fill"]
    if len(args) == 1:
        return
    args += ["--silent", "-f", str(WE_FPS), "--assets-dir", WE_ASSETS]

    log = open("/tmp/we-current.log", "wb")
    subprocess.Popen(args, stdout=log, stderr=subprocess.STDOUT,
                     stdin=subprocess.DEVNULL, start_new_session=True)

    with open(WE_MARKER, "w") as f:
        f.write("\n".join(f"{o}\t{w}" for o, w in assigned) + "\n")


# ── swww ─────────────────────────────────────────────────────────────────

def swww_running():
    """swww was renamed awww upstream and this machine reaches it through a
    /usr/local/bin/swww-daemon shim, so the daemon's comm is whichever name it
    happened to be launched under. Matching only one would miss a live daemon
    and start a second one on top of it."""
    for name in ("swww-daemon", "awww-daemon"):
        r = subprocess.run(["pgrep", "-x", name],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if r.returncode == 0:
            return True
    return False


def swww_ensure():
    import time
    if swww_running():
        return
    subprocess.Popen(["swww-daemon"], stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL,
                     start_new_session=True)
    for _ in range(30):
        time.sleep(0.2)
        if swww_running():
            return


def swww_apply(output, path, animate=True):
    swww_ensure()
    cmd = ["swww", "img", path, "--outputs", output, "--resize", "crop"]
    if animate:
        cmd += ["--transition-type", "any", "--transition-step", "90",
                "--transition-duration", "1.5", "--transition-fps", "60"]
    else:
        cmd += ["--transition-type", "none"]
    subprocess.run(cmd, check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def source_image(entry):
    """The still image representing an output's wallpaper."""
    if not entry:
        return None
    if entry.get("kind") == "we":
        return we_preview(entry.get("id"))
    p = entry.get("path")
    return p if p and os.path.isfile(p) else None


# ── themes ───────────────────────────────────────────────────────────────

def load_themes():
    try:
        with open(THEMES_FILE) as f:
            themes = json.load(f)
        if isinstance(themes, list) and themes:
            return themes
    except (OSError, ValueError):
        pass
    return [{"id": THEME_DEFAULT, "name": "Mono", "seed": "#ffffff",
             "scheme": "scheme-monochrome"}]


def theme_by_id(tid):
    for t in load_themes():
        if t["id"] == tid:
            return t
    return None


def system_theme():
    """The theme the machine-wide targets wear: whichever was applied last."""
    try:
        with open(THEME_FILE) as f:
            tid = json.load(f).get("system", "")
        if theme_by_id(tid):
            return tid
    except (OSError, ValueError, AttributeError):
        pass
    return THEME_DEFAULT


def set_system_theme(tid):
    tmp = THEME_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump({"system": tid}, f)
    os.replace(tmp, THEME_FILE)


def output_theme(state, output):
    tid = (state.get(output) or {}).get("theme", "")
    return tid if theme_by_id(tid) else system_theme()


def pin_themes(state):
    """Write each output's effective theme into its entry. An entry saved
    before themes existed has none and falls back to the system theme, so
    without this, applying a theme to one monitor would drag every such
    monitor along with it."""
    for o, e in state.items():
        if isinstance(e, dict) and not theme_by_id(e.get("theme", "")):
            e["theme"] = system_theme()


def load_index():
    """The wallpaper index, built on demand when it does not exist yet."""
    if not os.path.isfile(INDEX):
        subprocess.run([sys.executable, INDEXER], check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        with open(INDEX) as f:
            return json.load(f)
    except (OSError, ValueError):
        return []


def indexed_theme(key):
    for e in load_index():
        if e.get("key") == key:
            return e.get("theme", "")
    return ""


def pool(tid):
    """Stills that belong to a theme. Scenes are left out of random picks:
    each one starts a GPU-heavy linux-wallpaperengine render."""
    return [e["path"] for e in load_index()
            if e.get("kind") == "image" and e.get("theme") == tid
            and os.path.isfile(e.get("path", ""))]


# ── palette ──────────────────────────────────────────────────────────────

def _hls(hexc):
    import colorsys
    r, g, b = (int(hexc[i:i + 2], 16) / 255.0 for i in (1, 3, 5))
    return colorsys.rgb_to_hls(r, g, b)


def _hex(h, l, s):
    import colorsys
    r, g, b = colorsys.hls_to_rgb(h % 1.0, max(0, min(1, l)), max(0, min(1, s)))
    return "#%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255))


# Terminal colours keep their meaning (red is still red) and are only nudged
# toward the theme's hue, the way Material harmonizes custom colours: at most
# 15 degrees, half the distance.
ANSI = {"red": "#ef6f6c", "green": "#8bd17c", "yellow": "#e8c86a",
        "blue": "#7aa6f0", "magenta": "#c792ea", "cyan": "#6cd0d0"}


def derived_roles(colors):
    """Roles matugen has no notion of: the terminal's ANSI colours and the
    shell's `success`, the same harmonized green as the terminal's."""
    ph, _pl, ps = _hls(colors.get("primary", "#ffffff"))
    out = {}
    for name, base in ANSI.items():
        h, l, s = _hls(base)
        if ps > 0.12:
            d = ((ph - h + 0.5) % 1.0) - 0.5
            h += max(-15 / 360, min(15 / 360, d * 0.5))
        out["ansi_" + name] = _hex(h, l, s)
        out["ansi_bright_" + name] = _hex(h, l + 0.08, s)
    out["success"] = out["ansi_green"]
    return out


def theme_colors(theme):
    """Material roles for a theme plus the derived ones. matugen's output is
    cached per seed and scheme; the derived roles are cheap and recomputed."""
    raw = matugen_roles(theme)
    if raw is None:
        return None
    colors = dict(raw)
    colors.update(derived_roles(raw))
    return colors


def matugen_roles(theme):
    os.makedirs(THEME_CACHE, exist_ok=True)
    path = os.path.join(THEME_CACHE, theme["id"] + ".json")
    key = theme["seed"] + "|" + theme["scheme"]
    try:
        with open(path) as f:
            cached = json.load(f)
        if cached.get("key") == key:
            return cached["colors"]
    except (OSError, ValueError, KeyError):
        pass
    r = subprocess.run(["matugen", "color", "hex", theme["seed"], "--mode", "dark",
                        "--type", theme["scheme"], "--dry-run", "--json", "hex"],
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    try:
        raw = json.loads(r.stdout)["colors"]
    except (ValueError, KeyError):
        return None
    colors = {}
    for role, variants in raw.items():
        c = variants.get("dark") or variants.get("default") or {}
        if c.get("color"):
            colors[role] = c["color"].lower()
    with open(path, "w") as f:
        json.dump({"key": key, "colors": colors}, f)
    return colors


TOKEN = re.compile(r"\{\{\s*colors\.([a-z0-9_]+)\.(?:default|dark|light)\.(hex_stripped|hex)\s*\}\}")


def render(text, colors):
    def sub(m):
        c = colors.get(m.group(1))
        if c is None:
            return m.group(0)
        return c[1:] if m.group(2) == "hex_stripped" else c
    return TOKEN.sub(sub, text)


def write_if_changed(path, text):
    """In place, not by rename: Quickshell's FileViews and GTK's monitors
    watch these paths, and a rename swaps the inode out from under them."""
    try:
        with open(path) as f:
            if f.read() == text:
                return False
    except OSError:
        pass
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)
    return True


def system_templates():
    import tomllib
    try:
        with open(MATUGEN_CONFIG, "rb") as f:
            cfg = tomllib.load(f)
    except (OSError, ValueError):
        return []
    out = []
    for t in (cfg.get("templates") or {}).values():
        src = os.path.expanduser(t.get("input_path", ""))
        dst = os.path.expanduser(t.get("output_path", ""))
        if src and dst:
            out.append((src, dst))
    return out


def theme_css(theme):
    """The Quickshell palette for a theme, also what the switcher previews."""
    colors = theme_colors(theme)
    if colors is None:
        return None
    with open(QS_TEMPLATE) as f:
        css = render(f.read(), colors)
    path = os.path.join(THEME_CACHE, theme["id"] + ".css")
    write_if_changed(path, css)
    return css


def retheme(state, mons):
    """Render every palette target from the state.

    Machine-wide targets come from the system theme; each output then gets a
    Quickshell palette of its own theme. The reload helpers only run when a
    machine-wide file actually changed, so recolouring one monitor does not
    nudge GTK, nvim or the terminals.
    """
    sys_theme = theme_by_id(system_theme())
    colors = theme_colors(sys_theme)
    if colors is None:
        notify("Theme", "matugen failed", critical=True)
        return False

    changed = False
    for src, dst in system_templates():
        try:
            with open(src) as f:
                text = f.read()
        except OSError:
            continue
        changed |= write_if_changed(dst, render(text, colors))

    live = set()
    for m in mons:
        live.add(m["name"])
        css = theme_css(theme_by_id(output_theme(state, m["name"])))
        if css is not None:
            write_if_changed(os.path.join(QS_DIR, f"colors-{m['name']}.css"), css)

    # A monitor that has gone away must not leave a stale palette for one that
    # reappears under the same name with another theme.
    try:
        for n in os.listdir(QS_DIR):
            if n.startswith("colors-") and n.endswith(".css") \
                    and n[len("colors-"):-len(".css")] not in live:
                os.remove(os.path.join(QS_DIR, n))
    except OSError:
        pass

    if changed:
        # GTK reads the colours out of an @import its file monitor does not
        # watch, and the icon theme's folder colour is a rebuild of
        # ~/.local/share/icons/Tela-native; Ghostty rereads its config on SIGUSR2.
        for helper in ("gtk-theme-sync", "icon-theme-sync", "nvim-theme-reload"):
            subprocess.run([os.path.join(HOME, ".local/bin", helper)], check=False,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["pkill", "-USR2", "-x", "ghostty"], check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return True


THEME_LOCK = os.path.join(CACHE_DIR, "theme.lock")
THEME_REQ = os.path.join(CACHE_DIR, "theme.req")
THEME_DONE = os.path.join(CACHE_DIR, "theme.done")


def _mtime(path):
    try:
        return os.stat(path).st_mtime_ns
    except OSError:
        return 0


def retheme_async():
    """Queue a retheme and return immediately, so the wallpaper change itself
    is never stuck behind the GTK/nvim reload work. Latest-wins: the worker
    rethemes from whatever the state file says when it runs, and re-runs if
    another request lands mid-pass, so rapid changes collapse into the minimum
    number of passes instead of queueing one each."""
    os.makedirs(CACHE_DIR, exist_ok=True)
    with open(THEME_REQ, "w"):
        pass
    subprocess.Popen(
        [sys.executable, os.path.abspath(__file__), "theme-worker"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        stdin=subprocess.DEVNULL, start_new_session=True)


def cmd_theme_worker():
    """Background retheme worker. The flock serializes workers (concurrent
    passes would race writing the same palette files); the REQ/DONE mtime
    pair lets a worker that queued behind another exit without repeating work
    its predecessor already covered."""
    import fcntl

    os.makedirs(CACHE_DIR, exist_ok=True)
    with open(THEME_LOCK, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if _mtime(THEME_REQ) <= _mtime(THEME_DONE):
            return
        while True:
            req = _mtime(THEME_REQ)
            retheme(load_state(), monitors())
            with open(THEME_DONE, "w"):
                pass
            if _mtime(THEME_REQ) <= req:
                return


# ── commands ─────────────────────────────────────────────────────────────

def apply_all(state, mons, animate=True):
    for m in mons:
        e = state.get(m["name"])
        if e and e.get("kind") == "image" and os.path.isfile(e.get("path", "")):
            swww_apply(m["name"], e["path"], animate=animate)
    we_sync(state)


def resolve_theme(tid, key, state, outs):
    """An explicit theme wins, then the index's verdict for the wallpaper,
    then whatever the first target output already wears."""
    if tid and theme_by_id(tid):
        return tid
    tid = indexed_theme(key)
    if theme_by_id(tid):
        return tid
    return output_theme(state, outs[0]) if outs else system_theme()


def cmd_set(arg, path, tid=""):
    path = os.path.abspath(os.path.expanduser(path))
    if not os.path.isfile(path):
        die(f"not found: {path}")
    mons = monitors()
    state = load_state()
    pin_themes(state)
    outs = targets(arg, mons)
    tid = resolve_theme(tid, path, state, outs)

    had_we = any(state.get(o, {}).get("kind") == "we" for o in outs)
    for o in outs:
        state[o] = {"kind": "image", "path": path, "theme": tid}
    save_state(state)
    set_system_theme(tid)

    for o in outs:
        swww_apply(o, path)
    if had_we:
        we_sync(state)
    retheme_async()


def cmd_set_we(arg, wid, tid=""):
    wid = str(wid)
    if not os.path.isdir(we_dir(wid)):
        die(f"wallpaper {wid} not found")
    mons = monitors()
    state = load_state()
    pin_themes(state)
    outs = targets(arg, mons)
    tid = resolve_theme(tid, "we:" + wid, state, outs)

    for o in outs:
        # The preview rides along in the state so the lock screen can show a
        # still for the scene without any filesystem probing of its own.
        state[o] = {"kind": "we", "id": wid, "preview": we_preview(wid) or "",
                    "theme": tid}
    save_state(state)
    set_system_theme(tid)

    we_sync(state)
    retheme_async()

    title = ""
    try:
        with open(os.path.join(we_dir(wid), "project.json")) as f:
            title = json.load(f).get("title", "") or ""
    except (OSError, ValueError):
        pass
    notify("Wallpaper Engine", title or wid)


def pick(paths, n, avoid):
    """n stills, distinct while the pool allows, preferring ones not already
    on screen so a re-roll always changes something."""
    fresh = [p for p in paths if p not in avoid] or list(paths)
    random.shuffle(fresh)
    return [fresh[i % len(fresh)] for i in range(n)]


def set_many(choices, state, mons):
    """choices: output -> (path, theme). One state write, one retheme."""
    had_we = any(state.get(o, {}).get("kind") == "we" for o in choices)
    for o, (path, tid) in choices.items():
        state[o] = {"kind": "image", "path": path, "theme": tid}
    save_state(state)
    for o, (path, _tid) in choices.items():
        swww_apply(o, path)
    if had_we:
        we_sync(state)
    retheme_async()


def cmd_apply(arg, tid):
    if not theme_by_id(tid):
        die(f"unknown theme: {tid}")
    paths = pool(tid)
    if not paths:
        die(f"no wallpapers in the {tid} theme")
    mons = monitors()
    state = load_state()
    pin_themes(state)
    outs = targets(arg, mons)
    avoid = {(state.get(o) or {}).get("path") for o in state}
    chosen = pick(paths, len(outs), avoid)
    set_system_theme(tid)
    set_many({o: (p, tid) for o, p in zip(outs, chosen)}, state, mons)


def cmd_random(arg):
    mons = monitors()
    state = load_state()
    outs = targets(arg, mons)
    avoid = {(state.get(o) or {}).get("path") for o in state}
    choices = {}
    for o in outs:
        tid = output_theme(state, o)
        paths = pool(tid)
        if not paths:
            continue
        p = pick(paths, 1, avoid)[0]
        avoid.add(p)
        choices[o] = (p, tid)
    if not choices:
        die("no wallpapers in the current theme")
    set_many(choices, state, mons)


def cmd_restore():
    mons = monitors()
    state = load_state()
    if not state:
        return
    stale = [o for o in state if o not in {m["name"] for m in mons}]
    apply_all(state, mons, animate=False)
    if stale:
        print(f"note: saved outputs not connected: {', '.join(stale)}",
              file=sys.stderr)


def cmd_import_waypaper():
    """Adopt whatever the waypaper GUI just applied.

    waypaper stores per-monitor choices as parallel newline-joined `monitors`
    and `wallpaper` lists (or the literal "All"), and applies them itself — so
    this only records them and rebuilds the palette. Read raw, because the
    config holds a post_command containing "$wallpaper" and other % / $ text
    that interpolation would choke on.
    """
    import configparser

    cfg = os.path.join(HOME, ".config/waypaper/config.ini")
    cp = configparser.RawConfigParser()
    try:
        cp.read(cfg)
        mons_raw = cp.get("Settings", "monitors", fallback="All")
        paps_raw = cp.get("Settings", "wallpaper", fallback="")
    except (configparser.Error, OSError):
        return

    names = [s.strip() for s in mons_raw.split("\n") if s.strip()]
    paths = [os.path.expanduser(s.strip()) for s in paps_raw.split("\n") if s.strip()]
    if not paths:
        return

    mons = monitors()
    state = load_state()
    connected = [m["name"] for m in mons]

    def entry(o, p):
        return {"kind": "image", "path": p,
                "theme": resolve_theme("", p, state, [o])}

    if names[:1] == ["All"] or not names:
        for o in connected:
            state[o] = entry(o, paths[0])
    else:
        for name, path in zip(names, paths):
            if name in connected:
                state[name] = entry(name, path)

    save_state(state)
    we_sync(state)
    retheme_async()


def cmd_theme():
    retheme(load_state(), monitors())


def cmd_theme_list():
    """Every theme with the swatches matugen really produces for it and the
    path of its rendered Quickshell palette, plus who wears what."""
    mons = monitors()
    state = load_state()
    remember_last(state)
    walls = theme_wallpapers()
    themes = []
    for t in load_themes():
        colors = theme_colors(t) or {}
        theme_css(t)
        themes.append({
            "id": t["id"],
            "name": t["name"],
            "primary": colors.get("primary", t["seed"]),
            "swatches": [colors[r] for r in SWATCH_ROLES if r in colors],
            "surface": colors.get("surface_container", "#1b1b1b"),
            "surfaceHigh": colors.get("surface_container_high", "#262626"),
            "text": colors.get("on_surface_variant", "#c6c6c6"),
            "css": os.path.join(THEME_CACHE, t["id"] + ".css"),
            "wallpaper": walls.get(t["id"], ""),
        })
    print(json.dumps({
        "themes": themes,
        "system": system_theme(),
        "outputs": {m["name"]: output_theme(state, m["name"]) for m in mons},
    }))


def cmd_show():
    mons = monitors()
    state = load_state()
    out = {}
    for m in mons:
        e = state.get(m["name"]) or {}
        out[m["name"]] = {
            "kind": e.get("kind", ""),
            "path": e.get("path", ""),
            "id": e.get("id", ""),
            "theme": output_theme(state, m["name"]),
            "preview": source_image(e) or "",
        }
    print(json.dumps({"system": system_theme(), "outputs": out},
                     indent=2, sort_keys=True))


def main():
    if len(sys.argv) < 2:
        print(__doc__.strip(), file=sys.stderr)
        sys.exit(2)
    cmd = sys.argv[1]
    a = sys.argv[2:]
    if cmd == "set" and len(a) in (2, 3):
        cmd_set(a[0], a[1], a[2] if len(a) == 3 else "")
    elif cmd == "set-we" and len(a) in (2, 3):
        cmd_set_we(a[0], a[1], a[2] if len(a) == 3 else "")
    elif cmd == "apply" and len(a) == 2:
        cmd_apply(a[0], a[1])
    elif cmd == "random" and len(a) == 1:
        cmd_random(a[0])
    elif cmd == "restore" and not a:
        cmd_restore()
    elif cmd == "theme" and not a:
        cmd_theme()
    elif cmd == "theme-list" and not a:
        cmd_theme_list()
    elif cmd == "theme-worker" and not a:
        cmd_theme_worker()
    elif cmd == "import-waypaper" and not a:
        cmd_import_waypaper()
    elif cmd == "show" and not a:
        cmd_show()
    else:
        print(__doc__.strip(), file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
