import QtQuick
import Quickshell
import Quickshell.Io

// The Oukitel power station: IslandState.station is the `oukitel` daemon's
// reading, and commands go through its CLI. The daemon owns the LAN session,
// so closing the card costs the station nothing. The same panel heads
// Settings → Power station.
Item {
    id: root

    property var theme

    readonly property real preferredHeight: Math.max(260, body.implicitHeight + 36)
    readonly property bool showing: IslandState.tool === "station"

    readonly property var st: IslandState.station
    property var pending: ({})
    property int limitDraft: -1

    Process {
        id: ctl
        property var queue: []
        stderr: StdioCollector {
            onStreamFinished: if (this.text.trim() !== "") root.lastError = this.text.trim()
        }
        onExited: if (queue.length > 0) { command = queue.shift(); running = true; }
    }
    property string lastError: ""
    function run(args) {
        root.lastError = "";
        const cmd = ["@HOME@/.local/bin/oukitel"].concat(args);
        if (ctl.running) ctl.queue.push(cmd);
        else { ctl.command = cmd; ctl.running = true; }
    }
    function setSwitch(name, on) {
        const p = Object.assign({}, root.pending);
        p[name] = { v: on, until: Date.now() + 6000 };
        root.pending = p;
        root.run(name === "ac" && !on ? ["ac", "off", "--yes"] : [name, on ? "on" : "off"]);
    }
    // The PC itself runs off the AC outlets, so switching them off goes
    // through a confirmation drawn over the panel. Not a popup window: a
    // second focus grab would close the island card under it.
    property bool confirmAcOff: false
    function flip(name) {
        const on = root.sw(name);
        if (name === "ac" && on) {
            root.confirmAcOff = true;
            return;
        }
        root.setSwitch(name, !on);
    }
    function sw(name) {
        const p = root.pending[name];
        if (p && Date.now() < p.until) return p.v;
        return root.st[name] === true;
    }
    Timer {
        id: limitSend
        interval: 600
        onTriggered: { root.run(["limit", String(root.limitDraft)]); limitExpire.restart(); }
    }
    Timer {
        id: limitExpire
        interval: 8000
        onTriggered: root.limitDraft = -1
    }

    readonly property bool online: IslandState.stationOnline
    readonly property real battery: IslandState.stationOnline ? IslandState.stationPct : -1
    readonly property real inW: IslandState.stationIn
    readonly property real outW: IslandState.stationOut
    // A 100 % limit means no limitation at all: the daemon keeps the charger
    // at full power and the slider stands down.
    readonly property bool fullCharge: root.limitOn && root.target >= 100
    readonly property int chargeLimit: root.fullCharge ? 100 : root.limitDraft >= 0 ? root.limitDraft
        : root.st.power_cap !== undefined ? root.st.power_cap
        : (root.st.charge_limit !== undefined ? root.st.charge_limit : 100)
    // The charge limit is the daemon's: it holds the power cap at the
    // station's floor (~90 W) once the battery reaches the target. These
    // mirror a click until the daemon's next reading confirms it.
    property var targetDraft: null
    Timer { id: targetExpire; interval: 6000; onTriggered: root.targetDraft = null }
    readonly property bool limitOn: root.targetDraft !== null ? root.targetDraft.on : root.st.limit_enabled === true
    readonly property int target: root.targetDraft !== null ? root.targetDraft.t : (root.st.charge_target || 80)
    function setTarget(on, t) {
        root.targetDraft = { on: on, t: t };
        targetExpire.restart();
        root.run(["target", on ? String(t) : "off"]);
    }
    readonly property string statusLine: IslandState.stationKnown ? IslandState.stationStatus
        : "No station configured · run oukitel login"
    function pctColor(p) {
        return IslandState.batteryColor(p < 0 ? -1 : p / 100, false, root.theme);
    }

    Column {
        id: body
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 18
        spacing: 10

        Rectangle {
            width: parent.width
            height: 92
            radius: 14
            color: Qt.alpha(root.theme.fg, 0.05)

            Item {
                id: ringBox
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 70; height: 70
                RingProgress {
                    anchors.fill: parent
                    progress: Math.max(0, root.battery) / 100
                    ring: root.pctColor(root.battery)
                    track: root.theme.fg
                    thickness: 6
                }
                Text {
                    anchors.centerIn: parent
                    text: root.battery >= 0 ? Math.round(root.battery) + "%" : "—"
                    color: root.theme.fg
                    font.family: root.theme.fontMono
                    font.pixelSize: 15
                    font.weight: Font.Bold
                }
            }
            Column {
                anchors.left: ringBox.right
                anchors.leftMargin: 14
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                Text {
                    text: root.st.name || "Power station"
                    color: root.theme.fg
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(13)
                    font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.statusLine
                    color: root.online ? Qt.alpha(root.theme.on_surface_variant, 0.85) : root.theme.warn
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(10)
                }
                Text {
                    visible: root.lastError !== ""
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.lastError
                    color: root.theme.warn
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(9)
                }
            }
        }

        Row {
            id: stats
            width: parent.width
            spacing: 8
            readonly property real cellW: (width - spacing * 2) / 3

            Repeater {
                model: [
                    { glyph: "\u{f192d}", label: "Input", value: Math.round(root.inW) + " W",
                      sub: "AC " + Math.round(root.st.ac_in_w || 0) + " · DC " + Math.round(root.st.dc_in_w || 0) },
                    { glyph: "\u{f192c}", label: "Output", value: Math.round(root.outW) + " W",
                      sub: IslandState.stationRuntime ? (IslandState.stationOnBattery ? "" : "backup ") + IslandState.stationRuntime : "" },
                    { glyph: "\u{f06a5}", label: "AC out",
                      value: Math.round(((root.st.raw || {})["6"] || {})["2"] || 0) + " W",
                      sub: root.sw("ac") ? "outlets on" : "outlets off" }
                ]
                Rectangle {
                    required property var modelData
                    width: stats.cellW
                    height: 62
                    radius: 12
                    color: Qt.alpha(root.theme.fg, 0.05)
                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: modelData.glyph + "  " + modelData.label
                            color: Qt.alpha(root.theme.on_surface_variant, 0.8)
                            font.family: root.theme.fontSans
                            font.pixelSize: IslandState.ts(9)
                        }
                        Text {
                            text: modelData.value
                            color: root.theme.fg
                            font.family: root.theme.fontMono
                            font.pixelSize: 15
                            font.weight: Font.Bold
                        }
                        Text {
                            visible: modelData.sub !== ""
                            text: modelData.sub
                            color: Qt.alpha(root.theme.on_surface_variant, 0.6)
                            font.family: root.theme.fontSans
                            font.pixelSize: IslandState.ts(8)
                        }
                    }
                }
            }
        }

        Repeater {
            model: [
                { id: "ac",  glyph: "\u{f06a5}", name: "AC outlets" },
                { id: "dc",  glyph: "\u{f010b}", name: "DC / car port" },
                { id: "usb", glyph: "\u{f11f0}", name: "USB" }
            ]
            Rectangle {
                required property var modelData
                width: body.width
                height: 44
                radius: 12
                color: Qt.alpha(root.theme.fg, 0.05)
                opacity: root.online ? 1 : 0.5
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.glyph + "   " + modelData.name
                    color: root.theme.fg
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(12)
                    font.weight: Font.DemiBold
                }
                ToggleSwitch {
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    theme: root.theme
                    checked: root.sw(modelData.id)
                    onToggled: if (root.online) root.flip(modelData.id)
                }
            }
        }

        Rectangle {
            width: parent.width
            height: limitCol.implicitHeight + 20
            radius: 12
            color: Qt.alpha(root.theme.fg, 0.05)
            opacity: root.online ? 1 : 0.5
            Column {
                id: limitCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 10
                spacing: 8
                Item {
                    width: parent.width
                    height: 26
                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: 2
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Text {
                            text: "\u{f0084}   Charge limit"
                            color: root.theme.fg
                            font.family: root.theme.fontSans
                            font.pixelSize: IslandState.ts(12)
                            font.weight: Font.DemiBold
                        }
                        Text {
                            text: !root.limitOn ? "Charges to 100%"
                                : root.fullCharge ? "Charges to 100% · charger at full power"
                                : root.st.holding ? "Holding at " + root.target + "% · trickles ~90 W"
                                : "Stops charging at " + root.target + "%"
                            color: Qt.alpha(root.theme.on_surface_variant, 0.75)
                            font.family: root.theme.fontSans
                            font.pixelSize: IslandState.ts(9)
                        }
                    }
                    ToggleSwitch {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        theme: root.theme
                        checked: root.limitOn
                        onToggled: if (root.online) root.setTarget(!root.limitOn, root.target)
                    }
                }
                Row {
                    id: chips
                    width: parent.width
                    spacing: 6
                    readonly property real chipW: (width - spacing * 4) / 5
                    Repeater {
                        model: [20, 40, 60, 80, 100]
                        Rectangle {
                            required property int modelData
                            readonly property bool picked: root.limitOn && root.target === modelData
                            width: chips.chipW
                            height: 30
                            radius: 9
                            color: picked ? root.theme.primary : Qt.alpha(root.theme.fg, chipHov.hovered ? 0.12 : 0.07)
                            Behavior on color { ColorAnimation { duration: 140 } }
                            Text {
                                anchors.centerIn: parent
                                text: parent.modelData + "%"
                                color: parent.picked ? root.theme.on_primary : root.theme.fg
                                font.family: root.theme.fontMono
                                font.pixelSize: 12
                                font.weight: Font.Bold
                            }
                            HoverHandler { id: chipHov; cursorShape: Qt.PointingHandCursor }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: if (root.online) root.setTarget(true, parent.modelData)
                            }
                        }
                    }
                }
            }
        }

        ControlSlider {
            width: parent.width
            height: 58
            theme: root.theme
            opacity: root.online && !root.fullCharge ? 1 : 0.5
            enabled: !root.fullCharge
            label: "AC charge power"
            glyph: "\u{f0084}"
            valueText: root.fullCharge ? "100% · limit at 100%" : root.chargeLimit + "%"
            value: (root.chargeLimit - 3) / 97
            onMoved: (v) => {
                if (!root.online || root.fullCharge) return;
                root.limitDraft = Math.round(3 + v * 97);
                limitSend.restart();
            }
        }
    }

    // ── AC off confirmation ───────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        z: 50
        visible: opacity > 0
        opacity: root.confirmAcOff ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
        color: Qt.alpha(root.theme.surface, 0.72)
        // swallow clicks so nothing under the scrim reacts; outside the box cancels
        MouseArea { anchors.fill: parent; onClicked: root.confirmAcOff = false }
        Keys.onEscapePressed: root.confirmAcOff = false

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 48, 360)
            height: dlgCol.implicitHeight + 36
            radius: 16
            color: root.theme.surface_container_high
            border.width: 1
            border.color: Qt.alpha(root.theme.warn, 0.45)
            scale: root.confirmAcOff ? 1 : 0.96
            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            MouseArea { anchors.fill: parent }

            Column {
                id: dlgCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 18
                spacing: 8
                Text {
                    text: "\u{f0026}   Turn off AC outlets?"
                    color: root.theme.warn
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(13)
                    font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Everything on the station's AC outlets loses power at once, this PC included ("
                          + Math.round(((root.st.raw || {})["6"] || {})["2"] || 0) + " W drawn now). Unsaved work will be lost."
                    color: Qt.alpha(root.theme.on_surface_variant, 0.9)
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(10)
                }
                Item { width: 1; height: 4 }
                Row {
                    anchors.right: parent.right
                    spacing: 8
                    Repeater {
                        model: [
                            { label: "Cancel", danger: false },
                            { label: "Turn off", danger: true }
                        ]
                        Rectangle {
                            required property var modelData
                            width: btnText.implicitWidth + 28
                            height: 32
                            radius: 10
                            color: modelData.danger
                                ? (btnHov.hovered ? Qt.lighter(root.theme.error_container, 1.2) : root.theme.error_container)
                                : Qt.alpha(root.theme.fg, btnHov.hovered ? 0.14 : 0.08)
                            Text {
                                id: btnText
                                anchors.centerIn: parent
                                text: parent.modelData.label
                                color: parent.modelData.danger ? root.theme.on_error_container : root.theme.fg
                                font.family: root.theme.fontSans
                                font.pixelSize: IslandState.ts(11)
                                font.weight: Font.DemiBold
                            }
                            HoverHandler { id: btnHov; cursorShape: Qt.PointingHandCursor }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root.confirmAcOff = false;
                                    if (parent.modelData.danger) root.setSwitch("ac", false);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    onShowingChanged: if (!root.showing) root.confirmAcOff = false

    Connections {
        target: root
        function onStChanged() {
            if (root.limitDraft >= 0 && !limitSend.running && root.st.charge_limit === root.limitDraft)
                root.limitDraft = -1;
        }
    }
}
