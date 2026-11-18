#!/usr/bin/env bash
# Spotify Web API control for the island's media tool: shuffle, repeat and
# Liked Songs. Auth is Authorization Code + PKCE; refresh token and client id
# live in gnome-keyring, the access token in XDG_RUNTIME_DIR.
# Usage: auth <client-id> | status | shuffle | repeat | like | deauth
# status -> {shuffle,repeat,liked,premium,track,canShuffle,canRepeat} | {error}

set -u

API=https://api.spotify.com/v1
ACCOUNTS=https://accounts.spotify.com
REDIRECT=http://127.0.0.1:8898/callback
SCOPES="user-read-playback-state user-modify-playback-state user-library-read user-library-modify user-read-private"
CACHE="${XDG_RUNTIME_DIR:-/tmp}/spotify-ctl-token.json"

err() { printf '{"error":"%s"}\n' "$1"; exit 1; }

kr_get() { secret-tool lookup service spotify-ctl field "$1" 2>/dev/null; }
kr_set() { printf '%s' "$2" | secret-tool store --label="spotify-ctl $1" service spotify-ctl field "$1"; }

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

store_tokens() {
    local json="$1"
    local access expires refresh
    access=$(jq -r '.access_token // empty' <<<"$json")
    expires=$(jq -r '.expires_in // 3600' <<<"$json")
    refresh=$(jq -r '.refresh_token // empty' <<<"$json")
    [ -z "$access" ] && return 1
    umask 077
    jq -cn --arg t "$access" --argjson e "$(( $(date +%s) + expires - 60 ))" \
        '{access_token:$t, expires_at:$e}' > "$CACHE"
    [ -n "$refresh" ] && kr_set refresh "$refresh"
    return 0
}

access_token() {
    if [ -f "$CACHE" ]; then
        local tok exp
        tok=$(jq -r '.access_token // empty' "$CACHE" 2>/dev/null)
        exp=$(jq -r '.expires_at // 0' "$CACHE" 2>/dev/null)
        [ -n "$tok" ] && [ "$(date +%s)" -lt "$exp" ] && { printf '%s' "$tok"; return 0; }
    fi
    local refresh client
    refresh=$(kr_get refresh); client=$(kr_get clientid)
    [ -z "$refresh" ] || [ -z "$client" ] && return 1
    local resp
    resp=$(curl -sf -X POST "$ACCOUNTS/api/token" \
        -d grant_type=refresh_token -d refresh_token="$refresh" -d client_id="$client") || return 1
    store_tokens "$resp" || return 1
    jq -r '.access_token' "$CACHE"
}

api() { # method path [curl args...]
    local method="$1" path="$2"; shift 2
    local tok; tok=$(access_token) || return 9
    curl -s -X "$method" -H "Authorization: Bearer $tok" -w '\n%{http_code}' "$API$path" "$@"
}

cmd_auth() {
    local client="${1:-}"
    [ -z "$client" ] && { echo "usage: spotify-ctl.sh auth <client-id>" >&2; exit 1; }
    local verifier challenge
    verifier=$(openssl rand 48 | b64url)
    challenge=$(printf '%s' "$verifier" | openssl dgst -sha256 -binary | b64url)

    local url="$ACCOUNTS/authorize?client_id=$client&response_type=code&redirect_uri=$REDIRECT&code_challenge_method=S256&code_challenge=$challenge&scope=$(printf '%s' "$SCOPES" | sed 's/ /%20/g')"
    echo "Opening browser for Spotify consent..." >&2
    setsid -f xdg-open "$url" >/dev/null 2>&1

    local code
    code=$(python3 - <<'PYEOF'
import http.server, urllib.parse, sys
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        self.send_response(200); self.send_header("Content-Type","text/html"); self.end_headers()
        self.wfile.write(b"<h2>Authorized &mdash; you can close this tab.</h2>")
        print(q.get("code",[""])[0]); sys.stdout.flush()
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 8898), H)
s.timeout = 180
s.handle_request()
PYEOF
    )
    [ -z "$code" ] && err "no code received (timeout or denied)"

    local resp
    resp=$(curl -sf -X POST "$ACCOUNTS/api/token" \
        -d grant_type=authorization_code -d code="$code" -d redirect_uri="$REDIRECT" \
        -d client_id="$client" -d code_verifier="$verifier") || err "token exchange failed"
    kr_set clientid "$client"
    store_tokens "$resp" || err "no access token in response"
    echo '{"ok":"authorized"}'
}

split_resp() { PLAYER_HTTP="${1##*$'\n'}"; PLAYER_BODY="${1%$'\n'*}"; }

