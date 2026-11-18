import QtQuick
import Quickshell
import Quickshell.Widgets

// The system tray as a strip at the right end of the top bar, beside the
// island — the at-a-glance view the tray tool alone could not give.
//
// It never opens a menu of its own. A right-click (or a left-click on an item
// that only has a menu) opens the island's tray tool on that item, where the
// menu is drawn inside the card; a popup here would take a second focus grab
// and close the card, which is the trap TrayTool exists to avoid.
// In the menu bar a left-click is the exception: there is no card open, so the
// bar drops the item's own menu under the icon, the macOS way.
Rectangle {
    id: root

    property var theme
    property string screenName: ""
    // Inside the menu bar the strip is just icons: the bar is the background.
    property bool flat: false
    // In the menu bar a left-click asks the bar for the item's own dropdown
    // under the icon instead of opening the tray tool.
    signal menuAt(var item, Item slot)

    // The menu bar draws its own network and Bluetooth icons, so the
    // applets that only show the same state (nm-applet, blueman) are left
    // out of its tray. They stay in the island's tray tool for their menus.
    readonly property var duplicates: ["nm-applet", "blueman"]
    readonly property var items: root.flat
        ? IslandState.trayItems.filter(it => root.duplicates.indexOf(it.id) < 0)
        : IslandState.trayItems
    property var hoveredItem: null
    // Centre of the hovered icon in the pill's coordinates; the tooltip hangs
    // under that point instead of under the pill's left edge.
    property real hoveredX: 0

    visible: items.length > 0
    implicitHeight: IslandState.cfg.pillHeight
    implicitWidth: row.implicitWidth + 16
    radius: height / 2
    color: root.flat ? "transparent"
         : Qt.rgba(theme.islandBg.r, theme.islandBg.g, theme.islandBg.b,
                   IslandState.cfg.islandOpacity)
    border.width: root.flat ? 0 : 1
    border.color: Qt.alpha(theme.accent, 0.06)

    Behavior on implicitWidth { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 2

        Repeater {
            model: root.items

            Item {
                id: slot
                required property var modelData
                readonly property string glyph: TrayIcons.nativeGlyph(modelData.id)

                width: 28
                height: 28

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Qt.alpha(root.theme.fg, 0.12)
                    opacity: sh.hovered ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }

                IconImage {
                    anchors.centerIn: parent
                    width: 16; height: 16
                    source: slot.modelData.icon
                    visible: slot.glyph === ""
                    asynchronous: true
                }
                Text {
                    anchors.centerIn: parent
                    visible: slot.glyph !== ""
                    text: slot.glyph
                    color: TrayIcons.nativeColor(slot.modelData.id)
                    font.family: root.theme.fontMono
                    font.pixelSize: 15
                    Behavior on color { ColorAnimation { duration: 180 } }
                }

                HoverHandler {
                    id: sh
                    cursorShape: Qt.PointingHandCursor
                    onHoveredChanged: {
                        if (hovered) {
                            root.hoveredItem = slot.modelData;
                            root.hoveredX = row.x + slot.x + slot.width / 2;
                            tipDelay.restart();
                        }
                        else if (root.hoveredItem === slot.modelData) {
                            root.hoveredItem = null;
                            tipDelay.stop();
                            tip.visible = false;
                        }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: (e) => {
                        tip.visible = false;
                        const it = slot.modelData;
                        if (e.button === Qt.MiddleButton) it.secondaryActivate();
                        else if (root.flat && e.button === Qt.LeftButton && it.menu)
                            root.menuAt(it, slot);
                        else if (e.button === Qt.RightButton || it.onlyMenu)
                            IslandState.openTrayItem(it.id, root.screenName, root.flat);
                        else it.activate();
                    }
                    onWheel: (e) => slot.modelData.scroll(e.angleDelta.y, false)
                }
            }
        }
    }

    readonly property string tipText: {
        const it = root.hoveredItem;
        if (!it) return "";
        const name = TrayIcons.displayName(it);
        const t = it.tooltipTitle || "";
        return t !== "" && t !== name ? name + "\n" + t : name;
    }

    Tooltip {
        id: tip
        theme: root.theme
        body: root.tipText
        fillColor: Qt.rgba(root.theme.islandBg.r, root.theme.islandBg.g,
                           root.theme.islandBg.b, IslandState.cfg.islandOpacity)
        textColor: root.theme.fg
        borderColor: Qt.alpha(root.theme.accent, 0.28)
        anchor.item: root
        anchor.rect.y: root.height + 6
        anchor.rect.x: root.hoveredX - tip.implicitWidth / 2
    }
    Timer {
        id: tipDelay
        interval: 350
        onTriggered: if (root.hoveredItem && root.tipText !== "") tip.visible = true
    }
}
