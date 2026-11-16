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
SETUP_SKIP_TARGET_CHECK=0

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

mode_number() {
    case "$1" in
        reality) printf '1\n' ;;
        reality-self) printf '2\n' ;;
        xhttp) printf '3\n' ;;
        xhttp-reality) printf '4\n' ;;
        xhttp-reality-self) printf '5\n' ;;
        *) printf '1\n' ;;
    esac
}

# Mode this server is actually running, empty when setup never completed.
# The default state file already says "xhttp", so a mode only counts once its
# identity (domain or serverName) is filled in and a config was rendered.
onekey_current_mode() {
    local mode identity
    [ -r "$STATE_FILE" ] && [ -s "$XRAY_CONFIG" ] || return 0
    jq -e . "$STATE_FILE" >/dev/null 2>&1 || return 0
    mode="$(jq -r '.mode // ""' "$STATE_FILE")"
    case "$mode" in
        xhttp) identity="$(jq -r '.domain // ""' "$STATE_FILE")" ;;
        *) identity="$(jq -r '.reality.server_name // ""' "$STATE_FILE")" ;;
    esac
    [ -n "$identity" ] || return 0
    normalize_mode "$mode" || true
}

# True when a prompt can actually reach a person. Anything else must fail
# loudly instead of looping on a question nobody can answer.
setup_can_ask() {
    [ "$ONEKEY_ASSUME_YES" != "1" ] && { have_tty || [ -t 0 ]; }
}

setup_mode_row() {
    local number="$1" name="$2" hint="$3" default="$4" color="$c_bold"
    [ "$number" != "$default" ] || color="$c_bold$c_green"
    printf '  %s%s)%s %-34s %s%s%s\n' "$color" "$number" "$c_reset" "$name" "$c_dim" "$hint" "$c_reset"
}

# setup_choose_mode [default-number] -> normalized mode
setup_choose_mode() {
    local default="${1:-1}" choice raw
    {
        printf '\n%sChoose a mode%s\n' "$c_bold" "$c_reset"
        printf '\n  %sNo domain needed%s\n' "$c_dim" "$c_reset"
        setup_mode_row 1 "REALITY + Vision" "recommended: simplest and fastest" "$default"
        setup_mode_row 4 "XHTTP + REALITY" "XHTTP transport instead of Vision" "$default"
        printf '\n  %sNeeds a domain whose DNS record points at this server%s\n' "$c_dim" "$c_reset"
        setup_mode_row 2 "REALITY self-steal + local Caddy" "camouflages as your own site" "$default"
        setup_mode_row 3 "XHTTP + Caddy (TLS)" "real certificate, can sit behind a CDN" "$default"
        setup_mode_row 5 "XHTTP + REALITY self-steal" "XHTTP, camouflaged as your own site" "$default"
        printf '\n'
    } >&2

    while true; do
        raw="$(ask "Mode" "$default")"
        if choice="$(normalize_mode "$raw")"; then
            printf '%s\n' "$choice"
            return 0
        fi
        setup_can_ask || die "Unknown mode: $raw"
        ui_bad "unknown mode '$raw'; enter a number from 1 to 5"
    done
}

# What to do when setup runs on a server that is already configured.
# Prints show | reconfigure | cancel.
setup_existing_choice() {
    local current="$1" users raw
    users="$(jq '.users | length' "$USERS_FILE")"
    {
        printf '\n%sThis server is already set up:%s %s, %s user(s)\n\n' \
            "$c_bold" "$c_reset" "$(mode_display_name "$current")" "$users"
        printf '  %s1)%s Show the share link and status   %snothing is changed%s\n' \
            "$c_bold$c_green" "$c_reset" "$c_dim" "$c_reset"
        printf '  %s2)%s Reconfigure                      %susers and REALITY keys are kept%s\n' \
            "$c_bold" "$c_reset" "$c_dim" "$c_reset"
        printf '  %s0)%s Cancel\n\n' "$c_bold" "$c_reset"
    } >&2
    while true; do
        raw="$(ask "Choose" "1")"
        case "$raw" in
            1) printf 'show\n'; return 0 ;;
            2) printf 'reconfigure\n'; return 0 ;;
            0 | q | quit) printf 'cancel\n'; return 0 ;;
        esac
        ui_bad "enter 1, 2 or 0"
    done
}

derive_acme_email() {
    local domain="${1#www.}"
    printf 'admin@%s\n' "$domain"
}

