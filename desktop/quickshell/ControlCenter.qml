import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

// The hub — the card's home surface and the island's entry point. Everything
// lives on one grid of controls, after the reference control centre this is
// modelled on: live widgets (media, sliders, toggles, notifications) beside
// launcher tiles that drill into the full panels, every one of them placed by
// the user. The layout is {id, x, y, w, h} cells in island-prefs.json; empty
// means the compiled-in default below.
//
// The same component IS the editor: the settings window instantiates it with
// edit: true, where widgets stop acting and start moving — drag to a cell,
// size chips for the selected control, add-chips for whatever is unplaced.
// One layout engine, so the editor can never disagree with the real thing.
Item {
    id: root

    property var theme
    property bool edit: false

    // ── grid metrics ──────────────────────────────────────────────
    readonly property int columns: IslandState.cfg.ccColumns
    readonly property real gap: 10
    // Even the editor keeps a sliver of margin: the selection ring draws 3px
    // outside a face, and a ring clipped by the host's edge reads as broken.
    readonly property real margin: root.edit ? 8 : 18
    readonly property real cell:
        (width - margin * 2 - gap * (columns - 1)) / columns
    readonly property real pitch: cell + gap

    readonly property int rows: {
        let r = 0;
        for (let i = 0; i < root.placed.length; i++)
            r = Math.max(r, root.placed[i].y + root.placed[i].h);
        return r;
    }
    // The editor keeps two spare rows of dotted cells under the layout, so
    // there is always somewhere to drag a control down to.
    readonly property int canvasRows: root.edit ? root.rows + 2 : root.rows

    readonly property real gridHeight:
        canvasRows > 0 ? canvasRows * pitch - gap : 0
    readonly property real preferredHeight:
        margin * 2 + gridHeight
        + (callBanner.visible ? callBanner.height + gap : 0)
    implicitHeight: preferredHeight

    // ── the controls this machine offers ──────────────────────────
    // sizes is the SUGGESTED footprints (the editor's chips); any cell size
    // within minW/minH and the grid is legal — the corner grip is free-form
    // and every widget lays itself out from whatever box it gets. w/h is the
    // default. Launcher tiles for the drill-in panels are generated from the
    // tool registry, so a new tool becomes placeable without touching this.
    readonly property var defs: {
        const out = [
            { id: "media",    kind: "media",   name: "Media",           glyph: "\u{f075a}",
              minW: 3, minH: 1, sizes: [[3,2],[4,2],[5,2],[6,2],[7,2]], w: 4, h: 2 },
            { id: "sound",    kind: "slider",  name: "Sound",           glyph: "\u{f057e}",
              minW: 1, minH: 1, sizes: [[1,1],[1,2],[3,1],[4,1],[5,1],[6,1],[7,1]], w: 7, h: 1 },
            { id: "mic",      kind: "slider",  name: "Microphone",      glyph: "\u{f036c}",
              minW: 1, minH: 1, sizes: [[1,1],[1,2],[3,1],[4,1],[5,1],[6,1],[7,1]], w: 4, h: 1 },
            { id: "calendar", kind: "cal",     name: "Calendar",        glyph: "\u{f00ed}",
              minW: 1, minH: 1, sizes: [[1,1],[2,1],[2,2],[3,2],[4,2]], w: 2, h: 1 },
            { id: "timer",    kind: "timer",   name: "Timer",           glyph: "\u{f051b}",
              minW: 1, minH: 1, sizes: [[1,1],[2,1],[2,2]], w: 1, h: 1 },
            { id: "notes",    kind: "notes",   name: "Notes",           glyph: "\u{f09a5}",
              minW: 1, minH: 1, sizes: [[1,1],[2,1],[2,2],[3,2]], w: 2, h: 1 },
            { id: "system",   kind: "sys",     name: "System",          glyph: "\u{f04c5}",
              minW: 1, minH: 1, sizes: [[1,1],[2,1],[3,1],[2,2],[3,2]], w: 2, h: 1 },
            { id: "notifs",   kind: "notifs",  name: "Notifications",   glyph: "\u{f009a}",
              minW: 3, minH: 1, sizes: [[4,2],[5,2],[6,2],[7,2],[6,3],[7,3]], w: 7, h: 2 },
            { id: "weather",  kind: "weather", name: "Weather",         glyph: "\u{e30d}",
              minW: 1, minH: 1, sizes: [[1,1],[2,1],[3,1]], w: 2, h: 1 },
            { id: "battery",  kind: "battery", name: "Mouse battery",   glyph: "\u{f037d}",
              minW: 1, minH: 1, sizes: [[1,1],[2,2]], w: 1, h: 1 },
            { id: "network",  kind: "toggle",  name: "Network",         glyph: "\u{f0200}",
              sizes: [[1,1],[2,1]], w: 1, h: 1 },
            { id: "bluetooth", kind: "toggle", name: "Bluetooth",       glyph: "\u{f00af}",
              sizes: [[1,1],[2,1]], w: 1, h: 1 },
            { id: "gamemode", kind: "toggle",  name: "Game mode",       glyph: "\u{f05ba}",
              sizes: [[1,1],[2,1]], w: 1, h: 1 },
            { id: "layout",   kind: "toggle",  name: "Layout",          glyph: "\u{f030c}",
              sizes: [[1,1],[2,1]], w: 1, h: 1 },
            { id: "updates",  kind: "toggle",  name: "Updates",         glyph: "\u{f06b0}",
              sizes: [[1,1],[2,1]], w: 1, h: 1 },
            { id: "profile",  kind: "toggle",  name: "Power profile",   glyph: "\u{f0241}",
              sizes: [[1,1],[2,1]], w: 1, h: 1 },
            { id: "lock",     kind: "toggle",  name: "Lock",            glyph: "\u{f033e}",
              sizes: [[1,1],[2,1]], w: 1, h: 1 },
            { id: "shape",    kind: "toggle",  name: "Island / Notch",  glyph: "\u{f0379}",
              sizes: [[1,1],[2,1]], w: 1, h: 1 }
        ];
        const ts = IslandState.tools;
        // Launcher tiles only for panels nothing else owns: the ones with a
        // live widget (media, weather, calendar, …) or a toggle (bluetooth)
        // would be duplicates in the add-chips. A pruned widget makes its
        // panel add-chip-unreachable — Reset, or the pill and IPC, get it
        // back, and that beats a chip list that stutters every name twice.
        const owned = ["hub", "call", "media", "weather", "battery", "notifs",
                       "calendar", "timer", "notes", "monitor",
                       "bluetooth", "audio"];
        for (let i = 0; i < ts.length; i++) {
            const t = ts[i];
            if (owned.indexOf(t.id) !== -1) continue;
            out.push({ id: "go:" + t.id, kind: "launch", tool: t.id,
                       name: t.name, glyph: t.glyph,
                       minW: 1, minH: 1, sizes: [[1,1]], w: 1, h: 1 });
        }
        return out;
    }
    function defById(id) {
        for (let i = 0; i < root.defs.length; i++)
            if (root.defs[i].id === id) return root.defs[i];
        return null;
    }

    // The layout the hub ships with, saved from the live arrangement on
    // 2026-09-14. Authored for defaultColumns; on any other count sanitize()
    // relocates what no longer fits, so this never needs per-column variants.
    // resetLayout() restores the column count with it so the reset lands on
    // exactly this picture.
    readonly property int defaultColumns: 8
    function defaultLayout() {
        return [
            { id: "bluetooth",    x: 0, y: 0, w: 2, h: 1 },
            { id: "media",        x: 2, y: 0, w: 4, h: 2 },
            { id: "layout",       x: 6, y: 0, w: 1, h: 1 },
            { id: "go:power",     x: 7, y: 0, w: 1, h: 1 },
            { id: "network",      x: 0, y: 1, w: 2, h: 1 },
            { id: "battery",      x: 6, y: 1, w: 2, h: 1 },
            { id: "notifs",       x: 0, y: 2, w: 4, h: 2 },
            { id: "profile",      x: 4, y: 2, w: 2, h: 1 },
            { id: "mic",          x: 6, y: 2, w: 1, h: 2 },
            { id: "sound",        x: 7, y: 2, w: 1, h: 2 },
            { id: "gamemode",     x: 4, y: 3, w: 2, h: 1 },
            { id: "calendar",     x: 0, y: 4, w: 4, h: 3 },
            { id: "notes",        x: 4, y: 4, w: 2, h: 1 },
            { id: "updates",      x: 6, y: 4, w: 2, h: 1 },
            { id: "system",       x: 4, y: 5, w: 2, h: 1 },
            { id: "timer",        x: 4, y: 6, w: 2, h: 1 },
            { id: "go:display",   x: 6, y: 6, w: 2, h: 1 },
            { id: "weather",      x: 0, y: 7, w: 4, h: 1 },
            { id: "go:clipboard", x: 4, y: 7, w: 1, h: 1 },
            { id: "go:tray",      x: 5, y: 7, w: 1, h: 1 },
            { id: "go:capture",   x: 6, y: 7, w: 1, h: 1 },
            { id: "go:keys",      x: 7, y: 7, w: 1, h: 1 }
        ];
    }

    // ── layout engine ─────────────────────────────────────────────
    // Everything the grid renders passes through here: unknown ids dropped,
    // duplicates dropped, sizes clamped to what the control accepts and the
    // column count allows, and anything overlapping or out of bounds moved to
    // the first free slot. The saved file can therefore never draw a broken
    // grid, whatever wrote it.
    function sanitize(raw, cols) {
        const occ = {};
        function fits(x, y, w, h) {
            if (x < 0 || y < 0 || x + w > cols) return false;
            for (let i = 0; i < w; i++)
                for (let j = 0; j < h; j++)
                    if (occ[(x + i) + "," + (y + j)]) return false;
            return true;
        }
        function mark(x, y, w, h) {
            for (let i = 0; i < w; i++)
                for (let j = 0; j < h; j++)
                    occ[(x + i) + "," + (y + j)] = true;
        }
        function firstFree(w, h) {
            for (let y = 0; y < 60; y++)
                for (let x = 0; x <= cols - w; x++)
                    if (fits(x, y, w, h)) return { x: x, y: y };
            return null;
        }
        function clampSize(def, w, h) {
            // Free-form: the sizes list is suggestions for the chips, not
            // law. Anything between the control's minimum and the grid is a
            // legal footprint.
            let W = Math.round(Number(w)), H = Math.round(Number(h));
            if (!Number.isFinite(W)) W = def.w;
            if (!Number.isFinite(H)) H = def.h;
            const minW = def.minW || 1, minH = def.minH || 1;
            if (minW > cols) return null;
            W = Math.max(minW, Math.min(cols, W));
            H = Math.max(minH, Math.min(12, H));
            return [W, H];
        }
        const seen = {};
        const out = [];
        for (let i = 0; i < raw.length; i++) {
            const r = raw[i];
            const def = root.defById(r.id);
            if (!def || seen[r.id]) continue;
            seen[r.id] = true;
            const s = clampSize(def, r.w || def.w, r.h || def.h);
            if (!s) continue;
            let x = Math.round(Number(r.x) || 0), y = Math.round(Number(r.y) || 0);
            // A hand-edited file is a designed workflow (the FileView watches
            // it), so a typo must relocate, not render: NaN passes every
            // comparison in fits(), and a huge y would instantiate thousands
            // of editor dot cells. 60 rows is firstFree's own window.
            if (!Number.isFinite(x) || !Number.isFinite(y)
                || y < 0 || y >= 60 || !fits(x, y, s[0], s[1])) {
                const f = firstFree(s[0], s[1]);
                if (!f) continue;
                x = f.x; y = f.y;
            }
            mark(x, y, s[0], s[1]);
            out.push({ id: r.id, x: x, y: y, w: s[0], h: s[1], def: def });
        }
        return out;
    }

    readonly property var placed: {
        const raw = (IslandState.cfg.ccLayout && IslandState.cfg.ccLayout.length > 0)
                    ? IslandState.cfg.ccLayout : root.defaultLayout();
        return root.sanitize(raw, root.columns);
    }

    function commit(arr) {
        IslandState.setCcLayout(arr.map(i => ({ id: i.id, x: i.x, y: i.y, w: i.w, h: i.h })));
    }

    // Would (x,y,w,h) land cleanly, ignoring the control being moved itself?
    function slotFree(skipId, x, y, w, h) {
        if (x < 0 || y < 0 || x + w > root.columns) return false;
        for (let i = 0; i < root.placed.length; i++) {
            const p = root.placed[i];
            if (p.id === skipId) continue;
            if (x < p.x + p.w && p.x < x + w && y < p.y + p.h && p.y < y + h)
                return false;
        }
        return true;
    }

    function rectsOverlap(ax, ay, aw, ah, bx, by, bw, bh) {
        return ax < bx + bw && bx < ax + aw && ay < by + bh && by < ay + ah;
    }
    // Every placed control the region touches, except the one being moved.
    function itemsIn(skipId, x, y, w, h) {
        const out = [];
        for (let i = 0; i < root.placed.length; i++) {
            const p = root.placed[i];
            if (p.id === skipId) continue;
            if (root.rectsOverlap(x, y, w, h, p.x, p.y, p.w, p.h)) out.push(p);
        }
        return out;
    }
    // Dropping onto exactly one neighbour offers a trade: the dragged control
    // takes the drop cell and the neighbour moves to the dragged one's origin.
    // Feasible only when both new homes are in bounds, don't overlap each
    // other, and touch nothing else — otherwise the drop stays invalid and
    // snaps back, never shoving thirds around.
    function swapTarget(it, gx, gy) {
        const hits = root.itemsIn(it.id, gx, gy, it.w, it.h);
        if (hits.length !== 1) return null;
        const b = hits[0];
        if (it.x + b.w > root.columns) return null;
        if (root.rectsOverlap(gx, gy, it.w, it.h, it.x, it.y, b.w, b.h)) return null;
        for (let i = 0; i < root.placed.length; i++) {
            const p = root.placed[i];
            if (p.id === it.id || p.id === b.id) continue;
            if (root.rectsOverlap(gx, gy, it.w, it.h, p.x, p.y, p.w, p.h)) return null;
            if (root.rectsOverlap(it.x, it.y, b.w, b.h, p.x, p.y, p.w, p.h)) return null;
        }
        return b;
    }

    // ── editor state & API ────────────────────────────────────────
    // The settings window draws the chrome (column chips, size chips,
    // add-chips) against these; the grid itself only knows how to select,
    // drag and commit.
    property string selId: ""
    readonly property var selItem: {
        for (let i = 0; i < root.placed.length; i++)
            if (root.placed[i].id === root.selId) return root.placed[i];
        return null;
    }
    readonly property var unplaced: {
        const have = {};
        for (let i = 0; i < root.placed.length; i++) have[root.placed[i].id] = true;
        const out = [];
        for (let i = 0; i < root.defs.length; i++)
            if (!have[root.defs[i].id]) out.push(root.defs[i]);
        return out;
    }

    function addWidget(id) {
        const def = root.defById(id);
        if (!def) return;
        const arr = root.placed.slice();
        arr.push({ id: id, x: 0, y: root.rows, w: Math.min(def.w, root.columns), h: def.h });
        root.commit(arr);
        root.selId = id;
    }
    function removeSel() {
        if (root.selId === "") return;
        // An emptied layout would be byte-identical to resetCcLayout()'s
        // sentinel and resurrect every default widget — so the last control
        // stays, same reasoning as the old rail's last-tool guard.
        if (root.placed.length <= 1) return;
        root.commit(root.placed.filter(p => p.id !== root.selId));
        root.selId = "";
    }
    function setSelSize(w, h) {
        const it = root.selItem;
        if (!it) return;
        let nx = it.x, ny = it.y;
        if (nx + w > root.columns) nx = root.columns - w;
        // When the grown control collides where it sits, IT moves — leaning
        // on sanitize's relocation instead would teleport whichever
        // neighbour happens to come later in the array.
        if (!root.slotFree(it.id, nx, ny, w, h)) {
            let found = null;
            for (let y = 0; y < 60 && !found; y++)
                for (let x = 0; x <= root.columns - w && !found; x++)
                    if (root.slotFree(it.id, x, y, w, h)) found = { x: x, y: y };
            if (!found) return;
            nx = found.x; ny = found.y;
        }
        root.commit(root.placed.map(p => p.id === it.id
            ? { id: p.id, x: nx, y: ny, w: w, h: h } : p));
    }
    // Compact everything toward the top-left, keeping reading order — the
    // reference's "Tidy" button.
    function tidy() {
        const sorted = root.placed.slice().sort((a, b) => a.y - b.y || a.x - b.x);
        const occ = {};
        function fits(x, y, w, h) {
            if (x + w > root.columns) return false;
            for (let i = 0; i < w; i++)
                for (let j = 0; j < h; j++)
                    if (occ[(x + i) + "," + (y + j)]) return false;
            return true;
        }
        const out = [];
        for (let k = 0; k < sorted.length; k++) {
            const p = sorted[k];
            let done = false;
            for (let y = 0; y < 60 && !done; y++)
                for (let x = 0; x <= root.columns - p.w && !done; x++)
                    if (fits(x, y, p.w, p.h)) {
                        for (let i = 0; i < p.w; i++)
                            for (let j = 0; j < p.h; j++)
                                occ[(x + i) + "," + (y + j)] = true;
                        out.push({ id: p.id, x: x, y: y, w: p.w, h: p.h });
                        done = true;
                    }
        }
        root.commit(out);
    }
    function resetLayout() {
        IslandState.setCcColumns(root.defaultColumns);
        IslandState.resetCcLayout();
        root.selId = "";
    }

    // ── shared live data ──────────────────────────────────────────
    readonly property var sinkAudio: Pipewire.defaultAudioSink ? Pipewire.defaultAudioSink.audio : null
    readonly property var srcAudio: Pipewire.defaultAudioSource ? Pipewire.defaultAudioSource.audio : null
    PwObjectTracker {
        objects: {
            const o = [];
            if (Pipewire.defaultAudioSink) o.push(Pipewire.defaultAudioSink);
            if (Pipewire.defaultAudioSource) o.push(Pipewire.defaultAudioSource);
            return o;
        }
    }

    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property string btName: {
        const ds = Bluetooth.devices ? Bluetooth.devices.values : [];
        for (let i = 0; i < ds.length; i++)
            if (ds[i].connected) return ds[i].deviceName || ds[i].name;
        return root.btAdapter && root.btAdapter.enabled ? "no device" : "off";
    }

    // Same probe as the status circle: the one battery this machine has.
    readonly property var batDev: {
        const list = UPower.devices.values;
        let best = null;
        for (let i = 0; i < list.length; i++) {
            const d = list[i];
            if (!d.ready || d.isLaptopBattery || d.percentage <= 0) continue;
            if (d.type === UPowerDeviceType.Mouse) return d;
            if (best === null) best = d;
        }
        return best;
    }

    // Update count, carried over from the old control tool: loads on open,
    // refreshes on a slow tick. The editor instance never polls.
    property int updates: IslandState.cacheGet("control.updates", -1)
    property string updatesTip: IslandState.cacheGet("control.updatesTip", "")
    function reload() { if (!root.edit) updProc.running = true; }
    Process {
        id: updProc
        command: ["bash", "@HOME@/.config/quickshell/scripts/updates.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(this.text.trim());
                    if (j.class === "ok") { root.updates = 0; root.updatesTip = "up to date"; }
                    else {
                        const m = (j.text || "").match(/\d+/);
                        root.updates = m ? parseInt(m[0]) : -1;
                        root.updatesTip = j.tooltip || "";
                    }
                    IslandState.cacheSet("control.updates", root.updates);
                    IslandState.cacheSet("control.updatesTip", root.updatesTip);
                } catch (e) { /* keep the last good reading */ }
            }
        }
    }
    Timer {
        interval: 600000
        // cardOpen, not tool === "hub": the grid stays visible under a
        // stacked panel, so its readings should not freeze there.
        running: !root.edit && IslandState.cardOpen
        repeat: true
        onTriggered: updProc.running = true
    }

    Process { id: runProc }
    function spawn(cmd) {
        runProc.command = ["setsid", "-f"].concat(cmd);
        runProc.running = true;
    }

    // One table drives every small toggle: what it shows and what it does.
    // Read inside bindings, so each tile repaints as its state moves.
    function toggleModel(id) {
        switch (id) {
        case "network": {
            const k = IslandState.netKind;
            return { glyph: k === "vpn" ? "\u{f0582}" : k === "wifi" ? "\u{f05a9}"
                          : k === "disconnected" || k === "" ? "\u{f002a}" : "\u{f0200}",
                     label: k === "vpn" ? "VPN" : k === "wifi" ? "Wi-Fi"
                          : k === "ethernet" ? "Wired" : "Network",
                     sub: IslandState.netName,
                     on: k === "vpn", tint: root.theme.accent };
        }
        case "bluetooth":
            return { glyph: root.btAdapter && root.btAdapter.enabled ? "\u{f00af}" : "\u{f00b2}",
                     label: "Bluetooth", sub: root.btName,
                     on: root.btAdapter !== null && root.btAdapter.enabled,
                     tint: root.theme.accent };
        case "gamemode":
            // One glyph per MODE, not per engaged-state: auto used to borrow
            // whichever gamepad the probe happened to land on, so it was
            // indistinguishable from a forced on or off. The fill of the tile
            // still says whether it is engaged right now.
            return { glyph: IslandState.gameModeName === "auto" ? "\u{f18f2}"
                          : IslandState.gameModeName === "on" ? "\u{f05ba}"
                          : "\u{f05bb}",
                     label: "Game mode",
                     sub: IslandState.gameName !== "" ? IslandState.gameName
                        : IslandState.gameModeName,
                     on: IslandState.gameMode,
                     tint: IslandState.gameModeName === "on" ? root.theme.warn
                         : IslandState.gameModeName === "off" ? root.theme.accent3
                         : root.theme.accent };
        case "layout":
            return { glyph: "\u{f030c}",
                     label: IslandState.layoutCode !== "" ? IslandState.layoutCode : "Layout",
                     sub: IslandState.layoutName, on: false, tint: root.theme.accent3 };
        case "updates":
            return { glyph: "\u{f06b0}", label: "Updates",
                     sub: root.updates < 0 ? "checking\u{2026}"
                        : root.updates === 0 ? "up to date" : root.updates + " pending",
                     on: root.updates > 0, tint: root.theme.accent2 };
        case "profile":
            return { glyph: PowerProfiles.profile === PowerProfile.PowerSaver ? "\u{f06b1}" : "\u{f0241}",
                     label: "Profile",
                     sub: PowerProfiles.profile === PowerProfile.PowerSaver ? "saver"
                        : PowerProfiles.profile === PowerProfile.Performance ? "performance"
                        : "balanced",
                     on: PowerProfiles.profile !== PowerProfile.Balanced,
                     tint: root.theme.accent };
        case "lock":
            return { glyph: "\u{f033e}", label: "Lock", sub: "session",
                     on: false, tint: root.theme.accent3 };
        case "shape":
            return { glyph: "\u{f0379}", label: IslandState.notch ? "Notch" : "Island",
                     sub: "right-click: settings",
                     on: IslandState.notch, tint: root.theme.accent };
        }
        return { glyph: "\u{f0128}", label: id, sub: "", on: false, tint: root.theme.accent };
    }
    function toggleAction(id, right) {
        switch (id) {
        case "network":
            if (right) IslandState.openNmtui(); else IslandState.cycleNetwork();
            return;
        case "bluetooth":
            if (right && root.btAdapter) root.btAdapter.enabled = !root.btAdapter.enabled;
            else IslandState.openTool("bluetooth", IslandState.toolScreen);
            return;
        case "gamemode": IslandState.cycleGameMode(); return;
        case "layout": IslandState.switchLayout(); return;
        case "updates":
            root.spawn(["ghostty", "-e", "bash", "-c",
                        "paru; echo; read -p 'done — press enter'"]);
            IslandState.closeCard();
            return;
        case "profile": {
            const p = PowerProfiles.profile;
            if (p === PowerProfile.PowerSaver) PowerProfiles.profile = PowerProfile.Balanced;
            else if (p === PowerProfile.Balanced && PowerProfiles.hasPerformanceProfile)
                PowerProfiles.profile = PowerProfile.Performance;
            else PowerProfiles.profile = PowerProfile.PowerSaver;
            return;
        }
        case "lock":
            IslandState.closeCard();
            IslandState.requestLock();
            return;
        case "shape":
            if (right) { IslandState.closeCard(); IslandState.openSettings(); }
            else IslandState.toggleMode();
            return;
        }
    }

    // ── call banner ───────────────────────────────────────────────
    // The call panel has no tile: a call is transient, so its entry appears
    // with the call and leaves with it — a live activity above the grid, the
    // phone's own behaviour.
    Rectangle {
        id: callBanner
        visible: !root.edit && IslandState.inCall
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: root.margin
        height: 46
        radius: 14
        color: Qt.alpha(root.theme.accent2, 0.16)
        border.width: 1
        border.color: Qt.alpha(root.theme.accent2, 0.35)

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 13
            anchors.verticalCenter: parent.verticalCenter
            spacing: 9
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "\u{f03f6}"
                color: root.theme.accent2
                font.family: root.theme.fontMono
                font.pixelSize: 15
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                // The same formatter the pill capsule runs this value
                // through, so an hour-long call rolls to h:mm:ss in both.
                text: "On a call · " + IslandState.timerFmt(IslandState.callSecs)
                color: root.theme.fg
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(12)
                font.weight: Font.DemiBold
            }
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Rectangle {
                width: 30; height: 30; radius: 10
                color: IslandState.callMuted ? Qt.alpha(root.theme.warn, 0.25)
                     : (muteHov.hovered ? Qt.alpha(root.theme.fg, 0.12) : "transparent")
                Text {
                    anchors.centerIn: parent
                    text: IslandState.callMuted ? "\u{f036d}" : "\u{f036c}"
                    color: IslandState.callMuted ? root.theme.warn : root.theme.fg
                    font.family: root.theme.fontMono
                    font.pixelSize: 13
                }
                HoverHandler { id: muteHov; cursorShape: Qt.PointingHandCursor }
                MouseArea { anchors.fill: parent; onClicked: IslandState.toggleCallMute() }
            }
            Rectangle {
                width: 54; height: 30; radius: 10
                color: openHov.hovered ? Qt.alpha(root.theme.fg, 0.12) : Qt.alpha(root.theme.fg, 0.06)
                Text {
                    anchors.centerIn: parent
                    text: "open"
                    color: root.theme.fg
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(11)
                    font.weight: Font.DemiBold
                }
                HoverHandler { id: openHov; cursorShape: Qt.PointingHandCursor }
                MouseArea {
                    anchors.fill: parent
                    onClicked: IslandState.openTool("call", IslandState.toolScreen)
                }
            }
        }
    }

    // ── the grid ──────────────────────────────────────────────────
    Item {
        id: gridArea
        anchors.top: callBanner.visible ? callBanner.bottom : parent.top
        anchors.topMargin: callBanner.visible ? root.gap : root.margin
        anchors.left: parent.left
        anchors.leftMargin: root.margin
        anchors.right: parent.right
        anchors.rightMargin: root.margin
        height: root.gridHeight

        // The editor's dotted free cells — drawn under everything, so an
        // occupied cell simply hides its dot behind the control sitting on it.
        Repeater {
            model: root.edit ? root.columns * root.canvasRows : 0
            Rectangle {
                required property int index
                x: (index % root.columns) * root.pitch + root.cell / 2 - 4
                y: Math.floor(index / root.columns) * root.pitch + root.cell / 2 - 4
                width: 8; height: 8; radius: 4
                color: Qt.alpha(root.theme.on_surface_variant, 0.25)
            }
        }

        // Where a drag would land: painted while a control is held, in the
        // reference's manner — calm when the slot is free, error when not.
        property int dropX: 0
        property int dropY: 0
        property int dropW: 1
        property int dropH: 1
        property bool dropOk: false
        property bool dropLive: false
        // True while the corner grip is stretching a control rather than a
        // drag moving one; the same preview serves both.
        property bool resizeLive: false
        // The control being traded with, when the drop is a swap rather than
        // a move into empty cells.
        property string dropSwapId: ""
        Rectangle {
            visible: (gridArea.dropLive || gridArea.resizeLive) && root.selItem !== null
            x: gridArea.dropX * root.pitch
            y: gridArea.dropY * root.pitch
            width: gridArea.dropW * root.pitch - root.gap
            height: gridArea.dropH * root.pitch - root.gap
            radius: 16
            color: Qt.alpha(gridArea.dropOk ? root.theme.primary : root.theme.error, 0.12)
            border.width: 2
            border.color: Qt.alpha(gridArea.dropOk ? root.theme.primary : root.theme.error, 0.55)
        }
        // Where the traded neighbour will land — the dragged control's own
        // origin — so a swap reads as two moves, not a mystery.
        Rectangle {
            visible: gridArea.dropLive && gridArea.dropSwapId !== "" && root.selItem !== null
            x: root.selItem ? root.selItem.x * root.pitch : 0
            y: root.selItem ? root.selItem.y * root.pitch : 0
            readonly property var mate: {
                for (let i = 0; i < root.placed.length; i++)
                    if (root.placed[i].id === gridArea.dropSwapId) return root.placed[i];
                return null;
            }
            width: mate ? mate.w * root.pitch - root.gap : 0
            height: mate ? mate.h * root.pitch - root.gap : 0
            radius: 16
            color: Qt.alpha(root.theme.tertiary, 0.10)
            border.width: 2
            border.color: Qt.alpha(root.theme.tertiary, 0.45)
        }

        Repeater {
            model: root.placed

            Item {
                id: slot
                required property var modelData

                // No Behavior on these: every commit rebuilds the Repeater's
                // delegates (the model is a fresh array), so a position
                // animation would never get to run anyway.
                x: modelData.x * root.pitch
                y: modelData.y * root.pitch
                width: modelData.w * root.pitch - root.gap
                height: modelData.h * root.pitch - root.gap

                Item {
                    id: face
                    // Four line anchors rather than fill: AnchorChanges can
                    // only clear line anchors, so a filled face would stay
                    // pinned to its slot and the drag would never move it.
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    readonly property bool held: faceDrag.drag.active
                    z: held ? 10 : 0
                    scale: held ? 1.03 : 1
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                    states: State {
                        when: face.held
                        ParentChange { target: face; parent: gridArea }
                        AnchorChanges {
                            target: face
                            anchors.top: undefined; anchors.bottom: undefined
                            anchors.left: undefined; anchors.right: undefined
                        }
                    }

                    onXChanged: if (held) face.trackDrop()
                    onYChanged: if (held) face.trackDrop()
                    function trackDrop() {
                        const it = slot.modelData;
                        const gx = Math.max(0, Math.min(root.columns - it.w,
                                        Math.round(face.x / root.pitch)));
                        // Capped at the first row past the grid, so a drop in
                        // the far distance can't persist a y that stretches
                        // the canvas forever.
                        const gy = Math.max(0, Math.min(root.rows,
                                        Math.round(face.y / root.pitch)));
                        gridArea.dropX = gx;
                        gridArea.dropY = gy;
                        gridArea.dropW = it.w;
                        gridArea.dropH = it.h;
                        if (root.slotFree(it.id, gx, gy, it.w, it.h)) {
                            gridArea.dropOk = true;
                            gridArea.dropSwapId = "";
                            return;
                        }
                        const mate = root.swapTarget(it, gx, gy);
                        gridArea.dropOk = mate !== null;
                        gridArea.dropSwapId = mate !== null ? mate.id : "";
                    }

                    // selection ring, editor only
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -3
                        radius: 19
                        visible: root.edit && root.selId === slot.modelData.id
                        color: "transparent"
                        border.width: 2
                        border.color: Qt.alpha(root.theme.primary, 0.75)
                    }

                    Loader {
                        anchors.fill: parent
                        sourceComponent: {
                            switch (slot.modelData.def.kind) {
                            case "media":   return cMedia;
                            case "slider":  return cSlider;
                            case "cal":     return cCal;
                            case "timer":   return cTimer;
                            case "notes":   return cNotes;
                            case "sys":     return cSys;
                            case "notifs":  return cNotifs;
                            case "weather": return cWeather;
                            case "battery": return cBattery;
                            case "launch":  return cLaunch;
                            }
                            return cToggle;
                        }
                        onLoaded: { if (item) item.wi = slot.modelData; }
                    }

                    // The editor's hand: sits over the widget's own input, so
                    // in edit mode a control is a thing you move, not a thing
                    // that acts.
                    // ── corner grip: free-form resize ─────────────
                    // The chips stay as suggestions; this is "whatever I
                    // like" — pull the corner and the control takes any cell
                    // box its minimum allows.
                    Rectangle {
                        id: grip
                        visible: root.edit && root.selId === slot.modelData.id
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 3
                        width: 18; height: 18; radius: 7
                        z: 6
                        color: Qt.alpha(root.theme.primary, gripDrag.pressed ? 0.55 : 0.30)
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: "\u{f045d}"
                            color: root.theme.on_primary
                            font.family: root.theme.fontMono
                            font.pixelSize: 11
                        }

                        MouseArea {
                            id: gripDrag
                            anchors.fill: parent
                            cursorShape: Qt.SizeFDiagCursor
                            preventStealing: true

                            onPressed: {
                                const it = slot.modelData;
                                root.selId = it.id;
                                gridArea.dropX = it.x;
                                gridArea.dropY = it.y;
                                gridArea.dropW = it.w;
                                gridArea.dropH = it.h;
                                gridArea.dropOk = true;
                                gridArea.resizeLive = true;
                            }
                            onPositionChanged: (m) => {
                                if (!pressed) return;
                                const it = slot.modelData;
                                const pt = gripDrag.mapToItem(gridArea, m.x, m.y);
                                // +0.35: releasing just past a cell edge counts
                                // as wanting that cell, so growth doesn't need
                                // pixel-perfect aim.
                                let W = Math.floor((pt.x - it.x * root.pitch) / root.pitch + 0.35) + 1;
                                let H = Math.floor((pt.y - it.y * root.pitch) / root.pitch + 0.35) + 1;
                                W = Math.max(it.def.minW || 1, Math.min(root.columns - it.x, W));
                                H = Math.max(it.def.minH || 1, Math.min(12, H));
                                gridArea.dropW = W;
                                gridArea.dropH = H;
                                gridArea.dropOk = root.slotFree(it.id, it.x, it.y, W, H);
                            }
                            onReleased: {
                                gridArea.resizeLive = false;
                                if (!gridArea.dropOk) return;
                                const wid = slot.modelData.id;
                                const W = gridArea.dropW, H = gridArea.dropH;
                                Qt.callLater(function() {
                                    root.commit(root.placed.map(p => p.id === wid
                                        ? { id: p.id, x: p.x, y: p.y, w: W, h: H } : p));
                                });
                            }
                            onCanceled: gridArea.resizeLive = false
                        }
                    }

                    MouseArea {
                        id: faceDrag
                        anchors.fill: parent
                        enabled: root.edit
                        z: 5
                        cursorShape: face.held ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        drag.target: face
                        drag.threshold: 6
                        preventStealing: true
                        onPressed: {
                            root.selId = slot.modelData.id;
                            gridArea.dropLive = false;
                            gridArea.dropSwapId = "";
                        }
                        onPositionChanged: if (faceDrag.drag.active) gridArea.dropLive = true
                        onReleased: {
                            const wasDrag = gridArea.dropLive;
                            gridArea.dropLive = false;
                            if (!wasDrag || !gridArea.dropOk) return;
                            // Deferred: the commit rebuilds this very delegate,
                            // and tearing down the handler's own MouseArea from
                            // inside the handler is asking for a crash.
                            const wid = slot.modelData.id;
                            const ax = slot.modelData.x, ay = slot.modelData.y;
                            const gx = gridArea.dropX, gy = gridArea.dropY;
                            const swapId = gridArea.dropSwapId;
                            gridArea.dropSwapId = "";
                            Qt.callLater(function() {
                                root.commit(root.placed.map(p => {
                                    if (p.id === wid)
                                        return { id: p.id, x: gx, y: gy, w: p.w, h: p.h };
                                    // the traded neighbour inherits the origin
                                    if (swapId !== "" && p.id === swapId)
                                        return { id: p.id, x: ax, y: ay, w: p.w, h: p.h };
                                    return p;
                                }));
                            });
                        }
                        onCanceled: { gridArea.dropLive = false; gridArea.dropSwapId = "" }
                    }
                }
            }
        }
    }

    // ══ the widgets ═══════════════════════════════════════════════
    // Each takes `wi` (its layout entry, handed over once by the Loader) and
    // reads live state straight from the singletons, so a tile repaints the
    // moment the machine moves under it. Every widget carries two faces — a
    // horizontal one and a vertical one for portrait boxes (h > w) — and
    // grows detail with its footprint instead of stretching the same three
    // words across whatever box it gets.

    component TileBase: Rectangle {
        property var wi: null
        radius: 16
        color: Qt.alpha(root.theme.fg, 0.07)
    }

    function fmtSecs(sec) {
        const s = Math.max(0, Math.floor(sec));
        return Math.floor(s / 60) + ":" + ("0" + (s % 60)).slice(-2);
    }

    // ── small toggle: circle, pill, or big tile ───────────────────
    Component {
        id: cToggle
        Item {
            id: tRoot
            property var wi: null
            readonly property var m: wi ? root.toggleModel(wi.id) : null
            readonly property int aw: wi ? wi.w : 1
            readonly property int ah: wi ? wi.h : 1
            // The pill face is for the one-row wide box; everything else —
            // 1-wide, portrait, or big — centres around the circle.
            readonly property bool pillFace: aw >= 2 && ah === 1
            // On is a filled circle in the control's own tint with the glyph
            // cut out of it in a deep shade of that tint; off is a quiet grey
            // disc. The card behind stays neutral either way, so a row of
            // toggles reads by its circles alone.
            readonly property bool on: m !== null && m.on
            readonly property color onTint: m ? Qt.darker(m.tint, 3.4) : "black"

            // circle face
            Column {
                visible: !tRoot.pillFace
                anchors.centerIn: parent
                spacing: 4

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(Math.min(tRoot.width, tRoot.height) - 22, 64)
                    height: width
                    radius: width / 2
                    color: tRoot.on ? tRoot.m.tint
                         : (tHov.hovered && !root.edit ? Qt.alpha(root.theme.fg, 0.16)
                                                       : Qt.alpha(root.theme.fg, 0.10))
                    Behavior on color { ColorAnimation { duration: 160 } }
                    Text {
                        anchors.centerIn: parent
                        text: tRoot.m ? tRoot.m.glyph : ""
                        color: tRoot.on ? tRoot.onTint : Qt.alpha(root.theme.fg, 0.85)
                        Behavior on color { ColorAnimation { duration: 160 } }
                        font.family: root.theme.fontMono
                        font.pixelSize: 17
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: tRoot.width - 6
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                    text: tRoot.m ? tRoot.m.label : ""
                    color: Qt.alpha(root.theme.fg, 0.85)
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(9)
                    font.weight: Font.Medium
                }
                // The second row's worth of air carries the state line the
                // 1x1 has no room for.
                Text {
                    visible: tRoot.ah >= 2 && tRoot.m !== null && tRoot.m.sub !== ""
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: tRoot.width - 6
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                    text: tRoot.m ? tRoot.m.sub : ""
                    color: Qt.alpha(root.theme.on_surface_variant, 0.65)
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(9)
                }
            }

            // pill face
            Rectangle {
                visible: tRoot.pillFace
                anchors.fill: parent
                radius: 16
                color: tHov.hovered && !root.edit ? Qt.alpha(root.theme.fg, 0.11)
                                                  : Qt.alpha(root.theme.fg, 0.07)
                Behavior on color { ColorAnimation { duration: 130 } }
                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 9
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 9
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(34, tRoot.height - 18)
                        height: width
                        radius: width / 2
                        color: tRoot.on ? tRoot.m.tint : Qt.alpha(root.theme.fg, 0.10)
                        Behavior on color { ColorAnimation { duration: 160 } }
                        Text {
                            anchors.centerIn: parent
                            text: tRoot.m ? tRoot.m.glyph : ""
                            color: tRoot.on ? tRoot.onTint : Qt.alpha(root.theme.fg, 0.85)
                            Behavior on color { ColorAnimation { duration: 160 } }
                            font.family: root.theme.fontMono
                            font.pixelSize: 15
                        }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Text {
                            text: tRoot.m ? tRoot.m.label : ""
                            color: root.theme.fg
                            font.family: root.theme.fontSans
                            font.pixelSize: IslandState.ts(11)
                            font.weight: Font.DemiBold
                        }
                        Text {
                            width: tRoot.width - 64
                            elide: Text.ElideRight
                            text: tRoot.m ? tRoot.m.sub : ""
                            color: Qt.alpha(root.theme.on_surface_variant, 0.85)
                            font.family: root.theme.fontSans
                            font.pixelSize: IslandState.ts(9)
                        }
                    }
                }
            }

            HoverHandler { id: tHov; enabled: !root.edit; cursorShape: Qt.PointingHandCursor }
            MouseArea {
                anchors.fill: parent
                enabled: !root.edit
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (e) => { if (tRoot.wi) root.toggleAction(tRoot.wi.id, e.button === Qt.RightButton); }
            }
        }
    }

    // ── launcher tile: opens a drill-in panel ─────────────────────
    Component {
        id: cLaunch
        TileBase {
            id: lTile
            readonly property int unit: wi ? Math.min(wi.w, wi.h) : 1
            // Same disc as an off toggle, so launchers and switches read as
            // one family; the tile itself only answers hover.
            color: lHov.hovered && !root.edit ? Qt.alpha(root.theme.fg, 0.11)
                                              : Qt.alpha(root.theme.fg, 0.07)
            Behavior on color { ColorAnimation { duration: 130 } }
            Column {
                anchors.centerIn: parent
                spacing: 4
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(Math.min(lTile.width, lTile.height) - 26, 30 + (lTile.unit - 1) * 14)
                    height: width
                    radius: width / 2
                    color: Qt.alpha(root.theme.fg, 0.10)
                    Text {
                        anchors.centerIn: parent
                        text: lTile.wi ? lTile.wi.def.glyph : ""
                        color: Qt.alpha(root.theme.on_surface, 0.9)
                        font.family: root.theme.fontMono
                        font.pixelSize: Math.min(15 + (lTile.unit - 1) * 6, 28)
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: lTile.width - 8
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                    text: lTile.wi ? lTile.wi.def.name : ""
                    color: Qt.alpha(root.theme.fg, 0.85)
                    font.family: root.theme.fontSans
                    font.weight: Font.Medium
                    font.pixelSize: Math.min(9 + (lTile.unit - 1) * 2, 12)
                }
            }
            HoverHandler { id: lHov; enabled: !root.edit; cursorShape: Qt.PointingHandCursor }
            MouseArea {
                anchors.fill: parent
                enabled: !root.edit
                onClicked: if (lTile.wi) IslandState.openTool(lTile.wi.def.tool, IslandState.toolScreen)
            }
        }
    }

    // ── slider: the whole tile is the track, either way up ────────
    Component {
        id: cSlider
        Item {
            id: sTile
            property var wi: null
            readonly property bool isMic: wi && wi.id === "mic"
            readonly property var audio: isMic ? root.srcAudio : root.sinkAudio
            readonly property int aw: wi ? wi.w : 7
            readonly property int ah: wi ? wi.h : 1
            readonly property bool circle1: aw === 1 && ah === 1
            readonly property bool vertical: !circle1 && ah > aw
            readonly property string glyphNow:
                !audio ? (isMic ? "\u{f036c}" : "\u{f057e}")
                : isMic ? (audio.muted ? "\u{f036d}" : "\u{f036c}")
                        : (audio.muted ? "\u{f075f}" : "\u{f057e}")
            readonly property string devName: {
                const n = sTile.isMic ? Pipewire.defaultAudioSource : Pipewire.defaultAudioSink;
                if (!n) return "\u{2014}";
                return n.nickname || n.description || n.name || "device";
            }

            // ── 1x1 face: a circle, the level as its ring ─────
            Column {
                visible: sTile.circle1
                anchors.centerIn: parent
                spacing: 4

                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(Math.min(sTile.width, sTile.height) - 22, 64)
                    height: width

                    RingProgress {
                        anchors.fill: parent
                        progress: sTile.audio ? Math.max(0, Math.min(1, sTile.audio.volume)) : 0
                        ring: sTile.audio && sTile.audio.muted
                              ? Qt.alpha(root.theme.muted, 0.8) : root.theme.accent
                        track: root.theme.fg
                        trackAlpha: 0.10
                        thickness: 2.5
                    }
                    Text {
                        anchors.centerIn: parent
                        text: sTile.glyphNow
                        color: sTile.audio && sTile.audio.muted
                               ? Qt.alpha(root.theme.muted, 0.8) : Qt.alpha(root.theme.fg, 0.85)
                        font.family: root.theme.fontMono
                        font.pixelSize: 15
                    }

                    HoverHandler { enabled: !root.edit; cursorShape: Qt.PointingHandCursor }
                    MouseArea {
                        anchors.fill: parent
                        enabled: !root.edit
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        // click mutes, like the glyph on every other face;
                        // right-click drills into the audio panel
                        onClicked: (e) => {
                            if (e.button === Qt.RightButton)
                                IslandState.openTool("audio", IslandState.toolScreen);
                            else if (sTile.audio) sTile.audio.muted = !sTile.audio.muted;
                        }
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: sTile.audio ? Math.round(sTile.audio.volume * 100) + "%" : "\u{2014}"
                    color: Qt.alpha(root.theme.on_surface_variant, 0.85)
                    font.family: root.theme.fontMono
                    font.pixelSize: 8
                }
            }

            // ── horizontal face ───────────────────────────────
            Column {
                visible: !sTile.vertical && !sTile.circle1
                anchors.fill: parent
                spacing: 6

                ControlSlider {
                    width: parent.width
                    // fills a one-row box; taller boxes keep the familiar bar
                    // and spend the rest on detail
                    height: sTile.ah === 1 ? sTile.height : 54
                    theme: root.theme
                    label: sTile.isMic ? "Microphone" : "Sound"
                    glyph: sTile.glyphNow
                    muted: sTile.audio ? sTile.audio.muted : false
                    value: sTile.audio ? sTile.audio.volume : 0
                    valueText: sTile.audio ? Math.round(sTile.audio.volume * 100) + "%" : "\u{2014}"
                    enabled: !root.edit
                    drillable: true
                    onDrill: IslandState.openTool("audio", IslandState.toolScreen)
                    onMoved: (v) => { if (sTile.audio) sTile.audio.volume = v; }
                    onToggleMuted: if (sTile.audio) sTile.audio.muted = !sTile.audio.muted
                }

                // where the sound is actually going
                Row {
                    visible: sTile.ah >= 2
                    spacing: 6
                    leftPadding: 14
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u{f0765}"
                        color: Qt.alpha(root.theme.on_surface_variant, 0.6)
                        font.family: root.theme.fontMono
                        font.pixelSize: 10
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: sTile.width - 60
                        elide: Text.ElideRight
                        text: sTile.devName
                        color: Qt.alpha(root.theme.on_surface_variant, 0.85)
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(10)
                    }
                }
            }

            // ── vertical face: a phone volume pill ────────────
            ClippingRectangle {
                visible: sTile.vertical
                anchors.fill: parent
                radius: 16
                color: Qt.alpha(root.theme.fg, 0.07)

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    id: vFill
                    readonly property real lvl: sTile.audio ? Math.max(0, Math.min(1, sTile.audio.volume)) : 0
                    height: parent.height * lvl
                    radius: Math.min(16, height / 2)
                    color: sTile.audio && sTile.audio.muted ? Qt.alpha(root.theme.muted, 0.55)
                                                            : root.theme.accent
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                Text {
                    anchors.top: parent.top
                    anchors.topMargin: 12
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: sTile.glyphNow
                    color: sTile.audio && sTile.audio.volume > 0.82
                           ? (sTile.audio.muted ? root.theme.fg : Qt.darker(root.theme.accent, 3.4))
                           : Qt.alpha(root.theme.fg, 0.85)
                    font.family: root.theme.fontMono
                    font.pixelSize: 15
                }
                Text {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 10
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: sTile.audio ? Math.round(sTile.audio.volume * 100) + "%" : "\u{2014}"
                    // dark only while the fill actually reaches the reading
                    color: !sTile.audio || sTile.audio.muted || vFill.height < 24
                           ? Qt.alpha(root.theme.fg, 0.85) : Qt.darker(root.theme.accent, 3.4)
                    font.family: root.theme.fontSans
                    font.features: ({ "tnum": 1 })
                    font.pixelSize: IslandState.ts(10)
                    font.weight: Font.Bold
                }

                // One handler for the whole pill. The mute key used to be a
                // full-width band over the top 34px that won every press
                // there, which put everything above ~75% behind it: a tap
                // at the top muted instead of setting the level. Now only
                // the glyph's own square mutes, and only on a tap — a drag
                // that starts on it sets the volume like anywhere else.
                // Right-click anywhere mutes too.
                MouseArea {
                    id: pillArea
                    anchors.fill: parent
                    enabled: !root.edit
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    // keeps the grab from the hub's scroller for the whole
                    // press, so a drag that leaves the pill still adjusts
                    preventStealing: true
                    property real pressY: 0
                    property bool onGlyph: false
                    property bool dragging: false
                    function glyphHit(m) {
                        return m.y <= 36 && Math.abs(m.x - width / 2) <= 15;
                    }
                    function setLevel(y) {
                        if (sTile.audio) sTile.audio.volume = Math.max(0, Math.min(1, 1 - y / height));
                    }
                    onPressed: (m) => {
                        pressY = m.y;
                        dragging = false;
                        onGlyph = pillArea.glyphHit(m);
                        if (m.button === Qt.LeftButton && !onGlyph) pillArea.setLevel(m.y);
                    }
                    onPositionChanged: (m) => {
                        if (!pressed || !(pressedButtons & Qt.LeftButton)) return;
                        if (!dragging && Math.abs(m.y - pressY) <= 4) return;
                        dragging = true;
                        pillArea.setLevel(m.y);
                    }
                    onReleased: (m) => {
                        if (!sTile.audio) return;
                        if (m.button === Qt.RightButton || (onGlyph && !dragging))
                            sTile.audio.muted = !sTile.audio.muted;
                    }
                }
            }

            // the way into the full audio panel — devices, mixer, brightness
            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: sTile.vertical ? 6 : 54
                anchors.verticalCenter: sTile.vertical ? undefined : parent.verticalCenter
                anchors.top: sTile.vertical ? parent.top : undefined
                anchors.topMargin: sTile.vertical ? 6 : 0
                width: 24; height: 24; radius: 9
                visible: !sTile.isMic && sTile.vertical && sTile.aw >= 2
                color: expHov.hovered && !root.edit ? Qt.alpha(root.theme.fg, 0.16) : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: "\u{f0142}"
                    color: Qt.alpha(root.theme.on_surface_variant, 0.8)
                    font.family: root.theme.fontMono
                    font.pixelSize: 13
                }
                HoverHandler { id: expHov; enabled: !root.edit; cursorShape: Qt.PointingHandCursor }
                MouseArea {
                    anchors.fill: parent
                    enabled: !root.edit
                    onClicked: IslandState.openTool("audio", IslandState.toolScreen)
                }
            }
        }
    }

    // ── media card ────────────────────────────────────────────────
    Component {
        id: cMedia
        TileBase {
            id: mTile
            readonly property var player: IslandState.player
            readonly property bool active: player !== null && player.trackTitle !== ""
            readonly property int aw: wi ? wi.w : 4
            readonly property int ah: wi ? wi.h : 2
            readonly property bool vertical: ah > aw

            // Progress needs polling — position is not a notify property.
            // Only the live hub instance polls, and only while the card is up.
            property real pos: 0
            readonly property bool wantProg:
                mTile.ah >= 2 && mTile.player !== null
                && mTile.player.lengthSupported && mTile.player.length > 0
            Timer {
                interval: 1000
                repeat: true
                triggeredOnStart: true
                running: !root.edit && IslandState.cardOpen && mTile.wantProg
                onTriggered: mTile.pos = mTile.player ? mTile.player.position : 0
            }
            readonly property real prog:
                wantProg ? Math.max(0, Math.min(1, pos / player.length)) : 0

            function seek(frac) {
                if (!mTile.player || !mTile.player.canSeek || !mTile.player.length) return;
                mTile.player.position = frac * mTile.player.length;
                mTile.pos = frac * mTile.player.length;
            }

            Text {
                anchors.centerIn: parent
                visible: !mTile.active
                text: "Nothing playing"
                color: Qt.alpha(root.theme.on_surface_variant, 0.6)
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(11)
            }

            component MediaArt: ClippingRectangle {
                id: artBox
                radius: 12
                color: Qt.alpha(root.theme.muted, 0.2)
                Image {
                    id: aImg
                    anchors.fill: parent
                    source: mTile.player && mTile.player.trackArtUrl ? mTile.player.trackArtUrl : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 220
                    sourceSize.height: 220
                    asynchronous: true
                }
                TrackSwap { target: artBox; shift: 0; fromScale: 0.86 }
                Rectangle {
                    anchors.fill: parent
                    visible: aImg.status === Image.Ready
                    color: Qt.alpha(root.theme.accent, 0.16)
                }
                HoverHandler { enabled: !root.edit; cursorShape: Qt.PointingHandCursor }
                MouseArea {
                    anchors.fill: parent
                    enabled: !root.edit
                    onClicked: IslandState.openTool("media", IslandState.toolScreen)
                }
            }

            component MediaProgress: Item {
                width: parent.width
                height: 12
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width; height: 3; radius: 1.5
                    color: Qt.alpha(root.theme.fg, 0.12)
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * mTile.prog; height: 3; radius: 1.5
                    color: Qt.alpha(root.theme.accent, 0.85)
                }
                MouseArea {
                    preventStealing: true
                    anchors.fill: parent
                    enabled: !root.edit && mTile.player !== null && mTile.player.canSeek
                    cursorShape: Qt.PointingHandCursor
                    onPressed: (m) => mTile.seek(Math.max(0, Math.min(1, m.x / width)))
                    onPositionChanged: (m) => {
                        if (pressed) mTile.seek(Math.max(0, Math.min(1, m.x / width)));
                    }
                }
            }

            component MediaButtons: Row {
                spacing: 8
                Repeater {
                    model: [
                        { g: "\u{f04ae}", a: "prev" },
                        { g: mTile.player && mTile.player.isPlaying ? "\u{f03e4}" : "\u{f040a}", a: "toggle" },
                        { g: "\u{f04ad}", a: "next" }
                    ]
                    Rectangle {
                        required property var modelData
                        width: 30; height: 30; radius: 15
                        color: bHov.hovered && !root.edit ? Qt.alpha(root.theme.fg, 0.16)
                                                          : Qt.alpha(root.theme.fg, 0.07)
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            anchors.centerIn: parent
                            text: parent.modelData.g
                            color: root.theme.fg
                            font.family: root.theme.fontMono
                            font.pixelSize: 13
                        }
                        HoverHandler { id: bHov; enabled: !root.edit; cursorShape: Qt.PointingHandCursor }
                        MouseArea {
                            anchors.fill: parent
                            enabled: !root.edit
                            onClicked: {
                                if (!mTile.player) return;
                                if (parent.modelData.a === "prev") mTile.player.previous();
                                else if (parent.modelData.a === "next") mTile.player.next();
                                else mTile.player.togglePlaying();
                            }
                        }
                    }
                }
            }

            // ── horizontal face ───────────────────────────────
            Row {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12
                visible: mTile.active && !mTile.vertical

                MediaArt {
                    width: parent.height
                    height: parent.height
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - parent.height - 12
                    spacing: 5

                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: mTile.player ? mTile.player.trackTitle : ""
                        TrackSwap { delay: 50 }
                        color: root.theme.fg
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(12)
                        font.weight: Font.DemiBold
                    }
                    Text {
                        visible: mTile.ah >= 2
                        width: parent.width
                        elide: Text.ElideRight
                        text: mTile.player ? mTile.player.trackArtist : ""
                        TrackSwap { delay: 110 }
                        color: Qt.alpha(root.theme.on_surface_variant, 0.9)
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(10)
                    }
                    Text {
                        visible: mTile.ah >= 2 && mTile.aw >= 5 && text !== ""
                        width: parent.width
                        elide: Text.ElideRight
                        text: mTile.player ? (mTile.player.trackAlbum || "") : ""
                        TrackSwap { delay: 160 }
                        color: Qt.alpha(root.theme.on_surface_variant, 0.65)
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(9)
                    }

                    MediaProgress { visible: mTile.wantProg }

                    Row {
                        spacing: 10
                        MediaButtons { anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            visible: mTile.aw >= 5 && mTile.wantProg
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.fmtSecs(mTile.pos) + " / "
                                  + root.fmtSecs(mTile.player ? mTile.player.length : 0)
                            color: Qt.alpha(root.theme.on_surface_variant, 0.75)
                            font.family: root.theme.fontMono
                            font.pixelSize: 9
                        }
                    }
                }
            }

            // ── vertical face: art on top, the phone way up ───
            Column {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 6
                visible: mTile.active && mTile.vertical

                MediaArt {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(parent.width, mTile.height - 110)
                    height: width
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: mTile.player ? mTile.player.trackTitle : ""
                    TrackSwap { delay: 50 }
                    color: root.theme.fg
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(12)
                    font.weight: Font.DemiBold
                }
                Text {
                    visible: mTile.ah >= 3
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: mTile.player ? mTile.player.trackArtist : ""
                    TrackSwap { delay: 110 }
                    color: Qt.alpha(root.theme.on_surface_variant, 0.9)
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(10)
                }
                MediaProgress { visible: mTile.wantProg }
                MediaButtons { anchors.horizontalCenter: parent.horizontalCenter }
            }
        }
    }

    // ── calendar: today at a glance ───────────────────────────────
    Component {
        id: cCal
        TileBase {
            id: calTile
            readonly property int aw: wi ? wi.w : 2
            readonly property int ah: wi ? wi.h : 1
            color: calHov.hovered && !root.edit ? Qt.alpha(root.theme.fg, 0.12)
                                                : Qt.alpha(root.theme.fg, 0.07)
            Behavior on color { ColorAnimation { duration: 130 } }

            SystemClock { id: calClk; precision: SystemClock.Minutes }

            // Today's agenda, from the same tool the calendar panel reads —
            // cached so the tile carries yesterday's shape for the frame it
            // takes the poll to land.
            property var items: IslandState.cacheGet("cc.agenda", [])
            function reloadAgenda() {
                const d = calClk.date;
                const iso = d.getFullYear() + "-"
                          + ("0" + (d.getMonth() + 1)).slice(-2) + "-"
                          + ("0" + d.getDate()).slice(-2);
                agendaProc.command = ["@HOME@/.local/bin/calendar-agenda", "day", iso];
                agendaProc.running = true;
            }
            Process {
                id: agendaProc
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const j = JSON.parse(this.text.trim());
                            calTile.items = j.items || [];
                            IslandState.cacheSet("cc.agenda", calTile.items);
                        } catch (e) { /* keep the last good reading */ }
                    }
                }
            }
            Timer {
                interval: 300000
                repeat: true
                triggeredOnStart: true
                running: !root.edit && IslandState.cardOpen
                onTriggered: calTile.reloadAgenda()
            }

            // What is still ahead of now — done reminders and finished
            // meetings are the panel's business, not the glance's.
            readonly property var upcoming: {
                const now = ("0" + calClk.date.getHours()).slice(-2) + ":"
                          + ("0" + calClk.date.getMinutes()).slice(-2);
                const out = [];
                for (let i = 0; i < calTile.items.length; i++) {
                    const it = calTile.items[i];
                    if (it.completed === true) continue;
                    if (it.kind === "event" && !it.allday && it.end !== "" && it.end < now) continue;
                    out.push(it);
                }
                return out;
            }
            readonly property var nextUp: calTile.upcoming.length > 0 ? calTile.upcoming[0] : null
            readonly property int fitCount:
                Math.max(0, Math.floor((height - 46) / 26))

            // ── the date block, every face leads with it ──────
            component CalDate: Column {
                spacing: 0
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDate(calClk.date, "ddd").toUpperCase()
                    color: root.theme.accent
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(9)
                    font.weight: Font.Bold
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: calClk.date.getDate()
                    color: root.theme.fg
                    font.family: root.theme.fontDisplay
                    font.pixelSize: 22
                    font.weight: Font.Black
                }
            }

            // ── 1-wide face: the date, plus how much is left ──
            Column {
                visible: calTile.aw === 1
                anchors.centerIn: parent
                spacing: 2
                CalDate { anchors.horizontalCenter: parent.horizontalCenter }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: calTile.upcoming.length > 0
                    text: calTile.upcoming.length + " ahead"
                    color: Qt.alpha(root.theme.on_surface_variant, 0.75)
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(8)
                }
            }

            // ── one-row face: date beside the next thing ──────
            Row {
                visible: calTile.aw >= 2 && calTile.ah === 1
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12

                CalDate { anchors.verticalCenter: parent.verticalCenter }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 50
                    spacing: 1
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: calTile.nextUp ? calTile.nextUp.title : "Nothing ahead today"
                        color: calTile.nextUp ? root.theme.fg
                                              : Qt.alpha(root.theme.on_surface_variant, 0.6)
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(11)
                        font.weight: calTile.nextUp ? Font.DemiBold : Font.Normal
                    }
                    Text {
                        visible: calTile.nextUp !== null
                        width: parent.width
                        elide: Text.ElideRight
                        text: {
                            const n = calTile.nextUp;
                            if (!n) return "";
                            if (n.overdue === true) return "overdue";
                            if (n.allday === true) return "all day";
                            return n.start + (n.end !== "" ? " \u{2013} " + n.end : "");
                        }
                        color: calTile.nextUp && calTile.nextUp.overdue === true
                               ? root.theme.warn : Qt.alpha(root.theme.on_surface_variant, 0.8)
                        font.family: root.theme.fontMono
                        font.pixelSize: 9
                    }
                }
            }

            // ── tall face: the day's list ─────────────────────
            Column {
                visible: calTile.aw >= 2 && calTile.ah >= 2
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 12
                spacing: 6

                Row {
                    spacing: 10
                    CalDate {}
                    Text {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 2
                        text: Qt.formatDate(calClk.date, "MMMM yyyy")
                        color: Qt.alpha(root.theme.on_surface_variant, 0.75)
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(10)
                    }
                }

                Text {
                    visible: calTile.upcoming.length === 0
                    text: "Nothing ahead today"
                    color: Qt.alpha(root.theme.on_surface_variant, 0.55)
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(10)
                }

                Repeater {
                    model: calTile.upcoming.slice(0, Math.max(0, calTile.fitCount - 1))

                    Row {
                        id: agRow
                        required property var modelData
                        width: parent.width
                        spacing: 8

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 4; height: 16; radius: 2
                            color: agRow.modelData.color || root.theme.accent
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 38
                            text: agRow.modelData.allday === true ? "day"
                                : agRow.modelData.overdue === true ? "!"
                                : agRow.modelData.start
                            color: agRow.modelData.overdue === true
                                   ? root.theme.warn : Qt.alpha(root.theme.on_surface_variant, 0.85)
                            font.family: root.theme.fontMono
                            font.pixelSize: 9
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 58
                            elide: Text.ElideRight
                            text: agRow.modelData.title
                            color: root.theme.fg
                            font.family: root.theme.fontSans
                            font.pixelSize: IslandState.ts(10)
                        }
                    }
                }
            }

            HoverHandler { id: calHov; enabled: !root.edit; cursorShape: Qt.PointingHandCursor }
            MouseArea {
                anchors.fill: parent
                enabled: !root.edit
                onClicked: IslandState.openTool("calendar", IslandState.toolScreen)
            }
        }
    }

    // ── timer: the trail capsule's dial, parked on the grid ──────
    Component {
        id: cTimer
        TileBase {
            id: tmTile
            readonly property int aw: wi ? wi.w : 1
            readonly property bool live: IslandState.timerTotal > 0
            color: tmHov.hovered && !root.edit ? Qt.alpha(root.theme.fg, 0.12)
                                               : Qt.alpha(root.theme.fg, 0.07)
            Behavior on color { ColorAnimation { duration: 130 } }

            Column {
                anchors.centerIn: parent
                spacing: 4

                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(Math.min(tmTile.width, tmTile.height) - 22, 64)
                    height: width

                    RingProgress {
                        anchors.fill: parent
                        progress: tmTile.live ? IslandState.timerProgress : 0
                        ring: IslandState.timerRunning ? root.theme.accent : root.theme.accent2
                        track: root.theme.fg
                        trackAlpha: 0.10
                        thickness: 2.5
                    }
                    Text {
                        anchors.centerIn: parent
                        text: tmTile.live ? IslandState.timerText : "\u{f051b}"
                        color: tmTile.live && !IslandState.timerRunning
                               ? root.theme.accent2 : Qt.alpha(root.theme.fg, 0.9)
                        font.family: root.theme.fontMono
                        font.pixelSize: tmTile.live ? 10 : 15
                        font.weight: tmTile.live ? Font.Bold : Font.Normal
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Timer" + (tmTile.aw >= 2 && tmTile.live
                          ? (IslandState.timerRunning ? " · running" : " · paused") : "")
                    color: Qt.alpha(root.theme.on_surface_variant, 0.85)
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(8)
                }
            }

            HoverHandler { id: tmHov; enabled: !root.edit; cursorShape: Qt.PointingHandCursor }
            MouseArea {
                anchors.fill: parent
                enabled: !root.edit
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                // right-click pauses/resumes a live timer, the capsule's idiom
                onClicked: (e) => {
                    if (e.button === Qt.RightButton && tmTile.live) IslandState.timerToggle();
                    else IslandState.openTool("timer", IslandState.toolScreen);
                }
            }
        }
    }

    // ── notes: the pinned thought, then the pile ──────────────────
    Component {
        id: cNotes
        TileBase {
            id: noTile
            readonly property int aw: wi ? wi.w : 2
            readonly property int ah: wi ? wi.h : 1
            color: noHov.hovered && !root.edit ? Qt.alpha(root.theme.fg, 0.12)
                                               : Qt.alpha(root.theme.fg, 0.07)
            Behavior on color { ColorAnimation { duration: 130 } }

            // pinned first — a pin is "keep this in front of me", which is
            // exactly what a glance tile is for
            property var notes: IslandState.cacheGet("cc.notes", [])
            readonly property var topNote: noTile.notes.length > 0 ? noTile.notes[0] : null
            readonly property int fitCount:
                Math.max(0, Math.floor((height - 46) / 26))

            Process {
                id: noProc
                command: ["bash", "@HOME@/.config/quickshell/scripts/notes.sh", "list", "8"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const j = JSON.parse(this.text.trim());
                            const ns = (j.notes || []).slice();
                            ns.sort((a, b) => (b.pinned ? 1 : 0) - (a.pinned ? 1 : 0));
                            noTile.notes = ns;
                            IslandState.cacheSet("cc.notes", ns);
                        } catch (e) { /* keep the last good reading */ }
                    }
                }
            }
            Timer {
                interval: 60000
                repeat: true
                triggeredOnStart: true
                running: !root.edit && IslandState.cardOpen
                onTriggered: noProc.running = true
            }

            // ── 1-wide face ───────────────────────────────────
            Column {
                visible: noTile.aw === 1
                anchors.centerIn: parent
                spacing: 4
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "\u{f09a5}"
                    color: Qt.alpha(root.theme.on_surface, 0.9)
                    font.family: root.theme.fontMono
                    font.pixelSize: 17
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: noTile.notes.length > 0 ? noTile.notes.length + " notes" : "Notes"
                    color: Qt.alpha(root.theme.on_surface_variant, 0.85)
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(8)
                }
            }

            // ── one-row face: the note that matters ───────────
            Row {
                visible: noTile.aw >= 2 && noTile.ah === 1
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: noTile.topNote && noTile.topNote.pinned ? "\u{f0403}" : "\u{f09a5}"
                    color: noTile.topNote && noTile.topNote.pinned
                           ? root.theme.accent : Qt.alpha(root.theme.on_surface, 0.85)
                    font.family: root.theme.fontMono
                    font.pixelSize: 15
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 26
                    spacing: 1
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: noTile.topNote ? noTile.topNote.title : "No notes yet"
                        color: noTile.topNote ? root.theme.fg
                                          : Qt.alpha(root.theme.on_surface_variant, 0.6)
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(11)
                        font.weight: noTile.topNote ? Font.DemiBold : Font.Normal
                    }
                    Text {
                        visible: noTile.topNote !== null
                        width: parent.width
                        elide: Text.ElideRight
                        text: noTile.topNote
                              ? noTile.topNote.when + (noTile.notes.length > 1
                                    ? " · " + (noTile.notes.length - 1) + " more" : "")
                              : ""
                        color: Qt.alpha(root.theme.on_surface_variant, 0.7)
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(9)
                    }
                }
            }

            // ── tall face: the pile ───────────────────────────
            Column {
                visible: noTile.aw >= 2 && noTile.ah >= 2
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 12
                spacing: 6

                Row {
                    spacing: 7
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u{f09a5}"
                        color: Qt.alpha(root.theme.on_surface, 0.9)
                        font.family: root.theme.fontMono
                        font.pixelSize: 13
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Notes" + (noTile.notes.length > 0 ? " · " + noTile.notes.length : "")
                        color: root.theme.fg
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(11)
                        font.weight: Font.DemiBold
                    }
                }

                Text {
                    visible: noTile.notes.length === 0
                    text: "No notes yet"
                    color: Qt.alpha(root.theme.on_surface_variant, 0.55)
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(10)
                }

                Repeater {
                    model: noTile.notes.slice(0, Math.max(0, noTile.fitCount - 1))

                    Row {
                        id: noRow
                        required property var modelData
                        width: parent.width
                        spacing: 8

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: noRow.modelData.pinned ? "\u{f0403}" : "\u{f09a5}"
                            color: noRow.modelData.pinned
                                   ? root.theme.accent : Qt.alpha(root.theme.on_surface_variant, 0.6)
                            font.family: root.theme.fontMono
                            font.pixelSize: 10
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 70
                            elide: Text.ElideRight
                            text: noRow.modelData.title
                            color: root.theme.fg
                            font.family: root.theme.fontSans
                            font.pixelSize: IslandState.ts(10)
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: noRow.modelData.when
                            color: Qt.alpha(root.theme.on_surface_variant, 0.6)
                            font.family: root.theme.fontMono
                            font.pixelSize: 8
                        }
                    }
                }
            }

            HoverHandler { id: noHov; enabled: !root.edit; cursorShape: Qt.PointingHandCursor }
            MouseArea {
                anchors.fill: parent
                enabled: !root.edit
                onClicked: IslandState.openTool("notes", IslandState.toolScreen)
            }
        }
    }

    // ── system: the monitor panel's headline numbers ──────────────
    Component {
        id: cSys
        TileBase {
            id: syTile
            readonly property int aw: wi ? wi.w : 2
            readonly property int ah: wi ? wi.h : 1
            color: syHov.hovered && !root.edit ? Qt.alpha(root.theme.fg, 0.12)
                                               : Qt.alpha(root.theme.fg, 0.07)
            Behavior on color { ColorAnimation { duration: 130 } }

            property var rd: IslandState.cacheGet("cc.sys", ({}))
            function ingest(key, raw) {
                try {
                    const j = JSON.parse((raw || "").trim());
                    const next = {};
                    for (const k in syTile.rd) next[k] = syTile.rd[k];
                    next[key] = { text: j.text || "\u{2014}", cls: j.class || "" };
                    syTile.rd = next;
                    IslandState.cacheSet("cc.sys", next);
                } catch (e) { /* keep the last good reading */ }
            }
            function clsColor(cls) {
                if (!cls) return root.theme.fg;
                if (cls.indexOf("crit") !== -1) return root.theme.warn;
                if (cls.indexOf("high") !== -1) return root.theme.accent2;
                return root.theme.fg;
            }

            Process {
                id: syCpu
                command: ["bash", "@HOME@/.config/quickshell/scripts/cpu.sh"]
                stdout: StdioCollector { onStreamFinished: syTile.ingest("cpu", this.text) }
            }
            Process {
                id: syMem
                command: ["bash", "@HOME@/.config/quickshell/scripts/mem.sh"]
                stdout: StdioCollector { onStreamFinished: syTile.ingest("mem", this.text) }
            }
            Process {
                id: syGpu
                command: ["bash", "@HOME@/.config/quickshell/scripts/gpu.sh"]
                stdout: StdioCollector { onStreamFinished: syTile.ingest("gpu", this.text) }
            }
            Timer {
                interval: 4000
                repeat: true
                triggeredOnStart: true
                running: !root.edit && IslandState.cardOpen
                onTriggered: {
                    syCpu.running = true;
                    syMem.running = true;
                    if (syTile.aw >= 2 || syTile.ah >= 2) syGpu.running = true;
                }
            }

            // ── 1x1 face: the one number that spikes first ────
            Column {
                visible: syTile.aw === 1 && syTile.ah === 1
                anchors.centerIn: parent
                spacing: 4
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: syTile.rd.cpu ? syTile.rd.cpu.text : "\u{2026}"
                    color: syTile.clsColor(syTile.rd.cpu ? syTile.rd.cpu.cls : "")
                    font.family: root.theme.fontMono
                    font.pixelSize: 12
                    font.weight: Font.Bold
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "System"
                    color: Qt.alpha(root.theme.on_surface_variant, 0.85)
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(8)
                }
            }

            // ── wider: cpu, memory, gpu side by side ──────────
            // Each column gets a third of the box and the value shrinks to
            // fit it, so no width leaves a unit cut off. The scripts' text
            // is "<glyph>  <value>"; the glyph goes first when the column
            // gets tight. A one-wide tall box stacks the three instead.
            Grid {
                id: syGrid
                visible: syTile.aw >= 2 || syTile.ah >= 2
                readonly property bool stacked: syTile.aw === 1
                readonly property real colW: stacked ? syTile.width - 20
                                                     : (syTile.width - 20 - columnSpacing * 2) / 3
                anchors.centerIn: parent
                columns: stacked ? 1 : 3
                columnSpacing: 8
                rowSpacing: 6

                Repeater {
                    model: [
                        { key: "cpu", label: "cpu" },
                        { key: "mem", label: "mem" },
                        { key: "gpu", label: "gpu" }
                    ]
                    Column {
                        id: syCol
                        required property var modelData
                        readonly property var rd: syTile.rd[syCol.modelData.key] || null
                        readonly property var parts: (rd ? rd.text : "\u{2026}").trim().split(/\s+/)
                        readonly property string glyph: parts.length > 1 ? parts[0] : ""
                        readonly property string value: parts.length > 1 ? parts.slice(1).join(" ") : parts[0]
                        width: syGrid.colW
                        spacing: 1
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: (syCol.glyph !== "" && syGrid.colW >= 64 ? syCol.glyph + " " : "") + syCol.value
                            color: syTile.clsColor(syCol.rd ? syCol.rd.cls : "")
                            font.family: root.theme.fontMono
                            font.pixelSize: syTile.ah >= 2 ? 13 : 11
                            font.weight: Font.Bold
                            fontSizeMode: Text.HorizontalFit
                            minimumPixelSize: 8
                        }
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: syCol.modelData.label
                            color: Qt.alpha(root.theme.on_surface_variant, 0.7)
                            font.family: root.theme.fontSans
                            font.pixelSize: IslandState.ts(8)
                        }
                    }
                }
            }

            HoverHandler { id: syHov; enabled: !root.edit; cursorShape: Qt.PointingHandCursor }
            MouseArea {
                anchors.fill: parent
                enabled: !root.edit
                onClicked: IslandState.openTool("monitor", IslandState.toolScreen)
            }
        }
    }

    // ── notifications panel ───────────────────────────────────────
    Component {
        id: cNotifs
        TileBase {
            id: nTile
            readonly property var list: IslandState.notifs
            readonly property int aw: wi ? wi.w : 7
            // 48 = header band + bottom inset; a box too short for even one
            // row shows just the header and its count rather than a row
            // bleeding through the border.
            readonly property int fitCount:
                Math.max(0, Math.floor((height - 48) / 40))

            Item {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 12
                height: 18

                Row {
                    anchors.left: parent.left
                    spacing: 7
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: IslandState.dnd ? "\u{f09a1}" : "\u{f009a}"
                        color: IslandState.dnd ? root.theme.accent2 : root.theme.accent3
                        font.family: root.theme.fontMono
                        font.pixelSize: 13
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Notifications" + (nTile.list.length > 0 ? " · " + nTile.list.length : "")
                        color: root.theme.fg
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(11)
                        font.weight: Font.DemiBold
                    }
                }
                Row {
                    anchors.right: parent.right
                    spacing: 2
                    Rectangle {
                        width: 22; height: 22; radius: 8
                        visible: nTile.list.length > 0
                        color: clrHov.hovered && !root.edit ? Qt.alpha(root.theme.error, 0.2) : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "\u{f00e2}"
                            color: clrHov.hovered && !root.edit ? root.theme.error
                                 : Qt.alpha(root.theme.on_surface_variant, 0.7)
                            font.family: root.theme.fontMono
                            font.pixelSize: 12
                        }
                        HoverHandler { id: clrHov; enabled: !root.edit; cursorShape: Qt.PointingHandCursor }
                        MouseArea {
                            anchors.fill: parent
                            enabled: !root.edit
                            onClicked: IslandState.notifsClear()
                        }
                    }
                    Rectangle {
                        width: 22; height: 22; radius: 8
                        color: nOpen.hovered && !root.edit ? Qt.alpha(root.theme.fg, 0.14) : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "\u{f0142}"
                            color: Qt.alpha(root.theme.on_surface_variant, 0.8)
                            font.family: root.theme.fontMono
                            font.pixelSize: 12
                        }
                        HoverHandler { id: nOpen; enabled: !root.edit; cursorShape: Qt.PointingHandCursor }
                        MouseArea {
                            anchors.fill: parent
                            enabled: !root.edit
                            onClicked: IslandState.openTool("notifs", IslandState.toolScreen)
                        }
                    }
                }
            }

            // The empty state says what empty means: a bell in a quiet disc,
            // "All caught up", and since when — not a shrug of grey text.
            Column {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 9
                visible: nTile.list.length === 0 && nTile.fitCount > 0
                spacing: 3

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 26; height: 26; radius: 13
                    color: Qt.alpha(root.theme.fg, 0.08)
                    Text {
                        anchors.centerIn: parent
                        text: IslandState.dnd ? "\u{f009b}" : "\u{f009a}"
                        color: Qt.alpha(root.theme.fg, 0.6)
                        font.family: root.theme.fontMono
                        font.pixelSize: 13
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    topPadding: 3
                    text: "All caught up"
                    color: root.theme.fg
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(11)
                    font.weight: Font.DemiBold
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: nTile.height >= 130
                    text: "Nothing new since " + IslandState.clockHours(IslandState.quietSince) + ":"
                          + ("0" + IslandState.quietSince.getMinutes()).slice(-2)
                    color: Qt.alpha(root.theme.on_surface_variant, 0.7)
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(9)
                }
            }

            Column {
                anchors.top: parent.top
                anchors.topMargin: 36
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 4

                Repeater {
                    model: nTile.list.slice(0, nTile.fitCount)

                    Rectangle {
                        id: nRow
                        required property var modelData
                        width: parent.width
                        height: 36
                        radius: 10
                        color: Qt.alpha(root.theme.fg, 0.05)

                        Row {
                            id: nInner
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.right: nAge.visible ? nAge.left : parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 22; height: 22; radius: 8
                                color: Qt.alpha(root.theme.muted, 0.2)
                                clip: true
                                Image {
                                    anchors.fill: parent
                                    visible: (nRow.modelData.image || "") !== ""
                                    source: nRow.modelData.image || ""
                                    fillMode: Image.PreserveAspectCrop
                                    sourceSize.width: 44
                                    sourceSize.height: 44
                                    asynchronous: true
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: (nRow.modelData.image || "") === ""
                                    text: "\u{f009a}"
                                    color: Qt.alpha(root.theme.on_surface_variant, 0.7)
                                    font.family: root.theme.fontMono
                                    font.pixelSize: 11
                                }
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: nInner.width - 30
                                spacing: 0
                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: nRow.modelData.summary || ""
                                    color: root.theme.fg
                                    font.family: root.theme.fontSans
                                    font.pixelSize: IslandState.ts(10)
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    width: parent.width
                                    visible: text !== ""
                                    elide: Text.ElideRight
                                    text: (nRow.modelData.body || "").replace(/\n/g, " ")
                                    color: Qt.alpha(root.theme.on_surface_variant, 0.8)
                                    font.family: root.theme.fontSans
                                    font.pixelSize: IslandState.ts(9)
                                }
                            }
                        }

                        // a wide box earns the timestamps
                        Text {
                            id: nAge
                            visible: nTile.aw >= 5
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: IslandState.notifAge(nRow.modelData)
                            color: Qt.alpha(root.theme.on_surface_variant, 0.6)
                            font.family: root.theme.fontMono
                            font.pixelSize: 9
                        }
                    }
                }
            }
        }
    }

    // ── weather tile ──────────────────────────────────────────────
    Component {
        id: cWeather
        TileBase {
            id: wTile
            readonly property int aw: wi ? wi.w : 2
            readonly property int ah: wi ? wi.h : 1
            readonly property bool vertical: ah > aw
            readonly property int area: aw * ah
            color: wHov.hovered && !root.edit ? Qt.alpha(root.theme.fg, 0.12)
                                              : Qt.alpha(root.theme.fg, 0.07)
            Behavior on color { ColorAnimation { duration: 130 } }

            SystemClock { id: wClk; precision: SystemClock.Minutes }

            // The next hours, from the current one on. The poll is cached
            // for half an hour, so its strip can start in the past; the
            // clock decides what "now" is, not the fetch time.
            readonly property var hours: {
                const h = wClk.date.getHours();
                const out = [];
                const src = IslandState.wxHourly;
                for (let i = 0; i < src.length; i++)
                    if (src[i].tomorrow === true || src[i].hour >= h) out.push(src[i]);
                return out;
            }
            readonly property int hourCellW: 34
            // One row: the hours sit beside the reading once the box is
            // three wide. Taller boxes put them underneath instead.
            readonly property bool hoursInline: !wTile.vertical && wTile.ah === 1
                                                && wTile.aw >= 3 && wTile.hours.length > 0
            readonly property int inlineCount: Math.floor((wTile.width - 118) / wTile.hourCellW)
            readonly property bool hoursBelow: wTile.ah >= 2 && wTile.aw >= 2 && wTile.hours.length > 0
            readonly property int belowCount: Math.floor((wTile.width - 20) / wTile.hourCellW)

            component WxHours: Row {
                id: hoursRow
                property int count: 3
                spacing: 0
                Repeater {
                    model: wTile.hours.slice(0, Math.max(0, hoursRow.count))
                    Column {
                        id: hourCell
                        required property var modelData
                        required property int index
                        width: wTile.hourCellW
                        spacing: 1
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: hourCell.index === 0 ? "now"
                                : ("0" + hourCell.modelData.hour).slice(-2)
                            color: hourCell.index === 0 ? root.theme.accent
                                 : Qt.alpha(root.theme.on_surface_variant, 0.75)
                            font.family: root.theme.fontMono
                            font.pixelSize: 8
                            font.weight: hourCell.index === 0 ? Font.Bold : Font.Normal
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: hourCell.modelData.icon
                            color: root.theme.primary
                            font.family: root.theme.fontMono
                            font.pixelSize: 12
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: hourCell.modelData.temp + "\u{00b0}"
                            color: root.theme.fg
                            font.family: root.theme.fontMono
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                        }
                    }
                }
            }

            component WxExtras: Column {
                spacing: 3
                Repeater {
                    model: [
                        { g: "\u{e373}", v: IslandState.wxHumidity !== "" ? IslandState.wxHumidity + "%" : "" },
                        { g: "\u{e34c}", v: IslandState.wxWind !== "" ? IslandState.wxWind + " km/h" : "" },
                        { g: "\u{f059a}", v: IslandState.wxSunset }
                    ]
                    Row {
                        required property var modelData
                        visible: modelData.v !== ""
                        spacing: 5
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.g
                            color: Qt.alpha(root.theme.fg, 0.7)
                            font.family: root.theme.fontMono
                            font.pixelSize: 10
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.v
                            color: Qt.alpha(root.theme.on_surface_variant, 0.9)
                            font.family: root.theme.fontMono
                            font.pixelSize: 9
                        }
                    }
                }
            }

            component WxCore: Column {
                spacing: 0
                Text {
                    anchors.horizontalCenter: wTile.vertical ? parent.horizontalCenter : undefined
                    text: IslandState.wxTemp + "\u{00b0}"
                    color: root.theme.fg
                    font.family: root.theme.fontMono
                    font.pixelSize: 15
                    font.weight: Font.Black
                }
                Text {
                    visible: (wTile.aw >= 2 || wTile.vertical) && text !== ""
                    anchors.horizontalCenter: wTile.vertical ? parent.horizontalCenter : undefined
                    width: Math.min(implicitWidth, wTile.hoursInline ? 64 : wTile.width - 16)
                    elide: Text.ElideRight
                    text: IslandState.wxDesc
                    color: Qt.alpha(root.theme.on_surface_variant, 0.85)
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(9)
                }
                Text {
                    visible: (wTile.aw >= 2 || wTile.vertical) && IslandState.wxFeels !== ""
                    anchors.horizontalCenter: wTile.vertical ? parent.horizontalCenter : undefined
                    text: "feels " + IslandState.wxFeels + "\u{00b0}"
                    color: Qt.alpha(root.theme.on_surface_variant, 0.7)
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(9)
                }
            }

            // ── horizontal face ───────────────────────────────
            Column {
                visible: !wTile.vertical
                anchors.centerIn: parent
                spacing: 6

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 12

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: IslandState.wxIcon
                        color: root.theme.primary
                        font.family: root.theme.fontMono
                        font.pixelSize: wTile.ah >= 2 ? 26 : 20
                    }
                    WxCore { anchors.verticalCenter: parent.verticalCenter }
                    // a bigger box earns the conditions the pill keeps on
                    // hover; on one row the hours take that room instead
                    WxExtras {
                        visible: wTile.area >= 4 && !wTile.hoursInline
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    WxHours {
                        visible: wTile.hoursInline
                        anchors.verticalCenter: parent.verticalCenter
                        count: wTile.inlineCount
                    }
                }

                WxHours {
                    visible: wTile.hoursBelow
                    anchors.horizontalCenter: parent.horizontalCenter
                    count: wTile.belowCount
                }
            }

            // ── vertical face ─────────────────────────────────
            Column {
                visible: wTile.vertical
                anchors.centerIn: parent
                spacing: 4

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: IslandState.wxIcon
                    color: root.theme.primary
                    font.family: root.theme.fontMono
                    font.pixelSize: 24
                }
                WxCore { anchors.horizontalCenter: parent.horizontalCenter }
                WxExtras {
                    visible: wTile.area >= 3
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                WxHours {
                    visible: wTile.hoursBelow
                    anchors.horizontalCenter: parent.horizontalCenter
                    count: wTile.belowCount
                }
            }

            HoverHandler { id: wHov; enabled: !root.edit; cursorShape: Qt.PointingHandCursor }
            MouseArea {
                anchors.fill: parent
                enabled: !root.edit
                onClicked: IslandState.openTool("weather", IslandState.toolScreen)
            }
        }
    }

    // ── mouse battery tile ────────────────────────────────────────
    Component {
        id: cBattery
        TileBase {
            id: bTile
            readonly property int aw: wi ? wi.w : 1
            readonly property int ah: wi ? wi.h : 1
            readonly property bool horiz: aw > ah
            color: batHov.hovered && !root.edit ? Qt.alpha(root.theme.fg, 0.12)
                                                : Qt.alpha(root.theme.fg, 0.07)
            Behavior on color { ColorAnimation { duration: 130 } }

            readonly property real pct: root.batDev ? root.batDev.percentage : -1
            readonly property bool charging:
                root.batDev !== null && root.batDev.state === UPowerDeviceState.Charging

            component BatRing: Item {
                property real size: 47
                width: size
                height: size

                RingProgress {
                    anchors.fill: parent
                    symmetric: true
                    progress: Math.max(0, bTile.pct)
                    ring: bTile.charging ? root.theme.success
                        : bTile.pct < 0 ? root.theme.muted
                        : bTile.pct <= 0.2 ? root.theme.warn : root.theme.accent
                    track: root.theme.fg
                    trackAlpha: 0.10
                    thickness: 2.5
                }
                Text {
                    anchors.centerIn: parent
                    text: bTile.pct >= 0 ? Math.round(bTile.pct * 100) : "\u{2014}"
                    color: root.theme.fg
                    font.family: root.theme.fontMono
                    font.pixelSize: 12
                    font.weight: Font.Bold
                }
            }

            // ── wide face: the ring beside its words ──────────
            Row {
                visible: bTile.horiz
                anchors.centerIn: parent
                spacing: 12

                BatRing {
                    anchors.verticalCenter: parent.verticalCenter
                    size: Math.min(bTile.height - 26, 64)
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Text {
                        text: "Mouse"
                        color: root.theme.fg
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(11)
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: root.batDev === null ? "not seen"
                            : bTile.charging ? "charging" : "discharging"
                        color: bTile.charging ? root.theme.success
                                              : Qt.alpha(root.theme.on_surface_variant, 0.75)
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(9)
                    }
                    Text {
                        visible: bTile.aw >= 3 && root.batDev !== null
                        width: bTile.width - bTile.height - 30
                        elide: Text.ElideRight
                        text: root.batDev ? (root.batDev.model || "") : ""
                        color: Qt.alpha(root.theme.on_surface_variant, 0.55)
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(8)
                    }
                }
            }

            // ── stacked face: 1x1, square, portrait ───────────
            Column {
                visible: !bTile.horiz
                anchors.centerIn: parent
                spacing: 4

                BatRing {
                    anchors.horizontalCenter: parent.horizontalCenter
                    // taller boxes spend their extra height on the words
                    // below, so the ring only grows where it genuinely fits
                    size: Math.min(Math.min(bTile.width, bTile.height)
                                   - 26 - (bTile.ah >= 2 ? 24 : 0), 84)
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "mouse"
                    color: Qt.alpha(root.theme.on_surface_variant, 0.8)
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(8)
                }
                Text {
                    visible: bTile.ah >= 2 && root.batDev !== null
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: bTile.charging ? "charging" : "discharging"
                    color: bTile.charging ? root.theme.success : Qt.alpha(root.theme.on_surface_variant, 0.65)
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(9)
                }
                Text {
                    visible: bTile.aw >= 2 && bTile.ah >= 2 && root.batDev !== null
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: bTile.width - 14
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                    text: root.batDev ? (root.batDev.model || "") : ""
                    color: Qt.alpha(root.theme.on_surface_variant, 0.55)
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(8)
                }
            }

            HoverHandler { id: batHov; enabled: !root.edit; cursorShape: Qt.PointingHandCursor }
            MouseArea {
                anchors.fill: parent
                enabled: !root.edit
                onClicked: IslandState.openTool("battery", IslandState.toolScreen)
            }
        }
    }
}
