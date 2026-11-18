#!/usr/bin/env bash
# Which connectors can actually do HDR. Hyprland reports the CURRENT colour
# state (colorManagementPreset, currentFormat) but never the panel's
# capability, so the only honest source is the EDID the monitor hands the
# kernel: an HDR Static Metadata block advertising the SMPTE ST2084 (PQ)
# transfer function. Emits the panel's own desired peak luminance too, which
# is what makes a 400-nit edge-lit panel legible as such in the UI.
#
# JSON: {"probe":"ok|unavailable","caps":{"DP-2":{"hdr":true,"nits":367,"bpc":10}}}
# probe=unavailable means edid-decode is missing and capability is UNKNOWN —
# the UI must fail open there rather than hiding a toggle that would work.

if ! command -v edid-decode >/dev/null 2>&1; then
    printf '{"probe":"unavailable","caps":{}}\n'
    exit 0
fi

out=""
for edid in /sys/class/drm/card*-*/edid; do
    # sysfs reports this attribute as size 0 even when populated, so -s is a trap.
    [ -r "$edid" ] || continue
    dir=${edid%/edid}
    [ "$(cat "$dir/status" 2>/dev/null)" = "connected" ] || continue

    conn=${dir##*/}        # card1-DP-2
    conn=${conn#card*-}    # DP-2

    decoded=$(edid-decode "$edid" 2>/dev/null) || continue
    grep -q 'SMPTE ST2084' <<<"$decoded" || continue

    # "Desired content max luminance: 92 (366.802 cd/m^2)" — the panel's own
    # number, not the "Maximum luminance" of an unrelated block.
    nits=$(grep -m1 'Desired content max luminance' <<<"$decoded" \
           | sed -n 's/.*(\([0-9.]*\) cd\/m\^2).*/\1/p')
    nits=${nits%%.*}
    [ -n "$nits" ] || nits=0

    bpc=$(grep -m1 'Bits per primary color channel' <<<"$decoded" \
          | sed -n 's/.*: \([0-9]*\).*/\1/p')
    [ -n "$bpc" ] || bpc=10

    out+="\"${conn}\":{\"hdr\":true,\"nits\":${nits},\"bpc\":${bpc}},"
done

printf '{"probe":"ok","caps":{%s}}\n' "${out%,}"
