import QtQuick
import Quickshell.Services.UPower

// The iPhone Duo's corner indicator, translated to this desktop: one circle
// where a row of status glyphs would sit. The ring is the one battery this
// machine actually has — the mouse — with head and tail growing from twelve
// o'clock down both sides to meet at the bottom when full. The glyph inside
// is the network profile as network-profile.sh resolves it, VPN taking
// precedence over the ethernet underneath, so a glance answers both "am I on
// the VPN" and "will the mouse die today".
Item {
    id: root

    property var theme
    property string screenName: ""
    property bool expanded: false

    // trailCap's sizing, so the detached pieces of the island read as one
    // family and breathe together on hover.
    implicitWidth: root.expanded ? 34 : 30
    implicitHeight: implicitWidth
    Behavior on implicitWidth { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

    // UPower rather than devicebat.sh: the script exists for the battery
    // *tool*, which also folds in per-bud AirPods detail over bluez. The ring
    // needs one number that updates itself, and hidpp batteries already sit
    // in UPower — reactive, nothing to poll. A mouse outranks whatever other
    // peripheral shows up; isLaptopBattery keeps a future laptop's own cell
    // off a ring that means "peripheral".
    readonly property var dev: {
        const list = UPower.devices.values;
        let best = null;
        for (let i = 0; i < list.length; i++) {
            const d = list[i];
            if (!d.ready || d.isLaptopBattery) continue;
            // Asleep hidpp receivers surface a ghost device pinned to zero;
            // a reading of nothing is not a reading.
            if (d.percentage <= 0) continue;
            if (d.type === UPowerDeviceType.Mouse) return d;
            if (best === null) best = d;
        }
        return best;
    }
    readonly property real pct: root.dev ? root.dev.percentage : -1
    readonly property bool charging:
        root.dev !== null && root.dev.state === UPowerDeviceState.Charging

    readonly property real warnAt: IslandState.cfg.statusWarnPct / 100

    // The battery tool's ladder, scaled to the configurable threshold — at the
    // default 20% the two agree exactly; moving the slider moves only the
    // ring, since the tool's list keeps its fixed steps. Charging is the
    // theme's `success`: still green in every theme, only nudged toward it.
    readonly property color ringColor: {
        if (root.charging) return root.theme.success;
        if (root.pct < 0) return root.theme.muted;
        if (root.pct <= root.warnAt) return root.theme.warn;
        if (root.pct <= root.warnAt * 2) return root.theme.accent2;
        return root.theme.accent;
    }

    // The same codepoints network-profile.sh puts on the bar, so the circle
    // and the tile can never show different pictures of the same link.
    readonly property string netGlyph: {
        switch (IslandState.netKind) {
        case "vpn":          return "\u{f0582}";
        case "wifi":         return "\u{f05a9}";
        case "disconnected": return "\u{f002a}";
        default:             return "\u{f0200}";
        }
    }
    readonly property color netColor:
        IslandState.netKind === "vpn" ? root.theme.accent
        : IslandState.netKind === "disconnected" ? root.theme.warn
        : Qt.alpha(root.theme.fg, 0.85)

    // The whole circle leans in under the pointer — ring, glyph and fill
    // together — the same life the rail buttons had.
    scale: hov.hovered ? 1.08 : 1
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        // The pill's own fill and opacity — a detached piece of the island,
        // not a bar widget parked next to one.
        color: IslandState.notch ? "transparent"
             : Qt.rgba(root.theme.islandBg.r, root.theme.islandBg.g,
                       root.theme.islandBg.b, IslandState.cfg.islandOpacity)
        border.width: IslandState.notch ? 0 : 1
        border.color: hov.hovered ? Qt.alpha(root.theme.accent, 0.45)
                    : Qt.alpha(root.theme.accent, root.expanded ? 0.28 : 0.06)
        Behavior on border.color { ColorAnimation { duration: 220 } }
    }

    RingProgress {
        anchors.fill: parent
        anchors.margins: 2
        symmetric: true
        progress: Math.max(0, root.pct)
        ring: root.ringColor
        track: root.theme.fg
        trackAlpha: 0.10
        thickness: 2
    }

    Text {
        anchors.centerIn: parent
        text: root.netGlyph
        color: root.netColor
        font.family: root.theme.fontMono
        font.pixelSize: root.expanded ? 14 : 12
        Behavior on color { ColorAnimation { duration: 220 } }
    }

    HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        // Right-click cycles the VPN profiles — the network half of the
        // circle gets the network action, same as the old bar tile — and
        // left-click opens whichever tool the settings point it at.
        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) { IslandState.cycleNetwork(); return; }
            IslandState.toggleTool(IslandState.cfg.statusClick, root.screenName);
        }
    }
}
