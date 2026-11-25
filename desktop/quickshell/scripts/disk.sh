#!/usr/bin/env bash
path="$1"
icon="$2"

read -r src fstype opts < <(findmnt -no SOURCE,FSTYPE,OPTIONS --target "$path" 2>/dev/null | tail -1)
read -r size used avail < <(df -B1 --output=size,used,avail "$path" 2>/dev/null | tail -1)
[ -z "${size:-}" ] && { echo '{"text":""}'; exit 0; }

gb() { awk -v b="$1" 'BEGIN{ if (b>=1099511627776) printf "%.2fT", b/1099511627776; else printf "%.0fG", b/1073741824 }'; }
pct() { awk -v a="$1" -v b="$2" 'BEGIN{ printf "%.0f", (b>0) ? a*100/b : 0 }'; }

num=$(pct "$used" "$size")
reserved=$(( size - used - avail ))
(( reserved < 0 )) && reserved=0

if   [ "$num" -ge 92 ]; then class="crit"
elif [ "$num" -ge 85 ]; then class="high"
else class="ok"
fi

tip="used      $(gb "$used") of $(gb "$size")  (${num}%)"$'\n'
tip+="free      $(gb "$avail")"$'\n'
if (( reserved > 1073741824 )); then
    tip+="reserved  $(gb "$reserved")  (root-only ext4 blocks)"$'\n'
fi

read -r itot iused < <(df --output=itotal,iused "$path" 2>/dev/null | tail -1)
if [ "$fstype" != "fuseblk" ] && [ -n "${itot:-}" ] && [ "$itot" != "-" ] && (( itot > 0 )); then
    tip+="inodes    $(pct "$iused" "$itot")% of $(awk -v n="$itot" 'BEGIN{printf "%.1fM", n/1e6}')"$'\n'
fi

tip+=$'\n'"mount     $path"$'\n'
tip+="device    ${src}"$'\n'
tip+="fs        ${fstype}  (${opts%%,*})"$'\n'

part=$(basename "$(readlink -f "$src" 2>/dev/null)")
disk=$(lsblk -no PKNAME "/dev/$part" 2>/dev/null | head -1)
if [ -n "$disk" ]; then
    model=$(lsblk -dno MODEL "/dev/$disk" 2>/dev/null | sed 's/ *$//')
    [ -n "$model" ] && tip+="drive     ${model}"$'\n'
    for h in /sys/block/"$disk"/device/hwmon*/temp1_input; do
        [ -r "$h" ] && tip+="temp      $(( $(cat "$h") / 1000 ))°C"$'\n'
        break
    done
    st=/sys/block/$disk/$part/stat
    if [ -r "$st" ]; then
        read -r _ _ rs _ _ _ ws _ < "$st"
        tip+="I/O boot  read $(gb $((rs*512))) · wrote $(gb $((ws*512)))"$'\n'
    fi
fi

if [ "$path" = "/" ]; then
    raw="$HOME/.docker/desktop/vms/0/data/Docker.raw"
    [ -f "$raw" ] && tip+=$'\n'"Docker.raw  $(du -BG "$raw" 2>/dev/null | cut -f1)  (grows only)"
fi

jq -cn --arg t "${icon}  ${num}%" --arg tip "${tip%$'\n'}" --arg c "$class" \
       '{text:$t, tooltip:$tip, class:$c}'
