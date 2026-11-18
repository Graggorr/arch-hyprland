#!/usr/bin/env bash
set -uo pipefail

cache="$HOME/.local/share/Steam/appcache/librarycache"

icon_for() {
    local f
    f=$(ls "$cache/$1" 2>/dev/null | grep -m1 -E '^[0-9a-f]{40}\.jpg$')
    [ -n "$f" ] && { printf '%s\n' "$cache/$1/$f"; return 0; }
    for f in logo.png header.jpg; do
        [ -r "$cache/$1/$f" ] && { printf '%s\n' "$cache/$1/$f"; return 0; }
    done
    return 1
}

app_id() {
    local class=$1 pid=$2 v
    case $class in
        steam_app_[0-9]*) printf '%s\n' "${class#steam_app_}"; return 0 ;;
    esac
    [ "$pid" -gt 0 ] 2>/dev/null || return 1
    v=$(tr '\0' '\n' <"/proc/$pid/environ" 2>/dev/null | sed -n 's/^\(SteamAppId\|SteamGameId\)=\([0-9][0-9]*\)$/\2/p' | head -1)
    [ -n "$v" ] && [ "$v" != 0 ] && [ "$v" != 769 ] || return 1
    printf '%s\n' "$v"
}

out='{'
sep=''
while IFS=$'\t' read -r class pid; do
    [ -n "$class" ] || continue
    id=$(app_id "$class" "$pid") || continue
    icon=$(icon_for "$id") || continue
    out+="$sep\"${class//\"/}\":\"$icon\""
    sep=','
done < <(hyprctl clients -j | jq -r '.[] | [.class, .pid] | @tsv' | sort -u)
printf '%s}\n' "$out"
