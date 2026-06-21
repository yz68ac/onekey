#!/usr/bin/env bash
set -Eeuo pipefail

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin:/snap/bin
export PATH

REPO_URL="${ONEKEY_REPO_URL:-https://github.com/yz68ac/onekey}"
BRANCH="${ONEKEY_BRANCH:-main}"
INSTALL_DIR="${ONEKEY_INSTALL_DIR:-/usr/local/onekey-xray-caddy}"
ARCHIVE_URL="${REPO_URL}/archive/refs/heads/${BRANCH}.tar.gz"

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

require_root() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        cat >&2 <<EOF
ERROR: Please run this installer as root.

Recommended:
  wget -qO- https://raw.githubusercontent.com/yz68ac/onekey/main/install.sh | sudo bash

With arguments:
  wget -qO- https://raw.githubusercontent.com/yz68ac/onekey/main/install.sh | sudo bash -s -- menu
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
        curl -fL "$ARCHIVE_URL" -o "$output"
    elif have_cmd wget; then
        wget -O "$output" "$ARCHIVE_URL"
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
    archive="$tmp/onekey.tar.gz"
    staged="${INSTALL_DIR}.new"
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

    rm -rf "$INSTALL_DIR"
    mv "$staged" "$INSTALL_DIR"
    ok "Installed project to $INSTALL_DIR"
}

main() {
    require_root
    install_project
    exec "$INSTALL_DIR/xrayctl.sh" "${@:-menu}"
}

main "$@"
