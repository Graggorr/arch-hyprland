#!/usr/bin/env bash
set -uo pipefail

steam_root="$HOME/.local/share/Steam"
extra_file="$HOME/.config/quickshell/game-processes.txt"

emit() {
    local name=${2//\\/}
    name=${name//\"/}
    printf '{"active":%s,"name":"%s","source":"%s","pid":%s}\n' "$1" "$name" "$3" "${4:-0}"
}

game_pid() {
    ps -eo pid=,ppid=,rss= | awk -v root="$1" '
        { pid[NR]=$1; ppid[NR]=$2; rss[NR]=$3; n=NR }
        END {
            desc[root] = 1
            changed = 1
            while (changed) {
                changed = 0
                for (i = 1; i <= n; i++)
                    if (!desc[pid[i]] && desc[ppid[i]]) { desc[pid[i]] = 1; changed = 1 }
            }
            best = root; bestrss = -1
            for (i = 1; i <= n; i++)
                if (desc[pid[i]] && rss[i] + 0 > bestrss) { bestrss = rss[i] + 0; best = pid[i] }
            print best
        }'
}

steam_libraries() {
    printf '%s\n' "$steam_root"
    [ -r "$steam_root/steamapps/libraryfolders.vdf" ] &&
        sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' \
            "$steam_root/steamapps/libraryfolders.vdf"
}

steam_launch() {
    local pid cmd id
    for pid in $(pgrep -f -- 'SteamLaunch AppId=' 2>/dev/null); do
        cmd=$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null) || continue
        case $cmd in
            *'SteamLaunch AppId='*) : ;;
            *) continue ;;
        esac
        id=${cmd##*SteamLaunch AppId=}
        id=${id%% *}
        id=${id//[!0-9]/}
        if [ -n "$id" ]; then
            printf '%s %s\n' "$id" "$pid"
            return 0
        fi
    done
    return 1
}

steam_name() {
    local id=$1 lib manifest name
    while read -r lib; do
        [ -n "$lib" ] || continue
        manifest="$lib/steamapps/appmanifest_$id.acf"
        [ -r "$manifest" ] || continue
        name=$(sed -n 's/^[[:space:]]*"name"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$manifest" | head -1)
        if [ -n "$name" ]; then
            printf '%s\n' "$name"
            return 0
        fi
    done < <(steam_libraries)
    printf 'AppID %s\n' "$id"
}

if launch=$(steam_launch); then
    emit true "$(steam_name "${launch%% *}")" steam "$(game_pid "${launch##* }")"
    exit 0
fi

check_patterns() {
    local line pat label hit
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        case $line in \#*) continue ;; esac
        pat=${line%%|*}
        label=${line#*|}
        [ "$label" = "$line" ] && label=$pat
        hit=$(pgrep -f -- "$pat" 2>/dev/null | head -1)
        if [ -n "$hit" ]; then
            emit true "$label" other "$(game_pid "$hit")"
            return 0
        fi
    done
    return 1
}

builtin_patterns() {
    printf '%s\n' \
        'lutris-wrapper|Lutris game' \
        '(legendary|gogdl|nile) launch|Heroic game' \
        '(^|/)gamescope|gamescope session' \
        'bottles-cli run|Bottles game'
    [ -r "$extra_file" ] && cat "$extra_file"
}

if builtin_patterns | check_patterns; then
    exit 0
fi

emit false '' none
