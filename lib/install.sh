#!/usr/bin/env bash

install_dependencies() {
    detect_debian_ubuntu
    info "Installing base dependencies"
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        ca-certificates curl wget jq gpg openssl coreutils lsb-release
}

ensure_xray_user() {
    if id "$XRAY_RUN_USER" >/dev/null 2>&1; then
        return 0
    fi

    info "Creating system user for Xray: $XRAY_RUN_USER"
    if have_cmd useradd; then
        useradd --system --user-group --no-create-home --shell /usr/sbin/nologin "$XRAY_RUN_USER"
    elif have_cmd adduser; then
        adduser --system --no-create-home --disabled-login --group "$XRAY_RUN_USER"
    else
        die "useradd or adduser is required to create $XRAY_RUN_USER"
    fi
}

install_xray() {
    ensure_xray_user
    info "Installing or updating Xray with the official XTLS installer"
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --install-user "$XRAY_RUN_USER"
}

install_all() {
    install_dependencies
    install_xray
    init_state_files
    apply_xray_config
    if have_cmd systemctl; then
        systemctl enable "$XRAY_SERVICE" >/dev/null 2>&1 || true
    fi
    ok "Initialized xrayctl state and Xray config"
    info "Next: add a user and switch mode, or run ./xrayctl.sh for the menu"
}
