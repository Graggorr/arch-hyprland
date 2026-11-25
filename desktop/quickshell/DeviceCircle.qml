import QtQuick

// A linked device's piece of the island, detached left: the AirPods Pro, the
// phone, a controller or the power station, there only while it is reachable, so its presence alone answers
// "is it connected". The ring is the charge, from IslandState's shared
// reading (the menu bar's device items read the same one); the icon is
// DeviceGlyph, a controller's in its own body colour.
Item {
    id: root

    property var theme
    property string screenName: ""
    property bool expanded: false
    // "airpods", "phone", "mouse", "station" or "controller"; a controller also takes its entry
    // from IslandState.controllers.
    property string kind: "airpods"
    property var device: null

    readonly property bool isPhone: root.kind === "phone"
    readonly property bool isPad: root.kind === "controller"
    readonly property bool isStation: root.kind === "station"
    readonly property bool isMouse: root.kind === "mouse"
    readonly property bool connected: root.isPad ? root.device !== null
        : root.isStation ? IslandState.stationOnline
        : root.isMouse ? IslandState.mouseConnected
        : root.isPhone ? IslandState.phoneConnected : IslandState.airpodsConnected
    readonly property real pct: root.isPad ? (root.device ? root.device.pct : -1)
        : root.isStation ? IslandState.stationFrac
        : root.isMouse ? IslandState.mousePct
        : root.isPhone ? IslandState.phonePct : IslandState.airpodsPct
    readonly property bool charging: root.isPad ? (root.device !== null && root.device.charging)
        : root.isStation ? false
        : root.isMouse ? IslandState.mouseCharging
        : root.isPhone ? IslandState.phoneCharging : IslandState.airpodsCharging
    readonly property color ringColor: IslandState.batteryColor(root.pct, root.charging, root.theme)

    implicitWidth: root.expanded ? 34 : 30
    implicitHeight: implicitWidth
    Behavior on implicitWidth { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

    scale: hov.hovered ? 1.08 : 1
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
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

    DeviceGlyph {
        anchors.centerIn: parent
        kind: root.isPad ? (root.device ? root.device.kind : "gamepad")
            : root.isPhone ? IslandState.phoneKind : root.kind
        color: root.isPad && root.device && root.device.tint !== "" ? root.device.tint
             : Qt.alpha(root.theme.fg, 0.9)
        fontFamily: root.theme.fontMono
        size: root.width - 11
    }

    HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
    MouseArea {
        anchors.fill: parent
        // The batteries tool is where the per-bud, case and phone levels live.
        onClicked: IslandState.toggleTool("battery", root.screenName)
    }
}
