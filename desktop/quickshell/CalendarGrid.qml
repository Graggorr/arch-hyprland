import QtQuick

Item {
    id: root

    property var theme
    property date shown: new Date()
    // iso date -> { count, colors } from `calendar-agenda month`
    property var marks: ({})
    property string selected: ""

    signal daySelected(string iso)
    signal monthChanged(int year, int month)

    readonly property int cellW: 32
    readonly property int cellH: 34

    implicitWidth: 7 * cellW + 6 * 2
    implicitHeight: head.height + 10 + grid.implicitHeight

    function reset() {
        shown = new Date();
        selected = root.iso(new Date());
    }

    function iso(d) {
        return d.getFullYear() + "-"
             + ("0" + (d.getMonth() + 1)).slice(-2) + "-"
             + ("0" + d.getDate()).slice(-2);
    }

    function step(delta) {
        const d = new Date(shown);
        d.setDate(1);
        d.setMonth(d.getMonth() + delta);
        shown = d;
        monthChanged(d.getFullYear(), d.getMonth() + 1);
    }

    Item {
        id: head
        width: parent.width
        height: 24

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(root.shown, "MMMM yyyy")
            color: root.theme.fg
            font.family: root.theme.fontDisplay
            font.pixelSize: IslandState.ts(16)
            font.weight: Font.Bold
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Repeater {
                model: [{ g: "\u{f0141}", d: -1 }, { g: "\u{f0142}", d: 1 }]
                Rectangle {
                    required property var modelData
                    width: 20; height: 20; radius: 6
                    color: nav.containsMouse ? Qt.alpha(root.theme.fg, 0.12) : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text {
                        anchors.centerIn: parent
                        text: modelData.g
                        color: nav.containsMouse ? root.theme.fg : root.theme.muted
                        font.family: root.theme.fontMono
                        font.pixelSize: 12
                    }
                    MouseArea {
                        id: nav
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.step(modelData.d)
                    }
                }
            }
        }
    }

    Grid {
        id: grid
        anchors.top: head.bottom
        anchors.topMargin: 10
        columns: 7
        spacing: 2

        Repeater {
            model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
            Item {
                required property int index
                required property var modelData
                width: root.cellW; height: 18
                Text {
                    anchors.centerIn: parent
                    text: modelData
                    color: index > 4 ? Qt.alpha(root.theme.accent2, 0.75)
                                     : Qt.alpha(root.theme.muted, 0.8)
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(10)
                    font.weight: Font.DemiBold
                }
            }
        }

        Repeater {
            model: 42
            Item {
                id: cell
                required property int index
                readonly property var info: {
                    const first = new Date(root.shown.getFullYear(), root.shown.getMonth(), 1);
                    const offset = (first.getDay() + 6) % 7;
                    const d = new Date(first);
                    d.setDate(1 - offset + index);
                    const now = new Date();
                    return {
                        day: d.getDate(),
                        iso: root.iso(d),
                        weekend: (d.getDay() + 6) % 7 > 4,
                        inMonth: d.getMonth() === root.shown.getMonth(),
                        today: d.toDateString() === now.toDateString()
                    };
                }
                readonly property var mark: root.marks[info.iso] || null
                readonly property bool isSelected: root.selected === info.iso

                width: root.cellW; height: root.cellH

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 1
                    width: 26; height: 24
                    radius: cell.info.today ? 12 : 8
                    color: cell.info.today ? root.theme.accent
                         : cell.isSelected ? Qt.alpha(root.theme.accent, 0.18)
                         : dayHover.hovered ? Qt.alpha(root.theme.fg, 0.10)
                         : "transparent"
                    border.width: cell.isSelected && !cell.info.today ? 1 : 0
                    border.color: Qt.alpha(root.theme.accent, 0.55)
                    Behavior on color { ColorAnimation { duration: 130 } }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 6
                    text: cell.info.day
                    color: cell.info.today ? root.theme.base
                         : !cell.info.inMonth ? Qt.alpha(root.theme.muted, 0.32)
                         : cell.info.weekend ? root.theme.accent2
                         : root.theme.fg
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(12)
                    font.weight: cell.info.today ? Font.Bold : Font.Normal
                }

                // Up to three dots, one per calendar with something that day.
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 27
                    spacing: 3
                    visible: cell.mark !== null && cell.info.inMonth
                    Repeater {
                        model: cell.mark ? cell.mark.colors.slice(0, 3) : []
                        Rectangle {
                            required property var modelData
                            width: 4; height: 4; radius: 2
                            color: cell.info.today ? root.theme.base : modelData
                            opacity: cell.info.inMonth ? 1 : 0.35
                        }
                    }
                }

                HoverHandler { id: dayHover }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        root.selected = cell.info.iso;
                        root.daySelected(cell.info.iso);
                    }
                }
            }
        }
    }
}
