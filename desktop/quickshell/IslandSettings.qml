import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// The shell's settings app: an ordinary floating window (xdg toplevel, not a
// layer over the screen), so it takes focus, moves, closes and shows up in
// the dock like any app. `quickshell-settings.desktop` ("Settings") puts it in the
// launcher; hyprland.lua floats and centres it by its title. It edits the
// island and the dock live. Every row
// writes straight into IslandState's prefs adapter, which persists to
// island-prefs.json and feeds the bindings the pill and card already read,
// so the island itself is the preview: rearrange the control-center grid
// here and the hub the pill opens is already wearing it.
FloatingWindow {
    id: root

    property var theme
    property string query: ""
    property string section: "general"

    title: "Settings"
    visible: false
    implicitWidth: 820
    implicitHeight: 560
    minimumSize: Qt.size(720, 480)
    color: "transparent"

    // ── the settings themselves ───────────────────────────────────
    // One registry rather than hand-built panes, because search has to see
    // every row wherever it lives. A row is its section's business only until
    // someone types — then it is a search result like any other.
    // Ordered by purpose, not alphabet: the everyday switches first, then
    // the top of the screen from the outside in, the rest of the desktop,
    // the hardware, and input last. `group` heads a run in the sidebar.
    readonly property var sections: [
        { id: "general",  glyph: "\u{f062e}", name: "General",        group: "" },
        { id: "menubar",  glyph: "\u{f06fc}", name: "Menu bar",       group: "Top bar" },
        { id: "mode",     glyph: "\u{f0379}", name: "Notch",          group: "Top bar" },
        { id: "pill",     glyph: "\u{f0150}", name: "Pill",           group: "Top bar" },
        { id: "island",   glyph: "\u{f0cb5}", name: "Bar & Shape",    group: "Top bar" },
        { id: "card",     glyph: "\u{f0b33}", name: "Card",           group: "Top bar" },
        { id: "cc",       glyph: "\u{f0570}", name: "Control Center", group: "Top bar" },
        { id: "tray",     glyph: "\u{f168e}", name: "Tray",           group: "Top bar" },
        { id: "monitor",  glyph: "\u{f04c5}", name: "Monitoring",     group: "Hardware" },
        { id: "dock",     glyph: "\u{f10a9}", name: "Dock",           group: "Desktop" },
        { id: "gaps",     glyph: "\u{f1487}", name: "Gaps",           group: "Desktop" },
        { id: "corners",  glyph: "\u{f0607}", name: "Corners",        group: "Desktop" },
        { id: "type",     glyph: "\u{f0284}", name: "Font",           group: "Desktop" },
        { id: "displays", glyph: "\u{f037a}", name: "Displays",       group: "Hardware" },
        { id: "sound",    glyph: "\u{f057e}", name: "Sound",          group: "Hardware" },
        { id: "status",   glyph: "\u{f0079}", name: "Devices",        group: "Hardware" },
        { id: "station",  glyph: "\u{f1901}", name: "Power station",  group: "Hardware" },
        { id: "keys",     glyph: "\u{f030c}", name: "Keybinds",       group: "Input" },
        { id: "behavior", glyph: "\u{f0493}", name: "Behavior",       group: "Input" }
    ]
    // The sidebar's rows: the shown sections with a heading wherever the
    // group changes.
    readonly property var sidebarItems: {
        const out = [];
        let last = null;
        for (const sec of root.shownSections) {
            if (sec.group !== last && sec.group !== "") out.push({ header: sec.group });
            last = sec.group;
            out.push(sec);
        }
        return out;
    }

    // The order General lists its rows in. The rows themselves are declared
    // further down, next to the sections they were split off from.
    readonly property var generalKeys: [
        "shellMode", "powerProfile", "dnd", "gameMode", "dock", "menuBar", "topTray", "statusCircle", "clock24h", "liveBars", "desktopUpdates"
    ]

    // A section whose rows all went elsewhere, or mean nothing in the mode in
    // use, drops out of the sidebar instead of opening onto an empty pane.
    readonly property var shownSections: {
        const notch = IslandState.notch;
        const out = [];
        for (let s = 0; s < root.sections.length; s++) {
            const id = root.sections[s].id;
            let keep = id === "cc" || id === "sound" || id === "keys" || id === "displays"
                || id === "monitor" || id === "tray";
            for (let i = 0; !keep && i < root.registry.length; i++) {
                const r = root.registry[i];
                keep = r.section === id && !(r.notchOnly && !notch) && !(r.islandOnly && notch) && !(r.syncOnly && !IslandState.syncInstalled)
                    && !(r.stationOnly && !IslandState.stationKnown);
            }
            if (keep) out.push(root.sections[s]);
        }
        return out;
    }

    // Every family Qt can draw, for the font picker.
    readonly property var installedFonts: Qt.fontFamilies()

    readonly property var registry: [
        { section: "general", type: "choice", key: "shellMode",
          label: "Top centre shape",
          desc: "Each keeps its own look · every other section edits the one in use",
          choices: [ { id: "island", label: "Island" }, { id: "notch", label: "Notch" } ] },
        { section: "mode", type: "slider", key: "earRadius", notchOnly: true,
          label: "Ear radius", desc: "The concave fillets that melt the top corners into the bezel",
          min: 0, max: 20, step: 1, fmt: "px" },
        { section: "mode", type: "slider", key: "notchRadius", notchOnly: true,
          label: "Bottom corner radius", desc: "",
          min: 4, max: 24, step: 1, fmt: "px" },
        { section: "mode", type: "toggle", key: "pureBlack", notchOnly: true,
          label: "Pure black", desc: "Reads as a hardware cutout · off uses the theme's island fill" },
        { section: "mode", type: "toggle", key: "notchShadow", notchOnly: true,
          label: "Drop shadow", desc: "A soft shadow under the notch" },
        { section: "mode", type: "toggle", key: "hoverOpen", notchOnly: true,
          label: "Open on hover", desc: "Resting the pointer on the notch opens the control center" },
        { section: "mode", type: "slider", key: "hoverOpenMs", notchOnly: true,
          label: "Hover delay", desc: "",
          min: 150, max: 1200, step: 25, fmt: "ms" },
        { section: "pill", type: "order", key: "pillLayout",
          label: "Layout", desc: "Pill pieces · order · hide · drag · move · arrange" },
        { section: "pill", type: "choice", key: "artStyle",
          label: "Album art while a player is up",
          desc: "Circle detaches it beside the pill, the Duo look",
          choices: [ { id: "circle", label: "Circle" }, { id: "pill", label: "In pill" }, { id: "off", label: "Hidden" } ] },
        { section: "general", type: "choice", key: "powerProfile",
          label: "Power profile", desc: "power-profiles-daemon · applies at once",
          choices: [ { id: "saver", label: "Saver" }, { id: "balanced", label: "Balanced" }, { id: "performance", label: "Performance" } ] },
        { section: "general", type: "toggle", key: "desktopUpdates", syncOnly: true,
          label: "Desktop updates",
          desc: "Pull new versions of this desktop every hour · off keeps your config exactly as it is" },
        { section: "general", type: "toggle", key: "liveBars",
          label: "Live audio canvas",
          desc: "Media bars while a player plays, the call waveform during a call",
          barIdle: "Island only · the menu bar's Now playing item always draws its bars" },
        { section: "general", type: "toggle", key: "clock24h",
          label: "24-hour clock",
          desc: "Off shows 12-hour with AM/PM · the lock screen follows the active mode" },
        { section: "pill", type: "toggle", key: "revealSeconds",
          label: "Seconds on hover", desc: "Off hides them everywhere" },
        { section: "pill", type: "toggle", key: "alwaysSeconds",
          label: "Seconds always visible", desc: "Also turns on hover" },
        { section: "pill", type: "toggle", key: "revealDate",
          label: "Date on hover", desc: "Off hides it everywhere" },
        { section: "pill", type: "toggle", key: "alwaysDate",
          label: "Date always visible", desc: "Also turns on hover" },
        { section: "pill", type: "toggle", key: "revealUtc",
          label: "UTC clock on hover", desc: "Off hides it everywhere" },
        { section: "pill", type: "toggle", key: "alwaysUtc",
          label: "UTC clock always visible", desc: "Also turns on hover" },
        { section: "pill", type: "toggle", key: "revealWeather",
          label: "Weather on hover",
          desc: "Icon, temperature and conditions · off hides it everywhere" },
        { section: "pill", type: "toggle", key: "alwaysWeather",
          label: "Weather always visible",
          desc: "Icon and temperature; conditions stay on hover · also turns on hover" },
        { section: "pill", type: "toggle", key: "revealWorkspaces",
          label: "Workspaces on hover", desc: "Off hides them everywhere" },
        { section: "pill", type: "toggle", key: "alwaysWorkspaces",
          label: "Workspaces always visible", desc: "Also turns on hover" },
        { section: "pill", type: "toggle", key: "hudInIsland",
          label: "Volume HUD in the pill",
          desc: "Volume and mic changes show here instead of the floating capsule" },
        { section: "pill", type: "toggle", key: "progressLine",
          label: "Track progress line",
          desc: "A hairline along the lower edge while something plays · hidden while the date shows" },
        { section: "pill", type: "toggle", key: "statusLayout",
          label: "Keyboard layout", desc: "Right of the clock, the code of the layout in use" },
        { section: "pill", type: "toggle", key: "statusPrivacy",
          label: "Privacy dots", desc: "Orange while the mic records, green while the screen or a camera is captured" },
        { section: "pill", type: "toggle", key: "statusDnd",
          label: "Silent-mode moon", desc: "Only while silent mode is on" },
        { section: "pill", type: "toggle", key: "statusUnread",
          label: "Unread notifications", desc: "A count, until the bell or the hub is opened" },
        { section: "pill", type: "toggle", key: "statusLoad",
          label: "CPU / GPU load", desc: "Two small rings with the percentage · CPU light, GPU in the accent · click opens Monitoring" },
        { section: "pill", type: "toggle", key: "statusMeeting",
          label: "Next meeting", desc: "A countdown from an hour before, in the event's colour · click joins or opens the calendar" },
        { section: "pill", type: "slider", key: "islandOpacity",
          label: "Island opacity", desc: "",
          min: 0.5, max: 1.0, step: 0.01, fmt: "pct" },
        { section: "general", type: "toggle", key: "statusCircle",
          label: "Status circle",
          desc: "Mouse battery as the ring, network profile inside",
          barIdle: "Island only · the menu bar's Network and Devices items take its place" },
        { section: "status", type: "toggle", key: "airpodsCircle",
          label: "AirPods",
          desc: "While connected · a circle left of the island, or charge in the menu bar's Devices item" },
        { section: "status", type: "toggle", key: "phoneCircle",
          label: "Phone",
          desc: "While its battery is reachable over Bluetooth · a circle beside the AirPods, or charge in Devices" },
        { section: "status", type: "toggle", key: "controllerCircle",
          label: "Controllers",
          desc: "Each connected controller in its own icon and colour, taken from its Bluetooth name · a circle, or charge in Devices" },
        { section: "status", type: "toggle", key: "mouseCircle",
          label: "Mouse",
          desc: "While it reports a charge · a circle beside the island (the status circle's ring covers it while that is on), or charge in Devices" },
        { section: "status", type: "toggle", key: "stationCircle", stationOnly: true,
          label: "Power station",
          desc: "While the oukitel daemon reaches it · a circle beside the island, or charge in the menu bar's Devices item" },
        { section: "status", type: "slider", key: "statusWarnPct",
          label: "Low battery warning", desc: "Rings and the menu bar's charge turn to the warning tone at or below this",
          min: 5, max: 50, step: 5, fmt: "pctInt" },
        { section: "status", type: "choice", key: "statusClick",
          label: "Click opens", desc: "",
          barIdle: "Island only · what the status circle's click opens",
          choices: [ { id: "hub", label: "Hub" }, { id: "battery", label: "Batteries" }, { id: "monitor", label: "Monitoring" } ] },
        { section: "station", type: "toggle", key: "stationAlert", stationOnly: true,
          label: "Low-charge alert",
          desc: "A notification once per dip below Devices → Low battery warning, and the pill's warning while it lasts · only when it is not charging" },
        { section: "station", type: "slider", key: "stationFlowMax", stationOnly: true,
          label: "Power bar scale", desc: "The wattage that fills the menu bar's input and output bars",
          min: 200, max: 3000, step: 100, fmt: "w" },
        { section: "station", type: "slider", key: "stationCapacityWh", stationOnly: true,
          label: "Battery capacity", desc: "Used to estimate how long the battery carries the load when the station is not discharging · P2001E Pro = 2048 Wh",
          min: 500, max: 5000, step: 64, fmt: "wh" },
        { section: "general", type: "toggle", key: "menuBar",
          label: "Menu bar",
          desc: "Full-width bar · distro menu and app on the left · tray, status and date on the right" },
        { section: "menubar", type: "barorder", key: "barLayout",
          label: "Bar layout", desc: "Menu bar items · order · side · hide · drag · arrange" },
        { section: "menubar", type: "slider", key: "barHeight",
          label: "Height", desc: "0 follows the notch or island · taller leaves the notch hanging inside",
          min: 0, max: 56, step: 1, fmt: "px" },
        { section: "menubar", type: "slider", key: "barPad",
          label: "Item padding", desc: "Room inside each item, around its icon or text",
          min: 2, max: 16, step: 1, fmt: "px" },
        { section: "menubar", type: "slider", key: "barSpacing",
          label: "Gap between items", desc: "",
          min: 0, max: 20, step: 1, fmt: "px" },
        { section: "menubar", type: "slider", key: "barMargin",
          label: "Edge margin", desc: "Space at the left and right ends of the screen",
          min: 0, max: 48, step: 1, fmt: "px" },
        { section: "menubar", type: "slider", key: "barIconSize",
          label: "Icon size", desc: "Status and monitoring icons · the rest follow it",
          min: 11, max: 22, step: 1, fmt: "px" },
        { section: "menubar", type: "slider", key: "barFontSize",
          label: "Text size", desc: "App name, menus, date · figures run a size smaller",
          min: 10, max: 17, step: 1, fmt: "px" },
        { section: "menubar", type: "slider", key: "barOpacity",
          label: "Background opacity", desc: "The band behind the items · blurred underneath",
          min: 0, max: 1, step: 0.05, fmt: "pct" },
        { section: "menubar", type: "toggle", key: "barClearWhenEmpty",
          label: "Clear on an empty desktop", desc: "No background while the monitor's workspace has no windows" },
        { section: "menubar", type: "toggle", key: "barDivider",
          label: "Bottom hairline", desc: "A faint line along the bar's lower edge" },
        { section: "gaps", type: "slider", key: "winGapsIn",
          label: "Between windows", desc: "Space between neighbouring windows · kept apart for menu bar on and off",
          min: 0, max: 30, step: 1, fmt: "px" },
        { section: "gaps", type: "slider", key: "winGapsOut",
          label: "At the screen edges", desc: "Space to the bar, dock and screen edges · kept apart for menu bar on and off",
          min: 0, max: 40, step: 1, fmt: "px" },
        { section: "gaps", type: "slider", key: "winRounding",
          label: "Window rounding", desc: "Corner radius of every window · the fill under the bar follows it",
          min: 0, max: 24, step: 1, fmt: "px" },
        { section: "gaps", type: "slider", key: "winBorder",
          label: "Window frame", desc: "Border width around windows · 0 for none",
          min: 0, max: 6, step: 1, fmt: "px" },
        { section: "corners", type: "slider", key: "cornerRadius",
          label: "Screen corner radius", desc: "Rounded screen corners · 0 keeps them square",
          min: 0, max: 32, step: 1, fmt: "px" },
        { section: "corners", type: "toggle", key: "cornersTop",
          label: "Round the top corners", desc: "Black corners at the top, rounding off the bar's ends like a MacBook" },
        { section: "corners", type: "toggle", key: "barFillets",
          label: "Fill under the bar", desc: "The bar flows into the windows' rounded corners at the screen edges · sized by Gaps → Window rounding" },
        { section: "corners", type: "toggle", key: "cornersBottom",
          label: "Round the bottom corners", desc: "Black corners at the bottom, like the display's glass" },
        { section: "corners", type: "toggle", key: "cornerDots",
          label: "Privacy dots in the corner", desc: "Mic and camera dots top-right while a fullscreen app hides the bar, or the bar is off" },
        { section: "general", type: "toggle", key: "topTray",
          label: "Tray on the top bar",
          desc: "App icons at the right end of the bar · click activates, right-click opens the menu in the island",
          barIdle: "Island only · the menu bar has its own Tray item (Settings → Menu bar)" },
        { section: "island", type: "slider", key: "pillHeight",
          label: "Pill height", desc: "At rest · every value here is kept apart for menu bar on and off",
          min: 30, max: 52, step: 1, fmt: "px" },
        { section: "island", type: "slider", key: "pillHeightExpanded",
          label: "Expanded height", desc: "On hover and while the card is open · the bar reserves this much",
          min: 34, max: 60, step: 1, fmt: "px" },
        { section: "island", type: "slider", key: "edgeGap", islandOnly: true,
          label: "Gap from screen edge", desc: "",
          min: 0, max: 24, step: 1, fmt: "px" },
        { section: "island", type: "slider", key: "cardGap", islandOnly: true,
          label: "Gap between pill and card", desc: "Also where the polkit prompt hangs",
          min: 4, max: 32, step: 1, fmt: "px" },
        { section: "island", type: "slider", key: "hoverLift", islandOnly: true,
          label: "Stage lift on hover", desc: "The resting island steps down this far under the pointer · 0 is off",
          min: 0, max: 12, step: 1, fmt: "px" },
        { section: "island", type: "toggle", key: "morph",
          label: "Grow from the pill",
          desc: "The card and the polkit prompt stretch out of the pill instead of fading in" },
        { section: "island", type: "slider", key: "morphMs",
          label: "Grow duration", desc: "",
          min: 150, max: 700, step: 10, fmt: "ms" },
        { section: "card", type: "slider", key: "cardWidth",
          label: "Card width", desc: "",
          min: 520, max: 900, step: 5, fmt: "px" },
        { section: "card", type: "slider", key: "cardHeight",
          label: "Card height", desc: "",
          min: 380, max: 700, step: 5, fmt: "px" },
        { section: "card", type: "slider", key: "cardRadius",
          label: "Corner radius", desc: "",
          min: 8, max: 32, step: 1, fmt: "px" },
        { section: "type", type: "slider", key: "textSize", ticks: true,
          label: "Text size", desc: "Every label in the bar, island, dock and lock screen",
          min: 11, max: 15, step: 1, fmt: "px" },
        { section: "type", type: "font", key: "fontBody",
          label: "Body font", desc: "Labels, rows and every small line in the shell" },
        { section: "type", type: "font", key: "fontDisplay",
          label: "Display font", desc: "Large text: clocks, headings, results" },
        { section: "type", type: "choice", key: "clockFont",
          label: "Clock face", desc: "Pill and lock screen · display uses tabular figures so digits never shift",
          choices: [ { id: "display", label: "Display", font: root.theme.fontDisplay }, { id: "mono", label: "Mono", font: "JetBrainsMono Nerd Font" } ] },
        { section: "general", type: "toggle", key: "dock",
          label: "Show dock",
          desc: "Pinned and running apps along the bottom of every monitor" },
        { section: "general", type: "toggle", key: "dnd",
          label: "Silent mode",
          desc: "No toasts, Telegram and Steam sounds muted; history still collects on the bell" },
        { section: "general", type: "choice", key: "gameMode",
          label: "Game mode", desc: "Auto follows the running-game probe",
          choices: [ { id: "auto", label: "Auto" }, { id: "on", label: "On" }, { id: "off", label: "Off" } ] }
    ]

    // Search results replace the section pane. Matching is dumb substring
    // over label, description and section name — with fifteen rows anything
    // smarter is ceremony.
    readonly property bool searching: root.query.trim() !== ""
    readonly property var results: {
        const q = root.query.trim().toLowerCase();
        // Rows that mean nothing in the mode in use are left out: the notch
        // is welded to the edge, so it has no gaps or lift to tune.
        const notch = IslandState.notch;
        // stationOnly rows mean nothing without the oukitel daemon running.
        const fits = (r) => !(r.notchOnly && !notch) && !(r.islandOnly && notch) && !(r.syncOnly && !IslandState.syncInstalled)
            && !(r.stationOnly && !IslandState.stationKnown);
        if (q === "" && root.section === "general") {
            const out = [];
            for (let k = 0; k < root.generalKeys.length; k++)
                for (let i = 0; i < root.registry.length; i++)
                    if (root.registry[i].key === root.generalKeys[k] && fits(root.registry[i]))
                        out.push(root.registry[i]);
            return out;
        }
        if (q === "") {
            const out = [];
            for (let i = 0; i < root.registry.length; i++)
                if (root.registry[i].section === root.section && fits(root.registry[i]))
                    out.push(root.registry[i]);
            return out;
        }
        const qv = IslandState.searchVariants(q);
        const names = {};
        for (let i = 0; i < root.sections.length; i++)
            names[root.sections[i].id] = root.sections[i].name;
        const out = [];
        for (let i = 0; i < root.registry.length; i++) {
            const r = root.registry[i];
            if (IslandState.searchHit(r.label + " " + (r.desc || "") + " " + names[r.section], qv) && fits(r)) out.push(r);
        }
        return out;
    }

    function fmtValue(row, v) {
        if (row.fmt === "pct") return Math.round(v * 100) + "%";
        if (row.fmt === "pctInt") return Math.round(v) + "%";
        if (row.fmt === "ms") return Math.round(v) + " ms";
        if (row.fmt === "w") return Math.round(v) + " W";
        if (row.fmt === "wh") return Math.round(v) + " Wh";
        return Math.round(v) + " px";
    }

    function open() {
        query = "";
        // The field's text binding is dead after the first keystroke
        // (interactive edits overwrite it), so the reset is imperative too —
        // without it a reopened window shows last session's search over
        // unfiltered rows.
        input.text = "";
        if (visible) Hyprland.dispatch('hl.dsp.focus({ window = [[class:^(org\\.quickshell)$]] })');
        visible = true;
        input.forceActiveFocus();
    }
    function close() { visible = false; }
    function toggle() { if (visible) close(); else open(); }

    // Super+Q closes the toplevel behind Quickshell's back and leaves
    // visible stuck at true, so open() would never remap it again.
    onClosed: visible = false
    onVisibleChanged: if (visible) input.forceActiveFocus()

    IpcHandler {
        target: "settings"
        function toggle(): void { root.toggle(); }
        function open(): void { root.open(); }
        function close(): void { root.close(); }
        // Straight to one section: general, pill, status, card, cc, behavior.
        function section(name: string): void {
            root.open();
            let known = false;
            for (let i = 0; i < root.shownSections.length; i++)
                if (root.shownSections[i].id === name) known = true;
            root.section = known ? name : "general";
        }
    }

    Connections {
        target: IslandState
        function onSettingsRequested() { root.open(); }
    }

    Item {
        anchors.fill: parent

        Rectangle {
            id: panel
            anchors.fill: parent
            // Hyprland rounds and shadows the window itself.
            radius: 0

            readonly property color glassTop:
                root.theme.mix(root.theme.on_surface, root.theme.surface_container, 0.05)
            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: Qt.rgba(panel.glassTop.r, panel.glassTop.g, panel.glassTop.b, root.theme.contentOpacity)
                }
                GradientStop {
                    position: 1.0
                    color: Qt.rgba(root.theme.surface_container.r, root.theme.surface_container.g,
                                   root.theme.surface_container.b, root.theme.contentOpacity)
                }
            }
            border.width: 1
            border.color: Qt.alpha(root.theme.outline, 0.30)

            MouseArea { anchors.fill: parent }   // swallow clicks so the scrim doesn't close it

            Row {
                anchors.fill: parent
                spacing: 0

                // ── sidebar ───────────────────────────────────────
                Item {
                    id: sidebar
                    width: 208
                    height: parent.height

                    Rectangle {
                        anchors.fill: parent
                        topLeftRadius: panel.radius
                        bottomLeftRadius: panel.radius
                        color: Qt.alpha(root.theme.surface_container_lowest, 0.45)
                    }

                    Column {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 12

                        // search — same filled field the launcher leads with
                        Rectangle {
                            width: parent.width
                            height: 36
                            radius: 18
                            color: Qt.rgba(root.theme.surface_container_high.r, root.theme.surface_container_high.g,
                                           root.theme.surface_container_high.b, 0.85)
                            border.width: input.activeFocus ? 2 : 1
                            border.color: input.activeFocus ? Qt.alpha(root.theme.primary, 0.45)
                                                            : Qt.alpha(root.theme.outline, 0.25)

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                spacing: 8

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "\u{f0349}"
                                    font.family: root.theme.fontMono
                                    font.pixelSize: 13
                                    color: root.theme.primary
                                }
                                TextInput {
                                    id: input
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 44
                                    text: root.query
                                    onTextChanged: root.query = text
                                    color: root.theme.on_surface
                                    font.family: root.theme.fontSans
                                    font.pixelSize: IslandState.ts(12)
                                    selectionColor: Qt.alpha(root.theme.primary, 0.35)
                                    clip: true
                                    Keys.onEscapePressed: {
                                        if (text !== "") text = "";
                                        else root.close();
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: input.text === ""
                                        text: "Search settings…"
                                        color: Qt.alpha(root.theme.on_surface_variant, 0.70)
                                        font.family: root.theme.fontSans
                                        font.pixelSize: IslandState.ts(12)
                                    }
                                }
                            }
                        }

                        // The section list stops above the footer and scrolls
                        // past it: with Menu bar, Corners and Gaps added, the
                        // list outgrew the window and ran over the file name.
                        Flickable {
                            id: secFlick
                            width: parent.width
                            height: parent.height - 36 - parent.spacing - 26
                            contentHeight: secCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            interactive: contentHeight > height

                        Column {
                            id: secCol
                            width: parent.width
                            spacing: 3

                            Repeater {
                                model: root.sidebarItems

                              Item {
                                required property var modelData
                                width: parent.width
                                height: modelData.header ? 26 : 34

                                Text {
                                    visible: !!parent.modelData.header
                                    anchors.left: parent.left
                                    anchors.leftMargin: 12
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 4
                                    text: parent.modelData.header || ""
                                    color: Qt.alpha(root.theme.on_surface_variant, 0.6)
                                    font.family: root.theme.fontSans
                                    font.pixelSize: IslandState.ts(9)
                                    font.weight: Font.DemiBold
                                    font.capitalization: Font.AllUppercase
                                    font.letterSpacing: 0.8
                                }

                                Rectangle {
                                    id: secRow
                                    visible: !parent.modelData.header
                                    readonly property var modelData: parent.modelData
                                    readonly property bool active: !root.searching && root.section === modelData.id

                                    width: parent.width
                                    height: 34
                                    radius: 12
                                    color: active ? root.theme.secondary_container
                                         : (secHover.hovered ? Qt.alpha(root.theme.on_surface, 0.08) : "transparent")
                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    Row {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 10

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: secRow.modelData.glyph || ""
                                            color: secRow.active ? root.theme.on_secondary_container
                                                                 : Qt.alpha(root.theme.on_surface_variant, 0.85)
                                            font.family: root.theme.fontMono
                                            font.pixelSize: 15
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: secRow.modelData.name || ""
                                            color: secRow.active ? root.theme.on_secondary_container : root.theme.on_surface
                                            font.family: root.theme.fontSans
                                            font.pixelSize: IslandState.ts(12)
                                            font.weight: secRow.active ? Font.DemiBold : Font.Normal
                                        }
                                    }

                                    HoverHandler { id: secHover; cursorShape: Qt.PointingHandCursor }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: { root.query = ""; input.text = ""; root.section = secRow.modelData.id; }
                                    }
                                }
                              }
                            }
                        }
                        }
                    }

                    // footer: where this lands on disk, because a settings
                    // window that hides its file is a settings window you
                    // cannot back up.
                    Text {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 14
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: IslandState.notch ? "notch profile · notch-prefs.json" : "island profile · island-prefs.json"
                        color: Qt.alpha(root.theme.on_surface_variant, 0.45)
                        font.family: root.theme.fontMono
                        font.pixelSize: 9
                    }
                }

                Rectangle {
                    width: 1
                    height: parent.height
                    gradient: Gradient {
                        GradientStop { position: 0.0;  color: "transparent" }
                        GradientStop { position: 0.12; color: Qt.alpha(root.theme.outline_variant, 0.9) }
                        GradientStop { position: 0.88; color: Qt.alpha(root.theme.outline_variant, 0.9) }
                        GradientStop { position: 1.0;  color: "transparent" }
                    }
                }

                // ── content ───────────────────────────────────────
                Item {
                    width: parent.width - sidebar.width - 1
                    height: parent.height

                    // registry-driven rows (all sections but the grid editor)
                    Flickable {
                        id: rowsFlick
                        anchors.fill: parent
                        anchors.margins: 18
                        visible: root.searching || (root.section !== "cc" && root.section !== "sound" && root.section !== "keys" && root.section !== "displays")
                        contentHeight: rowsCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        interactive: contentHeight > height

                        ScrollBar { id: rowsBar; flick: rowsFlick; theme: root.theme }

                        Column {
                            id: rowsCol
                            width: rowsFlick.width - (rowsBar.visible ? rowsBar.width + 2 : 0)
                            spacing: 8

                            Text {
                                visible: root.searching
                                text: root.results.length === 0 ? "Nothing matches" : root.results.length + " matching"
                                color: Qt.alpha(root.theme.on_surface_variant, 0.7)
                                font.family: root.theme.fontMono
                                font.pixelSize: 10
                            }

                            // Monitoring and Tray: the island's panels, so CPU/RAM/
                            // GPU and the tray menus stay reachable whatever the
                            // menu bar or the Control Center hold.
                            MonitorTool {
                                visible: !root.searching && root.section === "monitor"
                                live: visible && root.visible
                                x: -18
                                width: rowsCol.width + 36
                                height: visible ? preferredHeight : 0
                                theme: root.theme
                            }
                            TrayTool {
                                visible: !root.searching && root.section === "tray"
                                x: -18
                                width: rowsCol.width + 36
                                height: visible ? preferredHeight : 0
                                theme: root.theme
                            }

                            // Power station: the island's panel itself heads
                            // the section, above its preference rows.
                            StationTool {
                                visible: !root.searching && root.section === "station"
                                x: -18
                                width: rowsCol.width + 36
                                height: visible ? preferredHeight - 18 : 0
                                theme: root.theme
                            }

                            Repeater {
                                model: root.results

                                Rectangle {
                                    id: row
                                    required property var modelData
                                    readonly property var cfg: IslandState.cfg
                                    readonly property var value: cfg[modelData.key]
                                    // A toggle that only shapes the island means
                                    // nothing while the menu bar is up: it stays
                                    // in place, greyed, saying where its job went.
                                    readonly property bool idle: !!modelData.barIdle && IslandState.cfg.menuBar

                                    width: rowsCol.width
                                    height: modelData.type === "order" ? pillBuilder.implicitHeight + 28
                                          : modelData.type === "barorder" ? barBuilder.implicitHeight + 28
                                          : modelData.type === "choice" && (modelData.desc !== "" || idle) ? 66
                                          : modelData.type === "choice" ? 56
                                          : modelData.desc !== "" ? 58 : 48
                                    radius: 14
                                    color: Qt.alpha(root.theme.fg, 0.05)

                                    Column {
                                        visible: row.modelData.type !== "order" && row.modelData.type !== "barorder"
                                        anchors.left: parent.left
                                        anchors.leftMargin: 14
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 2
                                        width: parent.width - 260

                                        Text {
                                            width: parent.width
                                            elide: Text.ElideRight
                                            text: row.modelData.label
                                            color: root.theme.fg
                                            opacity: row.idle ? 0.45 : 1
                                            font.family: root.theme.fontSans
                                            font.pixelSize: IslandState.ts(12)
                                            font.weight: Font.DemiBold
                                        }
                                        Text {
                                            visible: text !== ""
                                            width: parent.width
                                            elide: Text.ElideRight
                                            text: row.idle ? row.modelData.barIdle
                                                  : root.searching
                                                  ? (row.modelData.desc !== "" ? row.modelData.desc : "")
                                                  : (row.modelData.desc || "")
                                            color: Qt.alpha(root.theme.on_surface_variant, 0.85)
                                            font.family: root.theme.fontSans
                                            font.pixelSize: IslandState.ts(10)
                                        }
                                    }

                                    // order: the visual pill editor.
                                    PillBuilder {
                                        id: pillBuilder
                                        visible: row.modelData.type === "order"
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: 14
                                        theme: root.theme
                                    }

                                    // barorder: the menu bar's editor.
                                    BarBuilder {
                                        id: barBuilder
                                        visible: row.modelData.type === "barorder"
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: 14
                                        theme: root.theme
                                    }

                                    // toggle
                                    ToggleSwitch {
                                        visible: row.modelData.type === "toggle"
                                        anchors.right: parent.right
                                        anchors.rightMargin: 14
                                        anchors.verticalCenter: parent.verticalCenter
                                        theme: root.theme
                                        enabled: !row.idle
                                        opacity: row.idle ? 0.35 : 1
                                        checked: row.modelData.key === "desktopUpdates" ? IslandState.syncEnabled : row.value === true
                                        onToggled: {
                                            if (row.modelData.key === "desktopUpdates") IslandState.setDesktopUpdates(!IslandState.syncEnabled);
                                            else IslandState.setPref(row.modelData.key, !(row.value === true));
                                        }
                                    }

                                    // slider — label left, track right, live
                                    // value in the corner, the way the video
                                    // annotates its rows ("31 px").
                                    Row {
                                        visible: row.modelData.type === "slider"
                                        anchors.right: parent.right
                                        anchors.rightMargin: 14
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 12

                                        Item {
                                            id: track
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 170; height: 22
                                            readonly property real frac:
                                                row.modelData ? Math.max(0, Math.min(1,
                                                    (row.value - row.modelData.min) / (row.modelData.max - row.modelData.min))) : 0

                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width; height: 4; radius: 2
                                                color: Qt.alpha(root.theme.on_surface, 0.15)
                                            }
                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width * track.frac; height: 4; radius: 2
                                                color: root.theme.primary
                                            }
                                            // a stepped slider marks every
                                            // stop it can land on
                                            Repeater {
                                                model: row.modelData.ticks
                                                       ? Math.round((row.modelData.max - row.modelData.min) / row.modelData.step) + 1 : 0
                                                Rectangle {
                                                    required property int index
                                                    readonly property real at: index / Math.max(1, Math.round((row.modelData.max - row.modelData.min) / row.modelData.step))
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    x: track.width * at - width / 2
                                                    width: 4; height: 4; radius: 2
                                                    color: at <= track.frac ? Qt.darker(root.theme.primary, 2.6)
                                                                            : Qt.alpha(root.theme.on_surface, 0.4)
                                                }
                                            }
                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                x: parent.width * track.frac - width / 2
                                                width: 14; height: 14; radius: 7
                                                color: root.theme.primary
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                preventStealing: true
                                                function apply(mx) {
                                                    const m = row.modelData;
                                                    const f = Math.max(0, Math.min(1, mx / track.width));
                                                    let v = m.min + f * (m.max - m.min);
                                                    v = Math.round(v / m.step) * m.step;
                                                    // float steps accumulate 1e-17 dust; two decimals is
                                                    // plenty for an opacity and exact for the px sliders
                                                    v = Math.round(v * 100) / 100;
                                                    IslandState.setPref(m.key, v);
                                                }
                                                onPressed: (m) => apply(m.x)
                                                onPositionChanged: (m) => { if (pressed) apply(m.x); }
                                            }
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 44
                                            horizontalAlignment: Text.AlignRight
                                            text: root.fmtValue(row.modelData, row.value)
                                            color: Qt.alpha(root.theme.on_surface_variant, 0.95)
                                            font.family: root.theme.fontMono
                                            font.pixelSize: 11
                                        }
                                    }

                                    // font — a field that wears the face it
                                    // names; clicking it opens the picker.
                                    Rectangle {
                                        id: fontField
                                        visible: row.modelData.type === "font"
                                        anchors.right: parent.right
                                        anchors.rightMargin: 14
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 220; height: 30; radius: 10
                                        color: fontHov.hovered || (fontPicker.key === row.modelData.key)
                                               ? Qt.alpha(root.theme.on_surface, 0.12) : Qt.alpha(root.theme.on_surface, 0.07)
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        Text {
                                            anchors.left: parent.left
                                            anchors.leftMargin: 10
                                            anchors.right: fontChev.left
                                            anchors.rightMargin: 6
                                            anchors.verticalCenter: parent.verticalCenter
                                            elide: Text.ElideRight
                                            text: row.modelData.type === "font" ? String(row.value || "") : ""
                                            color: root.theme.fg
                                            font.family: text
                                            font.pixelSize: 12
                                        }
                                        Text {
                                            id: fontChev
                                            anchors.right: parent.right
                                            anchors.rightMargin: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "\u{f0140}"
                                            color: Qt.alpha(root.theme.on_surface_variant, 0.85)
                                            font.family: root.theme.fontMono
                                            font.pixelSize: 13
                                        }
                                        HoverHandler { id: fontHov; cursorShape: Qt.PointingHandCursor }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: fontPicker.openFor(row.modelData.key, fontField)
                                        }
                                    }

                                    // choice — segmented pills, selection in
                                    // secondary_container like every "you are
                                    // here" in this shell.
                                    Row {
                                        visible: row.modelData.type === "choice"
                                        anchors.right: parent.right
                                        anchors.rightMargin: 14
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 4
                                        enabled: !row.idle
                                        opacity: row.idle ? 0.35 : 1

                                        Repeater {
                                            model: row.modelData.type === "choice" ? row.modelData.choices : []

                                            Rectangle {
                                                id: chip
                                                required property var modelData
                                                readonly property bool on: row.value === modelData.id
                                                width: chipText.implicitWidth + 20
                                                height: 28; radius: 10
                                                color: on ? root.theme.secondary_container
                                                     : (chipHover.hovered ? Qt.alpha(root.theme.on_surface, 0.10)
                                                                          : Qt.alpha(root.theme.on_surface, 0.05))
                                                Behavior on color { ColorAnimation { duration: 120 } }

                                                Text {
                                                    id: chipText
                                                    anchors.centerIn: parent
                                                    text: chip.modelData.label
                                                    color: chip.on ? root.theme.on_secondary_container : root.theme.on_surface
                                                    font.family: chip.modelData.font || root.theme.fontSans
                                                    font.pixelSize: IslandState.ts(11)
                                                    font.weight: chip.on ? Font.DemiBold : Font.Normal
                                                }

                                                HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    onClicked: {
                                                        if (row.modelData.key === "gameMode")
                                                            IslandState.setGameMode(chip.modelData.id);
                                                        else
                                                            IslandState.setPref(row.modelData.key, chip.modelData.id);
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── control center editor ─────────────────
                    // The genuine article with edit: true — same layout
                    // engine, same widgets, so what is arranged here is
                    // exactly what the island opens. The chrome around it
                    // (columns, sizes, add-chips) lives here because it is
                    // settings furniture, not part of the grid.
                    Item {
                        anchors.fill: parent
                        anchors.margins: 18
                        visible: !root.searching && root.section === "cc"

                        Item {
                            id: ccHeader
                            width: parent.width
                            // Grows with the title block, which wraps beside the buttons
                            // instead of running under them.
                            height: Math.max(34, ccTitle.implicitHeight)

                            Column {
                                id: ccTitle
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(0, parent.width - ccActs.width - 12)
                                spacing: 2
                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: "Control Center"
                                    color: root.theme.fg
                                    font.family: root.theme.fontSans
                                    font.pixelSize: IslandState.ts(13)
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    width: parent.width
                                    wrapMode: Text.WordWrap
                                    text: "The hub the island opens — one layout for island, notch and menu bar"
                                    color: Qt.alpha(root.theme.on_surface_variant, 0.8)
                                    font.family: root.theme.fontSans
                                    font.pixelSize: IslandState.ts(10)
                                }
                            }

                            Row {
                                id: ccActs
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6

                                Repeater {
                                    model: [
                                        { key: "tidy",  glyph: "\u{f0570}", label: "Tidy" },
                                        { key: "reset", glyph: "\u{f054c}", label: "Default layout" }
                                    ]
                                    Rectangle {
                                        id: ccActBtn
                                        required property var modelData
                                        width: ccActRow.implicitWidth + 20
                                        height: 28; radius: 10
                                        color: ccActHov.hovered ? Qt.alpha(root.theme.on_surface, 0.10)
                                                                : Qt.alpha(root.theme.on_surface, 0.05)
                                        Behavior on color { ColorAnimation { duration: 120 } }

                                        Row {
                                            id: ccActRow
                                            anchors.centerIn: parent
                                            spacing: 6
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: ccActBtn.modelData.glyph
                                                color: root.theme.on_surface
                                                font.family: root.theme.fontMono
                                                font.pixelSize: 12
                                            }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: ccActBtn.modelData.label
                                                color: root.theme.on_surface
                                                font.family: root.theme.fontSans
                                                font.pixelSize: IslandState.ts(11)
                                            }
                                        }

                                        HoverHandler { id: ccActHov; cursorShape: Qt.PointingHandCursor }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                if (ccActBtn.modelData.key === "tidy") ccEdit.tidy();
                                                else ccEdit.resetLayout();
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // columns — the 5..9 selector from the reference
                        Row {
                            id: ccMeta
                            anchors.top: ccHeader.bottom
                            anchors.topMargin: 10
                            spacing: 5

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                rightPadding: 6
                                text: "Columns"
                                color: Qt.alpha(root.theme.on_surface_variant, 0.9)
                                font.family: root.theme.fontSans
                                font.pixelSize: IslandState.ts(11)
                            }
                            Repeater {
                                model: [5, 6, 7, 8, 9]
                                Rectangle {
                                    id: colChip
                                    required property int modelData
                                    readonly property bool on: IslandState.cfg.ccColumns === modelData
                                    width: 30; height: 26; radius: 9
                                    color: on ? root.theme.secondary_container
                                         : (colHov.hovered ? Qt.alpha(root.theme.on_surface, 0.10)
                                                           : Qt.alpha(root.theme.on_surface, 0.05))
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    Text {
                                        anchors.centerIn: parent
                                        text: colChip.modelData
                                        color: colChip.on ? root.theme.on_secondary_container : root.theme.on_surface
                                        font.family: root.theme.fontMono
                                        font.pixelSize: 11
                                        font.weight: colChip.on ? Font.DemiBold : Font.Normal
                                    }
                                    HoverHandler { id: colHov; cursorShape: Qt.PointingHandCursor }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: IslandState.setCcColumns(colChip.modelData)
                                    }
                                }
                            }
                        }

                        // ── saved layouts ─────────────────────────
                        // Named snapshots of the grid: a chip applies one,
                        // its × forgets it, and "Save as" snapshots what the
                        // editor shows right now under a typed name.
                        Flow {
                            id: ccPresets
                            anchors.top: ccMeta.bottom
                            anchors.topMargin: 8
                            width: parent.width
                            spacing: 5
                            property bool naming: false

                            Text {
                                height: 26
                                verticalAlignment: Text.AlignVCenter
                                rightPadding: 6
                                text: "Layouts"
                                color: Qt.alpha(root.theme.on_surface_variant, 0.9)
                                font.family: root.theme.fontSans
                                font.pixelSize: IslandState.ts(11)
                            }

                            Repeater {
                                model: IslandState.cfg.ccPresets || []
                                Rectangle {
                                    id: presetChip
                                    required property var modelData
                                    width: presetName.implicitWidth + 16 + (presetDel.visible ? 16 : 0)
                                    height: 26; radius: 9
                                    color: presetHov.hovered ? Qt.alpha(root.theme.on_surface, 0.10)
                                                             : Qt.alpha(root.theme.on_surface, 0.05)
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    Behavior on width { NumberAnimation { duration: 120 } }

                                    Text {
                                        id: presetName
                                        anchors.left: parent.left
                                        anchors.leftMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: presetChip.modelData.name
                                        color: root.theme.on_surface
                                        font.family: root.theme.fontSans
                                        font.pixelSize: IslandState.ts(11)
                                    }
                                    HoverHandler { id: presetHov; cursorShape: Qt.PointingHandCursor }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: IslandState.applyCcPreset(presetChip.modelData.name)
                                    }

                                    // the × only shows on hover, so the
                                    // chip reads as a name until you reach
                                    // for it
                                    Text {
                                        id: presetDel
                                        visible: presetHov.hovered || delHov.hovered
                                        anchors.right: parent.right
                                        anchors.rightMargin: 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "\u{f0156}"
                                        color: delHov.hovered ? root.theme.error : Qt.alpha(root.theme.on_surface, 0.6)
                                        font.family: root.theme.fontMono
                                        font.pixelSize: 11
                                        HoverHandler { id: delHov; cursorShape: Qt.PointingHandCursor }
                                        MouseArea {
                                            anchors.fill: parent
                                            anchors.margins: -4
                                            onClicked: IslandState.deleteCcPreset(presetChip.modelData.name)
                                        }
                                    }
                                }
                            }

                            Text {
                                visible: (IslandState.cfg.ccPresets || []).length === 0 && !ccPresets.naming
                                height: 26
                                verticalAlignment: Text.AlignVCenter
                                text: "none saved"
                                color: Qt.alpha(root.theme.on_surface_variant, 0.55)
                                font.family: root.theme.fontSans
                                font.pixelSize: IslandState.ts(10)
                            }

                            Rectangle {
                                visible: !ccPresets.naming
                                width: saveRow.implicitWidth + 18
                                height: 26; radius: 9
                                color: saveHov.hovered ? Qt.alpha(root.theme.primary, 0.22)
                                                       : Qt.alpha(root.theme.primary, 0.12)
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Row {
                                    id: saveRow
                                    anchors.centerIn: parent
                                    spacing: 5
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "\u{f0193}"
                                        color: root.theme.primary
                                        font.family: root.theme.fontMono
                                        font.pixelSize: 11
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Save as\u{2026}"
                                        color: root.theme.primary
                                        font.family: root.theme.fontSans
                                        font.pixelSize: IslandState.ts(11)
                                    }
                                }
                                HoverHandler { id: saveHov; cursorShape: Qt.PointingHandCursor }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        presetField.text = "";
                                        ccPresets.naming = true;
                                        presetField.focusField();
                                    }
                                }
                            }

                            ComposerField {
                                id: presetField
                                visible: ccPresets.naming
                                theme: root.theme
                                width: 180
                                height: 26
                                radius: 9
                                placeholder: "Layout name, Enter to save"
                                onSubmitted: {
                                    IslandState.saveCcPreset(presetField.text, IslandState.cfg.ccColumns,
                                        ccEdit.placed.map(i => ({ id: i.id, x: i.x, y: i.y, w: i.w, h: i.h })));
                                    ccPresets.naming = false;
                                }
                                onCancelled: ccPresets.naming = false
                            }
                        }

                        Flickable {
                            id: ccFlick
                            anchors.top: ccPresets.bottom
                            anchors.topMargin: 12
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: ccHint.top
                            anchors.bottomMargin: 8
                            contentHeight: ccCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            interactive: contentHeight > height

                            ScrollBar { flick: ccFlick; theme: root.theme }

                            Column {
                                id: ccCol
                                width: ccFlick.width - 10
                                spacing: 12
                                // room for the corner ✕ on a top-row control
                                topPadding: 8

                                ControlCenter {
                                    id: ccEdit
                                    edit: true
                                    theme: root.theme
                                    width: parent.width
                                    height: implicitHeight
                                }

                                // the selected control's sizes, the reference's
                                // "Sound · 7×1" picker row
                                Flow {
                                    width: parent.width
                                    spacing: 5
                                    visible: ccEdit.selItem !== null

                                    Text {
                                        height: 26
                                        verticalAlignment: Text.AlignVCenter
                                        rightPadding: 8
                                        text: ccEdit.selItem
                                              ? ccEdit.selItem.def.name + " · " + ccEdit.selItem.w + "\u{00d7}" + ccEdit.selItem.h
                                              : ""
                                        color: root.theme.fg
                                        font.family: root.theme.fontSans
                                        font.pixelSize: IslandState.ts(11)
                                        font.weight: Font.DemiBold
                                    }

                                    Repeater {
                                        model: ccEdit.selItem ? ccEdit.selItem.def.sizes : []
                                        Rectangle {
                                            id: sizeChip
                                            required property var modelData
                                            readonly property bool on:
                                                ccEdit.selItem !== null
                                                && ccEdit.selItem.w === modelData[0]
                                                && ccEdit.selItem.h === modelData[1]
                                            readonly property bool fitsCols: modelData[0] <= IslandState.cfg.ccColumns
                                            width: szText.implicitWidth + 18
                                            height: 26; radius: 9
                                            opacity: fitsCols ? 1 : 0.35
                                            color: on ? root.theme.secondary_container
                                                 : (szHov.hovered && fitsCols ? Qt.alpha(root.theme.on_surface, 0.10)
                                                                              : Qt.alpha(root.theme.on_surface, 0.05))
                                            Behavior on color { ColorAnimation { duration: 120 } }
                                            Text {
                                                id: szText
                                                anchors.centerIn: parent
                                                text: sizeChip.modelData[0] + "\u{00d7}" + sizeChip.modelData[1]
                                                color: sizeChip.on ? root.theme.on_secondary_container : root.theme.on_surface
                                                font.family: root.theme.fontMono
                                                font.pixelSize: 10
                                            }
                                            HoverHandler { id: szHov; enabled: sizeChip.fitsCols; cursorShape: Qt.PointingHandCursor }
                                            MouseArea {
                                                anchors.fill: parent
                                                enabled: sizeChip.fitsCols
                                                onClicked: ccEdit.setSelSize(sizeChip.modelData[0], sizeChip.modelData[1])
                                            }
                                        }
                                    }

                                }

                                // whatever is not placed — the reference's
                                // "Add a control" chips
                                Column {
                                    width: parent.width
                                    spacing: 6
                                    visible: ccEdit.unplaced.length > 0

                                    Text {
                                        text: "Add a control"
                                        color: Qt.alpha(root.theme.on_surface_variant, 0.9)
                                        font.family: root.theme.fontSans
                                        font.pixelSize: IslandState.ts(11)
                                        font.weight: Font.DemiBold
                                    }
                                    Flow {
                                        width: parent.width
                                        spacing: 5
                                        Repeater {
                                            model: ccEdit.unplaced
                                            Rectangle {
                                                id: addChip
                                                required property var modelData
                                                width: addRow.implicitWidth + 18
                                                height: 26; radius: 9
                                                color: addHov.hovered ? Qt.alpha(root.theme.on_surface, 0.10)
                                                                      : Qt.alpha(root.theme.on_surface, 0.05)
                                                Behavior on color { ColorAnimation { duration: 120 } }
                                                Row {
                                                    id: addRow
                                                    anchors.centerIn: parent
                                                    spacing: 5
                                                    Text {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: addChip.modelData.glyph
                                                        color: Qt.alpha(root.theme.on_surface, 0.9)
                                                        font.family: root.theme.fontMono
                                                        font.pixelSize: 11
                                                    }
                                                    Text {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: addChip.modelData.name
                                                        color: root.theme.on_surface
                                                        font.family: root.theme.fontSans
                                                        font.pixelSize: IslandState.ts(10)
                                                    }
                                                    Text {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: "\u{f0415}"
                                                        color: Qt.alpha(root.theme.on_surface_variant, 0.7)
                                                        font.family: root.theme.fontMono
                                                        font.pixelSize: 10
                                                    }
                                                }
                                                HoverHandler { id: addHov; cursorShape: Qt.PointingHandCursor }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    onClicked: ccEdit.addWidget(addChip.modelData.id)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            id: ccHint
                            anchors.bottom: parent.bottom
                            width: parent.width
                            text: "Drag to move — drop on another control to swap places · pull the corner grip to resize freely, chips are the suggested sizes · changes persist as you make them"
                            color: Qt.alpha(root.theme.on_surface_variant, 0.55)
                            font.family: root.theme.fontMono
                            font.pixelSize: 9
                        }
                    }

                    // ── displays ──────────────────────────────
                    // Resolution, refresh, scale, rotation and order of every
                    // monitor, saved to hypr/displays.lua (see DisplaysPane).
                    DisplaysPane {
                        anchors.fill: parent
                        anchors.margins: 18
                        visible: !root.searching && root.section === "displays"
                        active: root.visible && visible
                        theme: root.theme
                    }

                    // ── keybinds ──────────────────────────────
                    // Every Hyprland shortcut, re-bindable; the list itself
                    // comes from hypr/binds.lua (see KeybindsPane).
                    KeybindsPane {
                        anchors.fill: parent
                        anchors.margins: 18
                        visible: !root.searching && root.section === "keys"
                        active: root.visible && visible
                        theme: root.theme
                    }

                    // ── sound ─────────────────────────────────
                    // The island's audio panel itself, so volume, mic and
                    // device picking behave identically in both places.
                    Item {
                        anchors.fill: parent
                        anchors.margins: 18
                        visible: !root.searching && root.section === "sound"

                        Column {
                            id: soundHeader
                            width: parent.width
                            spacing: 2
                            Text {
                                text: "Sound"
                                color: root.theme.fg
                                font.family: root.theme.fontSans
                                font.pixelSize: IslandState.ts(13)
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: "Volume, output and input devices"
                                color: Qt.alpha(root.theme.on_surface_variant, 0.8)
                                font.family: root.theme.fontSans
                                font.pixelSize: IslandState.ts(10)
                            }
                        }

                        Flickable {
                            id: soundFlick
                            anchors.top: soundHeader.bottom
                            anchors.topMargin: 4
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            contentHeight: soundPanel.preferredHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            interactive: contentHeight > height

                            ScrollBar { flick: soundFlick; theme: root.theme }

                            AudioTool {
                                id: soundPanel
                                x: -18
                                width: soundFlick.width + 36
                                height: preferredHeight
                                theme: root.theme
                            }
                        }
                    }
                }
            }

            // the same hair of caught light the card wears
            Rectangle {
                x: panel.radius
                y: 1
                width: panel.width - panel.radius * 2
                height: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: Qt.alpha(root.theme.on_surface, 0.16) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
        }

        // ── font picker ───────────────────────────────────────────
        // Every installed family, each drawn in its own face, under the
        // field that opened it. A scrim over the window closes it.
        Item {
            id: fontPicker
            anchors.fill: parent
            visible: key !== ""
            z: 50

            property string key: ""
            property string filter: ""
            readonly property var families: {
                const seen = {};
                const out = [];
                const all = root.installedFonts;
                for (let i = 0; i < all.length; i++) {
                    const f = all[i];
                    if (f.startsWith(".") || seen[f]) continue;
                    seen[f] = true;
                    out.push(f);
                }
                out.sort((a, b) => a.localeCompare(b));
                return out;
            }
            readonly property var shown: {
                const q = fontPicker.filter.trim().toLowerCase();
                if (q === "") return fontPicker.families;
                const qv = IslandState.searchVariants(q);
                return fontPicker.families.filter(f => IslandState.searchHit(f, qv));
            }

            function openFor(k, field) {
                const p = field.mapToItem(fontPicker, 0, field.height + 6);
                const h = 320;
                sheet.x = Math.min(p.x + field.width - sheet.width, fontPicker.width - sheet.width - 12);
                sheet.y = p.y + h > fontPicker.height - 12 ? Math.max(12, p.y - field.height - 12 - h) : p.y;
                fontPicker.filter = "";
                filterInput.text = "";
                fontPicker.key = k;
                filterInput.forceActiveFocus();
                Qt.callLater(() => {
                    const i = fontPicker.shown.indexOf(IslandState.cfg[k]);
                    if (i >= 0) fontList.positionViewAtIndex(i, ListView.Center);
                });
            }
            function close() { fontPicker.key = ""; }
            function pick(f) {
                IslandState.setPref(fontPicker.key, f);
                fontPicker.close();
            }

            Connections {
                target: root
                function onSectionChanged() { fontPicker.close(); }
                function onVisibleChanged() { fontPicker.close(); }
            }

            MouseArea { anchors.fill: parent; onClicked: fontPicker.close() }

            Rectangle {
                id: sheet
                width: 300; height: 320
                radius: 14
                color: root.theme.surface_container_high
                border.width: 1
                border.color: Qt.alpha(root.theme.outline, 0.35)

                MouseArea { anchors.fill: parent }

                Rectangle {
                    id: filterBox
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 8
                    height: 30; radius: 9
                    color: Qt.alpha(root.theme.on_surface, 0.07)
                    Text {
                        id: filterGlyph
                        anchors.left: parent.left
                        anchors.leftMargin: 9
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u{f0349}"
                        color: Qt.alpha(root.theme.on_surface_variant, 0.8)
                        font.family: root.theme.fontMono
                        font.pixelSize: 13
                    }
                    TextInput {
                        id: filterInput
                        anchors.left: filterGlyph.right
                        anchors.leftMargin: 7
                        anchors.right: parent.right
                        anchors.rightMargin: 9
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.theme.fg
                        selectionColor: Qt.alpha(root.theme.primary, 0.4)
                        font.family: root.theme.fontSans
                        font.pixelSize: 12
                        clip: true
                        onTextChanged: fontPicker.filter = text
                        Keys.onEscapePressed: fontPicker.close()
                        Keys.onReturnPressed: if (fontPicker.shown.length > 0) fontPicker.pick(fontPicker.shown[0])
                        Text {
                            visible: filterInput.text === ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: fontPicker.families.length + " fonts"
                            color: Qt.alpha(root.theme.on_surface_variant, 0.6)
                            font.family: root.theme.fontSans
                            font.pixelSize: 12
                        }
                    }
                }

                ListView {
                    id: fontList
                    anchors.top: filterBox.bottom
                    anchors.topMargin: 6
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 6
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: fontPicker.shown
                    reuseItems: true

                    ScrollBar { flick: fontList; theme: root.theme }

                    delegate: Rectangle {
                        id: fItem
                        required property string modelData
                        readonly property bool current: fontPicker.key !== "" && IslandState.cfg[fontPicker.key] === modelData
                        width: fontList.width - 8
                        height: 32; radius: 8
                        color: current ? root.theme.secondary_container
                             : fHov.hovered ? Qt.alpha(root.theme.on_surface, 0.08) : "transparent"
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.right: fCheck.left
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: fItem.modelData
                            color: fItem.current ? root.theme.on_secondary_container : root.theme.fg
                            font.family: fItem.modelData
                            font.pixelSize: 14
                        }
                        Text {
                            id: fCheck
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            visible: fItem.current
                            text: "\u{f012c}"
                            color: root.theme.on_secondary_container
                            font.family: root.theme.fontMono
                            font.pixelSize: 13
                        }
                        HoverHandler { id: fHov; cursorShape: Qt.PointingHandCursor }
                        MouseArea { anchors.fill: parent; onClicked: fontPicker.pick(fItem.modelData) }
                    }
                }

                Text {
                    anchors.centerIn: fontList
                    visible: fontPicker.shown.length === 0
                    text: "No font matches"
                    color: Qt.alpha(root.theme.on_surface_variant, 0.7)
                    font.family: root.theme.fontSans
                    font.pixelSize: 12
                }
            }
        }
    }
}
