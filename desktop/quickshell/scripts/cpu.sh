#!/usr/bin/env bash
# CPU widget for the bar.
#   Bar text : overall CPU usage %.
#   Tooltip  : per-logical-core usage% + current clock, and a "total" section
#              with overall usage and real power draw (watts) from Intel RAPL.
#
# Power note: the i5-13400F only exposes two RAPL domains — package-0 (whole
# chip) and "core" (all cores combined). There is NO per-core wattage sensor,
# so watts are reported only as package / cores / uncore totals, not per core.
# Reading energy_uj requires the 99-rapl-powercap.rules udev rule (group wheel).

icon=$(printf '\U000f0ee0')
bolt=$(printf '\U000f0241')

RAPL_PKG=/sys/class/powercap/intel-rapl:0        # package-0
RAPL_CORE=/sys/class/powercap/intel-rapl:0:0     # core domain (all cores)
MAXRANGE=$(cat "$RAPL_PKG/max_energy_range_uj" 2>/dev/null)
INTERVAL=0.8

read_energy() { cat "$1/energy_uj" 2>/dev/null; }

# ── snapshot 1 ──
mapfile -t stat1 < <(grep -E '^cpu[0-9 ]' /proc/stat)
e_pkg1=$(read_energy "$RAPL_PKG")
e_core1=$(read_energy "$RAPL_CORE")
t1=$(date +%s.%N)

sleep "$INTERVAL"

# ── snapshot 2 ──
mapfile -t stat2 < <(grep -E '^cpu[0-9 ]' /proc/stat)
e_pkg2=$(read_energy "$RAPL_PKG")
e_core2=$(read_energy "$RAPL_CORE")
t2=$(date +%s.%N)

# ── per-core usage% + total, via awk over the two /proc/stat snapshots ──
# stat lines: "cpu ..." (aggregate) then cpu0..cpuN. Fields after label:
# user nice system idle iowait irq softirq steal guest guest_nice
# busy = total - idle - iowait ; usage% = 100 * dbusy / dtotal
usage_data=$(printf '%s\n' "${stat1[@]}" "===" "${stat2[@]}" | awk '
  /^===/ { phase=2; next }
  {
    key=$1
    total=0; for (i=2;i<=NF;i++) total+=$i
    idlev=$5+$6                       # idle + iowait
    if (phase!=2) { T1[key]=total; I1[key]=idlev }
    else          { T2[key]=total; I2[key]=idlev }
  }
  END {
    for (key in T2) {
      dt=T2[key]-T1[key]; di=I2[key]-I1[key]
      u = (dt>0) ? (100*(dt-di)/dt) : 0
      printf "%s %.0f\n", key, (u<0?0:(u>100?100:u))
    }
  }')

# total usage (the aggregate "cpu" line)
total_usage=$(awk '$1=="cpu"{print $2}' <<<"$usage_data")
[ -z "$total_usage" ] && total_usage=0

# ── per-core tooltip lines (core index order), pulling current clock ──
ncpu=$(grep -c '^cpu[0-9]' /proc/stat)
lines=""
for ((c=0; c<ncpu; c++)); do
  up=$(awk -v k="cpu$c" '$1==k{print $2}' <<<"$usage_data")
  [ -z "$up" ] && up=0
  khz=$(cat "/sys/devices/system/cpu/cpu$c/cpufreq/scaling_cur_freq" 2>/dev/null)
  if [ -n "$khz" ]; then
    ghz=$(awk -v k="$khz" 'BEGIN{printf "%.2f", k/1000000}')
    freq="${ghz} GHz"
  else
    freq="  —  "
  fi
  lines+=$(printf 'core %-2d  %3d%%   %s\n' "$c" "$up" "$freq")
  lines+=$'\n'
done

# ── power draw (watts) over the sample window ──
watt_line=""
if [ -n "$e_pkg1" ] && [ -n "$e_pkg2" ]; then
  watt_line=$(awk -v p1="$e_pkg1" -v p2="$e_pkg2" \
                  -v c1="$e_core1" -v c2="$e_core2" \
                  -v t1="$t1" -v t2="$t2" -v mx="$MAXRANGE" '
    function delta(a,b,  d){ d=b-a; if(d<0 && mx>0) d+=mx; return d }
    BEGIN {
      dt=t2-t1; if(dt<=0) dt=0.8
      wp=delta(p1,p2)/1e6/dt
      hascore=(c1!="" && c2!="")
      if(hascore){ wc=delta(c1,c2)/1e6/dt; wu=wp-wc; if(wu<0)wu=0 }
      if(hascore)
        printf "package %.1f W   (cores %.1f W · uncore %.1f W)", wp, wc, wu
      else
        printf "package %.1f W", wp
    }')
fi

# pango-markup tooltip: monospace body + a totals footer
tooltip="<tt>${lines}</tt>"
tooltip+="────────────────────"$'\n'
tooltip+="<b>total</b>  ${total_usage}% usage"
if [ -n "$watt_line" ]; then
  tooltip+=$'\n'"${bolt} ${watt_line}"
else
  tooltip+=$'\n'"${bolt} watts n/a (RAPL not readable — see 99-rapl-powercap.rules)"
fi

therm=$(printf '\uf2c9')
temp=$(sensors -j 2>/dev/null | jq -r '."coretemp-isa-0000"."Package id 0".temp1_input // empty')
[ -z "$temp" ] && temp=$(sensors -j 2>/dev/null | jq -r '[.. | objects | ."Package id 0"?.temp1_input] | map(select(.!=null)) | first // empty')
temp=${temp%.*}

class="ok"
[ "$total_usage" -ge 70 ] && class="high"
[ "$total_usage" -ge 90 ] && class="crit"

if [ -n "$temp" ]; then
  text="$icon  ${total_usage}%"
  tooltip+=$'\n'"${therm} package ${temp}°C"
  [ "$temp" -ge 70 ] && [ "$class" = "ok" ] && class="high"
  [ "$temp" -ge 85 ] && class="crit"
else
  text="$icon  ${total_usage}%"
  tooltip+=$'\n'"${therm} package temp n/a (no coretemp sensor)"
fi

jq -cn --arg t "$text" --arg c "$class" --arg tip "$tooltip" \
  '{text:$t, class:$c, tooltip:$tip}'
