#!/usr/bin/env bash
# Dependency auto-installation. Nothing here should ever hard-fail on a
# missing package manager; callers decide whether a command is required.

ONEKEY_PKG_MANAGER=""
ONEKEY_PKG_REFRESHED=0
ONEKEY_PKG_LAST_ERROR=""
# Exported so child processes (caddy-onekey.sh) and the outer installer do not
# each run their own apt-get update.
ONEKEY_PKG_INDEX_FRESH="${ONEKEY_PKG_INDEX_FRESH:-0}"
export ONEKEY_PKG_INDEX_FRESH

detect_pkg_manager() {
    [ -z "$ONEKEY_PKG_MANAGER" ] || return 0
    if have_cmd apt-get; then
        ONEKEY_PKG_MANAGER="apt"
    elif have_cmd dnf; then
        ONEKEY_PKG_MANAGER="dnf"
    elif have_cmd yum; then
        ONEKEY_PKG_MANAGER="yum"
    elif have_cmd apk; then
        ONEKEY_PKG_MANAGER="apk"
    elif have_cmd pacman; then
        ONEKEY_PKG_MANAGER="pacman"
    else
        return 1
    fi
}

# An apt index touched within the last hour is good enough to install from.
apt_index_fresh() {
    [ -d /var/lib/apt/lists ] || return 1
    [ -n "$(find /var/lib/apt/lists -maxdepth 1 -type f -name '*_Packages*' -mmin -60 -print -quit 2>/dev/null)" ]
}

# pkg_refresh [force]
# Refreshes the package index at most once per run, and skips it entirely when
# another process already did it or the index is still warm.
pkg_refresh() {
    local force="${1:-}"

    if [ "$force" != "force" ]; then
        [ "$ONEKEY_PKG_REFRESHED" -eq 0 ] || return 0
        if [ "$ONEKEY_PKG_INDEX_FRESH" = "1" ]; then
            ONEKEY_PKG_REFRESHED=1
            return 0
        fi
        if [ "$ONEKEY_PKG_MANAGER" = "apt" ] && apt_index_fresh; then
            ONEKEY_PKG_REFRESHED=1
            ONEKEY_PKG_INDEX_FRESH=1
            return 0
        fi
    fi

    ONEKEY_PKG_REFRESHED=1
    if [ "$force" = "force" ]; then
        ui_note "install failed, refreshing package index and retrying..."
    else
        ui_note "refreshing package index (this can take a moment)..."
    fi
    case "$ONEKEY_PKG_MANAGER" in
        apt) ONEKEY_PKG_LAST_ERROR="$(apt-get update 2>&1 >/dev/null)" || true ;;
        apk) ONEKEY_PKG_LAST_ERROR="$(apk update 2>&1 >/dev/null)" || true ;;
        pacman) ONEKEY_PKG_LAST_ERROR="$(pacman -Sy --noconfirm 2>&1 >/dev/null)" || true ;;
        *) : ;;
    esac
    ONEKEY_PKG_INDEX_FRESH=1
}

pkg_install() {
    local pkgs=("$@") out
    [ "${#pkgs[@]}" -gt 0 ] || return 0
    detect_pkg_manager || return 1
    [ "${EUID:-$(id -u)}" -eq 0 ] || return 1
    pkg_refresh

    # stderr is captured so a failure can be explained instead of swallowed
    case "$ONEKEY_PKG_MANAGER" in
        apt) out="$(DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${pkgs[@]}" 2>&1 >/dev/null)" || {
            ONEKEY_PKG_LAST_ERROR="$out"
            return 1
        } ;;
        dnf) out="$(dnf install -y -q "${pkgs[@]}" 2>&1 >/dev/null)" || {
            ONEKEY_PKG_LAST_ERROR="$out"
            return 1
        } ;;
        yum) out="$(yum install -y -q "${pkgs[@]}" 2>&1 >/dev/null)" || {
            ONEKEY_PKG_LAST_ERROR="$out"
            return 1
        } ;;
        apk) out="$(apk add --no-cache "${pkgs[@]}" 2>&1 >/dev/null)" || {
            ONEKEY_PKG_LAST_ERROR="$out"
            return 1
        } ;;
        pacman) out="$(pacman -S --noconfirm --needed "${pkgs[@]}" 2>&1 >/dev/null)" || {
            ONEKEY_PKG_LAST_ERROR="$out"
            return 1
        } ;;
        *) return 1 ;;
    esac
}

