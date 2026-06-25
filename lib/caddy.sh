#!/usr/bin/env bash

caddy_apply_from_state() {
    init_state_files
    local mode domain acme_email path port site_root
    mode="$(state_get '.mode // "xhttp"')"
    case "$mode" in
        xhttp) ;;
        reality-self|xhttp-reality-self)
            caddy_apply_reality_self_from_state
            return 0
            ;;
        *)
            die "Caddy is only managed automatically by xhttp and reality-self modes"
            ;;
    esac

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

caddy_apply_reality_self_from_state() {
    init_state_files
    local mode domain acme_email listen port site_root
    mode="$(state_get '.mode // "xhttp"')"
    case "$mode" in
        reality-self|xhttp-reality-self) ;;
        *) die "Current mode is not a self-steal mode" ;;
    esac

    domain="$(state_get '.domain // ""')"
    acme_email="$(state_get '.acme_email // ""')"
    listen="$(state_get '.reality_self.listen // "127.0.0.1"')"
    port="$(state_get '.reality_self.port // 8443')"
    site_root="$(state_get '.caddy.site_root // "/usr/share/caddy"')"

    [ -x "$ONEKEY_ROOT/caddy-onekey.sh" ] || chmod +x "$ONEKEY_ROOT/caddy-onekey.sh" 2>/dev/null || true
    bash "$ONEKEY_ROOT/caddy-onekey.sh" \
        --mode reality-self \
        --domain "$domain" \
        --email "$acme_email" \
        --fallback-listen "$listen" \
        --fallback-port "$port" \
        --site-root "$site_root"
}
