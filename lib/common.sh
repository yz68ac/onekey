#!/usr/bin/env bash

XRAY_BIN="${XRAY_BIN:-/usr/local/bin/xray}"
XRAY_SERVICE="${XRAY_SERVICE:-xray}"
XRAY_RUN_USER="${XRAY_RUN_USER:-xray}"
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
    local cmd="$1"
    have_cmd "$cmd" && return 0
    # lib/deps.sh knows how to install it. That file is sourced after this one,
    # so resolve the function lazily at call time.
    if declare -F ensure_cmd >/dev/null 2>&1; then
        ensure_cmd "$cmd"
        return 0
    fi
    die "Missing required command: $cmd"
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

# When the script is launched as `wget -qO- ... | sudo bash`, stdin is the
# script pipe, not the keyboard. Always talk to the real terminal if there is
# one, otherwise every prompt silently reads EOF.
ONEKEY_TTY=""
ONEKEY_ASSUME_YES="${ONEKEY_ASSUME_YES:-0}"

init_tty() {
    if [ -r /dev/tty ] && [ -w /dev/tty ] && { : >/dev/tty; } 2>/dev/null; then
        ONEKEY_TTY="/dev/tty"
    fi
}

have_tty() {
    [ -n "$ONEKEY_TTY" ]
}

# ask <label> [default] -> value on stdout, prompt on the terminal.
# Honours ONEKEY_ASSUME_YES: takes the default without asking.
ask() {
    local label="$1" default="${2:-}" value="" shown

    if [ "$ONEKEY_ASSUME_YES" = "1" ] && [ -n "$default" ]; then
        printf '%s\n' "$default"
        return 0
    fi

    if [ -n "$default" ]; then
        shown="$label [$default]: "
    else
        shown="$label: "
    fi

    if have_tty; then
        printf '%s' "$shown" >"$ONEKEY_TTY"
        IFS= read -r value <"$ONEKEY_TTY" || value=""
    elif [ -t 0 ]; then
        printf '%s' "$shown" >&2
        IFS= read -r value || value=""
    else
        # No terminal at all: only defaults are possible.
        value=""
    fi

    printf '%s\n' "${value:-$default}"
}

# Same as ask, but refuses to return empty.
ask_required() {
    local label="$1" default="${2:-}" hint="${3:-}" value
    value="$(ask "$label" "$default")"
    if [ -z "$value" ]; then
        if [ -n "$hint" ]; then
            die "$label is required. $hint"
        fi
        die "$label is required and no terminal was available to ask for it"
    fi
    printf '%s\n' "$value"
}

confirm() {
    local label="$1" default="${2:-y}" value
    value="$(ask "$label (y/n)" "$default")"
    case "${value,,}" in
        y | yes) return 0 ;;
        *) return 1 ;;
    esac
}

# Kept for backwards compatibility with existing call sites.
prompt() {
    ask "$@"
}

pause_menu() {
    printf '\n'
    if have_tty; then
        printf 'Press Enter to continue...' >"$ONEKEY_TTY"
        IFS= read -r _ <"$ONEKEY_TTY" || true
    else
        read -r -p "Press Enter to continue..." _ || true
    fi
}
