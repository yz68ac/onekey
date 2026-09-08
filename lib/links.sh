#!/usr/bin/env bash

LINK_DRIFT_WARNED=0

link_warn_reality_drift() {
    local mode
    [ "$LINK_DRIFT_WARNED" -eq 0 ] || return 0
    mode="$(state_get '.mode // "xhttp"')"
    case "$mode" in
        reality|reality-vision|vision|vison|reality-self|xhttp-reality|xhttp-reality-self) ;;
        *) return 0 ;;
    esac
    [ -f "$XRAY_CONFIG" ] || return 0
    if ! reality_config_matches_state; then
        warn "OneKey state differs from the active Xray REALITY config; this share link may be invalid."
        warn "$(reality_config_drift_detail)"
        warn "Use '$ONEKEY_ENTRY switch ...' or the interactive reconfigure option instead of editing config.json directly."
    fi
    LINK_DRIFT_WARNED=1
}

# build_link <email> -> the raw vless:// URL on stdout, nothing else.
build_link() {
    local email="$1" mode uuid label encoded_label

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
        xhttp-reality | xhttp-reality-self)
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
                "$uuid" "$(format_host "$address")" "$port" "$server_name" "$public_key" "$short_id" "$encoded_spider" "$encoded_path" "$encoded_label"
            ;;
        reality | reality-vision | vision | vison | reality-self)
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
                "$uuid" "$(format_host "$address")" "$port" "$server_name" "$public_key" "$short_id" "$encoded_spider" "$encoded_label"
            ;;
        *)
            die "Unsupported mode: $mode"
            ;;
    esac
}

# link_show [email] [--no-qr] [--raw]
#   --raw    print only the URL, for piping into other tools
#   --no-qr  print the summary and URL but skip the QR block
link_show() {
    local email="" show_qr=1 raw=0 arg uuid link

    for arg in "$@"; do
        case "$arg" in
            --no-qr) show_qr=0 ;;
            --raw | --plain) raw=1 ;;
            --qr) show_qr=1 ;;
            "") ;;
            *) email="$arg" ;;
        esac
    done

    init_state_files
    if [ -z "$email" ]; then
        email="$(single_user_email)"
    fi
    [ -n "$email" ] || die "Usage: $ONEKEY_ENTRY link email"

    link_warn_reality_drift
    link="$(build_link "$email")"

    if [ "$raw" -eq 1 ]; then
        printf '%s\n' "$link"
        return 0
    fi

    uuid="$(user_uuid_by_email "$email")"
    printf '\n'
    ui_panel_top
    ui_row "User" "$email"
    ui_row "UUID" "$uuid"
    ui_row "Mode" "$(mode_display_name "$(state_get '.mode // "xhttp"')")"
    ui_panel_bottom
    ui_link_block "$link" "$show_qr"
}

# Every user in one go, handy after adding a batch.
link_show_all() {
    local email first=1
    init_state_files
    while IFS= read -r email; do
        [ -n "$email" ] || continue
        [ "$first" -eq 1 ] || printf '\n'
        first=0
        link_show "$email" "$@"
    done < <(jq -r '.users[]?.email' "$USERS_FILE")
    [ "$first" -eq 0 ] || printf 'No users configured.\n'
}
