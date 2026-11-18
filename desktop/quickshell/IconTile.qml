import QtQuick

// The hub's toggle, as a part every panel can use: a neutral card with a
// round icon on the left, a label and a state line. On fills the circle with
// the tint and cuts the glyph out of it in a deep shade of that tint; off is
// a quiet grey disc. A danger tile shows its glyph in the error colour, and
// an armed one (a destructive action waiting for its second click) fills the
// circle with it and says so on the state line.
Rectangle {
    id: root

    property var theme
    property string glyph: ""
    property string label: ""
    property string sub: ""
    property bool on: false
    property color tint: theme ? theme.accent : "white"
    property bool danger: false
    property bool armed: false
    property bool interactive: true

    signal clicked(int button)

    implicitWidth: 170
    implicitHeight: 54
    radius: 16
    color: hov.hovered && root.interactive ? Qt.alpha(root.theme.fg, 0.11)
                                           : Qt.alpha(root.theme.fg, 0.07)
    border.width: root.armed ? 1 : 0
    border.color: Qt.alpha(root.theme.warn, 0.5)
    Behavior on color { ColorAnimation { duration: 130 } }

    readonly property color circleColor:
        root.armed ? root.theme.warn
        : root.on ? root.tint
        : Qt.alpha(root.theme.fg, 0.10)
    readonly property color glyphColor:
        root.armed ? Qt.darker(root.theme.warn, 3.4)
        : root.on ? Qt.darker(root.tint, 3.4)
        : root.danger ? root.theme.warn
        : Qt.alpha(root.theme.fg, 0.88)

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        Rectangle {
            id: disc
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(34, root.height - 18)
            height: width
            radius: width / 2
            color: root.circleColor
            Behavior on color { ColorAnimation { duration: 160 } }
            Text {
                anchors.centerIn: parent
                text: root.glyph
                color: root.glyphColor
                font.family: root.theme.fontMono
                font.pixelSize: Math.round(disc.width * 0.47)
                Behavior on color { ColorAnimation { duration: 160 } }
            }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: root.width - disc.width - 30
            spacing: 1
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: root.label
                color: root.theme.fg
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(12)
                font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                visible: text !== ""
                elide: Text.ElideRight
                text: root.armed ? "click again" : root.sub
                color: root.armed ? root.theme.warn : Qt.alpha(root.theme.on_surface_variant, 0.85)
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(9)
                font.weight: root.armed ? Font.DemiBold : Font.Normal
            }
        }
    }

    HoverHandler { id: hov; enabled: root.interactive; cursorShape: Qt.PointingHandCursor }
    MouseArea {
        anchors.fill: parent
        enabled: root.interactive
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (e) => root.clicked(e.button)
    }
}
