#!/usr/bin/env bash
set -u

expr="${1:-}"
[ -z "${expr// }" ] && exit 0

r=$(timeout 3 qalc -t "$expr" 2>/dev/null | tail -n 1)

if [[ "$r" == *" + "* && "$expr" =~ ^(.+)[[:space:]](to|in|→)[[:space:]]+([^+-].*)$ ]]; then
    r2=$(timeout 3 qalc -t "${BASH_REMATCH[1]} ${BASH_REMATCH[2]} -${BASH_REMATCH[3]}" 2>/dev/null | tail -n 1)
    [[ -n "$r2" && "$r2" != *"("* ]] && r="$r2"
fi

printf '%s\n' "$r"
