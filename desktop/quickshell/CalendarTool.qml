import QtQuick
import Quickshell
import Quickshell.Io

// The calendar, as one tool among several rather than as the card itself.
// Everything here — the agenda loading, the detail view, the composer hook —
// came out of IslandCard unchanged; what changed is that it no longer decides
// how big the surface is or what else is on it.
Item {
    id: root

    property var theme

    // What the shell sizes the card to when this tool is showing.
    readonly property real preferredHeight: 364

    signal composeRequested(string iso)

    property var agenda: []
    property var agendaSources: ({})
    property var marks: ({})
    property var calendars: []
    property string agendaDate: ""
    property bool agendaLoading: false

    property var detailItem: null
    property var detailInfo: null

    readonly property string home: Quickshell.env("HOME")

    SystemClock { id: clk; precision: SystemClock.Seconds }

    // Called by the shell every time the tool is shown, so a card reopened
    // after midnight or after an external edit is never stale.
    function reload() {
        cal.reset();
        detailItem = null;
        detailInfo = null;
        loadMonth(cal.shown.getFullYear(), cal.shown.getMonth() + 1);
        loadDay(cal.selected);
        loadCalendars();
    }

    function loadDetail(item) {
        detailItem = item;
        detailInfo = null;
        detProc.command = [root.home + "/.local/bin/calendar-agenda", "detail",
                           item.collection, item.uid];
        detProc.running = true;
    }
    function closeDetail() { detailItem = null; detailInfo = null; }
    readonly property bool detailOpen: detailItem !== null

    Process {
        id: detProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(this.text.trim());
                    root.detailInfo = j.error ? null : j;
                } catch (e) { root.detailInfo = null; }
            }
        }
    }

    function openLink(url) { IslandState.open(url); }

    function loadDay(iso) {
        agendaDate = iso;
        agendaLoading = true;
        detailItem = null;
        detailInfo = null;
        dayProc.command = [root.home + "/.local/bin/calendar-agenda", "day", iso];
        dayProc.running = true;
    }
    function loadMonth(y, m) {
        monthProc.command = [root.home + "/.local/bin/calendar-agenda", "month", "" + y, "" + m];
        monthProc.running = true;
    }
    function loadCalendars() {
        calProc.command = [root.home + "/.local/bin/calendar-agenda", "calendars"];
        calProc.running = true;
    }
    function refresh() {
        loadMonth(cal.shown.getFullYear(), cal.shown.getMonth() + 1);
        loadDay(cal.selected);
    }

    Process {
        id: dayProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.agendaLoading = false;
                try {
                    const j = JSON.parse(this.text.trim());
                    root.agenda = j.items || [];
                    root.agendaSources = j.sources || ({});
                } catch (e) { root.agenda = []; }
            }
        }
    }

    Process {
        id: monthProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(this.text.trim());
                    root.marks = j.days || ({});
                } catch (e) { root.marks = ({}); }
            }
        }
    }

    Process {
        id: calProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(this.text.trim());
                    root.calendars = j.calendars || [];
                } catch (e) { root.calendars = []; }
            }
        }
    }

    function prettyDate(iso) {
        const p = (iso || "").split("-");
        if (p.length < 3) return "";
        const d = new Date(parseInt(p[0]), parseInt(p[1]) - 1, parseInt(p[2]));
        const now = new Date();
        const t = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        const diff = Math.round((d - t) / 86400000);
        if (diff === 0) return "Today";
        if (diff === 1) return "Tomorrow";
        if (diff === -1) return "Yesterday";
        return Qt.formatDate(d, "ddd d MMM");
    }

    readonly property string sourceWarning: {
        const s = root.agendaSources;
        const bad = [];
        for (const k in s) if (s[k] !== "ok") bad.push(k + ": " + s[k]);
        return bad.length === Object.keys(s).length && bad.length > 0 ? bad.join("   ") : "";
    }

    Row {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 18

        // ── calendar ──────────────────────────────────────────────
        Column {
            height: parent.height
            spacing: 10

            CalendarGrid {
                id: cal
                theme: root.theme
                marks: root.marks
                onDaySelected: (iso) => root.loadDay(iso)
                onMonthChanged: (y, m) => root.loadMonth(y, m)
            }

            Rectangle {
                width: cal.width; height: 1
                color: Qt.alpha(root.theme.fg, 0.10)
            }

            Item {
                width: cal.width
                height: 16
                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        const u = new Date(clk.date.getTime());
                        return "UTC " + ("0" + u.getUTCHours()).slice(-2)
                             + ":" + ("0" + u.getUTCMinutes()).slice(-2);
                    }
                    color: Qt.alpha(root.theme.muted, 0.9)
                    font.family: root.theme.fontMono
                    font.pixelSize: 10
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        const d = new Date(clk.date.getTime());
                        const t = new Date(d.getFullYear(), 0, 1);
                        const wk = Math.ceil((((d - t) / 86400000) + t.getDay() + 1) / 7);
                        return "week " + wk;
                    }
                    color: Qt.alpha(root.theme.muted, 0.9)
                    font.family: root.theme.fontMono
                    font.pixelSize: 10
                }
            }
        }


        // ── agenda for the selected day ───────────────────────────
        Column {
            width: 268
            height: parent.height
            spacing: 8

            Item {
                visible: root.detailItem === null
                width: parent.width; height: 20

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.prettyDate(root.agendaDate)
                    color: root.theme.fg
                    font.family: root.theme.fontDisplay
                    font.pixelSize: IslandState.ts(16)
                    font.weight: Font.Bold
                }

                // New event — opens the composer for the selected day.
                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: addRow.implicitWidth + 16
                    height: 22
                    radius: 11
                    color: Qt.alpha(root.theme.accent, addHover.hovered ? 0.32 : 0.18)
                    border.width: 1
                    border.color: Qt.alpha(root.theme.accent, 0.4)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Row {
                        id: addRow
                        anchors.centerIn: parent
                        spacing: 4
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\u{f0415}"
                            color: root.theme.accent
                            font.family: root.theme.fontMono
                            font.pixelSize: 12
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "New"
                            color: root.theme.accent
                            font.family: root.theme.fontSans
                            font.pixelSize: IslandState.ts(11)
                            font.weight: Font.DemiBold
                        }
                    }
                    HoverHandler { id: addHover }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.composeRequested(root.agendaDate)
                    }
                }
            }

            // Setup hint when literally every source is down.
            Text {
                width: parent.width
                visible: root.detailItem === null && root.sourceWarning !== ""
                text: "Calendars not connected yet.\nRun calendar-setup in a terminal.\n\n" + root.sourceWarning
                color: Qt.alpha(root.theme.muted, 0.85)
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(11)
                wrapMode: Text.WordWrap
            }

            Item {
                visible: root.detailItem === null && root.sourceWarning === "" && !root.agendaLoading && root.agenda.length === 0
                width: parent.width
                height: 120
                EmptyState {
                    anchors.centerIn: parent
                    theme: root.theme
                    maxWidth: parent.width - 20
                    glyph: "\u{f00f6}"
                    title: "Nothing scheduled"
                    sub: "A free day"
                }
            }

            // ── event detail (replaces the list when a row is clicked) ──
            Item {
                visible: root.detailItem !== null
                width: parent.width; height: 20

                Rectangle {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: backRow.implicitWidth + 14
                    height: 22
                    radius: 11
                    color: Qt.alpha(root.theme.fg, backHover.hovered ? 0.14 : 0.07)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Row {
                        id: backRow
                        anchors.centerIn: parent
                        spacing: 4
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\u{f0141}"
                            color: root.theme.muted
                            font.family: root.theme.fontMono
                            font.pixelSize: 12
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.prettyDate(root.agendaDate)
                            color: root.theme.muted
                            font.family: root.theme.fontSans
                            font.pixelSize: IslandState.ts(11)
                            font.weight: Font.DemiBold
                        }
                    }
                    HoverHandler { id: backHover }
                    MouseArea { anchors.fill: parent; onClicked: root.closeDetail() }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8; height: 8; radius: 4
                        color: root.detailItem ? root.detailItem.color : "transparent"
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.detailItem ? root.detailItem.calendar : ""
                        color: Qt.alpha(root.theme.muted, 0.9)
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(10)
                    }
                }
            }

            Flickable {
                id: detailFlick
                visible: root.detailItem !== null
                width: parent.width
                height: parent.height - 28
                contentHeight: detailCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar { flick: detailFlick; theme: root.theme }

                Column {
                    id: detailCol
                    width: parent.width
                    spacing: 8

                    Text {
                        width: parent.width
                        text: root.detailItem ? root.detailItem.title : ""
                        color: root.theme.fg
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(15)
                        font.weight: Font.DemiBold
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        width: parent.width
                        text: {
                            if (!root.detailItem) return "";
                            if (root.detailItem.allday) return "All day";
                            let s = root.detailItem.start || "";
                            if (root.detailItem.end) s += " – " + root.detailItem.end;
                            return s;
                        }
                        color: root.theme.accent
                        font.family: root.theme.fontMono
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    // Join button when the event carries a Meet link.
                    Rectangle {
                        visible: root.detailInfo !== null && root.detailInfo.meet !== ""
                        width: joinRow.implicitWidth + 20
                        height: 28
                        radius: 14
                        color: Qt.alpha(root.theme.accent, joinHover.hovered ? 0.34 : 0.20)
                        border.width: 1
                        border.color: Qt.alpha(root.theme.accent, 0.45)
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Row {
                            id: joinRow
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "\u{f05a0}"
                                color: root.theme.accent
                                font.family: root.theme.fontMono
                                font.pixelSize: 12
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Join Meet"
                                color: root.theme.accent
                                font.family: root.theme.fontSans
                                font.pixelSize: IslandState.ts(11)
                                font.weight: Font.DemiBold
                            }
                        }
                        HoverHandler { id: joinHover }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.openLink(root.detailInfo.meet)
                        }
                    }

                    // Watch button for feeds that carry a link instead of
                    // a per-event URL — an F1 session has nowhere else to
                    // point you at the broadcast.
                    Rectangle {
                        id: watchBtn
                        // The feed's own colour, so an F1 session's button
                        // reads as F1 rather than as generic chrome.
                        readonly property color tint: root.detailInfo && root.detailInfo.color
                                                      ? root.detailInfo.color : root.theme.accent
                        visible: root.detailInfo !== null && (root.detailInfo.link || "") !== ""
                        width: watchRow.implicitWidth + 20
                        height: 28
                        radius: 14
                        color: Qt.alpha(watchBtn.tint, watchHover.hovered ? 0.34 : 0.20)
                        border.width: 1
                        border.color: Qt.alpha(watchBtn.tint, 0.45)
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Row {
                            id: watchRow
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "\u{f040a}"
                                color: watchBtn.tint
                                font.family: root.theme.fontMono
                                font.pixelSize: 12
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.detailInfo ? (root.detailInfo.linkLabel || "Open link") : ""
                                color: watchBtn.tint
                                font.family: root.theme.fontSans
                                font.pixelSize: IslandState.ts(11)
                                font.weight: Font.DemiBold
                            }
                        }
                        HoverHandler { id: watchHover }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.openLink(root.detailInfo.link)
                        }
                    }

                    Text {
                        width: parent.width
                        visible: root.detailItem !== null && (root.detailItem.location || "") !== ""
                        text: "\u{f034e}  " + (root.detailItem ? root.detailItem.location : "")
                        color: Qt.alpha(root.theme.fg, 0.85)
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(11)
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        width: parent.width
                        visible: root.detailInfo !== null && root.detailInfo.organizer !== ""
                        text: "organizer  " + (root.detailInfo ? (root.detailInfo.organizerName || root.detailInfo.organizer) : "")
                        color: Qt.alpha(root.theme.muted, 0.9)
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(10)
                        elide: Text.ElideRight
                    }

                    Text {
                        visible: root.detailInfo !== null && root.detailInfo.attendees.length > 0
                        text: root.detailInfo ? root.detailInfo.attendees.length + " attendees" : ""
                        color: Qt.alpha(root.theme.accent3, 0.9)
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(10)
                        font.weight: Font.DemiBold
                    }

                    Column {
                        width: parent.width
                        spacing: 2
                        Repeater {
                            model: root.detailInfo ? root.detailInfo.attendees : []
                            Row {
                                required property var modelData
                                spacing: 6
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.status === "accepted" ? "✓"
                                        : modelData.status === "declined" ? "✗"
                                        : modelData.status === "tentative" ? "~" : "·"
                                    color: modelData.status === "accepted" ? root.theme.success
                                         : modelData.status === "declined" ? root.theme.warn
                                         : Qt.alpha(root.theme.muted, 0.8)
                                    font.family: root.theme.fontMono
                                    font.pixelSize: 11
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 230
                                    elide: Text.ElideRight
                                    text: modelData.name + (modelData.optional ? "  (optional)" : "")
                                    color: Qt.alpha(root.theme.fg, 0.82)
                                    font.family: root.theme.fontSans
                                    font.pixelSize: IslandState.ts(10)
                                }
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        visible: root.detailInfo !== null && root.detailInfo.description !== ""
                        text: root.detailInfo ? root.detailInfo.description : ""
                        color: Qt.alpha(root.theme.muted, 0.95)
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(10)
                        wrapMode: Text.Wrap
                        maximumLineCount: 14
                        elide: Text.ElideRight
                    }

                    Text {
                        visible: root.detailInfo !== null && root.detailInfo.recurrence !== ""
                        text: "\u{f0456}  repeats"
                        color: Qt.alpha(root.theme.muted, 0.8)
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(10)
                    }
                }
            }

            Flickable {
                id: agendaFlick
                visible: root.detailItem === null
                width: parent.width
                height: parent.height - 28 - (root.sourceWarning !== "" ? 90 : 0)
                contentHeight: agendaCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar { flick: agendaFlick; theme: root.theme }

                Column {
                    id: agendaCol
                    width: parent.width
                    spacing: 4

                    Repeater {
                        model: root.agenda
                        Rectangle {
                            required property var modelData
                            width: agendaCol.width
                            height: itemRow.implicitHeight + 12
                            radius: 10
                            color: itemHover.hovered ? Qt.alpha(root.theme.fg, 0.07) : Qt.alpha(root.theme.fg, 0.035)
                            Behavior on color { ColorAnimation { duration: 120 } }
                            HoverHandler {
                                id: itemHover
                                cursorShape: modelData.kind === "event" ? Qt.PointingHandCursor : Qt.ArrowCursor
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: if (modelData.kind === "event") root.loadDetail(modelData)
                            }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.margins: 5
                                width: 3
                                radius: 1.5
                                color: modelData.color
                                opacity: modelData.completed ? 0.35 : 1
                            }

                            Row {
                                id: itemRow
                                anchors.left: parent.left
                                anchors.leftMargin: 14
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8

                                Column {
                                    width: 44
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text {
                                        text: modelData.allday ? "all-day"
                                            : (modelData.start || "—")
                                        color: modelData.overdue ? root.theme.warn
                                             : Qt.alpha(root.theme.fg, 0.9)
                                        font.family: root.theme.fontMono
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                    }
                                    Text {
                                        visible: !modelData.allday && (modelData.end || "") !== ""
                                        text: modelData.end || ""
                                        color: Qt.alpha(root.theme.muted, 0.7)
                                        font.family: root.theme.fontMono
                                        font.pixelSize: 9
                                    }
                                }

                                Column {
                                    width: parent.width - 44 - 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 1

                                    Row {
                                        spacing: 5
                                        Text {
                                            visible: modelData.kind !== "event"
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData.kind === "reminder" ? "\u{f0837}" : "\u{f0139}"
                                            color: modelData.completed
                                                   ? Qt.alpha(root.theme.muted, 0.6) : modelData.color
                                            font.family: root.theme.fontMono
                                            font.pixelSize: 11
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: Math.min(implicitWidth, agendaCol.width - 44 - 46)
                                            elide: Text.ElideRight
                                            text: modelData.title
                                            color: modelData.completed
                                                   ? Qt.alpha(root.theme.muted, 0.6)
                                                   : modelData.cancelled ? root.theme.warn : root.theme.fg
                                            font.family: root.theme.fontSans
                                            font.pixelSize: IslandState.ts(12)
                                            font.weight: Font.DemiBold
                                            font.strikeout: modelData.completed === true || modelData.cancelled === true
                                        }
                                    }

                                    Text {
                                        visible: (modelData.location || "") !== "" || (modelData.calendar || "") !== ""
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: {
                                            let s = modelData.calendar || "";
                                            if (modelData.location) s += (s ? "  ·  " : "") + modelData.location;
                                            if (modelData.overdue) s += (s ? "  ·  " : "") + "overdue";
                                            return s;
                                        }
                                        color: modelData.overdue
                                               ? Qt.alpha(root.theme.warn, 0.85)
                                               : Qt.alpha(root.theme.muted, 0.75)
                                        font.family: root.theme.fontSans
                                        font.pixelSize: IslandState.ts(10)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
