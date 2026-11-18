#!/usr/bin/env bash
# OBS Studio recording control for the island's capture tool.
# Usage: status | toggle | launch | open
#
# toggle launches OBS to the tray when it is not running: the websocket only
# exists while OBS does, so the first press is "start OBS", and the recording
# starts once it answers. Recordings land wherever the active OBS profile
# points (currently /mnt/ssd512/Videos/Obs) — this never sets the path.
set -u

WS="$HOME/.config/quickshell/scripts/obs-ws.py"
WS_CONFIG="$HOME/.config/obs-studio/plugin_config/obs-websocket/config.json"

# The websocket server is off in a stock OBS, and its config holds a password,
# so it is deliberately not in the backup repo — a restored machine would
# otherwise get a record button that silently does nothing. Enabling it is
# therefore done here, on the way to launching OBS, generating a password if
# there is none. Only ever while OBS is closed: it rewrites this file on exit
# and would discard the change.
ensure_ws() {
    pgrep -x obs >/dev/null 2>&1 && return 0
    WS_CONFIG="$WS_CONFIG" python3 -c '
import json, os, pathlib, secrets
p = pathlib.Path(os.environ["WS_CONFIG"])
p.parent.mkdir(parents=True, exist_ok=True)
try:
    c = json.loads(p.read_text())
except Exception:
    c = {}
before = dict(c)
c.setdefault("alerts_enabled", False)
c.setdefault("first_load", False)
c.setdefault("server_port", 4455)
c["auth_required"] = True
c["server_enabled"] = True
if not c.get("server_password"):
    c["server_password"] = secrets.token_urlsafe(12)
if c != before:
    p.write_text(json.dumps(c, indent=4))
' 2>/dev/null
}

launch() {
    ensure_ws
    pgrep -x obs >/dev/null 2>&1 && return 0
    setsid -f obs --minimize-to-tray --disable-shutdown-check >/dev/null 2>&1
    for _ in $(seq 1 40); do
        sleep 0.5
        python3 "$WS" status | grep -q '"running": true' && return 0
    done
    return 1
}

case "${1:-status}" in
    status)
        # pgrep first so the common case — OBS closed — costs one process
        # instead of a python start plus a refused TCP connect on every poll.
        if ! pgrep -x obs >/dev/null 2>&1; then
            printf '{"running": false, "recording": false}\n'
            exit 0
        fi
        out=$(python3 "$WS" status)
        # OBS is up but refused the websocket: the server is disabled in an
        # already-running instance, which ensure_ws cannot fix from here —
        # only restarting OBS picks up the config. Say so rather than claiming
        # OBS is not running, which is the one thing the user can see is false.
        case "$out" in
            *'"running": false'*)
                printf '{"running": false, "recording": false, "needsrestart": true}\n'
                ;;
            *) printf '%s\n' "$out" ;;
        esac
        ;;

    toggle)
        if ! pgrep -x obs >/dev/null 2>&1; then
            if ! launch; then
                printf '{"running": false, "recording": false, "error": "obs did not start"}\n'
                exit 0
            fi
        fi
        python3 "$WS" toggle
        ;;

    launch)
        launch && python3 "$WS" status \
               || printf '{"running": false, "recording": false}\n'
        ;;

    open)
        setsid -f obs --disable-shutdown-check >/dev/null 2>&1
        printf '{"ok": "opened"}\n'
        ;;

    *)
        echo "usage: obs.sh status | toggle | launch | open" >&2
        exit 1
        ;;
esac
