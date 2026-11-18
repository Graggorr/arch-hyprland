import QtQuick

// What an empty list says, the way the hub's notification tile says it: a
// glyph in a quiet disc, a short title, and one line on what empty means.
Column {
    id: root

    property var theme
    property string glyph: "\u{f0e1e}"
    property string title: ""
    property string sub: ""
    property real maxWidth: 280

    spacing: 4

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: 30; height: 30; radius: 15
        color: Qt.alpha(root.theme.fg, 0.08)
        Text {
            anchors.centerIn: parent
            text: root.glyph
            color: Qt.alpha(root.theme.fg, 0.6)
            font.family: root.theme.fontMono
            font.pixelSize: 14
        }
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        topPadding: 3
        text: root.title
        color: root.theme.fg
        font.family: root.theme.fontSans
        font.pixelSize: IslandState.ts(12)
        font.weight: Font.DemiBold
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.sub !== ""
        width: Math.min(implicitWidth, root.maxWidth)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: root.sub
        color: Qt.alpha(root.theme.on_surface_variant, 0.7)
        font.family: root.theme.fontSans
        font.pixelSize: IslandState.ts(10)
    }
}