# Resolve the public address once and reuse it for both the share link and
# the DNS sanity check.
setup_resolve_address() {
    local kept="${1:-}" ip
    if [ -n "$SETUP_ADDRESS" ]; then
        validate_client_address "$SETUP_ADDRESS" || die "Invalid --address: $SETUP_ADDRESS"
        printf '%s\n' "$SETUP_ADDRESS"
        return 0
    fi
    if [ -n "$kept" ]; then
        ui_good "keeping share-link address: $kept"
        printf '%s\n' "$kept"
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

setup_prepare_target() {
    local input="$1" normalized host
    normalized="$(normalize_reality_target "$input")" ||
        die "Invalid REALITY target: $input (expected host[:port] or [IPv6]:port)"
    host="$(reality_target_host "$normalized")"
    if is_discouraged_reality_target "$host"; then
        ui_bad "$host is a discouraged REALITY target; prefer a verified site in this server's ASN"
    fi
    if [ "$SETUP_SKIP_TARGET_CHECK" != "1" ]; then
        ui_note "verifying REALITY target: $normalized"
        verify_reality_target "$normalized" ||
            die "REALITY target failed certificate/TLSv1.3/h2 validation: $normalized"
    fi
    printf '%s\n' "$normalized"
}

setup_resolve_target() {
    local kept="${1:-}" target
    if [ -n "$SETUP_TARGET" ]; then
        setup_prepare_target "$SETUP_TARGET"
        return 0
    fi
    # Re-running setup must not silently move existing clients to a new SNI.
    if [ -n "$kept" ]; then
        ui_good "keeping current REALITY target: $kept (pass --target to change it)"
        printf '%s\n' "$kept"
        return 0
    fi
    ui_note "probing REALITY target candidates..."
    if target="$(pick_reality_target)"; then
        printf '%s\n' "$target"
        return 0
    fi
    ui_bad "no candidate passed the certificate + TLSv1.3 + h2 check from this server"
    target="$(ask_required "REALITY target" "www.microsoft.com:443" "Pass --target explicitly.")"
    setup_prepare_target "$target"
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
    local port="$1" what="$2" owner
    port_in_use "$port" || return 0
    owner="$(port_owner "$port")"
    case "$owner" in
        # Our own services get restarted/reconfigured, so they free the port.
        xray | caddy) return 0 ;;
    esac
    ui_bad "port $port is already in use${owner:+ by $owner}; $what may fail to bind"
}

# setup_collect_domain <address> [default]
# Typed input is re-asked until it is a valid name; a DNS record that does not
# point here gets a choice instead of a warning that scrolls away.
setup_collect_domain() {
    local address="$1" default="${2:-}" domain="$SETUP_DOMAIN" explicit="$SETUP_DOMAIN"
    while true; do
        if [ -z "$domain" ]; then
            domain="$(ask_required "Domain pointed at this server" "$default" "Pass --domain explicitly.")"
        fi
        if [[ "$domain" == *@* ]] || ! validate_domain "$domain"; then
            if [ -n "$explicit" ] || ! setup_can_ask; then
                die "Invalid domain: $domain (expected a DNS name such as vpn.example.com)"
            fi
            ui_bad "'$domain' is not a domain name (example: vpn.example.com)"
            domain=""
            explicit=""
            continue
        fi
        if check_domain_points_here "$domain" "$address" || ! setup_can_ask; then
            break
        fi
        if confirm "Continue anyway? The certificate cannot be issued until DNS points here" "n"; then
            break
        fi
        ui_note "fix the DNS record, then press Enter to check again (or type another domain)"
        default="$domain"
        domain=""
        explicit=""
    done
    printf '%s\n' "$domain"
}

# setup_email_for <domain> [kept-email]
setup_email_for() {
    local domain="$1" kept="${2:-}" email
    if [ -n "$SETUP_EMAIL" ]; then
        email="$SETUP_EMAIL"
    elif [ -n "$kept" ]; then
        email="$kept"
    else
        email="$(derive_acme_email "$domain")"
        ui_note "ACME email: $email (override with --email)"
    fi
    validate_email "$email" || die "Invalid email: $email"
    printf '%s\n' "$email"
}

