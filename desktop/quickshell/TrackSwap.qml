import QtQuick

// Replays a short entrance on its target whenever the track changes: the new
// title or cover slides in from the side, fades up and settles with a touch
// of overshoot, instead of the text just being swapped in place. Drop one
// inside (or beside) any piece of now-playing UI and point it at that piece;
// stagger several with `delay` so cover, title and artist arrive in order.
//
// It owns the target's opacity, scale and a Translate while it runs, so the
// target must not bind opacity or scale itself — point it at a wrapper then.
Item {
    id: root

    property Item target: parent
    property real shift: 14
    property real fromScale: 1
    property int delay: 0

    readonly property string key: IslandState.trackKey
    property string last: ""
    readonly property Translate tr: Translate {}

    visible: false
    width: 0
    height: 0

    Component.onCompleted: {
        root.last = root.key;
        if (root.target) root.target.transform = [root.tr];
    }

    // Only a real change replays: starting or stopping playback has its own
    // fades elsewhere, and a re-emitted identical key is not a new song.
    onKeyChanged: {
        const was = root.last;
        root.last = root.key;
        if (!root.target || was === "" || root.key === "" || was === root.key) return;
        if (!IslandState.cfg.morph) return;
        swap.restart();
    }

    SequentialAnimation {
        id: swap
        ScriptAction {
            script: {
                root.target.opacity = 0;
                root.target.scale = root.fromScale;
                root.tr.x = root.shift;
            }
        }
        PauseAnimation { duration: root.delay }
        ParallelAnimation {
            NumberAnimation { target: root.target; property: "opacity"; to: 1; duration: 300; easing.type: Easing.OutCubic }
            NumberAnimation { target: root.tr; property: "x"; to: 0; duration: 440; easing.type: Easing.OutCubic }
            NumberAnimation { target: root.target; property: "scale"; to: 1; duration: 480; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
        }
    }
}
