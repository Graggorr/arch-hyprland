import QtQuick
import Quickshell.Io
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets

// Now playing, as a tool. The playing state on the pill, the waves and the
// player selection all live in IslandState; this is the full-size view over
// the same data.
Item {
    id: root

    property var theme

    readonly property real preferredHeight:
        (spot.authed ? 372 : 330) + (root.volSupported ? 68 : 0)

    // ── Spotify Web API extras ────────────────────────────────────
    // Shuffle, repeat and Liked Songs go through spotify-ctl.sh: the Linux
    // client's MPRIS advertises CanControl and then silently ignores writes to
    // Shuffle/LoopStatus, and liking a track has no MPRIS surface at all.
    // Dormant until `spotify-ctl.sh auth` has been run once — the row simply
    // does not exist before that.
    QtObject {
        id: spot
        property bool authed: false
        property bool premium: false
        property bool shuffle: false
        property string repeat: "off"
        property bool liked: false
        property bool busy: false
        // Spotify forbids shuffle/repeat in some playback states (autoplay,
        // radio) and reports it; the buttons dim rather than 403 on click.
        property bool canShuffle: false
        property bool canRepeat: false
    }

    function ingestSpot(raw) {
        spot.busy = false;
        try {
            const j = JSON.parse((raw || "").trim());
            if (j.error) { spot.authed = j.error !== "noauth" && spot.authed; return; }
            spot.authed = true;
            spot.premium = !!j.premium;
            spot.shuffle = !!j.shuffle;
            spot.repeat = j.repeat || "off";
            spot.liked = !!j.liked;
            spot.canShuffle = !!j.canShuffle;
            spot.canRepeat = !!j.canRepeat;
        } catch (e) { /* keep the last good reading */ }
    }

    Process {
        id: spotStatus
        command: ["bash", "@HOME@/.config/quickshell/scripts/spotify-ctl.sh", "status"]
        stdout: StdioCollector { onStreamFinished: root.ingestSpot(this.text) }
    }
    Process {
        id: spotAction
        stdout: StdioCollector {
            // Actions echo their new state; folding it in directly makes the
            // button flip instantly instead of after the next poll.
            onStreamFinished: {
                try {
                    const j = JSON.parse(this.text.trim());
                    if (j.shuffle !== undefined) spot.shuffle = !!j.shuffle;
                    if (j.repeat !== undefined) spot.repeat = j.repeat;
                    if (j.liked !== undefined) spot.liked = !!j.liked;
                } catch (e) { /* next poll corrects it */ }
                spot.busy = false;
            }
        }
    }
    function spotRun(verb) {
        if (spot.busy) return;
        spot.busy = true;
        spotAction.command = ["bash", "@HOME@/.config/quickshell/scripts/spotify-ctl.sh", verb];
        spotAction.running = true;
    }

    Timer {
        interval: 5000
        running: root.showing && root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: spotStatus.running = true
    }

    // Shared with the pill's track flash so both mean the same player.
    readonly property var player: IslandState.player
    readonly property bool active: player !== null && player.trackTitle !== ""
    readonly property bool showing: IslandState.tool === "media"

    // ── raise the player's window ─────────────────────────────────
    // MPRIS gives us the track but no way back to the app, so the artwork
    // doubles as "take me there". The window is found the same way the
    // launcher and the notification actions find theirs: by matching the
    // player's advertised identity against the toplevel classes, since MPRIS
    // carries no pid and Hyprland carries no dbus name.
    property bool artHovered: false

    function tokens(s) {
        return String(s || "").toLowerCase()
            .replace(/[^a-z0-9]+/g, " ")
            .trim().split(" ")
            .filter(t => t.length > 2);
    }

    readonly property var playerWindow: {
        const p = root.player;
        if (!p) return null;
        // The bus name is the only identity every player has; the leading
        // org.mpris.MediaPlayer2. and any .instance<pid> suffix are noise.
        const bus = String(p.dbusName || "")
            .replace(/^org\.mpris\.MediaPlayer2\./, "").split(".")[0];
        const want = root.tokens(String(p.desktopEntry || "").replace(/\.desktop$/, ""))
            .concat(root.tokens(p.identity))
            .concat(root.tokens(bus));
        if (want.length === 0) return null;

        const tops = Hyprland.toplevels.values;
        for (let i = 0; i < tops.length; i++) {
            const o = tops[i].lastIpcObject;
            if (!o) continue;
            const have = root.tokens(o["class"]).concat(root.tokens(o.initialClass));
            for (let j = 0; j < want.length; j++)
                if (have.indexOf(want[j]) !== -1) return tops[i];
        }
        return null;
    }

    // Spotify closes to the tray while keeping MPRIS alive, so a missing
    // window is not a missing app — re-executing the entry raises the
    // running instance instead of starting a second one.
    readonly property var playerEntry: {
        const p = root.player;
        if (!p) return null;
        const id = String(p.desktopEntry || "").replace(/\.desktop$/, "");
        if (id === "") return null;
        return DesktopEntries.heuristicLookup(id);
    }

    readonly property bool canFocus: playerWindow !== null || playerEntry !== null

    function focusPlayer() {
        const tl = root.playerWindow;
        if (tl) {
            Hyprland.dispatch('hl.dsp.focus({ window = "address:0x' + tl.address + '" })');
            IslandState.closeCard();
            return;
        }
        if (root.playerEntry) {
            root.playerEntry.execute();
            IslandState.closeCard();
        }
    }

    // ── the player's own volume ───────────────────────────────────
    // Spotify's own level — the slider inside the app — not the machine's and
    // not the per-app mixer. MPRIS carries a writable Volume property and the
    // Linux client honours it, unlike Shuffle and LoopStatus, which it
    // advertises and then ignores. Its PipeWire stream is not an alternative
    // here: that node publishes no volume params at all, so there is nothing
    // on the mixer side to turn.
    //
    // MPRIS has no mute, so the glyph mutes by dropping the volume to zero and
    // restores the level it was at. Nothing on the bus remembers that, so it
    // lives here and resets when the shell reloads.
    property real preMuteVolume: 0
    readonly property bool volSupported:
        root.player !== null && root.player.volumeSupported
    readonly property bool volMuted:
        root.volSupported && root.player.volume <= 0.001

    function toggleVolMute() {
        if (!root.volSupported) return;
        if (root.volMuted) {
            root.player.volume = root.preMuteVolume > 0.02 ? root.preMuteVolume : 0.5;
        } else {
            root.preMuteVolume = root.player.volume;
            root.player.volume = 0;
        }
    }

    function fmt(sec) {
        if (!sec || sec <= 0) return "0:00";
        const s = Math.floor(sec);
        return Math.floor(s / 60) + ":" + ("0" + (s % 60)).slice(-2);
    }

    property real pos: 0
    readonly property real progress:
        player && player.lengthSupported && player.length > 0
        ? Math.max(0, Math.min(1, pos / player.length)) : 0

    Timer {
        interval: 500
        running: root.showing && root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: if (root.player) root.pos = root.player.position
    }

    EmptyState {
        anchors.centerIn: parent
        visible: !root.active
        theme: root.theme
        glyph: "\u{f075a}"
        title: "Nothing playing"
        sub: "Start something and it shows up here"
    }

    Column {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 18
        spacing: 14
        visible: root.active

        Row {
            width: parent.width
            spacing: 14

            Item {
                id: artWrap
                width: 116; height: 116
                TrackSwap { target: artWrap; shift: 0; fromScale: 0.86 }

                ClippingRectangle {
                    anchors.fill: parent
                    radius: 14
                    color: Qt.alpha(root.theme.muted, 0.2)
                    Image {
                        id: art
                        anchors.fill: parent
                        source: root.player && root.player.trackArtUrl ? root.player.trackArtUrl : ""
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: 232
                        sourceSize.height: 232
                        asynchronous: true
                    }
                    // An accent wash over the sleeve: album art is the one
                    // surface here whose colours the theme cannot govern, and
                    // the light tint is what keeps an arbitrary cover sitting
                    // comfortably inside whatever palette matugen produced.
                    // Only over a real cover — the empty placeholder is
                    // already on-palette.
                    Rectangle {
                        anchors.fill: parent
                        visible: art.status === Image.Ready
                        color: Qt.alpha(root.theme.accent, 0.16)
                    }
                    // The hover state is held on root rather than read from the
                    // HoverHandler below: ids outside a ClippingRectangle do
                    // not resolve from inside it.
                    Rectangle {
                        anchors.fill: parent
                        color: Qt.rgba(0, 0, 0, 0.55)
                        opacity: root.artHovered && root.canFocus ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 130 } }
                        Text {
                            anchors.centerIn: parent
                            text: "\u{f03cc}"
                            color: "#ffffff"
                            font.family: root.theme.fontMono
                            font.pixelSize: 22
                        }
                    }
                }

                HoverHandler {
                    enabled: root.canFocus
                    cursorShape: Qt.PointingHandCursor
                    onHoveredChanged: root.artHovered = hovered
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: root.canFocus
                    onClicked: root.focusPlayer()
                }
            }

            Column {
                // Fills whatever the static card width leaves after the art.
                width: parent.width - 116 - 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                Text {
                    width: parent.width
                    text: root.player ? root.player.trackTitle : ""
                    TrackSwap { delay: 50 }
                    color: root.theme.fg
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(14)
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: root.player ? root.player.trackArtist : ""
                    TrackSwap { delay: 110 }
                    color: root.theme.muted
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(11)
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: root.player ? root.player.trackAlbum : ""
                    color: Qt.alpha(root.theme.muted, 0.7)
                    font.family: root.theme.fontSans
                    font.pixelSize: IslandState.ts(10)
                    elide: Text.ElideRight
                }
            }
        }

        // ── seek ──────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 5

            Rectangle {
                width: parent.width; height: 5; radius: 2.5
                color: Qt.alpha(root.theme.muted, 0.3)
                Rectangle {
                    width: parent.width * root.progress
                    height: parent.height; radius: 2.5
                    color: root.theme.primary
                    Behavior on width { NumberAnimation { duration: 450 } }
                }
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -8
                    cursorShape: Qt.PointingHandCursor
                    enabled: root.player !== null && root.player.canSeek
                    onClicked: (m) => {
                        if (!root.player || !root.player.length) return;
                        const frac = Math.max(0, Math.min(1, m.x / width));
                        root.player.position = frac * root.player.length;
                        root.pos = frac * root.player.length;
                    }
                }
            }

            Item {
                width: parent.width; height: 14
                Text {
                    anchors.left: parent.left
                    text: root.fmt(root.pos)
                    color: root.theme.muted
                    font.family: root.theme.fontMono
                    font.pixelSize: 10
                }
                Text {
                    anchors.right: parent.right
                    text: root.player ? root.fmt(root.player.length) : "0:00"
                    color: root.theme.muted
                    font.family: root.theme.fontMono
                    font.pixelSize: 10
                }
            }
        }

        // ── transport ─────────────────────────────────────────────
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10
            Repeater {
                model: [
                    { g: "\u{f04ae}", a: "prev" },
                    { g: root.player && root.player.isPlaying ? "\u{f03e4}" : "\u{f040a}", a: "toggle" },
                    { g: "\u{f04ad}", a: "next" }
                ]
                Rectangle {
                    required property var modelData
                    width: 40
                    height: 40
                    radius: width / 2
                    color: mh.hovered ? Qt.alpha(root.theme.fg, 0.16) : Qt.alpha(root.theme.fg, 0.07)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text {
                        anchors.centerIn: parent
                        text: modelData.g
                        color: root.theme.fg
                        font.family: root.theme.fontMono
                        font.pixelSize: 16
                    }
                    HoverHandler { id: mh; cursorShape: Qt.PointingHandCursor }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (!root.player) return;
                            if (modelData.a === "prev") root.player.previous();
                            else if (modelData.a === "next") root.player.next();
                            else root.player.togglePlaying();
                        }
                    }
                }
            }
        }

        // ── the player's own volume ───────────────────────────────
        ControlSlider {
            width: parent.width
            visible: root.volSupported
            height: visible ? implicitHeight : 0
            theme: root.theme
            label: root.player ? root.player.identity : "Player"
            glyph: root.volMuted ? "\u{f075f}" : "\u{f057e}"
            muted: root.volMuted
            value: root.volSupported ? root.player.volume : 0
            valueText: root.volSupported
                       ? Math.round(root.player.volume * 100) + "%" : "—"
            onMoved: (v) => { if (root.volSupported) root.player.volume = v; }
            onToggleMuted: root.toggleVolMute()
        }

        // ── spotify extras: shuffle · repeat · liked ──────────────
        Row {
            visible: spot.authed
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10

            Repeater {
                model: [
                    { key: "shuffle", verb: "shuffle",
                      needsPremium: true },
                    { key: "repeat", verb: "repeat",
                      needsPremium: true },
                    { key: "liked", verb: "like",
                      needsPremium: false }
                ]

                Rectangle {
                    id: xbtn
                    required property var modelData
                    readonly property bool on:
                        modelData.key === "shuffle" ? spot.shuffle
                      : modelData.key === "repeat" ? spot.repeat !== "off"
                      : spot.liked
                    readonly property bool usable:
                        modelData.key === "shuffle" ? spot.premium && spot.canShuffle
                      : modelData.key === "repeat" ? spot.premium && spot.canRepeat
                      : true

                    width: 34; height: 34
                    radius: 17
                    opacity: usable ? 1 : 0.35
                    color: on ? Qt.alpha(root.theme.primary, 0.22)
                         : (xh.hovered && usable ? Qt.alpha(root.theme.fg, 0.14)
                                                 : Qt.alpha(root.theme.fg, 0.06))
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        text: xbtn.modelData.key === "shuffle" ? "\u{f049e}"
                            : xbtn.modelData.key === "repeat"
                              ? (spot.repeat === "track" ? "\u{f0458}" : "\u{f0456}")
                            : (spot.liked ? "\u{f02d1}" : "\u{f02d5}")
                        color: xbtn.on ? root.theme.primary
                             : Qt.alpha(root.theme.muted, xbtn.usable ? 0.95 : 0.7)
                        font.family: root.theme.fontMono
                        font.pixelSize: 15
                    }

                    HoverHandler {
                        id: xh
                        cursorShape: xbtn.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: xbtn.usable
                        onClicked: root.spotRun(xbtn.modelData.verb)
                    }
                }
            }
        }
    }

    WaveCanvas {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 1
        height: 44
        visible: root.active
        theme: root.theme
        vals: IslandState.wavVals
        frame: IslandState.wavFrame
        bottomRadius: 21
    }
}
