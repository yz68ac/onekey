#!/usr/bin/env bash
# The one-key path: dependencies, Xray, a mode, a user and a share link
# in a single run, asking as few questions as possible.

SETUP_MODE=""
SETUP_DOMAIN=""
SETUP_EMAIL=""
SETUP_ADDRESS=""
SETUP_TARGET=""
SETUP_SNI=""
SETUP_PATH=""
SETUP_PORT=""
SETUP_FALLBACK_PORT=""
SETUP_USER=""

SETUP_DEFAULT_USER="default@onekey.local"
ONEKEY_CLI_LINK="${ONEKEY_CLI_LINK:-/usr/local/bin/xrayctl}"

# Drop a `xrayctl` symlink on PATH so day-two commands are short. Never
# clobbers a real file that is already sitting there.
install_cli_shortcut() {
    local target="$ONEKEY_ROOT/xrayctl.sh" dir
    dir="$(dirname "$ONEKEY_CLI_LINK")"
    [ -d "$dir" ] || return 0

    if [ -e "$ONEKEY_CLI_LINK" ] && [ ! -L "$ONEKEY_CLI_LINK" ]; then
        return 0
    fi
    if ln -sfn "$target" "$ONEKEY_CLI_LINK" 2>/dev/null; then
        chmod +x "$target" 2>/dev/null || true
        ONEKEY_ENTRY="xrayctl"
        ui_good "shortcut ready: run 'xrayctl' from anywhere"
    fi
}

mode_display_name() {
    case "$1" in
        xhttp) printf 'XHTTP + Caddy (TLS)\n' ;;
        reality | reality-vision | vision | vison) printf 'REALITY + Vision\n' ;;
        reality-self) printf 'REALITY self-steal + local Caddy\n' ;;
        xhttp-reality) printf 'XHTTP + REALITY\n' ;;
        xhttp-reality-self) printf 'XHTTP + REALITY self-steal + local Caddy\n' ;;
        *) printf '%s\n' "$1" ;;
    esac
}

normalize_mode() {
    case "$1" in
        1 | reality | reality-vision | vision | vison) printf 'reality\n' ;;
        2 | reality-self | self | self-reality | reality_self) printf 'reality-self\n' ;;
        3 | xhttp | caddy | tls) printf 'xhttp\n' ;;
        4 | xhttp-reality | xreality | xhttp_reality) printf 'xhttp-reality\n' ;;
        5 | xhttp-reality-self | xreality-self | xhttp-self) printf 'xhttp-reality-self\n' ;;
        *) return 1 ;;
    esac
}

mode_needs_domain() {
    case "$1" in
        xhttp | reality-self | xhttp-reality-self) return 0 ;;
        *) return 1 ;;
    esac
}

setup_choose_mode() {
    local choice raw
    {
        printf '\n%sChoose a mode%s\n\n' "$c_bold" "$c_reset"
        printf '  %s1)%s REALITY + Vision                      %sno domain, no certificate%s\n' \
            "$c_bold$c_green" "$c_reset" "$c_dim" "$c_reset"
        printf '  %s2)%s REALITY self-steal + local Caddy      %sneeds a domain pointed here%s\n' \
            "$c_bold" "$c_reset" "$c_dim" "$c_reset"
        printf '  %s3)%s XHTTP + Caddy (TLS)                   %sneeds a domain pointed here%s\n' \
            "$c_bold" "$c_reset" "$c_dim" "$c_reset"
        printf '  %s4)%s XHTTP + REALITY                       %sno domain, no certificate%s\n' \
            "$c_bold" "$c_reset" "$c_dim" "$c_reset"
        printf '  %s5)%s XHTTP + REALITY self-steal            %sneeds a domain pointed here%s\n\n' \
            "$c_bold" "$c_reset" "$c_dim" "$c_reset"
    } >&2

    raw="$(ask "Mode" "1")"
    if ! choice="$(normalize_mode "$raw")"; then
        die "Unknown mode: $raw"
    fi
    printf '%s\n' "$choice"
}

derive_acme_email() {
    local domain="${1#www.}"
    printf 'admin@%s\n' "$domain"
}

# Resolve the public address once and reuse it for both the share link and
# the DNS sanity check.
setup_resolve_address() {
    local ip
    if [ -n "$SETUP_ADDRESS" ]; then
        printf '%s\n' "$SETUP_ADDRESS"
        return 0
    fi
    ui_note "detecting public address..."
    if ip="$(detect_public_ip)"; then
        ui_good "public address: $ip"
        printf '%s\n' "$ip"
        return 0
    fi
    ui_bad "could not detect the public address automatically"
    ask_required "Server address for the share link" "" "Pass --address explicitly."
}

setup_resolve_target() {
    local host
    if [ -n "$SETUP_TARGET" ]; then
        printf '%s\n' "$SETUP_TARGET"
        return 0
    fi
    ui_note "probing REALITY target candidates..."
    if host="$(pick_reality_target)"; then
        printf '%s\n' "$host"
        return 0
    fi
    ui_bad "no candidate passed the TLSv1.3 + h2 check from this server"
    ask_required "REALITY target domain" "www.microsoft.com" "Pass --target explicitly."
}

