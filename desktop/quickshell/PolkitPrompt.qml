import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Polkit

// The session's polkit agent. Nothing else on this machine registers one, so
// before this a GUI asking for privileges (pkexec, a settings app, a mount)
// had no one to answer it and silently failed. The prompt drops out of the
// island on the focused monitor, growing from a pill-sized blob into the card
// the way the control center does, and takes the keyboard exclusively while
// it is up — a password field that loses keys to the window behind it is how
// passwords end up typed into a chat.
//
// Only one agent can hold the session; if the shell is restarted while a
// request is open, polkit cancels that request and the next one lands here.
//
// The same card answers gnome-keyring. The keyring does not go through polkit:
// it calls whoever owns org.gnome.keyring.SystemPrompter, normally the GTK
// dialog of gcr-prompter. scripts/keyring-prompter.py owns that name for as
// long as the shell runs and hands each prompt over as a JSON line; the answer
// goes back on its stdin, so the password is never in an argv. With the shell
// down the name is free and D-Bus activates the stock dialog again. A polkit
// request wins if both are open; the keyring one shows once it is answered.
Scope {
    id: root

    property var theme

    readonly property var flow: agent.flow
    readonly property bool polkitActive: agent.isActive && agent.flow !== null
    readonly property bool keyringActive: !polkitActive && kr !== null
    readonly property bool active: polkitActive || keyringActive

    property var kr: null
    property bool krBusy: false
    property bool krChoice: false
    property string krError: ""

    readonly property bool wantsPassword: keyringActive ? kr.type === "password" : true
    readonly property bool wantsConfirm: keyringActive && kr.type === "password" && kr.passwordNew
    readonly property string heading: keyringActive ? (kr.message || kr.title || "Authentication required")
                                                    : "Authentication required"
    readonly property string bodyText: keyringActive ? (kr.description || kr.title) : (flow ? flow.message : "")
    readonly property string subText: keyringActive ? (kr.title !== heading && kr.description !== "" ? kr.title : "")
                                                    : (flow ? flow.actionId : "")
    readonly property string errorText: keyringActive ? (krError !== "" ? krError : kr.warning)
        : !flow ? ""
        : flow.supplementaryMessage !== "" ? flow.supplementaryMessage
        : flow.failed ? "Wrong password, try again" : ""
    readonly property bool errorIsError: keyringActive ? true : (flow !== null && (flow.supplementaryIsError || flow.failed))
    readonly property bool inputEnabled: keyringActive ? !krBusy : (flow !== null && flow.isResponseRequired)

    Process {
        id: krProc
        running: true
        command: ["/usr/bin/python3", "@HOME@/.config/quickshell/scripts/keyring-prompter.py"]
        stdinEnabled: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => root.ingestKeyring(line)
        }
        onRunningChanged: if (!running) { root.kr = null; krRestart.restart(); }
    }
    Timer { id: krRestart; interval: 3000; onTriggered: krProc.running = true }
    // The keyring normally answers a reply at once, with a retry or a stop.
    // A caller that died in between must not leave a dead card on screen.
    Timer { id: krStale; interval: 15000; running: root.krBusy; onTriggered: root.kr = null }
    onKrChanged: if (kr === null) { krBusy = false; krError = ""; }

    function ingestKeyring(line) {
        const s = (line || "").trim();
        if (s === "" || s.charAt(0) !== "{") return;
        let j;
        try { j = JSON.parse(s); } catch (e) { return; }
        if (j.op === "hide") { root.kr = null; return; }
        if (j.op !== "show") return;
        if (root.kr === null)
            win.screenName = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        const retry = root.kr !== null;
        root.krBusy = false;
        root.krError = "";
        root.krChoice = !!j.choiceChosen;
        root.kr = j;
        if (retry) win.refocus(j.warning !== "");
    }
    function answerKeyring(obj) {
        if (!root.kr) return;
        obj.id = root.kr.id;
        krProc.write(JSON.stringify(obj) + "\n");
    }

    PolkitAgent {
        id: agent
        onAuthenticationRequestStarted: {
            win.screenName = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
            win.shake = 0;
        }
    }

    PanelWindow {
        id: win

        property string screenName: ""
        property real shake: 0
        property real grow: 0

        screen: {
            const all = Quickshell.screens;
            for (let i = 0; i < all.length; i++)
                if (all[i].name === win.screenName) return all[i];
            return all.length ? all[0] : null;
        }

        visible: root.active || win.grow > 0.001
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-polkit"
        WlrLayershell.keyboardFocus: root.active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        anchors.top: true
        margins.top: IslandState.cfg.edgeGap + IslandState.cfg.pillHeightExpanded + IslandState.cfg.cardGap - padTop

        readonly property real cardW: 440
        readonly property real cardH: body.implicitHeight + 36
        readonly property real padSide: 28
        readonly property real padTop: 8
        readonly property real padBottom: 40
        implicitWidth: cardW + padSide * 2
        implicitHeight: cardH + padTop + padBottom

        onVisibleChanged: if (visible && root.active) openAnim.restart()

        Connections {
            target: root
            function onActiveChanged() {
                if (root.active) { openAnim.restart(); }
                else { openAnim.stop(); closeAnim.restart(); }
            }
        }

        NumberAnimation {
            id: openAnim
            target: win; property: "grow"
            from: 0; to: 1
            duration: IslandState.cfg.morph ? IslandState.cfg.morphMs : 1
            easing.type: Easing.OutBack; easing.overshoot: 0.9
            onStarted: { field.text = ""; field2.text = ""; }
            onFinished: win.refocus(false)
        }
        NumberAnimation {
            id: closeAnim
            target: win; property: "grow"
            to: 0
            duration: IslandState.cfg.morph ? 180 : 1
            easing.type: Easing.InCubic
        }

        SequentialAnimation {
            id: shakeAnim
            NumberAnimation { target: win; property: "shake"; to: -10; duration: 50 }
            NumberAnimation { target: win; property: "shake"; to: 8; duration: 70 }
            NumberAnimation { target: win; property: "shake"; to: -5; duration: 60 }
            NumberAnimation { target: win; property: "shake"; to: 0; duration: 60 }
        }

        Connections {
            target: root.flow
            ignoreUnknownSignals: true
            function onAuthenticationFailed() { shakeAnim.restart(); field.text = ""; field.forceActiveFocus(); }
        }

        Item {
            id: stage
            anchors.fill: parent
            transform: Translate { x: win.shake }
            Keys.onReturnPressed: win.submit()
            Keys.onEnterPressed: win.submit()
            Keys.onEscapePressed: win.cancel()

            // Pill-sized at grow 0, the full card at 1: the same morph the
            // island card uses, so the prompt reads as coming out of the pill.
            readonly property real g: Math.max(0, win.grow)
            readonly property real gw: Math.min(1, g * 1.6)
            readonly property real gh: Math.max(0, Math.min(1.08, (g - 0.15) / 0.85))

            RectangularShadow {
                anchors.fill: card
                radius: card.radius
                blur: 30; spread: 2
                offset: Qt.vector2d(0, 12)
                color: Qt.alpha(root.theme.shadow, 0.40 * parent.g)
            }

            Rectangle {
                id: card
                readonly property real pillW: 160
                readonly property real pillH: IslandState.cfg.pillHeight
                width: pillW + (win.cardW - pillW) * parent.gw
                height: pillH + (win.cardH - pillH) * parent.gh
                x: (parent.width - width) / 2
                y: win.padTop
                radius: pillH / 2 + (IslandState.cfg.cardRadius - pillH / 2) * Math.min(1, parent.gh)
                clip: true
                opacity: Math.min(1, parent.g * 3)
                color: Qt.rgba(root.theme.islandBg.r, root.theme.islandBg.g, root.theme.islandBg.b,
                               Math.max(IslandState.cfg.islandOpacity, root.theme.contentOpacity))
                border.width: 1
                border.color: Qt.alpha(root.theme.outline, 0.30)

                Column {
                    id: body
                    x: (card.width - win.cardW) / 2 + 18
                    y: 18
                    width: win.cardW - 36
                    spacing: 12
                    opacity: Math.max(0, (win.grow - 0.7) / 0.3)

                    Row {
                        spacing: 10
                        Rectangle {
                            width: 30; height: 30; radius: 15
                            color: root.theme.primary
                            Text {
                                anchors.centerIn: parent
                                text: "\u{f033e}"
                                color: root.theme.on_primary
                                font.family: root.theme.fontMono
                                font.pixelSize: 15
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: body.width - 40
                            elide: Text.ElideRight
                            text: root.heading
                            color: root.theme.on_surface
                            font.family: root.theme.fontSans
                            font.pixelSize: IslandState.ts(15)
                            font.weight: Font.DemiBold
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: msgCol.implicitHeight + 20
                        radius: 14
                        color: Qt.alpha(root.theme.on_surface, 0.06)
                        Column {
                            id: msgCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            Text {
                                width: parent.width
                                wrapMode: Text.WordWrap
                                text: root.bodyText
                                color: root.theme.on_surface
                                font.family: root.theme.fontSans
                                font.pixelSize: IslandState.ts(12)
                                font.weight: Font.DemiBold
                            }
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                visible: text !== ""
                                text: root.subText
                                color: Qt.alpha(root.theme.on_surface_variant, 0.75)
                                font.family: root.theme.fontMono
                                font.pixelSize: 10
                            }
                        }
                    }

                    Text {
                        visible: root.wantsPassword
                        text: {
                            if (root.wantsConfirm) return "New password";
                            const p = root.flow ? root.flow.inputPrompt.trim() : "";
                            return p === "" || p === "Password:" ? "Password" : p.replace(/:$/, "");
                        }
                        color: Qt.alpha(root.theme.on_surface_variant, 0.80)
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(11)
                    }

                    Rectangle {
                        visible: root.wantsPassword
                        width: parent.width
                        height: 40
                        radius: 20
                        color: Qt.alpha(root.theme.on_surface, 0.05)
                        border.width: 2
                        border.color: (root.flow && root.flow.failed) || (root.keyringActive && root.errorText !== "")
                                    ? Qt.alpha(root.theme.error, 0.70)
                                    : field.activeFocus ? Qt.alpha(root.theme.primary, 0.50)
                                    : Qt.alpha(root.theme.outline, 0.30)
                        Behavior on border.color { ColorAnimation { duration: 140 } }

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\u{f033e}"
                            color: Qt.alpha(root.theme.on_surface_variant, 0.7)
                            font.family: root.theme.fontMono
                            font.pixelSize: 13
                        }

                        TextInput {
                            id: field
                            anchors.left: parent.left
                            anchors.leftMargin: 38
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            echoMode: root.flow && root.flow.responseVisible ? TextInput.Normal : TextInput.Password
                            passwordCharacter: "•"
                            color: root.theme.on_surface
                            font.family: root.theme.fontSans
                            font.pixelSize: IslandState.ts(14)
                            clip: true
                            enabled: root.inputEnabled

                            Text {
                                anchors.fill: parent
                                visible: field.text === ""
                                text: "Enter your password"
                                color: Qt.alpha(root.theme.on_surface_variant, 0.6)
                                font: field.font
                                verticalAlignment: Text.AlignVCenter
                            }

                            Keys.onReturnPressed: root.wantsConfirm ? field2.forceActiveFocus() : win.submit()
                            Keys.onEnterPressed: root.wantsConfirm ? field2.forceActiveFocus() : win.submit()
                            Keys.onEscapePressed: win.cancel()
                        }
                    }

                    Rectangle {
                        visible: root.wantsConfirm
                        width: parent.width
                        height: 40
                        radius: 20
                        color: Qt.alpha(root.theme.on_surface, 0.05)
                        border.width: 2
                        border.color: field2.activeFocus ? Qt.alpha(root.theme.primary, 0.50)
                                    : Qt.alpha(root.theme.outline, 0.30)
                        Behavior on border.color { ColorAnimation { duration: 140 } }

                        TextInput {
                            id: field2
                            anchors.left: parent.left
                            anchors.leftMargin: 38
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            echoMode: TextInput.Password
                            passwordCharacter: "•"
                            color: root.theme.on_surface
                            font.family: root.theme.fontSans
                            font.pixelSize: IslandState.ts(14)
                            clip: true
                            enabled: root.inputEnabled

                            Text {
                                anchors.fill: parent
                                visible: field2.text === ""
                                text: "Repeat the password"
                                color: Qt.alpha(root.theme.on_surface_variant, 0.6)
                                font: field2.font
                                verticalAlignment: Text.AlignVCenter
                            }

                            Keys.onReturnPressed: win.submit()
                            Keys.onEnterPressed: win.submit()
                            Keys.onEscapePressed: win.cancel()
                        }
                    }

                    Item {
                        visible: root.keyringActive && root.kr.choiceLabel !== ""
                        width: parent.width
                        height: 24
                        Rectangle {
                            id: choiceBox
                            width: 18; height: 18; radius: 6
                            anchors.verticalCenter: parent.verticalCenter
                            color: root.krChoice ? root.theme.primary : "transparent"
                            border.width: 2
                            border.color: root.krChoice ? root.theme.primary : Qt.alpha(root.theme.outline, 0.60)
                            Rectangle {
                                anchors.centerIn: parent
                                width: 8; height: 8; radius: 3
                                visible: root.krChoice
                                color: root.theme.on_primary
                            }
                        }
                        Text {
                            anchors.left: choiceBox.right
                            anchors.leftMargin: 10
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: root.keyringActive ? root.kr.choiceLabel.replace(/_/g, "") : ""
                            color: root.theme.on_surface
                            font.family: root.theme.fontSans
                            font.pixelSize: IslandState.ts(12)
                        }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        MouseArea { anchors.fill: parent; onClicked: root.krChoice = !root.krChoice }
                    }

                    Text {
                        width: parent.width
                        visible: text !== ""
                        wrapMode: Text.WordWrap
                        text: root.errorText
                        color: root.errorIsError ? root.theme.error : root.theme.on_surface_variant
                        font.family: root.theme.fontSans
                        font.pixelSize: IslandState.ts(11)
                    }

                    Item {
                        width: parent.width
                        height: 34
                        Row {
                            anchors.right: parent.right
                            spacing: 8

                            Repeater {
                                model: [
                                    { id: "cancel", label: "Cancel" },
                                    { id: "ok", label: !root.keyringActive ? "Authenticate"
                                                     : root.kr.type === "confirm" ? "Continue"
                                                     : root.wantsConfirm ? "Create" : "Unlock" }
                                ]
                                Rectangle {
                                    id: btn
                                    required property var modelData
                                    readonly property bool primary: modelData.id === "ok"
                                    width: lbl.implicitWidth + 28
                                    height: 34
                                    radius: 17
                                    color: primary ? (bh.hovered ? Qt.lighter(root.theme.primary, 1.08) : root.theme.primary)
                                                   : (bh.hovered ? Qt.alpha(root.theme.on_surface, 0.10) : "transparent")
                                    scale: bm.pressed ? 0.95 : 1
                                    Behavior on scale { NumberAnimation { duration: 110 } }
                                    Text {
                                        id: lbl
                                        anchors.centerIn: parent
                                        text: btn.modelData.label
                                        color: btn.primary ? root.theme.on_primary : root.theme.on_surface
                                        font.family: root.theme.fontSans
                                        font.pixelSize: IslandState.ts(12)
                                        font.weight: Font.DemiBold
                                    }
                                    HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
                                    MouseArea {
                                        id: bm
                                        anchors.fill: parent
                                        onClicked: btn.primary ? win.submit() : win.cancel()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        function refocus(failed) {
            field.text = "";
            field2.text = "";
            if (failed) shakeAnim.restart();
            if (root.wantsPassword) field.forceActiveFocus();
            else stage.forceActiveFocus();
        }
        function submit() {
            if (root.keyringActive) {
                if (root.krBusy) return;
                if (root.wantsConfirm && field.text !== field2.text) {
                    root.krError = "The passwords do not match";
                    win.refocus(true);
                    return;
                }
                const reply = { ok: true, choice: root.krChoice };
                if (root.wantsPassword) reply.password = field.text;
                root.answerKeyring(reply);
                root.krBusy = true;
                field.text = "";
                field2.text = "";
                return;
            }
            if (!root.flow || !root.flow.isResponseRequired) return;
            root.flow.submit(field.text);
            field.text = "";
        }
        function cancel() {
            field.text = "";
            field2.text = "";
            if (root.keyringActive) {
                root.answerKeyring({ ok: false });
                root.kr = null;
                return;
            }
            if (root.flow) root.flow.cancelAuthenticationRequest();
        }
    }
}
