import QtQuick

// The first tool that is not a view of something else — it owns running state,
// which is exactly why that state sits in IslandState and not here. Close the
// card, switch monitors, hover the other island: the countdown carries on and
// the trailing capsule keeps showing it.
//
// Two faces, the way the phone does it: nothing armed means the picker, and an
// armed timer means the dial. They are never both up, so the card never has to
// explain which number is the one you are editing.
Item {
    id: root

    property var theme

    readonly property real preferredHeight: 400

    readonly property bool idle: IslandState.timerTotal <= 0
    readonly property bool done: IslandState.timerDone

    // The dial's share of the finished state. Same shape as the capsule's
    // pulse and for the same reason: a value the bindings read, so nothing has
    // to hand a colour or a scale over to an animation and lose its binding.
    // It keeps going after the alarm has rung itself out — the sound says the
    // timer finished, the dial says it is still waiting for you.
    property real donePulse: 0

    SequentialAnimation {
        running: root.done
        loops: Animation.Infinite
        alwaysRunToEnd: true
        onStopped: root.donePulse = 0
        NumberAnimation {
            target: root; property: "donePulse"
            from: 0; to: 1; duration: 460; easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root; property: "donePulse"
            from: 1; to: 0; duration: 640; easing.type: Easing.InOutCubic
        }
    }

    readonly property int picked:
        hourWheel.value * 3600 + minWheel.value * 60 + secWheel.value

    function applyPick(secs) {
        hourWheel.setValue(Math.floor(secs / 3600));
        minWheel.setValue(Math.floor((secs % 3600) / 60));
        secWheel.setValue(secs % 60);
    }

    // The wheels are built once and only hidden while a timer runs, so the
    // value survives a start/reset round trip without being re-derived.
    Component.onCompleted: root.applyPick(IslandState.timerPick)

    // A timer can also be started from a keybind or a script, and resetting
    // that one should come back to its length rather than to whatever the
    // wheels happened to be showing. Safe to follow blindly: turning a wheel
    // does not write the pick, only actually starting a timer does.
    Connections {
        target: IslandState
        function onTimerPickChanged() { root.applyPick(IslandState.timerPick); }
    }

    // ── one column of the picker ──────────────────────────────────
    // `theme` is passed in rather than reached for: an inline component does
    // not resolve the enclosing file's ids at runtime, the same trap the
    // clipped card children hit.
    component Wheel: Item {
        id: wheel

        property var theme
        property int count: 60
        // Written by the view, read by the parent. Deliberately one-way — a
        // two-way binding between this and currentIndex snaps back mid-drag.
        property int value: 0

        readonly property real rowH: 34
        readonly property int rows: 5

        function setValue(v) {
            view.currentIndex = Math.max(0, Math.min(wheel.count - 1, Math.round(v)));
        }

        width: 54
        height: rowH * rows

        ListView {
            id: view
            anchors.fill: parent
            model: wheel.count
            clip: true

            // Carried on the view so the delegates can reach them through
            // ListView.view instead of resolving ids up out of the inline
            // component — the same reason the tool takes `theme` as a property.
            // Typed, and resolved here rather than in the delegate: the Loader
            // hands the theme over after construction, so a delegate reading
            // `theme.fg` directly throws on every row of every column first.
            property color wheelFg: wheel.theme ? wheel.theme.fg : "#e0e3e8"
            property string wheelFont: wheel.theme ? wheel.theme.fontClock : "monospace"
            property var wheelFeatures: wheel.theme ? wheel.theme.clockFeatures : ({})
            property real wheelRowH: wheel.rowH

            // What makes it a wheel rather than a list: the view is only ever
            // allowed to rest with a row in the middle band, so a flick always
            // settles on a value and never between two.
            snapMode: ListView.SnapToItem
            highlightRangeMode: ListView.StrictlyEnforceRange
            preferredHighlightBegin: wheel.rowH * Math.floor(wheel.rows / 2)
            preferredHighlightEnd: wheel.rowH * (Math.floor(wheel.rows / 2) + 1)
            highlightMoveDuration: 220
            highlightMoveVelocity: -1

            boundsBehavior: Flickable.StopAtBounds
            flickDeceleration: 3200
            maximumFlickVelocity: 2000

            onCurrentIndexChanged: wheel.value = currentIndex

            delegate: Item {
                id: cell
                required property int index
                readonly property var v: cell.ListView.view

                width: v ? v.width : 0
                height: v ? v.wheelRowH : 0

                // Distance from the centre band in rows. Taken from contentY
                // rather than currentIndex so the fade tracks the drag itself
                // instead of jumping a row at a time at each snap.
                readonly property real dist: !v ? 0
                    : Math.abs((cell.index * v.wheelRowH + v.wheelRowH / 2)
                               - (v.contentY + v.height / 2)) / v.wheelRowH

                Text {
                    anchors.centerIn: parent
                    text: ("0" + cell.index).slice(-2)
                    color: cell.v ? cell.v.wheelFg : "#e0e3e8"
                    opacity: Math.max(0.12, 1 - cell.dist * 0.44)
                    scale: Math.max(0.74, 1 - cell.dist * 0.12)
                    font.family: cell.v ? cell.v.wheelFont : "monospace"
                    font.features: cell.v ? cell.v.wheelFeatures : ({})
                    font.pixelSize: 21
                    font.weight: cell.dist < 0.5 ? Font.Black : Font.DemiBold
                }
            }
        }
    }

    // ── picker face ───────────────────────────────────────────────
    Column {
        anchors.centerIn: parent
        spacing: 18
        visible: root.idle

        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 306
            height: hourWheel.height

            // The selected row reads as one band across all three columns,
            // which is what tells you the three numbers are a single value.
            Rectangle {
                anchors.centerIn: parent
                width: parent.width
                height: hourWheel.rowH
                radius: 10
                color: Qt.alpha(root.theme.fg, 0.08)
            }

            // Spelled out rather than driven by a Repeater: three columns is
            // the whole model, and the ids are what everything else reads.
            Row {
                anchors.centerIn: parent
                spacing: 0

                Item {
                    width: 102
                    height: hourWheel.height

                    Wheel {
                        id: hourWheel
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        theme: root.theme
                        count: 24
                    }
                    Text {
                        anchors.left: hourWheel.right
                        anchors.leftMargin: 7
                        anchors.verticalCenter: parent.verticalCenter
                        text: "h"
                        color: Qt.alpha(root.theme.muted, 0.9)
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(12)
                        font.weight: Font.DemiBold
                    }
                }

                Item {
                    width: 102
                    height: minWheel.height

                    Wheel {
                        id: minWheel
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        theme: root.theme
                        count: 60
                    }
                    Text {
                        anchors.left: minWheel.right
                        anchors.leftMargin: 7
                        anchors.verticalCenter: parent.verticalCenter
                        text: "m"
                        color: Qt.alpha(root.theme.muted, 0.9)
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(12)
                        font.weight: Font.DemiBold
                    }
                }

                Item {
                    width: 102
                    height: secWheel.height

                    Wheel {
                        id: secWheel
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        theme: root.theme
                        count: 60
                    }
                    Text {
                        anchors.left: secWheel.right
                        anchors.leftMargin: 7
                        anchors.verticalCenter: parent.verticalCenter
                        text: "s"
                        color: Qt.alpha(root.theme.muted, 0.9)
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(12)
                        font.weight: Font.DemiBold
                    }
                }
            }
        }

        // ── presets ───────────────────────────────────────────────
        // Still one click to a running timer. They fill the wheels on the way
        // through so a later Reset comes back to the length you last used.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 6

            Repeater {
                model: [
                    { label: "1m", secs: 60 },
                    { label: "5m", secs: 300 },
                    { label: "10m", secs: 600 },
                    { label: "25m", secs: 1500 },
                    { label: "45m", secs: 2700 }
                ]
                Rectangle {
                    required property var modelData
                    width: 50; height: 28
                    radius: 14
                    color: presetHover.hovered ? Qt.alpha(root.theme.accent, 0.28)
                                               : Qt.alpha(root.theme.fg, 0.07)
                    border.width: 1
                    border.color: presetHover.hovered ? Qt.alpha(root.theme.accent, 0.45)
                                                      : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        text: modelData.label
                        color: presetHover.hovered ? root.theme.accent : root.theme.fg
                        font.family: root.theme.fontMono
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                    HoverHandler { id: presetHover; cursorShape: Qt.PointingHandCursor }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.applyPick(modelData.secs);
                            IslandState.timerStart(modelData.secs);
                        }
                    }
                }
            }
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 216; height: 34
            radius: 17
            opacity: root.picked > 0 ? 1 : 0.4
            color: Qt.alpha(root.theme.tertiary, startHover.hovered && root.picked > 0 ? 0.38 : 0.22)
            border.width: 1
            border.color: Qt.alpha(root.theme.tertiary, 0.5)
            Behavior on color { ColorAnimation { duration: 120 } }

            Row {
                anchors.centerIn: parent
                spacing: 6
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{f040a}"
                    color: root.theme.tertiary
                    font.family: root.theme.fontMono
                    font.pixelSize: 13
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.picked > 0 ? "Start " + IslandState.timerFmt(root.picked)
                                          : "Start"
                    color: root.theme.tertiary
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(12)
                    font.weight: Font.DemiBold
                }
            }
            HoverHandler { id: startHover; cursorShape: Qt.PointingHandCursor }
            MouseArea {
                anchors.fill: parent
                enabled: root.picked > 0
                onClicked: IslandState.timerStart(root.picked)
            }
        }
    }

    // ── running face ──────────────────────────────────────────────
    Column {
        anchors.centerIn: parent
        spacing: 18
        visible: !root.idle

        // ── dial ──────────────────────────────────────────────────
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 132; height: 132
            scale: 1 + 0.05 * root.donePulse

            RingProgress {
                anchors.fill: parent
                thickness: 5 + 2 * root.donePulse
                progress: IslandState.timerProgress
                // A finished dial is a full ring, and grey would read as
                // paused. Paused is the only state that stays muted.
                ring: root.done
                    ? Qt.alpha(root.theme.tertiary, 0.55 + 0.45 * root.donePulse)
                    : (IslandState.timerRunning ? root.theme.tertiary : root.theme.muted)
                track: root.theme.fg
                trackAlpha: 0.12
            }

            Column {
                anchors.centerIn: parent
                spacing: 0
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: IslandState.timerText
                    color: root.done ? root.theme.tertiary : root.theme.fg
                    font.family: root.theme.fontClock
                    font.features: root.theme.clockFeatures
                    font.pixelSize: 30
                    font.weight: Font.Black
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.done
                        ? (IslandState.timerAlarming ? "ringing" : "done")
                        : (IslandState.timerRunning ? "running" : "paused")
                    color: root.done
                        ? Qt.alpha(root.theme.tertiary, 0.6 + 0.4 * root.donePulse)
                        : Qt.alpha(root.theme.muted, 0.9)
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(10)
                    font.weight: Font.DemiBold
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "of " + IslandState.timerFmt(IslandState.timerTotal)
            color: Qt.alpha(root.theme.muted, 0.75)
            font.family: root.theme.fontMono
            font.pixelSize: 11
        }

        // ── transport ─────────────────────────────────────────────
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8

            Rectangle {
                width: 104; height: 34
                radius: 17
                color: Qt.alpha(root.theme.tertiary, playHover.hovered ? 0.38 : 0.22)
                border.width: 1
                border.color: Qt.alpha(root.theme.tertiary, 0.5)
                Behavior on color { ColorAnimation { duration: 120 } }

                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: IslandState.timerRunning ? "\u{f03e4}" : "\u{f040a}"
                        color: root.theme.tertiary
                        font.family: root.theme.fontMono
                        font.pixelSize: 13
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        // A finished timer used to leave this button dead —
                        // toggle refuses to resume from zero. Repeating the
                        // length you just ran is the only thing it can mean.
                        text: root.done ? "Repeat"
                            : (IslandState.timerRunning ? "Pause" : "Start")
                        color: root.theme.tertiary
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(12)
                        font.weight: Font.DemiBold
                    }
                }
                HoverHandler { id: playHover; cursorShape: Qt.PointingHandCursor }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (root.done) IslandState.timerStart(IslandState.timerTotal);
                        else IslandState.timerToggle();
                    }
                }
            }

            Rectangle {
                width: 104; height: 34
                radius: 17
                color: Qt.alpha(root.theme.fg, resetHover.hovered ? 0.16 : 0.07)
                Behavior on color { ColorAnimation { duration: 120 } }

                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u{f0450}"
                        color: root.theme.muted
                        font.family: root.theme.fontMono
                        font.pixelSize: 13
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Reset"
                        color: root.theme.muted
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(12)
                        font.weight: Font.DemiBold
                    }
                }
                HoverHandler { id: resetHover; cursorShape: Qt.PointingHandCursor }
                MouseArea {
                    anchors.fill: parent
                    onClicked: IslandState.timerReset()
                }
            }
        }
    }
}
