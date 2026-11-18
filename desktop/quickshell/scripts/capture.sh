#!/usr/bin/env bash
# Screen capture and colour picking for the island's capture tool.
# Usage: shot <area|window|output> | pick | list [limit] | open <path> | reveal
#
# Every interactive mode needs the island card gone first: slurp and hyprpicker
# both take a screen-wide grab, and the card holds a hyprland focus grab of its
# own. The caller closes the card, so this waits a beat before capturing —
# without it the shot contains the card that asked for it.
set -u

SHOT_DIR="$HOME/Pictures/Screenshots"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell"
COLOR_FILE="$STATE_DIR/colors"
MAX_COLORS=24

mkdir -p "$SHOT_DIR" "$STATE_DIR"

case "${1:-list}" in
    shot)
        what=${2:-area}
        case "$what" in
            area|window|output) ;;
            *) echo '{"error":"area|window|output"}'; exit 1 ;;
        esac
        [ "$what" = window ] && what=active
        sleep 0.25
        file="$SHOT_DIR/$(date +%Y-%m-%d_%H-%M-%S).png"
        if grimblast --notify copysave "$what" "$file" >/dev/null 2>&1; then
            printf '{"ok":"captured","path":"%s"}\n' "$file"
        else
            printf '{"error":"cancelled"}\n'
        fi
        ;;

    pick)
        sleep 0.25
        hex=$(hyprpicker -a -f hex -l -q 2>/dev/null)
        if [ -z "$hex" ]; then
            printf '{"error":"cancelled"}\n'
            exit 0
        fi
        touch "$COLOR_FILE"
        { printf '%s\n' "$hex"; grep -vxF "$hex" "$COLOR_FILE"; } \
            | head -n "$MAX_COLORS" > "$COLOR_FILE.tmp"
        mv "$COLOR_FILE.tmp" "$COLOR_FILE"
        notify-send -a capture -i color-select "$hex" "copied to clipboard"
        printf '{"ok":"picked","hex":"%s"}\n' "$hex"
        ;;

    list)
        limit=${2:-12}
        { find "$SHOT_DIR" -maxdepth 1 -type f \
               \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) -printf '%T@\t%p\n' 2>/dev/null
          find "$HOME/Pictures" -maxdepth 1 -type f \
               \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) -printf '%T@\t%p\n' 2>/dev/null
        } | sort -rn | head -n "$limit" | COLOR_FILE="$COLOR_FILE" python3 -c '
import json, os, sys, time
shots = []
for line in sys.stdin:
    line = line.rstrip("\n")
    if "\t" not in line: continue
    ts, path = line.split("\t", 1)
    ts = float(ts)
    age = time.time() - ts
    if   age <  3600: when = f"{int(age//60)}m ago"
    elif age < 86400: when = f"{int(age//3600)}h ago"
    else:             when = time.strftime("%d %b", time.localtime(ts))
    shots.append({"path": path, "name": os.path.basename(path), "when": when})
colors = []
cf = os.path.expanduser(os.environ.get("COLOR_FILE", ""))
if cf and os.path.exists(cf):
    colors = [l.strip() for l in open(cf) if l.strip()]
print(json.dumps({"shots": shots, "colors": colors}))
'
        ;;

    open)
        [ -z "${2:-}" ] && { echo '{"error":"no path"}'; exit 1; }
        setsid -f xdg-open "$2" >/dev/null 2>&1
        printf '{"ok":"opened"}\n'
        ;;

    reveal)
        setsid -f xdg-open "$SHOT_DIR" >/dev/null 2>&1
        printf '{"ok":"revealed"}\n'
        ;;

    *)
        echo "usage: capture.sh shot <area|window|output> | pick | list [limit] | open <path> | reveal" >&2
        exit 1
        ;;
esac
