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
  "reality_self": {
    "listen": "127.0.0.1",
    "port": 8443
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

# Return success when the REALITY identity used for share links matches at
# least one REALITY inbound in the rendered Xray configuration.
reality_config_matches_state() {
    local server_name target private_key short_id
    [ -f "$STATE_FILE" ] && [ -f "$XRAY_CONFIG" ] || return 1

    server_name="$(jq -r '.reality.server_name // ""' "$STATE_FILE")"
    target="$(jq -r '.reality.target // ""' "$STATE_FILE")"
    private_key="$(jq -r '.reality.private_key // ""' "$STATE_FILE")"
    short_id="$(jq -r '(.reality.short_ids // []) | .[0] // ""' "$STATE_FILE")"
    [ -n "$server_name" ] && [ -n "$target" ] &&
        [ -n "$private_key" ] && [ -n "$short_id" ] || return 1

    jq -e --arg server_name "$server_name" --arg target "$target" --arg private_key "$private_key" --arg short_id "$short_id" 'any(
            .inbounds[]?;
            (.streamSettings.realitySettings // null) as $reality
            | $reality != null
            and $reality.target == $target
            and (($reality.serverNames // []) | index($server_name)) != null
            and $reality.privateKey == $private_key
            and (($reality.shortIds // []) | index($short_id)) != null
        )' "$XRAY_CONFIG" >/dev/null 2>&1
}

reality_config_drift_detail() {
    local state_server state_target config_server config_target
    state_server="$(jq -r '.reality.server_name // "(empty)"' "$STATE_FILE")"
    state_target="$(jq -r '.reality.target // "(empty)"' "$STATE_FILE")"
    config_server="$(jq -r '[.inbounds[]? | .streamSettings.realitySettings? | select(. != null)][0].serverNames[0] // "(missing)"' "$XRAY_CONFIG" 2>/dev/null || printf '(invalid)')"
    config_target="$(jq -r '[.inbounds[]? | .streamSettings.realitySettings? | select(. != null)][0].target // "(missing)"' "$XRAY_CONFIG" 2>/dev/null || printf '(invalid)')"
    printf 'state SNI/target=%s/%s; Xray SNI/target=%s/%s' "$state_server" "$state_target" "$config_server" "$config_target"
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
    replace_private_file "$STATE_FILE.tmp" "$STATE_FILE"
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
    replace_private_file "$STATE_FILE.tmp" "$STATE_FILE"
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
    replace_private_file "$STATE_FILE.tmp" "$STATE_FILE"
}

state_set_xhttp_reality_self() {
    local domain="$1" acme_email="$2" address="$3" path="$4" port="$5" fallback_port="$6" private_key="$7" public_key="$8" short_id="$9"
    local target="127.0.0.1:$fallback_port"
    init_state_files
    jq \
        --arg domain "$domain" \
        --arg acme_email "$acme_email" \
        --arg address "$address" \
        --arg path "$path" \
        --arg target "$target" \
        --argjson port "$port" \
        --argjson fallback_port "$fallback_port" \
        --arg private_key "$private_key" \
        --arg public_key "$public_key" \
        --arg short_id "$short_id" \
        '.mode = "xhttp-reality-self"
         | .domain = $domain
         | .address = $address
         | .acme_email = $acme_email
         | .xhttp.path = $path
         | .reality.server_name = $domain
         | .reality.server_names = [$domain]
         | .reality.target = $target
         | .reality.address = $address
         | .reality.listen_port = $port
         | .reality.private_key = $private_key
         | .reality.public_key = $public_key
         | .reality.short_ids = [$short_id]
         | .reality_self.listen = "127.0.0.1"
         | .reality_self.port = $fallback_port' \
        "$STATE_FILE" > "$STATE_FILE.tmp"
    replace_private_file "$STATE_FILE.tmp" "$STATE_FILE"
}

state_set_reality_self() {
    local domain="$1" acme_email="$2" address="$3" port="$4" fallback_port="$5" private_key="$6" public_key="$7" short_id="$8"
    local target="127.0.0.1:$fallback_port"
    init_state_files
    jq \
        --arg domain "$domain" \
        --arg acme_email "$acme_email" \
        --arg address "$address" \
        --arg target "$target" \
        --argjson port "$port" \
        --argjson fallback_port "$fallback_port" \
        --arg private_key "$private_key" \
        --arg public_key "$public_key" \
        --arg short_id "$short_id" \
        '.mode = "reality-self"
         | .domain = $domain
         | .address = $address
         | .acme_email = $acme_email
         | .reality.server_name = $domain
         | .reality.server_names = [$domain]
         | .reality.target = $target
         | .reality.address = $address
         | .reality.listen_port = $port
         | .reality.private_key = $private_key
         | .reality.public_key = $public_key
         | .reality.short_ids = [$short_id]
         | .reality_self.listen = "127.0.0.1"
         | .reality_self.port = $fallback_port' \
        "$STATE_FILE" > "$STATE_FILE.tmp"
    replace_private_file "$STATE_FILE.tmp" "$STATE_FILE"
}
