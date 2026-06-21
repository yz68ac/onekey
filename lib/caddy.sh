#!/usr/bin/env bash

caddy_apply_from_state() {
    init_state_files
    local mode domain acme_email path port site_root
    mode="$(state_get '.mode // "xhttp"')"
    [ "$mode" = "xhttp" ] || die "Caddy is only used by xhttp mode"

    domain="$(state_get '.domain // ""')"
    acme_email="$(state_get '.acme_email // ""')"
    path="$(state_get '.xhttp.path // "/xhttp"')"
    port="$(state_get '.xhttp.port // 10000')"
    site_root="$(state_get '.caddy.site_root // "/usr/share/caddy"')"

    [ -x "$ONEKEY_ROOT/caddy-onekey.sh" ] || chmod +x "$ONEKEY_ROOT/caddy-onekey.sh" 2>/dev/null || true
    bash "$ONEKEY_ROOT/caddy-onekey.sh" \
        --domain "$domain" \
        --email "$acme_email" \
        --xhttp-port "$port" \
        --path "$path" \
        --site-root "$site_root"
}
