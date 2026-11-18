import QtQuick
import Quickshell.Io

// Capture and colour picking. Screenshots already have three keybinds, so what
// this adds is the part a keybind cannot: seeing what you took, and a colour
// picker — hyprpicker is installed but had no binding at all, so picking a
// colour off the screen meant knowing to type it.
//
// Every action here closes the card first; the picked colour and the new shot
// are waiting the next time it is opened.
Item {
    id: root

    property var theme

    readonly property real preferredHeight: 432

    readonly property string script: "@HOME@/.config/quickshell/scripts/capture.sh"

    property var shots: IslandState.cacheGet("capture.shots", [])
    property var colors: IslandState.cacheGet("capture.colors", [])
    property string flash: ""

    function reload() { listProc.running = true; }

    Process {
        id: listProc
        command: ["bash", root.script, "list", "12"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(this.text.trim());
                    root.shots = j.shots || [];
                    root.colors = j.colors || [];
                    IslandState.cacheSet("capture.shots", root.shots);
                    IslandState.cacheSet("capture.colors", root.colors);
                } catch (e) { root.shots = []; root.colors = []; }
            }
        }
    }

    Process { id: openProc }
    function openShot(path) {
        openProc.command = ["bash", root.script, "open", path];
        openProc.running = true;
    }
    function reveal() {
        openProc.command = ["bash", root.script, "reveal"];
        openProc.running = true;
    }

    Process { id: copyProc }
    function copyColor(hex) {
        copyProc.command = ["wl-copy", hex];
        copyProc.running = true;
        root.flash = hex;
        flashOff.restart();
    }
    Timer { id: flashOff; interval: 900; onTriggered: root.flash = "" }

    readonly property var actions: [
        { label: "Area",   glyph: "\u{f0486}", verb: "shot", arg: "area"   },
        { label: "Window", glyph: "\u{f05d1}", verb: "shot", arg: "window" },
        { label: "Screen", glyph: "\u{f0379}", verb: "shot", arg: "output" },
        { label: "Colour", glyph: "\u{f0765}", verb: "pick", arg: ""       }
    ]

    // ── recording ─────────────────────────────────────────────────
    // Recording is OBS's job, not a second recorder's: it is already installed
    // and configured with the scenes, encoder and output path this machine
    // uses. The button is a remote for it — the state shown is OBS's own.
    readonly property bool obsRunning: IslandState.obsRunning
    readonly property bool recording: IslandState.obsRecording

    Column {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 12

        // ── actions ───────────────────────────────────────────────
        Row {
            width: parent.width
            spacing: 8

            Repeater {
                model: root.actions

                // Addressed by id, not by walking parent chains: a parent.parent
                // from inside the Column resolves one level off in a Repeater
                // delegate and silently yields undefined rather than erroring.
                Rectangle {
                    id: actBtn
                    required property var modelData
                    width: (root.width - 36 - 24) / 4
                    height: 56
                    radius: 12
                    color: ah.hovered ? Qt.alpha(root.theme.accent, 0.20)
                                      : Qt.alpha(root.theme.fg, 0.06)
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Column {
                        anchors.centerIn: parent
                        spacing: 3
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: actBtn.modelData.glyph
                            color: ah.hovered ? root.theme.accent : root.theme.fg
                            font.family: root.theme.fontMono
                            font.pixelSize: 18
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: actBtn.modelData.label
                            color: Qt.alpha(root.theme.muted, 0.95)
                            font.family: root.theme.fontSans
                            font.pixelSize: IslandState.ts(10)
                            font.weight: Font.DemiBold
                        }
                    }

                    HoverHandler { id: ah; cursorShape: Qt.PointingHandCursor }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (actBtn.modelData.arg === "")
                                IslandState.capture(actBtn.modelData.verb);
                            else
                                IslandState.capture(actBtn.modelData.verb,
                                                    actBtn.modelData.arg);
                        }
                    }
                }
            }
        }

        // ── recording ─────────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: 48
            radius: 12
            color: root.recording ? Qt.alpha(root.theme.error, 0.22)
                 : (rech.hovered ? Qt.alpha(root.theme.fg, 0.12)
                                 : Qt.alpha(root.theme.fg, 0.06))
            border.width: 1
            border.color: root.recording ? Qt.alpha(root.theme.error, 0.55) : "transparent"
            Behavior on color { ColorAnimation { duration: 140 } }

            // Pulses only while recording — a still red dot next to a timecode
            // is hard to tell from a red icon that is simply always there.
            Rectangle {
                id: dot
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                width: 12; height: 12; radius: 6
                color: root.recording ? root.theme.error : Qt.alpha(root.theme.muted, 0.65)

                SequentialAnimation on opacity {
                    running: root.recording
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.25; duration: 700; easing.type: Easing.InOutQuad }
                    NumberAnimation { to: 1.0;  duration: 700; easing.type: Easing.InOutQuad }
                    // An animation on a property keeps whatever value it was
                    // holding when it stops, so without this the dot is left
                    // dimmed mid-pulse once recording ends.
                    onRunningChanged: if (!running) dot.opacity = 1
                }
            }

            Column {
                anchors.left: parent.left
                anchors.leftMargin: 40
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                    text: root.recording ? "Recording" : "Record screen"
                    color: root.recording ? root.theme.error : root.theme.fg
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(12)
                    font.weight: Font.DemiBold
                }
                Text {
                    text: root.recording ? IslandState.obsTimecode + "  ·  OBS"
                        : IslandState.obsNeedsRestart ? "restart OBS to enable control"
                        : (root.obsRunning ? "OBS ready" : "starts OBS")
                    color: IslandState.obsNeedsRestart ? root.theme.accent2
                                                       : Qt.alpha(root.theme.muted, 0.9)
                    font.family: root.theme.fontMono
                    font.pixelSize: 9
                }
            }

            Text {
                id: openLink
                anchors.right: obsBtn.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: "open OBS"
                color: oh.hovered ? root.theme.accent : Qt.alpha(root.theme.muted, 0.8)
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(10)
                HoverHandler { id: oh; cursorShape: Qt.PointingHandCursor }
                MouseArea { anchors.fill: parent; onClicked: IslandState.obsOpen() }
            }

            Rectangle {
                id: obsBtn
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 78; height: 30
                radius: 9
                color: root.recording ? Qt.alpha(root.theme.error, 0.40)
                                      : Qt.alpha(root.theme.fg, 0.14)
                Behavior on color { ColorAnimation { duration: 140 } }
                Text {
                    anchors.centerIn: parent
                    text: root.recording ? "Stop" : "Start"
                    color: root.theme.fg
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(11)
                    font.weight: Font.DemiBold
                }
            }

            HoverHandler { id: rech; cursorShape: Qt.PointingHandCursor }
            // Stops short of the "open OBS" link rather than covering it: these
            // are declared last and would otherwise sit on top of it and
            // swallow its clicks.
            MouseArea {
                anchors.left: parent.left
                anchors.right: openLink.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                onClicked: IslandState.obsToggle()
            }
            MouseArea {
                anchors.fill: obsBtn
                onClicked: IslandState.obsToggle()
            }
        }

        // ── colours ───────────────────────────────────────────────
        Item {
            width: parent.width
            height: 16
            visible: root.colors.length > 0
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Picked colours"
                color: Qt.alpha(root.theme.on_surface_variant, 0.9)
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(11)
                font.weight: Font.DemiBold
                font.letterSpacing: 0.2
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.flash !== "" ? root.flash + " copied" : "click to copy"
                color: root.flash !== "" ? root.theme.success : Qt.alpha(root.theme.muted, 0.8)
                font.family: root.theme.fontMono
                font.pixelSize: 9
            }
        }

        Flow {
            width: parent.width
            spacing: 6
            visible: root.colors.length > 0

            Repeater {
                model: root.colors

                Rectangle {
                    id: swatch
                    required property string modelData
                    readonly property bool copied: root.flash === modelData

                    width: 42; height: 28
                    radius: 8
                    color: modelData
                    border.width: copied ? 2 : 1
                    border.color: copied ? root.theme.success : Qt.alpha(root.theme.fg, 0.25)

                    // The swatch is the colour, so the label on it has to stay
                    // legible on both a near-black and a near-white pick.
                    // modelData is the hex *string* — hslLightness is a
                    // property of the colour type, so it has to be converted
                    // rather than read off the string.
                    Text {
                        anchors.centerIn: parent
                        visible: ch.hovered
                        text: swatch.modelData.replace("#", "")
                        color: Qt.color(swatch.modelData).hslLightness > 0.5
                               ? "#000000" : "#ffffff"
                        font.family: root.theme.fontMono
                        font.pixelSize: 8
                        font.weight: Font.Bold
                    }

                    HoverHandler { id: ch; cursorShape: Qt.PointingHandCursor }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.copyColor(swatch.modelData)
                    }
                }
            }
        }

        // ── recent shots ──────────────────────────────────────────
        Item {
            width: parent.width
            height: 16
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Recent"
                color: Qt.alpha(root.theme.on_surface_variant, 0.9)
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(11)
                font.weight: Font.DemiBold
                font.letterSpacing: 0.2
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "open folder"
                color: fh.hovered ? root.theme.accent : Qt.alpha(root.theme.muted, 0.85)
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(10)
                HoverHandler { id: fh; cursorShape: Qt.PointingHandCursor }
                MouseArea { anchors.fill: parent; onClicked: root.reveal() }
            }
        }

        Item {
            visible: root.shots.length === 0
            width: parent.width
            height: 110
            EmptyState {
                anchors.centerIn: parent
                theme: root.theme
                maxWidth: parent.width - 20
                glyph: "\u{f0104}"
                title: "No screenshots yet"
                sub: "Shots taken here land in ~/Pictures/Screenshots; the Print keys copy without saving"
            }
        }

        Flow {
            width: parent.width
            spacing: 6

            Repeater {
                model: root.shots

                Rectangle {
                    id: thumb
                    required property var modelData
                    width: 132; height: 84
                    radius: 10
                    color: Qt.alpha(root.theme.fg, 0.06)
                    clip: true
                    border.width: 1
                    border.color: th.hovered ? Qt.alpha(root.theme.accent, 0.55)
                                             : Qt.alpha(root.theme.fg, 0.10)

                    Image {
                        anchors.fill: parent
                        anchors.margins: 1
                        source: "file://" + thumb.modelData.path
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        // Decoding a 2560x1440 png at full size for a 132px
                        // tile is the whole cost of this panel; sourceSize caps
                        // it at the tile.
                        sourceSize.width: 264
                        smooth: true
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 18
                        color: Qt.rgba(0, 0, 0, 0.55)
                        Text {
                            anchors.centerIn: parent
                            text: thumb.modelData.when
                            color: "#ffffff"
                            font.family: root.theme.fontMono
                            font.pixelSize: 9
                        }
                    }

                    HoverHandler { id: th; cursorShape: Qt.PointingHandCursor }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.openShot(thumb.modelData.path)
                    }
                }
            }
        }
    }
}
