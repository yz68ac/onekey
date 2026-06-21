#!/usr/bin/env bash

traffic_value() {
    local pattern="$1" server="$2" raw value
    raw="$("$XRAY_BIN" api statsquery --server="$server" -pattern "$pattern" 2>/dev/null || true)"
    value="$(printf '%s\n' "$raw" | awk '/value:/ {print $2; found=1} END {if (!found) print 0}' | tail -n 1)"
    printf '%s\n' "${value:-0}"
}

traffic_show_user() {
    local email="$1" server uplink downlink total
    server="$(state_get '(.api.host // "127.0.0.1") + ":" + ((.api.port // 32768) | tostring)')"
    uplink="$(traffic_value "user>>>$email>>>traffic>>>uplink" "$server")"
    downlink="$(traffic_value "user>>>$email>>>traffic>>>downlink" "$server")"
    total=$((uplink + downlink))
    printf '%-32s %14s %14s %14s\n' "$email" "$(bytes_human "$uplink")" "$(bytes_human "$downlink")" "$(bytes_human "$total")"
}

traffic_show() {
    local target="${1:-all}"
    init_state_files
    need_cmd "$XRAY_BIN"

    printf '%-32s %14s %14s %14s\n' "EMAIL" "UPLINK" "DOWNLINK" "TOTAL"
    if [ "$target" = "all" ]; then
        jq -r '.users[]?.email' "$USERS_FILE" | while IFS= read -r email; do
            [ -n "$email" ] && traffic_show_user "$email"
        done
    else
        if ! jq -e --arg email "$target" '.users[]? | select(.email == $email)' "$USERS_FILE" >/dev/null; then
            die "User not found: $target"
        fi
        traffic_show_user "$target"
    fi
}
