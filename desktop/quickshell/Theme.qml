import QtQuick
import Quickshell.Io

QtObject {
    id: root

    // ── legacy aliases ────────────────────────────────────────────────
    // The names the shell was originally written against. matugen still
    // emits them, so they keep resolving; new code should prefer the real
    // Material role names below, which carry the tonal relationships the
    // wallpaper actually produced instead of an approximation of them.
    property color bg: "#1c2024"          // = surface_container
    property color base: "#101417"        // = surface
    property color fg: "#e0e3e8"          // = on_surface
    property color muted: "#8b9198"       // = outline
    property color accent: "#97ccf9"      // = primary
    property color accent2: "#d0bfe7"     // = tertiary
    property color accent3: "#b8c8d9"     // = secondary
    property color warn: "#ffb4ab"        // = error

    // ── source ────────────────────────────────────────────────────────
    property color source_color: "#97ccf9"

    // ── primary ───────────────────────────────────────────────────────
    property color primary: "#97ccf9"
    property color on_primary: "#003353"
    property color primary_container: "#004a77"
    property color on_primary_container: "#cfe5ff"
    property color primary_fixed: "#cfe5ff"
    property color primary_fixed_dim: "#97ccf9"
    property color on_primary_fixed: "#001d33"
    property color on_primary_fixed_variant: "#004a77"
    property color inverse_primary: "#31628d"

    // ── secondary ─────────────────────────────────────────────────────
    property color secondary: "#b8c8d9"
    property color on_secondary: "#23323f"
    property color secondary_container: "#3a4856"
    property color on_secondary_container: "#d4e4f6"
    property color secondary_fixed: "#d4e4f6"
    property color secondary_fixed_dim: "#b8c8d9"
    property color on_secondary_fixed: "#0e1d2a"
    property color on_secondary_fixed_variant: "#3a4856"

    // ── tertiary ──────────────────────────────────────────────────────
    property color tertiary: "#d0bfe7"
    property color on_tertiary: "#362b4a"
    property color tertiary_container: "#4d4162"
    property color on_tertiary_container: "#ecdcff"
    property color tertiary_fixed: "#ecdcff"
    property color tertiary_fixed_dim: "#d0bfe7"
    property color on_tertiary_fixed: "#211634"
    property color on_tertiary_fixed_variant: "#4d4162"

    // ── error ─────────────────────────────────────────────────────────
    property color error: "#ffb4ab"
    property color on_error: "#690005"
    property color error_container: "#93000a"
    property color on_error_container: "#ffdad6"

    // ── success ───────────────────────────────────────────────────────
    // Derived by wallpapers.py, not matugen: green harmonized toward the
    // theme, for the good states (charging, copied) that must stay green.
    property color success: "#8bd17c"

    // ── surfaces ──────────────────────────────────────────────────────
    property color background: "#101417"
    property color on_background: "#e0e3e8"
    property color surface: "#101417"
    property color on_surface: "#e0e3e8"
    property color surface_variant: "#42474e"
    property color on_surface_variant: "#c2c7cf"
    property color surface_dim: "#101417"
    property color surface_bright: "#363a3e"
    property color surface_container_lowest: "#0b0f12"
    property color surface_container_low: "#191c20"
    property color surface_container: "#1c2024"
    property color surface_container_high: "#272a2e"
    property color surface_container_highest: "#313539"
    property color surface_tint: "#97ccf9"
    property color inverse_surface: "#e0e3e8"
    property color inverse_on_surface: "#2d3135"

    // ── outline & shadow ──────────────────────────────────────────────
    property color outline: "#8b9198"
    property color outline_variant: "#42474e"
    property color shadow: "#000000"
    property color scrim: "#000000"

    // Body and display faces come from the settings (Font); the
    // fallbacks are what the shell wore before the split.
    readonly property string fontSans: IslandState.cfg.fontBody || "Adwaita Sans"
    readonly property string fontDisplay: IslandState.cfg.fontDisplay || fontSans
    readonly property string fontMono: "JetBrainsMono Nerd Font"
    // The clocks: the display cut with tabular figures (so the minutes do
    // not shift sideways as digits change), or the mono they used to wear.
    readonly property bool clockDisplay: IslandState.cfg.clockFont !== "mono"
    readonly property string fontClock: clockDisplay ? fontDisplay : fontMono
    readonly property var clockFeatures: clockDisplay ? ({ "tnum": 1 }) : ({})
    readonly property int fontSize: 13
    readonly property int radius: 12
    readonly property real pillOpacity: 0.85
    // The island's own fill, black rather than a palette role. Deliberately not
    // in roleNames: the parser only assigns names listed there, so matugen
    // cannot repaint this on a wallpaper change the way it would `base` or
    // `bg`. Its opacity is the user's knob now — IslandState.cfg.islandOpacity,
    // default 0.92 — at which it reads as near-black with the wallpaper barely
    // lifting it; 1.0 in the settings window gives a flat black.
    readonly property color islandBg: "#000000"
    // Chrome that floats above the wallpaper — menus, OSD, tooltips, the
    // launcher. These sat at 0.97, visually opaque, so the compositor blur
    // underneath them never showed.
    readonly property real surfaceOpacity: 0.72
    // Panels you click open from a bar module to *read* something: the
    // calendar, the media popup, notifications. Denser than surfaceOpacity so
    // text and dates stay comfortable against a busy wallpaper — glass is a
    // backdrop here, not the point.
    readonly property real contentOpacity: 0.92
    // Full-screen backdrop behind the launcher and power menu. Above the
    // layerrule's ignore_alpha threshold, so the whole screen frosts while an
    // overlay is open.
    readonly property real scrimOpacity: 0.35

    // Every role matugen emits, in the order the template writes them. The
    // parser only assigns names present here, so a stray @define-color in the
    // CSS cannot invent a property on this object.
    readonly property var roleNames: [
        "bg", "base", "fg", "muted", "accent", "accent2", "accent3", "warn",
        "source_color",
        "primary", "on_primary", "primary_container", "on_primary_container",
        "primary_fixed", "primary_fixed_dim", "on_primary_fixed",
        "on_primary_fixed_variant", "inverse_primary",
        "secondary", "on_secondary", "secondary_container",
        "on_secondary_container", "secondary_fixed", "secondary_fixed_dim",
        "on_secondary_fixed", "on_secondary_fixed_variant",
        "tertiary", "on_tertiary", "tertiary_container", "on_tertiary_container",
        "tertiary_fixed", "tertiary_fixed_dim", "on_tertiary_fixed",
        "on_tertiary_fixed_variant",
        "error", "on_error", "error_container", "on_error_container",
        "success",
        "background", "on_background", "surface", "on_surface",
        "surface_variant", "on_surface_variant", "surface_dim", "surface_bright",
        "surface_container_lowest", "surface_container_low", "surface_container",
        "surface_container_high", "surface_container_highest", "surface_tint",
        "inverse_surface", "inverse_on_surface",
        "outline", "outline_variant", "shadow", "scrim"
    ]

    // Blend `top` over opaque `bottom` at `amount`, returning an opaque colour.
    // This is what Qt.alpha(c, a) *looks* like only when the thing behind it is
    // actually `bottom`; on a translucent panel Qt.alpha composites against the
    // wallpaper instead, so the same call lands on a different colour for every
    // image. Use this wherever the result is meant to be a fixed tone.
    function mix(top, bottom, amount) {
        const t = Math.max(0, Math.min(1, amount));
        return Qt.rgba(bottom.r + (top.r - bottom.r) * t,
                       bottom.g + (top.g - bottom.g) * t,
                       bottom.b + (top.b - bottom.b) * t,
                       1);
    }

    function applyCss(text) {
        // Names carry underscores and matugen can emit 8-digit hex, so both are
        // matched here; the original pattern accepted neither.
        const re = /@define-color\s+([A-Za-z0-9_-]+)\s+(#[0-9a-fA-F]{8}|#[0-9a-fA-F]{6})/g;
        const valid = {};
        for (let i = 0; i < root.roleNames.length; i++)
            valid[root.roleNames[i]] = true;

        let m;
        while ((m = re.exec(text)) !== null) {
            if (valid[m[1]] === true)
                root[m[1]] = m[2];
        }
    }

    // Which monitor this palette belongs to. Quickshell draws one bar per
    // screen, so each can carry the theme that monitor wears; wallpapers.py
    // writes colors-<output>.css alongside the shared colors.css. Left empty,
    // this is the shared palette — the system theme, the one applied last —
    // which is also the fallback when an output has no file of its own yet.
    property string output: ""
    property bool outputMissing: false

    // Set false for a palette that ignores matugen and keeps the values
    // compiled in above. With no path the FileView never loads, so applyCss
    // never runs and nothing repaints when the wallpaper changes — which is
    // the whole point: a surface that must look the same on every monitor and
    // through every retheme cannot be sourced from a per-wallpaper,
    // per-output file.
    property bool followWallpaper: true

    // An explicit palette file wins over the output's: the theme switcher
    // points one at ~/.cache/quickshell/themes/<id>.css to wear the theme
    // being browsed before it is applied.
    property string file: ""

    readonly property string paletteFile:
        !followWallpaper ? ""
        : file !== "" ? file
        : ((output !== "" && !outputMissing)
           ? "@HOME@/.config/quickshell/colors-" + output + ".css"
           : "@HOME@/.config/quickshell/colors.css")

    property var _palette: FileView {
        path: root.paletteFile
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.applyCss(text())
        onLoadFailed: {
            if (root.output !== "" && !root.outputMissing)
                root.outputMissing = true;
        }
    }

    // A monitor plugged in after the last retheme has no palette of its own
    // yet. Retry on a timer rather than straight from onLoadFailed, which would
    // ping-pong between the two paths forever. Nothing repaints on a failed
    // retry — applyCss only runs on a successful load — so the shared palette
    // stays on screen until the real one appears.
    property var _retry: Timer {
        interval: 4000
        repeat: true
        running: root.output !== "" && root.outputMissing
        onTriggered: root.outputMissing = false
    }
}
