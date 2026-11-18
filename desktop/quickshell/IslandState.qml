pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Notifications
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import Quickshell.Bluetooth

// Everything the island knows that must exist once per machine rather than
// once per monitor.
//
// This is not a tidiness preference. DynamicIsland is instantiated inside
// Variants { model: Quickshell.screens }, so on this two-monitor setup there
// were two of everything: two calendar-agenda polls a minute, two notifiedUids
// maps, and therefore two notify-send calls for every upcoming meeting. A
// timer built the same way would have run twice and fired twice. State lives
// here; the islands are renderers.
Singleton {
    id: root

    SystemClock { id: clk; precision: SystemClock.Seconds }

    Process { id: notifier }
    Process { id: opener }
    function open(url) {
        if (!url) return;
        opener.command = ["setsid", "-f", "xdg-open", url];
        opener.running = true;
    }

    // ── the expanded surface ──────────────────────────────────────
    // Which tool the card is showing, and which monitor owns it. Both islands
    // read the same tool id, so the screen name is what stops the card opening
    // on both at once.
    property string tool: ""
    property string toolScreen: ""
    // Which tab the wireless sheet opens on, set by whoever opens it (the
    // menu bar's network icon asks for "net"); the sheet takes it and clears it.
    property string wirelessTab: ""
    readonly property bool cardOpen: tool !== ""

    // An empty screen resolves to the focused monitor rather than being taken
    // literally. Activity actions pass root.toolScreen, which is "" whenever
    // the card is closed — so clicking the timer capsule, or a meeting segment
    // with no join link, used to open the card on a monitor named "": nothing
    // rendered, and the island was left half-open so the next pill click
    // toggled it shut instead of showing it.
    // Desktop updates: machines installed from the public repo pull new
    // versions of this desktop hourly through desktop-sync.timer. Settings →
    // General shows a switch for it only where that timer exists.
    property bool syncInstalled: false
    property bool syncEnabled: false
    function setDesktopUpdates(on) {
        Quickshell.execDetached(["systemctl", "--user", on ? "enable" : "disable", "--now", "desktop-sync.timer"]);
        root.syncEnabled = on;
        syncCheckLater.restart();
    }
    Timer { id: syncCheckLater; interval: 1200; onTriggered: syncCheck.running = true }
    Process {
        id: syncCheck
        running: true
        command: ["bash", "-c", '[ -f "$HOME/.config/systemd/user/desktop-sync.timer" ] || { echo none; exit 0; }; systemctl --user is-enabled desktop-sync.timer 2>/dev/null || true']
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text.trim();
                root.syncInstalled = t !== "none";
                root.syncEnabled = t === "enabled";
            }
        }
    }

    // A monitor's place in the left-to-right (then top-to-bottom) order: 0
    // for the leftmost.
    // The lock screen puts its password field on rank 0, the workspace strip
    // and the SUPER+N keys (hypr/binds.lua) give rank 1 workspaces 11..20.
    // Ranking by position instead of by output name is what lets the same
    // config work on a machine whose monitors are called something else.
    function screenRank(name) {
        const ss = Quickshell.screens;
        let me = null;
        for (let i = 0; i < ss.length; i++)
            if (ss[i].name === name) me = ss[i];
        if (!me) return 0;
        let rank = 0;
        for (let i = 0; i < ss.length; i++)
            if (ss[i].x < me.x || (ss[i].x === me.x && ss[i].y < me.y)) rank++;
        return rank;
    }

    function resolveScreen(screen) {
        return screen ? screen : root.activeScreen();
    }
    function openTool(id, screen) {
        // The old control tool dissolved into the hub; keybinds, saved
        // statusClick values and muscle memory that still say "control" land
        // on the surface that replaced it.
        if (id === "control") id = "hub";
        root.direct = false;
        root.toolScreen = root.resolveScreen(screen);
        root.tool = id;
    }
    function closeCard() { root.tool = ""; root.toolScreen = ""; root.direct = false; }
    // A tool opened straight from the menu bar takes the whole card, the way
    // the launcher does, instead of stacking as a sheet over the hub: clicking
    // the Arch logo means "the power menu", not "the control centre, then
    // power". Set before the tool so the card never draws a frame of hub.
    property bool direct: false
    function openDirect(id, screen) {
        root.direct = true;
        root.toolScreen = root.resolveScreen(screen);
        root.tool = id;
    }
    function toggleDirect(id, screen) {
        if (root.direct && root.tool === id && root.toolScreen === root.resolveScreen(screen))
            root.closeCard();
        else root.openDirect(id, screen);
    }
    function toggleTool(id, screen) {
        if (id === "control") id = "hub";
        if (root.tool === id && root.toolScreen === root.resolveScreen(screen))
            root.closeCard();
        else root.openTool(id, screen);
    }
    // Every surface the card can show. The hub is the entry point — the pill
    // opens it, and everything else drills in from its grid — so there is no
    // order here any more, only identity: glyphs for tiles, names for the
    // card header. Availability is the tool's own business — see Platform.
    readonly property var tools: [
        { id: "hub",      glyph: "\u{f0555}", name: "Control Center" },
        { id: "audio",    glyph: "\u{f057e}", name: "Audio" },
        { id: "bluetooth", glyph: "\u{f00af}", name: "Wireless" },
        { id: "display",  glyph: "\u{f037a}", name: "Displays" },
        { id: "calendar", glyph: "\u{f00ed}", name: "Calendar" },
        { id: "media",    glyph: "\u{f075a}", name: "Media" },
        { id: "weather",  glyph: "\u{e30d}",  name: "Weather" },
        { id: "battery",  glyph: "\u{f0079}", name: "Batteries" },
        { id: "monitor",  glyph: "\u{f04c5}", name: "Monitoring" },
        { id: "tray",     glyph: "\u{f168e}", name: "Tray" },
        { id: "notifs",   glyph: "\u{f009a}", name: "Notifications" },
        { id: "notes",    glyph: "\u{f09a5}", name: "Notes" },
        { id: "clipboard", glyph: "\u{f0192}", name: "Clipboard" },
        { id: "keys",     glyph: "\u{f030c}", name: "Shortcuts" },
        // face: the tool takes the card itself instead of a sheet over the hub
        { id: "apps",     glyph: "\u{f003b}", name: "Apps", face: "AppsTool.qml" },
        { id: "themes",   glyph: "\u{f03d8}", name: "Themes", face: "ThemesTool.qml", height: 420 },
        { id: "capture",  glyph: "\u{f0d19}", name: "Capture" },
        { id: "timer",    glyph: "\u{f051b}", name: "Timer" },
        { id: "call",     glyph: "\u{f03f6}", name: "Call", needs: "call" },
        { id: "power",    glyph: "\u{f0425}", name: "Power" }
    ]
    function toolInfo(id) {
        for (let i = 0; i < root.tools.length; i++)
            if (root.tools[i].id === id) return root.tools[i];
        return null;
    }

    // ── preferences that outlive the process ──────────────────────
    // PersistentProperties (the call and timer anchors below) is in-process
    // state: it survives the shell's own hot-reload and nothing else. A
    // toggle the user set deliberately —
    // silent mode, a forced game mode — is a decision about the machine, not
    // about this run of the shell, so it has to come back after a reboot too.
    // That takes a file.
    //
    // FileView creates the parent directory on write, so nothing has to make
    // ~/.local/state/quickshell first; a freshly restored machine writes the
    // file on its first load failure and carries on from there.
    property bool prefsReady: false

    FileView {
        id: prefsFile
        path: "@HOME@/.local/state/quickshell/island-prefs.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        // adapterUpdated does not fire for the load itself, only for a real
        // change — but it would fire for one made in the few ms before the
        // load lands, and writing then would erase the saved file with the
        // compiled-in defaults. The gate costs nothing and removes the race.
        //
        // Debounced rather than written inline: the settings sliders update a
        // pref on every pointer move, and a write per move would grind the
        // disk and re-trigger this view's own change watcher each time.
        onAdapterUpdated: if (root.prefsReady) prefsWrite.restart()
        onLoaded: {
            root.prefsReady = true;
            root.seedNotch();
            // One-time migration: the pre-hub shell saved the status circle's
            // click target as "control". openTool aliases it anyway, but the
            // settings chips match by identity, so the stored value moves too.
            if (prefs.statusClick === "control") prefs.statusClick = "hub";
        }
        onLoadFailed: (error) => {
            root.prefsReady = true;
            if (error === FileViewError.FileNotFound) writeAdapter();
        }

        JsonAdapter {
            id: prefs
            property bool dnd: false
            // Game mode is tri-state and JSON has no comfortable null, so it
            // is stored under the names gameModeName already reports.
            property string gameMode: "auto"
            // Typography: a text cut for UI copy and a display cut for
            // anything large — the clock, headings, a calculator result.
            // Display cuts are drawn tighter for big sizes; the text cut
            // stays open and legible at 10–13 px. clockFont picks whether
            // the clocks (pill, lock screen) use the display cut or the mono.
            property string fontBody: "Inter"
            property string fontDisplay: "Inter Display"
            property string clockFont: "display"
            // Text size: the shell's body size in px. 13 is the size every
            // label was drawn for; the rest scale from it (ts()).
            property int textSize: 13

            // ── island layout & looks, edited live by IslandSettings ──
            // One-way door: writeAdapter serializes only DECLARED properties,
            // so a shell downgraded past this block drops every key below on
            // its first write. Reverting the QML means the prefs file loses
            // the layout with it — restore both from the same backup.
            // The hub's grid: how many columns, and where each control sits
            // as {id, x, y, w, h} in cell units. Empty means the compiled-in
            // default layout in ControlCenter.qml, so a new widget added in
            // code still lands somewhere without the saved file knowing it.
            property int ccColumns: 8
            property var ccLayout: []
            // Named snapshots of the grid, {name, columns, layout}, saved
            // and applied from the settings' Control Center section.
            property var ccPresets: []
            property bool statusCircle: true
            // The AirPods circle left of the island; it shows only while
            // they are connected, and this keeps it away even then.
            property bool airpodsCircle: true
            // The phone circle beside it, shown while the phone's battery is
            // reachable over Bluetooth; in the menu bar both are items.
            property bool phoneCircle: true
            // A circle per connected controller, in its own colour.
            property bool controllerCircle: true
            // The tray strip at the right end of the top bar. The island's
            // tray tool stays either way; this only adds the always-visible row.
            property bool topTray: true
            // The full-width menu bar across the top: distro menu and the
            // focused app on the left, tray, status icons and the date on the
            // right, with the island or notch sitting in its middle.
            property bool menuBar: true
            // The menu bar's items, left to right, "notch" marking where the
            // island sits: what comes before it is the left side, what comes
            // after it the right. Shared by both modes. Empty means barDefault.
            property var barLayout: []
            property var barHidden: []
            // Its look, Settings → Menu bar: padding inside each item, space
            // between items, room at the screen edges, icon and text size,
            // the band's opacity and its bottom hairline.
            property int barPad: 8
            property int barSpacing: 2
            property int barMargin: 6
            property int barIconSize: 15
            property int barFontSize: 13
            property real barOpacity: 0.55
            property bool barDivider: true
            // Rounded screen corners: radius (0 = square), the bar-coloured
            // fillets under its ends, the black ones at the bottom, and the
            // corner privacy dots shown while the bar is covered or off.
            property int cornerRadius: 24
            property bool cornersTop: true
            property bool cornersBottom: true
            property bool cornerDots: true
            // Bar-coloured fillets under the bar's ends, sized to the windows'
            // corner rounding so the bar flows into a window with no gap.
            property bool barFillets: true
            // The bar's height; 0 follows the notch (its resting height) or
            // the island (edge gap + expanded pill).
            property int barHeight: 0
            // On a monitor whose workspace holds no windows the band goes fully
            // clear, so the wallpaper shows edge to edge.
            property bool barClearWhenEmpty: true
            // Hyprland's window gaps, corner rounding and frame, owned here
            // so Settings → Gaps can change them live. Applied over whatever
            // hyprland.lua says each time the shell starts or a value moves.
            // Two sets: win* while the menu bar is on (flush, frameless),
            // barOff* while it is off — the look from before the menu bar.
            // Settings → Gaps edits whichever set is in use right now.
            property int winGapsIn: 0
            property int winGapsOut: 0
            property int winRounding: 10
            property int winBorder: 0
            property int barOffGapsIn: 5
            property int barOffGapsOut: 10
            property int barOffRounding: 10
            property int barOffBorder: 2
            onWinGapsInChanged: root.applyWindowLook()
            onWinGapsOutChanged: root.applyWindowLook()
            onWinRoundingChanged: root.applyWindowLook()
            onWinBorderChanged: root.applyWindowLook()
            onBarOffGapsInChanged: root.applyWindowLook()
            onBarOffGapsOutChanged: root.applyWindowLook()
            onBarOffRoundingChanged: root.applyWindowLook()
            onBarOffBorderChanged: root.applyWindowLook()
            // "circle" detaches the album art beside the pill (the Duo look),
            // "pill" keeps it inside the pill's content row, "off" hides it.
            property string artStyle: "circle"
            // The pill's content row, left to right, "clock" included.
            // Empty means pillDefault. Ids it does not list are slotted in
            // where pillDefault would put them, so a unit added in code still
            // shows up without the saved file knowing it.
            property var pillLayout: []
            property var pillHidden: []
            property bool liveBars: true
            property bool revealSeconds: true
            property bool revealUtc: true
            property bool revealWeather: true
            property bool revealWorkspaces: true
            property bool revealDate: true
            // The same four, kept on the resting pill instead of only on
            // hover. Always implies on-hover and switching on-hover off clears
            // always, so a piece that rests on the pill never vanishes when
            // you hover it; the handlers below keep the pairs consistent.
            property bool alwaysSeconds: false
            property bool alwaysUtc: false
            property bool alwaysWeather: false
            property bool alwaysWorkspaces: false
            // The date line under the clock was always there before it
            // became a reveal, so both of its prefs start on.
            property bool alwaysDate: true
            // 24-hour clock on the pill, and on the lock screen while this mode
            // is active; off is 12-hour with the AM/PM marker.
            property bool clock24h: false
            onAlwaysSecondsChanged: if (alwaysSeconds) revealSeconds = true
            onAlwaysUtcChanged: if (alwaysUtc) revealUtc = true
            onAlwaysWeatherChanged: if (alwaysWeather) revealWeather = true
            onAlwaysWorkspacesChanged: if (alwaysWorkspaces) revealWorkspaces = true
            onAlwaysDateChanged: if (alwaysDate) revealDate = true
            onRevealSecondsChanged: if (!revealSeconds) alwaysSeconds = false
            onRevealUtcChanged: if (!revealUtc) alwaysUtc = false
            onRevealWeatherChanged: if (!revealWeather) alwaysWeather = false
            onRevealWorkspacesChanged: if (!revealWorkspaces) alwaysWorkspaces = false
            onRevealDateChanged: if (!revealDate) alwaysDate = false
            property real islandOpacity: 0.92
            property int cardWidth: 605
            property int cardHeight: 480
            property int cardRadius: 24
            property var barShape: ({})
            // Island geometry, the video-era "Bar & Island" sliders. The bar
            // reserves pillHeightExpanded below edgeGap, so these two move
            // windows; the rest only move the island's own surfaces.
            property int pillHeight: 40
            property int pillHeightExpanded: 46
            property int edgeGap: 6
            property int cardGap: 12
            property int hoverLift: 0
            // The card and the polkit prompt grow out of the pill instead of
            // fading in; morphMs is the length of the grow.
            property bool morph: true
            property int morphMs: 340
            property int statusWarnPct: 20
            property string statusClick: "battery"
            property bool dock: true
            // The dock's pinned apps, as desktop entry ids in display order.
            // Shared by every monitor's dock, edited by dragging on the dock.
            property var dockPinned: []
            // Which shape sits at the top centre: the floating "island" pill
            // or the "notch" welded to the screen edge. Each mode keeps its
            // own look profile — the island's lives in this file, the notch's
            // in notch-prefs.json — and cfg reads whichever is active.
            property string shellMode: "island"
            // Volume / mic changes show inside the pill instead of the
            // floating OSD capsule near the bottom of the screen.
            property bool hudInIsland: false
            // A hairline along the pill's lower edge tracking the playing
            // track's position.
            property bool progressLine: true
            // The status cluster right of the clock, the mirror of the
            // workspace pills: each piece is its own toggle.
            property bool statusLayout: true
            property bool statusPrivacy: true
            property bool statusDnd: true
            property bool statusUnread: true
            property bool statusLoad: false
            property bool statusMeeting: true
        }
    }

    // ── the notch's own look profile ──────────────────────────────
    // Same per-mode keys as above with notch-shaped defaults, plus the
    // notch-only ones. Shared, machine-wide keys (silent mode, game mode,
    // dock pins) are never read from here.
    property bool notchReady: false
    property bool notchFresh: false

    FileView {
        id: notchFile
        path: "@HOME@/.local/state/quickshell/notch-prefs.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onAdapterUpdated: if (root.notchReady) notchWrite.restart()
        onLoaded: { root.notchReady = true; root.seedNotch(); }
        onLoadFailed: (error) => {
            root.notchReady = true;
            if (error === FileViewError.FileNotFound) {
                root.notchFresh = true;
                root.seedNotch();
            }
        }

        JsonAdapter {
            id: notchPrefs
            property int ccColumns: 8
            property var ccLayout: []
            property bool statusCircle: true
            property bool airpodsCircle: true
            property bool phoneCircle: true
            property bool controllerCircle: true
            property bool topTray: false
            property bool menuBar: true
            property string artStyle: "circle"
            property var pillLayout: []
            property var pillHidden: []
            property bool liveBars: true
            property bool revealSeconds: true
            property bool revealUtc: false
            property bool revealWeather: true
            property bool revealWorkspaces: true
            property bool revealDate: true
            property bool alwaysSeconds: false
            property bool alwaysUtc: false
            property bool alwaysWeather: false
            property bool alwaysWorkspaces: false
            property bool alwaysDate: false
            property bool clock24h: false
            onAlwaysSecondsChanged: if (alwaysSeconds) revealSeconds = true
            onAlwaysUtcChanged: if (alwaysUtc) revealUtc = true
            onAlwaysWeatherChanged: if (alwaysWeather) revealWeather = true
            onAlwaysWorkspacesChanged: if (alwaysWorkspaces) revealWorkspaces = true
            onAlwaysDateChanged: if (alwaysDate) revealDate = true
            onRevealSecondsChanged: if (!revealSeconds) alwaysSeconds = false
            onRevealUtcChanged: if (!revealUtc) alwaysUtc = false
            onRevealWeatherChanged: if (!revealWeather) alwaysWeather = false
            onRevealWorkspacesChanged: if (!revealWorkspaces) alwaysWorkspaces = false
            onRevealDateChanged: if (!revealDate) alwaysDate = false
            property real islandOpacity: 1.0
            property int cardWidth: 640
            property int cardHeight: 460
            property int cardRadius: 26
            property int pillHeight: 32
            property int pillHeightExpanded: 38
            // The notch is welded to the edge; these two stay for the
            // proxy's sake and the notch ignores them.
            property int edgeGap: 0
            property int cardGap: 0
            property int hoverLift: 0
            property bool morph: true
            property int morphMs: 380
            property bool hudInIsland: true
            property bool progressLine: true
            // The status cluster right of the clock, the mirror of the
            // workspace pills: each piece is its own toggle.
            property bool statusLayout: true
            property bool statusPrivacy: true
            property bool statusDnd: true
            property bool statusUnread: true
            property bool statusLoad: false
            property bool statusMeeting: true
            // ── notch-only ──
            // Radius of the concave fillets that blend the top corners
            // into the bezel; 0 squares them off.
            property int earRadius: 10
            // Bottom corner radius of the resting notch.
            property int notchRadius: 14
            // Pure black, like a hardware cutout, instead of the theme's
            // island fill.
            property bool pureBlack: true
            property bool notchShadow: true
            // Resting the pointer on the notch opens the hub after
            // hoverOpenMs, the way the macOS notch apps open.
            property bool hoverOpen: false
            property int hoverOpenMs: 450
        }
    }
    Timer {
        id: notchWrite
        interval: 300
        onTriggered: notchFile.writeAdapter()
    }

    // A first notch profile inherits the island's clock format. The hub grid
    // needs no seeding: it is one shared layout for every mode.
    function seedNotch() {
        if (!root.notchFresh || !root.notchReady || !root.prefsReady) return;
        root.notchFresh = false;
        notchPrefs.clock24h = prefs.clock24h;
        notchFile.writeAdapter();
    }

    // ── the pill's content row ────────────────────────────────────
    // Every unit the pill can carry, in the order a fresh profile gets.
    // Settings → Pill reorders them; DynamicIsland only reads pillOrder.
    readonly property var pillUnits: [
        { id: "ws",     name: "Workspaces", glyph: "\u{f056e}", hint: "Workspace buttons" },
        { id: "art",    name: "Album art",  glyph: "\u{f0025}", hint: "Cover of what is playing, when art style is In pill" },
        { id: "lead",   name: "Activity",   glyph: "\u{f00f0}", hint: "A meeting or other live activity" },
        { id: "utc",    name: "UTC",        glyph: "\u{f01e7}", hint: "UTC time" },
        { id: "clock",  name: "Clock",      glyph: "\u{f0150}", hint: "The clock — always on the pill" },
        { id: "status", name: "Status",     glyph: "\u{f01d8}", hint: "Mic, camera, DND, unread, layout, load" },
        { id: "wx",     name: "Weather",    glyph: "\u{f0595}", hint: "Weather icon and temperature" },
        { id: "cond",   name: "Conditions", glyph: "\u{f058e}", hint: "City, conditions, humidity, wind" },
        { id: "live",   name: "Live bars",  glyph: "\u{f147d}", hint: "Music bars, or the call waveform" }
    ]
    readonly property var pillDefault: root.pillUnits.map(u => u.id)
    function pillUnit(id) {
        for (const u of root.pillUnits) if (u.id === id) return u;
        return { id: id, name: id, glyph: "?", hint: "" };
    }
    function pillName(id) { return root.pillUnit(id).name; }
    // Pieces taken off the pill, in default order. The clock never is.
    readonly property var pillHiddenList: {
        const h = root.cfg.pillHidden || [];
        return root.pillDefault.filter(n => n !== "clock" && h.indexOf(n) >= 0);
    }
    // The pill's row, left to right, without the hidden pieces. A piece
    // neither list knows (added in code later) slots in where pillDefault
    // would put it.
    readonly property var pillOrder: {
        const saved = root.cfg.pillLayout || [];
        const hidden = root.pillHiddenList;
        const out = [];
        for (const n of saved)
            if (root.pillDefault.indexOf(n) >= 0 && out.indexOf(n) < 0 && hidden.indexOf(n) < 0) out.push(n);
        for (let i = 0; i < root.pillDefault.length; i++) {
            const n = root.pillDefault[i];
            if (out.indexOf(n) >= 0 || hidden.indexOf(n) >= 0) continue;
            let at = 0;
            for (let j = i - 1; j >= 0; j--) {
                const k = out.indexOf(root.pillDefault[j]);
                if (k >= 0) { at = k + 1; break; }
            }
            out.splice(at, 0, n);
        }
        return out;
    }
    // Put a piece at `to` in the pill's row (shows it if it was hidden).
    function placePillUnit(id, to) {
        const o = root.pillOrder.filter(n => n !== id);
        to = Math.max(0, Math.min(o.length, to));
        o.splice(to, 0, id);
        root.setPref("pillLayout", o);
        root.setPref("pillHidden", root.pillHiddenList.filter(n => n !== id));
    }
    function hidePillUnit(id) {
        if (id === "clock" || root.pillHiddenList.indexOf(id) >= 0) return;
        root.setPref("pillLayout", root.pillOrder.filter(n => n !== id));
        root.setPref("pillHidden", root.pillHiddenList.concat([id]));
    }
    function resetPill() {
        root.setPref("pillLayout", []);
        root.setPref("pillHidden", []);
    }

    // ── the menu bar's items ──────────────────────────────────────
    // Same model as the pill's: one ordered list with a fixed divider. Here
    // the divider is the island itself — Settings → General → Bar layout.
    readonly property var barUnits: [
        { id: "logo",      name: "Arch menu",      glyph: "\u{f303}",  hint: "Opens the power menu · right-click opens the launcher" },
        { id: "app",       name: "App name",       glyph: "\u{f0614}", hint: "The focused app and its menu" },
        { id: "ws",        name: "Workspaces",     glyph: "\u{f056e}", hint: "This monitor's workspaces · click to switch" },
        { id: "menus",     name: "Window menus",   glyph: "\u{f035c}", hint: "Window and Go menus: float, pin, fullscreen, move, workspaces" },
        { id: "notch",     name: "Island",         glyph: "\u{f06fc}", hint: "Where the island or notch sits — always on the bar" },
        { id: "status",    name: "Privacy dots",   glyph: "\u{f01d8}", hint: "Orange while the mic is in use, green while the camera or screen is" },
        { id: "call",      name: "Call",           glyph: "\u{f03f6}", hint: "App, timer and the two-voice waveform while a call is up · click opens the call · right-click mutes" },
        { id: "media",     name: "Now playing",    glyph: "\u{f0387}", hint: "Cover, track and live bars · click opens the player · middle-click pauses" },
        { id: "weather",   name: "Weather",        glyph: "\u{f0595}", hint: "Conditions and temperature · click opens the forecast" },
        { id: "monitor",   name: "Monitoring",     glyph: "\u{f029a}", hint: "CPU, RAM and GPU load · click opens monitoring" },
        { id: "tray",      name: "Tray",           glyph: "\u{f1294}", hint: "App tray icons" },
        { id: "network",   name: "Network",        glyph: "\u{f06f3}", hint: "Opens Wi-Fi / network · right-click cycles VPN" },
        { id: "bluetooth", name: "Bluetooth",      glyph: "\u{f00af}", hint: "Opens Bluetooth · right-click turns it on or off" },
        { id: "devices",   name: "Devices",        glyph: "\u{f184f}", hint: "AirPods, phone and controller charge while connected · follows the toggles in Settings → Devices · click opens batteries" },
        { id: "sound",     name: "Sound",          glyph: "\u{f057e}", hint: "Opens sound · scroll for volume · right-click mutes" },
        { id: "layout",    name: "Keyboard",       glyph: "\u{f030c}", hint: "Keyboard layout · click switches" },
        { id: "notifs",    name: "Notifications",  glyph: "\u{f009a}", hint: "Unread count and silent mode · click opens notifications" },
        { id: "hub",       name: "Control Center", glyph: "\u{f1542}", hint: "Opens the Control Center" },
        { id: "clock",     name: "Date & time",    glyph: "\u{f0150}", hint: "Opens the calendar" }
    ]
    readonly property var barDefault: root.barUnits.map(u => u.id)
    function barUnit(id) {
        for (const u of root.barUnits) if (u.id === id) return u;
        return { id: id, name: id, glyph: "?", hint: "" };
    }
    function barName(id) { return root.barUnit(id).name; }
    readonly property var barHiddenList: {
        const h = prefs.barHidden || [];
        return root.barDefault.filter(n => n !== "notch" && h.indexOf(n) >= 0);
    }
    readonly property var barOrder: {
        const saved = prefs.barLayout || [];
        const hidden = root.barHiddenList;
        const out = [];
        for (const n of saved)
            if (root.barDefault.indexOf(n) >= 0 && out.indexOf(n) < 0 && hidden.indexOf(n) < 0) out.push(n);
        for (let i = 0; i < root.barDefault.length; i++) {
            const n = root.barDefault[i];
            if (out.indexOf(n) >= 0 || hidden.indexOf(n) >= 0) continue;
            let at = 0;
            for (let j = i - 1; j >= 0; j--) {
                const k = out.indexOf(root.barDefault[j]);
                if (k >= 0) { at = k + 1; break; }
            }
            out.splice(at, 0, n);
        }
        return out;
    }
    // With the menu bar up the island keeps only the time: workspaces,
    // track, cava, weather, status (privacy dots, silent mode, unread) and
    // monitoring move onto the bar, and the detached circles stand down (DynamicIsland checks
    // cfg.menuBar for those); the AirPods and phone circles become the bar's
    // Devices item, under the same toggles. Toasts and the progress line are not units and
    // stay on the island either way.
    readonly property var pillShown: root.cfg.menuBar
        ? ["clock"]
        : root.pillOrder
    // The menu bar's band: what it draws, what it reserves above windows,
    // and where the corner fillets hang from. One place, so they agree.
    readonly property real barBand: root.cfg.barHeight > 0 ? root.cfg.barHeight
        : root.notch ? root.cfg.pillHeight
        : root.cfg.edgeGap + root.cfg.pillHeightExpanded

    // Whether the named monitor's current workspace has no windows: the
    // menu bar goes clear there when barClearWhenEmpty is on.
    function workspaceEmpty(screenName) {
        const ms = Hyprland.monitors.values;
        for (let i = 0; i < ms.length; i++) {
            if (ms[i].name !== screenName) continue;
            const w = ms[i].activeWorkspace;
            return w !== null && w.toplevels.values.length === 0;
        }
        return false;
    }
    function barAlpha(screenName) {
        return root.cfg.barClearWhenEmpty && root.workspaceEmpty(screenName) ? 0 : root.cfg.barOpacity;
    }

    // Deferred a tick: a change signal can arrive before the cfg bindings
    // it feeds have re-evaluated, which applied the previous set.
    function applyWindowLook() { Qt.callLater(root.pushWindowLook); }
    function pushWindowLook() {
        const c = root.cfg;
        Quickshell.execDetached(["hyprctl", "eval",
            "hl.config({ general = { gaps_in = " + c.winGapsIn + ", gaps_out = " + c.winGapsOut
            + ", border_size = " + c.winBorder + " }, decoration = { rounding = " + c.winRounding + " } })"]);
    }
    // Switching the menu bar (or the shell mode, whose profile carries its
    // own menuBar) swaps which set applies.
    Connections {
        target: root.cfg
        function onMenuBarChanged() { root.applyWindowLook(); }
    }
    // Once at start, for values that equal the defaults (no change signal)
    // and to win over hyprland.lua after a Hyprland reload re-read it.
    Timer { interval: 1500; running: true; onTriggered: root.applyWindowLook() }
    // A config reload (Super+Ctrl+R, or Settings applying a rebind) re-reads
    // hyprland.lua's gaps, rounding and frame, so the shell's set goes back on.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded") root.applyWindowLook();
        }
    }
    readonly property var barLeft: root.barOrder.slice(0, Math.max(0, root.barOrder.indexOf("notch")))
    readonly property var barRight: root.barOrder.slice(root.barOrder.indexOf("notch") + 1)
    function placeBarUnit(id, to) {
        const o = root.barOrder.filter(n => n !== id);
        to = Math.max(0, Math.min(o.length, to));
        o.splice(to, 0, id);
        root.setPref("barLayout", o);
        root.setPref("barHidden", root.barHiddenList.filter(n => n !== id));
    }
    function hideBarUnit(id) {
        if (id === "notch" || root.barHiddenList.indexOf(id) >= 0) return;
        root.setPref("barLayout", root.barOrder.filter(n => n !== id));
        root.setPref("barHidden", root.barHiddenList.concat([id]));
    }
    function resetBar() {
        root.setPref("barLayout", []);
        root.setPref("barHidden", []);
    }

    readonly property bool notch: prefs.shellMode === "notch"
    // The adapter the per-mode keys are read from and written to.
    readonly property var profile: root.notch ? notchPrefs : prefs
    readonly property var perModeKeys: [
        "statusCircle", "airpodsCircle", "phoneCircle", "controllerCircle", "topTray", "menuBar",
        "artStyle", "liveBars", "pillLayout", "pillHidden",
        "revealSeconds", "revealUtc", "revealWeather", "revealWorkspaces", "revealDate",
        "alwaysSeconds", "alwaysUtc", "alwaysWeather", "alwaysWorkspaces", "alwaysDate",
        "clock24h",
        "islandOpacity",
        "pillHeight", "pillHeightExpanded", "edgeGap", "cardGap", "hoverLift",
        "morph", "morphMs", "hudInIsland", "progressLine",
        "statusLayout", "statusPrivacy", "statusDnd", "statusUnread",
        "statusLoad", "statusMeeting"
    ]
    readonly property var notchOnlyKeys: [
        "earRadius", "notchRadius", "pureBlack", "notchShadow", "hoverOpen", "hoverOpenMs"
    ]
    // Bar & Shape keeps a second set of values for while the menu bar is on,
    // per island/notch mode, in prefs.barShape as "<mode>.<key>". With the
    // bar off, or before a bar-on value is set, the plain value applies.
    readonly property var barShapeKeys: [
        "pillHeight", "pillHeightExpanded", "edgeGap", "cardGap", "hoverLift", "morph", "morphMs"
    ]
    function shapeKey(key) { return (root.notch ? "notch." : "island.") + key; }
    function shaped(key, plain) {
        const o = prefs.barShape;
        const v = root.profile.menuBar && o ? o[root.shapeKey(key)] : undefined;
        return v === undefined ? plain : v;
    }
    // The one write path for every pref: the settings rows, the dock and the
    // hub all come through here, so a per-mode key lands in the active
    // profile and a shared one in the shared file.
    function setPref(key, value) {
        if (key === "dnd") { prefs.dnd = value; return; }
        if (root.profile.menuBar && root.barShapeKeys.indexOf(key) >= 0) {
            const o = Object.assign({}, prefs.barShape || {});
            o[root.shapeKey(key)] = value;
            prefs.barShape = o;
            return;
        }
        // The window look is kept per menu-bar state; Settings edits the one
        // in use, so with the bar off these land in the barOff* set.
        const offKey = { winGapsIn: "barOffGapsIn", winGapsOut: "barOffGapsOut",
                         winRounding: "barOffRounding", winBorder: "barOffBorder" }[key];
        if (offKey && !root.profile.menuBar) { prefs[offKey] = value; return; }
        if (key === "shellMode") { root.setMode(value); return; }
        if (root.notchOnlyKeys.indexOf(key) >= 0) notchPrefs[key] = value;
        else if (root.perModeKeys.indexOf(key) >= 0) root.profile[key] = value;
        else prefs[key] = value;
    }
    function setMode(m) {
        if (m !== "island" && m !== "notch") return;
        if (prefs.shellMode === m) return;
        root.closeCard();
        prefs.shellMode = m;
    }
    function toggleMode() { root.setMode(root.notch ? "island" : "notch"); }

    // The hour as every clock face shows it, two digits either way. Built by
    // hand rather than with "hh": Qt only reads `hh` as 12-hour when an AP
    // token sits in the same format string, and the faces draw the meridiem
    // as their own Text.
    // A label's size at the chosen text size. Labels are written at the
    // size they were drawn for at 13 px; glyphs and big display numbers
    // stay put because their boxes are sized around them.
    readonly property real textScale: Math.max(10, Math.min(17, prefs.textSize)) / 13
    function ts(px) { return Math.max(7, Math.round(px * root.textScale)); }

    // Search that ignores the keyboard layout: "ащте" typed on the Russian
    // or Ukrainian layout finds "font", and "ghbdtn" finds "привет". The
    // query is read as the keys that were pressed and tried as us, ru and
    // ua; a match on any of them counts.
    readonly property string kbUs:  "`qwertyuiop[]asdfghjkl;'zxcvbnm,./"
    readonly property string kbRu:  "ёйцукенгшщзхъфывапролджэячсмитьбю."
    readonly property string kbUa:  "'йцукенгшщзхїфівапролджєячсмитьбю."
    readonly property var kbToUs: {
        const m = {};
        for (let i = 0; i < root.kbUs.length; i++) {
            m[root.kbRu[i]] = root.kbUs[i];
            m[root.kbUa[i]] = root.kbUs[i];
        }
        delete m["."];
        delete m["'"];
        return m;
    }
    function searchVariants(q) {
        q = String(q || "").trim().toLowerCase();
        if (q === "") return [];
        let us = "";
        for (const c of q) us += root.kbToUs[c] !== undefined ? root.kbToUs[c] : c;
        const out = [q];
        const add = (v) => { if (out.indexOf(v) < 0) out.push(v); };
        add(us);
        for (const target of [root.kbRu, root.kbUa]) {
            let t = "";
            for (const c of us) {
                const i = root.kbUs.indexOf(c);
                t += i >= 0 && /[a-z`\[\];',]/.test(c) ? target[i] : c;
            }
            add(t);
        }
        return out;
    }
    // hay contains the query in any layout (empty query matches all)
    function searchHit(hay, q) {
        const vs = Array.isArray(q) ? q : root.searchVariants(q);
        if (vs.length === 0) return true;
        const h = String(hay || "").toLowerCase();
        for (let i = 0; i < vs.length; i++) if (h.indexOf(vs[i]) !== -1) return true;
        return false;
    }
    function searchPrefix(hay, q) {
        const vs = Array.isArray(q) ? q : root.searchVariants(q);
        const h = String(hay || "").toLowerCase();
        for (let i = 0; i < vs.length; i++) if (h.indexOf(vs[i]) === 0) return true;
        return false;
    }

    function clockHours(d) {
        const h = root.profile.clock24h ? d.getHours() : (d.getHours() % 12 || 12);
        return ("0" + h).slice(-2);
    }

    // Do-not-disturb lives here rather than in ShellRoot because the control
    // centre owns it now and NotificationPill/NotificationPopups only read it.
    property alias dnd: prefs.dnd
    // Apps that play their own notification sounds (Telegram, the Steam
    // client) are muted at the PipeWire level while silent: WirePlumber's
    // silent-mode.lua reads this switch. Sent on every change and at start,
    // which also catches up after a prefs edit made with the shell down.
    onDndChanged: root.syncSilentAudio()
    function syncSilentAudio() {
        Quickshell.execDetached(["pw-metadata", "-n", "silent-mode", "0", "on",
                                 root.dnd ? "true" : "false"]);
    }

    Timer {
        id: prefsWrite
        interval: 300
        onTriggered: prefsFile.writeAdapter()
    }

    // The prefs adapter, exposed for the pill, the card and the settings
    // window to bind against. One name, because "IslandState.cfg.liveBars"
    // reads as configuration and "prefs" stays this file's private id.
    //
    // Read-only on purpose: every write goes through setPref, which knows
    // which file a key belongs to. Per-mode keys follow the active profile.
    readonly property QtObject cfg: QtObject {
        readonly property string shellMode: prefs.shellMode
        readonly property bool notch: root.notch
        // shared
        readonly property bool dnd: prefs.dnd
        readonly property string gameMode: prefs.gameMode
        readonly property string fontBody: prefs.fontBody
        readonly property string fontDisplay: prefs.fontDisplay
        readonly property string clockFont: prefs.clockFont
        readonly property int textSize: prefs.textSize
        readonly property var ccPresets: prefs.ccPresets
        readonly property int statusWarnPct: prefs.statusWarnPct
        readonly property string statusClick: prefs.statusClick
        readonly property bool dock: prefs.dock
        readonly property var dockPinned: prefs.dockPinned
        // per mode
        // The Control Center grid is one layout for island, notch and menu bar.
        readonly property int ccColumns: prefs.ccColumns
        readonly property var ccLayout: prefs.ccLayout
        readonly property bool statusCircle: root.profile.statusCircle
        readonly property bool airpodsCircle: root.profile.airpodsCircle
        readonly property bool phoneCircle: root.profile.phoneCircle
        readonly property bool controllerCircle: root.profile.controllerCircle
        readonly property bool topTray: root.profile.topTray
        readonly property bool menuBar: root.profile.menuBar
        readonly property int barPad: prefs.barPad
        readonly property int barSpacing: prefs.barSpacing
        readonly property int barMargin: prefs.barMargin
        readonly property int barIconSize: prefs.barIconSize
        readonly property int barFontSize: prefs.barFontSize
        readonly property real barOpacity: prefs.barOpacity
        readonly property bool barDivider: prefs.barDivider
        readonly property int cornerRadius: prefs.cornerRadius
        readonly property bool cornersTop: prefs.cornersTop
        readonly property bool cornersBottom: prefs.cornersBottom
        readonly property bool cornerDots: prefs.cornerDots
        readonly property bool barFillets: prefs.barFillets
        readonly property int barHeight: prefs.barHeight
        readonly property bool barClearWhenEmpty: prefs.barClearWhenEmpty
        // The set in use: menu bar on or off.
        readonly property int winGapsIn: root.profile.menuBar ? prefs.winGapsIn : prefs.barOffGapsIn
        readonly property int winGapsOut: root.profile.menuBar ? prefs.winGapsOut : prefs.barOffGapsOut
        readonly property int winRounding: root.profile.menuBar ? prefs.winRounding : prefs.barOffRounding
        readonly property int winBorder: root.profile.menuBar ? prefs.winBorder : prefs.barOffBorder
        readonly property string artStyle: root.profile.artStyle
        readonly property var pillLayout: root.profile.pillLayout
        readonly property var pillHidden: root.profile.pillHidden
        readonly property bool liveBars: root.profile.liveBars
        readonly property bool revealSeconds: root.profile.revealSeconds
        readonly property bool revealUtc: root.profile.revealUtc
        readonly property bool revealWeather: root.profile.revealWeather
        readonly property bool revealWorkspaces: root.profile.revealWorkspaces
        readonly property bool revealDate: root.profile.revealDate
        readonly property bool alwaysSeconds: root.profile.alwaysSeconds
        readonly property bool clock24h: root.profile.clock24h
        readonly property bool alwaysUtc: root.profile.alwaysUtc
        readonly property bool alwaysWeather: root.profile.alwaysWeather
        readonly property bool alwaysWorkspaces: root.profile.alwaysWorkspaces
        readonly property bool alwaysDate: root.profile.alwaysDate
        readonly property real islandOpacity: root.profile.islandOpacity
        // The card, and the Control Center in it, is one size for every mode.
        readonly property int cardWidth: prefs.cardWidth
        readonly property int cardHeight: prefs.cardHeight
        readonly property int cardRadius: prefs.cardRadius
        readonly property int pillHeight: root.shaped("pillHeight", root.profile.pillHeight)
        readonly property int pillHeightExpanded: root.shaped("pillHeightExpanded", root.profile.pillHeightExpanded)
        // The notch is welded to the edge and hangs its card straight off
        // its own body, so both gaps are zero there whatever its file says.
        readonly property int edgeGap: root.notch ? 0 : root.shaped("edgeGap", prefs.edgeGap)
        readonly property int cardGap: root.notch ? 0 : root.shaped("cardGap", prefs.cardGap)
        readonly property int hoverLift: root.notch ? 0 : root.shaped("hoverLift", prefs.hoverLift)
        readonly property bool morph: root.shaped("morph", root.profile.morph)
        readonly property int morphMs: root.shaped("morphMs", root.profile.morphMs)
        readonly property bool hudInIsland: root.profile.hudInIsland
        readonly property bool progressLine: root.profile.progressLine
        readonly property bool statusLayout: root.profile.statusLayout
        readonly property bool statusPrivacy: root.profile.statusPrivacy
        readonly property bool statusDnd: root.profile.statusDnd
        readonly property bool statusUnread: root.profile.statusUnread
        readonly property bool statusLoad: root.profile.statusLoad
        readonly property bool statusMeeting: root.profile.statusMeeting
        // notch only
        readonly property int earRadius: notchPrefs.earRadius
        readonly property int notchRadius: notchPrefs.notchRadius
        readonly property bool pureBlack: notchPrefs.pureBlack
        readonly property bool notchShadow: notchPrefs.notchShadow
        readonly property bool hoverOpen: notchPrefs.hoverOpen
        readonly property int hoverOpenMs: notchPrefs.hoverOpenMs
    }

    // The settings window is a real window and lives in shell.qml like the
    // wallpaper picker; this is how the card's gear and the IPC target reach
    // it without the singleton knowing the window exists.
    signal settingsRequested()
    function openSettings() { root.settingsRequested(); }

    // The theme carousel's Ctrl+B. The wallpaper browser is a window in
    // shell.qml too, and this seam replaces a `qs ipc` child process that
    // died with the carousel the moment the card closed.
    signal wallpapersRequested(string theme)
    function openWallpapers(theme) { root.wallpapersRequested(theme); }

    function setCcLayout(lay) { prefs.ccLayout = lay; }
    function setCcColumns(n) { prefs.ccColumns = Math.max(5, Math.min(9, n)); }
    function resetCcLayout() { prefs.ccLayout = []; }

    // ── layout presets ────────────────────────────────────────────
    // A preset carries its column count: the same cells on another count
    // get relocated by the hub's sanitizer, so applying one sets both.
    function saveCcPreset(name, columns, layout) {
        const n = (name || "").trim();
        if (n === "") return;
        const out = [];
        const cur = prefs.ccPresets || [];
        for (let i = 0; i < cur.length; i++) if (cur[i].name !== n) out.push(cur[i]);
        out.push({ name: n, columns: columns, layout: layout });
        out.sort((a, b) => a.name.localeCompare(b.name));
        prefs.ccPresets = out;
    }
    function applyCcPreset(name) {
        const cur = prefs.ccPresets || [];
        for (let i = 0; i < cur.length; i++) {
            if (cur[i].name !== name) continue;
            prefs.ccColumns = Math.max(5, Math.min(9, cur[i].columns || prefs.ccColumns));
            prefs.ccLayout = (cur[i].layout || []).slice();
            return;
        }
    }
    function deleteCcPreset(name) {
        prefs.ccPresets = (prefs.ccPresets || []).filter(p => p.name !== name);
    }

    // The hub's lock tile. The session lock lives in shell.qml's LockScreen
    // scope; this is how the grid reaches it without the singleton knowing
    // the window exists — same seam as the settings window.
    signal lockRequested()
    // True while the session lock is up. The desktop bar's island keeps its
    // card shut then; the lock surface's island opens it instead.
    property bool locked: false
    function requestLock() { root.lockRequested(); }


    // Which monitor a keybind-driven open should land on. The card is anchored
    // to one island, so "wherever the pointer is working" is the only sensible
    // answer — the same reasoning Osd uses to pick its screen.
    function activeScreen() {
        return Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
    }
    function ipcId(id) { return "ipc:" + id; }

    // Same idiom as the bar/gamemode/notifications handlers in shell.qml.
    // The old PowerMenu carried this target; keeping the name means any
    // keybind or script that called it still lands somewhere sensible.
    IpcHandler {
        target: "power"
        function toggle(): void { root.toggleTool("power", root.activeScreen()); }
        function open(): void { root.openTool("power", root.activeScreen()); }
        function close(): void { root.closeCard(); }
    }

    // The app launcher lived in its own window under this target until
    // 2026-09-21; it is the island's "apps" sheet now, and the old name keeps
    // every keybind and script that still says `launcher toggle` working.
    IpcHandler {
        target: "launcher"
        function toggle(): void { root.toggleTool("apps", root.activeScreen()); }
        function open(): void { root.openTool("apps", root.activeScreen()); }
        function close(): void { if (root.tool === "apps") root.closeCard(); }
    }

    IpcHandler {
        target: "island"
        function open(tool: string): void { root.openTool(tool, root.activeScreen()); }
        function toggle(tool: string): void { root.toggleTool(tool, root.activeScreen()); }
        // The menu bar's way in: the tool takes the whole card, no hub under it.
        function direct(tool: string): void { root.toggleDirect(tool, root.activeScreen()); }
        // Opens a tool on a named monitor instead of the focused one — for
        // scripts and for checking a panel while a game holds focus elsewhere.
        function openon(tool: string, screen: string): void { root.openTool(tool, screen); }
        // Worth a keybind: this is the machine's mute key while a call is up,
        // and it works whether or not the app has focus.
        // Context-aware: acts on whichever call is up. What the card uses.
        function callmute(): string { return root.toggleCallMute(); }
        function calldeafen(): string { return root.toggleCallDeafen(); }
        // Always Discord, call or no call. What the keybinds use.
        function discordmute(): string { return root.discordMute(); }
        function discorddeafen(): string { return root.discordDeafen(); }
        function close(): void { root.closeCard(); }
        // Island ⇄ notch. `mode` with no recognised name just reports.
        function mode(name: string): string { root.setMode(name); return prefs.shellMode; }
        function togglemode(): string { root.toggleMode(); return prefs.shellMode; }
        function settings(): void { root.openSettings(); }
        function timer(seconds: int): void { root.timerStart(seconds); }
        // A timer you can start from a keybind you must also be able to stop
        // from one; until now cancelling meant opening the tool and clicking.
        function timerpause(): void { root.timerToggle(); }
        function timerreset(): void { root.timerReset(); }
        function idle(mode: string): void {
            if (mode === "cycle") root.cycleIdleMode(); else root.setIdleMode(mode);
        }

        // Anything that can run a command can put a live activity in the
        // island — a long build, a deploy, an upgrade:
        //   qs ipc call island publish deploy trail "deploying" "helm upgrade"
        //   qs ipc call island advance deploy 0.4
        //   qs ipc call island retract deploy
        // Ids are namespaced so a script can never clobber the meeting or the
        // timer, and the priority sits below both.
        function publish(id: string, slot: string, title: string, sub: string): void {
            const prev = root.activities[root.ipcId(id)];
            root.publish(root.ipcId(id), {
                slot: (slot === "lead" || slot === "main") ? slot : "trail",
                priority: 20,
                title: title,
                sub: sub,
                glyph: "\u{f0493}",
                tone: "accent",
                progress: prev ? prev.progress : -1
            });
        }
        function advance(id: string, value: real): void {
            const cur = root.activities[root.ipcId(id)];
            if (!cur) return;
            const next = {};
            for (const k in cur) next[k] = cur[k];
            next.progress = Math.max(0, Math.min(1, value));
            root.publish(root.ipcId(id), next);
        }
        function retract(id: string): void { root.retract(root.ipcId(id)); }

        // Re-reads the pinned note. The tool calls refreshPinnedNote() itself
        // after every change it makes; this is for anything that edits the
        // notes folder from outside the island.
        function repin(): void { root.refreshPinnedNote(); }

        function alerts(): string {
            return JSON.stringify(root.alerts) + "  lead=" + JSON.stringify(root.lead);
        }
        function status(): string {
            return (root.tool === "" ? "closed" : root.tool + " on " + root.toolScreen)
                 + (root.timerTotal > 0
                    ? "  ·  timer " + root.timerText
                      + (root.timerDone
                         ? (root.timerAlarming ? " ringing" : " done")
                         : (root.timerRunning ? " running" : " paused"))
                    : "")
                 + (root.inCall
                    ? "  ·  " + root.callApp.name + " call " + root.timerFmt(root.callSecs)
                      + (root.callMuted ? " muted" : "")
                      + (root.callDeafened ? " deafened" : "")
                      + (root.callRpc ? " (rpc)" : "")
                    : "")
                 + "  ·  discord rpc: "
                   + (root.dcAuthed ? "authed"
                      : (root.dcConnected ? "connected" : "down"))
                   + (root.dcReason !== "" ? " (" + root.dcReason + ")" : "")
                   + (root.dcChannel !== "" ? " in " + root.dcChannel : "")
                 + (root.dnd ? "  ·  silent" : "")
                 + "  ·  weather " + (root.wxAgeMins < 0 ? "never fetched"
                    : root.wxAgeMins + "m old" + (root.wxStale ? " (stale)" : ""));
        }
    }

    // ── activity registry ─────────────────────────────────────────
    // Anything that wants the pill publishes an activity under an id;
    // publishing the same id again replaces it rather than stacking. Each
    // activity names the slot it wants:
    //
    //   "lead"  — its own segment left of the clock, two lines, like a meeting
    //   "main"  — replaces the clock text for as long as it is up
    //   "trail" — the detached capsule right of the pill, for something that
    //             keeps running while the main slot carries on changing
    //
    // Shape: { slot, priority, title, sub, tint, glyph, image, progress, action }
    // where progress < 0 means "no bar", image is an optional avatar shown in
    // the main slot, and action is an optional function run when that segment
    // is clicked.
    property var activities: ({})

    function publish(id, data) {
        const next = {};
        for (const k in root.activities) next[k] = root.activities[k];
        if (data === null) delete next[id];
        else next[id] = data;
        root.activities = next;
    }
    function retract(id) { root.publish(id, null); }

    // Written out per slot rather than routed through a shared pick(slot)
    // helper: the binding has to read root.activities in its own scope for the
    // engine to re-evaluate it when an activity is published or retracted.
    function bestIn(acts, slot) {
        let best = null;
        // With the menu bar on, the island shows notifications and the
        // keyboard-layout flash only: the track, volume and the rest already
        // live on the bar, but a layout switch is an answer to a key just
        // pressed and keeps its animation on the island.
        const barMode = root.cfg.menuBar;
        for (const k in acts) {
            const a = acts[k];
            if (a.slot !== slot) continue;
            if (barMode && k !== "notif" && k !== "layout") continue;
            if (best === null || (a.priority || 0) > (best.priority || 0)) best = a;
        }
        return best;
    }
    readonly property var lead: root.bestIn(root.activities, "lead")
    readonly property var main: root.bestIn(root.activities, "main")
    readonly property var trail: root.bestIn(root.activities, "trail")

    // ── output device priority ────────────────────────────────────
    // Where sound goes when the choice is not the user's: AirPods first, then
    // the IEM jack, then the desk speakers. The control tool ranks its output
    // list from the same table, so what you see there and what the machine
    // picks from are one order, maintained in one place.
    //
    // Each pattern is matched against the friendly label AND the raw
    // node.name. The labels come from WirePlumber (51-device-rename.conf) and
    // are empty until a node is tracked, so name matching is what makes the
    // rank right at the instant a device appears — which is exactly when this
    // has to decide. The bluetooth entry carries the MAC so other BT audio
    // (the DualSense) is never mistaken for the headphones.
    readonly property var sinkOrder: [
        /airpods/i,
        /truthear|pci-0000_00_1f\.3/i,
        /speakers|elite_silicon/i
    ]

    function sinkLabel(n) {
        if (!n) return "";
        return n.nickname || n.description || n.name || "";
    }

    function sinkRank(n) {
        if (!n) return root.sinkOrder.length;
        const hay = (root.sinkLabel(n) + " " + (n.name || "")).toLowerCase();
        for (let i = 0; i < root.sinkOrder.length; i++)
            if (root.sinkOrder[i].test(hay)) return i;
        return root.sinkOrder.length;
    }

    // Devices, not streams: an application's playback node is not somewhere
    // sound can be sent.
    readonly property var sinkNodes: {
        const out = [];
        const ns = Pipewire.nodes ? Pipewire.nodes.values : [];
        for (let i = 0; i < ns.length; i++) {
            const n = ns[i];
            if (!n.audio || n.isStream || !n.isSink) continue;
            out.push(n);
        }
        return out;
    }

    // The rank reads descriptions, which only exist for tracked nodes.
    PwObjectTracker { objects: root.sinkNodes }

    readonly property var sinkNames: root.sinkNodes.map(n => n.name).sort()

    // The policy acts on arrival and departure, never on the quiet in between:
    // choosing Speakers by hand while the Hexa is plugged in has to stick, or
    // the picker in the control tool is decoration. So an output that *just
    // appeared* takes over only if it outranks the current one, a default that
    // disappeared is replaced by the best remaining, and nothing else moves it.
    property var knownSinks: []
    property bool sinkPolicyArmed: false

    // Devices register over the first seconds of a session, and the default
    // WirePlumber restores lands somewhere in that window. Arming late means
    // the restored default is treated as the starting position rather than as
    // three devices arriving at once.
    Timer {
        interval: 4000
        running: Pipewire.ready
        onTriggered: {
            root.knownSinks = root.sinkNames;
            root.sinkPolicyArmed = true;
        }
    }

    // PipeWire's "default" metadata object belongs to the session manager, so
    // restarting wireplumber tears it down and rebuilds it while Pipewire.ready
    // stays true the whole time — the daemon connection never dropped, and
    // there is no metadata-readiness property to test. Writes that land in that
    // window are discarded with "Cannot set default node as metadata is not
    // ready", and nothing re-ran the policy afterwards, so the preferred sink
    // silently stopped being applied until the next device change.
    //
    // Coalescing the restart's burst of node churn into one late run puts the
    // write after the rebuild, and setPreferredSink re-queues itself if it
    // still did not take.
    Timer {
        id: sinkSettle
        interval: 700
        onTriggered: root.applySinkPolicy()
    }
    onSinkNamesChanged: sinkSettle.restart()

    // The write is a no-op while the metadata is missing, and it reports that
    // only to the log. Reading the property back is the one signal available
    // here that it actually landed. Bounded, so a sink that genuinely cannot
    // be made default does not spin forever.
    property int sinkRetries: 0
    readonly property int sinkRetryLimit: 5
    function setPreferredSink(node) {
        Pipewire.preferredDefaultAudioSink = node;
        if (Pipewire.preferredDefaultAudioSink === node) {
            root.sinkRetries = 0;
            return;
        }
        if (root.sinkRetries >= root.sinkRetryLimit) return;
        root.sinkRetries++;
        sinkSettle.restart();
    }

    function bestSink(nodes) {
        let best = null;
        let bestRank = root.sinkOrder.length + 1;
        for (let i = 0; i < nodes.length; i++) {
            const r = root.sinkRank(nodes[i]);
            if (r < bestRank) { best = nodes[i]; bestRank = r; }
        }
        return best;
    }

    function applySinkPolicy() {
        if (!root.sinkPolicyArmed) return;

        const now = root.sinkNames;
        const prev = root.knownSinks;
        root.knownSinks = now;

        // Gone. Covers unplugging, and also the bluetooth profile flip a call
        // triggers, which swaps one AirPods node for another.
        const cur = Pipewire.defaultAudioSink;
        if (!cur || now.indexOf(cur.name) === -1) {
            const fallback = root.bestSink(root.sinkNodes);
            if (fallback) root.setPreferredSink(fallback);
            return;
        }

        const arrived = root.sinkNodes.filter(n => prev.indexOf(n.name) === -1);
        const claim = root.bestSink(arrived);
        if (claim && root.sinkRank(claim) < root.sinkRank(cur))
            root.setPreferredSink(claim);
    }

    // ── screen capture ────────────────────────────────────────────
    // Flameshot's capture overlay is an ordinary floating window (see the
    // flameshot-editor rule in hyprland.lua), so the shell's layers would sit
    // on top of it. While it is open on a monitor, that monitor's bar,
    // island, dock and corners step aside: they go fully transparent and
    // click-through but keep their reserved zones, so no window resizes
    // under the frozen screenshot.
    function capturingOn(screenName) {
        const ts = ToplevelManager.toplevels.values;
        for (let i = 0; i < ts.length; i++) {
            const t = ts[i];
            if (t.appId !== "flameshot" || t.title !== "flameshot") continue;
            const ss = t.screens || [];
            if (ss.length === 0) return true;
            for (let j = 0; j < ss.length; j++) if (ss[j] && ss[j].name === screenName) return true;
        }
        return false;
    }

    // ── now playing ───────────────────────────────────────────────
    // Player selection lives here so the tool and the track flash agree on
    // which one they mean. Spotify wins when it is up; a browser tab playing
    // in the background should not steal the island from it.
    readonly property var player: {
        const all = Mpris.players.values;
        for (let i = 0; i < all.length; i++)
            if (String(all[i].dbusName).toLowerCase().indexOf("spotify") !== -1) return all[i];
        return all.length > 0 ? all[0] : null;
    }

    // Whether the pill should carry the playing indicator — art on one end,
    // live bars on the other, no text, after the phone island this is modelled
    // on. The full view lives in the media tool.
    readonly property bool mediaPlaying:
        player !== null && player.isPlaying && player.trackTitle !== ""

    // ── audio-reactive wave data ──────────────────────────────────
    // cava feeds 12 bars at 24fps whenever the machine is making sound; the
    // process dies with the audio, so silence costs nothing. One instance for
    // the whole machine — the old bar pill ran one per monitor — and both the
    // island pills and the media tool draw from these values.
    //
    // The trigger is the audio graph rather than MPRIS. A browser tab, mpv, a
    // game and Spotify all reach the speakers the same way, but only some of
    // them announce themselves on D-Bus, so metadata is the wrong question to
    // ask: a link group carries both the stream and whether it is actually
    // running, which is the same answer for every one of them.
    // Link state is only live on a tracked object — an untracked group reports
    // -1 for every state, which reads as "not active" and silently never fires.
    PwObjectTracker { objects: Pipewire.linkGroups ? Pipewire.linkGroups.values : [] }

    readonly property bool audioActive: {
        const gs = Pipewire.linkGroups ? Pipewire.linkGroups.values : [];
        for (let i = 0; i < gs.length; i++) {
            const g = gs[i];
            if (g.state !== PwLinkState.Active) continue;
            // Playback only — app to device. The reverse direction is a
            // capture, and the capture on this machine is cava itself reading
            // the monitor, which would keep it alive on its own output.
            const s = g.source, t = g.target;
            if (!s || !t || !s.isStream || t.isStream) continue;
            return true;
        }
        return false;
    }

    property var wavTargets: []
    property var wavVals: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    property int wavFrame: 0

    // The bars answer "how is this moving", not "how loud is it". Every volume
    // that sits before the monitor cava reads — the player's own stream volume
    // always, and the sink's too on any output mixed in software rather than
    // in hardware — scales the signal, so unscaled bars shrink when the volume
    // does. Dividing by a rolling peak takes all of them out at once, without
    // having to know which one moved. cava emits 0..1000 (`ascii_max_range`)
    // rather than 0..7 so there is something left to scale at low levels: a
    // signal 20 dB down lands near 100, where on the old range it floored to
    // zero and no amount of gain brought it back.
    property real wavPeak: 0
    readonly property real wavSilence: 25

    // The canvas answers to two things only: a player that says it is
    // playing, and a call. A game's gunfire or a browser tab without MPRIS
    // reaches the speakers too, but the island is not a VU meter for the
    // machine — it is the phone's now-playing and on-a-call signal. The
    // audio graph still has to agree (a "playing" player with no stream is
    // a stale D-Bus claim), so cava runs on the intersection.
    readonly property bool wavWanted: root.audioActive && (root.mediaPlaying || root.inCall)

    // An open stream is not the same as a sound. Spotify keeps one across a
    // pause, so `wavWanted` is the right gate for *running cava* and the
    // wrong one for showing the bars: it would leave them parked at zero on
    // the pill. The signal itself decides that, and the peak's slow decay
    // carries them over a gap between tracks rather than blinking out between
    // every one. A call takes the slot with its own waveform instead.
    readonly property bool wavAudible:
        root.mediaPlaying && !root.inCall && root.wavPeak >= root.wavSilence

    Process {
        running: root.wavWanted
        command: ["cava", "-p", "@HOME@/.config/quickshell/scripts/cava.conf"]
        stdout: SplitParser {
            onRead: data => {
                const parts = data.trim().split(" ").filter(s => s.length > 0);
                if (parts.length < 2) return;
                const raw = parts.map(s => parseInt(s) || 0);

                let top = 0;
                for (let i = 0; i < raw.length; i++) if (raw[i] > top) top = raw[i];
                // Instant attack, slow release: a hit lands at full height, and
                // the phrase after it keeps its shape instead of being pumped
                // back up bar by bar.
                root.wavPeak = Math.max(top, root.wavPeak * 0.992);

                // An active stream outputting near-nothing is a gap between
                // tracks or a muted tab, not something to amplify into a full
                // waveform.
                if (root.wavPeak < root.wavSilence) {
                    root.wavTargets = raw.map(() => 0);
                    return;
                }
                const k = 7 / root.wavPeak;
                root.wavTargets = raw.map(v => Math.min(7, v * k));
            }
        }
    }

    // ── the call's second ear ─────────────────────────────────────
    // During a call the monitor only hears the other side. A second cava on
    // the default source hears you, and the call waveform is the louder of
    // the two per band, so the line moves whoever is talking. The mic path
    // has a harder gate and a floor under its scale: peak-normalising a
    // silent room would amplify the noise floor into fake speech within a
    // few seconds of the last word.
    property var micTargets: []
    property real micPeak: 0
    readonly property real micSilence: 80
    readonly property real micFloor: 250

    Process {
        running: root.audioActive && root.inCall
        command: ["cava", "-p", "@HOME@/.config/quickshell/scripts/cava-mic.conf"]
        stdout: SplitParser {
            onRead: data => {
                const parts = data.trim().split(" ").filter(s => s.length > 0);
                if (parts.length < 2) return;
                const raw = parts.map(s => parseInt(s) || 0);
                let top = 0;
                for (let i = 0; i < raw.length; i++) if (raw[i] > top) top = raw[i];
                root.micPeak = Math.max(top, root.micPeak * 0.992);
                if (top < root.micSilence) { root.micTargets = raw.map(() => 0); return; }
                const k = 7 / Math.max(root.micPeak, root.micFloor);
                root.micTargets = raw.map(v => Math.min(7, v * k));
            }
        }
        onRunningChanged: if (!running) { root.micTargets = []; root.micPeak = 0; }
    }

    // The call waveform wants one loudness per side per tick, not a spectrum:
    // it is a scrolling history of who spoke, so each side collapses to its
    // mean band level. Lerped like the bars so a syllable rises and falls
    // rather than steps.
    property real callThem: 0
    property real callMe: 0

    // Lerp toward the latest cava frames at ~30fps so the 24fps ascii steps
    // render as motion instead of jumps. On pause the waves clear rather
    // than freezing mid-shape. One tick moves both the media bars and the
    // call levels, so they share a doorbell (wavFrame).
    Timer {
        interval: 33
        running: root.wavWanted
        repeat: true
        onTriggered: {
            const v = root.wavVals, t = root.wavTargets;
            for (let i = 0; i < v.length; i++)
                v[i] += ((i < t.length ? t[i] : 0) - v[i]) * 0.35;
            const m = root.micTargets;
            let them = 0, me = 0;
            for (let i = 0; i < t.length; i++) them += t[i];
            for (let i = 0; i < m.length; i++) me += m[i];
            them = t.length ? them / (t.length * 7) : 0;
            me = m.length ? me / (m.length * 7) : 0;
            root.callThem += (them - root.callThem) * 0.35;
            root.callMe += (me - root.callMe) * 0.35;
            root.wavFrame++;
        }
        onRunningChanged: if (!running) {
            root.wavTargets = [];
            root.wavVals = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
            root.callThem = 0;
            root.callMe = 0;
            // The next sound starts its own scale rather than inheriting the
            // one the last one ended on.
            root.wavPeak = 0;
            root.wavFrame++;
        }
    }

    // A track change takes the main slot for a moment and hands the clock
    // straight back. Keyed on title+artist rather than on the player object, so
    // pausing, seeking or a metadata refresh does not re-fire it.
    readonly property string trackKey:
        root.player && root.player.trackTitle
        ? root.player.trackTitle + " " + root.player.trackArtist : ""

    // Suppresses the flash that would otherwise fire for whatever happens to be
    // playing when the shell starts or reloads.
    property bool trackArmed: false
    Timer { interval: 2500; running: true; onTriggered: root.trackArmed = true }

    onTrackKeyChanged: {
        if (!root.trackArmed) return;
        if (root.trackKey === "") { root.retract("track"); return; }
        // Silent means the island holds still: a song change is exactly the
        // kind of chatter the switch exists to mute. The art circle and live
        // bars keep moving — state, not announcements.
        if (root.dnd) return;
        root.publish("track", {
            slot: "main",
            priority: 70,
            title: root.player.trackTitle,
            sub: root.player.trackArtist,
            tone: "accent",
            progress: -1,
            action: function () { root.toggleTool("media", root.activeScreen()); }
        });
        trackHold.restart();
    }
    Timer { id: trackHold; interval: 2600; onTriggered: root.retract("track") }

    // Where the current track is, 0..1, or -1 with nothing playing. MPRIS
    // only reports position when asked, so it is polled — once a second,
    // and only while something plays and a progress line wants it.
    property real trackProgress: -1
    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.mediaPlaying && root.cfg.progressLine
        onTriggered: {
            const p = root.player;
            root.trackProgress = p && p.length > 0
                ? Math.max(0, Math.min(1, p.position / p.length)) : -1;
        }
        onRunningChanged: if (!running) root.trackProgress = -1
    }

    // ── volume / mic HUD in the pill ──────────────────────────────
    // Osd hands its flashes here when hudInIsland is on: the level takes the
    // main slot as a bar for a moment, the way the notch apps replace the
    // system HUD. Above the track flash and the layout, below a notification.
    function showHud(kind, level, muted) {
        const mic = kind === "mic";
        const pct = Math.round(level * 100);
        root.publish("hud", {
            slot: "main",
            priority: 80,
            style: "hud",
            glyph: mic ? (muted ? "\u{f036d}" : "\u{f036c}")
                 : muted ? "\u{f075f}" : pct < 34 ? "\u{f057f}" : pct < 67 ? "\u{f0580}" : "\u{f057e}",
            title: muted ? "Muted" : pct + "%",
            tone: muted ? "muted" : "fg",
            progress: muted ? 0 : Math.min(1, level),
            action: function () { root.toggleTool("audio", root.activeScreen()); }
        });
        hudHold.restart();
    }
    Timer { id: hudHold; interval: 1500; onTriggered: root.retract("hud") }

    // ── weather ───────────────────────────────────────────────────
    // Here for the same reason the calendar poll is: per-island it ran once
    // per monitor, so sinoptik was fetched twice every 15 minutes for one
    // machine's worth of weather.
    // The city is the single source of truth: the script scrapes it and the
    // pill's right-click link points at the same page.
    property string wxCity: "kyiv"
    readonly property string wxUrl: "https://sinoptik.ua/pohoda/" + root.wxCity + "/10-dniv"
    property string wxIcon: "\u{e312}"
    property string wxTemp: "--"
    property string wxFeels: ""
    property string wxDesc: ""
    property string wxArea: ""
    property string wxHumidity: ""
    property string wxWind: ""
    property string wxUv: ""
    property string wxSunrise: ""
    property string wxSunset: ""
    property var wxForecast: []
    // The next 24 hours from the current one, flat; each forecast day also
    // carries its own `hours` for a reader that wants a specific date.
    property var wxHourly: []

    // A failed fetch keeps the last good reading, which is the right call —
    // but it used to keep it silently, so a provider that had been down all
    // day still showed this morning's sky as if it were now. The fetch time is
    // recorded so the panel can say how old the reading is, and go explicit
    // once it is older than two poll intervals.
    property real wxFetched: 0
    readonly property int wxAgeMins:
        wxFetched > 0 ? Math.floor((clk.date - wxFetched) / 60000) : -1
    readonly property bool wxStale: wxAgeMins > 30

    function ingestWeather(raw) {
        const s = (raw || "").trim();
        if (s === "" || s.charAt(0) !== "{") return;
        try {
            const j = JSON.parse(s);
            root.wxFetched = Date.now();
            root.wxIcon = j.icon || "\u{e312}";
            root.wxTemp = j.temp !== undefined ? j.temp : "--";
            root.wxFeels = j.feels || "";
            root.wxDesc = j.desc || "";
            root.wxArea = j.area || "";
            root.wxHumidity = j.humidity || "";
            root.wxWind = j.wind || "";
            root.wxUv = j.uv || "";
            root.wxSunrise = j.sunrise || "";
            root.wxSunset = j.sunset || "";
            root.wxForecast = Array.isArray(j.forecast) ? j.forecast : [];
            root.wxHourly = Array.isArray(j.hourly) ? j.hourly : [];
        } catch (e) { /* keep the last good reading */ }
    }

    Process {
        id: wproc
        command: ["bash", "@HOME@/.config/quickshell/scripts/weather.sh", root.wxCity]
        stdout: StdioCollector { onStreamFinished: root.ingestWeather(this.text) }
    }
    Timer {
        interval: 900000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: wproc.running = true
    }

    // ── load rings ────────────────────────────────────────────────
    // CPU from two /proc/stat readings, GPU from nvidia-smi, every two
    // seconds — and only while a status cluster shows the rings, so the
    // machine pays nothing for it otherwise. -1 means not measured yet.
    property real cpuLoad: -1
    property real gpuLoad: -1
    // Used memory (MemTotal − MemAvailable), for the menu bar's Monitoring.
    property real memLoad: -1
    property var cpuPrev: null
    function ingestLoad(raw) {
        const lines = (raw || "").trim().split("\n");
        const f = (lines[0] || "").trim().split(/\s+/);
        if (f[0] === "cpu") {
            let total = 0;
            for (let i = 1; i < f.length; i++) total += Number(f[i]) || 0;
            const idle = (Number(f[4]) || 0) + (Number(f[5]) || 0);
            if (root.cpuPrev) {
                const dt = total - root.cpuPrev.total, di = idle - root.cpuPrev.idle;
                if (dt > 0) root.cpuLoad = Math.max(0, Math.min(1, (dt - di) / dt));
            }
            root.cpuPrev = { total: total, idle: idle };
        }
        const g = Number((lines[1] || "").trim());
        if (lines.length > 1 && lines[1].trim() !== "" && !isNaN(g) && !/^Mem/.test(lines[1]))
            root.gpuLoad = Math.max(0, Math.min(1, g / 100));
        let memT = 0, memA = 0;
        for (const ln of lines) {
            const m = ln.match(/^(MemTotal|MemAvailable):\s+(\d+)/);
            if (m) { if (m[1] === "MemTotal") memT = Number(m[2]); else memA = Number(m[2]); }
        }
        if (memT > 0) root.memLoad = Math.max(0, Math.min(1, (memT - memA) / memT));
    }
    Process {
        id: loadProc
        command: ["bash", "-c", "head -1 /proc/stat; nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1; grep -E '^Mem(Total|Available):' /proc/meminfo"]
        stdout: StdioCollector { onStreamFinished: root.ingestLoad(this.text) }
    }
    Timer {
        interval: 2000
        repeat: true
        triggeredOnStart: true
        running: root.cfg.statusLoad || (root.cfg.menuBar && root.barOrder.indexOf("monitor") >= 0)
        onTriggered: loadProc.running = true
        onRunningChanged: if (!running) { root.cpuPrev = null; root.cpuLoad = -1; root.gpuLoad = -1; root.memLoad = -1; }
    }

    // ── upcoming meeting ──────────────────────────────────────────
    // A single heads-up, and nothing else. The island used to carry a live
    // segment for this — a countdown re-derived from the clock every tick,
    // a progress ring, a dismiss control — and it was removed on 2026-08-26:
    // the pill is for what is happening now, and the calendar tool already
    // answers what is next, better and on demand.
    //
    // The poll stays because the notification needs it, and `meeting` stays
    // because a calendar notification is tinted with its event's own colour.
    // Polled with a 60-minute lookahead so the pill's countdown can show from
    // an hour out; the heads-up notification still waits for the last 15.
    property var meeting: null
    readonly property var meetingStart: root.meeting ? root.parseLocal(root.meeting.startsAt) : null
    // Minutes to the start, recomputed on the clock; <= 0 once it is on.
    readonly property int meetingMins: root.meetingStart
        ? Math.ceil((root.meetingStart - clk.date) / 60000) : 0
    function openMeeting() {
        const m = root.meeting;
        if (m && m.meet) root.open(m.meet);
        else if (m && m.link) root.open(m.link);
        else root.toggleTool("calendar", root.activeScreen());
    }
    property var notifiedUids: ({})

    // "2026-08-06T11:30" as local time. Date's own parser treats a
    // seconds-less ISO string as UTC, which would shift this by the offset.
    function parseLocal(s) {
        const p = (s || "").split("T");
        if (p.length !== 2) return null;
        const d = p[0].split("-"), t = p[1].split(":");
        return new Date(d[0], d[1] - 1, d[2], t[0], t[1]);
    }

    function ingestNext(raw) {
        const s = (raw || "").trim();
        if (s === "" || s.charAt(0) !== "{") return;
        try {
            const j = JSON.parse(s);
            root.meeting = j.found ? j : null;
            const start = root.meeting ? root.parseLocal(root.meeting.startsAt) : null;
            const mins = start ? Math.ceil((start - clk.date) / 60000) : 0;
            if (root.meeting && mins <= 15 && !root.notifiedUids[root.meeting.uid]) {
                root.notifiedUids[root.meeting.uid] = true;
                notifier.command = ["notify-send", "-a", "calendar",
                                    "-i", "x-office-calendar",
                                    mins > 0 ? "Meeting in " + mins + "m" : "Meeting now",
                                    root.meeting.title + "  ·  " + root.meeting.start];
                notifier.running = true;
            }
        } catch (e) { /* keep last state */ }
    }

    Process {
        id: nextProc
        command: ["bash", "-c", "@HOME@/.local/bin/calendar-agenda next 60"]
        stdout: StdioCollector { onStreamFinished: root.ingestNext(this.text) }
    }
    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: nextProc.running = true
    }

    // ── calls ─────────────────────────────────────────────────────
    // None of these apps announces a call. Telegram, Slack and Discord expose
    // nothing usable on D-Bus, and their notifications cover the ring rather
    // than the call, so the island reads the one thing that is unambiguously
    // true for the whole of one: the app is holding the microphone.
    //
    // In PipeWire terms that is a capture stream. Measured on 0.3.1 against a
    // live pw-record, since the naming does not say it: a playback stream is
    // isStream with isSink true, a capture stream is isStream with isSink
    // false.
    //
    // The app allowlist is load-bearing, not decoration. cava — the island's
    // own wave visualiser — holds two permanent capture streams of its own, so
    // "something is recording" would read as a call that never ends.
    readonly property var callApps: [
        { id: "telegram", name: "Telegram", re: /telegram/i,
          glyph: "\u{f2c6}" },
        { id: "slack", name: "Slack", re: /slack/i,
          glyph: "\u{f04b1}" },
        { id: "discord", name: "Discord", re: /discord|vesktop|webcord|armcord/i,
          glyph: "\u{f066f}" }
    ]

    // Matched across every identity the stream carries rather than
    // application.name alone: an Electron app names its audio client
    // inconsistently between versions, and node.name is sometimes the only
    // field that says which app it is.
    function callAppFor(node) {
        if (!node) return null;
        const p = node.properties || {};
        const hay = [p["application.name"], p["application.process.binary"],
                     p["media.name"], node.name].join(" ");
        for (let i = 0; i < root.callApps.length; i++)
            if (root.callApps[i].re.test(hay)) return root.callApps[i];
        return null;
    }

    // Bound as a whole rather than filtered first: properties and mute state
    // are only live on a tracked object, and the set of audio streams on this
    // machine is small enough that tracking all of them costs nothing.
    readonly property var audioStreams: {
        const out = [];
        const ns = Pipewire.nodes ? Pipewire.nodes.values : [];
        for (let i = 0; i < ns.length; i++)
            if (ns[i].audio && ns[i].isStream) out.push(ns[i]);
        return out;
    }
    PwObjectTracker { objects: root.audioStreams }

    // ── privacy indicators ────────────────────────────────────────
    // Something is recording the mic: any capture stream except the island's
    // own cava instances, which hold two permanently for the wave canvas.
    readonly property bool micInUse: {
        for (let i = 0; i < root.audioStreams.length; i++) {
            const n = root.audioStreams[i];
            if (n.isSink) continue;
            const p = n.properties || {};
            const hay = [p["application.name"], p["application.process.binary"], n.name].join(" ");
            if (/cava/i.test(hay)) continue;
            return true;
        }
        return false;
    }
    // Something is taking video: a screencast or a camera feed both show up
    // as a video stream node, which exists only while an app consumes it.
    // Device and portal sources are not streams, so an idle webcam or the
    // portal's own source never count. Tracked for the same reason the audio
    // streams are: a node's type is only known once it is bound.
    readonly property var videoNodes: {
        const out = [];
        const ns = Pipewire.nodes ? Pipewire.nodes.values : [];
        for (let i = 0; i < ns.length; i++)
            if (!ns[i].audio) out.push(ns[i]);
        return out;
    }
    PwObjectTracker { objects: root.videoNodes }
    readonly property bool videoInUse: {
        if (root.camStreaming) return true;
        for (let i = 0; i < root.videoNodes.length; i++) {
            const n = root.videoNodes[i];
            if (n.isStream && (n.type & PwNodeType.Video)) return true;
        }
        return false;
    }
    // Most camera users never touch PipeWire: Discord and the browsers open
    // /dev/video* themselves, so the graph above only catches screencasts.
    // The kernel says it plainly instead — a UVC webcam's video-streaming
    // interface (class 0e, subclass 02) sits at alternate setting 0 while
    // idle and switches to a bandwidth setting only while frames flow. That
    // is "the camera is on", not "some app holds the device open", which
    // Discord does all day. Plain sysfs reads, so the poll costs nothing.
    property bool camStreaming: false
    Process {
        id: camProc
        command: ["bash", "-c", "for i in /sys/bus/usb/devices/*:*; do "
            + "[ \"$(cat $i/bInterfaceClass 2>/dev/null)\" = 0e ] && "
            + "[ \"$(cat $i/bInterfaceSubClass 2>/dev/null)\" = 02 ] && "
            + "cat $i/bAlternateSetting; done"]
        stdout: StdioCollector {
            onStreamFinished: root.camStreaming = this.text.split(/\s+/).some(v => v !== "" && v !== "0")
        }
    }
    Timer {
        interval: 2000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: camProc.running = true
    }

    readonly property var callStreams: {
        const out = [];
        for (let i = 0; i < root.audioStreams.length; i++) {
            const n = root.audioStreams[i];
            if (n.isSink) continue;
            if (root.callAppFor(n)) out.push(n);
        }
        return out;
    }
    function callAppById(id) {
        for (let i = 0; i < root.callApps.length; i++)
            if (root.callApps[i].id === id) return root.callApps[i];
        return null;
    }

    // ── discord rpc ───────────────────────────────────────────────
    // Discord's desktop client listens on a local socket, and it is the only
    // way to reach its *real* self-mute and self-deafen from outside. The
    // capture-stream mute below is a device mute: the far end hears silence
    // while Discord still shows you unmuted to everyone in the channel.
    //
    // scripts/discord-rpc.py holds one authenticated connection and speaks
    // JSON lines both ways — state out on stdout, commands in on stdin. One
    // process rather than one per click: AUTHENTICATE costs a round trip and
    // Discord rate-limits reconnections, so a button that reconnected on every
    // press would feel slow and eventually be refused.
    //
    // All of this degrades to nothing. With no application configured the
    // bridge reports authed false forever, every branch below falls back to
    // the PipeWire path, and the island behaves exactly as it did before.
    property bool dcConnected: false
    property bool dcAuthed: false
    property bool dcMute: false
    property bool dcDeaf: false
    property string dcChannel: ""
    property int dcUsers: 0
    property string dcReason: ""

    Process {
        id: dcProc
        running: true
        command: ["python3", "@HOME@/.config/quickshell/scripts/discord-rpc.py", "serve"]
        stdinEnabled: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => root.ingestDiscord(line)
        }
    }

    function ingestDiscord(line) {
        const s = (line || "").trim();
        if (s === "" || s.charAt(0) !== "{") return;
        try {
            const j = JSON.parse(s);
            root.dcConnected = !!j.connected;
            root.dcAuthed = !!j.authed;
            root.dcReason = j.reason || "";
            if (!root.dcAuthed) {
                root.dcChannel = "";
                root.dcUsers = 0;
                return;
            }
            root.dcMute = !!j.mute;
            root.dcDeaf = !!j.deaf;
            root.dcChannel = j.channel || "";
            root.dcUsers = j.users || 0;
        } catch (e) { /* keep the last good state */ }
        root.syncCall();
    }

    function dcSend(cmd, value) {
        if (!root.dcAuthed) return;
        dcProc.write(JSON.stringify({ cmd: cmd, value: value }) + "\n");
    }

    // Being in a voice channel is the call, whether or not the mic is open —
    // which is strictly better than the stream heuristic, since it still holds
    // while you are deafened or on push-to-talk.
    readonly property bool dcInVoice: root.dcAuthed && root.dcChannel !== ""

    readonly property var callNode: root.callStreams.length > 0 ? root.callStreams[0] : null
    readonly property var callStreamApp: root.callAppFor(root.callNode)
    readonly property var callApp:
        root.callStreamApp ? root.callStreamApp
      : (root.dcInVoice ? root.callAppById("discord") : null)
    readonly property bool inCall: root.callApp !== null
    // Whether this particular call can be controlled for real.
    readonly property bool callRpc:
        root.inCall && root.callApp.id === "discord" && root.dcAuthed
    // Discord's own self-mute when the bridge is up, and the stream mute
    // otherwise. They are not the same fact and the card says which one you
    // are looking at: a device mute sends silence, a self-mute is a state
    // everyone else in the channel can see.
    readonly property bool callMuted:
        root.callRpc ? root.dcMute
      : (root.callNode && root.callNode.audio ? root.callNode.audio.muted : false)
    // Deafen has no device-level equivalent worth offering — muting your own
    // output is a local mute that tells the channel nothing — so it exists
    // only where it is real.
    readonly property bool callDeafened: root.callRpc && root.dcDeaf

    // Anchored to wall-clock like the timer's deadline and for the same
    // reason: a counter incremented per tick loses whatever the shell slept
    // through, and a call is exactly when the machine might suspend.
    //
    // Persisted for the timer's other reason too. The shell hot-reloads on
    // every config save, which rebuilds this singleton and would restart a
    // running call at 0:00 — visibly wrong while you are still on it. A reboot
    // is not worth surviving: nothing is still on the line afterwards.
    PersistentProperties {
        id: callAnchor
        reloadableId: "islandCall"
        property real since: 0
        property string appId: ""
        property string dismissed: ""
    }
    property alias dismissedCall: callAnchor.dismissed
    readonly property int callSecs: root.inCall && callAnchor.since > 0
        ? Math.max(0, Math.floor((clk.date.getTime() - callAnchor.since) / 1000))
        : 0

    // Re-anchored only when this is genuinely a different call. Keying on the
    // app rather than on inCall alone is what makes the reload survivable: the
    // streams resolve a moment after the rebuild, so inCall always arrives as
    // a fresh false-to-true even when the call never stopped.
    function markCall() {
        if (root.inCall) {
            if (callAnchor.appId !== root.callApp.id || callAnchor.since <= 0) {
                callAnchor.since = Date.now();
                callAnchor.appId = root.callApp.id;
                // A new call is a new decision: dismissing the last one must
                // not silently hide this one as well.
                callAnchor.dismissed = "";
            }
        } else {
            callAnchor.since = 0;
            callAnchor.appId = "";
        }
        root.syncCall();
    }
    onInCallChanged: root.markCall()

    // markCall only fires on a *change*, which leaves one hole: a reload with
    // no call in progress restores the persisted anchor, inCall is false from
    // construction so it never changes, and the next call inherits the old
    // start time. Observed as a fresh call opening at 3:16.
    //
    // Checked once, late enough that a reload *during* a call has had time to
    // re-resolve its streams — PwObjectTracker binds them well inside a second,
    // so 2.5s clears the stale case without ever clearing a live one.
    Timer {
        interval: 2500
        running: true
        repeat: false
        onTriggered: {
            if (root.inCall) return;
            callAnchor.since = 0;
            callAnchor.appId = "";
        }
    }

    function syncCall() {
        if (!root.inCall || root.dismissedCall === root.callApp.id) {
            root.retract("call");
            return;
        }
        root.publish("call", {
            slot: "lead",
            priority: 60,
            // The phone's compact call is a filled glyph badge at one end and a
            // running timer at the other — no prose. `style` asks the island for
            // that layout instead of the generic dot-and-two-lines; anything
            // else published to lead is unaffected.
            style: "call",
            badge: root.callDeafened ? "\u{f07ce}"
                 : (root.callMuted ? "\u{f036d}" : root.callApp.glyph),
            value: root.timerFmt(root.callSecs),
            // The channel is what you actually want named once the bridge can
            // tell us — "Discord" you already knew, "General · 4" you did not.
            title: root.dcInVoice && root.callApp.id === "discord" && root.dcChannel !== ""
                 ? root.dcChannel + (root.dcUsers > 1 ? "  ·  " + root.dcUsers : "")
                 : root.callApp.name,
            muted: root.callMuted,
            // The theme's primary while live, its error red while muted: a
            // muted mic is the one state that has to read the same whichever
            // app you are talking through.
            tone: (root.callMuted || root.callDeafened) ? "warn" : "primary",
            progress: -1,
            dismiss: function () {
                root.dismissedCall = root.callApp ? root.callApp.id : "";
                root.retract("call");
            },
            // Tapping the island opens the call, the way the phone does. The
            // window itself is one button away inside.
            action: function () { root.toggleTool("call", root.toolScreen); }
        });
    }
    onCallSecsChanged: root.syncCall()
    onCallMutedChanged: root.syncCall()

    // Still no hang-up, and still for the same reason: nothing in Discord's
    // nineteen RPC commands ends a call, and neither Telegram nor Slack
    // exposes anything at all. Screen share is absent from that command set
    // too — see scripts/discord-rpc.py.
    //
    // Both report which layer they reached, because the keybinds need to know
    // whether to fall back. "none" means the island had no call to act on and
    // the caller should do whatever it did before the island existed — that is
    // what keeps Alt+' a working mic key outside Discord, which is most of the
    // time.
    function toggleCallMute() {
        if (root.callRpc) { root.dcSend("mute", "toggle"); return "discord"; }
        if (root.callNode && root.callNode.audio) {
            root.callNode.audio.muted = !root.callNode.audio.muted;
            return "stream";
        }
        return "none";
    }
    // Deafen has no honest fallback here: muting your own output is a local
    // silence the channel cannot see. Outside a Discord call this defers to the
    // caller, which does the device-level version and says so.
    function toggleCallDeafen() {
        if (!root.callRpc) return "none";
        root.dcSend("deaf", "toggle");
        return "discord";
    }

    // ── the Discord keys ──────────────────────────────────────────
    // Deliberately NOT gated on being in a call, unlike the card's buttons.
    // Discord's self-mute is a global setting, not a per-call one: it applies
    // the moment you set it and holds for the next channel you join, so
    // arming it before joining is a real thing people do. Gating these on
    // call detection made a Discord key that only sometimes reached Discord.
    //
    // The split from toggleCallMute is the point. These two surfaces want
    // different targets during a Telegram call: the card's Mute must silence
    // *that* call, while Alt+apostrophe is a key labelled Discord and should
    // keep meaning Discord. One shared function could not be both.
    function discordMute() {
        if (!root.dcAuthed) return "none";
        root.dcSend("mute", "toggle");
        return "discord";
    }
    function discordDeafen() {
        if (!root.dcAuthed) return "none";
        root.dcSend("deaf", "toggle");
        return "discord";
    }

    // The same two-step NotifActions uses: the stream carries the owning pid,
    // which is exact, and the app's own name is the fallback for anything that
    // opens its audio from a helper process.
    function focusCall() {
        if (!root.callNode || !root.callApp) return;
        const props = root.callNode.properties || {};
        const pid = parseInt(props["application.process.id"]);
        const tops = Hyprland.toplevels.values;
        if (pid > 0) {
            for (let i = 0; i < tops.length; i++) {
                const o = tops[i].lastIpcObject;
                if (o && parseInt(o.pid) === pid) {
                    Hyprland.dispatch('hl.dsp.focus({ window = "address:0x' + tops[i].address + '" })');
                    return;
                }
            }
        }
        for (let i = 0; i < tops.length; i++) {
            const o = tops[i].lastIpcObject;
            if (!o) continue;
            if (root.callApp.re.test((o["class"] || "") + " " + (o.initialClass || ""))) {
                Hyprland.dispatch('hl.dsp.focus({ window = "address:0x' + tops[i].address + '" })');
                return;
            }
        }
    }

    // ── game mode ─────────────────────────────────────────────────
    // Moved here from ShellRoot so the control centre can show and cycle it;
    // the bar pill and the notification mute read it from here now.
    //
    // `gameRunning` is what gamedetect.sh sees and `gameOverride` is the pill's
    // mode: null follows detection, true/false force it. The override sticks
    // until cycled rather than being cleared when detection flips — the modes
    // are named and visible, so "off" has to mean off, the same way a chosen
    // power profile is not silently reset. "auto" is how you ask for
    // detection back.
    //
    // The override is saved rather than held in memory: "off" has to still be
    // off after a reboot, or the mode is not a setting at all — it is a thing
    // that quietly re-arms itself whenever the machine restarts. `auto` is the
    // only state that follows detection, so it is the only one a restart may
    // recompute.
    property bool gameRunning: false
    property string gameName: ""
    readonly property string gameModeName: prefs.gameMode === "on" ? "on"
                                         : prefs.gameMode === "off" ? "off" : "auto"
    readonly property var gameOverride: root.gameModeName === "auto" ? null
                                      : root.gameModeName === "on"
    readonly property bool gameMode: gameOverride !== null ? gameOverride : gameRunning

    // The single writer. Everything that sets game mode goes through a name,
    // which is also what lands in the file.
    function setGameMode(name) {
        prefs.gameMode = (name === "on" || name === "off") ? name : "auto";
    }
    function cycleGameMode() {
        if (root.gameModeName === "auto") root.setGameMode("on");
        else if (root.gameModeName === "on") root.setGameMode("off");
        else root.setGameMode("auto");
    }

    // Resource priority follows game mode. The knob is app.slice's CPUWeight:
    // Steam and everything Hyprland spawns live in session.slice, so weighting
    // app.slice down puts Chrome, Docker Desktop and the Toolbox IDEs behind the
    // game under contention. It is set --runtime, so a reboot or a crashed shell
    // cannot leave the machine permanently deprioritized, and normalising on
    // startup covers a shell that died while a game was running.
    // gamePid is the game itself, not Steam's reaper wrapper — gamedetect.sh
    // walks the reaper's descendants and reports the heaviest one, which is what
    // gamemode has to renice for it to mean anything.
    property int gamePid: 0

    Process { id: prioProc }
    function applyPriority(on) {
        prioProc.command = on
            ? ["bash", "@HOME@/.config/quickshell/scripts/gameprio.sh", "on", String(root.gamePid)]
            : ["bash", "@HOME@/.config/quickshell/scripts/gameprio.sh", "off"];
        prioProc.running = true;
    }
    onGameModeChanged: root.applyPriority(root.gameMode)

    function ingestGame(raw) {
        const s = (raw || "").trim();
        if (s === "" || s.charAt(0) !== "{") return;
        try {
            const j = JSON.parse(s);
            root.gameName = j.active && j.name ? j.name : "";
            root.gamePid = j.active && j.pid ? j.pid : 0;
            root.gameRunning = !!j.active;
        } catch (e) { /* keep last state */ }
    }

    Process {
        id: gameProc
        command: ["bash", "-c", "@HOME@/.config/quickshell/scripts/gamedetect.sh"]
        stdout: StdioCollector { onStreamFinished: root.ingestGame(this.text) }
    }
    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: gameProc.running = true
    }

    IpcHandler {
        target: "gamemode"
        function cycle(): void { root.cycleGameMode(); }
        function enable(): void { root.setGameMode("on"); }
        function disable(): void { root.setGameMode("off"); }
        // "auto" hands control back to game detection.
        function follow(): void { root.setGameMode("auto"); }
        function toggle(): void { root.setGameMode(root.gameMode ? "off" : "on"); }
        function status(): string {
            return root.gameModeName
                 + (root.gameMode ? " · engaged" : " · idle")
                 + (root.gameName !== "" ? " · " + root.gameName : "");
        }
    }

    // ── notifications ─────────────────────────────────────────────
    // The whole module lives in the island: this server replaced the ShellRoot
    // one, an incoming notification flashes the pill's main slot (below), and
    // history is the notifs tool. Machine-wide by the singleton rule — one
    // decision about muting, one flash, however many monitors render it.
    NotificationServer {
        id: srv
        // History is only useful if it survives a config hot-reload.
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: true
        actionsSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: (n) => {
            n.tracked = true;
            // The server destroys a notification the sending app closes itself
            // (Telegram does this on every read chat). Drop it while it is still
            // alive — a stale entry makes the Repeater regenerate over a freed
            // pointer and segfault the whole shell.
            //
            // This is also why the flash must unwind when the notification
            // closes underneath it, whoever closed it.
            n.closed.connect(function() {
                root.notifStampSet(n.id, 0);
                if (root.notifShown === n) root.notifDismissFlash();
            });

            // keepOnReload does not just keep the notifications — it re-emits
            // every one of them through this handler on each config save. They
            // are not new, and treating them as new is what made the island
            // replay the whole backlog of flashes after every edit, and what
            // reset each arrival time to the moment of the reload.
            //
            // lastGeneration is the marker for a carried-over notification and
            // is constant, so it stays true however many reloads it survives.
            if (n.lastGeneration) return;

            root.notifStampSet(n.id, Date.now());
            root.flashNotif(n);
        }
    }

    readonly property var notifs:
        srv.trackedNotifications ? srv.trackedNotifications.values : []
    readonly property int notifCount: root.notifs.length
    // When the list last ran empty, for the hub's "nothing new since" line.
    // Starts at shell start: anything older was dealt with before this run.
    property date quietSince: new Date()
    onNotifCountChanged: if (root.notifCount === 0) root.quietSince = new Date()

    // ── when a notification arrived ───────────────────────────────
    // The freedesktop spec has no timestamp field and Quickshell exposes none,
    // so arrival time is recorded here, keyed by the server's id, and pruned
    // when the notification closes.
    //
    // Persistent for the same reason the server is keepOnReload: history
    // outlives a config save, and an age that snapped back to "just now" on
    // every file write would be actively misleading. It is deliberately not
    // persisted any further than that — the notifications themselves do not
    // survive the shell exiting, so neither should their clocks.
    //
    // Held as JSON rather than as a live object: a `var` holding a JS object is
    // mutated in place, and an in-place mutation is invisible to the reload
    // snapshot — the map came back empty on every config save, which is exactly
    // the bug this is meant to prevent. A string round-trips.
    PersistentProperties {
        id: notifTimes
        reloadableId: "islandNotifTimes"
        property string at: "{}"
        // When the notifications were last looked at — the bell or the hub,
        // which carries the notifications widget. Anything stamped after it
        // is unread. Persistent so a config save does not re-flag them.
        property real seenAt: 0
    }
    readonly property int unreadCount: {
        let c = 0;
        for (let i = 0; i < root.notifs.length; i++)
            if (root.notifStamp(root.notifs[i]) > notifTimes.seenAt) c++;
        return c;
    }
    function markNotifsSeen() { notifTimes.seenAt = Date.now(); }
    onToolChanged: if (root.tool === "notifs" || root.tool === "hub") root.markNotifsSeen()

    // Parsed once per write rather than once per read: every visible row
    // re-evaluates its age label on every clock tick.
    readonly property var notifStamps: {
        try { return JSON.parse(notifTimes.at) || {}; } catch (e) { return {}; }
    }
    function notifStampSet(id, ms) {
        const m = Object.assign({}, root.notifStamps);
        if (ms > 0) m[id] = ms; else delete m[id];
        notifTimes.at = JSON.stringify(m);
    }

    function notifStamp(n) {
        if (!n) return 0;
        const t = root.notifStamps[n.id];
        return t ? t : 0;
    }

    // Under two hours the useful answer is how long ("18m ago"); past that the
    // question stops being "how long" and becomes "when", so it switches to a
    // wall-clock stamp with the date on it.
    readonly property int notifAbsoluteAfter: 2 * 3600

    function notifAge(n) {
        const t = root.notifStamp(n);
        if (!t) return "";
        // Read off the shared clock rather than Date.now() so the label is a
        // live binding — every row re-renders on the same tick everything else
        // in the island does.
        const secs = Math.max(0, Math.floor((clk.date.getTime() - t) / 1000));
        if (secs >= root.notifAbsoluteAfter)
            return Qt.formatDateTime(new Date(t), "d MMM, hh:mm AP");
        if (secs < 60) return "just now";
        if (secs < 3600) return Math.floor(secs / 60) + "m ago";
        const m = Math.floor((secs % 3600) / 60);
        return "1h" + (m > 0 ? " " + m + "m" : "") + " ago";
    }

    function notifsClear() {
        const all = root.notifs.slice();
        for (let i = 0; i < all.length; i++)
            if (all[i] && all[i].tracked) all[i].dismiss();
    }

    // The notification the pill's main slot is currently flashing. One at a
    // time, newest wins — the island is a ticker, not a stack; anything that
    // scrolled past is waiting in the history tool.
    property var notifShown: null

    // Apps whose flashes survive game mode. Matched against appName, lowercased.
    // "calendar" is the -a passed by the meeting notify-send: those are
    // time-critical without being urgency 2, and a missed meeting is exactly
    // what game mode must not cost. Silent mode is stricter
    // still: it drops every flash, critical included.
    readonly property var gameModeAllowedApps: ["calendar"]

    // The same appName the meeting notify-send passes, so a reminder about an
    // event is recognisable as calendar text.
    function calendarApp(n) {
        return (n.appName || "").toLowerCase() === "calendar";
    }

    function allowedInGameMode(n) {
        const app = (n.appName || "").toLowerCase();
        return root.gameModeAllowedApps.indexOf(app) !== -1;
    }

    // Takes the main slot the way the track flash does, but outranks it — a
    // message beats "now playing". Suppression only skips the flash: the
    // notification stays tracked, so everything muted here is still waiting in
    // the history tool afterwards.
    function flashNotif(n) {
        // Silent means silent, critical included; the history still collects
        // everything.
        if (root.dnd) return;
        if (n.urgency !== 2 && root.gameMode && !root.allowedInGameMode(n)) return;
        root.notifShown = n;
        // The island renders plain text; notification bodies may carry markup.
        const body = (n.body || "").replace(/<[^>]*>/g, "").replace(/\s+/g, " ").trim();
        root.publish("notif", {
            slot: "main",
            priority: 80,
            title: n.summary !== "" ? n.summary : n.appName,
            sub: body !== "" ? body : n.appName,
            // A calendar notification is calendar text, so it carries the
            // event's own colour rather than the pill's default — the same
            // tint the meeting segment uses. Everything else falls through to
            // the default tone, which is now the surface's text colour.
            tint: root.calendarApp(n) && root.meeting ? root.meeting.color : "",
            tone: n.urgency === 2 ? "warn" : "accent",
            image: n.image !== "" ? n.image
                 : Quickshell.iconPath(n.appIcon, "dialog-information"),
            progress: -1,
            action: function () { root.notifActivate(n); }
        });
        // Critical holds the slot longer instead of forever — the clock is not
        // hostage material; the unread badge and history carry it from there.
        notifHold.interval = n.urgency === 2 ? 10000
                           : (n.expireTimeout > 0 ? n.expireTimeout : 5000);
        notifHold.restart();
    }

    // Ends the flash only. The notification itself is left alone — the flash is
    // a view of a notification, not its lifetime. expire()/dismiss() both
    // destroy and untrack, so calling either here is why the history tool
    // would otherwise be permanently empty.
    function notifDismissFlash() {
        root.notifShown = null;
        root.retract("notif");
    }

    // Spec: activating means the default action plus raising the app; the
    // notification is done at that point unless it declared itself resident.
    function notifActivate(n) {
        const a = NotifActions.defaultAction(n);
        if (a) a.invoke();
        NotifActions.focusApp(n);
        if (!n.resident) NotifActions.discard(n);
        root.notifDismissFlash();
    }

    Timer {
        id: notifHold
        onTriggered: {
            const n = root.notifShown;
            root.notifDismissFlash();
            // transient asks not to be persisted, so those genuinely go away.
            if (n && n.transient) NotifActions.discard(n);
        }
    }

    // The Super+Shift+N binding and anything else scripted against the old
    // notification centre keep working — the panel is just an island tool now.
    IpcHandler {
        target: "notifications"
        function toggle(): void { root.toggleTool("notifs", root.activeScreen()); }
        function open(): void { root.openTool("notifs", root.activeScreen()); }
        function close(): void { if (root.tool === "notifs") root.closeCard(); }
        function clear(): void { root.notifsClear(); }
        // Silent mode. Bound to Super+Home; the flash is not decoration —
        // with the bar's right side gone there is nothing showing DND state,
        // so an unannounced toggle leaves you guessing whether it took.
        function dnd(): void { root.toggleDnd(); }
        function dndon(): void { if (!root.dnd) root.toggleDnd(); }
        function dndoff(): void { if (root.dnd) root.toggleDnd(); }
    }

    function toggleDnd() {
        root.dnd = !root.dnd;
        root.publish("dnd", {
            slot: "main",
            priority: 75,
            title: root.dnd ? "Silent" : "Alerts on",
            sub: root.dnd ? "notifications muted" : "notifications resumed",
            glyph: root.dnd ? "\u{f009b}" : "\u{f009a}",
            tone: root.dnd ? "accent2" : "accent",
            progress: -1
        });
        dndHold.restart();
    }
    Timer { id: dndHold; interval: 1600; onTriggered: root.retract("dnd") }

    // ── idle behaviour ────────────────────────────────────────────
    // hypridle's 60-minute listener calls idle-mode.sh, which reads the mode
    // and acts; switching mode is a file write, so nothing has to restart.
    property string idleMode: "sleep"

    function ingestIdle(raw) {
        try {
            const j = JSON.parse((raw || "").trim());
            if (j.mode) root.idleMode = j.mode;
        } catch (e) { /* keep the last good reading */ }
    }

    Process {
        id: idleGet
        command: ["bash", "@HOME@/.config/hypr/scripts/idle-mode.sh", "get"]
        stdout: StdioCollector { onStreamFinished: root.ingestIdle(this.text) }
    }
    Process {
        id: idleSet
        stdout: StdioCollector { onStreamFinished: root.ingestIdle(this.text) }
    }

    function refreshIdleMode() { idleGet.running = true; }
    function setIdleMode(mode) {
        idleSet.command = ["bash", "@HOME@/.config/hypr/scripts/idle-mode.sh", "set", mode];
        idleSet.running = true;
    }
    function cycleIdleMode() {
        idleSet.command = ["bash", "@HOME@/.config/hypr/scripts/idle-mode.sh", "cycle"];
        idleSet.running = true;
    }

    // ── keyboard layout ───────────────────────────────────────────
    // Event-driven, not polled: Hyprland pushes `activelayout` the instant the
    // layout changes. This used to live in KbLayoutPill with a socat listener
    // per monitor; it is here now so one listener serves both the pill and the
    // control centre, over the native rawEvent hook instead of socat.
    property string layoutName: ""

    // Two-letter code, the way the bar pill showed it.
    readonly property string layoutCode: root.layoutName.substring(0, 2).toUpperCase()

    // Hyprland sends one `activelayout` per keyboard, and keyboards can sit on
    // different layouts (a device that joined late, a virtual one), so the
    // last event to arrive is not necessarily the layout being typed in. The
    // events only say "something changed"; the burst is coalesced and the
    // layout most keyboards agree on is read back.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activelayout") layoutSettle.restart();
        }
    }
    Timer {
        id: layoutSettle
        interval: 60
        onTriggered: { kbRead.flash = true; kbRead.running = true; }
    }
    Process {
        id: kbRead
        property bool flash: false
        command: ["bash", "@HOME@/.config/quickshell/scripts/kb-layout.sh", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text.trim();
                if (t === "") return;
                const changed = t !== root.layoutName;
                root.layoutName = t;
                if (kbRead.flash && changed) root.flashLayout();
                kbRead.flash = false;
            }
        }
    }

    // The bar pill's real job was not switching layouts — the control centre
    // does that — it was telling you which layout you are typing in. Folding it
    // into the island would have lost that entirely, so the switch announces
    // itself instead: the moment you change layout, the pill says so.
    //
    // Fired from the activelayout event rather than from layoutName changing,
    // because the startup seed also sets that property and would flash on login.
    // Priority sits above the track flash — this is a direct answer to
    // something you just pressed — but below a notification.
    function flashLayout() {
        if (root.layoutName === "") return;
        root.publish("layout", {
            slot: "main",
            priority: 75,
            title: root.layoutCode,
            sub: root.layoutName,
            glyph: "\u{f030c}",
            tone: "accent",
            progress: -1,
            action: function () { root.switchLayout(); }
        });
        layoutHold.restart();
    }
    Timer { id: layoutHold; interval: 1400; onTriggered: root.retract("layout") }

    // Events only report changes, so the current layout has to be seeded once
    // at startup or it stays blank until the user first switches.
    // Process silently ignores a start issued during component completion, so
    // both the layout seed and the startup priority normalisation are deferred
    // to the next event-loop turn.
    Component.onCompleted: Qt.callLater(function () {
        root.syncSilentAudio();
        btIdsProc.running = true;
        kbRead.running = true;
        idleGet.running = true;
        // Follows the restored mode rather than forcing it off: a saved
        // "on" must survive the shell starting, and everything else still
        // normalises, which is what covers a shell that died mid-game.
        root.applyPriority(root.gameMode);
        root.timerTick();
        root.syncTimer();
        root.refreshPinnedNote();
    })

    // Not Hyprland.dispatch: switchxkblayout is a hyprctl *command*, not a
    // dispatcher, and dispatching it answers "Invalid dispatcher" — which
    // Quickshell logs as a warning and nothing surfaces, so the layout tile and
    // the old bar pill had both been silently doing nothing. The name is still
    // in the compositor binary, which is what makes the failure so quiet.
    Process {
        id: kbSwitch
        command: ["bash", "@HOME@/.config/quickshell/scripts/kb-layout.sh", "next"]
    }
    function switchLayout() {
        kbSwitch.running = true;
    }

    // ── network profile ───────────────────────────────────────────
    // The name comes from network-profile.sh rather than the Networking
    // module, and deliberately: DeviceType only models None/Wifi/Wired, so the
    // native API cannot see a VPN at all. The script already resolves the
    // NetworkManager *profile* name with an active VPN taking precedence over
    // the ethernet underneath it, which is the thing worth reading. Same
    // source as the bar module, so the two can never disagree.
    property string netName: "—"
    property string netKind: ""
    property string netVia: ""

    function ingestNetwork(raw) {
        try {
            const j = JSON.parse((raw || "").trim());
            const lines = (j.tooltip || "").split("\n");
            const first = lines[0] || "";
            root.netKind = j.class || "";
            if (root.netKind === "vpn") {
                root.netName = first.replace(/^VPN:\s*/, "");
                root.netVia = (lines[1] || "").replace(/^via\s*/, "").trim();
            } else if (root.netKind === "disconnected") {
                root.netName = "Disconnected";
                root.netVia = "";
            } else {
                root.netName = first;
                root.netVia = "";
            }
        } catch (e) { /* keep the last good reading */ }
    }

    Process {
        id: netProc
        command: ["bash", "@HOME@/.config/quickshell/scripts/network-profile.sh", "once"]
        stdout: StdioCollector { onStreamFinished: root.ingestNetwork(this.text) }
    }
    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: netProc.running = true
    }

    // The bar module's own click actions, so the tile and the pill behave the
    // same way: cycle the VPN profiles, or drop into nmtui.
    Process { id: netAction }
    function cycleNetwork() {
        netAction.command = ["setsid", "-f",
                             "@HOME@/.config/quickshell/scripts/network-cycle.sh"];
        netAction.running = true;
    }
    function openNmtui() {
        netAction.command = ["setsid", "-f", "ghostty", "-e", "nmtui"];
        netAction.running = true;
    }

    // ── system alerts ─────────────────────────────────────────────
    // The bottom-bar pills already classify these and go invisible when
    // healthy, but a full disk deserves more than a tinted 26px pill. The same
    // scripts feed the lead segment when they are unhappy. Priority sits below
    // the meeting on purpose: a disk warning can wait a few minutes, a meeting
    // starting cannot.
    property var alerts: ({})

    function ingestAlert(key, raw) {
        let text = "", cls = "";
        try {
            const j = JSON.parse((raw || "").trim());
            text = (j.text || "").trim();
            cls = j.class || "";
        } catch (e) { return; }

        const next = {};
        for (const k in root.alerts) next[k] = root.alerts[k];
        if (text === "" || cls === "ok") delete next[key];
        else next[key] = { text: text, cls: cls };
        root.alerts = next;
        root.syncAlerts();
    }

    // How an alert key reads in the segment, and how it breaks a tie. Ranking
    // is explicit because `for (const k in ...)` walks insertion order, which
    // is whichever poll happened to land first — so two warnings of the same
    // severity used to show whichever one the scheduler picked that minute.
    readonly property var alertRank: ({ mounts: 0, disk: 1, units: 2 })
    readonly property var alertLabel: ({
        mounts: "drives",
        disk:   "disk space",
        units:  "failed services"
    })

    function syncAlerts() {
        const keys = Object.keys(root.alerts);
        if (keys.length === 0) { root.retract("alert"); return; }

        keys.sort(function (a, b) {
            const ca = root.alerts[a].cls.indexOf("crit") !== -1 ? 0 : 1;
            const cb = root.alerts[b].cls.indexOf("crit") !== -1 ? 0 : 1;
            if (ca !== cb) return ca - cb;
            return (root.alertRank[a] !== undefined ? root.alertRank[a] : 99)
                 - (root.alertRank[b] !== undefined ? root.alertRank[b] : 99);
        });

        const worstKey = keys[0];
        const worst = root.alerts[worstKey];
        // Only one alert fits the segment, but a second one going unmentioned
        // is how a filling disk hides behind a failed unit. The count says
        // there is more waiting; the monitoring panel is where it is.
        const label = root.alertLabel[worstKey] || worstKey;
        const rest = keys.length - 1;

        root.publish("alert", {
            slot: "lead",
            priority: 30,
            title: worst.text,
            sub: rest > 0 ? label + "  ·  +" + rest + " more" : label,
            tone: "warn",
            progress: -1,
            // A warning you can act on: the click goes to the monitoring
            // panel, where the failing units or the filling disk are spelled out.
            action: function () { root.openTool("monitor", root.activeScreen()); }
        });
    }

    // ── screen recording ──────────────────────────────────────────
    // OBS is the recorder — it already holds this machine's scenes, encoder and
    // output path, and nothing else should be writing video. State lives here
    // rather than in CaptureTool so the trailing capsule can keep showing that
    // a recording is running long after the card has been closed.
    property bool obsRunning: false
    property bool obsRecording: false
    property string obsTimecode: ""
    // OBS is up but refused the websocket, which only an OBS restart can fix.
    // Distinct from "not running" so the button does not claim OBS is closed
    // while its window is on screen.
    property bool obsNeedsRestart: false

    function ingestObs(raw) {
        try {
            const j = JSON.parse((raw || "").trim());
            root.obsRunning = !!j.running;
            root.obsRecording = !!j.recording;
            root.obsNeedsRestart = !!j.needsrestart;
            root.obsTimecode = j.timecode || "";
            root.syncRecording();
        } catch (e) { /* keep the last good reading */ }
    }

    Process {
        id: obsStat
        command: ["bash", "@HOME@/.config/quickshell/scripts/obs.sh", "status"]
        stdout: StdioCollector { onStreamFinished: root.ingestObs(this.text) }
    }
    Process {
        id: obsAct
        stdout: StdioCollector { onStreamFinished: root.ingestObs(this.text) }
    }
    function obsToggle() {
        obsAct.command = ["bash", "@HOME@/.config/quickshell/scripts/obs.sh", "toggle"];
        obsAct.running = true;
    }
    function obsOpen() {
        obsAct.command = ["bash", "@HOME@/.config/quickshell/scripts/obs.sh", "open"];
        obsAct.running = true;
    }

    // Every second while recording, to keep the timecode honest; every five
    // otherwise, which costs one pgrep because obs.sh short-circuits before
    // python when OBS is closed. Recording started from OBS's own window is
    // picked up the same way.
    Timer {
        interval: root.obsRecording ? 1000 : 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: obsStat.running = true
    }

    function syncRecording() {
        if (!root.obsRecording) { root.retract("recording"); return; }
        root.publish("recording", {
            slot: "trail",
            priority: 60,
            title: root.obsTimecode !== "" ? root.obsTimecode : "REC",
            glyph: "\u{f0319}",
            tone: "warn",
            progress: -1,
            action: function () { root.toggleTool("capture", root.toolScreen); }
        });
    }

    // ── pinned note ───────────────────────────────────────────────
    // A note can claim the lead segment. Priority 10 puts it below everything
    // that reports a condition — a meeting, a disk filling up — so pinning a
    // note can never hide one; it fills the segment the rest of the time.
    // Read once at startup and after every change the tool makes, rather than
    // polled: a file only this machine writes does not need watching.
    Process {
        id: pinProc
        command: ["bash", "@HOME@/.config/quickshell/scripts/notes.sh", "pinned"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(this.text.trim());
                    if (!j.pinned) { root.retract("note"); return; }
                    root.publish("note", {
                        slot: "lead",
                        priority: 10,
                        title: j.title,
                        sub: j.sub !== "" ? j.sub : "pinned note",
                        tone: "accent",
                        progress: -1,
                        action: function () {
                            root.toggleTool("notes", root.activeScreen());
                        }
                    });
                } catch (e) { /* keep whatever is up */ }
            }
        }
    }
    function refreshPinnedNote() { pinProc.running = true; }

    // ── system tray ───────────────────────────────────────────────
    // The tray list is held here rather than only inside TrayTool because the
    // SNI service starts with its first QML consumer, and a tool is a Loader
    // page — so until the tray tool was opened by hand there was no
    // StatusNotifierWatcher on the bus at all. Apps decide once, at their own
    // startup, whether a tray exists: GTK and Qt ones re-register when a
    // watcher finally appears, Electron ones (slack, discord, keeper, docker
    // desktop) ask once and never retry, so they spent the whole session with
    // no icon and the tray looked like it was dropping them. Owning the
    // reference here brings the watcher up with the shell, before
    // workspace-apps.sh spawns anything that wants an icon.
    readonly property var trayItems: SystemTray.items ? SystemTray.items.values : []

    // A right-click on the top-bar tray opens the tray tool on that item. The
    // menu is drawn inside the card rather than as a popup of its own — see
    // TrayTool for why a second focus grab is not an option.
    property string traySelect: ""
    function openTrayItem(id, screen, direct) {
        root.traySelect = id;
        if (direct) root.openDirect("tray", screen);
        else root.openTool("tray", screen);
    }

    // ── device batteries: AirPods and phone ───────────────────────
    // One reading for the island's circles and the menu bar's items, so the
    // two never disagree and the files are watched once, not per monitor.
    //
    // AirPods: the MAC is the same one sinkOrder keys on, the name the
    // fallback for a re-pair. AirStatus (airstatus.service) rewrites one JSON
    // object with each bud's charge from the BLE advertisement — the AirPods
    // never report through BlueZ's Battery1. A side not in the ear reads -1, so
    // the level is the lower of the buds that are present, the one that dies
    // first; an advertisement older than five minutes belongs to a previous
    // session.
    readonly property var airpodsDev: {
        const ds = Bluetooth.devices ? Bluetooth.devices.values : [];
        for (let i = 0; i < ds.length; i++) {
            const d = ds[i];
            if (/airpods/i.test(d.name)) return d;
        }
        return null;
    }
    readonly property bool airpodsConnected: root.airpodsDev !== null && root.airpodsDev.connected
    property var airData: null
    property real devNow: Date.now()
    FileView {
        id: airFile
        path: "/tmp/airstatus.out"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.airData = JSON.parse(text()); } catch (e) { root.airData = null; } }
    }
    readonly property bool airFresh: {
        const a = root.airData;
        if (!a || a.status !== 1 || !a.date) return false;
        const t = new Date(a.date.replace(" ", "T")).getTime();
        return !isNaN(t) && root.devNow - t < 300000;
    }
    readonly property real airpodsPct: {
        if (!root.airFresh) return -1;
        const l = root.airData.charge.left, r = root.airData.charge.right;
        if (l < 0 && r < 0) return -1;
        if (l < 0) return r / 100;
        if (r < 0) return l / 100;
        return Math.min(l, r) / 100;
    }
    readonly property bool airpodsCharging:
        root.airFresh && (root.airData.charging_left === true || root.airData.charging_right === true)

    // Phone: the Bluetooth battery UPower publishes for a paired phone. An
    // iPhone reports only 20 % steps and no charging flag over Bluetooth, so
    // the last event from iphone-charge-listener (an iOS Shortcuts webhook on
    // charger connect and disconnect) overrides both while it is under ten
    // minutes old, and its charging state for as long as it stands.
    readonly property var phoneDev: {
        const list = UPower.devices.values;
        for (let i = 0; i < list.length; i++)
            if (list[i].type === UPowerDeviceType.Phone) return list[i];
        return null;
    }
    readonly property bool phoneConnected: root.phoneDev !== null && root.phoneDev.percentage > 0
    // Apple's Bluetooth vendor id: an iPhone is drawn, anything else is the
    // generic phone glyph.
    readonly property string phoneKind: {
        const m = root.phoneDev ? (root.phoneDev.nativePath || "").match(/([0-9a-f]{2}[:_]){5}[0-9a-f]{2}/i) : null;
        const id = m ? root.btId(m[0].replace(/_/g, ":")) : null;
        return id && id.vid === "004C" ? "iphone" : "phone";
    }
    property var phoneCharge: null
    FileView {
        id: phoneChargeFile
        path: "/tmp/iphone-charge.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.phoneCharge = JSON.parse(text()); } catch (e) { root.phoneCharge = null; } }
    }
    readonly property bool phoneCharging:
        (root.phoneDev !== null && root.phoneDev.state === UPowerDeviceState.Charging)
        || (root.phoneCharge !== null && root.phoneCharge.state === "charging")
    readonly property real phonePct: {
        const c = root.phoneCharge;
        if (c && c.pct !== undefined && c.ts && root.devNow / 1000 - c.ts < 600) return c.pct / 100;
        return root.phoneDev ? root.phoneDev.percentage : -1;
    }

    // What each paired device says it is: the vendor and product from its
    // Bluetooth Device ID record (BlueZ's Modalias), keyed by MAC. That is the
    // device's own report, so it is what the icons key on — a DualSense is
    // 054C:0CE6 whatever it is named. Re-read when a device pairs or links.
    property var btIds: ({})
    readonly property string btIdsKey: {
        const ds = Bluetooth.devices ? Bluetooth.devices.values : [];
        return ds.map(d => d.address + (d.connected ? "+" : "")).join(",");
    }
    onBtIdsKeyChanged: btIdsProc.running = true
    Process {
        id: btIdsProc
        command: ["bash", "-c", "bluetoothctl devices | while read -r _ mac _; do m=$(bluetoothctl info \"$mac\" | sed -n 's/.*Modalias: //p'); echo \"$mac $m\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = {};
                for (const line of this.text.split("\n")) {
                    const m = line.match(/^(\S+)\s+\S*v([0-9A-Fa-f]{4})p([0-9A-Fa-f]{4})/);
                    if (m) out[m[1].toUpperCase()] = { vid: m[2].toUpperCase(), pid: m[3].toUpperCase() };
                }
                root.btIds = out;
            }
        }
    }
    function btId(mac) { return root.btIds[(mac || "").toUpperCase()] || null; }
    function btName(mac) {
        const ds = Bluetooth.devices ? Bluetooth.devices.values : [];
        for (let i = 0; i < ds.length; i++)
            if (mac && ds[i].address.toUpperCase() === mac.toUpperCase()) return ds[i].name;
        return "";
    }
    // The DeviceGlyph kind and body colour for a Bluetooth device, for the
    // Wireless panel's radar: the AirPods by address, then what the device
    // reports — its Device ID for phones and pads, BlueZ's icon class for the
    // rest. "" kind keeps the radar's own glyph (a fridge, a beacon).
    function btLook(d) {
        if (!d) return { kind: "", tint: "" };
        if (root.airpodsDev !== null && d.address === root.airpodsDev.address)
            return { kind: "airpods", tint: "" };
        const icon = (d.icon || "").toLowerCase();
        const id = root.btId(d.address);
        if (icon.indexOf("phone") >= 0 && icon.indexOf("headphone") < 0)
            return { kind: id && id.vid === "004C" ? "iphone" : "phone", tint: "" };
        if (icon.indexOf("gaming") >= 0 || icon.indexOf("joystick") >= 0)
            return { kind: root.controllerKind(d.deviceName || "", id),
                     tint: root.controllerColor(d.name) };
        if (icon.indexOf("mouse") >= 0) return { kind: "mouse", tint: "" };
        if (icon.indexOf("keyboard") >= 0) return { kind: "keyboard", tint: "" };
        if (icon.indexOf("headset") >= 0 || icon.indexOf("headphone") >= 0 || icon.indexOf("audio") >= 0)
            return { kind: "headphones", tint: "" };
        return { kind: "", tint: "" };
    }

    // The DeviceGlyph kind and body colour for a devicebat.sh row, so the
    // Batteries panel draws what the circles and the bar draw. "" kind means
    // the set has no drawing for it and the row keeps its script glyph.
    function deviceLook(row) {
        if (row.kind === "airpods") return { kind: "airpods", tint: "" };
        if (row.kind === "phone") {
            const id = root.btId(row.mac);
            return { kind: id && id.vid === "004C" ? "iphone" : "phone", tint: "" };
        }
        if (row.kind === "controller")
            return { kind: root.controllerKind(row.name, root.btId(row.mac)),
                     tint: root.controllerColor(root.btName(row.mac)) };
        if (row.kind === "mouse" || row.kind === "keyboard" || row.kind === "audio")
            return { kind: row.kind, tint: "" };
        return { kind: "", tint: "" };
    }

    // Controllers: every gaming-input battery UPower publishes (hid-playstation,
    // xpadneo, hid-nintendo all expose one). The pad's Device ID tells the
    // model apart, the HID name the kernel reports is the fallback. The colour
    // comes from the Bluetooth name: no controller reports its shell colour
    // (a pink and a white DualSense send identical IDs and names), so a pad
    // named "Pink controller" is drawn pink.
    // Very dark bodies are lifted so they still read on the dark surface.
    function controllerKind(model, id) {
        if (id) {
            if (id.vid === "054C") {
                if (id.pid === "0CE6" || id.pid === "0DF2") return "dualsense";
                if (id.pid === "05C4" || id.pid === "09CC" || id.pid === "0BA0") return "dualshock";
            }
            if (id.vid === "045E") return "xbox";
            if (id.vid === "057E") return "switch";
        }
        const m = (model || "").toLowerCase();
        if (m.indexOf("dualsense") >= 0) return "dualsense";
        if (m.indexOf("xbox") >= 0) return "xbox";
        if (m.indexOf("pro controller") >= 0 || m.indexOf("joy-con") >= 0) return "switch";
        if (m === "wireless controller" || m.indexOf("dualshock") >= 0) return "dualshock";
        return "gamepad";
    }
    readonly property var controllerColors: [
        ["pink", "#f2a2c4"], ["white", "#f2f2f0"], ["black", "#5b5d66"],
        ["midnight", "#5b5d66"], ["red", "#d8394a"], ["blue", "#5b8fe0"],
        ["purple", "#9a7fd1"], ["violet", "#9a7fd1"], ["grey", "#a7abb3"],
        ["gray", "#a7abb3"], ["silver", "#c8ccd2"], ["green", "#5fb37a"],
        ["camo", "#7d8a6a"], ["yellow", "#f0cf5a"], ["orange", "#f09a4a"]
    ]
    function controllerColor(name) {
        const n = (name || "").toLowerCase();
        for (const c of root.controllerColors) if (n.indexOf(c[0]) >= 0) return c[1];
        return "";
    }
    readonly property var controllers: {
        const out = [];
        const list = UPower.devices.values;
        const bts = Bluetooth.devices ? Bluetooth.devices.values : [];
        for (let i = 0; i < list.length; i++) {
            const d = list[i];
            if (d.type !== UPowerDeviceType.GamingInput || !(d.percentage > 0)) continue;
            const m = (d.nativePath || "").match(/([0-9a-f]{2}[:_]){5}[0-9a-f]{2}/i);
            const mac = m ? m[0].replace(/_/g, ":").toUpperCase() : "";
            let name = d.model || "Controller";
            for (let j = 0; j < bts.length; j++)
                if (mac !== "" && bts[j].address.toUpperCase() === mac) { name = bts[j].name; break; }
            out.push({
                key: d.nativePath || String(i),
                kind: root.controllerKind(d.model, root.btId(mac)),
                name: name,
                tint: root.controllerColor(name),
                pct: d.percentage,
                charging: d.state === UPowerDeviceState.Charging
            });
        }
        return out;
    }

    // A backstop for a rewrite the watchers miss, and the clock the freshness
    // checks run on. Idle while neither device is linked.
    Timer {
        interval: 30000
        running: root.airpodsConnected || root.phoneConnected
        repeat: true
        triggeredOnStart: true
        onTriggered: { root.devNow = Date.now(); airFile.reload(); phoneChargeFile.reload(); }
    }

    // The ring and item colour every battery shares: charging green, unknown
    // muted, then the warning ladder from Settings → Devices.
    function batteryColor(pct, charging, theme) {
        const warnAt = root.cfg.statusWarnPct / 100;
        if (charging) return theme.success;
        if (pct < 0) return theme.muted;
        if (pct <= warnAt) return theme.warn;
        if (pct <= warnAt * 2) return theme.accent2;
        return theme.accent;
    }

    // ── tool cache ────────────────────────────────────────────────
    // A tool is a Loader page, so closing the card destroys it along with
    // everything it had read. Every reopen therefore started from nothing and
    // painted an empty panel until its first poll returned — a second or two
    // for the monitor tiles, several for the update count, which reads as the
    // panel being broken rather than busy.
    //
    // The last reading is kept out here, outside the Loader's lifetime: a
    // reopen paints it immediately and the poll that follows simply replaces
    // it. Mutated in place on purpose — this is a store, not a source of
    // bindings, and reassigning it would re-render every tool on every poll.
    readonly property var toolCache: ({})
    function cacheGet(key, fallback) {
        const v = root.toolCache[key];
        return v === undefined ? fallback : v;
    }
    function cacheSet(key, value) { root.toolCache[key] = value; }

    // ── capture ───────────────────────────────────────────────────
    // Owned here rather than by CaptureTool because every one of these closes
    // the card first: slurp and hyprpicker each take a screen-wide grab that
    // fights the card's own focus grab, and an output shot would otherwise
    // photograph the card that asked for it. Closing the card destroys the
    // tool, and with it any Process the tool owned — so the process that has
    // to outlive the close lives in the singleton.
    Process { id: captureProc }
    function capture(verb, arg) {
        root.closeCard();
        captureProc.command = arg === undefined
            ? ["bash", "@HOME@/.config/quickshell/scripts/capture.sh", verb]
            : ["bash", "@HOME@/.config/quickshell/scripts/capture.sh", verb, arg];
        captureProc.running = true;
    }

    Process {
        id: diskAlert
        command: ["bash", "@HOME@/.config/quickshell/scripts/diskspace.sh"]
        stdout: StdioCollector { onStreamFinished: root.ingestAlert("disk", this.text) }
    }
    Process {
        id: unitAlert
        command: ["bash", "@HOME@/.config/quickshell/scripts/failed-units.sh"]
        stdout: StdioCollector { onStreamFinished: root.ingestAlert("units", this.text) }
    }
    // A games drive mounted with the wrong driver is silent until a Windows
    // game exits a second after launch with no error anywhere. Checking it here
    // means the island says so first — the whole point of putting it beside the
    // disk and unit alerts rather than only in the monitoring panel.
    Process {
        id: mountAlert
        command: ["bash", "@HOME@/.config/quickshell/scripts/mounts.sh"]
        stdout: StdioCollector { onStreamFinished: root.ingestAlert("mounts", this.text) }
    }
    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            diskAlert.running = true;
            unitAlert.running = true;
            mountAlert.running = true;
        }
    }

    // ── timer ─────────────────────────────────────────────────────
    // The first tool that is genuinely stateful, and the reason the trailing
    // slot exists: it has to keep counting while the main slot goes back to
    // the clock and the card closes.
    //
    // The countdown is anchored to a wall-clock deadline rather than counted
    // down a tick at a time, and the anchor is persisted. A ticking counter
    // loses whatever it slept through — a suspend, or the shell's own
    // hot-reload on every file save, which used to wipe a running timer
    // outright. Reading the deadline back means neither costs a second.
    PersistentProperties {
        id: tmr
        reloadableId: "islandTimer"
        property int total: 0
        property int left: 0
        property bool running: false
        property real deadline: 0
        // What the picker wheels were last dialled to. Persisted for the same
        // reason the deadline is: the tool is unloaded whenever you switch
        // tools, so without this every visit would start back at zero and the
        // wheels would be a worse preset row.
        property int pick: 300
    }
    property alias timerTotal: tmr.total
    property alias timerLeft: tmr.left
    property alias timerRunning: tmr.running
    property alias timerPick: tmr.pick
    readonly property real timerProgress:
        timerTotal > 0 ? (timerTotal - timerLeft) / timerTotal : 0
    // Armed and run out, as opposed to armed and paused at zero, which cannot
    // happen. Everything that has to look or sound urgent reads this.
    readonly property bool timerDone: timerTotal > 0 && timerLeft <= 0

    // ── the alarm ─────────────────────────────────────────────────
    // A timer that finishes silently is a timer you find out about ten minutes
    // later, so a finished one rings as well as notifying.
    //
    // Nothing repeats the sound, because it does not need repeating:
    // freedesktop's alarm-clock-elapsed is six seconds of a ringing clock, not
    // a single chime. An earlier version looped it on a 1.6s Timer and got two
    // rings six seconds apart — Process.running is already true for the whole
    // playback, so every re-assignment inside that window was a no-op. One
    // play is the alarm.
    //
    // The alarm is deliberately not gated on dnd. Silent mode is about what
    // other programs may interrupt you with; this countdown is one you asked
    // for by hand. The notification is sent critical for the same reason.
    //
    // Bound rather than tracked in a bool of its own: the sound playing *is*
    // the alarm state, and two copies of that fact would drift the moment a
    // player failed to start.
    readonly property bool timerAlarming: alarmProc.running

    Process {
        id: alarmProc
        command: ["bash", "@HOME@/.config/quickshell/scripts/alarm.sh",
                  "alarm-clock-elapsed"]
    }
    function timerAlarmStart() {
        if (alarmProc.running) return;
        alarmProc.running = true;
    }
    // running = false is a SIGTERM, which is why alarm.sh traps it and kills
    // the player rather than exec-ing it: acknowledging the timer has to cut
    // the ring off mid-sound, not orphan six seconds of it.
    function timerAlarmStop() { alarmProc.running = false; }

    function timerFmt(sec) {
        const s = Math.max(0, Math.floor(sec));
        const h = Math.floor(s / 3600);
        const m = Math.floor((s % 3600) / 60);
        const ss = s % 60;
        return (h > 0 ? h + ":" + ("0" + m).slice(-2) : "" + m)
             + ":" + ("0" + ss).slice(-2);
    }
    readonly property string timerText: root.timerFmt(root.timerLeft)

    function timerStart(seconds) {
        if (seconds <= 0) return;
        root.timerAlarmStop();
        tmr.pick = seconds;
        tmr.total = seconds;
        tmr.left = seconds;
        tmr.deadline = Date.now() + seconds * 1000;
        tmr.running = true;
    }
    function timerToggle() {
        root.timerAlarmStop();
        if (tmr.left <= 0) return;
        // Resuming re-anchors the deadline to what is left, so a pause is not
        // silently counted as elapsed time.
        if (!tmr.running) tmr.deadline = Date.now() + tmr.left * 1000;
        tmr.running = !tmr.running;
    }
    function timerReset() {
        root.timerAlarmStop();
        tmr.running = false;
        tmr.left = 0;
        tmr.total = 0;
        tmr.deadline = 0;
    }

    function timerTick() {
        if (!tmr.running) return;
        const left = Math.max(0, Math.round((tmr.deadline - Date.now()) / 1000));
        if (left === tmr.left) return;
        tmr.left = left;
        if (left > 0) return;
        tmr.running = false;
        root.timerAlarmStart();
        notifier.command = ["notify-send", "-a", "timer", "-u", "critical",
                            "-i", "alarm-symbolic",
                            "Timer finished",
                            root.timerFmt(tmr.total) + " elapsed"];
        notifier.running = true;
    }

    // Twice a second: the display is whole seconds, and sampling faster than
    // the value changes is what keeps the digits from visibly stalling when a
    // tick lands just after the second rolls over.
    Timer {
        interval: 500
        repeat: true
        running: root.timerRunning && root.timerLeft > 0
        triggeredOnStart: true
        onTriggered: root.timerTick()
    }

    function syncTimer() {
        if (root.timerTotal <= 0) { root.retract("timer"); return; }
        root.publish("timer", {
            slot: "trail",
            priority: 50,
            title: root.timerText,
            // A finished timer stops being a countdown and becomes an alarm,
            // and says so: bell glyph, warn tone, and `alert`, which is the
            // generic "this segment wants looking at" flag any producer can
            // set — the island renders the pulse, not the timer.
            glyph: root.timerDone ? "\u{f0020}" : "\u{f051b}",
            tone: root.timerDone ? "warn"
                : (root.timerRunning ? "accent2" : "muted"),
            alert: root.timerDone,
            progress: root.timerProgress,
            action: function () {
                root.timerAlarmStop();
                root.toggleTool("timer", root.toolScreen);
            },
            // The right-click action. Optional like `action` is, so a capsule
            // published by a script keeps the plain one-button behaviour and
            // only something with a sensible destructive verb — clearing a
            // timer — grows a second one.
            secondary: function () { root.timerReset(); }
        });
    }
    onTimerLeftChanged: root.syncTimer()
    onTimerRunningChanged: root.syncTimer()
    onTimerTotalChanged: root.syncTimer()

}
