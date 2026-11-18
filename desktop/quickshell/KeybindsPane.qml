import QtQuick
import Quickshell
import Quickshell.Io

// Settings → Keybinds. Every Hyprland binding, grouped under a header per
// app or module, each one re-bindable.
//
// The list is not kept here: hypr/binds.lua declares every bind and, each
// time Hyprland loads it, writes what is actually bound to
// keybinds-manifest.json. This page renders that file and writes the user's
// changes to keybinds.json ({ id: keys }, "" = unbound), then reloads
// Hyprland, which re-runs binds.lua with them applied — so what is shown is
// always what is bound.
//
// Profiles: keybind-profiles.json holds named sets of overrides
// ({ active, profiles: { name: { id: keys } } }). "Default" always exists and
// starts as whatever was set before profiles did; the active profile's set is
// the one copied into keybinds.json, so binds.lua never needs to know about
// profiles at all.
//
// Recording a chord: click it, press the new keys. Meanwhile Hyprland sits in
// the empty `keycapture` submap (defined in binds.lua) so no existing bind
// fires and every key reaches this window. Keys are taken by their physical
// position (the XKB keycode), so a chord means the same key on every layout.
Item {
    id: root

    property var theme
    property bool active: false

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/hypr"

    property var groups: []
    property var overrides: ({})
    property var profiles: ({ "Default": {} })
    property string activeProfile: "Default"
    property bool profilesLoaded: false
    property bool naming: false
    readonly property var profileNames: {
        const rest = Object.keys(root.profiles).filter(n => n !== "Default").sort((a, b) => a.localeCompare(b));
        return ["Default"].concat(rest);
    }
    property string capturing: ""

    onActiveChanged: if (!active) root.stopCapture()
    Component.onDestruction: if (root.capturing !== "") Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.submap("reset")'])

    FileView {
        path: root.stateDir + "/keybinds-manifest.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.groups = JSON.parse(text()).groups || []; } catch (e) { root.groups = []; }
        }
    }

    FileView {
        id: overridesFile
        path: root.stateDir + "/keybinds.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.overrides = JSON.parse(text()) || {}; } catch (e) { root.overrides = {}; }
        }
        onLoadFailed: root.overrides = {}
    }

    FileView {
        id: profilesFile
        path: root.stateDir + "/keybind-profiles.json"
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.profiles = d.profiles && d.profiles["Default"] ? d.profiles : { "Default": {} };
                root.activeProfile = root.profiles[d.active] ? d.active : "Default";
            } catch (e) { /* keep the defaults */ }
            root.profilesLoaded = true;
        }
        // First run: whatever was rebound before profiles existed becomes Default.
        onLoadFailed: firstProfiles.start()
    }
    // Wait for keybinds.json to be read, so the seeded Default holds it.
    Timer {
        id: firstProfiles
        interval: 400
        onTriggered: {
            root.profiles = { "Default": Object.assign({}, root.overrides) };
            root.activeProfile = "Default";
            root.profilesLoaded = true;
            root.saveProfiles();
        }
    }
    function saveProfiles() {
        profilesFile.setText(JSON.stringify({ active: root.activeProfile, profiles: root.profiles }, null, 2) + "\n");
    }

    // ── writing ───────────────────────────────────────────────
    function writeOverrides(o) {
        root.overrides = o;
        overridesFile.setText(JSON.stringify(o, null, 2) + "\n");
        const p = Object.assign({}, root.profiles);
        p[root.activeProfile] = Object.assign({}, o);
        root.profiles = p;
        root.saveProfiles();
        reloadTimer.restart();
    }
    function setKeys(item, keys) {
        const o = Object.assign({}, root.overrides);
        if (keys === item.default) delete o[item.id];
        else o[item.id] = keys;
        root.writeOverrides(o);
    }
    function resetAll() { root.writeOverrides({}); }

    function switchProfile(name) {
        if (!root.profiles[name] || name === root.activeProfile) return;
        root.stopCapture();
        root.activeProfile = name;
        root.writeOverrides(Object.assign({}, root.profiles[name]));
    }
    function saveProfileAs(name) {
        name = name.trim();
        if (name === "") return;
        const p = Object.assign({}, root.profiles);
        p[name] = Object.assign({}, root.overrides);
        root.profiles = p;
        root.activeProfile = name;
        root.saveProfiles();
    }
    function deleteProfile(name) {
        if (name === "Default" || !root.profiles[name]) return;
        const p = Object.assign({}, root.profiles);
        delete p[name];
        root.profiles = p;
        if (root.activeProfile === name) {
            root.activeProfile = "Default";
            root.writeOverrides(Object.assign({}, p["Default"]));
        } else {
            root.saveProfiles();
        }
    }
    // A tick after the write, so Hyprland reads the new file.
    Timer {
        id: reloadTimer
        interval: 120
        onTriggered: Quickshell.execDetached(["hyprctl", "reload"])
    }

    // ── capture ───────────────────────────────────────────────
    function startCapture(id) {
        root.capturing = id;
        Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.submap("keycapture")']);
        catcher.forceActiveFocus();
        captureTimeout.restart();
    }
    function stopCapture() {
        if (root.capturing === "") return;
        root.capturing = "";
        captureTimeout.stop();
        Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.submap("reset")']);
    }
    Timer { id: captureTimeout; interval: 12000; onTriggered: root.stopCapture() }

    // XKB keycode (evdev + 8) → the keysym name Hyprland binds, for a US
    // layout. Anything not listed is bound as `code:N`, which Hyprland takes
    // as the same physical key.
    readonly property var codeNames: ({
        10: "1", 11: "2", 12: "3", 13: "4", 14: "5", 15: "6", 16: "7", 17: "8", 18: "9", 19: "0",
        20: "minus", 21: "equal", 23: "Tab",
        24: "Q", 25: "W", 26: "E", 27: "R", 28: "T", 29: "Y", 30: "U", 31: "I", 32: "O", 33: "P",
        34: "bracketleft", 35: "bracketright", 36: "Return",
        38: "A", 39: "S", 40: "D", 41: "F", 42: "G", 43: "H", 44: "J", 45: "K", 46: "L",
        47: "semicolon", 48: "apostrophe", 49: "grave", 51: "backslash",
        52: "Z", 53: "X", 54: "C", 55: "V", 56: "B", 57: "N", 58: "M",
        59: "comma", 60: "period", 61: "slash", 65: "space",
        67: "F1", 68: "F2", 69: "F3", 70: "F4", 71: "F5", 72: "F6", 73: "F7", 74: "F8", 75: "F9", 76: "F10",
        95: "F11", 96: "F12", 104: "KP_Enter", 107: "Print", 110: "Home", 111: "up", 112: "Prior",
        113: "left", 114: "right", 115: "End", 116: "down", 117: "Next", 118: "Insert", 119: "Delete",
        121: "XF86AudioMute", 122: "XF86AudioLowerVolume", 123: "XF86AudioRaiseVolume", 127: "Pause",
        171: "XF86AudioNext", 172: "XF86AudioPlay", 173: "XF86AudioPrev", 174: "XF86AudioStop",
        198: "XF86AudioMicMute", 232: "XF86MonBrightnessDown", 233: "XF86MonBrightnessUp"
    })
    readonly property var modifierCodes: [37, 50, 62, 64, 66, 105, 108, 133, 134]

    function modsOf(m) {
        const out = [];
        if (m & Qt.MetaModifier) out.push("SUPER");
        if (m & Qt.ControlModifier) out.push("CTRL");
        if (m & Qt.AltModifier) out.push("ALT");
        if (m & Qt.ShiftModifier) out.push("SHIFT");
        return out;
    }

    FocusScope {
        id: catcher
        width: 1; height: 1
        Keys.onPressed: event => {
            if (root.capturing === "") return;
            event.accepted = true;
            const code = event.nativeScanCode;
            if (root.modifierCodes.indexOf(code) >= 0) return;
            const mods = root.modsOf(event.modifiers);
            const item = root.itemById(root.capturing);
            if (code === 9 && mods.length === 0) { root.stopCapture(); return; }
            if (code === 22 && mods.length === 0) { root.stopCapture(); if (item) root.setKeys(item, ""); return; }
            const name = root.codeNames[code] || ("code:" + code);
            root.stopCapture();
            if (item) root.setKeys(item, mods.concat([name]).join(" + "));
        }
    }

    function itemById(id) {
        for (let g = 0; g < root.groups.length; g++)
            for (let i = 0; i < root.groups[g].items.length; i++)
                if (root.groups[g].items[i].id === id) return root.groups[g].items[i];
        return null;
    }

    // ── display ───────────────────────────────────────────────
    readonly property var pretty: ({
        "SUPER": "Super", "CTRL": "Ctrl", "ALT": "Alt", "SHIFT": "Shift",
        "Return": "Enter", "KP_Enter": "Num Enter", "space": "Space", "slash": "/", "apostrophe": "'",
        "grave": "`", "minus": "-", "equal": "=", "comma": ",", "period": ".", "semicolon": ";",
        "backslash": "\\", "bracketleft": "[", "bracketright": "]",
        "left": "←", "right": "→", "up": "↑", "down": "↓", "Prior": "Page Up", "Next": "Page Down",
        "XF86AudioRaiseVolume": "Volume up", "XF86AudioLowerVolume": "Volume down",
        "XF86AudioMute": "Mute", "XF86AudioMicMute": "Mic mute", "XF86AudioPlay": "Play",
        "XF86AudioNext": "Next track", "XF86AudioPrev": "Previous track", "XF86AudioStop": "Stop",
        "XF86MonBrightnessUp": "Brightness up", "XF86MonBrightnessDown": "Brightness down"
    })
    function prettyKeys(k) {
        if (k === "") return "Not set";
        return k.split("+").map(s => {
            const t = s.trim();
            return root.pretty[t] || t;
        }).join(" + ");
    }

    // Two entries clash when any chord they produce is the same.
    function norm(k) {
        const parts = k.split("+").map(s => s.trim()).filter(s => s !== "");
        if (parts.length === 0) return "";
        const key = parts.pop().toLowerCase();
        return parts.map(s => s.toUpperCase()).sort().join("+") + "|" + key;
    }
    function chordsOf(item) {
        if (item.kind === "keys") return item.keys === "" ? [] : [root.norm(item.keys)];
        const p = item.keys === "" ? "" : item.keys + " + ";
        if (item.suffix === "1…0") return ["1","2","3","4","5","6","7","8","9","0"].map(d => root.norm(p + d));
        if (item.suffix === "Scroll") return [root.norm(p + "mouse_down"), root.norm(p + "mouse_up")];
        if (item.suffix === "Left drag") return [root.norm(p + "mouse:272")];
        if (item.suffix === "Right drag") return [root.norm(p + "mouse:273")];
        return [];
    }
    readonly property var clashes: {
        const owners = {};
        for (let g = 0; g < root.groups.length; g++)
            for (let i = 0; i < root.groups[g].items.length; i++) {
                const it = root.groups[g].items[i];
                const cs = root.chordsOf(it);
                for (let c = 0; c < cs.length; c++) (owners[cs[c]] = owners[cs[c]] || []).push(it.label);
            }
        const out = {};
        for (let g = 0; g < root.groups.length; g++)
            for (let i = 0; i < root.groups[g].items.length; i++) {
                const it = root.groups[g].items[i];
                const cs = root.chordsOf(it);
                const others = [];
                for (let c = 0; c < cs.length; c++)
                    for (const l of owners[cs[c]]) if (l !== it.label && others.indexOf(l) < 0) others.push(l);
                if (others.length) out[it.id] = others;
            }
        return out;
    }

    readonly property int changedCount: Object.keys(root.overrides).length

    // ── layout ────────────────────────────────────────────────
    Column {
        id: header
        width: parent.width
        spacing: 2

        Item {
            width: parent.width
            height: titleCol.implicitHeight

            Column {
                id: titleCol
                spacing: 2
                Text {
                    text: "Keybinds"
                    color: root.theme.fg
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(13)
                    font.weight: Font.DemiBold
                }
                Text {
                    text: "Profile " + root.activeProfile + " · "
                        + (root.changedCount === 0 ? "all at their defaults" : root.changedCount + " changed from the defaults")
                    color: Qt.alpha(root.theme.on_surface_variant, 0.8)
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(10)
                }
            }

            Rectangle {
                visible: root.changedCount > 0
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: resetAllText.implicitWidth + 20
                height: 28; radius: 10
                color: resetAllHover.hovered ? Qt.alpha(root.theme.on_surface, 0.10) : Qt.alpha(root.theme.on_surface, 0.05)
                Text {
                    id: resetAllText
                    anchors.centerIn: parent
                    text: "Reset all"
                    color: root.theme.on_surface
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(11)
                }
                HoverHandler { id: resetAllHover; cursorShape: Qt.PointingHandCursor }
                MouseArea { anchors.fill: parent; onClicked: root.resetAll() }
            }
        }
    }

    // ── profiles ──────────────────────────────────────────────
    Flow {
        id: profileBar
        anchors.top: header.bottom
        anchors.topMargin: 10
        width: parent.width
        spacing: 4

        Repeater {
            model: root.profileNames
            Rectangle {
                id: pchip
                required property string modelData
                readonly property bool on: modelData === root.activeProfile
                width: pRow.implicitWidth + 20
                height: 28; radius: 10
                color: on ? root.theme.secondary_container
                     : pHover.hovered ? Qt.alpha(root.theme.on_surface, 0.10) : Qt.alpha(root.theme.on_surface, 0.05)
                Row {
                    id: pRow
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: pchip.modelData
                        color: pchip.on ? root.theme.on_secondary_container : root.theme.on_surface
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(11)
                        font.weight: pchip.on ? Font.DemiBold : Font.Normal
                    }
                    Text {
                        visible: pchip.on && pchip.modelData !== "Default"
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u{f0156}"
                        color: delHover.hovered ? root.theme.warn : Qt.alpha(root.theme.on_secondary_container, 0.7)
                        font.family: root.theme.fontMono
                        font.pixelSize: 13
                        HoverHandler { id: delHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.deleteProfile(pchip.modelData) }
                    }
                }
                HoverHandler { id: pHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.switchProfile(pchip.modelData) }
            }
        }

        Rectangle {
            visible: !root.naming
            width: newText.implicitWidth + 20
            height: 28; radius: 10
            color: newHover.hovered ? Qt.alpha(root.theme.on_surface, 0.10) : "transparent"
            border.width: 1
            border.color: Qt.alpha(root.theme.on_surface, 0.15)
            Text {
                id: newText
                anchors.centerIn: parent
                text: "+ Save as new profile"
                color: Qt.alpha(root.theme.on_surface, 0.8)
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(11)
            }
            HoverHandler { id: newHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { root.naming = true; nameInput.text = ""; nameInput.forceActiveFocus(); } }
        }

        Rectangle {
            visible: root.naming
            width: 200
            height: 28; radius: 10
            color: Qt.alpha(root.theme.on_surface, 0.08)
            border.width: 1
            border.color: Qt.alpha(root.theme.primary, 0.5)
            TextInput {
                id: nameInput
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                verticalAlignment: TextInput.AlignVCenter
                color: root.theme.fg
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(11)
                maximumLength: 32
                clip: true
                Text {
                    visible: nameInput.text === ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Profile name, Enter to save"
                    color: Qt.alpha(root.theme.on_surface, 0.4)
                    font: nameInput.font
                }
                Keys.onReturnPressed: { root.saveProfileAs(text); root.naming = false; }
                Keys.onEnterPressed: { root.saveProfileAs(text); root.naming = false; }
                Keys.onEscapePressed: root.naming = false
                onActiveFocusChanged: if (!activeFocus) root.naming = false
            }
        }
    }

    Flickable {
        id: flick
        anchors.top: profileBar.bottom
        anchors.topMargin: 10
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: hint.top
        anchors.bottomMargin: 8
        contentHeight: list.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        ScrollBar { id: bar; flick: flick; theme: root.theme }

        Column {
            id: list
            width: flick.width - (bar.visible ? bar.width + 2 : 0)
            spacing: 6

            Text {
                visible: root.groups.length === 0
                width: parent.width
                wrapMode: Text.WordWrap
                text: "No keybind list yet. It is written by ~/.config/hypr/binds.lua when Hyprland loads it — reload Hyprland (Super + Ctrl + R)."
                color: Qt.alpha(root.theme.on_surface_variant, 0.8)
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(11)
            }

            Repeater {
                model: root.groups

                Column {
                    id: group
                    required property var modelData
                    width: list.width
                    spacing: 6

                    Text {
                        topPadding: 8
                        bottomPadding: 2
                        leftPadding: 4
                        text: group.modelData.name
                        color: root.theme.primary
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(11)
                        font.weight: Font.DemiBold
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 0.6
                    }

                    Repeater {
                        model: group.modelData.items

                        Rectangle {
                            id: row
                            required property var modelData
                            readonly property bool changed: modelData.keys !== modelData.default
                            readonly property var clash: root.clashes[modelData.id] || null
                            readonly property bool recording: root.capturing === modelData.id

                            width: group.width
                            height: row.clash ? 58 : 46
                            radius: 14
                            color: Qt.alpha(root.theme.fg, 0.05)

                            Column {
                                anchors.left: parent.left
                                anchors.leftMargin: 14
                                anchors.right: controls.left
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: row.modelData.label
                                    color: root.theme.fg
                                    font.family: root.theme.fontSans
                                    font.pixelSize: IslandState.ts(12)
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    visible: row.clash !== null
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: row.clash ? "Same keys as: " + row.clash.join(", ") : ""
                                    color: root.theme.warn
                                    font.family: root.theme.fontSans
                                    font.pixelSize: IslandState.ts(10)
                                }
                            }

                            Row {
                                id: controls
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6

                                // reset to default
                                Rectangle {
                                    visible: row.changed
                                    width: 28; height: 28; radius: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: resetHover.hovered ? Qt.alpha(root.theme.on_surface, 0.12) : "transparent"
                                    Text {
                                        anchors.centerIn: parent
                                        text: "\u{f0450}"
                                        color: Qt.alpha(root.theme.on_surface, 0.75)
                                        font.family: root.theme.fontMono
                                        font.pixelSize: 15
                                    }
                                    HoverHandler { id: resetHover; cursorShape: Qt.PointingHandCursor }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: { root.stopCapture(); root.setKeys(row.modelData, row.modelData.default); }
                                    }
                                }

                                // keys: one chip, click to record
                                Rectangle {
                                    visible: row.modelData.kind === "keys"
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.max(96, chipText.implicitWidth + 24)
                                    height: 30; radius: 10
                                    color: row.recording ? root.theme.primary_container
                                         : row.changed ? root.theme.secondary_container
                                         : chipHover.hovered ? Qt.alpha(root.theme.on_surface, 0.12)
                                         : Qt.alpha(root.theme.on_surface, 0.06)
                                    border.width: row.recording ? 1 : 0
                                    border.color: root.theme.primary
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    Text {
                                        id: chipText
                                        anchors.centerIn: parent
                                        text: row.recording ? "Press keys…" : root.prettyKeys(row.modelData.keys)
                                        color: row.recording ? root.theme.on_primary_container
                                             : row.changed ? root.theme.on_secondary_container
                                             : row.modelData.keys === "" ? Qt.alpha(root.theme.on_surface, 0.45)
                                             : root.theme.on_surface
                                        font.family: root.theme.fontMono
                                        font.pixelSize: IslandState.ts(11)
                                    }
                                    HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: row.recording ? root.stopCapture() : root.startCapture(row.modelData.id)
                                    }
                                }

                                // prefix: toggle each modifier, the key part is fixed
                                Repeater {
                                    model: row.modelData.kind === "prefix" ? ["SUPER", "CTRL", "ALT", "SHIFT"] : []
                                    Rectangle {
                                        id: mod
                                        required property string modelData
                                        readonly property var held: row.modelData.keys === "" ? []
                                            : row.modelData.keys.split("+").map(s => s.trim())
                                        readonly property bool on: held.indexOf(modelData) >= 0
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: modText.implicitWidth + 18
                                        height: 30; radius: 10
                                        color: on ? root.theme.secondary_container
                                             : modHover.hovered ? Qt.alpha(root.theme.on_surface, 0.12)
                                             : Qt.alpha(root.theme.on_surface, 0.06)
                                        Text {
                                            id: modText
                                            anchors.centerIn: parent
                                            text: root.pretty[mod.modelData]
                                            color: mod.on ? root.theme.on_secondary_container : Qt.alpha(root.theme.on_surface, 0.6)
                                            font.family: root.theme.fontMono
                                            font.pixelSize: IslandState.ts(11)
                                            font.weight: mod.on ? Font.DemiBold : Font.Normal
                                        }
                                        HoverHandler { id: modHover; cursorShape: Qt.PointingHandCursor }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                const order = ["SUPER", "CTRL", "ALT", "SHIFT"];
                                                const set = mod.held.slice();
                                                const at = set.indexOf(mod.modelData);
                                                if (at >= 0) set.splice(at, 1); else set.push(mod.modelData);
                                                set.sort((a, b) => order.indexOf(a) - order.indexOf(b));
                                                root.stopCapture();
                                                root.setKeys(row.modelData, set.join(" + "));
                                            }
                                        }
                                    }
                                }
                                Text {
                                    visible: row.modelData.kind === "prefix"
                                    anchors.verticalCenter: parent.verticalCenter
                                    leftPadding: 2
                                    width: 78
                                    text: "+ " + row.modelData.suffix
                                    color: Qt.alpha(root.theme.on_surface, 0.6)
                                    font.family: root.theme.fontMono
                                    font.pixelSize: IslandState.ts(11)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Text {
        id: hint
        anchors.bottom: parent.bottom
        width: parent.width
        wrapMode: Text.WordWrap
        text: root.capturing !== ""
            ? "Press the new shortcut · Esc cancels · Backspace removes it · other shortcuts are paused until you finish"
            : "Click a shortcut to record a new one · the arrow restores the default · changes apply at once and survive desktop updates"
        color: Qt.alpha(root.theme.on_surface_variant, 0.55)
        font.family: root.theme.fontMono
        font.pixelSize: 9
    }
}
