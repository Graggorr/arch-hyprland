import QtQuick

Rectangle {
    id: root

    property var theme
    property string placeholder: ""
    property string label: ""
    property alias text: input.text

    signal textEdited(string t)
    signal submitted()
    signal cancelled()

    height: 34
    radius: 10
    color: input.activeFocus ? Qt.alpha(theme.fg, 0.12) : Qt.alpha(theme.fg, 0.07)
    border.width: input.activeFocus ? 1 : 0
    border.color: Qt.alpha(theme.accent, 0.45)
    Behavior on color { ColorAnimation { duration: 120 } }

    function focusField() { input.forceActiveFocus(); }

    Text {
        id: lbl
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        visible: root.label !== ""
        text: root.label
        color: Qt.alpha(root.theme.muted, 0.8)
        font.family: root.theme.fontSans
        font.pixelSize: IslandState.ts(10)
        font.weight: Font.DemiBold
    }

    TextInput {
        id: input
        anchors.left: root.label !== "" ? lbl.right : parent.left
        anchors.leftMargin: 10
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        color: root.theme.fg
        font.family: root.theme.fontSans
        font.pixelSize: IslandState.ts(12)
        selectionColor: Qt.alpha(root.theme.accent, 0.35)
        selectByMouse: true
        clip: true

        onTextChanged: root.textEdited(text)
        Keys.onReturnPressed: root.submitted()
        Keys.onEnterPressed: root.submitted()
        Keys.onEscapePressed: root.cancelled()

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: input.text === "" && !input.activeFocus
            text: root.placeholder
            color: Qt.alpha(root.theme.muted, 0.65)
            font.family: root.theme.fontSans
            font.pixelSize: IslandState.ts(12)
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onClicked: input.forceActiveFocus()
        z: -1
    }
}
