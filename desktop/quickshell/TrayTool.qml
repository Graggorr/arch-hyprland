import QtQuick
import Quickshell
import Quickshell.Widgets

// The system tray, moved off the bar. Items on the left, the selected item's
// menu rendered on the right — inline, inside the card, not as its own window.
//
// That is the whole reason this shape works. TrayMenu was a PopupWindow with
// its own HyprlandFocusGrab, and a second grab taken while the card is up
// clears the card's, which closes the card and destroys the tool that opened
// the menu. Rendering the menu as part of the tool means no second grab exists.
//
// It also buys something the popup never had: submenus are navigable. blueman
// hangs a submenu off every paired device, and the popup could only draw a
// chevron next to them.
Item {
    id: root

    property var theme

    readonly property real preferredHeight: 480

    readonly property var items: IslandState.trayItems

    property string selectedId: ""
    // Handles from the item's root menu down to whichever submenu is open.
    property var menuStack: []

    readonly property var selected: {
        for (let i = 0; i < root.items.length; i++)
            if (root.items[i].id === root.selectedId) return root.items[i];
        return root.items.length > 0 ? root.items[0] : null;
    }

    // IslandCard routes Esc here first when this is true, so Esc pops one
    // submenu rather than closing the whole card.
    readonly property bool detailOpen: root.menuStack.length > 1
    function closeDetail() {
        if (root.menuStack.length > 1)
            root.menuStack = root.menuStack.slice(0, root.menuStack.length - 1);
    }

    function select(item) {
        root.selectedId = item.id;
        root.menuStack = item.menu ? [item.menu] : [];
    }
    function pushMenu(handle) {
        if (root.menuStack.length === 0) return;
        root.menuStack = [root.menuStack[0], handle];
    }

    function reload() {
        // The top-bar tray opens this tool on a right-click and names the
        // item it was clicked on; that wins over whatever was selected last.
        if (IslandState.traySelect !== "") {
            for (let i = 0; i < root.items.length; i++)
                if (root.items[i].id === IslandState.traySelect) { root.select(root.items[i]); break; }
            IslandState.traySelect = "";
        }
        if (root.selectedId === "" && root.items.length > 0) root.select(root.items[0]);
    }
    Component.onCompleted: root.reload()
    Connections {
        target: IslandState
        function onTraySelectChanged() { if (IslandState.traySelect !== "") root.reload(); }
    }

    // Two openers, one per level, and the root one stays attached even while a
    // submenu is showing. A single opener repointed at the submenu returns
    // nothing: DBusMenu loads children lazily and the parent menu closing
    // invalidates them, so the level above has to be held open underneath.
    // Two levels is the real depth here — blueman's per-device menus and
    // Chrome's profile menu — and nothing deeper is offered.
    QsMenuOpener {
        id: rootOpener
        menu: root.menuStack.length > 0 ? root.menuStack[0] : null
    }
    QsMenuOpener {
        id: subOpener
        menu: root.menuStack.length > 1 ? root.menuStack[1] : null
    }
    readonly property var entries: {
        const o = root.menuStack.length > 1 ? subOpener : rootOpener;
        return o.children ? o.children.values : [];
    }

    // ── menu icon resolution (carried over from TrayMenu) ─────────
    readonly property var glyphs: ({
        "bluetooth":              "\u{f00af}",
        "bluetooth-disabled":     "\u{f00b2}",
        "bluetooth-active":       "\u{f00b1}",
        "blueman-send":           "\u{f048a}",
        "edit-find":              "\u{f0349}",
        "document-open-recent":   "\u{f02da}",
        "document-properties":    "\u{f0493}",
        "application-x-addon":    "\u{f0431}",
        "application-exit":       "\u{f0206}",
        "help-about":             "\u{f0625}",
        "audio-headphones":       "\u{f02cb}",
        "audio-headset":          "\u{f02ce}",
        "audio-speakers":         "\u{f04c3}",
        "audio-card":             "\u{f04c3}",
        "input-gaming":           "\u{f0297}",
        "input-keyboard":         "\u{f030c}",
        "input-mouse":            "\u{f037d}",
        "phone":                  "\u{f011c}",
        "computer":               "\u{f0322}",
        "video-display":          "\u{f0379}",
        "printer":                "\u{f042a}"
    })

    function iconName(url) {
        if (!url || url.indexOf("image://icon/") !== 0) return "";
        return url.substring(13).split("?")[0];
    }
    // -symbolic is dropped for the glyph lookup only. It must not be dropped
    // before asking the theme, because hicolor ships blueman-send-symbolic and
    // nothing called blueman-send.
    function glyphFor(url) {
        const g = root.glyphs[root.iconName(url).replace(/-symbolic$/, "")];
        return g === undefined ? "" : g;
    }
    function showsIcon(url) {
        if (!url) return false;
        if (url.indexOf("image://icon/") !== 0) return true;
        return Quickshell.hasThemeIcon(root.iconName(url));
    }

    Row {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 14

        // ── items ─────────────────────────────────────────────────
        Column {
            id: leftCol
            width: 230
            height: parent.height
            spacing: 8

            Item {
                width: parent.width
                height: 16
                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Tray"
                    color: Qt.alpha(root.theme.on_surface_variant, 0.9)
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(11)
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.2
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.items.length + " items"
                    color: Qt.alpha(root.theme.muted, 0.9)
                    font.family: root.theme.fontMono
                    font.pixelSize: 9
                }
            }

            Item {
                visible: root.items.length === 0
                width: parent.width
                height: 140
                EmptyState {
                    anchors.centerIn: parent
                    theme: root.theme
                    maxWidth: parent.width - 20
                    glyph: "\u{f0e1e}"
                    title: "Tray is empty"
                    sub: "Apps that use a tray icon show up here"
                }
            }

            Flickable {
                id: itemFlick
                width: parent.width
                height: leftCol.height - 24
                contentHeight: itemCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                ScrollBar { flick: itemFlick; theme: root.theme }

                Column {
                    id: itemCol
                    width: parent.width
                    spacing: 3

                    Repeater {
                        model: root.items

                        Rectangle {
                            id: entry
                            required property var modelData
                            readonly property string glyph: TrayIcons.nativeGlyph(modelData.id)
                            readonly property bool current: root.selected === modelData

                            width: itemCol.width
                            height: 36
                            radius: 10
                            color: current ? Qt.alpha(root.theme.accent, 0.18)
                                 : (eh.hovered ? Qt.alpha(root.theme.fg, 0.12)
                                               : Qt.alpha(root.theme.fg, 0.05))
                            Behavior on color { ColorAnimation { duration: 120 } }

                            IconImage {
                                id: ico
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18; height: 18
                                source: entry.modelData.icon
                                visible: entry.glyph === ""
                                asynchronous: true
                            }
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18
                                horizontalAlignment: Text.AlignHCenter
                                visible: entry.glyph !== ""
                                text: entry.glyph
                                color: TrayIcons.nativeColor(entry.modelData.id)
                                font.family: root.theme.fontMono
                                font.pixelSize: 16
                                Behavior on color { ColorAnimation { duration: 180 } }
                            }

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 38
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                text: TrayIcons.displayName(entry.modelData)
                                color: entry.current ? root.theme.accent : root.theme.fg
                                font.family: root.theme.fontSans
                                font.pixelSize: IslandState.ts(11)
                                font.weight: entry.current ? Font.DemiBold : Font.Normal
                            }

                            HoverHandler { id: eh; cursorShape: Qt.PointingHandCursor }
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                onClicked: (e) => {
                                    if (e.button === Qt.MiddleButton)
                                        entry.modelData.secondaryActivate();
                                    else root.select(entry.modelData);
                                }
                            }
                        }
                    }
                }
            }
        }


        // ── selected item ─────────────────────────────────────────
        Column {
            id: rightCol
            width: parent.width - leftCol.width - 1 - 28
            height: parent.height
            spacing: 8

            Item {
                width: parent.width
                height: 34
                visible: root.selected !== null

                Column {
                    anchors.left: parent.left
                    anchors.right: openBtn.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: TrayIcons.displayName(root.selected)
                        color: root.theme.fg
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(12)
                        font.weight: Font.DemiBold
                    }
                    // The tooltip, which for several apps is live status rather
                    // than a name — "You have unread messages", "Bluetooth
                    // Active". Hidden when empty rather than falling back to
                    // the id, which is the string this pane exists to stop
                    // showing.
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        visible: text !== ""
                        text: root.selected && root.selected.tooltipTitle
                              ? root.selected.tooltipTitle : ""
                        color: Qt.alpha(root.theme.muted, 0.9)
                        font.family: root.theme.fontMono
                        font.pixelSize: 9
                    }
                }

                // Activating raises the app, which takes focus and therefore
                // closes the card. That is the right outcome — you asked for
                // the app — but it is why this is a button and not a row click.
                Rectangle {
                    id: openBtn
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 58; height: 28
                    radius: 9
                    visible: root.selected !== null && !root.selected.onlyMenu
                    color: obh.hovered ? Qt.alpha(root.theme.accent, 0.32)
                                       : Qt.alpha(root.theme.fg, 0.14)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text {
                        anchors.centerIn: parent
                        text: "Open"
                        color: root.theme.fg
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(10)
                        font.weight: Font.DemiBold
                    }
                    HoverHandler { id: obh; cursorShape: Qt.PointingHandCursor }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: if (root.selected) root.selected.activate()
                    }
                }
            }

            // Back row for a submenu — the popup this replaced could only draw
            // a chevron next to these and go no further.
            Rectangle {
                width: parent.width
                height: root.detailOpen ? 26 : 0
                visible: height > 0
                radius: 8
                color: bh.hovered ? Qt.alpha(root.theme.fg, 0.14) : Qt.alpha(root.theme.fg, 0.06)
                Behavior on height { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{f0141}  back"
                    color: root.theme.accent
                    font.family: root.theme.fontMono
                    font.pixelSize: 10
                }
                HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
                MouseArea { anchors.fill: parent; onClicked: root.closeDetail() }
            }

            Text {
                visible: root.selected !== null && root.entries.length === 0
                text: "This item has no menu"
                color: Qt.alpha(root.theme.muted, 0.7)
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(11)
            }

            Flickable {
                id: menuFlick
                width: parent.width
                height: rightCol.height - 42 - (root.detailOpen ? 34 : 0)
                contentHeight: menuCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                ScrollBar { flick: menuFlick; theme: root.theme }

                Column {
                    id: menuCol
                    width: parent.width
                    spacing: 1

                    Repeater {
                        model: root.entries

                        Item {
                            id: mrow
                            required property var modelData
                            readonly property string glyph: root.glyphFor(modelData.icon)
                            readonly property bool hasIcon:
                                glyph !== "" || root.showsIcon(modelData.icon)

                            width: menuCol.width
                            height: modelData.isSeparator ? 9 : 28

                            Rectangle {
                                visible: mrow.modelData.isSeparator
                                anchors.centerIn: parent
                                width: parent.width - 12
                                height: 1
                                color: Qt.alpha(root.theme.muted, 0.25)
                            }

                            Rectangle {
                                visible: !mrow.modelData.isSeparator
                                anchors.fill: parent
                                radius: 7
                                color: mh.hovered && mrow.modelData.enabled
                                       ? Qt.alpha(root.theme.accent, 0.18) : "transparent"
                                Behavior on color { ColorAnimation { duration: 110 } }

                                Row {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 8

                                    IconImage {
                                        width: 15; height: 15
                                        anchors.verticalCenter: parent.verticalCenter
                                        source: mrow.modelData.icon
                                        visible: mrow.hasIcon && mrow.glyph === ""
                                        asynchronous: true
                                    }
                                    Text {
                                        width: 15
                                        horizontalAlignment: Text.AlignHCenter
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: mrow.glyph !== ""
                                        text: mrow.glyph
                                        color: mrow.modelData.enabled
                                               ? Qt.alpha(root.theme.fg, 0.85)
                                               : Qt.alpha(root.theme.muted, 0.5)
                                        font.family: root.theme.fontMono
                                        font.pixelSize: 13
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: menuCol.width - 34 - (mrow.hasIcon ? 23 : 0)
                                        text: (mrow.modelData.checkState === Qt.Checked ? "\u{f012c}  " : "")
                                              + mrow.modelData.text
                                        color: mrow.modelData.enabled
                                               ? root.theme.fg : Qt.alpha(root.theme.muted, 0.5)
                                        font.family: root.theme.fontSans
                                        font.pixelSize: IslandState.ts(12)
                                        elide: Text.ElideRight
                                    }
                                }

                                Text {
                                    visible: mrow.modelData.hasChildren
                                    anchors.right: parent.right
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "\u{f0142}"
                                    color: Qt.alpha(root.theme.muted, 0.7)
                                    font.family: root.theme.fontMono
                                    font.pixelSize: 11
                                }

                                HoverHandler { id: mh; enabled: mrow.modelData.enabled }

                                MouseArea {
                                    anchors.fill: parent
                                    enabled: mrow.modelData.enabled
                                    onClicked: {
                                        if (mrow.modelData.hasChildren)
                                            root.pushMenu(mrow.modelData);
                                        else
                                            mrow.modelData.triggered();
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