setup_ensure_user() {
    local email="${SETUP_USER:-$SETUP_DEFAULT_USER}" count
    init_state_files
    count="$(jq '.users | length' "$USERS_FILE")"

    if [ -n "$SETUP_USER" ]; then
        if jq -e --arg email "$email" '.users[]? | select(.email == $email)' "$USERS_FILE" >/dev/null; then
            ui_good "user already exists: $email"
        else
            user_add "$email" "" >/dev/null
            ui_good "created user: $email"
        fi
        printf '%s\n' "$email"
        return 0
    fi

    if [ "$count" -gt 0 ]; then
        email="$(jq -r '.users[0].email' "$USERS_FILE")"
        ui_good "reusing existing user: $email"
        printf '%s\n' "$email"
        return 0
    fi

    user_add "$email" "" >/dev/null
    ui_good "created user: $email"
    printf '%s\n' "$email"
}

setup_warn_port() {
    local port="$1" what="$2"
    if port_in_use "$port"; then
        ui_bad "port $port is already in use; $what may fail to bind"
    fi
}

setup_collect_domain() {
    local address="$1" domain
    if [ -n "$SETUP_DOMAIN" ]; then
        domain="$SETUP_DOMAIN"
    else
        domain="$(ask_required "Domain pointed at this server" "" "Pass --domain explicitly.")"
    fi
    case "$domain" in
        *@*) die "--domain must be a DNS name, not an email address" ;;
    esac
    validate_domain "$domain" || die "Invalid domain: $domain"
    check_domain_points_here "$domain" "$address" || true
    printf '%s\n' "$domain"
}

setup_email_for() {
    local domain="$1" email
    if [ -n "$SETUP_EMAIL" ]; then
        email="$SETUP_EMAIL"
    else
        email="$(derive_acme_email "$domain")"
        ui_note "ACME email: $email (override with --email)"
    fi
    validate_email "$email" || die "Invalid email: $email"
    printf '%s\n' "$email"
}

setup_run_mode() {
    local mode="$1" address domain email target path port fallback

    case "$mode" in
        reality)
            address="$(setup_resolve_address)"
            target="$(setup_resolve_target)"
            port="${SETUP_PORT:-443}"
            setup_warn_port "$port" "Xray"
            ui_step "Applying REALITY + Vision"
            switch_reality_vision "${SETUP_SNI:-$target}" "$target:443" "$address" "$port"
            ;;
        xhttp-reality)
            address="$(setup_resolve_address)"
            target="$(setup_resolve_target)"
            path="${SETUP_PATH:-$(generate_path)}"
            port="${SETUP_PORT:-443}"
            setup_warn_port "$port" "Xray"
            ui_step "Applying XHTTP + REALITY"
            switch_xhttp_reality "${SETUP_SNI:-$target}" "$target:443" "$address" "$path" "$port"
            ;;
        xhttp)
            address="$(setup_resolve_address)"
            domain="$(setup_collect_domain "$address")"
            email="$(setup_email_for "$domain")"
            path="${SETUP_PATH:-$(generate_path)}"
            port="${SETUP_PORT:-10000}"
            setup_warn_port 443 "Caddy"
            ui_step "Applying XHTTP + Caddy"
            switch_xhttp "$domain" "$email" "$path" "$port"
            ;;
        reality-self)
            address="$(setup_resolve_address)"
            domain="$(setup_collect_domain "$address")"
            email="$(setup_email_for "$domain")"
            port="${SETUP_PORT:-443}"
            fallback="${SETUP_FALLBACK_PORT:-8443}"
            setup_warn_port "$port" "Xray"
            ui_step "Applying REALITY self-steal + local Caddy"
            switch_reality_self "$domain" "$email" "$address" "$port" "$fallback"
            ;;
        xhttp-reality-self)
            address="$(setup_resolve_address)"
            domain="$(setup_collect_domain "$address")"
            email="$(setup_email_for "$domain")"
            path="${SETUP_PATH:-$(generate_path)}"
            port="${SETUP_PORT:-443}"
            fallback="${SETUP_FALLBACK_PORT:-8443}"
            setup_warn_port "$port" "Xray"
            ui_step "Applying XHTTP + REALITY self-steal + local Caddy"
            switch_xhttp_reality_self "$domain" "$email" "$address" "$path" "$port" "$fallback"
            ;;
        *)
            die "Unsupported setup mode: $mode"
            ;;
    esac
}

service_state() {
    local unit="$1"
    have_cmd systemctl || {
        printf 'unknown\n'
        return 0
    }
    if systemctl is-active --quiet "$unit" 2>/dev/null; then
        printf 'running\n'
    elif systemctl list-unit-files 2>/dev/null | grep -q "^${unit}\.service"; then
        printf 'stopped\n'
    else
        printf 'not installed\n'
    fi
}

