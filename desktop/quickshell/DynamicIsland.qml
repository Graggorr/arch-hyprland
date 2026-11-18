import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets

// The pill. It owns no data any more — everything it draws comes from
// IslandState, which exists once per machine rather than once per monitor.
//
// Three slots, after the reference this was modelled on:
//   lead   its own segment left of the clock, two lines (a meeting)
//   main   replaces the clock text while it is up — no producer publishes to
//          it today; it is what a transient line (an OSD, a lyric) would take
//   trail  a detached capsule right of the pill, for something that keeps
//          running while the main slot carries on changing (a timer)
Item {
    id: root

    property var theme
    property string screenName: ""

    // ── lock mode ─────────────────────────────────────────────────
    // The lock surface draws this same island. lockMode makes the pill inert
    // (no hover growth, no click actions) and draws the card inside the lock
    // surface when the menu bar opens it. lockAuth additionally makes
    // the clock slot the password field: dots while typing, a spinner while
    // PAM checks, a shake and a warn edge on a wrong password. The real
    // TextInput lives here so keyboard focus sits on the island itself.
    property bool lockMode: false
    property bool lockAuth: false
    property string lockErr: ""
    property bool lockBusy: false
    property string lockLayout: ""
    readonly property string lockPw: lockInput.text
    property alias lockInput: lockInput
    signal lockSubmitted()

    function lockShake() { shakeAnim.restart(); }

    // Only the monitor that opened the card counts as expanded — otherwise
    // hovering one island would inflate the other.
    readonly property bool cardHere:
        (root.lockMode || !IslandState.locked)
        && IslandState.cardOpen && IslandState.toolScreen === root.screenName
    // In the notch the card is the expanded form — it grows over the notch —
    // so the notch itself rests while the card is up instead of widening
    // behind it and poking out at both sides.
    // With the menu bar on, the island holds still: no hover growth, no
    // lift, and only notifications reach it (see IslandState.bestIn).
    readonly property bool barMode: IslandState.cfg.menuBar
    readonly property bool hoverGrow: !lockMode && !barMode && hover.hovered
    readonly property bool expanded: lockMode
        ? lockAuth && (lockInput.text !== "" || lockBusy || lockErr !== "")
        : IslandState.notch
        ? !cardHere && (hoverGrow || (!barMode && notchHover.hovered))
        : hoverGrow || cardHere

    // A reveal piece is on the pill when its on-hover pref is set and either
    // the pill is expanded or its always pref keeps it there. The on-hover
    // pref gates both, so switching it off removes the piece everywhere.
    function reveals(name) {
        const c = IslandState.cfg;
        return c["reveal" + name] === true && (root.expanded || c["always" + name] === true);
    }

    readonly property var lead: IslandState.lead
    readonly property var main: root.lockAuth ? null : IslandState.main
    readonly property var trail: IslandState.trail

    // A call has no segment on the pill at all: its whole presence is the
    // waveform on the far right — who is talking, in colour — and the call
    // panel is a click on it away. Every other lead (a meeting) shows as its
    // two-line segment.
    readonly property bool leadShown:
        root.lead !== null && root.lead.style !== "call"

    // An activity carries either an explicit tint — a calendar event's own
    // colour, which is not ours to theme — or a semantic tone resolved against
    // the palette of the monitor this island is on. A producer that hardcoded
    // a colour would ignore the theme, so producers name a tone instead.
    function toneColor(a) {
        if (!a) return root.theme.fg;
        if (a.tint && a.tint !== "") return a.tint;
        switch (a.tone) {
        // warn survives on purpose: a filling disk or a failed unit is
        // the one thing on the pill that must not read as ordinary text.
        case "warn": return root.theme.warn;
        case "primary": return root.theme.primary;
        case "accent2": return root.theme.accent2;
        case "accent3": return root.theme.accent3;
        case "muted": return root.theme.muted;
        default: return root.theme.fg;
        }
    }
    readonly property color leadColor: root.toneColor(root.lead)
    readonly property color mainColor: root.toneColor(root.main)
    readonly property color trailColor: root.toneColor(root.trail)

    // Stage lift: the resting island steps down off the screen edge while
    // hovered, by the user's number of px (0 turns it off). Not while the
    // card is open — the card hangs off the pill and must not bob with it.
    transform: [
        Translate {
            y: root.hoverGrow && !root.cardHere ? IslandState.cfg.hoverLift : 0
            Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
        },
        Translate { id: shakeT; x: 0 }
    ]

    // The wrong-password shake, the phone's "no" wobble.
    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: shakeT; property: "x"; to: -14; duration: 50; easing.type: Easing.OutQuad }
        NumberAnimation { target: shakeT; property: "x"; to: 12; duration: 70; easing.type: Easing.InOutQuad }
        NumberAnimation { target: shakeT; property: "x"; to: -8; duration: 70; easing.type: Easing.InOutQuad }
        NumberAnimation { target: shakeT; property: "x"; to: 5; duration: 60; easing.type: Easing.InOutQuad }
        NumberAnimation { target: shakeT; property: "x"; to: 0; duration: 60; easing.type: Easing.OutQuad }
    }

    // The pill holds the screen's centre whatever hangs off its sides: the
    // box is the pill plus the wider side twice over, so the circles grow
    // outward from the pill's edges instead of shoving it off-centre. The
    // card centres on this box too, which keeps it under the pill.
    readonly property real leftW: padsSlot.width + phoneSlot.width + airpodsSlot.width + artSlot.width
    readonly property real rightW: statusSlot.width
                                   + (trailCap.visible ? trailCap.width + 8 : 0)
    implicitWidth: pill.width + 2 * Math.max(leftW, rightW)
    implicitHeight: pill.implicitHeight

    SystemClock { id: clk; precision: SystemClock.Seconds }

    // ── notch mode ────────────────────────────────────────────────
    // One black silhouette welded to the screen edge behind everything the
    // island otherwise draws as separate pieces: the side circles and the
    // trail capsule become its wings, the pill its middle, and each of them
    // drops its own fill so the notch reads as one body.
    readonly property bool notch: IslandState.notch
    readonly property color notchFill: IslandState.cfg.pureBlack
        ? "#000000"
        : Qt.rgba(root.theme.islandBg.r, root.theme.islandBg.g,
                  root.theme.islandBg.b, IslandState.cfg.islandOpacity)
    // The fill each detached piece wears: its own in island mode, none in the
    // notch, where the silhouette behind it already is that fill.
    readonly property color pieceFill: root.notch ? "transparent"
        : Qt.rgba(root.theme.islandBg.r, root.theme.islandBg.g,
                  root.theme.islandBg.b, IslandState.cfg.islandOpacity)
    readonly property real wingPad: 14
    // What the card grows out of: the whole silhouette in the notch, the
    // pill alone on the island.
    // The notch is symmetric around the clock: the pill is centred in the
    // box, and the box is the pill plus the wider side twice over.
    readonly property real notchLeft: -root.wingPad
    readonly property real notchBodyWidth: root.width + 2 * root.wingPad

    Item {
        id: notchBody
        visible: root.notch
        x: root.notchLeft - notchShape.e
        y: 0
        width: notchShape.width
        height: notchShape.height

        // The wings count as the notch: hovering the art or the status
        // circle grows the whole body, not just its middle.
        HoverHandler { id: notchHover; enabled: root.notch }

        layer.enabled: root.notch && IslandState.cfg.notchShadow
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.alpha(root.theme.shadow, 0.55)
            shadowBlur: 0.6
            shadowVerticalOffset: 3
            autoPaddingEnabled: true
        }

        NotchShape {
            id: notchShape
            bodyWidth: root.notchBodyWidth
            bodyHeight: pill.height
            ear: IslandState.cfg.earRadius
            // Rounder as it grows, the way the notch apps interpolate their
            // radii between closed and peeked.
            radius: IslandState.cfg.notchRadius + (root.expanded ? 3 : 0)
            topColor: root.notchFill
            bottomColor: root.notchFill
            edgeColor: root.lockAuth && root.lockErr !== "" ? Qt.alpha(root.theme.warn, 0.8)
                     : IslandState.cfg.pureBlack ? "transparent"
                     : Qt.alpha(root.theme.accent, root.expanded ? 0.22 : 0.06)
            Behavior on radius { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        }
    }

    // Resting on the notch opens the hub, if the user asked for that.
    Timer {
        id: hoverOpenTimer
        interval: IslandState.cfg.hoverOpenMs
        running: !root.lockMode && root.notch && IslandState.cfg.hoverOpen && hover.hovered && !root.cardHere
        onTriggered: IslandState.openTool("hub", root.screenName)
    }

    // ── album art circle, detached left ───────────────────────────
    // The Duo look: while something plays, the art sits beside the pill as
    // its own circle rather than inside the content row, mirroring the
    // status circle on the other end so the island reads as one symmetric
    // family of shapes. The accent tint over the cover is deliberate — an
    // arbitrary album sleeve never matches the wallpaper's palette, and the
    // wash is what keeps a hot-pink cover from shouting at a blue theme.
    // ── controller circles, outermost left ────────────────────────
    // One per connected controller, each in its own colour.
    Item {
        id: padsSlot
        anchors.right: phoneSlot.left
        anchors.verticalCenter: pill.verticalCenter
        readonly property var pads: IslandState.cfg.controllerCircle && !IslandState.cfg.menuBar
            ? IslandState.controllers : []
        readonly property real fullW: padsRow.implicitWidth + (pads.length ? 8 : 0)
        width: fullW
        height: root.expanded ? 34 : 30
        clip: true
        visible: width > 0.5
        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

        Row {
            id: padsRow
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Repeater {
                model: padsSlot.pads
                DeviceCircle {
                    required property var modelData
                    kind: "controller"
                    device: modelData
                    width: implicitWidth
                    height: implicitHeight
                    theme: root.theme
                    screenName: root.screenName
                    expanded: root.expanded
                }
            }
        }
    }

    // ── phone circle ──────────────────────────────────────────────
    // Only while the phone's battery is reachable, and never with its pref
    // off. In the menu bar both devices are items instead.
    Item {
        id: phoneSlot
        anchors.right: airpodsSlot.left
        anchors.verticalCenter: pill.verticalCenter
        readonly property bool show: IslandState.cfg.phoneCircle && phoneCircle.connected && !IslandState.cfg.menuBar
        readonly property real fullW: (root.expanded ? 34 : 30) + 8
        width: show ? fullW : 0
        height: phoneCircle.implicitHeight
        clip: width < fullW - 0.5
        visible: width > 0.5
        opacity: show ? 1 : 0
        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        DeviceCircle {
            id: phoneCircle
            kind: "phone"
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: implicitWidth
            height: implicitHeight
            theme: root.theme
            screenName: root.screenName
            expanded: root.expanded
        }
    }

    // ── AirPods circle, left of the art ───────────────────────────
    // Only while the AirPods hold a link, and never with its pref off.
    Item {
        id: airpodsSlot
        anchors.right: artSlot.left
        anchors.verticalCenter: pill.verticalCenter
        readonly property bool show: IslandState.cfg.airpodsCircle && airpodsCircle.connected && !IslandState.cfg.menuBar
        readonly property real fullW: (root.expanded ? 34 : 30) + 8
        width: show ? fullW : 0
        height: airpodsCircle.implicitHeight
        clip: width < fullW - 0.5
        visible: width > 0.5
        opacity: show ? 1 : 0
        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        DeviceCircle {
            id: airpodsCircle
            kind: "airpods"
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: implicitWidth
            height: implicitHeight
            theme: root.theme
            screenName: root.screenName
            expanded: root.expanded
        }
    }

    Item {
        id: artSlot
        anchors.right: pill.left
        anchors.verticalCenter: pill.verticalCenter
        readonly property bool show:
            IslandState.mediaPlaying && IslandState.cfg.artStyle === "circle" && !IslandState.cfg.menuBar
        // Sized from root.expanded directly, not from the circle's animated
        // width: reading the animated value would retarget this Behavior every
        // frame — the stacked-curves trap the morph comment below documents.
        readonly property real fullW: (root.expanded ? 34 : 30) + 8
        width: show ? fullW : 0
        height: artCircle.height
        // Clipped only mid-collapse: a permanent clip would shear the edges
        // off the hover scale, which grows the circle past this slot's box.
        clip: width < fullW - 0.5
        visible: width > 0.5
        opacity: show ? 1 : 0
        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        Rectangle {
            id: artCircle
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: root.expanded ? 34 : 30
            height: width
            radius: width / 2
            Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
            // The black capsule the reference gives its art: the cover sits
            // inset inside it rather than bleeding to the edge, so the circle
            // reads as a piece of the island holding a sleeve, not a sticker.
            color: root.pieceFill
            border.width: root.notch ? 0 : 1
            border.color: artHov.hovered ? Qt.alpha(root.theme.accent, 0.45)
                        : Qt.alpha(root.theme.accent, root.expanded ? 0.28 : 0.06)
            Behavior on border.color { ColorAnimation { duration: 220 } }
            scale: artHov.hovered ? 1.08 : 1
            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

            TrackSwap { target: artBigClip; shift: 0; fromScale: 0.6 }
            ClippingRectangle {
                id: artBigClip
                anchors.fill: parent
                anchors.margins: 4
                radius: width / 2
                color: Qt.alpha(root.theme.muted, 0.22)

                Image {
                    id: artBig
                    anchors.fill: parent
                    source: IslandState.player && IslandState.player.trackArtUrl
                            ? IslandState.player.trackArtUrl : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 68
                    sourceSize.height: 68
                    asynchronous: true
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 220 } }
                }
                Rectangle {
                    anchors.fill: parent
                    visible: artBig.status === Image.Ready
                    color: Qt.alpha(root.theme.accent, 0.18)
                }
            }
            Text {
                anchors.centerIn: parent
                visible: artBig.status !== Image.Ready
                text: "\u{f04c7}"
                color: root.theme.primary
                font.family: root.theme.fontMono
                font.pixelSize: 13
            }
        }

        HoverHandler { id: artHov; cursorShape: Qt.PointingHandCursor }
        MouseArea {
            anchors.fill: parent
            onClicked: IslandState.toggleTool("media", root.screenName)
        }
    }

    // ── status circle, detached right ─────────────────────────────
    Item {
        id: statusSlot
        anchors.left: pill.right
        anchors.verticalCenter: pill.verticalCenter
        readonly property bool show: IslandState.cfg.statusCircle && !IslandState.cfg.menuBar
        // Same decoupling as artSlot: the circle's implicitWidth animates, so
        // this binding derives from root.expanded to keep one curve per side.
        readonly property real fullW: (root.expanded ? 34 : 30) + 8
        width: show ? fullW : 0
        height: statusCircle.implicitHeight
        // Same conditional clip as artSlot, for the same hover-scale reason.
        clip: width < fullW - 0.5
        visible: width > 0.5
        opacity: show ? 1 : 0
        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        StatusCircle {
            id: statusCircle
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: implicitWidth
            height: implicitHeight
            theme: root.theme
            screenName: root.screenName
            expanded: root.expanded
        }
    }

    // Every morph Behavior below is hardcoded to 300ms OutCubic, and must stay
    // that way. Binding `easing.type` to a direction-dependent property does not
    // work: Qt builds the QEasingCurve once and a Behavior's animation keeps
    // serving the stale one, so the curve silently never changes. Measured, the
    // bound version still ran the first easing ever assigned — an ease-in-out
    // that sat still for ~70ms after the pointer left, then lurched. OutCubic
    // moves furthest on the first frame and settles without the long crawl
    // OutExpo leaves behind.

    Rectangle {
        id: pill

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top

        // The width tracks the content directly instead of carrying its own
        // Behavior. The reveals inside are already animating, so easing the
        // container too stacked two curves and left the pill trailing its own
        // contents on the way back. Only the padding is animated here.
        property real padH: root.expanded ? 36 : 30
        Behavior on padH { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

        implicitHeight: root.expanded ? IslandState.cfg.pillHeightExpanded : IslandState.cfg.pillHeight
        implicitWidth: content.implicitWidth + padH
        radius: height / 2

        // One fill in both states. The collapsed pill used to sit on the lighter
        // `bg` and the expanded one on `base`, which read as the island
        // changing material as it grew; black holds still.
        color: root.pieceFill
        border.width: root.notch ? 0 : 1
        border.color: root.lockAuth && root.lockErr !== ""
                      ? Qt.alpha(root.theme.warn, 0.8)
                      : root.leadShown
                      ? Qt.alpha(root.leadColor, 0.55)
                      : Qt.alpha(root.theme.accent, root.expanded ? 0.28 : 0.06)

        Behavior on implicitHeight { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 220 } }
        Behavior on border.color { ColorAnimation { duration: 220 } }

        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: false
            enabled: !root.lockMode
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (e) => {
                if (e.button === Qt.RightButton) {
                    IslandState.open(IslandState.wxUrl);
                    return;
                }
                // While an activity holds the main slot it owns the click too —
                // a track flash should open the media tool, not the card.
                if (root.main && root.main.action) { root.main.action(); return; }
                // The hub is the entry point: everything else drills in from
                // its grid, so the pill always opens home rather than
                // wherever the card happened to be last.
                IslandState.toggleTool("hub", root.screenName);
            }
        }

        // Not a Row: the units are placed by hand, because which side of the
        // clock a unit sits on is decided here rather than by where it is
        // declared. Each unit bakes its own gap into its width, as it did under
        // the Row, so a reveal collapsing to zero takes its gap with it.
        Item {
            id: content
            anchors.centerIn: parent
            implicitWidth: place.total
            height: parent.height

            // ── where ─────────────────────────────────────────────
            // Nothing is decided here: the order comes from the pillLayout
            // pref (IslandState.pillOrder, edited in Settings → Pill), left to
            // right with "clock" as one of its entries. A unit left of the
            // clock faces it from the left, one right of it from the right,
            // and that is all `side` means. The pill hugs its content — no
            // padding evens the halves out, no unit stretches into slack — so
            // the clock sits wherever the layout puts it.
            readonly property var order: IslandState.pillShown || ["clock"]
            readonly property var side: {
                const s = {};
                const c = order.indexOf("clock");
                for (let i = 0; i < order.length; i++)
                    if (order[i] !== "clock") s[order[i]] = i < c ? 0 : 1;
                return s;
            }
            // Kept for the units' bindings: nothing ever hides to swap sides
            // any more, so neither ever holds a name.
            readonly property var hiding: ({})
            readonly property var jumped: ({})
            // A layout edit glides every unit to its new place.
            property bool gliding: false
            onOrderChanged: { gliding = true; glideTimer.restart(); }
            Timer {
                id: glideTimer
                interval: 330
                onTriggered: content.gliding = false
            }
            readonly property var units: [wsSlot, artSeg, leadSeg, utcSeg, statusZone, wxSeg, condSeg, liveSeg]

            function has(name) { return content.order.indexOf(name) >= 0; }

            function unit(name) {
                for (let i = 0; i < units.length; i++)
                    if (units[i].objectName === name) return units[i];
                return null;
            }

            // Elastic units are summed by `base`, their natural animating
            // width; with no slack handed out it is also their whole width.
            function placeUnits() {
                const wOf = (c) => c.elastic ? c.base : (c.visible ? c.width : 0);
                const x = {};
                let cur = 0;
                for (const n of content.order) {
                    if (n === "clock") { x.main = cur; cur += mainSlot.width; continue; }
                    const c = content.unit(n);
                    if (!c) continue;
                    x[n] = cur;
                    cur += wOf(c);
                }
                return { x: x, total: cur };
            }
            readonly property var place: placeUnits()
            function grant(name) { return 0; }
            function xOf(name) { const v = content.place.x[name]; return v === undefined ? 0 : v; }

            // ── reveal: workspaces, leading the row ───────────────
            // Used to be the one always-present structural element; it now
            // rests hidden like the call, so the collapsed pill is just the
            // clock.
            Item {
                id: wsSlot
                objectName: "ws"
                anchors.verticalCenter: parent.verticalCenter
                height: wsZone.implicitHeight
                clip: true
                visible: base > 0.5
                x: content.xOf("ws")
                Behavior on x { enabled: content.gliding && !content.jumped.ws; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                readonly property bool flip: content.side.ws !== 0
                readonly property bool shown: content.has("ws") && root.reveals("Workspaces")
                readonly property real want: shown ? natural : 0
                readonly property bool elastic: true
                readonly property real natural: wsStrip.ids.length
                    * (root.expanded ? wsStrip.slotWide : wsStrip.slotCompact)
                    + (root.expanded ? 16 : 12)
                property real base: shown ? natural : 0
                readonly property real cap: natural > 0
                    ? wsStrip.ids.length * (root.expanded ? 8 : 10) * base / natural : 0
                width: base + content.grant("ws")
                opacity: shown && !content.hiding.ws ? 1 : 0
                Behavior on base { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                Row {
                    id: wsZone
                    anchors.left: parent.left
                    spacing: 0
                    // The gap faces the clock, whichever side that is.
                    layoutDirection: wsSlot.flip ? Qt.RightToLeft : Qt.LeftToRight

                    Workspaces {
                        id: wsStrip
                        anchors.verticalCenter: parent.verticalCenter
                        extra: content.grant("ws")
                        theme: root.theme
                        screenName: root.screenName
                        // Pills on the resting island (the always-visible
                        // reveal), icons once it is hovered or open.
                        compact: !root.expanded
                    }

                    Item { width: root.expanded ? 16 : 12; height: 1 }
                }
            }

            // ── now playing: album art, far left ──────────────────
            // Art on one end, live bars on the other, nothing in between —
            // after the phone island this is modelled on. The full view is
            // one click away in the media tool. This is the "pill" placement;
            // the default is the detached circle beside the pill (artSlot),
            // and the settings window switches between them.
            Item {
                id: artSeg
                objectName: "art"
                anchors.verticalCenter: parent.verticalCenter
                height: 24
                clip: true
                visible: width > 0.5
                x: content.xOf("art")
                Behavior on x { enabled: content.gliding && !content.jumped.art; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                readonly property bool shown: content.has("art")
                    && IslandState.mediaPlaying && IslandState.cfg.artStyle === "pill"
                readonly property real want: shown ? 24 + 14 : 0
                width: want
                opacity: shown ? 1 : 0
                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                // Its gap faces the clock, whichever side it is on.
                Rectangle {
                    x: content.side.art === 1 ? parent.width - width : 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24; height: 24; radius: 8
                    color: Qt.alpha(root.theme.muted, 0.22)
                    clip: true
                    TrackSwap { shift: 0; fromScale: 0.6 }

                    Image {
                        id: art
                        anchors.fill: parent
                        source: IslandState.player && IslandState.player.trackArtUrl
                                ? IslandState.player.trackArtUrl : ""
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: 48
                        sourceSize.height: 48
                        asynchronous: true
                        opacity: status === Image.Ready ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 220 } }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: art.status !== Image.Ready
                        text: "\u{f04c7}"
                        color: root.theme.primary
                        font.family: root.theme.fontMono
                        font.pixelSize: 13
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: IslandState.toggleTool("media", root.screenName)
                }
            }

            // ── lead slot ─────────────────────────────────────────
            Item {
                id: leadSeg
                objectName: "lead"
                anchors.verticalCenter: parent.verticalCenter
                x: content.xOf("lead")
                Behavior on x { enabled: content.gliding && !content.jumped.lead; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                height: Math.max(leadCol.implicitHeight, callRow.implicitHeight)
                clip: true
                visible: width > 0.5
                // A call asks for the phone's compact layout — a filled badge
                // and a running timer, nothing to read. Everything else, the
                // IPC publishers included, keeps the two-line segment.
                readonly property bool isCall: root.lead && root.lead.style === "call"
                // The extra room is reserved whenever the activity is
                // dismissible, not when hovered — growing the pill under the
                // pointer would move the very thing being aimed at.
                readonly property bool shown: root.leadShown && content.has("lead")
                readonly property real want: shown
                       ? (leadSeg.isCall ? callRow.implicitWidth : leadRow.implicitWidth)
                         + (root.lead.dismiss ? 36 : 14) : 0
                width: want
                opacity: leadSeg.shown ? 1 : 0
                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                // ── call face ─────────────────────────────────
                // Badge, then the name only once there is room for it, then
                // the timer. The phone shows icon and timer at rest and adds
                // the rest when the island grows; this does the same, with
                // hover standing in for the long press.
                Row {
                    id: callRow
                    anchors.left: parent.left
                    anchors.leftMargin: content.side.lead === 1 ? 14 : 0
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    visible: leadSeg.isCall
                    opacity: leadSeg.isCall ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 160 } }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22; height: 22; radius: 11
                        color: root.leadColor

                        // The badge breathes rather than a separate dot doing
                        // it: on a call the icon is the live thing.
                        SequentialAnimation on scale {
                            running: leadSeg.isCall
                            loops: Animation.Infinite
                            alwaysRunToEnd: true
                            NumberAnimation { to: 1.09; duration: 900; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: root.lead && root.lead.badge ? root.lead.badge : ""
                            // Straight white on the filled badge, as the phone
                            // has it — the tints are all saturated enough to
                            // carry it, and a themed foreground would vanish on
                            // the muted red.
                            color: "#ffffff"
                            font.family: root.theme.fontMono
                            font.pixelSize: 12
                        }
                    }

                    // A plain gap. The name below animates its own width, so
                    // sizing this one off the same text too would open twice
                    // the space the name needs.
                    Item { width: 10; height: 1 }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.lead && root.lead.title ? root.lead.title : ""
                        color: root.theme.fg
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(12)
                        font.weight: Font.DemiBold
                        opacity: root.expanded ? 1 : 0
                        visible: opacity > 0.01
                        width: root.expanded ? implicitWidth : 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    }

                    Item { width: 8; height: 1 }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.lead && root.lead.value ? root.lead.value : ""
                        color: root.leadColor
                        font.family: root.theme.fontMono
                        font.pixelSize: 13
                        font.weight: Font.Bold
                    }
                }

                // ── generic face ──────────────────────────────
                Row {
                    id: leadRow
                    anchors.left: parent.left
                    anchors.leftMargin: content.side.lead === 1 ? 14 : 0
                    spacing: 8
                    visible: !leadSeg.isCall

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 9; height: 9; radius: 4.5
                        color: root.lead ? root.leadColor : "transparent"
                        SequentialAnimation on opacity {
                            running: root.lead !== null
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.25; duration: 900; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine }
                        }
                    }

                    Column {
                        id: leadCol
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0
                        Text {
                            width: Math.min(implicitWidth, 190)
                            elide: Text.ElideRight
                            text: root.lead ? root.lead.title : ""
                            color: root.lead ? root.leadColor : root.theme.fg
                            font.family: root.theme.fontSans
                            font.pixelSize: IslandState.ts(12)
                            font.weight: Font.DemiBold
                        }
                        Text {
                            text: root.lead ? (root.lead.sub || "") : ""
                            color: Qt.alpha(root.theme.muted, 0.95)
                            font.family: root.theme.fontMono
                            font.pixelSize: 10
                            font.weight: Font.Bold
                        }
                    }
                }

                HoverHandler { id: leadHover }

                // The segment runs its activity's own action; everywhere else on
                // the pill keeps the card toggle. Declared after the pill-wide
                // MouseArea, so it wins within the segment.
                MouseArea {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.right: root.lead && root.lead.dismiss
                                   ? dismissBtn.left : parent.right
                    cursorShape: Qt.PointingHandCursor
                    // Right-click mutes the mic on a call, so the machine has
                    // a mute key that does not need the app focused. On
                    // anything else it falls through to the pill's own menu.
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (mouse) => {
                        if (mouse.button === Qt.RightButton) {
                            if (leadSeg.isCall) IslandState.toggleCallMute();
                            else IslandState.open(IslandState.wxUrl);
                            return;
                        }
                        if (root.lead && root.lead.action) root.lead.action();
                        else IslandState.toggleTool("calendar", root.screenName);
                    }
                }

                // Ends a meeting that finished early. Only appears on hover —
                // a permanent × on the pill reads as "something is wrong" — and
                // sits outside the join action's hit area so a meeting is never
                // dismissed by a mis-aimed click on the link.
                Rectangle {
                    id: dismissBtn
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18; height: 18; radius: 9
                    visible: root.lead && root.lead.dismiss !== undefined
                    opacity: leadHover.hovered ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 140 } }
                    color: dismissHover.hovered ? Qt.alpha(root.theme.warn, 0.30)
                                                : Qt.alpha(root.theme.fg, 0.14)
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        text: "\u{f0156}"
                        color: dismissHover.hovered ? root.theme.warn
                                                    : Qt.alpha(root.theme.fg, 0.85)
                        font.family: root.theme.fontMono
                        font.pixelSize: 11
                    }

                    HoverHandler { id: dismissHover; cursorShape: Qt.PointingHandCursor }
                    MouseArea {
                        anchors.fill: parent
                        enabled: dismissBtn.opacity > 0.5
                        onClicked: if (root.lead && root.lead.dismiss) root.lead.dismiss()
                    }
                }
            }

            // ── reveal: UTC, left of the clock ────────────────────
            Item {
                id: utcSeg
                objectName: "utc"
                anchors.verticalCenter: parent.verticalCenter
                height: utcCol.implicitHeight
                clip: true
                visible: width > 0.5
                x: content.xOf("utc")
                Behavior on x { enabled: content.gliding && !content.jumped.utc; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                readonly property bool flip: content.side.utc !== 0
                readonly property bool shown:
                    content.has("utc") && !root.main && root.reveals("Utc")
                readonly property real want: shown ? utcCol.implicitWidth + 14 : 0
                width: want
                opacity: shown && !content.hiding.utc ? 1 : 0
                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                Column {
                    id: utcCol
                    x: utcSeg.flip ? 14 : parent.width - width - 14
                    spacing: 1

                    Text {
                        text: {
                            const u = new Date(clk.date.getTime());
                            return ("0" + u.getUTCHours()).slice(-2) + ":"
                                 + ("0" + u.getUTCMinutes()).slice(-2) + "Z";
                        }
                        color: Qt.alpha(root.theme.accent3, 0.85)
                        font.family: root.theme.fontMono
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: "UTC"
                        color: Qt.alpha(root.theme.muted, 0.8)
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(9)
                        font.weight: Font.DemiBold
                    }
                }
            }

            // ── main slot: the clock, or whatever has taken it ────
            Item {
                id: mainSlot
                anchors.verticalCenter: parent.verticalCenter
                x: content.xOf("main")
                Behavior on x { enabled: content.gliding; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                height: Math.max(clockCol.implicitHeight, mainCol.implicitHeight, lockRow.implicitHeight)
                width: root.lockAuth ? lockRow.implicitWidth
                     : root.main ? mainCol.implicitWidth : clockCol.implicitWidth
                Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                // ── password field (lock surface only) ────────────────
                // The island is the placeholder: a lock glyph and "Password"
                // at rest, one dot per character while typing, a spinner
                // while PAM checks, the error in place after a miss. The
                // layout badge shows only when it is not English, so a
                // password typed in Cyrillic is caught before it is sent.
                Row {
                    id: lockRow
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    spacing: 9
                    visible: root.lockAuth

                    Text {
                        id: lockGlyph
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.lockBusy ? "\u{f0772}" : "\u{f033e}"
                        color: root.lockErr !== "" ? root.theme.warn : root.theme.fg
                        font.family: root.theme.fontMono
                        font.pixelSize: 15
                        RotationAnimator on rotation {
                            running: root.lockBusy
                            from: 0; to: 360; duration: 900
                            loops: Animation.Infinite
                            onRunningChanged: if (!running) lockGlyph.rotation = 0
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        readonly property int n: root.lockBusy ? 0 : lockInput.text.length
                        text: root.lockBusy ? "Checking…"
                            : n > 0 ? "•".repeat(Math.min(n, 24))
                            : root.lockErr !== "" ? root.lockErr
                            : "Password"
                        color: root.lockErr !== "" && n === 0 && !root.lockBusy ? root.theme.warn
                             : n > 0 ? root.theme.fg
                             : Qt.alpha(root.theme.fg, 0.55)
                        font.family: n > 0 ? root.theme.fontMono : root.theme.fontSans
                        font.pixelSize: n > 0 ? 15 : IslandState.ts(14)
                        font.weight: n > 0 ? Font.Black : Font.Medium
                        font.letterSpacing: n > 0 ? 1.5 : 0
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.lockLayout !== "" && root.lockLayout !== "EN"
                        width: lockKb.implicitWidth + 12
                        height: 18
                        radius: 6
                        color: Qt.alpha(root.theme.warn, 0.22)
                        Text {
                            id: lockKb
                            anchors.centerIn: parent
                            text: root.lockLayout
                            color: root.theme.warn
                            font.family: root.theme.fontMono
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }
                    }

                }

                // Invisible in all but name: it owns focus and the text, the
                // row above draws it. Outside the Row so it adds no gap.
                TextInput {
                    id: lockInput
                    width: 1
                    height: 1
                    opacity: 0
                    readOnly: !root.lockAuth || root.lockBusy
                    echoMode: TextInput.Password
                    onAccepted: root.lockSubmitted()
                    // Esc puts away whatever the bar opened, then clears.
                    Keys.onEscapePressed: {
                        if (IslandState.cardOpen) IslandState.closeCard();
                        else text = "";
                    }
                }

                Column {
                    id: clockCol
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    spacing: 0
                    opacity: root.main || root.lockAuth ? 0 : 1
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                    // Seconds slide in as their own reveal rather than the format
                    // string flipping — swapping "h:mm AP" for "h:mm:ss AP" mid-morph
                    // snaps the width and fights the container animation.
                    //
                    // Centred rather than left-aligned: the date below is the wider
                    // of the two, so a left-aligned time hung off to one side of its
                    // own slot. Horizontal anchors are safe inside a Column — the
                    // positioner only manages y — and this holds through the seconds
                    // reveal, which changes this row's width mid-animation.
                    Row {
                        spacing: 0
                        anchors.horizontalCenter: parent.horizontalCenter
                        // Away while the clock is up in the card or on its
                        // way there; the flyer draws it in between.
                        opacity: root.clockAway ? 0 : 1

                        Text {
                            id: hhmm
                            text: IslandState.clockHours(clk.date)
                                  + ":" + ("0" + clk.date.getMinutes()).slice(-2)
                            // One text colour across the pill — the same the
                            // weather temperature uses. The accent is reserved
                            // for a calendar event's own tint and for warnings.
                            color: root.theme.fg
                            font.family: root.theme.fontClock
                            font.features: root.theme.clockFeatures
                            font.pixelSize: 17
                            font.weight: Font.Black
                        }
                        Item {
                            height: hhmm.height
                            clip: true
                            visible: width > 0.5
                            readonly property bool shown:
                                root.reveals("Seconds")
                            width: shown ? secs.implicitWidth : 0
                            opacity: shown ? 1 : 0
                            Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                            Text {
                                id: secs
                                anchors.left: parent.left
                                text: ":" + ("0" + clk.date.getSeconds()).slice(-2)
                                // Dimmed only while the pill is expanded; on the
                                // resting pill they read as part of the time.
                                color: root.expanded ? Qt.alpha(root.theme.fg, 0.65) : root.theme.fg
                                Behavior on color { ColorAnimation { duration: 200 } }
                                font.family: root.theme.fontClock
                                font.features: root.theme.clockFeatures
                                font.pixelSize: 17
                                font.weight: Font.Black
                            }
                        }
                        Text {
                            visible: !IslandState.cfg.clock24h
                            text: clk.date.getHours() < 12 ? " AM" : " PM"
                            color: root.theme.fg
                            font.family: root.theme.fontClock
                            font.features: root.theme.clockFeatures
                            font.pixelSize: 17
                            font.weight: Font.Black
                        }
                    }
                    // The date folds away as its own reveal, height rather
                    // than width, so the time settles to the pill's centre.
                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        readonly property bool shown: root.reveals("Date")
                        width: dateText.implicitWidth
                        height: shown ? dateText.implicitHeight : 0
                        clip: true
                        visible: height > 0.5
                        opacity: shown ? 1 : 0
                        Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        Text {
                            id: dateText
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            text: Qt.formatDateTime(clk.date, "ddd, dd/MM/yyyy")
                            color: Qt.alpha(root.theme.fg, 0.75)
                            font.family: root.theme.fontMono
                            font.pixelSize: 11
                            font.weight: Font.Bold
                        }
                    }
                }

                Row {
                    id: mainCol
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    spacing: 8
                    opacity: root.main ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                    // Avatar, when the activity ships one — a notification's
                    // sender photo or app icon. Track flashes carry no image
                    // and render exactly as before.
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.main !== null && (root.main.image || "") !== ""
                        width: 26; height: 26; radius: 9
                        color: Qt.alpha(root.theme.muted, 0.22)
                        clip: true

                        Image {
                            anchors.fill: parent
                            source: root.main && root.main.image ? root.main.image : ""
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: 52
                            sourceSize.height: 52
                            asynchronous: true
                            cache: false
                        }
                    }

                    // Glyph, when the activity names one and ships no image —
                    // the layout flash, the volume HUD.
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.main !== null && (root.main.glyph || "") !== ""
                                 && (root.main.image || "") === ""
                        text: root.main && root.main.glyph ? root.main.glyph : ""
                        color: root.main && root.main.style === "hud" ? root.mainColor : root.theme.primary
                        font.family: root.theme.fontMono
                        font.pixelSize: 16
                    }

                    // The HUD face: a level bar and its number, nothing to read.
                    Item {
                        id: hudBar
                        readonly property bool on: root.main !== null && root.main.style === "hud"
                        anchors.verticalCenter: parent.verticalCenter
                        visible: on
                        width: on ? 118 : 0
                        height: 6

                        Rectangle {
                            anchors.fill: parent
                            radius: 3
                            color: Qt.alpha(root.theme.fg, 0.14)
                        }
                        Rectangle {
                            height: parent.height
                            radius: 3
                            width: Math.max(height, parent.width
                                   * (hudBar.on && root.main.progress >= 0 ? root.main.progress : 0))
                            visible: hudBar.on && root.main.progress > 0
                            color: root.theme.fg
                            Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0

                        // Capped: a long track title would otherwise stretch the
                        // whole pill for the two and a half seconds it is up.
                        Text {
                            width: Math.min(implicitWidth, 260)
                            elide: Text.ElideRight
                            text: root.main ? root.main.title : ""
                            color: root.mainColor
                            font.family: root.theme.fontSans
                            font.pixelSize: IslandState.ts(15)
                            font.weight: Font.Normal
                        }
                        Text {
                            visible: text !== ""
                            width: Math.min(implicitWidth, 260)
                            elide: Text.ElideRight
                            text: root.main ? (root.main.sub || "") : ""
                            color: Qt.alpha(root.theme.muted, 0.95)
                            font.family: root.theme.fontMono
                            font.pixelSize: 10
                            font.weight: Font.Normal
                        }
                    }
                }
            }

            // ── status cluster, right of the clock ────────────────
            // The mirror of the workspace pills: the keyboard layout, then
            // whatever needs attention — privacy dots, the silent-mode moon,
            // an unread count. Each piece is its own toggle and each one but
            // the layout shows only while it has something to say.
            Item {
                id: statusZone
                objectName: "status"
                anchors.verticalCenter: parent.verticalCenter
                x: content.xOf("status")
                Behavior on x { enabled: content.gliding && !content.jumped.status; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                readonly property bool flip: content.side.status !== 1
                height: 20
                clip: true
                visible: width > 0.5
                readonly property bool layoutOn: IslandState.cfg.statusLayout && IslandState.layoutCode !== ""
                readonly property bool micOn: IslandState.cfg.statusPrivacy && IslandState.micInUse
                readonly property bool camOn: IslandState.cfg.statusPrivacy && IslandState.videoInUse
                readonly property bool moonOn: IslandState.cfg.statusDnd && IslandState.dnd
                readonly property bool unreadOn: IslandState.cfg.statusUnread && IslandState.unreadCount > 0 && !IslandState.dnd
                readonly property bool meetOn: IslandState.cfg.statusMeeting && IslandState.meeting !== null
                readonly property bool loadOn: IslandState.cfg.statusLoad && (IslandState.cpuLoad >= 0 || IslandState.gpuLoad >= 0)
                readonly property bool shown: content.has("status") && (layoutOn || micOn || camOn || moonOn || unreadOn || meetOn || loadOn)
                readonly property real want: shown ? statusRow.implicitWidth + (root.expanded ? 16 : 12) : 0
                width: want
                opacity: shown && !content.hiding.status ? 1 : 0
                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                Row {
                    id: statusRow
                    x: statusZone.flip ? 0 : parent.width - width
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 7

                    // Next meeting: a dot in the event's own colour and the
                    // countdown, "now" once it has started. Only inside the
                    // hour before, so most of the day it is simply absent.
                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: statusZone.meetOn
                        width: meetRow.implicitWidth
                        height: meetRow.implicitHeight

                        Row {
                            id: meetRow
                            spacing: 5

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 6; height: 6; radius: 3
                                color: IslandState.meeting && IslandState.meeting.color
                                       ? IslandState.meeting.color : root.theme.accent
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                readonly property int m: IslandState.meetingMins
                                text: m <= 0 ? "now"
                                    : m < 60 ? "in " + m + "m"
                                    : "in 1h"
                                color: m <= 5 ? root.theme.fg : Qt.alpha(root.theme.fg, 0.62)
                                font.family: root.theme.fontMono
                                font.pixelSize: 11
                                font.weight: Font.Black
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: IslandState.openMeeting()
                        }
                    }

                    // Load: two small rings with the number inside — CPU in the
                    // text colour, GPU in the accent, both turning to the warn
                    // tone from 85 %. Numbers rather than a graph: a graph
                    // moves all the time and pulls the eye.
                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: statusZone.loadOn
                        width: loadRow.implicitWidth
                        height: loadRow.implicitHeight

                        Row {
                            id: loadRow
                            spacing: 4

                            Repeater {
                                model: [
                                    { v: IslandState.cpuLoad, c: Qt.alpha(root.theme.fg, 0.75) },
                                    { v: IslandState.gpuLoad, c: root.theme.accent }
                                ]

                                Item {
                                    required property var modelData
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: modelData.v >= 0
                                    width: 22; height: 22
                                    readonly property color tone: modelData.v >= 0.85 ? root.theme.warn : modelData.c

                                    RingProgress {
                                        anchors.fill: parent
                                        progress: Math.max(0, parent.modelData.v)
                                        ring: parent.tone
                                        track: root.theme.fg
                                        trackAlpha: 0.12
                                        thickness: 2
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        text: Math.round(Math.max(0, parent.modelData.v) * 100)
                                        color: parent.tone
                                        font.family: root.theme.fontMono
                                        font.pixelSize: 8
                                        font.weight: Font.Black
                                    }
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: IslandState.toggleTool("monitor", root.screenName)
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: statusZone.layoutOn
                        text: IslandState.layoutCode
                        // The busy-pill grey: present, never loud.
                        color: Qt.alpha(root.theme.fg, 0.42)
                        font.family: root.theme.fontMono
                        font.pixelSize: 11
                        font.weight: Font.Black

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: IslandState.switchLayout()
                        }
                    }

                    // Privacy dots keep the platform's colours whatever the
                    // theme: orange is the mic and green the camera or screen
                    // everywhere, which is the whole point of them.
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: statusZone.micOn
                        width: 6; height: 6; radius: 3
                        color: "#ff9f0a"
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: statusZone.camOn
                        width: 6; height: 6; radius: 3
                        color: "#30d158"
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: statusZone.moonOn
                        text: "\u{f0f65}"
                        color: root.theme.accent3
                        font.family: root.theme.fontMono
                        font.pixelSize: 13
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: statusZone.unreadOn
                        height: 14
                        width: Math.max(height, unreadText.implicitWidth + 8)
                        radius: height / 2
                        color: root.theme.primary

                        Text {
                            id: unreadText
                            anchors.centerIn: parent
                            text: IslandState.unreadCount > 9 ? "9+" : IslandState.unreadCount
                            color: root.theme.on_primary
                            font.family: root.theme.fontMono
                            font.pixelSize: 9
                            font.weight: Font.Black
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: IslandState.toggleTool("notifs", root.screenName)
                        }
                    }
                }
            }

            // ── reveal: weather, right of the clock ───────────────
            // Rests hidden like the call and the workspaces; hover brings the
            // icon and temperature in ahead of the conditions reveal
            // below.
            Item {
                id: wxSeg
                objectName: "wx"
                anchors.verticalCenter: parent.verticalCenter
                x: content.xOf("wx")
                Behavior on x { enabled: content.gliding && !content.jumped.wx; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                readonly property bool flip: content.side.wx !== 1
                readonly property real want: shown ? natural : 0
                height: wxZone.implicitHeight
                clip: true
                visible: base > 0.5
                readonly property bool shown:
                    content.has("wx") && root.reveals("Weather")
                readonly property bool elastic: true
                readonly property real gain: content.grant("wx")
                readonly property real natural: 16 + wxIcon.implicitWidth + 8 + wxTemp.implicitWidth
                property real base: shown ? natural : 0
                readonly property real cap: natural > 0 ? 18 * base / natural : 0
                width: base + gain
                opacity: shown && !content.hiding.wx ? 1 : 0
                Behavior on base { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                Row {
                    id: wxZone
                    anchors.left: parent.left
                    spacing: 0
                    layoutDirection: wxSeg.flip ? Qt.RightToLeft : Qt.LeftToRight

                    Item { width: 16 + parent.parent.gain / 2; height: 1 }

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8 + parent.parent.gain / 2

                        Text {
                            id: wxIcon
                            anchors.verticalCenter: parent.verticalCenter
                            text: IslandState.wxIcon
                            color: root.theme.primary
                            font.family: root.theme.fontMono
                            font.pixelSize: 24
                        }
                        Text {
                            id: wxTemp
                            anchors.verticalCenter: parent.verticalCenter
                            text: IslandState.wxTemp + "°"
                            color: root.theme.fg
                            font.family: root.theme.fontClock
                            font.features: root.theme.clockFeatures
                            font.pixelSize: 17
                            font.weight: Font.Black
                        }
                    }
                }
            }

            // ── reveal: conditions, right of the weather ──────────
            // Hover only, even with weather always visible: the resting
            // pill keeps the short form (icon and temperature).
            Item {
                id: condSeg
                objectName: "cond"
                anchors.verticalCenter: parent.verticalCenter
                height: rightCol.implicitHeight
                clip: true
                visible: width > 0.5
                x: content.xOf("cond")
                Behavior on x { enabled: content.gliding && !content.jumped.cond; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                readonly property bool flip: content.side.cond !== 1
                readonly property bool shown:
                    content.has("cond") && root.expanded && root.reveals("Weather")
                readonly property real want: shown ? rightCol.implicitWidth + 14 : 0
                width: want
                opacity: shown && !content.hiding.cond ? 1 : 0
                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                Column {
                    id: rightCol
                    x: condSeg.flip ? 0 : 14
                    spacing: 2

                    Text {
                        text: {
                            let s = IslandState.wxArea;
                            if (IslandState.wxDesc !== "") s += (s !== "" ? "  ·  " : "") + IslandState.wxDesc;
                            if (IslandState.wxFeels !== "") s += "  ·  feels " + IslandState.wxFeels + "°";
                            return s;
                        }
                        color: root.theme.fg
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(11)
                        font.weight: Font.DemiBold
                    }
                    Row {
                        spacing: 10
                        Repeater {
                            model: [
                                { g: "\u{e373}", v: IslandState.wxHumidity !== "" ? IslandState.wxHumidity + "%" : "" },
                                { g: "\u{e34c}", v: IslandState.wxWind !== "" ? IslandState.wxWind + " km/h" : "" },
                                { g: "\u{f059a}", v: IslandState.wxSunset }
                            ]
                            Row {
                                required property var modelData
                                visible: modelData.v !== ""
                                spacing: 4
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.g
                                    color: Qt.alpha(root.theme.fg, 0.75)
                                    font.family: root.theme.fontMono
                                    font.pixelSize: 11
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.v
                                    color: root.theme.fg
                                    font.family: root.theme.fontMono
                                    font.pixelSize: 10
                                }
                            }
                        }
                    }
                }
            }

            // ── live canvas, far right ────────────────────────────
            // Two faces for two kinds of sound, after the phone: dancing bars
            // for a player, a mirrored waveform in the app's colour for a
            // call — the call shows at rest, so the collapsed island breathes
            // with the conversation the way the phone's does.
            Item {
                id: liveSeg
                objectName: "live"
                anchors.verticalCenter: parent.verticalCenter
                x: content.xOf("live")
                Behavior on x { enabled: content.gliding && !content.jumped.live; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                readonly property bool flip: content.side.live !== 1
                readonly property real want: shown ? faceW + 14 : 0
                height: 20
                clip: true
                visible: base > 0.5
                readonly property bool onCall: IslandState.inCall
                readonly property bool shown:
                    content.has("live") && IslandState.cfg.liveBars && (IslandState.wavAudible || onCall)
                readonly property real faceW: onCall ? 56 : 27
                readonly property bool elastic: true
                readonly property real gain: content.grant("live")
                property real base: shown ? faceW + 14 : 0
                readonly property real cap: 30 * base / (faceW + 14)
                width: base + gain
                opacity: shown && !content.hiding.live ? 1 : 0
                Behavior on base { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                MiniBars {
                    x: liveSeg.flip ? 0 : parent.width - width
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !parent.onCall
                    width: 27 + parent.gain; height: 18
                    vals: IslandState.wavVals
                    frame: IslandState.wavFrame
                    color: root.theme.primary
                }
                CallWave {
                    x: liveSeg.flip ? 0 : parent.width - width
                    anchors.verticalCenter: parent.verticalCenter
                    visible: parent.onCall
                    width: 56 + parent.gain; height: 18
                    them: IslandState.callThem
                    me: IslandState.callMe
                    frame: IslandState.wavFrame
                    // the two voices in two theme roles, so the split still
                    // reads at a glance on every monitor's theme
                    colorThem: root.theme.primary
                    colorMe: root.theme.tertiary
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: IslandState.toggleTool(parent.onCall ? "call" : "media", root.screenName)
                }
            }

        }

        // How far through the lead activity we are. Tracks its segment rather
        // than the whole pill, so it never runs under the clock or the date, and
        // sits inside the rounded corner without needing a clip.
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 3
            x: content.x + leadSeg.x + 2
            width: Math.max(0, leadSeg.width - 16)
            height: 2
            radius: 1
            color: Qt.alpha(root.theme.fg, 0.10)
            visible: root.lead !== null && root.lead.progress >= 0

            Rectangle {
                anchors.left: parent.left
                height: parent.height
                radius: parent.radius
                width: parent.width * (root.lead && root.lead.progress >= 0 ? root.lead.progress : 0)
                color: root.lead ? Qt.alpha(root.leadColor, 0.85) : "transparent"
            }
        }
    }

    // ── track progress hairline ───────────────────────────────────
    // Rides the lower edge of whatever the shape is — the pill on the island,
    // the whole silhouette in the notch — inset past the rounded corners.
    Item {
        id: progressLine
        readonly property real inset: root.notch ? IslandState.cfg.notchRadius + 4 : pill.height / 2
        readonly property real x0: root.notch ? root.notchLeft : pill.x
        readonly property real span: root.notch ? root.notchBodyWidth : pill.width
        // Off whenever the date is on the pill — on hover, or at rest with
        // "date always visible": it runs along the same lower edge and the
        // hairline would strike through it. A main-slot activity hides the
        // date, so the line comes back for a track flash or the HUD.
        readonly property bool dateUp: root.reveals("Date") && !root.main
        // With the menu bar on, the line lives under the bar's track item.
        readonly property bool wanted: IslandState.cfg.progressLine && IslandState.trackProgress >= 0
                                       && !root.barMode
                                       && !root.cardHere && !dateUp
        visible: opacity > 0.01
        opacity: wanted ? 1 : 0
        x: x0 + inset
        y: pill.y + pill.height - (root.notch ? 3 : 4)
        width: Math.max(0, span - inset * 2)
        height: 2
        Behavior on opacity { NumberAnimation { duration: 160 } }

        Rectangle {
            anchors.fill: parent
            radius: 1
            color: Qt.alpha(root.theme.fg, 0.10)
        }
        // The glide lives on the progress, never on the width: animating the
        // width also eased every hover resize of the pill over a whole second,
        // so the fill lagged behind its own track. Now the fill follows the
        // track's geometry instantly and only the position glides — linearly,
        // across the one-second poll, so it reads as continuous playback. A
        // jump (seek, new track) lands at once instead of sweeping.
        property real shown: Math.max(0, IslandState.trackProgress)
        Connections {
            target: IslandState
            function onTrackProgressChanged() {
                const next = Math.max(0, IslandState.trackProgress);
                glide.stop();
                if (Math.abs(next - progressLine.shown) > 0.03) {
                    progressLine.shown = next;
                } else {
                    glide.to = next;
                    glide.start();
                }
            }
        }
        NumberAnimation {
            id: glide
            target: progressLine
            property: "shown"
            duration: 1000
            easing.type: Easing.Linear
        }

        Rectangle {
            height: parent.height
            radius: 1
            width: parent.width * progressLine.shown
            color: Qt.alpha(root.theme.accent, 0.9)
        }
    }

    // ── trail slot ────────────────────────────────────────────────
    // Detached on purpose: it is a second surface, not a segment, so the main
    // slot can keep changing underneath it without disturbing it.
    Rectangle {
        id: trailCap

        // statusSlot is zero-width while the status circle is off, so this is
        // the old pill.right anchor whenever the circle is away.
        anchors.left: statusSlot.right
        anchors.leftMargin: 8
        anchors.verticalCenter: pill.verticalCenter

        visible: root.trail !== null
        implicitHeight: root.expanded ? 34 : 30
        // In the notch it is a wing of the silhouette like the side circles,
        // not a capsule parked inside it: no fill, no border, and so none of
        // the padding a capsule needs around its content.
        implicitWidth: trailRow.implicitWidth + (root.notch ? 6 : 20)
        height: implicitHeight
        width: implicitWidth
        radius: height / 2

        // An activity may ask to be looked at — a finished timer is the first,
        // but nothing here knows that. The capsule breathes for as long as the
        // flag is up, which is until the thing is acknowledged, not until its
        // sound stops.
        readonly property bool alerting: root.trail !== null && root.trail.alert === true
        // Driven by the animation below rather than bound, so the border and
        // scale can stay ordinary bindings that read it. Animating border.color
        // directly would overwrite its binding for good the first time it ran.
        property real alertPulse: 0

        // Same fill and opacity as the pill it sits beside — it is a detached
        // piece of the island, not a bar widget, so it should not read as a
        // lighter material parked next to one.
        color: root.pieceFill
        // The notch has no outline to breathe, so there the alert pulses the
        // content instead: a larger swell and the title taking the tone.
        border.width: root.notch ? 0 : 1 + trailCap.alertPulse
        border.color: root.trail
            ? Qt.alpha(root.trailColor, 0.45 + 0.55 * trailCap.alertPulse)
            : Qt.alpha(root.theme.accent, 0.06)
        scale: 1 + (root.notch ? 0.09 : 0.045) * trailCap.alertPulse
                 + (root.notch && trailHov.hovered ? 0.06 : 0)

        Behavior on implicitHeight { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 220 } }

        // alwaysRunToEnd so acknowledging mid-breath settles rather than
        // snapping back a frame later; onStopped clears the value the loop was
        // left holding.
        SequentialAnimation {
            running: trailCap.alerting
            loops: Animation.Infinite
            alwaysRunToEnd: true
            onStopped: trailCap.alertPulse = 0
            NumberAnimation {
                target: trailCap; property: "alertPulse"
                from: 0; to: 1; duration: 460; easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: trailCap; property: "alertPulse"
                from: 1; to: 0; duration: 640; easing.type: Easing.InOutCubic
            }
        }

        Row {
            id: trailRow
            anchors.centerIn: parent
            spacing: 7

            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: 18; height: 18

                RingProgress {
                    anchors.fill: parent
                    progress: root.trail && root.trail.progress >= 0 ? root.trail.progress : 0
                    ring: root.trailColor
                    track: root.theme.fg
                }
                Text {
                    anchors.centerIn: parent
                    text: root.trail ? (root.trail.glyph || "") : ""
                    color: root.trailColor
                    font.family: root.theme.fontMono
                    font.pixelSize: 9
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.trail ? root.trail.title : ""
                color: root.notch && trailCap.alerting
                    ? Qt.tint(root.theme.fg, Qt.alpha(root.trailColor, trailCap.alertPulse))
                    : root.theme.fg
                font.family: root.theme.fontMono
                font.pixelSize: 12
                font.weight: Font.Bold
            }
        }

        HoverHandler { id: trailHov; cursorShape: Qt.PointingHandCursor }
        MouseArea {
            anchors.fill: parent
            // Right-click is the capsule's clear: on the timer it resets,
            // which is the one thing you otherwise have to open the card for.
            // An activity without a secondary action simply ignores it rather
            // than falling through to the left-click one — a right-click that
            // did what a left-click does is how you delete something you meant
            // to look at.
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (mouse) => {
                if (mouse.button === Qt.RightButton) {
                    if (root.trail && root.trail.secondary) root.trail.secondary();
                    return;
                }
                if (root.trail && root.trail.action) root.trail.action();
                else IslandState.toggleTool("timer", root.screenName);
            }
        }
    }

    IslandCard {
        id: card
        // On the lock screen the card is drawn inside the lock surface
        // (cardHost below); the desktop island's card stays shut meanwhile.
        suppressed: !root.lockMode && IslandState.locked
        inSurface: root.lockMode
        surfaceHost: cardHost
        theme: root.theme
        screenName: root.screenName
        anchor.item: root
        // The card pads its top by padTop for the drop shadow; subtracting it
        // here keeps the visible gap between pill and card at 12px.
        // The notch's card starts as the notch itself, over it, flush with
        // the screen edge, and grows down and out from there.
        anchor.rect.y: root.notch ? 0 : pill.height + IslandState.cfg.cardGap - card.padTop
        pillWidth: root.notch ? root.notchBodyWidth : pill.width
        pillHeight: pill.height
        anchor.rect.x: (root.width - card.implicitWidth) / 2
        clockLanded: !root.flightOn && !root.flightPending
        onComposeRequested: (iso) => composer.open(iso, card.calendars)
    }

    // ── clock flight ──────────────────────────────────────────────
    // Opening the hub carries the pill's clock into the card header instead
    // of fading one out and the other in; closing flies it back. flight is
    // where the clock is: 0 in the pill, 1 in the card. The pill and the card
    // are separate surfaces, so the clock travels on a third, input-less one
    // laid over both, and both ends are re-measured every frame — the pill
    // is still resizing while the clock is in the air.
    property real flight: 0
    property bool flightOn: false
    // A hair past zero, so the pill keeps its clock for the frame or two
    // the flyer surface needs to show up — the two overlap exactly there.
    readonly property bool clockAway: root.flight > 0.05 && !card.faceUp

    function canFly() {
        return !root.lockMode && IslandState.cfg.morph && !root.main && !card.faceUp
               && clockCol.visible && clockCol.opacity > 0.5;
    }
    function landFlight(v) {
        flightAnim.stop();
        takeoff.stop();
        root.flight = v;
        root.flightOn = false;
        root.flightPending = false;
        if (v <= 0) unmapFlyer.restart();
    }
    // The flyer surface is mapped just before a flight and unmapped a little
    // after it lands, with nothing drawn on it either time: Hyprland fades a
    // popup in on map and out on unmap, and a fade that carried the clock
    // left a ghost of it beside the pill. Mapping after the card is also what
    // keeps the flyer stacked above the card rather than under it.
    property bool flyerUp: false
    property bool flightPending: false
    Timer { id: unmapFlyer; interval: 450; onTriggered: if (!root.flightOn) root.flyerUp = false }
    Timer {
        id: takeoff
        interval: 110
        onTriggered: {
            root.flightPending = false;
            root.flightOn = true;
            flightAnim.start();
        }
    }
    function startFlight(open) {
        flightAnim.stop();
        takeoff.stop();
        unmapFlyer.stop();
        if (open) {
            if (!root.canFly()) { root.landFlight(0); return; }
            flightAnim.from = root.flight;
            flightAnim.to = 1;
            flightAnim.duration = IslandState.cfg.morphMs * 1.15;
            root.flyerUp = true;
            root.flightPending = true;
            takeoff.restart();
            return;
        }
        if (root.flight <= 0 || root.main || !IslandState.cfg.morph) { root.landFlight(0); return; }
        flightAnim.from = root.flight;
        flightAnim.to = 0;
        flightAnim.duration = 340;
        root.flyerUp = true;
        root.flightOn = true;
        flightAnim.start();
    }
    Timer { id: flyerRefocus; interval: 60; onTriggered: card.refocusGrab() }
    NumberAnimation {
        id: flightAnim
        target: root
        property: "flight"
        easing.type: Easing.Linear
        // Unmapped after landing either way, not kept up while the card is
        // open: a popup of the bar that is not in the card's focus grab
        // took the keyboard, and Esc stopped closing the card.
        onFinished: {
            root.flightOn = false;
            unmapFlyer.restart();
        }
    }
    Connections {
        target: card
        // Deferred a tick: the tool and the open flag can change together,
        // and whether this is the hub or a face is only settled after both.
        function onOpenHereChanged() { const o = card.openHere; Qt.callLater(() => root.startFlight(o)); }
        function onFaceUpChanged() { if (card.faceUp) root.landFlight(0); }
    }

    PopupWindow {
        id: flyer
        anchor.item: root
        anchor.rect.x: card.anchor.rect.x
        anchor.rect.y: 0
        implicitWidth: card.implicitWidth
        implicitHeight: card.anchor.rect.y + card.padTop + card.headerHeight + 8
        color: "transparent"
        visible: root.flyerUp
        mask: Region {}
        // Mapping or unmapping this surface moves Hyprland's keyboard focus
        // off the card; hand it back each time, once the change has landed.
        onVisibleChanged: if (card.visible) flyerRefocus.restart()

        function ease(t) { return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2; }
        function easeOut(t) { return 1 - Math.pow(1 - t, 3); }
        function lerp(a, b, t) { return a + (b - a) * t; }
        function pillPt() {
            const q = hhmm.mapToItem(root, 0, 0);
            return Qt.point(q.x - card.anchor.rect.x, q.y);
        }
        function cardPt() {
            const q = card.clockPos();
            return Qt.point(q.x, q.y + card.anchor.rect.y);
        }

        Text {
            id: flyText
            visible: root.flightOn
            // x leads and y trails, so the clock arcs down into the card
            // rather than sliding along a ruler-straight diagonal.
            readonly property real ex: flyer.easeOut(root.flight)
            readonly property real ey: flyer.ease(root.flight)
            x: flyer.lerp(flyer.pillPt().x, flyer.cardPt().x, ex)
            y: flyer.lerp(flyer.pillPt().y, flyer.cardPt().y, ey)
            transformOrigin: Item.TopLeft
            scale: flyer.lerp(hhmm.font.pixelSize / card.clockPx, 1, ey)
            text: card.clockText
            color: root.theme.fg
            font.family: root.theme.fontClock
            font.features: root.theme.clockFeatures
            font.pixelSize: card.clockPx
            font.weight: Font.Black
        }
    }

    // On the lock surface every click action of the pieces above is off:
    // this shield sits over all of them, takes the click and hands focus
    // back to the password field.
    MouseArea {
        x: Math.min(0, root.notchLeft - notchShape.e)
        width: Math.max(root.width, notchShape.width)
        height: Math.max(root.height, notchShape.height)
        visible: root.lockMode
        z: 1000
        acceptedButtons: Qt.AllButtons
        onPressed: if (root.lockAuth) lockInput.forceActiveFocus()
    }

    // Where the card's window would be, on the lock surface.
    Item {
        id: cardHost
        x: card.anchor.rect.x
        y: card.anchor.rect.y
        z: 1001
        width: card.implicitWidth
        height: card.implicitHeight
        visible: root.lockMode && card.live
    }

    EventComposer {
        id: composer
        theme: root.theme
        onCreated: card.refresh()
    }
}
