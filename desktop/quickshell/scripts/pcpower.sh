#!/usr/bin/env bash
# Estimated whole-PC power draw for the bar.
#
# This machine has NO true system-power sensor (no PSU wattage sensor, no UPS,
# no hwmon power input). Only two components report real watts:
#   CPU package  — Intel RAPL   (needs 99-rapl-powercap.rules, group wheel)
#   GPU          — nvidia-smi    (RTX 4060 Ti)
# Everything else (mobo, RAM, NVMe, fans) is folded into a fixed BASELINE, and
# the component sum is divided by PSU efficiency to approximate the wall draw.
# The number is therefore an ESTIMATE, not a measurement — the tooltip shows
# every term so it's transparent.

plug=$(printf '\uf1e6')   # plug (Font Awesome — MDI Nerd glyphs render broken here)

BASELINE=35           # W for mobo + RAM + NVMe x2 + fans (rough fixed floor)
PSU_EFF=0.88          # 80+ Gold-ish efficiency; wall = components / PSU_EFF

RAPL_PKG=/sys/class/powercap/intel-rapl:0
MAXRANGE=$(cat "$RAPL_PKG/max_energy_range_uj" 2>/dev/null)

# ── CPU package watts, sampled over a short window ──
e1=$(cat "$RAPL_PKG/energy_uj" 2>/dev/null); t1=$(date +%s.%N)
sleep 0.6
e2=$(cat "$RAPL_PKG/energy_uj" 2>/dev/null); t2=$(date +%s.%N)
if [ -n "$e1" ] && [ -n "$e2" ]; then
  cpu_w=$(awk -v a="$e1" -v b="$e2" -v t1="$t1" -v t2="$t2" -v mx="$MAXRANGE" \
    'BEGIN{d=b-a; if(d<0&&mx>0)d+=mx; dt=t2-t1; if(dt<=0)dt=0.6; printf "%.1f", d/1e6/dt}')
else
  cpu_w=""            # RAPL not readable
fi

# ── GPU watts (instantaneous) ──
gpu_w=$(nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')
[ -z "$gpu_w" ] && gpu_w=""

# ── combine ──
cpu_n=${cpu_w:-0}; gpu_n=${gpu_w:-0}
read -r components wall <<<"$(awk -v c="$cpu_n" -v g="$gpu_n" -v b="$BASELINE" -v eff="$PSU_EFF" \
  'BEGIN{comp=c+g+b; printf "%.0f %.0f", comp, comp/eff}')"

# ── styling by wall estimate ──
class="ok"
[ "$wall" -ge 250 ] && class="high"
[ "$wall" -ge 350 ] && class="crit"

# ── tooltip breakdown ──
cpu_disp=${cpu_w:-"n/a"}; [ "$cpu_disp" != "n/a" ] && cpu_disp="${cpu_disp} W"
gpu_disp=${gpu_w:-"n/a"}; [ "$gpu_disp" != "n/a" ] && gpu_disp="${gpu_disp} W"
loss=$((wall - components))

tip="<b>Estimated total system power</b>"$'\n'
tip+="<tt>"
tip+=$(printf 'CPU package         %s\n'   "$cpu_disp")$'\n'
tip+=$(printf 'GPU (RTX 4060 Ti)   %s\n'   "$gpu_disp")$'\n'
tip+=$(printf 'baseline (mobo/RAM/SSD/fans)  %d W\n' "$BASELINE")$'\n'
tip+="──────────────────────────"$'\n'
tip+=$(printf 'components          %d W\n' "$components")$'\n'
tip+=$(printf '+ PSU loss (~%d%%)    %d W\n' "$(awk -v e=$PSU_EFF 'BEGIN{printf "%.0f",(1-e)*100}')" "$loss")$'\n'
tip+=$(printf '≈ wall draw         %d W'    "$wall")
tip+="</tt>"$'\n\n'
tip+="<i>estimate — no real PSU/wall sensor on this PC</i>"

jq -cn --arg t "$plug  ${wall} W" --arg c "$class" --arg tip "$tip" \
  '{text:$t, class:$c, tooltip:$tip}'
