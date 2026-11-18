import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Widgets

// The app launcher, as an island tool. It used to be its own full-screen
// layer (Launcher.qml, retired 2026-09-21); now it is one more sheet over the
// hub, opened by Super+Space through `island toggle apps`, so the launcher
// looks and moves like everything else the pill owns. It is a "face" tool:
// it takes the card itself, with no control center under it.
//
// The keyboard is this tool's native input: the field takes focus on open,
// arrows/Tab walk the list, Enter runs, Esc closes the whole card — a
// launcher you dismiss should not leave the hub behind.
Item {
    id: root

    property var theme

    property string query: ""
    property int selected: 0

    // The launcher has modes rather than magic prefixes: apps, a calculator
    // and a run list of the shell's own surfaces. A prefix still gets you
    // there fast (= calc, > run, : clipboard), but each mode then owns the
    // whole card instead of being a stray row under the apps.
    property string mode: "apps"
    readonly property var modes: [
        { id: "apps",      glyph: "\u{f003b}", name: "Apps",       key: "" },
        { id: "calc",      glyph: "\u{f00ec}", name: "Calculator", key: "=" },
        { id: "clipboard", glyph: "\u{f0192}", name: "Clipboard",  key: ":" },
        { id: "run",       glyph: "\u{f0bdf}", name: "Run",        key: ">" }
    ]

    function setMode(m) {
        if (m === "clipboard") { IslandState.openTool("clipboard", IslandState.toolScreen); return; }
        root.mode = m;
        root.selected = 0;
        search.text = "";
        search.forceActiveFocus();
    }

    // ── calculator ────────────────────────────────────────────────
    // qalc, the engine behind Qalculate: units (10 km to mi), currencies
    // (20 usd to eur), percentages (100 + 10% is 110), functions.
    property string calcResult: ""
    property string calcFor: ""
    property bool calcCopied: false
    property var calcHistory: IslandState.cacheGet("launcher.calcHistory", [])
    readonly property string calcScript: "@HOME@/.config/quickshell/scripts/calc.sh"
    // Only text that reads like arithmetic gets evaluated in apps mode —
    // qalc happily turns "hello world" into a unit soup.
    readonly property bool looksLikeMath: /^\s*[-+(.√]?\d/.test(root.query)
                                         && /[-+*\/^%×÷!]|\bto\b|\bin\b/.test(root.query)
    readonly property string calcInput: root.mode === "calc" || (root.mode === "apps" && root.looksLikeMath)
                                        ? root.query.trim() : ""
    onCalcInputChanged: {
        root.calcCopied = false;
        if (root.calcInput === "") { root.calcResult = ""; root.calcFor = ""; return; }
        calcDebounce.restart();
    }
    Timer {
        id: calcDebounce
        interval: 120
        onTriggered: {
            if (calcProc.running) { calcDebounce.restart(); return; }
            calcProc.forExpr = root.calcInput;
            calcProc.command = ["bash", root.calcScript, root.calcInput];
            calcProc.running = true;
        }
    }
    Process {
        id: calcProc
        property string forExpr: ""
        stdout: StdioCollector {
            onStreamFinished: {
                if (calcProc.forExpr !== root.calcInput) return;
                const r = this.text.trim();
                root.calcResult = r !== calcProc.forExpr ? r : "";
                root.calcFor = calcProc.forExpr;
            }
        }
    }
    Process { id: copyProc }
    function copyCalc() {
        if (root.calcResult === "") return;
        copyProc.command = ["wl-copy", "--", root.calcResult];
        copyProc.running = true;
        root.calcCopied = true;
        const h = root.calcHistory.filter(e => e.expr !== root.calcFor);
        h.unshift({ expr: root.calcFor, result: root.calcResult });
        root.calcHistory = h.slice(0, 20);
        IslandState.cacheSet("launcher.calcHistory", root.calcHistory);
    }

    // ── run list ──────────────────────────────────────────────────
    // Everything the shell can open, by name, so nobody has to remember
    // Super+Comma to find the settings.
    readonly property var commands: {
        const scr = IslandState.toolScreen;
        const out = [
            { glyph: "\u{f0493}", name: "Settings", comment: "Shell settings window",
              act: () => { IslandState.closeCard(); IslandState.openSettings(); } },
            { glyph: "\u{f0e09}", name: "Wallpapers", comment: "Browse the wallpapers of a theme",
              act: () => { IslandState.closeCard(); IslandState.openWallpapers(""); } },
            { glyph: "\u{f033e}", name: "Lock screen", comment: "Lock the session now",
              act: () => { IslandState.closeCard(); IslandState.requestLock(); } },
            { glyph: "\u{f009b}", name: IslandState.cfg.dnd ? "Silent mode off" : "Silent mode on",
              comment: IslandState.cfg.dnd ? "Toasts and app sounds come back" : "Toasts and app sounds stop; history still collects",
              act: () => { IslandState.setPref("dnd", !IslandState.cfg.dnd); IslandState.closeCard(); } },
            { glyph: "\u{f0379}", name: IslandState.notch ? "Switch to island" : "Switch to notch",
              comment: "Top centre shape",
              act: () => { IslandState.toggleMode(); IslandState.closeCard(); } }
        ];
        const tools = IslandState.tools;
        for (let i = 0; i < tools.length; i++) {
            const t = tools[i];
            if (t.id === "apps" || t.needs) continue;
            out.push({ glyph: t.glyph, name: t.name, comment: "Open in the island",
                       act: () => IslandState.openTool(t.id, scr) });
        }
        return out;
    }

    readonly property var results: {
        if (root.mode === "calc") return [];
        if (root.mode === "run") {
            const q = IslandState.searchVariants(root.query);
            const c = root.commands;
            if (q.length === 0) return c;
            const starts = [], rest = [];
            for (let i = 0; i < c.length; i++) {
                if (IslandState.searchPrefix(c[i].name, q)) starts.push(c[i]);
                else if (IslandState.searchHit(c[i].name + " " + c[i].comment, q)) rest.push(c[i]);
            }
            return starts.concat(rest);
        }
        const all = DesktopEntries.applications.values;
        const q = IslandState.searchVariants(root.query);
        const out = [];
        for (let i = 0; i < all.length; i++) {
            const a = all[i];
            if (a.noDisplay) continue;
            if (q.length === 0) { out.push(a); continue; }
            if (IslandState.searchHit(a.name + " " + (a.genericName || "") + " " + (a.comment || ""), q)) out.push(a);
        }
        out.sort((x, y) => {
            if (q.length !== 0) {
                const xs = IslandState.searchPrefix(x.name, q) ? 0 : 1;
                const ys = IslandState.searchPrefix(y.name, q) ? 0 : 1;
                if (xs !== ys) return xs - ys;
            }
            return x.name.localeCompare(y.name);
        });
        return out;
    }

    onResultsChanged: if (selected >= results.length) selected = Math.max(0, results.length - 1)

    // Called by the card once the sheet is loaded — the same hook the
    // clipboard tool uses to take the keyboard.
    function reload() {
        root.mode = "apps";
        root.query = "";
        root.selected = 0;
        search.text = "";
        search.forceActiveFocus();
    }

    // Single-instance apps — every JetBrains IDE, and most Electron ones —
    // hand a second launch off to the already-running process and then exit
    // without raising anything, which from here is indistinguishable from the
    // launcher doing nothing at all. So an entry whose window already exists
    // gets focused rather than spawned. Hyprland's address needs the 0x that
    // HyprlandToplevel.address drops; lastIpcObject carries the class.
    function runningToplevel(entry) {
        const want = (entry.startupClass || "").toLowerCase();
        if (want === "") return null;
        const tls = Hyprland.toplevels.values;
        for (let i = 0; i < tls.length; i++) {
            const ipc = tls[i].lastIpcObject;
            if (ipc && String(ipc.class).toLowerCase() === want) return tls[i];
        }
        return null;
    }

    // forceNew (Ctrl+Enter / Ctrl+click) is the escape hatch for apps you do
    // want a second window of — terminals, file managers, browsers.
    function run(i, forceNew) {
        if (root.mode === "calc" || (root.results.length === 0 && root.calcResult !== "")) {
            root.copyCalc();
            return;
        }
        if (i < 0 || i >= root.results.length) return;
        if (root.mode === "run") { root.results[i].act(); return; }
        const entry = root.results[i];
        const tl = forceNew ? null : runningToplevel(entry);
        if (tl) Hyprland.dispatch('hl.dsp.focus({ window = "address:0x' + tl.address + '" })');
        else entry.execute();
        IslandState.closeCard();
    }

    function moveSelection(delta) {
        const n = root.results.length;
        if (n === 0) return;
        root.selected = Math.max(0, Math.min(n - 1, root.selected + delta));
    }

    Column {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        // search row — the control the launcher *is*, so it gets the filled
        // M3 field with the palette's focus ring.
        Rectangle {
            width: parent.width
            height: 38
            radius: 19
            color: Qt.rgba(root.theme.surface_container_high.r, root.theme.surface_container_high.g,
                           root.theme.surface_container_high.b, 0.85)
            border.width: 2
            border.color: search.activeFocus ? Qt.alpha(root.theme.primary, 0.45)
                                             : Qt.alpha(root.theme.outline, 0.25)
            Behavior on border.color { ColorAnimation { duration: 130 } }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: root.mode === "calc" ? "\u{f00ec}" : root.mode === "run" ? "\u{f0bdf}" : "\u{f0349}"
                font.family: root.theme.fontMono
                font.pixelSize: 15
                color: root.theme.primary
            }

            TextInput {
                id: search
                anchors.left: parent.left
                anchors.leftMargin: 38
                anchors.right: countLabel.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                onTextChanged: {
                    if (root.mode === "apps" && text.length > 0) {
                        const p = text.charAt(0);
                        if (p === "=") { root.mode = "calc"; text = text.slice(1); return; }
                        if (p === ">") { root.mode = "run"; text = text.slice(1); return; }
                        if (p === ":" && text.length === 1) { root.setMode("clipboard"); return; }
                    }
                    root.query = text;
                    root.selected = 0;
                }
                color: root.theme.on_surface
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(14)
                selectionColor: Qt.alpha(root.theme.primary, 0.35)
                selectByMouse: true
                clip: true

                Text {
                    anchors.fill: parent
                    visible: search.text === ""
                    text: root.mode === "calc" ? "Calculate…  12*8 · 10 km to mi · 20 usd to eur · 100 + 10%"
                        : root.mode === "run" ? "Run a shell command…"
                        : "Search applications…   = calc  ·  > run  ·  : clipboard"
                    color: Qt.alpha(root.theme.on_surface_variant, 0.70)
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(14)
                    verticalAlignment: Text.AlignVCenter
                }

                Keys.onEscapePressed: (e) => {
                    IslandState.closeCard();
                    e.accepted = true;
                }
                Keys.onReturnPressed: (e) => root.run(root.selected, (e.modifiers & Qt.ControlModifier) !== 0)
                Keys.onEnterPressed: (e) => root.run(root.selected, (e.modifiers & Qt.ControlModifier) !== 0)
                Keys.onDownPressed: root.moveSelection(1)
                Keys.onUpPressed: root.moveSelection(-1)
                Keys.onPressed: (e) => {
                    if (e.key === Qt.Key_Backspace && search.text === "" && root.mode !== "apps") {
                        root.setMode("apps");
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Tab && (e.modifiers & Qt.ControlModifier)) {
                        const order = ["apps", "calc", "run"];
                        root.setMode(order[(order.indexOf(root.mode) + 1) % order.length]);
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Tab) {
                        root.selected = (root.selected + 1) % Math.max(1, root.results.length);
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Backtab) {
                        const n = Math.max(1, root.results.length);
                        root.selected = (root.selected - 1 + n) % n;
                        e.accepted = true;
                    } else if (e.key === Qt.Key_PageDown) {
                        root.moveSelection(6); e.accepted = true;
                    } else if (e.key === Qt.Key_PageUp) {
                        root.moveSelection(-6); e.accepted = true;
                    }
                }
            }

            Text {
                id: countLabel
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: root.mode === "calc" ? "qalc"
                    : root.results.length + (root.query !== "" ? " found" : root.mode === "run" ? " commands" : " apps")
                color: Qt.alpha(root.theme.on_surface_variant, 0.70)
                font.family: root.theme.fontMono
                font.pixelSize: 10
            }
        }

        // mode strip — the modes are places, so they get chips you can
        // click, with the prefix that jumps there shown beside each.
        Row {
            id: modeRow
            width: parent.width
            height: 26
            spacing: 6
            Repeater {
                model: root.modes
                Rectangle {
                    id: chip
                    required property var modelData
                    readonly property bool on: root.mode === modelData.id
                    width: chipRow.implicitWidth + 20
                    height: 26
                    radius: 13
                    color: on ? root.theme.secondary_container
                         : chipHov.hovered ? Qt.alpha(root.theme.on_surface, 0.10)
                         : Qt.alpha(root.theme.on_surface, 0.05)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: chip.modelData.glyph
                            color: chip.on ? root.theme.on_secondary_container : root.theme.primary
                            font.family: root.theme.fontMono
                            font.pixelSize: 12
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: chip.modelData.name
                            color: chip.on ? root.theme.on_secondary_container : root.theme.on_surface
                            font.family: root.theme.fontSans
                            font.pixelSize: IslandState.ts(11)
                            font.weight: chip.on ? Font.DemiBold : Font.Medium
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: chip.modelData.key !== ""
                            text: chip.modelData.key
                            color: Qt.alpha(chip.on ? root.theme.on_secondary_container : root.theme.on_surface_variant, 0.6)
                            font.family: root.theme.fontMono
                            font.pixelSize: 10
                        }
                    }
                    HoverHandler { id: chipHov; cursorShape: Qt.PointingHandCursor }
                    MouseArea { anchors.fill: parent; onClicked: root.setMode(chip.modelData.id) }
                }
            }
        }

        // Arithmetic typed straight into the apps search answers inline;
        // Enter copies it once no app matches.
        Rectangle {
            id: inlineCalc
            visible: root.mode === "apps" && root.looksLikeMath && root.calcResult !== ""
            width: parent.width
            height: visible ? 48 : 0
            radius: 12
            color: root.results.length === 0 ? root.theme.secondary_container
                                             : Qt.alpha(root.theme.on_surface, 0.05)
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: "\u{f00ec}"
                color: root.theme.primary
                font.family: root.theme.fontMono
                font.pixelSize: 16
            }
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 44
                anchors.right: inlineHint.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: "= " + root.calcResult
                elide: Text.ElideRight
                color: root.results.length === 0 ? root.theme.on_secondary_container : root.theme.on_surface
                font.family: root.theme.fontDisplay
                font.features: ({ "tnum": 1 })
                font.pixelSize: 20
                font.weight: Font.DemiBold
            }
            Text {
                id: inlineHint
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: root.calcCopied ? "copied" : (root.results.length === 0 ? "↵ copy" : "= for more")
                color: root.calcCopied ? root.theme.success : Qt.alpha(root.theme.on_surface_variant, 0.75)
                font.family: root.theme.fontMono
                font.pixelSize: 10
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.copyCalc()
            }
        }

        Text {
            visible: root.results.length === 0 && root.mode !== "calc" && !inlineCalc.visible
            text: "Nothing matches"
            color: Qt.alpha(root.theme.on_surface_variant, 0.7)
            font.family: root.theme.fontSans
            font.pixelSize: IslandState.ts(12)
        }

        // ── calculator mode ──────────────────────────────────────
        Column {
            id: calcPane
            visible: root.mode === "calc"
            width: parent.width
            height: visible ? list.height : 0
            spacing: 10

            Rectangle {
                width: parent.width
                height: 92
                radius: 16
                color: root.calcCopied ? Qt.alpha(root.theme.success, 0.16)
                                       : Qt.alpha(root.theme.on_surface, 0.05)
                Behavior on color { ColorAnimation { duration: 160 } }
                Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 18
                    anchors.rightMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        width: parent.width
                        text: root.calcFor !== "" && root.calcResult !== "" ? root.calcFor : "Type an expression"
                        elide: Text.ElideRight
                        color: Qt.alpha(root.theme.on_surface_variant, 0.8)
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(12)
                    }
                    Text {
                        width: parent.width
                        text: root.calcResult !== "" ? root.calcResult : "—"
                        elide: Text.ElideRight
                        color: root.theme.on_surface
                        font.family: root.theme.fontDisplay
                        font.features: ({ "tnum": 1 })
                        font.pixelSize: 34
                        font.weight: Font.Bold
                    }
                }
                Text {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12
                    visible: root.calcResult !== ""
                    text: root.calcCopied ? "copied" : "↵ copy"
                    color: root.calcCopied ? root.theme.success : Qt.alpha(root.theme.on_surface_variant, 0.7)
                    font.family: root.theme.fontMono
                    font.pixelSize: 10
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.copyCalc()
                }
            }

            Text {
                visible: root.calcHistory.length > 0
                text: "Recent"
                color: Qt.alpha(root.theme.on_surface_variant, 0.7)
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(10)
                font.weight: Font.DemiBold
            }

            ListView {
                id: histList
                width: parent.width
                height: parent.height - 92 - 14 - parent.spacing * 2
                model: root.calcHistory
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                delegate: Rectangle {
                    id: hrow
                    required property var modelData
                    width: histList.width
                    height: 32
                    radius: 10
                    color: hh.hovered ? Qt.alpha(root.theme.on_surface, 0.06) : "transparent"
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.right: hres.left
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: hrow.modelData.expr
                        elide: Text.ElideRight
                        color: Qt.alpha(root.theme.on_surface_variant, 0.9)
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(12)
                    }
                    Text {
                        id: hres
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: hrow.modelData.result
                        color: root.theme.on_surface
                        font.family: root.theme.fontDisplay
                        font.features: ({ "tnum": 1 })
                        font.pixelSize: IslandState.ts(13)
                        font.weight: Font.DemiBold
                    }
                    HoverHandler { id: hh; cursorShape: Qt.PointingHandCursor }
                    // A past line comes back into the field to build on.
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { search.text = hrow.modelData.expr; search.forceActiveFocus(); }
                    }
                }
            }
        }

        ListView {
            id: list
            visible: root.mode !== "calc"
            width: parent.width
            height: parent.height - 38 - 26 - 14 - parent.spacing * 3
                    - (inlineCalc.visible ? inlineCalc.height + parent.spacing : 0)
            model: root.results
            currentIndex: root.selected
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            highlightFollowsCurrentItem: false

            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

            ScrollBar { flick: list; theme: root.theme }

            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool isSelected: index === root.selected

                width: list.width
                height: 44
                radius: 12
                // The selected app is a destination — same secondary_container
                // the sidebars and the hub tiles use for "you are here".
                color: isSelected ? root.theme.secondary_container
                     : (hov.hovered ? Qt.alpha(root.theme.on_surface, 0.06) : "transparent")
                Behavior on color { ColorAnimation { duration: 110 } }

                IconImage {
                    id: icon
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28; height: 28
                    visible: !row.modelData.glyph
                    source: row.modelData.glyph ? "" : Quickshell.iconPath(row.modelData.icon, "application-x-executable")
                    asynchronous: true
                }
                Text {
                    anchors.centerIn: icon
                    visible: !!row.modelData.glyph
                    text: row.modelData.glyph || ""
                    color: row.isSelected ? root.theme.on_secondary_container : root.theme.primary
                    font.family: root.theme.fontMono
                    font.pixelSize: 18
                }

                Column {
                    anchors.left: icon.right
                    anchors.leftMargin: 12
                    anchors.right: parent.right
                    anchors.rightMargin: 40
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Text {
                        width: parent.width
                        text: row.modelData.name
                        color: row.isSelected ? root.theme.on_secondary_container : root.theme.on_surface
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(13)
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: row.modelData.comment || row.modelData.genericName || ""
                        visible: text !== ""
                        color: row.isSelected ? Qt.alpha(root.theme.on_secondary_container, 0.75)
                                              : Qt.alpha(root.theme.on_surface_variant, 0.85)
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(10)
                        elide: Text.ElideRight
                    }
                }

                // The return glyph on the selected row: the keyboard is this
                // tool's native input, so the affordance is a key.
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    visible: row.isSelected
                    text: "\u{f0311}"
                    color: Qt.alpha(root.theme.on_secondary_container, 0.75)
                    font.family: root.theme.fontMono
                    font.pixelSize: 14
                }

                HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
                MouseArea {
                    anchors.fill: parent
                    onClicked: (mouse) => root.run(row.index, (mouse.modifiers & Qt.ControlModifier) !== 0)
                }
            }
        }

        // footer: the two keys worth knowing. ctrl+enter is otherwise
        // undiscoverable.
        Text {
            width: parent.width
            height: 14
            horizontalAlignment: Text.AlignRight
            text: root.mode === "calc" ? "↵ copy   ·   ⌫ on empty back to apps   ·   ctrl+tab next mode"
                : root.mode === "run" ? "↵ run   ·   ⌫ on empty back to apps   ·   ctrl+tab next mode"
                : "↵ open   ·   ctrl+↵ new window   ·   ctrl+tab mode   ·   esc close"
            color: Qt.alpha(root.theme.on_surface_variant, 0.60)
            font.family: root.theme.fontMono
            font.pixelSize: 10
        }
    }
}
