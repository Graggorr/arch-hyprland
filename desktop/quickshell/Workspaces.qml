import QtQuick
import QtQuick.Effects
import Quickshell.Hyprland

// The workspace strip. A segment of the island now, not a pill of its own, so
// it carries no background — the island's surface is underneath it.
//
// Two densities of the same data. Collapsed it is a row of dots that still
// reports focus and occupancy; expanded it becomes the icon buttons. The morph
// is the island's own idiom (animate width, cross-fade the contents), which is
// what lets the strip grow with the pill instead of on top of it.
Item {
    id: root

    property var theme
    property string screenName: ""
    // Driven by the island's `expanded`. Compact is the resting state.
    property bool compact: true
    // Width the island grants this strip beyond its natural size, spread
    // evenly over the slots so the strip fills its half of the pill.
    property real extra: 0

    // Every id here has an `icons` entry and every `icons` entry is here —
    // the two lists are kept in lockstep on purpose. A glyph with no slot is
    // dead weight, and a slot with no glyph falls through to the circle_small
    // dot, which is what made the old trailing ids (9-12 / 19-22) ~144px of
    // decorative nothing per monitor.
    // Monitor n (left to right, from 0) owns workspaces n*10+1 .. n*10+10,
    // the same ranges SUPER+N switches in hypr/binds.lua.
    readonly property var ids: {
        const base = IslandState.screenRank(screenName) * 10;
        return [1, 2, 3, 4, 5, 6].map(i => base + i);
    }

    // Material Design outlines for the generic workspaces, solid brand marks
    // where the workspace *is* one app (Steam, Docker, Discord). Outlines
    // read lighter at 17px over the blurred pill than the filled MDI set that
    // was here before, and the two sets separate "a kind of work" from "this
    // program" at a glance.
    //
    // `s` is a per-glyph pixelSize, not a constant, because these marks do not
    // share an ink box: at pixelSize 17 the drawn extents run from 12.8px
    // (view_grid_outline) to 18.1px (the Discord logo), so a single size makes
    // the row visibly ragged. Each `s` is solved so the glyph's larger ink
    // dimension lands on ~14.5px, which is what makes them look equal-sized.
    // Re-measure before changing a glyph — the codepoint alone tells you
    // nothing about how big it draws.
    readonly property var icons: ({
        "1":  { g: "\u{f059f}", s: 17 },  // md-web                        browser
        "2":  { g: "\u{f05c0}", s: 17 },  // md-xml (</>)                  coding
        "3":  { g: "\u{f0169}", s: 19 },  // md-code_array ({ })           coding, second slot
        "4":  { g: "\u{f1bc}",  s: 16 },  // fa-spotify                    the classic mark
        "5":  { g: "\u{f11d9}", s: 19 },  // md-view_grid_outline          keeper
        "6":  { g: "\u{f04d3}", s: 17 },  // md-steam
        "11": { g: "\u{f12ca}", s: 17 },  // md-chat_processing_outline    telegram + slack
        "12": { g: "\u{f1ff}",  s: 14 },  // fa-discord                    the classic mark
        "13": { g: "\u{f167a}", s: 16 },  // md-robot_outline              obsidian + claude
        //    14 is Ghostty  see ghosttyIds
        "15": { g: "\u{f062f}", s: 18 },  // md-webhook                    bruno / postman
        "16": { g: "\u{f0868}", s: 17 }   // md-docker                     docker desktop + k9s
    })

    // One ghostty window now: the startup terminal on the Terminal workspace.
    readonly property var ghosttyIds: [14]

    // GhosttyIcon's `size` *is* its ink box (the path fills its 10-unit square
    // exactly), so this is the raw 14.5px target rather than a font size.
    readonly property real ghosttySize: 14.5 * root.iconScale

    // Per-slot gap is baked into the slot width, and the Row runs at spacing 0,
    // for the reason the island's own content Row documents: a Row drops an
    // item's spacing along with the item, so animated spacing snaps at the end
    // of the morph instead of easing out with it.
    readonly property real slotCompact: 9
    // The menu bar draws the icon form smaller; 1 is the island's size.
    property real iconScale: 1
    readonly property real slotWide: Math.round(36 * root.iconScale)
    // Only the compact/wide switch animates. `extra` arrives already eased —
    // the island derives it from its own animating widths every frame — so a
    // Behavior on the slot width would restart on each of those frames and
    // chase the target, filling the strip in only after the pill had grown.
    property real slot: compact ? slotCompact : slotWide
    Behavior on slot { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

    implicitWidth: ws.implicitWidth
    implicitHeight: 26

    function state(id) {
        const all = Hyprland.workspaces.values;
        for (let i = 0; i < all.length; i++)
            if (all[i].id === id)
                return { focused: all[i].focused, active: all[i].active,
                         busy: all[i].toplevels.values.length > 0 };
        return { focused: false, active: false, busy: false };
    }

    Row {
        id: ws
        anchors.centerIn: parent
        spacing: 0

        Repeater {
            model: root.ids

            Item {
                id: slot
                required property var modelData
                readonly property var st: root.state(modelData)

                readonly property color iconColor: st.focused ? root.theme.accent
                    : ((st.busy || st.active) ? root.theme.fg
                    : Qt.alpha(root.theme.muted, 0.45))
                readonly property bool isGhostty: root.ghosttyIds.indexOf(modelData) !== -1
                readonly property var ico: root.icons[String(modelData)]

                width: root.slot + root.extra / root.ids.length
                height: 26
                clip: true

                // The hit target, and the only thing that carries focus/hover
                // fill. Kept at its full size and faded rather than resized, so
                // it never has to animate its own radius.
                Rectangle {
                    anchors.centerIn: parent
                    width: root.slotWide - 2; height: Math.round(26 * root.iconScale); radius: 8 * root.iconScale
                    opacity: root.compact ? 0 : 1
                    color: slot.st.focused ? Qt.alpha(root.theme.accent, 0.15)
                         : (hov.hovered ? Qt.alpha(root.theme.accent, 0.25)
                         : (slot.st.active ? Qt.alpha(root.theme.fg, 0.07) : "transparent"))
                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 130 } }
                }

                // Collapsed form: a row of upright pills, the page-indicator
                // look. The active slot is the tall one, so position reads at
                // this density; occupied slots sit brighter than empty ones.
                //
                // Shape tracks `active`, colour tracks `focused`. They are not
                // the same flag: one workspace on the machine is focused, but
                // each monitor has one active. Keying the shape to focus left
                // the unfocused monitor's strip a row of identical dots, with
                // nothing saying where you are on it.
                Item {
                    id: dot
                    anchors.centerIn: parent
                    width: slot.st.active ? 6 : 4
                    height: slot.st.active ? 11 : 7
                    opacity: root.compact ? 1 : 0
                    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                    readonly property color tone: slot.st.focused ? root.theme.accent
                        : slot.st.active ? root.theme.fg
                        : slot.st.busy ? Qt.alpha(root.theme.fg, 0.38)
                        : Qt.alpha(root.theme.fg, 0.14)

                    // The focused pill glows in its own colour — the soft halo
                    // that makes it read as lit rather than painted.
                    RectangularShadow {
                        anchors.fill: parent
                        radius: width / 2
                        blur: 6
                        spread: 0
                        color: Qt.alpha(root.theme.accent, 0.55)
                        opacity: slot.st.focused ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: dot.tone
                        Behavior on color { ColorAnimation { duration: 130 } }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: !slot.isGhostty
                    text: slot.ico !== undefined ? slot.ico.g : "\u{f09df}"  // md-circle_small
                    font.family: root.theme.fontMono
                    font.pixelSize: Math.round((slot.ico !== undefined ? slot.ico.s : 17) * root.iconScale)
                    color: slot.iconColor
                    opacity: root.compact ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 130 } }
                }

                GhosttyIcon {
                    anchors.centerIn: parent
                    visible: slot.isGhostty
                    size: root.ghosttySize
                    color: slot.iconColor
                    opacity: root.compact ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }

                HoverHandler { id: hov }

                // Declared inside the segment, so it wins over the pill-wide
                // MouseArea that would otherwise toggle the card.
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = " + slot.modelData + " })")
                }
            }
        }
    }
}