# The plan is collected before anything slow or destructive runs, shown, and
# confirmed; only then is Xray installed and the configuration written.
SETUP_REAPPLY=0
PLAN_MODE=""
PLAN_ADDRESS=""
PLAN_DOMAIN=""
PLAN_EMAIL=""
PLAN_TARGET=""
PLAN_SNI=""
PLAN_PATH=""
PLAN_PORT=""
PLAN_FALLBACK=""

# setup_kept <jq-expr>: the current value when re-applying the same mode, so a
# re-run keeps existing share links working. Empty otherwise.
setup_kept() {
    [ "$SETUP_REAPPLY" = "1" ] || return 0
    state_get "($1) // \"\""
}

setup_plan_port() {
    local value="$1" what="$2"
    validate_port "$value" || die "Invalid $what: $value"
    printf '%s\n' "$value"
}

setup_collect_plan() {
    local mode="$1" kept_target kept_domain
    PLAN_MODE="$mode"
    PLAN_ADDRESS="" PLAN_DOMAIN="" PLAN_EMAIL="" PLAN_TARGET="" PLAN_SNI=""
    PLAN_PATH="" PLAN_PORT="" PLAN_FALLBACK=""

    case "$mode" in
        reality | xhttp-reality)
            PLAN_ADDRESS="$(setup_resolve_address "$(setup_kept '.reality.address // .address')")"
            kept_target="$(setup_kept '.reality.target')"
            PLAN_TARGET="$(setup_resolve_target "$kept_target")"
            if [ -n "$SETUP_SNI" ]; then
                PLAN_SNI="$SETUP_SNI"
            elif [ -n "$kept_target" ] && [ "$PLAN_TARGET" = "$kept_target" ]; then
                PLAN_SNI="$(setup_kept '.reality.server_name')"
            fi
            PLAN_SNI="${PLAN_SNI:-$(reality_target_host "$PLAN_TARGET")}"
            validate_domain "$PLAN_SNI" || die "Invalid serverName: $PLAN_SNI"
            PLAN_PORT="${SETUP_PORT:-$(setup_kept '.reality.listen_port')}"
            PLAN_PORT="$(setup_plan_port "${PLAN_PORT:-443}" "Xray listen port")"
            setup_warn_port "$PLAN_PORT" "Xray"
            ;;
        xhttp)
            PLAN_ADDRESS="$(setup_resolve_address)"
            PLAN_PORT="${SETUP_PORT:-$(setup_kept '.xhttp.port')}"
            PLAN_PORT="$(setup_plan_port "${PLAN_PORT:-10000}" "local XHTTP port")"
            setup_warn_port "$PLAN_PORT" "Xray"
            setup_warn_port 80 "Caddy"
            setup_warn_port 443 "Caddy"
            ;;
        reality-self | xhttp-reality-self)
            PLAN_ADDRESS="$(setup_resolve_address "$(setup_kept '.reality.address // .address')")"
            PLAN_PORT="${SETUP_PORT:-$(setup_kept '.reality.listen_port')}"
            PLAN_PORT="$(setup_plan_port "${PLAN_PORT:-443}" "Xray listen port")"
            PLAN_FALLBACK="${SETUP_FALLBACK_PORT:-$(setup_kept '.reality_self.port')}"
            PLAN_FALLBACK="$(setup_plan_port "${PLAN_FALLBACK:-8443}" "local Caddy fallback port")"
            [ "$PLAN_PORT" != "$PLAN_FALLBACK" ] ||
                die "Xray listen port and local Caddy fallback port must be different"
            setup_warn_port "$PLAN_PORT" "Xray"
            setup_warn_port "$PLAN_FALLBACK" "Caddy"
            setup_warn_port 80 "Caddy"
            ;;
        *)
            die "Unsupported setup mode: $mode"
            ;;
    esac

    if mode_needs_domain "$mode"; then
        case "$mode" in
            xhttp) kept_domain="$(setup_kept '.domain')" ;;
            *) kept_domain="$(setup_kept '.reality.server_name // .domain')" ;;
        esac
        PLAN_DOMAIN="$(setup_collect_domain "$PLAN_ADDRESS" "$kept_domain")"
        if [ -n "$kept_domain" ] && [ "$PLAN_DOMAIN" = "$kept_domain" ]; then
            PLAN_EMAIL="$(setup_email_for "$PLAN_DOMAIN" "$(setup_kept '.acme_email')")"
        else
            PLAN_EMAIL="$(setup_email_for "$PLAN_DOMAIN")"
        fi
    fi

    case "$mode" in
        xhttp | xhttp-reality | xhttp-reality-self)
            PLAN_PATH="${SETUP_PATH:-$(setup_kept '.xhttp.path')}"
            PLAN_PATH="$(normalize_path "${PLAN_PATH:-$(generate_path)}")"
            ;;
    esac
}

