import QtQuick

// The call, opened. Modelled on the phone's expanded call: a big badge, who
// you are talking through, the running time, and the controls underneath as
// round buttons rather than a list of rows.
//
// There are two of those and not three. Mute is real — it is the app's own
// capture stream, so the far end stops hearing you exactly as if you had
// pressed mute inside the app. Hang up is not: none of Telegram, Slack or
// Discord exposes any way to end a call from outside, and the honest surface
// is a missing button rather than one that quietly does nothing.
Item {
    id: root

    property var theme

    readonly property real preferredHeight: 400

    readonly property bool live: IslandState.inCall
    readonly property color tint:
        !root.live ? root.theme.muted
        : ((IslandState.callMuted || IslandState.callDeafened)
           ? root.theme.error : root.theme.primary)

    Column {
        anchors.centerIn: parent
        spacing: 20
        visible: root.live

        // ── badge ─────────────────────────────────────────────────
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 96; height: 96

            // The halo is the only thing that moves. A ring that keeps
            // breathing is what says the call is still up without needing the
            // seconds to be read.
            Rectangle {
                anchors.centerIn: parent
                width: 96; height: 96; radius: 48
                color: "transparent"
                border.width: 2
                border.color: Qt.alpha(root.tint, 0.35)
                SequentialAnimation on scale {
                    running: root.live
                    loops: Animation.Infinite
                    alwaysRunToEnd: true
                    NumberAnimation { to: 1.0; duration: 1100; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0.86; duration: 1100; easing.type: Easing.InOutSine }
                }
                SequentialAnimation on opacity {
                    running: root.live
                    loops: Animation.Infinite
                    alwaysRunToEnd: true
                    NumberAnimation { to: 0.15; duration: 1100; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0.9; duration: 1100; easing.type: Easing.InOutSine }
                }
            }

            Rectangle {
                anchors.centerIn: parent
                width: 74; height: 74; radius: 37
                color: root.tint
                Behavior on color { ColorAnimation { duration: 200 } }

                Text {
                    anchors.centerIn: parent
                    text: !root.live ? ""
                    : IslandState.callDeafened ? "\u{f07ce}"
                    : IslandState.callMuted ? "\u{f036d}"
                    : IslandState.callApp.glyph
                    color: "#ffffff"
                    font.family: root.theme.fontMono
                    font.pixelSize: 32
                }
            }
        }

        // ── who and how long ──────────────────────────────────────
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 4

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.live ? IslandState.callApp.name : ""
                color: root.theme.fg
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(17)
                font.weight: Font.DemiBold
            }
            // Only the bridge knows this, so it simply is not there without it.
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: IslandState.dcInVoice && IslandState.dcChannel !== ""
                text: IslandState.dcChannel
                    + (IslandState.dcUsers > 1 ? "  ·  " + IslandState.dcUsers + " in channel" : "")
                color: Qt.alpha(root.theme.muted, 0.8)
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(11)
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: IslandState.timerFmt(IslandState.callSecs)
                color: Qt.alpha(root.theme.muted, 0.95)
                font.family: root.theme.fontMono
                font.pixelSize: 15
                font.weight: Font.Bold
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: IslandState.callDeafened ? "deafened"
                    : IslandState.callMuted
                      ? (IslandState.callRpc ? "muted in Discord" : "mic muted on this machine")
                      : "mic live"
                color: (IslandState.callMuted || IslandState.callDeafened)
                       ? root.theme.error : Qt.alpha(root.theme.muted, 0.7)
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(11)
                font.weight: Font.DemiBold
            }
        }

        // ── controls ──────────────────────────────────────────────
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 26

            // Round, labelled underneath, the way the phone lays its call
            // controls out — the glyph is the button and the word explains it.
            component CallButton: Item {
                id: btn
                property var theme
                property string glyph: ""
                property string label: ""
                property color fill: "#ffffff"
                property color glyphColor: "#ffffff"
                signal activated()

                width: 64
                height: circle.height + cap.height + 8

                Rectangle {
                    id: circle
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    width: 56; height: 56; radius: 28
                    color: btn.fill
                    scale: press.pressed ? 0.93 : (btnHover.hovered ? 1.05 : 1)
                    Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 160 } }

                    Text {
                        anchors.centerIn: parent
                        text: btn.glyph
                        color: btn.glyphColor
                        font.family: btn.theme.fontMono
                        font.pixelSize: 22
                    }
                }

                Text {
                    id: cap
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    text: btn.label
                    color: Qt.alpha(btn.theme.muted, 0.9)
                    font.family: btn.theme.fontSans
                    font.pixelSize: IslandState.ts(11)
                    font.weight: Font.DemiBold
                }

                HoverHandler { id: btnHover; cursorShape: Qt.PointingHandCursor }
                MouseArea {
                    id: press
                    anchors.fill: parent
                    onClicked: btn.activated()
                }
            }

            CallButton {
                theme: root.theme
                glyph: IslandState.callMuted ? "\u{f036d}" : "\u{f036c}"
                label: IslandState.callMuted ? "Unmute" : "Mute"
                fill: IslandState.callMuted ? root.theme.error : Qt.alpha(root.theme.fg, 0.12)
                glyphColor: IslandState.callMuted ? "#ffffff" : root.theme.fg
                onActivated: IslandState.toggleCallMute()
            }

            // Present only where it is real. Muting your own output would be
            // a local silence that tells the channel nothing, so there is no
            // fallback version of this button.
            CallButton {
                visible: IslandState.callRpc
                theme: root.theme
                glyph: IslandState.callDeafened ? "\u{f07ce}" : "\u{f02cb}"
                label: IslandState.callDeafened ? "Undeafen" : "Deafen"
                fill: IslandState.callDeafened ? root.theme.error : Qt.alpha(root.theme.fg, 0.12)
                glyphColor: IslandState.callDeafened ? "#ffffff" : root.theme.fg
                onActivated: IslandState.toggleCallDeafen()
            }

            CallButton {
                theme: root.theme
                glyph: "\u{f03cc}"
                label: "Open"
                fill: Qt.alpha(root.theme.fg, 0.12)
                glyphColor: root.theme.fg
                onActivated: IslandState.focusCall()
            }
        }

        // What you are actually getting, when it is not the real thing. Said
        // once, under the controls, rather than left for you to discover when
        // someone asks why they can still see you unmuted.
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.live && IslandState.callApp.id === "discord" && !IslandState.callRpc
            width: 300
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: "Discord RPC not authorized — this mutes the device, so Discord "
                + "still shows you unmuted. Run discord-rpc.py auth."
            color: Qt.alpha(root.theme.muted, 0.6)
            font.family: root.theme.fontSans
            font.pixelSize: IslandState.ts(10)
        }
    }

    // ── nothing on the line ───────────────────────────────────────
    // Reachable: the rail entry survives long enough for the card to still be
    // open on the tick the call drops.
    Column {
        anchors.centerIn: parent
        spacing: 10
        visible: !root.live

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "\u{f03f6}"
            color: Qt.alpha(root.theme.muted, 0.5)
            font.family: root.theme.fontMono
            font.pixelSize: 34
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "No call"
            color: Qt.alpha(root.theme.muted, 0.8)
            font.family: root.theme.fontSans
            font.pixelSize: IslandState.ts(13)
            font.weight: Font.DemiBold
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Telegram, Slack and Discord calls show up here"
            color: Qt.alpha(root.theme.muted, 0.55)
            font.family: root.theme.fontSans
            font.pixelSize: IslandState.ts(11)
        }
    }
}
