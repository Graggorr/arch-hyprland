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

procsnap() {
  awk '{ l=$0; o=index(l,"("); c=match(l,/\) [A-Z] /); n=substr(l,o+1,c-o-1); r=substr(l,c+2); split(r,f," "); print FILENAME, f[12]+f[13], n }' /proc/[0-9]*/stat 2>/dev/null
}

read_energy() { cat "$1/energy_uj" 2>/dev/null; }

# ── snapshot 1 ──
mapfile -t stat1 < <(grep -E '^cpu[0-9 ]' /proc/stat)
e_pkg1=$(read_energy "$RAPL_PKG")
e_core1=$(read_energy "$RAPL_CORE")
t1=$(date +%s.%N)
ps1=$(procsnap)

sleep "$INTERVAL"

# ── snapshot 2 ──
mapfile -t stat2 < <(grep -E '^cpu[0-9 ]' /proc/stat)
e_pkg2=$(read_energy "$RAPL_PKG")
e_core2=$(read_energy "$RAPL_CORE")
t2=$(date +%s.%N)
ps2=$(procsnap)

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


model=$(awk -F': ' '/^model name/{print $2; exit}' /proc/cpuinfo | sed 's/(R)//g; s/(TM)//g; s/13th Gen //; s/ CPU//; s/  */ /g')
read -r l1 l5 l15 runq _ < /proc/loadavg
gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)
up=$(awk '{s=int($1); d=int(s/86400); h=int(s%86400/3600); m=int(s%3600/60); if(d) printf "%dd %dh %dm", d,h,m; else printf "%dh %dm", h,m}' /proc/uptime)
hz=$(getconf CLK_TCK)
top=$(awk -v hz="$hz" -v dt="$(awk -v a="$t1" -v b="$t2" 'BEGIN{print b-a}')" '
  FNR==NR { a[$1]=$2; next }
  ($1 in a) { d=$2-a[$1]; if (d>0) { n=$3; for(i=4;i<=NF;i++) n=n" "$i; s[n]+=d } }
  END { for (n in s) printf "%.1f\t%s\n", 100*s[n]/hz/dt, n }' <(echo "$ps1") <(echo "$ps2") \
  | sort -t$'\t' -k1,1 -rn | head -6 | awk -F'\t' '{printf "  %6s%%  %s\n", $1, substr($2,1,28)}')

therm=$(printf '')
temp=$(sensors -j 2>/dev/null | jq -r '."coretemp-isa-0000"."Package id 0".temp1_input // empty')
[ -z "$temp" ] && temp=$(sensors -j 2>/dev/null | jq -r '[.. | objects | ."Package id 0"?.temp1_input] | map(select(.!=null)) | first // empty')
temp=${temp%.*}

tooltip="${model}  ·  ${ncpu} threads"$'\n'
tooltip+="usage     ${total_usage}%"$'\n'
[ -n "$temp" ] && tooltip+="temp      ${temp}°C package"$'\n'
if [ -n "$watt_line" ]; then
  tooltip+="power     ${watt_line#package }"$'\n'
else
  tooltip+="power     n/a (RAPL not readable)"$'\n'
fi
tooltip+="load      ${l1} ${l5} ${l15}"$'\n'
tooltip+="tasks     ${runq} running/total"$'\n'
tooltip+="governor  ${gov:-n/a}"$'\n'
tooltip+="uptime    ${up}"$'\n'$'\n'
tooltip+="busiest now (% of one core)"$'\n'"${top}"$'\n'$'\n'
tooltip+="per core"$'\n'"${lines%$'\n'}"

class="ok"
[ "$total_usage" -ge 70 ] && class="high"
[ "$total_usage" -ge 90 ] && class="crit"
if [ -n "$temp" ]; then
  [ "$temp" -ge 70 ] && [ "$class" = "ok" ] && class="high"
  [ "$temp" -ge 85 ] && class="crit"
fi
text="$icon  ${total_usage}%"

jq -cn --arg t "$text" --arg c "$class" --arg tip "$tooltip" \
  '{text:$t, class:$c, tooltip:$tip}'
