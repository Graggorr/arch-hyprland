import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// The power panel, laid out like the wireless one: the machine sits in the
// middle as an orb and what can be done to it floats around it. The switch
// along the bottom flips between Session (lock, logout, suspend near the
// orb; reboot, shutdown and Windows on the outer ring, since they end the
// session) and Idle (what happens after an hour alone). A session action is
// two clicks — pick the chip, then press the orb or the action chip
// bottom-left — so a stray click never takes the machine down. The round
// button bottom-right cycles the power profile.
Item {
    id: root

    property var theme

    // Fill the sheet: the radar lays itself out to whatever the card gives.
    readonly property real preferredHeight: 0

    property string mode: "session"   // "session" | "idle"
    property string selected: ""

    // The session is uwsm-managed, so logout goes through uwsm rather than
    // hl.dsp.exit(), which pulls the compositor out from under its own clients
    // and skips the ordered shutdown. Windows boots through the firmware's
    // one-shot BootNext, so the boot after it comes back here.
    readonly property var actions: [
        { key: "lock",     glyph: "\u{f033e}", name: "Lock",     ring: 1, ang: -90,
          cmd: ["qs", "ipc", "call", "lock", "lock"] },
        { key: "suspend",  glyph: "\u{f04b2}", name: "Suspend",  ring: 1, ang: 20,
          cmd: ["systemctl", "suspend"] },
        { key: "logout",   glyph: "\u{f0343}", name: "Logout",   ring: 1, ang: 160,
          cmd: ["uwsm", "stop"] },
        { key: "reboot",   glyph: "\u{f0709}", name: "Reboot",   ring: 2, ang: -150,
          cmd: ["systemctl", "reboot"], danger: true },
        { key: "shutdown", glyph: "\u{f0425}", name: "Shutdown", ring: 2, ang: -30,
          cmd: ["systemctl", "poweroff"], danger: true },
    ]
    readonly property var idleModes: [
        { key: "sleep", glyph: "\u{f04b2}", name: "Sleep",       sub: "suspend",    ring: 1, ang: -90 },
        { key: "dpms",  glyph: "\u{f0379}", name: "Screens off", sub: "stay awake", ring: 1, ang: 20 },
        { key: "off",   glyph: "\u{f0904}", name: "Disabled",    sub: "never idle", ring: 1, ang: 160 }
    ]

    readonly property var nodes: {
        if (root.mode === "idle")
            return root.idleModes.map(m => Object.assign({ on: IslandState.idleMode === m.key }, m));
        return root.actions.map(a => Object.assign({ on: false, sub: "" }, a));
    }
    readonly property var sel: {
        if (root.mode !== "session") return null;
        for (let i = 0; i < root.actions.length; i++)
            if (root.actions[i].key === root.selected) return root.actions[i];
        return null;
    }
    readonly property var idleCur: {
        for (let i = 0; i < root.idleModes.length; i++)
            if (root.idleModes[i].key === IslandState.idleMode) return root.idleModes[i];
        return root.idleModes[0];
    }

    function setMode(m) {
        if (root.mode === m) return;
        root.mode = m;
        root.selected = "";
    }
    function pick(n) {
        if (root.mode === "idle") { IslandState.setIdleMode(n.key); return; }
        root.selected = root.selected === n.key ? "" : n.key;
        if (root.selected !== "") selReset.restart();
    }
    // An armed shutdown left alone should not stay one click from firing.
    Timer { id: selReset; interval: 8000; onTriggered: root.selected = "" }

    // Spawned detached and before the card closes: closing the card unloads
    // this panel, and a Process child dies with the object that owns it.
    function act() {
        const a = root.sel;
        if (!a) return;
        root.selected = "";
        Quickshell.execDetached(a.cmd);
        IslandState.closeCard();
    }

    function cycleProfile() {
        const p = PowerProfiles.profile;
        if (p === PowerProfile.PowerSaver) PowerProfiles.profile = PowerProfile.Balanced;
        else if (p === PowerProfile.Balanced && PowerProfiles.hasPerformanceProfile)
            PowerProfiles.profile = PowerProfile.Performance;
        else PowerProfiles.profile = PowerProfile.PowerSaver;
    }
    readonly property bool profileOn: PowerProfiles.profile !== PowerProfile.Balanced
    readonly property string profileName: PowerProfiles.profile === PowerProfile.PowerSaver ? "Power saver"
        : PowerProfiles.profile === PowerProfile.Performance ? "Performance" : "Balanced"

    // Uptime, for the line under the orb when nothing is picked.
    property real upSecs: 0
    FileView {
        id: uptimeFile
        path: "/proc/uptime"
        onLoaded: root.upSecs = parseFloat(uptimeFile.text().split(" ")[0]) || 0
    }
    Timer { interval: 30000; running: true; repeat: true; onTriggered: uptimeFile.reload() }
    readonly property string uptime: {
        const m = Math.floor(root.upSecs / 60), h = Math.floor(m / 60), d = Math.floor(h / 24);
        return d > 0 ? d + " d " + (h % 24) + " h" : h > 0 ? h + " h " + (m % 60) + " min" : m + " min";
    }

    function reload() { IslandState.refreshIdleMode(); uptimeFile.reload(); }
    Component.onCompleted: IslandState.refreshIdleMode()

    // ── the radar ─────────────────────────────────────────────────
    Item {
        id: field
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: bar.top
        anchors.margins: 6

        readonly property real cx: width / 2
        readonly property real cy: height / 2
        readonly property real rx: width / 2 - 92
        readonly property real ry: height / 2 - 22
        function ringFrac(r) { return [0.5, 0.75, 1.0][r]; }

        Repeater {
            model: 3
            Rectangle {
                required property int index
                readonly property real f: field.ringFrac(index)
                x: field.cx - field.rx * f
                y: field.cy - field.ry * f
                width: field.rx * f * 2
                height: field.ry * f * 2
                radius: height / 2
                color: "transparent"
                border.width: 1
                border.color: Qt.alpha(root.theme.fg, 0.05 + 0.02 * (2 - index))
            }
        }

        // A slow pulse leaves the orb while a destructive action is picked.
        Repeater {
            model: 2
            Rectangle {
                id: pulse
                required property int index
                property real t: 0
                readonly property bool live: root.sel !== null && root.sel.danger === true
                x: field.cx - width / 2
                y: field.cy - height / 2
                width: 92 + (field.rx * 2 - 92) * t
                height: 92 + (field.ry * 2 - 92) * t
                radius: height / 2
                color: "transparent"
                border.width: 1.5
                border.color: Qt.alpha(root.theme.warn, 0.5 * (1 - t))
                visible: live
                SequentialAnimation on t {
                    running: pulse.live
                    loops: Animation.Infinite
                    PauseAnimation { duration: pulse.index * 1100 }
                    NumberAnimation { from: 0; to: 1; duration: 2200; easing.type: Easing.OutCubic }
                }
            }
        }

        // The orb: the machine. With an action picked it becomes that action.
        Rectangle {
            id: orb
            width: 92; height: 92; radius: 46
            x: field.cx - 46; y: field.cy - 46
            color: Qt.darker(root.theme.base, 1.5)
            border.width: 1
            border.color: Qt.alpha(root.theme.fg, orbHover.hovered && root.sel ? 0.22 : 0.12)
            scale: orbTap.pressed && root.sel ? 0.95 : 1
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Behavior on border.color { ColorAnimation { duration: 130 } }

            Rectangle {
                anchors.centerIn: parent
                width: 72; height: 72; radius: 36
                color: "transparent"
                border.width: 2
                border.color: root.sel ? Qt.alpha(root.sel.danger ? root.theme.warn : root.theme.accent, 0.9)
                            : root.mode === "idle" && root.idleCur.key !== "off"
                              ? Qt.alpha(root.theme.accent, 0.6)
                            : Qt.alpha(root.theme.fg, 0.35)
                Behavior on border.color { ColorAnimation { duration: 220 } }
            }
            Text {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: 1
                text: root.sel ? root.sel.glyph
                    : root.mode === "idle" ? root.idleCur.glyph : "\u{f0425}"
                color: root.sel && root.sel.danger ? root.theme.warn : root.theme.fg
                font.family: root.theme.fontMono
                font.pixelSize: 26
                Behavior on color { ColorAnimation { duration: 200 } }
            }
            HoverHandler { id: orbHover; cursorShape: root.sel ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { id: orbTap; onTapped: root.act() }
        }

        Text {
            anchors.horizontalCenter: orb.horizontalCenter
            anchors.top: orb.bottom
            anchors.topMargin: 8
            horizontalAlignment: Text.AlignHCenter
            text: root.sel ? "Click to " + root.sel.name.toLowerCase()
                : root.mode === "idle" ? "After an hour"
                : "Up " + root.uptime
            color: root.sel && root.sel.danger ? root.theme.warn : Qt.alpha(root.theme.muted, 0.8)
            font.family: root.theme.fontSans
            font.pixelSize: IslandState.ts(10)
        }

        Repeater {
            model: root.nodes

            Rectangle {
                id: chip
                required property var modelData

                readonly property real ang: modelData.ang * Math.PI / 180
                readonly property real f: field.ringFrac(modelData.ring)
                readonly property bool isSel: root.selected === modelData.key
                readonly property bool danger: modelData.danger === true

                x: field.cx + Math.cos(ang) * field.rx * f - width / 2
                y: field.cy + Math.sin(ang) * field.ry * f - height / 2

                width: chipRow.implicitWidth + 22
                height: 30
                radius: 10
                color: modelData.on ? Qt.alpha(root.theme.accent, 0.18)
                     : isSel && danger ? Qt.alpha(root.theme.warn, 0.14)
                     : Qt.alpha(root.theme.fg, chipHover.hovered || isSel ? 0.12 : 0.06)
                border.width: 1
                border.color: isSel ? Qt.alpha(danger ? root.theme.warn : root.theme.accent, 0.8)
                            : Qt.alpha(modelData.on ? root.theme.accent : root.theme.fg,
                                       modelData.on ? 0.4 : 0.1)
                Behavior on color { ColorAnimation { duration: 130 } }
                Behavior on border.color { ColorAnimation { duration: 130 } }

                opacity: 0
                scale: 0.8
                Component.onCompleted: { opacity = 1; scale = 1; }
                Behavior on opacity { NumberAnimation { duration: 260 } }
                Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }

                Row {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: chip.modelData.glyph
                        color: chip.modelData.on ? root.theme.accent
                             : chip.danger ? root.theme.warn : Qt.alpha(root.theme.fg, 0.7)
                        font.family: root.theme.fontMono
                        font.pixelSize: 13
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: chip.modelData.name
                        color: root.theme.fg
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(11)
                        font.weight: Font.DemiBold
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: text !== ""
                        text: chip.modelData.sub
                        color: Qt.alpha(root.theme.muted, 0.9)
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(9)
                    }
                }

                HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.pick(chip.modelData) }
            }
        }
    }

    // ── bottom bar: action chip, mode switch, power profile ───────
    Item {
        id: bar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        anchors.bottomMargin: 8
        height: 40

        Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            visible: root.sel !== null
            readonly property bool danger: root.sel !== null && root.sel.danger === true
            width: actLbl.implicitWidth + 28
            height: 34
            radius: 10
            color: danger ? Qt.alpha(root.theme.warn, actHover.hovered ? 0.3 : 0.18)
                          : Qt.alpha(root.theme.accent, actHover.hovered ? 0.32 : 0.2)
            Behavior on color { ColorAnimation { duration: 130 } }
            Text {
                id: actLbl
                anchors.centerIn: parent
                text: root.sel ? root.sel.name.toUpperCase() : ""
                color: parent.danger ? root.theme.warn : root.theme.fg
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(10)
                font.weight: Font.Bold
                font.letterSpacing: 0.6
            }
            HoverHandler { id: actHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.act() }
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            visible: root.mode === "idle"
            width: seg.x - 12
            text: "Audio or an idle inhibitor postpones it"
            wrapMode: Text.WordWrap
            color: Qt.alpha(root.theme.muted, 0.6)
            font.family: root.theme.fontSans
            font.pixelSize: IslandState.ts(9)
        }

        Rectangle {
            id: seg
            anchors.centerIn: parent
            width: 230; height: 34; radius: 10
            color: Qt.alpha(root.theme.fg, 0.06)

            Rectangle {
                x: root.mode === "session" ? 2 : seg.width / 2
                y: 2
                width: seg.width / 2 - 2
                height: seg.height - 4
                radius: 8
                color: root.theme.fg
                Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            }

            Repeater {
                model: [
                    { id: "session", glyph: "\u{f0425}", label: "Session" },
                    { id: "idle",    glyph: "\u{f04b2}", label: "Idle" }
                ]
                Item {
                    id: segItem
                    required property var modelData
                    required property int index
                    x: index * seg.width / 2
                    width: seg.width / 2
                    height: seg.height
                    readonly property bool cur: root.mode === modelData.id
                    Row {
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: segItem.modelData.glyph
                            color: segItem.cur ? root.theme.base : Qt.alpha(root.theme.fg, 0.7)
                            font.family: root.theme.fontMono
                            font.pixelSize: 12
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: segItem.modelData.label
                            color: segItem.cur ? root.theme.base : Qt.alpha(root.theme.fg, 0.7)
                            font.family: root.theme.fontSans
                            font.pixelSize: IslandState.ts(11)
                            font.weight: Font.DemiBold
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.setMode(segItem.modelData.id) }
                }
            }
        }

        // Power profile: saver → balanced → performance. Lit off balanced.
        Rectangle {
            id: profBtn
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 36; height: 36; radius: 18
            color: root.profileOn ? Qt.alpha(root.theme.accent, profHover.hovered ? 0.32 : 0.2)
                                  : Qt.alpha(root.theme.fg, profHover.hovered ? 0.14 : 0.07)
            Behavior on color { ColorAnimation { duration: 160 } }
            Text {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: 1
                text: PowerProfiles.profile === PowerProfile.PowerSaver ? "\u{f06b1}" : "\u{f0241}"
                color: root.profileOn ? root.theme.accent : Qt.alpha(root.theme.fg, 0.6)
                font.family: root.theme.fontMono
                font.pixelSize: 15
            }
            HoverHandler { id: profHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.cycleProfile() }
        }
        Text {
            anchors.right: profBtn.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            visible: profHover.hovered
            text: root.profileName
            color: Qt.alpha(root.theme.muted, 0.9)
            font.family: root.theme.fontSans
            font.pixelSize: IslandState.ts(10)
        }
    }
}
