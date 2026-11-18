import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland

ShellRoot {
    id: root

    // The shared palette: the system theme, i.e. the one applied last. It
    // themes whatever is not tied to one screen, and is the fallback for a
    // screen with no palette of its own yet.
    property Theme theme: Theme {}
    property bool barsVisible: true

    // The island used to carry its own frozen palette (followWallpaper: false)
    // so it looked identical on both monitors and through every retheme. As of
    // 2026-08-31 it follows the wallpaper like every other surface — the pill,
    // the card and all the tools wear the palette of the monitor they are on,
    // because the bar hands its per-screen theme down through DynamicIsland.

    // One palette per monitor, keyed by output name: the theme that monitor
    // wears (ThemeSwitcher sets it per monitor or for all). Rebuilt when
    // screens come and go.
    property var themes: ({})

    function themeFor(name) {
        const t = root.themes[name];
        return t ? t : root.theme;
    }

    // Instantiator rather than Variants: these are plain objects, not windows,
    // and they must outlive any single bar so the floating overlays can borrow
    // whichever one matches the screen they are currently on.
    property var _themePool: Instantiator {
        model: Quickshell.screens

        delegate: Theme {
            required property var modelData
            output: modelData.name
        }

        onObjectAdded: (index, object) => {
            root.themes[object.output] = object;
            root.themesChanged();
        }
        onObjectRemoved: (index, object) => {
            delete root.themes[object.output];
            root.themesChanged();
        }
    }

    IpcHandler {
        target: "bar"
        function toggle(): void { root.barsVisible = !root.barsVisible; }
        function show(): void { root.barsVisible = true; }
        function hide(): void { root.barsVisible = false; }
    }

    // Notifications live in the island now: the server, toast queue and the
    // "notifications" IPC target are IslandState's; the toasts render from
    // DynamicIsland and history is the island's notifs tool.
    readonly property string wb: "@HOME@/.config/quickshell/scripts/"

    // ── TOP: session & interaction ────────────────────────────────
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: bar
            required property var modelData
            screen: modelData

            // This bar wears the theme of its own monitor.
            readonly property Theme theme: root.themeFor(modelData.name)

            // With the menu bar on, the window spans the whole edge so the band
            // can run under the island from corner to corner; the edge gap then
            // moves inside, onto the island, and the reserved strip is the same.
            readonly property bool menuBar: IslandState.cfg.menuBar
            readonly property int inGap: menuBar ? IslandState.cfg.edgeGap : 0

            // Its own namespace so Hyprland can frost the menu bar alone;
            // every other shell surface stays on the unblurred "quickshell".
            WlrLayershell.namespace: "quickshell-bar"

            anchors { top: true; left: true; right: true }
            margins { top: menuBar ? 0 : IslandState.cfg.edgeGap; left: menuBar ? 0 : 10; right: menuBar ? 0 : 10 }
            // Taller than the 46px it reserves, so the island can expand down
            // past the bar. The mask keeps input to the widgets themselves, so
            // the surplus height stays click-through for the windows under it.
            implicitHeight: Math.max(menuBar ? IslandState.barBand : 0,
                                     inGap + IslandState.cfg.pillHeightExpanded + 6 + IslandState.cfg.hoverLift)
            visible: root.barsVisible
            color: "transparent"
            // With the menu bar the reserved strip is exactly its band, so
            // windows start where the band ends — no sliver of wallpaper. In
            // notch mode that is the notch's resting height; a hovered notch
            // grows a couple of px over the windows instead of pushing them.
            exclusiveZone: menuBar ? IslandState.barBand : IslandState.cfg.pillHeightExpanded

            MenuBar {
                id: menuBarItem
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                visible: bar.menuBar
                theme: bar.theme
                screenName: modelData.name
                island: island
            }

            Row {
                id: leftGroup
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.topMargin: 3
                spacing: 6
                visible: !bar.menuBar

                ScriptPill {
                    theme: bar.theme
                    cmd: root.wb + "browser-sound.sh"
                    intervalMs: 5000
                    tint: bar.theme.accent
                }
            }

            TopTray {
                id: topTray
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 3
                theme: bar.theme
                screenName: modelData.name
                visible: !bar.menuBar && IslandState.cfg.topTray && items.length > 0
            }

            DynamicIsland {
                id: island
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: bar.inGap
                theme: bar.theme
                // The island is per-screen but its state is not, so it has to
                // be able to tell whether the open card is its own.
                screenName: modelData.name
            }

            // Declared last on purpose: the Region items resolve their ids when
            // the property is assigned, and the widgets above must already exist.
            // During a Flameshot capture everything here goes transparent
            // and click-through; the reserved strip stays.
            readonly property bool capturing: IslandState.capturingOn(modelData.name)
            Binding { target: bar.contentItem; property: "opacity"; value: bar.capturing ? 0 : 1 }
            mask: Region {
                Region { item: bar.capturing ? null : leftGroup }
                Region { item: bar.capturing ? null : island }
                Region { item: bar.capturing ? null : topTray }
                Region { item: bar.capturing ? null : menuBarItem }
            }
        }
    }

    // ── CORNERS: rounded screen corners and the corner privacy dots ──
    Variants {
        model: Quickshell.screens

        ScreenCorners {
            required property var modelData
            screen: modelData
            theme: root.themeFor(modelData.name)
            barsVisible: root.barsVisible
        }
    }

    // ── BOTTOM: dock of running apps ──────────────────────────────
    Variants {
        model: Quickshell.screens

        Dock {
            required property var modelData
            screen: modelData
            theme: root.themeFor(modelData.name)
            shown: root.barsVisible && IslandState.cfg.dock
        }
    }

    // These follow whichever monitor they appear on: the theme switcher opens
    // on the focused screen, the OSD tracks focus as it moves. Before a screen is
    // assigned, themeFor falls back to the shared palette. The app launcher
    // is no longer a window of its own: it is the island's "apps" tool.
    ThemeSwitcher {
        id: themeSwitcher
        theme: root.themeFor(themeSwitcher.screen ? themeSwitcher.screen.name : "")
    }
    Osd {
        id: osd
        theme: root.themeFor(osd.screen ? osd.screen.name : "")
    }
    IslandSettings {
        id: islandSettings
        theme: root.themeFor(islandSettings.screen ? islandSettings.screen.name : "")
    }
    PolkitPrompt {
        theme: root.themeFor(Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "")
    }
    LockScreen {
        id: lockScreen
        theme: root.theme
        themes: root.themes
    }

    // The hub's lock tile ends up here: the singleton raises the signal, and
    // this is the one place that knows the lock surface by name — the same
    // seam the settings window uses.
    Connections {
        target: IslandState
        function onLockRequested() { lockScreen.locked = true; }
        function onWallpapersRequested(theme) { themeSwitcher.browseTheme(theme); }
    }

}
