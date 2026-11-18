import QtQuick

// A panel's section heading, in the hub's voice: plain text at the size of a
// card label, not an accent-coloured title. The accent is for state.
Text {
    property var theme
    color: Qt.alpha(theme.on_surface_variant, 0.9)
    font.family: theme.fontSans
    font.pixelSize: IslandState.ts(11)
    font.weight: Font.DemiBold
    font.letterSpacing: 0.2
}
