import QtQuick
import Quickshell
import Quickshell.Io

// Settings → Displays. Resolution, refresh rate, scale, rotation, order and
// on/off for every connected monitor, saved for good, plus how long the
// screens stay on without input.
//
// The monitors and their modes come from hypr/scripts/monitors.py --json.
// Apply hands the whole layout to monitors.py --apply, which writes
// ~/.config/hypr/displays.lua (the per-machine file hypr/monitors-apply.lua
// loads) and reloads Hyprland. Because a wrong mode can leave a screen black,
// every change has to be confirmed: without "Keep" within 15 seconds,
// monitors.py --revert puts the previous file back.
//
// Positions: drag the monitors in the preview to where they stand on the
// desk. On release a monitor snaps edge to edge against its nearest
// neighbour (never overlapping, aligning tops, bottoms or sides when close),
// so the pointer can always cross between screens. Sizes are logical — scaled
// and rotated — exactly as Hyprland places them. Left to right (then top to
// bottom) is also the workspace order: first 1-10, next 11-20, …
Item {
    id: root

    property var theme
    property bool active: false

    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/scripts/monitors.py"

    // [{ output, name, description, modes, native, enabled, width, height, rate, scale, transform }]
    property var mons: []
    property bool dirty: false
    property int countdown: 0

    onActiveChanged: if (active && !root.dirty && root.countdown === 0) root.refresh()

    function refresh() { listProc.running = true; }

    Process {
        id: listProc
        command: ["python3", root.script, "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                let raw = [];
                try { raw = JSON.parse(this.text); } catch (e) { raw = []; }
                root.mons = raw.map(m => ({
                    output: m.output, name: m.name,
                    description: [m.make, m.model].filter(s => s).join(" ") || m.description || m.name,
                    modes: m.modes, native: m.native,
                    enabled: !m.disabled,
                    width: m.width || m.native.width, height: m.height || m.native.height,
                    rate: m.rate, scale: m.scale, transform: m.transform % 4,
                    x: m.x, y: m.y
                }));
                root.dirty = false;
            }
        }
    }

    // ── editing ───────────────────────────────────────────────
    function update(i, patch) {
        const list = root.mons.slice();
        list[i] = Object.assign({}, list[i], patch);
        root.mons = root.settle(list, i);
        root.dirty = true;
    }

    // ── placement (logical pixels, as Hyprland positions them) ─
    function lw(m) { return Math.round((m.transform % 2 ? m.height : m.width) / m.scale); }
    function lh(m) { return Math.round((m.transform % 2 ? m.width : m.height) / m.scale); }
    function overlaps(a, ax, ay, b) {
        return ax < b.x + root.lw(b) && ax + root.lw(a) > b.x && ay < b.y + root.lh(b) && ay + root.lh(a) > b.y;
    }
    // Where monitor i lands when dropped at (px, py): the nearest spot that
    // touches another monitor edge to edge without overlapping any, with
    // tops / bottoms / sides aligned when they are close. A lone monitor
    // goes to 0,0.
    function snap(list, i, px, py) {
        const me = list[i];
        const w = root.lw(me), h = root.lh(me);
        const others = list.filter((m, j) => j !== i && m.enabled);
        if (others.length === 0) return { x: 0, y: 0 };
        const near = Math.max(w, h) * 0.08;
        const cands = [];
        function along(v, lo, hi, alignA, alignB) {
            v = Math.max(lo, Math.min(hi, v));
            if (Math.abs(v - alignA) < near) return alignA;
            if (Math.abs(v - alignB) < near) return alignB;
            return Math.round(v);
        }
        for (const o of others) {
            const ow = root.lw(o), oh = root.lh(o);
            const yy = along(py, o.y - h + 1, o.y + oh - 1, o.y, o.y + oh - h);
            const xx = along(px, o.x - w + 1, o.x + ow - 1, o.x, o.x + ow - w);
            cands.push({ x: o.x + ow, y: yy }, { x: o.x - w, y: yy }, { x: xx, y: o.y - h }, { x: xx, y: o.y + oh });
        }
        let best = null, bestD = Infinity;
        for (const c of cands) {
            if (others.some(o => root.overlaps(me, c.x, c.y, o))) continue;
            const d = Math.hypot(c.x - px, c.y - py);
            if (d < bestD) { bestD = d; best = c; }
        }
        return best || { x: px, y: py };
    }
    // After a size change, move whoever now overlaps or floats free back
    // against its neighbours, starting from the changed monitor.
    function settle(list, i) {
        const out = list.slice();
        const me = out[i];
        if (me.enabled && out.some((o, j) => j !== i && o.enabled && root.overlaps(me, me.x, me.y, o))) {
            const p = root.snap(out, i, me.x, me.y);
            out[i] = Object.assign({}, me, p);
        }
        for (let j = 0; j < out.length; j++) {
            if (j === i || !out[j].enabled) continue;
            const m = out[j];
            const clash = out.some((o, k) => k !== j && o.enabled && root.overlaps(m, m.x, m.y, o));
            if (clash) out[j] = Object.assign({}, m, root.snap(out, j, m.x, m.y));
        }
        return out;
    }
    // A monitor dropped at (px, py) in logical pixels.
    function place(i, px, py) {
        preview.dragging = false;
        const list = root.mons.slice();
        if (i < 0 || i >= list.length) return;
        list[i] = Object.assign({}, list[i], root.snap(list, i, px, py));
        root.mons = root.normalised(list);
        root.dirty = true;
    }

    // Shift everything so the top-left monitor sits at 0,0.
    function normalised(list) {
        const on = list.filter(m => m.enabled);
        if (on.length === 0) return list;
        const mx = Math.min(...on.map(m => m.x)), my = Math.min(...on.map(m => m.y));
        return list.map(m => Object.assign({}, m, { x: m.x - mx, y: m.y - my }));
    }

    function resolutions(m) {
        const seen = {}, out = [];
        for (const md of m.modes) {
            const k = md.width + "x" + md.height;
            if (!seen[k]) { seen[k] = true; out.push({ width: md.width, height: md.height }); }
        }
        out.sort((a, b) => b.width * b.height - a.width * a.height);
        return out;
    }
    function rates(m) {
        const out = [];
        for (const md of m.modes)
            if (md.width === m.width && md.height === m.height && out.indexOf(md.rate) < 0) out.push(md.rate);
        out.sort((a, b) => b - a);
        return out;
    }
    function scales(m) {
        return [1, 1.25, 1.5, 1.6, 1.75, 2, 2.5, 3].filter(s =>
            Math.abs(m.width / s - Math.round(m.width / s)) < 1e-6 && Math.abs(m.height / s - Math.round(m.height / s)) < 1e-6);
    }
    function pickResolution(i, r) {
        const m = root.mons[i];
        const rs = root.rates({ modes: m.modes, width: r.width, height: r.height });
        const sc = root.scales({ width: r.width, height: r.height });
        root.update(i, {
            width: r.width, height: r.height, rate: rs.length ? rs[0] : m.rate,
            scale: sc.indexOf(m.scale) >= 0 ? m.scale : 1
        });
    }
    function sameRate(a, b) { return Math.abs(a - b) < 0.05; }

    // ── applying ──────────────────────────────────────────────
    function layout() {
        const out = [];
        for (const m of root.normalised(root.mons)) {
            if (!m.enabled) { out.push({ output: m.output, disabled: true }); continue; }
            out.push({
                output: m.output,
                mode: m.width + "x" + m.height + "@" + m.rate.toFixed(2),
                position: m.x + "x" + m.y, scale: m.scale, transform: m.transform
            });
        }
        return out;
    }
    readonly property int enabledCount: root.mons.filter(m => m.enabled).length

    function apply() {
        if (root.enabledCount === 0) return;
        applyProc.command = ["bash", "-c", 'printf "%s" "$1" | python3 "$2" --apply', "_",
                             JSON.stringify(root.layout()), root.script];
        applyProc.running = true;
    }
    Process {
        id: applyProc
        onExited: code => {
            if (code !== 0) return;
            root.dirty = false;
            root.countdown = 15;
            confirmTimer.restart();
        }
    }
    Timer {
        id: confirmTimer
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown -= 1;
            if (root.countdown <= 0) root.revert();
        }
    }
    function keep() {
        confirmTimer.stop();
        root.countdown = 0;
        Quickshell.execDetached(["rm", "-f", (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/hypr/displays.lua.previous"]);
        root.refresh();
    }
    function revert() {
        confirmTimer.stop();
        root.countdown = 0;
        revertProc.running = true;
    }
    Process {
        id: revertProc
        command: ["python3", root.script, "--revert"]
        onExited: refreshLater.restart()
    }
    Timer { id: refreshLater; interval: 1200; onTriggered: root.refresh() }

    // ── layout ────────────────────────────────────────────────
    Column {
        id: header
        width: parent.width
        spacing: 2
        Text {
            text: "Displays"
            color: root.theme.fg
            font.family: root.theme.fontSans
            font.pixelSize: IslandState.ts(13)
            font.weight: Font.DemiBold
        }
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.mons.length === 1 ? "1 monitor"
                : root.mons.length + " monitors · drag them to where they stand on your desk · workspaces go left to right (1–10, 11–20, …)"
            color: Qt.alpha(root.theme.on_surface_variant, 0.8)
            font.family: root.theme.fontSans
            font.pixelSize: IslandState.ts(10)
        }
    }

    // Screens off: how long without pointer or keyboard input before every
    // monitor goes dark. Applies at once, no Apply / Keep needed. The unit is
    // the pane's own choice, so 90 sec stays 90 sec instead of turning into
    // 1.5 min; on open it starts from the largest unit that fits evenly.
    readonly property var units: [ { id: "s", label: "sec", k: 1 }, { id: "m", label: "min", k: 60 }, { id: "h", label: "h", k: 3600 } ]
    property string offUnit: {
        const v = IslandState.cfg.screenOffSecs;
        return v % 3600 === 0 ? "h" : v % 60 === 0 ? "m" : "s";
    }
    function unitK(u) { return u === "h" ? 3600 : u === "m" ? 60 : 1; }
    function setScreenOff(amount, unit) {
        const n = Math.round(Number(amount));
        if (!(n > 0)) { offInput.text = String(IslandState.cfg.screenOffSecs / root.unitK(root.offUnit)); return; }
        root.offUnit = unit;
        IslandState.setPref("screenOffSecs", Math.max(5, Math.min(86400, n * root.unitK(unit))));
    }

    Rectangle {
        id: screenOffCard
        anchors.top: header.bottom
        anchors.topMargin: 10
        width: parent.width
        height: 56
        radius: 14
        color: Qt.alpha(root.theme.fg, 0.05)

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.right: offControls.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Text {
                text: "Turn screens off"
                color: root.theme.fg
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(12)
                font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: IslandState.cfg.screenOff ? "After this long without mouse or keyboard input · audio postpones it"
                                                : "Never · screens stay on"
                color: Qt.alpha(root.theme.on_surface_variant, 0.85)
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(10)
            }
        }

        Row {
            id: offControls
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: IslandState.cfg.screenOff
                width: 56; height: 28; radius: 10
                color: Qt.alpha(root.theme.on_surface, offInput.activeFocus ? 0.12 : 0.07)
                border.width: offInput.activeFocus ? 1 : 0
                border.color: Qt.alpha(root.theme.primary, 0.7)
                TextInput {
                    id: offInput
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    verticalAlignment: TextInput.AlignVCenter
                    horizontalAlignment: TextInput.AlignHCenter
                    text: String(IslandState.cfg.screenOffSecs / root.unitK(root.offUnit))
                    validator: IntValidator { bottom: 1; top: 86400 }
                    color: root.theme.fg
                    selectionColor: Qt.alpha(root.theme.primary, 0.4)
                    selectByMouse: true
                    font.family: root.theme.fontMono
                    font.pixelSize: IslandState.ts(11)
                    clip: true
                    onEditingFinished: root.setScreenOff(text, root.offUnit)
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.IBeamCursor
                    onClicked: { offInput.forceActiveFocus(); offInput.selectAll(); }
                }
            }
            Repeater {
                model: IslandState.cfg.screenOff ? root.units : []
                Chip {
                    required property var modelData
                    anchors.verticalCenter: parent.verticalCenter
                    label: modelData.label
                    on: root.offUnit === modelData.id
                    onPicked: root.setScreenOff(offInput.text, modelData.id)
                }
            }
            ToggleSwitch {
                anchors.verticalCenter: parent.verticalCenter
                theme: root.theme
                checked: IslandState.cfg.screenOff
                onToggled: IslandState.setPref("screenOff", !IslandState.cfg.screenOff)
            }
        }
    }

    // arrangement: drag monitors where they stand on the desk; they snap
    // edge to edge on release
    Item {
        id: preview
        anchors.top: screenOffCard.bottom
        anchors.topMargin: 10
        width: parent.width
        height: 140

        // the view's scale and origin are frozen while dragging, so the
        // canvas does not rescale under the pointer
        property bool dragging: false
        property var frozen: null
        readonly property var view: {
            if (preview.dragging && preview.frozen) return preview.frozen;
            const on = root.mons.filter(m => m.enabled);
            if (on.length === 0) return { k: 1, ox: 0, oy: 0 };
            const x0 = Math.min(...on.map(m => m.x)), y0 = Math.min(...on.map(m => m.y));
            const x1 = Math.max(...on.map(m => m.x + root.lw(m))), y1 = Math.max(...on.map(m => m.y + root.lh(m)));
            const k = Math.min((width - 40) / Math.max(1, x1 - x0), (height - 20) / Math.max(1, y1 - y0)) * 0.9;
            return { k: k, ox: (width - (x1 - x0) * k) / 2 - x0 * k, oy: (height - (y1 - y0) * k) / 2 - y0 * k };
        }

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: Qt.alpha(root.theme.fg, 0.03)
        }

        Repeater {
            model: root.mons
            Rectangle {
                id: box
                required property var modelData
                required property int index
                visible: modelData.enabled
                x: preview.view.ox + modelData.x * preview.view.k
                y: preview.view.oy + modelData.y * preview.view.k
                z: drag.active ? 2 : 1
                width: root.lw(modelData) * preview.view.k
                height: root.lh(modelData) * preview.view.k
                radius: 6
                color: Qt.alpha(root.theme.primary, drag.active ? 0.30 : boxHover.hovered ? 0.22 : 0.16)
                border.width: 1
                border.color: Qt.alpha(root.theme.primary, drag.active ? 0.9 : 0.55)
                Text {
                    anchors.centerIn: parent
                    text: box.modelData.name
                    color: root.theme.fg
                    font.family: root.theme.fontMono
                    font.pixelSize: IslandState.ts(10)
                }
                HoverHandler { id: boxHover; cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor }
                DragHandler {
                    id: drag
                    enabled: root.countdown === 0 && root.mons.filter(m => m.enabled).length > 1
                    onActiveChanged: {
                        if (active) {
                            preview.frozen = preview.view;
                            preview.dragging = true;
                            return;
                        }
                        const v = preview.frozen;
                        const i = box.index;
                        const px = (box.x - v.ox) / v.k, py = (box.y - v.oy) / v.k;
                        // Replacing the model destroys this delegate, so the
                        // move runs from the page once this handler returns.
                        Qt.callLater(() => root.place(i, px, py));
                    }
                }
            }
        }
    }

    Flickable {
        id: flick
        anchors.top: preview.bottom
        anchors.topMargin: 10
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footer.top
        anchors.bottomMargin: 8
        contentHeight: cards.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        ScrollBar { id: bar; flick: flick; theme: root.theme }

        Column {
            id: cards
            width: flick.width - (bar.visible ? bar.width + 2 : 0)
            spacing: 8

            Text {
                visible: root.mons.length === 0
                text: "No monitors reported by Hyprland."
                color: Qt.alpha(root.theme.on_surface_variant, 0.8)
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(11)
            }

            Repeater {
                model: root.mons

                Rectangle {
                    id: card
                    required property var modelData
                    required property int index
                    width: cards.width
                    height: body.implicitHeight + 24
                    radius: 14
                    color: Qt.alpha(root.theme.fg, 0.05)

                    Column {
                        id: body
                        x: 14; y: 12
                        width: parent.width - 28
                        spacing: 8

                        // title row: number, name, model · move · on/off
                        Item {
                            width: parent.width
                            height: 30
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                Text {
                                    text: card.modelData.name
                                    color: root.theme.fg
                                    font.family: root.theme.fontSans
                                    font.pixelSize: IslandState.ts(12)
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    text: card.modelData.description
                                    color: Qt.alpha(root.theme.on_surface_variant, 0.85)
                                    font.family: root.theme.fontSans
                                    font.pixelSize: IslandState.ts(10)
                                }
                            }
                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6
                                ToggleSwitch {
                                    anchors.verticalCenter: parent.verticalCenter
                                    theme: root.theme
                                    checked: card.modelData.enabled
                                    enabled: !card.modelData.enabled || root.enabledCount > 1
                                    opacity: enabled ? 1 : 0.4
                                    onToggled: root.update(card.index, { enabled: !card.modelData.enabled })
                                }
                            }
                        }

                        Column {
                            visible: card.modelData.enabled
                            width: parent.width
                            spacing: 8

                            Setting {
                                label: "Resolution"
                                Repeater {
                                    model: root.resolutions(card.modelData)
                                    Chip {
                                        required property var modelData
                                        label: modelData.width + "×" + modelData.height
                                            + (modelData.width === card.modelData.native.width && modelData.height === card.modelData.native.height ? "  native" : "")
                                        on: modelData.width === card.modelData.width && modelData.height === card.modelData.height
                                        onPicked: root.pickResolution(card.index, modelData)
                                    }
                                }
                            }
                            Setting {
                                label: "Refresh rate"
                                Repeater {
                                    model: root.rates(card.modelData)
                                    Chip {
                                        required property real modelData
                                        label: (Math.abs(modelData - Math.round(modelData)) < 0.05 ? Math.round(modelData) : modelData.toFixed(2)) + " Hz"
                                        on: root.sameRate(modelData, card.modelData.rate)
                                        onPicked: root.update(card.index, { rate: modelData })
                                    }
                                }
                            }
                            Setting {
                                label: "Scale"
                                Repeater {
                                    model: root.scales(card.modelData)
                                    Chip {
                                        required property real modelData
                                        label: Math.round(modelData * 100) + "%"
                                        on: Math.abs(modelData - card.modelData.scale) < 0.01
                                        onPicked: root.update(card.index, { scale: modelData })
                                    }
                                }
                            }
                            Setting {
                                label: "Rotation"
                                Repeater {
                                    model: [0, 1, 2, 3]
                                    Chip {
                                        required property int modelData
                                        label: (modelData * 90) + "°"
                                        on: modelData === card.modelData.transform
                                        onPicked: root.update(card.index, { transform: modelData })
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // footer: apply / undo, or the keep-or-revert question
    Item {
        id: footer
        anchors.bottom: parent.bottom
        width: parent.width
        height: 36

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - buttons.width - 12
            wrapMode: Text.WordWrap
            text: root.countdown > 0 ? "Keep these display settings? Reverting in " + root.countdown + " s"
                : root.dirty ? "Not applied yet"
                : "Saved for this set of monitors · a different set gets its own layout"
            color: root.countdown > 0 ? root.theme.fg : Qt.alpha(root.theme.on_surface_variant, 0.6)
            font.family: root.countdown > 0 ? root.theme.fontSans : root.theme.fontMono
            font.pixelSize: root.countdown > 0 ? IslandState.ts(11) : 9
        }
        Row {
            id: buttons
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Chip { visible: root.countdown > 0; label: "Revert"; onPicked: root.revert() }
            Chip { visible: root.countdown > 0; label: "Keep"; on: true; onPicked: root.keep() }
            Chip { visible: root.countdown === 0 && root.dirty; label: "Undo"; onPicked: root.refresh() }
            Chip { visible: root.countdown === 0; label: "Apply"; on: root.dirty; enabled: root.dirty && !applyProc.running; onPicked: root.apply() }
        }
    }

    // ── small pieces ──────────────────────────────────────────
    component Chip: Rectangle {
        id: chip
        property string label: ""
        property bool on: false
        property bool mono: false
        signal picked()
        width: chipText.implicitWidth + 20
        height: 28; radius: 10
        opacity: enabled ? 1 : 0.35
        color: on ? root.theme.secondary_container
             : (hover.hovered && enabled ? Qt.alpha(root.theme.on_surface, 0.10) : Qt.alpha(root.theme.on_surface, 0.05))
        Behavior on color { ColorAnimation { duration: 120 } }
        Text {
            id: chipText
            anchors.centerIn: parent
            text: chip.label
            color: chip.on ? root.theme.on_secondary_container : root.theme.on_surface
            font.family: chip.mono ? root.theme.fontMono : root.theme.fontSans
            font.pixelSize: chip.mono ? 15 : IslandState.ts(11)
            font.weight: chip.on ? Font.DemiBold : Font.Normal
        }
        HoverHandler { id: hover; cursorShape: chip.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
        MouseArea { anchors.fill: parent; enabled: chip.enabled; onClicked: chip.picked() }
    }

    component Setting: Row {
        id: setting
        property string label: ""
        default property alias chips: flow.data
        width: parent ? parent.width : 0
        spacing: 10
        Text {
            width: 92
            height: 28
            verticalAlignment: Text.AlignVCenter
            text: setting.label
            color: Qt.alpha(root.theme.on_surface_variant, 0.9)
            font.family: root.theme.fontSans
            font.pixelSize: IslandState.ts(11)
        }
        Flow {
            id: flow
            width: setting.width - 102
            spacing: 4
        }
    }
}
