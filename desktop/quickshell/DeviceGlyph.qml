import QtQuick
import QtQuick.Shapes
import "DeviceIcons.js" as DeviceIcons

// One device's icon, the same in an island circle, the menu bar's Devices
// item, the Batteries panel and the Bluetooth radar. The icons live in
// DeviceIcons.js, each from an open icon set; this only paints one in a colour.
//   kind: airpods · iphone · phone · headphones · audio · mouse · keyboard ·
//         dualsense · dualshock · xbox · switch · gamepad · station
// A kind the set has no drawing for falls back to Material's gamepad glyph.
Item {
    id: root

    property string kind: "gamepad"
    property color color: "white"
    property string fontFamily: ""
    property real size: 16

    implicitWidth: root.size
    implicitHeight: root.size

    readonly property var icon: DeviceIcons.get(root.kind)

    Text {
        visible: root.icon === null
        anchors.centerIn: parent
        text: "\u{f0297}"
        color: root.color
        font.family: root.fontFamily
        font.pixelSize: Math.round(root.size)
    }

    Shape {
        visible: root.icon !== null
        anchors.centerIn: parent
        readonly property real grid: root.icon ? root.icon.grid : 24
        width: grid; height: grid
        scale: root.size / grid
        layer.enabled: true
        layer.samples: 8
        ShapePath {
            fillColor: root.color
            strokeColor: "transparent"
            fillRule: root.icon && root.icon.rule === "evenodd" ? ShapePath.OddEvenFill : ShapePath.WindingFill
            PathSvg { path: root.icon ? root.icon.d : "" }
        }
    }
}