setup_user_summary() {
    local count first
    count="$(jq '.users | length' "$USERS_FILE")"
    if [ -n "$SETUP_USER" ]; then
        if jq -e --arg email "$SETUP_USER" '.users[]? | select(.email == $email)' "$USERS_FILE" >/dev/null; then
            printf '%s (existing)\n' "$SETUP_USER"
        else
            printf '%s (new, random UUID)\n' "$SETUP_USER"
        fi
    elif [ "$count" -gt 0 ]; then
        first="$(jq -r '.users[0].email' "$USERS_FILE")"
        printf '%s (existing, %s user(s) kept)\n' "$first" "$count"
    else
        printf '%s (new, random UUID)\n' "$SETUP_DEFAULT_USER"
    fi
}

setup_show_plan() {
    printf '\n'
    ui_panel_top
    if [ "$SETUP_REAPPLY" = "1" ]; then
        ui_title "Ready to re-apply"
    else
        ui_title "Ready to set up"
    fi
    ui_panel_sep
    ui_row "Mode" "$(mode_display_name "$PLAN_MODE")"
    case "$PLAN_MODE" in
        reality | xhttp-reality)
            ui_row "Address" "$(format_host "$PLAN_ADDRESS"):$PLAN_PORT"
            ui_row "SNI" "$PLAN_SNI"
            ui_row "Target" "$PLAN_TARGET"
            ;;
        xhttp)
            ui_row "Address" "$PLAN_DOMAIN:443 (Caddy)"
            ui_row "Xray local" "127.0.0.1:$PLAN_PORT"
            ;;
        *)
            ui_row "Address" "$(format_host "$PLAN_ADDRESS"):$PLAN_PORT"
            ui_row "SNI" "$PLAN_DOMAIN"
            ui_row "Target" "local Caddy 127.0.0.1:$PLAN_FALLBACK"
            ;;
    esac
    if [ -n "$PLAN_PATH" ]; then
        ui_row "Path" "$PLAN_PATH"
    fi
    if [ -n "$PLAN_EMAIL" ]; then
        ui_row "ACME email" "$PLAN_EMAIL"
    fi
    ui_row "User" "$(setup_user_summary)"
    ui_panel_sep
    ui_row_plain "Next: install or update Xray, write the config, restart"
    case "$PLAN_MODE" in
        reality | xhttp-reality)
            ui_row_plain "Caddy is stopped if running: Xray takes port $PLAN_PORT"
            ;;
        *)
            ui_row_plain "Caddy is configured and requests a certificate for $PLAN_DOMAIN"
            ;;
    esac
    ui_row_plain "Any failure rolls back to the previous configuration"
    ui_panel_bottom
}

