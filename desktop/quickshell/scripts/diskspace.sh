#!/usr/bin/env bash
# Root filesystem headroom: invisible while there's room, warns before a full
# disk can truncate files mid-write. JSON output ({text,tooltip,class}).
#
# Thresholds are absolute, not percentage: ENOSPC is about bytes, and a single
# docker build can transiently claim ~20G. Warning at 25G free gives notice
# while a build still has somewhere to go.
#
# Docker.raw is called out in the tooltip because it only ever grows — Docker
# Desktop's qemu layer drops the guest's TRIM, so freed blocks are never
# returned to the host. It is the usual reason this pill appears.
WARN_GB=25
CRIT_GB=12
DOCKER_RAW="$HOME/.docker/desktop/vms/0/data/Docker.raw"

read -r size used avail pct < <(df -B1G --output=size,used,avail,pcent / 2>/dev/null | tail -1)
[ -z "${avail:-}" ] && { printf '{"text": "", "class": "ok", "tooltip": false}\n'; exit 0; }
pct=${pct%\%}

tooltip="Root filesystem: ${avail}G free of ${size}G (${pct}% used)"
if [ -f "$DOCKER_RAW" ]; then
    raw=$(du -BG "$DOCKER_RAW" 2>/dev/null | cut -f1)
    [ -n "$raw" ] && tooltip="$tooltip\nDocker.raw: ${raw} (grows only; never shrinks)"
fi

if   (( avail < CRIT_GB )); then class=crit
elif (( avail < WARN_GB )); then class=warn
else
    printf '{"text": "", "class": "ok", "tooltip": false}\n'
    exit 0
fi

printf '{"text": "  %sG", "class": "%s", "tooltip": "%s"}\n' "$avail" "$class" "$tooltip"