# Last few lines of whatever the package manager complained about.
pkg_error_detail() {
    [ -n "$ONEKEY_PKG_LAST_ERROR" ] || return 0
    printf '\n%s' "$(printf '%s\n' "$ONEKEY_PKG_LAST_ERROR" | grep -v '^$' | tail -n 3 | sed 's/^/    /')"
}

# Command name -> distro package name.
pkg_for_cmd() {
    local cmd="$1"
    case "$cmd" in
        gpg)
            case "$ONEKEY_PKG_MANAGER" in
                apt) printf 'gnupg\n' ;;
                *) printf 'gnupg2\n' ;;
            esac
            ;;
        ss) printf 'iproute2\n' ;;
        dig)
            case "$ONEKEY_PKG_MANAGER" in
                apt) printf 'dnsutils\n' ;;
                *) printf 'bind-utils\n' ;;
            esac
            ;;
        timeout | od | shuf) printf 'coreutils\n' ;;
        lsb_release) printf 'lsb-release\n' ;;
        sysctl)
            case "$ONEKEY_PKG_MANAGER" in
                pacman) printf 'procps-ng\n' ;;
                *) printf 'procps\n' ;;
            esac
            ;;
        modprobe)
            case "$ONEKEY_PKG_MANAGER" in
                apk) printf 'kmod\n' ;;
                *) printf 'kmod\n' ;;
            esac
            ;;
        *) printf '%s\n' "$cmd" ;;
    esac
}

# ensure_cmd <command> [optional]
# Installs the command if missing. Returns non-zero (instead of dying) when
# the second argument is "optional".
ensure_cmd() {
    local cmd="$1" mode="${2:-required}" pkg
    have_cmd "$cmd" && return 0

    case "$cmd" in
        */*)
            [ "$mode" = "optional" ] && return 1
            die "Missing required binary: $cmd"
            ;;
    esac

    detect_pkg_manager || true
    pkg="$(pkg_for_cmd "$cmd")"
    ui_note "installing missing dependency: $cmd ($pkg)"
    pkg_install "$pkg" || true

    # A cached index can be too old for the version the mirror now serves;
    # force one real refresh before giving up.
    if ! have_cmd "$cmd"; then
        pkg_refresh force
        pkg_install "$pkg" || true
    fi

    if have_cmd "$cmd"; then
        return 0
    fi
    if [ "$mode" = "optional" ]; then
        ui_bad "could not install $cmd; continuing without it$(pkg_error_detail)"
        return 1
    fi
    die "Missing required command: $cmd (tried to install package '$pkg')$(pkg_error_detail)"
}

# Everything the manager itself needs to run.
ONEKEY_CORE_DEPS=(curl wget jq openssl tar gpg logrotate timeout)
# Nice to have; absence only degrades output.
ONEKEY_EXTRA_DEPS=(qrencode)

ensure_base_deps() {
    local cmd missing=()
    for cmd in "${ONEKEY_CORE_DEPS[@]}"; do
        have_cmd "$cmd" || missing+=("$cmd")
    done
    for cmd in "${ONEKEY_EXTRA_DEPS[@]}"; do
        have_cmd "$cmd" || missing+=("$cmd")
    done

    if [ "${#missing[@]}" -eq 0 ]; then
        ui_good "all dependencies present"
        return 0
    fi

    ui_step "Installing dependencies: ${missing[*]}"
    if ! detect_pkg_manager; then
        ui_bad "no supported package manager found; install manually: ${missing[*]}"
    else
        local pkgs=() cmd_pkg
        for cmd in "${missing[@]}"; do
            cmd_pkg="$(pkg_for_cmd "$cmd")"
            pkgs+=("$cmd_pkg")
        done
        # ca-certificates keeps curl/acme happy on bare images.
        pkgs+=(ca-certificates)
        pkg_install "${pkgs[@]}" || true
    fi

    for cmd in "${ONEKEY_CORE_DEPS[@]}"; do
        ensure_cmd "$cmd"
    done
    for cmd in "${ONEKEY_EXTRA_DEPS[@]}"; do
        ensure_cmd "$cmd" optional || true
    done
    ui_good "dependencies ready"
}
