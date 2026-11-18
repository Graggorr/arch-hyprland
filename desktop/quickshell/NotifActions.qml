pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

// Shared notification behaviour for the toasts and the centre, so the two can
// not drift apart.
Singleton {
    id: root

    // Spec: the action keyed "default" is what activating the notification body
    // means. Everything else is an explicit button.
    function defaultAction(n) {
        if (!n || !n.actions) return null;
        for (let i = 0; i < n.actions.length; i++)
            if (n.actions[i].identifier === "default") return n.actions[i];
        return null;
    }

    // Destroying a notification unwinds the card or row whose click handler is
    // still on the stack, taking its MouseArea with it. Always defer.
    function discard(n) {
        Qt.callLater(function() { if (n && n.tracked) n.dismiss(); });
    }

    // Reverse-DNS ids, human app names and window classes never agree on shape:
    // "Telegram Desktop" (appName) vs org.telegram.desktop (class). Comparing
    // significant tokens matches them without matching everything — the dropped
    // words are the ones nearly every id carries.
    function tokens(s) {
        const drop = { org: 1, com: 1, net: 1, io: 1, gnome: 1, kde: 1,
                       desktop: 1, app: 1, gtk: 1, qt: 1, electron: 1 };
        const out = [];
        const parts = ("" + (s || "")).toLowerCase().split(/[^a-z0-9]+/);
        for (let i = 0; i < parts.length; i++)
            if (parts[i] !== "" && !drop[parts[i]]) out.push(parts[i]);
        return out;
    }

    // invoke() only tells the app the button was pressed. The app then tries to
    // raise itself, but the click happened in *our* surface, so it has no
    // activation token to present and the compositor drops the request — the app
    // really does act on it, the window just never comes forward. That reads as
    // "the button does nothing", so the shell raises the window itself.
    function focusApp(n) {
        if (!n) return false;
        const tops = Hyprland.toplevels.values;

        // The sender-pid hint is exact whenever the notifying process owns the
        // window, which covers single-process apps like Telegram.
        const hints = n.hints;
        const pid = hints && hints["sender-pid"] !== undefined
                    ? parseInt(hints["sender-pid"]) : -1;
        if (pid > 0) {
            for (let i = 0; i < tops.length; i++) {
                const o = tops[i].lastIpcObject;
                if (o && parseInt(o.pid) === pid) {
                    Hyprland.dispatch('hl.dsp.focus({ window = "address:0x' + tops[i].address + '" })');
                    return true;
                }
            }
        }

        // Electron and friends notify from a helper process, so fall back to the
        // app's advertised identity.
        let want = root.tokens(("" + (n.desktopEntry || "")).replace(/\.desktop$/, ""));
        want = want.concat(root.tokens(n.appName));
        if (want.length === 0) return false;

        for (let i = 0; i < tops.length; i++) {
            const o = tops[i].lastIpcObject;
            if (!o) continue;
            const have = root.tokens(o["class"]).concat(root.tokens(o.initialClass));
            for (let j = 0; j < want.length; j++) {
                if (have.indexOf(want[j]) !== -1) {
                    Hyprland.dispatch('hl.dsp.focus({ window = "address:0x' + tops[i].address + '" })');
                    return true;
                }
            }
        }
        return false;
    }
}
