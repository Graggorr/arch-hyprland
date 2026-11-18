import QtQuick

// Settings → Pill → Layout. A mock of the pill to arrange, a tray below it
// for the pieces taken off, and a caption line that names whatever is under
// the pointer. Drag a piece along the pill to move it (a bar marks where it
// lands), drag it into the tray to hide it, drag it back to show it. Clicking
// a piece selects it and offers the same moves as buttons, for when dragging
// is fiddly. Every change goes through IslandState and lands in the active
// profile's pillLayout / pillHidden.
Item {
    id: root

    property var theme

    implicitHeight: col.implicitHeight

    readonly property var order: IslandState.pillOrder
    readonly property var hidden: IslandState.pillHiddenList

    property string hoverId: ""
    property string selId: ""
    // Drag state: what is carried, and where it would land.
    property string dragId: ""
    property string dropZone: ""   // "pill" | "tray" | ""
    property int dropIndex: -1

    readonly property string focusId: dragId !== "" ? dragId : hoverId !== "" ? hoverId : selId
    readonly property bool selHidden: hidden.indexOf(selId) >= 0

    // The selection outlives a move but not a reset that drops it.
    onOrderChanged: if (selId !== "" && order.indexOf(selId) < 0 && hidden.indexOf(selId) < 0) selId = ""

    property string now: ""
    function tick() {
        const d = new Date();
        root.now = IslandState.clockHours(d) + ":" + ("0" + d.getMinutes()).slice(-2);
    }
    Timer { interval: 15000; running: root.visible; repeat: true; triggeredOnStart: true; onTriggered: root.tick() }

    // ── dragging ──────────────────────────────────────────────────
    function startDrag(id, fromItem, mx, my) {
        const p = fromItem.mapToItem(root, 0, 0);
        ghost.x = p.x;
        ghost.y = p.y;
        ghost.width = fromItem.width;
        ghost.grabX = mx;
        ghost.grabY = my;
        root.dragId = id;
        root.selId = "";
    }
    function moveDrag(fromItem, mx, my) {
        const p = fromItem.mapToItem(root, mx, my);
        ghost.x = p.x - ghost.grabX;
        ghost.y = p.y - ghost.grabY;
        const cx = p.x, cy = p.y;
        const st = stage.mapToItem(root, 0, 0);
        const tr = tray.mapToItem(root, 0, 0);
        if (cy >= st.y && cy <= st.y + stage.height) {
            root.dropZone = "pill";
            // Count the pieces (not the carried one) whose centre is left of
            // the pointer: that is the slot it would take.
            let idx = 0;
            for (let i = 0; i < pieces.count; i++) {
                const it = pieces.itemAt(i);
                if (!it || it.pid === root.dragId) continue;
                const c = it.mapToItem(root, it.width / 2, 0).x;
                if (c < cx) idx++;
            }
            root.dropIndex = idx;
        } else if (cy >= tr.y - 8 && cy <= tr.y + tray.height + 8 && root.dragId !== "clock") {
            root.dropZone = "tray";
            root.dropIndex = -1;
        } else {
            root.dropZone = "";
            root.dropIndex = -1;
        }
    }
    function endDrag() {
        const id = root.dragId;
        if (root.dropZone === "pill" && root.dropIndex >= 0) IslandState.placePillUnit(id, root.dropIndex);
        else if (root.dropZone === "tray") IslandState.hidePillUnit(id);
        root.dragId = "";
        root.dropZone = "";
        root.dropIndex = -1;
    }
    // Where the landing bar goes: in the gap before the dropIndex-th piece
    // that is not the carried one, in pillRow coordinates.
    function markerX() {
        let k = 0, lastRight = 0;
        for (let i = 0; i < pieces.count; i++) {
            const it = pieces.itemAt(i);
            if (!it || it.pid === root.dragId) continue;
            if (k === root.dropIndex) return it.x - pillRow.spacing / 2;
            lastRight = it.x + it.width;
            k++;
        }
        return lastRight + pillRow.spacing / 2;
    }

    Column {
        id: col
        width: parent.width
        spacing: 10

        // ── header ────────────────────────────────────────────────
        Item {
            width: parent.width
            height: 34
            Column {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                    text: "Layout"
                    color: root.theme.fg
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(12)
                    font.weight: Font.DemiBold
                }
                Text {
                    text: "What sits on the pill, and in which order"
                    color: Qt.alpha(root.theme.on_surface_variant, 0.85)
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(10)
                }
            }
            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: resetRow.implicitWidth + 20
                height: 28; radius: 10
                color: resetHover.hovered ? Qt.alpha(root.theme.on_surface, 0.12)
                                          : Qt.alpha(root.theme.on_surface, 0.06)
                Behavior on color { ColorAnimation { duration: 120 } }
                Row {
                    id: resetRow
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u{f099b}"
                        color: root.theme.on_surface
                        font.family: root.theme.fontMono
                        font.pixelSize: 13
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Reset"
                        color: root.theme.on_surface
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(11)
                    }
                }
                HoverHandler { id: resetHover; cursorShape: Qt.PointingHandCursor }
                MouseArea { anchors.fill: parent; onClicked: { root.selId = ""; IslandState.resetPill(); } }
            }
        }

        // ── the stage: a mock pill to arrange ─────────────────────
        Rectangle {
            id: stage
            width: parent.width
            height: 84
            radius: 14
            color: Qt.alpha(root.theme.on_surface, 0.04)
            border.width: 1
            border.color: root.dropZone === "pill" ? Qt.alpha(root.theme.accent, 0.55)
                                                   : Qt.alpha(root.theme.outline, 0.18)
            Behavior on border.color { ColorAnimation { duration: 140 } }

            Rectangle {
                id: pillBody
                anchors.centerIn: parent
                // Up off the side labels along the stage's bottom edge.
                anchors.verticalCenterOffset: -8
                width: pillRow.implicitWidth + 20
                height: 46
                radius: height / 2
                color: Qt.rgba(0.02, 0.02, 0.02, 1)
                border.width: 1
                border.color: Qt.alpha(root.theme.outline, 0.35)
                Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                Row {
                    id: pillRow
                    anchors.centerIn: parent
                    spacing: 6

                    move: Transition { NumberAnimation { properties: "x"; duration: 220; easing.type: Easing.OutCubic } }

                    Repeater {
                        id: pieces
                        model: root.order

                        Rectangle {
                            id: piece
                            required property var modelData
                            required property int index
                            readonly property string pid: modelData
                            readonly property bool isClock: pid === "clock"
                            readonly property bool sel: root.selId === pid
                            readonly property bool carried: root.dragId === pid

                            width: isClock ? clockText.implicitWidth + 24 : 36
                            height: 34
                            radius: 11
                            opacity: carried ? 0.25 : 1
                            color: sel ? root.theme.secondary_container
                                 : isClock ? "transparent"
                                 : (pieceMouse.containsMouse ? Qt.alpha(root.theme.on_surface, 0.16)
                                                             : Qt.alpha(root.theme.on_surface, 0.08))
                            border.width: sel ? 0 : 1
                            border.color: isClock ? Qt.alpha(root.theme.outline, 0.3) : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                id: clockText
                                visible: piece.isClock
                                anchors.centerIn: parent
                                text: root.now
                                color: piece.sel ? root.theme.on_secondary_container : root.theme.fg
                                font.family: root.theme.fontClock || root.theme.fontMono
                                font.pixelSize: 17
                                font.weight: Font.DemiBold
                            }
                            Text {
                                visible: !piece.isClock
                                anchors.centerIn: parent
                                text: IslandState.pillUnit(piece.pid).glyph
                                color: piece.sel ? root.theme.on_secondary_container : root.theme.on_surface
                                font.family: root.theme.fontMono
                                font.pixelSize: 16
                            }

                            MouseArea {
                                id: pieceMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                preventStealing: true
                                cursorShape: piece.isClock ? Qt.PointingHandCursor
                                           : pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                property real px: 0
                                property real py: 0
                                property bool dragging: false
                                onContainsMouseChanged: root.hoverId = containsMouse ? piece.pid
                                                       : (root.hoverId === piece.pid ? "" : root.hoverId)
                                onPressed: (m) => { px = m.x; py = m.y; dragging = false; }
                                onPositionChanged: (m) => {
                                    if (!pressed) return;
                                    if (!dragging && Math.hypot(m.x - px, m.y - py) > 5) {
                                        dragging = true;
                                        root.startDrag(piece.pid, piece, px, py);
                                    }
                                    if (dragging) root.moveDrag(piece, m.x, m.y);
                                }
                                onReleased: {
                                    if (dragging) { dragging = false; root.endDrag(); }
                                    else root.selId = root.selId === piece.pid ? "" : piece.pid;
                                }
                                onCanceled: if (dragging) { dragging = false; root.dragId = ""; root.dropZone = ""; }
                            }
                        }
                    }
                }

                // Where the carried piece would land.
                Rectangle {
                    visible: root.dropZone === "pill" && root.dropIndex >= 0
                    x: pillRow.x + root.markerX() - width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 3; height: 30; radius: 1.5
                    color: root.theme.accent
                }
            }

            Text {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: 8
                text: "\u{f0141} left of the clock"
                color: Qt.alpha(root.theme.on_surface_variant, 0.5)
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(9)
            }
            Text {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 8
                text: "right of the clock \u{f0142}"
                color: Qt.alpha(root.theme.on_surface_variant, 0.5)
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(9)
            }
        }

        // ── caption: names what is under the pointer, or the selection ──
        Item {
            width: parent.width
            height: 32

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.right: actions.visible ? actions.left : parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.focusId !== ""
                    text: root.focusId !== "" ? IslandState.pillUnit(root.focusId).glyph : ""
                    color: root.theme.accent
                    font.family: root.theme.fontMono
                    font.pixelSize: 14
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 30
                    elide: Text.ElideRight
                    textFormat: Text.StyledText
                    text: {
                        if (root.dragId !== "")
                            return "<b>" + IslandState.pillName(root.dragId) + "</b> — "
                                + (root.dropZone === "pill" ? "drop to place it here"
                                   : root.dropZone === "tray" ? "drop to take it off the pill"
                                   : root.dragId === "clock" ? "the clock can only move along the pill"
                                   : "drop on the pill or in the tray below");
                        if (root.focusId !== "") {
                            const u = IslandState.pillUnit(root.focusId);
                            return "<b>" + u.name + "</b> — " + u.hint;
                        }
                        return "Drag a piece to move it · drop it below to hide it · click one for buttons";
                    }
                    color: root.focusId !== "" ? root.theme.fg : Qt.alpha(root.theme.on_surface_variant, 0.8)
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(11)
                }
            }

            // Buttons for the selected piece.
            Row {
                id: actions
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                visible: root.selId !== "" && root.dragId === ""

                readonly property int at: root.order.indexOf(root.selId)
                readonly property var buttons: root.selHidden
                    ? [{ id: "add", glyph: "\u{f0415}", label: "Add to pill", on: true }]
                    : [{ id: "left", glyph: "\u{f0141}", label: "", on: at > 0 },
                       { id: "right", glyph: "\u{f0142}", label: "", on: at >= 0 && at < root.order.length - 1 }]
                      .concat(root.selId === "clock" ? []
                              : [{ id: "hide", glyph: "\u{f0209}", label: "Hide", on: true }])

                Repeater {
                    model: actions.buttons
                    Rectangle {
                        required property var modelData
                        width: btnRow.implicitWidth + (modelData.label !== "" ? 20 : 16)
                        height: 28; radius: 10
                        opacity: modelData.on ? 1 : 0.35
                        color: btnHover.hovered && modelData.on ? Qt.alpha(root.theme.on_surface, 0.14)
                                                                : Qt.alpha(root.theme.on_surface, 0.07)
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Row {
                            id: btnRow
                            anchors.centerIn: parent
                            spacing: 5
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: parent.parent.modelData.glyph
                                color: root.theme.on_surface
                                font.family: root.theme.fontMono
                                font.pixelSize: 14
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: text !== ""
                                text: parent.parent.modelData.label
                                color: root.theme.on_surface
                                font.family: root.theme.fontSans
                                font.pixelSize: IslandState.ts(11)
                            }
                        }
                        HoverHandler { id: btnHover; cursorShape: parent.modelData.on ? Qt.PointingHandCursor : Qt.ArrowCursor }
                        MouseArea {
                            anchors.fill: parent
                            enabled: parent.modelData.on
                            onClicked: {
                                const id = root.selId, at = actions.at;
                                switch (parent.modelData.id) {
                                case "left":  IslandState.placePillUnit(id, at - 1); break;
                                case "right": IslandState.placePillUnit(id, at + 1); break;
                                case "hide":  IslandState.hidePillUnit(id); break;
                                case "add":
                                    // Next to the clock, on its right: the
                                    // spot easiest to find again.
                                    IslandState.placePillUnit(id, root.order.indexOf("clock") + 1);
                                    break;
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── the tray: pieces taken off the pill ───────────────────
        Rectangle {
            id: tray
            width: parent.width
            height: Math.max(52, trayFlow.implicitHeight + 34)
            radius: 14
            color: root.dropZone === "tray" ? Qt.alpha(root.theme.accent, 0.10) : "transparent"
            border.width: 1
            border.color: root.dropZone === "tray" ? Qt.alpha(root.theme.accent, 0.55)
                                                   : Qt.alpha(root.theme.outline, 0.25)
            Behavior on color { ColorAnimation { duration: 140 } }
            Behavior on border.color { ColorAnimation { duration: 140 } }

            Text {
                x: 12; y: 8
                text: "\u{f0209}  Off the pill"
                color: Qt.alpha(root.theme.on_surface_variant, 0.75)
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(10)
                font.weight: Font.DemiBold
            }

            Text {
                visible: root.hidden.length === 0
                x: 12; y: 26
                text: "Nothing hidden — drag a piece here to take it off the pill"
                color: Qt.alpha(root.theme.on_surface_variant, 0.5)
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(10)
            }

            Flow {
                id: trayFlow
                x: 10; y: 26
                width: parent.width - 20
                spacing: 6

                Repeater {
                    model: root.hidden

                    Rectangle {
                        id: chip
                        required property var modelData
                        readonly property string pid: modelData
                        readonly property bool sel: root.selId === pid
                        width: chipRow.implicitWidth + 20
                        height: 30; radius: 10
                        opacity: root.dragId === pid ? 0.25 : 1
                        color: sel ? root.theme.secondary_container
                             : (chipMouse.containsMouse ? Qt.alpha(root.theme.on_surface, 0.14)
                                                        : Qt.alpha(root.theme.on_surface, 0.06))
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Row {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: IslandState.pillUnit(chip.pid).glyph
                                color: chip.sel ? root.theme.on_secondary_container : Qt.alpha(root.theme.on_surface, 0.7)
                                font.family: root.theme.fontMono
                                font.pixelSize: 14
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: IslandState.pillName(chip.pid)
                                color: chip.sel ? root.theme.on_secondary_container : Qt.alpha(root.theme.on_surface, 0.7)
                                font.family: root.theme.fontSans
                                font.pixelSize: IslandState.ts(11)
                            }
                        }
                        MouseArea {
                            id: chipMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            preventStealing: true
                            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                            property real px: 0
                            property real py: 0
                            property bool dragging: false
                            onContainsMouseChanged: root.hoverId = containsMouse ? chip.pid
                                                   : (root.hoverId === chip.pid ? "" : root.hoverId)
                            onPressed: (m) => { px = m.x; py = m.y; dragging = false; }
                            onPositionChanged: (m) => {
                                if (!pressed) return;
                                if (!dragging && Math.hypot(m.x - px, m.y - py) > 5) {
                                    dragging = true;
                                    root.startDrag(chip.pid, chip, px, py);
                                }
                                if (dragging) root.moveDrag(chip, m.x, m.y);
                            }
                            onReleased: {
                                if (dragging) { dragging = false; root.endDrag(); }
                                else root.selId = root.selId === chip.pid ? "" : chip.pid;
                            }
                            onCanceled: if (dragging) { dragging = false; root.dragId = ""; root.dropZone = ""; }
                        }
                    }
                }
            }
        }
    }

    // ── the carried piece ─────────────────────────────────────────
    Rectangle {
        id: ghost
        property real grabX: 0
        property real grabY: 0
        visible: root.dragId !== ""
        z: 100
        height: 34
        radius: 11
        color: root.theme.secondary_container
        border.width: 1
        border.color: Qt.alpha(root.theme.accent, 0.7)
        Row {
            anchors.centerIn: parent
            spacing: 6
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.dragId === "clock" ? root.now
                    : root.dragId !== "" ? IslandState.pillUnit(root.dragId).glyph : ""
                color: root.theme.on_secondary_container
                font.family: root.theme.fontMono
                font.pixelSize: root.dragId === "clock" ? 15 : 16
            }
        }
    }
}
