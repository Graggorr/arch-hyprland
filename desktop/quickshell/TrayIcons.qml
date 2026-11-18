pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth

// How a tray item is named and drawn, shared by the island's tray tool and
// the tray strip on the top bar so the two never disagree about an icon.
Singleton {
    id: root

    // nm-applet and blueman ask for icons no installed theme resolves well, so
    // they are drawn from the island's own font — which also lets them carry
    // live state instead of a fixed badge.
    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property bool btOn: btAdapter !== null && btAdapter.enabled
    readonly property bool btConnected: {
        const ds = Bluetooth.devices ? Bluetooth.devices.values : [];
        for (let i = 0; i < ds.length; i++) if (ds[i].connected) return true;
        return false;
    }

    // Chromium and Electron apps leave Title empty and register an id like
    // "chrome_status_icon_1", which is what the list showed. Their tooltip
    // usually carries the real name — but not dependably: Slack's is "You have
    // unread messages", which is live status, so using it as a name would put a
    // changing sentence where an app name belongs. The name is derived from the
    // id instead, which is stable, and the tooltip stays on the status line.
    function displayName(item) {
        if (!item) return "";
        const t = (item.title || "").trim();
        if (t !== "") return t.charAt(0).toUpperCase() + t.slice(1);
        const id = (item.id || "").replace(/_status_icon(_\d+)?$/i, "");
        return id.replace(/[-_]+/g, " ").trim()
                 .replace(/\b\w/g, c => c.toUpperCase());
    }

    function nativeGlyph(id) {
        if (id === "nm-applet") {
            switch (IslandState.netKind) {
            case "vpn": return "\u{f0582}";
            case "wifi": return "\u{f05a9}";
            case "ethernet": return "\u{f0200}";
            }
            return "\u{f002a}";
        }
        if (id === "blueman") {
            if (!root.btOn) return "\u{f00b2}";
            return root.btConnected ? "\u{f00b1}" : "\u{f00af}";
        }
        return "";
    }

    // Always white, whatever the theme: these are icon-pack glyphs standing
    // in for a tray icon, and the glyph itself already changes with the state
    // (adapter off, connected, VPN), so no colour has to carry it.
    function nativeColor(id) {
        return "#ffffff";
    }
}
