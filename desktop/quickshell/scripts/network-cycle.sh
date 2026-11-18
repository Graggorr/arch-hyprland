#!/usr/bin/env bash
# Bar on-click: rotate network profiles.
# Cycle order: base connection only (no VPN) -> VPN #1 -> VPN #2 -> ... -> base.
# The base ethernet/wifi connection is never touched; only VPNs are toggled.

notify() {
    command -v notify-send >/dev/null && notify-send -a network -t 3000 "$1" "$2"
}

# All configured VPN-ish profiles, sorted for a stable cycle order.
mapfile -t vpns < <(nmcli -t -f NAME,TYPE connection show 2>/dev/null \
    | awk -F: '$2=="vpn" || $2=="wireguard" {gsub(/\\:/,":",$1); print $1}' | sort)

if (( ${#vpns[@]} == 0 )); then
    notify "Network" "No VPN profiles configured — nothing to cycle"
    exit 0
fi

# Currently active VPNs (normally 0 or 1).
mapfile -t active < <(nmcli -t -f NAME,TYPE connection show --active 2>/dev/null \
    | awk -F: '$2=="vpn" || $2=="wireguard" {gsub(/\\:/,":",$1); print $1}')

next=""
if (( ${#active[@]} == 0 )); then
    next="${vpns[0]}"
else
    # Find the active VPN in the cycle; next is the one after it,
    # or empty (= plain ethernet/wifi) when it was the last.
    cur="${active[0]}"
    for i in "${!vpns[@]}"; do
        if [[ "${vpns[$i]}" == "$cur" ]]; then
            (( i + 1 < ${#vpns[@]} )) && next="${vpns[i+1]}"
            break
        fi
    done
    for v in "${active[@]}"; do
        nmcli connection down "$v" >/dev/null 2>&1
    done
fi

if [[ -n "$next" ]]; then
    if err=$(nmcli connection up "$next" 2>&1 >/dev/null); then
        notify "Network" "Switched to VPN: $next"
    else
        notify "Network" "Failed to bring up $next: $err"
    fi
else
    notify "Network" "VPN off — direct connection"
fi
