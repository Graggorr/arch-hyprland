#!/usr/bin/env bash
# Bar module: show NetworkManager connection profile name.
# Active VPN(s) take precedence over the underlying ethernet/wifi.

ICON_ETH=$'\U000f0200'
ICON_WIFI=$'\U000f05a9'
ICON_VPN=$'\U000f0582'
ICON_DISC=$'\U000f002a'

emit() {
    local vpns=() phys="" phys_type=""
    local name type dev

    while IFS=: read -r name type dev; do
        # Unescape backslashed colons (nmcli -t escapes ':' as '\:').
        name="${name//\\:/:}"
        case "$type" in
            vpn|wireguard)
                vpns+=("$name")
                ;;
            802-3-ethernet)
                phys="$name"
                phys_type="ethernet"
                ;;
            802-11-wireless)
                phys="$name"
                phys_type="wifi"
                ;;
        esac
    done < <(nmcli -t -f NAME,TYPE,DEVICE connection show --active 2>/dev/null)

    local text class tooltip
    if (( ${#vpns[@]} > 0 )); then
        local joined=""
        local v
        for v in "${vpns[@]}"; do
            [[ -n "$joined" ]] && joined+=", "
            joined+="$v"
        done
        text="${ICON_VPN}  ${joined}"
        class="vpn"
        tooltip="VPN: ${joined}"
        [[ -n "$phys" ]] && tooltip+=$'\n'"via ${phys}"
    elif [[ -n "$phys" ]]; then
        if [[ "$phys_type" == "ethernet" ]]; then
            text="${ICON_ETH}  ${phys}"
        else
            text="${ICON_WIFI}  ${phys}"
        fi
        class="$phys_type"
        tooltip="$phys"
    else
        text="Disconnected ${ICON_DISC}"
        class="disconnected"
        tooltip="Disconnected"
    fi

    tooltip+=$'\n''Click: next connection   Right-click: nmtui'
    jq -cn --arg t "$text" --arg tt "$tooltip" --arg c "$class" \
        '{text:$t, tooltip:$tt, class:$c, alt:$c}'
}

if [ "$1" = "once" ]; then emit; exit 0; fi

cleanup() { kill 0 2>/dev/null; }
trap cleanup EXIT TERM HUP INT PIPE

BAR_PID=$PPID
(
    while [[ "$(ps -o ppid= -p $$ 2>/dev/null | tr -d ' ')" == "$BAR_PID" ]]; do
        sleep 5
    done
    kill -TERM 0 2>/dev/null
) &

emit
# Stream updates whenever NetworkManager reports state changes.
nmcli monitor 2>/dev/null | while IFS= read -r _; do
    emit
done
