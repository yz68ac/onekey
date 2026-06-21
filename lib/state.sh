#!/usr/bin/env bash

default_state_json() {
    cat <<EOF
{
  "version": 1,
  "mode": "xhttp",
  "domain": "",
  "address": "",
  "acme_email": "",
  "api": {
    "host": "$API_HOST_DEFAULT",
    "port": $API_PORT_DEFAULT
  },
  "xhttp": {
    "listen": "127.0.0.1",
    "port": 10000,
    "path": "$(generate_path)"
  },
  "reality": {
    "listen_port": 443,
    "target": "",
    "server_name": "",
    "server_names": [],
    "address": "",
    "private_key": "",
    "public_key": "",
    "short_ids": [],
    "spider_x": "/"
  },
  "caddy": {
    "site_root": "$CADDY_SITE_ROOT"
  }
}
EOF
}

init_state_files() {
    need_cmd jq
    ensure_dirs
    if [ ! -f "$STATE_FILE" ]; then
        default_state_json > "$STATE_FILE"
        chmod 600 "$STATE_FILE"
    fi
    if [ ! -f "$USERS_FILE" ]; then
        printf '{\n  "users": []\n}\n' > "$USERS_FILE"
        chmod 600 "$USERS_FILE"
    fi
    jq -e . "$STATE_FILE" >/dev/null || die "Invalid state file: $STATE_FILE"
    jq -e '.users | type == "array"' "$USERS_FILE" >/dev/null || die "Invalid users file: $USERS_FILE"
}

state_get() {
    init_state_files
    jq -r "$1" "$STATE_FILE"
}

state_set_xhttp() {
    local domain="$1" acme_email="$2" path="$3" port="$4"
    init_state_files
    jq \
        --arg domain "$domain" \
        --arg acme_email "$acme_email" \
        --arg path "$path" \
        --argjson port "$port" \
        '.mode = "xhttp"
         | .domain = $domain
         | .address = $domain
         | .acme_email = $acme_email
         | .xhttp.path = $path
         | .xhttp.port = $port' \
        "$STATE_FILE" > "$STATE_FILE.tmp"
    mv "$STATE_FILE.tmp" "$STATE_FILE"
    chmod 600 "$STATE_FILE"
}

state_set_reality() {
    local server_name="$1" target="$2" address="$3" port="$4" private_key="$5" public_key="$6" short_id="$7"
    init_state_files
    jq \
        --arg server_name "$server_name" \
        --arg target "$target" \
        --arg address "$address" \
        --argjson port "$port" \
        --arg private_key "$private_key" \
        --arg public_key "$public_key" \
        --arg short_id "$short_id" \
        '.mode = "reality-vision"
         | .domain = $address
         | .address = $address
         | .reality.server_name = $server_name
         | .reality.server_names = [$server_name]
         | .reality.target = $target
         | .reality.address = $address
         | .reality.listen_port = $port
         | .reality.private_key = $private_key
         | .reality.public_key = $public_key
         | .reality.short_ids = [$short_id]' \
        "$STATE_FILE" > "$STATE_FILE.tmp"
    mv "$STATE_FILE.tmp" "$STATE_FILE"
    chmod 600 "$STATE_FILE"
}

state_set_xhttp_reality() {
    local server_name="$1" target="$2" address="$3" path="$4" port="$5" private_key="$6" public_key="$7" short_id="$8"
    init_state_files
    jq \
        --arg server_name "$server_name" \
        --arg target "$target" \
        --arg address "$address" \
        --arg path "$path" \
        --argjson port "$port" \
        --arg private_key "$private_key" \
        --arg public_key "$public_key" \
        --arg short_id "$short_id" \
        '.mode = "xhttp-reality"
         | .domain = $address
         | .address = $address
         | .xhttp.path = $path
         | .reality.server_name = $server_name
         | .reality.server_names = [$server_name]
         | .reality.target = $target
         | .reality.address = $address
         | .reality.listen_port = $port
         | .reality.private_key = $private_key
         | .reality.public_key = $public_key
         | .reality.short_ids = [$short_id]' \
        "$STATE_FILE" > "$STATE_FILE.tmp"
    mv "$STATE_FILE.tmp" "$STATE_FILE"
    chmod 600 "$STATE_FILE"
}
