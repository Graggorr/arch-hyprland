import QtQuick
import Quickshell
import Quickshell.Widgets

// Notification history, migrated from the old bell-pill popup into the island.
// The server, the list and the toast queue live in IslandState; this is a
// renderer, same as every other tool.
Item {
    id: root

    property var theme

    readonly property real preferredHeight: 364

    readonly property var list: IslandState.notifs

    // Spec: an action closes the notification unless it declared itself resident.
    // The raise is what actually takes you to the message — see NotifActions.
    function runAction(n, a) {
        a.invoke();
        NotifActions.focusApp(n);
        if (!n.resident) NotifActions.discard(n);
        IslandState.closeCard();
    }

    // Clicking a row means "take me to this", so it raises the app even when the
    // notification shipped no default action to invoke.
    function activate(n) {
        const a = NotifActions.defaultAction(n);
        if (a) { root.runAction(n, a); return; }
        NotifActions.focusApp(n);
        NotifActions.discard(n);
        IslandState.closeCard();
    }

    Column {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 10

        Item {
            width: parent.width
            height: 24

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Notifications"
                color: root.theme.fg
                font.family: root.theme.fontDisplay
                font.pixelSize: IslandState.ts(16)
                font.weight: Font.Bold
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                // DND lives in the control centre, but the bell pill's
                // right-click used to be the fast path to it — this button is
                // that path's new home.
                Rectangle {
                    width: dndTxt.implicitWidth + 18
                    height: 22
                    radius: 7
                    color: IslandState.dnd ? Qt.alpha(root.theme.warn, 0.30)
                         : (dh.hovered ? Qt.alpha(root.theme.fg, 0.12)
                                       : Qt.alpha(root.theme.fg, 0.08))
                    Behavior on color { ColorAnimation { duration: 110 } }

                    Text {
                        id: dndTxt
                        anchors.centerIn: parent
                        text: IslandState.dnd ? "\u{f009b} DND on" : "\u{f009b} DND"
                        color: IslandState.dnd ? root.theme.warn : root.theme.fg
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(10)
                    }

                    HoverHandler { id: dh }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: IslandState.dnd = !IslandState.dnd
                    }
                }

                Rectangle {
                    visible: root.list.length > 0
                    width: clr.implicitWidth + 18
                    height: 22
                    radius: 7
                    color: ch.hovered ? Qt.alpha(root.theme.warn, 0.28)
                                      : Qt.alpha(root.theme.fg, 0.08)
                    Behavior on color { ColorAnimation { duration: 110 } }

                    Text {
                        id: clr
                        anchors.centerIn: parent
                        text: "Clear all"
                        color: root.theme.fg
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(10)
                    }

                    HoverHandler { id: ch }
                    MouseArea { anchors.fill: parent; onClicked: IslandState.notifsClear() }
                }
            }
        }

        Item {
            visible: root.list.length === 0
            width: parent.width
            height: 260
            EmptyState {
                anchors.centerIn: parent
                theme: root.theme
                glyph: IslandState.dnd ? "\u{f009b}" : "\u{f009a}"
                title: "All caught up"
                sub: "Nothing new since " + IslandState.clockHours(IslandState.quietSince) + ":"
                     + ("0" + IslandState.quietSince.getMinutes()).slice(-2)
            }
        }

        ListView {
            id: notifList
            width: parent.width
            height: parent.height - 34
            model: root.list
            clip: true
            spacing: 6
            visible: root.list.length > 0
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar { flick: notifList; theme: root.theme }

            delegate: Rectangle {
                id: row
                required property var modelData
                // The action Repeater below rebinds `modelData` to its own
                // NotificationAction, so handlers need this stable handle.
                readonly property var notif: modelData
                width: ListView.view.width
                height: body.implicitHeight + 20
                radius: 11
                color: nh.hovered ? Qt.alpha(root.theme.fg, 0.08)
                                  : Qt.alpha(root.theme.fg, 0.04)
                Behavior on color { ColorAnimation { duration: 110 } }

                Row {
                    id: body
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 10

                    IconImage {
                        width: 26; height: 26
                        anchors.verticalCenter: parent.verticalCenter
                        source: modelData.image !== "" ? modelData.image
                              : Quickshell.iconPath(modelData.appIcon, "dialog-information")
                        asynchronous: true
                    }

                    Column {
                        width: parent.width - 46
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        // Summary and age share a line: the age is the shorter,
                        // fixed half, so the summary elides against it rather
                        // than the two competing for the row.
                        Item {
                            width: parent.width
                            height: sumTxt.implicitHeight

                            Text {
                                id: sumTxt
                                anchors.left: parent.left
                                anchors.right: ageTxt.left
                                anchors.rightMargin: 8
                                text: modelData.summary
                                color: root.theme.fg
                                font.family: root.theme.fontSans
                                font.pixelSize: IslandState.ts(11)
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            Text {
                                id: ageTxt
                                anchors.right: parent.right
                                anchors.baseline: sumTxt.baseline
                                text: IslandState.notifAge(row.notif)
                                visible: text !== ""
                                // The hover close button lands exactly here, so
                                // the age steps aside for it. Hidden rather than
                                // unsized: the summary is anchored to this edge
                                // and would jump if the width went to zero.
                                opacity: nh.hovered ? 0 : 1
                                Behavior on opacity { NumberAnimation { duration: 110 } }
                                color: Qt.alpha(root.theme.muted, 0.85)
                                font.family: root.theme.fontMono
                                font.pixelSize: 9
                            }
                        }
                        Text {
                            width: parent.width
                            text: modelData.body
                            visible: text !== ""
                            color: Qt.alpha(root.theme.fg, 0.72)
                            font.family: root.theme.fontSans
                            font.pixelSize: IslandState.ts(10)
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            textFormat: Text.StyledText
                        }

                        Row {
                            spacing: 6
                            visible: modelData.actions.length > 0
                            topPadding: 4

                            Repeater {
                                model: modelData.actions

                                Rectangle {
                                    id: hact
                                    required property var modelData
                                    width: hTxt.implicitWidth + 18
                                    height: 22
                                    radius: 7
                                    color: hh.hovered ? Qt.alpha(root.theme.accent, 0.28)
                                                      : Qt.alpha(root.theme.fg, 0.08)
                                    Behavior on color { ColorAnimation { duration: 110 } }

                                    Text {
                                        id: hTxt
                                        anchors.centerIn: parent
                                        text: hact.modelData.text
                                        color: root.theme.fg
                                        font.family: root.theme.fontSans
                                        font.pixelSize: IslandState.ts(10)
                                    }

                                    HoverHandler { id: hh }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: root.runAction(row.notif, hact.modelData)
                                    }
                                }
                            }
                        }
                    }
                }

                // Hover-only, overlaying the row's right edge — the text
                // column is already sized against the full width.
                Rectangle {
                    anchors { right: parent.right; top: parent.top; rightMargin: 6; topMargin: 6 }
                    visible: nh.hovered
                    width: 18
                    height: 18
                    radius: 9
                    color: nx.hovered ? Qt.alpha(root.theme.warn, 0.35)
                                      : Qt.rgba(root.theme.bg.r, root.theme.bg.g, root.theme.bg.b, 0.92)
                    border.width: 1
                    border.color: Qt.alpha(root.theme.fg, 0.18)
                    Behavior on color { ColorAnimation { duration: 110 } }

                    Text {
                        anchors.centerIn: parent
                        text: "×"
                        color: root.theme.fg
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(13)
                    }

                    HoverHandler { id: nx }
                    MouseArea { anchors.fill: parent; onClicked: NotifActions.discard(row.notif) }
                }

                HoverHandler { id: nh }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    z: -1
                    onClicked: (m) => {
                        if (m.button === Qt.MiddleButton) NotifActions.discard(row.notif);
                        else root.activate(row.notif);
                    }
                }
            }
        }
    }
}
