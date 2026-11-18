import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Mpris

// Shared body of the lock screen. `primary` picks the layout: the main monitor
// carries the password field, the secondary is a full-bleed now-playing panel.
// Kept separate from LockScreen.qml so it can be previewed without locking.
Item {
    id: root

    property var theme
    property bool primary: true
    property string screenName: ""
    readonly property string pw: lockIsland.lockPw
    property string err: ""
    property bool busy: false
    property alias inputItem: lockIsland.lockInput

    signal submitted()

    // A miss shakes the island and empties it, the way the phone does.
    onErrChanged: if (err !== "" && primary) {
        lockIsland.lockShake();
        lockIsland.lockInput.text = "";
    }

    SystemClock { id: clk; precision: SystemClock.Seconds }

    // ── background ───────────────────────────────────────────────
    // Palette-derived gradient, only visible when the wallpaper image below
    // fails to load.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.theme.surface_container }
            GradientStop { position: 0.55; color: root.theme.surface }
            GradientStop { position: 1.0; color: Qt.darker(root.theme.surface_container_lowest, 1.4) }
        }
    }

    // Each lock surface resolves its own output's wallpaper live out of
    // wallpapers.py's state file — nothing runs per wallpaper change to keep
    // the lock current (the old .lockscreen-bg-<output> symlinks are gone).
    // A Wallpaper Engine entry carries the scene's preview path, written by
    // wallpapers.py at set time, since the animated scene cannot be rendered
    // here. The gradient above shows through when nothing resolves (no entry
    // for this output yet, or /mnt/games unmounted).
    FileView {
        path: "@HOME@/.config/hypr/wallpapers.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.wallStateText = text()
    }
    property string wallStateText: ""
    property bool bgFallback: false

    readonly property string bgPath: {
        let st = {};
        try { st = JSON.parse(root.wallStateText); } catch (e) { return ""; }
        const entry = st[root.screenName];
        if (!entry) return "";
        return (entry.kind === "we" ? entry.preview : entry.path) || "";
    }
    onBgPathChanged: bgFallback = false

    // The desktop's hyprglass preset, parsed live out of hyprland.lua so the
    // lock wallpaper always wears the same glass the windows do — edit the
    // preset and the lock follows on its own (grade comes from the sub-table
    // default_theme selects). Only the backdrop treatment is reproducible
    // here: blur radius = strength * 2^iterations * 3 mapped onto blurMax 64
    // (the *3 is calibration — hyprglass's dual-kawase spreads much wider than
    // the nominal radius; matched by eye against a fullscreen glass terminal
    // on 2026-09-11), the multiplicative grade factors shifted to
    // MultiEffect's additive ranges,
    // vibrancy folded into saturation at half weight, and adaptive_dim as a
    // flat half-strength scrim (the plugin dims relative to backdrop
    // luminance, which a static overlay cannot). The optics — refraction,
    // lens distortion, chromatic aberration, fresnel rim, specular sheen —
    // are approximated by shaders/glass.frag (compiled to .qsb; see the
    // comment there), fed the preset values parsed here.
    // Fallbacks mirror the preset as of 2026-09-11.
    FileView {
        path: "@HOME@/.config/hypr/hyprland.lua"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.hyprConfText = text()
    }
    property string hyprConfText: ""

    readonly property var glass: {
        const fb = { blur: 0.96, brightness: -0.18, contrast: -0.10,
                     saturation: -0.125, dim: 0.4, refraction: 0.55,
                     aberration: 0.3, fresnel: 0.5, specular: 0.75,
                     edge: 0.05, lens: 0.3 };
        const preset = /hg\.preset\(\s*"main"\s*,\s*\{([\s\S]*?)\}\s*\)/
                       .exec(root.hyprConfText);
        if (!preset) return fb;
        const body = preset[1];
        const num = (src, key, dflt) => {
            const m = new RegExp(key + "\\s*=\\s*(-?[0-9.]+)").exec(src);
            return m ? parseFloat(m[1]) : dflt;
        };
        const themeName =
            (/default_theme\s*=\s*"(\w+)"/.exec(root.hyprConfText) || [, "dark"])[1];
        const sub = new RegExp(themeName + "\\s*=\\s*\\{([^}]*)\\}").exec(body);
        const grade = sub ? sub[1] : "";
        const radius = num(body, "blur_strength", 2.2)
                       * Math.pow(2, num(body, "blur_iteration", 3));
        return {
            blur: Math.min(1, radius * 3.5 / 64),
            brightness: num(grade, "brightness", 0.82) - 1,
            contrast: num(grade, "contrast", 0.90) - 1,
            saturation: num(grade, "saturation", 0.80) - 1
                        + num(grade, "vibrancy", 0.15) * 0.5,
            dim: num(grade, "adaptive_dim", 0),
            refraction: num(body, "refraction_strength", 0.55),
            aberration: num(body, "chromatic_aberration", 0.3),
            fresnel: num(body, "fresnel_strength", 0.5),
            specular: num(body, "specular_strength", 0.75),
            edge: num(body, "edge_thickness", 0.05),
            lens: num(body, "lens_distortion", 0.3)
        };
    }

    Image {
        id: bg
        anchors.fill: parent
        source: (root.bgPath !== "" && !root.bgFallback)
                ? "file://" + root.bgPath : ""
        onStatusChanged: if (status === Image.Error && !root.bgFallback) root.bgFallback = true
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        visible: false
        layer.enabled: true
    }

    MultiEffect {
        id: bgGraded
        anchors.fill: parent
        source: bg
        blurEnabled: true
        blur: root.glass.blur
        blurMax: 64
        brightness: root.glass.brightness
        contrast: root.glass.contrast
        saturation: root.glass.saturation
        visible: false
        layer.enabled: true
    }

    ShaderEffect {
        anchors.fill: parent
        property var source: bgGraded
        property real refraction: root.glass.refraction
        property real aberration: root.glass.aberration
        property real fresnel: root.glass.fresnel
        property real specular: root.glass.specular
        property real edge: root.glass.edge
        property real lens: root.glass.lens
        fragmentShader: Qt.resolvedUrl("shaders/glass.frag.qsb")
        visible: bg.status === Image.Ready
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: root.glass.dim * 0.5
        visible: bg.status === Image.Ready
    }

    // diagonal accent wash
    Rectangle {
        anchors.fill: parent
        rotation: 20
        scale: 1.7
        opacity: 0.55
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.alpha(root.theme.accent, 0.55) }
            GradientStop { position: 0.45; color: "transparent" }
            GradientStop { position: 1.0; color: Qt.alpha(root.theme.accent2, 0.40) }
        }
    }

    // soft vignette
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.30) }
            GradientStop { position: 0.5; color: Qt.rgba(0, 0, 0, 0.10) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.55) }
        }
    }

    // ── weather + sun, read from the caches the bar already fills ─
    QtObject {
        id: wx
        property string temp: ""
        property string place: ""
        property string desc: ""
        property string sun: ""
    }

    FileView {
        path: "/tmp/qs-weather.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const j = JSON.parse(text());
                wx.temp = (j.text || "").trim();
                const lines = (j.tooltip || "").split("\n");
                wx.place = lines.length > 0 ? lines[0].trim() : "";
                wx.desc = lines.length > 1 ? lines[1].split("—")[0].trim() : "";
            } catch (e) { /* cache not ready */ }
        }
    }

    FileView {
        path: "/tmp/qs-sun"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const L = text().trim().split("\n");
            if (L.length < 2) return;
            const to24 = (s) => {
                const m = /(\d{1,2}):(\d{2})\s*(AM|PM)/i.exec(s || "");
                if (!m) return "";
                let h = parseInt(m[1]) % 12;
                if (m[3].toUpperCase() === "PM") h += 12;
                return (h < 10 ? "0" : "") + h + ":" + m[2];
            };
            const set = to24(L[0]);
            const rise = to24(L[1]);
            const now = clk.date;
            const sp = set.split(":");
            const sd = new Date(now); sd.setHours(parseInt(sp[0]), parseInt(sp[1]), 0, 0);
            wx.sun = now < sd ? "\u{f059a} " + set : "\u{f059b} " + rise;
        }
    }

    readonly property var player: {
        const all = Mpris.players.values;
        for (let i = 0; i < all.length; i++)
            if (String(all[i].dbusName).toLowerCase().indexOf("spotify") !== -1) return all[i];
        return all.length > 0 ? all[0] : null;
    }
    readonly property bool hasMedia: player !== null && player.trackTitle !== ""
    readonly property real mediaProgress: (player && player.length > 0)
        ? Math.max(0, Math.min(1, posTick.pos / player.length)) : 0

    // Keyboard layout — the point is catching "I'm typing my password in
    // Russian" before submitting, so it polls fast and shouts when not English.
    property string kbLayout: ""
    readonly property bool kbEnglish: kbLayout === "EN"

    Process {
        id: kbProc
        command: ["bash", "-c",
                  "@HOME@/.config/quickshell/scripts/kb-layout.sh get"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text.trim();
                if (t === "") return;
                const l = t.toLowerCase();
                root.kbLayout = l.indexOf("english") === 0 ? "EN"
                              : l.indexOf("russian") === 0 ? "RU"
                              : l.indexOf("ukrain") === 0 ? "UA"
                              : t.slice(0, 2).toUpperCase();
            }
        }
    }

    Timer {
        interval: 400
        running: root.primary
        repeat: true
        triggeredOnStart: true
        onTriggered: kbProc.running = true
    }

    function fmt(sec) {
        if (!sec || sec <= 0) return "0:00";
        const s = Math.floor(sec);
        return Math.floor(s / 60) + ":" + ("0" + (s % 60)).slice(-2);
    }

    QtObject { id: posTick; property real pos: 0 }
    Timer {
        interval: 1000
        running: root.hasMedia
        repeat: true
        triggeredOnStart: true
        onTriggered: if (root.player) posTick.pos = root.player.position
    }

    // ── layout ───────────────────────────────────────────────────
    // ═══ PRIMARY: clock + password + keyboard layout ══════════════
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -80
        spacing: 0
        visible: root.primary

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12

            Text {
                id: lockClock
                text: IslandState.clockHours(clk.date)
                      + ":" + ("0" + clk.date.getMinutes()).slice(-2)
                color: "white"
                font.family: root.theme.fontClock
                font.features: root.theme.clockFeatures
                font.pixelSize: 104
                font.weight: Font.Light
            }

            Text {
                anchors.baseline: lockClock.baseline
                visible: !IslandState.cfg.clock24h
                text: clk.date.getHours() < 12 ? "AM" : "PM"
                color: Qt.rgba(1, 1, 1, 0.6)
                font.family: root.theme.fontClock
                font.features: root.theme.clockFeatures
                font.pixelSize: 34
                font.weight: Font.Light
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clk.date, "dddd, d MMMM")
            color: Qt.rgba(1, 1, 1, 0.72)
            font.family: root.theme.fontSans
            font.pixelSize: IslandState.ts(17)
        }

    }

    // ── notifications, iPhone-style ───────────────────────────────
    // A read-only mirror of the island's live notification list, stacked as
    // frosted cards under the password area. Deliberately no actions, no
    // dismiss, no app raising: acting on a notification requires unlocking,
    // both because raising an app under a session lock cannot work and
    // because the lock screen must not be a way to poke the session.
    Item {
        visible: root.primary && IslandState.notifs.length > 0
        width: 430
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.verticalCenter
        // Clears the clock and date above the centre.
        anchors.topMargin: 20
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 64

        ListView {
            id: lockNotifs
            anchors.fill: parent
            // The server tracks in arrival order; reversed here so the
            // freshest card sits on top of the stack, like the phone.
            model: IslandState.notifs.slice().reverse()
            spacing: 8
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                id: lockRow
                required property var modelData

                width: ListView.view.width
                height: lockBody.implicitHeight + 26
                radius: 22
                color: Qt.rgba(1, 1, 1, 0.13)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.10)

                Row {
                    id: lockBody
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 12

                    IconImage {
                        width: 34; height: 34
                        anchors.verticalCenter: parent.verticalCenter
                        source: lockRow.modelData.image !== ""
                                ? lockRow.modelData.image
                                : Quickshell.iconPath(lockRow.modelData.appIcon,
                                                      "dialog-information")
                        asynchronous: true
                    }

                    Column {
                        width: parent.width - 46 - 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        // Summary and age share a line, the same split the
                        // island's history tool uses.
                        Item {
                            width: parent.width
                            height: lockSum.implicitHeight

                            Text {
                                id: lockSum
                                anchors.left: parent.left
                                anchors.right: lockAge.left
                                anchors.rightMargin: 8
                                text: lockRow.modelData.summary !== ""
                                      ? lockRow.modelData.summary
                                      : lockRow.modelData.appName
                                color: "white"
                                font.family: root.theme.fontSans
                                font.pixelSize: IslandState.ts(13)
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            Text {
                                id: lockAge
                                anchors.right: parent.right
                                anchors.baseline: lockSum.baseline
                                text: IslandState.notifAge(lockRow.modelData)
                                visible: text !== ""
                                color: Qt.rgba(1, 1, 1, 0.5)
                                font.family: root.theme.fontMono
                                font.pixelSize: 10
                            }
                        }

                        Text {
                            width: parent.width
                            text: lockRow.modelData.body
                            visible: text !== ""
                            color: Qt.rgba(1, 1, 1, 0.75)
                            font.family: root.theme.fontSans
                            font.pixelSize: IslandState.ts(12)
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            textFormat: Text.StyledText
                        }
                    }
                }
            }
        }

        // Soft fade at the stack's bottom edge so a long list reads as
        // "scrolls", not "cut off".
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 28
            visible: !lockNotifs.atYEnd
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.35) }
            }
        }
    }

    Text {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 36
        visible: root.primary
        text: Quickshell.env("USER") || ""
        color: Qt.rgba(1, 1, 1, 0.45)
        font.family: root.theme.fontSans
        font.pixelSize: IslandState.ts(12)
    }

    // ═══ SECONDARY: ambient clock + now-playing hero ═════════════
    Item {
        anchors.fill: parent
        visible: !root.primary

        Column {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.leftMargin: 96
            anchors.topMargin: 84
            spacing: -22

            Text {
                text: IslandState.clockHours(clk.date)
                color: Qt.rgba(1, 1, 1, 0.92)
                font.family: root.theme.fontClock
                font.features: root.theme.clockFeatures
                font.pixelSize: 180
                font.weight: Font.Thin
            }
            Row {
                spacing: 14

                Text {
                    id: ambMm
                    text: Qt.formatDateTime(clk.date, "mm")
                    color: Qt.alpha(root.theme.accent, 0.85)
                    font.family: root.theme.fontClock
                    font.features: root.theme.clockFeatures
                    font.pixelSize: 180
                    font.weight: Font.Thin
                }
                Text {
                    anchors.baseline: ambMm.baseline
                    text: clk.date.getHours() < 12 ? "AM" : "PM"
                    color: Qt.rgba(1, 1, 1, 0.55)
                    font.family: root.theme.fontClock
                    font.features: root.theme.clockFeatures
                    font.pixelSize: 44
                    font.weight: Font.Thin
                }
            }
            Text {
                topPadding: 34
                text: Qt.formatDateTime(clk.date, "dddd, d MMMM").toUpperCase()
                color: Qt.rgba(1, 1, 1, 0.55)
                font.family: root.theme.fontSans
                font.pixelSize: IslandState.ts(15)
                font.letterSpacing: 5
            }
        }

        Row {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: 96
            anchors.topMargin: 96
            spacing: 18
            visible: wx.temp !== ""

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: wx.temp
                color: "white"
                font.family: root.theme.fontMono
                font.pixelSize: 40
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                Text {
                    text: wx.desc
                    color: Qt.rgba(1, 1, 1, 0.78)
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(15)
                }
                Text {
                    text: wx.place
                    color: Qt.rgba(1, 1, 1, 0.5)
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(12)
                }
                Text {
                    text: wx.sun
                    visible: text !== ""
                    color: Qt.alpha(root.theme.accent, 0.75)
                    font.family: root.theme.fontMono
                    font.pixelSize: 12
                }
            }
        }

        Row {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 96
            anchors.bottomMargin: 110
            spacing: 26
            visible: root.hasMedia

            ClippingRectangle {
                width: 190; height: 190; radius: 20
                anchors.verticalCenter: parent.verticalCenter
                color: Qt.rgba(1, 1, 1, 0.08)
                Image {
                    anchors.fill: parent
                    source: root.player && root.player.trackArtUrl ? root.player.trackArtUrl : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 380; sourceSize.height: 380
                    asynchronous: true
                }
            }

            Column {
                width: 340
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Text {
                    text: root.player && root.player.isPlaying ? "NOW PLAYING" : "PAUSED"
                    color: Qt.alpha(root.theme.accent, 0.9)
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(10)
                    font.letterSpacing: 3
                    font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    text: root.player ? root.player.trackTitle : ""
                    color: "white"
                    font.family: root.theme.fontDisplay
                    font.pixelSize: 26
                    font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: root.player ? root.player.trackArtist : ""
                    color: Qt.rgba(1, 1, 1, 0.65)
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(15)
                    elide: Text.ElideRight
                }

                Item { width: 1; height: 6 }

                Rectangle {
                    width: parent.width; height: 4; radius: 2
                    color: Qt.rgba(1, 1, 1, 0.16)
                    Rectangle {
                        width: parent.width * root.mediaProgress
                        height: parent.height; radius: 2
                        color: root.theme.primary
                        Behavior on width { NumberAnimation { duration: 900 } }
                    }
                }
                Item {
                    width: parent.width; height: 14
                    Text {
                        anchors.left: parent.left
                        text: root.fmt(posTick.pos)
                        color: Qt.rgba(1, 1, 1, 0.5)
                        font.family: root.theme.fontMono
                        font.pixelSize: 10
                    }
                    Text {
                        anchors.right: parent.right
                        text: root.player ? root.fmt(root.player.length) : ""
                        color: Qt.rgba(1, 1, 1, 0.5)
                        font.family: root.theme.fontMono
                        font.pixelSize: 10
                    }
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 40
            text: "\u{f033e}  password on the main display"
            color: Qt.rgba(1, 1, 1, 0.30)
            font.family: root.theme.fontSans
            font.pixelSize: IslandState.ts(11)
            font.letterSpacing: 1
        }
    }

    // ── the real bar: menu bar (when it is on) and the island ────
    // The same components the desktop bar draws, placed where the bar puts
    // them, so locking leaves the top edge exactly as it was. The menu bar
    // works as on the desktop; its dropdowns and the island's panels are
    // drawn inside the lock surface (no popup can hang off one). The island
    // pill itself is inert, and on the main display it is the password field.
    // Any click on the lock surface hands focus back to the password.
    // A click on the wallpaper is a click away: it closes whatever the bar
    // opened, like the focus grab does on the desktop.
    MouseArea {
        anchors.fill: parent
        z: -1
        onPressed: {
            lockBar.closeMenus();
            if (IslandState.cardOpen) IslandState.closeCard();
            if (root.primary) lockIsland.lockInput.forceActiveFocus();
        }
    }

    // Typing goes back to the password once a menu or panel is put away.
    function refocus() { if (root.primary) lockIsland.lockInput.forceActiveFocus(); }
    Connections {
        target: IslandState
        function onCardOpenChanged() { if (!IslandState.cardOpen) root.refocus(); }
    }

    MenuBar {
        id: lockBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        visible: IslandState.cfg.menuBar
        inSurface: true
        theme: root.theme
        screenName: root.screenName
        island: lockIsland
        onDropdownClosed: root.refocus()
    }

    DynamicIsland {
        id: lockIsland
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: IslandState.cfg.edgeGap
        theme: root.theme
        screenName: root.screenName
        lockMode: true
        lockAuth: root.primary
        lockErr: root.err
        lockBusy: root.busy
        lockLayout: root.kbLayout
        onLockSubmitted: root.submitted()
    }

    // Typing again clears the error. Raised as a signal rather than written
    // here: err is bound from LockScreen, and assigning it would cut that
    // binding, so the next miss would never show.
    signal edited()
    Connections {
        target: lockIsland.lockInput
        function onTextChanged() { if (lockIsland.lockInput.text !== "") root.edited(); }
    }
}
