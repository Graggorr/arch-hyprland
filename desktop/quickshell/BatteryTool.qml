import QtQuick
import Quickshell.Io
import Quickshell.Services.UPower

// Every battery this machine can see: the system one where it exists, then
// the peripherals — mouse, controller, phone, AirPods. The list comes from
// devicebat.sh's json mode, the same script whose one-line summary sits on
// the bar, so the two can never disagree about a reading.
Item {
    id: root

    property var theme

    readonly property real preferredHeight: Math.max(200, list.implicitHeight + 36)

    property var devices: IslandState.cacheGet("battery.devices", [])
    readonly property bool showing: IslandState.tool === "battery"

    function reload() { batProc.running = true; }

    Process {
        id: batProc
        command: ["bash", "@HOME@/.config/quickshell/scripts/devicebat.sh", "json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(this.text.trim());
                    root.devices = j.devices || [];
                    IslandState.cacheSet("battery.devices", root.devices);
                } catch (e) { /* keep the last good reading */ }
            }
        }
    }

    // Refresh while the tool is actually on screen; nothing runs while the
    // card is closed. The card's reload hook covers the moment it opens.
    Timer {
        interval: 30000
        running: root.showing
        repeat: true
        onTriggered: batProc.running = true
    }

    function pctColor(pct) {
        if (pct < 0) return root.theme.muted;
        if (pct <= 20) return root.theme.warn;
        if (pct <= 40) return root.theme.accent2;
        return root.theme.accent;
    }

    Column {
        id: list
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 18
        spacing: 8


        // The system battery comes straight from UPower rather than the
        // script, so it carries time-to-empty. Absent on this desktop —
        // see Platform for why the gate is the battery, not the chassis.
        Rectangle {
            visible: Platform.hasSystemBattery
            width: parent.width
            height: 46
            radius: 12
            color: Qt.alpha(root.theme.fg, 0.05)

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 9
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: UPower.onBattery ? "\u{f0079}" : "\u{f0084}"
                    color: UPower.onBattery ? root.theme.accent3 : root.theme.success
                    font.family: root.theme.fontMono
                    font.pixelSize: 15
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Text {
                        text: "System"
                        color: root.theme.fg
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(12)
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: {
                            const d = UPower.displayDevice;
                            if (!d) return "";
                            const secs = UPower.onBattery ? d.timeToEmpty : d.timeToFull;
                            if (!secs || secs <= 0) return UPower.onBattery ? "discharging" : "charging";
                            const h = Math.floor(secs / 3600), m = Math.round((secs % 3600) / 60);
                            return (UPower.onBattery ? "" : "full in ")
                                 + (h > 0 ? h + "h " : "") + m + "m"
                                 + (UPower.onBattery ? " left" : "");
                        }
                        color: Qt.alpha(root.theme.muted, 0.85)
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(9)
                    }
                }
            }
            Text {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: UPower.displayDevice
                      ? Math.round(UPower.displayDevice.percentage * 100) + "%" : ""
                color: root.theme.fg
                font.family: root.theme.fontMono
                font.pixelSize: 13
                font.weight: Font.Bold
            }
        }

        Text {
            visible: root.devices.length === 0 && !Platform.hasSystemBattery
            text: "No batteries visible"
            color: Qt.alpha(root.theme.muted, 0.7)
            font.family: root.theme.fontSans
            font.pixelSize: IslandState.ts(12)
        }

        Repeater {
            model: root.devices

            Rectangle {
                id: devRow
                required property var modelData
                readonly property var look: IslandState.deviceLook(modelData)
                // A controller is listed by the name it was given ("Pink
                // controller"), the HID model underneath.
                readonly property string alias: modelData.kind === "controller" ? IslandState.btName(modelData.mac) : ""
                width: list.width
                height: 50
                radius: 12
                color: Qt.alpha(root.theme.fg, 0.05)

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 9

                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18; height: 18
                        Text {
                            anchors.centerIn: parent
                            visible: devRow.look.kind === ""
                            text: modelData.icon
                            color: root.pctColor(modelData.pct)
                            font.family: root.theme.fontMono
                            font.pixelSize: 15
                        }
                        DeviceGlyph {
                            anchors.centerIn: parent
                            visible: devRow.look.kind !== ""
                            kind: devRow.look.kind || "gamepad"
                            color: devRow.look.tint !== "" ? devRow.look.tint : root.pctColor(modelData.pct)
                            fontFamily: root.theme.fontMono
                            size: 18
                        }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            width: 160
                            elide: Text.ElideRight
                            text: devRow.alias !== "" ? devRow.alias : modelData.name
                            color: root.theme.fg
                            font.family: root.theme.fontSans
                            font.pixelSize: IslandState.ts(12)
                            font.weight: Font.DemiBold
                        }
                        // AirPods report per-bud detail in status; plain
                        // devices report Charging/Discharging.
                        Text {
                            width: 160
                            elide: Text.ElideRight
                            // Bluetooth carries no charging state from an
                            // iPhone; the shared reading has the webhook's.
                            text: modelData.kind === "phone"
                                  ? (IslandState.phoneCharging ? "Charging" : "On battery")
                                  : devRow.alias !== "" ? modelData.name + " · " + modelData.status
                                  : modelData.status
                            color: Qt.alpha(root.theme.muted, 0.85)
                            font.family: root.theme.fontSans
                            font.pixelSize: IslandState.ts(9)
                        }
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 54; height: 5; radius: 2.5
                        color: Qt.alpha(root.theme.fg, 0.10)
                        Rectangle {
                            anchors.left: parent.left
                            height: parent.height
                            radius: parent.radius
                            width: parent.width * Math.max(0, Math.min(1, modelData.pct / 100))
                            color: root.pctColor(modelData.pct)
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.pct >= 0 ? modelData.pct + "%" : "—"
                        color: root.theme.fg
                        font.family: root.theme.fontMono
                        font.pixelSize: 12
                        font.weight: Font.Bold
                    }
                }
            }
        }
    }
}
