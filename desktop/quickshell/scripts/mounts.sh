#!/usr/bin/env bash
set -u

mapfile -t failed < <(systemctl list-units --type=mount,automount --state=failed \
                      --no-legend --no-pager 2>/dev/null | awk '{print $1}')

inv=$(lsblk -dno NAME,TYPE,SIZE,MODEL 2>/dev/null | awk '$2=="disk" && NF>3' | while read -r name _ size model; do
    t=""
    for h in /sys/block/"$name"/device/hwmon*/temp1_input; do
        [ -r "$h" ] && t="$(( $(cat "$h") / 1000 ))°C"; break
    done
    printf '  %-8s %6s  %s\n' "$name" "$size" "${t:-   —}"
    printf '    %s\n' "$model"
done)

mp=$(findmnt -rno TARGET,SOURCE,FSTYPE -t ext4,fuseblk,ntfs3,vfat,btrfs,xfs 2>/dev/null \
  | awk '{printf "  %-12s %-15s %s\n", $1, substr($2,6), $3}')

if [ "${#failed[@]}" -eq 0 ]; then
    tooltip="All mounts healthy"
else
    tooltip="failed units"$'\n'$(printf '  %s\n' "${failed[@]}")
fi
tooltip+=$'\n\n'"mounted"$'\n'"${mp}"
tooltip+=$'\n\n'"physical drives"$'\n'"${inv}"

if [ "${#failed[@]}" -eq 0 ]; then
    jq -cn --arg tip "$tooltip" '{text:"", class:"ok", tooltip:$tip}'
    exit 0
fi

text="${failed[0]} failed"
[ "${#failed[@]}" -gt 1 ] && text="$text  ·  +$((${#failed[@]} - 1)) more"

jq -cn --arg t "$(printf '\U000f02ca')  $text" --arg tip "$tooltip" \
    '{text:$t, class:"warn", tooltip:$tip}'
