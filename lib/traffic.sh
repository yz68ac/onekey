#!/usr/bin/env bash

traffic_query() {
    local server="$1" pattern="${2:-user>>>}" raw
    if ! raw="$("$XRAY_BIN" api statsquery --server="$server" -pattern "$pattern" 2>/dev/null)"; then
        warn "Unable to query Xray Stats API at $server"
        return 1
    fi
    printf '%s\n' "$raw"
}

traffic_value_from_output() {
    local raw="$1" name="$2" value
    value="$(printf '%s\n' "$raw" | jq -er --arg name "$name" '
        [(.stat // [])[] | select(.name == $name) | (.value | tonumber)]
        | add // 0
    ' 2>/dev/null)" || value=""

    # Compatibility with older protobuf-text CLI output.
    if [ -z "$value" ]; then
        value="$(printf '%s\n' "$raw" |
            awk -v wanted="$name" '
                /"name"[[:space:]]*:/ {
                    current = index($0, wanted) > 0
                    next
                }
                /^[[:space:]]*name:/ {
                    current = index($0, wanted) > 0
                    next
                }
                (current && /"value"[[:space:]]*:/) || (current && /^[[:space:]]*value:/) {
                    line=$0
                    sub(/^.*:[[:space:]]*/, "", line)
                    gsub(/[^0-9-]/, "", line)
                    if (line ~ /^[0-9]+$/) { print line; found=1 }
                    current=0
                }
                END { if (!found) print 0 }
            ' | tail -n 1)"
    fi

    [[ "$value" =~ ^[0-9]+$ ]] || value=0
    printf '%s\n' "$value"
}

traffic_show_user() {
    local email="$1" raw="$2" uplink downlink total
    uplink="$(traffic_value_from_output "$raw" "user>>>$email>>>traffic>>>uplink")"
    downlink="$(traffic_value_from_output "$raw" "user>>>$email>>>traffic>>>downlink")"
    total=$((uplink + downlink))
    printf '%-32s %14s %14s %14s\n' "$email" "$(bytes_human "$uplink")" "$(bytes_human "$downlink")" "$(bytes_human "$total")"
}

traffic_show() {
    local target="${1:-all}" server raw
    init_state_files
    need_cmd "$XRAY_BIN"

    server="$(state_get '(.api.host // "127.0.0.1") + ":" + ((.api.port // 32768) | tostring)')"
    raw="$(traffic_query "$server" "user>>>")" || die "Xray Stats API query failed"

    printf '%-32s %14s %14s %14s\n' "EMAIL" "UPLINK" "DOWNLINK" "TOTAL"
    if [ "$target" = "all" ]; then
        while IFS= read -r email; do
            [ -n "$email" ] && traffic_show_user "$email" "$raw"
        done < <(jq -r '.users[]?.email' "$USERS_FILE")
    else
        if ! jq -e --arg email "$target" '.users[]? | select(.email == $email)' "$USERS_FILE" >/dev/null; then
            die "User not found: $target"
        fi
        traffic_show_user "$target" "$raw"
    fi
}
