#!/usr/bin/env bash
# cliphist bridge for the island's clipboard tool.
# Usage: list [limit] | copy <id> | delete <id> | wipe
# list -> {"entries":[{id,preview,binary}]}
set -u

case "${1:-list}" in
    list)
        cliphist list 2>/dev/null | head -n "${2:-200}" | python3 -c '
import json, os, re, subprocess, sys
thumbs = os.path.expanduser("~/.cache/quickshell/cliphist")
os.makedirs(thumbs, exist_ok=True)
meta = re.compile(r"\[\[ binary data (\S+ \S+) (\w+) (\d+)x(\d+) \]\]")
out, keep = [], set()
for line in sys.stdin:
    line = line.rstrip("\n")
    if "\t" not in line:
        continue
    cid, preview = line.split("\t", 1)
    binary = preview.startswith("[[ binary data")
    e = {"id": cid, "preview": preview, "binary": binary}
    m = meta.match(preview)
    if m and m.group(2) in ("png", "jpeg", "jpg", "webp", "gif", "bmp"):
        name = cid + "." + m.group(2)
        path = os.path.join(thumbs, name)
        if not os.path.exists(path):
            data = subprocess.run(["cliphist", "decode"], input=(cid + "\t").encode(),
                                  capture_output=True).stdout
            if data:
                with open(path, "wb") as f:
                    f.write(data)
        if os.path.exists(path):
            keep.add(name)
            e.update({"thumb": path, "size": m.group(1), "format": m.group(2).upper(),
                      "w": int(m.group(3)), "h": int(m.group(4))})
    out.append(e)
for name in os.listdir(thumbs):
    if name not in keep:
        os.remove(os.path.join(thumbs, name))
json.dump({"entries": out}, sys.stdout, ensure_ascii=False)
'
        ;;
    copy)
        [ -z "${2:-}" ] && { echo '{"error":"no id"}'; exit 1; }
        printf '%s\t' "$2" | cliphist decode | wl-copy && echo '{"ok":"copied"}'
        ;;
    delete)
        [ -z "${2:-}" ] && { echo '{"error":"no id"}'; exit 1; }
        printf '%s\t' "$2" | cliphist delete && echo '{"ok":"deleted"}'
        ;;
    wipe)
        cliphist wipe && echo '{"ok":"wiped"}'
        ;;
    *)
        echo "usage: clipboard.sh list [limit] | copy <id> | delete <id> | wipe" >&2
        exit 1
        ;;
esac