cmd_status() {
    local raw; raw=$(api GET /me/player) || err "noauth"
    split_resp "$raw"
    local shuffle=false repeat=off track_id="" track=""
    local can_shuffle=false can_repeat=false
    if [ "$PLAYER_HTTP" = "200" ]; then
        shuffle=$(jq -r '.shuffle_state // false' <<<"$PLAYER_BODY")
        repeat=$(jq -r '.repeat_state // "off"' <<<"$PLAYER_BODY")
        track_id=$(jq -r '.item.id // empty' <<<"$PLAYER_BODY")
        track=$(jq -r '.item.name // empty' <<<"$PLAYER_BODY")
        can_shuffle=$(jq -r '.actions.disallows.toggling_shuffle // false | not' <<<"$PLAYER_BODY")
        can_repeat=$(jq -r '(.actions.disallows.toggling_repeat_context // false) and (.actions.disallows.toggling_repeat_track // false) | not' <<<"$PLAYER_BODY")
    elif [ "$PLAYER_HTTP" != "204" ]; then
        err "player http $PLAYER_HTTP"
    fi

    local premium=false
    raw=$(api GET /me); split_resp "$raw"
    [ "$PLAYER_HTTP" = "200" ] && \
        [ "$(jq -r '.product // ""' <<<"$PLAYER_BODY")" = "premium" ] && premium=true

    local liked=false
    if [ -n "$track_id" ]; then
        raw=$(api GET "/me/library/contains?uris=spotify%3Atrack%3A$track_id"); split_resp "$raw"
        [ "$PLAYER_HTTP" = "200" ] && liked=$(jq -r '.[0] // false' <<<"$PLAYER_BODY")
    fi

    jq -cn --argjson s "$shuffle" --arg r "$repeat" --argjson l "$liked" \
           --argjson p "$premium" --arg t "$track" \
           --argjson cs "$can_shuffle" --argjson cr "$can_repeat" \
           '{shuffle:$s, repeat:$r, liked:$l, premium:$p, track:$t,
             canShuffle:$cs, canRepeat:$cr}'
}

cmd_shuffle() {
    local raw; raw=$(api GET /me/player) || err "noauth"
    split_resp "$raw"
    [ "$PLAYER_HTTP" != "200" ] && err "no active device"
    local cur; cur=$(jq -r '.shuffle_state // false' <<<"$PLAYER_BODY")
    local next=true; [ "$cur" = "true" ] && next=false
    raw=$(api PUT "/me/player/shuffle?state=$next"); split_resp "$raw"
    case "$PLAYER_HTTP" in 2*) printf '{"shuffle":%s}\n' "$next";; *) err "http $PLAYER_HTTP";; esac
}

cmd_repeat() {
    local raw; raw=$(api GET /me/player) || err "noauth"
    split_resp "$raw"
    [ "$PLAYER_HTTP" != "200" ] && err "no active device"
    local cur next
    cur=$(jq -r '.repeat_state // "off"' <<<"$PLAYER_BODY")
    case "$cur" in
        off) next=context ;;
        context) next=track ;;
        *) next=off ;;
    esac
    raw=$(api PUT "/me/player/repeat?state=$next"); split_resp "$raw"
    case "$PLAYER_HTTP" in 2*) printf '{"repeat":"%s"}\n' "$next";; *) err "http $PLAYER_HTTP";; esac
}

cmd_like() {
    local raw; raw=$(api GET /me/player) || err "noauth"
    split_resp "$raw"
    local track_id
    track_id=$(jq -r '.item.id // empty' <<<"$PLAYER_BODY")
    [ -z "$track_id" ] && err "nothing playing"
    local uri="spotify%3Atrack%3A$track_id"
    raw=$(api GET "/me/library/contains?uris=$uri"); split_resp "$raw"
    local liked; liked=$(jq -r '.[0] // false' <<<"$PLAYER_BODY")
    if [ "$liked" = "true" ]; then
        raw=$(api DELETE "/me/library?uris=$uri")
    else
        raw=$(api PUT "/me/library?uris=$uri")
    fi
    split_resp "$raw"
    case "$PLAYER_HTTP" in
        2*) printf '{"liked":%s}\n' "$([ "$liked" = "true" ] && echo false || echo true)";;
        *) err "http $PLAYER_HTTP";;
    esac
}

cmd_deauth() {
    secret-tool clear service spotify-ctl field refresh 2>/dev/null
    secret-tool clear service spotify-ctl field clientid 2>/dev/null
    rm -f "$CACHE"
    echo '{"ok":"forgotten"}'
}

case "${1:-}" in
    auth) shift; cmd_auth "$@" ;;
    status) cmd_status ;;
    shuffle) cmd_shuffle ;;
    repeat) cmd_repeat ;;
    like) cmd_like ;;
    deauth) cmd_deauth ;;
    *) echo "usage: spotify-ctl.sh auth <client-id> | status | shuffle | repeat | like | deauth" >&2; exit 1 ;;
esac
