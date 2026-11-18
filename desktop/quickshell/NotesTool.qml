import QtQuick
import Quickshell.Io

// Quick notes. Plain markdown files under ~/Documents/Notes, one per note, so
// a note written here stays readable by grep, any editor, and anything that
// syncs a folder — the island is one way in, not the only one.
//
// The Claude knowledge vault is deliberately not the store: it is a memory
// graph with its own conventions, not somewhere to drop a shopping list.
Item {
    id: root

    property var theme

    readonly property real preferredHeight: 480

    readonly property string script: "@HOME@/.config/quickshell/scripts/notes.sh"

    property var notes: IslandState.cacheGet("notes.list", [])
    property string query: ""
    // Which note the editor is bound to; "" means the editor writes a new one.
    property string editing: ""
    property string flash: ""

    readonly property var shown: {
        const q = root.query.toLowerCase();
        if (q === "") return root.notes;
        const qv = IslandState.searchVariants(q);
        const out = [];
        for (let i = 0; i < root.notes.length; i++) {
            const n = root.notes[i];
            if (IslandState.searchHit(n.title + "\n" + n.preview, qv))
                out.push(n);
        }
        return out;
    }

    function reload() { listProc.running = true; }

    Process {
        id: listProc
        command: ["bash", root.script, "list", "100"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.notes = JSON.parse(this.text.trim()).notes || [];
                    IslandState.cacheSet("notes.list", root.notes);
                } catch (e) { root.notes = []; }
            }
        }
    }

    Process {
        id: actProc
        stdout: StdioCollector {
            onStreamFinished: {
                listProc.running = true;
                IslandState.refreshPinnedNote();
            }
        }
    }
    function act(args) {
        actProc.command = ["bash", root.script].concat(args);
        actProc.running = true;
    }

    function save() {
        const body = editor.text.trim();
        if (body === "") return;
        if (root.editing === "") root.act(["add", body]);
        else root.act(["update", root.editing, body]);
        root.flash = root.editing === "" ? "saved" : "updated";
        flashOff.restart();
        root.clearEditor();
    }
    function clearEditor() {
        editor.text = "";
        root.editing = "";
    }
    function edit(note) {
        editor.text = note.body.replace(/\n+$/, "");
        root.editing = note.id;
        editor.forceActiveFocus();
    }
    Timer { id: flashOff; interval: 1400; onTriggered: root.flash = "" }

    Column {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 10

        // ── search ────────────────────────────────────────────────
        Item {
            width: parent.width
            height: 30

            Rectangle {
                anchors.left: parent.left
                anchors.right: folderLink.left
                anchors.rightMargin: 12
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
                    Keys.onEscapePressed: (e) => {
                        IslandState.closeCard();
                        e.accepted = true;
                    }

                    Text {
                        anchors.fill: parent
                        visible: search.text === ""
                        text: "Search notes"
                        color: Qt.alpha(root.theme.muted, 0.6)
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(12)
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            Text {
                id: folderLink
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.notes.length + (root.notes.length === 1 ? " note" : " notes")
                      + "  ·  open folder"
                color: flh.hovered ? root.theme.accent : Qt.alpha(root.theme.muted, 0.85)
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(10)
                HoverHandler { id: flh; cursorShape: Qt.PointingHandCursor }
                MouseArea { anchors.fill: parent; onClicked: root.act(["reveal"]) }
            }
        }

        // ── editor ────────────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: 116
            radius: 12
            color: Qt.alpha(root.theme.fg, 0.06)
            border.width: 1
            border.color: root.editing !== "" ? Qt.alpha(root.theme.accent, 0.45)
                        : (editor.activeFocus ? Qt.alpha(root.theme.accent, 0.28) : "transparent")
            Behavior on border.color { ColorAnimation { duration: 140 } }

            Flickable {
                id: editorFlick
                anchors.fill: parent
                anchors.margins: 10
                anchors.bottomMargin: 32
                contentHeight: editor.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                ScrollBar { flick: editorFlick; theme: root.theme }

                TextEdit {
                    id: editor
                    width: parent.width
                    color: root.theme.fg
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(12)
                    wrapMode: TextEdit.Wrap
                    selectByMouse: true
                    selectionColor: Qt.alpha(root.theme.accent, 0.35)

                    // Ctrl+Enter saves; a bare Enter has to stay a newline or
                    // the editor cannot hold more than one line.
                    Keys.onPressed: (e) => {
                        if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter)
                            && (e.modifiers & Qt.ControlModifier)) {
                            root.save();
                            e.accepted = true;
                        } else if (e.key === Qt.Key_Escape) {
                            IslandState.closeCard();
                            e.accepted = true;
                        }
                    }

                    Text {
                        anchors.fill: parent
                        visible: editor.text === ""
                        text: "Write a note — first line is the title"
                        color: Qt.alpha(root.theme.muted, 0.55)
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(12)
                    }
                }
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 9
                text: root.flash !== "" ? root.flash
                    : (root.editing !== "" ? "editing  ·  Esc to cancel"
                                           : "Ctrl+Enter to save")
                color: root.flash !== "" ? root.theme.success : Qt.alpha(root.theme.muted, 0.8)
                font.family: root.theme.fontMono
                font.pixelSize: 9
            }

            Rectangle {
                id: saveBtn
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8
                width: 66; height: 24
                radius: 8
                enabled: editor.text.trim() !== ""
                opacity: enabled ? 1 : 0.4
                color: sbh.hovered && enabled ? Qt.alpha(root.theme.accent, 0.35)
                                              : Qt.alpha(root.theme.fg, 0.14)
                Behavior on color { ColorAnimation { duration: 120 } }
                Text {
                    anchors.centerIn: parent
                    text: root.editing !== "" ? "Update" : "Save"
                    color: root.theme.fg
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(10)
                    font.weight: Font.DemiBold
                }
                HoverHandler { id: sbh; cursorShape: Qt.PointingHandCursor }
                MouseArea {
                    anchors.fill: parent
                    enabled: saveBtn.enabled
                    onClicked: root.save()
                }
            }
        }

        Item {
            visible: root.shown.length === 0
            width: parent.width
            height: 120
            EmptyState {
                anchors.centerIn: parent
                theme: root.theme
                maxWidth: parent.width - 20
                glyph: root.notes.length === 0 ? "\u{f09a5}" : "\u{f0349}"
                title: root.notes.length === 0 ? "No notes yet" : "Nothing matches"
                sub: root.notes.length === 0 ? "Write one above" : "Try fewer letters"
            }
        }

        // ── list ──────────────────────────────────────────────────
        Flickable {
            id: noteListFlick
            width: parent.width
            height: parent.height - 176
            contentHeight: list.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar { flick: noteListFlick; theme: root.theme }

            Column {
                id: list
                width: parent.width
                spacing: 4

                Repeater {
                    model: root.shown

                    Rectangle {
                        id: row
                        required property var modelData
                        readonly property bool current: root.editing === modelData.id

                        width: list.width
                        height: 46
                        radius: 10
                        color: current ? Qt.alpha(root.theme.accent, 0.16)
                             : (rh.hovered ? Qt.alpha(root.theme.fg, 0.12)
                                           : Qt.alpha(root.theme.fg, 0.05))
                        Behavior on color { ColorAnimation { duration: 130 } }

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.modelData.pinned ? "\u{f0403}" : "\u{f021b}"
                            color: row.modelData.pinned ? root.theme.accent2
                                                        : Qt.alpha(root.theme.accent3, 0.8)
                            font.family: root.theme.fontMono
                            font.pixelSize: 14
                        }

                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: 38
                            anchors.right: parent.right
                            anchors.rightMargin: rh.hovered ? 96 : 56
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1

                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: row.modelData.title
                                color: root.theme.fg
                                font.family: root.theme.fontSans
                                font.pixelSize: IslandState.ts(12)
                                font.weight: Font.DemiBold
                            }
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                visible: row.modelData.preview !== ""
                                text: row.modelData.preview
                                color: Qt.alpha(root.theme.muted, 0.9)
                                font.family: root.theme.fontSans
                                font.pixelSize: IslandState.ts(10)
                            }
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !rh.hovered
                            text: row.modelData.when
                            color: Qt.alpha(root.theme.muted, 0.8)
                            font.family: root.theme.fontMono
                            font.pixelSize: 9
                        }

                        // Pin and delete appear on hover, so a list you are
                        // reading does not offer destruction on every line.
                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            visible: rh.hovered
                            spacing: 4

                            Rectangle {
                                width: 26; height: 26; radius: 8
                                color: ph.hovered ? Qt.alpha(root.theme.accent2, 0.30)
                                                  : Qt.alpha(root.theme.fg, 0.10)
                                Text {
                                    anchors.centerIn: parent
                                    text: "\u{f0403}"
                                    color: row.modelData.pinned || ph.hovered
                                           ? root.theme.accent2 : root.theme.muted
                                    font.family: root.theme.fontMono
                                    font.pixelSize: 12
                                }
                                HoverHandler { id: ph; cursorShape: Qt.PointingHandCursor }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.act(["pin", row.modelData.id])
                                }
                            }

                            Rectangle {
                                width: 26; height: 26; radius: 8
                                color: dh.hovered ? Qt.alpha(root.theme.warn, 0.28)
                                                  : Qt.alpha(root.theme.fg, 0.10)
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
                                    onClicked: {
                                        if (root.editing === row.modelData.id)
                                            root.clearEditor();
                                        root.act(["delete", row.modelData.id]);
                                    }
                                }
                            }
                        }

                        HoverHandler { id: rh; cursorShape: Qt.PointingHandCursor }
                        MouseArea {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.rightMargin: 66
                            onClicked: root.edit(row.modelData)
                        }
                    }
                }
            }
        }
    }
}
