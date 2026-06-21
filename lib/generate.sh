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
    if have_cmd "$XRAY_BIN"; then
        if [ -z "$input" ]; then
            "$XRAY_BIN" uuid
        elif validate_uuid "$input"; then
            printf '%s\n' "$input"
        else
            "$XRAY_BIN" uuid -i "$input"
        fi
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
    private_key="$(printf '%s\n' "$output" | awk -F': ' '/Private key/ {print $2; exit}')"
    public_key="$(printf '%s\n' "$output" | awk -F': ' '/Public key/ {print $2; exit}')"
    [ -n "$private_key" ] && [ -n "$public_key" ] || die "Failed to parse xray x25519 output"
    printf '%s\n%s\n' "$private_key" "$public_key"
}

generate_short_id() {
    random_hex 8
}
