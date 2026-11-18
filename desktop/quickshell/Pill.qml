import QtQuick

Rectangle {
    id: root

    property var theme
    property bool interactive: false
    property color tint: theme ? theme.fg : "white"
    property bool fillOnHover: false
    property color fillColor: tint
    // Modules whose glyph IS the accent (the distro logo) tint instead of
    // filling, so the icon stays legible on hover.
    property bool darkenOnFill: true
    property string tooltipText: ""
    property bool tooltipAbove: false

    // HoverHandler, not MouseArea.containsMouse: modules resize when their value
    // changes (9% -> 10%), and MouseArea only re-evaluates containment on pointer
    // events, so a relayout under a stationary cursor left hover stuck stale.
    property bool hovered: hover.hovered
    readonly property color contentColor: (fillOnHover && darkenOnFill && hovered && theme) ? theme.base : tint

    signal clicked(var button)
    signal wheel(int delta)

    implicitHeight: 34
    radius: theme ? theme.radius : 12
    color: (fillOnHover && hovered)
           ? fillColor
           : Qt.rgba(theme ? theme.bg.r : 0.1,
                     theme ? theme.bg.g : 0.1,
                     theme ? theme.bg.b : 0.1,
                     hovered && interactive ? 0.95 : (theme ? theme.pillOpacity : 0.85))

    Behavior on color { ColorAnimation { duration: 140 } }

    HoverHandler {
        id: hover
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: false
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: (e) => { if (root.interactive) root.clicked(e.button); }
        onWheel: (e) => { if (root.interactive) root.wheel(e.angleDelta.y); }
    }

    Tooltip {
        id: tipWin
        theme: root.theme
        body: root.tooltipText
        anchor.item: root
        anchor.rect.y: root.tooltipAbove ? -tipWin.implicitHeight - 6 : root.height + 6
        anchor.rect.x: 0
    }

    Timer {
        id: tipDelay
        interval: 350
        onTriggered: if (root.hovered && root.tooltipText !== "") tipWin.visible = true
    }

    onHoveredChanged: {
        if (hovered && tooltipText !== "") tipDelay.restart();
        else { tipDelay.stop(); tipWin.visible = false; }
    }
}
