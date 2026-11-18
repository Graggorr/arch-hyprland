import QtQuick
import Quickshell.Io

Pill {
    id: root

    property string cmd
    property int intervalMs: 3000
    property bool hideWhenEmpty: true
    property var classColors: ({})

    property string out: ""
    property string tip: ""
    property string cls: ""

    interactive: true
    tooltipText: tip
    fillOnHover: true

    // Commands are spawned via setsid so the child outlives a shell restart —
    // otherwise reloading quickshell would kill the terminal it opened.
    property var clickCmd: null
    property var rightClickCmd: null

    onClicked: (b) => {
        const c = (b === Qt.RightButton) ? rightClickCmd : clickCmd;
        if (!c) return;
        runner.command = ["setsid", "-f"].concat(c);
        runner.running = true;
    }

    Process { id: runner }
    visible: !hideWhenEmpty || out !== ""
    // Width hysteresis: grow immediately, but only shrink when the content is
    // meaningfully narrower (>1 char). Stops 9%<->10% oscillation from re-laying
    // out the bar every tick, which is what made hover go stale and made the
    // whole row twitch as values changed.
    readonly property real rawW: label.implicitWidth + 32
    property real stableW: 0
    onRawWChanged: if (rawW > stableW || rawW < stableW - 12) stableW = rawW
    implicitWidth: visible ? Math.max(stableW, rawW) : 0

    tint: {
        for (const key in classColors)
            if (cls.split(" ").indexOf(key) !== -1)
                return classColors[key];
        return theme ? theme.fg : "white";
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: root.out
        color: root.contentColor
        font.family: theme ? theme.fontMono : "monospace"
        font.pixelSize: theme ? theme.fontSize : 13
        font.weight: Font.Medium
        renderType: Text.NativeRendering
    }

    function ingest(raw) {
        const s = (raw || "").trim();
        if (s === "") { root.out = ""; root.tip = ""; root.cls = ""; return; }
        if (s.charAt(0) === "{") {
            try {
                const j = JSON.parse(s);
                root.out = j.text !== undefined ? j.text : "";
                root.tip = j.tooltip !== undefined && j.tooltip !== false ? j.tooltip : "";
                root.cls = Array.isArray(j["class"]) ? j["class"].join(" ")
                         : (j["class"] !== undefined ? String(j["class"]) : "");
                return;
            } catch (e) { /* fall through to plain text */ }
        }
        root.out = s; root.tip = ""; root.cls = "";
    }

    Process {
        id: proc
        command: ["bash", "-c", root.cmd]
        stdout: StdioCollector { onStreamFinished: root.ingest(this.text) }
    }

    Timer {
        interval: root.intervalMs
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: proc.running = true
    }
}
