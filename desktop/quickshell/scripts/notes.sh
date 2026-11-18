#!/usr/bin/env bash
# Quick notes for the island's notes tool.
# Usage: list [limit] | add <body> | update <id> <body> | delete <id>
#        | pin <id> | pinned | open <id> | reveal
# The body is passed as one argument, newlines and all — the caller hands over
# an argv array, so nothing is re-parsed by a shell on the way in.
#
# One markdown file per note under ~/Documents/Notes, named by creation time.
# Plain files rather than a database so a note stays greppable, editable in any
# editor and syncable — the island is one way in, not the only one. The Claude
# knowledge vault is deliberately not used: it is a memory graph, not a place
# for scratch notes.
set -u

NOTE_DIR="${NOTES_DIR:-$HOME/Documents/Notes}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell"
PIN_FILE="$STATE_DIR/note-pinned"

mkdir -p "$NOTE_DIR" "$STATE_DIR"

note_path() { printf '%s/%s.md' "$NOTE_DIR" "$1"; }

valid_id() {
    case "$1" in
        note-[0-9]*) [ -f "$(note_path "$1")" ] ;;
        *) false ;;
    esac
}

case "${1:-list}" in
    list)
        NOTE_DIR="$NOTE_DIR" PIN_FILE="$PIN_FILE" LIMIT="${2:-100}" python3 -c '
import json, os, time
d = os.environ["NOTE_DIR"]
pin = ""
pf = os.environ["PIN_FILE"]
if os.path.exists(pf):
    pin = open(pf).read().strip()
out = []
for name in os.listdir(d):
    if not name.endswith(".md"):
        continue
    path = os.path.join(d, name)
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
        mtime = os.path.getmtime(path)
    except OSError:
        continue
    lines = [l.rstrip() for l in text.split("\n")]
    title = next((l.lstrip("# ").strip() for l in lines if l.strip()), "(empty)")
    rest = "\n".join(lines[1:]).strip() if len(lines) > 1 else ""
    age = time.time() - mtime
    if   age <  3600: when = f"{max(1,int(age//60))}m ago"
    elif age < 86400: when = f"{int(age//3600)}h ago"
    elif age < 604800: when = f"{int(age//86400)}d ago"
    else: when = time.strftime("%d %b", time.localtime(mtime))
    nid = name[:-3]
    out.append({"id": nid, "title": title[:120], "preview": rest.replace("\n", " ")[:160],
                "body": text, "when": when, "mtime": mtime, "pinned": nid == pin})
out.sort(key=lambda n: (not n["pinned"], -n["mtime"]))
print(json.dumps({"notes": out[:int(os.environ["LIMIT"])], "dir": d}))
'
        ;;

    add)
        [ -z "${2:-}" ] && { echo '{"error":"empty"}'; exit 1; }
        id="note-$(date +%s%3N)"
        printf '%s\n' "$2" > "$(note_path "$id")"
        printf '{"ok":"added","id":"%s"}\n' "$id"
        ;;

    update)
        [ -z "${2:-}" ] && { echo '{"error":"no id"}'; exit 1; }
        valid_id "$2" || { echo '{"error":"unknown id"}'; exit 1; }
        [ -z "${3:-}" ] && { echo '{"error":"empty"}'; exit 1; }
        printf '%s\n' "$3" > "$(note_path "$2")"
        printf '{"ok":"updated"}\n'
        ;;

    delete)
        [ -z "${2:-}" ] && { echo '{"error":"no id"}'; exit 1; }
        valid_id "$2" || { echo '{"error":"unknown id"}'; exit 1; }
        rm -f "$(note_path "$2")"
        [ "$(cat "$PIN_FILE" 2>/dev/null)" = "$2" ] && rm -f "$PIN_FILE"
        printf '{"ok":"deleted"}\n'
        ;;

    pin)
        [ -z "${2:-}" ] && { echo '{"error":"no id"}'; exit 1; }
        valid_id "$2" || { echo '{"error":"unknown id"}'; exit 1; }
        if [ "$(cat "$PIN_FILE" 2>/dev/null)" = "$2" ]; then
            rm -f "$PIN_FILE"
            printf '{"ok":"unpinned"}\n'
        else
            printf '%s' "$2" > "$PIN_FILE"
            printf '{"ok":"pinned"}\n'
        fi
        ;;

    pinned)
        id=$(cat "$PIN_FILE" 2>/dev/null)
        if [ -z "$id" ] || ! valid_id "$id"; then
            printf '{"pinned":false}\n'
            exit 0
        fi
        NOTE_PATH="$(note_path "$id")" NOTE_ID="$id" python3 -c '
import json, os
text = open(os.environ["NOTE_PATH"], encoding="utf-8", errors="replace").read()
lines = [l.rstrip() for l in text.split("\n")]
title = next((l.lstrip("# ").strip() for l in lines if l.strip()), "(empty)")
rest = "\n".join(lines[1:]).strip() if len(lines) > 1 else ""
print(json.dumps({"pinned": True, "id": os.environ["NOTE_ID"],
                  "title": title[:80], "sub": rest.replace("\n", " ")[:80]}))
'
        ;;

    open)
        [ -z "${2:-}" ] && { echo '{"error":"no id"}'; exit 1; }
        valid_id "$2" || { echo '{"error":"unknown id"}'; exit 1; }
        setsid -f xdg-open "$(note_path "$2")" >/dev/null 2>&1
        printf '{"ok":"opened"}\n'
        ;;

    reveal)
        setsid -f xdg-open "$NOTE_DIR" >/dev/null 2>&1
        printf '{"ok":"revealed"}\n'
        ;;

    *)
        echo "usage: notes.sh list [limit] | add | update <id> | delete <id> | pin <id> | pinned | open <id> | reveal" >&2
        exit 1
        ;;
esac
