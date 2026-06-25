#!/usr/bin/env bash

link_show() {
    local email="${1:-}" mode uuid label encoded_label
    init_state_files
    if [ -z "$email" ]; then
        email="$(single_user_email)"
    fi
    [ -n "$email" ] || die "Usage: ./xrayctl.sh link email"

    uuid="$(user_uuid_by_email "$email")"
    [ -n "$uuid" ] || die "User not found: $email"
    mode="$(state_get '.mode // "xhttp"')"
    label="onekey-$email"
    encoded_label="$(urlencode "$label")"

    case "$mode" in
        xhttp)
            local domain path encoded_path
            domain="$(state_get '.domain // ""')"
            path="$(state_get '.xhttp.path // "/xhttp"')"
            [ -n "$domain" ] || die "No domain configured for xhttp mode"
            encoded_path="$(urlencode "$path")"
            printf 'vless://%s@%s:443?encryption=none&type=xhttp&security=tls&sni=%s&host=%s&path=%s&mode=auto&alpn=h2&fp=chrome#%s\n' \
                "$uuid" "$domain" "$domain" "$domain" "$encoded_path" "$encoded_label"
            ;;
        xhttp-reality|xhttp-reality-self)
            local address port server_name public_key short_id path encoded_path encoded_spider
            address="$(state_get '.reality.address // .address // ""')"
            port="$(state_get '.reality.listen_port // 443')"
            server_name="$(state_get '.reality.server_name // ""')"
            public_key="$(state_get '.reality.public_key // ""')"
            short_id="$(state_get '(.reality.short_ids // []) | .[0] // ""')"
            path="$(state_get '.xhttp.path // "/xhttp"')"
            encoded_path="$(urlencode "$path")"
            encoded_spider="$(urlencode "$(state_get '.reality.spider_x // "/"')")"
            [ -n "$address" ] || die "No client address configured for xhttp-reality mode"
            [ -n "$server_name" ] || die "No REALITY serverName configured"
            [ -n "$public_key" ] || die "No REALITY public key configured"
            printf 'vless://%s@%s:%s?encryption=none&type=xhttp&security=reality&sni=%s&pbk=%s&sid=%s&spx=%s&path=%s&mode=auto&fp=chrome#%s\n' \
                "$uuid" "$address" "$port" "$server_name" "$public_key" "$short_id" "$encoded_spider" "$encoded_path" "$encoded_label"
            ;;
        reality|reality-vision|vision|vison|reality-self)
            local address port server_name public_key short_id encoded_spider
            address="$(state_get '.reality.address // .address // ""')"
            port="$(state_get '.reality.listen_port // 443')"
            server_name="$(state_get '.reality.server_name // ""')"
            public_key="$(state_get '.reality.public_key // ""')"
            short_id="$(state_get '(.reality.short_ids // []) | .[0] // ""')"
            encoded_spider="$(urlencode "$(state_get '.reality.spider_x // "/"')")"
            [ -n "$address" ] || die "No client address configured for reality mode"
            [ -n "$server_name" ] || die "No REALITY serverName configured"
            [ -n "$public_key" ] || die "No REALITY public key configured"
            printf 'vless://%s@%s:%s?encryption=none&type=raw&security=reality&sni=%s&pbk=%s&sid=%s&spx=%s&fp=chrome&flow=xtls-rprx-vision#%s\n' \
                "$uuid" "$address" "$port" "$server_name" "$public_key" "$short_id" "$encoded_spider" "$encoded_label"
            ;;
        *)
            die "Unsupported mode: $mode"
            ;;
    esac
}
