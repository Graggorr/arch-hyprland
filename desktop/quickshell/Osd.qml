import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Pipewire

PanelWindow {
    id: root

    property var theme

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var sinkAudio: sink ? sink.audio : null
    readonly property var srcAudio: source ? source.audio : null

    // "volume" | "mic"
    property string mode: "volume"
    // Suppresses the flash that would otherwise fire when the bindings first
    // resolve at startup.
    property bool armed: false
    // The window stays mapped for the fade-out; visible flips only after the
    // capsule has finished leaving. Without this the OSD vanished in one frame
    // no matter what Behaviors the inner rectangle carried.
    property bool shown: false

    PwObjectTracker {
        objects: {
            const o = [];
            if (root.sink) o.push(root.sink);
            if (root.source) o.push(root.source);
            return o;
        }
    }

    // follow the focused monitor rather than duplicating on both
    screen: {
        const want = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        const all = Quickshell.screens;
        for (let i = 0; i < all.length; i++)
            if (all[i].name === want) return all[i];
        return all.length > 0 ? all[0] : null;
    }

    anchors { bottom: true }
    margins { bottom: 140 }
    exclusiveZone: 0
    implicitWidth: 320
    implicitHeight: 84
    color: "transparent"
    visible: false

    readonly property real level: mode === "mic"
        ? (srcAudio ? srcAudio.volume : 0)
        : (sinkAudio ? sinkAudio.volume : 0)
    readonly property bool muted: mode === "mic"
        ? (srcAudio ? srcAudio.muted : false)
        : (sinkAudio ? sinkAudio.muted : false)

    function flash(which) {
        if (!armed) return;
        // The pill carries it instead when the active shape asks for that.
        if (IslandState.cfg.hudInIsland) {
            const mic = which === "mic";
            IslandState.showHud(which,
                mic ? (srcAudio ? srcAudio.volume : 0) : (sinkAudio ? sinkAudio.volume : 0),
                mic ? (srcAudio ? srcAudio.muted : false) : (sinkAudio ? sinkAudio.muted : false));
            return;
        }
        mode = which;
        unmapTimer.stop();
        visible = true;
        shown = true;
        hideTimer.restart();
    }

    Timer { id: hideTimer; interval: 1600; onTriggered: { root.shown = false; unmapTimer.restart(); } }
    Timer { id: unmapTimer; interval: 240; onTriggered: root.visible = false }
    Timer { id: armTimer; interval: 1500; running: true; onTriggered: root.armed = true }

    Connections {
        target: root.sinkAudio
        function onVolumeChanged() { root.flash("volume"); }
        function onMutedChanged() { root.flash("volume"); }
    }

    Connections {
        target: root.srcAudio
        function onMutedChanged() { root.flash("mic"); }
    }

    Item {
        anchors.fill: parent

        opacity: root.shown ? 1 : 0
        scale: root.shown ? 1 : 0.92
        transformOrigin: Item.Bottom
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

        RectangularShadow {
            anchors.fill: capsule
            radius: capsule.radius
            blur: 20; spread: 1
            offset: Qt.vector2d(0, 6)
            color: Qt.alpha(root.theme.shadow, 0.38)
        }

        Rectangle {
            id: capsule
            anchors.fill: parent
            anchors.margins: 12
            radius: height / 2
            color: Qt.rgba(root.theme.surface_container.r, root.theme.surface_container.g,
                           root.theme.surface_container.b, root.theme.contentOpacity)
            border.width: 1
            border.color: Qt.alpha(root.theme.outline, 0.30)

            Row {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 20
                spacing: 14

                // The icon sits in a tonal disc — the M3 "who is talking"
                // badge — and swaps to the error pair when muted, which reads
                // from across the room in a way a grey glyph never did.
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40; height: 40; radius: 20
                    color: root.muted ? Qt.alpha(root.theme.error, 0.20)
                                      : root.theme.primary_container
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: {
                            if (root.mode === "mic")
                                return root.muted ? "\u{f036d}" : "\u{f036c}";
                            if (root.muted) return "\u{f075f}";
                            const p = root.level * 100;
                            return p >= 66 ? "\u{f057e}" : p >= 33 ? "\u{f0580}" : "\u{f057f}";
                        }
                        color: root.muted ? root.theme.error : root.theme.on_primary_container
                        font.family: root.theme.fontMono
                        font.pixelSize: 19
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 40 - 14 - 46 - 14
                    height: 6
                    radius: 3
                    color: Qt.alpha(root.theme.on_surface, 0.16)

                    Rectangle {
                        width: Math.max(height, parent.width * Math.max(0, Math.min(1, root.level)))
                        height: parent.height
                        radius: 3
                        color: root.muted ? Qt.alpha(root.theme.on_surface_variant, 0.6) : root.theme.primary
                        Behavior on width { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 130 } }
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 46
                    horizontalAlignment: Text.AlignRight
                    text: root.muted && root.mode === "mic" ? "off" : Math.round(root.level * 100) + "%"
                    color: root.muted ? root.theme.on_surface_variant : root.theme.on_surface
                    font.family: root.theme.fontMono
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
            }
        }
    }
}
