import QtQuick
import Quickshell

PopupWindow {
    id: root

    property var theme
    property string body: ""
    // Inverse tones by default; a surface that sits on the island's own black
    // (the top-bar tray) passes its palette so the tip reads as part of it.
    property color fillColor: theme.inverse_surface
    property color textColor: theme.inverse_on_surface
    property color borderColor: "transparent"

    // Waybar tooltips carry Pango markup; strip it and render monospace so the
    // <tt> aligned tables (cpu cores, pcpower breakdown) keep their columns.
    readonly property string plain: body
        .replace(/<br\s*\/?>/g, "\n")
        .replace(/<[^>]+>/g, "")
        .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&")
        .trim()

    implicitWidth: Math.min(560, txt.implicitWidth + 28)
    implicitHeight: txt.implicitHeight + 20
    color: "transparent"
    visible: false

    // Material's inverse surface: a tooltip is an annotation *about* the UI,
    // not part of it, and flipping the tones is what separates the two. It
    // also needs no border and no translucency to stay legible anywhere.
    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: 10
        color: root.fillColor
        border.width: 1
        border.color: root.borderColor

        Text {
            id: txt
            anchors.centerIn: parent
            text: root.plain
            color: root.textColor
            font.family: root.theme.fontMono
            font.pixelSize: 11
            lineHeight: 1.15
            textFormat: Text.PlainText
        }
    }
}
