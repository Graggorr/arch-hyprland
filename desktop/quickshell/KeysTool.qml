import QtQuick
import Quickshell.Io

// The machine's cheatsheet. Three sources under one search box: the live
// Hyprland keybinds (hyprctl binds -j — every bind in hyprland.lua carries a
// description, and that description is what renders here), a curated Linux
// command reference, and per-app shortcut lists. The last two live in
// cheatsheet.json next to this file and hot-reload on edit, so extending the
// sheet is a JSON entry, not a shell change.
Item {
    id: root

    property var theme

    readonly property real preferredHeight: 432

    property var binds: IslandState.cacheGet("keys.binds", [])
    property var linux: IslandState.cacheGet("keys.linux", [])
    property var apps: IslandState.cacheGet("keys.apps", [])
    property string query: ""
    property string section: "all"
    property int flashRow: -1

    readonly property var sections: [
        { id: "all",   name: "All" },
        { id: "keys",  name: "Keybinds" },
        { id: "linux", name: "Linux" },
        { id: "apps",  name: "Apps" }
    ]

    function reload() { bindsProc.running = true; }

    // hyprctl reports Lua binds as dispatcher "__lua" with an opaque handler
    // index, so the description field is the only human-readable part — the
    // formatter below only has to make the key chord itself presentable.
    readonly property var keyNames: ({
        "slash": "/", "apostrophe": "'", "grave": "`",
        "left": "←", "right": "→", "up": "↑", "down": "↓",
        "mouse:272": "Left drag", "mouse:273": "Right drag",
        "mouse_down": "Scroll ↓", "mouse_up": "Scroll ↑"
    })

    function chord(b) {
        const parts = [];
        if (b.modmask & 64) parts.push("SUPER");
        if (b.modmask & 4)  parts.push("CTRL");
        if (b.modmask & 8)  parts.push("ALT");
        if (b.modmask & 1)  parts.push("SHIFT");
        let key = b.key;
        if (root.keyNames[key]) key = root.keyNames[key];
        else if (key.indexOf("XF86") === 0) key = key.substring(4);
        parts.push(key);
        return parts.join(" + ");
    }

    Process {
        id: bindsProc
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const raw = JSON.parse(this.text.trim());
                    const out = [];
                    for (let i = 0; i < raw.length; i++) {
                        const b = raw[i];
                        if (b.submap !== "") continue;
                        out.push({
                            keys: root.chord(b),
                            desc: b.description !== "" ? b.description
                                : (b.dispatcher === "__lua" ? "" : b.dispatcher + " " + b.arg)
                        });
                    }
                    root.binds = out;
                    IslandState.cacheSet("keys.binds", out);
                } catch (e) { root.binds = []; }
            }
        }
    }

    FileView {
        path: "@HOME@/.config/quickshell/cheatsheet.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.linux = d.linux || [];
                root.apps = d.apps || [];
                IslandState.cacheSet("keys.linux", root.linux);
                IslandState.cacheSet("keys.apps", root.apps);
            } catch (e) { /* a half-saved hand edit; keep the last good parse */ }
        }
    }

    // One flat list: header markers interleaved with items, so a single
    // Repeater renders everything and matches never lose their category.
    readonly property var shown: {
        const q = root.query.toLowerCase();
        const qv = IslandState.searchVariants(q);
        const out = [];
        function addCat(name, items) {
            const hits = [];
            for (let i = 0; i < items.length; i++) {
                const it = items[i];
                if (q === "" ||
                    IslandState.searchHit(it.keys + " " + it.desc + " " + name, qv))
                    hits.push(it);
            }
            if (hits.length === 0) return;
            out.push({ header: name });
            for (let i = 0; i < hits.length; i++) out.push(hits[i]);
        }
        if (root.section === "all" || root.section === "keys")
            addCat("Hyprland keybinds", root.binds);
        if (root.section === "all" || root.section === "linux")
            for (let i = 0; i < root.linux.length; i++) addCat(root.linux[i].name, root.linux[i].items);
        if (root.section === "all" || root.section === "apps")
            for (let i = 0; i < root.apps.length; i++) addCat(root.apps[i].name, root.apps[i].items);
        return out;
    }

    readonly property int shownCount: {
        let n = 0;
        for (let i = 0; i < root.shown.length; i++) if (!root.shown[i].header) n++;
        return n;
    }

    Process { id: copyProc }
    function copyRow(index, text) {
        copyProc.command = ["wl-copy", "--", text];
        copyProc.running = true;
        root.flashRow = index;
        flashOff.restart();
    }
    Timer { id: flashOff; interval: 900; onTriggered: root.flashRow = -1 }

    Column {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 10

        Item {
            width: parent.width
            height: 30

            Rectangle {
                anchors.left: parent.left
                anchors.right: countLabel.left
                anchors.rightMargin: 10
                height: 30
                radius: 10
                color: Qt.alpha(root.theme.fg, 0.07)
                border.width: 1
                border.color: search.activeFocus ? Qt.alpha(root.theme.accent, 0.4) : "transparent"

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{f0349}"
                    color: Qt.alpha(root.theme.muted, 0.9)
                    font.family: root.theme.fontMono
                    font.pixelSize: 13
                }
                TextInput {
                    id: search
                    anchors.left: parent.left
                    anchors.leftMargin: 32
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.theme.fg
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(12)
                    selectByMouse: true
                    onTextChanged: root.query = text
                    // Esc closes the whole card, like everywhere in the island.
                    Keys.onEscapePressed: (e) => {
                        IslandState.closeCard();
                        e.accepted = true;
                    }

                    Text {
                        anchors.fill: parent
                        visible: search.text === ""
                        text: "Search shortcuts & commands"
                        color: Qt.alpha(root.theme.muted, 0.6)
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(12)
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            Text {
                id: countLabel
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.shownCount + " entries"
                color: Qt.alpha(root.theme.muted, 0.8)
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(10)
            }
        }

        Row {
            spacing: 6

            Repeater {
                model: root.sections

                Rectangle {
                    id: chip
                    required property var modelData
                    readonly property bool active: root.section === modelData.id

                    width: chipLabel.implicitWidth + 20
                    height: 24
                    radius: 8
                    color: active ? Qt.alpha(root.theme.accent, 0.22)
                         : (chipHover.hovered ? Qt.alpha(root.theme.fg, 0.12)
                                              : Qt.alpha(root.theme.fg, 0.05))
                    Behavior on color { ColorAnimation { duration: 130 } }

                    Text {
                        id: chipLabel
                        anchors.centerIn: parent
                        text: chip.modelData.name
                        color: chip.active ? root.theme.accent : root.theme.fg
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(11)
                        font.weight: chip.active ? Font.DemiBold : Font.Normal
                    }

                    HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                    MouseArea { anchors.fill: parent; onClicked: root.section = chip.modelData.id }
                }
            }
        }

        Text {
            visible: root.shown.length === 0
            text: "Nothing matches"
            color: Qt.alpha(root.theme.muted, 0.7)
            font.family: root.theme.fontSans
            font.pixelSize: IslandState.ts(12)
        }

        Flickable {
            id: keysFlick
            width: parent.width
            height: parent.height - 74
            contentHeight: list.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar { flick: keysFlick; theme: root.theme }

            Column {
                id: list
                width: parent.width
                spacing: 3

                Repeater {
                    model: root.shown

                    Item {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool isHeader: modelData.header !== undefined
                        readonly property bool justCopied: root.flashRow === index

                        width: list.width
                        height: isHeader ? 28 : 30

                        Text {
                            visible: row.isHeader
                            anchors.left: parent.left
                            anchors.leftMargin: 2
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 4
                            text: row.isHeader ? row.modelData.header : ""
                            color: Qt.alpha(root.theme.accent3, 0.95)
                            font.family: root.theme.fontSans
                            font.pixelSize: IslandState.ts(11)
                            font.weight: Font.DemiBold
                        }

                        Rectangle {
                            visible: !row.isHeader
                            anchors.fill: parent
                            radius: 9
                            color: row.justCopied ? Qt.alpha(root.theme.success, 0.22)
                                 : (rowHover.hovered ? Qt.alpha(root.theme.fg, 0.10)
                                                     : Qt.alpha(root.theme.fg, 0.04))
                            Behavior on color { ColorAnimation { duration: 130 } }

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width * 0.44
                                elide: Text.ElideRight
                                text: row.isHeader ? "" : row.modelData.keys
                                color: root.theme.accent
                                font.family: root.theme.fontMono
                                font.pixelSize: 10
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.left: parent.left
                                anchors.leftMargin: parent.width * 0.44 + 22
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                text: row.isHeader ? ""
                                    : (row.justCopied ? "copied" : row.modelData.desc)
                                color: row.justCopied ? root.theme.success : root.theme.fg
                                font.family: root.theme.fontSans
                                font.pixelSize: IslandState.ts(11)
                            }

                            HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.copyRow(row.index, row.modelData.keys)
                            }
                        }
                    }
                }
            }
        }
    }
}
