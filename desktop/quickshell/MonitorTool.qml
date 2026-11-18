import QtQuick
import Quickshell.Io

// The bottom bar's telemetry, given a surface with room: the same scripts,
// polled only while the tool is on screen. Hovering a tile pours its full
// tooltip — the per-core table, the power breakdown — into the detail panel,
// which a 26px bar pill never had space for.
Item {
    id: root

    property var theme

    readonly property real preferredHeight: 360

    readonly property bool showing: IslandState.tool === "monitor"
    readonly property string wb: "@HOME@/.config/quickshell/scripts/"

    // Which tile the detail panel is describing. Sticky on the last hover
    // rather than cleared on exit, so the panel never flashes empty while the
    // pointer travels.
    property int detailIdx: 0

    readonly property var metrics: [
        // Temperature rides along with usage rather than holding a tile of its
        // own: cpu.sh reports both, and its class escalates on either, so a hot
        // idle CPU still colours the tile.
        { label: "CPU",     cmd: root.wb + "cpu.sh",              ms: 3000 },
        { label: "GPU",     cmd: root.wb + "gpu.sh",              ms: 3000 },
        { label: "Power",   cmd: root.wb + "pcpower.sh",          ms: 3000 },
        { label: "Memory",  cmd: root.wb + "mem.sh",              ms: 5000 },
        { label: "Disk /",  cmd: root.wb + "disk.sh / \u{f02ca}", ms: 30000 },
        { label: "Home",    cmd: root.wb + "disk.sh /home \u{f02dc}", ms: 30000 },
        // Empty text is this script's healthy state — made explicit here,
        // where a blank tile would read as broken rather than as calm.
        { label: "Services", cmd: root.wb + "failed-units.sh",     ms: 30000,
          okText: "\u{f0560}  0", okTip: "No failed systemd units (system or user)" },
        // Healthy here is a real answer, not an absence: the tooltip names both
        // drives and their driver either way, so the tile can be read as
        // confirmation before launching a game rather than only as a warning.
        { label: "Drives",  cmd: root.wb + "mounts.sh",           ms: 30000,
          okText: "\u{f02ca}  ok" }
    ]

    // One slot per metric, filled by the tiles as their polls land. Seeded from
    // the last time the tool was open so the tiles carry numbers on the first
    // frame instead of ten "…" placeholders.
    //
    // Keyed by label, not by index. The cache outlives the shell, so an index
    // key means adding or removing one metric silently shifts every tile after
    // it onto its neighbour's last reading until each poll lands — up to a
    // minute for the 30s and 60s scripts. A label key just misses instead.
    property var readings: IslandState.cacheGet("monitor.readings", ({}))

    function ingest(idx, raw) {
        try {
            const j = JSON.parse((raw || "").trim());
            const m = root.metrics[idx];
            const healthy = (j.text || "") === "" && m.okText !== undefined;
            const next = {};
            for (const k in root.readings) next[k] = root.readings[k];
            const tip = String(j.tooltip || "").replace(/<[^>]+>/g, "");
            next[m.label] = {
                text: healthy ? m.okText : (j.text || "—"),
                // okTip is only a stand-in for a script that says nothing when
                // it is happy. One that still reports detail — which drives are
                // mounted, under which driver — keeps its own tooltip.
                tip: healthy && m.okTip !== undefined ? m.okTip : tip,
                cls: j.class || ""
            };
            root.readings = next;
            IslandState.cacheSet("monitor.readings", next);
        } catch (e) { /* keep the last good reading */ }
    }

    function clsColor(cls) {
        if (!cls) return root.theme.fg;
        if (cls.indexOf("crit") !== -1 || cls.indexOf("failed") !== -1) return root.theme.warn;
        if (cls.indexOf("high") !== -1) return root.theme.accent2;
        if (cls.indexOf("stale") !== -1) return root.theme.muted;
        return root.theme.fg;
    }

    Row {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 14

        // ── tiles ─────────────────────────────────────────────────
        Grid {
            id: grid
            columns: 2
            spacing: 6

            Repeater {
                model: root.metrics

                Rectangle {
                    id: tile
                    required property var modelData
                    required property int index
                    readonly property var r: root.readings[modelData.label] || null
                    readonly property bool current: root.detailIdx === index

                    // Narrow enough to leave the detail panel 294px. The widest
                    // line any of these scripts emits is cpu.sh's package row
                    // ("󰉁 package 35.8 W  (cores … · uncore …)") at 288px of
                    // 10px mono; at the old 146 the panel was 242px, so the
                    // power breakdown — the whole reason the panel exists —
                    // was elided mid-line. The widest tile text is 84px, so
                    // the tiles lose nothing.
                    width: 120
                    height: 54
                    radius: 12
                    color: tileHover.hovered ? Qt.alpha(root.theme.fg, 0.11)
                                             : Qt.alpha(root.theme.fg, 0.07)
                    Behavior on color { ColorAnimation { duration: 120 } }

                    // The scripts lead their text with a glyph; it goes in the
                    // hub's disc, filled for the tile whose detail is open, and
                    // the number stands on its own in the display face.
                    readonly property var parts: {
                        const t = tile.r ? String(tile.r.text) : "\u2026";
                        const m = t.match(/^([\uD800-\uDBFF][\uDC00-\uDFFF]|[\uE000-\uF8FF])\s*(.*)$/)
                               || t.match(/^([^\s\w%.\u2026-]+)\s+(.*)$/);
                        return m ? { glyph: m[1], value: m[2] } : { glyph: "", value: t };
                    }

                    Rectangle {
                        id: tDisc
                        anchors.left: parent.left
                        anchors.leftMargin: 9
                        anchors.verticalCenter: parent.verticalCenter
                        width: 28; height: 28; radius: 14
                        color: tile.current ? root.theme.accent : Qt.alpha(root.theme.fg, 0.10)
                        Behavior on color { ColorAnimation { duration: 160 } }
                        Text {
                            anchors.centerIn: parent
                            text: tile.parts.glyph
                            color: tile.current ? Qt.darker(root.theme.accent, 3.4) : Qt.alpha(root.theme.fg, 0.85)
                            font.family: root.theme.fontMono
                            font.pixelSize: 13
                        }
                    }

                    Column {
                        anchors.left: tDisc.right
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0

                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: tile.parts.value
                            color: root.clsColor(tile.r ? tile.r.cls : "")
                            font.family: root.theme.fontDisplay
                            font.features: ({ "tnum": 1 })
                            font.pixelSize: IslandState.ts(14)
                            font.weight: Font.Bold
                        }
                        Text {
                            text: tile.modelData.label
                            color: Qt.alpha(root.theme.on_surface_variant, 0.8)
                            font.family: root.theme.fontSans
                            font.pixelSize: IslandState.ts(9)
                        }
                    }

                    HoverHandler {
                        id: tileHover
                        onHoveredChanged: if (hovered) root.detailIdx = tile.index
                    }

                    // Each tile owns its poll; nothing runs while the card is
                    // closed, and each script keeps the cadence it had on the
                    // bar rather than one shared drumbeat.
                    Process {
                        id: proc
                        command: ["bash", "-c", tile.modelData.cmd]
                        stdout: StdioCollector {
                            onStreamFinished: root.ingest(tile.index, this.text)
                        }
                    }
                    Timer {
                        interval: tile.modelData.ms
                        running: root.showing
                        repeat: true
                        triggeredOnStart: true
                        onTriggered: proc.running = true
                    }
                }
            }
        }


        // ── detail ────────────────────────────────────────────────
        Column {
            width: parent.width - grid.width - 1 - 28
            spacing: 6

            Text {
                text: root.metrics[root.detailIdx].label
                color: root.theme.fg
                font.family: root.theme.fontDisplay
                font.pixelSize: IslandState.ts(15)
                font.weight: Font.Bold
            }

            Text {
                width: parent.width
                text: {
                    const r = root.readings[root.metrics[root.detailIdx].label];
                    return r && r.tip !== "" ? r.tip : "no detail";
                }
                color: Qt.alpha(root.theme.fg, 0.88)
                font.family: root.theme.fontMono
                font.pixelSize: 10
                lineHeight: 1.25
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
                clip: true
            }
        }
    }
}
