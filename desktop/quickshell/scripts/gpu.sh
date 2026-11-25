#!/usr/bin/env bash
# NVIDIA GPU stats for the bar (RTX 4060 Ti) via nvidia-smi.
read -r util temp mu mt pw < <(nvidia-smi \
    --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw \
    --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ',')

[ -z "$util" ] && { echo '{"text":"󰍹  n/a","tooltip":"nvidia-smi unavailable"}'; exit 0; }

# nvidia-smi can answer with words instead of numbers ("Failed to initialize
# NVML: Driver/library version mismatch" after an unattended driver update,
# until the next reboot). Words in the bar read as breakage; say what it is.
case "$util" in
    *[!0-9.]*) jq -cn --arg tip "nvidia-smi: $(nvidia-smi 2>&1 | head -1)" \
        '{text:"󰍹  —", tooltip:$tip, class:"stale"}'; exit 0 ;;
esac

u=${util%.*}; t=${temp%.*}
class="ok"
[ "$u" -ge 70 ] && class="high"
[ "$t" -ge 80 ] && class="crit"

IFS=',' read -r name drv cgr cmem cmax fan plim pstate pgen pwid umem enc dec < <(nvidia-smi \
    --query-gpu=name,driver_version,clocks.gr,clocks.mem,clocks.max.gr,fan.speed,power.limit,pstate,pcie.link.gen.current,pcie.link.width.current,utilization.memory,utilization.encoder,utilization.decoder \
    --format=csv,noheader,nounits 2>/dev/null | head -1 | sed 's/, */,/g')
vpct=$(awk -v u="$mu" -v t="$mt" 'BEGIN{printf "%.0f", (t>0) ? u*100/t : 0}')
gib() { awk -v m="$1" 'BEGIN{printf "%.1f", m/1024}'; }

apps=$(nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader,nounits 2>/dev/null \
  | while IFS=', ' read -r pid mem; do
      [ -n "$pid" ] || continue
      printf '%s\t%s\n' "$mem" "$(ps -o comm= -p "$pid" 2>/dev/null || echo "$pid")"
    done | awk -F'\t' '{s[$2]+=$1} END{for(n in s) printf "%d\t%s\n", s[n], n}' \
  | sort -rn | head -6 | awk -F'\t' '{printf "  %5d MiB  %s\n", $1, substr($2,1,26)}')

tip="${name#NVIDIA GeForce }  ·  driver ${drv}"$'\n'
tip+="core      ${util}%    ${cgr} / ${cmax} MHz"$'\n'
tip+="memctl    ${umem}%     ${cmem} MHz"$'\n'
tip+="VRAM      $(gib "$mu") / $(gib "$mt") GiB  (${vpct}%)"$'\n'
fan_txt="${fan}%"; [ "${fan%.*}" = "0" ] && fan_txt="stopped (zero-RPM idle)"
tip+="temp      ${t}°C   fan ${fan_txt}"$'\n'
tip+="power     ${pw} / ${plim%.*} W   ${pstate}"$'\n'
tip+="video     enc ${enc}%  dec ${dec}%"$'\n'
tip+="PCIe      gen ${pgen} x${pwid}"
[ -n "$apps" ] && tip+=$'\n\n'"VRAM by process"$'\n'"${apps}"

jq -cn --arg t "󰍹  ${util}%" --arg tip "$tip" --arg c "$class" '{text:$t, tooltip:$tip, class:$c}'
