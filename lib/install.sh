#!/usr/bin/env bash

install_dependencies() {
    detect_debian_ubuntu
    info "Installing base dependencies"
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        ca-certificates curl wget jq gpg openssl coreutils lsb-release
}

install_xray() {
    info "Installing or updating Xray with the official XTLS installer"
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
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
