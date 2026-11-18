import QtQuick
import Quickshell.Io

// Clipboard history. wl-paste has been feeding cliphist since login but
// nothing on this machine could read it back — no keybind, no picker wired up.
// This is the missing half.
//
// Entries load on open and after every change rather than on a timer: the
// history only moves when something is copied, and this tool is the only thing
// that deletes from it.
Item {
    id: root

    property var theme

    readonly property real preferredHeight: 432

    property var entries: IslandState.cacheGet("clipboard.entries", [])
    property string query: ""
    property string flash: ""
    // The keyboard row, like the launcher's: arrows move, Enter copies and
    // closes the card so the paste can follow at once, Shift+Del forgets.
    property int selected: 0
    onQueryChanged: selected = 0
    onShownChanged: if (selected >= shown.length) selected = Math.max(0, shown.length - 1)

    function moveSelection(d) {
        const n = root.shown.length;
        if (n === 0) return;
        root.selected = Math.max(0, Math.min(n - 1, root.selected + d));
        const it = rows.itemAt(root.selected);
        if (!it) return;
        if (it.y < clipFlick.contentY) clipFlick.contentY = it.y;
        else if (it.y + it.height > clipFlick.contentY + clipFlick.height)
            clipFlick.contentY = it.y + it.height - clipFlick.height;
    }

    readonly property string script: "@HOME@/.config/quickshell/scripts/clipboard.sh"

    readonly property var shown: {
        const q = root.query.toLowerCase();
        if (q === "") return root.entries;
        const qv = IslandState.searchVariants(q);
        const out = [];
        for (let i = 0; i < root.entries.length; i++)
            if (IslandState.searchHit(root.entries[i].preview, qv))
                out.push(root.entries[i]);
        return out;
    }

    // The field takes the keyboard on open: this tool is for finding
    // something, and the launcher sets the same expectation.
    function reload() { listProc.running = true; search.forceActiveFocus(); }

    Process {
        id: listProc
        command: ["bash", root.script, "list", "200"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.entries = JSON.parse(this.text.trim()).entries || [];
                    IslandState.cacheSet("clipboard.entries", root.entries);
                } catch (e) { root.entries = []; }
            }
        }
    }

    Process {
        id: actProc
        stdout: StdioCollector { onStreamFinished: listProc.running = true }
    }
    function act(verb, id) {
        actProc.command = ["bash", root.script, verb, String(id)];
        actProc.running = true;
    }

    function pick() {
        if (root.selected >= root.shown.length) return;
        root.act("copy", root.shown[root.selected].id);
        IslandState.closeCard();
    }

    function copyEntry(e) {
        root.act("copy", e.id);
        root.flash = e.id;
        flashOff.restart();
    }
    Timer { id: flashOff; interval: 900; onTriggered: root.flash = "" }

    // Wiping hundreds of entries is not something to do on one misclick, so
    // the button arms first and disarms itself if left alone — same shape as
    // reboot and shutdown in the power tool.
    property bool wipeArmed: false
    Timer { id: wipeReset; interval: 4000; onTriggered: root.wipeArmed = false }
    function wipe() {
        if (!root.wipeArmed) { root.wipeArmed = true; wipeReset.restart(); return; }
        root.wipeArmed = false;
        actProc.command = ["bash", root.script, "wipe"];
        actProc.running = true;
    }

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
                    Keys.onDownPressed: root.moveSelection(1)
                    Keys.onUpPressed: root.moveSelection(-1)
                    Keys.onReturnPressed: root.pick()
                    Keys.onEnterPressed: root.pick()
                    Keys.onPressed: (e) => {
                        if (e.key === Qt.Key_Delete && (e.modifiers & Qt.ShiftModifier)
                                && root.selected < root.shown.length) {
                            root.act("delete", root.shown[root.selected].id);
                            e.accepted = true;
                        } else if (e.key === Qt.Key_PageDown) {
                            root.moveSelection(6); e.accepted = true;
                        } else if (e.key === Qt.Key_PageUp) {
                            root.moveSelection(-6); e.accepted = true;
                        }
                    }

                    Text {
                        anchors.fill: parent
                        visible: search.text === ""
                        text: "Search clipboard"
                        color: Qt.alpha(root.theme.muted, 0.6)
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(12)
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            Text {
                id: countLabel
                anchors.right: clearBtn.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: root.shown.length + (root.query !== "" ? " found" : " entries")
                color: Qt.alpha(root.theme.muted, 0.9)
                font.family: root.theme.fontMono
                font.pixelSize: 10
            }

            Rectangle {
                id: clearBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: clearRow.implicitWidth + 20
                height: 30
                radius: 10
                visible: root.entries.length > 0
                color: root.wipeArmed ? Qt.alpha(root.theme.warn, 0.28)
                     : (ch.hovered ? Qt.alpha(root.theme.fg, 0.14)
                                   : Qt.alpha(root.theme.fg, 0.07))
                border.width: 1
                border.color: root.wipeArmed ? Qt.alpha(root.theme.warn, 0.5) : "transparent"
                Behavior on color { ColorAnimation { duration: 130 } }

                Row {
                    id: clearRow
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u{f05e8}"
                        color: root.wipeArmed ? root.theme.warn : root.theme.muted
                        font.family: root.theme.fontMono
                        font.pixelSize: 13
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.wipeArmed ? "Clear all?" : "Clear"
                        color: root.wipeArmed ? root.theme.warn : root.theme.fg
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(11)
                        font.weight: Font.DemiBold
                    }
                }

                HoverHandler { id: ch; cursorShape: Qt.PointingHandCursor }
                MouseArea { anchors.fill: parent; onClicked: root.wipe() }
            }
        }

        Item {
            visible: root.shown.length === 0
            width: parent.width
            height: 160
            EmptyState {
                anchors.centerIn: parent
                theme: root.theme
                maxWidth: parent.width - 20
                glyph: root.entries.length === 0 ? "\u{f014c}" : "\u{f0349}"
                title: root.entries.length === 0 ? "Clipboard is empty" : "Nothing matches"
                sub: root.entries.length === 0 ? "Copy something and it lands here" : "Try fewer letters"
            }
        }

        Flickable {
            id: clipFlick
            width: parent.width
            height: parent.height - 40
            contentHeight: list.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar { flick: clipFlick; theme: root.theme }

            Column {
                id: list
                width: parent.width
                spacing: 4

                Repeater {
                    id: rows
                    model: root.shown

                    Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool justCopied: root.flash === modelData.id
                        readonly property bool isSelected: index === root.selected
                        readonly property bool hasThumb: !!modelData.thumb

                        width: list.width
                        height: hasThumb ? 56 : 38
                        radius: 10
                        color: justCopied ? Qt.alpha(root.theme.success, 0.22)
                             : isSelected ? root.theme.secondary_container
                             : (rh.hovered ? Qt.alpha(root.theme.fg, 0.12)
                                           : Qt.alpha(root.theme.fg, 0.05))
                        Behavior on color { ColorAnimation { duration: 130 } }

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !row.hasThumb
                            text: row.modelData.binary ? "\u{f021f}" : "\u{f018f}"
                            color: Qt.alpha(root.theme.accent3, 0.85)
                            font.family: root.theme.fontMono
                            font.pixelSize: 13
                        }

                        // An image is its own best preview: a small crop of
                        // it inline, the way a text row shows its first line,
                        // rather than a separate grid that would split images
                        // from text and leave holes when there are few.
                        Rectangle {
                            id: thumbFrame
                            visible: row.hasThumb
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: 64; height: 42
                            radius: 7
                            color: Qt.alpha(root.theme.fg, 0.08)
                            clip: true
                            Image {
                                anchors.fill: parent
                                source: row.hasThumb ? "file://" + row.modelData.thumb : ""
                                sourceSize.width: 128
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: false
                            }
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: row.hasThumb ? 84 : 36
                            anchors.right: parent.right
                            anchors.rightMargin: row.justCopied ? 78 : 44
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                            text: row.hasThumb
                                  ? "Image · " + row.modelData.format + " · "
                                    + row.modelData.w + "×" + row.modelData.h + " · " + row.modelData.size
                                  : row.modelData.preview
                            color: row.isSelected && !row.justCopied ? root.theme.on_secondary_container : root.theme.fg
                            font.family: root.theme.fontSans
                            font.pixelSize: IslandState.ts(11)
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 42
                            anchors.verticalCenter: parent.verticalCenter
                            visible: row.justCopied
                            text: "copied"
                            color: root.theme.success
                            font.family: root.theme.fontSans
                            font.pixelSize: IslandState.ts(10)
                            font.weight: Font.DemiBold
                        }

                        // Delete stays out of the way until the row is hovered —
                        // a history you browse should not offer destruction on
                        // every line at rest.
                        Rectangle {
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: 26; height: 26
                            radius: 8
                            visible: rh.hovered
                            color: dh.hovered ? Qt.alpha(root.theme.warn, 0.28)
                                              : Qt.alpha(root.theme.fg, 0.10)
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text {
                                anchors.centerIn: parent
                                text: "\u{f0a79}"
                                color: dh.hovered ? root.theme.warn : root.theme.muted
                                font.family: root.theme.fontMono
                                font.pixelSize: 12
                            }
                            HoverHandler { id: dh; cursorShape: Qt.PointingHandCursor }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.act("delete", row.modelData.id)
                            }
                        }

                        HoverHandler { id: rh; cursorShape: Qt.PointingHandCursor }
                        MouseArea {
                            anchors.fill: parent
                            anchors.rightMargin: 40
                            onClicked: root.copyEntry(row.modelData)
                        }
                    }
                }
            }
        }
    }
}