# onekey_status_panel [email]
# With an email, the panel also carries that user's credentials so the
# one-key run does not need a second box.
onekey_status_panel() {
    local focus_email="${1:-}"
    init_state_files
    local mode users address port sni path domain
    mode="$(state_get '.mode // "xhttp"')"
    users="$(jq '.users | length' "$USERS_FILE")"

    printf '\n'
    ui_panel_top
    ui_title "OneKey Xray is ready"
    ui_panel_sep
    ui_row "Mode" "$(mode_display_name "$mode")"

    case "$mode" in
        xhttp)
            domain="$(state_get '.domain // ""')"
            path="$(state_get '.xhttp.path // ""')"
            port="$(state_get '.xhttp.port // 10000')"
            ui_row "Domain" "$domain"
            ui_row "Client port" "443 (Caddy)"
            ui_row "Xray local" "127.0.0.1:$port"
            ui_row "Path" "$path"
            ;;
        xhttp-reality | xhttp-reality-self)
            address="$(state_get '.reality.address // .address // ""')"
            port="$(state_get '.reality.listen_port // 443')"
            sni="$(state_get '.reality.server_name // ""')"
            path="$(state_get '.xhttp.path // ""')"
            ui_row "Address" "$(format_host "$address"):$port"
            ui_row "SNI" "$sni"
            ui_row "Target" "$(state_get '.reality.target // ""')"
            ui_row "Path" "$path"
            ;;
        *)
            address="$(state_get '.reality.address // .address // ""')"
            port="$(state_get '.reality.listen_port // 443')"
            sni="$(state_get '.reality.server_name // ""')"
            ui_row "Address" "$(format_host "$address"):$port"
            ui_row "SNI" "$sni"
            ui_row "Target" "$(state_get '.reality.target // ""')"
            ;;
    esac

    ui_row "Users" "$users"
    ui_row "Xray" "$(service_state "$XRAY_SERVICE")"
    ui_row "Caddy" "$(service_state "$CADDY_SERVICE")"

    if [ -n "$focus_email" ]; then
        ui_panel_sep
        ui_row "User" "$focus_email"
        ui_row "UUID" "$(user_uuid_by_email "$focus_email")"
    fi
    ui_panel_bottom
}

setup_parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --mode)
                SETUP_MODE="${2:-}"
                shift 2
                ;;
            --domain)
                SETUP_DOMAIN="${2:-}"
                shift 2
                ;;
            --email | --acme-email)
                SETUP_EMAIL="${2:-}"
                shift 2
                ;;
            --address)
                SETUP_ADDRESS="${2:-}"
                shift 2
                ;;
            --target | --dest)
                SETUP_TARGET="${2:-}"
                shift 2
                ;;
            --server-name | --sni)
                SETUP_SNI="${2:-}"
                shift 2
                ;;
            --path)
                SETUP_PATH="${2:-}"
                shift 2
                ;;
            --port)
                SETUP_PORT="${2:-}"
                shift 2
                ;;
            --fallback-port | --local-port | --https-port)
                SETUP_FALLBACK_PORT="${2:-}"
                shift 2
                ;;
            --user)
                SETUP_USER="${2:-}"
                shift 2
                ;;
            -y | --yes | --non-interactive)
                ONEKEY_ASSUME_YES=1
                shift
                ;;
            -h | --help)
                usage
                exit 0
                ;;
            *)
                die "Unknown setup option: $1"
                ;;
        esac
    done
}

onekey_setup() {
    require_root
    setup_parse_args "$@"

    ui_banner
    ui_step "Checking dependencies"
    ensure_base_deps

    ui_step "Installing Xray"
    install_xray_if_needed
    install_cli_shortcut
    init_state_files

    local mode
    if [ -n "$SETUP_MODE" ]; then
        mode="$(normalize_mode "$SETUP_MODE")" || die "Unknown mode: $SETUP_MODE"
    elif [ "$ONEKEY_ASSUME_YES" = "1" ]; then
        mode="reality"
        ui_note "no --mode given, defaulting to REALITY + Vision"
    else
        mode="$(setup_choose_mode)"
    fi

    local user_email
    ui_step "Preparing user"
    user_email="$(setup_ensure_user)"

    setup_run_mode "$mode"

    onekey_status_panel "$user_email"
    ui_link_block "$(build_link "$user_email")"

    printf '\n%sNext%s %s(%s ...)%s\n' "$c_bold" "$c_reset" "$c_dim" "$ONEKEY_ENTRY" "$c_reset"
    printf '  %-28s %s# add another user%s\n' "user add bob@example.com" "$c_dim" "$c_reset"
    printf '  %-28s %s# show its link + QR%s\n' "link bob@example.com" "$c_dim" "$c_reset"
    printf '  %-28s %s# per-user traffic%s\n' "traffic all" "$c_dim" "$c_reset"
    printf '  %-28s %s# interactive menu%s\n' "(no arguments)" "$c_dim" "$c_reset"
    printf '\n'
}
