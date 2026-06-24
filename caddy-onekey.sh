#!/usr/bin/env bash
set -Eeuo pipefail

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin:/snap/bin
export PATH

CADDYFILE="${CADDYFILE:-/etc/caddy/Caddyfile}"
CADDY_SERVICE="${CADDY_SERVICE:-caddy}"
SITE_ROOT="${SITE_ROOT:-/usr/share/caddy}"

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

normalize_path() {
    local path="$1"
    [ -n "$path" ] || die "Path cannot be empty"
    case "$path" in
        /*) ;;
        *) path="/$path" ;;
    esac
    path="${path%/}"
    [ -n "$path" ] || path="/xhttp"
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
        info "Caddy already installed: $(caddy version 2>/dev/null || true)"
        return 0
    fi

    info "Installing Caddy from the official stable repository"
    apt-get update
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
    if [ -f "$CADDYFILE" ]; then
        cp -a "$CADDYFILE" "$CADDYFILE.$(date '+%Y%m%d-%H%M%S').bak"
    fi
    install -m 0644 "$tmp" "$CADDYFILE"
    rm -f "$tmp"
}

write_xhttp_caddyfile() {
    local domain="$1" email="$2" xhttp_port="$3" xhttp_path="$4" site_root="$5"
    local tmp
    tmp="$(mktemp)"
    mkdir -p "$(dirname "$CADDYFILE")" "$site_root"

    cat > "$tmp" <<EOF
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
            systemctl reload "$CADDY_SERVICE" || systemctl restart "$CADDY_SERVICE"
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
                mode="${2:-}"
                shift 2
                ;;
            --reality-self)
                mode="reality-self"
                shift
                ;;
            --domain)
                domain="${2:-}"
                shift 2
                ;;
            --email)
                email="${2:-}"
                shift 2
                ;;
            --xhttp-port|--port)
                xhttp_port="${2:-}"
                shift 2
                ;;
            --path)
                xhttp_path="${2:-}"
                shift 2
                ;;
            --fallback-listen|--listen)
                fallback_listen="${2:-}"
                shift 2
                ;;
            --fallback-port|--local-port|--https-port)
                fallback_port="${2:-}"
                shift 2
                ;;
            --site-root)
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
    reload_caddy
    ok "Caddy configured: $CADDYFILE"
}

main "$@"
