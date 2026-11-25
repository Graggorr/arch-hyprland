import QtQuick
import Quickshell.Io

// The displays panel — every monitor Hyprland can see, with the knobs the
// compositor actually owns: mode (resolution + refresh), scale, VRR and HDR
// per display, plus hyprsunset's nightlight for the lot. Changes go through
// `hyprctl eval 'hl.monitor(...)'`, which is RUNTIME ONLY — the boot default
// stays whatever hyprland.lua says, so a wrong click never survives a
// restart. Brightness is absent on purpose: these panels speak DDC and
// ddcutil is not installed; the tile for it can grow here the day it is.
//
// HDR capability is the one thing the compositor will not report: the monitor
// JSON carries the CURRENT colour state (colorManagementPreset, sdrBrightness)
// but no "this panel can do it" flag, so scripts/hdr-capable.sh reads the EDID
// instead. On these two ~400-nit edge-lit panels HDR buys gamut and 10-bit
// gradients, not contrast, and SDR content goes dim under it — hence the SDR
// brightness row appearing with the switch rather than a bare on/off.
Item {
    id: root

    property var theme

    readonly property real preferredHeight: col.implicitHeight + 36

    // name, description, current mode pieces, availableModes, scale, x/y, vrr,
    // hdr and the sdr brightness riding with it
    property var mons: []

    readonly property string capScript:
        "@HOME@/.config/quickshell/scripts/hdr-capable.sh"

    // { "DP-2": { hdr: true, nits: 366, bpc: 10 } }, from the EDID.
    property var hdrCaps: ({})
    // False only when edid-decode is missing, which makes capability UNKNOWN
    // rather than absent. The switch stays live in that case: a toggle that
    // works beats one greyed out for a reason the user cannot see.
    property bool hdrProbeOk: true

    function hdrCapable(name) {
        if (!root.hdrProbeOk) return true;
        const c = root.hdrCaps[name];
        return !!(c && c.hdr);
    }
    function hdrNote(name) {
        const c = root.hdrCaps[name];
        if (!c || !c.hdr)
            return root.hdrProbeOk ? "HDR not advertised by this panel"
                                   : "HDR capability unknown";
        return "HDR10 \u{00b7} PQ \u{00b7} ~" + c.nits + " nits \u{00b7} " + c.bpc + "-bit";
    }

    function reload() {
        monProc.running = true;
        capProc.running = true;
        nlCheck.running = true;
    }

    Process {
        id: capProc
        command: [root.capScript]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const js = JSON.parse(this.text.trim());
                    root.hdrProbeOk = js.probe === "ok";
                    root.hdrCaps = js.caps || ({});
                } catch (e) { /* keep the last good reading */ }
            }
        }
    }

    Process {
        id: monProc
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const js = JSON.parse(this.text.trim());
                    const out = [];
                    for (let i = 0; i < js.length; i++) {
                        const m = js[i];
                        const seen = {};
                        const modes = [];
                        const av = m.availableModes || [];
                        for (let k = 0; k < av.length; k++) {
                            const s = String(av[k]).replace(/Hz$/, "");
                            if (!seen[s]) { seen[s] = true; modes.push(s); }
                        }
                        out.push({
                            name: m.name,
                            desc: (m.description || "").replace(/^GIGA-BYTE TECHNOLOGY CO\.,? LTD\.?\s*/i, ""),
                            w: m.width, h: m.height, rr: m.refreshRate,
                            scale: m.scale, x: m.x, y: m.y,
                            vrr: m.vrr === true,
                            hdr: m.colorManagementPreset === "hdr"
                                 || m.colorManagementPreset === "hdredid",
                            sdrb: m.sdrBrightness === undefined
                                  ? 1.0 : m.sdrBrightness,
                            focused: m.focused === true,
                            modes: modes
                        });
                    }
                    root.mons = out;
                } catch (e) { /* keep the last good reading */ }
            }
        }
    }

    // A settle beat between applying and re-reading: the compositor reports
    // the old mode for a frame or two while the change lands.
    Timer { id: reread; interval: 400; onTriggered: monProc.running = true }

    Process { id: applyProc }
    // Always the full spec — output, mode, position, scale, vrr AND the colour
    // fields — because a spec that omits a field can reset it, and "change the
    // refresh rate" must never re-position a monitor or drop it out of HDR as a
    // side effect. Every caller therefore passes the current hdr/sdrb through.
    //
    // Off is cm = "auto" rather than "srgb": auto is the compiled-in default, so
    // switching HDR off restores exactly the state hyprland.lua boots into.
    function apply(mon, mode, scale, vrr, hdr, sdrb) {
        const spec = 'hl.monitor({ output = "' + mon.name + '"'
                   + ', mode = "' + mode + '"'
                   + ', position = "' + mon.x + 'x' + mon.y + '"'
                   + ', scale = ' + scale
                   + ', vrr = ' + (vrr ? 1 : 0)
                   + ', bitdepth = ' + (hdr ? 10 : 8)
                   + ', cm = "' + (hdr ? 'hdr' : 'auto') + '"'
                   + ', sdrbrightness = ' + (hdr ? Number(sdrb).toFixed(2) : '1.0')
                   + ', sdrsaturation = ' + (hdr ? '0.98' : '1.0') + ' })';
        applyProc.command = ["hyprctl", "eval", spec];
        applyProc.running = true;
        reread.restart();
    }

    function modeLabel(s) {
        const m = String(s).match(/^(\d+)x(\d+)@([\d.]+)/);
        if (!m) return s;
        const rr = parseFloat(m[3]);
        const rrs = Math.abs(rr - Math.round(rr)) < 0.05
                    ? String(Math.round(rr)) : rr.toFixed(1);
        return m[1] + "\u{00d7}" + m[2] + " @ " + rrs;
    }
    function isCurrent(mon, s) {
        const m = String(s).match(/^(\d+)x(\d+)@([\d.]+)/);
        if (!m) return false;
        return parseInt(m[1]) === mon.w && parseInt(m[2]) === mon.h
            && Math.abs(parseFloat(m[3]) - mon.rr) < 0.5;
    }

    // ── nightlight ────────────────────────────────────────────────
    // hyprsunset is not a daemon anyone starts at login here; the switch owns
    // its lifetime. Temperature rides hyprland's IPC forwarding while it
    // runs. Session state — like the runtime monitor spec, deliberately not
    // persisted anywhere.
    property bool nlOn: false
    property real nlTemp: 4500

    Process {
        id: nlCheck
        command: ["pgrep", "-x", "hyprsunset"]
        stdout: StdioCollector {
            onStreamFinished: root.nlOn = this.text.trim() !== ""
        }
    }
    Process { id: nlCtl }
    function nlToggle() {
        if (root.nlOn) {
            nlCtl.command = ["pkill", "-x", "hyprsunset"];
            root.nlOn = false;
        } else {
            nlCtl.command = ["setsid", "-f", "hyprsunset", "-t", String(Math.round(root.nlTemp))];
            root.nlOn = true;
        }
        nlCtl.running = true;
        IslandState.nightOn = root.nlOn;
    }
    Process { id: nlTempProc }
    function nlSetTemp(t) {
        root.nlTemp = t;
        if (!root.nlOn) return;
        nlTempProc.command = ["hyprctl", "hyprsunset", "temperature", String(Math.round(t))];
        nlTempProc.running = true;
    }

    Column {
        id: col
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 18
        spacing: 10

        Repeater {
            model: root.mons

            Column {
                id: monCol
                required property var modelData
                width: col.width
                spacing: 8

                // ── one display ───────────────────────────────────
                Rectangle {
                    width: parent.width
                    height: 46
                    radius: 12
                    color: Qt.alpha(root.theme.fg, 0.05)

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 9
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\u{f0379}"
                            color: monCol.modelData.focused ? root.theme.accent
                                                            : Qt.alpha(root.theme.muted, 0.8)
                            font.family: root.theme.fontMono
                            font.pixelSize: 15
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1
                            Text {
                                text: monCol.modelData.name
                                      + (monCol.modelData.focused ? "  ·  focused" : "")
                                color: root.theme.fg
                                font.family: root.theme.fontSans
                                font.pixelSize: IslandState.ts(12)
                                font.weight: Font.DemiBold
                            }
                            Text {
                                width: 300
                                elide: Text.ElideRight
                                text: monCol.modelData.desc
                                color: Qt.alpha(root.theme.muted, 0.9)
                                font.family: root.theme.fontSans
                                font.pixelSize: IslandState.ts(9)
                            }
                            // What the panel itself claims, so the switch being
                            // dead — or the contrast being unremarkable when it
                            // is not — reads as a property of the hardware.
                            Text {
                                width: 300
                                elide: Text.ElideRight
                                text: root.hdrNote(monCol.modelData.name)
                                color: monCol.modelData.hdr
                                       ? Qt.alpha(root.theme.accent, 0.9)
                                       : Qt.alpha(root.theme.muted, 0.55)
                                font.family: root.theme.fontMono
                                font.pixelSize: 8
                            }
                        }
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "HDR"
                            color: root.hdrCapable(monCol.modelData.name)
                                   ? Qt.alpha(root.theme.muted, 0.9)
                                   : Qt.alpha(root.theme.muted, 0.35)
                            font.family: root.theme.fontSans
                            font.pixelSize: IslandState.ts(10)
                            font.weight: Font.DemiBold
                        }
                        ToggleSwitch {
                            anchors.verticalCenter: parent.verticalCenter
                            theme: root.theme
                            // enabled propagates to the MouseArea inside, so an
                            // incapable panel cannot be switched at all.
                            enabled: root.hdrCapable(monCol.modelData.name)
                            opacity: enabled ? 1.0 : 0.35
                            checked: monCol.modelData.hdr
                            // Floor the SDR multiplier at 1.2 when switching
                            // ON, or HDR's first impression is every ordinary
                            // window going dim. Only the switch does this —
                            // the chips below and the other knobs pass sdrb
                            // through untouched, so an explicit 100% sticks.
                            // On switching OFF the value is ignored; apply()
                            // writes 1.0 with cm = auto.
                            onToggled: root.apply(monCol.modelData,
                                                  monCol.modelData.w + "x" + monCol.modelData.h
                                                  + "@" + monCol.modelData.rr.toFixed(2),
                                                  monCol.modelData.scale,
                                                  monCol.modelData.vrr,
                                                  !monCol.modelData.hdr,
                                                  Math.max(monCol.modelData.sdrb, 1.2))
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "VRR"
                            color: Qt.alpha(root.theme.muted, 0.9)
                            font.family: root.theme.fontSans
                            font.pixelSize: IslandState.ts(10)
                            font.weight: Font.DemiBold
                        }
                        ToggleSwitch {
                            anchors.verticalCenter: parent.verticalCenter
                            theme: root.theme
                            checked: monCol.modelData.vrr
                            onToggled: root.apply(monCol.modelData,
                                                  monCol.modelData.w + "x" + monCol.modelData.h
                                                  + "@" + monCol.modelData.rr.toFixed(2),
                                                  monCol.modelData.scale,
                                                  !monCol.modelData.vrr,
                                                  monCol.modelData.hdr,
                                                  monCol.modelData.sdrb)
                        }
                    }
                }

                // ── sdr brightness ────────────────────────────────
                // Mapping SDR into an HDR curve leaves ordinary windows dim;
                // this is the multiplier that pulls them back. Chips rather
                // than a slider because it wants setting once per panel, and
                // the two panels here do not want the same number.
                Flow {
                    width: parent.width
                    spacing: 5
                    visible: monCol.modelData.hdr

                    Text {
                        height: 26
                        verticalAlignment: Text.AlignVCenter
                        rightPadding: 6
                        text: "SDR brightness"
                        color: Qt.alpha(root.theme.muted, 0.9)
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(10)
                    }
                    Repeater {
                        model: [1.0, 1.2, 1.4, 1.6]
                        Rectangle {
                            id: sdrChip
                            required property var modelData
                            readonly property bool on:
                                Math.abs(monCol.modelData.sdrb - modelData) < 0.01
                            width: sdrText.implicitWidth + 16
                            height: 26; radius: 9
                            color: on ? Qt.alpha(root.theme.accent, 0.24)
                                 : (sdrHov.hovered ? Qt.alpha(root.theme.fg, 0.12)
                                                   : Qt.alpha(root.theme.fg, 0.05))
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text {
                                id: sdrText
                                anchors.centerIn: parent
                                text: Math.round(sdrChip.modelData * 100) + "%"
                                color: sdrChip.on ? root.theme.accent : root.theme.fg
                                font.family: root.theme.fontMono
                                font.pixelSize: 10
                            }
                            HoverHandler { id: sdrHov; cursorShape: Qt.PointingHandCursor }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.apply(monCol.modelData,
                                                      monCol.modelData.w + "x" + monCol.modelData.h
                                                      + "@" + monCol.modelData.rr.toFixed(2),
                                                      monCol.modelData.scale,
                                                      monCol.modelData.vrr,
                                                      true,
                                                      sdrChip.modelData)
                            }
                        }
                    }
                }

                // ── scale ─────────────────────────────────────────
                Flow {
                    width: parent.width
                    spacing: 5

                    Text {
                        height: 26
                        verticalAlignment: Text.AlignVCenter
                        rightPadding: 6
                        text: "Scale"
                        color: Qt.alpha(root.theme.muted, 0.9)
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(10)
                    }
                    Repeater {
                        model: [1.0, 1.25, 1.5, 1.75, 2.0]
                        Rectangle {
                            id: scChip
                            required property var modelData
                            readonly property bool on:
                                Math.abs(monCol.modelData.scale - modelData) < 0.01
                            width: scText.implicitWidth + 16
                            height: 26; radius: 9
                            color: on ? Qt.alpha(root.theme.accent, 0.24)
                                 : (scHov.hovered ? Qt.alpha(root.theme.fg, 0.12)
                                                  : Qt.alpha(root.theme.fg, 0.05))
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text {
                                id: scText
                                anchors.centerIn: parent
                                text: Math.round(scChip.modelData * 100) + "%"
                                color: scChip.on ? root.theme.accent : root.theme.fg
                                font.family: root.theme.fontMono
                                font.pixelSize: 10
                            }
                            HoverHandler { id: scHov; cursorShape: Qt.PointingHandCursor }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.apply(monCol.modelData,
                                                      monCol.modelData.w + "x" + monCol.modelData.h
                                                      + "@" + monCol.modelData.rr.toFixed(2),
                                                      scChip.modelData,
                                                      monCol.modelData.vrr,
                                                      monCol.modelData.hdr,
                                                      monCol.modelData.sdrb)
                            }
                        }
                    }
                }

                // ── modes ─────────────────────────────────────────
                Flow {
                    width: parent.width
                    spacing: 5

                    Repeater {
                        model: monCol.modelData.modes

                        Rectangle {
                            id: modeChip
                            required property string modelData
                            readonly property bool on: root.isCurrent(monCol.modelData, modelData)
                            width: modeText.implicitWidth + 16
                            height: 26; radius: 9
                            color: on ? Qt.alpha(root.theme.accent, 0.24)
                                 : (modeHov.hovered ? Qt.alpha(root.theme.fg, 0.12)
                                                    : Qt.alpha(root.theme.fg, 0.05))
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text {
                                id: modeText
                                anchors.centerIn: parent
                                text: root.modeLabel(modeChip.modelData)
                                color: modeChip.on ? root.theme.accent : root.theme.fg
                                font.family: root.theme.fontMono
                                font.pixelSize: 10
                            }
                            HoverHandler { id: modeHov; cursorShape: Qt.PointingHandCursor }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.apply(monCol.modelData, modeChip.modelData,
                                                      monCol.modelData.scale,
                                                      monCol.modelData.vrr,
                                                      monCol.modelData.hdr,
                                                      monCol.modelData.sdrb)
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Qt.alpha(root.theme.fg, 0.08)
                }
            }
        }

        // ── nightlight ────────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: 46
            radius: 12
            color: Qt.alpha(root.theme.fg, 0.05)

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 9
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{f0594}"
                    color: root.nlOn ? root.theme.accent2 : Qt.alpha(root.theme.muted, 0.8)
                    font.family: root.theme.fontMono
                    font.pixelSize: 15
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Text {
                        text: "Night light"
                        color: root.theme.fg
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(12)
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: "hyprsunset · every display"
                        color: Qt.alpha(root.theme.muted, 0.9)
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(9)
                    }
                }
            }

            ToggleSwitch {
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                theme: root.theme
                checked: root.nlOn
                onToggled: root.nlToggle()
            }
        }

        ControlSlider {
            visible: root.nlOn
            width: parent.width
            theme: root.theme
            glyph: "\u{f18d7}"
            label: "Temperature"
            value: (6500 - root.nlTemp) / 4000
            valueText: Math.round(root.nlTemp) + "K"
            onMoved: (v) => root.nlSetTemp(6500 - v * 4000)
        }

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Runtime only — the boot layout stays whatever hyprland.lua says, so nothing here can survive a restart wrong."
            color: Qt.alpha(root.theme.muted, 0.6)
            font.family: root.theme.fontMono
            font.pixelSize: 9
        }
    }
}
