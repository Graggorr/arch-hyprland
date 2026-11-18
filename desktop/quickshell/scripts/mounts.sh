#!/usr/bin/env bash

set -u

mapfile -t failed < <(systemctl list-units --type=mount,automount --state=failed \
                      --no-legend --no-pager 2>/dev/null | awk '{print $1}')

if [ "${#failed[@]}" -eq 0 ]; then
    printf '{"text": "", "class": "ok", "tooltip": "All mounts healthy"}\n'
    exit 0
fi

text="${failed[0]} failed"
[ "${#failed[@]}" -gt 1 ] && text="$text  ·  +$((${#failed[@]} - 1)) more"

tooltip=$(printf '%s\\n' "${failed[@]}")
tooltip=${tooltip%\\n}

printf '{"text": "\U000f02ca  %b", "class": "warn", "tooltip": "%s"}\n' "$text" "$tooltip"
