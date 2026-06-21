#!/usr/bin/env bash

XRAY_BIN="${XRAY_BIN:-/usr/local/bin/xray}"
XRAY_SERVICE="${XRAY_SERVICE:-xray}"
XRAY_CONFIG_DIR="${XRAY_CONFIG_DIR:-/usr/local/etc/xray}"
XRAY_CONFIG="${XRAY_CONFIG:-$XRAY_CONFIG_DIR/config.json}"

CADDY_SERVICE="${CADDY_SERVICE:-caddy}"
CADDYFILE="${CADDYFILE:-/etc/caddy/Caddyfile}"
CADDY_SITE_ROOT="${CADDY_SITE_ROOT:-/usr/share/caddy}"

ONEKEY_STATE_DIR="${ONEKEY_STATE_DIR:-/etc/onekey-xray}"
STATE_FILE="${STATE_FILE:-$ONEKEY_STATE_DIR/state.json}"
USERS_FILE="${USERS_FILE:-$ONEKEY_STATE_DIR/users.json}"
BACKUP_DIR="${BACKUP_DIR:-$ONEKEY_STATE_DIR/backups}"
RENDERED_DIR="${RENDERED_DIR:-$ONEKEY_STATE_DIR/rendered}"

API_HOST_DEFAULT="127.0.0.1"
API_PORT_DEFAULT="32768"

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

info() {
    printf '[INFO] %s\n' "$*"
}

warn() {
    printf '[WARN] %s\n' "$*" >&2
}

ok() {
    printf '[OK] %s\n' "$*"
}

have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

need_cmd() {
    have_cmd "$1" || die "Missing required command: $1"
}

require_root() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        die "Please run as root, for example: sudo bash $0"
    fi
}

ensure_dirs() {
    mkdir -p "$ONEKEY_STATE_DIR" "$BACKUP_DIR" "$RENDERED_DIR"
}

timestamp() {
    date '+%Y%m%d-%H%M%S'
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

validate_uuid() {
    local uuid="$1"
    [[ "$uuid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
}

validate_short_id() {
    local sid="$1"
    [[ "$sid" =~ ^([0-9a-fA-F]{2}){0,8}$ ]]
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

backup_file() {
    local file="$1"
    [ -f "$file" ] || return 0
    mkdir -p "$BACKUP_DIR"
    cp -a "$file" "$BACKUP_DIR/$(basename "$file").$(timestamp).bak"
}

bytes_human() {
    local bytes="${1:-0}"
    awk -v b="$bytes" 'BEGIN {
        split("B KiB MiB GiB TiB", u, " ");
        i = 1;
        while (b >= 1024 && i < 5) { b /= 1024; i++ }
        if (i == 1) printf "%d %s", b, u[i];
        else printf "%.2f %s", b, u[i];
    }'
}

urlencode() {
    local raw="$1" i c out=""
    for ((i = 0; i < ${#raw}; i++)); do
        c="${raw:i:1}"
        case "$c" in
            [a-zA-Z0-9.~_-]) out+="$c" ;;
            *) printf -v out '%s%%%02X' "$out" "'$c" ;;
        esac
    done
    printf '%s\n' "$out"
}

detect_debian_ubuntu() {
    [ -r /etc/os-release ] || die "Cannot detect OS: /etc/os-release is missing"
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}" in
        debian|ubuntu) return 0 ;;
    esac
    case "${ID_LIKE:-}" in
        *debian*) return 0 ;;
    esac
    die "This project supports Debian/Ubuntu with systemd"
}

prompt() {
    local label="$1" default="${2:-}" value
    if [ -n "$default" ]; then
        read -r -p "$label [$default]: " value
        printf '%s\n' "${value:-$default}"
    else
        read -r -p "$label: " value
        printf '%s\n' "$value"
    fi
}

pause_menu() {
    printf '\n'
    read -r -p "Press Enter to continue..." _
}
