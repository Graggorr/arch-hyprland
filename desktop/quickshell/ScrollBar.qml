import QtQuick

// A slim overlay scrollbar for any Flickable, ListView or GridView.
//
// It is declared *inside* the flickable it serves so that attaching a bar stays
// one line at each call site, and it reparents itself to that flickable. Where
// an inline child lands otherwise depends on the type: a plain Flickable puts
// it in the content item, where it scrolls away with the content, while
// ListView and GridView keep it as a child of the view. Owning the parent
// outright is what makes one component behave the same in all three.
Item {
    id: root

    required property Flickable flick
    property var theme

    parent: flick

    property real barWidth: 6
    property real edgeMargin: 3
    property real endMargin: 6
    // Shortest the handle is allowed to get. A proportional handle on a long
    // list shrinks to a few pixels and stops being grabbable.
    property real minHandle: 32
    // One mouse notch. Flickable's own step is three text lines, which is a
    // crawl on the island's longer lists; this is closer to a third of a view.
    property real wheelStep: 110

    readonly property real scrollable:
        flick ? Math.max(0, flick.contentHeight - flick.height) : 0
    readonly property real position:
        scrollable > 0 ? Math.max(0, Math.min(1, flick.contentY / scrollable)) : 0
    readonly property bool engaged: hover.hovered || area.pressed

    z: 100
    visible: scrollable > 1
    width: barWidth + edgeMargin * 2
    height: flick ? flick.height : 0
    x: flick ? flick.width - width : 0
    y: 0

    // Dim while idle so it reads as a position indicator, full strength once
    // the pointer is on it or the view is actually moving.
    opacity: engaged || (flick && flick.moving) ? 1 : 0.75
    Behavior on opacity { NumberAnimation { duration: 140 } }

    Rectangle {
        id: track
        x: root.edgeMargin
        y: root.endMargin
        width: root.barWidth
        height: Math.max(0, root.height - root.endMargin * 2)
        radius: width / 2
        color: Qt.alpha(root.theme.fg, 0.10)
    }

    Rectangle {
        id: handle
        x: root.edgeMargin
        width: root.barWidth
        height: Math.max(root.minHandle,
                         track.height * (root.flick.height / Math.max(1, root.flick.contentHeight)))
        // Driven by the binding, never by the drag: the drag writes contentY
        // and the position follows, so nothing has to break this binding and
        // re-establish it afterwards.
        y: track.y + (track.height - height) * root.position
        radius: width / 2
        color: root.engaged ? root.theme.accent : Qt.alpha(root.theme.fg, 0.45)
        // The wallpaper grid puts the bar over full-bleed thumbnails, where a
        // pale handle on a pale photo disappears. A hairline of the surface
        // colour keeps the edge readable against anything behind it.
        border.width: 1
        border.color: Qt.alpha(root.theme.base, 0.55)
        Behavior on color { ColorAnimation { duration: 130 } }
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }

    MouseArea {
        id: area
        anchors.fill: parent
        // The bar lives inside the flickable, so the flickable filters its
        // mouse events: past the drag threshold it steals the grab and starts
        // dragging the content instead. Content follows the pointer, the bar
        // opposes it, so a handle dragged downwards scrolled the view up and
        // then came loose. Keeping the grab is what makes the handle actually
        // track the pointer all the way to the bottom.
        preventStealing: true
        property real grab: 0

        onPressed: mouse => {
            glide.stop();
            // A flick still coasting would keep writing contentY underneath
            // the drag and fight it for as long as it takes to decelerate.
            if (root.flick.flicking) root.flick.cancelFlick();
            if (mouse.y >= handle.y && mouse.y <= handle.y + handle.height) {
                grab = mouse.y - handle.y;
            } else {
                // Clicking the bare track puts the handle under the pointer
                // rather than paging, which is one gesture instead of several
                // on a list long enough to need the bar in the first place.
                grab = handle.height / 2;
                root.moveHandleTo(mouse.y - grab);
            }
        }
        onPositionChanged: mouse => {
            if (pressed) root.moveHandleTo(mouse.y - grab);
        }
    }

    function moveHandleTo(handleTop) {
        const span = track.height - handle.height;
        if (span <= 0 || root.scrollable <= 0) return;
        const frac = Math.max(0, Math.min(1, (handleTop - track.y) / span));
        root.flick.contentY = frac * root.scrollable;
    }

    // Wheel: a bigger step than Flickable's, eased so a burst of notches reads
    // as one glide instead of a stutter. Restricted to real mice on purpose —
    // touchpads send pixel deltas that are already the right size, and scaling
    // those would make them unusable.
    //
    // The glide is timed by distance rather than held at a fixed duration. A
    // fixed one gives every call site a different speed: a notch is 110px in
    // the island and a whole ~200px thumbnail row in the wallpaper grid, so
    // the same duration is a glide in one and a lurch in the other. Timing it
    // by distance keeps px/second identical everywhere, and a burst of notches
    // still lands fast because the distance keeps growing once the cap is hit.
    property real glideSpeed: 0.8   // px per ms
    property int glideMin: 130
    property int glideMax: 280

    NumberAnimation {
        id: glide
        target: root.flick
        property: "contentY"
        // Duration is set per glide, from the distance — see scrollBy.
        easing.type: Easing.OutQuad
    }

    WheelHandler {
        parent: root.flick
        blocking: true
        acceptedDevices: PointerDevice.Mouse
        enabled: root.scrollable > 0
        onWheel: event => root.scrollBy(-event.angleDelta.y / 120 * root.wheelStep)
    }

    // Notches that land mid-glide add to where the glide was going, not to
    // wherever it happens to have reached — otherwise fast scrolling loses
    // most of its distance to the easing curve.
    function scrollBy(dy) {
        if (root.scrollable <= 0) return;
        const from = glide.running ? glide.to : root.flick.contentY;
        const to = Math.max(0, Math.min(root.scrollable, from + dy));
        // A flick the user started by dragging would keep writing contentY
        // against the glide until it decelerated. Only cancel a live one:
        // cancelFlick() on a view that is not moving still ends a movement,
        // and on GridView that runs the fixup pass for no reason.
        if (root.flick.flicking) root.flick.cancelFlick();
        glide.stop();
        glide.duration = Math.max(root.glideMin,
                                  Math.min(root.glideMax,
                                           Math.abs(to - root.flick.contentY) / root.glideSpeed));
        glide.from = root.flick.contentY;
        glide.to = to;
        glide.start();
    }
}
