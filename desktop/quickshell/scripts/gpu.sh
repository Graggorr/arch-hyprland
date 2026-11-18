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

tip=$(printf 'NVIDIA RTX 4060 Ti\n  Util %s%%    Temp %s°C\n  VRAM %s / %s MiB\n  Power %s W' \
      "$util" "$temp" "$mu" "$mt" "$pw")

jq -cn --arg t "󰍹  ${util}%" --arg tip "$tip" --arg c "$class" '{text:$t, tooltip:$tip, class:$c}'
