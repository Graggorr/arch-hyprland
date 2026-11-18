import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

// The bottom dock: pinned apps first, in the order the user arranged them,
// then every other running app (every window on every monitor) grouped by
// desktop entry in the order they were first opened, after a thin divider.
// Anchored to the bottom edge only, which layer-shell centres horizontally,
// so the surface is exactly as wide as its icons; it disappears when there
// is nothing pinned and nothing open.
//
// Left click focuses the app (or launches a pinned one that is not running);
// clicking the app that already has focus cycles through its windows. Middle
// click starts a new instance. Right click opens pin / new window / close.
// Dots under the icon count its windows (up to three).
//
// Dragging a pinned icon reorders the pins; dragging a running app into the
// pinned section pins it at the drop position. Pins are desktop entry ids in
// IslandState's prefs (`dockPinned`), so both monitors' docks share them and
// they survive a restart.
//
// ToplevelManager (wlr foreign-toplevel) rather than Hyprland.toplevels:
// it carries `activated` and `activate()` directly and updates live, while
// HyprlandToplevel only knows its class through the lastIpcObject snapshot.
PanelWindow {
    id: root

    property var theme
    property bool shown: true

    readonly property int iconSize: 34
    readonly property int cell: 46
    readonly property int spacing: 4
    readonly property int gap: 13
    readonly property int step: cell + spacing

    readonly property var pinned: IslandState.cfg.dockPinned || []

    readonly property var items: {
        const all = ToplevelManager.toplevels.values;
        const order = [];
        const byKey = {};
        for (let i = 0; i < all.length; i++) {
            const t = all[i];
            const appId = t.appId || "";
            if (appId === "") continue;
            const entry = root.entryFor(appId);
            const key = entry ? entry.id : appId;
            if (!byKey[key]) {
                byKey[key] = { key: key, appId: appId, entry: entry, pinned: false, windows: [] };
                order.push(byKey[key]);
            }
            byKey[key].windows.push(t);
        }
        const out = [];
        for (let i = 0; i < root.pinned.length; i++) {
            const id = root.pinned[i];
            const run = byKey[id];
            if (run) {
                run.pinned = true;
                out.push(run);
            } else {
                const entry = root.entryById(id);
                if (entry) out.push({ key: id, appId: id, entry: entry, pinned: true, windows: [] });
            }
        }
        for (let i = 0; i < order.length; i++) if (!order[i].pinned) out.push(order[i]);
        return out;
    }
    readonly property int pinnedCount: {
        let n = 0;
        while (n < items.length && items[n].pinned) n++;
        return n;
    }
    readonly property bool divided: pinnedCount > 0 && items.length > pinnedCount

    function slotX(i) { return i * step + (divided && i >= pinnedCount ? gap : 0); }

    // ── drag state ──
    property int dragFrom: -1
    property int dragTo: -1
    property real dragDx: 0

    function nearestSlot(x) {
        let best = 0, bestD = 1e9;
        for (let i = 0; i < items.length; i++) {
            const d = Math.abs(slotX(i) - x);
            if (d < bestD) { bestD = d; best = i; }
        }
        return best;
    }

    function updateDrag(from, dx) {
        dragFrom = from;
        dragDx = dx;
        const near = nearestSlot(slotX(from) + dx);
        if (items[from].pinned) dragTo = Math.min(near, pinnedCount - 1);
        else dragTo = near <= pinnedCount ? near : -1;
    }

    function shiftFor(i) {
        if (dragFrom < 0 || dragTo < 0 || i === dragFrom) return 0;
        if (dragFrom < i && i <= dragTo) return -step;
        if (dragTo <= i && i < dragFrom) return step;
        return 0;
    }

    // Saving the pins rebuilds `items`, and the Repeater then recreates every
    // icon. The drag state is therefore cleared first — indices from the old
    // order applied to the new one would shift the wrong icons for a frame —
    // and the dropped icon's position is handed over through land*, so its new
    // delegate glides from where it was released into its slot.
    property string landKey: ""
    property real landX: 0
    property double landAt: 0
    readonly property int landMs: 140

    function endDrag() {
        const from = dragFrom, to = dragTo;
        const it = from >= 0 ? items[from] : null;
        const dropX = from >= 0 ? slotX(from) + dragDx : 0;
        let arr = null;
        if (it && to >= 0 && to !== from) {
            arr = root.pinned.slice();
            if (it.pinned) arr.splice(from, 1);
            arr.splice(to, 0, it.key);
        } else if (it && to === from && !it.pinned) {
            // An unpinned app dropped on its own slot only lands there when it
            // is the first running app, right after the pins: that is a pin too.
            arr = root.pinned.concat([it.key]);
        }
        if (arr) {
            landKey = it.key;
            landX = dropX;
            landAt = Date.now();
        }
        dragFrom = -1;
        dragTo = -1;
        dragDx = 0;
        if (arr) IslandState.setPref("dockPinned", arr);
    }

    function setPinned(it, on) {
        const arr = root.pinned.filter(k => k !== it.key);
        if (on) arr.push(it.key);
        IslandState.setPref("dockPinned", arr);
    }

    anchors.bottom: true
    margins.bottom: 6
    exclusiveZone: implicitHeight
    implicitHeight: cell + 12
    implicitWidth: (items.length > 0 ? slotX(items.length - 1) + cell : 0) + 16
    visible: shown && items.length > 0
    // During a Flameshot capture the dock goes transparent and click-through
    // but keeps its reserved zone, so nothing resizes under the overlay.
    readonly property bool capturing: IslandState.capturingOn(root.screen ? root.screen.name : "")
    Binding { target: root.contentItem; property: "opacity"; value: root.capturing ? 0 : 1 }
    readonly property Region noInput: Region {}
    mask: root.capturing ? root.noInput : null
    color: "transparent"

    // Window classes rarely match desktop ids exactly: Spotify's window says
    // "Spotify" but its entry says "spotify", Keeper's "keeper-password-manager"
    // vs "Keeper Password Manager". Compared with case and punctuation stripped,
    // against the entry's StartupWMClass, its id and its name. A class no entry
    // claims at all (Ghostty runs under a custom class) goes through `aliases`.
    readonly property var aliases: ({ "io.startup.terminal": "com.mitchellh.ghostty" })

    function norm(s) { return String(s || "").toLowerCase().replace(/[^a-z0-9]/g, ""); }

    function entryById(id) {
        const all = DesktopEntries.applications.values;
        for (let i = 0; i < all.length; i++) if (all[i].id === id) return all[i];
        return null;
    }

    // Several entries can claim one window class (google-chrome,
    // com.google.Chrome and every Chrome profile launcher all say
    // "google-chrome"), so a pinned entry that matches wins over the first
    // match in the full list — otherwise the running app would show up a
    // second time next to its own pin.
    function entryFor(appId) {
        const id = aliases[appId] || appId;
        const want = norm(id);
        for (let i = 0; i < root.pinned.length; i++) {
            const e = entryById(root.pinned[i]);
            if (e && (norm(e.startupClass) === want || norm(e.id) === want)) return e;
        }
        const all = DesktopEntries.applications.values;
        for (let i = 0; i < all.length; i++)
            if (norm(all[i].startupClass) === want || norm(all[i].id) === want) return all[i];
        for (let i = 0; i < all.length; i++)
            if (!all[i].noDisplay && norm(all[i].name) === want) return all[i];
        return DesktopEntries.heuristicLookup(id);
    }

    // Steam games have no desktop entry: a Proton window's class is
    // steam_app_<id> and a native one carries SteamAppId in its environment.
    // game-icons.sh maps those classes to the icon in Steam's library cache.
    property var gameIcons: ({})
    readonly property string classKey: {
        const all = ToplevelManager.toplevels.values;
        const s = [];
        for (let i = 0; i < all.length; i++) if (all[i].appId) s.push(all[i].appId);
        return s.sort().join("|");
    }
    onClassKeyChanged: gameIconsTimer.restart()

    Timer {
        id: gameIconsTimer
        interval: 400
        onTriggered: if (!gameIconsProc.running) gameIconsProc.running = true; else restart()
    }

    Process {
        id: gameIconsProc
        command: ["@HOME@/.config/quickshell/scripts/game-icons.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.gameIcons = JSON.parse(this.text); } catch (e) {}
            }
        }
    }

    function iconFor(appId, entry) {
        if (root.gameIcons[appId]) return "file://" + root.gameIcons[appId];
        const name = entry && entry.icon ? entry.icon : appId;
        if (name.startsWith("/")) return "file://" + name;
        const themed = Quickshell.iconPath(name, true) || Quickshell.iconPath(appId.toLowerCase(), true);
        if (themed) return themed;
        // Some apps (Keeper) ship their icon only in /usr/share/pixmaps, which
        // the icon theme lookup never searches.
        if (entry && entry.icon) return "file:///usr/share/pixmaps/" + name + ".png";
        return Quickshell.iconPath("application-x-executable");
    }

    function activateItem(it) {
        const w = it.windows;
        if (w.length === 0) {
            if (it.entry) it.entry.execute();
            return;
        }
        let cur = -1;
        for (let i = 0; i < w.length; i++) if (w[i].activated) { cur = i; break; }
        w[(cur + 1) % w.length].activate();
    }

    Rectangle {
        anchors.fill: parent
        radius: 18
        color: Qt.rgba(root.theme.bg.r, root.theme.bg.g, root.theme.bg.b, root.theme.pillOpacity)
        border.width: 1
        border.color: Qt.alpha(root.theme.outline, 0.2)

        Item {
            id: row
            anchors.fill: parent
            anchors.margins: 8
            anchors.topMargin: 6
            anchors.bottomMargin: 6


            Repeater {
                model: root.items

                Item {
                    id: slot
                    required property var modelData
                    required property int index
                    readonly property bool dragging: root.dragFrom === index
                    readonly property bool active: {
                        const w = modelData.windows;
                        for (let i = 0; i < w.length; i++) if (w[i].activated) return true;
                        return false;
                    }

                    property real land: 0

                    x: root.slotX(index) + land + (dragging ? root.dragDx : root.shiftFor(index))
                    z: dragging || landAnim.running ? 10 : 0
                    width: root.cell
                    height: root.cell
                    Behavior on x {
                        enabled: !slot.dragging && !landAnim.running
                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                    }
                    NumberAnimation {
                        id: landAnim
                        target: slot
                        property: "land"
                        to: 0
                        easing.type: Easing.OutCubic
                    }
                    Component.onCompleted: {
                        if (root.landKey !== modelData.key) return;
                        const left = root.landMs - (Date.now() - root.landAt);
                        if (left <= 0) return;
                        land = (root.landX - root.slotX(index)) * left / root.landMs;
                        landAnim.duration = left;
                        landAnim.start();
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 12
                        color: slot.dragging ? Qt.alpha(root.theme.fg, 0.14)
                             : slot.active ? Qt.alpha(root.theme.primary, 0.18)
                             : hover.hovered ? Qt.alpha(root.theme.fg, 0.08) : "transparent"
                        Behavior on color { ColorAnimation { duration: 130 } }
                    }

                    IconImage {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -2
                        implicitSize: root.iconSize
                        opacity: slot.modelData.windows.length > 0 ? 1.0 : 0.7
                        scale: slot.dragging ? 1.12 : hover.hovered ? 1.08 : 1.0
                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        source: root.iconFor(slot.modelData.appId, slot.modelData.entry)
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 2
                        spacing: 3
                        Repeater {
                            model: Math.min(3, slot.modelData.windows.length)
                            Rectangle {
                                width: slot.active ? 6 : 4
                                height: 4
                                radius: 2
                                color: slot.active ? root.theme.primary : Qt.alpha(root.theme.fg, 0.55)
                            }
                        }
                    }

                    HoverHandler {
                        id: hover
                        cursorShape: slot.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                        property real pressX: 0
                        property bool moved: false

                        onPressed: (e) => {
                            pressX = mapToItem(row, e.x, e.y).x;
                            moved = false;
                            tipDelay.stop();
                            tip.visible = false;
                        }
                        onPositionChanged: (e) => {
                            if (!(pressedButtons & Qt.LeftButton)) return;
                            const dx = mapToItem(row, e.x, e.y).x - pressX;
                            if (!moved && Math.abs(dx) < 6) return;
                            moved = true;
                            root.updateDrag(slot.index, dx);
                        }
                        onReleased: (e) => {
                            if (moved) root.endDrag();
                        }
                        onCanceled: if (moved) root.endDrag()
                        onClicked: (e) => {
                            if (moved) return;
                            if (e.button === Qt.MiddleButton) {
                                if (slot.modelData.entry) slot.modelData.entry.execute();
                            } else if (e.button === Qt.RightButton) {
                                menu.open(slot);
                            } else {
                                root.activateItem(slot.modelData);
                            }
                        }
                    }

                    Tooltip {
                        id: tip
                        theme: root.theme
                        body: {
                            const it = slot.modelData;
                            const name = it.entry ? it.entry.name : it.appId;
                            const w = it.windows;
                            if (w.length === 0) return name;
                            return w.length === 1 ? name + "\n" + w[0].title : name + " — " + w.length + " windows";
                        }
                        anchor.item: slot
                        anchor.rect.y: -tip.implicitHeight - 10
                        anchor.rect.x: (slot.width - tip.implicitWidth) / 2
                    }

                    Timer {
                        id: tipDelay
                        interval: 400
                        onTriggered: if (hover.hovered && !menu.visible && root.dragFrom < 0) tip.visible = true
                    }

                    Connections {
                        target: hover
                        function onHoveredChanged() {
                            if (hover.hovered) tipDelay.restart();
                            else { tipDelay.stop(); tip.visible = false; }
                        }
                    }
                }
            }
        }
    }

    // ── right-click menu ──
    PopupWindow {
        id: menu

        property var target: null
        readonly property var it: target ? target.modelData : null
        readonly property var actions: {
            const a = [];
            if (!it) return a;
            if (it.entry) a.push({ id: "pin", label: it.pinned ? "Unpin from dock" : "Pin to dock",
                                   glyph: it.pinned ? "\u{f0932}" : "\u{f0403}" });
            if (it.entry) a.push({ id: "new", label: "New window", glyph: "\u{f0415}" });
            if (it.windows.length === 1) a.push({ id: "close", label: "Close window", glyph: "\u{f0156}" });
            else if (it.windows.length > 1) a.push({ id: "close", label: "Close all " + it.windows.length + " windows", glyph: "\u{f0156}" });
            return a;
        }

        function open(s) {
            target = s;
            visible = true;
            armGrab.restart();
        }

        function close() {
            armGrab.stop();
            grab.active = false;
            visible = false;
        }

        function run(id) {
            const item = it;
            close();
            if (!item) return;
            if (id === "pin") root.setPinned(item, !item.pinned);
            else if (id === "new") item.entry.execute();
            else if (id === "close") item.windows.slice().forEach(w => w.close());
        }

        anchor.item: target
        anchor.rect.y: -implicitHeight - 8
        anchor.rect.x: target ? (target.width - implicitWidth) / 2 : 0
        implicitWidth: 210
        implicitHeight: menuCol.implicitHeight + 12
        color: "transparent"
        visible: false

        Rectangle {
            anchors.fill: parent
            radius: 14
            color: root.theme.surface_container_high
            border.width: 1
            border.color: Qt.alpha(root.theme.outline, 0.3)

            // The grab parks the keyboard on the menu's surface; this item takes
            // it so Escape reaches the menu.
            Item {
                id: keys
                focus: true
                Keys.onEscapePressed: menu.close()
            }

            Column {
                id: menuCol
                anchors.fill: parent
                anchors.margins: 6
                spacing: 2

                Repeater {
                    model: menu.actions

                    Rectangle {
                        id: mi
                        required property var modelData
                        width: menuCol.width
                        height: 32
                        radius: 9
                        color: miHover.hovered ? Qt.alpha(root.theme.fg, 0.1) : "transparent"

                        Text {
                            id: miGlyph
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: mi.modelData.glyph
                            font.family: root.theme.fontMono
                            font.pixelSize: 15
                            color: mi.modelData.id === "close" ? root.theme.error : root.theme.primary
                        }
                        Text {
                            anchors.left: miGlyph.right
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: mi.modelData.label
                            font.pixelSize: IslandState.ts(13)
                            color: root.theme.fg
                        }

                        HoverHandler { id: miHover; cursorShape: Qt.PointingHandCursor }
                        MouseArea { anchors.fill: parent; onClicked: menu.run(mi.modelData.id) }
                    }
                }
            }
        }
    }

    // Click-away close. The grab must be armed after the popup is mapped —
    // activating it in the same tick that visible flips silently fails (the
    // same trap IslandCard and ThemeSwitcher work around).
    HyprlandFocusGrab {
        id: grab
        windows: [menu]
        active: false
        onCleared: menu.close()
    }
    Timer {
        id: armGrab
        interval: 120
        onTriggered: { grab.active = true; keys.forceActiveFocus(); }
    }
}
