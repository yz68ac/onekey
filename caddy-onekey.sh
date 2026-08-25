#!/usr/bin/env bash
set -Eeuo pipefail
umask 022

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin:/snap/bin
export PATH

CADDYFILE="${CADDYFILE:-/etc/caddy/Caddyfile}"
CADDY_SERVICE="${CADDY_SERVICE:-caddy}"
SITE_ROOT="${SITE_ROOT:-/usr/share/caddy}"
CADDY_ROLLBACK_FILE=""
CADDYFILE_EXISTED=0

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

info() {
    printf '[INFO] %s\n' "$*"
}

ok() {
    printf '[OK] %s\n' "$*"
}

warn() {
    printf '[WARN] %s\n' "$*" >&2
}

have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

require_root() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        die "Please run as root"
    fi
}

require_option_value() {
    local option="$1" value="${2:-}"
    [ -n "$value" ] && [[ "$value" != -* ]] || die "$option requires a value"
}

validate_domain() {
    local domain="$1"
    [[ "$domain" =~ ^([A-Za-z0-9]([-A-Za-z0-9]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,}$ ]]
}

validate_email() {
    local email="$1"
    [[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}

validate_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

validate_local_listen() {
    local listen="$1"
    case "$listen" in
        127.0.0.1|localhost|::1) return 0 ;;
        *) return 1 ;;
    esac
}

validate_xhttp_path() {
    local path="$1"
    [ -n "$path" ] || return 1
    [ "${#path}" -le 256 ] || return 1
    [[ "$path" =~ ^/[A-Za-z0-9._~!%+,:=@/-]+$ ]]
}

validate_filesystem_path() {
    local path="$1"
    [ -n "$path" ] || return 1
    [[ "$path" == /* ]] || return 1
    [[ "$path" =~ ^/[A-Za-z0-9._~%+,:=@/-]+$ ]]
}

normalize_path() {
    local path="$1"
    [ -n "$path" ] || die "Path cannot be empty"
    case "$path" in
        /*) ;;
        *) path="/$path" ;;
    esac
    path="${path%/}"
    [ -n "$path" ] || path="/xhttp"
    validate_xhttp_path "$path" ||
        die "Invalid XHTTP path; use URL-safe characters only"
    printf '%s\n' "$path"
}

detect_debian_ubuntu() {
    [ -r /etc/os-release ] || die "Cannot detect OS"
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}" in
        debian|ubuntu) return 0 ;;
    esac
    case "${ID_LIKE:-}" in
        *debian*) return 0 ;;
    esac
    die "This Caddy installer supports Debian/Ubuntu"
}

install_caddy() {
    detect_debian_ubuntu
    if have_cmd caddy; then
        if ! have_cmd systemctl || systemctl cat "$CADDY_SERVICE" >/dev/null 2>&1; then
            info "Caddy already installed: $(caddy version 2>/dev/null || true)"
            return 0
        fi
        warn "Caddy binary exists but the $CADDY_SERVICE systemd unit is missing; installing the official package"
    fi

    info "Installing Caddy from the official stable repository"
    # xrayctl may have refreshed the index moments ago; the refresh after the
    # Caddy repo is added below is the one that actually matters.
    if [ "${ONEKEY_PKG_INDEX_FRESH:-0}" != "1" ]; then
        apt-get update
    fi
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        debian-keyring debian-archive-keyring apt-transport-https \
        curl gpg

    mkdir -p /usr/share/keyrings /etc/apt/sources.list.d
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' |
        gpg --yes --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
        | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
    chmod o+r /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    chmod o+r /etc/apt/sources.list.d/caddy-stable.list

    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y caddy
    if ! id caddy >/dev/null 2>&1; then
        warn "Caddy package did not expose a caddy system user; keeping package defaults"
    fi
}

install_generated_caddyfile() {
    local tmp="$1"
    local validate_output
    if ! validate_output="$(caddy validate --config "$tmp" --adapter caddyfile 2>&1)"; then
        printf '%s\n' "$validate_output" >&2
        rm -f "$tmp"
        die "Generated Caddyfile validation failed"
    fi

    CADDYFILE_EXISTED=0
    CADDY_ROLLBACK_FILE=""
    if [ -f "$CADDYFILE" ]; then
        CADDYFILE_EXISTED=1
        CADDY_ROLLBACK_FILE="$CADDYFILE.$(date '+%Y%m%d-%H%M%S')-$$.bak"
        cp -a "$CADDYFILE" "$CADDY_ROLLBACK_FILE"
        if ! grep -q '^# Managed by OneKey Xray' "$CADDYFILE"; then
            warn "Existing unmanaged Caddyfile will be replaced; backup: $CADDY_ROLLBACK_FILE"
        fi
    fi
    install -m 0644 "$tmp" "$CADDYFILE"
    rm -f "$tmp"
}

restore_generated_caddyfile() {
    if [ "$CADDYFILE_EXISTED" -eq 1 ] && [ -f "$CADDY_ROLLBACK_FILE" ]; then
        cp -a "$CADDY_ROLLBACK_FILE" "$CADDYFILE"
    else
        rm -f "$CADDYFILE"
    fi
}

write_xhttp_caddyfile() {
    local domain="$1" email="$2" xhttp_port="$3" xhttp_path="$4" site_root="$5"
    local tmp
    tmp="$(mktemp)"
    mkdir -p "$(dirname "$CADDYFILE")" "$site_root"

    cat > "$tmp" <<EOF
# Managed by OneKey Xray. Manual changes may be replaced.
{
    email $email
}

$domain {
    encode zstd gzip

    @xray_xhttp path $xhttp_path $xhttp_path/*
    reverse_proxy @xray_xhttp 127.0.0.1:$xhttp_port {
        transport http {
            versions h2c 2
        }
        flush_interval -1
        header_up Host {host}
    }

    root * $site_root
    file_server

    respond /health "ok" 200
}
EOF

    install_generated_caddyfile "$tmp"
}

write_reality_self_caddyfile() {
    local domain="$1" email="$2" fallback_listen="$3" fallback_port="$4" site_root="$5"
    local tmp
    tmp="$(mktemp)"
    mkdir -p "$(dirname "$CADDYFILE")" "$site_root"

    cat > "$tmp" <<EOF
# Managed by OneKey Xray. Manual changes may be replaced.
{
    email $email
}

http://$domain {
    bind 0.0.0.0
    encode zstd gzip

    root * $site_root
    file_server

    respond /health "ok" 200
}

https://$domain:$fallback_port {
    bind $fallback_listen
    tls $email
    encode zstd gzip

    root * $site_root
    file_server

    respond /health "ok" 200
}
EOF

    install_generated_caddyfile "$tmp"
}

reload_caddy() {
    if have_cmd systemctl; then
        systemctl enable "$CADDY_SERVICE" >/dev/null 2>&1 || true
        if systemctl is-active --quiet "$CADDY_SERVICE"; then
            systemctl reload "$CADDY_SERVICE"
        else
            systemctl start "$CADDY_SERVICE"
        fi
    else
        caddy reload --config "$CADDYFILE" --adapter caddyfile
    fi
}

usage() {
    cat <<'EOF'
Usage:
  ./caddy-onekey.sh --domain example.com --email admin@example.com --xhttp-port 10000 --path /secret
  ./caddy-onekey.sh --mode reality-self --domain example.com --email admin@example.com [--fallback-port 8443]

Options:
  --mode          xhttp or reality-self, default xhttp
  --domain        Domain served by Caddy
  --email         ACME account email
  --xhttp-port    Local Xray XHTTP port
  --path          XHTTP path
  --fallback-listen
                  Local HTTPS listen address for reality-self, default 127.0.0.1
  --fallback-port Local HTTPS listen port for reality-self, default 8443
  --site-root     Static site root, default /usr/share/caddy
  --install-only  Only install Caddy
EOF
}

main() {
    local mode="xhttp" domain="" email="" xhttp_port="" xhttp_path="" site_root="$SITE_ROOT" install_only=0
    local fallback_listen="127.0.0.1" fallback_port="8443"

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --mode)
                require_option_value "$1" "${2:-}"
                mode="${2:-}"
                shift 2
                ;;
            --reality-self)
                mode="reality-self"
                shift
                ;;
            --domain)
                require_option_value "$1" "${2:-}"
                domain="${2:-}"
                shift 2
                ;;
            --email)
                require_option_value "$1" "${2:-}"
                email="${2:-}"
                shift 2
                ;;
            --xhttp-port|--port)
                require_option_value "$1" "${2:-}"
                xhttp_port="${2:-}"
                shift 2
                ;;
            --path)
                require_option_value "$1" "${2:-}"
                xhttp_path="${2:-}"
                shift 2
                ;;
            --fallback-listen|--listen)
                require_option_value "$1" "${2:-}"
                fallback_listen="${2:-}"
                shift 2
                ;;
            --fallback-port|--local-port|--https-port)
                require_option_value "$1" "${2:-}"
                fallback_port="${2:-}"
                shift 2
                ;;
            --site-root)
                require_option_value "$1" "${2:-}"
                site_root="${2:-}"
                shift 2
                ;;
            --install-only)
                install_only=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
    done

    require_root
    install_caddy
    [ "$install_only" -eq 0 ] || exit 0

    [ -n "$domain" ] || die "--domain is required"
    [ -n "$email" ] || die "--email is required"

    validate_domain "$domain" || die "Invalid domain: $domain"
    validate_email "$email" || die "Invalid email: $email"
    validate_filesystem_path "$site_root" || die "Invalid --site-root path: $site_root"

    case "$mode" in
        xhttp)
            [ -n "$xhttp_port" ] || die "--xhttp-port is required"
            [ -n "$xhttp_path" ] || die "--path is required"
            validate_port "$xhttp_port" || die "Invalid port: $xhttp_port"
            xhttp_path="$(normalize_path "$xhttp_path")"
            write_xhttp_caddyfile "$domain" "$email" "$xhttp_port" "$xhttp_path" "$site_root"
            ;;
        reality-self|self|reality_self)
            validate_local_listen "$fallback_listen" || die "--fallback-listen must be 127.0.0.1, localhost, or ::1"
            validate_port "$fallback_port" || die "Invalid fallback port: $fallback_port"
            write_reality_self_caddyfile "$domain" "$email" "$fallback_listen" "$fallback_port" "$site_root"
            ;;
        *)
            die "Unsupported Caddy mode: $mode"
            ;;
    esac
    if ! reload_caddy; then
        restore_generated_caddyfile
        die "Caddy reload/start failed; restored the previous Caddyfile"
    fi
    ok "Caddy configured: $CADDYFILE"
}

main "$@"
