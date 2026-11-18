import QtQuick

// The phone switch: a track and a thumb that slides, in Material colours.
// One component so every on/off in the shell moves the same way — the
// settings rows, the Bluetooth adapter, whatever grows one next.
Rectangle {
    id: root

    property var theme
    property bool checked: false
    signal toggled()

    implicitWidth: 44
    implicitHeight: 26
    radius: height / 2
    color: root.checked ? root.theme.primary : Qt.alpha(root.theme.on_surface, 0.15)
    Behavior on color { ColorAnimation { duration: 140 } }

    Rectangle {
        width: parent.height - 6
        height: width
        radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        x: root.checked ? parent.width - width - 3 : 3
        Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        color: root.checked ? root.theme.on_primary : root.theme.surface_bright
    }

    HoverHandler { cursorShape: Qt.PointingHandCursor }
    MouseArea {
        anchors.fill: parent
        onClicked: root.toggled()
    }
}
