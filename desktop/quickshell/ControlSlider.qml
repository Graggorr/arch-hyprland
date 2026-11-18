import QtQuick
import Quickshell.Widgets

// A labelled slider card: the name and reading on a line of their own, the
// level below it as a thick capsule whose solid fill carries the glyph. The
// fill never shrinks past its own height, so the glyph always sits in a
// filled circle — the control reads as "on, at this much" even near zero.
// A drillable card shows a chevron on the label line that opens the
// control's full panel.
Item {
    id: root

    property var theme
    property string label: ""
    property string glyph: ""
    property string valueText: ""
    property real value: 0
    property bool muted: false
    property bool drillable: false

    signal moved(real v)
    signal toggleMuted()
    signal drill()

    implicitHeight: 54
    implicitWidth: 200

    readonly property real level: Math.max(0, Math.min(1, root.value))
    readonly property color fillColor: root.muted ? Qt.alpha(root.theme.muted, 0.55) : root.theme.accent
    readonly property color onFill: root.muted ? root.theme.fg : Qt.darker(root.theme.accent, 3.4)

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: Qt.alpha(root.theme.fg, 0.07)
    }

    Text {
        id: labelText
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.top: parent.top
        anchors.topMargin: 7
        text: root.label
        color: root.theme.fg
        font.family: root.theme.fontSans
        font.pixelSize: IslandState.ts(11)
        font.weight: Font.DemiBold
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: root.drillable ? 4 : 12
        anchors.verticalCenter: labelText.verticalCenter
        spacing: 2

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.valueText
            color: Qt.alpha(root.theme.on_surface_variant, 0.8)
            font.family: root.theme.fontSans
            font.features: ({ "tnum": 1 })
            font.pixelSize: IslandState.ts(10)
            font.weight: Font.Medium
        }
        Rectangle {
            visible: root.drillable
            anchors.verticalCenter: parent.verticalCenter
            width: 18; height: 18; radius: 9
            color: chevHov.hovered ? Qt.alpha(root.theme.fg, 0.14) : "transparent"
            Text {
                anchors.centerIn: parent
                text: "\u{f0142}"
                color: Qt.alpha(root.theme.on_surface_variant, 0.85)
                font.family: root.theme.fontMono
                font.pixelSize: 12
            }
            HoverHandler { id: chevHov; cursorShape: Qt.PointingHandCursor }
            MouseArea { anchors.fill: parent; onClicked: root.drill() }
        }
    }

    ClippingRectangle {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 6
        height: Math.max(16, Math.min(24, root.height - 32))
        radius: height / 2
        color: Qt.alpha(root.theme.fg, 0.09)

        Rectangle {
            id: fill
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: track.height + (track.width - track.height) * root.level
            radius: height / 2
            color: root.fillColor
            Behavior on color { ColorAnimation { duration: 150 } }
        }
        Text {
            x: (track.height - width) / 2
            anchors.verticalCenter: parent.verticalCenter
            text: root.glyph
            color: root.onFill
            font.family: root.theme.fontMono
            font.pixelSize: Math.round(track.height * 0.62)
        }
    }

    MouseArea {
        anchors.fill: track
        cursorShape: Qt.PointingHandCursor
        preventStealing: true
        property bool onGlyph: false
        property bool dragging: false
        property real pressX: 0
        function at(x) {
            return Math.max(0, Math.min(1, (x - track.height / 2) / Math.max(1, width - track.height)));
        }
        onPressed: (m) => {
            pressX = m.x;
            dragging = false;
            onGlyph = m.x <= track.height;
            if (!onGlyph) root.moved(at(m.x));
        }
        onPositionChanged: (m) => {
            if (!pressed) return;
            if (!dragging && Math.abs(m.x - pressX) <= 4) return;
            dragging = true;
            root.moved(at(m.x));
        }
        onReleased: if (onGlyph && !dragging) root.toggleMuted()
    }
}
