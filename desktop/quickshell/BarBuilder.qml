import QtQuick

// Settings → General → Bar layout. The menu bar's twin of PillBuilder: a
// mock of the bar with the island as a fixed block in the middle, a tray below
// for the items taken off, and a caption naming what is under the pointer.
// Drag an item along the bar to move it — left of the island is the bar's
// left side, right of it the right side — into the tray to hide it, back out
// to show it. Clicking one selects it and offers the same moves as buttons.
// Every change lands in barLayout / barHidden through IslandState.
Item {
    id: root

    property var theme

    implicitHeight: col.implicitHeight

    readonly property var order: IslandState.barOrder
    readonly property var hidden: IslandState.barHiddenList

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
        ghost.width = Math.min(fromItem.width, 120);
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
            root.dropZone = "bar";
            // Carried to an edge of a bar that overflows: scroll it along.
            const fx = cx - pillFlick.mapToItem(root, 0, 0).x;
            const maxX = Math.max(0, pillFlick.contentWidth - pillFlick.width);
            if (fx < 36) pillFlick.contentX = Math.max(0, pillFlick.contentX - 10);
            else if (fx > pillFlick.width - 36) pillFlick.contentX = Math.min(maxX, pillFlick.contentX + 10);
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
        } else if (cy >= tr.y - 8 && cy <= tr.y + tray.height + 8 && root.dragId !== "notch") {
            root.dropZone = "tray";
            root.dropIndex = -1;
        } else {
            root.dropZone = "";
            root.dropIndex = -1;
        }
    }
    function endDrag() {
        const id = root.dragId;
        if (root.dropZone === "bar" && root.dropIndex >= 0) IslandState.placeBarUnit(id, root.dropIndex);
        else if (root.dropZone === "tray") IslandState.hideBarUnit(id);
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
                    text: "Bar layout"
                    color: root.theme.fg
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(12)
                    font.weight: Font.DemiBold
                }
                Text {
                    text: "What sits on the menu bar, and on which side of the island"
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
                MouseArea { anchors.fill: parent; onClicked: { root.selId = ""; IslandState.resetBar(); } }
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
            border.color: root.dropZone === "bar" ? Qt.alpha(root.theme.accent, 0.55)
                                                   : Qt.alpha(root.theme.outline, 0.18)
            Behavior on border.color { ColorAnimation { duration: 140 } }

            Rectangle {
                id: pillBody
                anchors.centerIn: parent
                // Up off the side labels along the stage's bottom edge.
                anchors.verticalCenterOffset: -8
                width: parent.width - 16
                height: 42
                radius: 10
                color: Qt.rgba(root.theme.islandBg.r, root.theme.islandBg.g, root.theme.islandBg.b, 0.55)
                border.width: 1
                border.color: Qt.alpha(root.theme.outline, 0.35)
                Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                // Item chips keep one readable size; when they do not all fit
                // the bar scrolls sideways (wheel, drag on empty space, or the
                // carried chip nearing an edge) instead of shrinking them —
                // shrinking to fit made every chip tiny once the bar had
                // twenty-odd items. The island takes whatever room is left,
                // which pushes the right side to the bar's right end.
                readonly property int sideCount: Math.max(1, root.order.length - 1)
                readonly property real pieceW: 32
                readonly property real sidesW: sideCount * (pieceW + pillRow.spacing)
                // Too many items for the bar: the arrows take a lane of their
                // own at each end and the chips scroll between them, so an
                // arrow never sits on top of a chip.
                readonly property real arrowLane: 30
                readonly property bool overflow: sidesW + 80 + 12 > width
                Flickable {
                    id: pillFlick
                    anchors.fill: parent
                    anchors.leftMargin: pillBody.overflow ? pillBody.arrowLane : 0
                    anchors.rightMargin: pillBody.overflow ? pillBody.arrowLane : 0
                    contentWidth: pillRow.width + 12
                    contentHeight: height
                    flickableDirection: Flickable.HorizontalFlick
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: contentWidth > width + 1
                    clip: true
                    readonly property real maxX: Math.max(0, contentWidth - width)
                    readonly property bool canLeft: interactive && contentX > 1
                    readonly property bool canRight: interactive && contentX < maxX - 1
                    function scrollBy(dx, animate) {
                        const to = Math.max(0, Math.min(maxX, (scrollAnim.running ? scrollAnim.to : contentX) + dx));
                        if (!animate) { scrollAnim.stop(); contentX = to; return; }
                        scrollAnim.to = to;
                        scrollAnim.restart();
                    }
                    NumberAnimation {
                        id: scrollAnim
                        target: pillFlick
                        property: "contentX"
                        duration: 240
                        easing.type: Easing.OutCubic
                    }
                Row {
                    id: pillRow
                    x: 6
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3

                    move: Transition { NumberAnimation { properties: "x"; duration: 220; easing.type: Easing.OutCubic } }

                    Repeater {
                        id: pieces
                        model: root.order

                        Rectangle {
                            id: piece
                            required property var modelData
                            required property int index
                            readonly property string pid: modelData
                            readonly property bool isNotch: pid === "notch"
                            readonly property bool sel: root.selId === pid
                            readonly property bool carried: root.dragId === pid

                            width: isNotch ? (pillBody.overflow ? 80 : pillBody.width - 12 - pillBody.sidesW) : pillBody.pieceW
                            height: isNotch ? 34 : 30
                            radius: isNotch ? 12 : 9
                            opacity: carried ? 0.25 : 1
                            color: sel ? root.theme.secondary_container
                                 : isNotch ? "transparent"
                                 : (pieceMouse.containsMouse ? Qt.alpha(root.theme.on_surface, 0.16)
                                                             : Qt.alpha(root.theme.on_surface, 0.08))
                            border.width: sel ? 0 : 1
                            border.color: isNotch ? Qt.alpha(root.theme.outline, 0.3) : "transparent"

                            // The island itself, centred in its stretch.
                            Rectangle {
                                visible: piece.isNotch
                                anchors.centerIn: parent
                                width: Math.min(120, parent.width - 10); height: parent.height - 6
                                radius: IslandState.notch ? 10 : height / 2
                                color: Qt.rgba(0.02, 0.02, 0.02, 1)
                            }
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                id: clockText
                                visible: piece.isNotch
                                anchors.centerIn: parent
                                text: IslandState.notch ? "notch" : "island"
                                color: Qt.alpha(root.theme.fg, 0.6)
                                font.family: root.theme.fontSans
                                font.pixelSize: IslandState.ts(11)
                            }
                            Text {
                                visible: !piece.isNotch
                                anchors.centerIn: parent
                                text: IslandState.barUnit(piece.pid).glyph
                                color: piece.sel ? root.theme.on_secondary_container : root.theme.on_surface
                                font.family: root.theme.fontMono
                                font.pixelSize: Math.min(16, Math.round(pillBody.pieceW * 0.5))
                            }

                            MouseArea {
                                id: pieceMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                preventStealing: true
                                cursorShape: piece.isNotch ? Qt.PointingHandCursor
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
                    visible: root.dropZone === "bar" && root.dropIndex >= 0
                    x: pillRow.x + root.markerX() - width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 3; height: 30; radius: 1.5
                    color: root.theme.accent
                }
                }

                // The wheel anywhere over the bar scrolls it, chips included
                // (a vertical wheel scrolls sideways; a tilt wheel too).
                WheelHandler {
                    target: null
                    enabled: pillFlick.interactive
                    onWheel: (e) => {
                        const d = Math.abs(e.angleDelta.x) > Math.abs(e.angleDelta.y) ? e.angleDelta.x : e.angleDelta.y;
                        pillFlick.scrollBy(-d * 0.6, false);
                        e.accepted = true;
                    }
                }

                // Arrows in their own lanes at the ends, there only while the
                // bar overflows; dimmed at the end it cannot scroll past.
                // A click moves the bar by most of its width.
                Repeater {
                    model: pillBody.overflow ? [ { dir: -1, glyph: "\u{f0141}" }, { dir: 1, glyph: "\u{f0142}" } ] : []
                    Rectangle {
                        id: arrow
                        required property var modelData
                        readonly property bool isLeft: !modelData || modelData.dir < 0
                        readonly property bool can: isLeft ? pillFlick.canLeft : pillFlick.canRight
                        anchors.verticalCenter: parent.verticalCenter
                        x: isLeft ? 4 : parent.width - width - 4
                        width: pillBody.arrowLane - 6
                        height: 30
                        radius: 9
                        opacity: can ? 1 : 0.35
                        color: can && arrowHov.hovered ? root.theme.secondary_container : Qt.alpha(root.theme.on_surface, 0.08)
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on opacity { NumberAnimation { duration: 140 } }
                        Text {
                            anchors.centerIn: parent
                            text: arrow.modelData ? arrow.modelData.glyph : ""
                            color: arrow.can && arrowHov.hovered ? root.theme.on_secondary_container : root.theme.on_surface
                            font.family: root.theme.fontMono
                            font.pixelSize: 16
                        }
                        HoverHandler { id: arrowHov; cursorShape: arrow.can ? Qt.PointingHandCursor : Qt.ArrowCursor }
                        TapHandler {
                            enabled: arrow.can
                            onTapped: pillFlick.scrollBy(arrow.modelData.dir * pillFlick.width * 0.7, true)
                        }
                    }
                }
            }

            Text {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: 8
                text: "\u{f0141} left side"
                color: Qt.alpha(root.theme.on_surface_variant, 0.5)
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(9)
            }
            Text {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 8
                text: "right side \u{f0142}"
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
                    text: root.focusId !== "" ? IslandState.barUnit(root.focusId).glyph : ""
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
                            return "<b>" + IslandState.barName(root.dragId) + "</b> — "
                                + (root.dropZone === "bar" ? "drop to place it here"
                                   : root.dropZone === "tray" ? "drop to take it off the bar"
                                   : root.dragId === "notch" ? "the island always stays on the bar"
                                   : "drop on the bar or in the tray below");
                        if (root.focusId !== "") {
                            const u = IslandState.barUnit(root.focusId);
                            return "<b>" + u.name + "</b> — " + u.hint;
                        }
                        return "Drag an item along the bar to move it · drop it below to hide it · click one for buttons";
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
                    ? [{ id: "add", glyph: "\u{f0415}", label: "Add to bar", on: true }]
                    : [{ id: "left", glyph: "\u{f0141}", label: "", on: at > 0 },
                       { id: "right", glyph: "\u{f0142}", label: "", on: at >= 0 && at < root.order.length - 1 }]
                      .concat(root.selId === "notch" ? []
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
                                case "left":  IslandState.placeBarUnit(id, at - 1); break;
                                case "right": IslandState.placeBarUnit(id, at + 1); break;
                                case "hide":  IslandState.hideBarUnit(id); break;
                                case "add":
                                    // Next to the clock, on its right: the
                                    // spot easiest to find again.
                                    IslandState.placeBarUnit(id, root.order.indexOf("notch") + 1);
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
                text: "\u{f0209}  Off the bar"
                color: Qt.alpha(root.theme.on_surface_variant, 0.75)
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(10)
                font.weight: Font.DemiBold
            }

            Text {
                visible: root.hidden.length === 0
                x: 12; y: 26
                text: "Nothing hidden — drag an item here to take it off the bar"
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
                                text: IslandState.barUnit(chip.pid).glyph
                                color: chip.sel ? root.theme.on_secondary_container : Qt.alpha(root.theme.on_surface, 0.7)
                                font.family: root.theme.fontMono
                                font.pixelSize: 14
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: IslandState.barName(chip.pid)
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
                text: root.dragId === "notch" ? "island"
                    : root.dragId !== "" ? IslandState.barUnit(root.dragId).glyph : ""
                color: root.theme.on_secondary_container
                font.family: root.theme.fontMono
                font.pixelSize: 16
            }
        }
    }
}
