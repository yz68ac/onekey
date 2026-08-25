#!/usr/bin/env bash
set -Eeuo pipefail
umask 022

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin:/snap/bin
export PATH

REPO_URL="${ONEKEY_REPO_URL:-https://github.com/yz68ac/onekey}"
BRANCH="${ONEKEY_BRANCH:-main}"
INSTALL_DIR="${ONEKEY_INSTALL_DIR:-/usr/local/onekey-xray-caddy}"
ARCHIVE_URL="${REPO_URL}/archive/refs/heads/${BRANCH}.tar.gz"
ONEKEY_TMP_DIR=""
ONEKEY_STAGED_DIR=""

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

have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# The installer needs a downloader and tar before anything else can happen,
# so bootstrap those without asking.
bootstrap_tools() {
    local missing=()
    if ! have_cmd curl && ! have_cmd wget; then
        missing+=(curl)
    fi
    have_cmd tar || missing+=(tar)
    [ "${#missing[@]}" -gt 0 ] || return 0

    info "Installing bootstrap tools: ${missing[*]}"
    # Tell the rest of the pipeline the index is already current, so xrayctl
    # and caddy-onekey.sh do not each run apt-get update again.
    ONEKEY_PKG_INDEX_FRESH=1
    export ONEKEY_PKG_INDEX_FRESH
    if have_cmd apt-get; then
        apt-get update -qq >/dev/null 2>&1 || true
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ca-certificates "${missing[@]}" >/dev/null 2>&1 || true
    elif have_cmd dnf; then
        dnf install -y -q ca-certificates "${missing[@]}" >/dev/null 2>&1 || true
    elif have_cmd yum; then
        yum install -y -q ca-certificates "${missing[@]}" >/dev/null 2>&1 || true
    elif have_cmd apk; then
        apk add --no-cache ca-certificates "${missing[@]}" >/dev/null 2>&1 || true
    elif have_cmd pacman; then
        pacman -Sy --noconfirm --needed ca-certificates "${missing[@]}" >/dev/null 2>&1 || true
    fi
}

require_root() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        cat >&2 <<EOF
ERROR: Please run this installer as root.

Recommended:
  wget -qO- https://raw.githubusercontent.com/yz68ac/onekey/main/install.sh | sudo bash

With arguments:
  wget -qO- https://raw.githubusercontent.com/yz68ac/onekey/main/install.sh | sudo bash -s -- setup --mode reality -y
EOF
        exit 1
    fi
}

require_install_dir() {
    case "$INSTALL_DIR" in
        /*) ;;
        *) die "ONEKEY_INSTALL_DIR must be an absolute path" ;;
    esac

    case "$INSTALL_DIR" in
        *..*|"") die "Refusing unsafe install directory: $INSTALL_DIR" ;;
    esac

    case "$INSTALL_DIR" in
        /|/bin|/boot|/dev|/etc|/home|/lib|/lib64|/opt|/proc|/root|/run|/sbin|/sys|/tmp|/usr|/usr/local|/var)
            die "Refusing unsafe install directory: $INSTALL_DIR"
            ;;
    esac
}

download_archive() {
    local output="$1"
    if have_cmd curl; then
        curl -fsSL --retry 3 --retry-connrefused --connect-timeout 10 "$ARCHIVE_URL" -o "$output"
    elif have_cmd wget; then
        wget -q --tries=3 --timeout=30 -O "$output" "$ARCHIVE_URL"
    else
        die "curl or wget is required"
    fi
}

install_project() {
    require_install_dir
    have_cmd tar || die "tar is required"
    have_cmd mktemp || die "mktemp is required"

    local tmp archive src staged parent
    tmp="$(mktemp -d)"
    ONEKEY_TMP_DIR="$tmp"
    archive="$tmp/onekey.tar.gz"
    staged="${INSTALL_DIR}.new"
    ONEKEY_STAGED_DIR="$staged"
    parent="$(dirname "$INSTALL_DIR")"
    trap 'rm -rf "$tmp" "$staged"' EXIT

    info "Downloading $ARCHIVE_URL"
    download_archive "$archive"

    tar -xzf "$archive" -C "$tmp"
    src="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    [ -n "$src" ] || die "Failed to unpack project archive"
    [ -f "$src/xrayctl.sh" ] || die "Archive does not contain xrayctl.sh"

    mkdir -p "$parent"
    rm -rf "$staged"
    cp -a "$src" "$staged"
    chmod +x "$staged/xrayctl.sh" "$staged/install.sh" "$staged/caddy-onekey.sh"

    if [ -e "$INSTALL_DIR" ] && [ ! -d "$INSTALL_DIR" ]; then
        die "Install path exists and is not a directory: $INSTALL_DIR"
    fi

    if [ -d "$INSTALL_DIR" ]; then
        info "Updating existing project in place"
        cp -a "$staged"/. "$INSTALL_DIR"/
    else
        mv "$staged" "$INSTALL_DIR"
    fi
    ok "Installed project to $INSTALL_DIR"
}

main() {
    require_root
    bootstrap_tools
    install_project
    # install_project's EXIT trap will not run across exec, so clean up now.
    trap - EXIT
    rm -rf "${ONEKEY_TMP_DIR:-}" 2>/dev/null || true
    rm -rf "${ONEKEY_STAGED_DIR:-}" 2>/dev/null || true
    if [ "$#" -eq 0 ]; then
        exec "$INSTALL_DIR/xrayctl.sh" setup
    fi
    exec "$INSTALL_DIR/xrayctl.sh" "$@"
}

main "$@"
