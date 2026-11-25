import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire

// The macOS-style menu bar: one band across the top of the screen with the
// island or notch in its middle, drawn around it so it adapts to both shapes:
//   - notch: the band is exactly the notch's resting height, so the notch
//     reads as a black cut-out of the bar, the way a MacBook's does;
//   - island: the band covers the strip the bar reserves (edge gap + the
//     expanded pill), and the pill floats centred in it.
//
// What sits on it, and on which side, is IslandState.barOrder — one list with
// "notch" as the divider, arranged in Settings → General → Bar layout.
//
// Real app menus (File, Edit…) cannot be had here: a native Wayland app only
// exports them over KDE's appmenu protocol, which Hyprland does not speak,
// and Chromium/Electron export none on Wayland at all. So the menus are the
// ones every window has — App, Window and Go — built from Hyprland actions.
// Every status icon opens its own panel in the island, straight, without the
// Control Center under it.
Item {
    id: root

    property var theme
    property string screenName: ""
    property Item island: null
    // On the lock screen there is no window for a popup to hang off (a lock
    // surface is not one), so the dropdown is drawn inside the bar's own
    // surface instead; inSurface switches that.
    property bool inSurface: false
    signal dropdownClosed()
    function closeMenus() { if (dropdown.open) dropdown.close(); }

    readonly property real band: IslandState.barBand
    readonly property real islandLeft: root.island
        ? root.island.x - (IslandState.notch ? 14 : 0) : root.width / 2

    height: root.band

    // The look knobs, from Settings → Menu bar. Item-specific sizes are
    // offsets from these, so the bar scales as one.
    readonly property int pad: IslandState.cfg.barPad
    readonly property int iconPx: IslandState.cfg.barIconSize
    readonly property int fontPx: IslandState.cfg.barFontSize

    // ── the band ───────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        // Clear over an empty workspace (Settings → Menu bar), so the
        // wallpaper runs edge to edge; fades rather than snaps.
        // Fully clear on the lock screen: the items float on the wallpaper.
        property real alpha: root.inSurface ? 0 : IslandState.barAlpha(root.screenName)
        Behavior on alpha { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        color: Qt.rgba(root.theme.islandBg.r, root.theme.islandBg.g, root.theme.islandBg.b, alpha)
        Rectangle {
            visible: IslandState.cfg.barDivider && parent.alpha > 0.01
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Qt.alpha(root.theme.fg, 0.06)
        }
    }

    // A hover-lit slot in the bar. Content goes in as children.
    component Slot: Item {
        id: slot
        property bool active: false
        property real pad: root.pad
        default property alias content: inner.data
        signal clicked(int button)
        signal wheel(int delta)
        signal entered()
        implicitWidth: inner.childrenRect.width + slot.pad * 2
        implicitHeight: Math.min(28, root.band - 6)
        Rectangle {
            anchors.fill: parent
            radius: 7
            color: Qt.alpha(root.theme.fg, slot.active ? 0.16 : 0.12)
            opacity: hov.hovered || slot.active ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }
        Item {
            id: inner
            x: slot.pad
            width: childrenRect.width
            height: parent.height
        }
        HoverHandler {
            id: hov
            cursorShape: Qt.PointingHandCursor
            onHoveredChanged: if (hovered) slot.entered()
        }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: (e) => slot.clicked(e.button)
            onWheel: (e) => slot.wheel(e.angleDelta.y)
        }
    }
    component Glyph: Text {
        anchors.verticalCenter: parent.verticalCenter
        color: root.theme.fg
        font.family: root.theme.fontMono
        font.pixelSize: root.iconPx
    }
    component Label: Text {
        anchors.verticalCenter: parent.verticalCenter
        color: root.theme.fg
        font.family: root.theme.fontSans
        font.pixelSize: IslandState.ts(root.fontPx)
        font.weight: Font.DemiBold
    }

    // ── the focused app ────────────────────────────────────────────
    readonly property var focused: ToplevelManager.activeToplevel
    readonly property bool focusedHere: {
        if (!root.focused) return false;
        const ss = root.focused.screens || [];
        for (let i = 0; i < ss.length; i++) if (ss[i] && ss[i].name === root.screenName) return true;
        return false;
    }
    readonly property var aliases: ({ "io.startup.terminal": "com.mitchellh.ghostty" })
    function norm(s) { return String(s || "").toLowerCase().replace(/[^a-z0-9]/g, ""); }
    function entryFor(appId) {
        if (!appId) return null;
        const id = root.aliases[appId] || appId;
        const want = root.norm(id);
        const all = DesktopEntries.applications.values;
        // An exact id first: several entries can claim one window class (both
        // Claude profiles say com.anthropic.Claude), and the one named after
        // the class is the app itself.
        for (let i = 0; i < all.length; i++)
            if (all[i].id === id) return all[i];
        for (let i = 0; i < all.length; i++)
            if (root.norm(all[i].startupClass) === want || root.norm(all[i].id) === want) return all[i];
        return DesktopEntries.heuristicLookup(id);
    }
    readonly property var focusedEntry: root.focused ? root.entryFor(root.focused.appId) : null
    readonly property string appName: {
        if (!root.focused) return "Desktop";
        const e = root.focusedEntry;
        return e && e.name ? e.name : (root.focused.appId || "Window");
    }

    // ── Hyprland's view of the focused window, for the menus ───────
    readonly property var hyprWin: Hyprland.activeToplevel
    readonly property var winIpc: root.hyprWin ? root.hyprWin.lastIpcObject : null
    readonly property string winAddr: root.hyprWin ? "address:0x" + root.hyprWin.address : ""
    function dispatch(lua) { Quickshell.execDetached(["hyprctl", "dispatch", lua]); }
    // Every window action names its window by address: the menu holds the
    // keyboard while it is open, and "the active window" is not a promise
    // worth trusting across a focus grab.
    function winAct(fn, args) {
        if (root.winAddr === "") return;
        const a = Object.assign({}, args || {});
        let body = 'window = "' + root.winAddr + '"';
        for (const k in a)
            body += ", " + k + " = " + (typeof a[k] === "string" ? '"' + a[k] + '"' : a[k]);
        root.dispatch("hl.dsp.window." + fn + "({ " + body + " })");
    }
    function closeApp() {
        if (!root.focused) return;
        const id = root.focused.appId;
        const all = ToplevelManager.toplevels.values;
        for (let i = 0; i < all.length; i++) if (all[i].appId === id) all[i].close();
    }
    readonly property var screenWorkspaces: {
        const all = Hyprland.workspaces.values;
        const out = [];
        for (let i = 0; i < all.length; i++) {
            const w = all[i];
            if (w.id > 0 && w.monitor && w.monitor.name === root.screenName) out.push(w);
        }
        out.sort((a, b) => a.id - b.id);
        return out;
    }

    // The menus' contents, built when one opens. An item is one of
    //   { label, glyph?, act, checked?, danger?, off? }
    //   { sep: true }
    //   { label, chips: [{ label, act, cur? }] }   (a row of choices)
    function menuItems(kind) {
        const w = root.winIpc;
        const hasWin = root.hyprWin !== null && w !== null;
        if (kind === "app") {
            const out = [];
            if (root.focusedEntry)
                out.push({ label: "New Window", glyph: "\u{f0415}", act: () => root.focusedEntry.execute() });
            if (root.focused) {
                if (out.length) out.push({ sep: true });
                out.push({ label: "Quit " + root.appName, glyph: "\u{f0156}", act: () => root.closeApp() });
                // Killing a shell window kills the shell drawing this menu.
                if (root.focused.appId !== "org.quickshell")
                    out.push({ label: "Force Quit", glyph: "\u{f0bc8}", danger: true,
                               act: () => root.winAct("kill") });
            }
            return out;
        }
        if (kind === "window") {
            if (!hasWin) return [{ label: "No window", off: true }];
            const ws = root.screenWorkspaces.map(x => ({
                label: String(x.id), cur: w.workspace && w.workspace.id === x.id,
                act: () => root.winAct("move", { workspace: x.id, follow: false }) }));
            ws.push({ label: "+", act: () => root.winAct("move", { workspace: "emptym", follow: false }) });
            const mons = Hyprland.monitors.values.map(m => ({
                label: m.name, cur: m.name === w.monitor || (root.hyprWin.monitor && root.hyprWin.monitor.name === m.name),
                act: () => root.winAct("move", { monitor: m.name }) }));
            const out = [
                { label: "Float", glyph: "\u{f05b2}", checked: w.floating === true,
                  act: () => root.winAct("float", { action: "toggle" }) },
                { label: "Pin on All Workspaces", glyph: "\u{f0403}", checked: w.pinned === true,
                  off: w.floating !== true, act: () => root.winAct("pin") },
                { label: "Center", glyph: "\u{f02f1}", off: w.floating !== true,
                  act: () => root.winAct("center") },
                { sep: true },
                { label: "Maximize", glyph: "\u{f05af}", checked: w.fullscreen === 1,
                  act: () => root.winAct("fullscreen", { mode: "maximized" }) },
                { label: "Fullscreen", glyph: "\u{f0293}", checked: w.fullscreen === 2,
                  act: () => root.winAct("fullscreen", { mode: "fullscreen" }) },
                { sep: true },
                { label: "Move to Workspace", chips: ws }
            ];
            if (mons.length > 1) out.push({ label: "Move to Monitor", chips: mons });
            out.push({ sep: true });
            out.push({ label: "Close Window", glyph: "\u{f0156}", danger: true, act: () => root.winAct("close") });
            return out;
        }
        if (kind.indexOf("tray:") === 0) return root.trayMenuItems();
        // go
        const out = root.screenWorkspaces.map(x => ({
            label: "Workspace " + (x.name && x.name !== String(x.id) ? x.name : x.id),
            glyph: x.focused || x.active ? "\u{f012c}" : "",
            hint: x.toplevels ? String(x.toplevels.values.length) : "",
            act: () => root.dispatch("hl.dsp.focus({ workspace = " + x.id + " })") }));
        out.push({ sep: true });
        out.push({ label: "Previous", glyph: "\u{f0141}", act: () => root.dispatch('hl.dsp.focus({ workspace = "m-1" })') });
        out.push({ label: "Next", glyph: "\u{f0142}", act: () => root.dispatch('hl.dsp.focus({ workspace = "m+1" })') });
        out.push({ label: "Empty Workspace", glyph: "\u{f0415}", act: () => root.dispatch('hl.dsp.focus({ workspace = "emptym" })') });
        return out;
    }

    // ── tray menus ─────────────────────────────────────────────────
    // A tray item's own DBusMenu, shown in the same dropdown. Two openers, one
    // per level, with the root held open under a submenu: DBusMenu loads
    // children lazily and closing the parent invalidates them (TrayTool's
    // finding).
    property var trayItem: null
    property var traySub: null
    QsMenuOpener { id: trayRoot; menu: root.trayItem ? root.trayItem.menu : null }
    QsMenuOpener { id: traySubOpener; menu: root.traySub }
    function trayMenuItems() {
        const it = root.trayItem;
        if (!it) return [];
        const out = [];
        const sub = root.traySub !== null;
        if (sub) {
            out.push({ label: root.traySub.text, glyph: "\u{f0141}", keep: true,
                       act: () => { root.traySub = null; } });
            out.push({ sep: true });
        } else if (!it.onlyMenu) {
            out.push({ label: "Open " + TrayIcons.displayName(it), glyph: "\u{f03cc}",
                       act: () => it.activate() });
            out.push({ sep: true });
        }
        const o = sub ? traySubOpener : trayRoot;
        const es = o.children ? o.children.values : [];
        for (let i = 0; i < es.length; i++) {
            const e = es[i];
            if (e.isSeparator) {
                if (out.length && !out[out.length - 1].sep) out.push({ sep: true });
                continue;
            }
            out.push({
                label: e.text, off: !e.enabled,
                checked: e.checkState === Qt.Checked,
                hint: e.hasChildren ? "\u{f0142}" : "",
                keep: e.hasChildren,
                act: e.hasChildren ? () => { root.traySub = e; } : () => e.triggered()
            });
        }
        while (out.length && out[out.length - 1].sep) out.pop();
        if (out.length === 0) out.push({ label: "No menu", off: true });
        return out;
    }
    function openTrayMenu(item, slot) {
        const k = "tray:" + item.id;
        if (dropdown.open && dropdown.kind === k) { dropdown.close(); return; }
        root.traySub = null;
        root.trayItem = item;
        dropdown.openOn(k, slot);
    }

    // ── the dropdown ───────────────────────────────────────────────
    PopupWindow {
        id: dropdown
        property string kind: ""
        property Item target: null
        // Bound, not snapshotted: the refresh below lands a moment after the
        // menu opens, and the checkmarks follow it.
        readonly property var items: kind !== "" ? root.menuItems(kind) : []

        function openOn(k, slot) {
            Hyprland.refreshToplevels();
            Hyprland.refreshWorkspaces();
            Hyprland.refreshMonitors();
            kind = k;
            target = slot;
            const p = slot.mapToItem(root, 0, 0);
            hostX = Math.max(0, Math.min(p.x, root.width - implicitWidth));
            hostY = p.y + anchor.rect.y;
            if (!open) {
                open = true;
                if (root.inSurface) keys.forceActiveFocus();
                else armGrab.restart();
            }
        }
        function close() {
            armGrab.stop();
            grab.active = false;
            const was = open;
            open = false;
            kind = "";
            root.traySub = null;
            root.trayItem = null;
            if (was) root.dropdownClosed();
        }
        function run(it) {
            if (it.keep) { if (it.act) it.act(); return; }
            close();
            if (it.act) it.act();
        }

        anchor.item: target
        anchor.rect.y: target ? target.height + (root.band - target.height) / 2 + 2 : 0
        anchor.rect.x: 0
        // A Column sizes to its children's widths, which follow the Column, so
        // the widest row's own implicitWidth is read off the Repeater instead.
        readonly property real rowsWidth: {
            let m = 0;
            for (let i = 0; i < menuRep.count; i++) {
                const r = menuRep.itemAt(i);
                if (r) m = Math.max(m, r.implicitWidth);
            }
            return m;
        }
        implicitWidth: Math.min(480, Math.max(220, rowsWidth + 12))
        implicitHeight: menuCol.implicitHeight + 12
        color: "transparent"
        property bool open: false
        visible: open && !root.inSurface
        property real hostX: 0
        property real hostY: 0

        Rectangle {
            parent: root.inSurface ? ddHost : dropdown.contentItem
            anchors.fill: parent
            radius: 12
            color: root.theme.surface_container_high
            border.width: 1
            border.color: Qt.alpha(root.theme.outline, 0.3)

            Item {
                id: keys
                focus: true
                Keys.onEscapePressed: dropdown.close()
            }

            Column {
                id: menuCol
                x: 6; y: 6
                width: dropdown.implicitWidth - 12
                spacing: 1

                Repeater {
                    id: menuRep
                    model: dropdown.items

                    Item {
                        id: mi
                        required property var modelData
                        readonly property var d: modelData
                        width: menuCol.width
                        implicitWidth: d.sep ? 0 : d.chips ? chipsRow.implicitWidth + 20
                                     : miLabel.implicitWidth + (d.hint ? 80 : 56)
                        height: d.sep ? 9 : d.chips ? 58 : 30

                        Rectangle {
                            visible: !!mi.d.sep
                            anchors.verticalCenter: parent.verticalCenter
                            x: 8; width: parent.width - 16; height: 1
                            color: Qt.alpha(root.theme.outline, 0.25)
                        }

                        Rectangle {
                            visible: !mi.d.sep && !mi.d.chips
                            anchors.fill: parent
                            radius: 7
                            color: miHover.hovered && !mi.d.off
                                   ? (mi.d.danger ? Qt.alpha(root.theme.error, 0.16) : Qt.alpha(root.theme.fg, 0.1))
                                   : "transparent"
                        }
                        Text {
                            visible: !mi.d.sep && !mi.d.chips
                            x: 10
                            anchors.verticalCenter: parent.verticalCenter
                            width: 18
                            text: mi.d.checked ? "\u{f012c}" : (mi.d.glyph || "")
                            color: mi.d.danger ? root.theme.error
                                 : mi.d.checked ? root.theme.accent : Qt.alpha(root.theme.fg, 0.7)
                            opacity: mi.d.off ? 0.35 : 1
                            font.family: root.theme.fontMono
                            font.pixelSize: 14
                        }
                        Text {
                            id: miLabel
                            visible: !mi.d.sep
                            x: mi.d.chips ? 10 : 36
                            y: mi.d.chips ? 5 : (parent.height - height) / 2
                            text: mi.d.label || ""
                            color: mi.d.danger ? root.theme.error
                                 : mi.d.chips ? Qt.alpha(root.theme.on_surface_variant, 0.85) : root.theme.fg
                            opacity: mi.d.off ? 0.35 : 1
                            font.family: root.theme.fontSans
                            font.pixelSize: IslandState.ts(mi.d.chips ? 11 : 13)
                        }
                        Text {
                            visible: !mi.d.sep && !mi.d.chips && !!mi.d.hint
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: mi.d.hint || ""
                            color: Qt.alpha(root.theme.on_surface_variant, 0.6)
                            font.family: root.theme.fontMono
                            font.pixelSize: IslandState.ts(11)
                        }
                        Row {
                            id: chipsRow
                            visible: !!mi.d.chips
                            x: 8; y: 25
                            spacing: 4
                            Repeater {
                                model: mi.d.chips || []
                                Rectangle {
                                    required property var modelData
                                    width: Math.max(28, chipLbl.implicitWidth + 16)
                                    height: 26; radius: 7
                                    color: modelData.cur ? Qt.alpha(root.theme.accent, 0.25)
                                         : chipHover.hovered ? Qt.alpha(root.theme.fg, 0.14) : Qt.alpha(root.theme.fg, 0.06)
                                    Text {
                                        id: chipLbl
                                        anchors.centerIn: parent
                                        text: parent.modelData.label
                                        color: parent.modelData.cur ? root.theme.accent : root.theme.fg
                                        font.family: root.theme.fontSans
                                        font.pixelSize: IslandState.ts(12)
                                        font.weight: Font.DemiBold
                                    }
                                    HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: !parent.modelData.cur
                                        onClicked: dropdown.run(parent.modelData)
                                    }
                                }
                            }
                        }

                        HoverHandler { id: miHover; cursorShape: mi.d.act && !mi.d.off ? Qt.PointingHandCursor : Qt.ArrowCursor }
                        MouseArea {
                            anchors.fill: parent
                            visible: !mi.d.sep && !mi.d.chips && !mi.d.off && !!mi.d.act
                            onClicked: dropdown.run(mi.d)
                        }
                    }
                }
            }
        }
    }
    // The dropdown's stand-in window on the lock surface.
    // Lifted onto the bar's parent there, so it stacks over the island and
    // its card rather than under them; the bar sits at the parent's origin,
    // so the coordinates hold.
    Item {
        id: ddHost
        parent: root.inSurface && root.parent ? root.parent : root
        x: dropdown.hostX
        y: dropdown.hostY
        z: 100
        width: dropdown.implicitWidth
        height: dropdown.implicitHeight
        visible: root.inSurface && dropdown.open
    }

    // Click-away close. Armed only after the popup maps — activating it in
    // the same tick visible flips silently fails (the Dock menu's trap too).
    HyprlandFocusGrab {
        id: grab
        windows: [dropdown]
        active: false
        onCleared: dropdown.close()
    }
    Timer {
        id: armGrab
        interval: 120
        onTriggered: { grab.active = true; keys.forceActiveFocus(); }
    }
    function toggleMenu(k, slot) {
        if (dropdown.open && dropdown.kind === k) dropdown.close();
        else dropdown.openOn(k, slot);
    }
    // Once a menu is open, sliding onto another title switches to it.
    function slideMenu(k, slot) {
        if (dropdown.open && dropdown.kind !== k) dropdown.openOn(k, slot);
    }

    // ── status ─────────────────────────────────────────────────────
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var audio: root.sink ? root.sink.audio : null
    PwObjectTracker { objects: root.sink ? [root.sink] : [] }
    readonly property var bt: Bluetooth.defaultAdapter
    readonly property bool btOn: root.bt !== null && root.bt.enabled
    readonly property bool btLinked: {
        const ds = Bluetooth.devices ? Bluetooth.devices.values : [];
        for (let i = 0; i < ds.length; i++) if (ds[i].connected) return true;
        return false;
    }
    SystemClock { id: clk; precision: SystemClock.Minutes }

    function loadPct(v) { return v < 0 ? "–" : Math.round(v * 100) + "%"; }
    function loadTint(v) { return v >= 0.85 ? root.theme.warn : root.theme.fg; }
    function isOpen(t) { return IslandState.tool === t && IslandState.toolScreen === root.screenName; }
    function openWireless(tab) {
        if (root.isOpen("bluetooth")) { IslandState.closeCard(); return; }
        IslandState.wirelessTab = tab;
        IslandState.openDirect("bluetooth", root.screenName);
    }

    // ── the items ──────────────────────────────────────────────────
    Component {
        id: logoC
        Slot {
            active: root.isOpen("power")
            pad: root.pad + 2
            onClicked: (b) => b === Qt.RightButton
                ? IslandState.toggleDirect("apps", root.screenName)
                : IslandState.toggleDirect("power", root.screenName)
            Glyph { text: "\u{f303}"; font.pixelSize: root.iconPx + 1; color: root.theme.accent }
        }
    }
    // The app name; its menu holds the app-wide actions.
    Component {
        id: appC
        Row {
            spacing: 0
            Slot {
                id: appSlot
                anchors.verticalCenter: parent.verticalCenter
                active: dropdown.open && dropdown.kind === "app"
                onClicked: root.toggleMenu("app", appSlot)
                onEntered: root.slideMenu("app", appSlot)
                Label {
                    text: root.appName
                    font.weight: Font.Bold
                    opacity: root.focused === null || root.focusedHere ? 1 : 0.55
                }
            }
        }
    }
    Component {
        id: wsC
        // The island's resting form: a row of page dots, the active one tall,
        // the focused one lit. Each dot is still a click target.
        Item {
            implicitWidth: wsDots.implicitWidth + 16
            implicitHeight: wsDots.implicitHeight
            Workspaces {
                id: wsDots
                anchors.centerIn: parent
                theme: root.theme
                screenName: root.screenName
                compact: true
            }
        }
    }
    Component {
        id: menusC
        Row {
            spacing: 2
            Repeater {
                model: [{ k: "window", label: "Window" }, { k: "go", label: "Go" }]
                Slot {
                    id: mSlot
                    required property var modelData
                    anchors.verticalCenter: parent.verticalCenter
                    active: dropdown.open && dropdown.kind === modelData.k
                    onClicked: root.toggleMenu(modelData.k, mSlot)
                    onEntered: root.slideMenu(modelData.k, mSlot)
                    Label { text: mSlot.modelData.label; font.weight: Font.Medium }
                }
            }
        }
    }
    // The call, while one is up: the island keeps only the clock with the
    // bar on, so the call's badge, timer and waveform live here instead.
    // Click opens the call panel, right-click mutes, middle-click focuses
    // the call window.
    Component {
        id: callC
        Slot {
            id: cSlot
            readonly property bool hushed: IslandState.callMuted || IslandState.callDeafened
            active: root.isOpen("call")
            onClicked: (b) => {
                if (b === Qt.RightButton) IslandState.toggleCallMute();
                else if (b === Qt.MiddleButton) IslandState.focusCall();
                else IslandState.toggleDirect("call", root.screenName);
            }
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Item {
                    id: cBadge
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(root.band - 8, 20); height: width
                    Text {
                        anchors.centerIn: parent
                        text: IslandState.callDeafened ? "\u{f07ce}"
                            : IslandState.callMuted ? "\u{f036d}"
                            : (IslandState.callApp ? IslandState.callApp.glyph : "")
                        color: cSlot.hushed ? root.theme.error : root.theme.fg
                        font.family: root.theme.fontMono
                        font.pixelSize: root.iconPx
                    }
                    SequentialAnimation on opacity {
                        running: IslandState.inCall
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.7; duration: 900; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
                    }
                }
                Label {
                    textFormat: Text.PlainText
                    text: IslandState.dcInVoice && IslandState.callApp && IslandState.callApp.id === "discord"
                          && IslandState.dcChannel !== ""
                        ? IslandState.dcChannel
                        : (IslandState.callApp ? IslandState.callApp.name : "")
                    color: Qt.alpha(root.theme.fg, 0.65)
                }
                Label {
                    text: IslandState.timerFmt(IslandState.callSecs)
                    font.features: { "tnum": 1 }
                    color: cSlot.hushed ? root.theme.error : root.theme.fg
                }
                CallWave {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: IslandState.cfg.liveBars
                    width: 56; height: 20
                    them: IslandState.callThem
                    me: IslandState.callMe
                    frame: IslandState.wavFrame
                    colorThem: root.theme.primary
                    colorMe: root.theme.tertiary
                }
            }
        }
    }
    // Now playing: cover, track and the live cava bars, the slot the island
    // used to give it. Shows while a player has a track; dims when paused.
    Component {
        id: mediaC
        Slot {
            id: mSlot
            readonly property var pl: IslandState.player
            // Only while something is actually playing: a paused or stopped
            // player leaves the bar.
            visible: IslandState.mediaPlaying
            active: root.isOpen("media")
            onClicked: (b) => {
                if (b === Qt.MiddleButton) { if (pl && pl.canTogglePlaying) pl.togglePlaying(); }
                else IslandState.toggleDirect("media", root.screenName);
            }
            Row {
                id: mRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                opacity: mSlot.pl && mSlot.pl.isPlaying ? 1 : 0.6
                // Cover, artist, song, then the live bars — a size up from
                // the other items, since it is the bar's one moving piece.
                ClippingRectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(root.band - 6, 24); height: width; radius: 6
                    color: Qt.alpha(root.theme.muted, 0.22)
                    Image {
                        anchors.fill: parent
                        source: mSlot.pl && mSlot.pl.trackArtUrl ? mSlot.pl.trackArtUrl : ""
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: 48; sourceSize.height: 48
                        asynchronous: true
                    }
                }
                // The whole artist and song, never cut.
                Label {
                    visible: text !== ""
                    textFormat: Text.PlainText
                    text: mSlot.pl ? (mSlot.pl.trackArtist || "") : ""
                    color: Qt.alpha(root.theme.fg, 0.65)
                    font.pixelSize: IslandState.ts(root.fontPx)
                }
                Label {
                    visible: mSlot.pl !== null && !!mSlot.pl.trackArtist
                    text: "·"
                    color: Qt.alpha(root.theme.fg, 0.45)
                    font.pixelSize: IslandState.ts(root.fontPx)
                }
                Label {
                    textFormat: Text.PlainText
                    text: mSlot.pl ? (mSlot.pl.trackTitle || "") : ""
                    font.weight: Font.DemiBold
                    font.pixelSize: IslandState.ts(root.fontPx)
                }
                // The bars stay up the whole time the track is shown; in a quiet
                // passage they just lie flat.
                MiniBars {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 52; height: 22
                    vals: IslandState.wavVals
                    frame: IslandState.wavFrame
                    color: root.theme.primary
                }
            }
            // Track progress, a hairline along the item's lower edge. Only
            // the position glides, linearly over the one-second poll; a seek
            // or a new track lands at once.
            Item {
                id: mProg
                visible: IslandState.cfg.progressLine && IslandState.trackProgress >= 0
                // Sized from the row, not the slot: the slot's width is taken
                // from its children, this line included.
                // Starts past the cover, under the names and bars.
                x: 32
                y: parent.height - 2
                width: Math.max(0, mRow.width - 32)
                height: 2
                property real shown: Math.max(0, IslandState.trackProgress)
                Connections {
                    target: IslandState
                    function onTrackProgressChanged() {
                        const next = Math.max(0, IslandState.trackProgress);
                        mGlide.stop();
                        if (Math.abs(next - mProg.shown) > 0.03) mProg.shown = next;
                        else { mGlide.to = next; mGlide.start(); }
                    }
                }
                NumberAnimation { id: mGlide; target: mProg; property: "shown"; duration: 1000; easing.type: Easing.Linear }
                Rectangle {
                    anchors.fill: parent
                    radius: 1
                    color: Qt.alpha(root.theme.fg, 0.12)
                }
                Rectangle {
                    height: parent.height
                    radius: 1
                    width: parent.width * mProg.shown
                    color: Qt.alpha(root.theme.accent, 0.9)
                }
            }
        }
    }
    // Privacy dots in the platform's own colours, whatever the theme:
    // orange while the mic is in use, green while the camera or a screen
    // capture runs. Small and quiet, the way macOS keeps them.
    Component {
        id: statusC
        Slot {
            pad: Math.max(2, root.pad - 4)
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: IslandState.micInUse
                    width: 5; height: 5; radius: 2.5
                    color: "#ff9f0a"
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: IslandState.videoInUse
                    width: 5; height: 5; radius: 2.5
                    color: "#30d158"
                }
            }
        }
    }
    // Notifications: the unread count as a badge, or the moon while silent
    // mode holds the toasts back. Click opens the notification list.
    Component {
        id: notifsC
        Slot {
            active: root.isOpen("notifs")
            onClicked: IslandState.toggleDirect("notifs", root.screenName)
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 5
                Glyph {
                    visible: IslandState.dnd
                    text: "\u{f0f65}"
                    color: root.theme.accent3
                    font.pixelSize: root.iconPx - 1
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: IslandState.unreadCount > 0 && !IslandState.dnd
                    height: 15
                    width: Math.max(height, unreadTxt.implicitWidth + 8)
                    radius: height / 2
                    color: root.theme.primary
                    Text {
                        id: unreadTxt
                        anchors.centerIn: parent
                        text: IslandState.unreadCount > 9 ? "9+" : IslandState.unreadCount
                        color: root.theme.on_primary
                        font.family: root.theme.fontMono
                        font.pixelSize: 9
                        font.weight: Font.Black
                    }
                }
            }
        }
    }
    Component {
        id: weatherC
        Slot {
            visible: IslandState.wxTemp !== "--"
            active: root.isOpen("weather")
            onClicked: IslandState.toggleDirect("weather", root.screenName)
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Glyph { text: IslandState.wxIcon; color: root.theme.primary; font.pixelSize: root.iconPx + 1 }
                Label { text: IslandState.wxTemp + "°" }
            }
        }
    }
    // CPU, RAM and GPU load, from the same two-second poll the status rings use.
    Component {
        id: monitorC
        Slot {
            active: root.isOpen("monitor")
            pad: Math.max(2, root.pad - 4)
            onClicked: IslandState.toggleDirect("monitor", root.screenName)
            // Each figure sits tight against its icon at its natural width:
            // tabular digits keep a reading from wobbling, and the slot only
            // grows when one gains a digit.
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Repeater {
                    model: [
                        // Font Awesome's solid hardware set: a chip, a RAM
                        // stick, a graphics card — one style, told apart at
                        // a glance.
                        { glyph: "\u{f2db}",  v: IslandState.cpuLoad, on: true },
                        { glyph: "\u{efc5}",  v: IslandState.memLoad, on: true },
                        { glyph: "\u{f0fb2}", v: IslandState.gpuLoad, on: IslandState.gpuLoad >= 0 }
                    ]
                    Row {
                        required property var modelData
                        anchors.verticalCenter: parent.verticalCenter
                        visible: modelData.on
                        spacing: 3
                        Glyph { text: parent.modelData.glyph; font.pixelSize: root.iconPx; color: Qt.alpha(root.theme.fg, 0.75) }
                        Label {
                            text: root.loadPct(parent.modelData.v)
                            color: root.loadTint(parent.modelData.v)
                            font.pixelSize: IslandState.ts(root.fontPx - 1)
                            font.weight: Font.Medium
                            font.features: { "tnum": 1 }
                        }
                    }
                }
            }
        }
    }
    // Station input and output as two live bars, scaled to the rated output
    // (Settings → Power station), each with its wattage, then the time left.
    Component {
        id: stationFlowC
        Slot {
            active: root.isOpen("station")
            pad: Math.max(2, root.pad - 4)
            onClicked: IslandState.toggleDirect("station", root.screenName)
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Repeater {
                    model: [
                        { glyph: "\u{f192d}", w: IslandState.stationIn,  tint: root.theme.success },
                        { glyph: "\u{f192c}", w: IslandState.stationOut, tint: root.theme.accent }
                    ]
                    Row {
                        required property var modelData
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        Glyph { text: parent.modelData.glyph; color: Qt.alpha(root.theme.fg, 0.75) }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 30; height: 6; radius: 3
                            color: Qt.alpha(root.theme.fg, 0.14)
                            Rectangle {
                                anchors.left: parent.left
                                height: parent.height
                                radius: parent.radius
                                width: parent.width * Math.max(0, Math.min(1, parent.parent.modelData.w / Math.max(1, IslandState.cfg.stationFlowMax)))
                                color: parent.parent.modelData.tint
                                Behavior on width { NumberAnimation { duration: 250 } }
                            }
                        }
                        Label {
                            text: Math.round(parent.modelData.w) + "W"
                            font.pixelSize: IslandState.ts(root.fontPx - 1)
                            font.weight: Font.Medium
                            font.features: { "tnum": 1 }
                        }
                    }
                }
                // Time estimate: how long the battery carries the load when
                // not charging (UPS, hold, on battery), time to full while
                // charging; hidden when the station has no figure.
                Row {
                    readonly property string full: IslandState.stationCharging
                        ? IslandState.stationHm(IslandState.station.charge_remain_min < 5940 ? IslandState.station.charge_remain_min : 0) : ""
                    readonly property string time: IslandState.stationRuntime || full
                    visible: IslandState.stationOnline && time !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    Glyph {
                        text: parent.full !== "" && !IslandState.stationRuntime ? "\u{f0084}" : "\u{f051b}"
                        color: IslandState.stationOnBattery ? root.theme.warn : Qt.alpha(root.theme.fg, 0.75)
                    }
                    Label {
                        text: parent.time
                        font.pixelSize: IslandState.ts(root.fontPx - 1)
                        font.weight: Font.Medium
                        font.features: { "tnum": 1 }
                    }
                }
            }
        }
    }
    Component {
        id: trayC
        TopTray {
            theme: root.theme
            screenName: root.screenName
            flat: true
            onMenuAt: (item, slot) => root.openTrayMenu(item, slot)
            implicitHeight: Math.min(30, root.band - 4)
        }
    }
    Component {
        id: networkC
        Slot {
            active: root.isOpen("bluetooth")
            onClicked: (b) => b === Qt.RightButton ? IslandState.cycleNetwork() : root.openWireless("net")
            Glyph {
                text: IslandState.netKind === "vpn" ? "\u{f0582}"
                    : IslandState.netKind === "wifi" ? "\u{f05a9}"
                    : IslandState.netKind === "disconnected" ? "\u{f002a}" : "\u{f0200}"
                color: IslandState.netKind === "vpn" ? root.theme.accent
                     : IslandState.netKind === "disconnected" ? root.theme.warn : root.theme.fg
            }
        }
    }
    Component {
        id: bluetoothC
        Slot {
            visible: root.bt !== null
            onClicked: (b) => {
                if (b === Qt.RightButton) root.bt.enabled = !root.bt.enabled;
                else root.openWireless("bt");
            }
            Glyph {
                text: !root.btOn ? "\u{f00b2}" : root.btLinked ? "\u{f00b1}" : "\u{f00af}"
                color: root.btLinked ? root.theme.accent : Qt.alpha(root.theme.fg, root.btOn ? 1 : 0.5)
            }
        }
    }
    // AirPods, phone, mouse, controller and power station charge, the way macOS menu bar battery
    // apps show them: the device's icon (the same DeviceGlyph the island's
    // circles draw, a controller in its own colour) and its percentage, no ring. Each follows the
    // same toggle as its island circle and shows only while connected; the
    // charge is coloured only when it needs attention (charging, low).
    Component {
        id: devicesC
        Slot {
            active: root.isOpen("battery")
            onClicked: IslandState.toggleDirect("battery", root.screenName)
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Repeater {
                    model: root.barDevices
                    Row {
                        required property var modelData
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        readonly property color tint: IslandState.batteryColor(modelData.pct, modelData.charging, root.theme)
                        readonly property bool alert: modelData.charging
                            || (modelData.pct >= 0 && modelData.pct <= IslandState.cfg.statusWarnPct / 100)
                        DeviceGlyph {
                            anchors.verticalCenter: parent.verticalCenter
                            kind: parent.modelData.kind
                            color: parent.modelData.charging ? parent.tint
                                 : parent.modelData.body !== "" ? parent.modelData.body : root.theme.fg
                            fontFamily: root.theme.fontMono
                            size: root.iconPx + 3
                        }
                        Label {
                            text: parent.modelData.pct < 0 ? "–" : Math.round(parent.modelData.pct * 100) + "%"
                            color: parent.alert ? parent.tint : root.theme.fg
                            font.pixelSize: IslandState.ts(root.fontPx - 1)
                            font.weight: Font.Medium
                            font.features: { "tnum": 1 }
                        }
                    }
                }
            }
        }
    }
    readonly property var barDevices: IslandState.devices.filter(d => IslandState.cfg[d.pref])
    Component {
        id: soundC
        Slot {
            visible: root.audio !== null
            active: root.isOpen("audio")
            onClicked: (b) => {
                if (b === Qt.MiddleButton || b === Qt.RightButton) root.audio.muted = !root.audio.muted;
                else IslandState.toggleDirect("audio", root.screenName);
            }
            onWheel: (d) => {
                if (!root.audio) return;
                root.audio.volume = Math.max(0, Math.min(1, root.audio.volume + (d > 0 ? 0.05 : -0.05)));
            }
            Glyph {
                readonly property real p: root.audio ? root.audio.volume * 100 : 0
                text: !root.audio || root.audio.muted ? "\u{f075f}"
                    : p >= 66 ? "\u{f057e}" : p >= 33 ? "\u{f0580}" : "\u{f057f}"
                color: root.audio && root.audio.muted ? Qt.alpha(root.theme.fg, 0.5) : root.theme.fg
            }
        }
    }
    Component {
        id: layoutC
        Slot {
            visible: IslandState.layoutCode !== ""
            onClicked: IslandState.switchLayout()
            Label { text: IslandState.layoutCode; font.pixelSize: IslandState.ts(root.fontPx - 2) }
        }
    }
    Component {
        id: hubC
        Slot {
            active: root.isOpen("hub")
            onClicked: IslandState.toggleTool("hub", root.screenName)
            Glyph { text: "\u{f1542}" }
        }
    }
    Component {
        id: clockC
        Slot {
            active: root.isOpen("calendar")
            pad: root.pad + 2
            onClicked: IslandState.toggleDirect("calendar", root.screenName)
            Label {
                text: Qt.formatDateTime(clk.date, "ddd d MMM") + "   "
                    + Qt.formatDateTime(clk.date, IslandState.cfg.clock24h ? "HH:mm" : "h:mm AP")
            }
        }
    }
    // Whether an item has anything to show right now. Decided here, not by
    // reading the item's own visible: an item inside a hidden Loader reads
    // as hidden too, so that check latches every slot off for good.
    function present(id) {
        switch (id) {
        case "call": return IslandState.inCall;
        case "media": return IslandState.mediaPlaying;
        case "status": return IslandState.micInUse || IslandState.videoInUse;
        case "notifs": return IslandState.dnd || IslandState.unreadCount > 0;
        case "weather": return IslandState.wxTemp !== "--";
        case "tray": return IslandState.trayItems.length > 0;
        case "bluetooth": return root.bt !== null;
        case "devices": return root.barDevices.length > 0;
        case "sound": return root.audio !== null;
        case "layout": return IslandState.layoutCode !== "";
        case "stationflow": return IslandState.stationOnline;
        }
        return true;
    }
    function comp(id) {
        switch (id) {
        case "logo": return logoC;
        case "app": return appC;
        case "ws": return wsC;
        case "menus": return menusC;
        case "call": return callC;
        case "media": return mediaC;
        case "weather": return weatherC;
        case "status": return statusC;
        case "notifs": return notifsC;
        case "monitor": return monitorC;
        case "stationflow": return stationFlowC;
        case "tray": return trayC;
        case "network": return networkC;
        case "bluetooth": return bluetoothC;
        case "devices": return devicesC;
        case "sound": return soundC;
        case "layout": return layoutC;
        case "hub": return hubC;
        case "clock": return clockC;
        }
        return null;
    }


    Row {
        id: left
        anchors.left: parent.left
        anchors.leftMargin: IslandState.cfg.barMargin
        anchors.verticalCenter: parent.verticalCenter
        spacing: IslandState.cfg.barSpacing
        Repeater {
            id: leftRep
            model: IslandState.barLeft
            Loader {
                required property var modelData
                readonly property string uid: modelData
                anchors.verticalCenter: parent.verticalCenter
                // A hidden item (no track playing, no Bluetooth adapter)
                // takes no room: Row only skips children that are invisible.
                visible: root.present(modelData)
                sourceComponent: root.comp(modelData)
            }
        }
    }

    Row {
        id: right
        anchors.right: parent.right
        anchors.rightMargin: IslandState.cfg.barMargin
        anchors.verticalCenter: parent.verticalCenter
        spacing: IslandState.cfg.barSpacing
        Repeater {
            model: IslandState.barRight
            Loader {
                required property var modelData
                anchors.verticalCenter: parent.verticalCenter
                // A hidden item (no track playing, no Bluetooth adapter)
                // takes no room: Row only skips children that are invisible.
                visible: root.present(modelData)
                sourceComponent: root.comp(modelData)
            }
        }
    }
}
