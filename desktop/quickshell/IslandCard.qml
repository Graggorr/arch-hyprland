import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland

// The expanded surface: the control-center card, with every drill-in panel
// stacked ON TOP of it as its own smaller sheet — the reference's layering,
// where opening Bluetooth floats a panel over the grid rather than replacing
// it. The hub dims underneath while a panel is up, and clicking the dimmed
// grid (or the panel's back chevron) puts the panel away; Esc closes the card.
//
// The frame speaks Material 3, in the same dialect the GTK sheets give the
// file managers: surface_container glass, secondary_container for the
// selected destination, on_surface_variant for resting chrome. Since
// 2026-08-31 the island follows the wallpaper palette like every other
// surface (see shell.qml), so these roles are what actually keeps the card
// on-theme.
PopupWindow {
    id: root

    property var theme
    property string screenName: ""
    property bool shown: false

    // Pinned means "stay while I work": the focus grab is released, so the
    // card survives clicks elsewhere until it is closed from the header or
    // the pill. Reset on every open — a pin is a decision about this look at
    // the card, not a mode the shell remembers.
    property bool pinned: false

    // The hub header's clock. The island owns the flight that carries the
    // pill's clock here; until it lands, clockLanded keeps this copy hidden
    // so only one clock is ever on screen. clockPos() is where the flyer
    // has to end up, in this window's coordinates.
    readonly property int clockPx: 24
    readonly property string clockText: IslandState.clockHours(hdrClk.date)
        + ":" + ("0" + hdrClk.date.getMinutes()).slice(-2)
        + (IslandState.cfg.clock24h ? "" : (hdrClk.date.getHours() < 12 ? " AM" : " PM"))
    property bool clockLanded: true
    property real dateIn: root.clockLanded && root.openHere ? 1 : 0
    Behavior on dateIn { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    function clockPos() { return hdrClock.mapToItem(null, 0, 0); }

    signal composeRequested(string iso)

    // The width is static on purpose: the card is centred under the pill, so
    // a per-tool width would re-centre it on every switch. Height is static
    // for the same reason the rail era made it so: a surface that grows with
    // every list would keep pushing down the screen. Both are the user's
    // numbers, edited live from the settings window; content scrolls inside.
    // A face tool may name its own height in the registry: the theme carousel
    // is one row and would otherwise float in a card sized for lists.
    readonly property real toolWidth: IslandState.cfg.cardWidth
    readonly property real toolHeight: root.faceInfo && root.faceInfo.height
                                       ? root.faceInfo.height : IslandState.cfg.cardHeight
    readonly property real headerHeight: 44
    readonly property real viewHeight: toolHeight - headerHeight

    // Room around the card for its drop shadow. Asymmetric on purpose: the
    // shadow is cast downward, and padding the top by the same amount would
    // slide the popup surface up over the pill and steal its hover.
    readonly property real padSide: 28
    // The notch's card is welded to the screen edge, so it gets no top pad:
    // a popup reaching above the screen would be slid back down by the
    // compositor and come loose from the edge.
    readonly property real padTop: IslandState.notch ? 0 : 8
    readonly property real padBottom: 40

    implicitWidth: padSide * 2 + toolWidth
    implicitHeight: padTop + toolHeight + padBottom

    color: "transparent"

    // The pill this card grows out of. The card starts as a capsule of the
    // pill's own size hanging under it, stretches sideways, then drops to full
    // height before its contents fade up — and on close it shrinks back into
    // that capsule before the surface goes away, which is why the window
    // lingers past cardOpen.
    property real pillWidth: 200
    property real pillHeight: 46
    // suppressed: the desktop island's card stays shut while the session is
    // locked — the lock surface's own island opens it instead.
    // inSurface: the lock surface is not a window a popup can hang off, so
    // there the card and its sheet are drawn inside the island's surface,
    // in surfaceHost, and this window never maps.
    property bool suppressed: false
    property bool inSurface: false
    property Item surfaceHost: null
    readonly property bool openHere: !root.suppressed && IslandState.cardOpen && IslandState.toolScreen === root.screenName
    readonly property bool live: root.openHere || root.lingering
    onLiveChanged: if (root.inSurface) root.mapped(root.live)
    property bool lingering: false
    property real gw: 0
    property real gh: 0
    property real bodyIn: 0
    property bool settled: false
    property bool surfaceUp: false
    Timer { id: surfaceTimer; interval: 50; onTriggered: root.surfaceUp = true }
    visible: !root.inSurface && (root.openHere || root.lingering)

    readonly property int morphMs: IslandState.cfg.morph ? IslandState.cfg.morphMs : 1

    onOpenHereChanged: {
        if (root.openHere) {
            root.lingering = false;
            closeMorph.stop();
            openMorph.restart();
            root.onOpened();
        } else {
            openMorph.stop();
            root.settled = false;
            armGrab.stop();
            grab.active = false;
            root.bodyIn = 0;
            root.lingering = true;
            closeMorph.restart();
        }
    }

    ParallelAnimation {
        id: openMorph
        onStarted: root.settled = false
        onFinished: root.settled = true
        NumberAnimation {
            target: root; property: "gw"; to: 1
            duration: root.morphMs * 0.7; easing.type: Easing.OutCubic
        }
        SequentialAnimation {
            PauseAnimation { duration: root.morphMs * 0.15 }
            NumberAnimation {
                target: root; property: "gh"; to: 1
                duration: root.morphMs * 0.85; easing.type: Easing.OutBack; easing.overshoot: 0.9
            }
        }
        SequentialAnimation {
            PauseAnimation { duration: root.morphMs * 0.55 }
            NumberAnimation {
                target: root; property: "bodyIn"; to: 1
                duration: IslandState.cfg.morph ? 200 : 1; easing.type: Easing.OutCubic
            }
        }
    }

    ParallelAnimation {
        id: closeMorph
        onFinished: root.lingering = false
        NumberAnimation {
            target: root; property: "gh"; to: 0
            duration: IslandState.cfg.morph ? 170 : 1; easing.type: Easing.InCubic
        }
        SequentialAnimation {
            PauseAnimation { duration: IslandState.cfg.morph ? 50 : 0 }
            NumberAnimation {
                target: root; property: "gw"; to: 0
                duration: IslandState.cfg.morph ? 150 : 1; easing.type: Easing.InCubic
            }
        }
    }

    // A "face" tool is the card: Super+Space turns the island into the app
    // launcher, with no control center under it and no sheet over it. The
    // tool entry names the QML file; everything else still stacks.
    readonly property var faceInfo: {
        const t = IslandState.toolInfo(IslandState.tool);
        if (t && t.face) return t;
        // Opened from the menu bar: the panel's own file becomes the face.
        if (t && IslandState.direct && IslandState.tool !== "hub" && root.toolFile(IslandState.tool) !== "")
            return { id: t.id, glyph: t.glyph, name: t.name, face: root.toolFile(IslandState.tool) };
        return null;
    }
    function toolFile(id) {
        switch (id) {
            case "audio":    return "AudioTool.qml";
            case "bluetooth": return "BluetoothTool.qml";
            case "display":  return "DisplayTool.qml";
            case "calendar": return "CalendarTool.qml";
            case "media":    return "MediaTool.qml";
            case "weather":  return "WeatherTool.qml";
            case "battery":  return "BatteryTool.qml";
            case "monitor":  return "MonitorTool.qml";
            case "tray":     return "TrayTool.qml";
            case "notifs":   return "NotifsTool.qml";
            case "notes":    return "NotesTool.qml";
            case "clipboard": return "ClipboardTool.qml";
            case "keys":     return "KeysTool.qml";
            case "capture":  return "CaptureTool.qml";
            case "timer":    return "TimerTool.qml";
            case "call":     return "CallTool.qml";
            case "power":    return "PowerTool.qml";
            case "station":  return "StationTool.qml";
        }
        return "";
    }
    readonly property bool faceUp: root.openHere && root.faceInfo !== null

    // Whether a drill-in panel is stacked over the grid right now.
    readonly property bool panelUp: root.openHere && IslandState.tool !== "hub" && !root.faceUp

    // The composer reaches through to the calendar tool; these keep that seam
    // from knowing which panel is loaded.
    // Whichever loader holds the open tool: the stacked sheet, or the card
    // itself when the menu bar opened it directly.
    readonly property var liveTool: panelLoader.item ? panelLoader.item : faceLoader.item
    readonly property var calendars:
        root.liveTool && root.liveTool.calendars ? root.liveTool.calendars : []
    function refresh() {
        if (root.liveTool && root.liveTool.refresh) root.liveTool.refresh();
    }

    // Every panel floats over the hub, so back always means "put the sheet
    // away" — a one-level stack, which is all the phone reference keeps too.
    function goHome() {
        IslandState.openTool("hub", root.screenName);
    }

    // The frame owns the entrance animation so the shadows scale and fade in
    // lockstep with the card — animating the card alone left the shadow
    // hanging at full size while the surface was still growing into it.
    Item {
        parent: root.inSurface && root.surfaceHost ? root.surfaceHost : root.contentItem
        anchors.fill: parent

        opacity: root.shown ? 1 : 0
        scale: IslandState.cfg.morph || root.shown ? 1 : 0.94
        transformOrigin: Item.Top
        Behavior on opacity { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.08 } }

        // Two shadows, not one: a tight dark contact shadow that seats the
        // card against whatever is behind it, and a wide soft key shadow that
        // gives it altitude. A single blur at either size reads as a smudge.
        RectangularShadow {
            anchors.fill: card
            radius: card.radius
            blur: 12
            spread: 0
            offset: Qt.vector2d(0, 2)
            color: Qt.alpha(root.theme.shadow, 0.42)
        }
        RectangularShadow {
            anchors.fill: card
            radius: card.radius
            blur: 30
            spread: 2
            offset: Qt.vector2d(0, 12)
            color: Qt.alpha(root.theme.shadow, 0.38)
        }

        // The notch's card is the notch itself grown down: the same black
        // silhouette with the same ears, starting exactly over the resting
        // notch. It draws behind the card, which then wears no fill of its own.
        NotchShape {
            visible: IslandState.notch
            x: card.x - e
            y: card.y
            bodyWidth: card.width
            bodyHeight: card.height
            ear: IslandState.cfg.earRadius
                 + (IslandState.cfg.earRadius > 0 ? 6 * Math.min(1, root.gh) : 0)
            radius: card.radius
            readonly property color base: IslandState.cfg.pureBlack ? "#000000" : root.theme.islandBg
            topColor: base
            bottomColor: IslandState.cfg.pureBlack
                ? root.theme.mix(root.theme.on_surface, base, 0.035)
                : root.theme.mix(root.theme.on_surface, base, 0.02)
        }

        Rectangle {
            id: card
            width: root.pillWidth + (root.toolWidth - root.pillWidth) * root.gw
            height: root.pillHeight + (root.toolHeight - root.pillHeight) * root.gh
            x: root.padSide + (root.toolWidth - width) / 2
            y: root.padTop
            readonly property real restRadius: IslandState.notch
                ? IslandState.cfg.notchRadius : root.pillHeight / 2
            radius: restRadius + (IslandState.cfg.cardRadius - restRadius) * Math.min(1, root.gh)
            topLeftRadius: IslandState.notch ? 0 : radius
            topRightRadius: IslandState.notch ? 0 : radius
            clip: !root.settled

            // A faint vertical falloff instead of a flat fill: light lands on
            // the top of a raised surface, and the couple of points of lift up
            // there is what makes the sheet read as glass rather than paint.
            // Black, like the island it extends from, but not flat: both stops
            // are the island fill lifted a couple of points toward the text
            // colour, which keeps the falloff that makes the sheet read as a
            // raised surface. Flattening it to one black would have cost the
            // only cue that this is glass rather than paint.
            readonly property color glassTop:
                root.theme.mix(root.theme.on_surface, root.theme.islandBg, 0.06)
            readonly property color glassBottom:
                root.theme.mix(root.theme.on_surface, root.theme.islandBg, 0.02)
            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: Qt.rgba(card.glassTop.r, card.glassTop.g, card.glassTop.b,
                                   IslandState.notch ? 0 : root.theme.contentOpacity)
                }
                GradientStop {
                    position: 1.0
                    color: Qt.rgba(card.glassBottom.r, card.glassBottom.g,
                                   card.glassBottom.b, IslandState.notch ? 0 : root.theme.contentOpacity)
                }
            }
            border.width: IslandState.notch ? 0 : 1
            border.color: Qt.alpha(root.theme.outline, 0.30)
            Behavior on border.color { ColorAnimation { duration: 300 } }

            // Everything the card holds keeps its full size while the frame
            // morphs around it, centred, so nothing reflows mid-grow; the
            // frame's clip trims it and bodyIn fades it up at the end.
            Item {
                id: body
                x: (card.width - root.toolWidth) / 2
                width: root.toolWidth
                height: root.toolHeight
                opacity: root.bodyIn

                // ── header ────────────────────────────────────────────
                // The grid's own chrome: name on the left; pin, the
                // machine's silent switch and close on the right.
                Item {
                    id: header
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: root.headerHeight

                    // The hub's header is the clock that flew in from the
                    // pill: the island lands its flyer exactly on hdrClock,
                    // then the date slides out from under it. A click sends
                    // it home — the card closes and the clock flies back.
                    Item {
                        id: hdrClockBox
                        visible: !root.faceInfo
                        anchors.left: parent.left
                        anchors.leftMargin: 18
                        anchors.verticalCenter: parent.verticalCenter
                        width: hdrClock.implicitWidth + 10 + hdrDate.implicitWidth
                        height: hdrClock.implicitHeight

                        SystemClock { id: hdrClk; precision: SystemClock.Minutes }

                        Text {
                            id: hdrClock
                            text: root.clockText
                            color: root.theme.on_surface
                            font.family: root.theme.fontClock
                            font.features: root.theme.clockFeatures
                            font.pixelSize: root.clockPx
                            font.weight: Font.Black
                            opacity: root.clockLanded ? 1 : 0
                        }
                        Text {
                            id: hdrDate
                            anchors.left: hdrClock.right
                            anchors.leftMargin: 10 - 8 * (1 - root.dateIn)
                            anchors.baseline: hdrClock.baseline
                            text: Qt.formatDateTime(hdrClk.date, "dddd, d MMMM")
                            color: Qt.alpha(root.theme.on_surface_variant, 0.85)
                            font.family: root.theme.fontSans
                            font.pixelSize: IslandState.ts(12)
                            font.weight: Font.Medium
                            opacity: root.dateIn
                        }
                        MouseArea {
                            anchors.fill: hdrClock
                            cursorShape: Qt.PointingHandCursor
                            onClicked: IslandState.closeCard()
                        }
                    }

                    Row {
                        visible: !!root.faceInfo
                        anchors.left: parent.left
                        anchors.leftMargin: 18
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.faceInfo ? root.faceInfo.glyph : "\u{f0555}"
                            color: Qt.alpha(root.theme.on_surface_variant, 0.85)
                            font.family: root.theme.fontMono
                            font.pixelSize: 15
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.faceInfo ? root.faceInfo.name : "Control Center"
                            color: root.theme.on_surface
                            font.family: root.theme.fontSans
                            font.pixelSize: IslandState.ts(13)
                            font.weight: Font.DemiBold
                        }
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Repeater {
                            model: ["pin", "dnd", "close"]

                            Rectangle {
                                id: utilBtn
                                required property string modelData
                                readonly property string uid: modelData
                                readonly property bool isClose: uid === "close"
                                readonly property bool on:
                                    uid === "pin" ? root.pinned
                                  : uid === "dnd" ? IslandState.dnd : false
                                readonly property string glyph:
                                    uid === "pin" ? (root.pinned ? "\u{f0403}" : "\u{f0930}")
                                  : uid === "dnd" ? (IslandState.dnd ? "\u{f009b}" : "\u{f009a}")
                                  : "\u{f0156}"

                                width: 30; height: 30; radius: 11

                                color: on ? root.theme.secondary_container
                                     : utilHover.hovered
                                       ? (isClose ? Qt.alpha(root.theme.error, 0.22)
                                                  : Qt.alpha(root.theme.on_surface, 0.10))
                                       : "transparent"
                                Behavior on color { ColorAnimation { duration: 130 } }
                                scale: utilPress.pressed ? 0.90 : 1
                                Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }

                                Text {
                                    anchors.centerIn: parent
                                    text: utilBtn.glyph
                                    color: utilBtn.on ? root.theme.on_secondary_container
                                         : utilHover.hovered
                                           ? (utilBtn.isClose ? root.theme.error : root.theme.on_surface)
                                           : Qt.alpha(root.theme.on_surface_variant, 0.70)
                                    font.family: root.theme.fontMono
                                    font.pixelSize: 14
                                    Behavior on color { ColorAnimation { duration: 130 } }
                                }

                                HoverHandler { id: utilHover; cursorShape: Qt.PointingHandCursor }
                                MouseArea {
                                    id: utilPress
                                    anchors.fill: parent
                                    onClicked: {
                                        switch (utilBtn.uid) {
                                        case "pin": root.setPinned(!root.pinned); break;
                                        case "dnd": IslandState.toggleDnd(); break;
                                        case "close": IslandState.closeCard(); break;
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // The seam under the header fades out before it reaches the
                    // edges — a full-width line hard against rounded corners is
                    // what makes a frame look like a table, not a surface.
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 1
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0;  color: "transparent" }
                            GradientStop { position: 0.10; color: Qt.alpha(root.theme.outline_variant, 0.9) }
                            GradientStop { position: 0.90; color: Qt.alpha(root.theme.outline_variant, 0.9) }
                            GradientStop { position: 1.0;  color: "transparent" }
                        }
                    }
                }

                // ── the grid ──────────────────────────────────────────
                Flickable {
                    id: hubFlick
                    anchors.top: header.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    contentHeight: Math.max(root.viewHeight, hubView.preferredHeight)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: contentHeight > height && !root.panelUp
                    visible: !root.faceUp

                    ScrollBar { flick: hubFlick; theme: root.theme }

                    ControlCenter {
                        id: hubView
                        width: root.toolWidth
                        height: Math.max(root.viewHeight, preferredHeight)
                        theme: root.theme
                    }
                }

                // ── the face ──────────────────────────────────────────
                // Where the grid would be, when a face tool owns the card. Fresh
                // on every open (active follows visibility), so the launcher
                // always comes up empty and focused.
                // A panel opened straight from the menu bar can be taller than
                // the card (the calendar, the sound mixer), so the face
                // scrolls the way the stacked sheet does; one that asks for
                // nothing just fills it.
                Flickable {
                    id: faceFlick
                    anchors.top: header.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    contentHeight: faceLoader.item && faceLoader.item.preferredHeight
                                   ? Math.max(height, faceLoader.item.preferredHeight) : height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: contentHeight > height

                    ScrollBar { flick: faceFlick; theme: root.theme }

                    Loader {
                        id: faceLoader
                        width: faceFlick.width
                        height: faceFlick.contentHeight
                        active: root.faceUp
                        source: root.faceInfo ? root.faceInfo.face : ""
                        onLoaded: {
                            if (!item) return;
                            item.theme = root.theme;
                            if (item.reload) item.reload();
                            faceFlick.contentY = 0;
                        }
                    }
                }
            }

            // While a panel is stacked above, the grid steps back — and a
            // click on the dimmed surface is the same gesture as the panel's
            // back chevron.
            Rectangle {
                anchors.fill: parent
                radius: card.radius
                color: Qt.rgba(0, 0, 0, 0.38)
                opacity: root.panelUp ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                MouseArea { anchors.fill: parent; onClicked: root.goHome() }
            }

            // A hair of caught light along the top edge, fading before the
            // corner rounds away. It sits inside the border and is the one
            // detail that sells the gradient above as lighting.
            Rectangle {
                x: card.radius
                y: 1
                width: card.width - card.radius * 2
                height: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: Qt.alpha(root.theme.on_surface, 0.16) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            // Pinned indicator: a whisper of primary along the card's top edge
            // so a card that will no longer close on its own says so.
            Rectangle {
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.pinned ? 120 : 0
                height: 3
                radius: 1.5
                color: root.theme.primary
                opacity: root.pinned ? 0.9 : 0
                Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 180 } }
            }
        }
    }

    // ── the stacked panel ─────────────────────────────────────────
    // Its own window, floating over the grid the way the reference floats
    // Bluetooth over its control centre. Slightly narrower and lower than the
    // card, so the hub reads as still there underneath.
    PopupWindow {
        id: panelWin

        // Anchored to the card's body, not the card: the frame morphs from
        // pill size on open, but the body keeps the settled size and sits at
        // the same spot throughout, so the sheet never chases the grow.
        anchor.item: body
        anchor.rect.x: (root.toolWidth - panelWin.implicitWidth) / 2
        anchor.rect.y: 26 - panelWin.wPadTop

        readonly property real wPadSide: 24
        readonly property real wPadTop: 8
        readonly property real wPadBottom: 34
        readonly property real panelWidth: root.toolWidth - 48
        readonly property real panelHeight: root.toolHeight - 36
        readonly property real panelView: panelHeight - root.headerHeight
        readonly property real panelContent:
            panelLoader.item && panelLoader.item.preferredHeight
            ? Math.max(panelView, panelLoader.item.preferredHeight) : panelView

        implicitWidth: wPadSide * 2 + panelWidth
        implicitHeight: wPadTop + panelHeight + wPadBottom

        color: "transparent"
        // Never in the same frame the card itself maps: an xdg popup created
        // under a parent that is not on screen yet never shows, and took the
        // card's own repaints down with it. surfaceUp waits a few frames.
        // Otherwise mapped as soon as a sheet is up, even mid-grow: the focus grab
        // lists this window, and a grabbed window that is not mapped yet
        // clears the grab — which closed a card opened straight onto a sheet
        // (the status circle) the instant it armed. It stays invisible until
        // the morph settles; shownP is what fades it in.
        visible: !root.inSurface && up
        readonly property bool up: root.panelUp && root.surfaceUp

        property bool shownP: false
        property real swapShift: 0

        Item {
            parent: root.inSurface ? panelHost : panelWin.contentItem
            anchors.fill: parent

            opacity: panelWin.shownP ? 1 : 0
            scale: panelWin.shownP ? 1 : 0.95
            transformOrigin: Item.Top
            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.06 } }

            RectangularShadow {
                anchors.fill: sheet
                radius: sheet.radius
                blur: 12
                spread: 0
                offset: Qt.vector2d(0, 2)
                color: Qt.alpha(root.theme.shadow, 0.45)
            }
            RectangularShadow {
                anchors.fill: sheet
                radius: sheet.radius
                blur: 26
                spread: 2
                offset: Qt.vector2d(0, 10)
                color: Qt.alpha(root.theme.shadow, 0.40)
            }

            Rectangle {
                id: sheet
                x: panelWin.wPadSide
                y: panelWin.wPadTop
                width: panelWin.panelWidth
                height: panelWin.panelHeight
                radius: Math.max(12, IslandState.cfg.cardRadius - 4)

                // One step brighter than the card underneath: a sheet on a
                // sheet needs its own altitude in colour, not just in shadow.
                // Opaque, unlike the card: at the glass alpha the hub's tiles
                // showed through and a panel's controls read as sitting on
                // them (the radio power button on the sound slider).
                readonly property color glassTop:
                    root.theme.mix(root.theme.on_surface, root.theme.islandBg, 0.09)
                readonly property color glassBottom:
                    root.theme.mix(root.theme.on_surface, root.theme.islandBg, 0.04)
                gradient: Gradient {
                    GradientStop {
                        position: 0.0
                        color: Qt.rgba(sheet.glassTop.r, sheet.glassTop.g, sheet.glassTop.b, 1)
                    }
                    GradientStop {
                        position: 1.0
                        color: Qt.rgba(sheet.glassBottom.r, sheet.glassBottom.g,
                                       sheet.glassBottom.b, 1)
                    }
                }
                border.width: 1
                border.color: Qt.alpha(root.theme.outline, 0.35)

                // ── panel header: back, identity, close ───────────
                Item {
                    id: panelHeader
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: root.headerHeight

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 30; height: 30; radius: 11
                            color: backHover.hovered ? Qt.alpha(root.theme.on_surface, 0.10) : "transparent"
                            Behavior on color { ColorAnimation { duration: 130 } }
                            scale: backPress.pressed ? 0.9 : 1
                            Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }

                            Text {
                                anchors.centerIn: parent
                                text: "\u{f0141}"
                                color: root.theme.on_surface
                                font.family: root.theme.fontMono
                                font.pixelSize: 16
                            }
                            HoverHandler { id: backHover; cursorShape: Qt.PointingHandCursor }
                            MouseArea { id: backPress; anchors.fill: parent; onClicked: root.goHome() }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: {
                                const t = IslandState.toolInfo(IslandState.tool);
                                return t ? t.glyph : "";
                            }
                            color: Qt.alpha(root.theme.on_surface_variant, 0.85)
                            font.family: root.theme.fontMono
                            font.pixelSize: 15
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: {
                                const t = IslandState.toolInfo(IslandState.tool);
                                return t ? t.name : "";
                            }
                            color: root.theme.on_surface
                            font.family: root.theme.fontSans
                            font.pixelSize: IslandState.ts(13)
                            font.weight: Font.DemiBold
                        }
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        // A panel's main switch rides in the header — back,
                        // name and toggle in one row, the reference's
                        // Bluetooth alignment. Any tool that declares the
                        // headerToggle interface gets it.
                        ToggleSwitch {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: panelLoader.item !== null
                                     && panelLoader.item.headerToggle === true
                            theme: root.theme
                            checked: panelLoader.item !== null
                                     && panelLoader.item.headerToggleOn === true
                            onToggled: if (panelLoader.item) panelLoader.item.headerToggled()
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 30; height: 30; radius: 11
                            color: xHover.hovered ? Qt.alpha(root.theme.error, 0.22) : "transparent"
                            Behavior on color { ColorAnimation { duration: 130 } }
                            Text {
                                anchors.centerIn: parent
                                text: "\u{f0156}"
                                color: xHover.hovered ? root.theme.error
                                     : Qt.alpha(root.theme.on_surface_variant, 0.70)
                                font.family: root.theme.fontMono
                                font.pixelSize: 14
                            }
                            HoverHandler { id: xHover; cursorShape: Qt.PointingHandCursor }
                            // Closes the sheet alone — the control center it
                            // floats over stays up; the island closes from its
                            // own header, Esc, or a click elsewhere.
                            MouseArea { anchors.fill: parent; onClicked: root.goHome() }
                        }
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 1
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0;  color: "transparent" }
                            GradientStop { position: 0.10; color: Qt.alpha(root.theme.outline_variant, 0.9) }
                            GradientStop { position: 0.90; color: Qt.alpha(root.theme.outline_variant, 0.9) }
                            GradientStop { position: 1.0;  color: "transparent" }
                        }
                    }
                }

                // ── the panel content ─────────────────────────────
                Flickable {
                    id: panelFlick
                    anchors.top: panelHeader.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    contentHeight: panelWin.panelContent
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: contentHeight > height

                    ScrollBar { flick: panelFlick; theme: root.theme }

                    Loader {
                        id: panelLoader
                        width: panelWin.panelWidth
                        height: panelWin.panelContent
                        transform: Translate { y: panelWin.swapShift }

                        source: root.panelUp ? root.toolFile(IslandState.tool) : ""

                        // Loader cannot bind properties into a source-loaded
                        // item, so the theme is handed over once. That is safe
                        // because shell.qml builds a single Theme object and
                        // mutates its properties in place — the tool's own
                        // bindings stay live across a matugen reload.
                        onLoaded: {
                            if (!item) return;
                            item.theme = root.theme;
                            if (item.reload) item.reload();
                            panelFlick.contentY = 0;
                            swapAnim.restart();
                        }
                    }

                    // Switching panels used to snap — the Loader swaps its
                    // item in one frame. The fresh sheet settles in from a few
                    // px below instead.
                    ParallelAnimation {
                        id: swapAnim
                        NumberAnimation {
                            target: panelLoader; property: "opacity"
                            from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic
                        }
                        NumberAnimation {
                            target: panelWin; property: "swapShift"
                            from: 10; to: 0; duration: 260; easing.type: Easing.OutCubic
                        }
                    }
                }

                // the same hair of caught light the card wears
                Rectangle {
                    x: sheet.radius
                    y: 1
                    width: sheet.width - sheet.radius * 2
                    height: 1
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.5; color: Qt.alpha(root.theme.on_surface, 0.18) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }
            }
        }

        // Esc always closes the whole card, from any sheet or detail view;
        // the back button is the way back to the hub.
        Item {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: IslandState.closeCard()
        }

        Timer { id: panelIn; interval: 16; onTriggered: panelWin.shownP = true }
        onUpChanged: {
            if (up) { if (root.settled) panelIn.restart(); }
            else { panelIn.stop(); shownP = false; }
        }
        Connections {
            target: root
            function onSettledChanged() {
                if (root.settled && panelWin.up) panelIn.restart();
            }
        }
    }

    // The sheet's stand-in window on the lock surface: where panelWin would
    // sit, in the card's coordinates (the body rests at padSide, padTop).
    Item {
        id: panelHost
        parent: root.inSurface && root.surfaceHost ? root.surfaceHost : root.contentItem
        x: root.padSide + panelWin.anchor.rect.x
        y: root.padTop + panelWin.anchor.rect.y
        z: 10
        width: panelWin.implicitWidth
        height: panelWin.implicitHeight
        visible: root.inSurface && panelWin.up
    }

    Connections {
        target: panelLoader.item
        ignoreUnknownSignals: true
        function onComposeRequested(iso) { root.composeRequested(iso); }
    }

    // The hyprland focus grab spans both windows, so a click on the stacked
    // panel never reads as "clicked away" and Esc lands wherever the keyboard
    // is. Both handlers close the card, so the key behaves the same wherever
    // focus happens to sit.
    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: IslandState.closeCard()
    }

    function setPinned(value) {
        root.pinned = value;
        if (value) {
            // Dropping the grab is what lets the card outlive a click
            // elsewhere; onCleared checks pinned so this release does not
            // read as "the user clicked away".
            armGrab.stop();
            grab.active = false;
        } else if (root.visible) {
            armGrab.restart();
        }
    }

    HyprlandFocusGrab {
        id: grab
        windows: [root, panelWin]
        active: false
        onCleared: if (!root.pinned) IslandState.closeCard()
    }

    // The grab must be armed after the surface is mapped; activating it in the
    // same tick that visible flips silently fails and never reports an error.
    Timer {
        id: armGrab
        interval: 120
        onTriggered: {
            if (root.inSurface) return;
            grab.active = true;
            if (root.panelUp) refocusTimer.restart();
        }
    }

    // Keyboard focus has to follow the sheet. The bar these popups hang off
    // is not keyboard-interactive, so Hyprland never moves the keyboard to a
    // popup on click; the grab parks it on the first grabbed surface and a
    // search field in the panel never saw a keystroke. Hyprland does refocus
    // when the focused surface leaves the grab set, so the set is re-listed
    // with only the sheet for a tick, then both with the sheet first. Same
    // dance back to the card when the sheet goes away.
    function refocusGrab() {
        if (!grab.active) return;
        grab.windows = root.panelUp ? [panelWin] : [root];
        refocusStep2.restart();
    }
    Timer {
        id: refocusStep2
        interval: 50
        onTriggered: grab.windows = root.panelUp ? [panelWin, root] : [root, panelWin]
    }
    // After the sheet's surface has mapped, for the same reason armGrab waits.
    Timer { id: refocusTimer; interval: 160; onTriggered: root.refocusGrab() }
    onPanelUpChanged: if (root.visible) refocusTimer.restart()
    // A sheet only maps once the morph has settled, so a card opened
    // straight onto one (the status circle, an IPC open) refocuses then.
    onSettledChanged: if (root.settled && root.panelUp) refocusTimer.restart()
    Timer { id: animIn; interval: 16; onTriggered: root.shown = true }

    // Open and close are keyed on openHere, not visible: the window stays
    // mapped through the shrink-back, and a reopen caught mid-shrink never
    // toggles visible at all, so the grab and the hub refresh would not run.
    function onOpened() {
        root.pinned = false;
        armGrab.restart();
        animIn.restart();
        hubFlick.contentY = 0;
        hubView.reload();
    }

    onVisibleChanged: if (!root.inSurface) root.mapped(visible)
    function mapped(visible) {
        if (visible) surfaceTimer.restart();
        else { surfaceTimer.stop(); root.surfaceUp = false; }
        if (visible) {
            root.pinned = false;
            animIn.restart();
            // The grid keeps whatever offset it was left on, so a card that
            // was closed part-scrolled reopened part-scrolled, with the top
            // row hidden under the header. The stacked sheet already resets
            // its own flick on load; this is the hub's equivalent.
            // The hub polls only while showing; opening the card is the
            // moment to refresh what it shows (onOpened does that, along
            // with resetting the grid's scroll).
        } else {
            armGrab.stop();
            animIn.stop();
            grab.active = false;
            root.shown = false;
            root.pinned = false;
        }
    }
}
