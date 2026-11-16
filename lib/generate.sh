#!/usr/bin/env bash

random_hex() {
    local bytes="${1:-8}"
    if have_cmd openssl; then
        openssl rand -hex "$bytes"
    elif [ -r /dev/urandom ]; then
        od -An -N "$bytes" -tx1 /dev/urandom | tr -d ' \n'
    else
        date +%s%N | sha256sum | awk "{print substr(\$1,1,$((bytes * 2)))}"
    fi
}

generate_path() {
    printf '/%s.%s\n' "$(random_hex 5)" "$(random_hex 7)"
}

generate_uuid() {
    local input="${1:-}"
    # A caller-supplied UUID or seed must never be swapped for a random one:
    # clients configured with it would silently stop matching.
    if [ -n "$input" ]; then
        if validate_uuid "$input"; then
            printf '%s\n' "$input"
        elif have_cmd "$XRAY_BIN"; then
            "$XRAY_BIN" uuid -i "$input"
        else
            die "Cannot derive a UUID from a seed without Xray; install Xray first or pass a full UUID"
        fi
    elif have_cmd "$XRAY_BIN"; then
        "$XRAY_BIN" uuid
    elif [ -r /proc/sys/kernel/random/uuid ]; then
        cat /proc/sys/kernel/random/uuid
    else
        die "Cannot generate UUID: install Xray first or provide a UUID"
    fi
}

generate_x25519_pair() {
    need_cmd "$XRAY_BIN"
    local output private_key public_key
    output="$("$XRAY_BIN" x25519)"
    private_key="$(printf '%s\n' "$output" | awk -F':[[:space:]]*' 'tolower($1) ~ /^private[[:space:]]*key$/ || tolower($1) == "privatekey" {print $2; exit}')"
    public_key="$(printf '%s\n' "$output" | awk -F':[[:space:]]*' 'tolower($1) ~ /public[[:space:]]*key/ || tolower($1) ~ /publickey/ || tolower($1) ~ /^password([[:space:]]|\(|$)/ {print $2; exit}')"
    [ -n "$private_key" ] && [ -n "$public_key" ] || die "Failed to parse xray x25519 output"
    printf '%s\n%s\n' "$private_key" "$public_key"
}

generate_short_id() {
    random_hex 8
}