setup_apply_plan() {
    ui_step "Applying $(mode_display_name "$PLAN_MODE")"
    case "$PLAN_MODE" in
        reality)
            switch_reality_vision "$PLAN_SNI" "$PLAN_TARGET" "$PLAN_ADDRESS" "$PLAN_PORT"
            ;;
        xhttp-reality)
            switch_xhttp_reality "$PLAN_SNI" "$PLAN_TARGET" "$PLAN_ADDRESS" "$PLAN_PATH" "$PLAN_PORT"
            ;;
        xhttp)
            switch_xhttp "$PLAN_DOMAIN" "$PLAN_EMAIL" "$PLAN_PATH" "$PLAN_PORT"
            ;;
        reality-self)
            switch_reality_self "$PLAN_DOMAIN" "$PLAN_EMAIL" "$PLAN_ADDRESS" "$PLAN_PORT" "$PLAN_FALLBACK"
            ;;
        xhttp-reality-self)
            switch_xhttp_reality_self "$PLAN_DOMAIN" "$PLAN_EMAIL" "$PLAN_ADDRESS" "$PLAN_PATH" "$PLAN_PORT" "$PLAN_FALLBACK"
            ;;
        *)
            die "Unsupported setup mode: $PLAN_MODE"
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
    elif systemctl cat "$unit" >/dev/null 2>&1; then
        # Not `list-unit-files | grep -q`: grep exits early and pipefail
        # turns systemctl's SIGPIPE into a false "not installed".
        if systemctl is-enabled --quiet "$unit" 2>/dev/null; then
            printf 'stopped\n'
        else
            printf 'stopped, disabled\n'
        fi
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
                require_option_value "$1" "${2:-}"
                SETUP_MODE="${2:-}"
                shift 2
                ;;
            --domain)
                require_option_value "$1" "${2:-}"
                SETUP_DOMAIN="${2:-}"
                shift 2
                ;;
            --email | --acme-email)
                require_option_value "$1" "${2:-}"
                SETUP_EMAIL="${2:-}"
                shift 2
                ;;
            --address)
                require_option_value "$1" "${2:-}"
                SETUP_ADDRESS="${2:-}"
                shift 2
                ;;
            --target | --dest)
                require_option_value "$1" "${2:-}"
                SETUP_TARGET="${2:-}"
                shift 2
                ;;
            --server-name | --sni)
                require_option_value "$1" "${2:-}"
                SETUP_SNI="${2:-}"
                shift 2
                ;;
            --path)
                require_option_value "$1" "${2:-}"
                SETUP_PATH="${2:-}"
                shift 2
                ;;
            --port)
                require_option_value "$1" "${2:-}"
                SETUP_PORT="${2:-}"
                shift 2
                ;;
            --fallback-port | --local-port | --https-port)
                require_option_value "$1" "${2:-}"
                SETUP_FALLBACK_PORT="${2:-}"
                shift 2
                ;;
            --user)
                require_option_value "$1" "${2:-}"
                SETUP_USER="${2:-}"
                shift 2
                ;;
            --skip-target-check)
                SETUP_SKIP_TARGET_CHECK=1
                shift
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
    init_state_files

    local current mode existing_user
    current="$(onekey_current_mode)"
    existing_user="$(jq -r '.users[0].email // ""' "$USERS_FILE")"

    if [ -n "$SETUP_MODE" ]; then
        mode="$(normalize_mode "$SETUP_MODE")" || die "Unknown mode: $SETUP_MODE"
    elif [ -n "$current" ] && [ "$ONEKEY_ASSUME_YES" = "1" ]; then
        # Unattended re-runs keep the running mode instead of silently
        # switching an existing server to the first-install default.
        mode="$current"
        ui_note "already set up; re-applying $(mode_display_name "$current") (pass --mode to switch)"
    elif [ "$ONEKEY_ASSUME_YES" = "1" ]; then
        mode="reality"
        ui_note "no --mode given, defaulting to REALITY + Vision"
    elif [ -n "$current" ] && [ -n "$existing_user" ]; then
        case "$(setup_existing_choice "$current")" in
            show)
                onekey_status_panel "$existing_user"
                ui_link_block "$(build_link "$existing_user")"
                return 0
                ;;
            cancel)
                ui_note "cancelled; nothing was changed"
                return 0
                ;;
        esac
        mode="$(setup_choose_mode "$(mode_number "$current")")"
    else
        mode="$(setup_choose_mode 1)"
    fi
    if [ -n "$current" ] && [ "$mode" = "$current" ]; then
        SETUP_REAPPLY=1
    fi

    ui_step "Preparing $(mode_display_name "$mode")"
    setup_collect_plan "$mode"
    setup_show_plan
    if ! confirm "Apply this configuration?" "y"; then
        ui_note "cancelled; no configuration was changed"
        return 0
    fi

    ui_step "Installing Xray"
    install_xray_if_needed
    install_cli_shortcut
    transaction_begin

    local user_email
    ui_step "Preparing user"
    user_email="$(setup_ensure_user)"

    setup_apply_plan
    transaction_commit

    onekey_status_panel "$user_email"
    ui_link_block "$(build_link "$user_email")"

    printf '\n%sNext%s %s(%s ...)%s\n' "$c_bold" "$c_reset" "$c_dim" "$ONEKEY_ENTRY" "$c_reset"
    printf '  %-28s %s# add another user%s\n' "user add bob@example.com" "$c_dim" "$c_reset"
    printf '  %-28s %s# show its link + QR%s\n' "link bob@example.com" "$c_dim" "$c_reset"
    printf '  %-28s %s# per-user traffic%s\n' "traffic all" "$c_dim" "$c_reset"
    printf '  %-28s %s# interactive menu%s\n' "(no arguments)" "$c_dim" "$c_reset"
    printf '\n'
}
