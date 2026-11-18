import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// The screen's corners, MacBook style, for one monitor:
//   - all four: black fillets on the overlay layer, the way a display's own
//     rounded glass looks — the top pair cuts into the menu bar's ends,
//     exactly as a MacBook's screen corners round off its menu bar.
//   - privacy dots: the mic/camera pair in the top-right corner, on the
//     overlay layer, shown only when the bar's own Status item cannot be
//     seen — the bar is off, or a fullscreen window covers it.
// The corners belong to the menu bar's look and only show while it is on;
// without it the screen is as it was before. Every surface here is click-through (empty input mask) and ignores the
// other panels' reserved zones, so it never moves a window.
Scope {
    id: root

    required property var screen
    property var theme

    readonly property int r: IslandState.cfg.cornerRadius
    // The fillets under the bar match the windows' own corner rounding
    // (decoration.rounding in hyprland.lua), so they fill exactly the
    // triangle a rounded window corner leaves open at the screen edge.
    readonly property int ur: IslandState.cfg.winRounding
    readonly property real band: IslandState.barBand
    // Follows the band, clear over an empty workspace included.
    property real barAlpha: IslandState.barAlpha(root.screen.name)
    Behavior on barAlpha { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    readonly property color barColor: root.theme
        ? Qt.rgba(root.theme.islandBg.r, root.theme.islandBg.g, root.theme.islandBg.b, root.barAlpha)
        : "transparent"
    property bool barsVisible: true
    readonly property bool barOn: IslandState.cfg.menuBar
    // Corners and fillets step aside during a Flameshot capture.
    readonly property bool capturing: IslandState.capturingOn(root.screen.name)

    readonly property var hyprMon: Hyprland.monitorFor(root.screen)
    // Hyprland's hasFullscreen also counts a maximized window, which leaves
    // the bar in plain view. The Wayland toplevel's own flag is the real
    // fullscreen only, so both have to agree.
    readonly property bool fullscreen: {
        if (root.hyprMon === null || root.hyprMon.activeWorkspace === null
            || !root.hyprMon.activeWorkspace.hasFullscreen) return false;
        const ts = ToplevelManager.toplevels.values;
        for (let i = 0; i < ts.length; i++) {
            if (!ts[i].fullscreen) continue;
            const ss = ts[i].screens || [];
            for (let j = 0; j < ss.length; j++) if (ss[j] && ss[j].name === root.screen.name) return true;
        }
        return false;
    }

    // A concave fillet: the corner square minus a quarter disc. Drawn as a
    // ring whose hole is the disc, clipped to the square; (cx, cy) is where
    // the disc's centre sits inside the square.
    component Fillet: Item {
        id: f
        property real cx: 0
        property real cy: 0
        property real rad: root.r
        property color fill: "black"
        width: f.rad
        height: f.rad
        clip: true
        Rectangle {
            x: f.cx - 2 * f.rad
            y: f.cy - 2 * f.rad
            width: 4 * f.rad
            height: 4 * f.rad
            radius: 2 * f.rad
            color: "transparent"
            border.width: f.rad
            border.color: f.fill
        }
    }

    component Corner: PanelWindow {
        id: cw
        property bool atTop: true
        property bool atLeft: true
        property color fill: "black"
        property real rad: root.r
        screen: root.screen
        anchors { top: cw.atTop; bottom: !cw.atTop; left: cw.atLeft; right: !cw.atLeft }
        exclusionMode: ExclusionMode.Ignore
        implicitWidth: Math.max(1, cw.rad)
        implicitHeight: Math.max(1, cw.rad)
        color: "transparent"
        mask: Region {}
        Fillet {
            fill: cw.fill
            rad: cw.rad
            cx: cw.atLeft ? cw.rad : 0
            cy: cw.atTop ? cw.rad : 0
        }
    }

    // ── top: the screen's own corners, over the bar's ends ────────
    Corner {
        atTop: true; atLeft: true
        visible: root.r > 0 && !root.capturing && IslandState.cfg.menuBar && IslandState.cfg.cornersTop
        WlrLayershell.layer: WlrLayer.Overlay
        fill: "black"
    }
    Corner {
        atTop: true; atLeft: false
        visible: root.r > 0 && !root.capturing && IslandState.cfg.menuBar && IslandState.cfg.cornersTop
        WlrLayershell.layer: WlrLayer.Overlay
        fill: "black"
    }

    // ── under the bar: bar-coloured, filling the window's corner ──
    // On the bar's layer and in its namespace, so they frost with it and go
    // under a fullscreen window with it.
    Corner {
        atTop: true; atLeft: true
        visible: root.ur > 0 && !root.capturing && IslandState.cfg.menuBar && root.barsVisible && IslandState.cfg.barFillets
        WlrLayershell.namespace: "quickshell-bar"
        margins.top: root.band
        rad: root.ur
        fill: root.barColor
    }
    Corner {
        atTop: true; atLeft: false
        visible: root.ur > 0 && !root.capturing && IslandState.cfg.menuBar && root.barsVisible && IslandState.cfg.barFillets
        WlrLayershell.namespace: "quickshell-bar"
        margins.top: root.band
        rad: root.ur
        fill: root.barColor
    }

    // ── bottom: the display's own corners ─────────────────────────
    Corner {
        atTop: false; atLeft: true
        visible: root.r > 0 && !root.capturing && IslandState.cfg.menuBar && IslandState.cfg.cornersBottom
        WlrLayershell.layer: WlrLayer.Overlay
        fill: "black"
    }
    Corner {
        atTop: false; atLeft: false
        visible: root.r > 0 && !root.capturing && IslandState.cfg.menuBar && IslandState.cfg.cornersBottom
        WlrLayershell.layer: WlrLayer.Overlay
        fill: "black"
    }

    // ── privacy dots, when the bar cannot show them ───────────────
    PanelWindow {
        screen: root.screen
        anchors { top: true; right: true }
        margins { top: 6; right: 10 }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        implicitWidth: dots.implicitWidth + 8
        implicitHeight: 14
        color: "transparent"
        mask: Region {}
        visible: IslandState.cfg.cornerDots && (IslandState.micInUse || IslandState.videoInUse)
                 && (!root.barOn || root.fullscreen)
        Row {
            id: dots
            anchors.centerIn: parent
            spacing: 4
            // The platform's colours, whatever the theme.
            Rectangle {
                visible: IslandState.micInUse
                width: 6; height: 6; radius: 3
                color: "#ff9f0a"
            }
            Rectangle {
                visible: IslandState.videoInUse
                width: 6; height: 6; radius: 3
                color: "#30d158"
            }
        }
    }
}
