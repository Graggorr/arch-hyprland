import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam

Scope {
    id: root

    property var theme
    // output name -> that monitor's palette, so each lock surface matches the
    // wallpaper it is covering. Falls back to the shared palette.
    property var themes: ({})
    property bool locked: false
    property string err: ""
    property bool busy: false
    property string pw: ""

    IpcHandler {
        target: "lock"
        function lock(): void { root.locked = true; }
    }

    // Whatever the island had open is put away first: the card is a popup
    // of the desktop bar and would come back over the desktop on unlock.
    onLockedChanged: {
        IslandState.closeCard();
        IslandState.locked = locked;
        if (locked) err = "";
    }

    // Reuses /etc/pam.d/hyprlock — already configured for this machine's auth
    // stack, so no new PAM policy is introduced.
    PamContext {
        id: pam
        config: "hyprlock"

        onPamMessage: {
            if (responseRequired) respond(root.pw);
            else if (messageIsError) root.err = message;
        }

        onCompleted: (result) => {
            root.busy = false;
            if (result === PamResult.Success) {
                root.err = "";
                root.locked = false;
            } else {
                root.err = "Incorrect password";
            }
        }

        onError: (e) => { root.busy = false; root.err = "Authentication error"; }
    }

    function submit() {
        if (busy || pw === "") return;
        err = "";
        busy = true;
        pam.start();
    }

    WlSessionLock {
        locked: root.locked

        WlSessionLockSurface {
            id: surface
            color: "black"

            LockContent {
                anchors.fill: parent
                theme: {
                    const n = surface.screen ? surface.screen.name : "";
                    const t = root.themes[n];
                    return t ? t : root.theme;
                }
                // password only on the leftmost display
                primary: surface.screen ? IslandState.screenRank(surface.screen.name) === 0 : true
                screenName: surface.screen ? surface.screen.name : ""
                err: root.err
                busy: root.busy
                onPwChanged: root.pw = pw
                onEdited: if (root.err !== "") root.err = ""
                onSubmitted: root.submit()
                Component.onCompleted: if (primary) inputItem.forceActiveFocus()
            }
        }
    }
}
