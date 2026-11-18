#!/usr/bin/env bash
out=""; tip=""; seen=""; rows=()

add() {
    out="$out  $1 $2"
    tip="$tip$3"$'\n'
    rows+=("$1	$4	$5	$6	$7	$8")
}

for ps in /sys/class/power_supply/ps-controller-battery-*; do
    [ -e "$ps/capacity" ] || continue
    cap=$(cat "$ps/capacity")
    status=$(cat "$ps/status" 2>/dev/null)
    name=$(sed -n 's/^HID_NAME=//p' "$ps/device/uevent" 2>/dev/null | head -1)
    [ -z "$name" ] && name="Controller"
    icon="󰊴"
    [ "$status" = "Charging" ] && icon="󰂄"
    mac=$(basename "$ps"); mac=${mac#ps-controller-battery-}
    add "$icon" "${cap}%" "$name: ${cap}% ($status)" "$name" "$cap" "$status" controller "${mac^^}"
    seen="$seen $(tr 'a-f:' 'A-F_' <<<"$mac")"
done

for ps in /sys/class/power_supply/hidpp_battery_*; do
    [ -e "$ps/capacity" ] || continue
    cap=$(cat "$ps/capacity")
    status=$(cat "$ps/status" 2>/dev/null)
    name=$(grep -m1 POWER_SUPPLY_MODEL_NAME "$ps/uevent" 2>/dev/null | cut -d= -f2)
    [ -z "$name" ] && name=$(basename "$ps")
    icon="󰍽"
    [ "$status" = "Charging" ] && icon="󰂄"
    add "$icon" "${cap}%" "$name: ${cap}% ($status)" "$name" "$cap" "$status" mouse ""
done

while read -r dev; do
    upmac=$(basename "$dev"); upmac=${upmac#*_dev_}
    case " $seen " in *" $upmac "*) continue ;; esac
    info=$(upower -i "$dev")
    pct=$(sed -n 's/^ *percentage: *\([0-9]*\)%.*/\1/p' <<<"$info" | head -1)
    [ -n "$pct" ] || continue
    model=$(sed -n 's/^ *model: *//p' <<<"$info" | head -1)
    state=$(sed -n 's/^ *state: *//p' <<<"$info" | head -1)
    kind=$(basename "$dev")
    kind=${kind%%_dev_*}
    if [ "$kind" = "phone" ] && [ -f /tmp/iphone-charge.json ]; then
        read -r cstate cpct cts < <(jq -r '[.state, .pct // -1, .ts] | join(" ")' /tmp/iphone-charge.json 2>/dev/null)
        if [ -n "$cstate" ]; then
            [ "$cstate" = "charging" ] && state="charging"
            [ "$cpct" -ge 0 ] && [ $(( $(date +%s) - cts )) -lt 600 ] && pct=$cpct
        fi
    fi
    case "$kind" in
        phone) icon="󰄜" ;;
        headset|headphones|speakers|other_audio) icon="󰋋" ;;
        keyboard) icon="󰌌" ;;
        mouse) icon="󰍽" ;;
        gaming_input) icon="󰊴" ;;
        *) icon="󰂯" ;;
    esac
    [ "$state" = "charging" ] && icon="󰂄"
    case "$kind" in
        phone|mouse|keyboard) dkind=$kind ;;
        gaming_input) dkind=controller ;;
        headset|headphones|speakers|other_audio) dkind=audio ;;
        *) dkind=other ;;
    esac
    add "$icon" "${pct}%" "${model:-$kind}: ${pct}% (${state:-unknown})" "${model:-$kind}" "$pct" "${state:-unknown}" "$dkind" "$(tr '_' ':' <<<"$upmac")"
done < <(upower -e | grep '_dev_')

ap=/tmp/airstatus.out
if [ -f "$ap" ] && [ $(( $(date +%s) - $(stat -c %Y "$ap") )) -lt 120 ]; then
    fields=$(jq -r 'select(.status==1) | [.model, .charge.left, .charge.right, .charge.case, .charging_left, .charging_right, .charging_case] | join(" ")' "$ap" 2>/dev/null)
    if [ -n "$fields" ]; then
        read -r model l r c cl cr cc <<<"$fields"
        show=-1
        [ "$l" -ge 0 ] && show=$l
        [ "$r" -ge 0 ] && { [ "$show" -lt 0 ] || [ "$r" -lt "$show" ]; } && show=$r
        if [ "$show" -ge 0 ]; then
            icon="󱡏"
            { [ "$cl" = "true" ] || [ "$cr" = "true" ]; } && icon="󰂄"
            txt="${show}%"
            [ "$c" -ge 0 ] && txt="$txt C${c}%"
            detail=""
            [ "$l" -ge 0 ] && detail="L ${l}%"
            [ "$r" -ge 0 ] && detail="$detail  R ${r}%"
            [ "$c" -ge 0 ] && detail="$detail  case ${c}%"
            add "$icon" "$txt" "$model: ${detail#  }" "$model" "$show" "${detail#  }" airpods ""
        fi
    fi
fi

if [ "$1" = "json" ]; then
    printf '%b\n' "${rows[@]}" | jq -cRs 'split("\n") | map(select(length>0) | split("\t") | {icon:.[0], name:.[1], pct:(.[2]|tonumber? // -1), status:.[3], kind:(.[4] // ""), mac:(.[5] // "")}) | {devices:.}'
    exit 0
fi

out="${out#  }"
[ -z "$out" ] && { echo '{"text":""}'; exit 0; }

tip="${tip%$'\n'}"
jq -cn --arg t "$out" --arg tip "$tip" '{text:$t, tooltip:$tip, class:"devicebat"}'
