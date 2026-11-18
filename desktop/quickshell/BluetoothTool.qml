import QtQuick
import Quickshell.Bluetooth
import Quickshell.Networking

// The wireless panel — a drill-in from the hub's Bluetooth tile. A radar
// rather than a list: the radio sits in the middle as an orb, and what it can
// reach floats around it, nearer the centre the closer it is (connected,
// then paired, then merely seen; for Wi-Fi, by signal). Clicking the orb
// scans, clicking a device selects it and the action chip bottom-left acts on
// it, the switch along the bottom flips between Wi-Fi and Bluetooth, and the
// round button bottom-right powers the radio.
//
// Without a Wi-Fi adapter the first tab becomes "Network" and lists the
// wired profiles NetworkManager knows, so it is never a dead tab.
Item {
    id: root

    property var theme

    // Fill the sheet instead of asking for more: the radar lays itself out
    // to whatever the card gives it.
    readonly property real preferredHeight: 0

    // ── what the two radios offer ─────────────────────────────────
    property string mode: "bt"   // "bt" | "net"
    property string selected: ""
    property string psk: ""
    property string failMsg: ""
    // Only a scan this panel started is ours to stop: another client may be
    // discovering too, and BlueZ would end its scan along with ours.
    property bool ownScan: false

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool btOn: root.adapter !== null && root.adapter.enabled
    readonly property bool btScanning: root.adapter !== null && root.adapter.discovering

    readonly property var netDevices: Networking.devices ? Networking.devices.values : []
    readonly property var wifiDev: {
        for (let i = 0; i < root.netDevices.length; i++)
            if (root.netDevices[i].type === DeviceType.Wifi) return root.netDevices[i];
        return null;
    }
    readonly property var wiredDev: {
        for (let i = 0; i < root.netDevices.length; i++)
            if (root.netDevices[i].type === DeviceType.Wired) return root.netDevices[i];
        return null;
    }
    readonly property bool hasWifi: root.wifiDev !== null
    readonly property bool wifiOn: root.hasWifi && Networking.wifiEnabled
    readonly property bool netScanning: root.hasWifi && root.wifiDev.scannerEnabled

    readonly property bool radioOn: root.mode === "bt" ? root.btOn
                                  : (root.hasWifi ? root.wifiOn : root.wiredDev !== null)
    readonly property bool scanning: root.mode === "bt" ? root.btScanning : root.netScanning

    function btGlyph(d) {
        const i = (d.icon || "").toLowerCase();
        if (i.indexOf("headset") >= 0 || i.indexOf("headphone") >= 0 || i.indexOf("audio") >= 0)
            return "\u{f02cb}";
        if (i.indexOf("gaming") >= 0 || i.indexOf("joystick") >= 0) return "\u{f0eb5}";
        if (i.indexOf("phone") >= 0) return "\u{f011c}";
        if (i.indexOf("mouse") >= 0) return "\u{f037d}";
        if (i.indexOf("keyboard") >= 0) return "\u{f030c}";
        if (i.indexOf("computer") >= 0) return "\u{f0379}";
        return "\u{f00af}";
    }
    function wifiGlyph(s) {
        return s >= 0.75 ? "\u{f0928}" : s >= 0.5 ? "\u{f0925}"
             : s >= 0.25 ? "\u{f0922}" : "\u{f091f}";
    }

    // One flat list of nodes for the radar, whichever radio is showing. Each
    // carries a ring (0 nearest) and a key that survives model churn, so
    // selection and placement stay put while the scan reorders things.
    readonly property var nodes: {
        const out = [];
        if (root.mode === "bt") {
            if (!root.btOn) return out;
            const ds = Bluetooth.devices ? Bluetooth.devices.values : [];
            for (let i = 0; i < ds.length; i++) {
                const d = ds[i];
                // `name` is the BlueZ alias — the name the user gave it, which is
                // what tells two identical controllers apart.
                const name = d.name || d.deviceName || "";
                const paired = d.paired || d.bonded || d.connected;
                // Trusted but unpaired is still the user's own device — a
                // DualSense whose key a Windows boot replaced, say.
                const known = paired || d.trusted;
                // Unnamed beacons are noise; strangers only show while scanning.
                if (!known && (!root.btScanning || name === "" || name.replace(/[-:]/g, "").toUpperCase()
                               === (d.address || "").replace(/:/g, ""))) continue;
                out.push({ key: "bt:" + d.address, obj: d, name: name || d.address,
                           glyph: root.btGlyph(d), look: IslandState.btLook(d),
                           ring: d.connected ? 0 : known ? 1 : 2,
                           on: d.connected, busy: d.pairing || d.state === BluetoothDeviceState.Connecting,
                           sub: d.batteryAvailable ? Math.round(d.battery * 100) + "%" : "",
                           known: known, paired: paired });
            }
        } else {
            const dev = root.hasWifi ? (root.wifiOn ? root.wifiDev : null) : root.wiredDev;
            if (!dev) return out;
            const ns = dev.networks ? dev.networks.values : [];
            for (let i = 0; i < ns.length; i++) {
                const n = ns[i];
                if (!n.name) continue;
                const wifi = root.hasWifi;
                const s = wifi ? n.signalStrength : 1;
                out.push({ key: "net:" + n.name, obj: n, name: n.name,
                           glyph: wifi ? root.wifiGlyph(s) : "\u{f0200}",
                           ring: n.connected ? 0 : (wifi ? (s >= 0.55 ? 1 : 2) : 1),
                           on: n.connected, busy: n.stateChanging,
                           sub: wifi && n.security !== WifiSecurityType.Open ? "\u{f033e}" : "",
                           known: n.known, secure: wifi && n.security !== WifiSecurityType.Open,
                           strength: s });
            }
        }
        out.sort((a, b) => a.ring - b.ring || (b.strength || 0) - (a.strength || 0)
                           || a.name.localeCompare(b.name));
        return out.slice(0, 10);
    }
    readonly property var sel: {
        for (let i = 0; i < root.nodes.length; i++)
            if (root.nodes[i].key === root.selected) return root.nodes[i];
        return null;
    }
    // A password is asked for only where NetworkManager has none stored.
    readonly property bool needsPsk: root.sel !== null && root.mode === "net"
                                     && root.sel.secure === true && !root.sel.known && !root.sel.on

    function setMode(m) {
        if (root.mode === m) return;
        root.stopScan();
        root.mode = m;
        root.selected = "";
        root.psk = "";
        root.failMsg = "";
    }
    function toggleScan() {
        if (!root.radioOn) return;
        if (root.scanning) { root.stopScan(); return; }
        root.ownScan = true;
        if (root.mode === "bt") root.adapter.discovering = true;
        else if (root.hasWifi) root.wifiDev.scannerEnabled = true;
    }
    function stopScan() {
        if (!root.ownScan) return;
        root.ownScan = false;
        if (root.adapter && root.adapter.discovering) root.adapter.discovering = false;
        if (root.wifiDev && root.wifiDev.scannerEnabled) root.wifiDev.scannerEnabled = false;
    }
    function togglePower() {
        if (root.mode === "bt") { if (root.adapter) root.adapter.enabled = !root.adapter.enabled; }
        else if (root.hasWifi) Networking.wifiEnabled = !Networking.wifiEnabled;
        root.selected = "";
    }
    function act() {
        const n = root.sel;
        if (!n) return;
        root.failMsg = "";
        if (n.on) { n.obj.disconnect(); return; }
        if (root.mode === "bt") {
            if (n.paired) n.obj.connect();
            else { n.obj.trusted = true; n.obj.pair(); }
        } else if (root.needsPsk) {
            if (root.psk === "") { pskInput.forceActiveFocus(); return; }
            n.obj.connectWithPsk(root.psk);
            root.psk = "";
        } else n.obj.connect();
    }
    function forget() {
        if (root.sel && root.sel.known && !root.sel.on) root.sel.obj.forget();
        root.selected = "";
    }

    Connections {
        target: root.sel ? root.sel.obj : null
        ignoreUnknownSignals: true
        function onConnectionFailed(reason) { root.failMsg = "Couldn't connect"; }
    }

    Component.onCompleted: {
        if (IslandState.wirelessTab !== "") {
            root.mode = IslandState.wirelessTab;
            IslandState.wirelessTab = "";
        }
    }
    Component.onDestruction: root.stopScan()

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
        // The rings are ellipses: the sheet is wider than tall, and circles
        // would leave the corners empty while chips piled up top and bottom.
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

        // Scan pulses: rings leaving the orb, staggered, only while scanning.
        Repeater {
            model: 2
            Rectangle {
                id: pulse
                required property int index
                property real t: 0
                x: field.cx - width / 2
                y: field.cy - height / 2
                width: 92 + (field.rx * 2 - 92) * t
                height: 92 + (field.ry * 2 - 92) * t
                radius: height / 2
                color: "transparent"
                border.width: 1.5
                border.color: Qt.alpha(root.theme.accent, 0.5 * (1 - t))
                visible: root.scanning
                SequentialAnimation on t {
                    running: root.scanning
                    loops: Animation.Infinite
                    PauseAnimation { duration: pulse.index * 1100 }
                    NumberAnimation { from: 0; to: 1; duration: 2200; easing.type: Easing.OutCubic }
                }
            }
        }

        // The orb: the radio itself. Click to scan.
        Rectangle {
            id: orb
            width: 92; height: 92; radius: 46
            x: field.cx - 46; y: field.cy - 46
            color: Qt.darker(root.theme.base, 1.5)
            border.width: 1
            border.color: Qt.alpha(root.theme.fg, orbHover.hovered ? 0.22 : 0.12)
            scale: orbTap.pressed ? 0.95 : 1
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Behavior on border.color { ColorAnimation { duration: 130 } }

            Rectangle {
                anchors.centerIn: parent
                width: 72; height: 72; radius: 36
                color: "transparent"
                border.width: 2
                border.color: root.radioOn ? Qt.alpha(root.scanning ? root.theme.accent : root.theme.fg,
                                                      root.scanning ? 0.9 : 0.35)
                                           : Qt.alpha(root.theme.muted, 0.2)
                Behavior on border.color { ColorAnimation { duration: 220 } }
            }
            Text {
                anchors.centerIn: parent
                text: root.mode === "bt" ? (root.btOn ? "\u{f00af}" : "\u{f00b2}")
                    : root.hasWifi ? (root.wifiOn ? "\u{f05a9}" : "\u{f05aa}") : "\u{f0200}"
                color: root.radioOn ? root.theme.fg : Qt.alpha(root.theme.muted, 0.6)
                font.family: root.theme.fontMono
                font.pixelSize: 26
            }
            HoverHandler { id: orbHover; cursorShape: root.radioOn ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { id: orbTap; onTapped: root.toggleScan() }
        }

        Text {
            anchors.horizontalCenter: orb.horizontalCenter
            anchors.top: orb.bottom
            anchors.topMargin: 8
            text: !root.radioOn ? (root.mode === "bt" ? "Bluetooth is off"
                                   : root.hasWifi ? "Wi-Fi is off" : "No network device")
                : root.scanning ? "Scanning\u{2026}"
                : root.nodes.length === 0 ? "Click to scan" : ""
            color: Qt.alpha(root.theme.muted, 0.8)
            font.family: root.theme.fontSans
            font.pixelSize: IslandState.ts(10)
        }

        // The nodes. Angles are spread evenly per ring and staggered between
        // rings, so neighbours never sit on the same ray.
        Repeater {
            model: root.nodes

            Rectangle {
                id: chip
                required property var modelData
                required property int index

                readonly property var sameRing: root.nodes.filter(n => n.ring === modelData.ring)
                readonly property int slot: sameRing.findIndex(n => n.key === modelData.key)
                readonly property real ang: -Math.PI / 2 + (modelData.ring * 0.62)
                    + slot * 2 * Math.PI / Math.max(1, sameRing.length)
                readonly property real f: field.ringFrac(modelData.ring)
                readonly property bool isSel: root.selected === modelData.key

                x: field.cx + Math.cos(ang) * field.rx * f - width / 2
                y: field.cy + Math.sin(ang) * field.ry * f - height / 2
                Behavior on x { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
                Behavior on y { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }

                width: chipRow.implicitWidth + 22
                height: 30
                radius: 10
                color: modelData.on ? Qt.alpha(root.theme.accent, 0.18)
                     : Qt.alpha(root.theme.fg, chipHover.hovered || isSel ? 0.12 : 0.06)
                border.width: 1
                border.color: isSel ? Qt.alpha(root.theme.accent, 0.8)
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
                    // The shell's device icon where it has one (a pad in its
                    // own colour), the radar's glyph otherwise.
                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        readonly property var look: chip.modelData.look || { kind: "", tint: "" }
                        readonly property color tone: chip.modelData.on ? root.theme.accent : Qt.alpha(root.theme.fg, 0.7)
                        width: look.kind !== "" ? 15 : chipGlyph.implicitWidth
                        height: 15
                        Text {
                            id: chipGlyph
                            anchors.centerIn: parent
                            visible: parent.look.kind === ""
                            text: chip.modelData.glyph
                            color: parent.tone
                            font.family: root.theme.fontMono
                            font.pixelSize: 13
                        }
                        DeviceGlyph {
                            anchors.centerIn: parent
                            visible: parent.look.kind !== ""
                            kind: parent.look.kind || "gamepad"
                            color: parent.look.tint !== "" ? parent.look.tint : parent.tone
                            fontFamily: root.theme.fontMono
                            size: 15
                        }
                        // Blinks while pairing or connecting; the blink lives
                        // on its own property so it rests at full opacity.
                        property real blink: 1
                        opacity: chip.modelData.busy ? blink : 1
                        SequentialAnimation on blink {
                            running: chip.modelData.busy
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.3; duration: 500 }
                            NumberAnimation { to: 1; duration: 500 }
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, 112)
                        elide: Text.ElideRight
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
                TapHandler {
                    onTapped: {
                        root.failMsg = "";
                        root.psk = "";
                        root.selected = chip.isSel ? "" : chip.modelData.key;
                    }
                }
            }
        }
    }

    // ── bottom bar: action chip, radio switch, power ──────────────
    Item {
        id: bar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        // The power button is round and sits in the sheet's rounded corner:
        // at 6 px it touched the curve, closer on the right than below. Ten
        // px on the sides and eight below (plus the 2 px the 36 px button
        // leaves in this 40 px bar) give it the same inset both ways.
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        anchors.bottomMargin: 8
        height: 40

        // The action chip acts on the selection. Bottom-left, as in the
        // reference, so it never covers a node.
        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            visible: root.sel !== null || root.failMsg !== ""
            opacity: visible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 160 } }

            Rectangle {
                visible: root.needsPsk
                width: 120; height: 34; radius: 10
                color: Qt.alpha(root.theme.fg, 0.06)
                border.width: 1
                border.color: Qt.alpha(pskInput.activeFocus ? root.theme.accent : root.theme.fg,
                                       pskInput.activeFocus ? 0.7 : 0.12)
                TextInput {
                    id: pskInput
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password
                    clip: true
                    text: root.psk
                    onTextEdited: root.psk = text
                    onAccepted: root.act()
                    color: root.theme.fg
                    font.family: root.theme.fontMono
                    font.pixelSize: 11
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: parent.text === ""
                        text: "Password"
                        color: Qt.alpha(root.theme.muted, 0.6)
                        font: parent.font
                    }
                }
            }

            Repeater {
                model: root.sel === null ? []
                     : [{ id: "act", label: root.sel.on ? "DISCONNECT"
                                         : root.sel.busy ? "WORKING\u{2026}"
                                         : (root.mode === "bt" && !root.sel.paired) ? "PAIR" : "CONNECT" }]
                       .concat(root.sel.known && !root.sel.on && !(root.mode === "net" && !root.hasWifi)
                               ? [{ id: "forget", label: "FORGET" }] : [])

                Rectangle {
                    required property var modelData
                    width: lbl.implicitWidth + 28
                    height: 34
                    radius: 10
                    color: modelData.id === "forget"
                           ? Qt.alpha(root.theme.error, actHover.hovered ? 0.24 : 0.12)
                           : Qt.alpha(root.theme.accent, actHover.hovered ? 0.32 : 0.2)
                    Behavior on color { ColorAnimation { duration: 130 } }
                    Text {
                        id: lbl
                        anchors.centerIn: parent
                        text: parent.modelData.label
                        color: parent.modelData.id === "forget" ? root.theme.error : root.theme.fg
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(10)
                        font.weight: Font.Bold
                        font.letterSpacing: 0.6
                    }
                    HoverHandler { id: actHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: parent.modelData.id === "forget" ? root.forget() : root.act()
                    }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.failMsg !== ""
                text: root.failMsg
                color: root.theme.error
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(10)
            }
        }

        // The radio switch: a segmented pill with a sliding highlight.
        Rectangle {
            id: seg
            anchors.centerIn: parent
            width: 230; height: 34; radius: 10
            color: Qt.alpha(root.theme.fg, 0.06)

            Rectangle {
                x: root.mode === "net" ? 2 : seg.width / 2
                y: 2
                width: seg.width / 2 - 2
                height: seg.height - 4
                radius: 8
                color: root.theme.fg
                Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            }

            Repeater {
                model: [
                    { id: "net", glyph: root.hasWifi ? "\u{f05a9}" : "\u{f0200}",
                      label: root.hasWifi ? "Wi-Fi" : "Network" },
                    { id: "bt", glyph: "\u{f00af}", label: "Bluetooth" }
                ]
                Item {
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
                            text: parent.parent.modelData.glyph
                            color: parent.parent.cur ? root.theme.base : Qt.alpha(root.theme.fg, 0.7)
                            font.family: root.theme.fontMono
                            font.pixelSize: 12
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: parent.parent.modelData.label
                            color: parent.parent.cur ? root.theme.base : Qt.alpha(root.theme.fg, 0.7)
                            font.family: root.theme.fontSans
                            font.pixelSize: IslandState.ts(11)
                            font.weight: Font.DemiBold
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.setMode(parent.modelData.id) }
                }
            }
        }

        // Radio power. Absent for a wired-only Network tab: there is no
        // radio to switch, and unplugging the machine is not a toggle.
        Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.mode === "bt" || root.hasWifi
            width: 36; height: 36; radius: 18
            color: root.radioOn ? Qt.alpha(root.theme.accent, pwrHover.hovered ? 0.32 : 0.2)
                                : Qt.alpha(root.theme.fg, pwrHover.hovered ? 0.14 : 0.07)
            Behavior on color { ColorAnimation { duration: 160 } }
            Text {
                anchors.centerIn: parent
                // The glyph's ink sits 1 px left of its advance box.
                anchors.horizontalCenterOffset: 1
                text: "\u{f0425}"
                color: root.radioOn ? root.theme.accent : Qt.alpha(root.theme.fg, 0.6)
                font.family: root.theme.fontMono
                font.pixelSize: 15
            }
            HoverHandler { id: pwrHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.togglePower() }
        }
    }
}
