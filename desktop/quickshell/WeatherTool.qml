import QtQuick
import Quickshell

// The weather column, promoted out of the calendar card into a tool of its
// own. It reads IslandState directly rather than taking a wx object, so the
// forecast it renders is the one poll the machine makes, not one per monitor.
//
// Laid out for the card's static 605 width: current conditions on the left,
// the forecast as its own column on the right — stacking everything on one
// side left half the card dead.
Item {
    id: root

    property var theme

    // Ten forecast rows now, where wttr.in only ever gave three. The rail is
    // nine tools tall and already sets a taller floor, so this costs nothing.
    readonly property real preferredHeight: 404

    // The next 24 hours, from the current one on. The poll is cached for
    // half an hour, so the strip can start in the past; the clock decides
    // what "now" is, not the fetch time.
    SystemClock { id: clk; precision: SystemClock.Minutes }
    // A clicked forecast row puts that day's own hours in the strip; 0 is
    // the rolling next-24h strip. Every day is 24 rows; past tomorrow they
    // come from Open-Meteo, unless that fetch failed (then sinoptik's four).
    property int dayIndex: 0
    readonly property var pickedDay: root.dayIndex > 0 ? IslandState.wxForecast[root.dayIndex] : null
    readonly property var hours: {
        if (root.pickedDay) return root.pickedDay.hours || [];
        const h = clk.date.getHours();
        const out = [];
        const src = IslandState.wxHourly;
        for (let i = 0; i < src.length; i++)
            if (src[i].tomorrow === true || src[i].hour >= h) out.push(src[i]);
        return out;
    }
    property var hoverHour: null
    onHoursChanged: {
        root.hoverHour = null;
        hoursFlick.contentX = 0;
    }
    Connections {
        target: IslandState
        function onWxForecastChanged() {
            if (root.dayIndex >= IslandState.wxForecast.length) root.dayIndex = 0;
        }
    }

    function dayDate(iso) {
        const p = (iso || "").split("-");
        if (p.length < 3) return new Date(NaN);
        return new Date(parseInt(p[0]), parseInt(p[1]) - 1, parseInt(p[2]));
    }

    function dayName(iso) {
        const d = root.dayDate(iso);
        if (isNaN(d.getTime())) return "";
        const today = new Date();
        return d.toDateString() === today.toDateString() ? "Today" : Qt.formatDate(d, "ddd");
    }

    Row {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 18

        // ── current conditions ────────────────────────────────────
        Column {
            id: nowCol
            width: 280
            height: parent.height
            spacing: 12

            Item {
                width: parent.width; height: 16
                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{f034e}  " + (IslandState.wxArea || "—")
                    color: root.theme.accent3
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(12)
                    font.weight: Font.DemiBold
                }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    // Says how old the reading is only once that matters: a
                    // fresh poll is the normal case and does not need a label.
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: IslandState.wxStale
                        text: "\u{f04e6}  " + (IslandState.wxAgeMins >= 120
                              ? Math.floor(IslandState.wxAgeMins / 60) + "h old"
                              : IslandState.wxAgeMins + "m old")
                        color: root.theme.warn
                        font.family: root.theme.fontMono
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: IslandState.wxUv !== "" ? "UV " + IslandState.wxUv : ""
                        color: Qt.alpha(root.theme.muted, 0.9)
                        font.family: root.theme.fontMono
                        font.pixelSize: 10
                    }
                }
            }

            Row {
                spacing: 14
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: IslandState.wxIcon
                    color: root.theme.primary
                    font.family: root.theme.fontMono
                    font.pixelSize: 46
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    Text {
                        text: IslandState.wxTemp + "°"
                        color: root.theme.fg
                        font.family: root.theme.fontClock
                        font.features: root.theme.clockFeatures
                        font.pixelSize: 38
                        font.weight: Font.Black
                    }
                    Text {
                        text: IslandState.wxDesc
                        color: root.theme.accent
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(12)
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: IslandState.wxFeels !== "" ? "feels like " + IslandState.wxFeels + "°" : ""
                        color: root.theme.muted
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(11)
                    }
                }
            }

            Grid {
                columns: 2
                spacing: 6
                Repeater {
                    model: [
                        { g: "\u{e373}", l: "humidity", v: IslandState.wxHumidity !== "" ? IslandState.wxHumidity + "%" : "—" },
                        { g: "\u{e34c}", l: "wind", v: IslandState.wxWind !== "" ? IslandState.wxWind + " km/h" : "—" },
                        { g: "\u{f059b}", l: "sunrise", v: IslandState.wxSunrise || "—" },
                        { g: "\u{f059a}", l: "sunset", v: IslandState.wxSunset || "—" }
                    ]
                    Rectangle {
                        required property var modelData
                        height: 34
                        width: (nowCol.width - 6) / 2
                        radius: 10
                        color: Qt.alpha(root.theme.fg, 0.07)
                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 7
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.g
                                color: Qt.alpha(root.theme.accent, 0.85)
                                font.family: root.theme.fontMono
                                font.pixelSize: 13
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: -1
                                Text {
                                    text: modelData.v
                                    color: root.theme.fg
                                    font.family: root.theme.fontMono
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    text: modelData.l
                                    color: Qt.alpha(root.theme.muted, 0.8)
                                    font.family: root.theme.fontSans
                                    font.pixelSize: IslandState.ts(8)
                                }
                            }
                        }
                    }
                }
            }

            // ── the next 24 hours ─────────────────────────────────
            // Under the readings, in the room the column had spare. The
            // strip scrolls sideways; a hovered hour puts its conditions on
            // the line beneath.
            Item {
                width: parent.width; height: 16
                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.hoverHour === null || !root.pickedDay
                    text: root.pickedDay ? "\u{f0141}  " + Qt.formatDate(root.dayDate(root.pickedDay.date), "ddd d MMM")
                                         : "Hourly"
                    color: Qt.alpha(root.theme.on_surface_variant, 0.9)
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(11)
                    font.weight: Font.DemiBold
                    // the back chevron returns to the rolling strip
                    TapHandler {
                        enabled: root.pickedDay !== null
                        cursorShape: Qt.PointingHandCursor
                        onTapped: root.dayIndex = 0
                    }
                }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    visible: root.hoverHour !== null
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.hoverHour ? root.hoverHour.desc : ""
                        color: Qt.alpha(root.theme.muted, 0.9)
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(10)
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            const h = root.hoverHour;
                            if (!h) return "";
                            return "feels " + h.feels + "\u{00b0}"
                                 + (h.wind !== "" ? "  \u{00b7}  " + h.wind + " km/h" : "")
                                 + (parseInt(h.rain) > 0 ? "  \u{00b7}  " + h.rain + "%" : "");
                        }
                        color: Qt.alpha(root.theme.fg, 0.9)
                        font.family: root.theme.fontMono
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                }
            }

            Text {
                visible: root.hours.length === 0
                text: "No hourly data"
                color: Qt.alpha(root.theme.muted, 0.7)
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(11)
            }

            Flickable {
                id: hoursFlick
                visible: root.hours.length > 0
                width: parent.width
                height: 58
                contentWidth: hoursRow.implicitWidth
                contentHeight: height
                clip: true
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds

                // A wheel over the strip scrolls it sideways; the sheet
                // behind is vertical and would otherwise take the gesture.
                WheelHandler {
                    onWheel: (ev) => {
                        const d = ev.angleDelta.y !== 0 ? ev.angleDelta.y : ev.angleDelta.x;
                        hoursFlick.contentX = Math.max(0, Math.min(
                            hoursFlick.contentX - d * 0.6,
                            hoursFlick.contentWidth - hoursFlick.width));
                    }
                }

                Row {
                    id: hoursRow
                    spacing: 4

                    Repeater {
                        model: root.hours
                        Rectangle {
                            id: hourCell
                            required property var modelData
                            required property int index
                            readonly property bool isNow: !root.pickedDay && hourCell.index === 0
                            // midnight is labelled with the day it starts,
                            // so the strip shows where tomorrow begins
                            readonly property bool dayStart: !root.pickedDay
                                                             && hourCell.modelData.tomorrow === true
                                                             && hourCell.modelData.hour === 0
                            width: 46
                            height: 58
                            radius: 10
                            color: hourCell.isNow ? Qt.alpha(root.theme.accent, 0.18)
                                 : Qt.alpha(root.theme.fg, 0.035)
                            border.width: hourCell.isNow ? 1 : 0
                            border.color: Qt.alpha(root.theme.accent, 0.45)

                            Column {
                                anchors.centerIn: parent
                                spacing: 1
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: hourCell.isNow ? "now"
                                        : hourCell.dayStart ? Qt.formatDate(new Date(clk.date.getTime() + 86400000), "ddd")
                                        : ("0" + hourCell.modelData.hour).slice(-2) + ":00"
                                    color: hourCell.isNow || hourCell.dayStart ? root.theme.accent
                                         : Qt.alpha(root.theme.muted, 0.9)
                                    font.family: root.theme.fontMono
                                    font.pixelSize: 9
                                    font.weight: hourCell.isNow || hourCell.dayStart ? Font.Bold : Font.Normal
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: hourCell.modelData.icon
                                    color: root.theme.primary
                                    font.family: root.theme.fontMono
                                    font.pixelSize: 15
                                }
                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    spacing: 3
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: hourCell.modelData.temp + "\u{00b0}"
                                        color: root.theme.fg
                                        font.family: root.theme.fontMono
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: parseInt(hourCell.modelData.rain) > 0
                                        text: hourCell.modelData.rain + "%"
                                        color: Qt.alpha(root.theme.accent3, 0.75)
                                        font.family: root.theme.fontMono
                                        font.pixelSize: 8
                                    }
                                }
                            }

                            HoverHandler {
                                onHoveredChanged: root.hoverHour = hovered ? hourCell.modelData : null
                            }
                        }
                    }
                }
            }
        }


        // ── forecast ──────────────────────────────────────────────
        Column {
            width: parent.width - nowCol.width - 1 - 36
            spacing: 4

            Text {
                text: "Forecast"
                color: Qt.alpha(root.theme.on_surface_variant, 0.9)
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(11)
                font.weight: Font.DemiBold
                font.letterSpacing: 0.2
            }

            Item { width: 1; height: 4 }

            Text {
                visible: IslandState.wxForecast.length === 0
                text: "No forecast data"
                color: Qt.alpha(root.theme.muted, 0.7)
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(11)
            }

            Repeater {
                model: IslandState.wxForecast
                Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool picked: index === root.dayIndex
                    width: parent.width
                    height: 30
                    radius: 9
                    color: picked ? Qt.alpha(root.theme.accent, 0.16)
                         : fcHover.hovered ? Qt.alpha(root.theme.fg, 0.06) : Qt.alpha(root.theme.fg, 0.035)
                    border.width: picked ? 1 : 0
                    border.color: Qt.alpha(root.theme.accent, 0.4)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    HoverHandler { id: fcHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.dayIndex = index }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.dayName(modelData.date)
                        color: root.theme.fg
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(11)
                        font.weight: Font.DemiBold
                    }
                    Row {
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.icon
                            color: root.theme.primary
                            font.family: root.theme.fontMono
                            font.pixelSize: 14
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.rain + "%"
                            color: Qt.alpha(root.theme.accent3, 0.75)
                            font.family: root.theme.fontMono
                            font.pixelSize: 10
                        }
                    }
                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.min + "°"
                            color: Qt.alpha(root.theme.muted, 0.9)
                            font.family: root.theme.fontMono
                            font.pixelSize: 11
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "/"
                            color: Qt.alpha(root.theme.muted, 0.4)
                            font.family: root.theme.fontMono
                            font.pixelSize: 11
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.max + "°"
                            color: root.theme.fg
                            font.family: root.theme.fontMono
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                    }
                }
            }
        }
    }
}
