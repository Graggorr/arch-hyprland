import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// A focusable full-screen overlay rather than a child of the island card:
// PopupWindow cannot take keyboard focus, and this form is all text entry.
PanelWindow {
    id: root

    property var theme
    property string date: ""
    property var calendars: []

    signal created(string uid)

    property var targetScreen: null

    visible: false
    focusable: true
    // Full screen of the monitor in use — see the same block in Launcher.qml
    // for why exclusiveZone alone leaves the bars sharp.
    screen: targetScreen
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }

    property string title: ""
    property string startT: "09:00"
    property string endT: "10:00"
    property bool allDay: false
    property string endDate: ""
    property string location: ""
    property string notes: ""
    property string attendees: ""
    property int alarm: 10
    property int calIndex: 0
    property string busy: ""
    property string error: ""

    readonly property var alarmOptions: [
        { label: "none", v: 0 }, { label: "5 min", v: 5 }, { label: "10 min", v: 10 },
        { label: "30 min", v: 30 }, { label: "1 hour", v: 60 }, { label: "1 day", v: 1440 }
    ]

    function focusedScreen() {
        const want = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        const all = Quickshell.screens;
        for (let i = 0; i < all.length; i++) if (all[i].name === want) return all[i];
        return all.length > 0 ? all[0] : null;
    }

    function open(iso, cals) {
        targetScreen = focusedScreen();
        date = iso;
        endDate = iso;
        calendars = cals || [];
        title = ""; location = ""; notes = ""; attendees = "";
        startT = "09:00"; endT = "10:00"; allDay = false; alarm = 10;
        calIndex = 0; busy = ""; error = "";
        visible = true;
        // Through the field's own focus API: forceActiveFocus() on the
        // component root landed on its Rectangle, not the TextInput inside.
        titleInput.focusField();
    }

    function close() { visible = false; }

    function submit() {
        if (title.trim() === "") { error = "Give it a title"; return; }
        if (calendars.length === 0) { error = "No calendars — run calendar-setup first"; return; }
        error = ""; busy = "Creating…";
        const spec = {
            calendar: calendars[calIndex].collection,
            title: title.trim(),
            date: date,
            endDate: endDate,
            allday: allDay,
            start: startT,
            end: endT,
            location: location.trim(),
            description: notes.trim(),
            alarm: alarm,
            attendees: attendees.split(/[,;\s]+/).filter(s => s.indexOf("@") > 0)
        };
        creator.stdinText = JSON.stringify(spec);
        creator.running = true;
    }

    Process {
        id: creator
        command: [Quickshell.env("HOME") + "/.local/bin/calendar-create"]
        stdinEnabled: true
        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = "";
                let r = {};
                try { r = JSON.parse(this.text.trim()); } catch (e) { r = { ok: false, error: "bad response" }; }
                if (r.ok) {
                    if (r.syncError) root.error = "Saved locally — " + r.syncError;
                    else { root.created(r.uid); root.close(); return; }
                    root.created(r.uid);
                } else {
                    root.error = r.error || "Could not create the event";
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(root.theme.base.r, root.theme.base.g, root.theme.base.b, root.theme.scrimOpacity)
        MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 520
        implicitHeight: form.implicitHeight + 40
        radius: 24
        color: Qt.rgba(root.theme.surface_container.r, root.theme.surface_container.g,
                       root.theme.surface_container.b, root.theme.contentOpacity)
        border.width: 1
        border.color: Qt.alpha(root.theme.outline, 0.30)

        MouseArea { anchors.fill: parent }

        Column {
            id: form
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 20
            spacing: 12

            Item {
                width: parent.width; height: 22
                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "New event"
                    color: root.theme.accent
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(15)
                    font.weight: Font.DemiBold
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.date
                    color: root.theme.muted
                    font.family: root.theme.fontMono
                    font.pixelSize: 12
                }
            }

            ComposerField {
                id: titleInput
                theme: root.theme
                width: parent.width
                placeholder: "Title"
                text: root.title
                onTextEdited: (t) => root.title = t
                onSubmitted: root.submit()
                onCancelled: root.close()
            }

            Row {
                width: parent.width
                spacing: 10

                Rectangle {
                    width: 96; height: 34; radius: 10
                    color: root.allDay ? Qt.alpha(root.theme.accent, 0.22) : Qt.alpha(root.theme.fg, 0.07)
                    border.width: root.allDay ? 1 : 0
                    border.color: Qt.alpha(root.theme.accent, 0.5)
                    Text {
                        anchors.centerIn: parent
                        text: "All day"
                        color: root.allDay ? root.theme.accent : root.theme.muted
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(12)
                        font.weight: Font.DemiBold
                    }
                    MouseArea { anchors.fill: parent; onClicked: root.allDay = !root.allDay }
                }

                ComposerField {
                    theme: root.theme
                    width: 92
                    visible: !root.allDay
                    placeholder: "09:00"
                    label: "from"
                    text: root.startT
                    onTextEdited: (t) => root.startT = t
                    onSubmitted: root.submit()
                    onCancelled: root.close()
                }
                ComposerField {
                    theme: root.theme
                    width: 92
                    visible: !root.allDay
                    placeholder: "10:00"
                    label: "to"
                    text: root.endT
                    onTextEdited: (t) => root.endT = t
                    onSubmitted: root.submit()
                    onCancelled: root.close()
                }
                ComposerField {
                    theme: root.theme
                    width: 130
                    visible: root.allDay
                    placeholder: "YYYY-MM-DD"
                    label: "until"
                    text: root.endDate
                    onTextEdited: (t) => root.endDate = t
                    onSubmitted: root.submit()
                    onCancelled: root.close()
                }
            }

            ComposerField {
                theme: root.theme
                width: parent.width
                placeholder: "Location"
                text: root.location
                onTextEdited: (t) => root.location = t
                onSubmitted: root.submit()
                onCancelled: root.close()
            }

            ComposerField {
                theme: root.theme
                width: parent.width
                placeholder: "Attendees — comma separated emails"
                text: root.attendees
                onTextEdited: (t) => root.attendees = t
                onSubmitted: root.submit()
                onCancelled: root.close()
            }

            ComposerField {
                theme: root.theme
                width: parent.width
                placeholder: "Notes"
                text: root.notes
                onTextEdited: (t) => root.notes = t
                onSubmitted: root.submit()
                onCancelled: root.close()
            }

            // ── calendar picker ────────────────────────────────────
            Flow {
                width: parent.width
                spacing: 6
                Repeater {
                    model: root.calendars
                    Rectangle {
                        required property var modelData
                        required property int index
                        height: 28
                        width: chipRow.implicitWidth + 20
                        radius: 14
                        color: index === root.calIndex
                               ? Qt.alpha(modelData.color, 0.28)
                               : Qt.alpha(root.theme.fg, 0.07)
                        border.width: index === root.calIndex ? 1 : 0
                        border.color: modelData.color
                        Row {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 6
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 8; height: 8; radius: 4
                                color: modelData.color
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.display
                                color: index === root.calIndex ? root.theme.fg : root.theme.muted
                                font.family: root.theme.fontSans
                                font.pixelSize: IslandState.ts(11)
                                font.weight: Font.DemiBold
                            }
                        }
                        MouseArea { anchors.fill: parent; onClicked: root.calIndex = index }
                    }
                }
            }

            // ── alarm ──────────────────────────────────────────────
            Row {
                width: parent.width
                spacing: 6
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{f00ed}  alert"
                    color: root.theme.muted
                    font.family: root.theme.fontMono
                    font.pixelSize: 11
                }
                Repeater {
                    model: root.alarmOptions
                    Rectangle {
                        required property var modelData
                        height: 24
                        width: aTxt.implicitWidth + 16
                        radius: 12
                        color: root.alarm === modelData.v
                               ? Qt.alpha(root.theme.accent, 0.24) : Qt.alpha(root.theme.fg, 0.07)
                        Text {
                            id: aTxt
                            anchors.centerIn: parent
                            text: modelData.label
                            color: root.alarm === modelData.v ? root.theme.accent : root.theme.muted
                            font.family: root.theme.fontSans
                            font.pixelSize: IslandState.ts(10)
                            font.weight: Font.DemiBold
                        }
                        MouseArea { anchors.fill: parent; onClicked: root.alarm = modelData.v }
                    }
                }
            }

            Text {
                width: parent.width
                visible: root.error !== "" || root.busy !== ""
                text: root.busy !== "" ? root.busy : root.error
                color: root.busy !== "" ? root.theme.muted : root.theme.warn
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(11)
                wrapMode: Text.WordWrap
            }

            Row {
                anchors.right: parent.right
                spacing: 8
                Rectangle {
                    width: 84; height: 32; radius: 10
                    color: cancelHover.hovered ? Qt.alpha(root.theme.fg, 0.12) : Qt.alpha(root.theme.fg, 0.06)
                    Text {
                        anchors.centerIn: parent
                        text: "Cancel"
                        color: root.theme.muted
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(12)
                    }
                    HoverHandler { id: cancelHover }
                    MouseArea { anchors.fill: parent; onClicked: root.close() }
                }
                Rectangle {
                    width: 84; height: 32; radius: 10
                    color: Qt.alpha(root.theme.accent, saveHover.hovered ? 0.36 : 0.22)
                    border.width: 1
                    border.color: Qt.alpha(root.theme.accent, 0.5)
                    Text {
                        anchors.centerIn: parent
                        text: "Create"
                        color: root.theme.accent
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(12)
                        font.weight: Font.DemiBold
                    }
                    HoverHandler { id: saveHover }
                    MouseArea { anchors.fill: parent; onClicked: root.submit() }
                }
            }
        }
    }
}
