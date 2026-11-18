import QtQuick
import Quickshell.Io
import Quickshell.Services.Pipewire

// The audio panel — the sound half of the old control tool, now a drill-in
// from the hub's sound slider. Sliders for the defaults, then the full
// output/input device lists (always open here: picking devices is the whole
// reason to drill in), then the pwvucontrol escape hatch and, where a
// backlight exists, brightness.
Item {
    id: root

    property var theme

    readonly property real preferredHeight: col.implicitHeight + 36

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var sinkAudio: sink ? sink.audio : null
    readonly property var srcAudio: source ? source.audio : null

    // Outputs are listed in a fixed preference order, not the order Pipewire
    // happens to register them in — that one is arbitrary and reshuffles every
    // time a device appears or drops, so the entry under the cursor moved. The
    // order is IslandState's, the same table the machine routes by when a
    // device connects, so the list and the automatic choice never disagree.
    // Anything unlisted sorts after the known devices, alphabetically.
    //
    // Devices, not streams: isStream is an application's playback or capture,
    // which has no business in a "where does sound go" list.
    function audioNodes(wantSink) {
        const out = [];
        const ns = Pipewire.nodes ? Pipewire.nodes.values : [];
        for (let i = 0; i < ns.length; i++) {
            const n = ns[i];
            if (!n.audio || n.isStream) continue;
            if (!!n.isSink !== wantSink) continue;
            out.push(n);
        }
        if (!wantSink) return out;
        return out.sort(function (a, b) {
            const d = IslandState.sinkRank(a) - IslandState.sinkRank(b);
            return d !== 0 ? d : root.nodeLabel(a).localeCompare(root.nodeLabel(b));
        });
    }
    readonly property var sinks: root.audioNodes(true)
    readonly property var sources: root.audioNodes(false)

    // Every listed node is tracked, not just the two defaults — an untracked
    // node has no description to show.
    PwObjectTracker {
        objects: {
            const o = [];
            if (root.sink) o.push(root.sink);
            if (root.source) o.push(root.source);
            return o.concat(root.sinks, root.sources);
        }
    }

    function nodeLabel(n) {
        if (!n) return "—";
        return n.nickname || n.description || n.name || "device";
    }

    Process { id: brightProc }
    Process { id: pavuProc }

    Column {
        id: col
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 18
        spacing: 10

        ControlSlider {
            width: parent.width
            theme: root.theme
            glyph: root.sinkAudio && root.sinkAudio.muted ? "\u{f075f}" : "\u{f057e}"
            label: "Volume"
            muted: root.sinkAudio ? root.sinkAudio.muted : false
            value: root.sinkAudio ? root.sinkAudio.volume : 0
            valueText: root.sinkAudio ? Math.round(root.sinkAudio.volume * 100) + "%" : "—"
            onMoved: (v) => { if (root.sinkAudio) root.sinkAudio.volume = v; }
            onToggleMuted: if (root.sinkAudio) root.sinkAudio.muted = !root.sinkAudio.muted
        }

        ControlSlider {
            width: parent.width
            theme: root.theme
            glyph: root.srcAudio && root.srcAudio.muted ? "\u{f036d}" : "\u{f036c}"
            label: "Microphone"
            muted: root.srcAudio ? root.srcAudio.muted : false
            value: root.srcAudio ? root.srcAudio.volume : 0
            valueText: root.srcAudio ? Math.round(root.srcAudio.volume * 100) + "%" : "—"
            onMoved: (v) => { if (root.srcAudio) root.srcAudio.volume = v; }
            onToggleMuted: if (root.srcAudio) root.srcAudio.muted = !root.srcAudio.muted
        }

        // ── devices ───────────────────────────────────────────────
        Repeater {
            model: [
                { key: "out", label: "Output", glyph: "\u{f057e}" },
                { key: "in",  label: "Input",  glyph: "\u{f036c}" }
            ]

            Column {
                id: devCol
                required property var modelData
                readonly property bool isOut: modelData.key === "out"
                readonly property var nodes: isOut ? root.sinks : root.sources
                readonly property var current: isOut ? root.sink : root.source

                width: col.width
                spacing: 6

                SectionLabel { theme: root.theme; text: devCol.modelData.label; topPadding: 4 }

                Repeater {
                    model: devCol.nodes

                    // Each device is the hub's toggle: the one in use has its
                    // circle filled, the rest sit as grey discs.
                    IconTile {
                        required property var modelData
                        width: col.width
                        height: 46
                        theme: root.theme
                        glyph: devCol.isOut
                               ? (/headphone|headset|hexa|airpods|buds/i.test(root.nodeLabel(modelData))
                                  ? "\u{f02cb}" : "\u{f04c3}")
                               : "\u{f036c}"
                        label: root.nodeLabel(modelData)
                        sub: modelData === devCol.current ? "in use" : ""
                        on: modelData === devCol.current
                        onClicked: {
                            if (devCol.isOut)
                                Pipewire.preferredDefaultAudioSink = modelData;
                            else
                                Pipewire.preferredDefaultAudioSource = modelData;
                        }
                    }
                }
            }
        }

        // Everything used day to day — switching output, switching input,
        // muting — is above; this is the escape hatch for per-application
        // streams and profiles, which nothing here models. pwvucontrol rather
        // than pavucontrol: it speaks Pipewire natively and is libadwaita, so
        // it follows the same matugen palette as this card.
        IconTile {
            width: parent.width
            height: 46
            theme: root.theme
            glyph: "\u{f0554}"
            label: "Audio settings"
            sub: "per-app streams and profiles in pwvucontrol"
            onClicked: {
                // setsid so it outlives a shell reload, and the card gets
                // out of the way of the window it just launched.
                pavuProc.command = ["setsid", "-f", "pwvucontrol"];
                pavuProc.running = true;
                IslandState.closeCard();
            }
        }

        // Only where a backlight exists. Untested on this machine by
        // definition — it has no /sys/class/backlight — and it needs
        // brightnessctl, which is not in install-apps.sh yet.
        ControlSlider {
            id: brightness
            visible: Platform.hasBacklight
            width: parent.width
            theme: root.theme
            glyph: "\u{f00df}"
            label: "Display"
            value: brightness.level
            valueText: Math.round(brightness.level * 100) + "%"

            property real level: 0
            onMoved: (v) => {
                brightness.level = v;
                brightProc.command = ["brightnessctl", "-d", Platform.backlightDevice,
                                      "set", Math.round(v * 100) + "%"];
                brightProc.running = true;
            }
        }
    }
}
