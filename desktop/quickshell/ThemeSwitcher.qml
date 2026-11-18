import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets

// The theme switcher, which replaced the wallpaper picker on Super+W. A theme
// is a colour family (~/.config/hypr/themes.json) and owns only the
// wallpapers whose colours belong to it — wallpaper-index.py sorts every
// still and Wallpaper Engine scene into exactly one theme — so browsing Green
// shows green wallpapers and nothing else.
//
// Picking a wallpaper applies it together with its theme to the chosen scope:
// every monitor, or one. The bar, island, dock and OSD of a monitor wear that
// monitor's theme; GTK, Qt, rofi, nvim and the terminals follow the theme
// applied last. "Apply" on the theme row does the same with random stills
// from the theme. Window frames are never recoloured.
//
// The panel itself wears the theme being browsed, so the colours can be
// judged before anything is applied.
PanelWindow {
    id: root

    property var theme
    property var targetScreen: null

    readonly property string script: "@HOME@/.config/hypr/scripts/wallpapers.py"
    readonly property string cacheDir: "@HOME@/.cache/quickshell/themes/"

    // From `wallpapers.py theme-list`: [{id, name, primary, swatches, css}].
    property var themes: []
    // The wallpaper index: [{kind, path, id, name, thumb, theme}].
    property var entries: []
    // output name -> its entry in wallpapers.json ({kind, path|id, theme}).
    property var applied: ({})
    property string system: "mono"

    // "all" or an output name: where the next pick lands. Reset on every
    // open so the common case stays one keystroke.
    property string target: "all"
    // The theme whose wallpapers are on show (and whose colours the panel
    // wears). Browsing never applies anything by itself.
    property string browse: "mono"
    property string kind: ""
    property string query: ""
    property int selected: 0

    // Left to right, the way they sit on the desk.
    readonly property var outputs: {
        const all = Array.from(Quickshell.screens);
        all.sort((a, b) => a.x - b.x || a.y - b.y);
        return all.map(s => s.name);
    }

    function themeOf(output) {
        const e = root.applied[output];
        return e && e.theme ? e.theme : root.system;
    }
    function themeInfo(id) {
        for (let i = 0; i < root.themes.length; i++)
            if (root.themes[i].id === id) return root.themes[i];
        return null;
    }
    function themeName(id) {
        const t = root.themeInfo(id);
        return t ? t.name : id;
    }
    // Whether the current scope already wears a theme: every monitor for
    // "all", the one monitor otherwise.
    function worn(id) {
        if (root.target !== "all") return root.themeOf(root.target) === id;
        for (let i = 0; i < root.outputs.length; i++)
            if (root.themeOf(root.outputs[i]) !== id) return false;
        return root.outputs.length > 0;
    }

    readonly property var counts: {
        const c = {};
        for (let i = 0; i < entries.length; i++) {
            const t = entries[i].theme;
            c[t] = (c[t] || 0) + 1;
        }
        return c;
    }

    readonly property var results: {
        const q = query.trim().toLowerCase();
        const qv = IslandState.searchVariants(q);
        const out = [];
        for (let i = 0; i < entries.length; i++) {
            const e = entries[i];
            if (e.theme !== browse) continue;
            if (kind !== "" && e.kind !== kind) continue;
            if (q !== "" && !IslandState.searchHit(e.name, qv)) continue;
            out.push(e);
        }
        return out;
    }
    onResultsChanged: if (selected >= results.length) selected = Math.max(0, results.length - 1)

    // The colours of the theme being browsed, straight from the palette
    // wallpapers.py rendered for it.
    Theme {
        id: pal
        file: root.cacheDir + root.browse + ".css"
    }

    function focusedScreen() {
        const want = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        const all = Quickshell.screens;
        for (let i = 0; i < all.length; i++) if (all[i].name === want) return all[i];
        return all.length > 0 ? all[0] : null;
    }

    function moveTheme(delta) {
        const n = root.themes.length;
        if (n === 0) return;
        let i = 0;
        for (let k = 0; k < n; k++) if (root.themes[k].id === root.browse) i = k;
        root.browse = root.themes[(i + delta + n) % n].id;
        root.selected = 0;
        grid.positionViewAtBeginning();
    }

    function cycleTarget() {
        const opts = ["all"].concat(root.outputs);
        root.target = opts[(opts.indexOf(root.target) + 1) % opts.length];
    }

    // Applying takes a few seconds end to end (swww's transition, then the
    // palette pass), and flipping running=true on a Process that is still
    // running is a no-op. Latest-wins instead: remember the newest pick, stop
    // the in-flight run, and start the pick once it has exited. Stopping
    // mid-way is safe: the state file is written atomically before anything
    // else and the palette worker is a separate, detached process.
    Process {
        id: applyProc
        property var pending: null
        onExited: {
            if (pending) {
                command = pending;
                pending = null;
                running = true;
            }
        }
    }

    function run(cmd) {
        if (applyProc.running) {
            applyProc.pending = cmd;
            applyProc.running = false;
        } else {
            applyProc.command = cmd;
            applyProc.running = true;
        }
    }

    // Deliberately leaves the panel up: the badges repaint from
    // wallpapers.json as soon as the pick lands, so picks can be compared
    // without reopening. Esc is the way out.
    function apply(i) {
        if (i < 0 || i >= root.results.length) return;
        const e = root.results[i];
        if (e.kind === "we")
            root.run(["python3", root.script, "set-we", root.target, e.id, root.browse]);
        else
            root.run(["python3", root.script, "set", root.target, e.path, root.browse]);
    }

    function applyTheme() {
        if ((root.counts[root.browse] || 0) === 0) return;
        root.run(["python3", root.script, "apply", root.target, root.browse]);
    }

    function randomAll() {
        root.run(["python3", root.script, "random", "all"]);
    }

    function open() {
        query = ""; kind = ""; selected = 0; target = "all";
        targetScreen = focusedScreen();
        browse = themeOf(targetScreen ? targetScreen.name : "");
        indexProc.running = true;
        listProc.running = true;
        visible = true;
        armGrab.restart();
        // Hiding the window does not destroy the GridView, so without this a
        // reopen resumes at whatever row was last scrolled to.
        grid.positionViewAtBeginning();
        input.forceActiveFocus();
    }
    function close() { armGrab.stop(); grab.active = false; visible = false; }
    function browseTheme(theme) {
        if (!root.visible) root.open();
        root.browse = theme;
        root.selected = 0;
        grid.positionViewAtBeginning();
    }
    function toggle() { if (visible) close(); else open(); }

    FileView {
        id: indexFile
        path: "@HOME@/.cache/quickshell/wallpapers/index.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.entries = JSON.parse(text()); } catch (e) { root.entries = []; }
        }
    }

    // Rescan on open so wallpapers added since the last run show up. The
    // script reuses cached thumbnails and verdicts, so this is a stat pass
    // unless something changed.
    Process {
        id: indexProc
        command: ["python3", "@HOME@/.config/quickshell/scripts/wallpaper-index.py"]
        onExited: indexFile.reload()
    }

    Process {
        id: listProc
        command: ["python3", root.script, "theme-list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.themes = JSON.parse(text).themes; } catch (e) { }
            }
        }
    }

    // What is on each output and which theme it wears, including picks made
    // by Super+Shift+W, the island's theme tool or the command line.
    FileView {
        path: "@HOME@/.config/hypr/wallpapers.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.applied = JSON.parse(text()) || {}; } catch (e) { root.applied = {}; }
        }
    }

    FileView {
        path: "@HOME@/.config/hypr/theme.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { root.system = JSON.parse(text()).system || "mono"; } catch (e) { }
        }
    }

    visible: false
    focusable: true
    screen: targetScreen
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    color: "transparent"
    implicitWidth: 620
    anchors { top: true; bottom: true; left: true }

    // Click-away close without a full-screen scrim: a focus grab reports the
    // first click landing outside the panel. It must be armed after the
    // surface is mapped — activating it in the same tick that visible flips
    // silently fails (same trap as IslandCard's grab).
    HyprlandFocusGrab {
        id: grab
        windows: [root]
        active: false
        onCleared: root.close()
    }
    Timer { id: armGrab; interval: 120; onTriggered: grab.active = true }

    onVisibleChanged: if (visible) input.forceActiveFocus()

    IpcHandler {
        target: "wallpaper"
        function toggle(): void { root.toggle(); }
        function open(): void { root.open(); }
        function close(): void { root.close(); }
        // Super+Shift+W: a new still on every monitor, each within its own
        // theme, so a re-roll never changes the colours.
        function random(): void { root.randomAll(); }
        // Opens straight onto one theme's wallpapers.
        function browse(theme: string): void { root.browseTheme(theme); }
    }

    Rectangle {
        id: panel
        anchors.fill: parent
        anchors.margins: 10
        radius: 20
        color: pal.surface_container
        border.width: 1
        border.color: Qt.alpha(pal.outline, 0.30)
        Behavior on color { ColorAnimation { duration: 220 } }

        Column {
            id: top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 16
            spacing: 12

            // ── title + scope ─────────────────────────────────────
            Item {
                width: parent.width
                height: 32

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Themes"
                    color: pal.on_surface
                    font.family: pal.fontDisplay
                    font.pixelSize: IslandState.ts(18)
                    font.weight: Font.DemiBold
                }

                // Where a pick lands. Each monitor chip carries a dot in the
                // primary of the theme that monitor wears right now.
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    visible: root.outputs.length > 1

                    Repeater {
                        model: ["all"].concat(root.outputs)

                        Rectangle {
                            id: chip
                            required property var modelData
                            readonly property bool active: root.target === modelData
                            readonly property var info: modelData === "all" ? null
                                                        : root.themeInfo(root.themeOf(modelData))

                            width: chipRow.implicitWidth + 20
                            height: 30
                            radius: 9
                            color: chip.active ? Qt.alpha(pal.primary, 0.20)
                                               : Qt.alpha(pal.on_surface, 0.06)
                            Behavior on color { ColorAnimation { duration: 110 } }

                            Row {
                                id: chipRow
                                anchors.centerIn: parent
                                spacing: 6

                                Rectangle {
                                    visible: chip.info !== null
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 8; height: 8; radius: 4
                                    color: chip.info ? chip.info.primary : "transparent"
                                    border.width: 1
                                    border.color: Qt.alpha(pal.on_surface, 0.25)
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: chip.modelData === "all" ? "All monitors" : chip.modelData
                                    color: chip.active ? pal.primary : pal.on_surface_variant
                                    font.family: pal.fontSans
                                    font.pixelSize: IslandState.ts(12)
                                    font.weight: Font.DemiBold
                                }
                            }

                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.target = chip.modelData
                            }
                        }
                    }
                }
            }

            // ── themes ────────────────────────────────────────────
            Row {
                id: themeRow
                width: parent.width
                spacing: 4

                Repeater {
                    model: root.themes

                    Rectangle {
                        id: tile
                        required property var modelData
                        readonly property bool current: root.browse === modelData.id
                        readonly property bool wearing: root.worn(modelData.id)
                        readonly property int n: root.counts[modelData.id] || 0

                        width: (themeRow.width - themeRow.spacing * (root.themes.length - 1))
                               / Math.max(1, root.themes.length)
                        height: 70
                        radius: 14
                        color: tile.current ? Qt.alpha(pal.on_surface, 0.10)
                             : (tileHov.hovered ? Qt.alpha(pal.on_surface, 0.06) : "transparent")
                        border.width: tile.current ? 2 : 0
                        border.color: tile.modelData.primary
                        Behavior on color { ColorAnimation { duration: 110 } }

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: 11
                            spacing: -5

                            Repeater {
                                model: tile.modelData.swatches.slice(0, 3)
                                Rectangle {
                                    required property string modelData
                                    width: 18; height: 18; radius: 9
                                    color: modelData
                                    border.width: 2
                                    border.color: pal.surface_container
                                }
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 20
                            text: tile.modelData.name
                            color: tile.current ? pal.on_surface : pal.on_surface_variant
                            font.family: pal.fontSans
                            font.pixelSize: IslandState.ts(11)
                            font.weight: tile.current ? Font.DemiBold : Font.Normal
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 7
                            text: tile.n
                            color: Qt.alpha(pal.on_surface_variant, 0.6)
                            font.family: pal.fontMono
                            font.pixelSize: 9
                        }

                        // The scope already wears this theme.
                        Rectangle {
                            visible: tile.wearing
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 5
                            width: 14; height: 14; radius: 7
                            color: tile.modelData.primary
                            Text {
                                anchors.centerIn: parent
                                text: "\u{f012c}"
                                color: pal.surface_container
                                font.family: pal.fontMono
                                font.pixelSize: 9
                            }
                        }

                        HoverHandler { id: tileHov; cursorShape: Qt.PointingHandCursor }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                root.browse = tile.modelData.id;
                                root.selected = 0;
                                grid.positionViewAtBeginning();
                                input.forceActiveFocus();
                            }
                        }
                    }
                }
            }

            // ── search, kind, apply ───────────────────────────────
            Row {
                width: parent.width
                spacing: 8

                Rectangle {
                    id: searchBox
                    width: parent.width - kindRow.width - applyBtn.width - parent.spacing * 2
                    height: 36
                    radius: 11
                    color: Qt.alpha(pal.on_surface, 0.06)
                    border.width: 1
                    border.color: input.activeFocus ? Qt.alpha(pal.primary, 0.45) : "transparent"

                    Text {
                        id: searchGlyph
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u{f0349}"
                        font.family: pal.fontMono
                        font.pixelSize: 15
                        color: pal.primary
                    }

                    TextInput {
                        id: input
                        anchors.left: searchGlyph.right
                        anchors.leftMargin: 9
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.query
                        onTextChanged: { root.query = text; root.selected = 0; }
                        color: pal.on_surface
                        font.family: pal.fontSans
                        font.pixelSize: IslandState.ts(14)
                        selectionColor: Qt.alpha(pal.primary, 0.35)
                        clip: true

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: input.text === ""
                            text: "Search " + root.themeName(root.browse) + " wallpapers…"
                            color: Qt.alpha(pal.on_surface_variant, 0.7)
                            font.family: pal.fontSans
                            font.pixelSize: IslandState.ts(14)
                        }

                        // Every plain key belongs to the search, so the
                        // panel's own actions sit on Tab and Ctrl.
                        Keys.onPressed: (e) => {
                            const ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
                            if (e.key === Qt.Key_Tab) { root.moveTheme(1); e.accepted = true; }
                            else if (e.key === Qt.Key_Backtab) { root.moveTheme(-1); e.accepted = true; }
                            else if (ctrl && e.key === Qt.Key_R) { root.applyTheme(); e.accepted = true; }
                            else if (ctrl && e.key === Qt.Key_M) { root.cycleTarget(); e.accepted = true; }
                        }
                        Keys.onEscapePressed: root.close()
                        Keys.onReturnPressed: root.apply(root.selected)
                        Keys.onEnterPressed: root.apply(root.selected)
                        Keys.onLeftPressed: root.selected = Math.max(root.selected - 1, 0)
                        Keys.onRightPressed: root.selected = Math.min(root.selected + 1, root.results.length - 1)
                        Keys.onUpPressed: root.selected = Math.max(root.selected - grid.columns, 0)
                        Keys.onDownPressed: root.selected = Math.min(root.selected + grid.columns, root.results.length - 1)
                    }
                }

                Row {
                    id: kindRow
                    spacing: 4

                    Repeater {
                        model: [{ k: "", label: "All" },
                                { k: "image", label: "Stills" },
                                { k: "we", label: "Animated" }]

                        Rectangle {
                            id: kchip
                            required property var modelData
                            readonly property bool active: root.kind === modelData.k
                            width: kLabel.implicitWidth + 18
                            height: 36
                            radius: 11
                            color: kchip.active ? Qt.alpha(pal.primary, 0.20)
                                                : Qt.alpha(pal.on_surface, 0.06)
                            Behavior on color { ColorAnimation { duration: 110 } }
                            Text {
                                id: kLabel
                                anchors.centerIn: parent
                                text: kchip.modelData.label
                                color: kchip.active ? pal.primary : pal.on_surface_variant
                                font.family: pal.fontSans
                                font.pixelSize: IslandState.ts(12)
                                font.weight: Font.DemiBold
                            }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: { root.kind = kchip.modelData.k; root.selected = 0; }
                            }
                        }
                    }
                }

                // The whole theme in one click: random stills from it on the
                // chosen scope.
                Rectangle {
                    id: applyBtn
                    width: applyLabel.implicitWidth + 28
                    height: 36
                    radius: 11
                    color: applyHov.hovered ? Qt.lighter(pal.primary, 1.08) : pal.primary
                    opacity: (root.counts[root.browse] || 0) > 0 ? 1 : 0.4
                    Behavior on color { ColorAnimation { duration: 110 } }

                    Row {
                        id: applyLabel
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\u{f049d}"
                            color: pal.on_primary
                            font.family: pal.fontMono
                            font.pixelSize: 14
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Apply " + root.themeName(root.browse)
                            color: pal.on_primary
                            font.family: pal.fontSans
                            font.pixelSize: IslandState.ts(12)
                            font.weight: Font.DemiBold
                        }
                    }

                    HoverHandler { id: applyHov; cursorShape: Qt.PointingHandCursor }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.applyTheme()
                    }
                }
            }
        }

        // ── wallpapers of the browsed theme ───────────────────────
        GridView {
            id: grid

            readonly property int columns: Math.max(1, Math.floor(width / 268))

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: top.bottom
            anchors.bottom: footer.top
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.topMargin: 12
            anchors.bottomMargin: 8
            cellWidth: Math.floor(width / columns)
            cellHeight: Math.floor(cellWidth * 0.62)
            model: root.results
            currentIndex: root.selected
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            cacheBuffer: 400

            onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Contain)

            ScrollBar {
                flick: grid
                theme: pal
                barWidth: 8
                edgeMargin: 5
                endMargin: 8
                minHandle: 40
                wheelStep: grid.cellHeight
            }

            delegate: Item {
                required property var modelData
                required property int index

                width: grid.cellWidth
                height: grid.cellHeight

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 5
                    radius: 13
                    color: index === root.selected ? Qt.alpha(pal.primary, 0.22)
                         : (cellHov.hovered ? Qt.alpha(pal.on_surface, 0.08) : "transparent")
                    Behavior on color { ColorAnimation { duration: 110 } }

                    ClippingRectangle {
                        id: shot
                        anchors.fill: parent
                        anchors.margins: 4
                        radius: 10
                        color: Qt.alpha(pal.surface, 0.6)

                        // The delegate's ids are not resolvable from inside
                        // ClippingRectangle at runtime, so everything this
                        // child needs is bound through properties, and
                        // markNames works the outputs out inline from plain
                        // property reads, which do resolve.
                        property string src: modelData.thumb
                        property bool animated: modelData.kind === "we"
                        property string markNames: {
                            const outs = root.outputs;
                            const app = root.applied;
                            const hits = [];
                            for (let i = 0; i < outs.length; i++) {
                                const a = app[outs[i]];
                                if (!a || !modelData) continue;
                                if (modelData.kind === "we" ? (a.kind === "we" && a.id === modelData.id)
                                                            : (a.kind === "image" && a.path === modelData.path))
                                    hits.push(outs[i]);
                            }
                            return hits.join(" ");
                        }
                        property int markCount: markNames === "" ? 0 : markNames.split(" ").length
                        property bool everywhere: markCount > 0 && markCount === root.outputs.length
                        property color badgeBg: pal.primary
                        property color badgeFg: pal.on_primary
                        property string sans: pal.fontSans
                        property string mono: pal.fontMono

                        Image {
                            anchors.fill: parent
                            source: "file://" + shot.src
                            sourceSize.width: 420
                            asynchronous: true
                            cache: true
                            fillMode: Image.PreserveAspectCrop
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.right: parent.right
                            height: 26
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "#00000000" }
                                GradientStop { position: 1.0; color: "#cc000000" }
                            }
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.margins: 7
                            width: parent.width - 34
                            text: modelData.name
                            color: "#ffffff"
                            font.family: shot.sans
                            font.pixelSize: IslandState.ts(10)
                            elide: Text.ElideRight
                        }

                        // Wallpaper Engine scene: it moves, and it costs GPU.
                        Text {
                            visible: shot.animated
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 6
                            text: "\u{f040a}"
                            color: "#ffffff"
                            font.family: shot.mono
                            font.pixelSize: IslandState.ts(13)
                        }

                        // A tick when this wallpaper is on every output,
                        // otherwise the names of the outputs showing it.
                        Rectangle {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 6
                            width: shot.everywhere ? 18 : badgeLabel.implicitWidth + 12
                            height: 18
                            radius: 9
                            visible: shot.markCount > 0
                            color: shot.badgeBg
                            Text {
                                id: badgeLabel
                                anchors.centerIn: parent
                                text: shot.everywhere ? "\u{f012c}" : shot.markNames
                                font.family: shot.everywhere ? shot.mono : shot.sans
                                font.pixelSize: shot.everywhere ? 11 : 9
                                font.weight: Font.DemiBold
                                color: shot.badgeFg
                            }
                        }
                    }

                    HoverHandler { id: cellHov }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.selected = index; root.apply(index); }
                    }
                }
            }
        }

        Text {
            anchors.centerIn: grid
            visible: root.results.length === 0
            text: root.entries.length === 0 ? "No wallpapers indexed yet"
                : (root.counts[root.browse] || 0) === 0 ? "No wallpapers in " + root.themeName(root.browse)
                : "Nothing matches that filter"
            color: Qt.alpha(pal.on_surface_variant, 0.8)
            font.family: pal.fontSans
            font.pixelSize: IslandState.ts(14)
        }

        // ── footer ────────────────────────────────────────────────
        Item {
            id: footer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 16
            height: 52

            Column {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Text {
                    text: "Apps & terminal follow " + root.themeName(root.system)
                    color: pal.on_surface_variant
                    font.family: pal.fontSans
                    font.pixelSize: IslandState.ts(12)
                }
                Text {
                    text: "Window frames, app and tray icons keep their own colours"
                    color: Qt.alpha(pal.on_surface_variant, 0.65)
                    font.family: pal.fontSans
                    font.pixelSize: IslandState.ts(10)
                }
            }

            Column {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Text {
                    anchors.right: parent.right
                    text: root.results.length + " wallpapers"
                    color: Qt.alpha(pal.on_surface_variant, 0.6)
                    font.family: pal.fontMono
                    font.pixelSize: 10
                }
                Text {
                    anchors.right: parent.right
                    text: "⇥ theme  ·  ↵ apply  ·  ^R shuffle  ·  ^M monitor"
                    color: Qt.alpha(pal.on_surface_variant, 0.55)
                    font.family: pal.fontMono
                    font.pixelSize: 10
                }
            }
        }
    }
}
